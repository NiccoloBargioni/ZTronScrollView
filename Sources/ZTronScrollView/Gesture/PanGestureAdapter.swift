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
    var doubleTap: DoubleTapZoom?
    /// `ZTronScrollView.nestedScrollPolicy(_:)` (member); nil = the environment twin.
    var nestedPolicy: ZTronNestedScrollPolicy?
    let mode = PanGestureMode.current
    @Environment(\.ztronScrollIsEnabled) private var ownEnabled
    @Environment(\.ztronHorizontalBounce) private var bounceX
    @Environment(\.ztronVerticalBounce) private var bounceY
    /// `View.ztronScrollYieldsToSheet(_:)`: while true every gesture below attaches with `GestureMask.subviews`.
    @Environment(\.ztronYieldsToSheet) private var yields
    /// `View.ztronScrollPickersAbsorbDrags(_:)` (spike PICKER-s1): installs the probe-only window recognizer on 17+.
    @Environment(\.ztronPickersAbsorbDrags) private var pickersAbsorb
    /// The outermost enclosing `ZTronScrollView`'s probe hub; nil when this view is the outermost (PICKER-s2).
    @Environment(\.ztronPickerProbeHub) private var outerProbeHub
    @Environment(\.displayScale) private var displayScale
    @State private var observer = CatchObserverState()
    /// Fallback observer gating (iOS < 28, D34, D37): the zero-distance drag steals touches from UIKit-backed controls, so
    /// it is attached only while the content moves without a finger, or while a touch it saw is still down.
    @State private var armed = CatchArming()
    @GestureState private var panActive: Bool

    init(coordinator: PanCoordinator, axes: Axis.Set, doubleTap: DoubleTapZoom? = nil,
         nestedPolicy: ZTronNestedScrollPolicy? = nil) {
        self.coordinator = coordinator
        self.axes = axes
        self.doubleTap = doubleTap
        self.nestedPolicy = nestedPolicy
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
        coordinator.yieldsToSheet = yields
        coordinator.pickersAbsorbDrags = pickersAbsorb
        let arming = armed
        let send: @MainActor (PanEvent) -> Void = { [coordinator] event in
            coordinator.handle(event)
            if case .touchesEnded = event { arming.touchEnded() }
        }
        // iOS 15-16 (D31): the window recognizer replaces the SwiftUI observer gesture, so nothing is armed or gated.
        let uikit = coordinator.state.usesUIKitTouchObserver
        let gated = !coordinator.state.usesSpatialEvents && !uikit
        // 17+: only the outermost view installs the window probe; a nested one joins its hub (an anchor inside a nested
        // view breaks that view's drags, PICKER-s2). 15-16: every view reports through its own D31 recognizer.
        let reportsPickers = pickersAbsorb && (uikit || outerProbeHub == nil)
        if pickersAbsorb, !uikit, let outerProbeHub { outerProbeHub.join(coordinator) }
        let obs = observer
        let tap = doubleTap.map { PinchGestureAdapter.doubleTap(coordinator: coordinator, observer: obs, config: $0) }
        return content
            .modifier(NativeEnabledBridge(coordinator: coordinator))
            .modifier(ArbitrationRegistration(coordinator: coordinator, policy: nestedPolicy))
            .modifier(GatedGestureAttach(mode: mode, pan: pan(send: send),
                                         observer: uikit ? nil : observerGestureBox(send: send), arming: arming, gated: gated,
                                         yields: yields))
            .modifier(PinchGestureAttach(pinch: PinchGestureAdapter.gesture(coordinator: coordinator, observer: observer),
                                         doubleTap: tap, yields: yields))
            .modifier(CatchArmingProbe(state: gated ? coordinator.state : nil, arming: arming, observer: observer))
            .modifier(UIKitObserverAttach(enabled: uikit || reportsPickers, feedsCore: uikit,
                                          reportsPickers: reportsPickers, coordinator: coordinator, catchState: observer))
            .onChangeCompat(of: yields) { yielding in
                // The masked gestures are cancelled by SwiftUI without `onEnded`: forget what they left behind, then end
                // a sequence in flight like a cancelled touch.
                guard yielding else { return }
                observer.reset()
                arming.touchEnded()
                coordinator.cancelForSheetYield()
            }
    }

    private func pan(send: @escaping @MainActor (PanEvent) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($panActive) { _, active, _ in active = true }
            .onChanged { v in
                MainActor.assumeIsolated {
                    observer.panStart = v.startLocation
                    send(.dragChanged(translation: v.translation, startLocation: v.startLocation,
                                      time: v.time.timeIntervalSinceReferenceDate))
                    // 15-17 centroid estimate follows the drag (spatial events carry the true centroid on 18+).
                    if !coordinator.state.usesSpatialEvents, !coordinator.state.usesUIKitTouchObserver, PinchGestureAdapter.dragFollow,
                       coordinator.isPinching {
                        coordinator.handlePinch(.panTranslation(v.translation, time: v.time.timeIntervalSinceReferenceDate))
                    }
                }
            }
            .onEnded { v in
                MainActor.assumeIsolated {
                    observer.panStart = nil
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
        if #available(iOS 18, *), coordinator.state.usesSpatialEvents {
            let now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
            let c = coordinator
            return AnyGesture(SpatialCatchGesture.gesture(
                observer: obs, send: send,
                pinch: { c.handlePinch($0) },
                synthesize: { c.synthesizePan(location: $0, time: $1) }, now: now).map { _ in () })
        }
        return AnyGesture(DragCatchGesture.gesture(observer: obs, send: send).map { _ in () })
    }
}

/// Attaches pan and observer according to `mode`. `observer` is nil on the iOS 15-16 UIKit observer path (D31).
/// `yields` (`ztronScrollYieldsToSheet`) keeps the modifier chain and flips only the mask / `isEnabled`, so the content's
/// identity and body are untouched: `.subviews` disables the gesture and leaves the content's own controls working.
struct GestureAttach<P: Gesture>: ViewModifier {
    let mode: PanGestureMode
    let pan: P
    let observer: AnyGesture<Void>?
    var observerEnabled = true
    var yields = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            // Named so a pager's UIKit pan can run alongside (SPEC S12, S16). `isEnabled: false` is `.subviews`.
            let n = scrollArbitrationGestureName
            let on = !yields
            switch (mode, observer) {
            case (.simultaneous, let observer?):
                // Armed gating (`observerEnabled`) holds on 18.x too: the observer that is not `SpatialEventGesture`
                // (D34, D37, or any forced fallback) must not sit on the content while it is at rest.
                content.simultaneousGesture(observer, name: n, isEnabled: on && observerEnabled)
                    .simultaneousGesture(pan, name: n, isEnabled: on)
            case (.gesture, let observer?):
                content.gesture(observer.simultaneously(with: pan), name: n, isEnabled: on)
            case (.high, let observer?):
                content.highPriorityGesture(observer.simultaneously(with: pan), name: n, isEnabled: on)
            case (_, nil):
                content.simultaneousGesture(pan, name: n, isEnabled: on)
            }
        } else {
            let mask: GestureMask = yields ? .subviews : .all
            switch (mode, observer) {
            case (.simultaneous, let observer?):
                content.simultaneousGesture(observer, including: observerEnabled ? mask : .subviews)
                    .simultaneousGesture(pan, including: mask)
            case (.gesture, let observer?):
                content.gesture(observer.simultaneously(with: pan), including: mask)
            case (.high, let observer?):
                content.highPriorityGesture(observer.simultaneously(with: pan), including: mask)
            case (_, nil):
                content.simultaneousGesture(pan, including: mask)
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
            content.background(NativeScrollEnabledReader { enabled in
                coordinator.nativeScrollEnabled = enabled
            })
        } else {
            content
        }
    }
}

/// Arming state of the fallback catch observer (iOS < 18); publishes only when `isArmed` flips.
final class CatchArming: ObservableObject, @unchecked Sendable {
    private(set) var isArmed = false
    private var moving = false

    /// The content starts or stops moving without a finger. Disarming is deferred while a touch is down.
    func setMoving(_ value: Bool, observerDown: Bool) {
        moving = value
        update(observerDown: observerDown)
    }

    func touchEnded() { update(observerDown: false) }

    private func update(observerDown: Bool) {
        let next = moving || observerDown
        guard next != isArmed else { return }
        objectWillChange.send()
        isArmed = next
    }
}

/// Feeds `CatchArming` from the phase channel without waking the content.
struct CatchArmingProbe: ViewModifier {
    let state: ZTronScrollState?
    @ObservedObject var arming: CatchArming
    let observer: CatchObserverState

    @ViewBuilder
    func body(content: Content) -> some View {
        if let state {
            content.background(ReaderProbe(state: state, transform: { g in
                g.phase == .decelerating || g.phase == .animating
            }, update: { moving in
                arming.setMoving(moving, observerDown: observer.down)
            }))
        } else {
            content
        }
    }
}

/// Observes `CatchArming` so only this modifier (never the content) re-evaluates when the observer is armed/disarmed.
struct GatedGestureAttach<P: Gesture>: ViewModifier {
    let mode: PanGestureMode
    let pan: P
    let observer: AnyGesture<Void>?
    @ObservedObject var arming: CatchArming
    let gated: Bool
    var yields = false

    func body(content: Content) -> some View {
        content.modifier(GestureAttach(mode: mode, pan: pan, observer: observer,
                                       observerEnabled: !gated || arming.isArmed, yields: yields))
    }
}

/// iOS 15-16 observer path (D31): a zero-size anchor at the viewport's top-leading corner installs the window recognizer
/// (`Gesture/UIKit/UIKitTouchObserver.swift`). `feedsCore: false` = the probe-only recognizer of
/// `ztronScrollPickersAbsorbDrags` (17+); `reportsPickers` = that modifier's value.
/// Anywhere else the content passes through.
struct UIKitObserverAttach: ViewModifier {
    let enabled: Bool
    let feedsCore: Bool
    let reportsPickers: Bool
    let coordinator: PanCoordinator
    let catchState: CatchObserverState

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(UIKit) && os(iOS)
        if enabled {
            content.background(alignment: .topLeading) {
                UIKitTouchObserverAnchor(coordinator: coordinator, catchState: catchState, feedsCore: feedsCore,
                                         reportsPickers: reportsPickers)
                    .frame(width: 0, height: 0).allowsHitTesting(false)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
