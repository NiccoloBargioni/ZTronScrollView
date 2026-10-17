import CoreGraphics
import Foundation

// MARK: - Fling acceleration

/// Carries the remaining momentum into a quick same-direction fling that starts while still decelerating
/// (SPEC S6 "Fling acceleration").
///
///     v = clamp(release + carryFactor · remainingAtCatch, ±maximumVelocity)
///         when sign(release) == sign(remainingAtCatch) and touchDuration < maximumCatchDuration
///     v = clamp(release, ±maximumVelocity) otherwise
///
/// Velocities in `pt/s`, durations in `s`.
public struct FlingAcceleration: Sendable, Equatable {
    /// `pt/s` cap on the combined velocity (calibrate against native).
    public var maximumVelocity: CGFloat
    /// Fraction of the remaining momentum carried over.
    public var carryFactor: CGFloat
    /// `s`: touch-down → lift must be quicker than this for the fling to carry momentum.
    public var maximumCatchDuration: TimeInterval

    public init(maximumVelocity: CGFloat = 12_000, carryFactor: CGFloat = 1.0, maximumCatchDuration: TimeInterval = 0.30) {
        self.maximumVelocity = maximumVelocity.positive(or: 12_000)
        self.carryFactor = Swift.max(0, carryFactor.finite(or: 1))
        self.maximumCatchDuration = maximumCatchDuration.isFinite ? Swift.max(0, maximumCatchDuration) : 0.30
    }

    /// Combined release velocity in `pt/s` (see the type documentation). Non-finite inputs count as `0`.
    public func combine(release: CGFloat, remainingAtCatch: CGFloat, touchDuration: TimeInterval) -> CGFloat {
        let release = release.finiteOrZero
        let remaining = remainingAtCatch.finiteOrZero
        let quick = touchDuration.isFinite && touchDuration >= 0 && touchDuration < maximumCatchDuration
        let sameDirection = release * remaining > 0
        let v = quick && sameDirection ? release + carryFactor * remaining : release
        let cap = maximumVelocity.positive(or: 12_000)
        return Swift.min(Swift.max(v, -cap), cap)
    }
}

// MARK: - Paging

/// `isPagingEnabled` / `.scrollTargetBehavior(.paging)` target resolution (SPEC S6 "Paging").
public enum PagingSolver: Sendable {
    /// Page boundaries sit at `bounds.min + n · pageLength` (`pt`).
    ///
    /// - The start page is the boundary nearest `dragStart`.
    /// - `|velocity| > flickVelocity` (`pt/s`): the next boundary past `current` in the direction of `velocity`.
    /// - Otherwise: the boundary nearest `current` (moves once the displacement exceeds half a page).
    /// - The result is at most one page from the start page and clamped to `bounds` (a partial last page ends at
    ///   `bounds.max`).
    ///
    /// A non-positive or non-finite `pageLength` degrades to `bounds.clamped(current)`.
    public static func target(current: CGFloat, dragStart: CGFloat, velocity: CGFloat, pageLength: CGFloat,
                              bounds: AxisBounds, flickVelocity: CGFloat = 300) -> CGFloat {
        let current = current.finite(or: bounds.min)
        guard pageLength.isFinite, pageLength > 0 else { return bounds.clamped(current) }
        let origin = bounds.min
        let startIndex = ((dragStart.finite(or: current) - origin) / pageLength).rounded()
        let position = (current - origin) / pageLength
        let v = velocity.finiteOrZero
        let epsilon: CGFloat = 1e-6

        var index: CGFloat
        if abs(v) > abs(flickVelocity.finiteOrZero) {
            index = v > 0 ? (position + epsilon).rounded(.down) + 1 : (position - epsilon).rounded(.up) - 1
        } else {
            index = position.rounded()
        }
        index = Swift.min(Swift.max(index, startIndex - 1), startIndex + 1)
        return bounds.clamped(origin + index * pageLength)
    }
}

// MARK: - Target snapping

/// Helpers for scroll-target behaviors that snap the natural rest point to candidate offsets.
public enum TargetSnapping: Sendable {
    /// The candidate nearest `projected` (`pt`); ties (within `1e-9` pt) resolve in the direction of travel
    /// (`direction > 0` → larger candidate, `< 0` → smaller, `0` → first). Non-finite candidates are ignored;
    /// `nil` when none remain.
    public static func nearest(to projected: CGFloat, candidates: [CGFloat], direction: CGFloat) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = CGFloat.infinity
        for candidate in candidates where candidate.isFinite {
            let distance = abs(candidate - projected)
            guard let current = best else {
                best = candidate
                bestDistance = distance
                continue
            }
            if distance < bestDistance - 1e-9 {
                best = candidate
                bestDistance = distance
            } else if abs(distance - bestDistance) <= 1e-9 {
                if (direction > 0 && candidate > current) || (direction < 0 && candidate < current) {
                    best = candidate
                    bestDistance = Swift.min(distance, bestDistance)
                }
            }
        }
        return best
    }

    /// Natural decay rest point `x₀ − v₀ / k` in `pt` (`origin` in `pt`, `velocity` in `pt/s`).
    public static func projectedRest(origin: CGFloat, velocity: CGFloat, rate: DecelerationRate) -> CGFloat {
        Decay(origin: origin, initialVelocity: velocity, rate: rate).restPosition
    }
}
