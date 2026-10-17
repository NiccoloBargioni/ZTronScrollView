import CoreGraphics
import Foundation

/// Content insets on one axis, in `pt` (`adjustedContentInset` = `contentInset` + safe area, SPEC S6 "Geometry").
public struct AxisInsets: Sendable, Equatable {
    /// Leading (top / left) inset in `pt`.
    public var start: CGFloat
    /// Trailing (bottom / right) inset in `pt`.
    public var end: CGFloat

    /// Non-finite insets become `0`.
    public init(start: CGFloat = 0, end: CGFloat = 0) {
        self.start = start.finiteOrZero
        self.end = end.finiteOrZero
    }

    public static let zero = AxisInsets()

    /// `start + end` in `pt`.
    public var total: CGFloat { start + end }
}

/// Scrollable offset range on one axis (SPEC S6 "Geometry"):
///
///     min = −insets.start
///     max = max(min, contentLength + insets.end − viewportLength)
///
/// `contentLength` is the zoomed length (`unscaled × zoomScale`), all in `pt`.
public struct AxisBounds: Sendable, Equatable {
    /// Lowest offset in `pt`.
    public var min: CGFloat
    /// Highest offset in `pt`; never below ``min``.
    public var max: CGFloat

    /// Bounds from geometry. Non-finite or negative lengths are treated as `0`.
    public init(contentLength: CGFloat, viewportLength: CGFloat, insets: AxisInsets) {
        let content = Swift.max(0, contentLength.finiteOrZero)
        let viewport = Swift.max(0, viewportLength.finiteOrZero)
        let lower = -insets.start.finiteOrZero
        min = lower
        max = Swift.max(lower, content + insets.end.finiteOrZero - viewport)
    }

    /// Explicit bounds; non-finite values become `0` and `max` is raised to `min` when smaller.
    public init(min: CGFloat, max: CGFloat) {
        let lower = min.finiteOrZero
        self.min = lower
        self.max = Swift.max(lower, max.finiteOrZero)
    }

    /// True when `max > min` (there is room to scroll).
    public var isScrollable: Bool { max > min }

    /// `x` clamped into `[min, max]`; `NaN` maps to `min`.
    public func clamped(_ x: CGFloat) -> CGFloat {
        clamp(x, to: min...Swift.max(min, max))
    }

    /// Signed overscroll in `pt`: `0` inside, `x − min < 0` before `min`, `x − max > 0` past `max`
    /// (`NaN` → `0`).
    public func overscroll(of x: CGFloat) -> CGFloat {
        if x < min { return x - min }
        if x > max { return x - max }
        return 0
    }

    /// The edge closest to `x` (`min` on ties): the edge it is beyond when out of bounds.
    public func nearestEdge(to x: CGFloat) -> CGFloat {
        guard !x.isNaN else { return min }
        return x - min <= max - x ? min : max
    }
}

/// Everything the solvers need for one axis.
public struct AxisGeometry: Sendable, Equatable {
    /// Viewport length in `pt`.
    public var viewportLength: CGFloat
    /// Content length at zoom scale 1, in `pt`.
    public var unscaledContentLength: CGFloat
    /// Adjusted content insets.
    public var insets: AxisInsets
    /// Placement of content that fits: `0` leading, `0.5` center, `1` trailing (a `UnitPoint` component).
    public var alignment: CGFloat

    /// Non-finite or negative lengths become `0`; non-finite alignment becomes `0`.
    public init(viewportLength: CGFloat, unscaledContentLength: CGFloat, insets: AxisInsets = .zero,
                alignment: CGFloat = 0) {
        self.viewportLength = Swift.max(0, viewportLength.finiteOrZero)
        self.unscaledContentLength = Swift.max(0, unscaledContentLength.finiteOrZero)
        self.insets = insets
        self.alignment = alignment.finiteOrZero
    }

    /// Zoomed content length `unscaled × scale` in `pt` (non-finite or non-positive scale → `1`).
    public func contentLength(at scale: CGFloat) -> CGFloat {
        unscaledContentLength * scale.positive(or: 1)
    }

    /// Offset bounds at `scale`.
    public func bounds(at scale: CGFloat) -> AxisBounds {
        AxisBounds(contentLength: contentLength(at: scale), viewportLength: viewportLength, insets: insets)
    }

    /// Alignment padding in `pt` when the content fits:
    /// `max(0, viewport − insets.total − content·s) × alignment` (`0` when the content overflows).
    public func alignmentPadding(at scale: CGFloat) -> CGFloat {
        let free = viewportLength - insets.total - contentLength(at: scale)
        return Swift.max(0, free) * alignment
    }

    /// Center of the visible (inset-adjusted) area in viewport coordinates:
    /// `insets.start + (viewport − insets.total) / 2`.
    public var visibleCenter: CGFloat {
        insets.start + (viewportLength - insets.total) / 2
    }

    /// Inset-adjusted viewport length `max(0, viewport − insets.total)` in `pt`.
    public var adjustedViewportLength: CGFloat {
        Swift.max(0, viewportLength - insets.total)
    }
}
