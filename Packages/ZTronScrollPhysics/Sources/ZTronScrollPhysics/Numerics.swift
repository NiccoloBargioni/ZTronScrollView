import CoreGraphics
import Foundation

extension CGFloat {
    /// `self` when finite, otherwise `0`.
    @inline(__always) var finiteOrZero: CGFloat { isFinite ? self : 0 }

    /// `self` when finite, otherwise `fallback`.
    @inline(__always) func finite(or fallback: CGFloat) -> CGFloat { isFinite ? self : fallback }

    /// `self` when finite and strictly positive, otherwise `fallback`.
    @inline(__always) func positive(or fallback: CGFloat) -> CGFloat { isFinite && self > 0 ? self : fallback }

    /// `-1`, `0` or `1`.
    @inline(__always) var signum: CGFloat { self > 0 ? 1 : (self < 0 ? -1 : 0) }
}

/// Elapsed-time guard shared by every sampler: `NaN` and negative times sample the start state (`0`);
/// `+inf` is preserved so callers can map it to the end state.
@inline(__always) func sanitizedElapsed(_ t: TimeInterval) -> TimeInterval {
    t.isNaN || t < 0 ? 0 : t
}

/// Slack (`s`) when comparing the elapsed time `time − start` against a settling time, so a sample at exactly
/// `start + T` settles despite the rounding of `(start + T) − start`.
///
/// That rounding is up to half an ulp of the absolute clock value: about `1.2e-7 s` for a `Date`-based
/// `TimeInterval` (`~8e8 s` since the reference date) and `2.4e-7 s` around `1.76e9 s` (Unix epoch). The slack is
/// therefore `max(1e-9, 4 · ulp(|time|))`, which stays below `2e-6 s` (far below one frame) for any clock up to
/// `2^31 s`. Non-finite times get the `1e-9` floor.
@inline(__always) func settleTolerance(at time: TimeInterval) -> TimeInterval {
    guard time.isFinite else { return 1e-9 }
    return Swift.max(1e-9, 4 * time.magnitude.ulp)
}

/// Clamps `x` into `range`; `NaN` maps to the lower bound.
@inline(__always) func clamp(_ x: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    if x.isNaN { return range.lowerBound }
    return Swift.min(Swift.max(x, range.lowerBound), range.upperBound)
}
