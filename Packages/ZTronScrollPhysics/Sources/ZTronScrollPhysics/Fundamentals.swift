import CoreGraphics
import Foundation

// MARK: - Velocity units

/// Velocity unit conversions.
///
/// The physics works in `pt/s`; UIKit's `scrollViewWillEndDragging(_:withVelocity:targetContentOffset:)`
/// reports `pt/ms`. Non-finite inputs convert to `0`.
public enum Velocity: Sendable {
    /// `v [pt/s] → v / 1000 [pt/ms]` (delegate convention). Non-finite → `0`.
    public static func pointsPerMillisecond(_ v: CGFloat) -> CGFloat {
        v.finiteOrZero / 1000
    }

    /// `v [pt/ms] → v · 1000 [pt/s]`. Non-finite → `0`.
    public static func pointsPerSecond(fromPerMillisecond v: CGFloat) -> CGFloat {
        v.finiteOrZero * 1000
    }
}

// MARK: - Deceleration rate

/// UIKit-style deceleration rate `r`: the fraction of velocity kept after each millisecond.
///
/// Velocity decays as `v(t) = v₀ · r^(1000·t) = v₀ · e^(k·t)` with `k = 1000 · ln r` (`1/s`, negative).
/// `r` is clamped to `[0.5, 0.9999]`; a non-finite `r` falls back to ``normal``.
public struct DecelerationRate: Sendable, Hashable {
    private var storage: CGFloat

    /// `r` per millisecond, always within `[0.5, 0.9999]`.
    public var perMillisecond: CGFloat {
        get { storage }
        set { storage = Self.sanitized(newValue) }
    }

    /// `UIScrollView.DecelerationRate.normal` (`r = 0.998`).
    public static let normal = DecelerationRate(perMillisecond: 0.998)
    /// `UIScrollView.DecelerationRate.fast` (`r = 0.99`).
    public static let fast = DecelerationRate(perMillisecond: 0.99)

    /// The range of `r` a re-solved decay may use before falling back to a spring (SPEC S6).
    public static let plausibleRange: ClosedRange<CGFloat> = 0.98...0.9995

    /// The clamp applied to every stored `r`.
    public static let storableRange: ClosedRange<CGFloat> = 0.5...0.9999

    /// Creates a rate; `r ∉ [0.5, 0.9999]` is clamped, non-finite `r` becomes `0.998`.
    public init(perMillisecond r: CGFloat) {
        storage = Self.sanitized(r)
    }

    /// `k = 1000 · ln r` in `1/s` (always negative). Used by every decay formula.
    public var k: CGFloat { 1000 * log(storage) }

    private static func sanitized(_ r: CGFloat) -> CGFloat {
        guard r.isFinite else { return 0.998 }
        return clamp(r, to: storableRange)
    }
}

// MARK: - Rest thresholds

/// Thresholds that decide when a motion counts as stopped.
///
/// Non-finite or non-positive values fall back to the defaults.
public struct RestThresholds: Sendable, Equatable {
    /// `pt/s`: `|v|` below this counts as stopped.
    public var velocity: CGFloat
    /// `pt`: remaining distance below this snaps to the target.
    public var distance: CGFloat
    /// `pt/s`: a release velocity below this is "`v₀ ≈ 0`" (SPEC S6) everywhere in ``ReleaseSolver``: a natural
    /// release rests in place (`willDecelerate == false`), a release already on its target rests there, and
    /// ``Decay/retargeted(origin:initialVelocity:target:thresholds:)`` refuses to re-solve (spring fallback).
    public var negligibleReleaseVelocity: CGFloat

    public init(velocity: CGFloat = 4, distance: CGFloat = 0.5, negligibleReleaseVelocity: CGFloat = 20) {
        self.velocity = velocity.positive(or: 4)
        self.distance = distance.positive(or: 0.5)
        self.negligibleReleaseVelocity = negligibleReleaseVelocity.positive(or: 20)
    }
}

// MARK: - Pixel snapping

/// Rounds positions to the device pixel grid: `snap(x) = round(x · scale) / scale`.
public enum PixelSnap: Sendable {
    /// `(x · displayScale).rounded() / displayScale`; returns `x` unchanged when `displayScale ≤ 0`,
    /// `displayScale` is non-finite, or `x` is non-finite.
    public static func snap(_ x: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard x.isFinite, displayScale.isFinite, displayScale > 0 else { return x }
        return (x * displayScale).rounded() / displayScale
    }

    /// Snaps both components of `p` (see `snap(_:displayScale:)` for scalars).
    public static func snap(_ p: CGPoint, displayScale: CGFloat) -> CGPoint {
        CGPoint(x: snap(p.x, displayScale: displayScale), y: snap(p.y, displayScale: displayScale))
    }
}
