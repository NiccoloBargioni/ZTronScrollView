import SwiftUI
import Combine
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
    ///   - band: with `overlay`, the `.stretch` band (`inStretchBand`, S-RS-1): the overlay's look, drawn only over the
    ///     band the pull stretches, its far edge on the header's drawn bottom (see the branch).
    ///   - trigger: the trigger distance `T` (`configuration.triggerDistance`): the band's and the overlay's pull look read
    ///     the drag position at THIS pull, `min(1, p / T)` as the engine's `progress(for:)`, so they are a function of the
    ///     drawn pull (open item 31); `nil` draws the pull look of a trigger at least `length` long (today's).
    static func placement(edge: Edge, style: ZTronRefreshStyle, overlay: Bool, band: Bool = false, refreshing: Bool,
                          dragPosition: CGFloat, pull: CGFloat, length: CGFloat, viewport: CGSize, base: EdgeInsets,
                          header: CGFloat = 0, hold: CGFloat? = nil, trigger: CGFloat? = nil) -> RefreshPlacement? {
        let p = max(0, pull)
        let L = max(0, length)
        // Open item 31 (M8b-s8, L2): the band's and the overlay's pull look reach the refreshing look (opacity 1, the overlay
        // at `[0, L]`, the band's `.system` centred) at the trigger, also when it is shorter than the indicator (`T < L`):
        // they follow `max(p / L, drag)` instead of `p / L`, `drag` the drag position at this pull. With `T ≥ L` (every
        // default) `drag ≤ p / L` on every pull, so `reach` is nil and every expression is today's, bit for bit.
        let reach: CGFloat? = trigger.flatMap { T in
            let drag: CGFloat = p > 0 ? (T > 0 ? min(1, p / T) : 1) : 0
            return L > 0 && drag > p / L ? drag : nil
        }
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
        if overlay, band {
            // The `.stretch` band `[0, pull]` (S-RS-1, open item 30): the band is the header the pull stretches, its far
            // end the header's drawn bottom, on the content's top. As an overlay it slides in from outside the base with
            // the pull and sits at `[0, L]` once the band is `L` long, now also while refreshing: below that it stays on
            // the band's far end (a refreshing `.system` spinner: centred in the band, R1-RC1-1), so a hold the content is scrolled out of (and a programmatic hold's opening) moves it
            // with the content, clipped to the band, as open item 19 does in the gap. Before, it stayed at `[0, L]` while
            // refreshing whatever the pull and was drawn over the content scrolled under it (seam lab: 168-275 frames).
            // The box and the region are the gap's, so its layer exists off the screen and moves rigidly with the
            // content (open items 18, 19); the same pixels as before under a pull and at the hold's rest (`H ≥ L`).
            guard refreshing || pull > 0 else { return nil }
            let s = pull
            let H = max(0, hold ?? L)
            if refreshing, style == .system {
                // R1-RC1-1: the 20 pt spinner is centred in the band, as in the gap (`s/2`), up to `L` (then `[0, L]`
                // as above: the same place once the band is `L` long, so a refresh triggered by a pull starts there).
                // On the far end a hold shorter than `L/2 + 10` (40 at the default L 60) cut it at the band's start, and
                // one of 20 or less hid it for the whole refresh. Also in its retraction (the leaf's `refreshing`), so
                // the refresh's end moves nothing. Scrolled away it goes on with the content's edge until it sits where
                // the hold rests it (`H − rest` before the edge), then moves rigidly with the content, as the gap's.
                let rest = min(H, L) / 2
                center = s > 0 ? min(s, L) / 2 : s - min(H - rest, -s / 2)
            } else if style == .system, let reach {
                // Open item 31 (M8b-s8, C8): the pull look slides in from the band's far end as before and hands over to
                // the refreshing look's centre by the trigger: `+ (L·drag − p)/2` reaches `min(s, L)/2` exactly at
                // `p = T` and stays on it past it (`.armed` included). Continuous and monotone in the pull; only for `T < L`.
                center = min(s, L) - L / 2 + max(0, L * reach - p) / 2
            } else {
                center = min(s, L) - L / 2
            }
            opacity = refreshing ? 1 : Double(reach ?? (L > 0 ? min(1, p / L) : 1))
            box = (s - max(s, L, H), s)
            visible = (0, p)
            region = (0, max(s, along))
        } else if overlay {
            // Floats over the content: slides in from outside the base with the pull, sits at L when refreshing (and, open
            // item 31, by the trigger when it is shorter than the indicator).
            center = -L / 2 + (refreshing ? L : reach.map { L * $0 } ?? min(p, L))
            // To the viewport's far edge, and never shorter than the indicator: a base beyond the viewport (a `.stretch`
            // band below the landscape screen) keeps the indicator, off-screen, where a rotation's interpolation finds it
            // (open item 18). Past the far edge the container's clip bounds the drawing anyway.
            let clipEnd = max(0, along - b, center + L / 2)
            opacity = refreshing ? 1 : Double(reach ?? (L > 0 ? min(1, p / L) : 1))
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

    /// S-RS-1: whether the top indicator is drawn as the `.stretch` band's (`placement(band:)`): a vertical `.stretch` header
    /// and a refresher with a hold (not `overlay:`, which keeps the content where it is and floats over it by choice).
    static func inStretchBand(edge: Edge, metrics m: ScrollMetrics, overlay: Bool) -> Bool {
        guard edge == .top, !overlay, let header = m.header, header.vertical else { return false }
        return header.behavior == .stretch
    }

    /// The `refreshing` the leaf hands `placement`: refreshing, or the spinner's retraction after a refresh (and a pull that
    /// grabbed it again, which carries it: open item 32) in the gap and in the `.stretch` band (R1-RC1-1: centred there while
    /// refreshing, so the refresh's end moves nothing, as in the gap; M8b-s8 L3: for every style, so the band's `.default`
    /// end no longer fades to `H/L` in one frame). An overlay's retraction has the pull's look.
    static func holdsPlacement(mode: ZTronRefreshState.Mode, retract: RefreshEngine.RetractLook?, overlay: Bool, band: Bool,
                               style: ZTronRefreshStyle) -> Bool {
        mode == .refreshing || (retract == .spinner && (!overlay || band))
    }
}

// MARK: Host (cold) — the container hook

/// Owns the coordinator of one scroll view and the cold bookkeeping around it. An `ObservableObject` that never
/// publishes: holding it as a `@StateObject` keeps the objects alive without making any view observe them.
@MainActor
final class RefreshHolder: ObservableObject {
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

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

struct ReachSignature: Equatable {
    var edge: Edge
    var threshold: CGFloat
}

/// The container's refresh hook: resolves the refreshers (member ?? twin ?? `.refreshable`), runs the coordinator, draws
/// the indicators and carries the accessibility actions. Cold: it re-evaluates when the declarations change, never per
/// frame (the indicators below it observe the coordinator).
///
/// D80: on the path without layer groups (15–16, the forced fallbacks) the container has two slots, `.front` above the
/// content and the header and `.behind` behind the content; each leaf draws in one of them (`RefreshLayerMath.draws`).
/// Both share the container's `RefreshHolder` (one coordinator). Only the front slot wires it (the specs, `pan.refresh`,
/// the announcements, the reach watchers, `cancelAll` on disappear) and carries the accessibility elements and the
/// haptic; the behind slot resolves the same declarations and lays out the leaves only. 17+ build the front slot alone.
struct RefreshOverlay: View {
    let state: ZTronScrollState
    let pan: PanCoordinator
    /// The container's holder (D80: one per scroll view, shared by both slots). Never publishes, so never observed.
    let holder: RefreshHolder
    let axes: Axis.Set
    let member: [RefresherDecl]
    var layer: RefreshLayer = .front
    @Environment(\.ztronRefreshSpecs) private var twin
    @Environment(\.ztronReachEdges) private var reachDecls
    @Environment(\.refresh) private var refreshable

    @ViewBuilder var body: some View {
        let resolved = resolve()
        if layer == .behind {
            RefreshHostSlot(coordinator: holder.coordinator, state: state, specs: resolved, layer: .behind)
                .allowsHitTesting(false)
        } else {
            front(resolved)
        }
    }

    private func resolve() -> [Edge: RefresherSpec] {
        var bridge: (@MainActor () async -> Void)?
        if let action = refreshable { bridge = { await action() } }
        return RefreshResolver.resolve(member: member, twin: twin, refreshable: bridge, axes: axes)
    }

    private func front(_ resolved: [Edge: RefresherSpec]) -> some View {
        holder.latest = resolved
        holder.reach = reachDecls
        let values = RefreshHookValues(signature: RefreshResolver.signature(resolved),
                                       reach: reachDecls.map { ReachSignature(edge: $0.edge, threshold: $0.threshold) })
        // The hooks hang on a leaf that always exists (cost5-A): the host slot below is empty without a refresher, and an
        // empty view never appears, so a reach-only container (or one that gains a refresher later) would never wire the
        // pan, the announcer or its reach-edge watchers.
        return ZStack {
            Color.clear   // the slot's own frame (the host below fills it too), drawing and hit-testing nothing
                .modifier(RefreshHooks(state: state, pan: pan, holder: holder, values: values))
            RefreshHostSlot(coordinator: holder.coordinator, state: state, specs: resolved)
        }
        .allowsHitTesting(false)
    }
}

/// The front slot's appear / disappear / change hooks in one modifier (cost5-A, as `ContainerHooks`): they were one
/// `onAppear`, one `onDisappear` and two stacked `onChangeCompat` (each a wrapper type, on 17+ an `AnyView` too). Same
/// actions, same order: a change runs `apply()` for a new refresher signature, then `syncReach` for new reach
/// declarations, as the stacked chain did (inner first); the values a change compares against are the last ones seen.
struct RefreshHooks: ViewModifier {
    let state: ZTronScrollState
    let pan: PanCoordinator
    let holder: RefreshHolder
    let values: RefreshHookValues
    @State private var last = RefreshHookValues.Box()

    func body(content: Content) -> some View {
        let state = state, pan = pan, holder = holder, values = values, last = last
        return content
            .onAppear {
                last.value = values
                pan.refresh = holder.coordinator
                holder.coordinator.announce = RefreshAccessibility.announce
                holder.apply()
                holder.syncReach(state: state)
            }
            .onDisappear {
                holder.coordinator.cancelAll()
                holder.removeReachWatchers(state: state)
            }
            .onChangeCompat(of: values) { new in
                let old = last.value
                last.value = new
                if old?.signature != new.signature { holder.apply() }
                if old?.reach != new.reach { holder.syncReach(state: state) }
            }
    }
}

/// What `RefreshHooks` watches.
struct RefreshHookValues: Equatable {
    var signature: [Edge: RefreshResolver.Signature]
    var reach: [ReachSignature]

    /// The values the last appear or change saw (never published).
    final class Box {
        var value: RefreshHookValues?
    }
}

// MARK: Indicators

/// D80: the container slot a refresh indicator is drawn in (`RefreshOverlay`).
enum RefreshLayer: Equatable, Sendable {
    /// Above the content and the header (the z-order contract): every indicator on 17+, an overlay or a grouped one on 15–16.
    case front
    /// Behind the content (15–16 and the forced fallbacks only): a gap indicator without a layer group.
    case behind
}

/// D80 (open item 27): which slot draws a leaf's boxes. A gap indicator without a layer group (`RefreshIndicatorGroup.Kind
/// .none`: 15–16 or the forced fallbacks, a custom indicator, no scaling header, D65) keeps no layer while its gap is off
/// the viewport (open item 20), so a system rotation that brings the gap back draws it at once at its final place; behind
/// the content, the content still sliding in hides it instead (as UIKit's `UIRefreshControl`, the scroll view's lowest
/// subview), and an instant resize draws it at once in its place, as 17+ do. No hiding, so no resize needs telling apart
/// (D66, which hid it for 0.45 s after any resize that began with nothing of it visible, is retired). Every other indicator
/// is drawn in front: an overlay floats over the content by design, a grouped one keeps its layer off the viewport.
enum RefreshLayerMath {
    static func draws(layer: RefreshLayer, kind: RefreshIndicatorGroup.Kind, overlay: Bool) -> Bool {
        (kind == .none && !overlay) == (layer == .behind)
    }
}

/// Observes the coordinator (cold values that change per frame only during a pull) and lays out one leaf per active edge
/// plus the accessibility elements. The haptic rides on the trigger serial. D80: the `.behind` slot's host lays out the
/// leaves only (the front one carries the accessibility elements and the haptic, once).
/// The indicators' host, only while a refresher is resolved (cost4-A). Without one the host draws nothing and holds no
/// state (its leaves need a spec; the haptic fires on a trigger change only), so leaving it out changes nothing drawn; it
/// keeps its subtree's view types (indicator leaves, haptic, accessibility elements) off a container's first appearance:
/// building them there costs one first-use conformance lookup per type (about 50 on 27.0). A refresher resolved later
/// installs the host in the same update that resolves it.
struct RefreshHostSlot: View {
    let coordinator: RefreshCoordinator
    let state: ZTronScrollState
    let specs: [Edge: RefresherSpec]
    var layer: RefreshLayer = .front

    var body: some View {
        if !specs.isEmpty {
            RefreshIndicatorsHost(coordinator: coordinator, state: state, specs: specs, layer: layer)
        }
    }
}

struct RefreshIndicatorsHost: View {
    @ObservedObject var coordinator: RefreshCoordinator
    let state: ZTronScrollState
    let specs: [Edge: RefresherSpec]
    var layer: RefreshLayer = .front

    private static let order: [Edge] = [.top, .leading, .bottom, .trailing]

    @ViewBuilder var body: some View {
        #if DEBUG
        let _ = ZTronRenderCounters.increment(layer == .front ? "refresh.host.body" : "refresh.host.behind.body")
        #endif
        if layer == .front {
            ZStack {
                leaves
                ForEach(Self.order.filter { specs[$0] != nil }, id: \.self) { edge in
                    RefreshAccessibilityElement(coordinator: coordinator, edge: edge)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshHaptic(trigger: coordinator.triggerSerial)
        } else {
            ZStack { leaves }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var leaves: some View {
        ForEach(Self.order, id: \.self) { edge in
            if let spec = specs[edge], let st = coordinator.states[edge],
               st.mode != .notRefreshing || st.dragPosition > 0 || coordinator.retractions[edge] != nil {
                RefreshEdgeIndicator(coordinator: coordinator, state: state, edge: edge, spec: spec, refresh: st,
                                     retract: coordinator.retractions[edge], layer: layer)
                    // D75 `.headerFollows`: the top base `+ L`, evaluated per frame by the header's own lift (the leaf is
                    // viewport-sized), so the indicator stays at the lifted header's edge (`HeaderLift.swift`).
                    .modifier(HeaderLiftHost(state: state, axes: state.scrollAxes, viewportSized: true,
                                             slot: layer == .front ? .refresh : .refreshBehind, active: edge == .top))
            }
        }
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
    /// D80: the container slot of this leaf (`RefreshOverlay`); it draws only if its latched decision names this slot.
    var layer: RefreshLayer = .front
    /// The custom view the leaf built last (`BuiltRefreshIndicator`).
    @StateObject private var built = BuiltRefreshIndicator()
    /// Whether this frame's base move follows an app-animated inset change (`RefreshBaseFollow`).
    @StateObject private var follow = RefreshBaseFollow()
    /// The pull look → refreshing look switch of a `beginRefreshing()` during a retraction (`RefreshLookSwitch`).
    @StateObject private var lookSwitch = RefreshLookSwitch()

    var body: some View {
        let built = built, lookSwitch = lookSwitch, layer = layer
        return ChromeLeaf(state, channels: [.offset, .metrics]) { sample in
            #if DEBUG
            // Per slot (D80): the path without layer groups evaluates one leaf per edge in each slot.
            let _ = ZTronRenderCounters.increment(layer == .front ? "refresh.leaf.front" : "refresh.leaf.behind")
            #endif
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
            let band = RefreshIndicatorMath.inStretchBand(edge: edge, metrics: m, overlay: spec.overlay)
            let length = spec.configuration.indicatorHeight
            let hold = RefreshEngine.holdSize(edge: edge, config: spec.configuration, overlay: false)
            let refreshing = RefreshIndicatorMath.holdsPlacement(mode: refresh.mode, retract: retract, overlay: overlay,
                                                                 band: band, style: spec.style)
            // Whether any of the indicator is inside its clip at this pull (a hold scrolled away keeps its placement and
            // draws nothing: open item 19).
            let drawn = RefreshIndicatorMath.placement(
                edge: edge, style: spec.style, overlay: overlay, band: band, refreshing: refreshing,
                dragPosition: refresh.dragPosition, pull: pull, length: length, viewport: m.viewportSize, base: base, hold: hold,
                trigger: spec.configuration.triggerDistance)
            let visible = drawn.map { $0.visibleLength(vertical: edge == .top || edge == .bottom) > 0 } ?? false
            // The switch to the refreshing look while the pull look is drawn (M8b-s8 s1): where the pull look drew it. Each
            // slot's leaf decides it from the same inputs (D80); the front one, present on every path, traces it.
            let look = lookSwitch.look(edge: edge, refreshing: refreshing, pull: pull, drawn: drawn, trace: layer == .front) {
                RefreshIndicatorMath.placement(
                    edge: edge, style: spec.style, overlay: overlay, band: band, refreshing: false,
                    dragPosition: refresh.dragPosition, pull: pull, length: length, viewport: m.viewportSize, base: base,
                    hold: hold, trigger: spec.configuration.triggerDistance)
            }
            // What the content is drawn with while the resize is open (the transform host's `ResizeMath.resolve` inputs):
            // the box follows the drawn content's edge (open item 21).
            let draw = target.map {
                RefreshContentDraw(offset: $0.targetOffset, zoom: $0.targetZoom, limits: state.zoomLimits,
                                   alignment: state.contentAlignment, paging: state.isPagingEnabled ? state.scrollAxes : [])
            }
            let along: CGFloat = switch edge {
            case .top: base.top
            case .bottom: base.bottom
            case .leading: base.leading
            case .trailing: base.trailing
            }
            let baseAnimation = open ? nil : follow.animation(base: along, pull: pull, overlay: overlay,
                                                              insets: m.adjustedContentInset, follow: state.insetFollow)
            indicator(visible: visible, built: built).modifier(RefreshPlacementEffect(
                pull: pull, edge: edge, style: spec.style, overlay: overlay, band: band, length: length, hold: hold,
                trigger: spec.configuration.triggerDistance, refreshing: refreshing, refresh: refresh, retract: retract,
                viewport: m.viewportSize, base: base, useGeometryGroup: state.usesGeometryGroup,
                hasHeader: state.headerSpec != nil || m.header != nil, custom: spec.indicator != nil, layer: layer,
                resize: m.resize, baseFollowsInset: edge != .top || HeaderMath.refreshTop(m)?.overlay != false, draw: draw,
                baseAnimation: baseAnimation, look: look, stash: lookSwitch.stash, pin: state.catchPinRef,
                modelPull: pull))
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
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    private var last: (view: AnyView, state: ZTronRefreshState)?

    func view(reuse: Bool, state: ZTronRefreshState, build: () -> AnyView) -> AnyView {
        if reuse, let last, last.state == state { return last.view }
        let view = build()
        last = (view, state)
        return view
    }
}

/// The switch from the pull look to the refreshing look while the pull look is drawn (M8b-s8 s1, refresh design §4 and §6
/// step 5): a `beginRefreshing()` while the indicator goes back with the content after a pull let go below the trigger (a
/// `.pull` retraction; an overlay's spinner retraction too). The leaf went from the pull look (its place: the band's far end,
/// an overlay's slide-in; its opacity `p / L`, the gap's `dragPosition`) to the refreshing look (centred, opacity 1) in one
/// frame. Now the switch follows the glyph's own cross-fade (`modeAnimated`, 0.15 s): the glyph glides from where the pull
/// look drew it to the refreshing look's place and its opacity goes from the pull look's to the refreshing look's
/// (`RefreshLookFade`: a weight animated to its target in that cross-fade, drawn frame by frame). The switch is decided on
/// the update where the leaf's `refreshing` turns on while the pull look was drawn, and repeated for the same pull (a body
/// run twice). Every other update keeps the weight at its target: the leaf draws as before, bit for bit. A pull that
/// reaches the trigger switches with nothing to animate (the same place and opacity 1: open item 31). Never publishes.
@MainActor
final class RefreshLookSwitch: ObservableObject {
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    struct Look: Equatable {
        /// The weight's target, flipped by every switch.
        var target: CGFloat = 1
        /// From the refreshing look's place to the pull look's at the switch, in the viewport (y down).
        var shift: CGSize = .zero
        /// The opacity the pull look drew on the frame before the switch (where the switch's opacity starts).
        var from: Double = 1
        /// This update is the switch: the leaf animates the weight with the look's cross-fade.
        var switching = false
    }

    /// The look's own cross-fade (`BuiltInRefreshIndicator`'s `modeAnimated` animation).
    nonisolated static let crossFade = Animation.easeOut(duration: 0.15)

    let stash = RefreshTransactionStash()
    private var current = Look()
    /// The previous update: the leaf's `refreshing` and the opacity it drew (nil: nothing drawn).
    private var last: (refreshing: Bool, opacity: Double?)?
    private var switchPull: CGFloat?

    /// `drawn`: this update's placement (the leaf's `refreshing`); `pullLook`: the pull look at this pull, read only at a switch.
    /// `trace`: record the switch in the DEBUG event log (one leaf per switch: the front slot's, D80).
    func look(edge: Edge, refreshing: Bool, pull: CGFloat, drawn: RefreshPlacement?, trace: Bool = true,
              pullLook: () -> RefreshPlacement?) -> Look {
        defer { last = (refreshing, drawn?.opacity) }
        if refreshing, let last, !last.refreshing, let from = last.opacity, let to = drawn, let pulled = pullLook() {
            let shift = CGSize(width: pulled.frame.midX - to.frame.midX, height: pulled.frame.midY - to.frame.midY)
            // Something to animate (a pull that reaches the trigger switches in place, at opacity 1: rounding only).
            if max(abs(shift.width), abs(shift.height)) > 1e-6 || abs(from - to.opacity) > 1e-6 {
                current.target = 1 - current.target
                current.shift = shift
                current.from = from
                current.switching = true
                switchPull = pull
                #if DEBUG
                if trace { RefreshTrace.event("switch \(edge) pull=\(RefreshTrace.f(pull)) shift=\(RefreshTrace.f(shift.width)),\(RefreshTrace.f(shift.height)) from=\(RefreshTrace.f(CGFloat(from)))") }
                #endif
                return current
            }
        }
        if current.switching, !(refreshing && pull == switchPull) { current.switching = false }
        return current
    }
}

/// The look switch drawn frame by frame (`RefreshLookSwitch`): the weight is animated to its target in the switch's
/// cross-fade and every frame of that animation runs this body with the weight it reached, which draws the glyph
/// `k` = `|weight − target|` of the way back: `k` of the switch's shift away from the placement's place and at the opacity
/// `k` of the way from the placement's (1 while refreshing) to the pull look's (`from`). `k` is 0 on every update but a
/// switch's animation: nothing moved, opacity 1, the placement's frame, place and opacity (outside, `boxes`) bit for bit.
///
/// Open item 41. (1) The switch animated a shift (an animatable `GeometryEffect`) and the plain opacity in the cross-fade:
/// SwiftUI resolves its ancestors' animations at the leaves, so the spinner the cross-fade inserts is a new leaf and started
/// at their end values (no glide; a compositing group around the glyph resolved them at the group). With the glyphs in a
/// `ZStack` (`BuiltInRefreshIndicator`) the indicator was not drawn at all on the 1-2 frames after the switch (27.0: 16 of
/// 20 runs, with or without a group, the shift and the opacity animated or drawn frame by frame through a `GeometryEffect`;
/// 0 of 4 with the switch unanimated). (2) The body depends on nothing but the weight and the switch (fixed for its
/// duration): the shift is layout (the glyph's centre guides, which the placement's frame aligns: no geometry effect, and
/// the glyph is offered the placement's size as without a switch; a padding shrank a flexible custom indicator's proposal),
/// the opacity a factor; the frame, the opacity and the place are the leaf's, outside, with the update's own transaction.
/// The 8 pt drift with the content after a trigger below `indicatorHeight` (seam lab 27.0, `rtrig40` / `rtrig30`) was not
/// this modifier's (NSLog: no switch at those triggers, `k` 0, the place fresh every frame) but the fading arrow's
/// (`RefreshGlyphBoundary`). The content keeps the update's own transaction too (`RefreshTransactionStash.restore`): a
/// custom indicator's change is drawn as without the switch.
nonisolated struct RefreshLookFade: ViewModifier, Animatable {
    /// Animated from the previous target to `look.target` in the switch's cross-fade; at the target otherwise.
    var weight: CGFloat
    let look: RefreshLookSwitch.Look
    let stash: RefreshTransactionStash

    var animatableData: CGFloat {
        get { weight }
        set { weight = newValue }
    }

    /// What is left of the switch: 1 at its start, 0 at its end and outside a switch.
    static func remaining(weight: CGFloat, target: CGFloat) -> CGFloat { min(1, abs(weight - target)) }

    /// The factor on the placement's opacity: the pull look's opacity (`from`) at the switch's start over the refreshing
    /// look's (1), 1 at its end and outside a switch.
    static func factor(from: Double, remaining k: CGFloat) -> Double { k > 0 ? 1 + (from - 1) * Double(k) : 1 }

    /// The drawn opacity, the placement's `opacity` times `factor`.
    static func opacity(_ opacity: Double, from: Double, remaining k: CGFloat) -> Double {
        k > 0 ? opacity * factor(from: from, remaining: k) : opacity
    }

    /// The drawn place: `k` of the switch's shift away from the placement's.
    static func position(_ p: CGPoint, shift: CGSize, remaining k: CGFloat) -> CGPoint {
        k > 0 ? CGPoint(x: p.x + shift.width * k, y: p.y + shift.height * k) : p
    }

    /// The drawn shift from the placement's place: `k` of the switch's (zero outside a switch).
    static func offset(shift: CGSize, remaining k: CGFloat) -> CGSize {
        k > 0 ? CGSize(width: shift.width * k, height: shift.height * k) : .zero
    }

    func body(content: Content) -> some View {
        let k = Self.remaining(weight: weight, target: look.target)
        let d = Self.offset(shift: look.shift, remaining: k)
        // The placement's frame (outside) puts the glyph's centre guides on its centre: with the guides `d` before the
        // glyph's centre, the glyph is drawn `d` away from it.
        content
            .transaction { t in stash.restore(&t) }
            .alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] - d.width }
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] - d.height }
            .opacity(Self.factor(from: look.from, remaining: k))
    }
}

/// The transaction of the update that animates a look switch, as it was before the switch's animation replaced it: the
/// indicator's content gets it back (`restore`), so only the switch's weight takes the cross-fade (`RefreshLookFade`; the
/// frame, the opacity and the place are outside the override).
/// Written by the outer `.transaction` of the same update (which runs first: the inner one reads what it hands down),
/// cleared by it on every other update.
nonisolated final class RefreshTransactionStash: @unchecked Sendable {
    private var animation: Animation?
    private var disablesAnimations = false
    private var overridden = false

    func override(_ t: inout Transaction, with animation: Animation) {
        self.animation = t.animation
        disablesAnimations = t.disablesAnimations
        overridden = true
        t.disablesAnimations = false
        t.animation = animation
    }

    func clear() { overridden = false }

    func restore(_ t: inout Transaction) {
        guard overridden else { return }
        t.animation = animation
        t.disablesAnimations = disablesAnimations
    }
}

/// Fix round 2 of M8b-s6 (review of open item 21): an inset-only change the app animates (`withAnimation` around a bottom
/// `.safeAreaInset`, a bar) is reported after the layout pass that animates the container's frame, and written without
/// animation: the edge's base, where the indicator's clip begins (`region`), moved at once while the container's own clip,
/// its frame, followed the app's curve. A hold in the gap at the bottom vanished on the first frame instead of sliding out
/// clipped by the frame (seam lab kbfake, 150 pt, 27.0 / 17.5 / forced; hosted: the region 806 → 656 at once, the frame
/// 806 → 656 over 1.2 s), and an overlay jumped 150 pt to its new base (and back, drawn at once at its old place).
/// `ZTronScrollState.insetFollow` keeps the turn's animation and the inset it wrote; on the frame whose base moves by that
/// change the leaf draws the move in it (`RefreshPlacementEffect` interpolates the base with the pull): an overlay with
/// its base, in the gap only where the content's edge stays (`base + pull` unchanged: the box stays on the content's edge,
/// the region slides with the frame). Where the content moves (the start edge kept), the base moves at once as before.
/// The decision is made once per change and repeated only for the same values (a body run twice). Never publishes.
@MainActor
final class RefreshBaseFollow: ObservableObject {
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    private var last: (base: CGFloat, edge: CGFloat)?
    private var decided: (serial: UInt64, base: CGFloat, pull: CGFloat, animation: Animation?)?

    /// `base`: the edge's base along its axis; `pull`: the signed pull (the content's edge is `base + pull` from the
    /// viewport's side of the edge); `insets`: this frame's adjusted inset.
    func animation(base: CGFloat, pull: CGFloat, overlay: Bool, insets: EdgeInsets,
                   follow: ZTronScrollState.InsetFollow?) -> Animation? {
        let prev = last
        last = (base, base + pull)
        guard let follow, follow.insets == insets else { return nil }
        if let d = decided, d.serial == follow.serial {
            return abs(d.base - base) < 0.01 && abs(d.pull - pull) < 0.01 ? d.animation : nil
        }
        var a: Animation?
        if let prev, abs(base - prev.base) > 0.5, overlay || abs(base + pull - prev.edge) <= 0.5 { a = follow.animation }
        decided = (follow.serial, base, pull, a)
        return a
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
/// Open item 21: the region is laid out as the drawn viewport (its far side the viewport's, across the edge the whole
/// width: the box clips there) and moved along the pull axis to the base by a render-time translation, and the box inside
/// it is placed in a frame of the drawn viewport's size. So during an open `withAnimation` resize, which SwiftUI draws
/// frame by frame at the drawn size, both render-time moves are functions of that size (`RefreshResizeEffect`): the region
/// to the presented base, the box with the content's drawn edge and centred across the edge. Identity (the region: its
/// committed base) at the committed size: a system rotation's Core Animation frames are unchanged.
///
/// Review of open item 21: no layout above the box's effect changes at the resize's commit. The commit is written
/// without animation; a layout move it makes to an ancestor of a `GeometryEffect` (the region `.padding`ed to the committed
/// base, as a04c279 laid it out, or `.offset` by it) ended the animation of that effect's geometry on 15–16 (the forced
/// lane), so the effect saw the committed size from the commit on and the box's move along the edge was not drawn: a
/// bottom overlay hold, the height animated to 0.4 top-pinned (its bottom inset 34 → 0 at the commit), jumped 500 pt to
/// its committed place in the middle of the content on the way out and was not drawn on the way back (hosted presented
/// layer tree: 41 of 56 samples; seam lab 59 frames missing); a bottom hold in the gap vanished at once instead of sliding
/// out clipped. 17+ resolve it at each `geometryGroup()`. The base is the region effect's translation instead, a render-
/// time move, and the cross move is the box's (the region spans the drawn viewport across the edge, so a move across
/// never cuts it; a04c279 to 8f902f4 widened it by a margin of the committed cross length, which also changed at a width
/// resize's commit).
private nonisolated struct RefreshPlacementEffect: ViewModifier, Animatable {
    var pull: CGFloat
    let edge: Edge
    let style: ZTronRefreshStyle
    let overlay: Bool
    /// The `.stretch` band (`RefreshIndicatorMath.inStretchBand`): drawn over the band only, its box on the content's edge.
    let band: Bool
    let length: CGFloat
    /// The gap the hold keeps open (`RefreshEngine.holdSize`): where a `.system` indicator rests against the content.
    let hold: CGFloat
    /// The trigger distance: the band's and the overlay's pull look follow the drag position at the drawn pull (open item 31).
    let trigger: CGFloat
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
    /// D80: the container slot of this leaf; the boxes are drawn only in the slot `RefreshLayerMath.draws` names.
    let layer: RefreshLayer
    /// The resize commit (`RefreshResizeEffect`): identity outside an open resize.
    let resize: ResizeCommit
    /// Whether the edge's base is the adjusted inset (`RefreshResizeEffect`).
    let baseFollowsInset: Bool
    /// What the content is drawn with while the resize is open (nil otherwise).
    let draw: RefreshContentDraw?

    /// The animation of an app-animated inset change this frame's base move follows (`RefreshBaseFollow`), else nil.
    let baseAnimation: Animation?
    /// The pull look → refreshing look switch (`RefreshLookSwitch`): the glyph's shift and whether this update animates it.
    let look: RefreshLookSwitch.Look
    /// The update's own transaction, kept for the indicator's content while the switch's weight animates.
    let stash: RefreshTransactionStash
    /// D79: the catch pin and the pull the leaf computed (the model): drawn instead of the interpolated `pull` while it
    /// pins (`CatchPin`), so a residual SwiftUI keeps after a catch never moves the indicator off the caught content.
    var pin: CatchPin.Ref? = nil
    var modelPull: CGFloat = 0

    var animatableData: CGFloat {
        get { pull }
        set { pull = newValue }
    }

    /// 15–16 group the boxes under a scaling header (open item 18) and around the built-in indicator (open item 19); a
    /// custom indicator without a header stays ungrouped, so its blend modes reach what is behind it (final check of D65).
    private var fallbackGroup: Bool { hasHeader || !custom }

    /// The region is the drawn viewport moved along the pull axis so that its end on the edge's side is the edge's base
    /// (`region` from the base on, open item 19): `(0, b)` top, `(0, −b)` bottom, `(b, 0)` leading, `(−b, 0)` trailing.
    /// Across the edge it spans the drawn viewport (the box clips the indicator to the free width). The move is the region
    /// effect's translation (`RefreshResizeEffect.Part.region`), not layout: see the type's note on the commit.
    static func regionOrigin(edge: Edge, region: CGRect, viewport: CGSize) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 0, y: region.minY)
        case .bottom: return CGPoint(x: 0, y: region.maxY - viewport.height)
        case .leading: return CGPoint(x: region.minX, y: 0)
        case .trailing: return CGPoint(x: region.maxX - viewport.width, y: 0)
        }
    }

    @MainActor func body(content: Content) -> some View {
        let key: CatchPin.Key = layer == .behind ? .refreshBehind(edge) : .refresh(edge)   // one latch per effect (D80)
        let pull = pin?.resolve(key, interpolated: self.pull, model: modelPull) ?? self.pull
        let placement = RefreshIndicatorMath.placement(
            edge: edge, style: style, overlay: overlay, band: band, refreshing: refreshing, dragPosition: refresh.dragPosition,
            pull: pull, length: length, viewport: viewport, base: base, hold: hold, trigger: trigger)
        #if DEBUG
        let _ = RefreshTrace.leaf(edge: edge, pull: pull, refresh: refresh, retract: retract, placement: placement)
        #endif
        ZStack(alignment: .topLeading) {
            if let placement {
                // One group decision, latched at the boxes' first frame, for both groups and the slot (D80).
                RefreshGroupLatched(useGeometryGroup: useGeometryGroup, fallbackGroup: fallbackGroup, overlay: overlay,
                                    layer: layer) { group in
                    boxes(content, placement: placement, group: group)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The box and the region around it (see the type's note), in the latched layer-group decision `group`. A gap
    /// indicator without a layer group (`group == .none`: 15–16 or the forced fallbacks, a custom indicator, no scaling
    /// header) keeps no layer while its gap is off the screen (open item 20); it is drawn behind the content (D80,
    /// `RefreshLayerMath`), so a system rotation that brings the gap back cannot draw it over the content still sliding in.
    @MainActor private func boxes(_ content: Content, placement: RefreshPlacement,
                                  group: RefreshIndicatorGroup.Kind) -> some View {
        let look = look, stash = stash
        let box = placement.box
        let origin = Self.regionOrigin(edge: edge, region: placement.region, viewport: viewport)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    content
                        // The look switch drawn frame by frame (M8b-s8 s1): its weight in the look's cross-fade; the
                        // frame, the opacity and the place below keep the update's own.
                        .modifier(RefreshLookFade(weight: look.target, look: look, stash: stash))
                        .transaction { t in
                            stash.clear()
                            if look.switching {
                                stash.override(&t, with: RefreshLookSwitch.crossFade)
                            }
                        }
                        .frame(width: placement.frame.width, height: placement.frame.height)
                        .opacity(placement.opacity)
                        .position(x: placement.frame.midX - box.minX, y: placement.frame.midY - box.minY)
                }
                .frame(width: max(0, box.width), height: max(0, box.height), alignment: .topLeading)
                .clipped()
                .modifier(RefreshIndicatorGroup(kind: group))
                .position(x: box.midX - origin.x, y: box.midY - origin.y)
            }
            // The drawn viewport's size, so the box's move is a function of the drawn size (open item 21).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(RefreshResizeEffect(commit: resize, edge: edge, baseFollowsInset: baseFollowsInset,
                                          part: .box(overlay: overlay && !band), draw: draw))
        }
        // The drawn viewport, laid out with nothing that the resize's commit changes (no committed base, no
        // committed margin): see the note above.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .modifier(RefreshIndicatorGroup(kind: group))
        .modifier(RefreshResizeEffect(commit: resize, edge: edge, baseFollowsInset: baseFollowsInset,
                                      part: .region(origin: origin), draw: nil))
        // An app-animated inset change (`RefreshBaseFollow`): the boxes' layout and the region's origin move in its
        // animation, below this modifier, whose own `pull` lands at once (interpolated here too, the values the body
        // derives were animated again on every frame: the moves lagged 0.1 s to most of the change, hosted).
        .transaction { t in
            if let baseAnimation { t.animation = baseAnimation }
        }
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
/// (SPEC S10 "15–16 layer groups"). Latched at the boxes' first frame (`RefreshGroupLatched`; the boxes exist while the
/// indicator has a placement: in the gap for the whole hold), so installing or removing the header during a hold never
/// changes the custom indicator's identity, nor its slot (D80), which reads the same decision.
struct RefreshIndicatorGroup: ViewModifier {
    enum Kind: Equatable { case geometry, compositing, none }
    let kind: Kind

    @ViewBuilder
    func body(content: Content) -> some View {
        if kind == .geometry, #available(iOS 17, *) {
            content.geometryGroup()
        } else if kind == .compositing {
            content.compositingGroup()
        } else {
            content
        }
    }
}

/// The boxes' layer-group decision for their lifetime: 17+ `geometryGroup()` (the state's flag, fixed at its creation),
/// 15–16 `compositingGroup()` or none, decided once (`GroupLatch`) at the boxes' first frame. The box and the region read
/// it, and so does the slot (D80): the boxes are drawn only in the slot `RefreshLayerMath.draws` names for the latched
/// kind and this frame's `overlay`. Both slots carry the leaf on the path without layer groups and latch the same kind
/// from the same inputs at the same frame, so exactly one draws, and installing or removing a header or swapping the
/// indicator during a hold never moves it to the other slot (no identity change while it is drawn). An indicator whose
/// placement becomes an overlay's during a hold (`overlay:` changed by the app, a `.stretch` header installed: its band)
/// moves to the front slot, the only one that can draw it over the content or the header (a new view there on 15–16).
struct RefreshGroupLatched<Boxes: View>: View {
    let useGeometryGroup: Bool
    /// 15–16: whether to group, as of this frame (`RefreshPlacementEffect.fallbackGroup`); only the first one counts.
    let fallbackGroup: Bool
    /// The placement floats over the content (`RefreshIndicatorMath.base`: `overlay:` or the `.stretch` band).
    let overlay: Bool
    let layer: RefreshLayer
    let boxes: (RefreshIndicatorGroup.Kind) -> Boxes
    @StateObject private var latch = GroupLatch(note: "refresh.group")

    @ViewBuilder var body: some View {
        let kind = self.kind
        if RefreshLayerMath.draws(layer: layer, kind: kind, overlay: overlay) {
            #if DEBUG
            let _ = Self.noteSlot(layer)
            #endif
            boxes(kind)
        }
    }

    #if DEBUG
    /// The slot that drew the boxes last (`"front"` / `"behind"`), for the tests.
    @MainActor static func noteSlot(_ layer: RefreshLayer) {
        let v = layer == .behind ? "behind" : "front"
        if ZTronRenderCounters.notes["refresh.slot"] != v { ZTronRenderCounters.notes["refresh.slot"] = v }
    }
    #endif

    private var kind: RefreshIndicatorGroup.Kind {
        if useGeometryGroup, #available(iOS 17, *) { return .geometry }
        return latch.grouped(fallbackGroup) ? .compositing : .none
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
/// transform does (`ResizeMath.presented`). Render-time moves at the drawn size, identity outside an open resize and at
/// the committed size (a system rotation, whose frames Core Animation interpolates):
/// - `.region(origin:)` (the outer clip, laid out as the drawn viewport): the committed base (`origin`, also at rest)
///   and from it to the presented one, the inset change along the pull axis (`regionDelta`; a `.stretch` header's
///   `top0 + R` moves with `aci.top` by `ΔR`, a `.preserve` `.openGap` header's plain base too, D65; a `.preserve`
///   `.followContent` header's base, `top0`, stays).
/// - `.box(overlay:)` (inside the region): centred across the edge in the drawn width / height (`crossDelta`); along
///   the edge an overlay with its base (`delta`), in the gap the box's far edge on the content's DRAWN edge (`boxDelta`,
///   open item 21).
///
/// Both are drawn per frame only while no layout above them changes at the commit (`RefreshPlacementEffect`): on 15–16
/// an effect under a layout move made at the (unanimated) commit saw the committed size from then on (review of open
/// item 21; a04c279's cross move inside the region the same, 80.5 pt, which 8b9cbcc moved to the leaf).
///
/// Measured before the commit moved to the presented geometry (seam lab, `.stretch` hold, width 402 → 241 pt): the
/// indicator jumped 90 pt (`ΔR`) and 80 pt sideways in one frame at the commit. Open item 21 (a headerless hold, the
/// height animated to 0.4 top-pinned and back, easeInOut 1.2 s): the box moved with the base only, so it sat at the
/// committed pull while S7 slid the content over the gap: the indicator vanished at once on the way out and was drawn
/// at its final place over the content still sliding in (holdgap.py: 57 frames over the content, about 1.1 s; 27.0,
/// 17.5 and forced).
nonisolated struct RefreshResizeEffect: GeometryEffect {
    enum Part: Equatable { case region(origin: CGPoint), box(overlay: Bool) }

    let commit: ResizeCommit
    let edge: Edge
    /// Whether the edge's base is the adjusted inset (no header, `.stretch`, `.preserve` `.openGap`, the end edges) or stays
    /// (`.preserve` `.followContent`: `top0`).
    let baseFollowsInset: Bool
    var part: Part
    /// The content's drawing inputs (`.box` in the gap); nil outside an open resize.
    let draw: RefreshContentDraw?

    /// The region's committed base (`.region(origin:)`) animates as the layout it replaces did: a base the leaf moves in
    /// an animated transaction (an app's `withAnimation` inset change) is interpolated with it; the resize's commit is
    /// unanimated, so it lands at once there and `regionDelta` draws the move. The box has none.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            if case let .region(origin) = part { return AnimatablePair(origin.x, origin.y) }
            return .zero
        }
        set {
            if case .region = part { part = .region(origin: CGPoint(x: newValue.first, y: newValue.second)) }
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let d: CGPoint
        switch part {
        case let .region(origin):
            let r = Self.regionDelta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, size: size)
            d = CGPoint(x: origin.x + r.x, y: origin.y + r.y)
        case let .box(overlay):
            // Its frame is the drawn viewport (the region's).
            let b = Self.boxDelta(commit: commit, edge: edge, baseFollowsInset: baseFollowsInset, overlay: overlay,
                                  draw: draw, size: size)
            let c = Self.crossDelta(commit: commit, edge: edge, size: size)
            d = CGPoint(x: b.x + c.x, y: b.y + c.y)
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

    /// The box's move across the edge: centred in the drawn width / height (`delta`'s cross term). The region spans the
    /// drawn viewport across the edge and does not move across.
    static func crossDelta(commit: ResizeCommit, edge: Edge, size: CGSize) -> CGPoint {
        let d = delta(commit: commit, edge: edge, baseFollowsInset: true, size: size)
        return edge == .top || edge == .bottom ? CGPoint(x: d.x, y: 0) : CGPoint(x: 0, y: d.y)
    }

    /// The box's move along the edge inside the region (whose own move is `regionDelta`; across the edge the box moves by
    /// `crossDelta`). An overlay rests on its base (`delta`); in the gap the far edge is the content's edge drawn
    /// at this size, `contentEdge(size) − contentEdge(committed)` (the gap's far edge moves with the drawn content, less
    /// the bound's move where the base does not follow it: `.preserve` `.followContent`, whose gap ends at the header's
    /// top, the content's edge less `aci.top − top0`).
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
        return vertical ? finite(CGPoint(x: 0, y: along - region.y)) : finite(CGPoint(x: along - region.x, y: 0))
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

/// A geometry boundary around the built-in glyphs (open item 41). The glyph the cross-fade removes keeps the geometry it was
/// last laid out with until it has faded, resolved against the nearest geometry boundary above it; without one inside the
/// box that was the box's layer group (`RefreshIndicatorGroup`), which moves with the content: after a trigger below
/// `indicatorHeight` the fading arrow stayed where the trigger found it in the box and went on with the content, up to 8 pt
/// off the band's centre for the 0.15 s (seam lab 27.0, `rtrig40` / `rtrig30`), while its placement moved as it should.
/// Under this boundary the fading glyph follows its placement. An identity effect: nothing is moved or drawn differently.
nonisolated struct RefreshGlyphBoundary: GeometryEffect {
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform() }
}

/// The built-in look. `.system`: an arrow that turns with the pull, then the system spinner (the UIRefreshControl idiom);
/// `.default`: a ring that fills with the pull, then the spinner. The mode switch is animated by `modeAnimated`: the pull's
/// glyph and the spinner cross-fade in 0.15 s.
///
/// M8b-s8 s1 (open item 41): the cross-fade was never drawn, and neither was the look switch of a `beginRefreshing()` during a
/// retraction (`RefreshLookSwitch`): both landed in one frame (seam lab, every lane: the arrow at full intensity on one frame,
/// the spinner at full on the next; the begin's glyph from the band's far end to its centre and from opacity `p / L` to 1).
/// - A `Group` hands its modifiers to each of its children, so `.animation(_:value:)` sat on the branch itself and the branch
///   swap ran in the update's own transaction (no animation). The `ZStack` takes the modifier as one view: the swap runs in the
///   cross-fade (the glyphs' opacity transitions).
/// - SwiftUI resolves the opacity and the geometry animations of a view's ancestors at its leaves: the glyph a switch inserts
///   is a new leaf and started at the end values of the switch's animated opacity and shift (NSLog: the weight 1, 1, 1,
///   0.82 … 0.02; red test squares beside the glyph with the same animation, persistent leaves, faded over 8-10 frames). The
///   switch is now drawn frame by frame (`RefreshLookFade`): no animation of an ancestor to resolve, the inserted spinner
///   draws where the glyph is.
/// - Both glyphs are laid out in the same 24 pt square: in a stack that took the spinner's size, the arrow kept its place
///   as laid out before (its own height) through the cross-fade, 0.67-1 pt off the centre until it had faded (27.0, every
///   trigger).
/// - The glyphs sit under `RefreshGlyphBoundary`: the arrow the cross-fade removes follows its placement while it fades.
struct BuiltInRefreshIndicator: View {
    let refresh: ZTronRefreshState
    let edge: Edge
    /// The spinner stays although the refresh is over: the indicator is going back with the content.
    var spinner = false

    var body: some View {
        ZStack {
            if refresh.modeAnimated == .refreshing || spinner {
                ProgressView()
                    .frame(width: Self.side, height: Self.side)
                    .transition(.opacity)
            } else {
                pullGlyph
                    .frame(width: Self.side, height: Self.side)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: refresh.modeAnimated)
        .modifier(RefreshGlyphBoundary())
    }

    /// The square both glyphs are laid out in (the `.default` ring's; the spinner is 20 pt, the arrow under it).
    private static let side: CGFloat = 24

    /// The pull's look: the arrow (`.system`) or the ring (`.default`), turned or filled by the drag position.
    @ViewBuilder private var pullGlyph: some View {
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
