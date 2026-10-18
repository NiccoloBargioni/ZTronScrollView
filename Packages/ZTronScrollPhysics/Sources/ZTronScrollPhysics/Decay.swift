import CoreGraphics
import Foundation

/// UIKit-style exponential deceleration on one axis (SPEC S6 "Release in bounds").
///
/// With `k = 1000 · ln r` (`1/s`, negative) and `r^(1000·t) = e^(k·t)`:
///
///     x(t) = x₀ + v₀ · (e^(k·t) − 1) / k        [pt]
///     v(t) = v₀ · e^(k·t)                        [pt/s]
///     x(∞) = x₀ − v₀ / k                         (rest point)
///
/// Non-finite `origin` / `initialVelocity` become `0`; `t < 0` (or `NaN`) samples `t = 0`; `t = +∞` samples the
/// rest point.
public struct Decay: Sendable, Equatable {
    /// `x₀` in `pt`.
    public var origin: CGFloat
    /// `v₀` in `pt/s`.
    public var initialVelocity: CGFloat
    /// Deceleration rate `r` per ms.
    public var rate: DecelerationRate
    /// `true` for a re-solved decay (``retargeted(origin:initialVelocity:target:thresholds:)``): it runs until the
    /// remaining distance is below `thresholds.distance` and ends exactly on ``restPosition`` (a snap or page
    /// boundary). `false` (natural fling): it ends where `|v|` falls under `thresholds.velocity` and stays there
    /// (``stopPosition(thresholds:)``), like UIKit, which leaves the last ≈ 5 pt of the analytic rest untraveled
    /// rather than jumping to it (docs/design/PHYSICS-calibration.md).
    public var landsOnRestPosition: Bool

    public init(origin: CGFloat, initialVelocity: CGFloat, rate: DecelerationRate = .normal,
                landsOnRestPosition: Bool = false) {
        self.origin = origin.finiteOrZero
        self.initialVelocity = initialVelocity.finiteOrZero
        self.rate = rate
        self.landsOnRestPosition = landsOnRestPosition
    }

    /// `x(t) = x₀ + v₀ · (e^(k·t) − 1) / k` in `pt` (evaluated with `expm1` for precision near `t = 0`).
    public func position(at t: TimeInterval) -> CGFloat {
        let t = sanitizedElapsed(t)
        guard initialVelocity != 0 else { return origin }
        if t == .infinity { return restPosition }
        let k = rate.k
        return origin + initialVelocity * expm1(k * CGFloat(t)) / k
    }

    /// `v(t) = v₀ · e^(k·t)` in `pt/s`.
    public func velocity(at t: TimeInterval) -> CGFloat {
        let t = sanitizedElapsed(t)
        guard initialVelocity != 0, t != .infinity else { return 0 }
        return initialVelocity * exp(rate.k * CGFloat(t))
    }

    /// Rest point `x₀ − v₀ / k` in `pt`.
    public var restPosition: CGFloat { origin + restDisplacement }

    /// Total travel `−v₀ / k` in `pt` (same sign as `v₀`).
    public var restDisplacement: CGFloat { -initialVelocity / rate.k }

    /// First `t ≥ 0` (`s`) with `position(t) == x`: `t = ln(1 + k·(x − x₀)/v₀) / k`.
    ///
    /// `0` when `x == x₀`; `nil` when `x` is never reached (opposite side of the motion, at or beyond the rest point,
    /// `v₀ = 0`, or non-finite `x`).
    public func time(toReach x: CGFloat) -> TimeInterval? {
        guard x.isFinite else { return nil }
        let delta = x - origin
        if delta == 0 { return 0 }
        guard initialVelocity != 0, delta.signum == initialVelocity.signum else { return nil }
        let k = rate.k
        let u = k * delta / initialVelocity           // in (−1, 0) when reachable
        guard u > -1 else { return nil }
        let t = log1p(u) / k
        return t.isFinite ? TimeInterval(Swift.max(0, t)) : nil
    }

    /// Time (`s`) at which `|v|` falls to `speed` (`pt/s`): `ln(speed / |v₀|) / k`.
    ///
    /// `0` when `|v₀| ≤ speed`; `+∞` when `speed ≤ 0` or is `NaN` (an exponential never reaches zero).
    public func time(toSlowTo speed: CGFloat) -> TimeInterval {
        let v0 = abs(initialVelocity)
        guard !speed.isNaN, speed > 0 else { return v0 == 0 ? 0 : .infinity }
        guard v0 > speed else { return 0 }
        return TimeInterval(log(speed / v0) / rate.k)
    }

    /// Time (`s`) after which the motion counts as stopped.
    ///
    /// - Natural (`landsOnRestPosition == false`): `time(toSlowTo: thresholds.velocity)` (UIKit: ≈ 10 pt/s).
    /// - Re-solved: both `|v| < thresholds.velocity` and the remaining distance `|x(∞) − x(t)| = |v(t)| / |k| <
    ///   thresholds.distance`, i.e. `time(toSlowTo: min(thresholds.velocity, thresholds.distance · |k|))`.
    public func duration(thresholds: RestThresholds = .init()) -> TimeInterval {
        guard landsOnRestPosition else { return time(toSlowTo: thresholds.velocity) }
        let speed = Swift.min(thresholds.velocity, thresholds.distance * abs(rate.k))
        return time(toSlowTo: speed)
    }

    /// Where the motion ends (`pt`): ``restPosition`` for a re-solved decay, else `position(at: duration)` — the
    /// offset at which `|v|` dropped under `thresholds.velocity` (the untraveled remainder is `≈ velocity / |k|`,
    /// 5 pt at `.normal`; the caller pixel-snaps it).
    public func stopPosition(thresholds: RestThresholds = .init()) -> CGFloat {
        landsOnRestPosition ? restPosition : position(at: duration(thresholds: thresholds))
    }

    /// A decay from `origin` with `initialVelocity` whose rest point is exactly `target` (SPEC S6 re-solve):
    ///
    ///     Δ = target − x₀,   r′ = exp(−v₀ / (1000 · Δ))   ⇒   x₀ − v₀ / k′ = x₀ + Δ = target
    ///
    /// Returns `nil` (the caller falls back to a critically damped spring seeded with `v₀`) when `Δ == 0`,
    /// `sign(Δ) ≠ sign(v₀)`, `|v₀| < thresholds.negligibleReleaseVelocity`, any input is non-finite, or
    /// `r′ ∉ DecelerationRate.plausibleRange` (`0.98…0.9995`).
    public static func retargeted(origin: CGFloat, initialVelocity: CGFloat, target: CGFloat,
                                  thresholds: RestThresholds = .init()) -> Decay? {
        guard origin.isFinite, initialVelocity.isFinite, target.isFinite else { return nil }
        let delta = target - origin
        guard delta != 0,
              abs(initialVelocity) >= thresholds.negligibleReleaseVelocity,
              delta.signum == initialVelocity.signum else { return nil }
        let r = exp(-initialVelocity / (1000 * delta))
        guard r.isFinite, DecelerationRate.plausibleRange.contains(r) else { return nil }
        return Decay(origin: origin, initialVelocity: initialVelocity, rate: DecelerationRate(perMillisecond: r),
                     landsOnRestPosition: true)
    }
}
