# M8b · Refresh facade and scaling header (design)

Scope: SPEC S9 (refresh), S10 (scaling header, **rewritten by the amendment of 2026-10-19 (user)**), S11 (`withScalingHeader`, state additions; the
delegate-modifier map of the same amendment is designed in M8-chrome §7b / task M8-8). Builds on M3-pan §2–5 (pan/release pipeline, rubber band,
`PanEnvironment.bounces`), M5-resize §2–3/§6 (`adjustedContentInset`, inset-change rule, `headerObscured`/`ResizeCommit.header`, unobscured centre),
M6-targets §1–4 (member/twin resolution, `effectiveTargetBehavior`, `ZTronScrollAnimation`, `setContentOffset`), M8-chrome §1–2 (`ChromeConfig`, `ChromeLeaf`,
`ChromeSample`, `IndicatorMath` conventions `o′ = o + aci.start`, `E = C·s + aci.start + aci.end`) and the shipped reader engine (M2 §8 / D10:
`ZTronScrollReader` + `ReaderProbe`, `discoverChannels`, `ChannelRelay`, the `TransformHost` placeholder pattern — `State/ZTronScrollReader.swift`,
`Render/ContentTransform.swift`). Names per CLAUDE.md. iOS 15 deployment.
Rule of the doc: refresh and header state are **cold** except one hot value each (`dragPosition`, the header's live height), both derived from the
offset inside viewport-overlay leaves. Content bodies **and the header builder** run 0 times for every pull, hold, reset, collapse, stretch and snap
(tier-0 counter), S4.

**Amendment 2026-10-19 (user), in one paragraph.** (1) The refresh API has a single source: S9's `refresher(…)` members / `ztronRefresher` twins /
`.refreshable`, plus `onZTronScrollReachEdge`; the header has no `pullToRefresh`, `pullToLoadMore` or `scrollViewDidReachBottom`. (2) The header is
installed with `ZTronScrollView.withScalingHeader(size:scalingBehavior:snap:fade:header:)` (returns `Self`), **precedes the content** (the first `R`
points of the viewport, also above a horizontal scroll view) and reacts to a pull past the top with `.preserve` (no consequence on the header) or
`.stretch` (grows from its bottom edge with the pull, top edge pinned; shrinks from the bottom on scroll-up until it vanishes; a sticky overlay inside
it gets the live height; optional fade). (3) Every `UIScrollViewDelegate` method is also an `onZTronScroll…` modifier (M8-chrome §7b). §1 below is the
2026-10-18 refresh design with the header routes removed; §2–§3 are new. The user's reference snippet (GeometryReader + named space + `.frame(height:)`
+ `.offset`) illustrates the behaviour only; neither its API nor its code is copied (§2.3 says why it cannot be, under S4).

## 1. Refresh engine (`Refresh/`)

### 1.1 Data flow
```
.refreshable (env \.refresh) ─┐
member refresher(…) / twin ztronRefresher(…) ┴─► RefreshResolver → [Edge: RefresherSpec]   (cold; explicit member ?? twin ?? .refreshable(.system) ?? none)
   (no header route — Amendment 2026-10-19 (user): the header has no refresh API)       │
PanCoordinator offset write / phase change ──► RefreshCoordinator.sample(ChromeSample-like input, ≤ 1/frame, after didScroll flush)
      └─► RefreshEngine (pure struct, one per edge).handle(.sample/.lift/.sequenceEnd/.done/.tick) → [Effect]
            setProgress → hot channel .refresh(edge) → indicator leaf only          trigger → action Task (once per pull) + haptic serial + announce
            setHold(H) → state.refreshHoldInset (cold inset, part of adjustedContentInset) → bounds/indicators/center move with it (M5 inset rule)
            clearHold(animated) → same, in a transaction with config.resetAnimation
```

### 1.2 Types and signatures
```swift
// Refresh/RefreshTypes.swift (public)
public struct ZTronRefreshState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case notRefreshing, pulling, refreshing }
    public var mode: Mode; public var modeAnimated: Mode   // modeAnimated is written inside withAnimation(config.resetAnimation / .default)
    public var dragPosition: CGFloat                       // 0…1, pull ÷ triggerDistance; stays 1 while .refreshing
    public var style: ZTronRefreshStyle; public var edge: Edge
}
public enum ZTronRefreshStyle: Equatable, Sendable { case system, `default` }
public enum ZTronRefreshTriggerMode: Equatable, Sendable { case whilePulling, onRelease }
public struct ZTronRefreshConfiguration: Equatable {                     // defaults are UIRefreshControl-calibrated placeholders (§4 R1)
    public var triggerDistance: CGFloat = 100; public var indicatorHeight: CGFloat = 60; public var holdOffset: CGFloat? = nil   // nil → indicatorHeight
    public var triggerMode: ZTronRefreshTriggerMode = .whilePulling; public var minimumVisibleTime: TimeInterval = 0.5
    public var resetAnimation: ZTronScrollAnimation? = .swiftUI(.easeOut(duration: 0.3))   // nil = unanimated
    public var allowedEdges: Edge.Set? = nil                                 // nil = start edge of the primary axis (.top; .leading for horizontal-only)
    public var loadMorePadding: CGFloat = 0                                  // extra end-edge content padding while a bottom/trailing refresh is active
    public var disablesWhenZoomed: Bool = true
    public static let `default` = Self(); public static let loadMore = Self(allowedEdges: [.bottom], loadMorePadding: 44)
}
// Refresh/RefreshEngine.swift (internal, pure, Equatable, no clock/SwiftUI)
struct RefreshEngine: Equatable {
    enum Phase: Equatable { case idle, pulling, armed /* .onRelease: crossed, waiting for lift */, triggered /* action running, hold deferred to lift */,
                            refreshing(since: TimeInterval), finishing(until: TimeInterval),
                            retracting(RetractLook, until: TimeInterval) /* USER-s6: the indicator goes back with the content */ }
    struct Input: Equatable { var pull: CGFloat /* §1.3, ≥ 0 */; var isTracking: Bool; var enabled: Bool /* !zoomed && isScrollEnabled && otherEdgeIdle */; var time: TimeInterval }
    enum Event: Equatable { case sample(Input), lift(Input), sequenceEnd, begin(programmatic: Bool), done(TimeInterval), tick(TimeInterval), cancel }
    enum Effect: Equatable { case progress(CGFloat), mode(ZTronRefreshState.Mode, animated: Bool), trigger, hold(CGFloat), clearHold(animated: Bool), announce(String), retract(RetractLook?) }
    var phase: Phase = .idle; var firedThisPull = false; let config: ZTronRefreshConfiguration; let edge: Edge
    mutating func handle(_ e: Event) -> [Effect]
}
// Refresh/RefreshCoordinator.swift (@MainActor final class, owned by ScrollContainer next to PanCoordinator)
@MainActor final class RefreshCoordinator { var specs: [Edge: RefresherSpec] /* != guarded */; private var engines: [Edge: RefreshEngine]
    private var task: Task<Void, Never>?; private(set) var states: [Edge: ZTronRefreshState]; var triggerSerial: Int /* sensoryFeedback trigger */
    func sample(offset: CGPoint, metrics: ScrollMetrics, isTracking: Bool, zoomAboveMin: Bool, now: TimeInterval)  // called by PanCoordinator flush + clock
    func begin(_ edge: Edge, runAction: Bool); func end(_ edge: Edge); func cancelAll()   // onDisappear → cancelAll (task.cancel, engines idle, hold cleared unanimated)
}
struct RefresherSpec { var style: ZTronRefreshStyle; var overlay: Bool; var config: ZTronRefreshConfiguration
    var action: @MainActor (Edge) async -> Void; var indicator: ((Binding<ZTronRefreshState>) -> AnyView)? }   // nil → built-in style
final class DoneToken: @unchecked Sendable { private let lock = NSLock(); private var fired = false
    func fire(_ resume: @escaping @MainActor () -> Void) /* idempotent; hops with Task { @MainActor in } */ }
// Refresh/RefreshAPI.swift — members (S8-2a) + twins (Modifiers/RefreshTwins.swift, env ztronRefreshSpecs overlay)
extension ZTronScrollView {
    public func refresher(style: ZTronRefreshStyle = .default, overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                          action: @escaping @MainActor () async -> Void) -> Self
    public func refresher(style: ZTronRefreshStyle = .default, overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                          action: @escaping (_ done: @escaping () -> Void) -> Void) -> Self        // wrapped: withCheckedContinuation + DoneToken
    public func refresher<V: View>(@ViewBuilder refreshView: @escaping (Binding<ZTronRefreshState>) -> V, overlay: Bool = false,
                                   configuration: ZTronRefreshConfiguration = .default, action: @escaping @MainActor () async -> Void) -> Self
    public func refresher<V: View>(@ViewBuilder refreshView:…, overlay:…, configuration:…, action: @escaping (_ done: @escaping () -> Void) -> Void) -> Self
    public func refresher(edges: Edge.Set, …, action: @escaping @MainActor (Edge) async -> Void) -> Self   // edge-aware form; others call it with the edge dropped
}
extension View { public func ztronRefresher(…same four…) -> some View
                 public func onZTronScrollReachEdge(_ edge: Edge, threshold: CGFloat = 0, perform: @escaping () -> Void) -> some View }
extension ZTronScrollState { public func beginRefreshing(edge: Edge = .top); public func endRefreshing(edge: Edge = .top)
                             var refreshHoldInset: EdgeInsets /* cold; adjustedContentInset = contentInset + safeArea(per behavior) + hold + header(§2) */ }
```
**Mandatory shapes (user, 2026-10-19):** `.refresher { await load() }` (trailing closure → the async overload, `.default` style = the built-in loader) and
`.refresher(refreshView: { MyLoader($0) }) { await load() }` (custom view + action) must compile exactly so; `{ done in … }` picks the completion overloads by
arity. The amendment removed only the header's own entry points. No UIKit, no introspection anywhere in this doc (S2; S10's mention is the reference's technique).
Precedence per edge: `refresher(…)` member ?? `ztronRefresher` twin ?? `\.refresh` env (style `.system`, top/start edge, `.default` config) ?? none. Documented:
"explicit wins over `.refreshable`". A later `refresher` call replaces the spec of the edges it names (dictionary merge, never accumulates).

### 1.3 Formulas and state machine (per edge; vertical shown, horizontal mirrors with x)
- `o′ = o + aci.top` where `aci` **excludes** this edge's own hold (bounds before hold); `pull_top = max(0, −o′)`, `pull_bottom = max(0, o′ − (E − V))`
  (displayed, rubber-banded overscroll, as UIRefreshControl reads `contentOffset`). `dragPosition = clamp(pull / triggerDistance, 0, 1)`.
- `enabled = !(disablesWhenZoomed && zoom > minZoom + 1e-4) && isScrollEnabled && noOtherEdgeRefreshing` (one refresh at a time, globally).
- Transitions: `idle →(sample, pull > 0, isTracking, enabled)→ pulling [mode .pulling, progress]`; `pulling →(progress ≥ 1 && !firedThisPull)→`
  `.whilePulling`: `triggered` + `trigger` (action starts, haptic, announce "Refreshing"); `.onRelease`: `armed`; `armed →(lift, progress ≥ 1)→ triggered + trigger`;
  `armed/pulling →(lift, progress < 1)→ idle [mode .notRefreshing animated]`. `triggered →(lift or already lifted)→ refreshing(since: now)` + `hold(H)`;
  `H = holdOffset ?? indicatorHeight (+ loadMorePadding on end edges)`, `overlay == true ⇒ H = 0` (content never pushed). `firedThisPull` resets at `sequenceEnd`
  **and** only once `mode == .notRefreshing`, so a second pull during a refresh never calls the action.
- **Hold is applied at lift, never mid-drag** (changing `bounds.min` under a finger would remap the rubber band → jump; M5 §5 rebase exists but is unnecessary).
  The release pipeline then sees `min_new = −(aci.top + H)`: an over-pulled release springs back exactly to the hold position; a release below H decays to it.
  `beginRefreshing()` with no finger applies the hold immediately and reveals it: `setContentOffset(min_new, animated: true)` if `o′ ≤ 0.5`, else only the mode changes
  (indicator spins off-screen, UIKit parity). It does **not** run the action (UIKit `beginRefreshing` sends no `valueChanged`); `endRefreshing()` ends either kind.
- `done`/action return → `finishing(until: max(now, since + minimumVisibleTime))`; `tick ≥ until && !isTracking` → `clearHold(animated: true)` + `mode .notRefreshing`
  (animated). The M5 inset rule (`o′ ≤ min_old + 0.5` → stay at the start edge) moves the content back to rest inside the transaction; if the user scrolled away,
  nothing moves. If tracking at that moment, the clear waits for `lift` and is then unanimated-if-overpulled / animated otherwise ("unless the user is tracking").
- **Retraction (USER-s6, D39).** `UIRefreshControl` keeps the spinner glued to the content edge until the gap closes; the engine used to go idle (progress 0,
  leaf removed) on the frame the content was still sliding back. Phase `.retracting(RetractLook, until:)` + effect `.retract(look?)` are entered where the
  engine would go idle with the content still pulled (> 0.5 pt): a lift below the trigger or a cancelled one (look `.pull`: ring / arrow with the falling
  progress), the end of a refresh at the lift or by `resetAnimation` (look `.spinner`: the built-in indicator keeps the spinner, a display-only override,
  `ZTronRefreshState` unchanged) and the early-return release of D35 (`.spinner`). Not entered when nothing follows the finger (`sequenceEnd`, a missed lift),
  when the edge is disabled, when the pull is already gone, for `resetAnimation: nil`, or for an overlay edge whose content never moved. In it `mode` is
  `.notRefreshing` (a custom view reads an idle edge) and `progress` follows the live pull (`pull ÷ trigger`) down to 0; it ends when the pull is ≤ 0.5 pt, at
  `until` (3 s, a safeguard) or when a new pull takes over (a normal pull; a lift on it may fire; `begin` is not swallowed). The end condition is NOT "settled
  and not tracking": the first flush after the lift runs before the release motion has started. The pull is the state's, except that a reset SwiftUI
  animates (`.swiftUI`, the default) JUMPS the state's offset to rest in the call while the content is drawn back over ~0.3 s with the clock idle (measured
  on 27.0: `presentation 0` at +0 ms, the content effect's probe 60 → 0 from +60…100 ms): so the retraction's effects are applied inside one
  `withAnimation(resetAnimation)`, the leaf draws through an animatable placement (`pull` = `animatableData`) that SwiftUI interpolates in that transaction,
  and while an edge retracts the coordinator feeds the engine `max(state pull, last drawn pull)` and samples it on a 30 Hz beat when the clock is idle.
  The overlay style keeps its formula (`center = −L/2 + min(pull, L)`): it slides out with the pull.
- Bounce: a spec on a vertical edge sets `PanEnvironment.bouncesY = true` (and `bouncesX` for horizontal edges) regardless of `BounceConfiguration.resolve` —
  axis-wide, as UIKit's refresh control turns on `alwaysBounceVertical` (documented; short content then bounces at both ends, like UIKit).
- Indicator placement (leaf, viewport points; `top0 = aci.top − hold + header_current(o′)` §2.4 — the live header height counts; under `.stretch` the indicator is centred over the stretched band, under `.preserve` it sits in the gap below the header): gap `g = max(0, −o′_withHold)`;
  `.system`: center `y = top0 − min(g, H)/2`, opacity/arrow angle from `dragPosition`, spinner while refreshing; `.default`: frame `[top0 − g, top0)` clipped to H, follows
  the pull 1:1; `overlay`: center `y = top0 − H/2 + (refreshing ? H : min(g, H))` floating over the content/header. Bottom/trailing mirror around `V − aci.bottom`.
  Custom `refreshView` is evaluated inside the same leaf with `Binding<ZTronRefreshState>`; writes of `.mode == .refreshing/.notRefreshing` map to begin/end, others ignored.
- `onZTronScrollReachEdge(edge, threshold)`: `d_top = o′`, `d_bottom = (E − V) − o′` (x likewise). Fires when `d ≤ threshold` becomes true, re-arms when
  `d > threshold + 1` (1 pt hysteresis) — including after content growth (load-more append). Evaluated at the didScroll flush (≤ 1/frame), from the coordinator, not a view body.
  (Amendment 2026-10-19 (user): there is no header-specific `scrollViewDidReachBottom`; `onZTronScrollReachEdge(.bottom)` is the only spelling.)
- Haptic: `.sensoryFeedback(.impact(weight: .light), trigger: triggerSerial)` on the indicator leaf (17+). iOS 15–16: no haptic (UIKit not allowed) — doc + matrix gap.
- Accessibility: viewport gets `accessibilityAction(named: "Refresh") { begin(.top/.leading, runAction: true) }` / `"Load more"` for end edges when a spec exists;
  announcements via `AccessibilityNotification.Announcement("Refreshing" / "Refresh complete")` 17+; <17 the indicator's `accessibilityValue` carries the state (gap, as M8 §5).
- Parity: `didScroll` keeps firing during the pull (pan path); hold/clear transactions go through the M2 token → `.animating` → `.idle`; no extra delegate calls.

### 1.4 Edge cases
`.refreshable` on a non-scrolling axis → start edge of the primary axis. Top refresh + bottom load-more on one view → two engines, the global `enabled` keeps one running.
Content shorter than viewport → `E − V ≤ 0`, bounds collapse, both pulls still measure from `o′` (bounce forced). Zoom above min while pulling → `enabled` false → progress 0,
`pulling → idle`; back at min → next sample re-enters. Spec removed while refreshing (view re-rendered without a refresher) → `cancelAll()` + unanimated clear. `done` twice,
`endRefreshing` without begin, `beginRefreshing` while running → no-ops. `done` never called → never ends (UIKit parity; continuation stays suspended; documented). Disappear
during `finishing` → task cancelled, hold cleared unanimated, no reset animation. Rotation while holding → hold is part of `adjustedContentInset`, M5 center rule applies.
`isScrollEnabled == false` → no pan → no pull; `beginRefreshing` still works. Horizontal-only view → `.leading/.trailing`; both axes → the `allowedEdges` chosen apply per axis.

## 2. Scaling header (`ScalingHeader/`) — amended design

### 2.1 Types and signatures (public shapes are SPEC S10's; repeated here only where the implementation hangs on them)
```swift
extension ZTronScrollView { public func withScalingHeader<Header: View>(size: ZTronHeaderSize, scalingBehavior: ZTronHeaderScalingBehavior = .preserve,
    snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil, @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self }
// Returns Self: the builder is stored type-erased, `HeaderSpec.builder: (ZTronHeaderProxy) -> AnyView`. S4.2 forbids AnyView around *content*; here the
// erased type is fixed at the call site, so the header's identity and @State survive every update (test 11). It buys every other member in any order,
// no forwarding file and no second container type (2026-10-18 Q5 is void). No `ztron…` twin: there is no native counterpart and a header is per view.
public struct ZTronHeaderProxy: Equatable { unowned let state: ZTronScrollState /* internal */; public static func == (a: Self, b: Self) -> Bool { a.state === b.state } }
public struct ZTronHeaderGeometryReader<Value: Equatable, Content: View>: View {    // body = ZTronScrollReader(header?.state, of: { $0.header.map(transform) }) { $0.map(content) }
    public init(_ header: ZTronHeaderProxy? = nil, of transform: @escaping (ZTronHeaderGeometry) -> Value, @ViewBuilder content: @escaping (Value) -> Content)
    public init(_ header: ZTronHeaderProxy? = nil, @ViewBuilder content: @escaping (ZTronHeaderGeometry) -> Content) where Value == ZTronHeaderGeometry }
extension ZTronHeaderGeometry { public static func quantizedProgress(steps: Int) -> (ZTronHeaderGeometry) -> Int { { Int(($0.progress * CGFloat(steps)).rounded()) } } }
extension ZTronScrollGeometry { public var header: ZTronHeaderGeometry? }   // metrics.header.map { HeaderMath.geometry(o′: contentOffset.y + metrics.headerInsetTop, m: $0) } — reads offset + metrics only
extension ZTronScrollState { public var headerGeometry: ZTronHeaderGeometry? { geometry.header }     // tracked on 17+ like contentOffset: leaves only
                             public func snapHeader(to target: ZTronHeaderSnapTarget, animated: Bool = true)
                             func setHeaderMetrics(_ m: HeaderMetrics?)    // discrete inset change via M5 §6; applies a pending snapHeader(to:)
                             func headerHeight(at o′: CGFloat) -> CGFloat  // = geometry(o′).height; indicators, scrollTo, refresh top0, ResizeCommit.header }
// internal
struct HeaderSpec { var size: ZTronHeaderSize; var behavior: ZTronHeaderScalingBehavior; var snap: ZTronHeaderSnap; var fade: ZTronHeaderFade?
    var builder: (ZTronHeaderProxy) -> AnyView }                           // in ScrollViewConfig.header (M6 §1 member slot); `==` on the value fields only
struct HeaderMetrics: Equatable, Sendable { var min: CGFloat; var resting: CGFloat; var behavior: ZTronHeaderScalingBehavior; var width: CGFloat
    var band: CGFloat { max(0, resting - min) } }                          // ScrollMetrics.header: HeaderMetrics? (cold); aci.top includes `resting`
enum HeaderMath {   // pure, unit-tested, no SwiftUI
    static func resolve(size: ZTronHeaderSize, width: CGFloat, natural: CGFloat?) -> (HeaderMetrics?, warning: String?)   // nil while .fit is unmeasured
    static func geometry(o′: CGFloat, m: HeaderMetrics) -> ZTronHeaderGeometry                                            // §2.4 table
    static func contentGap(o′: CGFloat, m: HeaderMetrics) -> CGFloat            // .preserve: max(0, −o′); .stretch: 0 — refresh placement
    static func snapOffset(progress p: CGFloat, m: HeaderMetrics) -> CGFloat { m.band * clamp(p, 0, 1) }   // ONE convention: 0 expanded, 1 collapsed
    static func nearestSnap(to o′: CGFloat, positions: [CGFloat], m: HeaderMetrics) -> CGFloat?           // nil outside (0, band) or band == 0
    static func offset(for t: ZTronHeaderSnapTarget, m: HeaderMetrics) -> CGFloat   // .expanded 0 · .collapsed band · .progress p → band·p · .height h → resting − clamp(h, min, resting)
}
struct HeaderHost: View { let spec: HeaderSpec; let state: ZTronScrollState; let safeTop: CGFloat }   // cold body (§2.2)
struct HeaderFrameModifier: ViewModifier { let state: ZTronScrollState; @StateObject private var relay = ChannelRelay() }   // hot leaf (§2.3)
struct HeaderMeasure: ViewModifier { /* .fit only: HeaderLayout on 16+, measuring pass on 15 (§2.6) */ }
struct HeaderSnapBehavior: ZTronScrollTargetBehavior { /* composed after the user's behavior in effectiveTargetBehavior (Q3 2026-10-18) */ }
```

### 2.2 Data flow
```
withScalingHeader(…) ──► ScrollViewConfig.header = HeaderSpec (cold, on the view value; a later call replaces it)
ScrollContainer.body (cold):  config.header? → .overlay(alignment: .top) { HeaderHost(spec, state, safeTop) }  above content + refresh leaves, below the
                              indicators, inside the viewport clip, .accessibilitySortPriority(1) (announced before the content: "precedes")
                              state.setHeaderMetrics(HeaderMath.resolve(spec.size, W, natural))   (!=-guarded → aci.top += resting: M5 §6 discrete inset change)
HeaderHost.body (cold; runs on install, spec change, width / Dynamic Type / natural-height change):
      spec.builder(ZTronHeaderProxy(state))                  ← the ONLY place the user's builder runs
          .modifier(HeaderFrameModifier(state))              ← hot leaf; the built header is its `content` placeholder
          .overlay(FadeOverlay(spec.fade))                   ← cold; framed by layout, no hot read
          .modifier(HeaderMeasure(spec.size))                ← .fit only
          .padding(.top, safeTop)
HeaderFrameModifier.body (hot leaf, D10 pattern): relay.subscribe([.target, .metrics]) → h = HeaderMath.geometry(o′_target, metrics.header).height
      content.frame(width: W, height: h, alignment: .top).clipped().allowsHitTesting(h > 0.5).accessibilityHidden(h <= 0.5)
Readers inside the header: ZTronHeaderGeometryReader → ZTronScrollReader → ReaderProbe(transform reads geometry.header) → channels {.offset, .metrics} (15–16) / tracked (17+)
Release → M6 pipeline: user behavior → HeaderSnapBehavior (.immediately) → willEndDragging (delegate + modifiers).  Settle → .afterFinishAccelerating / pending snapHeader(to:)
```
Reserved inset: `aci.top = safe.top (per `contentInsetAdjustmentBehavior`) + header.resting + contentInset.top (+ refresh hold)`. It changes only in
`setHeaderMetrics` (install/removal, `.aspectRatio`/`.fit` on width change, `.fit` re-measure, `size` change): a discrete inset change through M5 §6,
never per frame. Content size and proposal are untouched by collapse and stretch. On a horizontal view the content's height proposal is
`V − aci.top − aci.bottom`, so the content lays out *below* the header (stacked), and the header is full viewport width on every axis configuration.

### 2.3 The live geometry without content re-evaluation (the render-time constraint)
The user's reference does three things per frame **on a content item**: a `GeometryReader` body re-runs (minY in a named space), `.frame(height:)`
re-lays out the whole stack and `.offset` moves it — the content's bodies and layout change while scrolling, the opposite of S4.1, which is why its
code cannot be ported. Ours:
- **Offset → height is a leaf computation.** `HeaderFrameModifier` is the `TransformHost` pattern (`Render/ContentTransform.swift`, D10): its *own* body
  reads the hot value and applies `.frame(height:)` to its `content` placeholder. SwiftUI does not re-evaluate the placeholder's body (the user's
  header) when a modifier's body re-runs; it re-lays it out at the new proposal — a layout pass over the header subtree only. Counter proof:
  `header.builder` 0, `header.frame` = frames, `content.body` 0.
- **Which offset.** The frame leaf wakes on the **`.target`** channel (presentation writes never wake it, D10) and `frame(height:)` is animatable, so a
  transaction-driven move (`withAnimation { scrollTo }`, rotation, an inset change) runs the leaf once inside the transaction and SwiftUI interpolates
  the header's height in lockstep with the content's `GeometryEffect`: no one-frame lag, no per-frame body. Finger tracking and the clock write
  target = presentation every frame unanimated, so the leaf then runs per frame, as the transform host does. Readers (`ZTronHeaderGeometryReader`,
  `state.headerGeometry`, `geometry.header`) use the **presentation** offset: they report what is on screen, frame by frame (S1), the semantics of
  `contentOffset`; under a SwiftUI transaction they follow the M2 probe (≤ 1 frame behind the interpolated frame, invisible; identical to indicators).
- **`o′` for the header** = `o.y + aci.top − refreshHold.top` (the hold excluded, as in §1.3): a hold is seen as `o′ = −H`.
- **The content is untouched.** Collapse and stretch change neither `contentSize`, nor the content's proposal, nor `aci` (the resting height is
  reserved once). The content moves only through the transform; `.preserve`'s gap is simply the content's rubber-banded position below a header
  that did not move.
- **No `GeometryReader`, no preference, no Binding per frame** anywhere on the hot path (S4.6: the removed `collapseProgress(Binding)` would have
  re-run its owner every frame).

### 2.4 Formulas (`top0 = safe.top`, `W` viewport width, `R` resting, `band = max(0, R − min)`, `c = clamp(o′, 0, band)`, `g = max(0, −o′)`)
| | `.preserve` | `.stretch` |
|---|---|---|
| `height h` | `R − c` | `R − c + g` |
| frame / proposal | `(0, top0, W, h)` / `(W, h)`, clipped, top pinned | same |
| content top (viewport y) | `aci.top − o′ (+ H under a hold) = top0 + R + ci.top + g (+ H)`: a gap `g` opens below the header | same content position; the header's bottom `top0 + h` meets it (gap 0) |
| `progress` / `stretch` | `band > 0 ? c / band : 0` / `0` | same / `g` |
| hit-test & accessibility | hidden when `h ≤ 0.5` | same |
- **Overflow feel:** `g` is the pan's already rubber-banded overscroll (M3 band `c 0.55, d viewport`; D24 under a pinch), so the stretch resists like
  the content does and springs back with it on release; no second band. A `scaledToFill` child zooms because the proposal grows; a `Color` extends.
- **Sticky overlay:** the proposal *is* the live height, so `.overlay(alignment: .bottom…)` children follow the bottom edge in both directions and read
  `height` through the reader to resize themselves (title font = f(h)). Fade: `LinearGradient(colors: [.clear, color], startPoint: UnitPoint(x: 0.5,
  y: start), endPoint: .bottom)` overlaid on the framed header, below the refresh indicator — follows the frame by layout, no hot read.
- **Sizes:** `.fixed(min:max:)` → `R = max`; `.aspectRatio(r, min:)` → `R = W / r`, recomputed on width change; `.fit(min:)` → `R = natural` (§2.6).
  `min ≥ R` → `R := min`, band 0, progress 0, snapping off, `.stretch` still grows; DEBUG warning only for `.fixed` given with `min > max`. `R < 1`
  (`.fit` of a flexible-only header) → DEBUG warning naming `.fixed` / `.aspectRatio` / `.frame(idealHeight:)`.
- **Horizontal view:** no vertical travel → `o′ ≡ 0` → `h = R`, progress 0, stretch 0: a fixed banner stacked above; `.stretch` inert (DEBUG note). Both
  axes, or D15 vertical panning of zoomed content → driven by `o.y` as on a vertical view.
- **Refresh with the header (S9's API only):** hold `H` → `o′ = −H` at rest: `.stretch` → header `R + H`, indicator centred in the stretched band
  (overlay placement regardless of `overlay:` — there is no gap); `.preserve` → gap `H` between header bottom and content top, indicator in it. §1.3's
  `top0_refresh = aci.top − hold + header_current(o′)` with `header_current = h`. Bottom load-more unaffected.
- **Snapping (band > 0):** positions as collapse progress. `.immediately` = `HeaderSnapBehavior` composed **after** the user's behavior (Q3): if that
  target has `o′ ∈ (0, band)` → `target.y = nearestSnap`; velocity-aware because it works on the projected rest; `willEndDragging` (delegate and
  modifiers) sees the final target. `.afterFinishAccelerating`: at settle after user motion with `o′ ∈ (0, band)` and `|o′ − nearest| > 0.5` →
  `setContentOffset(nearest, animated: true)` (`.uikit` clock path, no new gesture). `snapHeader(to:animated:)` → `setContentOffset(HeaderMath.offset(for:),
  animated:)`; before metrics exist it is queued and applied unanimated by the first `setHeaderMetrics` (replaces `initialSnapPosition`).
- **Inset consumers (kept):** `headerHeight(at: o′)` feeds indicator insets (`indInset.start += h`), M9 pinned headers (`metrics.headerObscured`),
  `scrollTo` (`I.start += h(at target)`, M6 §4), refresh `top0`, and `ResizeCommit.header = h(o′_presentation)` at capture (M5 §3 `c(V, I, h)`); the
  centre is preserved with the header captured, and `.aspectRatio`'s new `R` after a rotation enters as the discrete inset change of the same commit.
  Rotation keeps `progress` (S7): the commit re-realises `o′ = progress · band_new` through the M5 intent, not through a second write.

### 2.5 The reactive-geometry pattern: decision and alternatives
Goal (user): keep `{ headerGeo in … }`; only the header's affected children update; the content never. **Decision: proxy + reader.** `ZTronHeaderProxy`
exposes nothing hot; `ZTronHeaderGeometryReader(header, of:)` is the S4 derived-reader tier over `ZTronScrollGeometry.header`, built on
`ZTronScrollReader`/`ReaderProbe` (tracked reads on 17+; `discoverChannels` → `{.offset, .metrics}` + `ChannelRelay` on 15–16). Considered:
| Pattern | Verdict |
|---|---|
| A. `ObservableObject` handed to the builder, children `@ObservedObject` (user's sketch) | Works on 15+, but `objectWillChange` is object-wide: every observing child re-renders every frame whatever it reads, so a quantized / "past 50 %" child can never be cheaper than per frame — the user's own goal fails for derived values. And the object in the builder's hand invites `headerGeo.height` in the builder body = the host re-runs the whole header per frame. Anti-pattern for this goal. |
| B. `@Observable` (17+) with A as the 15–16 fallback | Per-property tracking buys nothing: `height`, `progress`, `stretch` change together every frame; two object types for one feature; A's builder-scope hazard remains. |
| C. `@Environment(\.ztronHeaderGeometry)` written per frame | Environment writes per frame invalidate every reader of the key through the header subtree; a read in the builder body re-runs the header per frame. |
| D. `collapseProgress(Binding)` (reference) | Mirrors a hot value into the owner's state → owner body + content every frame (S4.6). Removed. |
| E. A `DynamicProperty` wrapper (`@ZTronHeaderGeometryObserved(header, of:)`) over the same engine | Closest to "installs via its initializer", but on 17+ a derived (Equatable-gated) update needs `withObservationTracking`, whose `onChange` fires at willSet (new value not stored yet) → re-derive one hop later = one frame of latency on the title; a tracked owner body instead gives no derived gating. The reader view reads after the update in the same pass. Not now; possible later sugar if measurements ask for it. |
| F. Builder receives `ZTronHeaderGeometry` per frame (Exyte, reference, the previous design's second init) | The whole header body per frame. Removed. |
| **G. Proxy + reader (chosen)** | One engine, already counter-tested on both OS paths; zero latency; derived gating; the type system forbids hot reads outside a leaf; the user's shape kept (`BannerTitle(header)` takes the proxy in its init and reads inside its reader). |
The proxy carries no cold facts either (resting height, width): a builder-body read of a cold fact would be legal but blurs the rule; the reader
delivers them inside `ZTronHeaderGeometry`, where a transform like `\.restingHeight` re-renders only on discrete changes.

### 2.6 iOS 15 fallback (same API; same behaviour except where stated)
- Leaf wake-ups: `ChannelRelay` on `.target`/`.metrics` for the frame leaf, `.offset`/`.metrics` for readers. `discoverChannels` needs no table: the
  computed `geometry.header` reads the presentation offset and the metrics through the recording storage, so both channels are recorded.
- `frame(height:)` animation under a transaction, `clipped`, `LinearGradient`, `accessibilitySortPriority`, `accessibilityHidden`: iOS 13–14 API.
- `.fit` measurement without `Layout`: `HeaderMeasure` runs a *measuring pass* — the header laid out with `fixedSize(horizontal: false, vertical: true)`
  inside the live frame (cropped, so nothing visible changes) with a size reporter (`GeometryReader` background → preference) — at the first layout and
  on width / `\.dynamicTypeSize` change; the result is cached as `natural` and resolved through `setHeaderMetrics`. Gap: header *content* changes are
  not re-measured on 15 (16+ sees them through `HeaderLayout.sizeThatFits` every pass). Matrix row; `.fixed` / `.aspectRatio` have no gap.
- No haptics (S9). `snapHeader` animations use the `.uikit` clock path on every OS.

### 2.7 Edge cases
`size` change at runtime → new metrics, discrete inset change, `progress` kept. Header taller than the viewport → band may exceed the scrollable range;
collapse limited by bounds (DEBUG note). Rotation mid-collapse → `.aspectRatio`/`.fit` recompute `R` → one inset change inside the resize commit, M5 centre
rule with the header captured; on 15 the `.fit` measuring pass happens in the same turn (cropped frame, invisible). Content shorter than the viewport →
with `.automatic` bounce no overflow is possible → `.stretch` never shows (DEBUG note; set `.always`); a refresher forces bounce and then both work. Zoom
enabled → the header ignores zoom; refresh disabled above min (S9); D15 vertical panning of zoomed content on a horizontal view collapses the header
(documented). Two header-equipped views nested → each host reads its own container's state (the host is inside its own container's overlay; the proxy
pins the state explicitly anyway). Parent rebuild with a new builder closure → the host re-runs the builder once (cold), the header's `@State` survives
(AnyView over a fixed type). `withScalingHeader` applied twice → the later call replaces the spec. Header removed → inset shrinks by `R` through M5 §6,
pending snap dropped. `snapHeader(to: .height(h))` outside `[min, R]` → clamped. `.immediately` snap with a user vertical paging behavior → composed after
it (Q3): if paging lands inside the band (band shorter than a page) the snap wins, otherwise untouched.

## 3. Builder sessions, tests, parity, device risks (amended 2026-10-19)

| Session | Files (Sources/ZTronScrollView/…) | Depends on |
|---|---|---|
| M8b-1 refresh engine | `Refresh/{RefreshTypes,RefreshEngine,RefreshCoordinator,ReachEdgeWatcher}.swift`; `State/ZTronScrollState.swift` (+ `ScrollStateTypes.swift`): `refreshHoldInset` in `adjustedContentInset`, `beginRefreshing/endRefreshing`, reach-edge list; `Gesture/PanCoordinator.swift` bounce force + sample call; tests `RefreshEngineTests`, `ReachEdgeTests`, `RefreshHoldTests` | M5 (a), M6 s1 committed (shared state file) |
| M8b-2 refresher API, styles, demo | `Refresh/{RefreshAPI,RefreshResolver,RefreshIndicators,RefreshAccessibility}.swift`, `Modifiers/RefreshTwins.swift`, `.refresh` env bridge, container overlay hook, `docs/parity-matrix.md` rows; Demo `RefreshScreen` gallery (system / default / overlay / custom / load-more / horizontal / `.refreshable`) + `RefreshUITests` | M8b-1, M8-1 (`ChromeLeaf`) |
| M8b-3 scaling header | `ScalingHeader/{HeaderTypes,HeaderMath,HeaderSpec,HeaderHost,HeaderFrameModifier,HeaderMeasure,HeaderSnap,ZTronHeaderGeometryReader,ScalingHeaderAPI}.swift`; `State/ZTronScrollGeometry.swift` (`header`), `ScrollMetrics.header` + `setHeaderMetrics` / `headerHeight(at:)` / `snapHeader(to:)` / `headerGeometry` (state, ≤ 15 lines); M6 pipeline compose hook (`effectiveTargetBehavior` suffix); indicator / `scrollTo` / M5-capture consumers (2 lines each); DEBUG counters `header.builder`, `header.frame`, `header.measure`; Demo `ProfileScreen` (`.fixed(min: 64, max: 240)`, `.preserve`, `snap: .immediately`, `.refresher(style: .system)`, avatar scaling and title fade through the reader) and `BannerScreen` (`.aspectRatio(16/9)`, `.stretch`, `fade`, title font from `height`, `.refresher(overlay: true)`, horizontal-axis toggle, `-ZTronHeaderSize fixed|aspect|fit` launch arg) + `HeaderUITests` | M8b-1/2, M6 s1–2, M8-1 |
No `MemberForwarding.swift` and no `ZTronScalingHeaderScrollView`: `withScalingHeader` returns `Self`. The header's refresh is M8b-2's `refresher`, nothing else.
The delegate modifiers are M8-chrome task M8-8 (on M7's hub), not an M8b session.

Tests (unit over `OSPath.allCases` with the test clock; demo UI on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`; `content.body` 0 in all):
1. Engine: `dragPosition` = pull/trigger clamped; `.whilePulling` fires at crossing with the finger down, exactly once per pull, not again while refreshing; `.onRelease` fires only at lift ≥ 1,
   disarms below; hold applied at lift (never mid-drag); min visible time; reset waits for lift while tracking; `done` idempotent from a background thread; disappear cancels the Task and clears unanimated.
2. Precedence: member > twin > `.refreshable(.system)`; later `refresher` replaces per edge; bottom spec adds `loadMorePadding`; horizontal → leading/trailing; disabled above min zoom and when scroll disabled;
   compile-shape (user, 2026-10-19): `.refresher { await load() }` → async overload with `.default` style, `.refresher { done in … }` → completion overload, `.refresher(refreshView: { MyLoader($0) }) { … }` → custom-view overload.
3. Hold geometry: `adjustedContentInset` includes the hold; release over-pull springs to `−(aci.top + H)`; clear → M5 inset rule returns to rest only if at the start edge; `beginRefreshing` reveals, runs no action.
4. Reach edge: once per arrival, re-arm after +1 pt, re-fires after content growth. 5. Indicator placement for all 3 styles × 4 edges, with and without a header (`.preserve` gap / `.stretch` band).
6. `HeaderMath` table: `o′ ∈ {−80, −20, 0, 20, band/2, band, band + 50}` × `.preserve`/`.stretch` → `h`, `progress`, `stretch`, frame, content top, gap; top edge always `top0`; `h ≥ 0` always;
   `min = 0` vanishes at `o′ ≥ band`; `.fixed`/`.aspectRatio`/`.fit` resolution (`.aspectRatio(16/9)` at `W = 402` → `226.125`); `min ≥ R` → fixed, band 0, `.stretch` still grows; warnings.
7. **Render-counter proofs (tier-0, the acceptance of §2.3):** a header with (a) a static image, (b) a child without a reader holding `@State`, (c) a per-frame reader, (d) `of: \.height.rounded()`,
   (e) `quantizedProgress(steps: 10)`, (f) `of: \.restingHeight`; drive 120 frames of collapse then 60 of stretch (clock + synthetic finger), then `withAnimation { scrollTo }`, then a rotation:
   `content.body == 0`, `header.builder == 0` during motion (== 1 per cold change: install, rotation under `.aspectRatio`), `header.frame == drawn frames` during finger/clock motion and `== 1`
   per transaction, (b) body == 0, (c) == frames with a distinct geometry, (d) == distinct rounded heights, (e) ≤ 11 per full collapse, (f) == 1 + rotations; both OS paths, preferred and forced.
8. Snapping through the M6 pipeline (`willEndDragging` delegate **and** modifier see the snapped target; composed after a paging behavior); `.afterFinishAccelerating` after settle; `snapHeader(to:)`
   clamps `.height`/`.progress`, queues before metrics, consumed once; positions in collapse-progress convention (`[1, 0.5, 0]` of the migration row ≡ `[0, 0.5, 1]`).
9. Natural height (`.fit`): `HeaderLayout` query (16+) and the 15 measuring pass give the same `resting` for an image with `.aspectRatio(16/9, contentMode: .fit)` (== `.aspectRatio(16/9)`);
   `header.measure` ≤ 1 per width/Dynamic Type change, 0 per frame; width change → exactly one `metrics` publish (discrete inset change) and the M5 centre preserved with `header` captured.
10. Inset consumers: `headerHeight(at:)` in indicator insets, `scrollTo` anchor at the target height, `ResizeCommit.header` (M5 §10.1 with header re-run), refresh `top0`; M9's `headerObscured` equals it.
11. Identity: the header's `@State` (a counter button) survives a full collapse, a stretch, a parent rebuild with a new builder closure and a `size` change; the new closure is the one that runs (R7).
12. Horizontal: `axes == .horizontal` → `h == R` for every horizontal offset and any `o.y`; `[.horizontal, .vertical]` → driven by `o.y`; a D15 zoomed vertical pan on a horizontal view collapses it.
13. Refresh + header: `.stretch` + hold → `h == R + H`, indicator centred over the band; `.preserve` → gap `H`, indicator in the gap; `.refreshable` on a header-equipped view resolves to the top edge;
    no header refresh symbols exist (compile-time: a `#if canImport` smoke that `pullToRefresh` does not resolve on `ZTronScrollView`).
14. Accessibility: header announced before the first content element (sort priority), hidden at `h ≤ 0.5`, buttons in the header hit-testable at every `h > 0.5`.
15. Delegate modifiers: M8-chrome §10 `DelegateModifierTests` (M8-8).
Demo UI: pull → spinner → `done` → rest, counters `refresh.actions == 1` per pull, `content.body == 0`; VoiceOver "Refresh" action; Profile: collapse + snap + system refresher under `.preserve`
(spinner in the gap); Banner: stretch with the title font growing, fade, overlay refresher over the stretched band, horizontal toggle keeps the banner fixed; `header.builder == 0` and
`content.body == 0` across the whole run (both OS, both paths).
Parity rows (API | strategy | min OS | fallback | test): `.refreshable`/`RefreshAction` | 1 (env) | 15 | — | 2; `refresher(…)` ×4 + edge form | 2a+2b | 15 | — | 1–3; `ZTronRefreshState/Configuration/Style/TriggerMode` | 4 (reference mirror) | 15;
`onZTronScrollReachEdge` | 2b | 15 | — | 4; `UIRefreshControl.begin/endRefreshing` | state | 15 | — | 3; haptic | 1 | 17 | none <17 (gap); announcements | 17 | `accessibilityValue` <17 (gap);
`withScalingHeader` + `ZTronHeaderSize/ScalingBehavior/Snap/Fade/Geometry/Proxy/GeometryReader/SnapTarget`, `snapHeader(to:)`, `headerGeometry`, `geometry.header` | ours (no native) | 15 |
`.fit`: Layout 16+, measuring pass 15 (content changes not re-measured on 15: gap) | 6–14; ScalingHeaderScrollView port | migration table (S10) | — | removed modifiers listed | 6, 8, 13;
header `.immediately` with a user vertical behavior | composed after it.

Device risks (in order): R1 calibrate `triggerDistance`, `indicatorHeight`, spinner look and the `.whilePulling` haptic moment side by side with `UIRefreshControl` in the MC spike app.
R2 hold-at-lift: any visible hitch when bounds change at lift at 120 Hz (if so, use the M5 `resizeGeneration` rebase and apply mid-drag). R3 spring-back to `−H` feel vs UIKit's.
R4 the per-frame `frame(height:)` re-layout of a real header (image + overlay + 2 texts) at 120 Hz on an iPhone 11-class device: cost of the layout pass (expected ≪ 1 ms; if not, the
fallback is a clip-only collapse for the header's *background* slot — a design change, not a tuning). R5 `frame(height:)` interpolation in lockstep with the `GeometryEffect` under
`withAnimation { scrollTo }` and under a rotation (no visible seam between header bottom and content top under `.stretch`); 15.x and 17.5 (`-ZTronForceAllFallbacks`) too.
R6 16+ `HeaderLayout` deferred measurement: no "modifying state during view update", ≤ 1 frame latency; 15 measuring pass invisible mid-collapse. R7 header button hit-testing at partial
height; drags starting on header buttons scroll (M3 §8 checklist); D11 gate on the host. R8 `.immediately` snap feel vs the reference; `.afterFinishAccelerating` double-animation visibility.
R9 `.refreshable` env read: confirm `\.refresh` is non-nil only below a `.refreshable` and that a native `List` inside the content does not inherit ours. R10 accessibility order of the
overlay host vs content with `accessibilitySortPriority` on 17.5 and 27.0 (VoiceOver reads the header first).

## Open questions (2026-10-18)
- Q1 Bounce forcing is axis-wide (UIKit parity) rather than per edge as S9's wording suggests — accept, or add per-edge bounce flags to `PanEnvironment` (touches M3 session code)?
- Q2 `beginRefreshing()` reveals the indicator by scrolling (Refresher-style) but runs no action (UIKit-style) — confirm the mix.
- Q3 Header `.immediately` snap is skipped when the user sets a vertical target behavior (paging/viewAligned) — or compose after it instead?
- Q4 S14 §3 bullets were not read (outside the allowed ranges): cross-check the test list above against them before kickoff.
- Q5 Member forwarding file: generate the one-liners from the M6/M8 member lists at session time (they are still landing), or ship the `scrollView { }` escape hatch only in M8b-3 and forwarders in M10?

## Orchestrator resolutions (2026-10-18)
- Q1 Accepted: axis-wide bounce forcing (UIKit sets `alwaysBounceVertical` for a refresh control).
- Q2 Accepted: `beginRefreshing()` animates the indicator in (reveals it) without running the action; `endRefreshing()`
  animates it out (S9 "both animate the indicator in and out").
- Q3 Compose, don't skip: run the user's target behavior first; if its target lands inside the collapse band, snap that
  to the nearest header snap position (still before `willEndDragging`, so the delegate sees the final target).
- Q4 Builders cross-check the test list against docs/SPEC.md S14 §3 (refresh + header bullets, amended 2026-10-19) at kickoff.
- Q5 **Void since 2026-10-19:** `withScalingHeader` returns `Self`; there is no container type and nothing to forward.
- Sequencing: M8b-1/-3 start only after M5 (a) and M6 session 1 are committed.

## Open questions (amendment 2026-10-19) — resolved below; the user may veto any of them before M8b-3 starts
- A1 `.preserve` under a pull past the top: the header's top edge stays pinned and a gap opens *below* it (the content pulls away), rather than the header translating down with the content as a plain first item would.
- A2 Collapse mode: shrink from the bottom with the top edge pinned, in both behaviors (the user's description); the reference's slide-up (`allowsHeaderCollapse` off) mode is not offered.
- A3 `.stretch` does not force vertical bounce (a refresher does): explicit over implicit, DEBUG note when the axis cannot bounce.
- A4 Removed as redundant with existing API, beyond the two refresh modifiers the user named: `scrollViewDidReachBottom` (`onZTronScrollReachEdge`), `hideScrollIndicators` (`showsIndicators`), `collapseProgress(Binding)` (reader; S4.6), `scrollToTop(resetScroll:)` (`state.scrollToTop`), `initialSnapPosition`/`snapHeaderToState` (`state.snapHeader(to:)`).
- A5 One convention for snap positions and progress (0 expanded, 1 collapsed); the reference's inverse snap convention is dropped with the type.
- A6 `ZTronScalingHeaderScrollView` no longer exists (CLAUDE.md's naming map still lists it; harmless, update at the next CLAUDE.md touch); no `ztron…` twin for the header.
- A7 Horizontal scroll view: the header is a fixed banner stacked above (driven by the vertical offset only).
- A8 The header builder is type-erased (`AnyView`) so `withScalingHeader` can return `Self`; identity/state proof is test 11.
- A9 `.fit` means "measured ideal height at the scroll view's width"; `.aspectRatio` is the computed equivalent and the recommended banner sizing.
- A10 The frame leaf wakes on `.target` (lockstep with the content under transactions); readers report the presentation geometry.

## Orchestrator resolutions (2026-10-19, side session M8b-s0, Architect)
- A1–A10 resolved as stated: each follows the user's wording (A1 "no consequence on the header", A2 "shrinks from the bottom with its top edge pinned", A7 "stacked above") or the
  non-negotiables (A3 no hidden side effects, A4/A6 no API redundancy, A8/A10 S4). They are listed so the user can veto any in one line; none changes the data flow.
- The reactive-geometry pattern is G of §2.5 (proxy + reader), D26 in Orchestration.md. E (a `DynamicProperty` wrapper) may be added later as sugar over the same engine if the
  builder's counters show demand; it must not introduce a second engine.
- M8b-3 is one Fable builder session (physics-free but layout-subtle: the frame leaf, the 15 measuring pass, the M6 compose hook); M8b-1/-2 stay Sonnet. Kickoff reads: this doc §2–3,
  SPEC S10 + S11 (header block, state additions), S9 "Refresh with the header" pointer, M8-chrome §7b only for the `willEndDragging` modifier in test 8.
- Sequencing unchanged (after M5 (a) and M6 s1); M8-8 (delegate modifiers) is independent and sits on M7 s1.
- **User confirmation (2026-10-19, in session M8b-s0): A1–A10 stand.** Two constraints added: (1) `.refresher { action }` with the default loader and
  `.refresher(refreshView:action:)` are preserved as spelled (§1.2 "Mandatory shapes", test 2); (2) no introspection anywhere (S2): the only mention in
  S10 is the reference's technique; nothing in §2 needs UIKit, reflection or private API — the header is a leaf modifier over our own offset state.
