import CoreGraphics
import Foundation

/// Cubic Bézier timing curve through (0, 0), `p1`, `p2`, (1, 1) with `CAMediaTimingFunction` semantics: `x` is the
/// normalized time, `y` the progress.
public struct UnitBezier: Sendable, Equatable {
    public var p1: CGPoint
    public var p2: CGPoint

    public init(_ p1x: CGFloat, _ p1y: CGFloat, _ p2x: CGFloat, _ p2y: CGFloat) {
        p1 = CGPoint(x: p1x, y: p1y)
        p2 = CGPoint(x: p2x, y: p2y)
    }

    /// `UIView.AnimationCurve.easeInOut` / `kCAMediaTimingFunctionEaseInEaseOut`: (0.42, 0, 0.58, 1).
    public static let easeInOut = UnitBezier(0.42, 0, 0.58, 1)

    private static func bezier(_ a: CGFloat, _ b: CGFloat, _ u: CGFloat) -> CGFloat {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    private static func derivative(_ a: CGFloat, _ b: CGFloat, _ u: CGFloat) -> CGFloat {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }

    /// Progress at normalized time `x` (clamped to [0, 1]): Newton on the curve parameter, bisection when Newton
    /// does not converge. Exactly 0 at 0 and 1 at 1.
    public func value(at x: CGFloat) -> CGFloat {
        let x = min(1, max(0, x.finiteOrZero))
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var u = x
        for _ in 0..<8 {
            let residual = Self.bezier(p1.x, p2.x, u) - x
            if abs(residual) < 1e-7 { break }
            let d = Self.derivative(p1.x, p2.x, u)
            if abs(d) < 1e-6 { break }
            u = min(1, max(0, u - residual / d))
        }
        if abs(Self.bezier(p1.x, p2.x, u) - x) > 1e-6 {
            var lo: CGFloat = 0, hi: CGFloat = 1
            for _ in 0..<48 {
                u = (lo + hi) / 2
                if Self.bezier(p1.x, p2.x, u) < x { lo = u } else { hi = u }
            }
        }
        return Self.bezier(p1.y, p2.y, u)
    }
}

/// UIKit's programmatic zoom animation (`UIScrollView.setZoomScale(_:animated:)`, `zoom(to:animated:)`), measured on
/// iOS 27.0 (docs/design/PHYSICS-calibration.md, "Programmatic zoom"): the scale and the offset follow one
/// fixed-duration ``UnitBezier/easeInOut`` (rms ≤ 0.008 of progress per frame; a critically damped spring misses by
/// 0.09–0.10), the model scale jumps to the target at once, and the duration grows with the zoom ratio up to 0.4 s.
public struct ZoomTiming: Sendable, Equatable {
    /// Absolute start time (`s`, the state clock).
    public var start: TimeInterval
    /// `s`
    public var duration: TimeInterval
    public var curve: UnitBezier

    public init(start: TimeInterval, duration: TimeInterval, curve: UnitBezier = .easeInOut) {
        self.start = start
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        self.curve = curve
    }

    /// Native duration of a zoom from scale `from` to `to` (iOS 27.0, table in the calibration note): linear in the
    /// zoom ratio `r = max / min` — 0.17 s at 1.25×, 0.225 s at 1.5×, 0.315 s at 2× (the same for 1→2, 2→4 and
    /// 4→8) — and capped at 0.40 s from 3× up; the same in both directions. `0.125 + 0.19·(r − 1)` is within 5 ms
    /// (a third of a frame) of every measured case.
    public static func duration(from: CGFloat, to: CGFloat) -> TimeInterval {
        let a = from.positive(or: 1), b = to.positive(or: 1)
        let ratio = Double(max(a, b) / min(a, b))
        return min(0.40, 0.125 + 0.19 * (ratio - 1))
    }

    public struct Sample: Sendable, Equatable {
        /// Progress in [0, 1]; exactly 1 once settled.
        public var progress: CGFloat
        /// The animation is over (the clock may stop).
        public var isSettled: Bool
    }

    /// Progress at absolute `time`. Before the start: 0, running; at or after `start + duration`: 1, settled.
    public func sample(at time: TimeInterval) -> Sample {
        guard duration > 0 else { return Sample(progress: 1, isSettled: true) }
        let t = time - start
        if t <= 0 { return Sample(progress: 0, isSettled: false) }
        if t >= duration { return Sample(progress: 1, isSettled: true) }
        return Sample(progress: curve.value(at: CGFloat(t / duration)), isSettled: false)
    }
}
