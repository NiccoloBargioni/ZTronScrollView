import SwiftUI
import ZTronScrollPhysics
import ScrollArbitration

/// Cold per-event settings merged by the adapter from the environment and the state's UIKit knobs.
struct PanSettings: Equatable {
    var isScrollEnabled = true
    var bounceX = BounceBehavior.automatic
    var bounceY = BounceBehavior.automatic
    var displayScale: CGFloat = 2
}

/// Owns one `PanSession` and the velocity tracker; applies effects to the state (design M3-pan §1). Part (c) adds the
/// arbitration participant; here `askOwner` is a pass-through (we are always the participant).
@MainActor
final class PanCoordinator: ObservableObject {
    let state: ZTronScrollState
    var axes: Axis.Set
    var settings = PanSettings()
    /// SwiftUI's own `isScrollEnabled` (16+), mirrored by the adapter.
    var nativeScrollEnabled = true
    private(set) var session = PanSession()
    private var tracker = PointVelocityTracker()
    private var pendingBegin = false
    /// Arbitration participant; nil without an arbiter in the environment (then nothing of S12 "Inside a pager" runs).
    private(set) var participant: ArbitrationParticipant?
    /// The sequence caught motion and the owner is not decided yet (sticky `isMovingWithoutFinger`, design §12 Q3).
    private(set) var caughtUndecided = false
    /// Pinch state machine (design M4 §1); the coordinator is the only object touching both sessions.
    var pinch = PinchSession()
    var isPinching: Bool { pinch.isActive }
    /// Last pan translation / start seen, for the one-finger-lift rebase.
    private var lastPanTranslation = CGSize.zero
    /// Pan continued by hand from the remaining finger after the DragGesture died on the second finger (R1).
    private var synthesizedPanStart: CGPoint?
    #if DEBUG
    var effectsLog: [PanEffect] = []
    var pinchLog: [PinchEffect] = []
    #endif

    init(state: ZTronScrollState, axes: Axis.Set) {
        self.state = state
        self.axes = axes
        if ZTronAvailability.isAvailable(.spatialEvents) {
            pinch.centroidSource = .spatial
        } else if ZTronAvailability.isAvailable(.magnifyGesture) {
            pinch.centroidSource = .startLocationPlusDrag
        } else {
            pinch.centroidSource = .dragOnly
        }
        state.onZoomBounceSettled = { [weak self] in self?.rebaseAfterBounce() }
    }

    /// Solver geometry shared by the pan bounds and the pinch.
    func makeZoomGeometry() -> ZoomGeometry { state.makeZoomGeometry() }

    /// Called by the registration modifier on every body evaluation; cheap unless the arbiter instance changed.
    func setArbiter(_ arbiter: (any ScrollArbiter)?) {
        if let arbiter {
            if let p = participant, p.arbiter === arbiter { return }
            participant?.unregister()
            participant = ArbitrationParticipant(arbiter: arbiter, coordinator: self)
        } else if participant != nil {
            participant?.unregister()
            participant = nil
        }
    }

    var isSequenceActive: Bool {
        if case .idle = session.phase { return false }
        return true
    }

    func environment() -> PanEnvironment {
        let s = state.peek
        let m = s.metrics
        let z = s.presentationZoom
        let bounds = makeZoomGeometry().bounds(at: z)
        let bx = bounds.x, by = bounds.y
        var env = PanEnvironment()
        let effAxes = PanEnvironment.effectiveAxes(axes, zoomEnabled: state.isZoomEnabled, boundsX: bx, boundsY: by)
        env.axes = effAxes
        env.isScrollEnabled = state.isScrollEnabled && settings.isScrollEnabled && nativeScrollEnabled
        env.isDirectionalLockEnabled = state.isDirectionalLockEnabled
        env.presentationOffset = s.presentationOffset
        env.boundsX = bx
        env.boundsY = by
        env.bouncesX = BounceConfiguration(behavior: settings.bounceX, bounces: state.bounces,
                                           alwaysBounce: state.alwaysBounceHorizontal)
            .resolve(isAxisEnabled: effAxes.contains(.horizontal), isScrollable: bx.isScrollable)
        env.bouncesY = BounceConfiguration(behavior: settings.bounceY, bounces: state.bounces,
                                           alwaysBounce: state.alwaysBounceVertical)
            .resolve(isAxisEnabled: effAxes.contains(.vertical), isScrollable: by.isScrollable)
        env.viewport = m.viewportSize
        env.isMovingWithoutFinger = (state.phase == .decelerating || state.phase == .animating) && !state.isTracking
        env.interruptedVelocity = state.lastInterruptedVelocity
        env.hasArbiter = participant != nil
        #if DEBUG
        if env.isMovingWithoutFinger { ZTronRenderCounters.increment("pan.movingAtEvent") }
        #endif
        return env
    }

    func handle(_ event: PanEvent) {
        #if DEBUG
        let name: String
        switch event {
        case .touchDown: name = "down"
        case .dragChanged: name = "drag"
        case .dragEnded: name = "dragEnd"
        case .touchesEnded: name = "up"
        case .frame: name = "frame"
        case .cancelled: name = "cancel"
        }
        ZTronRenderCounters.increment("pan.ev.\(name)")
        #endif
        // New sequence: forget the previous finger samples.
        switch (session.phase, event) {
        case (.idle, .touchDown), (.idle, .dragChanged), (.released, .touchDown): tracker.reset()
        default: break
        }
        switch event {
        case let .dragChanged(translation, _, _):
            lastPanTranslation = translation
            synthesizedPanStart = nil
        case .touchesEnded, .cancelled, .dragEnded: synthesizedPanStart = nil
        default: break
        }
        var env = environment()
        var effects = session.handle(event, env: env)
        if case let .dragChanged(translation, start, time) = event {
            tracker.add(CGPoint(x: start.x + translation.width, y: start.y + translation.height), at: time)
        }
        // The catch's interrupt() changes what the recognition sample must read.
        if effects.contains(.catchMotion) { apply(effects, env: env); effects = []; env = environment() }
        apply(effects, env: env)
        switch session.phase {
        case .idle, .released: caughtUndecided = false
        default: break
        }
    }

    /// The system cancelled the gesture (or the view went away) while a sequence is active.
    func cancelIfActive() {
        guard isSequenceActive else { return }
        handle(.cancelled)
    }

    private func apply(_ effects: [PanEffect], env: PanEnvironment) {
        var queue = effects
        while !queue.isEmpty {
            let fx = queue.removeFirst()
            #if DEBUG
            effectsLog.append(fx)
            #endif
            switch fx {
            case .catchMotion:
                #if DEBUG
                ZTronRenderCounters.increment("pan.catch")
                #endif
                state.interrupt(); state.catchLocksContent = true; caughtUndecided = true
            case .beginTracking: state.beginTracking()
            case .beginDragging:
                // willBeginDragging (and the hit-test gate) wait for the first real movement: a drag that moves
                // nothing (a Slider on a vertical-only view) must leave the content interactive.
                pendingBegin = true
            case let .setOffset(p):
                // A pinch (or its bounce) owns the offset; the pan keeps tracking its translation.
                if isPinching || state.isZoomBouncing { break }
                if pendingBegin, hypot(p.x - state.peek.presentationOffset.x, p.y - state.peek.presentationOffset.y) > 0.01 {
                    pendingBegin = false
                    state.beginDragging()
                }
                state.writeDragOffset(p)
            case .release where isPinching || state.isZoomBouncing:
                // Combined release: the pinch decides where the content goes; the pan just ends.
                if pendingBegin { pendingBegin = false; state.beginDragging() }
                state.endDragWithoutDeceleration()
            case let .release(r):
                if pendingBegin { pendingBegin = false; state.beginDragging() }
                var release = ReleaseSettings()
                release.rate = state.decelerationRate == .fast ? .fast : .normal
                release.isPagingEnabled = state.isPagingEnabled
                release.displayScale = settings.displayScale
                state.endDrag(r, tracker: tracker, env: env, settings: release)
            case .endSequence: pendingBegin = false; state.endTracking()
            case let .askOwner(start, translation, touchCount):
                // Once per sequence, at the hysteresis. No participant (cannot happen: hasArbiter) owns the swipe.
                let owner = participant?.owner(startLocation: start, translation: translation, touchCount: touchCount)
                    ?? .participant
                caughtUndecided = false
                if owner == .container { state.catchLocksContent = false }
                queue.insert(contentsOf: session.decided(owner, env: env), at: 0)
            }
        }
    }

    // MARK: Pinch

    func makePinchEnvironment() -> PinchEnvironment {
        let s = state.peek
        var e = PinchEnvironment()
        e.limits = state.resolvedZoom
        e.isZoomEnabled = state.isZoomEnabled
        e.bouncesZoom = state.bouncesZoom
        e.presentationScale = s.presentationZoom
        e.presentationOffset = s.presentationOffset
        e.geometry = makeZoomGeometry()
        e.isMovingWithoutFinger = (state.phase == .decelerating || state.phase == .animating) && !state.isTracking
        if case .dragging = session.phase { e.panDragActive = true }
        return e
    }

    func handlePinch(_ event: PinchEvent) {
        let env = makePinchEnvironment()
        applyPinch(pinch.handle(event, env: env), env: env, event: event)
    }

    /// 18+ after the DragGesture died on the second finger: feed the remaining finger's location as pan samples.
    func synthesizePan(location: CGPoint, time: TimeInterval) {
        guard let start = synthesizedPanStart else { return }
        let t = CGSize(width: location.x - start.x, height: location.y - start.y)
        let startLocation = start
        let keep = start
        handle(.dragChanged(translation: t, startLocation: startLocation, time: time))
        synthesizedPanStart = keep
    }

    /// The zoom bounce moved the offset while pan writes were dropped: a still-dragging pan continues from here.
    private func rebaseAfterBounce() {
        guard case .dragging = session.phase else { return }
        session.rebase(presentation: state.peek.presentationOffset, translation: lastPanTranslation,
                       env: environment())
    }

    private func applyPinch(_ effects: [PinchEffect], env: PinchEnvironment, event: PinchEvent) {
        for fx in effects {
            #if DEBUG
            pinchLog.append(fx)
            #endif
            switch fx {
            case .catchMotion:
                state.interrupt(); state.catchLocksContent = true
            case .beginZooming:
                // Two fingers are zoom intent: an undecided pan is ours (the pinch never calls the arbiter).
                if case .awaitingDecision = session.phase {
                    caughtUndecided = false
                    apply(session.decided(.participant, env: environment()), env: environment())
                }
                state.beginZooming()
            case let .setZoom(scale, offset):
                state.writePinch(scale: scale, offset: offset)
            case let .bounce(req):
                let time = state.now()   // D14: event times are on another clock
                let m = ZoomSolver.bounceBack(from: req.scale, limits: env.limits, lastCentroid: req.lastCentroid,
                                              offset: req.offset, geometry: env.geometry, at: time)
                state.beginZoomBounce(m, at: time)
            case let .endZooming(scale):
                state.endZooming(atScale: scale)
            case let .handOffToPan(remaining):
                handOffToPan(remaining: remaining, time: eventTime(event))
            }
        }
    }

    private func eventTime(_ event: PinchEvent) -> TimeInterval {
        switch event {
        case let .began(_, t), let .changed(_, _, t), let .fingerCountChanged(_, _, t), let .panTranslation(_, t),
             let .ended(t), let .frame(t): return t
        case .cancelled: return state.now()
        }
    }

    /// One finger lifted: the pan continues from the remaining finger without a jump (design M4 §4).
    private func handOffToPan(remaining: CGPoint?, time: TimeInterval) {
        if case .dragging = session.phase {
            session.rebase(presentation: state.peek.presentationOffset, translation: lastPanTranslation,
                           env: environment())
        } else if let remaining {
            // The DragGesture died when the second finger landed: restart the pan right at the remaining finger.
            handle(.touchDown(location: remaining, time: time, touchCount: 1))
            handle(.dragChanged(translation: .zero, startLocation: remaining, time: time))
            synthesizedPanStart = remaining
        }
    }
}

extension PanEnvironment {
    /// D15: with zoom enabled an axis outside `axes` still pans while the zoomed content exceeds the viewport on it.
    /// Such an axis is scrollable by construction, so its bounce equals `.basedOnSize`.
    static func effectiveAxes(_ axes: Axis.Set, zoomEnabled: Bool, boundsX: AxisBounds, boundsY: AxisBounds) -> Axis.Set {
        guard zoomEnabled else { return axes }
        var a = axes
        if boundsX.isScrollable { a.insert(.horizontal) }
        if boundsY.isScrollable { a.insert(.vertical) }
        return a
    }
}
