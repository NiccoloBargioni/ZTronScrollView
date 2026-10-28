import SwiftUI
import ZTronScrollPhysics

// Refresh indicators (SPEC S9, design M8b §1.3): chrome leaves in the viewport overlay, on `ChromeLeaf`. During a pull only
// the leaf of the pulled edge re-renders; the container's body, the content and the cold host never run (tier 0). Nothing
// here is hit-testable and nothing needs UIKit.

// MARK: Placement (pure)

/// Where one indicator sits, in viewport points.
struct RefreshPlacement: Equatable {
    /// The indicator's frame: `length` along the pull axis, the free viewport width across it.
    var frame: CGRect
    /// The part of the viewport the indicator may draw in (the gap the pull opened, or everything for an overlay): `box`
    /// within `region`. Empty (zero length at the base) while the gap is closed or scrolled away.
    var clip: CGRect
    var opacity: Double
    /// The indicator's layer group (`RefreshPlacementEffect`), clipped to itself. In the gap its far edge is the content's
    /// edge in every state (open item 19), so the box moves rigidly with the content, also where the gap left the
    /// viewport; an overlay's box is `clip`.
    var box: CGRect
    /// The outer clip around the box: from the edge's base into the viewport (beyond it when the gap is), so nothing shows
    /// above the base; an overlay's is `box`. Drawn as the viewport from the base on (`RefreshPlacementEffect`), the
    /// same clip along the pull axis.
    var region: CGRect

    /// How much of the indicator is inside its clip along the pull axis (`frame ∩ clip`): its visible thickness.
    func visibleLength(vertical: Bool) -> CGFloat {
        vertical ? max(0, min(frame.maxY, clip.maxY) - max(frame.minY, clip.minY))
                 : max(0, min(frame.maxX, clip.maxX) - max(frame.minX, clip.minX))
    }
}

/// The formulas of M8b §1.3 in viewport points, y down. `d` is the distance from the edge's base (the adjusted inset
/// without this edge's own hold, plus the live header height) INTO the viewport; the gap a pull opens is `[0, pull]`.
/// The design text writes `top0 − …`; with y down the band grows from `top0` toward the content, as `UIRefreshControl`.
enum RefreshIndicatorMath {
    /// - Parameters:
    ///   - pull: signed displayed overscroll past the edge, against the bounds without the hold (`RefreshMath.signedPull`):
    ///     where the content's edge is along `d`.
    ///   - length: the indicator's thickness along the pull axis (`configuration.indicatorHeight`).
    ///   - hold: the gap a hold keeps open (`RefreshEngine.holdSize`); `nil` = `length`.
    ///   - base: `adjustedContentInset − refreshHold` per edge.
    ///   - header: the live scaling header height counted onto the top base (0 until M8b-3).
    /// - Returns: `nil` for a degenerate viewport, for an overlay none of whose indicator is inside its clip, and in the
    ///   gap for a closed gap (`pull <= 0`) unless `refreshing` (a pull or its release ends there, as before). While
    ///   refreshing (the hold, the spinner's retraction) the placement in the gap is kept whatever the pull (open item 19):
    ///   with the gap closed or scrolled off the viewport the indicator draws nothing (`clip` empty), its box stays on
    ///   the content's edge.
    static func placement(edge: Edge, style: ZTronRefreshStyle, overlay: Bool, refreshing: Bool, dragPosition: CGFloat,
                          pull: CGFloat, length: CGFloat, viewport: CGSize, base: EdgeInsets,
                          header: CGFloat = 0, hold: CGFloat? = nil) -> RefreshPlacement? {
        let p = max(0, pull)
        let L = max(0, length)
        let vertical = edge == .top || edge == .bottom
        let along = vertical ? viewport.height : viewport.width
        let crossStart = vertical ? base.leading : base.top
        let crossEnd = vertical ? viewport.width - base.trailing : viewport.height - base.bottom
        guard crossEnd > crossStart, along > 0, pull.isFinite else { return nil }
        let b: CGFloat
        switch edge {
        case .top: b = base.top + header
        case .bottom: b = base.bottom
        case .leading: b = base.leading
        case .trailing: b = base.trailing
        }
        // The centre of the indicator, its box, the visible part and the outer clip, along d.
        let center: CGFloat
        let opacity: Double
        let box: (CGFloat, CGFloat)
        let visible: (CGFloat, CGFloat)
        let region: (CGFloat, CGFloat)
        if overlay {
            // Floats over the content: slides in from outside the base with the pull, sits at L when refreshing.
            center = -L / 2 + (refreshing ? L : min(p, L))
            // To the viewport's far edge, and never shorter than the indicator: a base beyond the viewport (a `.stretch`
            // band below the landscape screen) keeps the indicator, off-screen, where a rotation's interpolation finds it
            // (open item 18). Past the far edge the container's clip bounds the drawing anyway.
            let clipEnd = max(0, along - b, center + L / 2)
            opacity = refreshing ? 1 : Double(L > 0 ? min(1, p / L) : 1)
            guard clipEnd > 0, center + L / 2 > 0, center - L / 2 < clipEnd else { return nil }
            box = (0, clipEnd)
            visible = box
            region = box
        } else {
            // In the gap `[0, pull]`, its far end on the content's edge. Open item 19: while refreshing the box keeps that
            // far edge whatever the pull, also where the content covers the base (a hold scrolled away, S7 in a rotation), so its
            // layer exists and moves rigidly with the content; `region` (from the base on) keeps the drawing to the gap.
            // The box reaches `max(L, hold)` before the content's edge (the whole gap when it is longer): it holds the
            // indicator's part before the edge, and the visible gap of any interpolated frame of an animation that
            // ends at rest (a gap of at most the hold).
            guard refreshing || pull > 0 else { return nil }
            let s = pull
            let H = max(0, hold ?? L)
            switch style {
            case .system:
                // Centred in the gap, as UIRefreshControl. With the gap closed (s <= 0, nothing visible) it keeps
                // going with the content's edge, continuous at 0, until it sits where the hold rests it (H/2 before
                // the edge) and then moves rigidly with the content: a rotation that brings a scrolled-away hold back
                // interpolates it at that place.
                center = s > 0 ? s / 2 : s - min(H, -s) / 2
                opacity = refreshing ? 1 : Double(max(0, min(1, dragPosition)))
            case .default:
                center = s - L / 2                                // glued to the content's edge, following the pull 1:1
                opacity = 1
            }
            box = (s - max(s, L, H), s)
            visible = (0, p)
            region = (0, max(s, along))
        }
        func interval(_ d0: CGFloat, _ d1: CGFloat) -> (CGFloat, CGFloat) {
            switch edge {
            case .top, .leading: return (b + d0, b + d1)
            case .bottom, .trailing: return (along - b - d1, along - b - d0)
            }
        }
        func rect(_ a: (CGFloat, CGFloat)) -> CGRect {
            vertical
                ? CGRect(x: crossStart, y: a.0, width: crossEnd - crossStart, height: a.1 - a.0)
                : CGRect(x: a.0, y: crossStart, width: a.1 - a.0, height: crossEnd - crossStart)
        }
        return RefreshPlacement(frame: rect(interval(center - L / 2, center + L / 2)), clip: rect(interval(visible.0, visible.1)),
                                opacity: opacity, box: rect(interval(box.0, box.1)), region: rect(interval(region.0, region.1)))
    }
}

extension RefreshIndicatorMath {
    /// The edge bases (`adjustedContentInset − refreshHold`) and whether the indicator floats over the content. With a
    /// vertical scaling header (M8b-3, `HeaderMath.refreshTop`): under `.preserve` `.openGap` (D65, the default) the header
    /// stays still and the gap opens below it, which is the plain base (the resting header's bottom edge); under
    /// `.preserve` `.followContent` the header moves down with the pull and the gap opens ABOVE it, so the base is the
    /// header slot's top (`top0`, the gap `[top0, top0 + pull]`; D61); under `.stretch` there is no gap, so the top
    /// indicator floats over the stretched band (`top0 + R`), overlay placement whatever `overlay:` says (SPEC S10 "Refresh
    /// with the header").
    static func base(edge: Edge, metrics m: ScrollMetrics, overlay: Bool) -> (EdgeInsets, Bool) {
        let aci = m.adjustedContentInset, hold = m.refreshHold
        var base = EdgeInsets(top: aci.top - hold.top, leading: aci.leading - hold.leading,
                              bottom: aci.bottom - hold.bottom, trailing: aci.trailing - hold.trailing)
        guard edge == .top, let top = HeaderMath.refreshTop(m) else { return (base, overlay) }
        base.top = top.base
        return (base, overlay || top.overlay)
    }
}

// MARK: Host (cold) — the container hook

/// Owns the coordinator of one scroll view and the cold bookkeeping around it. An `ObservableObject` that never
/// publishes: holding it as a `@StateObject` keeps the objects alive without making any view observe them.
@MainActor
final class RefreshHolder: ObservableObject {
    let coordinator: RefreshCoordinator
    /// The resolved refreshers of the latest evaluation; actions are read from here at trigger time, so a parent
    /// re-evaluation with a new closure never needs to rebuild an engine.
    var latest: [Edge: RefresherSpec] = [:]
    /// The latest `onZTronScrollReachEdge` closures (read at fire time) and the watchers registered on the state.
    var reach: [ReachEdgeDecl] = []
    private var watchers: [ReachEdgeWatcher] = []

    init(state: ZTronScrollState) {
        coordinator = RefreshCoordinator(state: state)
    }

    /// Hands the engines the values of `latest` (cold: on appear and when a value changes). The action is a trampoline.
    func apply() {
        coordinator.setSpecs(latest.mapValues { spec in
            var s = spec
            s.indicator = nil
            s.action = { [weak self] edge in await self?.latest[edge]?.action(edge) }
            return s
        })
    }

    /// Reconciles the watchers with the declarations: same edge at the same position keeps its arming (threshold updated
    /// in place), anything else is replaced.
    func syncReach(state: ZTronScrollState) {
        let old = watchers
        var next: [ReachEdgeWatcher] = []
        for (i, decl) in reach.enumerated() {
            if i < old.count, old[i].edge == decl.edge {
                old[i].threshold = max(0, decl.threshold)
                next.append(old[i])
            } else {
                next.append(ReachEdgeWatcher(edge: decl.edge, threshold: decl.threshold) { [weak self] in
                    guard let self, i < self.reach.count else { return }
                    self.reach[i].perform()
                })
            }
        }
        for w in old where !next.contains(where: { $0 === w }) { state.removeReachEdgeWatcher(w) }
        watchers = next
        for w in next { state.addReachEdgeWatcher(w) }
    }

    func removeReachWatchers(state: ZTronScrollState) {
        for w in watchers { state.removeReachEdgeWatcher(w) }
        watchers = []
    }
}

private struct ReachSignature: Equatable {
    var edge: Edge
    var threshold: CGFloat
}

/// The container's refresh hook: resolves the refreshers (member ?? twin ?? `.refreshable`), runs the coordinator, draws
/// the indicators and carries the accessibility actions. Cold: it re-evaluates when the declarations change, never per
/// frame (the indicators below it observe the coordinator).
struct RefreshOverlay: View {
    let state: ZTronScrollState
    let pan: PanCoordinator
    let axes: Axis.Set
    let member: [RefresherDecl]
    @Environment(\.ztronRefreshSpecs) private var twin
    @Environment(\.ztronReachEdges) private var reachDecls
    @Environment(\.refresh) private var refreshable
    @StateObject private var holder: RefreshHolder

    init(state: ZTronScrollState, pan: PanCoordinator, axes: Axis.Set, member: [RefresherDecl]) {
        self.state = state
        self.pan = pan
        self.axes = axes
        self.member = member
        _holder = StateObject(wrappedValue: RefreshHolder(state: state))
    }

    var body: some View {
        var bridge: (@MainActor () async -> Void)?
        if let action = refreshable { bridge = { await action() } }
        let resolved = RefreshResolver.resolve(member: member, twin: twin, refreshable: bridge, axes: axes)
        holder.latest = resolved
        holder.reach = reachDecls
        let signature = RefreshResolver.signature(resolved)
        let reach = reachDecls.map { ReachSignature(edge: $0.edge, threshold: $0.threshold) }
        return RefreshIndicatorsHost(coordinator: holder.coordinator, state: state, specs: resolved)
            .allowsHitTesting(false)
            .onAppear {
                pan.refresh = holder.coordinator
                holder.coordinator.announce = RefreshAccessibility.announce
                holder.apply()
                holder.syncReach(state: state)
            }
            .onDisappear {
                holder.coordinator.cancelAll()
                holder.removeReachWatchers(state: state)
            }
            .onChangeCompat(of: signature) { _ in holder.apply() }
            .onChangeCompat(of: reach) { _ in holder.syncReach(state: state) }
    }
}

// MARK: Indicators

/// Observes the coordinator (cold values that change per frame only during a pull) and lays out one leaf per active edge
/// plus the accessibility elements. The haptic rides on the trigger serial.
struct RefreshIndicatorsHost: View {
    @ObservedObject var coordinator: RefreshCoordinator
    let state: ZTronScrollState
    let specs: [Edge: RefresherSpec]

    private static let order: [Edge] = [.top, .leading, .bottom, .trailing]

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("refresh.host.body")
        #endif
        return ZStack {
            ForEach(Self.order, id: \.self) { edge in
                if let spec = specs[edge], let st = coordinator.states[edge],
                   st.mode != .notRefreshing || st.dragPosition > 0 || coordinator.retractions[edge] != nil {
                    RefreshEdgeIndicator(coordinator: coordinator, state: state, edge: edge, spec: spec, refresh: st,
                                         retract: coordinator.retractions[edge])
                }
            }
            ForEach(Self.order.filter { specs[$0] != nil }, id: \.self) { edge in
                RefreshAccessibilityElement(coordinator: coordinator, edge: edge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshHaptic(trigger: coordinator.triggerSerial)
    }
}

/// One edge's indicator: a `ChromeLeaf` on the offset and metrics channels (the pull and the hold), alive while the edge is
/// pulling, refreshing or going back with the content (`retract`).
struct RefreshEdgeIndicator: View {
    let coordinator: RefreshCoordinator
    let state: ZTronScrollState
    let edge: Edge
    let spec: RefresherSpec
    let refresh: ZTronRefreshState
    /// Set while the indicator retracts: after a refresh it keeps the spinner look, whatever `refresh.mode` says.
    var retract: RefreshEngine.RetractLook?
    /// The custom view the leaf built last (`BuiltRefreshIndicator`).
    @StateObject private var built = BuiltRefreshIndicator()

    var body: some View {
        let built = built
        return ChromeLeaf(state, channels: [.offset, .metrics]) { sample in
            let m = sample.metrics
            // While an app-driven animated resize is open (M8b-s6), `m` is the committed geometry and the content is drawn
            // at the presented one (`ResizeMath` at the drawn size): the pull comes from the target (realised at the
            // committed geometry, an untracked read) instead of the presentation offset (drawn against the presented
            // insets: measured that against the committed ones, it jumped by the inset change), and `RefreshResizeEffect`
            // moves the placement to the presented geometry at the drawn size.
            let open = m.resize.isOpen
            let target = open ? state.peek : nil
            let pull = RefreshMath.signedPull(edge: edge, offset: target?.targetOffset ?? sample.offset,
                                              zoom: target?.targetZoom ?? sample.zoom, metrics: m,
                                              alignment: state.contentAlignment)
            let (base, overlay) = RefreshIndicatorMath.base(edge: edge, metrics: m, overlay: spec.overlay)
            let length = spec.configuration.indicatorHeight
            let hold = RefreshEngine.holdSize(edge: edge, config: spec.configuration, overlay: false)
            let refreshing = refresh.mode == .refreshing || (retract == .spinner && !overlay)
            // Whether any of the indicator is inside its clip at this pull (a hold scrolled away keeps its placement and
            // draws nothing: open item 19).
            let visible = RefreshIndicatorMath.placement(
                edge: edge, style: spec.style, overlay: overlay, refreshing: refreshing, dragPosition: refresh.dragPosition,
                pull: pull, length: length, viewport: m.viewportSize, base: base, hold: hold)
                .map { $0.visibleLength(vertical: edge == .top || edge == .bottom) > 0 } ?? false
            // What the content is drawn with while the resize is open (the transform host's `ResizeMath.resolve` inputs):
            // the box follows the drawn content's edge (open item 21).
            let draw = target.map {
                RefreshContentDraw(offset: $0.targetOffset, zoom: $0.targetZoom, limits: state.zoomLimits,
                                   alignment: state.contentAlignment, paging: state.isPagingEnabled ? state.scrollAxes : [])
            }
            indicator(visible: visible, built: built).modifier(RefreshPlacementEffect(
                pull: pull, edge: edge, style: spec.style, overlay: overlay, length: length, hold: hold,
                refreshing: refreshing, refresh: refresh, retract: retract,
                viewport: m.viewportSize, base: base, useGeometryGroup: state.usesGeometryGroup,
                hasHeader: state.headerSpec != nil || m.header != nil, custom: spec.indicator != nil,
                resize: m.resize, baseFollowsInset: edge != .top || HeaderMath.refreshTop(m)?.overlay != false, draw: draw))
        }
    }

    /// `visible`: any of it is inside its clip. A custom view leaves the accessibility tree while nothing of it is drawn: a
    /// hold scrolled away keeps it in the tree (open item 19), clipped, with a frame over whatever is there (review of
    /// open item 19: 226 pt above the scroll view, over the other controls). `accessibilityHidden` on the one structure
    /// keeps its identity and its state. While nothing of it is drawn (outside a retraction) and its state is the same,
    /// the leaf hands SwiftUI the view it built last (`BuiltRefreshIndicator`), so its body does not run.
    @ViewBuilder private func indicator(visible: Bool, built: BuiltRefreshIndicator) -> some View {
        if let custom = spec.indicator {
            // A retraction (a release, a refresh's end) may be drawn by a SwiftUI-animated reset whose last leaf frame is
            // already at rest: it builds every frame, as before.
            built.view(reuse: !visible && retract == nil, state: refresh) { custom(binding) }
                .accessibilityHidden(!visible)
        } else {
            BuiltInRefreshIndicator(refresh: refresh, edge: edge, spinner: retract == .spinner)
                .accessibilityHidden(true)      // the named element carries the state; a custom view decides for itself
        }
    }

    /// The custom view's binding: reads the live state; a write of `.refreshing` / `.notRefreshing` begins / ends the
    /// refresh (no action run, as `beginRefreshing()`), the other fields are read-only.
    private var binding: Binding<ZTronRefreshState> {
        let edge = edge, coordinator = coordinator
        return Binding(
            get: { MainActor.assumeIsolated { coordinator.states[edge] ?? ZTronRefreshState(edge: edge) } },
            set: { new in
                MainActor.assumeIsolated {
                    let current = coordinator.states[edge]?.mode
                    if new.mode == .refreshing, current != .refreshing {
                        coordinator.begin(edge, runAction: false)
                    } else if new.mode == .notRefreshing, current == .refreshing {
                        coordinator.end(edge)
                    }
                }
            })
    }
}

/// The custom indicator the leaf built last and the state it shows (review of open item 19). The leaf rebuilds
/// `custom(binding)` on each of its frames, a fresh closure `Binding` each time, so the view's body ran on every frame
/// of a plain scroll while a hold was scrolled away and nothing of it was drawn (hosted rig, "away": 4 -> 20 at 779acb1;
/// SPEC S4 allows an indicator body per frame only during a pull or a collapse). With `reuse` (nothing of it visible, no
/// retraction) and the state it was built with (`ZTronRefreshState`: mode, drag position, style, edge), the leaf hands
/// SwiftUI the SAME `AnyView`, as the header's user views are reused (D42): no body runs ("away" 20 -> 3, the frames with
/// the gap on the screen). Otherwise it builds it again, as before (every other rig phase unchanged). Never publishes.
@MainActor
final class BuiltRefreshIndicator: ObservableObject {
    private var last: (view: AnyView, state: ZTronRefreshState)?

    func view(reuse: Bool, state: ZTronRefreshState, build: () -> AnyView) -> AnyView {
        if reuse, let last, last.state == state { return last.view }
        let view = build()
        last = (view, state)
        return view
    }
}

/// Places the indicator for one pull and clips it to the gap. `pull` is the animatable data. A reset that SwiftUI animates
/// (`resetAnimation: .swiftUI`, the default) jumps the state's offset while the content's drawing is interpolated; this modifier
/// is interpolated in the same transaction, so the indicator goes back with the content instead of vanishing on the first frame.
/// Every other frame (a finger, a release on the clock) just evaluates it with the pull of that frame.
///
/// The indicator box (the clip's size, the indicator at its place inside it, `.clipped()`) is its own layer group
/// (`RefreshIndicatorGroup`: 17+ `geometryGroup()`, 15–16 `compositingGroup()` under a scaling header), laid out at the
/// clip's place. Open item 18: without the group (the indicator `.position`ed in the viewport's frame under a mask
/// path) SwiftUI drew no layer for the indicator while its place was outside the viewport
/// (`RefreshIndicatorLayerTests`). In a system rotation that takes the gap below the screen (a refresh hold under a
/// header taller than the landscape viewport: an uncapped 16:9 `.preserve` `.openGap` or `.stretch` header) the
/// indicator vanished on the way out and, on the way back, appeared at once at its final place, over the header Core
/// Animation was still shrinking (seam lab: 5-6 of 32-34 rotation frames drawn, up to 79 pt off the gap). A laid-out
/// clip box alone changed nothing (spike); as a group it keeps its layer below the screen and Core Animation
/// interpolates it with the content's and the header's groups. The box stays laid out (`.position`), not moved by a
/// render-time translation: a placement change the leaf makes in an animated transaction (a `withAnimation` resize)
/// must animate as layout does (a translation landed at once, 88 pt off the gap at the start of a narrowing). An
/// overlay's clip is never shorter than the indicator (`RefreshIndicatorMath.placement`), so a `.stretch` base below
/// the screen keeps it too.
///
/// Open item 19 (no header): S7 scrolls a top hold's gap above the landscape viewport (the content covers the base), where
/// the placement was nil, so the indicator left the tree; on the way back it was drawn at once at its final place, over
/// the content Core Animation was still sliding in (seam lab, 14 frames; 4 more vanished early on the way out). In the gap
/// the placement is now kept whatever the pull while refreshing (a pull or its release still ends at 0): the box's far edge
/// is the content's edge in every state (it reaches `max(L, hold)` back from it), so the box moves rigidly with the content
/// and an interpolated frame cannot draw the
/// indicator past that edge; an outer box, `region`, from the edge's base on, clips the drawing to the gap (nothing above
/// the base, nothing at all while the gap is closed or scrolled away). Both are layer groups: the box keeps its layer
/// outside the region and off the viewport, the region off the viewport (a header taller than the landscape viewport puts
/// the base below it). An overlay's region is its box.
///
/// Open item 21: the region is laid out as the drawn viewport moved along the pull axis to the base (its far side the
/// viewport's, across the edge the whole width: the box clips there), and the box inside it is placed in a frame of the
/// drawn viewport's size. So during an open `withAnimation` resize, which SwiftUI draws frame by frame at the drawn size,
/// both render-time moves are functions of that size (`RefreshResizeEffect`): the region to the presented base, the box
/// with the content's drawn edge. Identity at the committed size: a system rotation's Core Animation frames are unchanged.
private nonisolated struct RefreshPlacementEffect: ViewModifier, Animatable {
    var pull: CGFloat
    let edge: Edge
    let style: ZTronRefreshStyle
    let overlay: Bool
    let length: CGFloat
    /// The gap the hold keeps open (`RefreshEngine.holdSize`): where a `.system` indicator rests against the content.
    let hold: CGFloat
    let refreshing: Bool
    let refresh: ZTronRefreshState
    let retract: RefreshEngine.RetractLook?
    let viewport: CGSize
    let base: EdgeInsets
    /// The state's layer-group flag (fixed at its creation): 17+ `geometryGroup()`, 15–16 `compositingGroup()`.
    let useGeometryGroup: Bool
    /// The view has a scaling header (its spec or its metrics): 15–16 group a custom indicator only under it
    /// (`RefreshIndicatorGroup`).
    let hasHeader: Bool
    /// The indicator is the app's view (`refresher(refreshView:)`), not the built-in one.
    let custom: Bool
    /// The resize commit (`RefreshResizeEffect`): identity outside an open resize.
    let resize: ResizeCommit
    /// Whether the edge's base is the adjusted inset (`RefreshResizeEffect`).
    let baseFollowsInset: Bool
    /// What the content is drawn with while the resize is open (nil otherwise).
    let draw: RefreshContentDraw?

    var animatableData: CGFloat {
        get { pull }
        set { pull = newValue }
    }

    /// 15–16 group the boxes under a scaling header (open item 18) and around the built-in indicator (open item 19); a
    /// custom indicator without a header stays ungrouped, so its blend modes reach what is behind it (final check of D65).
    private var fallbackGroup: Bool { hasHeader || !custom }

    /// The region is the drawn viewport moved along the pull axis so that its end on the edge's side is the edge's base
    /// (`region` from the base on, open item 19): `(0, b)` top, `(0, −b)` bottom, `(b, 0)` leading, `(−b, 0)` trailing.
    /// Across the edge it spans the viewport (the box clips the indicator to the free width there).
    static func regionOrigin(edge: Edge, region: CGRect, viewport: CGSize) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 0, y: region.minY)
        case .bottom: return CGPoint(x: 0, y: region.maxY - viewport.height)
        case .leading: return CGPoint(x: region.minX, y: 0)
        case .trailing: return CGPoint(x: region.maxX - viewport.width, y: 0)
        }
    }

    @MainActor func body(content: Content) -> some View {
        let placement = RefreshIndicatorMath.placement(
            edge: edge, style: style, overlay: overlay, refreshing: refreshing, dragPosition: refresh.dragPosition, pull: pull,
            length: length, viewport: viewport, base: base, hold: hold)
        #if DEBUG
        let _ = RefreshTrace.leaf(edge: edge, pull: pull, refresh: refresh, retract: retract, placement: placement)
        #endif
        ZStack(alignment: .topLeading) {
            if let placement {
                let box = placement.box
                let origin = Self.regionOrigin(edge: edge, region: placement.region, viewport: viewport)
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            content
                                .frame(width: placement.frame.width, height: placement.frame.height)
                                .opacity(placement.opacity)
                                .position(x: placement.frame.midX - box.minX, y: placement.frame.midY - box.minY)
                        }
                        .frame(width: max(0, box.width), height: max(0, box.height), alignment: .topLeading)
                        .clipped()
                        .modifier(RefreshIndicatorGroup(useGeometryGroup: useGeometryGroup, fallbackGroup: fallbackGroup))
                        .position(x: box.midX - origin.x, y: box.midY - origin.y)
                    }
                    // The drawn viewport's size, so the box's move is a function of the drawn size (open item 21).
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(RefreshResizeEffect(commit: resize, edge: edge, baseFollowsInset: baseFollowsInset,
                                                  part: .box(overlay: overlay), draw: draw))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .modifier(RefreshIndicatorGroup(useGeometryGroup: useGeometryGroup, fallbackGroup: fallbackGroup))
                .padding(EdgeInsets(top: origin.y, leading: origin.x, bottom: -origin.y, trailing: -origin.x))
                .modifier(RefreshResizeEffect(commit: resize, edge: edge, baseFollowsInset: baseFollowsInset,
                                              part: .region, draw: nil))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The refresh indicator's layer groups (open items 18 and 19, `RefreshPlacementEffect`: the box and the region around it).
/// 17+: `geometryGroup()` in every view (geometry only, drawing-neutral). 15–16: `compositingGroup()` under a scaling
/// header, where open item 18 arises (the indicator's place below the screen in a rotation: the gap or the `.stretch`
/// band under a header taller than the landscape viewport), and around the built-in indicator (open item 19: a hold
/// scrolled off the viewport, by S7 in a rotation; it has no blend mode, so the group draws it as on 17+). A custom
/// indicator without a header is not grouped, as before 5b32f97, and draws as on 17+ (final check of D65): a compositing
/// group is not drawing-neutral, a custom indicator's `.blendMode` composites within it and no longer reaches what is
/// behind the indicator (forced lane, no header, grouped in every view: a `.difference` white square stayed white over the
/// gap's blue and the content's green, yellow / magenta on 17+; `RefreshUITests`). So on 15–16 that one keeps no layer
/// while its gap is off the viewport, and a rotation that brings the gap back draws it at once at its final place (open
/// item 20). Under a header the 15–16 indicator keeps the documented blend difference, as the header and the content do
/// (SPEC S10 "15–16 layer groups"). Latched at the box's first frame (`GroupLatch`; the boxes exist while the indicator
/// has a placement: in the gap for the whole hold), so installing or removing the header during a hold never changes the
/// custom indicator's identity.
struct RefreshIndicatorGroup: ViewModifier {
    let useGeometryGroup: Bool
    /// 15–16: whether to group (`compositingGroup()`), decided once (`GroupLatch`).
    let fallbackGroup: Bool
    @StateObject private var latch = GroupLatch(note: "refresh.group")

    @ViewBuilder
    func body(content: Content) -> some View {
        if useGeometryGroup, #available(iOS 17, *) {
            content.geometryGroup()
        } else if latch.grouped(fallbackGroup) {
            content.compositingGroup()
        } else {
            content
        }
    }
}

/// What the content is drawn with during an open resize: the transform host's `ResizeMath.resolve` inputs besides the
/// commit (the target, unclamped; the state's limits, alignment and paging axes).
struct RefreshContentDraw: Equatable, Sendable {
    var offset: CGPoint
    var zoom: CGFloat
    var limits: ZoomLimits
    var alignment: UnitPoint
    var paging: Axis.Set
}

/// The indicator during an open app-driven animated resize (Split View, Stage Manager, a `withAnimation` size change;
/// M8b-s6): `RefreshPlacementEffect` places it in the COMMITTED geometry (the resize commit is unanimated), while the
/// viewport and the content are drawn at the presented one, interpolated by the drawn size exactly as the content's
/// transform does (`ResizeMath.presented`). Two render-time moves at the drawn size, both identity outside an open
/// resize and at the committed size (a system rotation, whose frames Core Animation interpolates):
/// - `.region` (the outer clip, laid out as the drawn viewport from the committed base): its base to the presented one,
///   the inset change along the pull axis (`regionDelta`; a `.stretch` header's `top0 + R` moves with `aci.top` by
///   `ΔR`, a `.preserve` `.openGap` header's plain base too, D65; a `.preserve` `.followContent` header's base, `top0`,
///   stays).
/// - `.box(overlay:)` (inside the region): an overlay with its base (`delta`, centred across the edge in the drawn
///   width / height); in the gap the box's far edge stays on the content's DRAWN edge (`boxDelta`, open item 21).
///
/// Measured before the commit moved to the presented geometry (seam lab, `.stretch` hold, width 402 → 241 pt): the
/// indicator jumped 90 pt (`ΔR`) and 80 pt sideways in one frame at the commit. Open item 21 (a headerless hold, the
/// height animated to 0.4 top-pinned and back, easeInOut 1.2 s): the box moved with the base only, so it sat at the
/// committed pull while S7 slid the content over the gap: the indicator vanished at once on the way out and was drawn
/// at its final place over the content still sliding in (holdgap.py: 57 frames over the content, about 1.1 s; 27.0,
/// 17.5 and forced).
nonisolated struct RefreshResizeEffect: GeometryEffect {
    enum Part: Equatable { case region, box(overlay: Bool) }

    let commit: ResizeCommit
    let edge: Edge
    /// Whether the edge's base is the adjusted inset (no header, `.stretch`, `.preserve` `.openGap`, the end edges) or stays
    /// (`.preserve` `.followContent`: `top0`).
    let baseFollowsInset: Bool
    let part: Part
    /// The content's drawing inputs (`.box` in the gap); nil outside an open resize.
    let draw: RefreshContentDraw?

    func effectValue(size: CGSize) -> ProjectionTransform {
        let d: CGPoint
        switch part {
        case .region: d = Self.regionDelta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, size: size)
        case let .box(overlay):
            d = Self.boxDelta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, overlay: overlay, draw: draw,
                              size: size)
        }
        return ProjectionTransform(CGAffineTransform(translationX: d.x, y: d.y))
    }

    static func isOpen(_ commit: ResizeCommit, size: CGSize) -> Bool {
        let cur = commit.current
        return commit.isOpen && cur.viewport.width > 0 && cur.viewport.height > 0 && size.width > 0 && size.height > 0
    }

    /// The presented placement minus the committed one at the drawn size of an indicator that rests on its base (pure,
    /// testable): centred across the edge, the base moved with the presented insets (`baseFollowsInset`) and, for the end
    /// edges, with the drawn viewport's far side.
    static func delta(commit: ResizeCommit, edge: Edge, baseFollowsInset: Bool, size: CGSize) -> CGPoint {
        guard isOpen(commit, size: size) else { return .zero }
        let cur = commit.current
        let p = ResizeMath.presented(commit, size: size)
        let dw = size.width - cur.viewport.width, dh = size.height - cur.viewport.height
        let top = p.insets.top - cur.insets.top, bottom = p.insets.bottom - cur.insets.bottom
        let leading = p.insets.leading - cur.insets.leading, trailing = p.insets.trailing - cur.insets.trailing
        let follow: CGFloat = baseFollowsInset ? 1 : 0
        let d: CGPoint
        switch edge {
        case .top: d = CGPoint(x: (dw + leading - trailing) / 2, y: top * follow)
        case .bottom: d = CGPoint(x: (dw + leading - trailing) / 2, y: dh - bottom * follow)
        case .leading: d = CGPoint(x: leading * follow, y: (dh + top - bottom) / 2)
        case .trailing: d = CGPoint(x: dw - trailing * follow, y: (dh + top - bottom) / 2)
        }
        return finite(d)
    }

    /// The region's move: the presented base minus the committed one along the pull axis, the inset change only (the
    /// region is laid out as the drawn viewport, so an end edge's base already moves with the drawn far side).
    static func regionDelta(commit: ResizeCommit, edge: Edge, baseFollowsInset: Bool, size: CGSize) -> CGPoint {
        guard isOpen(commit, size: size), baseFollowsInset else { return .zero }
        let cur = commit.current
        let p = ResizeMath.presented(commit, size: size)
        switch edge {
        case .top: return finite(CGPoint(x: 0, y: p.insets.top - cur.insets.top))
        case .bottom: return finite(CGPoint(x: 0, y: -(p.insets.bottom - cur.insets.bottom)))
        case .leading: return finite(CGPoint(x: p.insets.leading - cur.insets.leading, y: 0))
        case .trailing: return finite(CGPoint(x: -(p.insets.trailing - cur.insets.trailing), y: 0))
        }
    }

    /// The box's move inside the region (whose own move is `regionDelta`). Across the edge: centred in the drawn width /
    /// height (`delta`). Along it: an overlay rests on its base (`delta`); in the gap the far edge is the content's edge
    /// drawn at this size, `contentEdge(size) − contentEdge(committed)` (the gap's far edge moves with the drawn content,
    /// less the bound's move where the base does not follow it: `.preserve` `.followContent`, whose gap ends at the
    /// header's top, the content's edge less `aci.top − top0`).
    static func boxDelta(commit: ResizeCommit, edge: Edge, baseFollowsInset: Bool, overlay: Bool, draw: RefreshContentDraw?,
                         size: CGSize) -> CGPoint {
        guard isOpen(commit, size: size) else { return .zero }
        let base = delta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, size: size)
        let region = regionDelta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, size: size)
        let vertical = edge == .top || edge == .bottom
        var along = vertical ? base.y : base.x
        if !overlay, let draw {
            let moved = contentEdge(edge, commit: commit, draw: draw, size: size)
                - contentEdge(edge, commit: commit, draw: draw, size: commit.current.viewport)
            let bound = delta(commit: commit, edge: edge, baseFollowsInset: true, size: size)
            along = moved - (baseFollowsInset ? 0 : (vertical ? bound.y : bound.x))
        }
        return vertical ? finite(CGPoint(x: base.x, y: along - region.y)) : finite(CGPoint(x: along - region.x, y: base.y))
    }

    /// Where the content's `edge` is drawn at `size` along the pull axis, in viewport points: the content transform's
    /// `x_v = s·x_c + pad − o` (`ResizeMath.resolve`, as `ContentTransform` draws an open resize) at the content's start or
    /// end (the presented content size).
    static func contentEdge(_ edge: Edge, commit: ResizeCommit, draw: RefreshContentDraw, size: CGSize) -> CGFloat {
        let r = ResizeMath.resolve(size: size, offset: draw.offset, scale: draw.zoom, insetsAnimated: commit.current.insets,
                                   commit: commit, limits: draw.limits, alignment: draw.alignment, paging: draw.paging)
        let k = ResizeMath.presented(commit, size: size).contentSize
        switch edge {
        case .top: return r.pad.y - r.offset.y
        case .bottom: return r.pad.y - r.offset.y + r.scale * k.height
        case .leading: return r.pad.x - r.offset.x
        case .trailing: return r.pad.x - r.offset.x + r.scale * k.width
        }
    }

    private static func finite(_ d: CGPoint) -> CGPoint {
        CGPoint(x: d.x.isFinite ? d.x : 0, y: d.y.isFinite ? d.y : 0)
    }
}

#if DEBUG
/// DEBUG-only trace of what the refresher DRAWS and when its state machine moves (the slow-pull probe, D35): one compact
/// line per change in the shared `ZTronRenderCounters` event log, so a UI test can read the display it cannot see while a
/// finger is down. A leaf render is logged only when the indicator's visible thickness (to 0.5 pt), its mode or its
/// progress (to 0.01) changed.
@MainActor
enum RefreshTrace {
    private static var lastLeaf = ""

    static func leaf(edge: Edge, pull: CGFloat, refresh: ZTronRefreshState, retract: RefreshEngine.RetractLook?,
                     placement: RefreshPlacement?) {
        let vertical = edge == .top || edge == .bottom
        let visible = placement?.visibleLength(vertical: vertical) ?? 0
        let key = "\(Int((visible * 2).rounded())) \(refresh.mode) \(Int((refresh.dragPosition * 100).rounded())) \(String(describing: retract))"
        guard key != lastLeaf else { return }
        lastLeaf = key
        event("leaf \(edge) pull=\(f(pull)) p=\(f(refresh.dragPosition)) mode=\(refresh.mode) look=\(retract.map { "\($0)" } ?? "-") vis=\(f(visible))")
    }

    static func event(_ text: String) {
        ZTronRenderCounters.event("rf " + text)
    }

    static func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
}
#endif

/// The built-in look. `.system`: an arrow that turns with the pull, then the system spinner (the UIRefreshControl idiom);
/// `.default`: a ring that fills with the pull, then the spinner. The mode switch is animated by `modeAnimated`.
struct BuiltInRefreshIndicator: View {
    let refresh: ZTronRefreshState
    let edge: Edge
    /// The spinner stays although the refresh is over: the indicator is going back with the content.
    var spinner = false

    var body: some View {
        Group {
            if refresh.modeAnimated == .refreshing || spinner {
                ProgressView()
            } else {
                switch refresh.style {
                case .system:
                    Image(systemName: Self.arrow(edge))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(Double(refresh.dragPosition) * 180))
                case .default:
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: refresh.dragPosition)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 24, height: 24)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: refresh.modeAnimated)
    }

    private static func arrow(_ edge: Edge) -> String {
        switch edge {
        case .top: return "arrow.down"
        case .bottom: return "arrow.up"
        case .leading: return "arrow.right"
        case .trailing: return "arrow.left"
        }
    }
}

extension View {
    /// `.sensoryFeedback` when the action starts, on iOS 17+. Below 17 there is no haptic: UIKit is not allowed in the
    /// library (SPEC S9, a documented gap).
    @ViewBuilder
    func refreshHaptic(trigger: Int) -> some View {
        if #available(iOS 17, *) {
            sensoryFeedback(.impact(weight: .light), trigger: trigger)
        } else {
            self
        }
    }
}
