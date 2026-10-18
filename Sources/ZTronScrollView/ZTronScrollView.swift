import SwiftUI
import ZTronScrollPhysics

/// Pure-SwiftUI scroll view. M2: render path only (offset / zoom transform, frame clock, programmatic commands);
/// gestures arrive in M3. The container's own body never reads hot values (SPEC S4).
public struct ZTronScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let externalState: ZTronScrollState?
    private let content: Content
    private var zoomLimits = ZoomLimits()
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
        return ScrollContainer(axes: axes, state: state, content: content, zoomLimits: zoomLimits)
            .environment(\.ztronScrollState, state)
    }
}

extension ZTronScrollView {
    /// Zoom limits, absolute or relative to the content's fit / fill scale (recomputed on resize). Zooming is enabled
    /// iff max > min; the default is 1...1, as in UIKit.
    public func zoomRange(min: ZTronZoomScale, max: ZTronZoomScale) -> Self {
        func bound(_ z: ZTronZoomScale) -> ZoomBound {
            switch z {
            case let .absolute(v): return .absolute(v)
            case .fit: return .fit
            case .fill: return .fill
            }
        }
        var copy = self
        copy.zoomLimits = ZoomLimits(min: bound(min), max: bound(max))
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
    let zoomLimits: ZoomLimits
    @StateObject private var coordinator: PanCoordinator

    init(axes: Axis.Set, state: ZTronScrollState, content: Content, zoomLimits: ZoomLimits = ZoomLimits()) {
        self.zoomLimits = zoomLimits
        self.axes = axes
        self.state = state
        self.content = content
        _coordinator = StateObject(wrappedValue: PanCoordinator(state: state, axes: axes))
    }

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
            .modifier(PanGestureAdapter(coordinator: coordinator, axes: axes))
            .onAppear { state.zoomLimits = zoomLimits }
            .onChangeCompat(of: zoomLimits) { state.zoomLimits = $0 }
    }
}
