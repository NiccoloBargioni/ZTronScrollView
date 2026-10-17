import CoreGraphics
import Foundation

// MARK: - Limits

/// One zoom limit: an absolute scale, or relative to the content's fit / fill scale (recomputed on resize).
public enum ZoomBound: Sendable, Equatable {
    /// A fixed scale (non-finite or non-positive → `1`).
    case absolute(CGFloat)
    /// `min(vw/cw, vh/ch)` with the inset-adjusted viewport: the whole content is visible.
    case fit
    /// `max(vw/cw, vh/ch)` with the inset-adjusted viewport: the content covers the viewport.
    case fill
}

/// `minimumZoomScale` / `maximumZoomScale` (SPEC S6 "Limits"). The default `1…1` disables zooming, as in UIKit.
public struct ZoomLimits: Sendable, Equatable {
    public var min: ZoomBound
    public var max: ZoomBound

    public init(min: ZoomBound = .absolute(1), max: ZoomBound = .absolute(1)) {
        self.min = min
        self.max = max
    }

    /// Resolves both bounds for the current geometry (call on every resize).
    ///
    /// `fit = min(vw/cw, vh/ch)` and `fill = max(vw/cw, vh/ch)` with `vw = viewport.width − insets.x.total` (likewise
    /// `vh`); an axis with a non-positive or non-finite length is ignored, and with no usable axis both are `1`.
    /// Non-finite or non-positive bounds become `1`. The result is normalized so `lower ≤ upper`: a minimum above the
    /// maximum raises the maximum (the minimum wins and zooming is disabled).
    public func resolve(unscaledContentSize: CGSize, viewportSize: CGSize,
                        insets: (x: AxisInsets, y: AxisInsets)) -> ClosedRange<CGFloat> {
        let vw = viewportSize.width.finiteOrZero - insets.x.total
        let vh = viewportSize.height.finiteOrZero - insets.y.total
        let ratios = [Self.ratio(vw, unscaledContentSize.width), Self.ratio(vh, unscaledContentSize.height)]
            .compactMap { $0 }
        let fit = ratios.min() ?? 1
        let fill = ratios.max() ?? 1

        func value(_ bound: ZoomBound) -> CGFloat {
            switch bound {
            case let .absolute(scale): return scale.positive(or: 1)
            case .fit: return fit.positive(or: 1)
            case .fill: return fill.positive(or: 1)
            }
        }
        let lower = value(min)
        return lower...Swift.max(lower, value(max))
    }

    /// Zooming is enabled iff `upper > lower`.
    public static func isZoomEnabled(_ range: ClosedRange<CGFloat>) -> Bool {
        range.upperBound > range.lowerBound
    }

    private static func ratio(_ viewport: CGFloat, _ content: CGFloat) -> CGFloat? {
        guard viewport.isFinite, content.isFinite, viewport > 0, content > 0 else { return nil }
        let r = viewport / content
        return r.isFinite && r > 0 ? r : nil
    }
}

// MARK: - Geometry

/// A 2D view over two ``AxisGeometry`` values.
public struct ZoomGeometry: Sendable, Equatable {
    public var x: AxisGeometry
    public var y: AxisGeometry

    public init(x: AxisGeometry, y: AxisGeometry) {
        self.x = x
        self.y = y
    }

    /// Convenience: `alignment` is a `UnitPoint`-like pair (default center, the SPEC's default when zooming is
    /// enabled).
    public init(viewportSize: CGSize, unscaledContentSize: CGSize,
                insets: (x: AxisInsets, y: AxisInsets) = (.zero, .zero),
                alignment: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        x = AxisGeometry(viewportLength: viewportSize.width, unscaledContentLength: unscaledContentSize.width,
                         insets: insets.x, alignment: alignment.x)
        y = AxisGeometry(viewportLength: viewportSize.height, unscaledContentLength: unscaledContentSize.height,
                         insets: insets.y, alignment: alignment.y)
    }

    /// Offset bounds per axis at `scale`.
    public func bounds(at scale: CGFloat) -> (x: AxisBounds, y: AxisBounds) {
        (x.bounds(at: scale), y.bounds(at: scale))
    }

    /// Alignment padding per axis at `scale`, in `pt`.
    public func alignmentPadding(at scale: CGFloat) -> CGPoint {
        CGPoint(x: x.alignmentPadding(at: scale), y: y.alignmentPadding(at: scale))
    }

    /// Center of the inset-adjusted viewport, in viewport coordinates (`pt`).
    public var visibleCenter: CGPoint {
        CGPoint(x: x.visibleCenter, y: y.visibleCenter)
    }

    /// Unscaled content size in `pt`.
    public var unscaledContentSize: CGSize {
        CGSize(width: x.unscaledContentLength, height: y.unscaledContentLength)
    }

    /// The offset clamped into ``bounds(at:)``.
    public func clamped(_ offset: CGPoint, at scale: CGFloat) -> CGPoint {
        let b = bounds(at: scale)
        return CGPoint(x: b.x.clamped(offset.x), y: b.y.clamped(offset.y))
    }
}

// MARK: - Solver

/// Closed-form zoom math (SPEC S6 "Zoom", S7 resize).
///
/// Rendering model: an unscaled content point `u` appears at viewport point `p = s·u + pad(s) − offset`, where `s` is
/// the zoom scale and `pad(s)` the alignment padding (``ZoomGeometry/alignmentPadding(at:)``). All positions in `pt`.
/// Non-finite or non-positive scales count as `1`.
public enum ZoomSolver: Sendable {
    /// Unscaled content point under viewport point `p`: `u = (offset + p − pad(s)) / s`.
    public static func contentPoint(under p: CGPoint, offset: CGPoint, scale: CGFloat,
                                    geometry: ZoomGeometry) -> CGPoint {
        let s = scale.positive(or: 1)
        let pad = geometry.alignmentPadding(at: s)
        return CGPoint(x: (offset.x + p.x - pad.x) / s, y: (offset.y + p.y - pad.y) / s)
    }

    /// Offset that keeps `u` under `p` at scale `s′`: `pad(s′) + s′·u − p`; `clamped` applies `bounds(s′)`.
    public static func offset(keeping u: CGPoint, under p: CGPoint, scale: CGFloat, geometry: ZoomGeometry,
                              clamped: Bool) -> CGPoint {
        let s = scale.positive(or: 1)
        let pad = geometry.alignmentPadding(at: s)
        let raw = CGPoint(x: pad.x + s * u.x - p.x, y: pad.y + s * u.y - p.y)
        return clamped ? geometry.clamped(raw, at: s) : raw
    }

    /// Live pinch: `u` is anchored at gesture start and the offset is re-derived every frame from the current
    /// centroid (so a two-finger pan while pinching moves the content with the fingers). Unclamped; the caller
    /// applies rubber banding.
    ///
    /// Accuracy: with the true centroid (iOS 18+, `SpatialEventGesture`) the focal error is rounding only (≤ 0.5 pt
    /// after pixel snapping). On iOS 15–17 the centroid is estimated from the pan location and the pinch's start
    /// location, which can drift by a few pt.
    public static func pinch(anchor u: CGPoint, centroid: CGPoint, scale: CGFloat, geometry: ZoomGeometry) -> CGPoint {
        offset(keeping: u, under: centroid, scale: scale, geometry: geometry, clamped: false)
    }

    /// Log-space resistance past the limits (SPEC S6 "Past the limits"): with `L` the nearest limit and
    /// `e = ln(raw / L)`, the shown scale is `L · exp(RubberBand(dimension: logDimension).displacement(e))`.
    ///
    /// Inside the limits the raw scale is returned unchanged. The result is symmetric in log space
    /// (`ln(shown/L)` is odd in `e`) and bounded: `L·e^(−logDimension) < shown < L·e^(logDimension)`.
    /// A non-positive or `NaN` raw scale returns the lower limit; `+∞` returns the upper limit.
    public static func resisted(rawScale: CGFloat, limits: ClosedRange<CGFloat>, logDimension: CGFloat = 1.0) -> CGFloat {
        let limits = sanitized(limits)
        guard !rawScale.isNaN, rawScale > 0 else { return limits.lowerBound }
        guard rawScale.isFinite else { return limits.upperBound }
        if limits.contains(rawScale) { return rawScale }
        let edge = rawScale < limits.lowerBound ? limits.lowerBound : limits.upperBound
        let band = RubberBand(dimension: logDimension.positive(or: 1))
        return edge * exp(band.displacement(forOverscroll: log(rawScale / edge)))
    }

    /// Inverse of ``resisted(rawScale:limits:logDimension:)``: the raw scale that shows as `shownScale` (re-baselines
    /// a pinch that catches a zoom bounce without a jump).
    public static func unresisted(shownScale: CGFloat, limits: ClosedRange<CGFloat>, logDimension: CGFloat = 1.0) -> CGFloat {
        let limits = sanitized(limits)
        guard shownScale.isFinite, shownScale > 0 else { return limits.lowerBound }
        if limits.contains(shownScale) { return shownScale }
        let edge = shownScale < limits.lowerBound ? limits.lowerBound : limits.upperBound
        let band = RubberBand(dimension: logDimension.positive(or: 1))
        return edge * exp(band.overscroll(forDisplacement: log(shownScale / edge)))
    }

    /// Bounce-back after a release past a limit (no zoom momentum):
    /// - the scale follows a `CriticalSpring` in log space from `ln(s₀)` to `ln(L)`, `L` = nearest limit;
    /// - the offset is `pinch(anchor: u, centroid: lastCentroid, scale: s(t))` with `u` the content point under the last
    ///   centroid, minus the overscroll residual `r = pinch(L) − clamp(pinch(L))`, removed by its own spring `0 → r`,
    ///   so the offset settles into `bounds(L)`.
    public static func bounceBack(from scale: CGFloat, limits: ClosedRange<CGFloat>, lastCentroid: CGPoint,
                                  offset: CGPoint, geometry: ZoomGeometry, at time: TimeInterval) -> ZoomMotion {
        let limits = sanitized(limits)
        let s0 = scale.positive(or: 1)
        let target = clamp(s0, to: limits)
        let centroid = CGPoint(x: lastCentroid.x.finiteOrZero, y: lastCentroid.y.finiteOrZero)
        let start = CGPoint(x: offset.x.finiteOrZero, y: offset.y.finiteOrZero)
        let anchor = contentPoint(under: centroid, offset: start, scale: s0, geometry: geometry)
        let end = pinch(anchor: anchor, centroid: centroid, scale: target, geometry: geometry)
        let settled = geometry.clamped(end, at: target)
        return ZoomMotion(
            logScale: CriticalSpring(origin: log(s0), target: log(target)),
            start: time.isFinite ? time : 0,
            anchor: anchor,
            centroid: centroid,
            residual: (x: CriticalSpring(origin: 0, target: end.x - settled.x),
                       y: CriticalSpring(origin: 0, target: end.y - settled.y)),
            endScale: target
        )
    }

    /// `setZoomScale(_:)`: anchors the content point under ``ZoomGeometry/visibleCenter``, clamps the scale to
    /// `limits` and the offset to `bounds(s′)`.
    public static func zoom(to scale: CGFloat, anchoredAtVisibleCenterOf offset: CGPoint, currentScale: CGFloat,
                            limits: ClosedRange<CGFloat>, geometry: ZoomGeometry) -> (scale: CGFloat, offset: CGPoint) {
        let limits = sanitized(limits)
        let current = currentScale.positive(or: 1)
        let target = clamp(scale.positive(or: current), to: limits)
        let center = geometry.visibleCenter
        let u = contentPoint(under: center, offset: offset, scale: current, geometry: geometry)
        return (target, self.offset(keeping: u, under: center, scale: target, geometry: geometry, clamped: true))
    }

    /// `zoom(to rect:)`: `s′ = clamp(min(vw/rect.w, vh/rect.h))` with the inset-adjusted viewport, then `rect.mid` is
    /// centered at the visible center (offset clamped). `rect` is in unscaled content coordinates. A degenerate axis is
    /// ignored; a rect with no usable axis zooms to the upper limit; a non-finite rect means the whole content.
    public static func zoom(toFit rect: CGRect, limits: ClosedRange<CGFloat>,
                            geometry: ZoomGeometry) -> (scale: CGFloat, offset: CGPoint) {
        let limits = sanitized(limits)
        let finite = rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
        let rect = finite ? rect : CGRect(origin: .zero, size: geometry.unscaledContentSize)
        var ratios: [CGFloat] = []
        if rect.width > 0, geometry.x.adjustedViewportLength > 0 {
            ratios.append(geometry.x.adjustedViewportLength / rect.width)
        }
        if rect.height > 0, geometry.y.adjustedViewportLength > 0 {
            ratios.append(geometry.y.adjustedViewportLength / rect.height)
        }
        let target = clamp((ratios.min() ?? limits.upperBound).positive(or: limits.upperBound), to: limits)
        let u = CGPoint(x: rect.midX, y: rect.midY)
        return (target, offset(keeping: u, under: geometry.visibleCenter, scale: target, geometry: geometry,
                               clamped: true))
    }

    /// S7 resize / rotation: the content point at the old visible center ends at the new visible center (offset
    /// clamped to the new bounds).
    public static func offset(preservingVisibleCenterFrom old: ZoomGeometry, offset: CGPoint, scale: CGFloat,
                              to new: ZoomGeometry, newScale: CGFloat) -> CGPoint {
        let u = contentPoint(under: old.visibleCenter, offset: offset, scale: scale, geometry: old)
        return self.offset(keeping: u, under: new.visibleCenter, scale: newScale, geometry: new, clamped: true)
    }

    /// Limits with non-finite / non-positive bounds replaced by `1` and `upper ≥ lower`.
    static func sanitized(_ limits: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        let lower = limits.lowerBound.positive(or: 1)
        let upper = limits.upperBound.positive(or: lower)
        return lower...Swift.max(lower, upper)
    }
}

// MARK: - Zoom motion

/// The zoom bounce-back, sampled by the frame clock like ``AxisMotion``.
public struct ZoomMotion: Sendable, Equatable {
    /// `ln(scale)` spring (dimensionless), `ln(s₀) → ln(L)`.
    public var logScale: CriticalSpring
    /// Absolute start time in `s` (any clock; the sample times must use the same one).
    public var start: TimeInterval
    /// Unscaled content point kept under ``centroid``.
    public var anchor: CGPoint
    /// Viewport point (the last pinch centroid) in `pt`.
    public var centroid: CGPoint
    /// Overscroll residual springs (`0 → r`, `pt`) subtracted from the pinch offset.
    public var residual: (x: CriticalSpring, y: CriticalSpring)

    /// The exact final scale (the limit itself, so a bounce to `maximumZoomScale` ends `==` to it).
    public var endScale: CGFloat

    /// `endScale` defaults to `exp(logScale.target)`; pass the limit to end on it exactly (`exp(ln L)` can differ
    /// from `L` by an ulp). A non-finite or non-positive `endScale` falls back to the default.
    public init(logScale: CriticalSpring, start: TimeInterval, anchor: CGPoint, centroid: CGPoint,
                residual: (x: CriticalSpring, y: CriticalSpring), endScale: CGFloat? = nil) {
        self.logScale = logScale
        self.start = start
        self.anchor = anchor
        self.centroid = centroid
        self.residual = residual
        self.endScale = (endScale ?? .nan).positive(or: exp(logScale.target).positive(or: 1))
    }

    /// Samples at absolute `time` (`s`, same clock as ``start``).
    ///
    /// `scale = exp(logScale(t))`, `offset = pinch(anchor, centroid, scale) − residual(t)`. Once everything is settled
    /// the sample is exactly `endScale` and the offset clamped into `bounds(endScale)`.
    ///
    /// **Settling is judged on what the user sees.** Under the rendering model the content point `u′` appears at
    /// `p = s·(u′ − u) + centroid + residual`: the scroll position cancels out, so a log error `δ` moves visible content
    /// on each axis by `|e^(−δ) − 1| · |p − centroid| < δ · extent` pt (`extent` = the larger viewport length, which
    /// bounds `|p − centroid|` per axis), wherever the content is scrolled. The log spring therefore settles with the
    /// thresholds divided by `extent`, and the final snap moves visible content by less than `thresholds.distance`
    /// per axis, like ``AxisMotion``. The zoomed-coordinate `offset` itself can jump by `δ·s·u` (several pt far into
    /// a zoomed image); the simultaneous scale snap compensates it exactly, so nothing visibly moves. Judging settling
    /// on the offset instead would lengthen every bounce by `~ln(s·u / extent)/ω` (with content hit testing disabled
    /// meanwhile) for no visible change.
    public func sample(at time: TimeInterval, geometry: ZoomGeometry,
                       thresholds: RestThresholds = .init()) -> (scale: CGFloat, offset: CGPoint, isSettled: Bool) {
        let t = sanitizedElapsed(time - start)
        let tolerance = settleTolerance(at: time)
        let logThresholds = Self.logThresholds(thresholds, geometry: geometry)
        let scaleSettled = t >= logScale.settlingTime(thresholds: logThresholds) - tolerance
        let xSettled = t >= residual.x.settlingTime(thresholds: thresholds) - tolerance
        let ySettled = t >= residual.y.settlingTime(thresholds: thresholds) - tolerance

        let scale = scaleSettled ? endScale : exp(logScale.position(at: t))
        let rx = xSettled ? residual.x.target : residual.x.position(at: t)
        let ry = ySettled ? residual.y.target : residual.y.position(at: t)
        let p = ZoomSolver.pinch(anchor: anchor, centroid: centroid, scale: scale, geometry: geometry)
        let offset = CGPoint(x: p.x - rx, y: p.y - ry)
        if scaleSettled, xSettled, ySettled {
            return (scale, geometry.clamped(offset, at: scale), true)
        }
        return (scale, offset, false)
    }

    /// Elapsed time (`s` after ``start``) from which ``sample(at:geometry:thresholds:)`` reports settled: the latest of
    /// the log-scale spring's and both residual springs' settling times (same thresholds as the sampler).
    public func settlingTime(geometry: ZoomGeometry, thresholds: RestThresholds = .init()) -> TimeInterval {
        Swift.max(logScale.settlingTime(thresholds: Self.logThresholds(thresholds, geometry: geometry)),
                  residual.x.settlingTime(thresholds: thresholds),
                  residual.y.settlingTime(thresholds: thresholds))
    }

    /// `pt` thresholds mapped to log space by the larger viewport length (see ``sample(at:geometry:thresholds:)``).
    private static func logThresholds(_ thresholds: RestThresholds, geometry: ZoomGeometry) -> RestThresholds {
        let extent = Swift.max(geometry.x.viewportLength, geometry.y.viewportLength, 1)
        return RestThresholds(velocity: thresholds.velocity / extent, distance: thresholds.distance / extent,
                              negligibleReleaseVelocity: thresholds.negligibleReleaseVelocity)
    }

    public static func == (lhs: ZoomMotion, rhs: ZoomMotion) -> Bool {
        lhs.logScale == rhs.logScale && lhs.start == rhs.start && lhs.anchor == rhs.anchor
            && lhs.centroid == rhs.centroid && lhs.residual.x == rhs.residual.x && lhs.residual.y == rhs.residual.y
            && lhs.endScale == rhs.endScale
    }
}
