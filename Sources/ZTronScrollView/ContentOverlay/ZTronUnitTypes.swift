import SwiftUI

// Normalized fractions (user request 2026-10-21, M6b units): every `.relative` of the content-integral overlay API takes
// one of these, so a fraction outside `0...1` cannot exist. The invariant holds by construction: the stored properties
// are `let`, the only initializers are the explicit clamping ones below (no memberwise initializer, no `Codable`), and
// each initializer maps NaN to 0, values below 0 to 0 and values above 1 (`+infinity` included) to 1.

/// Clamps `v` to `0...1`; NaN becomes 0.
@inline(__always)
func ztronUnitClamped(_ v: CGFloat) -> CGFloat {
    v.isNaN ? 0 : Swift.min(Swift.max(v, 0), 1)
}

/// A fraction of a length, always in `0...1`.
///
/// ``init(_:)`` clamps: `-1` and `-infinity` become 0, `2` and `+infinity` become 1, NaN becomes 0. A float or integer
/// literal goes through the same initializer, so `let k: ZTronUnitLength = 2` is ``full``. What the fraction is taken
/// of depends on where it is used: in ``ZTronContentOverlayLength/relative(_:)`` it is the content's length on the same
/// axis.
public struct ZTronUnitLength: Hashable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// The fraction, always in `0...1`.
    public let value: CGFloat

    /// A fraction clamped to `0...1`; NaN becomes 0.
    public init(_ value: CGFloat) {
        self.value = ztronUnitClamped(value)
    }

    /// A literal fraction, clamped as ``init(_:)``.
    public init(floatLiteral value: Double) {
        self.init(CGFloat(value))
    }

    /// A literal fraction (`0` or `1`; other integers clamp), clamped as ``init(_:)``.
    public init(integerLiteral value: Int) {
        self.init(CGFloat(value))
    }

    /// Nothing of the length: 0.
    public static let zero = ZTronUnitLength(0)
    /// The whole length: 1.
    public static let full = ZTronUnitLength(1)
}

/// A fraction of a size per axis, each component always in `0...1`.
///
/// The initializers clamp each component as ``ZTronUnitLength/init(_:)`` does (NaN becomes 0). In
/// ``ZTronContentOverlaySize/relative(_:)`` it is a fraction of the content's size: `(W · width, H · height)`.
public struct ZTronUnitSize: Hashable, Sendable {
    /// The fraction of the width, always in `0...1`.
    public let width: CGFloat
    /// The fraction of the height, always in `0...1`.
    public let height: CGFloat

    /// Each component clamped to `0...1`; NaN becomes 0.
    public init(width: CGFloat, height: CGFloat) {
        self.width = ztronUnitClamped(width)
        self.height = ztronUnitClamped(height)
    }

    /// `size`'s components read as fractions, each clamped to `0...1` (NaN becomes 0).
    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    /// Nothing on either axis: `(0, 0)`.
    public static let zero = ZTronUnitSize(width: 0, height: 0)
    /// The whole size: `(1, 1)`.
    public static let full = ZTronUnitSize(width: 1, height: 1)
}

/// A point of a rectangle in fractions of its size, each coordinate always in `0...1`: SwiftUI's `UnitPoint`, clamped
/// to the rectangle.
///
/// The initializers clamp each coordinate as ``ZTronUnitLength/init(_:)`` does (NaN becomes 0), so a point built from
/// `UnitPoint(x: 2, y: -1)` is ``topTrailing``. In ``ZTronContentOverlayAnchor/relative(_:)`` it names a point of the
/// content, `(W · x, H · y)`; a point outside the content is ``ZTronContentOverlayAnchor/absolute(_:)``'s job.
public struct ZTronUnitPoint: Hashable, Sendable {
    /// The horizontal fraction, always in `0...1` (0 = leading).
    public let x: CGFloat
    /// The vertical fraction, always in `0...1` (0 = top).
    public let y: CGFloat

    /// Each coordinate clamped to `0...1`; NaN becomes 0.
    public init(x: CGFloat, y: CGFloat) {
        self.x = ztronUnitClamped(x)
        self.y = ztronUnitClamped(y)
    }

    /// `point` clamped to `0...1` per coordinate (NaN becomes 0).
    public init(_ point: UnitPoint) {
        self.init(x: point.x, y: point.y)
    }

    /// The same point as a SwiftUI `UnitPoint`.
    public var unitPoint: UnitPoint { UnitPoint(x: x, y: y) }

    /// `(0, 0)`.
    public static let topLeading = ZTronUnitPoint(x: 0, y: 0)
    /// `(0.5, 0)`.
    public static let top = ZTronUnitPoint(x: 0.5, y: 0)
    /// `(1, 0)`.
    public static let topTrailing = ZTronUnitPoint(x: 1, y: 0)
    /// `(0, 0.5)`.
    public static let leading = ZTronUnitPoint(x: 0, y: 0.5)
    /// `(0.5, 0.5)`.
    public static let center = ZTronUnitPoint(x: 0.5, y: 0.5)
    /// `(1, 0.5)`.
    public static let trailing = ZTronUnitPoint(x: 1, y: 0.5)
    /// `(0, 1)`.
    public static let bottomLeading = ZTronUnitPoint(x: 0, y: 1)
    /// `(0.5, 1)`.
    public static let bottom = ZTronUnitPoint(x: 0.5, y: 1)
    /// `(1, 1)`.
    public static let bottomTrailing = ZTronUnitPoint(x: 1, y: 1)
}
