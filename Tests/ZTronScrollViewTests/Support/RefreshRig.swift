import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// A refresh action the test controls: suspends until `release()`, counts how often it started, was cancelled and
/// finished. Lock-protected: the cancellation handler runs on whichever thread cancels.
final class ActionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var _started = 0, _cancelled = 0, _finished = 0
    var started: Int { locked { _started } }
    var cancelled: Int { locked { _cancelled } }
    var finished: Int { locked { _finished } }

    /// Synchronous on purpose: `NSLock.lock()` is unavailable inside `async` bodies.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func run() async {
        locked { _started += 1 }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                locked { continuation = c }
            }
        } onCancel: {
            let c: CheckedContinuation<Void, Never>? = locked {
                _cancelled += 1
                let c = continuation
                continuation = nil
                return c
            }
            c?.resume()
        }
        locked { _finished += 1 }
    }

    /// Lets the suspended action return (a no-op when none is suspended).
    func release() {
        let c: CheckedContinuation<Void, Never>? = locked {
            let c = continuation
            continuation = nil
            return c
        }
        c?.resume()
    }
}

/// One scroll state, its pan coordinator and a refresh coordinator on a manual clock (M8b-1). Objects are built inside
/// `withOSPath`, the body runs outside it, like the other state suites. Vertical by default: 390×800 viewport, 3000 pt of
/// content, rest at `-aci.top`.
@MainActor
final class RefreshRig {
    final class Clock { var t: TimeInterval = 100 }
    let clock: Clock
    let state: ZTronScrollState
    let pan: PanCoordinator
    let refresh: RefreshCoordinator
    let gate = ActionGate()
    let delegate = InsetDelegate()
    let viewport: CGSize
    /// One-shot timers the coordinator asked for (the minimum visible time), run by hand with `fireWakes()`.
    var wakes: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
    var announcements: [String] = []
    private var start = CGPoint(x: 200, y: 300)
    private var lastTranslation = CGSize.zero

    init(_ path: OSPath, configs: [Edge: ZTronRefreshConfiguration] = [.top: ZTronRefreshConfiguration()],
         axes: Axis.Set = .vertical, viewport: CGSize = CGSize(width: 390, height: 800),
         content: CGSize = CGSize(width: 390, height: 3000), safe: EdgeInsets = EdgeInsets(), overlay: Bool = false) {
        let clock = Clock()
        let gate = self.gate
        let s = makeState(path)
        s.now = { clock.t }
        s.scrollAxes = axes
        s.setMetrics(ScrollMetrics(viewportSize: viewport, contentSize: content, safeAreaInsets: safe, displayScale: 2))
        let aci = s.adjustedContentInset
        s.track(offset: CGPoint(x: -aci.leading, y: -aci.top), zoom: 1)
        let pan = withOSPath(path) { PanCoordinator(state: s, axes: axes) }
        pan.settings.displayScale = 2
        let refresh = RefreshCoordinator(state: s)
        pan.refresh = refresh
        s.delegate = delegate
        self.clock = clock
        self.state = s
        self.pan = pan
        self.refresh = refresh
        self.viewport = viewport
        refresh.schedule = { [weak self] delay, fire in self?.wakes.append((delay, fire)) }
        refresh.announce = { [weak self] in self?.announcements.append($0) }
        refresh.setSpecs(Dictionary(uniqueKeysWithValues: configs.map { edge, config in
            (edge, RefresherSpec(overlay: overlay, configuration: config, action: { _ in await gate.run() }))
        }))
    }

    var now: TimeInterval { clock.t }
    var aci: EdgeInsets { state.adjustedContentInset }
    var hold: EdgeInsets { state.refreshHoldInset }
    var offset: CGPoint { state.contentOffset }
    func engine(_ edge: Edge = .top) -> RefreshEngine { refresh.engines[edge]! }
    func refreshState(_ edge: Edge = .top) -> ZTronRefreshState { refresh.states[edge]! }

    /// Displayed overscroll past `edge`, measured against the bounds without the hold.
    func pull(_ edge: Edge = .top) -> CGFloat {
        let s = state.peek
        return RefreshMath.pull(edge: edge, offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics,
                                alignment: state.contentAlignment)
    }

    /// The offset bounds right now (what the pan and the release read).
    var boundsY: AxisBounds { pan.peekEnvironment().boundsY }
    var boundsX: AxisBounds { pan.peekEnvironment().boundsX }

    // MARK: Clock

    /// `n` frames of 1/60 s through the state's clock (the flush that feeds the engines).
    func tick(_ n: Int = 1) {
        for _ in 0..<n {
            clock.t += 1.0 / 60
            state.step(to: Date(timeIntervalSinceReferenceDate: clock.t))
        }
    }

    /// Runs frames until nothing moves (or `maxFrames`).
    func settle(maxFrames: Int = 900) {
        var n = 0
        while state.isClockRunning, n < maxFrames { tick(); n += 1 }
    }

    /// Advances the clock by `seconds` in frames of 1/60 s (the finger keeps still, a motion keeps running).
    func wait(_ seconds: TimeInterval) { tick(max(1, Int((seconds * 60).rounded()))) }

    func fireWakes() {
        let due = wakes
        wakes.removeAll()
        for w in due { w.fire() }
    }

    /// Lets the queued `Task { @MainActor }` jobs (the action, its completion) run. A nested run loop cannot: the test
    /// itself is a job on the main queue, so the tasks only get the main actor while the test is suspended.
    func pumpTasks() async {
        for _ in 0..<30 { await Task.yield() }
    }

    // MARK: Finger

    func touchDown(at p: CGPoint = CGPoint(x: 200, y: 300)) {
        start = p
        lastTranslation = .zero
        pan.handle(.touchDown(location: p, time: now, touchCount: 1))
    }

    /// Moves the finger (one frame) so the displayed pull past `edge` is `target`, from a view resting at that edge:
    /// the first call after `touchDown` is the recognition sample (10 pt hysteresis credited).
    func finger(toPull target: CGFloat, edge: Edge = .top) {
        let horizontal = edge == .leading || edge == .trailing
        let band = RubberBand(dimension: horizontal ? viewport.width : viewport.height, coefficient: 0.55)
        let x = abs(band.overscroll(forDisplacement: target))
        let t = (edge == .top || edge == .leading ? 1 : -1) * (10 + x)
        drag(CGSize(width: horizontal ? t : 0, height: horizontal ? 0 : t))
    }

    /// The finger's total translation since the touch-down, one frame.
    func drag(_ translation: CGSize) {
        lastTranslation = translation
        pan.handle(.dragChanged(translation: translation, startLocation: start, time: now))
        tick()
    }

    /// Lifts the finger where it is, after a still frame (a pause: the release does not fling).
    func lift() {
        tick()
        pan.handle(.dragEnded(translation: lastTranslation, time: now, fallbackVelocity: nil))
        pan.handle(.touchesEnded(time: now))
    }

    /// A whole pull-and-release at `edge`: touch, pull to `target`, lift. Leaves the release running.
    func pullAndRelease(to target: CGFloat, edge: Edge = .top) {
        touchDown()
        finger(toPull: target, edge: edge)
        lift()
    }

    /// Completes the running action and delivers its completion.
    func completeAction() async {
        gate.release()
        await pumpTasks()
    }
}

extension RefreshEngine {
    /// The look of a retracting edge, nil in every other phase.
    var retractLook: RetractLook? {
        if case let .retracting(look, _) = phase { return look }
        return nil
    }
}

extension RefreshRig {
    /// How much of the indicator of `edge` the leaf draws now, from the same inputs `RefreshEdgeIndicator` feeds the placement:
    /// the live pull, the state's progress and mode, and the retraction look (the spinner stays after a refresh; an overlay
    /// indicator keeps sliding out with the pull).
    func visibleIndicator(_ edge: Edge = .top, style: ZTronRefreshStyle = .default, overlay: Bool = false,
                          length: CGFloat = 60) -> CGFloat {
        let s = state.peek, st = refreshState(edge)
        let pull = RefreshMath.signedPull(edge: edge, offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics,
                                          alignment: state.contentAlignment)
        let aci = s.metrics.adjustedContentInset, hold = s.metrics.refreshHold
        let base = EdgeInsets(top: aci.top - hold.top, leading: aci.leading - hold.leading,
                              bottom: aci.bottom - hold.bottom, trailing: aci.trailing - hold.trailing)
        guard let p = RefreshIndicatorMath.placement(
            edge: edge, style: style, overlay: overlay, refreshing: st.mode == .refreshing || (refresh.retractions[edge] == .spinner && !overlay),
            dragPosition: st.dragPosition, pull: pull, length: length, viewport: s.metrics.viewportSize, base: base)
        else { return 0 }
        return p.visibleLength(vertical: edge == .top || edge == .bottom)
    }

    /// One frame of a retraction: what the leaf draws and what the engine tells the indicator.
    struct RetractFrame {
        var pull: CGFloat, visible: CGFloat, progress: CGFloat, look: RefreshEngine.RetractLook?, mode: ZTronRefreshState.Mode
    }

    /// Runs frames from now until the edge stops retracting (or `maxFrames`), recording each one before it is ticked.
    func retractFrames(_ edge: Edge = .top, style: ZTronRefreshStyle = .default, overlay: Bool = false,
                       maxFrames: Int = 600) -> [RetractFrame] {
        var frames: [RetractFrame] = []
        while engine(edge).isActive, frames.count < maxFrames {
            frames.append(RetractFrame(pull: pull(edge), visible: visibleIndicator(edge, style: style, overlay: overlay),
                                       progress: refreshState(edge).dragPosition, look: refresh.retractions[edge],
                                       mode: refreshState(edge).mode))
            tick()
        }
        return frames
    }
}
