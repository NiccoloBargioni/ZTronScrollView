import SwiftUI
import ScrollArbitration
import ZTronScrollPhysics

/// Thin SwiftUI layer for the pinch (design M4 §5): MagnifyGesture (17+) / MagnificationGesture (15-16) become
/// `PinchEvent`s for the coordinator. Pinches never ask the arbiter. No logic here.
enum PinchGestureAdapter {
    /// DEBUG launch argument `-ZTronPinchCentroid startOnly|dragFollow` (iOS 15-17 estimate comparison, M4-s2).
    static var dragFollow: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ZTronPinchCentroid"), i + 1 < args.count { return args[i + 1] != "startOnly" }
        #endif
        return true
    }

    @MainActor
    static func gesture(coordinator: PanCoordinator, observer: CatchObserverState) -> AnyGesture<Void> {
        let spatial = coordinator.state.usesSpatialEvents
        // iOS 15-16 (D31): the gesture stays attached for recognition only; the UIKit observer feeds the pinch.
        let uikit = coordinator.state.usesUIKitTouchObserver
        let began = Began()
        let onChange: @MainActor (CGFloat, CGPoint?) -> Void = { [coordinator] magnification, start in
            guard !uikit else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if !began.value {
                began.value = true
                let c: CGPoint? = spatial ? observer.centroid : (start ?? observer.panStart)
                coordinator.handlePinch(.began(centroid: c, time: now))
            }
            coordinator.handlePinch(.changed(magnification: magnification, centroid: spatial ? observer.centroid : nil,
                                             time: now))
        }
        let onEnd: @MainActor () -> Void = { [coordinator] in
            guard !uikit else { return }
            began.value = false
            let now = Date().timeIntervalSinceReferenceDate
            // 18+: the magnify gesture ends when one finger lifts. If the observer still sees that one finger, this IS
            // the one-finger hand-off (D23), whichever of the two callbacks SwiftUI delivers first; the observer's own
            // count change then finds the pinch already released and does nothing.
            if spatial, observer.activeCount == 1, let c = observer.centroid {
                coordinator.handlePinch(.fingerCountChanged(count: 1, remaining: c, time: now))
            }
            // Always the gesture's own end too: it closes the trailing-sample window (D25) on an already released
            // session without effects.
            coordinator.handlePinch(.ended(time: now))
        }
        if #available(iOS 17, *), coordinator.state.usesMagnifyGesture {
            return AnyGesture(MagnifyGesture()
                .onChanged { v in MainActor.assumeIsolated { onChange(v.magnification, v.startLocation) } }
                .onEnded { _ in MainActor.assumeIsolated { onEnd() } }
                .map { _ in () })
        }
        return AnyGesture(MagnificationGesture()
            .onChanged { m in MainActor.assumeIsolated { onChange(m, nil) } }
            .onEnded { _ in MainActor.assumeIsolated { onEnd() } }
            .map { _ in () })
    }

    final class Began: @unchecked Sendable { var value = false }

    /// Opt-in double tap; the location comes from SpatialTapGesture (16+), else the last touch-down.
    @MainActor
    static func doubleTap(coordinator: PanCoordinator, observer: CatchObserverState, config: DoubleTapZoom)
        -> AnyGesture<Void> {
        if #available(iOS 16, *) {
            return AnyGesture(SpatialTapGesture(count: 2, coordinateSpace: .local)
                .onEnded { v in MainActor.assumeIsolated { coordinator.doubleTap(at: v.location, scale: config.scale) } }
                .map { _ in () })
        }
        return AnyGesture(TapGesture(count: 2)
            .onEnded { MainActor.assumeIsolated {
                coordinator.doubleTap(at: observer.panStart ?? coordinator.state.makeZoomGeometry().visibleCenter,
                                      scale: config.scale)
            } }
            .map { _ in () })
    }
}

/// Attaches the pinch (and the optional double tap) next to the pan; always simultaneous so pan and pinch compose.
struct PinchGestureAttach: ViewModifier {
    let pinch: AnyGesture<Void>
    let doubleTap: AnyGesture<Void>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            let n = scrollArbitrationGestureName
            if let doubleTap {
                content.simultaneousGesture(pinch, name: n).simultaneousGesture(doubleTap, name: n)
            } else {
                content.simultaneousGesture(pinch, name: n)
            }
        } else {
            if let doubleTap {
                content.simultaneousGesture(pinch).simultaneousGesture(doubleTap)
            } else {
                content.simultaneousGesture(pinch)
            }
        }
    }
}

extension PanCoordinator {
    /// Double tap: from the minimum scale zoom to `scale` (default maximum) around the tap, else back to the minimum.
    func doubleTap(at location: CGPoint, scale: ZTronZoomScale?) {
        let min = state.minimumZoomScale, max = state.maximumZoomScale
        guard state.isZoomEnabled, !isPinching else { return }
        let current = state.zoomScale
        if abs(current - min) <= 0.01 * min {
            var target = max
            if case let .absolute(v)? = scale { target = Swift.min(Swift.max(v, min), max) }
            guard target > 0 else { return }
            let s = state.peek
            let g = makeZoomGeometry()
            let u = ZoomSolver.contentPoint(under: location, offset: s.presentationOffset, scale: current, geometry: g)
            let size = CGSize(width: s.metrics.viewportSize.width / target, height: s.metrics.viewportSize.height / target)
            state.zoom(to: CGRect(x: u.x - size.width / 2, y: u.y - size.height / 2, width: size.width, height: size.height),
                       animated: true)
        } else {
            state.setZoomScale(min, animated: true)
        }
    }
}
