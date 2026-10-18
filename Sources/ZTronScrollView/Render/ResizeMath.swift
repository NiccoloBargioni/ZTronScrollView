import SwiftUI
import ZTronScrollPhysics

/// Pure resize math (SPEC S7, design M5 section 3). Axis conventions: `x_v = s*x_c + pad - o`.
enum ResizeMath {
    // MARK: Helpers

    static func axisInsets(_ i: EdgeInsets) -> (x: AxisInsets, y: AxisInsets) {
        (AxisInsets(start: i.leading, end: i.trailing), AxisInsets(start: i.top, end: i.bottom))
    }

    static func geometry(viewport: CGSize, content: CGSize, insets: EdgeInsets, alignment: UnitPoint) -> ZoomGeometry {
        ZoomGeometry(viewportSize: viewport, unscaledContentSize: content, insets: axisInsets(insets),
                     alignment: CGPoint(x: alignment.x, y: alignment.y))
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    static func lerp(_ a: CGSize, _ b: CGSize, _ t: CGFloat) -> CGSize {
        CGSize(width: max(0, lerp(a.width, b.width, t)), height: max(0, lerp(a.height, b.height, t)))
    }

    static func lerp(_ a: EdgeInsets, _ b: EdgeInsets, _ t: CGFloat) -> EdgeInsets {
        EdgeInsets(top: lerp(a.top, b.top, t), leading: lerp(a.leading, b.leading, t),
                   bottom: lerp(a.bottom, b.bottom, t), trailing: lerp(a.trailing, b.trailing, t))
    }

    static func plus(_ a: EdgeInsets, _ b: EdgeInsets, minus c: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: a.top + b.top - c.top, leading: a.leading + b.leading - c.leading,
                   bottom: a.bottom + b.bottom - c.bottom, trailing: a.trailing + b.trailing - c.trailing)
    }

    // MARK: Spec signatures

    /// Center of the unobscured viewport: `inset.start + header(top) + (len - total - header) / 2` per axis.
    static func unobscuredCenter(viewport: CGSize, insets: EdgeInsets, header: CGFloat) -> CGPoint {
        unobscuredPoint(viewport: viewport, insets: insets, header: header, at: .center)
    }

    /// The point at `unit` of the unobscured rect (`.center` is the preserved visible center).
    static func unobscuredPoint(viewport: CGSize, insets: EdgeInsets, header: CGFloat, at unit: UnitPoint) -> CGPoint {
        let h = max(0, header.isFinite ? header : 0)
        let w = viewport.width - insets.leading - insets.trailing
        let v = viewport.height - insets.top - insets.bottom - h
        return CGPoint(x: insets.leading + w * unit.x, y: insets.top + h + v * unit.y)
    }

    /// Progress `t` in [0, 1] of the animated `size` between `from` and `to`, on the axis with the larger |delta|;
    /// 1 when the sizes are equal.
    static func progress(size: CGSize, from: CGSize, to: CGSize) -> CGFloat {
        let dw = to.width - from.width, dh = to.height - from.height
        let d = abs(dw) >= abs(dh) ? dw : dh
        guard abs(d) > 1e-9 else { return 1 }
        let t = abs(dw) >= abs(dh) ? (size.width - from.width) / dw : (size.height - from.height) / dh
        guard t.isFinite else { return 1 }
        return min(1, max(0, t))
    }

    /// Unscaled content point at `center`: `u = (o + c - pad) / s`.
    static func anchor(offset: CGPoint, scale: CGFloat, center: CGPoint, pad: CGPoint) -> CGPoint {
        let s = scale > 0 && scale.isFinite ? scale : 1
        return CGPoint(x: (offset.x + center.x - pad.x) / s, y: (offset.y + center.y - pad.y) / s)
    }

    static func isAtFit(_ scale: CGFloat, fit: CGFloat) -> Bool {
        guard fit > 0, fit.isFinite else { return false }
        return abs(scale / fit - 1) <= 1e-4
    }

    /// Fit scale for a geometry (nil without a usable axis).
    static func fitScale(content: CGSize, viewport: CGSize, insets: EdgeInsets) -> CGFloat? {
        let vw = viewport.width - insets.leading - insets.trailing
        let vh = viewport.height - insets.top - insets.bottom
        var r: [CGFloat] = []
        if vw > 0, content.width > 0 { r.append(vw / content.width) }
        if vh > 0, content.height > 0 { r.append(vh / content.height) }
        guard let f = r.min(), f.isFinite, f > 0 else { return nil }
        return f
    }

    /// Re-expresses a target in a new geometry: the content point `u` goes to the focus of `new`; at fit stays at fit.
    /// Neither the offset nor the scale is clamped (the effect clamps while the commit is open).
    static func retarget(scale: CGFloat, old: ResizeCommit.Snapshot, new: ResizeCommit.Snapshot, u: CGPoint,
                         header: CGFloat, focus: UnitPoint, alignment: UnitPoint) -> (offset: CGPoint, scale: CGFloat) {
        var s = scale
        if let f0 = fitScale(content: old.contentSize, viewport: old.viewport, insets: old.insets),
           isAtFit(scale, fit: f0),
           let f1 = fitScale(content: new.contentSize, viewport: new.viewport, insets: new.insets) {
            s = f1
        }
        let g = geometry(viewport: new.viewport, content: new.contentSize, insets: new.insets, alignment: alignment)
        let pad = g.alignmentPadding(at: s)
        let c = unobscuredPoint(viewport: new.viewport, insets: new.insets, header: header, at: focus)
        return (CGPoint(x: pad.x + s * u.x - c.x, y: pad.y + s * u.y - c.y), s)
    }

    /// The geometry actually drawn at `size` under `commit` (interpolated content size and insets).
    static func presented(_ commit: ResizeCommit, size: CGSize) -> ResizeCommit.Snapshot {
        let t = progress(size: size, from: commit.previous.viewport, to: commit.current.viewport)
        return ResizeCommit.Snapshot(viewport: size,
                                     contentSize: lerp(commit.previous.contentSize, commit.current.contentSize, t),
                                     insets: lerp(commit.previous.insets, commit.current.insets, t))
    }

    /// F: the offset, scale and alignment padding drawn when the container is `size` big (design M5 section 3). A pure
    /// function of `size`, the committed target (`offset`, `scale`) and the commit; clamped to the bounds.
    static func resolve(size: CGSize, offset: CGPoint, scale: CGFloat, insetsAnimated: EdgeInsets, commit: ResizeCommit,
                        limits: ZoomLimits, alignment: UnitPoint, paging: Axis.Set)
        -> (offset: CGPoint, scale: CGFloat, pad: CGPoint) {
        let cur = commit.current, prev = commit.previous
        let t = progress(size: size, from: prev.viewport, to: cur.viewport)
        let content = lerp(prev.contentSize, cur.contentSize, t)
        let insets = plus(lerp(prev.insets, cur.insets, t), insetsAnimated, minus: cur.insets)

        // The anchored content point, from the committed target in the committed geometry.
        let gCur = geometry(viewport: cur.viewport, content: cur.contentSize, insets: cur.insets, alignment: alignment)
        let cCur = unobscuredPoint(viewport: cur.viewport, insets: cur.insets, header: commit.header, at: commit.focus)
        let uC = anchor(offset: offset, scale: scale, center: cCur, pad: gCur.alignmentPadding(at: scale))
        let u = CGPoint(x: uC.x + (commit.anchorOld.x - commit.anchorNew.x) * (1 - t),
                        y: uC.y + (commit.anchorOld.y - commit.anchorNew.y) * (1 - t))

        // Scale: at fit stays at fit (recomputed for the drawn size), always inside the limits.
        var s = scale
        if let f0 = fitScale(content: cur.contentSize, viewport: cur.viewport, insets: cur.insets), isAtFit(scale, fit: f0),
           let f = fitScale(content: content, viewport: size, insets: insets) {
            s = f
        }
        let range = limits.resolve(unscaledContentSize: content, viewportSize: size, insets: axisInsets(insets))
        s = min(max(s, range.lowerBound), range.upperBound)

        let g = geometry(viewport: size, content: content, insets: insets, alignment: alignment)
        let pad = g.alignmentPadding(at: s)
        let c = unobscuredPoint(viewport: size, insets: insets, header: commit.header, at: commit.focus)
        var o = CGPoint(x: pad.x + s * u.x - c.x, y: pad.y + s * u.y - c.y)
        if paging.contains(.horizontal), let k = commit.pagingIndex.x { o.x = CGFloat(k) * size.width }
        if paging.contains(.vertical), let k = commit.pagingIndex.y { o.y = CGFloat(k) * size.height }
        return (g.clamped(o, at: s), s, pad)
    }

    /// Inset-only change (keyboard, bars): nil `anchor` keeps the offset, except at the start edge where the content
    /// stays at the start edge; an anchor keeps the content point at that unobscured point fixed. Clamped.
    static func insetChange(offset: CGPoint, scale: CGFloat, old: ZoomGeometry, new: ZoomGeometry, anchor: UnitPoint?) -> CGPoint {
        let s = scale > 0 && scale.isFinite ? scale : 1
        func axis(_ o: CGFloat, _ a: AxisGeometry, _ b: AxisGeometry, _ unit: CGFloat?) -> CGFloat {
            let minOld = a.bounds(at: s).min
            if let unit {
                let pOld = a.insets.start + (a.viewportLength - a.insets.total) * unit
                let pNew = b.insets.start + (b.viewportLength - b.insets.total) * unit
                let u = (o + pOld - a.alignmentPadding(at: s)) / s
                return b.bounds(at: s).clamped(b.alignmentPadding(at: s) + s * u - pNew)
            }
            if o <= minOld + 0.5 { return b.bounds(at: s).min }
            return b.bounds(at: s).clamped(o)
        }
        return CGPoint(x: axis(offset.x, old.x, new.x, anchor?.x), y: axis(offset.y, old.y, new.y, anchor?.y))
    }
}
