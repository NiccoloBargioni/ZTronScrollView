import SwiftUI

/// Visible-centre geometry, ported verbatim from ZTronMapKit `ContentGeometry` (`normalizedCenter` /
/// `contentOffset(normalizedCenter:)`), SPEC S7 "preserve the visible center" (design M5, D17).
///
/// Conventions are ZTronMapKit's: `contentOffset` is the scroll-view offset (`0` at the content's start edge),
/// `viewport` the visible area and `contentSize` the *zoomed* content size. The library's offset
/// (`x_v = s*x_c + pad - o`, insets, alignment padding, scaling header) is mapped to and from these by
/// `ResizeMath.mapKitOffset` / `ResizeMath.libraryOffset`.
enum CenterGeometry {
    /// The normalized visible centre `(offset + viewport / 2) / contentSize`, per axis.
    ///
    /// - Returns: `nil` when `contentSize` has a non-positive or non-finite side (nothing to preserve), or when the
    ///   arithmetic overflows.
    static func normalizedCenter(contentOffset: CGPoint,
                                 viewport: CGSize,
                                 contentSize: CGSize) -> CGPoint? {
        guard isPositive(contentSize.width), isPositive(contentSize.height) else { return nil }
        let offset = sanitized(contentOffset)
        let view = sanitized(viewport)
        let center = CGPoint(x: (offset.x + view.width / 2) / contentSize.width,
                             y: (offset.y + view.height / 2) / contentSize.height)
        return center.x.isFinite && center.y.isFinite ? center : nil
    }

    /// The content offset that puts `normalizedCenter` at the centre of `viewport`, clamped per axis into
    /// `[0, max(contentSize − viewport, 0)]`. When the content is smaller than the viewport on an axis the offset is
    /// `0` on that axis. A negative viewport side is treated as `0`; the result is always finite.
    static func contentOffset(normalizedCenter: CGPoint,
                              viewport: CGSize,
                              contentSize: CGSize) -> CGPoint {
        let center = sanitized(normalizedCenter)
        let view = nonNegative(sanitized(viewport))
        let content = sanitized(contentSize)
        let maxX = max(content.width - view.width, 0)
        let maxY = max(content.height - view.height, 0)
        let tx = center.x * content.width - view.width / 2
        let ty = center.y * content.height - view.height / 2
        return CGPoint(x: clamp(tx, 0, maxX), y: clamp(ty, 0, maxY))
    }

    // MARK: Focus generalisation (`defaultScrollAnchor(for: .sizeChanges)`)

    /// `normalizedCenter` with the viewport point at `focus` (`0.5` = the verbatim centre rule) instead of the centre.
    static func normalizedPoint(contentOffset: CGPoint, viewport: CGSize, contentSize: CGSize,
                                focus: UnitPoint) -> CGPoint? {
        if focus == .center { return normalizedCenter(contentOffset: contentOffset, viewport: viewport, contentSize: contentSize) }
        guard isPositive(contentSize.width), isPositive(contentSize.height) else { return nil }
        let offset = sanitized(contentOffset)
        let view = sanitized(viewport)
        let p = CGPoint(x: (offset.x + view.width * focus.x) / contentSize.width,
                        y: (offset.y + view.height * focus.y) / contentSize.height)
        return p.x.isFinite && p.y.isFinite ? p : nil
    }

    /// `contentOffset(normalizedCenter:)` with the content point at `normalizedPoint` placed at `focus` of `viewport`.
    static func contentOffset(normalizedPoint: CGPoint, viewport: CGSize, contentSize: CGSize,
                              focus: UnitPoint) -> CGPoint {
        if focus == .center { return contentOffset(normalizedCenter: normalizedPoint, viewport: viewport, contentSize: contentSize) }
        let n = sanitized(normalizedPoint)
        let view = nonNegative(sanitized(viewport))
        let content = sanitized(contentSize)
        let maxX = max(content.width - view.width, 0)
        let maxY = max(content.height - view.height, 0)
        return CGPoint(x: clamp(n.x * content.width - view.width * focus.x, 0, maxX),
                       y: clamp(n.y * content.height - view.height * focus.y, 0, maxY))
    }

    // MARK: Helpers (verbatim)

    /// `true` for a finite, strictly positive value.
    @inline(__always)
    static func isPositive(_ value: CGFloat) -> Bool {
        value.isFinite && value > 0
    }

    /// `value` when finite, `fallback` otherwise.
    @inline(__always)
    static func finite(_ value: CGFloat, or fallback: CGFloat) -> CGFloat {
        value.isFinite ? value : fallback
    }

    /// Non-finite components become `0`.
    @inline(__always)
    static func sanitized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: finite(point.x, or: 0), y: finite(point.y, or: 0))
    }

    /// Non-finite components become `0`.
    @inline(__always)
    static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(width: finite(size.width, or: 0), height: finite(size.height, or: 0))
    }

    /// Negative sides become `0` (a viewport cannot have a negative extent).
    @inline(__always)
    static func nonNegative(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 0), height: max(size.height, 0))
    }

    /// NaN-safe clamp: a NaN `value` yields `lower`; an inverted range yields `lower`.
    @inline(__always)
    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard !value.isNaN, upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}

/// What a resize preserves (D17, sticky across consecutive resizes until the user or code moves the view): the
/// normalized centre of the zoomed content and the zoom scale ("at fit" re-resolves the fit for every geometry).
struct ResizeIntent: Equatable, Sendable {
    var normalizedCenter: CGPoint
    var scale: CGFloat
    var atFit: Bool
}
