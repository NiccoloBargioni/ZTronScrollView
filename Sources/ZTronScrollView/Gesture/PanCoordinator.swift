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
    #if DEBUG
    var effectsLog: [PanEffect] = []
    #endif

    init(state: ZTronScrollState, axes: Axis.Set) {
        self.state = state
        self.axes = axes
    }

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
        let gx = AxisGeometry(viewportLength: m.viewportSize.width, unscaledContentLength: m.contentSize.width,
                              alignment: state.contentAlignment.x)
        let gy = AxisGeometry(viewportLength: m.viewportSize.height, unscaledContentLength: m.contentSize.height,
                              alignment: state.contentAlignment.y)
        let bx = gx.bounds(at: z), by = gy.bounds(at: z)
        var env = PanEnvironment()
        env.axes = axes
        env.isScrollEnabled = state.isScrollEnabled && settings.isScrollEnabled && nativeScrollEnabled
        env.isDirectionalLockEnabled = state.isDirectionalLockEnabled
        env.presentationOffset = s.presentationOffset
        env.boundsX = bx
        env.boundsY = by
        env.bouncesX = BounceConfiguration(behavior: settings.bounceX, bounces: state.bounces,
                                           alwaysBounce: state.alwaysBounceHorizontal)
            .resolve(isAxisEnabled: axes.contains(.horizontal), isScrollable: bx.isScrollable)
        env.bouncesY = BounceConfiguration(behavior: settings.bounceY, bounces: state.bounces,
                                           alwaysBounce: state.alwaysBounceVertical)
            .resolve(isAxisEnabled: axes.contains(.vertical), isScrollable: by.isScrollable)
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
                if pendingBegin, hypot(p.x - state.peek.presentationOffset.x, p.y - state.peek.presentationOffset.y) > 0.01 {
                    pendingBegin = false
                    state.beginDragging()
                }
                state.writeDragOffset(p)
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
}
