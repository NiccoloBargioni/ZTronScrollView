import CoreGraphics
import Foundation

/// Critically damped spring with mass 1 on one axis (SPEC S6 "Spring starting point").
///
/// With `ω = √stiffness` (`1/s`), `A = x₀ − target` and `B = v₀ + ω·A`:
///
///     x(t) = target + (A + B·t) · e^(−ω·t)          [pt]
///     v(t) = (B − ω·(A + B·t)) · e^(−ω·t)           [pt/s]   (v(0) = v₀)
///
/// The motion crosses the target at most once (`A + B·t` is linear), so a spring seeded with velocity toward the
/// target overshoots at most once and returns without oscillating. Non-finite inputs become `0`; a non-finite or
/// non-positive stiffness falls back to `100`.
public struct CriticalSpring: Sendable, Equatable {
    /// `x₀` in `pt`.
    public var origin: CGFloat
    /// Rest position in `pt`.
    public var target: CGFloat
    /// `v₀` in `pt/s`.
    public var initialVelocity: CGFloat
    /// `ω²` in `1/s²` (mass 1). `100` → `ω = 10 /s`; calibrate against the native feel.
    public var stiffness: CGFloat

    /// Calibrated against a native `ScrollView` (docs/design/PHYSICS-calibration.md): both the rubber-band return and
    /// the edge bounce after a fling fit `ω ≈ 10.9 /s` → `119 /s²` (SPEC S6 starting point was `100`).
    public static let defaultStiffness: CGFloat = 119

    public init(origin: CGFloat, target: CGFloat, initialVelocity: CGFloat = 0,
                stiffness: CGFloat = CriticalSpring.defaultStiffness) {
        self.origin = origin.finiteOrZero
        self.target = target.finiteOrZero
        self.initialVelocity = initialVelocity.finiteOrZero
        self.stiffness = stiffness.positive(or: Self.defaultStiffness)
    }

    /// `ω = √stiffness` in `1/s`.
    public var omega: CGFloat { stiffness.positive(or: Self.defaultStiffness).squareRoot() }

    private var a: CGFloat { origin - target }
    private var b: CGFloat { initialVelocity + omega * a }

    /// `x(t) = target + (A + B·t) · e^(−ω·t)` in `pt`. `t ≤ 0` returns `origin` exactly; `t = +∞` returns `target`.
    public func position(at t: TimeInterval) -> CGFloat {
        let t = sanitizedElapsed(t)
        if t == 0 { return origin }
        guard t != .infinity else { return target }
        let tt = CGFloat(t)
        let value = target + (a + b * tt) * exp(-omega * tt)
        return value.isFinite ? value : target
    }

    /// `v(t) = (B − ω·(A + B·t)) · e^(−ω·t)` in `pt/s`. `t ≤ 0` returns `v₀` exactly; `t = +∞` returns `0`.
    public func velocity(at t: TimeInterval) -> CGFloat {
        let t = sanitizedElapsed(t)
        if t == 0 { return initialVelocity }
        guard t != .infinity else { return 0 }
        let tt = CGFloat(t)
        let w = omega
        let value = (b - w * (a + b * tt)) * exp(-w * tt)
        return value.isFinite ? value : 0
    }

    /// True when `|x(t) − target| < thresholds.distance` and `|v(t)| < thresholds.velocity` at this instant.
    public func isSettled(at t: TimeInterval, thresholds: RestThresholds = .init()) -> Bool {
        abs(position(at: t) - target) < thresholds.distance && abs(velocity(at: t)) < thresholds.velocity
    }

    /// Smallest `t` (`s`) after which the spring stays settled: `max(T_x, T_v)` where `T_x` is the last time
    /// `|A + B·t|·e^(−ω·t) ≥ distance` and `T_v` the last time `|v₀ − ω·B·t|·e^(−ω·t) ≥ velocity`.
    ///
    /// Each envelope `|P + Q·t|·e^(−ω·t)` is strictly decreasing after `t* = 1/ω − P/Q`, so the crossing is
    /// bracketed analytically (initial upper bound `(ln(|P| + |Q|/ω) − ln(tol))/ω + 1/ω`, doubled until it holds) and
    /// refined by bisection on the closed form (≤ 40 iterations). Not integration.
    public func settlingTime(thresholds: RestThresholds = .init()) -> TimeInterval {
        let w = omega
        let tx = Self.lastTimeAtOrAbove(p: a, q: b, omega: w, threshold: thresholds.distance)
        let tv = Self.lastTimeAtOrAbove(p: initialVelocity, q: -w * b, omega: w, threshold: thresholds.velocity)
        return Swift.max(tx, tv)
    }

    /// Last `t ≥ 0` with `g(t) = |p + q·t|·e^(−ω·t) ≥ threshold` (`0` when `g < threshold` everywhere on `t ≥ 0`).
    /// The returned time is the upper end of the bisection bracket, so `g(result) < threshold`.
    static func lastTimeAtOrAbove(p: CGFloat, q: CGFloat, omega: CGFloat, threshold: CGFloat) -> TimeInterval {
        func g(_ t: CGFloat) -> CGFloat { abs(p + q * t) * exp(-omega * t) }
        guard threshold > 0, omega > 0 else { return 0 }

        // g is decreasing on [lo, ∞): lo = max(0, t*), t* = 1/ω − p/q (or 0 when q == 0).
        let tStar: CGFloat = q == 0 ? 0 : 1 / omega - p / q
        let lo = Swift.max(0, tStar.finiteOrZero)

        if g(lo) >= threshold {
            // Seed with the analytic estimate, then double the bracket until g(hi) < threshold.
            let seed = (log((abs(p) + abs(q) / omega) / threshold)) / omega + 1 / omega
            var hi = Swift.max(lo + 1 / omega, seed.finiteOrZero)
            var doublings = 0
            while g(hi) >= threshold, doublings < 64 {
                hi = lo + 2 * (hi - lo)
                doublings += 1
            }
            return TimeInterval(bisect(g, threshold: threshold, lo: lo, hi: hi))
        }

        // On [0, lo] g first decreases to its zero t₀ = −p/q, then rises to g(lo) < threshold: the only possible
        // crossing is in the decreasing part [0, t₀].
        guard g(0) >= threshold, q != 0 else { return 0 }
        let tZero = -p / q
        guard tZero > 0, tZero.isFinite else { return 0 }
        return TimeInterval(bisect(g, threshold: threshold, lo: 0, hi: tZero))
    }

    /// Bisection on a function decreasing through `threshold` in `[lo, hi]` (`g(lo) ≥ threshold > g(hi)`).
    private static func bisect(_ g: (CGFloat) -> CGFloat, threshold: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        var lo = lo, hi = hi
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if g(mid) >= threshold { lo = mid } else { hi = mid }
        }
        return hi
    }
}
