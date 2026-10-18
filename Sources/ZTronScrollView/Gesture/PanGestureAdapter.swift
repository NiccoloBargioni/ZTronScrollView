import SwiftUI
import ScrollArbitration

/// How the pan and the observer attach to the viewport. The default is chosen empirically per OS (design §8).
enum PanGestureMode: String {
    case gesture, simultaneous, high

    /// DEBUG launch argument `-ZTronPanGestureMode <gesture|simultaneous|high>`.
    static var current: PanGestureMode {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ZTronPanGestureMode"), i + 1 < args.count,
           let m = PanGestureMode(rawValue: args[i + 1]) { return m }
        #endif
        return .simultaneous
    }
}

/// Thin SwiftUI layer: builds the gestures, forwards `PanEvent`s to the coordinator. No logic.
struct PanGestureAdapter: ViewModifier {
    @ObservedObject var coordinator: PanCoordinator
    let axes: Axis.Set
    let mode = PanGestureMode.current
    @Environment(\.ztronScrollIsEnabled) private var ownEnabled
    @Environment(\.ztronHorizontalBounce) private var bounceX
    @Environment(\.ztronVerticalBounce) private var bounceY
    @Environment(\.displayScale) private var displayScale
    @State private var observer = CatchObserverState()
    @GestureState private var panActive: Bool

    init(coordinator: PanCoordinator, axes: Axis.Set) {
        self.coordinator = coordinator
        self.axes = axes
        // The reset runs when SwiftUI ends or cancels the pan; a cancelled one never calls onEnded.
        _panActive = GestureState(wrappedValue: false, reset: { [weak coordinator] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { coordinator?.cancelIfActive() } }
        })
    }

    func body(content: Content) -> some View {
        coordinator.axes = axes
        coordinator.settings.isScrollEnabled = ownEnabled
        coordinator.settings.bounceX = bounceX.physics
        coordinator.settings.bounceY = bounceY.physics
        coordinator.settings.displayScale = displayScale
        let send: @MainActor (PanEvent) -> Void = { [coordinator] in coordinator.handle($0) }
        return content
            .modifier(NativeEnabledBridge(coordinator: coordinator))
            .modifier(ArbitrationRegistration(coordinator: coordinator))
            .modifier(GestureAttach(mode: mode, pan: pan(send: send), observer: observerGestureBox(send: send)))
    }

    private func pan(send: @escaping @MainActor (PanEvent) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($panActive) { _, active, _ in active = true }
            .onChanged { v in
                MainActor.assumeIsolated {
                    send(.dragChanged(translation: v.translation, startLocation: v.startLocation,
                                      time: v.time.timeIntervalSinceReferenceDate))
                }
            }
            .onEnded { v in
                MainActor.assumeIsolated {
                    send(.dragEnded(translation: v.translation, time: v.time.timeIntervalSinceReferenceDate,
                                    fallbackVelocity: Self.velocity(v)))
                }
            }
    }

    private static func velocity(_ v: DragGesture.Value) -> CGVector? {
        if #available(iOS 17, *) { return CGVector(dx: v.velocity.width, dy: v.velocity.height) }
        return nil
    }

    private func observerGestureBox(send: @escaping @MainActor (PanEvent) -> Void) -> AnyGesture<Void> {
        let obs = observer
        if #available(iOS 18, *), CatchObserver.usesSpatial {
            let now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
            return AnyGesture(SpatialCatchGesture.gesture(observer: obs, send: send, now: now).map { _ in () })
        }
        return AnyGesture(DragCatchGesture.gesture(observer: obs, send: send).map { _ in () })
    }
}

/// Attaches pan and observer according to `mode`.
struct GestureAttach<P: Gesture>: ViewModifier {
    let mode: PanGestureMode
    let pan: P
    let observer: AnyGesture<Void>

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            // Named so a pager's UIKit pan can run alongside (SPEC S12, S16).
            let n = scrollArbitrationGestureName
            switch mode {
            case .simultaneous:
                content.simultaneousGesture(observer, name: n).simultaneousGesture(pan, name: n)
            case .gesture:
                content.gesture(observer.simultaneously(with: pan), name: n)
            case .high:
                content.highPriorityGesture(observer.simultaneously(with: pan), name: n)
            }
        } else {
            switch mode {
            case .simultaneous:
                content.simultaneousGesture(observer).simultaneousGesture(pan)
            case .gesture:
                content.gesture(observer.simultaneously(with: pan))
            case .high:
                content.highPriorityGesture(observer.simultaneously(with: pan))
            }
        }
    }
}

/// Mirrors SwiftUI's `isScrollEnabled` (16+) into the coordinator; a no-op below.
struct NativeEnabledBridge: ViewModifier {
    let coordinator: PanCoordinator

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.modifier(NativeScrollEnabledReader { enabled in
                coordinator.nativeScrollEnabled = enabled
            })
        } else {
            content
        }
    }
}
