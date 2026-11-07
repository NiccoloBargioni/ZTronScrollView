#if canImport(UIKit) && os(iOS)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// UIKit raw-touch observer for iOS 15-16 (SPEC S2 amendment 2026-10-20, D31; design UIKIT-touch-observer.md §2). The only
// UIKit in the library: a recognizer that never recognizes, installed on the window, turns touches into `TouchSample`s for
// the pure `TouchObserverCore`; its outputs reach the same coordinator entry points as `SpatialCatchGesture`'s. Every line
// here is a straight forward or a one-branch guard (100 % line coverage gate, scripts/coverage-uikit.sh).
// Spike PICKER-s1 (open items 37-39, `ztronScrollPickersAbsorbDrags`): the same recognizer, probe-only on 17+, tells the
// coordinator whether a sequence's first finger landed inside a wheel picker (public classes, a `superview` walk).

/// Passive observer: stays `.possible`, never cancels, delays or blocks another recognizer, and cannot be blocked.
final class UIKitTouchObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var core = TouchObserverCore()
    private weak var anchor: UIView?
    private weak var coordinator: PanCoordinator?
    private weak var catchState: CatchObserverState?
    /// D31 (15-16): touches feed `TouchObserverCore`. False = probe only (17+): the picker check and nothing else.
    let feedsCore: Bool
    /// `ztronScrollPickersAbsorbDrags`: at a sequence's first touch-down, the coordinator learns whether it began on a
    /// picker.
    var reportsPickers: Bool

    init(anchor: UIView, coordinator: PanCoordinator, catchState: CatchObserverState, feedsCore: Bool = true,
         reportsPickers: Bool = false) {
        self.anchor = anchor
        self.coordinator = coordinator
        self.catchState = catchState
        self.feedsCore = feedsCore
        self.reportsPickers = reportsPickers
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
        if feedsCore { deliver(core.reset()) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if reportsPickers, Self.beginsSequence(touches, event) {
            coordinator?.touchSequenceBegan(onPicker: touches.contains { Self.isInPicker($0.view) })
        }
        forward(touches, .began)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesMoved(touches, with: event); forward(touches, .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesEnded(touches, with: event); forward(touches, .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesCancelled(touches, with: event); forward(touches, .cancelled) }

    /// Locations in the anchor's space = the viewport's local space (the anchor sits at its top-leading corner).
    private func forward(_ touches: Set<UITouch>, _ phase: TouchSample.Phase) {
        guard feedsCore else { return }
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

    /// The first finger of a sequence: no other touch of the event is still down.
    static func beginsSequence(_ touches: Set<UITouch>, _ event: UIEvent) -> Bool {
        !(event.allTouches ?? []).contains { !touches.contains($0) && $0.phase != .ended && $0.phase != .cancelled }
    }

    /// The hit view or one of its superviews is a wheel: a `UIPickerView` (`Picker(.wheel)`) or a `UIDatePicker` in its wheels
    /// style (`DatePicker(.wheel)`). A compact or graphical `UIDatePicker` is not: a vertical drag that starts on it scrolls.
    static func isInPicker(_ view: UIView?) -> Bool {
        var v = view
        while let c = v, !isWheel(c) { v = c.superview }
        #if DEBUG
        // Measurement only (PICKER-s1): the class names from the hit view up (to the picker), observed, never matched.
        var names: [String] = [], c = view
        while let x = c, names.count < (v == nil ? 3 : 12) {
            names.append(String(describing: type(of: x)))
            c = x === v ? nil : x.superview
        }
        ZTronRenderCounters.increment(v == nil ? "picker.miss" : "picker.hit")
        ZTronRenderCounters.notes[v == nil ? "picker.miss" : "picker.chain"] = names.joined(separator: ">")
        #endif
        return v != nil
    }

    static func isWheel(_ view: UIView) -> Bool {
        view is UIPickerView || (view as? UIDatePicker)?.datePickerStyle == .wheels
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
    let feedsCore: Bool
    let reportsPickers: Bool

    func makeUIView(context: Context) -> UIKitTouchAnchorView {
        let view = UIKitTouchAnchorView()
        view.isUserInteractionEnabled = false
        view.recognizer = UIKitTouchObserverRecognizer(anchor: view, coordinator: coordinator, catchState: catchState,
                                                       feedsCore: feedsCore, reportsPickers: reportsPickers)
        return view
    }

    /// 15-16: the recognizer stays while the modifier flips (17+ adds and removes the anchor instead).
    func updateUIView(_ view: UIKitTouchAnchorView, context: Context) {
        view.recognizer?.reportsPickers = reportsPickers
    }

    static func dismantleUIView(_ view: UIKitTouchAnchorView, coordinator: ()) { view.recognizer?.install(on: nil) }
}
#endif
