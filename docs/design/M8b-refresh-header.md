# M8b · Refresh facade and scaling header (design)

Scope: SPEC S9 (330–395), S10 (396–482), S11 `height(min:max:)` doc comment (538–540). Builds on M3-pan §2–5 (pan/release pipeline, rubber
band, `PanEnvironment.bounces`), M5-resize §2–3/§6 (`adjustedContentInset`, inset-change rule, `headerObscured`/`ResizeCommit.header`, unobscured
center), M6-targets §1–4 (member/twin resolution, `effectiveTargetBehavior`, `ZTronScrollAnimation`, `setContentOffset`), M8-chrome §1–2 (`ChromeConfig`,
`ChromeLeaf`, `ChromeSample`, `IndicatorMath` conventions `o′ = o + aci.start`, `E = C·s + aci.start + aci.end`). Names per CLAUDE.md. iOS 15 deployment.
Rule of the doc: refresh and header state are **cold** except one hot value each (`dragPosition`, header height), both derived from the offset inside
viewport-overlay leaves. Content bodies run 0 times for every pull, hold, reset, collapse, stretch and snap (tier-0 counter), S4.

## 1. Refresh engine (`Refresh/`)

### 1.1 Data flow
```
.refreshable (env \.refresh) ─┐
member refresher(…) / twin ztronRefresher(…) ├─► RefreshResolver → [Edge: RefresherSpec]   (cold; explicit member ?? twin ?? .refreshable(.system) ?? none)
header pullToRefresh / pullToLoadMore ────────┘            │
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
                            refreshing(since: TimeInterval), finishing(until: TimeInterval) }
    struct Input: Equatable { var pull: CGFloat /* §1.3, ≥ 0 */; var isTracking: Bool; var enabled: Bool /* !zoomed && isScrollEnabled && otherEdgeIdle */; var time: TimeInterval }
    enum Event: Equatable { case sample(Input), lift(Input), sequenceEnd, begin(programmatic: Bool), done(TimeInterval), tick(TimeInterval), cancel }
    enum Effect: Equatable { case progress(CGFloat), mode(ZTronRefreshState.Mode, animated: Bool), trigger, hold(CGFloat), clearHold(animated: Bool), announce(String) }
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
- Bounce: a spec on a vertical edge sets `PanEnvironment.bouncesY = true` (and `bouncesX` for horizontal edges) regardless of `BounceConfiguration.resolve` —
  axis-wide, as UIKit's refresh control turns on `alwaysBounceVertical` (documented; short content then bounces at both ends, like UIKit).
- Indicator placement (leaf, viewport points; `top0 = aci.top − hold + header_current(o′)` §2.3 — the current header height counts): gap `g = max(0, −o′_withHold)`;
  `.system`: center `y = top0 − min(g, H)/2`, opacity/arrow angle from `dragPosition`, spinner while refreshing; `.default`: frame `[top0 − g, top0)` clipped to H, follows
  the pull 1:1; `overlay`: center `y = top0 − H/2 + (refreshing ? H : min(g, H))` floating over the content/header. Bottom/trailing mirror around `V − aci.bottom`.
  Custom `refreshView` is evaluated inside the same leaf with `Binding<ZTronRefreshState>`; writes of `.mode == .refreshing/.notRefreshing` map to begin/end, others ignored.
- `onZTronScrollReachEdge(edge, threshold)`: `d_top = o′`, `d_bottom = (E − V) − o′` (x likewise). Fires when `d ≤ threshold` becomes true, re-arms when
  `d > threshold + 1` (1 pt hysteresis) — including after content growth (load-more append). Evaluated at the didScroll flush (≤ 1/frame), from the coordinator, not a view body.
  `scrollViewDidReachBottom(perform:)` = `.bottom, threshold 0`.
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

## 2. `ZTronScalingHeaderScrollView` (`ScalingHeader/`)

### 2.1 Types and signatures
```swift
public struct ZTronHeaderGeometry: Equatable, Sendable { public var progress: CGFloat /* 0 expanded … 1 collapsed */; public var height: CGFloat /* current incl. stretch */
                                                        public var stretch: CGFloat /* ≥ 0 */; public var minHeight: CGFloat; public var maxHeight: CGFloat /* resolved */ }
public enum ZTronHeaderSnapMode: Sendable { case disabled, immediately, afterFinishAccelerating }
public enum ZTronHeaderSnapState: Equatable, Sendable { case collapsed, expanded, custom(CGFloat) }
public struct ZTronScalingHeaderScrollView<Header: View, Content: View>: View {
    public init(@ViewBuilder header: @escaping () -> Header, @ViewBuilder content: @escaping () -> Content)
    public init(@ViewBuilder header: @escaping (ZTronHeaderGeometry) -> Header, @ViewBuilder content: @escaping () -> Content)   // header body re-runs per frame (documented cost)
    public func height(min: CGFloat? = nil, max: CGFloat? = nil) -> Self     // S11 doc comment; no 150/350 defaults (migration note)
    public func collapseProgress(_ progress: Binding<CGFloat>) -> Self       // 0 expanded, 1 collapsed; written per frame from the coordinator
    public func allowsHeaderCollapse() -> Self; public func allowsHeaderGrowth() -> Self
    public func setHeaderSnapMode(_ mode: ZTronHeaderSnapMode) -> Self
    public func headerSnappingPositions(snapPositions: [CGFloat]) -> Self     // ⚠ inverse convention: 0 = collapsed, 1 = expanded (reference parity, doc'd on every symbol)
    public func initialSnapPosition(initialSnapPosition: CGFloat) -> Self    // same inverse convention
    public func snapHeaderToState(state: Binding<ZTronHeaderSnapState?>, animated: Bool = true) -> Self   // consumed → binding reset to nil
    public func scrollToTop(resetScroll: Binding<Bool>) -> Self             // true → setContentOffset(min, animated: true); false on settle
    public func pullToRefresh(isActive: Binding<Bool>, perform: @escaping () -> Void) -> Self             // §1: top spec, completion ends via isActive = false
    public func pullToLoadMore(isActive: Binding<Bool>, contentOffset: CGFloat, perform: @escaping () -> Void) -> Self   // bottom spec, loadMorePadding = contentOffset
    public func scrollViewDidReachBottom(perform: @escaping () -> Void) -> Self; public func hideScrollIndicators() -> Self
    var base: ZTronScrollView<Content>; var spec: HeaderSpec                  // internal
}
extension ZTronScalingHeaderScrollView { public func scrollView(_ f: (ZTronScrollView<Content>) -> ZTronScrollView<Content>) -> Self }   // escape hatch
// ScalingHeader/MemberForwarding.swift: one-line forwarders for every ZTronScrollView member in M3/M4/M6/M8 (`func scrollTargetBehavior(_ b:) -> Self { scrollView { $0.scrollTargetBehavior(b) } }`).
// Twins (`ztron…`) and ZTronScrollState observation work unchanged: the header view *is* a ZTronScrollView plus an env spec + overlay host. Zoom off by default (1…1).
struct HeaderSpec: Equatable { var min: CGFloat?; var max: CGFloat?; var collapses = false; var grows = false; var snap: ZTronHeaderSnapMode = .disabled
    var snapPositions: [CGFloat] = [0, 1]; var initialSnap: CGFloat?; var progress: Binding<CGFloat>?; var snapRequest: Binding<ZTronHeaderSnapState?>?; var scrollToTop: Binding<Bool>? }
struct HeaderMetrics: Equatable, Sendable { var min: CGFloat; var resolvedMax: CGFloat; var collapses: Bool; var grows: Bool; var band: CGFloat { max(0, resolvedMax − min) } }  // in ScrollMetrics.header
enum HeaderMath {   // pure, unit-tested
    static func resolve(min: CGFloat?, max: CGFloat?, natural: CGFloat?) -> (HeaderMetrics, warning: String?)
    static func geometry(o′: CGFloat, m: HeaderMetrics) -> ZTronHeaderGeometry          // §2.3
    static func frame(o′: CGFloat, m: HeaderMetrics, top0: CGFloat, width: CGFloat) -> (CGRect, proposedHeight: CGFloat?)
    static func snapOffset(position p: CGFloat, m: HeaderMetrics) -> CGFloat { m.band · (1 − p) }   // inverse convention lives in exactly one place
    static func nearestSnap(to o′: CGFloat, positions: [CGFloat], m: HeaderMetrics) -> CGFloat?    // nil outside the band or band == 0
}
public struct ZTronHeaderGeometryReader<C: View>: View { public init(@ViewBuilder content: @escaping (ZTronHeaderGeometry) -> C) }           // hot leaf, per frame
public struct ZTronHeaderProgressReader<C: View>: View { public init(steps: Int = 10, @ViewBuilder content: @escaping (CGFloat) -> C) }     // quantized: re-runs only when round(progress·steps) changes
extension ZTronScrollState { func setHeaderMetrics(_ m: HeaderMetrics?) /* discrete inset change via M5 §6 rule */; func headerHeight(at o′: CGFloat) -> CGFloat /* feeds headerObscured, indicators, scrollTo, refresh */ }
```

### 2.2 Data flow
```
ZTronScalingHeaderScrollView.body = base.environment(\.ztronHeaderSpec, spec)            ScrollContainer (2-line hook, like M8-1's overlay hook):
   HeaderHost (viewport overlay, above content and refresh leaves, inside the clip)        reads spec → HeaderMeasure → HeaderMath.resolve → state.setHeaderMetrics (cold)
   HeaderMeasure: 16+ HeaderLayout (single subview; ideal = sizeThatFits(W, nil)); 15: preference while expanded   ChromeLeaf(.offset) → HeaderMath.frame → frame/offset/clip of the one header instance
   release → M6 pipeline (HeaderSnapBehavior composed before the user behavior)          settle → afterFinishAccelerating / scrollToTop reset / snapRequest consume
```
Reserved inset: `adjustedContentInset.top = safe.top + header.resolvedMax + contentInset.top (+ hold)`. It changes only in `setHeaderMetrics` (natural-height change,
width/Dynamic Type/content change, explicit bounds change) — a discrete inset change through M5 §6, never per frame. Content size and proposal are untouched by collapse.

### 2.3 Formulas (`o′ = o + aci.top`, rest `o′ = 0` = fully expanded; `top0 = safe.top`)
- `c = clamp(o′, 0, band)`; `progress = band > 0 ? c / band : 0`; `g = grows ? max(0, −o′) : 0`; `height = resolvedMax − c + g`; `stretch = g`.
- Frame: `collapses` → `frame = (0, top0, W, height)`, header **proposed** `(W, height)` (it shrinks); else → `frame = (0, top0 − c, W, resolvedMax + g)`, proposed `(W, resolvedMax + g)`,
  clipped to `(0, top0, W, height)` (slides up until `min` remains). Growth anchors at the top in both modes. `height ≤ 0.5` ⇒ `allowsHitTesting(false)` + `accessibilityHidden(true)` (leaf modifiers).
- Natural height: `max == nil` → `resolvedMax = natural` (16+: `HeaderLayout.placeSubviews` queries `subviews[0].sizeThatFits(.init(width: W, height: nil)).height` and reports it
  through a `!=`-guarded deferred callback — one frame late at most, harmless as a discrete inset change; 15: a background `GeometryReader` on the header reports its height only while
  `progress == 0 && g == 0`, cached in `HeaderMeasure.natural`, the first layout always proposes `(W, nil)` so an `initialSnapPosition` applies one frame later on 15). Never a hidden copy.
  Re-measure triggers: viewport width (metrics), `\.dynamicTypeSize` (HeaderHost env), header content change (Layout invalidation / preference change).
- Resolution: `resolvedMax < 1` → DEBUG warning "header has no natural height; give explicit `height(min:max:)` or `.frame(idealHeight:)`"; `min ≥ resolvedMax` → `resolvedMax := min`,
  `band = 0`, progress 0, snapping off, growth still on; DEBUG warning only when both bounds were given with `min > max`. `min == nil` → 0.
- Snapping (band > 0 only): `.immediately` = `HeaderSnapBehavior` run **before** the user's behavior in M6 §4 (`natural ∈ (0, band)` ⇒ `target.y = nearestSnap(natural)`; velocity-aware
  because `natural` is the projected rest; skipped when the user set a vertical behavior — documented). `willEndDragging` then sees the snapped target; the retargeted decay lands exactly.
  `.afterFinishAccelerating`: at settle after user motion (`didEndDecelerating`, or `didEndDragging(false)`) with `o′ ∈ (0, band)` and `|o′ − nearest| > 0.5` → `setContentOffset(nearest, animated: true)`
  (`.uikit` clock path, no new gesture). `snapHeaderToState`: `.collapsed → o′ = band`, `.expanded → 0`, `.custom(h) → resolvedMax − clamp(h, min, resolvedMax)`; animated via `.uikit`, binding → nil.
  `initialSnapPosition(p)` → one unanimated write `o′ = snapOffset(p)` at the first layout with `band > 0`.
- Header height as top inset: `state.headerHeight(at:)` is used by indicators (`indInset.start += height`), M9 pinned section headers, `scrollTo` (`I.start += height` in M6 §4 formulas),
  refresh placement (§1.3 `top0`), and `ResizeCommit.header = headerHeight(at: o′_presentation)` at capture (M5 §3 `c(V, I, h)`); `headerObscured` is computed there, never written per frame.
- Refresh with header: growth on → hold makes `o′ = −H`, the header stretches by H and the indicator (overlay math) sits on the stretched header; growth off → the header stays at `resolvedMax`
  and the indicator sits in the gap `[top0 + resolvedMax − H, top0 + resolvedMax)` between header and content. Both fall out of §1.3 with `top0 + header_current`.
- Interaction: the host lives inside the viewport, so the pan/catch gestures (M3 §8) see drags that start on the header; buttons work (same `.simultaneousGesture` rules as content); the D11
  hit-test gate applies to the header host too. Content scrolls under the header (overlay z-order).

### 2.4 Edge cases
Explicit `max` → no measurement at all. `height(min: 100)` only → max = natural. Header taller than the viewport → `band` may exceed `E − V`; collapse limited by bounds (content shorter than band:
header can't fully collapse — reference behaves the same; DEBUG note). Rotation mid-collapse → metrics re-measure (width) → discrete inset change + M5 center rule with `header` captured.
`collapseProgress` binding per frame re-renders the owner if it reads it — doc recommends `ZTronHeaderProgressReader`. Snap positions outside 0…1 or empty → clamped / `[0, 1]`. Zoom enabled
explicitly → the header ignores zoom (viewport-space overlay), refresh disabled above min as §1. Two `ZTronScalingHeaderScrollView`s nested → each env spec binds to its own container only.

## 3. Builder sessions, tests, parity, device risks

| Session | Files (Sources/ZTronScrollView/…) | Depends on |
|---|---|---|
| M8b-1 refresh engine | `Refresh/{RefreshTypes,RefreshEngine,RefreshCoordinator,ReachEdgeWatcher}.swift`; `State/ZTronScrollState.swift` (+ `ScrollStateTypes.swift`): `refreshHoldInset` in `adjustedContentInset`, `beginRefreshing/endRefreshing`, reach-edge list; `Gesture/PanCoordinator.swift` bounce force + sample call; tests `RefreshEngineTests`, `ReachEdgeTests`, `RefreshHoldTests` | M5 (a), M6 s1 committed (shared state file) |
| M8b-2 refresher API, styles, demo | `Refresh/{RefreshAPI,RefreshResolver,RefreshIndicators,RefreshAccessibility}.swift`, `Modifiers/RefreshTwins.swift`, `.refresh` env bridge, container overlay hook, `docs/parity-matrix.md` rows; Demo `RefreshScreen` gallery (system / default / overlay / custom / load-more / horizontal / `.refreshable`) + `RefreshUITests` | M8b-1, M8-1 (`ChromeLeaf`) |
| M8b-3 scaling header | `ScalingHeader/{ZTronScalingHeaderScrollView,HeaderSpec,HeaderMath,HeaderMeasure,HeaderHost,HeaderSnap,ProgressReaders,MemberForwarding}.swift`; `ScrollMetrics.header` + `setHeaderMetrics/headerHeight(at:)` (state); M6 pipeline compose hook (`effectiveTargetBehavior` prefix); indicator/scrollTo inset consumers (2 lines each); Demo `ProfileScreen` (avatar header, snap, pull-to-refresh), `MapScreen` (stretchy image, overlay refresh, load-more) + `HeaderUITests` | M8b-1/2, M6 s1–2, M8-1 |

Tests (unit over `OSPath.allCases` with the test clock; demo UI on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`; content.body 0 in all):
1. Engine: `dragPosition` = pull/trigger clamped; `.whilePulling` fires at crossing with the finger down, exactly once per pull, not again while refreshing; `.onRelease` fires only at lift ≥ 1,
   disarms below; hold applied at lift (never mid-drag); min visible time; reset waits for lift while tracking; `done` idempotent from a background thread; disappear cancels the Task and clears unanimated.
2. Precedence: member > twin > `.refreshable(.system)`; later `refresher` replaces per edge; bottom spec adds `loadMorePadding`; horizontal → leading/trailing; disabled above min zoom and when scroll disabled.
3. Hold geometry: `adjustedContentInset` includes the hold; release over-pull springs to `−(aci.top + H)`; clear → M5 inset rule returns to rest only if at the start edge; `beginRefreshing` reveals, runs no action.
4. Reach edge: once per arrival, re-arm after +1 pt, re-fires after content growth; `scrollViewDidReachBottom` mapping. 5. Indicator placement for all 3 styles × 4 edges, with and without a header (growth on/off).
6. HeaderMath: progress/height/stretch across `o′`; collapse vs slide frames; zero-height hiding; natural <1 and `min ≥ max` warnings; `snapOffset` inverse convention; nearest snap inside band only.
7. Snap `.immediately` through the M6 pipeline (`willEndDragging` sees the snapped target; skipped with a user vertical behavior); `.afterFinishAccelerating` after settle; `snapHeaderToState` clamps `.custom`
   and resets the binding; `initialSnapPosition` once. 8. Natural height: Layout query (16+) vs cache (15) give the same `resolvedMax`; no re-measure per frame (measure counter); width/Dynamic Type change → one
   discrete inset change. 9. Header height feeds indicator inset, `scrollTo` anchor, `ResizeCommit.header` (M5 §10.1 with header re-run), refresh `top0`. 10. Quantized reader re-runs ≤ steps+1 times per full collapse.
Demo UI: pull → spinner → `done` → rest, counters `refresh.actions == 1` per pull, `content.body == 0`; VoiceOver "Refresh" action; header collapse/snap on Profile, stretch + overlay refresh on Map, load-more appends rows.
Parity rows (API | strategy | min OS | fallback | test): `.refreshable`/`RefreshAction` | 1 (env) | 15 | — | 2; `refresher(…)` ×4 + edge form | 2a+2b | 15 | — | 1–3; `ZTronRefreshState/Configuration/Style/TriggerMode` | 4 (reference mirror) | 15;
`onZTronScrollReachEdge` | 2b | 15 | — | 4; `UIRefreshControl.begin/endRefreshing` | state | 15 | — | 3; haptic | 1 | 17 | none <17 (gap); announcements | 17 | `accessibilityValue` <17 (gap); `ZTronScalingHeaderScrollView` + S10 table | reference mirror | 15 |
Layout 16+, cache 15 | 6–10; `height` defaults | gap (no 150/350) | migration note; header `.immediately` with a user vertical behavior | documented skip.

Device risks (in order): R1 calibrate `triggerDistance`, `indicatorHeight`, spinner look and the `.whilePulling` haptic moment side by side with `UIRefreshControl` in the MC spike app.
R2 hold-at-lift: any visible hitch when bounds change at lift at 120 Hz (if so, use the M5 `resizeGeneration` rebase and apply mid-drag). R3 spring-back to `−H` feel vs UIKit's. R4 16+ `HeaderLayout`
deferred measurement: confirm no "modifying state during view update" and ≤ 1 frame latency; 15: the one-frame expanded flash with `initialSnapPosition`. R5 header slide-mode clipping and button
hit-testing at partial/zero height; drags starting on header buttons scroll (M3 §8 checklist). R6 `.immediately` snap feel vs the reference; `.afterFinishAccelerating` double-animation visibility.
R7 `collapseProgress` binding cost in the owner at 120 Hz. R8 `.refreshable` env read: confirm `\.refresh` is non-nil only below a `.refreshable` and that a native `List` inside the content does not inherit ours.

## Open questions
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
- Q4 Builders cross-check the test list against docs/SPEC.md l.676–691 (S14 §3 refresh + header bullets) at kickoff.
- Q5 Generate the member-forwarding one-liners in M8b-3 from the members that have landed (S10: every ZTronScrollView
  API must work on it); keep the `scrollView { }` escape hatch too.
- Sequencing: M8b-1/-3 start only after M5 (a) and M6 session 1 are committed.
