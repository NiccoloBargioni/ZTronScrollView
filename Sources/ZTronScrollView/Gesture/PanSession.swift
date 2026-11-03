import SwiftUI
import ZTronScrollPhysics
import ScrollArbitration

// Pure pan state machine (design M3-pan §2-3). No SwiftUI views, no state object, no clock: the coordinator (part b)
// feeds gesture values and applies the returned effects.

enum PanEvent: Equatable {
    /// Observer; may be missing on iOS 17 and older for fast swipes (a `dragChanged` then synthesizes it).
    case touchDown(location: CGPoint, time: TimeInterval, touchCount: Int)
    /// Pan `DragGesture` recognized (>= 10 pt): the first one is the recognition sample.
    case dragChanged(translation: CGSize, startLocation: CGPoint, time: TimeInterval)
    /// `fallbackVelocity`: `DragGesture.Value.velocity` (17+), used only when the tracker has < 2 samples.
    case dragEnded(translation: CGSize, time: TimeInterval, fallbackVelocity: CGVector?)
    /// Last finger up (observer); ends a sequence that never became a drag.
    case touchesEnded(time: TimeInterval)
    case frame(time: TimeInterval)
    case cancelled
    /// The UIKit pan's `shouldBegin` answered false (D60, UIKit path only): at most once per sequence, from `UIKitPanCore`.
    /// A caught motion settles; nothing else happens until the touch ends.
    case declined
}

/// Cold snapshot taken by the coordinator before each event.
struct PanEnvironment: Equatable {
    var axes: Axis.Set = [.horizontal, .vertical]
    var isScrollEnabled = true
    var isDirectionalLockEnabled = false
    var presentationOffset: CGPoint = .zero
    var boundsX = AxisBounds(min: 0, max: 0)
    var boundsY = AxisBounds(min: 0, max: 0)
    var bouncesX = true
    var bouncesY = true
    var viewport: CGSize = .zero
    /// Content moves without a finger (deceleration, bounce, animation) and nobody is tracking.
    var isMovingWithoutFinger = false
    var hasArbiter = false
    /// Container role (NESTED §3): a nested `ZTronScrollView` is registered with our arbiter, so the swipe is
    /// arbitrated at the hysteresis exactly as with `hasArbiter`.
    var isContainer = false
    /// Tracking begins at the owner decision (D7) when either side of a nested pair is involved.
    var arbitrates: Bool { hasArbiter || isContainer }
    /// `ZTronScrollState.lastInterruptedVelocity`, read at recognition (after the catch's `interrupt()`).
    var interruptedVelocity: CGVector = .zero
    /// The recognizer's translation already excludes its hysteresis (the UIKit pan, F1): the recognition sample moves the
    /// content by its whole length. Read once per sequence, at touch-down.
    var translationExcludesHysteresis = false
}

enum PanEffect: Equatable {
    case catchMotion
    case beginTracking
    case askOwner(start: CGPoint, translation: CGSize, touchCount: Int)
    case beginDragging
    case setOffset(CGPoint)
    case release(ReleaseRequest)
    case endSequence
    /// A caught motion whose touch declined the UIKit pan (D60): it settles from where the catch stopped it with zero
    /// velocity (paging and targets snap, plain content stays) and no drag delegate callbacks.
    case settle
}

struct ReleaseRequest: Equatable {
    var origin: CGPoint
    var dragStart: CGPoint
    var liftTime: TimeInterval
    var fallbackVelocity: CGVector?
    /// Directional lock of the gesture (the other axis releases with zero velocity).
    var lock: Axis?
    /// Gesture began by catching a moving scroll view: time of the catch, and the velocity of the stopped motion.
    var caughtAt: TimeInterval?
    var caughtVelocity: CGVector = .zero
    /// Cancelled gesture: lift with velocity 0 (`liftTime` is NaN: the release uses the state clock).
    var zeroVelocity = false
}

struct PanSession: Equatable {
    struct Pending: Equatable {
        var down: TimeInterval
        var caught: Bool
        var startLocation: CGPoint
        var translation: CGSize
    }
    struct Drag: Equatable {
        var baseline: CGPoint
        var lock: Axis?
        var dragStart: CGPoint
        var caughtAt: TimeInterval?
        var caughtVelocity: CGVector
        var current: CGPoint
    }
    enum Phase: Equatable {
        case idle
        case touching(down: TimeInterval, caught: Bool)
        case awaitingDecision(Pending)
        case ignored
        case dragging(Drag)
        case released
    }

    var phase: Phase = .idle
    var rubberBandCoefficient: CGFloat = 0.55
    /// `DragGesture(minimumDistance:)` of the adapter. At recognition the content moves by the finger travel beyond
    /// this (native: a 128 pt first sample moves the content 117 pt; docs/design/PHYSICS-calibration.md), so only the
    /// hysteresis itself is "lost", never the whole recognition sample.
    var hysteresis: CGFloat = 10
    /// `PanEnvironment.translationExcludesHysteresis` of the current sequence, read at its touch-down.
    private(set) var creditsWholeFirstSample = false
    /// `.ignored` after an owner decision: the recognition sample, kept current, so the swipe can still become ours if
    /// the inner view it was decided for declines it (`revive(env:)`, asked only by this view's own nested arbiter).
    private(set) var yielded: Pending?

    // MARK: Events

    mutating func handle(_ event: PanEvent, env: PanEnvironment) -> [PanEffect] {
        if case .released = phase {
            switch event {
            case .touchesEnded, .frame, .cancelled, .dragEnded: phase = .idle; return []
            default: phase = .idle
            }
        }
        switch phase {
        case .idle, .released:
            return handleIdle(event, env: env)

        case let .touching(down, caught):
            switch event {
            case .declined:
                guard caught else { return [] }
                phase = .touching(down: down, caught: false)
                return [.settle]
            case let .dragChanged(translation, startLocation, _):
                let pending = Pending(down: down, caught: caught, startLocation: startLocation, translation: translation)
                if env.arbitrates {
                    phase = .awaitingDecision(pending)
                    return [.askOwner(start: startLocation, translation: translation, touchCount: 1)]
                }
                return beginDrag(pending, env: env, deferredTracking: false)
            case .dragEnded, .touchesEnded, .cancelled:
                phase = .idle
                return [.endSequence]
            default:
                return []
            }

        case var .awaitingDecision(pending):
            switch event {
            case let .dragChanged(translation, _, _):
                pending.translation = translation
                phase = .awaitingDecision(pending)
                return []
            case .dragEnded, .touchesEnded, .cancelled:
                phase = .idle
                return []
            default:
                return []
            }

        case .ignored:
            switch event {
            case let .dragChanged(translation, _, _): yielded?.translation = translation
            case .dragEnded, .touchesEnded, .cancelled: phase = .idle; yielded = nil
            default: break
            }
            return []

        case var .dragging(drag):
            switch event {
            case let .dragChanged(translation, _, _):
                let p = Self.offset(baseline: drag.baseline, translation: translation, lock: drag.lock, env: env)
                drag.current = p
                phase = .dragging(drag)
                return [.setOffset(p)]
            case let .dragEnded(translation, time, fallback):
                let p = Self.offset(baseline: drag.baseline, translation: translation, lock: drag.lock, env: env)
                phase = .released
                return [.setOffset(p), .release(request(drag, origin: p, time: time, fallback: fallback, zero: false))]
            case .cancelled:
                phase = .released
                return [.release(request(drag, origin: drag.current, time: .nan, fallback: nil, zero: true))]
            default:
                return []
            }
        }
    }

    /// One-finger lift after a pinch (design M4 §4): the baseline is rebuilt so that
    /// `offset(baseline, translation) == presentation`. Only while dragging; no effects.
    mutating func rebase(presentation: CGPoint, translation: CGSize, env: PanEnvironment) {
        guard case var .dragging(drag) = phase else { return }
        drag.baseline = Self.baseline(presentation: presentation, translation: translation, env: env,
                                      coefficient: rubberBandCoefficient, hysteresis: 0)
        drag.current = presentation
        phase = .dragging(drag)
    }

    /// Owner decision for an `.askOwner` effect, from this view's side: `.participant` = this view drags,
    /// `.container` = this view ignores the sequence (the coordinator maps the container role onto the same two
    /// answers: an inner that follows the swipe is `.container` here).
    mutating func decided(_ owner: ScrollOwner, env: PanEnvironment) -> [PanEffect] {
        guard case let .awaitingDecision(pending) = phase else { return [] }
        switch owner {
        case .participant: return beginDrag(pending, env: env, deferredTracking: true)
        case .container: phase = .ignored; yielded = pending; return []
        }
    }

    /// The inner view the swipe was decided for declined it after this view's ask (D60 §2 "Decline", the reverse of the
    /// order `NestedScrollArbiter.participantDeclined` assumes): the swipe is this view's after all, from its current
    /// sample. Nothing when this view is not waiting on such a decision.
    mutating func revive(env: PanEnvironment) -> [PanEffect] {
        guard case .ignored = phase, let pending = yielded else { return [] }
        yielded = nil
        return beginDrag(pending, env: env, deferredTracking: true)
    }

    private mutating func handleIdle(_ event: PanEvent, env: PanEnvironment) -> [PanEffect] {
        switch event {
        case let .touchDown(_, time, touchCount):
            creditsWholeFirstSample = env.translationExcludesHysteresis
            yielded = nil
            guard env.isScrollEnabled, !env.axes.isEmpty, touchCount < 2 else { phase = .ignored; return [] }
            let caught = env.isMovingWithoutFinger
            phase = .touching(down: time, caught: caught)
            var effects: [PanEffect] = caught ? [.catchMotion] : []
            if !env.arbitrates { effects.append(.beginTracking) }
            return effects
        case let .dragChanged(_, startLocation, time):
            // The observer missed the touch-down (iOS 17 and older): synthesize it, then recognize.
            var effects = handleIdle(.touchDown(location: startLocation, time: time, touchCount: 1), env: env)
            effects += handle(event, env: env)
            return effects
        default:
            return []
        }
    }

    private mutating func beginDrag(_ p: Pending, env: PanEnvironment, deferredTracking: Bool) -> [PanEffect] {
        // F1: UIKit's translation already excludes its hysteresis (U1 Q5), so the baseline is built from a zero
        // translation and the content moves by the whole recognition sample.
        let baseline = Self.baseline(presentation: env.presentationOffset,
                                     translation: creditsWholeFirstSample ? .zero : p.translation, env: env,
                                     coefficient: rubberBandCoefficient, hysteresis: hysteresis)
        var lock: Axis?
        if env.isDirectionalLockEnabled, env.axes.contains(.horizontal), env.axes.contains(.vertical) {
            let dx = abs(p.translation.width), dy = abs(p.translation.height)
            lock = dx >= 2 * dy ? .horizontal : (dy >= 2 * dx ? .vertical : nil)
        }
        let offset = Self.offset(baseline: baseline, translation: p.translation, lock: lock, env: env,
                                 coefficient: rubberBandCoefficient)
        phase = .dragging(Drag(baseline: baseline, lock: lock, dragStart: env.presentationOffset,
                               caughtAt: p.caught ? p.down : nil,
                               caughtVelocity: p.caught ? env.interruptedVelocity : .zero, current: offset))
        return (deferredTracking ? [.beginTracking] : []) + [.beginDragging, .setOffset(offset)]
    }

    private func request(_ d: Drag, origin: CGPoint, time: TimeInterval, fallback: CGVector?, zero: Bool) -> ReleaseRequest {
        ReleaseRequest(origin: origin, dragStart: d.dragStart, liftTime: time, fallbackVelocity: fallback,
                       lock: d.lock, caughtAt: d.caughtAt, caughtVelocity: d.caughtVelocity, zeroVelocity: zero)
    }

    // MARK: Pure formulas (design §3)

    private static func axisOffset(baseline: CGFloat, translation: CGFloat, bounds b: AxisBounds, bounces: Bool,
                                   viewport: CGFloat, coefficient: CGFloat) -> CGFloat {
        let raw = baseline - translation
        guard bounces else { return b.clamped(raw) }
        let rb = RubberBand(dimension: viewport, coefficient: coefficient)
        return b.clamped(raw) + rb.displacement(forOverscroll: b.overscroll(of: raw))
    }

    private static func isEnabled(_ axis: Axis, lock: Axis?, env: PanEnvironment) -> Bool {
        env.isScrollEnabled && env.axes.contains(axis == .horizontal ? .horizontal : .vertical)
            && (lock == nil || lock == axis)
    }

    /// offset = baseline - translation per axis (never accumulated), rubber-banded past the bounds.
    static func offset(baseline: CGPoint, translation: CGSize, lock: Axis?, env: PanEnvironment,
                       coefficient: CGFloat = 0.55) -> CGPoint {
        let p = env.presentationOffset
        let x = isEnabled(.horizontal, lock: lock, env: env)
            ? axisOffset(baseline: baseline.x, translation: translation.width, bounds: env.boundsX,
                         bounces: env.bouncesX, viewport: env.viewport.width, coefficient: coefficient)
            : p.x
        let y = isEnabled(.vertical, lock: lock, env: env)
            ? axisOffset(baseline: baseline.y, translation: translation.height, bounds: env.boundsY,
                         bounces: env.bouncesY, viewport: env.viewport.height, coefficient: coefficient)
            : p.y
        return CGPoint(x: x, y: y)
    }

    private static func axisBaseline(presentation p: CGFloat, translation: CGFloat, bounds b: AxisBounds,
                                     bounces: Bool, viewport: CGFloat, coefficient: CGFloat) -> CGFloat {
        var raw0 = p
        if bounces, b.overscroll(of: p) != 0 {
            let edge = b.nearestEdge(to: p)
            raw0 = edge + RubberBand(dimension: viewport, coefficient: coefficient).overscroll(forDisplacement: p - edge)
        }
        return raw0 + translation
    }

    /// Baseline at recognition (inverse rubber band when catching a bounce). With `hysteresis == 0`,
    /// `offset(translation0) == presentation` (used by `rebase`). With the gesture's hysteresis `h`, the recognition
    /// sample `t₀` is credited beyond the first `h` points: the baseline uses `t₀ · min(1, h / |t₀|)`, so the content
    /// moves by `|t₀| − h` in the direction of `t₀` at recognition — exactly what a `UIScrollView` does (the finger has
    /// already travelled that far; only the hysteresis is absorbed). Without this a fast flick lost up to a frame of
    /// travel and tracked one frame behind the finger.
    static func baseline(presentation: CGPoint, translation: CGSize, env: PanEnvironment,
                         coefficient: CGFloat = 0.55, hysteresis: CGFloat = 0) -> CGPoint {
        var t = translation
        let length = hypot(t.width, t.height)
        if hysteresis > 0, length > hysteresis {
            let f = hysteresis / length
            t = CGSize(width: t.width * f, height: t.height * f)
        }
        return CGPoint(
            x: axisBaseline(presentation: presentation.x, translation: t.width, bounds: env.boundsX,
                            bounces: env.bouncesX, viewport: env.viewport.width, coefficient: coefficient),
            y: axisBaseline(presentation: presentation.y, translation: t.height, bounds: env.boundsY,
                            bounces: env.bouncesY, viewport: env.viewport.height, coefficient: coefficient))
    }
}
