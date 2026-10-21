import SwiftUI

// Normalized fractions (user request 2026-10-21, M6b units): every `.relative` of the content-integral overlay API takes
// one of these, so a fraction outside `0...1` cannot exist. The invariant holds by construction: the stored properties
// are `let`, the only initializers are the explicit clamping ones below (no memberwise initializer, no `Codable`), and
// each initializer maps NaN to 0, values below 0 to 0 and values above 1 (`+infinity` included) to 1. A clamped value
// is reported in DEBUG builds (`ZTronDiagnostics`, user request 2026-10-21): with the caller's location from the explicit
// initializers, as `literal` from the literal ones, and again with the location of a constructor that receives a
// clamped literal (a `ZTronUnitLength` keeps its unclamped literal in DEBUG builds for that, outside `==` and `hash`).

/// Clamps `v` to `0...1`; NaN becomes 0.
@inline(__always)
func ztronUnitClamped(_ v: CGFloat) -> CGFloat {
    v.isNaN ? 0 : Swift.min(Swift.max(v, 0), 1)
}

/// Clamps `v` to `0...1` (NaN becomes 0); in DEBUG builds a changed value is reported once per `subject` (the
/// component), site and value. In range, the only extra work is one comparison, in DEBUG builds only.
@inline(__always)
func ztronUnitClamped(_ v: CGFloat, _ subject: StaticString, _ site: ZTronDiagnostics.Site) -> CGFloat {
    let c = ztronUnitClamped(v)
    #if DEBUG
    if c != v {   // NaN included (NaN != 0); −0 is in range (−0 == 0)
        ZTronDiagnostics.report(.unitClamped, subject, v.isNaN ? "is NaN" : "is outside 0...1", bits: v, site: site,
                                input: "\(v)", result: "\(c)")
    }
    #endif
    return c
}

/// A fraction of a length, always in `0...1`.
///
/// ``init(_:fileID:line:)`` clamps: `-1` and `-infinity` become 0, `2` and `+infinity` become 1, NaN becomes 0. A float
/// or integer literal clamps the same way, so `let k: ZTronUnitLength = 2` is ``full``. What the fraction is taken of
/// depends on where it is used: in ``ZTronContentOverlayLength/relative(_:)`` it is the content's length on the same
/// axis.
///
/// In DEBUG builds every clamped value is also reported (one `NSLog` line, `[ZTronScrollView] …`), once per call site
/// and value (at most a few values per call site, so a value that changes every frame cannot flood the console): with
/// the caller's file and line from ``init(_:fileID:line:)``; as `literal` from a literal, which carries no location
/// (Swift types `ZTronUnitLength(2)` with a literal argument as that literal), and again with the caller's location
/// when the clamped literal is passed to a ``ZTronContentOverlaySize`` constructor (`.relative(width: 50, height: 0.5)`
/// reports `50.0 -> 1.0` at that call). A symbolic breakpoint on `ZTronDiagnostics.report` stops at every clamp, the
/// caller on the stack. Release builds clamp without reporting (the defaulted `fileID:` / `line:` arguments are still
/// passed, unused).
///
/// Equality and hashing are those of ``value``.
public struct ZTronUnitLength: Hashable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// The fraction, always in `0...1`.
    public let value: CGFloat
    #if DEBUG
    /// The literal this value was clamped from, `nil` if it was not a clamped literal: a constructor that receives the
    /// value reports the clamp again with its caller's location (`reportClampedLiteral`). Outside `==` and `hash`.
    let clampedLiteral: CGFloat?
    #endif

    /// A fraction clamped to `0...1`; NaN becomes 0. A clamped value is reported in DEBUG builds with the caller's
    /// location, once per call site and value.
    ///
    /// - Parameters:
    ///   - value: The fraction.
    ///   - fileID: The caller's file, for the DEBUG report; leave the default.
    ///   - line: The caller's line, for the DEBUG report; leave the default.
    public init(_ value: CGFloat, fileID: StaticString = #fileID, line: UInt = #line) {
        self.value = ztronUnitClamped(value, "ZTronUnitLength.value", .caller(fileID: fileID, line: line))
        #if DEBUG
        clampedLiteral = nil
        #endif
    }

    /// A literal fraction, clamped as ``init(_:fileID:line:)``; a clamped literal is reported in DEBUG builds as
    /// `literal` (once per value: a literal carries no location), and again with the caller's location by a
    /// ``ZTronContentOverlaySize`` constructor that receives it.
    public init(floatLiteral value: Double) {
        self.init(literal: CGFloat(value))
    }

    /// A literal fraction (`0` or `1`; other integers clamp), clamped as ``init(_:fileID:line:)``; a clamped literal
    /// is reported in DEBUG builds as `literal` (once per value: a literal carries no location), and again with the
    /// caller's location by a ``ZTronContentOverlaySize`` constructor that receives it.
    public init(integerLiteral value: Int) {
        self.init(literal: CGFloat(value))
    }

    private init(literal raw: CGFloat) {
        value = ztronUnitClamped(raw, "ZTronUnitLength.value", .literal)
        #if DEBUG
        clampedLiteral = value != raw ? raw : nil   // NaN included
        #endif
    }

    public static func == (a: ZTronUnitLength, b: ZTronUnitLength) -> Bool { a.value == b.value }

    public func hash(into hasher: inout Hasher) { hasher.combine(value) }

    /// DEBUG builds: if this value was clamped from a literal, reports that clamp again at `site`, the location of the
    /// constructor's caller that received it (`subject` names the argument). Release builds: nothing.
    @inline(__always)
    func reportClampedLiteral(_ subject: StaticString, _ site: ZTronDiagnostics.Site) {
        #if DEBUG
        if let raw = clampedLiteral {
            ZTronDiagnostics.report(.unitClamped, subject, raw.isNaN ? "is a NaN literal" : "is a literal outside 0...1",
                                    bits: raw, site: site, input: "\(raw)", result: "\(value)")
        }
        #endif
    }

    /// Nothing of the length: 0.
    public static let zero = ZTronUnitLength(0)
    /// The whole length: 1.
    public static let full = ZTronUnitLength(1)
}

/// A fraction of a size per axis, each component always in `0...1`.
///
/// The initializers clamp each component as ``ZTronUnitLength/init(_:fileID:line:)`` does (NaN becomes 0) and, in
/// DEBUG builds, report each clamped component with the caller's location, once per call site and value (at most a few
/// values per call site and component). In
/// ``ZTronContentOverlaySize/relative(_:fileID:line:)`` it is a fraction of the content's size: `(W · width, H · height)`.
public struct ZTronUnitSize: Hashable, Sendable {
    /// The fraction of the width, always in `0...1`.
    public let width: CGFloat
    /// The fraction of the height, always in `0...1`.
    public let height: CGFloat

    /// Each component clamped to `0...1`; NaN becomes 0. A clamped component is reported in DEBUG builds with the
    /// caller's location, once per call site and value.
    ///
    /// - Parameters:
    ///   - width: The fraction of the width.
    ///   - height: The fraction of the height.
    ///   - fileID: The caller's file, for the DEBUG report; leave the default.
    ///   - line: The caller's line, for the DEBUG report; leave the default.
    public init(width: CGFloat, height: CGFloat, fileID: StaticString = #fileID, line: UInt = #line) {
        self.width = ztronUnitClamped(width, "ZTronUnitSize.width", .caller(fileID: fileID, line: line))
        self.height = ztronUnitClamped(height, "ZTronUnitSize.height", .caller(fileID: fileID, line: line))
    }

    /// `size`'s components read as fractions, each clamped to `0...1` (NaN becomes 0). A clamped component is
    /// reported in DEBUG builds with the caller's location, once per call site and value.
    ///
    /// - Parameters:
    ///   - size: The fractions.
    ///   - fileID: The caller's file, for the DEBUG report; leave the default.
    ///   - line: The caller's line, for the DEBUG report; leave the default.
    public init(_ size: CGSize, fileID: StaticString = #fileID, line: UInt = #line) {
        self.init(width: size.width, height: size.height, fileID: fileID, line: line)
    }

    /// Nothing on either axis: `(0, 0)`.
    public static let zero = ZTronUnitSize(width: 0, height: 0)
    /// The whole size: `(1, 1)`.
    public static let full = ZTronUnitSize(width: 1, height: 1)
}

/// A point of a rectangle in fractions of its size, each coordinate always in `0...1`: SwiftUI's `UnitPoint`, clamped
/// to the rectangle.
///
/// The initializers clamp each coordinate as ``ZTronUnitLength/init(_:fileID:line:)`` does (NaN becomes 0), so a point
/// built from `UnitPoint(x: 2, y: -1)` is ``topTrailing``; in DEBUG builds they report each clamped coordinate with the
/// caller's location, once per call site and value (at most a few values per call site and coordinate, so a point
/// that follows a drag past the edge logs a few lines, then one saying further values are not logged). In ``ZTronContentOverlayAnchor/relative(_:)`` it names a point of
/// the content, `(W · x, H · y)`; a point outside the content is ``ZTronContentOverlayAnchor/absolute(_:)``'s job.
public struct ZTronUnitPoint: Hashable, Sendable {
    /// The horizontal fraction, always in `0...1` (0 = leading).
    public let x: CGFloat
    /// The vertical fraction, always in `0...1` (0 = top).
    public let y: CGFloat

    /// Each coordinate clamped to `0...1`; NaN becomes 0. A clamped coordinate is reported in DEBUG builds with the
    /// caller's location, once per call site and value.
    ///
    /// - Parameters:
    ///   - x: The horizontal fraction.
    ///   - y: The vertical fraction.
    ///   - fileID: The caller's file, for the DEBUG report; leave the default.
    ///   - line: The caller's line, for the DEBUG report; leave the default.
    public init(x: CGFloat, y: CGFloat, fileID: StaticString = #fileID, line: UInt = #line) {
        self.x = ztronUnitClamped(x, "ZTronUnitPoint.x", .caller(fileID: fileID, line: line))
        self.y = ztronUnitClamped(y, "ZTronUnitPoint.y", .caller(fileID: fileID, line: line))
    }

    /// `point` clamped to `0...1` per coordinate (NaN becomes 0). A clamped coordinate is reported in DEBUG builds with
    /// the caller's location, once per call site and value.
    ///
    /// - Parameters:
    ///   - point: The point, in fractions of the rectangle's size.
    ///   - fileID: The caller's file, for the DEBUG report; leave the default.
    ///   - line: The caller's line, for the DEBUG report; leave the default.
    public init(_ point: UnitPoint, fileID: StaticString = #fileID, line: UInt = #line) {
        self.init(x: point.x, y: point.y, fileID: fileID, line: line)
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
