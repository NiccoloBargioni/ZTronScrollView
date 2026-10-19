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
    @StateObject private var holder = StateHolder()

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.externalState = nil
        self.content = content()
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
                               nestedPolicy: nestedPolicy)
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
    @Environment(\.ztronZoomLimits) private var envLimits
    @Environment(\.ztronDoubleTapZoom) private var envDoubleTap
    @StateObject private var coordinator: PanCoordinator

    init(axes: Axis.Set, state: ZTronScrollState, content: Content, zoomLimits: ZoomLimits? = nil,
         doubleTap: DoubleTapZoom? = nil, nestedPolicy: ZTronNestedScrollPolicy? = nil) {
        self.zoomLimits = zoomLimits
        self.doubleTap = doubleTap
        self.nestedPolicy = nestedPolicy
        self.axes = axes
        self.state = state
        self.content = content
        state.scrollAxes = axes
        _coordinator = StateObject(wrappedValue: PanCoordinator(state: state, axes: axes))
    }

    private var effectiveLimits: ZoomLimits { zoomLimits ?? envLimits ?? ZoomLimits() }

    var body: some View {
        let edges = state.contentInsetAdjustmentBehavior.edges(for: axes)
        // Container role (NESTED §3): the ZTronScrollViews in the content register with this view's arbiter, with
        // frames in a named space on the content (cold: they do not change while this view scrolls). Constant per
        // identity, so the environment write never re-evaluates content bodies.
        let nested = coordinator.nestedArbiter
        return content
            .environment(\.scrollArbiter, nested)
            .modifier(ContentSizeMeasure(state: state))
            .modifier(NamedSpaceModifier(name: "ztronScroll.content", useNew: state.usesNamedCoordinateSpace))
            .modifier(NamedSpaceModifier(name: nested.coordinateSpaceName, useNew: state.usesNamedCoordinateSpace))
            .modifier(ContentLayoutHost(axes: axes, useLayout: state.usesLayoutProtocol))
            .modifier(TransformHost(state: state, axes: axes))
            .modifier(NamedSpaceModifier(name: "ztronScroll.viewport", useNew: state.usesNamedCoordinateSpace))
            .ignoresSafeArea(.all, edges: edges)
            .modifier(ViewportObserver(state: state, edges: edges))
            .background(FrameClockDriver(state: state))
            .clipped()
            .contentShape(Rectangle())
            .modifier(PanGestureAdapter(coordinator: coordinator, axes: axes, doubleTap: doubleTap ?? envDoubleTap,
                                        nestedPolicy: nestedPolicy))
            .onAppear { state.zoomLimits = effectiveLimits }
            .onChangeCompat(of: effectiveLimits) { state.zoomLimits = $0 }
    }
}
