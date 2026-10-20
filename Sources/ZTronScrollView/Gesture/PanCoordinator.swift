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
    /// How this view yields a shared drag to its container (NESTED §3); read by the participant's `canFollow`.
    private(set) var nestedPolicy = ZTronNestedScrollPolicy.automatic
    /// The arbiter offered to the `ZTronScrollView`s in this view's content (container role, NESTED §3).
    let nestedArbiter = NestedScrollArbiter()
    /// The sequence caught motion and the owner is not decided yet (sticky `isMovingWithoutFinger`, design §12 Q3).
    private(set) var caughtUndecided = false
    /// The refresh engines of this view (M8b); nil without a refresher. Sampled at every flush, told of the lift before
    /// the release reads the bounds, and the reason an axis bounces even when its content fits.
    var refresh: RefreshCoordinator?
    /// Pinch state machine (design M4 §1); the coordinator is the only object touching both sessions.
    var pinch = PinchSession()
    var isPinching: Bool { pinch.isActive }
    /// Last pan translation / start seen, for the one-finger-lift rebase.
    private var lastPanTranslation = CGSize.zero
    /// Pan continued by hand from the remaining finger after the DragGesture died on the second finger (R1).
    private var synthesizedPanStart: CGPoint?
    /// A pinch took over the current pan sequence. Its release then ends without a deceleration (UIScrollView never
    /// flings after a pinch; the pinch's own bounce settles the offset), unless one finger stayed down and the pan
    /// continued from it (`handOffToPan(remaining:)` clears it).
    private var pinchOwnedPan = false
    /// The pan continued from the finger left after a pinch (`handOffToPan(remaining:)`): its release flings only
    /// from that finger's own movement since the hand-off, never from the gesture's pinch-phase velocity.
    private var panContinuedFromPinch = false
    /// `synthesizePan` is feeding a sample (so a `.dragChanged` is not the DragGesture reappearing).
    private var isFeedingSynthesizedSample = false
    /// A release that arrived after a pinch hand-off while the finger may still be down (D29): SwiftUI ends the
    /// one-finger DragGesture when a second finger lands, and that `.dragEnded` can precede the observer's count
    /// change. Held until the observer says the fingers are gone (`touchesEnded`: released then, from the current
    /// time) or that two are down again (`fingerCountChanged(≥ 2)` / `.began`: dropped, the pinch takes over).
    private var heldRelease: (request: ReleaseRequest, env: PanEnvironment)?
    #if DEBUG
    var effectsLog: [PanEffect] = []
    var pinchLog: [PinchEffect] = []
    #endif

    init(state: ZTronScrollState, axes: Axis.Set) {
        self.state = state
        self.axes = axes
        if state.usesSpatialEvents || state.usesUIKitTouchObserver {   // the UIKit observer (D31) provides the centroid too
            pinch.centroidSource = .spatial
        } else if state.usesMagnifyGesture {
            pinch.centroidSource = .startLocationPlusDrag
        } else {
            pinch.centroidSource = .dragOnly
        }
        state.onZoomBounceSettled = { [weak self] in self?.rebaseAfterBounce() }
        state.onFlush = { [weak self] in self?.refreshFlush() }
        nestedArbiter.container = self
    }

    /// Solver geometry shared by the pan bounds and the pinch.
    func makeZoomGeometry() -> ZoomGeometry { state.makeZoomGeometry() }

    /// Called by the registration modifier on every body evaluation; cheap unless the arbiter instance changed.
    /// `.independent` opts out of the *nested* container only (no participant toward an outer `ZTronScrollView`);
    /// an external ScrollArbitration arbiter (a ZTronPages pager) is always joined.
    func setArbiter(_ arbiter: (any ScrollArbiter)?, policy: ZTronNestedScrollPolicy = .automatic) {
        nestedPolicy = policy
        if let arbiter, policy.joins(arbiter) {
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

    /// `isContainerMoving` for the nested arbiter: live motion, or motion this sequence caught and nobody decided yet.
    var isMovingForNestedArbiter: Bool { caughtUndecided || peekEnvironment().isMovingWithoutFinger }
    /// Could this view take a swipe now (enabled, with an axis)? The nested arbiter answers `.participant` to its
    /// inners without deciding while this is false (see `PanEnvironment.isContainer`).
    var canTakeSwipe: Bool {
        let e = peekEnvironment()
        return e.isScrollEnabled && !e.axes.isEmpty
    }
    /// The axes a swipe can move this view on now (D15: `axes` plus any axis the zoomed content exceeds the viewport
    /// on). The nested arbiter's paging axis comes from here, not from the declared `axes`: a vertical outer zoomed
    /// past its width takes a horizontal swipe its inner cannot follow.
    var effectiveAxes: Axis.Set { peekEnvironment().axes }

    /// The viewport-local touch point in the content space the nested arbiter's frames are expressed in
    /// (`ZoomSolver.contentPoint`: offset, zoom and alignment padding of this view). Internal for the tests.
    func nestedStart(_ local: CGPoint) -> CGPoint {
        let s = state.peek
        return ZoomSolver.contentPoint(under: local, offset: s.presentationOffset, scale: s.presentationZoom,
                                       geometry: makeZoomGeometry())
    }

    /// The cold snapshot an event is handled against. In DEBUG it also counts `pan.movingAtEvent`; the side-effect
    /// free reads the nested arbiter and the gates use are `peekEnvironment()`.
    func environment() -> PanEnvironment {
        let env = peekEnvironment()
        #if DEBUG
        if env.isMovingWithoutFinger { ZTronRenderCounters.increment("pan.movingAtEvent") }
        #endif
        return env
    }

    /// `environment()` without the DEBUG counter.
    func peekEnvironment() -> PanEnvironment {
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
        // A refresher on an edge makes its axis bounce even when the content fits (UIKit sets `alwaysBounceVertical` for a
        // refresh control): axis-wide, regardless of the bounce behavior.
        if let refresh {
            if refresh.bouncesVertical { env.bouncesY = true }
            if refresh.bouncesHorizontal { env.bouncesX = true }
        }
        env.viewport = m.viewportSize
        env.isMovingWithoutFinger = (state.phase == .decelerating || state.phase == .animating) && !state.isTracking
        env.interruptedVelocity = state.lastInterruptedVelocity
        // Toward a nested container that cannot take the swipe (NESTED §3, R7's `.ztronScrollDisabled` on the
        // outer): no arbiter for this touch, we behave as if alone. An external (pager) arbiter is always asked.
        env.hasArbiter = participant != nil && ((participant?.arbiter as? NestedScrollArbiter)?.isArbitrating ?? true)
        // Container role (NESTED §3) only while this view could take the swipe itself, the session's own touch-down
        // gate: a scroll-disabled outer (`.ztronScrollDisabled(true)`, R7's idiom) or one without an axis arbitrates
        // nothing and its inners behave as if alone.
        env.isContainer = nestedArbiter.hasParticipants && env.isScrollEnabled && !env.axes.isEmpty
        return env
    }

    func handle(_ incoming: PanEvent) {
        var event = incoming
        // The touch-down time becomes `caughtAt` and is compared with `state.now()` at release (fling acceleration):
        // stamp it on the state clock (D14: observer/event clocks differ from the state clock on iOS 27 and on the
        // DragGesture fallback), so `touchDuration` is never negative or decades long.
        if case let .touchDown(location, _, touchCount) = incoming {
            event = .touchDown(location: location, time: state.now(), touchCount: touchCount)
            // Container role: the sequence begins at the first finger down (before the catch below stops our motion,
            // so the snapshot sees it). Without inners, or while we cannot scroll, nothing is asked and nothing begins.
            if peekEnvironment().isContainer { nestedArbiter.beginSequence() }
        }
        // A pan synthesized from the remaining finger (the DragGesture died on the second finger) has no DragGesture
        // to end it: the last finger up is its release, from the last synthesized translation.
        var endsSynthesizedPan = false
        if case let .touchesEnded(time) = incoming, synthesizedPanStart != nil, case .dragging = session.phase {
            event = .dragEnded(translation: lastPanTranslation, time: time, fallbackVelocity: nil)
            endsSynthesizedPan = true
        }
        // After a hand-off the gesture's own velocity describes one finger of the pinch, not a pan: only the tracker's
        // post-hand-off samples may fling (UIScrollView never flings out of a pinch).
        if case let .dragEnded(translation, time, _) = incoming, panContinuedFromPinch {
            event = .dragEnded(translation: translation, time: time, fallbackVelocity: nil)
        }
        if synthesizedPanStart != nil, !isFeedingSynthesizedSample, case .dragging = session.phase {
            switch incoming {
            case let .dragChanged(translation, _, _):
                // The DragGesture (re)appears under the synthesized pan (it followed the remaining finger and only now
                // passed its hysteresis): it takes over from where the content is, no jump; its samples restart.
                session.rebase(presentation: state.peek.presentationOffset, translation: translation, env: environment())
                tracker.reset()
            case .dragEnded:
                // It followed the finger that already lifted: stale. The remaining finger's lift ends this pan.
                return
            default: break
            }
        }
        #if DEBUG
        let name: String
        switch incoming {
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
        case (.idle, .touchDown), (.idle, .dragChanged), (.released, .touchDown):
            tracker.reset(); pinchOwnedPan = false; panContinuedFromPinch = false; heldRelease = nil
        default: break
        }
        if case .cancelled = incoming { heldRelease = nil }
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
        // The converted lift was both the drag's end and the last finger up: the session is over, as after a real
        // `.dragEnded` + `.touchesEnded` pair.
        if endsSynthesizedPan, case let .touchesEnded(time) = incoming {
            _ = session.handle(.touchesEnded(time: time), env: env)
        }
        // All fingers are gone: a release held since the hand-off runs now, timed from now (a finger that stayed down
        // and paused releases at rest: the tracker's rest rule sees the old samples).
        if case .touchesEnded = incoming, let held = heldRelease {
            heldRelease = nil
            var r = held.request
            r.liftTime = state.now()
            isHandlingHeldRelease = true
            apply([.release(r)], env: held.env)
            isHandlingHeldRelease = false
        }
        switch session.phase {
        case .idle, .released:
            caughtUndecided = false; panContinuedFromPinch = false
            // Container role: the sequence is over (last finger up, or the DragGesture ended / cancelled).
            nestedArbiter.endSequence()
            // Participant role toward a nested container: close a sequence it began at our ask (see the arbiter).
            (participant?.arbiter as? NestedScrollArbiter)?.participantSequenceEnded()
        default: break
        }
    }

    /// The system cancelled the gesture (or the view went away) while a sequence is active.
    func cancelIfActive() {
        guard isSequenceActive else { return }
        handle(.cancelled)
    }

    /// The held release is being applied: `.release` must not be held again.
    private var isHandlingHeldRelease = false

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
                // A pinch (or its bounce) owns the offset; the pan keeps tracking its translation. After both fingers
                // lifted, the drag's last sample must not land on top of the pinch's offset either.
                if isPinching || state.isZoomBouncing || pinchOwnedPan { break }
                if pendingBegin, hypot(p.x - state.peek.presentationOffset.x, p.y - state.peek.presentationOffset.y) > 0.01 {
                    pendingBegin = false
                    state.beginDragging()
                }
                state.writeDragOffset(p)
            case .release where isPinching || state.isZoomBouncing || pinchOwnedPan:
                // Combined release: the pinch decides where the content goes; the pan just ends.
                pinchOwnedPan = false
                if pendingBegin { pendingBegin = false; state.beginDragging() }
                state.endDragWithoutDeceleration()
                refresh?.sequenceEnded(isScrollEnabled: env.isScrollEnabled)
            case let .release(r) where panContinuedFromPinch && !r.zeroVelocity && heldRelease == nil
                && !isHandlingHeldRelease:
                // After a hand-off the DragGesture's end may be the second finger landing, not a lift (D29): hold it.
                heldRelease = (r, env)
            case let .release(r):
                if pendingBegin { pendingBegin = false; state.beginDragging() }
                var release = ReleaseSettings()
                release.rate = state.decelerationRate == .fast ? .fast : .normal
                release.isPagingEnabled = state.isPagingEnabled
                release.displayScale = settings.displayScale
                // The refresh hold opens (or its reset closes) BEFORE the release reads the bounds: an over-pulled release
                // springs to the hold position, a late reset springs back to rest.
                let boundsChanged = refresh?.lift(isScrollEnabled: env.isScrollEnabled, cancelled: r.zeroVelocity) ?? false
                state.endDrag(r, tracker: tracker, env: boundsChanged ? peekEnvironment() : env, settings: release)
                if boundsChanged { refresh?.finishRelease() }
            case .endSequence:
                pendingBegin = false; pinchOwnedPan = false; state.endTracking()
                refresh?.sequenceEnded(isScrollEnabled: env.isScrollEnabled)
            case let .askOwner(start, translation, touchCount):
                // Once per sequence, at the hysteresis. `owner` is from our side: `.participant` = we drag.
                // Participant role first (our container's arbiter), then container role: an inner under the touch
                // that follows the swipe makes us ignore the sequence (three levels: each view talks to its nearest
                // container; OR-ing an inner's answer into our own `canFollow` is phase 2).
                var owner = participant?.owner(startLocation: start, translation: translation, touchCount: touchCount)
                    ?? .participant
                if owner == .participant, env.isContainer,
                   nestedArbiter.containerOwner(ofDragFrom: nestedStart(start), translation: translation,
                                                touchCount: touchCount) == .participant {
                    owner = .container
                }
                caughtUndecided = false
                if owner == .container { state.catchLocksContent = false }
                queue.insert(contentsOf: session.decided(owner, env: env), at: 0)
            }
        }
    }

    /// A `didScroll` flush (the end of `deliverPending`): the refresh engines sample the offset, at most once per frame.
    private func refreshFlush() {
        guard let refresh, refresh.isActive else { return }
        refresh.sample(isScrollEnabled: state.isScrollEnabled && settings.isScrollEnabled && nativeScrollEnabled)
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
        let pan = environment()
        e.bouncesX = pan.bouncesX
        e.bouncesY = pan.bouncesY
        e.rubberBandCoefficient = session.rubberBandCoefficient
        return e
    }

    func handlePinch(_ event: PinchEvent) {
        // Two fingers are down again (D29): a release held since the hand-off was the DragGesture ending on the second
        // finger, not a lift. The pan ends without motion and the pinch takes over.
        if heldRelease != nil {
            var twoFingers = false
            switch event {
            case .began: twoFingers = true
            case let .fingerCountChanged(count, _, _): twoFingers = count >= 2
            default: break
            }
            if twoFingers {
                heldRelease = nil
                state.endDragWithoutDeceleration()
            }
        }
        let env = makePinchEnvironment()
        applyPinch(pinch.handle(event, env: env), env: env, event: event)
    }

    /// 18+ after the DragGesture died on the second finger: feed the remaining finger's location as pan samples.
    /// While a zoom bounce runs it owns the offset (design M4 §4): the samples are dropped and the pan restarts from
    /// the finger's location once the bounce has settled (its travel during the bounce is not replayed).
    func synthesizePan(location: CGPoint, time: TimeInterval) {
        guard synthesizedPanStart != nil, !state.isZoomBouncing else { return }
        switch session.phase {
        case .idle, .released: restartPan(at: location, time: time); return
        default: break
        }
        guard let start = synthesizedPanStart else { return }
        let t = CGSize(width: location.x - start.x, height: location.y - start.y)
        isFeedingSynthesizedSample = true
        handle(.dragChanged(translation: t, startLocation: start, time: time))
        isFeedingSynthesizedSample = false
        synthesizedPanStart = start
    }

    /// The zoom bounce moved the offset while pan writes were dropped: a still-dragging pan continues from here.
    private func rebaseAfterBounce() {
        guard case .dragging = session.phase else { return }
        session.rebase(presentation: state.peek.presentationOffset, translation: lastPanTranslation,
                       env: environment())
        tracker.reset()
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
                if isSequenceActive { pinchOwnedPan = true }
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

    /// One finger lifted: the pan continues from the remaining finger without a jump (design M4 §4). The finger's
    /// samples from the pinch are not a pan: the tracker restarts, so a lift right after never flings.
    private func handOffToPan(remaining: CGPoint?, time: TimeInterval) {
        if remaining != nil { pinchOwnedPan = false }
        if case .dragging = session.phase {
            session.rebase(presentation: state.peek.presentationOffset, translation: lastPanTranslation,
                           env: environment())
            tracker.reset()
        } else if let remaining {
            // The DragGesture died when the second finger landed (or both fingers landed together and the pan ignored
            // the sequence): restart the pan right at the remaining finger. Not while the release bounce runs: that
            // touch-down would catch (cancel) it; `synthesizePan` restarts the pan where the finger is once it settled.
            if case .ignored = session.phase { _ = session.handle(.touchesEnded(time: time), env: environment()) }
            if state.isZoomBouncing {
                synthesizedPanStart = remaining
            } else {
                restartPan(at: remaining, time: time)
            }
        }
        if remaining != nil {
            panContinuedFromPinch = true
            // Nobody took the finger (arbitrated to the container, scrolling disabled): an overscroll the pinch left
            // has no pan to spring it back, so the pan's own rubber-band return runs now (a deceleration, as after a
            // pan release; the scale is already in range).
            if case .dragging = session.phase {} else { springBackOverscrollWithoutPan() }
        }
    }

    private func springBackOverscrollWithoutPan() {
        let s = state.peek
        guard !state.isZoomBouncing else { return }
        let o = s.presentationOffset, c = makeZoomGeometry().clamped(o, at: s.presentationZoom)
        guard c != o else { return }
        let time = state.now()
        func axis(_ from: CGFloat, _ to: CGFloat) -> AxisMotion {
            from == to ? .rest(position: from) : .spring(CriticalSpring(origin: from, target: to), start: time)
        }
        state.beginDeceleration(x: axis(o.x, c.x), y: axis(o.y, c.y), at: time, displayScale: settings.displayScale)
    }

    private func restartPan(at location: CGPoint, time: TimeInterval) {
        handle(.touchDown(location: location, time: time, touchCount: 1))
        handle(.dragChanged(translation: .zero, startLocation: location, time: time))
        synthesizedPanStart = location
        panContinuedFromPinch = true
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
