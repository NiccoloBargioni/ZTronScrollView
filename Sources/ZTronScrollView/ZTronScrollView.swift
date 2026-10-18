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
        return ScrollContainer(axes: axes, state: state, content: content, zoomLimits: zoomLimits, doubleTap: doubleTap)
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
}

/// Owns the state created by `init(_:showsIndicators:content:)`; created once per view identity.
@MainActor
final class StateHolder: ObservableObject {
    let state = ZTronScrollState()
}

/// content -> size measurement -> content space -> TransformHost -> layout host -> viewport space, clip, hit shape.
struct ScrollContainer<Content: View>: View {
    let axes: Axis.Set
    let state: ZTronScrollState
    let content: Content
    let zoomLimits: ZoomLimits?
    let doubleTap: DoubleTapZoom?
    @Environment(\.ztronZoomLimits) private var envLimits
    @Environment(\.ztronDoubleTapZoom) private var envDoubleTap
    @StateObject private var coordinator: PanCoordinator

    init(axes: Axis.Set, state: ZTronScrollState, content: Content, zoomLimits: ZoomLimits? = nil,
         doubleTap: DoubleTapZoom? = nil) {
        self.zoomLimits = zoomLimits
        self.doubleTap = doubleTap
        self.axes = axes
        self.state = state
        self.content = content
        _coordinator = StateObject(wrappedValue: PanCoordinator(state: state, axes: axes))
    }

    private var effectiveLimits: ZoomLimits { zoomLimits ?? envLimits ?? ZoomLimits() }

    var body: some View {
        content
            .modifier(ContentSizeMeasure(state: state))
            .modifier(NamedSpaceModifier(name: "ztronScroll.content", useNew: state.usesNamedCoordinateSpace))
            .modifier(TransformHost(state: state))
            .modifier(ContentLayoutHost(axes: axes, useLayout: state.usesLayoutProtocol))
            .modifier(NamedSpaceModifier(name: "ztronScroll.viewport", useNew: state.usesNamedCoordinateSpace))
            .modifier(ViewportObserver(state: state))
            .background(FrameClockDriver(state: state))
            .clipped()
            .contentShape(Rectangle())
            .modifier(PanGestureAdapter(coordinator: coordinator, axes: axes, doubleTap: doubleTap ?? envDoubleTap))
            .onAppear { state.zoomLimits = effectiveLimits }
            .onChangeCompat(of: effectiveLimits) { state.zoomLimits = $0 }
    }
}
