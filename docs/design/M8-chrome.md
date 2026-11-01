# M8 · Chrome: indicators, insets, behavior, keyboard/a11y, helpers, edge effects, containers (design)

Scope: SPEC S6 "Also" (222–236), S8 strategies 1–4 (253–276), inventory 302–321 and 326–329, plus S11 "Delegate callbacks as modifiers" (Amendment 2026-10-19 (user), §7b here). Builds on M5-resize §2/§7
(`contentInset`, `adjustedContentInset`, `ZTronContentInsetAdjustmentBehavior`, `safeAreaInsets` observer) and M6-targets §1
(member/twin/content-level/mirror shapes, `ScrollViewConfig`, `ztronScrollConfig`). Names per CLAUDE.md. iOS 15 deployment.
iOS-26/27-only SDK symbols follow D3 (`#if compiler(>=6.4)` + `#available`, reported through `ZTronCapability.isInBuildSDK`).
Every chrome element is a **leaf** in the viewport overlay: it subscribes to the hot `.offset`/`.zoom` channels (M3 transform host
pattern) and renders itself; user content bodies run 0 times while scrolling, zooming, flashing or fading (S4, tier-0 counter).
M5's "M8b hook" (`headerObscured`, scaling header) is **not** in this doc. Nothing here touches M5/M6 files: chrome state lives in its
own `ChromeConfig` + `EnvironmentValues.ztronChromeConfig` (same resolution order as M6 §1: member ?? twin ?? default).

## 1. Shared types and plumbing (`Chrome/ChromeConfig.swift`, `Chrome/ChromeLeaf.swift`)

```swift
struct ChromeConfig: Equatable {                       // cold; stored on ZTronScrollView (member form) and in the environment (twin form)
    var indicators: (h: ZTronScrollIndicatorVisibility?, v: ZTronScrollIndicatorVisibility?)
    var showsIndicators: Bool?                         // init(showsIndicators:) → false ⇒ both axes .hidden (member precedence)
    var indicatorInsets: EdgeInsets?; var contentMargins: EdgeInsets?   // contentMargins(for:) split
    var flashOnAppear: Bool; var flashTrigger: AnyHashable?
    var clipDisabled: Bool?; var contentBackground: Visibility?
    var offsetAdjustment: ZTronScrollContentOffsetAdjustmentBehavior?
    var dismissesKeyboard: ZTronScrollDismissesKeyboardMode?
    var input: [ZTronScrollInputKind: ZTronScrollInputBehavior]
    var edgeEffect: [Edge: ZTronScrollEdgeEffectStyle?]; var edgeEffectHidden: Edge.Set
    var keyboardScrolling: ZTronKeyboardScrollingMode
}
extension EnvironmentValues { var ztronChromeConfig: ChromeConfig; var ztronViewportFrame: CGRect? /* cold, container-relative frame, §3 */ }
struct ChromeLeaf<Body: View>: View { init(_ state: ZTronScrollState, channels: ChannelSet, @ViewBuilder body: (ChromeSample) -> Body) }
struct ChromeSample { var offset: CGPoint; var zoom: CGFloat; var phase: ZTronScrollPhase; var metrics: ScrollMetrics; var overshoot: CGPoint }
```
Hot values arrive via `ChromeLeaf` only; `ChromeSample.metrics` is M5's cold `ScrollMetrics` (viewport, contentSize, adjustedContentInset).
Twins (`View.ztron…`) write `ztronChromeConfig` **and** apply the native modifier under `#available` (D8 pattern); unprefixed members bind only
on `ZTronScrollView` (parity matrix note). Mirrors: `init?(_ native:)` by `==` against the native statics (all the types below are Equatable),
`var native` the other way; both in `Chrome/NativeChromeBridges.swift`, gated per type.

## 2. Indicators (`Chrome/ScrollIndicators.swift`, exemplar task M8-1)

```swift
public enum ZTronScrollIndicatorVisibility: Sendable, Equatable { case automatic, visible, hidden, never }   // ⇄ ScrollIndicatorVisibility 16+
extension ZTronScrollView {
    public func scrollIndicators(_ v: ZTronScrollIndicatorVisibility, axes: Axis.Set = [.horizontal, .vertical]) -> Self
    public func scrollIndicatorsFlash(onAppear: Bool) -> Self
    public func scrollIndicatorsFlash<T: Equatable>(trigger: T) -> Self
}
extension View {   // twins; native applied when 16+/17+
    public func ztronScrollIndicators(_ v: ZTronScrollIndicatorVisibility, axes: Axis.Set = [.horizontal, .vertical]) -> some View
    public func ztronScrollIndicatorsFlash(onAppear: Bool) -> some View
    public func ztronScrollIndicatorsFlash<T: Equatable>(trigger: T) -> some View
}
extension ZTronScrollState { public var scrollIndicatorInsets: EdgeInsets; public func flashScrollIndicators() }   // UIKit parity
enum IndicatorMath {   // pure, unit-tested; per axis, viewport points
    static func thumb(viewport V: CGFloat, content C: CGFloat, zoom s: CGFloat, inset aci: (start: CGFloat, end: CGFloat),
                      indInset: (start: CGFloat, end: CGFloat), offset o: CGFloat, otherVisible: Bool) -> (origin: CGFloat, length: CGFloat)?
}
```
Resolution (order corrected by the M8-1 addendum below: an explicit value beats the flag): `showsIndicators == false` ⇒ `.hidden` on both axes; else member per axis ?? our env ?? native env
(`horizontal/verticalScrollIndicatorVisibility`, read under `#available(iOS 16.4)`; confirm 16.0 vs 16.4 by compile test) ?? `.automatic`.
Formulas (constants `thickness 3`, `edgeGap 3`, `minLength 36`, `minLengthRubber 8`, `hideDelay 0.4 s`, `fade 0.3 s`, `flashHold 0.6 s`; tune on device):
`E = C·s + aci.start + aci.end`; `T = V − indInset.start − indInset.end − 2·edgeGap − (otherVisible ? thickness + edgeGap : 0)`;
`f = min(1, V/E)`; `ℓ = max(minLength, f·T)`; `o′ = o + aci.start` (0 at the start rest position; same convention as M5 §3);
`p = clamp(o′ / (E − V), 0, 1)`; `origin = indInset.start + edgeGap + p·(T − ℓ)`. Rubber band `d = max(0, −o′, o′ − (E − V))`:
`ℓ′ = max(minLengthRubber, ℓ − d)`, pinned at the start if `o′ < 0`, else at `T − ℓ′`. Returns nil when `f ≥ 1` (`.automatic`) — `.visible`
draws it anyway when `E > V`, never when not scrollable. Opacity: 1 while `phase ≠ .idle`; `.idle` ⇒ after `hideDelay` animate to 0 over `fade`;
`.visible` never fades. Flash (`onAppear`, `trigger` change, `state.flashScrollIndicators()`): opacity 1 for `flashHold` then fade; no-op under
`.hidden`/`.never`. Thumb: `Capsule().fill(.primary.opacity(0.35))`, trailing/bottom edge, `allowsHitTesting(false)`. Both axes visible ⇒ the
vertical thumb's track is shortened (`otherVisible`). Indicator insets: `.automatic` adds `safeAreaInsets` (UIKit `automaticallyAdjustsScrollIndicatorInsets`)
+ `scrollIndicatorInsets` + `contentMargins(for: .scrollIndicators)`. Gap: direct-manipulation thumb dragging (iOS 13 UIKit) — not in M8 (matrix row).

## 3. Content & insets (`Chrome/ContentMargins.swift`, `Chrome/ContainerRelativeFrame.swift`, `Chrome/ClipAndBackground.swift`)

```swift
public enum ZTronContentMarginPlacement: Sendable, Equatable { case automatic, scrollContent, scrollIndicators }   // ⇄ ContentMarginPlacement 17+
extension ZTronScrollView {
    public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for p: ZTronContentMarginPlacement = .automatic) -> Self
    public func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for p: ZTronContentMarginPlacement = .automatic) -> Self
    public func contentMargins(_ length: CGFloat, for p: ZTronContentMarginPlacement = .automatic) -> Self
    public func scrollClipDisabled(_ disabled: Bool = true) -> Self
    public func scrollContentBackground(_ v: Visibility) -> Self
    public func scrollContentOffsetAdjustmentBehavior(_ b: ZTronScrollContentOffsetAdjustmentBehavior) -> Self
}
extension View {   // twins: ztronContentMargins(…), ztronScrollClipDisabled(_:), ztronScrollContentBackground(_:), ztronSafeAreaPadding(_:) / (_:_:)
    public func ztronContainerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View
    public func ztronContainerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat, alignment: Alignment = .center) -> some View
    public func ztronContainerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center, _ length: @escaping (CGFloat, Axis) -> CGFloat) -> some View
}
public enum ZTronScrollContentOffsetAdjustmentBehavior: Sendable, Equatable { case automatic, disabled }   // mirror of the 18+ type
```
- `contentMargins`: `.scrollContent` → `state.contentInset` (M5; adds to the developer value set directly on the state — the member/twin value
  *replaces* a previous member/twin value, never accumulates); `.scrollIndicators` → `indicatorInsets`; `.automatic` → both. Native applied 17+.
- `safeAreaPadding` (17+) is strategy 1: it changes the safe area our root observes (M5 §7). `ztronSafeAreaPadding` applies native 17+, else
  `safeAreaInset(edge:) { Color.clear.frame(length) }` per edge (iOS 15 API) — identical result because both feed `safeAreaInsets`.
- `scrollClipDisabled`: viewport root uses `.clipShape(ViewportClip(disabled:))` (a `Shape` returning the rect, or the rect inset by −1e5 when
  disabled — a parameter change, not a branch flip, M5 R6). `.contentShape(Rectangle())` keeps hit-testing inside the viewport (UIKit `clipsToBounds=false` parity).
- `scrollContentBackground`: accepted and forwarded natively (16+) for Lists/TextEditors inside the content; the ZTronScrollView itself has no
  default background, so no visual change (native ScrollView behaves the same) — matrix row "accepted, no effect".
- `ScrollContentOffsetAdjustmentBehavior` (18+): `.automatic` = M5 §6 `.sizeChanges` rule in `setContentSize`; `.disabled` = keep `offset`, clamp only.
  Stored as `state.contentOffsetAdjustmentBehavior`. The native modifier spelling is unconfirmed (open Q2); we ship ours regardless.
- `containerRelativeFrame` (17+): the native one resolves against SwiftUI's own container and does **not** see our viewport. Content-level dual mode:
  inside a ZTronScrollView (`ztronViewportFrame != nil`) apply `.frame(width/height:, alignment:)` computed from the cold viewport frame
  `F = viewport − adjustedContentInset − contentMargins`; outside, native 17+, else identity (documented gap). Formula per axis for the
  `count/span/spacing` overload: `len = (F − (count − 1)·spacing)/count · span + (span − 1)·spacing`; closure overload: `len = length(F, axis)`.
  Resolved in **unscaled** content units at zoom 1: zooming never relayouts (S4). `ztronViewportFrame` is written by the container once per
  resize commit (cold), so only these leaf modifiers re-run on rotation — not the content bodies.

## 4. Behavior (`Chrome/DismissKeyboard.swift`, `Chrome/ScrollInput.swift`; `ScrollEnvironment.swift` already has disabled/bounce)

```swift
public enum ZTronScrollDismissesKeyboardMode: Sendable, Equatable { case automatic, immediately, interactively, never }   // ⇄ 16+ type
public enum ZTronScrollInputBehavior: Sendable, Equatable { case automatic, enabled, disabled }
public struct ZTronScrollInputKind: Hashable, Sendable { public static let drag, scrollIndicator, keyboard, accessibility: Self }
extension ZTronScrollView { public func scrollDismissesKeyboard(_ m: ZTronScrollDismissesKeyboardMode) -> Self
                            public func scrollInputBehavior(_ b: ZTronScrollInputBehavior, for kind: ZTronScrollInputKind) -> Self }
extension View { public func ztronScrollDismissesKeyboard(_:) -> some View; public func ztronScrollInputBehavior(_:for:) -> some View }
```
- `scrollDisabled` (strategy 1, `isScrollEnabled` 16+, `ztronScrollDisabled` everywhere) and `scrollBounceBehavior` (D8, one-way) exist; M8 only adds
  matrix rows and tests. `refreshable` is S9.
- `scrollDismissesKeyboard`: resolution member ?? ours ?? native env `scrollDismissesKeyboardMode` (16+) ?? `.automatic` (= `.never` for a plain
  scroll view, as UIKit). Pure-SwiftUI dismissal: the viewport root is `.focusable(true, interactions: .activate)` with a private `@FocusState`;
  on `.dragging` entry we set it, which moves focus off the text field and dismisses the keyboard (17+, capability `keyboardScrolling` reused).
  `.interactively` cannot track the keyboard frame without UIKit → behaves as `.immediately` (gap). <17: no public way to resign focus → no-op (gap).
  **The `.never` half is real since DBG-s3b** (`docs/progress/DBG-s3b.md`, D72): until then the M3b content gate resigned a focused text field on every drag, fling, animated
  scroll and resize (`.disabled` / `allowsHitTesting(false)` on the content make UIKit resign it); while a text input is being edited the gate now uses a shield overlay and
  a gesture mask instead, and the focus survives all four as in a native `ScrollView` (`PanUITests.testDragKeepsFocusedTextField` and its siblings, native reference included).
- `scrollInputBehavior` (27 SDK, D3): ours gates each source — `.drag` → pan gesture disabled like `isScrollEnabled`; `.keyboard` → §5 handlers off;
  `.accessibility` → §5 actions removed; `.scrollIndicator` → accepted (thumb dragging is a gap anyway). Native kinds convert where the SDK declares
  them (`#if compiler(>=6.4)`), unknown kinds map to `.drag`. Names/minimum OS confirmed by compile test (open Q3).

## 5. Keyboard and accessibility (`Chrome/KeyboardScrolling.swift`, `Chrome/Accessibility.swift`)

```swift
public enum ZTronKeyboardScrollingMode: Sendable { case automatic /* focused 17+, disabled <17 */, focused, global, disabled }
enum KeyboardScrollMath { static let arrowStep: CGFloat = 40; static func page(_ V: CGFloat) -> CGFloat { max(0, V − 32) }
    static func target(from o: CGPoint, key: KeyEquivalent, modifiers: EventModifiers, metrics: ScrollMetrics, axes: Axis.Set) -> CGPoint /* clamped */ }
extension View { public func ztronScrollKeyboardScrolling(_ mode: ZTronKeyboardScrollingMode) -> some View }
```
17+: `.focusable()` + `.onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .pageUp, .pageDown, .home, .end], phases: [.down, .repeat])`
→ `state.setContentOffset(target, animated: true)` (M6). Arrows ±40 pt, space/pageDown +page, shift-space/pageUp −page, home/end to the clamped edges
of the primary axis; a horizontal-only view maps up/down to leading/trailing. Fallback 15–16 (`.global`): hidden `Button {}.keyboardShortcut(key, modifiers:)`
stack at 0×0 in the viewport overlay (shortcuts are app-wide, so `.automatic` keeps them off; opt in per view). Repeats are honored by
`.repeat` only on 17+ (gap <17). Accessibility: `accessibilityScrollAction { edge in … }` (15+) scrolls one page along `edge` and then
posts the page announcement; zoom: `accessibilityZoomAction { $0.direction == .zoomIn ? zoom(×2) : zoom(÷2) }` (16+), <16 `accessibilityAction(named: "Zoom in"/"Zoom out")`.
Announcements: `AccessibilityNotification.PageScrolled("Page i of n").post()` (17+); <17 the container element's `accessibilityValue` is "Page i of n"
(read on focus, not announced — gap). `n = ceil(E / V)`, `i = floor(o′ / V) + 1`; with paging (M6) use `pagingIndex`. Element: `.accessibilityElement(children: .contain)`
on the viewport, `.accessibilityAddTraits(.allowsDirectInteraction)` off by default. Mapping table (S6): `contentLayoutGuide` → `.ztronContent`
coordinate space, `frameLayoutGuide` → `.ztronViewport`; pan/pinch recognizers → `phase`, `isDragging`, `isZooming`; tvOS APIs out of scope.

## 6. Helpers (`Helpers/CounterScaled.swift`, `Helpers/StickyParallax.swift`, `Helpers/ZoomLOD.swift`)

```swift
extension View {
    public func ztronScrollCounterScaled(anchor: UnitPoint = .center) -> some View  /* shipped by M6b as (anchor:fileID:line:) */          // GeometryEffect scale 1/zoom, hot leaf, content body 0 runs
    public func ztronScrollSticky(edge: Edge = .top, inset: CGFloat = 0) -> some View         // t = max(0, visibleRect.min − frame.min + inset) along edge axis
    public func ztronScrollParallax(_ rate: CGFloat, axis: Axis = .vertical) -> some View      // t = (visibleRect.min − frame.min)·(1 − rate); rate 1 = normal, 0 = fixed
}
public struct ZTronZoomLODReader<Content: View>: View {                                       // level = max i with steps[i] ≤ zoom, hysteresis ±5 %
    public init(steps: [CGFloat], @ViewBuilder content: @escaping (_ level: Int, _ step: CGFloat) -> Content) }
```
Sticky/parallax read the item's frame in `.ztronContent` once (cold, `anchorPreference`/`GeometryReader` in the background, changes only on
layout) and the hot offset through `ChromeLeaf`, applying a `GeometryEffect` translation; the translated item is kept inside its container
(`t ≤ frame.max − visibleRect.min − length` for sticky, UIKit section-header style). Counter-scaled uses the live zoom from the `.zoom` channel
(including pinch and zoom bounce). LOD: the level is a cold channel derived from the hot zoom, so `content` re-evaluates only on level change;
hysteresis prevents flicker near a step. All three forward through `allowsHitTesting` unchanged.

## 7. Edge effects 26+, containers 27+, system integrations (`Chrome/EdgeEffects.swift`, `Containers/*.swift`, `Chrome/SystemHooks.swift`)

```swift
public enum ZTronScrollEdgeEffectStyle: Sendable, Equatable { case automatic, soft, hard }   // ⇄ ScrollEdgeEffectStyle 26+
extension ZTronScrollView { public func scrollEdgeEffectStyle(_ s: ZTronScrollEdgeEffectStyle?, for edges: Edge.Set) -> Self
                            public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> Self }
extension View { public func ztronSafeAreaBar<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                                       @ViewBuilder content: () -> V) -> some View
                 public func ztronBackgroundExtensionEffect() -> some View
                 public func ztronSwipeActions<V: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                                                        @ViewBuilder content: () -> V, onPresentationChanged: ((Bool) -> Void)? = nil) -> some View
                 public func ztronSwipeActionsContainer() -> some View
                 public func ztronReorderable() -> some View
                 public func ztronReorderContainer<ID: Hashable>(for ids: [ID], isEnabled: Bool = true, move: @escaping (IndexSet, Int) -> Void) -> some View }
public struct ZTronScrollChromeHooks { public var isAtTop: Bool; public var scrollDirection: ZTronScrollDirection; public var topOvershoot: CGFloat }
extension View { public func onZTronScrollChromeChange(_ action: @escaping (ZTronScrollChromeHooks) -> Void) -> some View }
```
- Edge effects: SwiftUI's native effect is private to its ScrollView, so we **always** emulate in the viewport overlay, per edge where the content
  scrolls under a bar (`adjustedContentInset.edge − contentInset.edge > 0`). `.soft`: `Rectangle().fill(.ultraThinMaterial)` covering the inset region
  + 24 pt, masked by a linear gradient (opaque → clear). `.hard`: `.bar` material over the inset region + hairline divider. Opacity `clamp(o′_edge / 16, 0, 1)`
  from a hot leaf (hidden at the rest edge, as iOS 26). `.automatic` ⇒ `.soft` on 26+, **none** below (the "plain fallback": the OS look of that era);
  explicit `.soft`/`.hard` emulate on every OS. `safeAreaBar` 26+ is strategy 1 (feeds `safeAreaInsets`); `ztronSafeAreaBar` applies native 26+, else
  `safeAreaInset(edge:alignment:spacing:)` (15+) with our edge effect behind it. `backgroundExtensionEffect` 26+ is applied natively inside the content
  (`ztron…` forwards; <26 identity — gap: no mirrored extension).
- Containers: the 27 `swipeActions`/`reorderable` generalizations are expected to need a native container (confirm by compile+device test, open Q4); ours work
  on every OS inside the view. Swipe: horizontal `DragGesture` on the row registered as a ScrollArbitration participant (API frozen; direction lock
  `|dx| > |dy|` claims the row, else the pan wins); reveal width = sum of action widths, full swipe at ≥ 0.6·row width; `ztronSwipeActionsContainer` keeps one
  row open (`ztronSwipeHost` env) and closes it when `phase` leaves `.idle`. Reorder: long-press 0.5 s lifts the row into the viewport overlay (hot offset),
  target index `= clamp(floor((lift.midY − rows[0].minY) / rowHeight), 0, n−1)`, `move` on drop; **edge auto-scroll is achievable**: the state clock drives
  `offset += maxV·((44 − d)/44)·dt` (`maxV` 600 pt/s) while the lifted row is within 44 pt of a viewport edge — no UIKit needed.
- System integrations: large-title collapse, `toolbarMinimizationBehavior`, `tabBarMinimizeBehavior` and status-bar tap-to-top all observe the UIKit scroll
  view and cannot be driven from pure SwiftUI (gaps, matrix rows). Hooks: `onZTronScrollChromeChange` (cold, 1 pt hysteresis on `isAtTop`, direction
  flips only) so apps can toggle `toolbarBackground(.visible, for: .navigationBar)` (16+) / `.toolbar(.hidden, for: .tabBar)` (16+);
  `ZTronScrollState.scrollsToTop` accepted (no effect) + `scrollToTop(animated:)` for the app's own trigger.

## 7b. Delegate callbacks as modifiers (`Observation/DelegateModifiers.swift`) — Amendment 2026-10-19 (user), SPEC S11

Every `UIScrollViewDelegate` method gets an `onZTronScroll…` modifier as an alternative to the delegate object (full table and signatures in SPEC S11
"Delegate callbacks as modifiers"): a member on `ZTronScrollView` → `Self` and a same-name `View` twin (env overlay `ztronScrollConfig.delegateBoxes`,
appended, reaching every ZTronScrollView below; the member wins when applied directly, M7 Q4's compile test covers the pair). Mechanism = M7's
`ObserverHub` grows one box list per event:
```swift
final class DelegateObserverBox { enum Kind { case didScroll, didZoom, willBeginDragging, willEndDragging, didEndDragging, willBeginDecelerating, didEndDecelerating,
    didEndScrollingAnimation, willBeginZooming, didEndZooming, shouldScrollToTop, didScrollToTop, didChangeAdjustedContentInset }
    let kind: Kind; var action: Any /* the typed closure for `kind`; re-assigned every body of the owning modifier (R7) */ }
extension ObserverHub { func addDelegate(_ box: DelegateObserverBox) -> Token; func remove(_ token: Token)
    func didScroll(_ s: ZTronScrollState); func didZoom(_ s: ZTronScrollState); func willBeginDragging(_ s: ZTronScrollState)
    func willEndDragging(_ s: ZTronScrollState, velocity: CGPoint, target: inout CGPoint); func didEndDragging(_ s: ZTronScrollState, willDecelerate: Bool)
    func willBeginDecelerating(_:); func didEndDecelerating(_:); func didEndScrollingAnimation(_:); func willBeginZooming(_:); func didEndZooming(_:, atScale: CGFloat)
    func shouldScrollToTop(_ s: ZTronScrollState) -> Bool /* conjunction; true when no box */; func didScrollToTop(_:); func didChangeAdjustedContentInset(_:) }
```
`ZTronScrollState` wraps each `delegate?.scrollViewX(self, …)` call (today 13 sites: `deliverPending` ×5, `notifyAdjustedInsetChange`, the three
`willBegin…` sites, `didEndDragging` ×2 incl. `Gesture/ReleasePipeline.swift`, `willEndDragging` in `ReleasePipeline`, scroll-to-top) in `notifyX(…)`:
delegate first, then `observers.X(…)` — one code path on both OS paths, cadence and order unchanged (S11). `willEndDragging` threads the `inout` target
delegate → boxes in registration order; `shouldScrollToTop` ANDs. Registration order = environment twins outermost first, then the member's closures in
application order (the container registers env boxes before config boxes, identity-diffed on change, removed on disappear). The boxes are cold: a callback
causes no view update (they run inside `deliverPending`, after the delegate and before the M7 geometry observers; S4). `viewForZooming` has no modifier
(zoom range). Not a native SwiftUI API → no `#available` branch and no native twin application. Velocity stays pt/ms (delegate parity; M7's context is pt/s).

## 8. Edge cases
Not scrollable on an axis → no thumb, flash no-op on that axis; zoom changes `E` → thumb resizes live, no content re-eval; both axes visible → shortened vertical
track; `.hidden` after a flash started → fade cancels; rotation mid-fade → geometry re-derived from the new `ScrollMetrics`, timer continues;
`contentMargins` + `state.contentInset` set directly → the later write wins (documented); `containerRelativeFrame` before the first viewport commit →
`ztronViewportFrame == nil` ⇒ identity for one frame, then frame; keyboard scroll while `isScrollEnabled == false` or `.keyboard` input disabled → ignored;
reorder drag reaching the content end → auto-scroll stops at the clamp; swipe row open + pinch → row closes first; `scrollDismissesKeyboard` with no focused
field → focus steal is harmless (no UI change); edge effect with `contentInsetAdjustmentBehavior == .never` → region height 0 ⇒ nothing drawn.

## 9. Builder tasks (O5: exemplar first, then a 3-item slice, then the rest; one owner per file; orchestrator commits — D5)
| Task | Files (Sources/ZTronScrollView/…) | Notes |
|---|---|---|
| M8-1 exemplar | `Chrome/ChromeConfig.swift`, `Chrome/ChromeLeaf.swift`, `Chrome/ScrollIndicators.swift`, `Chrome/NativeChromeBridges.swift` (indicator part), 2-line hook in `ScrollContainer.body` (overlay) | sets the pattern: member+twin+mirror+leaf+tests; reviewed before the slice starts |
| M8-2 | `Chrome/ContentMargins.swift`, `Chrome/ContainerRelativeFrame.swift`, `Chrome/ClipAndBackground.swift` | §3 |
| M8-3 | `Chrome/DismissKeyboard.swift`, `Chrome/ScrollInput.swift`, `Chrome/KeyboardScrolling.swift`, `Chrome/Accessibility.swift` | §4–5; D3 gating for ScrollInputKind |
| M8-4 | `Helpers/CounterScaled.swift`, `Helpers/StickyParallax.swift`, `Helpers/ZoomLOD.swift` | §6 |
| M8-5 | `Chrome/EdgeEffects.swift` (+ safeAreaBar/backgroundExtension twins) | §7 edge effects |
| M8-6 | `Containers/SwipeActions.swift`, `Containers/Reorder.swift` | §7 containers; ScrollArbitration participant only (no API change) |
| M8-7 | `Chrome/SystemHooks.swift`, `docs/parity-matrix.md` rows, Demo `ChromeScreen` + `ChromeUITests` | after M8-1…6 |
| M8-8 delegate modifiers (amendment 2026-10-19) | `Observation/DelegateModifiers.swift` (13 members + 13 twins), `State/ObserverHub.swift` (+ delegate boxes), `notifyX` wrappers in `State/ZTronScrollState.swift` + `Gesture/ReleasePipeline.swift`, Demo `EventLogScreen` rows, parity rows | §7b; **after M7 session 1** (`ObserverHub`); independent of M8-1…7 |

## 10. Tests (unit over `OSPath.allCases`; demo UI on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`)
`IndicatorMathTests`: fraction/length/min length/position at both edges, rubber-band shrink+pin, two-axis track shortening, insets, nil when not scrollable.
`IndicatorVisibilityTests`: resolution order (showsIndicators > member > ours env > native env > automatic), native⇄ours round trip (16+), fade timing
with the test clock (hideDelay, fade, flash hold, flash under `.hidden` no-op). `ContentMarginsTests`: placement split → `contentInset`/`indicatorInsets`,
replace-not-accumulate. `ContainerRelativeFrameTests`: all three overloads, count/span/spacing formula, zoom-independence, nil frame before commit.
`ClipTests`: `ViewportClip` rect with/without disabled. `OffsetAdjustmentTests`: `.disabled` keeps offset on content growth, `.automatic` = M5 rule.
`KeyboardScrollMathTests`: every key, modifiers, clamping, horizontal-only mapping. `AccessibilityTests`: page i/n formula, scroll action edges,
zoom action ×2/÷2 clamped to `ZoomLimits`. `DismissKeyboardTests`: mode resolution and conversions. `ScrollInputTests`: gating per kind, D3 compile-out path.
`DelegateModifierTests` (M8-8): a recording delegate + recording modifiers see identical sequences for drag → decelerate → idle, pinch → bounce, a programmatic
animation, scroll-to-top and an inset change; `willEndDragging` target threading (delegate, then two modifiers, the last value lands); `shouldScrollToTop`
conjunction; append semantics (two `onZTronScrollDidScroll` both fire); a twin above two nested views fires for both, the member for its own only; stale-closure
(R7); tier-0: content body 0 and the modifier owner's body 0 with all 13 attached during 120 frames; velocity equals the delegate's (pt/ms).
`HelpersTests`: counter-scale = 1/zoom, sticky clamp inside container, parallax translation for rate 0/0.5/1, LOD level + hysteresis. `EdgeEffectTests`:
region height per behavior, opacity ramp, `.automatic` per OS path. `SwipeReorderTests`: reveal width, full-swipe threshold, target index, auto-scroll
velocity ramp and clamp. Render counters (tier-0): content body runs 0 during scroll/zoom/flash/fade/edge-effect/auto-scroll in every test above.
Demo `ChromeScreen` (both OS, both paths): indicator flash button, margins toggles, clip toggle, keyboard focus, VoiceOver page announcements,
swipe/reorder list; UI tests assert thumb exists/absent, fades, and `move` indices. Parity-matrix rows (API → strategy → min OS → fallback → tests) for
every symbol in §2–§7 plus the documented gaps (thumb dragging, interactive keyboard dismissal, <17 focus resignation, <17 announcements, native
containerRelativeFrame outside ours <17, large-title/toolbar/tabBar/status-bar-tap).

## 11. Risks to check on device (in order)
1. `focusable` + `@FocusState` steal actually dismisses the keyboard on 17.5 and 27.0 (if not, `.immediately` becomes a gap on all OS).
2. `onKeyPress` on a focusable viewport receives arrows/space when a text field inside has focus (expected: no — document).
3. Indicator constants (36 pt min, 3 pt thickness, 0.4 s delay) vs a UIKit sibling in the MC spike app, side by side; 120 Hz fade smoothness as a leaf.
4. Materials in the edge-effect scrim over moving content at 120 Hz (GPU cost) — fallback to a gradient-only scrim if frames drop.
5. 27.0: native `swipeActions`/`reorderable` inside our view — inert, broken, or fighting our pan (D12 `.simultaneousGesture`).
6. ScrollArbitration direction lock for row swipes vs our horizontal pan when both axes scroll.
7. `scrollInputBehavior` / `ScrollInputKind` names and minimum OS compile under Xcode 26.x (D3 compile-out) and Xcode 27.

## Open questions
- Q1 Indicator look: adopt `.primary.opacity(0.35)` or sample UIKit's exact colors in the spike and mirror them?
- Q2 Native spelling/OS of the `ScrollContentOffsetAdjustmentBehavior` modifier (18+?) — compile test; ours ships regardless.
- Q3 `ScrollInputKind` member names and whether it is 26 or 27 SDK (task says 27 + D3; capability table agrees).
- Q4 Do 27's `swipeActions`/`reorderable` work at all outside a native container? Decides whether the `ztron…` twins forward native or always use ours.
- Q5 Keyboard default on <17: keep `.global` opt-in (app-wide shortcuts) or disable entirely?

## Orchestrator resolutions (2026-10-18)
- Q1 Start with the proposed constants (`.primary.opacity(0.35)`, 36 pt min, 0.4 s fade delay); the user calibrates
  side by side on device (Device feedback queue). No spike rerun.
- Q2/Q3 Resolve by compile tests against the Xcode 27 SDK swiftinterface during the task; gate per D3. Ours ships regardless.
- Q4 Decide empirically in the task: if iOS 27 `swipeActions`/`reorderable` work inside our content, twins forward
  native; otherwise use ours. Record the result in the parity matrix.
- Q5 Fallback keyboard scrolling on 15–16 is opt-in only (`.global` off by default) — an app-wide shortcut grabbing
  arrows/space would surprise apps.
- Risk accepted: if focus-steal can't dismiss the keyboard, `scrollDismissesKeyboard` is a documented gap.
- (2026-10-19, user amendment) M8-8 delegate modifiers added (§7b, SPEC S11): depends on M7 session 1 (`ObserverHub`), not on M8-1…7; build it in the
  M7 session 2 slot or right after M7 s1, whichever comes first; one parity row per modifier (13) + `viewForZooming` → "replaced by zoomRange".

## M8-1 addendum (2026-10-20, builder; the pattern the rest of the slice follows)
- **Resolution order, measured** (hosted native `ScrollView` on iOS 17.5 and 27.0, `NativeIndicatorFixtureTests`): `showsIndicators: false` is the view's
  own default, not a veto. Per axis: `member ?? twin ?? native environment (16.4+) ?? .automatic`; only when that is `.automatic` does `showsIndicators:
  false` turn it into `.hidden`. An explicit `.visible` (member, twin, a native modifier above) beats the flag; `.hidden` / `.never` hide. This supersedes
  the "showsIndicators > member" order of §2 and §10.
- **Config shape**: `ChromeConfig` holds `AxisPair<T>` (an optional per axis, so an explicit `.automatic` overrides an outer `.hidden`), optional flags
  (`flashOnAppear: Bool?`) and `AnyEquatable?` for the trigger (`scrollIndicatorsFlash(trigger:)` is only `Equatable`). Stored on the view as
  `ZTronScrollView.chrome` (member side) and `EnvironmentValues.ztronChromeConfig` (twin side); later tasks append fields.
- **Where the overlay sits**: `.overlay(ScrollIndicatorsOverlay(...))` goes right after the named viewport space and BEFORE `.ignoresSafeArea`: the
  viewport root's frame there is the viewport itself (ignored safe-area edges included), so chrome positions are viewport coordinates. After
  `.ignoresSafeArea` the frame is the safe-area-respecting one.
- **Cold host + hot leaf**: `ScrollIndicatorsHost` (cold: resolution, `IndicatorController`, flash lifecycle; re-evaluates on configuration changes only)
  renders a `ChromeLeaf` (hot: channels `.all` while something is drawn, `[]` otherwise). `ChromeLeaf` tracks the channels it declares and reads the
  others as untracked snapshots (a `ChromeSample` is always a consistent read; undeclared fields do not wake the leaf).
- **Activity**: `.interacting`, `.decelerating`, `.animating` with no resize open. `.tracking` (finger down, content not moving) shows nothing: UIKit shows the
  thumb when the content moves, and `.animating` is also the resize watch's phase, which is not scrolling.
- **Fade**: no frame clock. `IndicatorController` keeps `isShown`; it flips on at once and off through one `withAnimation(.linear(duration: fade))`,
  with one one-shot timer per deadline (`schedule` injectable like the refresh coordinator's). Hold = `hideDelay` after activity, `flashHold` after a flash;
  `.visible` axes ignore it.
- **State API**: `scrollIndicatorInsets` is `ScrollMetrics.indicatorInsets` (cold, metrics channel, so the leaf follows a change); the track inset =
  safe area the content adjusts for + `scrollIndicatorInsets` + the view's `contentMargins(for: .scrollIndicators)` (`ChromeConfig.indicatorInsets`, M8-2).
  `ZTronScrollState.indicatorController` (weak) is how `flashScrollIndicators()` reaches the fade.
- **Native availability, compile-confirmed against the iOS 27 SDK interface**: `scrollIndicators(_:axes:)` and the two environment keys are iOS 16.0,
  `ScrollIndicatorVisibility: Equatable` is 16.4 (so the environment is read from 16.4 and `init?(_ native:)` is 16.4), `scrollIndicatorsFlash` is 17.0.
