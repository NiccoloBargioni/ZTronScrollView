import UIKit
import ScrollArbitration

/// Paging scroll view whose pan asks the page arbiters who owns a drag (SPEC "Spike", MC-contract section 5).
final class ArbitratedPagingScrollView: UIScrollView, UIGestureRecognizerDelegate {
    var pageViews: [UIView] = []
    var arbiters: [ReferenceScrollArbiter] = []
    let recorder: SequenceRecorder
    var pageIndex: () -> Int = { 0 }

    private var activeTouches = 0
    private var activePage: Int?
    private var touchDownPoint: CGPoint = .zero  // in the page's hosting view
    private var seenOthers: [(recognizer: WeakRecognizer, className: String)] = []
    private var pollTimer: Timer?

    init(recorder: SequenceRecorder) {
        self.recorder = recorder
        super.init(frame: .zero)
        panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
    }

    required init?(coder: NSCoder) { fatalError() }

    private final class WeakRecognizer { weak var value: UIGestureRecognizer?; init(_ v: UIGestureRecognizer) { value = v } }

    private func page(containing point: CGPoint) -> Int? {
        pageViews.firstIndex { $0.frame.contains(point) }
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let moving = isDecelerating
        if activeTouches == 0, let first = touches.first, let p = page(containing: first.location(in: self)) {
            activePage = p
            let arbiter = arbiters[p]
            arbiter.isContainerMoving = moving
            touchDownPoint = first.location(in: pageViews[p])
            recorder.begin(page: p, uikitPoint: touchDownPoint, pageIndex: pageIndex())
            arbiter.beginSequence()
            startPolling()
        }
        activeTouches += touches.count
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchesFinished(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesFinished(touches.count)
    }

    private func touchesFinished(_ count: Int) {
        activeTouches = max(0, activeTouches - count)
        guard activeTouches == 0, let p = activePage else { return }
        pollForeign()
        recorder.mutate { r in
            if !r.panStates.contains("began"), r.panStates.last != "failed" { r.panStates.append("failed") }
            r.open = false
        }
        arbiters[p].endSequence()
        activePage = nil
        // Keep polling briefly for deceleration, then stop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.activePage == nil else { return }
            self.pollTimer?.invalidate(); self.pollTimer = nil
        }
    }

    // MARK: arbitration

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let pan = panGestureRecognizer
        guard let p = page(containing: pan.location(in: self)) else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let t = pan.translation(in: pageViews[p])
        let owner = arbiters[p].containerOwner(ofDragFrom: touchDownPoint, translation: CGSize(width: t.x, height: t.y),
                                               touchCount: pan.numberOfTouches)
        recorder.onChange?()
        return owner == .container && super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if !seenOthers.contains(where: { $0.recognizer.value === other }) {
            seenOthers.append((WeakRecognizer(other), String(describing: type(of: other))))
        }
        if #available(iOS 18, *) { return other.name == scrollArbitrationGestureName }
        return false
    }

    // MARK: recording

    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        recorder.panState(Self.name(pan.state))
        pollForeign()
    }

    static func name(_ s: UIGestureRecognizer.State) -> String {
        switch s {
        case .possible: "possible"
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .failed: "failed"
        @unknown default: "unknown"
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForeign() }
        }
    }

    /// Any recognizer in the touched page (or seen by the simultaneity query) not named for arbitration that
    /// reached began/changed counts as foreign.
    private func pollForeign() {
        guard let p = activePage ?? page(containing: CGPoint(x: bounds.midX + contentOffset.x - bounds.minX, y: bounds.midY)) else { return }
        var names: Set<String> = []
        func scan(_ view: UIView) {
            for g in view.gestureRecognizers ?? [] where g !== panGestureRecognizer { consider(g, &names) }
            view.subviews.forEach(scan)
        }
        scan(pageViews[p])
        for o in seenOthers { if let g = o.recognizer.value { consider(g, &names) } }
        if !names.isEmpty { recorder.mutate { $0.foreignNames.formUnion(names) } }
    }

    private func consider(_ g: UIGestureRecognizer, _ names: inout Set<String>) {
        guard g.state == .began || g.state == .changed, g.name != scrollArbitrationGestureName else { return }
        names.insert(String(describing: type(of: g)))
    }
}
