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
    /// The part of the viewport the indicator may draw in (the gap the pull opened, or everything for an overlay).
    var clip: CGRect
    var opacity: Double

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
    ///   - pull: signed displayed overscroll past the edge, against the bounds without the hold (`RefreshMath.signedPull`).
    ///   - length: the indicator's thickness along the pull axis (`configuration.indicatorHeight`).
    ///   - base: `adjustedContentInset − refreshHold` per edge.
    ///   - header: the live scaling header height counted onto the top base (0 until M8b-3).
    /// - Returns: `nil` when nothing of the indicator is inside its clip.
    static func placement(edge: Edge, style: ZTronRefreshStyle, overlay: Bool, refreshing: Bool, dragPosition: CGFloat,
                          pull: CGFloat, length: CGFloat, viewport: CGSize, base: EdgeInsets,
                          header: CGFloat = 0) -> RefreshPlacement? {
        let p = max(0, pull)
        let L = max(0, length)
        let vertical = edge == .top || edge == .bottom
        let along = vertical ? viewport.height : viewport.width
        let crossStart = vertical ? base.leading : base.top
        let crossEnd = vertical ? viewport.width - base.trailing : viewport.height - base.bottom
        guard crossEnd > crossStart, along > 0 else { return nil }
        let b: CGFloat
        switch edge {
        case .top: b = base.top + header
        case .bottom: b = base.bottom
        case .leading: b = base.leading
        case .trailing: b = base.trailing
        }
        // The centre of the indicator and the end of its clip, along d.
        let center: CGFloat
        let clipEnd: CGFloat
        let opacity: Double
        if overlay {
            // Floats over the content: slides in from outside the base with the pull, sits at L when refreshing.
            center = -L / 2 + (refreshing ? L : min(p, L))
            clipEnd = max(0, along - b)
            opacity = refreshing ? 1 : Double(L > 0 ? min(1, p / L) : 1)
        } else {
            clipEnd = p
            switch style {
            case .system:
                center = p / 2                                    // centred in the gap, as UIRefreshControl
                opacity = refreshing ? 1 : Double(max(0, min(1, dragPosition)))
            case .default:
                center = p - L / 2                                // glued to the content's edge, following the pull 1:1
                opacity = 1
            }
        }
        guard clipEnd > 0, center + L / 2 > 0, center - L / 2 < clipEnd else { return nil }
        func interval(_ d0: CGFloat, _ d1: CGFloat) -> (CGFloat, CGFloat) {
            switch edge {
            case .top, .leading: return (b + d0, b + d1)
            case .bottom, .trailing: return (along - b - d1, along - b - d0)
            }
        }
        let f = interval(center - L / 2, center + L / 2)
        let c = interval(0, clipEnd)
        func rect(_ a: (CGFloat, CGFloat)) -> CGRect {
            vertical
                ? CGRect(x: crossStart, y: a.0, width: crossEnd - crossStart, height: a.1 - a.0)
                : CGRect(x: a.0, y: crossStart, width: a.1 - a.0, height: crossEnd - crossStart)
        }
        return RefreshPlacement(frame: rect(f), clip: rect(c), opacity: opacity)
    }
}

extension RefreshIndicatorMath {
    /// The edge bases (`adjustedContentInset − refreshHold`) and whether the indicator floats over the content. With a
    /// scaling header (M8b-3): under `.preserve` the gap opens below the resting header, which the base already counts;
    /// under `.stretch` there is no gap, so the top indicator floats over the stretched band (`top0 + R`), overlay placement
    /// whatever `overlay:` says (SPEC S10 "Refresh with the header").
    static func base(edge: Edge, metrics m: ScrollMetrics, overlay: Bool) -> (EdgeInsets, Bool) {
        let aci = m.adjustedContentInset, hold = m.refreshHold
        var base = EdgeInsets(top: aci.top - hold.top, leading: aci.leading - hold.leading,
                              bottom: aci.bottom - hold.bottom, trailing: aci.trailing - hold.trailing)
        guard edge == .top, let band = HeaderMath.stretchBandTop(m) else { return (base, overlay) }
        base.top = band
        return (base, true)
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

    var body: some View {
        ChromeLeaf(state, channels: [.offset, .metrics]) { sample in
            let m = sample.metrics
            let pull = RefreshMath.signedPull(edge: edge, offset: sample.offset, zoom: sample.zoom, metrics: m,
                                              alignment: state.contentAlignment)
            let (base, overlay) = RefreshIndicatorMath.base(edge: edge, metrics: m, overlay: spec.overlay)
            indicator.modifier(RefreshPlacementEffect(
                pull: pull, edge: edge, style: spec.style, overlay: overlay, length: spec.configuration.indicatorHeight,
                refreshing: refresh.mode == .refreshing || (retract == .spinner && !overlay), refresh: refresh, retract: retract,
                viewport: m.viewportSize, base: base))
        }
    }

    @ViewBuilder private var indicator: some View {
        if let custom = spec.indicator {
            custom(binding)
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

/// Places the indicator for one pull and clips it to the gap. `pull` is the animatable data. A reset that SwiftUI animates
/// (`resetAnimation: .swiftUI`, the default) jumps the state's offset while the content's drawing is interpolated; this modifier
/// is interpolated in the same transaction, so the indicator goes back with the content instead of vanishing on the first frame.
/// Every other frame (a finger, a release on the clock) just evaluates it with the pull of that frame.
private nonisolated struct RefreshPlacementEffect: ViewModifier, Animatable {
    var pull: CGFloat
    let edge: Edge
    let style: ZTronRefreshStyle
    let overlay: Bool
    let length: CGFloat
    let refreshing: Bool
    let refresh: ZTronRefreshState
    let retract: RefreshEngine.RetractLook?
    let viewport: CGSize
    let base: EdgeInsets

    var animatableData: CGFloat {
        get { pull }
        set { pull = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let placement = RefreshIndicatorMath.placement(
            edge: edge, style: style, overlay: overlay, refreshing: refreshing, dragPosition: refresh.dragPosition, pull: pull,
            length: length, viewport: viewport, base: base)
        #if DEBUG
        let _ = RefreshTrace.leaf(edge: edge, pull: pull, refresh: refresh, retract: retract, placement: placement)
        #endif
        ZStack(alignment: .topLeading) {
            if let placement {
                content
                    .frame(width: placement.frame.width, height: placement.frame.height)
                    .opacity(placement.opacity)
                    .position(x: placement.frame.midX, y: placement.frame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RefreshClip(rect: placement?.clip ?? .zero))
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

struct RefreshClip: Shape {
    var rect: CGRect
    func path(in _: CGRect) -> Path { Path(rect) }
}

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
