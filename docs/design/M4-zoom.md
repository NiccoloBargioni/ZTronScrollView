# M4 · Pinch zoom, limits, zoom bounce, programmatic zoom (design)

Scope: SPEC S6 (geometry lines 162–166, Zoom 206–220), S11 zoom delegate order, S12 pinch composition. Extends M3-pan §1–2/§8;
physics from M1-physics §5 (`ZoomLimits`, `ZoomGeometry`, `ZoomSolver`, `ZoomMotion`, all already in `ZTronScrollPhysics/Zoom.swift`).
Names per CLAUDE.md. New code in `Sources/ZTronScrollView/Gesture/` and `State/`. No UIKit. Pan code is only extended, not re-shaped.

## 1. Architecture (data flow)

```
SwiftUI viewport                                              view-free                               ZTronScrollState
 CatchObserver (Spatial 18+: activeCount + centroid) ─┐
 Magnify (17+) / Magnification (15–16) gesture        ├─► PinchEvent ─► PinchSession.handle ─► [PinchEffect] ─┐
 Pan DragGesture (M3, unchanged)                      ┼─► PanEvent   ─► PanSession.handle   ─► [PanEffect]   ├─► PanCoordinator.apply ─► writePinch / beginZoomBounce / delegate
 FrameClockDriver tick                                ┘                                                       ┘                           └─► ZoomMotion sampled by step(to:)
```
- `PinchSession` is a pure `struct` state machine, fed gesture samples and timestamps, returns effects. Tests drive it with synthetic samples.
- `PanCoordinator` (existing, M3) gains one `PinchSession` and `handle(_: PinchEvent)`. It stays the only object touching both sides, so the
  pinch/pan interplay (offset ownership, one-finger lift, combined release) lives in one place. No new coordinator class.
- While a pinch is active the pinch owns the offset: pan `.setOffset` effects are dropped (pan keeps tracking its translation). Two-finger panning is
  delivered through the centroid (§2). When the pinch ends with one finger down, pan resumes from a rebuilt baseline (§4).
- Pinch writes are render-time transforms only (S4): `state.writePinch(scale:offset:)` = `unanimated { writeBoth }` + pending didZoom/didScroll flags.
- The pinch never calls the arbiter. A pan `.awaitingDecision` when a pinch begins is resolved locally as `.participant` (two fingers = zoom intent);
  a pan already `.ignored` (container owns) does not block zooming.

## 2. Types and signatures

```swift
// Gesture/PinchSession.swift (internal, Equatable, Sendable)
enum PinchEvent: Equatable {
    case began(centroid: CGPoint?, time: TimeInterval)                    // first gesture value (magnification 1) or 2nd finger down (18+)
    case changed(magnification: CGFloat, centroid: CGPoint?, time: TimeInterval)   // ratio vs. gesture start; nil centroid = keep estimate
    case fingerCountChanged(count: Int, remaining: CGPoint?, time: TimeInterval)   // Spatial observer 18+; count 2→1 = one-finger lift
    case panTranslation(CGSize, time: TimeInterval)                       // 15–17 only: pan DragGesture translation, drives the centroid estimate
    case ended(time: TimeInterval)                                        // gesture ended (all/one finger up per OS, §4)
    case frame(time: TimeInterval)
    case cancelled
}
struct PinchEnvironment: Equatable {   // snapshot by the coordinator before each event (cold)
    var limits: ClosedRange<CGFloat>; var isZoomEnabled: Bool; var bouncesZoom: Bool
    var presentationScale: CGFloat; var presentationOffset: CGPoint
    var geometry: ZoomGeometry                 // viewport, unscaled content, insets, alignment → bounds(at:) and alignmentPadding(at:)
    var isMovingWithoutFinger: Bool; var logDimension: CGFloat = 1; var panDragActive: Bool
}
enum PinchEffect: Equatable {
    case catchMotion                           // began while moving: state.interrupt() (same as pan)
    case beginZooming                          // willBeginZooming, isZooming = true, phase .interacting, clock running
    case setZoom(scale: CGFloat, offset: CGPoint)   // writePinch; didZoom + didScroll coalesced per frame (§6)
    case bounce(ZoomBounceRequest)             // → ZoomSolver.bounceBack → state.beginZoomBounce; isZoomBouncing per §3
    case endZooming(atScale: CGFloat)          // didEndZooming, isZooming = false (after the bounce when one runs)
    case handOffToPan(remaining: CGPoint?)     // one-finger lift: coordinator rebases PanSession (§4)
}
struct ZoomBounceRequest: Equatable { var scale: CGFloat; var offset: CGPoint; var lastCentroid: CGPoint; var time: TimeInterval }

struct PinchSession: Equatable {
    struct Pinch: Equatable {
        var startScale: CGFloat; var anchor: CGPoint          // u = unscaled content point under the start centroid
        var startCentroid: CGPoint; var centroid: CGPoint     // current (true or estimated) centroid, viewport coordinates
        var panTranslationAtStart: CGSize?                    // 15–17 estimate baseline
        var lastRaw: CGFloat; var fingers: Int; var hasZoomed: Bool
    }
    enum Phase: Equatable { case idle, armed(Pinch) /* began, no change yet */, pinching(Pinch), released }
    var phase: Phase = .idle
    var centroidSource: CentroidSource = .spatial              // .spatial (18+) | .startLocationPlusDrag (17) | .dragOnly (15–16)
    enum CentroidSource: Equatable { case spatial, startLocationPlusDrag, dragOnly }
    mutating func handle(_ event: PinchEvent, env: PinchEnvironment) -> [PinchEffect]
    /// raw = startScale·magnification; shown = bouncesZoom ? ZoomSolver.resisted(raw, limits, logDimension) : clamp(raw).
    static func shownScale(startScale: CGFloat, magnification: CGFloat, env: PinchEnvironment) -> CGFloat
    /// offset = ZoomSolver.pinch(anchor:centroid:scale:geometry:), unclamped while bouncesZoom (settles on release), else geometry.clamped.
    static func offset(anchor: CGPoint, centroid: CGPoint, scale: CGFloat, env: PinchEnvironment) -> CGPoint
    static func estimatedCentroid(start: CGPoint, panAtStart: CGSize?, panNow: CGSize) -> CGPoint   // start + (panNow − panAtStart)
}
```
```swift
// Gesture/PanSession.swift (one addition)
mutating func rebase(presentation: CGPoint, translation: CGSize, env: PanEnvironment)   // dragging only: baseline := Self.baseline(presentation, translation, env), no effects
// Gesture/PanCoordinator.swift (additions)
var pinch = PinchSession(); var isPinching: Bool { get }
func handle(_ event: PinchEvent)                        // snapshot PinchEnvironment → pinch.handle → apply; pan .setOffset dropped while isPinching
func makeZoomGeometry() -> ZoomGeometry                 // factored out of environment(); shared with PanEnvironment bounds (insets M5 → zero now)
```
```swift
// Public surface (ZTronScrollView.swift, State/ScrollStateTypes.swift, State/ZTronScrollState.swift)
public enum ZTronZoomScale: Equatable, Sendable { case absolute(CGFloat), fit, fill }     // maps 1:1 to physics ZoomBound
extension ZTronScrollView { public func zoomRange(min: ZTronZoomScale, max: ZTronZoomScale) -> Self }   // default .absolute(1)…absolute(1)
extension ZTronScrollView { public func doubleTapToZoom(_ enabled: Bool = true, scale: ZTronZoomScale? = nil) -> Self }   // off by default; §5
extension View { public func ztronScrollZoomRange(min:max:) -> some View; public func ztronScrollDoubleTapToZoom(_:scale:) -> some View }

public final class ZTronScrollState {   // additions
    public var bouncesZoom = true
    public var minimumZoomScale: CGFloat { get }; public var maximumZoomScale: CGFloat { get }   // resolved range, cold channel .metrics
    public var isZoomEnabled: Bool { get }                       // max > min
    public var isZooming: Bool { get }; public var isZoomBouncing: Bool { get }                   // cold channel .flags
    public func setZoomScale(_ scale: CGFloat, animated: Bool)   // existing; body replaced by ZoomSolver.zoom(to:anchoredAtVisibleCenterOf:…)
    public func zoom(to rect: CGRect, animated: Bool)            // ZoomSolver.zoom(toFit:…): fit with inset-adjusted viewport, center rect.mid
    var zoomLimits: ZoomLimits                                   // set by the container from zoomRange; resolve on setViewport/setContentSize
    func beginZooming(); func writePinch(scale: CGFloat, offset: CGPoint); func endZooming(atScale: CGFloat)
    func beginZoomBounce(_ m: ZoomMotion, at t: TimeInterval)    // ClockMotion.kind = .zoomBounce; settle → endZooming
    // ClockMotion gains `case zoomBounce(ZoomMotion)`; `zoom: AxisMotion?` + zoomCenter path stays for setZoomScale(animated:)
}
```

## 3. Formulas

- **Anchor** at `.began` (or the first `.changed` when `began` carries no centroid): c₀ = centroid; u = `ZoomSolver.contentPoint(under: c₀, offset, scale, geometry)`.
  Insets and alignment padding are inside `geometry` (pad(s) = alignmentPadding(at: s)); u is in unscaled content coordinates, so it is
  independent of scale and the pad change between scales is handled by `pinch(…)`.
- **Each sample:** s = shownScale(startScale·m); offset = pinch(anchor: u, centroid: c_t, scale: s) = pad(s) + s·u − c_t. A moving c_t (two-finger pan)
  shifts the offset 1:1, so the content point under the fingers is invariant with zero extra terms.
- **Resistance (log space):** e = ln(raw/L), L = nearest limit; shown = L·exp(RubberBand(dimension: 1).displacement(e)). Symmetric: pinching to 2×max
  and to min/2 give equal |ln(shown/L)|. `ZoomSolver.unresisted` inverts it when a pinch restarts past the limit (startScale := unresisted shown).
  Without `bouncesZoom`: shown = clamp(raw), offset clamped by `geometry.clamped`.
- **Release:** if shown ∉ limits or offset ∉ bounds(shown) → `.bounce`: `ZoomSolver.bounceBack(from: shown, limits, lastCentroid: c_last, offset, geometry, at: t)`;
  the log spring goes ln(shown) → ln(L) anchored at u under c_last; the offset residual (end − clamped end) springs to 0 on its own so the offset
  settles into bounds while the scale snaps. No momentum: the spring starts at zero velocity. `isZoomBouncing` = true while the ZoomMotion runs and
  shown ≠ L; an offset-only settle runs the same motion with `isZoomBouncing` false. Else → `.endZooming(atScale:)` immediately.
- **Limits:** `zoomLimits.resolve(unscaledContentSize, viewportSize, insets)` on every setViewport/setContentSize; fit = min(vw/cw, vh/ch), fill = max.
  After S7 center preservation, if the current scale falls outside the new range it is clamped through `ZoomSolver.zoom(to:anchoredAtVisibleCenterOf:)`
  (unanimated, one `didZoom` + `didScroll`). Enabled iff upper > lower; disabled → pinch events return `[]`, gesture still attached (cheap).
- **Alignment:** `contentAlignment` = `.center` when `isZoomEnabled`, else the native default; `ZoomGeometry` carries it, so `bounds(at:)` collapse
  (min == max) when content is smaller than the viewport and the pad centers it.
- **setZoomScale(animated:)**: `ZoomSolver.zoom(to:anchoredAtVisibleCenterOf:currentScale:limits:geometry:)` (replaces the v/2, pad-less formula at
  ZTronScrollState.swift:304–313). **zoom(to:animated:)**: `ZoomSolver.zoom(toFit:)`. Both: `isZoomAnimating`, end → `didEndScrollingAnimation`
  (UIKit fires no didEndZooming for programmatic zoom).

## 4. Centroid sources, accuracy, one-finger lift

| OS | Gesture | Centroid | Expected focal error |
|---|---|---|---|
| 26+ (D34) | MagnifyGesture + SpatialEventGesture observer | mean of `.active` event locations (local), updated every event; `fingerCountChanged` on count change | ≤ 0.5 pt (pixel snap only) |
| 17, 18.x (D34) | MagnifyGesture | c₀ = `value.startLocation` (local); c_t = c₀ + (panTranslation_t − panTranslation at began) | exact for two-finger pan; ≤ \|Δspread\|/2 during a spread (DragGesture follows one finger) |
| 15–16 | MagnificationGesture (no location) | c₀ = pan `startLocation` if a drag is live, else viewport center; c_t as 17 | ≤ ½ initial finger separation + the 17 term |

`centroidSource` is injected by the coordinator from `ZTronAvailability` (forced fallbacks exercise all three on 27). The 17 estimate must be
measured on 17.5 against `.startLocation` only (no drag-follow); the handoff records which is less wrong and the default may switch per OS.

**One-finger lift.** 18+: `fingerCountChanged(2→1, remaining:)` → effects `[.endZooming(atScale:) or .bounce, .handOffToPan(remaining)]`; the
coordinator then (a) if `PanSession` is `.dragging`, calls `pan.rebase(presentation:translation:env:)` so `offset(baseline, translation) ==
presentation` (no jump); (b) if the DragGesture died when the second finger landed (device risk R1), it synthesizes `PanEvent.dragChanged`
from the observer's remaining-finger location (startLocation = `remaining`, translation = delta) until the real drag or `touchesEnded`, so the
pan continues without waiting for 10 pt of hysteresis. A bounce started at lift keeps owning the offset until settled; pan writes resume after.
15–17: the gesture's `.ended` arrives on the lift; continuation happens only if the DragGesture survives (rebase as above). Document the gap.
**Combined release** (both fingers up in one event batch): pinch is processed first; if it produced `.bounce`, the pan `.release` is replaced by
`.endSequence` (didEndDragging(willDecelerate: false)); otherwise pan release runs normally.

## 5. Gesture adapter, double tap

- `GestureAttach` gets a third gesture in the same `mode`: `MagnifyGesture()` (17+) / `MagnificationGesture()` (15–16), `name:` on 18+, attached after
  observer and pan, all `.simultaneousGesture` by default. `onChanged` → `.began` on first value then `.changed(magnification, centroid)`; `onEnded` → `.ended`.
- `CatchObserverState` gains `centroid: CGPoint?` and reports count changes; `PinchGestureAdapter` (~60 lines) builds `PinchEvent`s and, on 15–17,
  forwards pan translations as `.panTranslation` (tap into the existing pan `send`). All coordinates `.local`.
- **Double tap (opt-in):** `TapGesture(count: 2)` simultaneous, with location from `SpatialTapGesture` (16+) or the last observer touch-down (15):
  if |scale − min| ≤ 0.01·min → zoom(to: rect of size viewport/s′ centered at `contentPoint(under: tap)`), s′ = given scale or max; else setZoomScale(min, animated: true). Risk R4.

## 6. Delegate and phase order, reader tiers

- `willBeginZooming` fires on the first `.setZoom` whose scale differs (mirrors M3's deferred willBeginDragging); phase `.interacting`, `isZooming`.
- Per frame while pinching: `writePinch` sets `didZoomPending` + `didScrollPending`; `step(to:)` flushes **didZoom then didScroll**, once per tick
  (clock runs while tracking/zooming, as in M3 §8). Bounce frames: `stepClockMotion` samples the ZoomMotion, same flush. Then `didEndZooming(atScale:)`
  after settle (or immediately at release without bounce), `isZooming` false, phase `.decelerating` during the bounce → `.idle` (open Q2).
- Pan + pinch together: pan's dragging callbacks keep their M3 order; the two sequences are independent, as in UIKit.
- **Reader tiers:** `writeBoth` publishes channel `.zoom` only when the zoom value changed and `.offset` only when the offset changed. A
  `ZTronScrollReader` whose transform reads only `geometry.zoomScale` records `{.zoom}` (existing `discoverChannels`) and does not update during a
  pure pan; `isZooming`/`isZoomBouncing` are `.flags` (cold). Edge: a pinch frame with unchanged scale but moved centroid publishes `.offset` only.

## 7. Edge cases

Limits min == max → no effects, no delegate. Non-finite/≤ 0 magnification → sample ignored. Centroid nil on 18+ (events not yet arrived) → use last.
Limits change mid-pinch (resize/rotation) → re-anchor: u := contentPoint(under: c_t) at the new geometry, startScale := presentation, m baseline := current.
Pinch during deceleration or zoom bounce → `.catchMotion` (interrupt), startScale = presentation (unresisted if past a limit). `.cancelled` ≡ `.ended`.
Rotation mid-pinch: `setViewport` preserves the center (S7) then the re-anchor above. Pinch when content < viewport at min: bounds collapse, offset
rubber-bands around the centered pad and the residual spring returns it. Zoom disabled by `zoomRange` removal mid-session → `.ended` path.

## 8. Tests

Unit (Swift Testing, `Tests/ZTronScrollViewTests/PinchSessionTests.swift`, `ZoomStateTests.swift`, both OS storage paths where state is involved):
1. Focal invariance: random pinch sequences (spread + two-finger pan) with true centroids → `contentPoint(under: c_t)` − u ≤ 1e-9 pre-snap, ≤ 0.5 pt after
   display-scale rounding; with insets ≠ 0 and `.center` alignment at scales below fit.
2. Limits: `.fit`/`.fill` resolve on resize (portrait→landscape), range normalization, `isZoomEnabled` false for 1…1; out-of-range scale after resize clamps with
   the visible center kept.
3. Resistance symmetry: |ln(shown(2·max)/max)| == |ln(shown(min/2)/min)|; `unresisted(resisted(x)) ≈ x`; bouncesZoom = false → clamp exactly.
4. Bounce-back anchor: release at 1.6·max with centroid c → the content point under c at release is under c at every sample and at the end; end scale == max exactly;
   offset within bounds at settle; `isZoomBouncing` true during, false after; no overshoot in log space.
5. One-finger lift: pinching → `fingerCountChanged(1)` → pan `rebase` → the next `dragChanged` with the same translation produces `setOffset == presentation` (no jump);
   with a dead DragGesture, synthesized events continue the pan.
6. Delegate order (coordinator `effectsLog` + recording delegate): willBeginZooming → (didZoom, didScroll)… → [bounce frames] → didEndZooming(atScale:); at most one
   didScroll/didZoom per `step(to:)`; combined release yields didEndDragging(willDecelerate: false) when a bounce starts; programmatic zoom fires no didEndZooming.
7. Reader tier: zoom-only `ZTronScrollReader` body count unchanged across 100 pan frames; offset-only reader unchanged across a scale-only pinch.
8. Programmatic: setZoomScale anchors at the visible center with insets/pad; zoom(to:) fits and centers; both clamp to limits.

Demo UI (`ZoomScreen`: coordinate grid with 50 pt labelled cells, launch arg `-ZTronScreen zoom`, DEBUG counters `zoom.didZoom`, `zoom.didScroll`,
`zoom.bounce`, `content.body`, `reader.zoomOnly`; `ZoomUITests`) on iOS 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`:
a. `XCUIElement.pinch(withScale: 2, velocity: 1)` on the grid → the cell under the screen center stays (label read back via accessibility value), `content.body` 0 during the pinch.
b. Pinch to 3× with max 2 → bounce back to exactly 2.0, `zoom.bounce` 1, didEndZooming after the bounce.
c. Pan after zoom → `reader.zoomOnly` unchanged, `zoom.didScroll` ≥ frames − 1 and ≤ frames.
d. Controls unaffected: Button tap fires inside a zoomed grid; pinch over a Button zooms.
e. Double tap (opt-in via launch arg) zooms to max around the tap, second double tap returns to min.

## 9. Builder sessions and file ownership

- **(a) state + PinchSession + unit tests:** new `Gesture/PinchSession.swift`; `Gesture/PanSession.swift` (`rebase`), `Gesture/PanCoordinator.swift`
  (pinch handling, `makeZoomGeometry`, drop pan setOffset while pinching, combined release); `State/ZTronScrollState.swift` and `State/ScrollStateTypes.swift`
  (§2 additions, `.zoomBounce` motion, channel publishing, setZoomScale rewrite, `zoom(to:)`); `ZTronScrollView.swift` (`zoomRange`, alignment default);
  `Tests/ZTronScrollViewTests/{PinchSessionTests,ZoomStateTests}.swift`. Exit: `scripts/test.sh -only-testing:ZTronScrollViewTests` green on 27.0 and 17.5.
- **(b) gesture adapter + demo + UI tests** (starts after (a) is committed): new `Gesture/PinchGestureAdapter.swift`; `Gesture/PanGestureAdapter.swift`
  (`GestureAttach` third gesture), `Gesture/CatchObserver.swift` (centroid, count changes), `Modifiers/ScrollEnvironment.swift` (double-tap, zoom-range
  env twins); Demo `ZoomScreen`, `DemoApp` arg, `ZoomUITests`. Exit: §8 a–e on 27.0 preferred + forced, 17.5; record centroid-estimate accuracy per path.
Neither session touches `Packages/ZTronScrollPhysics` or `ScrollArbitration`. If a solver gap appears, (a) files it in the handoff and works around it in PinchSession.

## 10. Device risks to check first

- R1: SwiftUI `DragGesture` may fail/cancel when a second finger lands (and may not resume on lift). Decides whether the synthesized-pan path (§4) is the
  main path on 18+ and whether 15–17 can meet "lift continues as a pan" at all. Check on 27.0 first, then 17.5.
- R2: `SpatialEventGesture` event cadence vs. `MagnifyGesture` updates: the centroid used for a `.changed` may lag one event (≈ 8 ms); measure the focal error on
  device with the grid, target ≤ 0.5 pt; if lagging, apply the latest centroid at the frame tick instead of at the gesture callback.
- R3: `XCUIElement.pinch` on the simulator may not produce spatial events (centroid nil on 18+ path) — then UI tests a–c run on the estimate path only; note it.
- R4: `TapGesture(count: 2)` composed simultaneously may delay or swallow single taps on Buttons (S12 checklist). If so, the helper requires a hit-test gate or is dropped from M4.
- R5: Pinch starting during a pager's horizontal drag (ScrollArbitration): the inner view must still zoom; verify the `.ignored` pan does not block pinch events.
- R6: 27.0 pointer input (trackpad pinch) arrives through MagnifyGesture without spatial touches → centroid fallback on 18+; use the pointer location if exposed.

## Orchestrator resolutions (2026-10-18)
- Q1 Zoom bounce phase = `.decelerating` (consistent with the pan bounce-back; `isZoomBouncing` distinguishes it).
- Q2 iOS 17 centroid: implement drag-follow as designed; session (b) measures start-only vs drag-follow on 17.5 and
  keeps the better one (record the error in the handoff and the parity matrix).
- Q3 Accepted: if `DragGesture` dies on the second finger, the synthesized-pan path is primary on 18+; the 15–17
  gap is a documented limitation (S14 §6).
- Q4 `setZoomScale` is used by `Tests/ZTronScrollViewTests/{TargetPresentationTests,StateStorageTests}.swift`:
  session (a) replaces the formula with `ZoomSolver.zoom(to:anchoredAtVisibleCenterOf:)` and updates those
  assertions if they encoded the old (inset-blind) result; the visible-center anchor must still hold.
- Q5 `StateChannel` already has separate `.offset`, `.zoom`, `.metrics`, `.phase`, `.target` — no new channel needed.
