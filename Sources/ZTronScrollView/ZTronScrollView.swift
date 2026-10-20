import SwiftUI
import ZTronScrollPhysics

/// Pure-SwiftUI scroll view. M2: render path only (offset / zoom transform, frame clock, programmatic commands);
/// gestures arrive in M3. The container's own body never reads hot values (SPEC S4).
public struct ZTronScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let externalState: ZTronScrollState?
    private let content: Content
    private var zoomLimits: ZoomLimits?
    private var doubleTap: DoubleTapZoom?
    private var nestedPolicy: ZTronNestedScrollPolicy?
    var config = ScrollViewConfig()
    /// Chrome members (indicators, M8): the `ztron…` twins carry the same settings in the environment.
    var chrome = ChromeConfig()
    @StateObject private var holder = StateHolder()

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.externalState = nil
        self.content = content()
        if !showsIndicators { chrome.showsIndicators = false }
    }

    public init(_ axes: Axis.Set = .vertical, state: ZTronScrollState, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = true
        self.externalState = state
        self.content = content()
    }

    public var body: some View {
        let state = externalState ?? holder.state
        return ScrollContainer(axes: axes, state: state, content: content, zoomLimits: zoomLimits, doubleTap: doubleTap,
                               nestedPolicy: nestedPolicy, config: config, chrome: chrome)
            .environment(\.ztronScrollState, state)
    }
}

extension ZTronScrollView {
    /// Zoom limits, absolute or relative to the content's fit / fill scale (recomputed on resize). Zooming is enabled
    /// iff max > min; the default is 1...1, as in UIKit.
    public func zoomRange(min: ZTronZoomScale, max: ZTronZoomScale) -> Self {
        var copy = self
        copy.zoomLimits = ZoomLimits(min: min.bound, max: max.bound)
        return copy
    }

    /// Double tap toggles between the minimum scale and `scale` (default: the maximum), around the tap. Off by default.
    public func doubleTapToZoom(_ enabled: Bool = true, scale: ZTronZoomScale? = nil) -> Self {
        var copy = self
        copy.doubleTap = enabled ? DoubleTapZoom(scale: scale) : nil
        return copy
    }

    /// How this view yields a drag to the `ZTronScrollView` (or ScrollArbitration container) that holds it; see
    /// `ZTronNestedScrollPolicy`. Default `.automatic` (UIScrollView parity); `.independent` opts out.
    public func nestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> Self {
        var copy = self
        copy.nestedPolicy = policy
        return copy
    }
}

/// Owns the state created by `init(_:showsIndicators:content:)`; created once per view identity.
@MainActor
final class StateHolder: ObservableObject {
    let state = ZTronScrollState()
}

/// content -> size measurement -> content space -> layout host -> TransformHost (the viewport-sized effect, M5 C1)
/// -> viewport space -> safe-area policy -> observer, clip, hit shape.
struct ScrollContainer<Content: View>: View {
    let axes: Axis.Set
    let state: ZTronScrollState
    let content: Content
    let zoomLimits: ZoomLimits?
    let doubleTap: DoubleTapZoom?
    let nestedPolicy: ZTronNestedScrollPolicy?
    let config: ScrollViewConfig
    let chrome: ChromeConfig
    @Environment(\.ztronZoomLimits) private var envLimits
    @Environment(\.ztronDoubleTapZoom) private var envDoubleTap
    @Environment(\.ztronScrollConfig) private var envConfig
    @Environment(\.ztronProxyScope) private var proxyScope
    @StateObject private var coordinator: PanCoordinator
    @StateObject private var observerStore = ObserverStore()

    init(axes: Axis.Set, state: ZTronScrollState, content: Content, zoomLimits: ZoomLimits? = nil,
         doubleTap: DoubleTapZoom? = nil, nestedPolicy: ZTronNestedScrollPolicy? = nil,
         config: ScrollViewConfig = ScrollViewConfig(), chrome: ChromeConfig = ChromeConfig()) {
        self.zoomLimits = zoomLimits
        self.chrome = chrome
        self.doubleTap = doubleTap
        self.nestedPolicy = nestedPolicy
        self.config = config
        self.axes = axes
        self.state = state
        self.content = content
        state.scrollAxes = axes
        _coordinator = StateObject(wrappedValue: PanCoordinator(state: state, axes: axes))
    }

    private var effectiveLimits: ZoomLimits { zoomLimits ?? envLimits ?? ZoomLimits() }

    var body: some View {
        let edges = state.contentInsetAdjustmentBehavior.edges(for: axes)
        // Member, else environment twin (M6): a cold write, never observed.
        state.targetBehavior = config.behavior ?? envConfig.behavior
        // Anchors and the position binding (M6 s3): cold writes; the binding's value is read here so a new one re-evaluates
        // this view and nothing in the content.
        state.initialOffsetAnchor = config.anchor(.initialOffset, else: envConfig)
        state.sizeChangesAnchor = config.anchor(.sizeChanges, else: envConfig)
        state.alignmentAnchor = config.anchor(.alignment, else: envConfig)
        let positionBinding = config.position ?? envConfig.position
        state.positionDriver.bind(positionBinding)
        let position = positionBinding?.read()
        let ticket = state.positionDriver.ticket(for: position)
        // Container role (NESTED §3): the ZTronScrollViews in the content register with this view's arbiter, with
        // frames in a named space on the content (cold: they do not change while this view scrolls). Constant per
        // identity, so the environment write never re-evaluates content bodies.
        let nested = coordinator.nestedArbiter
        let observerBoxes = observerStore.boxes(for: envConfig.observers + config.observers)
        return content
            .environment(\.ztronTargetRegistry, state.targets)
            .environment(\.scrollArbiter, nested)
            .modifier(ContentSizeMeasure(state: state))
            .modifier(NamedSpaceModifier(name: "ztronScroll.content", useNew: state.usesNamedCoordinateSpace))
            .modifier(NamedSpaceModifier(name: nested.coordinateSpaceName, useNew: state.usesNamedCoordinateSpace))
            .modifier(ContentLayoutHost(axes: axes, useLayout: state.usesLayoutProtocol))
            .modifier(TransformHost(state: state, axes: axes))
            .modifier(NamedSpaceModifier(name: "ztronScroll.viewport", useNew: state.usesNamedCoordinateSpace))
            .overlay(ScrollIndicatorsOverlay(state: state, member: chrome))   // chrome leaves: the viewport's own frame (M8)
            .ignoresSafeArea(.all, edges: edges)
            .modifier(ViewportObserver(state: state, edges: edges))
            .modifier(MeasurementIsolation())
            .background(FrameClockDriver(state: state))
            .background(TargetEnvironmentCapture(state: state))
            .background(Group { if let proxyScope { ProxyFrameReporter(scope: proxyScope, state: state) } })
            .clipped()
            .contentShape(Rectangle())
            .modifier(PanGestureAdapter(coordinator: coordinator, axes: axes, doubleTap: doubleTap ?? envDoubleTap,
                                        nestedPolicy: nestedPolicy))
            .modifier(ObserverRegistration(state: state, boxes: observerBoxes))
            .onAppear { state.zoomLimits = effectiveLimits }
            .modifier(PositionTicket(ticket: ticket))
            .transaction { state.positionDriver.noteTransaction($0) }
            .onAppear { state.positionDriver.receive(position) }
            .onChangeCompat(of: position) { state.positionDriver.receive($0) }
            .onAppear { proxyScope?.attach(state) }
            .onDisappear { proxyScope?.detach(state) }
            .onChangeCompat(of: effectiveLimits) { state.zoomLimits = $0 }
    }
}
