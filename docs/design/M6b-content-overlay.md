# M6b · Content-integral overlay (`scrollContentIntegralOverlay`) — design, no code (2026-10-21, Architect, Fable 5.1)

Scope: the user's request and refinements of 2026-10-21 (§0), SPEC S4 (render contract), S5 (tree), S7 (rotation), S8-2/3 (member + twin),
S11 (API), S12 (touches), S14 (tests). Builds on M2 (`ContentTransform`), M5 D16–D19 (resize commit, turn origin), M6 (`ScrollViewConfig`
members / `ztronScroll…` twins, `ztronScrollID` registry), M8-1 (`ChromeLeaf`), M8-chrome §6 (`ztronScrollCounterScaled`). SPEC amendment
2026-10-21 (user) written alongside: S4 tier row, S8 inventory, S11 signatures, S14 demo / unit / acceptance bullets. Proposed decision: D34.

## 0. Interpretation (to confirm)

`ZTronScrollView { map }.scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .bottom, size: .ideal) { Pin() }`
draws `Pin` as a part of the content: laid out in the **unscaled content space** under the transform, so it scrolls and zooms with the
content like a marker drawn on a map; positioned by an **anchor that names a content point** (nine named alignments, `.relative(ZTronUnitPoint)`,
`.absolute(CGPoint)` in content points) on which the overlay's **`overlayAnchor` point** (a `UnitPoint`, default `.topLeading`) is pinned;
**sized against the content size** (`.fillMaxSize`, the default: the whole content rect; `.fillMaxWidth(aspect)`: width = content width,
height = width / aspect; `.fillMaxHeight(aspect)`; `.relative(ZTronUnitSize)`: a clamped fraction of the content size per axis; `.absolute(CGSize)`: content
points; `.ideal`: the view's ideal size); frame re-derived whenever the content's size changes (a reflow on rotation, a growing list, an
image swap) and **animated to the new frame exactly as the content itself animates** (in lockstep with the system rotation transition, every
frame; D16/D18 timing is irrelevant to it, §2). Not a viewport overlay: SwiftUI's `.overlay(alignment:)` on a scroll view never moves.

## 1. Semantics

**Coordinate space.** The overlay is a child of the content node, inside `"ztronScroll.content"` and the nested-arbiter space, below
`ContentLayoutHost` and `TransformHost`. Its frame is in unscaled content points; the effect maps it with `x_v = s·x_c + pad − o` like
every content pixel. Consequences: `ztronScrollID` on an overlay element registers a content-space frame (a marker is a scroll target,
`proxy.scrollTo(markerID)` works); `onZTronScrollVisibilityChange` and `ztronScrollTransition` work on it unchanged.

**Scaling.** Default `.withContent`: the overlay's content scales with the zoom (it is content). `.counterScaled` keeps a constant
on-screen size: the frame is still resolved in content space and the overlay's anchor point `q` stays glued to the content point `P`,
but the drawing is scaled by `1 / zoomScale` around `q` — the M8-chrome §6 helper `ztronScrollCounterScaled(anchor: q)` (CLAUDE.md
name) applied to the overlay inside the host, a hot `GeometryEffect` on the `.zoom` channel (zoom bounce included); nested effects
compose with `ContentTransform`. Hit-testing follows the drawn geometry on both settings.

**Anchor and size resolution** (pure, `ContentOverlayMath.resolve`; `W × H` = the content size the host is laid out with):

```
P   anchor (a content point):  named α → (W·uα.x, H·uα.y)   uα: topLeading (0,0), top (.5,0), … center (.5,.5), … bottomTrailing (1,1)
                               .relative(p) → (W·p.x, H·p.y)       p: ZTronUnitPoint, clamped to [0, 1]; the named cases are sugar for this
                               .absolute(A) → A                     unscaled content points
q   overlayAnchor: UnitPoint (SwiftUI's nine statics `.topLeading` … `.bottomTrailing`, or any point), default .topLeading
S   .fillMaxSize (default)  (W, H): F = the whole content rect; P and q are IGNORED; a view that takes less is centred in F (= SwiftUI `.overlay`)
    .fillMaxWidth(height: L) (W, L_h)    L_h: .ideal → nil (SwiftUI decides), .aspectRatio(r) → W / r, .absolute(h) → h, .relative(k) → H·k
    .fillMaxHeight(width: L) (L_w, H)    L_w: .ideal → nil, .aspectRatio(r) → H·r, .absolute(w) → w, .relative(k) → W·k
                             .fillMaxWidth(r) / .fillMaxHeight(r) are sugar for .aspectRatio(r), nil → .ideal (revision R6)
    .relative(k)            (W·k.width, H·k.height)      k: ZTronUnitSize, clamped to [0, 1]
    .absolute(s)            s, unscaled content points: independent of the content size (only the origin follows it)
    .ideal              unspecified proposal: the view's ideal size (`fixedSize()`: a 6 pt marker, a label at its natural size)
v   the size the view takes for S (Layout: sizeThatFits(S); fallback: the .frame(S) box, ideal on a nil axis)
F   origin = P − (q.x·v.width, q.y·v.height), size = v       = anchorPoint(content rect) − overlayAnchor × overlaySize, every anchor case
```

One rule covers every case: *the overlay's `overlayAnchor` point sits on the content point `anchor`* — `.absolute(A)` included: it pins
the overlay's `overlayAnchor` point at `A` (the default `.topLeading` is UIKit's `frame.origin` reading; a pin's tip is `overlayAnchor:
.bottom`). `anchor` names a content point only and `overlayAnchor` the overlay's point, so the two are orthogonal: SwiftUI's
`.overlay(alignment: .center)` on a sized view is `anchor: .center, overlayAnchor: .center`; the default `.fillMaxSize` is `.overlay` as is
(it fills the modified view, here the content). `overlayAnchor` is a plain `UnitPoint`: the user's list is exactly SwiftUI's nine `UnitPoint`
statics, no new enum. Every `.relative` takes a clamped unit type (`ZTronUnitPoint`, `ZTronUnitSize`, `ZTronUnitLength`: SwiftUI's `UnitPoint` does not clamp,
its initializer stores any value), so a relative anchor or size can never leave the content (R6). Aspect ratio = width / height (SwiftUI `aspectRatio`): `.fillMaxWidth(16/9)` → `W × 9W/16`.

**Degenerate inputs** (normalized when the size is built, so sizes compare equal iff they draw the same frame). `r ≤ 0` or non-finite → `.ideal`
(reported in DEBUG by `ZTronDiagnostics`, R7); an overflowing `W / r` or `H·r` → 0 (reported at layout); unit values clamp to `[0, 1]` (NaN → 0, +∞ → 1);
absolute lengths and sizes clamp to `≥ 0`; `W` or
`H` = 0 (empty content) → the frame collapses on that axis for the fill / relative sizes, an `.ideal` or `.absolute` view sits at `P`
at its size; nothing is hidden (an empty content is the app's state, not ours). "Unmeasured, first layout" does not exist here: the overlay
is laid out in the same pass as the content, from the content's own size, never from the metrics (§2) — no first-frame flash, no stale
frame on a late measurement.

**Exceeding the content.** Allowed and drawn (the content is not clipped by its bounds; the viewport clips drawing and hits, S5). The overlay
is never measured: `.overlay` does not change its base's size, so it does not extend the scrollable range — a banner hanging below
the content is reachable only as far as the content scrolls, exactly like `.overlay` on a view inside a native `ScrollView`. Documented.

**Hit-testing (S12).** Default: the overlay receives touches like content, above it in z-order: a Button in a banner fires on tap, a pan
that starts on it scrolls, a pinch on it zooms — the gestures live on the viewport, the content composes per S12, and `TransformHost`'s
`allowsHitTesting(!blocked)` / `disabled(blocked)` cover the overlay too (catch during deceleration, cancel-on-drag). The host itself
draws nothing and has no `contentShape`, so the empty area of an overlay is transparent to touches. Opt-out per overlay: the user applies
`.allowsHitTesting(false)` inside the builder (no API). Content scrolled outside the viewport receives no touches (clip).

**Accessibility.** Ordinary content elements (XCUI reads their `frame` — the demo test relies on it). An overlay outside the content rect is
still an element while inside the viewport clip. Identifiers, traits and `accessibilityElement(children:)` are the user's.

**Several overlays, ordering.** Every call appends one `ContentOverlayDecl`; one host places them all, in order, all above the content:
environment twins first (outermost first, lowest), then the members in call order (the M7/M8-8 convention). Identity is the decl's key
(a member's position in the list, a twin's `@State` token — `ObserverDescriptor.key`'s rule): re-applying the modifier with a new anchor or
size re-lays out the same overlay (its `@State` survives), a changed call order is a new identity, like a chain of `.overlay`s.

## 2. Mechanism (honours S4; one hook in `ScrollContainer`)

```
content.overlay(alignment: .topLeading) { ContentOverlayHost(decls) }   ← the FIRST modifier on `content` in ScrollContainer.body
   .modifier(ContentSizeMeasure)  .modifier(NamedSpace "ztronScroll.content")  .modifier(ContentLayoutHost)  .modifier(TransformHost) …
```

- **Placement is layout, not state.** `.overlay` proposes the content's *current layout size* to the host in the same layout pass that sized
  the content. The host resolves §1 from that size: it reads **no** metrics, **no** offset, **no** zoom, subscribes to **no** channel. Scrolling and
  zooming are the effect above it (render-time transform, no layout, no body): zero layout passes, zero bodies, same as the content.
- **16+ (`state.usesLayoutProtocol`, R6 constant branch):** `ContentOverlayLayout: Layout` — `sizeThatFits` returns the proposal; `placeSubviews`:
  per subview `subview.place(at: P, anchor: q, proposal: S)` (`place(at:anchor:)` is §1's rule verbatim; `.fillMaxSize`: `place(at:
  centre, anchor: .center, proposal: (W, H))`; `.ideal`: `proposal: .unspecified`); `Cache` holds the resolved frames per proposal. No
  body runs on a content-size change: only `placeSubviews`. Counter `contentOverlay.place`.
- **15 / `-ZTronForceAllFallbacks`:** `GeometryReader { g in ZStack(alignment: .topLeading) { ForEach(decls) { d in d.view.frame(S(g.size))
  .alignmentGuide(.leading) { v in v.width·q.x − P.x }.alignmentGuide(.top) { v in v.height·q.y − P.y } } } }` (`.fillMaxSize`:
  `.frame(width: W, height: H)` at the origin; `.ideal`: `.fixedSize()`) — the guide closures get the view's own dimensions, so
  `origin = P − q·v` needs no measurement pass and no `@State`; the reader's closure runs once per layout size change (counter
  `contentOverlay.host.body`), the overlays' bodies do not (same values → no diff).
- **Rotation, D16/D18** (corrected after L1/L2). SwiftUI lays the content out once at its new size and animates the change by
  interpolating every view's frame with the ambient transaction's curve (no layout pass per frame). The overlay, placed by the same pass,
  is interpolated with the same curve, so its pinned point moves exactly like the content point it marks; the effect draws the whole
  subtree with the offset/scale it resolves for `ResizeMath.presented(commit, size)`. No second interpolation to keep in step with the
  commit, no dependency on whether the reflowed size lands in the same turn (D18) or later (M5 §9), nothing written to the state.
  Measured in L2: overlay centre vs the content's own `GeometryReader` marker at the same fraction ≤ 6e-14 pt after Zoom, a drag,
  4 rotations and a pinch, on 27.0 and 17.5, both paths; a per-tick lockstep probe (fill overlay size vs content size) never lagged.
- **Other content-size changes.** A list that grows (`cs idle`), an image swap, a `withAnimation` around a content change: the overlay
  follows the content's drawn size each frame — animated when the content's size animates, a snap when the content snaps (integral). It does
  not glide on its own while the content jumped (that is the rejected metrics-driven variant: a `ChromeLeaf` on `.metrics` only +
  animatable `.frame`/`.offset`; exact only when the overlay's curve equals the content's, wrong by one frame on the 15 preference path,
  and able to lag a late measurement — kept as the answer to Q4 if the user wants independent animation).
- **Counters (DEBUG):** see the L1 notes. Tiers (S4 row, as measured): scroll, zoom, refresh, collapse → no body anywhere, no host
  body, no reader closure; placements 0 with no control in the overlays, about 2 per gesture on 16+ when an overlay holds a control
  (the content gate's `.disabled` flips re-measure it), more while a pressed control is cancelled; a content-size change → one
  placement pass (or one reader closure on 15); a container body evaluation → host body 1, overlay bodies 0 for unchanged inputs.
- **Type erasure.** `ContentOverlayDecl { key, anchor, overlayAnchor, size, scaling, view: AnyView }`; the member and the twin both store
  `AnyView(content())` (M8b-2's custom refresh indicator does the same). `AnyView` keeps identity while the wrapped type is constant; its
  cost is a possible body re-run per container body evaluation (R1), never on motion. If `V: Equatable` the overload wraps `EquatableView`.

## 3. Public API (names per CLAUDE.md; S8-2a member returning `Self` + S8-2b twin)

```swift
// Superseded by revision R6 (see "Open questions — resolved"); the current types are SPEC S11's block:
// ZTronUnitLength / ZTronUnitSize / ZTronUnitPoint (clamped to [0, 1]), ZTronContentOverlayAnchor.relative(ZTronUnitPoint),
// ZTronContentOverlayLength (.ideal / .aspectRatio / .absolute / .relative) and the struct ZTronContentOverlaySize with
// .fillMaxSize, .ideal, .fillMaxWidth(_:) / .fillMaxWidth(height:), .fillMaxHeight(_:) / .fillMaxHeight(width:), .relative(_:),
// .relative(width:height:), .absolute(_:).
public enum ZTronContentOverlayScaling: Equatable { case withContent, counterScaled }   // default .withContent

extension ZTronScrollView {
    /// An overlay laid out in the unscaled content space: it scrolls and zooms with the content. The overlay's `overlayAnchor` point is
    /// pinned on the content point `anchor`; `size` is resolved against the content size; both follow it, frame by frame, whenever it
    /// changes (rotation included). Several calls stack in order.
    public func scrollContentIntegralOverlay<V: View>(anchor: ZTronContentOverlayAnchor = .center, overlayAnchor: UnitPoint = .topLeading,
                                                      size: ZTronContentOverlaySize = .fillMaxSize,
                                                      scaling: ZTronContentOverlayScaling = .withContent,
                                                      @ViewBuilder content: () -> V) -> Self
}
extension View {
    /// Environment twin: every `ZTronScrollView` below gets this overlay (nesting included; the members draw above it).
    /// No native counterpart: a SwiftUI `ScrollView` below ignores it (its `.overlay` is the viewport's).
    public func ztronScrollContentIntegralOverlay<V: View>(anchor: ZTronContentOverlayAnchor = .center, overlayAnchor: UnitPoint = .topLeading,
                                                           size: ZTronContentOverlaySize = .fillMaxSize,
                                                           scaling: ZTronContentOverlayScaling = .withContent,
                                                           @ViewBuilder content: () -> V) -> some View
}
```

- `content` is non-escaping and evaluated at the call, like SwiftUI's `overlay`; the user's `V` is wrapped once (§2 identity).
- iOS 15: no `Layout` → the `GeometryReader` + `alignmentGuide` host (§2), same `ContentOverlayMath`, same API and behaviour; the branch is
  the `usesLayoutProtocol` flag `ContentLayoutHost` already uses. `.counterScaled` is 15+ (a `GeometryEffect`).
- Parity note (parity matrix row, status "full, no native counterpart"): SwiftUI's `.overlay(alignment:)` on a `ScrollView` is applied to
  the viewport (it does not scroll); `.overlay` on the content inside a `ScrollView` scrolls but is sized by the content's layout and cannot
  express a fraction of the content or an aspect without a `GeometryReader`, and SwiftUI has no zoom to keep it integral to. Hence a new
  name; `overlay(alignment:)` on `ZTronScrollView` keeps SwiftUI's meaning (viewport), so no existing call site changes meaning. The
  `.fillMaxSize` default mirrors SwiftUI's own `.overlay`, which fills the modified view by default — here the content, in content space.
- Spelling from the user (2026-10-21): `.scrollContentIntegralOverlay(anchor:overlayAnchor:size:)`, `overlayAnchor` default `.topLeading`,
  `.fillMaxSize` default, `.fillMaxWidth(16/9)`, `.relative(CGSize)` / `.absolute(CGSize)`. Added with defaults: `scaling:` (Q1); the
  `.ideal` case keeps the ideal-size behaviour reachable (SwiftUI's term, R4).

## 4. Tests

**Unit** (`Tests/ZTronScrollViewTests/ContentOverlayTests.swift`, Swift Testing, `@Suite(.serialized)`, `OSPath.allCases`):
- `ContentOverlayMath.resolve`: the nine named anchors × `overlayAnchor` {.topLeading (default), .center, .bottom, (0.25, 0.75)} ×
  {fillMaxWidth(16/9), fillMaxWidth(nil), fillMaxHeight(4/3), relative(0.5 × 0.2), absolute(120 × 40), ideal} equal the §1 formula
  (origin = anchorPoint(content) − overlayAnchor × overlaySize); `.relative(0.3, 0.65)`; `.absolute(A)` pins the `overlayAnchor` point at `A`;
  `.fillMaxSize` gives the content rect whatever the anchors; degenerate: `W = 0`, `H = 0`, aspect 0 / −1 / ∞ / NaN → nil, negative
  `k` / `s` → 0, overlay larger than the content (negative origin, kept).
- Hosted (the `host(...)` rig of `LayoutHostTests`): a 200-wide viewport, content `200 × 1000`, overlay `.relative(0.3, 0.65)`,
  `overlayAnchor: .center`, `size: .ideal` with a `10 × 10` marker carrying `.ztronScrollID("m")`: the registry's content-space frame
  of `"m"` equals the formula (both host paths read the same registry); a `.fillMaxSize` overlay's frame equals the content rect. Then the
  content's height becomes 1500 (`@State`): both frames equal the formula at the new size; `content.body` +1 (its own change only),
  `contentOverlay.body` ≤ 1, `place` / `host.body` ≥ 1.
- Motion counters (the scripted scroll / zoom / clock steps of `TransformTests`): a 3 s fling, a rubber band, a pinch with bounce, an
  animated `scrollTo`, `setZoomScale(animated:)`: `content.body` 0, `contentOverlay.body` 0, `contentOverlay.host.body` 0,
  `contentOverlay.place` 0 (Layout path); the registry's `writes` flat.
- Identity: re-applying the member with another anchor keeps the overlay's `@State` (`BodyCount.ids` stays one id); a second member call
  is a second overlay above the first; twin + member coexist (twin below); the twin reaches a nested inner `ZTronScrollView` with its own copy.
- `.counterScaled`: at zoom 2 the overlay's drawn size equals its ideal size and its anchor point stays on `P` (read through the effect's
  value, as `TransformTests` reads `ContentTransform`).
- `LayoutHostTests` unchanged and green on both paths (the overlay must not change the measured content size, R4).

**Demo** (`ResizeScreen`, launch flag `-ZTronResizeOverlay` on the user trees): on `UserTreeScroller` add
`.scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .center, size: .ideal) { 6 pt red circle,
id "overlay.detail" }`, `.scrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom, size: .fillMaxWidth(16/9)) { translucent
banner, id "overlay.banner", with a Button "overlay.banner.button" that bumps the `button.fired` counter }` and
`.scrollContentIntegralOverlay(anchor: .topLeading) { a faint tint, id "overlay.fill" }` (the `.fillMaxSize` default); a
`-ZTronResizeOverlayCounterScaled` variant of the marker. The readout appends `contentOverlay.*` counters to `resizeInfo`.

**UI** (`Demo/ZTronScrollViewDemoUITests/ContentOverlayUITests.swift`, on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`; the
marker helpers of `ResizeUITests` move to a shared `MarkerSpace.swift`):
- Rotate ×4 on `-ZTronResizeUserTree2` zoomed 2.5× on the detail (the `testUserTreeZoomedDetailStaysCentredAcrossRotation` script):
  after every rotation `overlay.detail`'s frame centre coincides with the existing `marker.detail` (the `GeometryReader` marker at the
  same fraction) within 0.5 pt, and with `screenPoint(markers, (0.3, 0.65))` within 1 pt; the banner's width = the marker-derived content
  width ± 1, height = width · 9/16 ± 1, bottom edge = content bottom ± 1; `overlay.fill`'s frame = the marker-derived content rect ± 1;
  even rotations: every overlay frame back to its initial one within 0.5 pt (criterion B, D17). Counters after the four rotations:
  `contentOverlay.body` ≤ 4, `content.body` as today.
- Scroll + zoom: after `Zoom` and a drag, the same coincidence holds and the banner is 2.5× wider; a tap on `overlay.banner.button` fires
  once; a pan that starts on the banner scrolls and does not fire it (S12 pattern of `ControlsScreen`).
- Counter-scaled: at 2.5× the marker's frame is still 6 × 6 on screen, centred on `marker.detail`.

## 5. Builder split, sequencing, budget, risks

| Session | Files (owned) | Depends on | Budget |
|---|---|---|---|
| L1 library + unit (Sonnet builder) | new `Sources/ZTronScrollView/ContentOverlay/{ContentOverlayTypes,ContentOverlayMath,ContentOverlayHost}.swift`, `Modifiers/ContentOverlayTwins.swift` (member, twin, env key, `ScrollViewConfig.contentOverlays` in `ScrollConfigTwins.swift`), one `.overlay` line in `ZTronScrollView.swift`, counters, `Tests/…/ContentOverlayTests.swift` | the M7-s3 / M8-2 / M8b-3 commits that touch `ScrollConfigTwins.swift` and `ZTronScrollView.swift` (rebase otherwise); `.counterScaled` needs M8-4's `Helpers/CounterScaled.swift` — L1 builds it to the §6 spec if M8-4 has not started | 1.5–2 % |
| L2 demo + UI (Sonnet builder) | `Demo/…/ResizeScreen.swift` (flag + overlays), `Demo/…UITests/{ContentOverlayUITests,MarkerSpace}.swift` (+ `ResizeUITests` imports the helpers) | L1 committed | 1–1.5 % + 4 UI runs |
| docs (clerk) | parity row, `docs/progress/M6b-s1.md`, Orchestration State row + D34, usage log | L2 | 0.3 % |

Sequencing: after step 4's running sessions commit (M7 session 3, M8-2, M8b-3), before M9 (the virtualizing stacks must not learn about
overlays: the host is above the content node and sees the materialised size only). Independent of D31 (c) and NESTED-mixed. Total ≈ 3–4 %.

Risks, ranked:
1. **R1 `AnyView` re-runs the overlay body on every container body evaluation** (never on motion; once per rotation because the user's
   `GeometryReader` rebuilds the view anyway). Measured by `contentOverlay.body`; mitigation `EquatableView` for `V: Equatable`, then a
   generic `ContentOverlayLeaf<V>` captured in the decl's closure.
2. **R2 The 15 fallback's `GeometryReader` closure re-runs per scroll frame** if the effect's transform counts as a geometry change for
   descendants. The demo's `ContentMarkers` (same shape) has lived under the effect since M5 with `content.body` 0 and no noted cost;
   `host.body` during the scripted fling decides. Fallback of the fallback: the metrics-driven host on 15 only (§2, degraded lockstep).
3. **R3 Per-frame `sizeThatFits` in `placeSubviews` during a rotation** (a Text measuring 60× per rotation): `Cache` by proposal; trivial.
4. **R4 The 15 `ContentLayoutHost` path** (`fixedSize` + `Color.clear.overlay(.topLeading)`) must measure the overlaid content as before:
   `LayoutHostTests` is the gate.
5. **R5 Device checks:** hit area of a `.counterScaled` overlay (effect-transformed hits), an overlay hanging outside the content near an
   edge (reachable only as far as the content scrolls), VoiceOver order of overlays vs content. Shared files (`ScrollViewConfig`,
   `ScrollContainer.body`): one writer at a time, L1 starts after the sessions above commit.

## Open questions — resolved by the user (2026-10-21, in this session; nothing left open)

Settled by the refinements: `overlayAnchor: UnitPoint = .topLeading` (`.absolute(A)` pins that point at `A`), `.relative(CGSize)` /
`.absolute(CGSize)`, `.fillMaxSize` default. Answers to Q1–Q5:
- **R1 Scaling.** `.withContent` is the default (the overlay's zoom is integral with the content's `zoomScale`); `.counterScaled` stays an
  option on the interface (`scaling:`).
- **R2 Hit-testing.** Overlays receive touches like content by default; opt out inside the builder. Confirmed.
- **R3 Animation.** When the content snaps, the overlay snaps with it; no independent-animation parameter. Confirmed.
- **R4 Spellings, "parity with SwiftUI's `.overlay`".** `anchor:` defaults to `.center` (SwiftUI's `alignment: .center`); with the
  `.fillMaxSize` default the bare call is `.overlay` exactly. `.fillMaxWidth()` keeps the optional aspect (nil = ideal height, as
  `.frame(width:)` does). The ideal-size case is spelled `.ideal` (SwiftUI's word: `idealWidth`, "ideal size"). Builder note: a sized
  overlay with no anchors given lands its top-leading on the content centre (`overlayAnchor` default `.topLeading`, the user's choice);
  `.overlay(alignment: .center)` parity for sized views is `overlayAnchor: .center` — one default to flip if the user prefers.
- **R5 Twin.** Kept, for consistency with the rest of the API (every member has a `ztronScroll…` twin, S8-2b / S11). Confirmed again after
  the build (2026-10-21): the twin stays environment-only (`some View`); `scrollContentIntegralOverlay` is the chainable spelling.
- **R6 Units and free axes (2026-10-21, user, after M6b-s1).** `.fillMaxWidth` / `.fillMaxHeight` take the free axis as a length:
  `.ideal` (SwiftUI decides), `.aspectRatio(r)`, `.absolute(points)`, `.relative(fraction of the content on that axis)`; the old
  `.fillMaxWidth(16/9)` / `.fillMaxWidth()` spellings remain as sugar. Every `.relative` runs on a clamped unit type
  (`ZTronUnitLength`, `ZTronUnitSize`, `ZTronUnitPoint`; the anchor's `.relative` included, so it stays inside the content; `.absolute`
  and `overlayAnchor` stay unclamped). `ZTronContentOverlaySize` became a struct of static constructors (Swift cannot overload enum
  cases by type) with canonical equality. Source change: `.relative(UnitPoint)` → `.relative(ZTronUnitPoint)`, `.relative(CGSize)` →
  `.relative(ZTronUnitSize(_:))`. Built in M6b-s2 (`docs/progress/M6b-s2.md`).
- **R7 Clamps are reported (2026-10-21, user: "Clamping should at least produce a log, otherwise it becomes hard to track an error
  originating from an unexpected clamp").** Every silent normalization of caller input is reported in DEBUG builds by an internal
  `ZTronDiagnostics` (Foundation `NSLog`; `os` is outside the allowed imports) with the caller's `#fileID:#line`: the clamping
  initializers, the size constructors, both modifiers and `ztronScrollCounterScaled` gained defaulted `fileID:line:` parameters (source
  compatible for calls; unapplied references such as `.map(ZTronUnitLength.init)` no longer type-check). Literal arguments go through the
  literal initializers (SE-0213) and are re-reported with the enclosing call's location; layout-time reports carry the modifier call's
  location. Once per call site and value, at most 8 values per site, 512 keys per process; a symbolic breakpoint on
  `ZTronDiagnostics.report` stops at every normalization. Release builds compile the report path out. Built in M6b-s3.

## L1 notes (2026-10-21, builder; after the two-reviewer pass)

What L1 built where it differs from, or settles, §2–§5 (sections 1–4 and R1–R5 still bind):
- **API = SPEC S11 exactly, plus `Sendable`.** One member and one twin. An `Equatable` overlay (a `Text`, an `Image`, a `Color`
  included) is detected at the call (`ContentOverlayEquality.make`, `as? any Equatable`) instead of separate `V: Equatable`
  overloads: same diffing, no second public symbol per name, unambiguous DocC links. The host keeps the previous `AnyView`
  while the new value is `==` (`ContentOverlayViewCache`); `EquatableView` alone did not gate the body inside `AnyView`.
- **Counters (DEBUG).** `contentOverlay.body` = `ContentOverlayLeaf<V>`, the erased root whose only input is the user's view
  (it runs exactly when that view would); `contentOverlay.host.body` = `ContentOverlayHost.body`, container evaluations only;
  `contentOverlay.reader` = the iOS 15 host's `GeometryReader` closure (each reflow frame and each container evaluation);
  `contentOverlay.place` = `placeSubviews`; the `contentOverlay.badAspect` note was replaced by `ZTronDiagnostics` (R7). L2 reads these from the readout.
- **No `Cache` in `ContentOverlayLayout` (R3).** A rotation proposes a new content size every frame, so a per-proposal cache
  never hits while it matters; measuring happens only on an open axis (`.ideal`, nil aspect); nothing can go stale.
- **The overlay subtree drops the twin list** (`transformEnvironment` on the host): a `ZTronScrollView` inside an overlay does
  not inherit the overlay twins (a twin holding a scroll view nested without end). Scroll views nested in the content keep them.
- **`.counterScaled` = the S6 helper.** `Helpers/CounterScaled.swift` ships `ztronScrollCounterScaled(anchor:)` (M8-chrome §6,
  built here per §5 since M8-4 had not started); the host applies the same `CounterScaleLeaf`. M8-4 builds sticky/parallax/LOD
  next to it and must not re-implement counter-scaling. The leaf reads `targetZoom` alone: tracked on that key path on 17+,
  woken by `ChannelStorage.targetZoomChannel` (target-zoom writes only) on 15–16, so presentation-only zoom writes (the
  transaction probe, a rotation's resize tick) wake it on neither path. Pivot: `overlayAnchor`, the centre for `.fillMaxSize`.
- **Unverified: the iOS 15 runtime.** The reader host ships on iOS 15 only; R2 (the closure must not re-run per motion frame,
  nor on the `.disabled` flips at motion start/end) is measured on the 17.5 / 27.0 runtimes with forced fallbacks, not on 15.
  Run `ContentOverlayTests` (motion, refresh, probe) on an iOS 15 simulator (Xcode 26.x, older macOS) before calling S4 met
  there; the contingency stays §2's metrics-driven host on 15 only.

## L2 notes (2026-10-21, demo + UI; orchestrator summary)

- Demo: `-ZTronResizeOverlay` on the resize screen's user trees (marker `.relative(0.3, 0.65)` / `.center` / `.ideal`, banner `.bottom` /
  `.bottom` / `.fillMaxWidth(16/9)` with a Button, `.fillMaxSize` tint, a `.fillMaxWidth(height: .relative(0.05))` top strip and a
  `.fillMaxHeight(width: .absolute(12))` trailing bar (R6), a constant-input label and a bare `Text`),
  `-ZTronResizeOverlayCounterScaled`, `-ZTronResizeOverlayNoButton`; readout fields `ovb ovh ovr ovp ocs mk bn tn lb btap lks lag rst`. Without
  the flags the screen behaves as before (ResizeUITests 13/13 on all lanes).
- `ContentOverlayUITests` (4 tests × 27.0 / 17.5 × preferred / forced, all green): overlay vs content marker ≤ 6e-14 pt, size = 6 × z,
  banner / tint = content width × z exactly, even rotations restore every overlay frame ≤ 0.5 pt with the detail > 60 pt off centre;
  after a drag, 4 rotations and a pinch every overlay body counter is 0 (positive controls ≥ 1 at launch); the banner Button fires on a
  tap and not on a 100 pt drag that starts on it (the content moved 90 pt); `.counterScaled` keeps 6 × 6 pt at z 1, 2.23, 4.
- Placements during motion: 0 without a control in the overlays; 2 per drag or pinch with the banner Button present (its `.disabled`
  flips); up to ~25 in one drag that started by pressing the Button. Layout only, no bodies; documented in the S4 row instead of fixed.
- Not provable from the app: per-frame lockstep of a `.counterScaled` overlay against the drawn zoom (needs a library DEBUG probe).

