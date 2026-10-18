# M5 · Rotation & resize: visible center preserved, in lockstep (design)

Scope: SPEC S7 (237–252), S6 geometry (162–166), S4/S5 target-vs-presentation (123–137). Builds on M2-render §4–5/§7 and
M4-zoom §3 (limits re-resolve, alignment). Names per CLAUDE.md. No UIKit. Physics package untouched (`ZoomGeometry`,
`ZoomLimits`, `ZoomSolver` already take `insets`; `AxisGeometry.visibleCenter` is inset-aware).

## 1. Data flow

```
viewport background: onGeometryChange (16+) / GeometryReader+PreferenceKey (15)   ← size + safeAreaInsets (keyboard incl.)
   └─► state.setViewport(ViewportMetrics)      cold metrics, adjustedContentInset, didChangeAdjustedContentInset
         ├─ interrupt() if moving without a finger (target := presentation)      §5
         ├─ commitResize(...)  → ResizeCommit (cold, channel .metrics) + unclamped target (unanimated)   §3–4
         └─ clock: resize watch → phase .animating while probe.size ≠ commit.viewport → settle → closeResize()  §8
content measurement → state.setContentSize   → `.sizeChanges` rule (§6), same commit path
ztronScrollID registry (M6) → state.targetFrameDidChange(id)  → re-derive pending reflow anchor (§6)
TransformHost (now on the viewport-sized ContentLayoutHost) → ContentTransform.effectValue(size:) = pure F(size, animatables, commit)
```
The commit never animates. The system transition animates the container's `size`; `F` maps that size to the offset/scale that
keeps the anchor at the unobscured center, so every interpolated frame is right without a state write (S7 suggested approach).

## 2. Types and signatures

```swift
// State/ScrollStateTypes.swift (additions)
public enum ZTronContentInsetAdjustmentBehavior: Sendable { case automatic /* = scrollableAxes */, scrollableAxes, never, always }
struct ScrollMetrics {   // existing + :
    var contentInset: EdgeInsets = .init()        // developer (state.contentInset)
    var safeAreaInsets: EdgeInsets = .init()      // observed (container + keyboard), replaces today's `contentInsets = safeArea`
    var headerObscured: CGFloat = 0               // M8b hook: scaling header height; unobscured rect only, not bounds
    var adjustedContentInset: EdgeInsets { get }  // contentInset + safeArea per behavior/axes (S6)
    var resizeGeneration: UInt64 = 0              // bumps per commit; PanCoordinator rebases its baseline when it changes
}
struct ResizeCommit: Equatable, Sendable {        // Render/ResizeCommit.swift; cold, lives in metrics
    struct Snapshot: Equatable, Sendable { var viewport: CGSize; var contentSize: CGSize }
    var current: Snapshot; var previous: Snapshot // previous == current unless the viewport size changed
    var insets: EdgeInsets; var header: CGFloat   // adjustedContentInset + header at commit (u-derivation uses these, not the animated ones)
    var anchorOld: CGPoint; var anchorNew: CGPoint// unscaled content points; differ only for a registry-target reflow (§6)
    var pagingIndex: (x: Int?, y: Int?)           // page kept current when isPagingEnabled (§6)
    var isOpen: Bool                              // true from commit until closeResize(); F clamps while open
}
enum ResizeMath {                                  // Render/ResizeMath.swift, pure, unit-tested
    static func unobscuredCenter(viewport: CGSize, insets: EdgeInsets, header: CGFloat) -> CGPoint   // inset.start + header(top) + (len − total − header)/2
    static func progress(size: CGSize, from: CGSize, to: CGSize) -> CGFloat                          // t∈[0,1] on the axis with larger |Δ|; 1 if none
    static func anchor(offset: CGPoint, scale: CGFloat, center: CGPoint, pad: CGPoint) -> CGPoint     // u = (o + c − pad)/s
    static func isAtFit(_ scale: CGFloat, fit: CGFloat) -> Bool                                      // |scale/fit − 1| ≤ 1e-4
    static func resolve(size: CGSize, offset: CGPoint, scale: CGFloat, insetsAnimated: EdgeInsets, commit: ResizeCommit,
                        limits: ZoomLimits, alignment: UnitPoint, paging: Axis.Set) -> (offset: CGPoint, scale: CGFloat, pad: CGPoint)
    static func insetChange(offset: CGPoint, old: ZoomGeometry, new: ZoomGeometry, anchor: UnitPoint?) -> CGPoint   // §6 rule
}
struct TransformVector: VectorArithmetic { var ox, oy, s, top, leading, bottom, trailing: CGFloat }   // 7 scalars
struct ContentTransform: GeometryEffect {         // Render/ContentTransform.swift (reshaped)
    var offset: CGPoint; var scale: CGFloat; var insets: EdgeInsets        // animatable; `pad` is now derived, never animated
    let commit: ResizeCommit; let limits: ZoomLimits; let alignment: UnitPoint; let paging: Axis.Set; let probe: PresentationBox?
    var animatableData: TransformVector
    func effectValue(size: CGSize) -> ProjectionTransform   // fast path if !commit.isOpen && size == commit.current.viewport, else ResizeMath.resolve
}
final class PresentationBox { func record(_ o: CGPoint, _ s: CGFloat, size: CGSize); var pending: (CGPoint, CGFloat, CGSize) }
protocol ScrollTargetRegistry: AnyObject {        // M6 fills it via ztronScrollID; M5 ships the protocol + an empty default
    func nearestTarget(to point: CGPoint) -> (id: AnyHashable, frame: CGRect)?   // unscaled ztronContent coordinates
    func frame(of id: AnyHashable) -> CGRect?
}
public final class ZTronScrollState {             // additions
    public var contentInset: EdgeInsets { get set }                     // didSet → applyInsetChange (§6), didChangeAdjustedContentInset
    public var contentInsetAdjustmentBehavior: ZTronContentInsetAdjustmentBehavior = .automatic
    public var adjustedContentInset: EdgeInsets { get }                 // cold (.metrics)
    var sizeChangesAnchor: UnitPoint?                                   // nil = S7/UIKit defaults; set by M6's defaultScrollAnchor(_:for: .sizeChanges) twin
    weak var targetRegistry: (any ScrollTargetRegistry)?
    func setViewport(_ v: ViewportMetrics)                              // rewritten: size change → center rule; inset-only → inset rule
    func setContentSize(_ s: CGSize)                                    // `.sizeChanges` rule + pending reflow anchor
    func setHeaderObscured(_ h: CGFloat)                                // M8b hook (center only)
    func targetFrameDidChange(_ id: AnyHashable)                        // registry callback; re-derives a pending reflow anchor
    func closeResize()                                                  // target := clamped presentation (unanimated), commit.isOpen = false, snap if paging
}
public protocol ZTronScrollViewDelegate { func didChangeAdjustedContentInset(_ state: ZTronScrollState) /* default no-op */ }
```

## 3. Formulas (per axis; `x_v = s·x_c + pad − o` unchanged)

- Unobscured center `c(V, I, h) = I.start + h + (V − I.total − h)/2` (h only on top). Bounds: `min = −I.start`, `max = max(min, s·content + I.end − V)`
  (`ZoomGeometry(insets:)` already does this). Pad: `max(0, V − I.total − s·content)·alignment` (`AxisGeometry.alignmentPadding`).
- **Capture** (in `setViewport`, from *presentation* values after `interrupt()`): `u = (o + c_old − pad_old(s))/s`, `atFit = isAtFit(s, fit_old)`,
  `fit = min(vw'/cw, vh'/ch)` with inset-adjusted viewport (`ZoomLimits.resolve`). `anchorOld = anchorNew = u`.
- **Re-derive** at `V_new`: `s' = atFit ? fit_new : s` (both then clamped to `limits(V_new)` *inside F*); `o' = pad_new(s') + s'·u − c_new` **unclamped**
  (stored as target so F stays invariant across the commit; the clamp is applied by F while `isOpen` and committed by `closeResize`).
- **F(size)** (`ResizeMath.resolve`): `t = progress(size, prev.viewport, cur.viewport)`; `content(t) = lerp(prev.content, cur.content, t)` (reflowing
  content interpolates under the same transaction, so the same `t` applies); `u_c = anchor(offset, scale, c(cur.viewport, cur.insets), pad_cur)`;
  `u(t) = u_c + (anchorOld − anchorNew)·(1 − t)`; `s(size) = isAtFit(scale, fit(cur)) ? fit(size, content(t)) : scale`, clamped to `limits(size, content(t))`;
  `c(size) = c(size, insetsAnimated, header)`; `o = pad(size, s) + s·u(t) − c(size)`; paging axis: `o = pagingIndex·size.len`; then clamp to
  `bounds(content(t), s, size, insetsAnimated)`. Fast path (`!isOpen && size == cur.viewport && insetsAnimated == cur.insets`): today's matrix.
- **Invariance (the no-jump proof, unit-tested):** for every `size` between `V_old` and `V_new`, `F(size | commit_old, target_old) == F(size | commit_new, target_new)`
  within 1e-6, because both describe the same `u`, the same fit-ness and the same unclamped mapping. So it does not matter on which frame the
  commit lands (one frame late on the 15 preference path is harmless) and the commit is never animated.
- **At-fit edge:** `isAtFit` tolerance 1e-4 (scale is never pixel-snapped; a zoom bounce ends exactly at the limit). Scale outside the new
  limits → clamped by F, committed at settle (one `didZoom` + `didScroll`), replacing M4's `resolveZoomLimits` clamp during resizes.

## 4. Lockstep on both OS paths

- 16+: `onGeometryChange(for: ViewportMetrics.self)` on the viewport background fires with the *model* (final) size in the same update
  that changed it; `setViewport` commits before the first animated frame. 15 / forced: `GeometryReader` preference also carries the model
  value; `onPreferenceChange` may run one frame later. Either way frame 1 renders through `F(size | commit_old)` with the correct anchor
  (§3 invariance), so neither path has a jump or a lag frame. Pixel snapping (TransformHost, idle only) is off while the phase is `.animating`.
- The effect must sit on the **viewport-sized** container: M2 placed `TransformHost` inside `ContentLayoutHost` (size = content). New order:
  content → measurement → `ztronContent` space → `ContentLayoutHost` → `TransformHost` (effect, hit-test gate) → viewport. Content is placed at
  the container origin on both paths (Layout `bounds.origin`; D10 `overlay(alignment: .topLeading)`), so the matrix is unchanged.
  `contentStateSurvivesScrollZoomRotation` (both paths) still guards identity (R6).
- Animated insets: the commit writes `insets` in the ambient transaction. If the system animates the safe-area change (rotation), the center
  follows it per frame; `u` derivation uses the committed insets so invariance holds regardless.
- Continuous resizes (Split View drag, Stage Manager): one commit per frame, `t` is 0 or 1, no watch, no phase change, no animation.

## 5. Motion in progress

- Finger-less motion (deceleration, bounce-back, zoom bounce, transaction animation incl. a running `scrollTo`): `setViewport` calls
  `interrupt()` first → target = `probe.pending` unanimated, clock motion cancelled; capture uses that presentation. A motion that was
  out of bounds (mid-bounce) is captured as is and clamped by F, so it settles into bounds with the transition (no second bounce).
- Finger down (`isDragging`/`isZooming`): no interrupt; the commit bumps `resizeGeneration`; `PanCoordinator` compares it on the next
  event and calls `pan.rebase(presentation:translation:env:)` (M4 §4) so the next sample produces `offset == presentation`; the pinch
  re-anchors per M4 §7 (geometry change). Any gesture or programmatic target write while `isOpen` first calls `closeResize()`.

## 6. Reflow, paging, `.sizeChanges`

- **Reflow hook:** at capture, if `targetRegistry?.nearestTarget(to: u)` exists: `pendingReflow = (id, rel = (u − frame.origin)/frame.size)`.
  When the new frame arrives (`setContentSize` or `targetFrameDidChange(id)`, whichever is later): `anchorNew = frame'.origin + rel·frame'.size`,
  `anchorOld = u`, offset re-derived (unanimated; F lerps `u(t)`). Expires at `closeResize()`. Without a registry: `anchorOld == anchorNew == u`.
- **Paging:** `pagingIndex = round(o_presentation / V_old.len)` per paging axis at capture; F renders `index·size.len` (pages are viewport-wide
  and reflow with it, so the page stays current and ends snapped). A resize that interrupts a paging deceleration lands on the nearest page in
  the first frame (documented; UIKit is equally abrupt). View-aligned targets (M6) plug in by overriding `pagingIndex` with a target id.
- **Content-size change alone** (`setContentSize`, viewport unchanged): `sizeChangesAnchor == nil` → offset unchanged, clamped (UIKit/SwiftUI
  default); anchor `a` → the content point at unobscured point `a` stays at `a` (`.bottom` = chat). Written in the ambient transaction.
- **Inset change alone** (`ResizeMath.insetChange`): nil → if `o ≤ min_old + 0.5` stay at the start edge (`min_new`), else keep `o`, clamp; anchor
  `a` → point `a` fixed. Keyboard show/hide therefore never scrolls content that sits at the top (native). Size + insets in one `setViewport`
  (rotation on a notch device) → center rule with old/new insets inside `c`.
- **Override:** `sizeChangesAnchor` (set by M6's public `defaultScrollAnchor(_:for: .sizeChanges)` twin) replaces the center rule for viewport
  changes too (`u` captured at point `a`). Document that only this overrides S7.

## 7. Insets wiring (what M5 must change)

Today `setViewport` stores `safeArea` into `contentInsets` but geometry passes `insets: (.zero, .zero)` and `visibleCenter` ignores insets;
the viewport lies inside the safe area, so a keyboard *shrinks* it (and would trigger the center rule). M5: the viewport root applies
`.ignoresSafeArea(.all, edges: edges(for: axes, behavior))` (`.automatic`/`.scrollableAxes`: edges of scrollable axes; `.always`: all; `.never`: none;
a parameter change, not a branch flip — R6), reads `safeAreaInsets` (container + keyboard) from the background observer, and
`makeZoomGeometry` / `ZoomLimits.resolve` / `ContentGeometry` / `PanEnvironment` / `PinchEnvironment` all take `adjustedContentInset`. `ZTronScrollGeometry.contentInsets`
returns the adjusted value. Gesture bounds in M3/M4 (`makeZoomGeometry`, "insets M5 → zero now") become correct for free.

## 8. Delegate and phase

- `didChangeAdjustedContentInset` fires synchronously inside `setViewport`/`contentInset.didSet` when the adjusted value changes, before any didScroll.
- `setViewport` with a size change starts the clock in *resize watch* (≤ 2 ticks). Tick: `probe.size ≠ commit.viewport` → `phase = .animating`
  (no transaction token), presentation := probe (`!=`-guarded) → one `didScroll` (+ `didZoom` if the scale moved) per tick, as the existing
  `probeTick`. Settle = probe stable for 2 ticks → `closeResize()` → phase `.idle`, clock paused. No `didEndScrollingAnimation` (UIKit fires it only
  for `setContentOffset(animated:)`; open Q1). If the first tick already shows `size == commit.viewport` (unanimated resize) the watch ends silently.
- Readers: `.metrics` publishes once per commit; `.offset`/`.zoom` per tick during the transition; content bodies run 0 times (tier-0 counter).

## 9. Edge cases

First layout (`!hadViewport`) → store metrics only. Zero/non-finite size → ignore. Content smaller than viewport → bounds collapse, pad centers (fit
stays fit, offset = min). `V_new == V_old` on both axes → `t = 1`, no watch. Limits min == max (zoom off) → `s` stays 1. Resize during a
transaction-driven `scrollTo` → interrupted at its presentation (UIKit parity). Two resizes within one transition (rotate back quickly) →
second commit captures from the probe presentation; `previous := presentation-size snapshot` so `t` restarts from the current size. Registry
target disappears mid-reflow → fall back to `u`. `contentSize` arrives one frame after the viewport (slow reflow) → clamp uses old content
for that frame only; `t` logic unaffected.

## 10. Tests

Unit (Swift Testing, `Tests/ZTronScrollViewTests/{ResizeMathTests,ResizeStateTests,TransformInvarianceTests}.swift`; state tests over `OSPath.allCases`):
1. `ResizeMath` anchor round-trip: at fit, zoomed 2.5×, content smaller than viewport (pad), with insets + header; `anchor → resolve(V_new)` puts `u` at `c_new` (≤ 1e-9).
2. Fit stays fit (portrait↔landscape, insets change), non-fit keeps `s` and clamps to new limits; offset never out of bounds at `t = 1`.
3. Near edges: top-of-list portrait→landscape stays at `min` on every `t`; last page/bottom stays at `max`; no frame exceeds bounds(content(t)).
4. Invariance: 200 random `size` samples between `V_old`/`V_new` × (fit, zoomed, clamped, reflow anchors, paging): `|F_old − F_new| ≤ 1e-6`.
5. Mid-deceleration / mid-bounce / mid-`scrollTo` `setViewport`: target == presentation first, clock motion nil, then center preserved.
6. Paging: index kept, `F` snapped at every `t`; `closeResize` leaves `o == k·V_new.w`. Reflow: registry stub returns moved frame → `anchorNew`, `u(t)` lerps, item at center at `t = 1`.
7. Inset-only: keyboard inset at top → offset unchanged; at `min` → stays at `min_new`; `.bottom` anchor pins the bottom; `didChangeAdjustedContentInset` once, before didScroll.
8. Phase/delegate: resize watch → `.animating` → `.idle`; ≤ 1 didScroll per tick; unanimated resize → no phase change; `content.body` counter 0 (render harness, both paths).
Demo UI (`ResizeScreen`: 50 pt labelled grid, zoom range fit…4, launch arg `-ZTronScreen resize`; counters `resize.jumpFrames` (frames where
`size` unchanged but `|Δo| > 1 pt`, or `o` differs from `F_prev(size)` by > 1 pt), `transform.effect`, `content.body`; `ResizeUITests`) on 27.0 and 17.5,
preferred and `-ZTronForceAllFallbacks`:
a. iPhone `XCUIDevice.shared.orientation` portrait→landscapeLeft→portrait at fit and at 2×: center cell label identical, center offset ≤ 1 pt, `resize.jumpFrames` 0, `content.body` 0.
b. iPad orientation change + an in-app "animated container resize" button (`withAnimation(.easeInOut(0.4))` width 1024→507, Split View stand-in; real
   Split View is not scriptable on the simulator): same assertions. c. Keyboard: TextField above the grid, tap → keyboard → grid top row unchanged.
d. Rotate during a fling → stops, center preserved, no bounce afterward. e. Paging screen rotates → same page, snapped.

## 11. Builder sessions and file ownership

- **(a) math + state + transform + unit tests** (can start now; State/ and Render/ only): new `Render/ResizeMath.swift`, `Render/ResizeCommit.swift`;
  `Render/ContentTransform.swift` (effect reshape, `TransformVector`, probe size), `Render/ContentLayoutHost.swift` + `ZTronScrollView.swift` (host order §4,
  `ignoresSafeArea` edges), `Render/ViewportSpaces.swift` (safeArea → `safeAreaInsets`), `State/ZTronScrollState.swift`, `State/ScrollStateTypes.swift`,
  `State/ZTronScrollGeometry.swift`, delegate protocol file; tests §10 1–8. Exit: `scripts/test.sh -only-testing:ZTronScrollViewTests` green on 27.0 and 17.5.
- **(b) gestures + demo + UI tests** (after M4 (b) *and* (a) are committed): `Gesture/PanCoordinator.swift` (`resizeGeneration` rebase, `closeResize` on gesture
  write, adjusted insets into environments); Demo `ResizeScreen`, keyboard/paging variants, `ResizeUITests`. Exit: §10 a–e; record device-risk findings.
  Neither session touches `Packages/ZTronScrollPhysics` or `ScrollArbitration`.

## 12. Device risks (check first, in this order)

- R1 (load-bearing): `GeometryEffect.effectValue(size:)` must be re-evaluated on every interpolated frame of a *size* animation when `animatableData`
  is unchanged, and SwiftUI must interpolate the container's size during rotation on 15/17.5/27. Verify with `transform.effect` ≈ duration × fps.
  Fallback if not: keep the commit but write it in the ambient transaction with `offset`/`scale` animatable (today's approach) — center still
  preserved, lockstep only as good as the ambient transaction.
- R2 Rotation transaction: does the system animate the safe-area inset change (notch side)? If not, the animated `insets` jump at commit (≤ ½ inset).
- R3 Keyboard: with `ignoresSafeArea(.all, edges:)` the background observer must report the keyboard in `safeAreaInsets` on 15/17.5/27; check
  `ignoresSafeArea(.keyboard)` interaction with host apps that already ignore the keyboard.
- R4 Stage Manager / Split View live resize: continuous commits per frame — measure cost (no clock, no animation); verify no `.animating` blips.
- R5 Foldables / Slide Over: size and safe-area may change in separate updates → two commits; the second captures from the probe (§9).
- R6 Moving the effect above the layout host: confirm hit-testing in zoomed content and `ztronContent` frames are unchanged (M3/M4 UI tests).

## Open questions
- Q1 Phase/delegate at settle: `.animating → .idle` with no `didEndScrollingAnimation` (UIKit parity) — confirm, or fire it for SwiftUI-style parity.
- Q2 `contentInsetAdjustmentBehavior` default `.automatic` mapped to scrollable-axes edges (SwiftUI ScrollView extends under bars only along the scroll axis) — confirm.
- Q3 Public `contentInset` lives on the state in M5; the `View` modifier twin waits for M6/M7 — ok?

## Orchestrator resolutions (2026-10-18)
- C1 Accepted: `TransformHost` moves above `ContentLayoutHost` so the effect's `size` is the animated viewport
  (S5 deviation, reason: lockstep rotation needs the animated size). M2 `ProofUITests` must stay 6/6 and
  `content.body` 0 — that is the acceptance gate for the move.
- C2 Accepted (unclamped target while `isOpen`, `closeResize()` commits the clamp).
- C3 Accepted: viewport root ignores the safe area on the scrollable-axis edges; bars/keyboard become insets
  (matches native ScrollView, which scrolls content under bars).
- Q1 No `didEndScrollingAnimation` at resize settle (UIKit doesn't send it for bounds changes).
- Q2 `.automatic` = adjust on the scrollable axes' edges (native behaviour); document in the parity matrix.
- Q3 Yes: public `contentInset` on the state in M5; the `contentMargins`/modifier twins land in M6/M7.
- Session (a) starts only after M4 (b) is committed (both touch `State/ZTronScrollState.swift`).
