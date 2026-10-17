import CoreGraphics
import Foundation

/// UIKit's rubber-band resistance past an edge (SPEC S6 "Rubber band").
///
/// With coefficient `c` and dimension `d` (the viewport length on the axis, `pt`), an overscroll `x` (`pt`, finger
/// travel past the edge) is shown as
///
///     f(x) = (1 − 1 / (|x|·c/d + 1)) · d · sign(x) = x·c·d / (|x|·c + d)
///
/// `f` is odd, strictly increasing, `|f| < d`, and `f′(0) = c`. Its inverse rebuilds the baseline when catching
/// content mid-bounce:
///
///     x = |f|·d / (c·(d − |f|)) · sign(f)
///
/// A non-positive or non-finite dimension degrades to a clamp (`f ≡ 0`); a non-positive or non-finite coefficient
/// falls back to `0.55`; non-finite inputs return `0`.
public struct RubberBand: Sendable, Equatable {
    /// `c` (dimensionless).
    public var coefficient: CGFloat
    /// `d` in `pt` (viewport length on the axis).
    public var dimension: CGFloat

    public init(dimension: CGFloat, coefficient: CGFloat = 0.55) {
        self.dimension = dimension.finiteOrZero
        self.coefficient = coefficient.positive(or: 0.55)
    }

    /// `f(x) = x·c·d / (|x|·c + d)` in `pt`; `|f|` never reaches `d` (saturates at `d.nextDown`).
    public func displacement(forOverscroll x: CGFloat) -> CGFloat {
        let d = dimension, c = coefficient.positive(or: 0.55)
        guard d.isFinite, d > 0, x.isFinite, x != 0 else { return 0 }
        let magnitude = abs(x) * c * d / (abs(x) * c + d)
        return Swift.min(magnitude, d.nextDown) * x.signum
    }

    /// `x = |f|·d / (c·(d − |f|)) · sign(f)` in `pt`. `|f|` is first clamped to `d·(1 − 1e-6)` (asymptote guard).
    public func overscroll(forDisplacement f: CGFloat) -> CGFloat {
        let d = dimension, c = coefficient.positive(or: 0.55)
        guard d.isFinite, d > 0, f.isFinite, f != 0 else { return 0 }
        let magnitude = Swift.min(abs(f), d * (1 - 1e-6))
        return magnitude * d / (c * (d - magnitude)) * f.signum
    }
}
