import SwiftUI
import Combine
import ZTronScrollPhysics

/// One refresher as the coordinator runs it: its look, its tunables and what it starts (resolved by the refresher API,
/// design M8b §1.2). Closures never compare, so `sameValues` is what decides whether a running engine must be rebuilt.
struct RefresherSpec {
    var style: ZTronRefreshStyle = .default
    var overlay = false
    var configuration = ZTronRefreshConfiguration.default
    /// Refreshing ends when it returns.
    var action: @MainActor (Edge) async -> Void
    /// A custom indicator; `nil` = the built-in one of `style`.
    var indicator: ((Binding<ZTronRefreshState>) -> AnyView)?

    func sameValues(as other: RefresherSpec) -> Bool {
        style == other.style && overlay == other.overlay && configuration == other.configuration
    }

    /// The async action of a completion-handler refresher: suspends until `done` is called. `done` is idempotent
    /// and safe to call from any thread; the first call resumes on the main actor.
    static func awaiting(_ body: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> @MainActor (Edge) async -> Void {
        { _ in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let token = DoneToken()
                body { token.fire { continuation.resume() } }
            }
        }
    }
}

/// The completion handler of a completion-style refresher: the first `fire` wins, from any thread, and `resume` runs
/// on the main actor (a continuation can only resume once).
final class DoneToken: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire(_ resume: @escaping @MainActor () -> Void) {
        lock.lock()
        let first = !fired
        fired = true
        lock.unlock()
        guard first else { return }
        Task { @MainActor in resume() }
    }
}

/// Owns the refresh engines of one scroll view (one per edge with a refresher) and everything an engine cannot do:
/// reads the offset, starts and cancels the action `Task`, opens and closes the hold on the state, runs the minimum
/// visible time on a one-shot timer. The container owns it next to the `PanCoordinator` (M8b-2); the pan feeds it.
@MainActor
final class RefreshCoordinator: ObservableObject {
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    let state: ZTronScrollState
    private(set) var specs: [Edge: RefresherSpec] = [:]
    private(set) var engines: [Edge: RefreshEngine] = [:]
    /// What the indicators read, per edge (cold, but `dragPosition` changes per frame during a pull: the indicator leaf
    /// is the only observer). `objectWillChange` fires before each change.
    private(set) var states: [Edge: ZTronRefreshState] = [:]
    /// The edges whose indicator is going back with the content, and how the built-in one draws itself meanwhile (display
    /// only: the public `ZTronRefreshState` keeps `mode .notRefreshing` and a falling `dragPosition`).
    private(set) var retractions: [Edge: RefreshEngine.RetractLook] = [:]
    /// Bumps once per started action: the `sensoryFeedback` trigger of the indicator leaf (iOS 17+).
    private(set) var triggerSerial = 0
    /// Accessibility announcements ("Refreshing", "Refresh complete"); wired by the accessibility layer.
    var announce: ((String) -> Void)?
    /// One-shot timer for the minimum visible time; tests replace it to drive the clock by hand.
    var schedule: (_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Void = { delay, fire in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { fire() } }
    }

    private var tasks: [Edge: Task<Void, Never>] = [:]
    private var generations: [Edge: Int] = [:]
    private var holds: [Edge: CGFloat] = [:]
    private var deferredBegin: [Edge: Bool] = [:]
    /// Holds opened at a lift that left the offset inside the hold band (pulled, but less than the hold): the release
    /// pipeline decays from there and never reaches the hold bound, so `finishRelease()` scrolls it there.
    private var revealAfterRelease: Set<Edge> = []
    private var scrollEnabled = true
    /// The finger has lifted (the release pipeline is running) but the state still reports it as tracking until the
    /// release has been handed over: a flush inside that window must not read the pull as a new one (the lift resets
    /// `firedThisPull`, so a pull whose action had already returned would fire a second time).
    private var liftedThisTouch = false
    private var isApplying = false
    /// The deadline the pending one-shot timer covers (one timer per deadline, however many frames sample meanwhile).
    private var wakeDeadline: TimeInterval?
    private var heartbeatPending = false
    /// How often a retracting edge samples while the frame clock is idle.
    private static let heartbeat: TimeInterval = 1.0 / 30

    /// Fixed order, so two edges crossing in one frame resolve the same way on every run.
    private static let order: [Edge] = [.top, .leading, .bottom, .trailing]

    init(state: ZTronScrollState) {
        self.state = state
        state.refresh = self
    }

    // MARK: Specs

    /// The refreshers of this scroll view, whole (the resolver's result: later `refresher` calls already replaced the
    /// edges they name). New edges get an engine; removed ones are cancelled (the hold clears unanimated); an edge whose
    /// values changed gets a fresh engine as soon as it is idle (a running refresh keeps its configuration).
    func setSpecs(_ new: [Edge: RefresherSpec]) {
        for edge in Self.order where specs[edge] != nil && new[edge] == nil { remove(edge) }
        for edge in Self.order {
            guard let spec = new[edge] else { continue }
            let isNew = specs[edge] == nil
            specs[edge] = spec
            if isNew || engines[edge] == nil {
                engines[edge] = RefreshEngine(config: spec.configuration, edge: edge, overlay: spec.overlay)
                states[edge] = ZTronRefreshState(style: spec.style, edge: edge)
            } else {
                syncEngine(edge)
            }
        }
    }

    private func syncEngine(_ edge: Edge) {
        guard let spec = specs[edge], let e = engines[edge] else { return }
        if states[edge]?.style != spec.style {
            objectWillChange.send()
            states[edge]?.style = spec.style
        }
        let size = RefreshEngine.holdSize(edge: edge, config: spec.configuration, overlay: spec.overlay)
        guard e.phase == .idle, !e.holdApplied, e.config != spec.configuration || e.holdSize != size else { return }
        engines[edge] = RefreshEngine(config: spec.configuration, edge: edge, overlay: spec.overlay)
    }

    private func remove(_ edge: Edge) {
        cancelTask(edge)
        deferredBegin[edge] = nil
        revealAfterRelease.remove(edge)
        send(edge, .cancel)
        specs[edge] = nil
        engines[edge] = nil
        retractions[edge] = nil
        if states[edge] != nil {
            objectWillChange.send()
            states[edge] = nil
        }
    }

    /// A refresher on a vertical (horizontal) edge makes that axis bounce even when the content fits, as UIKit does
    /// when a refresh control is set (`alwaysBounceVertical`): axis-wide, not per edge.
    var bouncesVertical: Bool { specs[.top] != nil || specs[.bottom] != nil }
    var bouncesHorizontal: Bool { specs[.leading] != nil || specs[.trailing] != nil }

    /// The pan has something to tell the engines: a finger is down, or an edge is past `.idle`.
    var isActive: Bool {
        guard !engines.isEmpty else { return false }
        return state.isTracking || engines.values.contains { $0.isActive }
    }

    // MARK: Pan hooks (PanCoordinator)

    /// A frame (the `didScroll` flush / clock tick): pull progress, the trigger, and the deadline of a finishing edge.
    func sample(isScrollEnabled: Bool) {
        scrollEnabled = isScrollEnabled
        if liftedThisTouch, !state.isTracking { liftedThisTouch = false }
        guard !isApplying, !engines.isEmpty else { return }
        for edge in Self.order where engines[edge] != nil { send(edge, .sample(input(edge))) }
        scheduleWake()
    }

    /// The finger lifts and the release pipeline follows. Opens the hold of a triggered edge and closes the one of a
    /// finished edge BEFORE the release reads the bounds: an over-pulled release then springs to the hold position (or
    /// back to rest). Returns `true` when the bounds changed, so the caller re-reads its environment.
    @discardableResult
    func lift(isScrollEnabled: Bool, cancelled: Bool) -> Bool {
        scrollEnabled = isScrollEnabled
        guard !engines.isEmpty else { return false }
        state.flushPendingScroll()
        let before = state.peek.metrics.adjustedContentInset
        for edge in Self.order where engines[edge] != nil { send(edge, .lift(input(edge), cancelled: cancelled)) }
        liftedThisTouch = true
        runDeferredBegins()
        scheduleWake()
        return state.peek.metrics.adjustedContentInset != before
    }

    /// The release pipeline has started (`endDrag` ran): a hold opened at that lift under the hold band is scrolled to.
    func finishRelease() {
        guard !revealAfterRelease.isEmpty else { return }
        let edges = revealAfterRelease
        revealAfterRelease.removeAll()
        for edge in Self.order where edges.contains(edge) { scrollToHold(edge) }
    }

    /// The touch sequence ended with no release behind it (a tap, an ignored or pinch-owned sequence).
    func sequenceEnded(isScrollEnabled: Bool) {
        scrollEnabled = isScrollEnabled
        liftedThisTouch = false
        guard !engines.isEmpty else { return }
        for edge in Self.order where engines[edge] != nil { send(edge, .sequenceEnd(input(edge))) }
        runDeferredBegins()
        scheduleWake()
    }

    // MARK: Commands

    /// `beginRefreshing()` (`runAction: false`, UIKit parity: no action) or the accessibility action (`true`). While a
    /// finger is down it waits for the lift: changing the bounds under a finger would make the content jump.
    func begin(_ edge: Edge, runAction: Bool) {
        guard engines[edge] != nil else { return }
        if state.isTracking { deferredBegin[edge] = runAction; return }
        send(edge, .begin(input(edge), runAction: runAction))
    }

    /// `endRefreshing()`: ends a refresh of either kind (a running action is cancelled). The minimum visible time applies.
    func end(_ edge: Edge) {
        deferredBegin[edge] = nil
        guard engines[edge] != nil else { return }
        cancelTask(edge)
        send(edge, .done(input(edge)))
        scheduleWake()
    }

    /// The view disappeared (or every refresher was removed): the actions are cancelled, holds clear unanimated, the
    /// indicators return to rest.
    func cancelAll() {
        for edge in Self.order { cancelTask(edge) }
        deferredBegin.removeAll()
        revealAfterRelease.removeAll()
        wakeDeadline = nil
        for edge in Self.order where engines[edge] != nil { send(edge, .cancel) }
    }

    private func runDeferredBegins() {
        guard !deferredBegin.isEmpty, !state.isTracking else { return }
        let pending = deferredBegin
        deferredBegin.removeAll()
        for edge in Self.order {
            guard let runAction = pending[edge] else { continue }
            begin(edge, runAction: runAction)
        }
    }

    // MARK: Engine plumbing

    private func input(_ edge: Edge) -> RefreshEngine.Input {
        let s = state.peek
        var i = RefreshEngine.Input()
        i.time = state.now()
        i.isTracking = s.isTracking && !liftedThisTouch
        i.isSettled = !(s.phase == .decelerating || s.phase == .animating || s.isZoomBouncing)
        i.pull = RefreshMath.pull(edge: edge, offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics,
                                  alignment: state.contentAlignment)
        // A reset that SwiftUI animates moves the drawing, not the state: the offset has already jumped to rest while the
        // content is still on its way (no clock, no flush). A retracting indicator follows what was last drawn.
        if case .retracting? = engines[edge]?.phase, let drawn = state.probe.pending {
            i.pull = max(i.pull, RefreshMath.pull(edge: edge, offset: drawn.offset, zoom: drawn.zoom, metrics: s.metrics,
                                                  alignment: state.contentAlignment))
        }
        let zoomed = (specs[edge]?.configuration.disablesWhenZoomed ?? true)
            && s.presentationZoom > state.minimumZoomScale + 1e-4
        let otherBusy = engines.contains { $0.key != edge && $0.value.isRefreshing }
        i.enabled = scrollEnabled && !zoomed && !otherBusy
        return i
    }

    private func send(_ edge: Edge, _ event: RefreshEngine.Event) {
        guard var e = engines[edge] else { return }
        #if DEBUG
        if case .sample = event {} else { RefreshTrace.event("ev \(edge) \(event) phase=\(e.phase)") }
        #endif
        let fx = e.handle(event)
        engines[edge] = e
        apply(fx, edge: edge)
        if e.phase == .idle, !e.holdApplied { syncEngine(edge) }
    }

    private func apply(_ effects: [RefreshEngine.Effect], edge: Edge) {
        guard !effects.isEmpty else { return }
        let wasApplying = isApplying
        isApplying = true
        defer { isApplying = wasApplying }
        let configuration = specs[edge]?.configuration
        // The hold clears inside the reset animation and the indicator retracts with the content: both changes ride in ONE
        // transaction, so the indicator's drawing is animated by the same curve as the content's.
        if case let .swiftUI(animation)? = configuration?.resetAnimation, effects.contains(.clearHold(atLift: false, animated: true)),
           effects.contains(where: { if case .retract(.some) = $0 { return true } else { return false } }) {
            // D79: SwiftUI draws the content back while the model is at rest at once: a touch meanwhile catches it there.
            state.noteSwiftUIDrawnMotion()
            withAnimation(state.catchable(animation)) { perform(effects, edge: edge, configuration: configuration) }
        } else {
            perform(effects, edge: edge, configuration: configuration)
        }
    }

    /// Applies the effects in order, in whatever transaction the caller opened.
    private func perform(_ effects: [RefreshEngine.Effect], edge: Edge, configuration: ZTronRefreshConfiguration?) {
        for fx in effects {
            #if DEBUG
            switch fx {
            case .progress: break
            default: RefreshTrace.event("fx \(edge) \(fx) pull=\(RefreshTrace.f(input(edge).pull)) tracking=\(state.isTracking)")
            }
            #endif
            switch fx {
            case let .progress(p):
                objectWillChange.send()
                states[edge]?.dragPosition = p
            case let .mode(mode, animated):
                objectWillChange.send()
                states[edge]?.mode = mode
                if animated {
                    var animation = Animation.default
                    if case let .swiftUI(a)? = configuration?.resetAnimation { animation = a }
                    withAnimation(state.catchable(animation)) { states[edge]?.modeAnimated = mode }   // D79
                } else {
                    states[edge]?.modeAnimated = mode
                }
            case .trigger:
                triggerSerial += 1
                startAction(edge)
            case let .hold(amount, reveal):
                openHold(edge, amount: amount, reveal: reveal)
            case let .clearHold(atLift, animated):
                closeHold(edge, atLift: atLift, animated: animated, animation: configuration?.resetAnimation)
            case let .announce(text):
                announce?(text)
            case let .retract(look):
                objectWillChange.send()
                retractions[edge] = look
            }
        }
    }

    // MARK: The action

    private func startAction(_ edge: Edge) {
        guard let spec = specs[edge] else { return }
        cancelTask(edge)
        let generation = generations[edge, default: 0]
        let action = spec.action
        #if DEBUG
        ZTronRenderCounters.increment("refresh.actions")
        #endif
        tasks[edge] = Task { @MainActor [weak self] in
            await action(edge)
            guard !Task.isCancelled else { return }
            self?.actionReturned(edge, generation: generation)
        }
    }

    /// Cancels the running action and invalidates its completion.
    private func cancelTask(_ edge: Edge) {
        tasks[edge]?.cancel()
        tasks[edge] = nil
        generations[edge, default: 0] += 1
    }

    private func actionReturned(_ edge: Edge, generation: Int) {
        guard generations[edge, default: 0] == generation else { return }
        tasks[edge] = nil
        guard engines[edge] != nil else { return }
        send(edge, .done(input(edge)))
        scheduleWake()
    }

    // MARK: The hold

    private var holdInset: EdgeInsets {
        EdgeInsets(top: holds[.top] ?? 0, leading: holds[.leading] ?? 0, bottom: holds[.bottom] ?? 0,
                   trailing: holds[.trailing] ?? 0)
    }

    /// Opens the hold: bounds only, the offset stays where it is (the release pipeline springs an over-pull to the new
    /// bound). `reveal`: nothing springs it (programmatic begin), so an offset at or past the edge scrolls to the hold.
    private func openHold(_ edge: Edge, amount: CGFloat, reveal: Bool) {
        let before = state.peek
        let pulled = RefreshMath.signedPull(edge: edge, offset: before.presentationOffset, zoom: before.presentationZoom,
                                            metrics: before.metrics, alignment: state.contentAlignment)
        holds[edge] = amount > 0 ? amount : nil
        state.setRefreshHold(holdInset, followsOffset: false)
        guard amount > 0 else { return }
        if reveal {
            if pulled >= -0.5 { scrollToHold(edge) }
        } else if pulled > 0, pulled < amount - 0.5 {
            revealAfterRelease.insert(edge)
        }
    }

    /// Scrolls (on the clock) to the bound the hold opened: the position where the indicator is fully shown.
    private func scrollToHold(_ edge: Edge) {
        let s = state.peek
        let b = state.makeZoomGeometry(s.metrics).bounds(at: s.presentationZoom)
        var target = s.presentationOffset
        switch edge {
        case .top: target.y = b.y.min
        case .bottom: target.y = b.y.max
        case .leading: target.x = b.x.min
        case .trailing: target.x = b.x.max
        }
        if target != s.presentationOffset { state.setContentOffset(target, animated: true) }
    }

    /// Closes the hold. At the lift the release pipeline follows: bounds only. Otherwise the M5 inset rule returns the
    /// content to rest when it sits in the hold, inside the reset animation (`nil` / not `animated` = unanimated; `.uikit`
    /// = the clock curve after the bounds changed); a user who scrolled away sees nothing move.
    private func closeHold(_ edge: Edge, atLift: Bool, animated: Bool, animation: ZTronScrollAnimation?) {
        holds[edge] = nil
        let inset = holdInset
        if atLift {
            state.setRefreshHold(inset, followsOffset: false)
            return
        }
        guard animated, let animation else {
            state.unanimated { state.setRefreshHold(inset, followsOffset: true) }
            return
        }
        switch animation {
        case let .swiftUI(a):
            state.noteSwiftUIDrawnMotion()      // D79, as in `apply`
            withAnimation(state.catchable(a)) { state.setRefreshHold(inset, followsOffset: true) }
        case .uikit:
            state.setRefreshHold(inset, followsOffset: false)
            let s = state.peek
            let clamped = state.makeZoomGeometry(s.metrics).clamped(s.presentationOffset, at: s.presentationZoom)
            if clamped != s.presentationOffset { state.setContentOffset(clamped, animated: true) }
        }
    }

    // MARK: The minimum visible time

    /// A finishing edge waits for its deadline: one timer wake-up samples again when it passes (the frame clock is idle
    /// at rest, and a refresh must not keep it running). A deadline already passed but blocked (a finger down, a motion
    /// running) needs no timer: the lift or the settling motion samples. A retracting edge follows the content: the clock
    /// samples it while a motion runs, and a beat does while none does (SwiftUI animates the reset with the clock idle).
    private func scheduleWake() {
        var next: TimeInterval?
        var retracting = false
        for e in engines.values {
            switch e.phase {
            case let .finishing(until): next = min(next ?? until, until)
            case .retracting: retracting = true
            default: break
            }
        }
        if let until = next, until != wakeDeadline {
            let delay = until - state.now()
            if delay > 0 {
                wakeDeadline = until
                schedule(delay) { [weak self] in
                    guard let self else { return }
                    self.wakeDeadline = nil
                    self.sample(isScrollEnabled: self.scrollEnabled)
                }
            }
        }
        // The beat also ends a retraction nothing moves (its deadline) and one that is not drawn.
        if retracting, !heartbeatPending, !state.isClockRunning {
            heartbeatPending = true
            schedule(Self.heartbeat) { [weak self] in
                guard let self else { return }
                self.heartbeatPending = false
                self.sample(isScrollEnabled: self.scrollEnabled)
            }
        }
    }
}
