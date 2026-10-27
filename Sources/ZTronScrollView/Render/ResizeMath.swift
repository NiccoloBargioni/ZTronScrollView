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
        let h = headerTerm(header, insets: insets)
        let w = viewport.width - insets.leading - insets.trailing
        let v = viewport.height - insets.top - insets.bottom - h
        return CGPoint(x: insets.leading + w * unit.x, y: insets.top + h + v * unit.y)
    }

    /// Progress `t` of the animated `size` between `from` (0) and `to` (1), on the axis with the larger |delta|; 1 when the
    /// sizes are equal. NOT clamped to [0, 1]: SwiftUI interpolates every frame of the change (the container, the
    /// scaling header's slot) linearly in one curve value that leaves [0, 1] — a spring overshoots `to` (t > 1), and a
    /// retargeted change (a second `withAnimation` while the first runs) is composed additively, so the drawn size first
    /// keeps moving past the snapshot the second commit starts from (t < 0). The content's geometry is extrapolated along
    /// the same line, which keeps it on the header there; clamped, it stayed at the end geometry while the header
    /// overshot (seam lab, spring with damping 0.5: 14.5 pt seam, 13 pt lateral) or froze at the snapshot while the
    /// header kept moving (retarget after 0.5 s: 23 pt).
    static func progress(size: CGSize, from: CGSize, to: CGSize) -> CGFloat {
        let dw = to.width - from.width, dh = to.height - from.height
        let d = abs(dw) >= abs(dh) ? dw : dh
        guard abs(d) > 1e-9 else { return 1 }
        let t = abs(dw) >= abs(dh) ? (size.width - from.width) / dw : (size.height - from.height) / dh
        return t.isFinite ? t : 1
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

    // MARK: ZTronMapKit mapping (D17)

    /// The header term added to the top inset: the scaling header's resting height is part of the inset since M8b-3, so a
    /// collapsed header contributes `min − R < 0`; never more negative than the top inset itself.
    static func headerTerm(_ header: CGFloat, insets: EdgeInsets) -> CGFloat {
        header.isFinite ? max(header, -max(0, insets.top)) : 0
    }

    /// ZTronMapKit's `viewport`: the unobscured area (insets and the scaling header removed), never negative.
    static func unobscuredViewport(_ v: CGSize, insets: EdgeInsets, header: CGFloat) -> CGSize {
        let h = headerTerm(header, insets: insets)
        return CGSize(width: max(0, v.width - insets.leading - insets.trailing),
                      height: max(0, v.height - insets.top - insets.bottom - h))
    }

    /// Unobscured start edge per axis (`insets.start`, plus the header on y).
    private static func unobscuredStart(insets: EdgeInsets, header: CGFloat) -> CGPoint {
        CGPoint(x: insets.leading, y: insets.top + headerTerm(header, insets: insets))
    }

    /// Library offset `o` (`x_v = s*x_c + pad - o`) -> ZTronMapKit offset `o' = o + start - pad` (`x_u = s*x_c - o'`,
    /// measured from the unobscured start edge; `0` when the content fits and is aligned by `pad`).
    static func mapKitOffset(_ o: CGPoint, insets: EdgeInsets, header: CGFloat, pad: CGPoint) -> CGPoint {
        let st = unobscuredStart(insets: insets, header: header)
        return CGPoint(x: o.x + st.x - pad.x, y: o.y + st.y - pad.y)
    }

    /// Inverse of `mapKitOffset`.
    static func libraryOffset(_ o: CGPoint, insets: EdgeInsets, header: CGFloat, pad: CGPoint) -> CGPoint {
        let st = unobscuredStart(insets: insets, header: header)
        return CGPoint(x: o.x - st.x + pad.x, y: o.y - st.y + pad.y)
    }

    /// The resize intent captured from (`offset`, `scale`) drawn in `snap`: ZTronMapKit `normalizedCenter` of the
    /// zoomed content (`0.5` on an axis without content) and the scale, flagged "at fit" when it equals the fit.
    static func intent(offset: CGPoint, scale: CGFloat, in snap: ResizeCommit.Snapshot, header: CGFloat, focus: UnitPoint,
                       alignment: UnitPoint) -> ResizeIntent {
        let s = scale > 0 && scale.isFinite ? scale : 1
        let g = geometry(viewport: snap.viewport, content: snap.contentSize, insets: snap.insets, alignment: alignment)
        // The scaling header (M8b-3): its place is captured; a collapsed one counts at its minimum height in the centre.
        let anchor = snap.header.map { HeaderMath.resizeAnchor(offsetY: offset.y, $0) }
        let header = header + (anchor == .collapsed ? -(snap.header?.band ?? 0) : 0)
        let o = mapKitOffset(offset, insets: snap.insets, header: header, pad: g.alignmentPadding(at: s))
        let v = unobscuredViewport(snap.viewport, insets: snap.insets, header: header)
        let k = CGSize(width: snap.contentSize.width * s, height: snap.contentSize.height * s)
        let n = CenterGeometry.normalizedPoint(contentOffset: o, viewport: v, contentSize: k, focus: focus)
            ?? CGPoint(x: 0.5, y: 0.5)
        let fit = fitScale(content: snap.contentSize, viewport: snap.viewport, insets: snap.insets)
        return ResizeIntent(normalizedCenter: n, scale: s, atFit: fit.map { isAtFit(s, fit: $0) } ?? false, header: anchor)
    }

    /// Scale, offset (library convention, clamped by ZTronMapKit `contentOffset(normalizedCenter:)`) and alignment
    /// padding that realise `intent` in the geometry (`viewport`, `content`, `insets`).
    static func realize(_ intent: ResizeIntent, viewport: CGSize, content: CGSize, insets: EdgeInsets, header: CGFloat,
                        focus: UnitPoint, limits: ZoomLimits, alignment: UnitPoint, headerGeometry: HeaderResize? = nil)
        -> (offset: CGPoint, scale: CGFloat, pad: CGPoint) {
        let header = header + (intent.header == .collapsed ? -(headerGeometry?.band ?? 0) : 0)
        var s = intent.scale
        if intent.atFit, let f = fitScale(content: content, viewport: viewport, insets: insets) { s = f }
        let range = limits.resolve(unscaledContentSize: content, viewportSize: viewport, insets: axisInsets(insets))
        s = min(max(s, range.lowerBound), range.upperBound)
        let g = geometry(viewport: viewport, content: content, insets: insets, alignment: alignment)
        let pad = g.alignmentPadding(at: s)
        let v = unobscuredViewport(viewport, insets: insets, header: header)
        let k = CGSize(width: content.width * s, height: content.height * s)
        let o = CenterGeometry.contentOffset(normalizedPoint: intent.normalizedCenter, viewport: v, contentSize: k, focus: focus)
        var r = libraryOffset(o, insets: insets, header: header, pad: pad)
        if let anchor = intent.header, let g = headerGeometry { r.y = HeaderMath.resizeOffsetY(anchor, centred: r.y, g) }
        return (r, s, pad)
    }

    /// The (previous, current) track `size` is drawn on: the commit's, or at a safe-area step's undrawn size the track
    /// before the step (`ResizeCommit.stepFallback`).
    static func track(_ commit: ResizeCommit, size: CGSize) -> (previous: ResizeCommit.Snapshot, current: ResizeCommit.Snapshot) {
        if let f = commit.stepFallback, abs(size.width - f.size.width) < 1e-3, abs(size.height - f.size.height) < 1e-3 {
            return (f.previous, f.current)
        }
        return (commit.previous, commit.current)
    }

    /// The geometry actually drawn at `size` under `commit` (interpolated content size and insets).
    static func presented(_ commit: ResizeCommit, size: CGSize) -> ResizeCommit.Snapshot {
        let (prev, cur) = track(commit, size: size)
        let t = progress(size: size, from: prev.viewport, to: cur.viewport)
        return ResizeCommit.Snapshot(viewport: size,
                                     contentSize: lerp(prev.contentSize, cur.contentSize, t),
                                     insets: lerp(prev.insets, cur.insets, t),
                                     header: HeaderResize.lerp(prev.header, cur.header, t))
    }

    /// `s` moved by the model change `from` -> `to` (every field). An UNANIMATED change of the model while a transition is
    /// in flight is drawn by SwiftUI as a step of the whole drawn track (additive composition: the in-flight animation keeps
    /// its progress and both of its ends move by the change), so a commit for it keeps the open commit's progress with
    /// `previous` shifted by the same change (`ZTronScrollState`, safe-area steps).
    static func shifted(_ s: ResizeCommit.Snapshot, from a: ResizeCommit.Snapshot, to b: ResizeCommit.Snapshot)
        -> ResizeCommit.Snapshot {
        func d(_ p: CGSize, _ q: CGSize, _ r: CGSize) -> CGSize {
            CGSize(width: max(0, p.width + r.width - q.width), height: max(0, p.height + r.height - q.height))
        }
        var header = b.header
        if let h = s.header, let ha = a.header, let hb = b.header {
            header = HeaderResize(base: h.base + hb.base - ha.base, band: h.band + hb.band - ha.band)
        }
        return ResizeCommit.Snapshot(viewport: d(s.viewport, a.viewport, b.viewport),
                                     contentSize: d(s.contentSize, a.contentSize, b.contentSize),
                                     insets: plus(s.insets, b.insets, minus: a.insets), header: header)
    }

    /// F: the offset, scale and alignment padding drawn when the container is `size` big (design M5 section 3, D17).
    /// A pure function of `size` and the commit's intent (ZTronMapKit `contentOffset(normalizedCenter:)` against the
    /// interpolated content size and insets); without an intent (commit closed) the target (`offset`, `scale`) is
    /// re-expressed by the same rule. Clamped to the bounds.
    static func resolve(size: CGSize, offset: CGPoint, scale: CGFloat, insetsAnimated: EdgeInsets, commit: ResizeCommit,
                        limits: ZoomLimits, alignment: UnitPoint, paging: Axis.Set)
        -> (offset: CGPoint, scale: CGFloat, pad: CGPoint) {
        let (prev, cur) = track(commit, size: size)
        let t = progress(size: size, from: prev.viewport, to: cur.viewport)
        let content = lerp(prev.contentSize, cur.contentSize, t)
        let insets = plus(lerp(prev.insets, cur.insets, t), insetsAnimated, minus: commit.current.insets)
        let intent = commit.intent
            ?? self.intent(offset: offset, scale: scale, in: cur, header: commit.header, focus: commit.focus, alignment: alignment)
        let r = realize(intent, viewport: size, content: content, insets: insets, header: commit.header, focus: commit.focus,
                        limits: limits, alignment: alignment,
                        headerGeometry: HeaderResize.lerp(prev.header, cur.header, t))
        var o = r.offset
        if paging.contains(.horizontal), let k = commit.pagingIndex.x { o.x = CGFloat(k) * size.width }
        if paging.contains(.vertical), let k = commit.pagingIndex.y { o.y = CGFloat(k) * size.height }
        let g = geometry(viewport: size, content: content, insets: insets, alignment: alignment)
        return (g.clamped(o, at: r.scale), r.scale, r.pad)
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
