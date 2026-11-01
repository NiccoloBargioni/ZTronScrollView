import CoreGraphics
import Foundation

/// A finger-free motion on one axis, sampled by the frame clock as a pure function of absolute time (`s`).
///
/// Every case is closed form; the edge crossing of a decay is precomputed at release, so sampling never integrates
/// and any instant can be evaluated independently. `start`, ``EdgeHandoff/crossingTime`` and every sample time must
/// come from one clock (see "Clocks" in `ZTronScrollPhysics.swift`); any epoch works.
public enum AxisMotion: Sendable, Equatable {
    /// Not moving.
    case rest(position: CGFloat)
    /// Exponential deceleration started at absolute time `start`; `handoff` describes a precomputed edge crossing.
    case decay(Decay, start: TimeInterval, handoff: EdgeHandoff?)
    /// Critically damped spring started at absolute time `start`.
    case spring(CriticalSpring, start: TimeInterval)

    /// A decay whose rest point lies past an edge (SPEC S6 "Decay that crosses an edge").
    public struct EdgeHandoff: Sendable, Equatable {
        /// Absolute crossing time in `s`: `start + decay.time(toReach: edge)`.
        public var crossingTime: TimeInterval
        /// The crossed edge in `pt`.
        public var edge: CGFloat
        /// `true` → spring from the edge back to it carrying the crossing velocity; `false` → stop at the edge.
        public var bounces: Bool

        public init(crossingTime: TimeInterval, edge: CGFloat, bounces: Bool) {
            self.crossingTime = crossingTime
            self.edge = edge
            self.bounces = bounces
        }
    }

    /// One sampled frame.
    public struct Sample: Sendable, Equatable {
        /// `pt`; exactly ``AxisMotion/endPosition`` once settled.
        public var position: CGFloat
        /// `pt/s`; `0` once settled.
        public var velocity: CGFloat
        /// The motion is over (the clock may stop).
        public var isSettled: Bool

        public init(position: CGFloat, velocity: CGFloat, isSettled: Bool) {
            self.position = position
            self.velocity = velocity
            self.isSettled = isSettled
        }
    }

    /// Samples the motion at absolute `time` (`s`). Times before the start sample the start state.
    ///
    /// - `.rest`: settled at its position.
    /// - `.decay`: the decay until `handoff.crossingTime`; at/after it, a `CriticalSpring(origin: edge, target: edge,
    ///   initialVelocity: decay.velocity(at: tc − start))` started at `tc`, or `.rest(edge)` without bounce.
    ///   Without a handoff it settles after `decay.duration(thresholds:)` at `decay.stopPosition(thresholds:)`.
    /// - `.spring`: settles after `settlingTime(thresholds:)`.
    ///
    /// Settled samples report ``endPosition`` exactly and zero velocity (no drift). Sampling at exactly
    /// `start + settlingTime` settles for any clock magnitude (the comparison allows a few ulps of `time`).
    public func sample(at time: TimeInterval, thresholds: RestThresholds = .init()) -> Sample {
        let tolerance = settleTolerance(at: time)
        switch self {
        case let .rest(position):
            return Sample(position: position, velocity: 0, isSettled: true)

        case let .spring(spring, start):
            return Self.sample(spring, elapsed: time - start, thresholds: thresholds, tolerance: tolerance)

        case let .decay(decay, start, handoff):
            if let handoff, !time.isNaN, time >= handoff.crossingTime {
                guard handoff.bounces else {
                    return Sample(position: handoff.edge, velocity: 0, isSettled: true)
                }
                return Self.sample(Self.handoffSpring(decay, start: start, handoff: handoff),
                                   elapsed: time - handoff.crossingTime, thresholds: thresholds, tolerance: tolerance)
            }
            let t = sanitizedElapsed(time - start)
            if handoff == nil, t >= decay.duration(thresholds: thresholds) - tolerance {
                return Sample(position: decay.stopPosition(thresholds: thresholds), velocity: 0, isSettled: true)
            }
            return Sample(position: decay.position(at: t), velocity: decay.velocity(at: t), isSettled: false)
        }
    }

    /// Where the motion ends, in `pt` (default ``RestThresholds``; a natural decay ends at its
    /// ``Decay/stopPosition(thresholds:)``, not at the analytic rest point).
    public var endPosition: CGFloat {
        switch self {
        case let .rest(position): return position
        case let .spring(spring, _): return spring.target
        case let .decay(decay, _, handoff): return handoff?.edge ?? decay.stopPosition()
        }
    }

    /// UIKit's `willDecelerate`: `true` for every case except `.rest` (a release out of bounds springs back and
    /// counts as decelerating, SPEC S6).
    public var willDecelerate: Bool {
        if case .rest = self { return false }
        return true
    }

    /// The spring that takes over at an edge crossing: from the edge back to it, seeded with the decay's velocity at
    /// the crossing (C¹ continuity).
    public static func handoffSpring(_ decay: Decay, start: TimeInterval, handoff: EdgeHandoff) -> CriticalSpring {
        let v = decay.velocity(at: handoff.crossingTime - start)
        return CriticalSpring(origin: handoff.edge, target: handoff.edge, initialVelocity: v)
    }

    private static func sample(_ spring: CriticalSpring, elapsed: TimeInterval, thresholds: RestThresholds,
                               tolerance: TimeInterval) -> Sample {
        let t = sanitizedElapsed(elapsed)
        if t >= spring.settlingTime(thresholds: thresholds) - tolerance {
            return Sample(position: spring.target, velocity: 0, isSettled: true)
        }
        return Sample(position: spring.position(at: t), velocity: spring.velocity(at: t), isSettled: false)
    }
}

/// Everything ``ReleaseSolver`` needs at finger lift on one axis.
public struct ReleaseContext: Sendable, Equatable {
    /// Offset at lift in `pt`.
    public var origin: CGFloat
    /// Release velocity in `pt/s` (after fling combination).
    public var velocity: CGFloat
    /// Offset bounds at the current zoom scale.
    public var bounds: AxisBounds
    /// Deceleration rate.
    public var rate: DecelerationRate
    /// Resolved bounce for this axis (``BounceConfiguration/resolve(isAxisEnabled:isScrollable:)``).
    public var bounces: Bool
    /// Rest thresholds.
    public var thresholds: RestThresholds
    /// Target resolved by the scroll-target behavior, then the delegate's `willEndDragging` (`nil` = natural).
    public var target: CGFloat?
    /// `pt/s`: the finger's last movement velocity in content direction, *not* gated by the 250 pt/s deceleration
    /// threshold and not zeroed by a pause before the lift (``VelocityTracker/lastMotionVelocity``). Seeds the
    /// spring-back when released out of bounds. Defaults to `velocity`.
    public var rubberBandVelocity: CGFloat

    public init(origin: CGFloat, velocity: CGFloat, bounds: AxisBounds, rate: DecelerationRate = .normal,
                bounces: Bool = true, thresholds: RestThresholds = .init(), target: CGFloat? = nil,
                rubberBandVelocity: CGFloat? = nil) {
        self.origin = origin
        self.velocity = velocity
        self.bounds = bounds
        self.rate = rate
        self.bounces = bounces
        self.thresholds = thresholds
        self.target = target
        self.rubberBandVelocity = rubberBandVelocity ?? velocity
    }
}

/// Chooses the motion after a finger lift or a programmatic animated command (SPEC S6).
public enum ReleaseSolver: Sendable {
    /// The spring-back from a rubber band, calibrated against UIKit (docs/design/PHYSICS-calibration.md): with
    /// `A = origin − edge` the native return is `x(t) = edge + (A + v·t)·e^(−ωt)`, `ω = 10.9`, where `v` is the pan's
    /// last raw finger velocity in content direction (a pause before lifting does not zero it; a 2.7 pt overscroll
    /// released after dragging outward at 400 pt/s first moves 5 pt further out). The same form as the edge hand-off
    /// after a fling (`A = 0`, `v` = crossing velocity). In ``CriticalSpring`` terms (`B = v₀ + ωA`) the seed is
    /// `v₀ = v + ω·(edge − origin)`.
    public static func bounceBack(origin: CGFloat, edge: CGFloat, rubberBandVelocity v: CGFloat) -> CriticalSpring {
        let omega = CriticalSpring.defaultStiffness.squareRoot()
        return CriticalSpring(origin: origin, target: edge, initialVelocity: v.finiteOrZero + omega * (edge - origin))
    }
    /// SPEC S6 order:
    /// 1. Origin out of bounds → ``bounceBack(origin:edge:rubberBandVelocity:)`` to the nearest edge (counts as
    ///    decelerating).
    /// 2. Target given → clamped to `bounds`; `.rest(target)` when already there with
    ///    `|v| < thresholds.negligibleReleaseVelocity`; else a re-solved decay that lands exactly on it
    ///    (``Decay/retargeted(origin:initialVelocity:target:thresholds:)``); else the spring of
    ///    ``targetSpring(origin:target:velocity:bounds:bounces:)``, which never passes the target and, without bounce,
    ///    never leaves `bounds`.
    /// 3. Natural → `.rest(origin)` when `|v| < thresholds.negligibleReleaseVelocity` (the same "`v₀ ≈ 0`" as the
    ///    target path; pixel-snapped by the caller) or the decay's duration is `0`; else a decay with an
    ///    ``AxisMotion/EdgeHandoff`` when its rest point exits `bounds`.
    ///
    /// Non-finite `origin` / `velocity` count as `0`; a non-finite `time` counts as `0`.
    public static func resolve(_ ctx: ReleaseContext, at time: TimeInterval) -> AxisMotion {
        let bounds = ctx.bounds
        let origin = ctx.origin.finiteOrZero
        let v = ctx.velocity.finiteOrZero
        let start = time.isFinite ? time : 0

        if bounds.overscroll(of: origin) != 0 {
            let edge = bounds.clamped(origin)
            return .spring(bounceBack(origin: origin, edge: edge, rubberBandVelocity: ctx.rubberBandVelocity), start: start)
        }

        if let rawTarget = ctx.target, rawTarget.isFinite {
            let target = bounds.clamped(rawTarget)
            if abs(target - origin) < ctx.thresholds.distance, abs(v) < ctx.thresholds.negligibleReleaseVelocity {
                return .rest(position: target)
            }
            if let decay = Decay.retargeted(origin: origin, initialVelocity: v, target: target,
                                            thresholds: ctx.thresholds) {
                return .decay(decay, start: start, handoff: nil)
            }
            return .spring(targetSpring(origin: origin, target: target, velocity: v, bounds: bounds,
                                        bounces: ctx.bounces),
                           start: start)
        }

        if abs(v) < ctx.thresholds.negligibleReleaseVelocity { return .rest(position: origin) }
        let decay = Decay(origin: origin, initialVelocity: v, rate: ctx.rate)
        if decay.duration(thresholds: ctx.thresholds) == 0 { return .rest(position: origin) }
        let rest = decay.restPosition
        guard bounds.overscroll(of: rest) != 0 else { return .decay(decay, start: start, handoff: nil) }
        let edge = rest < bounds.min ? bounds.min : bounds.max
        guard let crossing = decay.time(toReach: edge) else { return .decay(decay, start: start, handoff: nil) }
        let handoff = AxisMotion.EdgeHandoff(crossingTime: start + crossing, edge: edge, bounces: ctx.bounces)
        return .decay(decay, start: start, handoff: handoff)
    }

    /// The target-path fallback spring (SPEC S6: "a critically damped spring seeded with v₀"), shaped so it never
    /// passes the target (a snap or page boundary) and, without bounce, never leaves `bounds`. With `Δ = target − x₀`,
    /// `A = −Δ`, `B = v₀ + ω·A` and `ω₀ = √CriticalSpring.defaultStiffness`:
    ///
    /// - **Toward the target** (`v₀·Δ > 0`): `ω = max(ω₀, |v₀/Δ|)`. Then `B = v₀ − ω·Δ` is `0` or has the sign of
    ///   `A`, so `A + B·t` never changes sign: the motion approaches the target monotonically from the origin side
    ///   (no overshoot, stays between origin and target) and still starts with `v(0) = v₀` (C¹ at release). This is
    ///   the softest critically damped spring that does not overshoot; when `|v₀/Δ| > ω₀` it has `B = 0`, i.e. the
    ///   exponential `x = target − Δ·e^(−ω·t)` (the re-solved decay with the too-strong rate `r′ < 0.98`).
    /// - **Away from the target, or `Δ = 0`** (`v₀·Δ ≤ 0`, `v₀ ≠ 0`): `ω = ω₀`. `B` has the sign of `A`, so the motion
    ///   never crosses the target; it first travels on beyond the origin by the excursion
    ///   `E = (|B|/ω)·e^(ω|A|/|B| − 1) − |A|` (increasing in `|v₀|`), then returns. With `bounces == false` and
    ///   `E` larger than the room to the edge in the direction of `v₀`, `|v₀|` is reduced by bisection until
    ///   `E ≤ room` (the content meets the wall, like a decay that stops at an edge). With bounce, an excursion past
    ///   the edge is a bounce.
    /// - `v₀ = 0`: the plain spring `ω₀` (monotone, no overshoot).
    static func targetSpring(origin: CGFloat, target: CGFloat, velocity v: CGFloat, bounds: AxisBounds,
                             bounces: Bool) -> CriticalSpring {
        let omega0 = CriticalSpring.defaultStiffness.squareRoot()
        let delta = target - origin
        if v * delta > 0 {
            let omega = Swift.max(omega0, abs(v / delta))
            let stiffness = omega == omega0 ? CriticalSpring.defaultStiffness : omega * omega
            return CriticalSpring(origin: origin, target: target, initialVelocity: v, stiffness: stiffness)
        }
        let plain = CriticalSpring(origin: origin, target: target, initialVelocity: v)
        guard v != 0, !bounces else { return plain }

        let a = abs(delta)
        let room = Swift.max(0, v > 0 ? bounds.max - origin : origin - bounds.min)
        func excursion(_ speed: CGFloat) -> CGFloat {
            let b = speed + omega0 * a                                   // |B|
            guard b > 0 else { return 0 }
            return Swift.max(0, (b / omega0) * exp(omega0 * a / b - 1) - a)
        }
        guard excursion(abs(v)) > room else { return plain }
        var lo: CGFloat = 0, hi = abs(v)                                 // excursion(lo) ≤ room < excursion(hi)
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if excursion(mid) <= room { lo = mid } else { hi = mid }
        }
        return CriticalSpring(origin: origin, target: target, initialVelocity: lo * v.signum)
    }

    /// Programmatic `animated:` path (UIKit-like, ~0.3 s): a critically damped spring from `from` to `to` (`pt`)
    /// seeded with `velocity` (`pt/s`; retargeting preserves velocity, SPEC S6) whose stiffness is solved by bisection
    /// on `ln ω` so that `settlingTime(thresholds:) ≈ duration` (`s`).
    ///
    /// A non-positive or non-finite duration, or `from == to` with zero velocity, returns `.rest(to)`.
    public static func animated(from: CGFloat, velocity: CGFloat, to: CGFloat, duration: TimeInterval,
                                at time: TimeInterval, thresholds: RestThresholds = .init()) -> AxisMotion {
        let from = from.finiteOrZero, to = to.finiteOrZero, v = velocity.finiteOrZero
        let start = time.isFinite ? time : 0
        guard duration.isFinite, duration > 0 else { return .rest(position: to) }
        if from == to, v == 0 { return .rest(position: to) }

        func settling(_ logOmega: CGFloat) -> TimeInterval {
            let omega = exp(logOmega)
            return CriticalSpring(origin: from, target: to, initialVelocity: v, stiffness: omega * omega)
                .settlingTime(thresholds: thresholds)
        }
        // ω ∈ [0.01, 10 000] /s; settling time decreases as ω grows.
        var lo: CGFloat = log(0.01), hi: CGFloat = log(10_000)
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if settling(mid) > duration { lo = mid } else { hi = mid }
        }
        let omega = exp(hi)
        return .spring(CriticalSpring(origin: from, target: to, initialVelocity: v, stiffness: omega * omega),
                       start: start)
    }
}
