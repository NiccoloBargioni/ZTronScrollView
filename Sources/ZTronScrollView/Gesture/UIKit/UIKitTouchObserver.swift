#if canImport(UIKit) && os(iOS)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// UIKit raw-touch observer for iOS 15-16 (SPEC S2 amendment 2026-10-20, D31; design UIKIT-touch-observer.md §2). The only
// UIKit in the library: a recognizer that never recognizes, installed on the window, turns touches into `TouchSample`s for
// the pure `TouchObserverCore`; its outputs reach the same coordinator entry points as `SpatialCatchGesture`'s. Every line
// here is a straight forward or a one-branch guard (100 % line coverage gate, scripts/coverage-uikit.sh).

/// Passive observer: stays `.possible`, never cancels, delays or blocks another recognizer, and cannot be blocked.
final class UIKitTouchObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var core = TouchObserverCore()
    private weak var anchor: UIView?
    private weak var coordinator: PanCoordinator?
    private weak var catchState: CatchObserverState?

    init(anchor: UIView, coordinator: PanCoordinator, catchState: CatchObserverState) {
        self.anchor = anchor
        self.coordinator = coordinator
        self.catchState = catchState
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        allowedTouchTypes = [UITouch.TouchType.direct, .pencil].map { NSNumber(value: $0.rawValue) }
        delegate = self
    }

    /// Idempotent: moves the recognizer to `window` (nil = uninstall). A sequence live in the old window is cancelled.
    func install(on window: UIWindow?) {
        guard view !== window else { return }
        view?.removeGestureRecognizer(self)
        window?.addGestureRecognizer(self)
        deliver(core.reset())
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesBegan(touches, with: event); forward(touches, .began) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesMoved(touches, with: event); forward(touches, .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesEnded(touches, with: event); forward(touches, .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesCancelled(touches, with: event); forward(touches, .cancelled) }

    /// Locations in the anchor's space = the viewport's local space (the anchor sits at its top-leading corner).
    private func forward(_ touches: Set<UITouch>, _ phase: TouchSample.Phase) {
        #if DEBUG
        ZTronRenderCounters.increment("uikit.\(phase)")
        #endif
        let samples = touches.map { TouchSample(id: UInt(bitPattern: ObjectIdentifier($0)), phase: phase, location: $0.location(in: anchor)) }
        let size = coordinator?.state.peek.metrics.viewportSize ?? .zero
        deliver(core.handle(samples, viewport: CGRect(origin: .zero, size: size), time: Date().timeIntervalSinceReferenceDate))
    }

    private func deliver(_ outputs: [ObserverOutput]) {
        for output in outputs {
            switch output {
            case let .pan(event): coordinator?.handle(event)
            case let .pinch(event): coordinator?.handlePinch(event)
            case let .synthesize(point, time): coordinator?.synthesizePan(location: point, time: time)
            }
        }
        catchState?.down = core.isDown; catchState?.activeCount = core.activeCount; catchState?.centroid = core.centroid
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool {
        #if DEBUG
        ZTronRenderCounters.increment("uikit.canPrevent")
        #endif
        return false
    }

    override func canBePrevented(by other: UIGestureRecognizer) -> Bool {
        #if DEBUG
        ZTronRenderCounters.increment("uikit.canBePrevented")
        #endif
        return false
    }
}

/// Zero-size view at the viewport's top-leading corner: installs the recognizer on its window, follows window moves.
final class UIKitTouchAnchorView: UIView {
    var recognizer: UIKitTouchObserverRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer?.install(on: window)
    }
}

struct UIKitTouchObserverAnchor: UIViewRepresentable {
    let coordinator: PanCoordinator
    let catchState: CatchObserverState

    func makeUIView(context: Context) -> UIKitTouchAnchorView {
        let view = UIKitTouchAnchorView()
        view.isUserInteractionEnabled = false
        view.recognizer = UIKitTouchObserverRecognizer(anchor: view, coordinator: coordinator, catchState: catchState)
        return view
    }

    func updateUIView(_ view: UIKitTouchAnchorView, context: Context) {}

    static func dismantleUIView(_ view: UIKitTouchAnchorView, coordinator: ()) { view.recognizer?.install(on: nil) }
}
#endif
