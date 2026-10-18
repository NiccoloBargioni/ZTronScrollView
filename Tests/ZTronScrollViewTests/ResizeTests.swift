import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class InsetDelegate: ZTronScrollViewDelegate {
    var log: [String] = []
    func scrollViewDidScroll(_ s: ZTronScrollState) { log.append("didScroll") }
    func scrollViewDidChangeAdjustedContentInset(_ s: ZTronScrollState) { log.append("inset") }
}

@MainActor
@Suite(.serialized)
struct ResizeMathTests {
    let al = UnitPoint.center
    func snap(_ v: CGSize, _ c: CGSize, _ i: EdgeInsets = EdgeInsets()) -> ResizeCommit.Snapshot { .init(viewport: v, contentSize: c, insets: i) }

    /// Commit from V0 to V1 with target values re-derived exactly as setViewport does.
    func commit(from a: ResizeCommit.Snapshot, to b: ResizeCommit.Snapshot, offset: CGPoint, scale: CGFloat,
                insets: Bool = true) -> (ResizeCommit, CGPoint, CGFloat, CGPoint) {
        let g = ResizeMath.geometry(viewport: a.viewport, content: a.contentSize, insets: a.insets, alignment: al)
        let c0 = ResizeMath.unobscuredCenter(viewport: a.viewport, insets: a.insets, header: 0)
        let u = ResizeMath.anchor(offset: offset, scale: scale, center: c0, pad: g.alignmentPadding(at: scale))
        let r = ResizeMath.retarget(scale: scale, old: a, new: b, u: u, header: 0, focus: .center, alignment: al)
        var c = ResizeCommit()
        c.current = b; c.previous = a; c.anchorOld = u; c.anchorNew = u; c.isOpen = true
        return (c, r.offset, r.scale, u)
    }

    @Test func anchorRoundTripAtFitZoomedAndSmallContent() {
        let limits = ZoomLimits(min: .fit, max: .absolute(4))
        let cases: [(CGSize, CGFloat, CGPoint)] = [
            (CGSize(width: 400, height: 1200), 2.5, CGPoint(x: 300, y: 900)),
            (CGSize(width: 100, height: 100), 1, .zero),
            (CGSize(width: 400, height: 300), 1.5, CGPoint(x: 100, y: 50)),
        ]
        for (content, scale, offset) in cases {
            let a = snap(CGSize(width: 390, height: 800), content, EdgeInsets(top: 40, leading: 0, bottom: 30, trailing: 0))
            let b = snap(CGSize(width: 800, height: 390), content, EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 30))
            let (c, o, s, u) = commit(from: a, to: b, offset: offset, scale: scale)
            let r = ResizeMath.resolve(size: b.viewport, offset: o, scale: s, insetsAnimated: b.insets, commit: c,
                                       limits: ZoomLimits(min: .absolute(0.01), max: .absolute(8)), alignment: al, paging: [])
            _ = limits
            let g = ResizeMath.geometry(viewport: b.viewport, content: content, insets: b.insets, alignment: al)
            let center = ResizeMath.unobscuredCenter(viewport: b.viewport, insets: b.insets, header: 0)
            let seen = ResizeMath.anchor(offset: r.offset, scale: r.scale, center: center, pad: g.alignmentPadding(at: r.scale))
            // equal unless clamped at an edge: then the offset is within bounds
            let bnds = g.bounds(at: r.scale)
            #expect(r.offset.x >= bnds.x.min - 1e-9 && r.offset.x <= bnds.x.max + 1e-9)
            #expect(r.offset.y >= bnds.y.min - 1e-9 && r.offset.y <= bnds.y.max + 1e-9)
            if r.offset == o { #expect(abs(seen.x - u.x) < 1e-9 && abs(seen.y - u.y) < 1e-9) }
        }
    }

    @Test func fitStaysFitAndNonFitKeepsScale() {
        let content = CGSize(width: 400, height: 800)
        let a = snap(CGSize(width: 400, height: 800), content), b = snap(CGSize(width: 800, height: 400), content)
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        let (c, o, s, _) = commit(from: a, to: b, offset: .zero, scale: 1)
        let r = ResizeMath.resolve(size: b.viewport, offset: o, scale: s, insetsAnimated: b.insets, commit: c, limits: lim, alignment: al, paging: [])
        #expect(abs(r.scale - 0.5) < 1e-9)
        let (c2, o2, s2, _) = commit(from: a, to: b, offset: .zero, scale: 2)
        let r2 = ResizeMath.resolve(size: b.viewport, offset: o2, scale: s2, insetsAnimated: b.insets, commit: c2, limits: lim, alignment: al, paging: [])
        #expect(r2.scale == 2)
        let r3 = ResizeMath.resolve(size: b.viewport, offset: o2, scale: 9, insetsAnimated: b.insets, commit: c2, limits: lim, alignment: al, paging: [])
        #expect(r3.scale == 4)
    }

    @Test func invarianceAcrossTheCommit() {
        var rng = SystemRandomNumberGenerator()
        let content = CGSize(width: 390, height: 3000)
        let a = snap(CGSize(width: 390, height: 844), content), b = snap(CGSize(width: 844, height: 390), content)
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        for (offset, scale) in [(CGPoint(x: 0, y: 500), CGFloat(1)), (CGPoint(x: 0, y: 0), 1), (CGPoint(x: 100, y: 800), 2)] {
            var old = ResizeCommit(); old.current = a; old.previous = a
            let (new, o, s, _) = commit(from: a, to: b, offset: offset, scale: scale)
            for _ in 0..<200 {
                let t = CGFloat.random(in: 0...1, using: &rng)
                let size = CGSize(width: a.viewport.width + (b.viewport.width - a.viewport.width) * t,
                                  height: a.viewport.height + (b.viewport.height - a.viewport.height) * t)
                let f0 = ResizeMath.resolve(size: size, offset: offset, scale: scale, insetsAnimated: a.insets, commit: old, limits: lim, alignment: al, paging: [])
                let f1 = ResizeMath.resolve(size: size, offset: o, scale: s, insetsAnimated: b.insets, commit: new, limits: lim, alignment: al, paging: [])
                #expect(abs(f0.offset.x - f1.offset.x) < 1e-6 && abs(f0.offset.y - f1.offset.y) < 1e-6 && abs(f0.scale - f1.scale) < 1e-9)
            }
        }
    }

    @Test func pagingSnapsAtEveryT() {
        let content = CGSize(width: 390 * 3, height: 800)
        let a = snap(CGSize(width: 390, height: 800), content), b = snap(CGSize(width: 800, height: 390), content)
        var (c, o, s, _) = commit(from: a, to: b, offset: CGPoint(x: 400, y: 0), scale: 1)
        c.pagingIndex.x = 1
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let size = CGSize(width: 390 + 410 * t, height: 800 - 410 * t)
            let r = ResizeMath.resolve(size: size, offset: o, scale: s, insetsAnimated: b.insets, commit: c,
                                       limits: ZoomLimits(), alignment: .topLeading, paging: .horizontal)
            #expect(r.offset.x == size.width || r.offset.x == max(0, content.width - size.width))
        }
    }

    // MARK: D16 normalized centre (ported from ZTronMapKit ContentGeometry.normalizedCenter / contentOffset)

    @Test func normalizedCentreClampsAndCentresDegenerateAxes() {
        let k = CGSize(width: 400, height: 1000)
        let n = ResizeMath.normalized(CGPoint(x: 100, y: 400), in: k)
        #expect(abs(n.x - 0.25) < 1e-12 && abs(n.y - 0.4) < 1e-12)
        let d = ResizeMath.denormalized(n, in: CGSize(width: 800, height: 2000))
        #expect(abs(d.x - 200) < 1e-9 && abs(d.y - 800) < 1e-9)
        // beyond the content (top-leading alignment, content smaller than the viewport) -> clamped to [0, 1]
        let c = ResizeMath.normalized(CGPoint(x: 600, y: -5), in: k)
        #expect(c.x == 1 && c.y == 0)
        // no content on an axis -> 0.5 (nothing to preserve, whole axis visible)
        #expect(ResizeMath.normalized(CGPoint(x: 10, y: 10), in: CGSize(width: 0, height: 100)).x == 0.5)
    }

    /// Reflow commit as the state builds it: viewport first (content unchanged), then the reflowed content size with
    /// `anchorNew = n * newContent` (`ResizeStateTests` covers the sequence through the state).
    func reflowCommit(from a: ResizeCommit.Snapshot, to b: ResizeCommit.Snapshot, offset: CGPoint, scale: CGFloat)
        -> (ResizeCommit, CGPoint, CGFloat, CGPoint) {
        let g = ResizeMath.geometry(viewport: a.viewport, content: a.contentSize, insets: a.insets, alignment: al)
        let c0 = ResizeMath.unobscuredCenter(viewport: a.viewport, insets: a.insets, header: 0)
        let u = ResizeMath.anchor(offset: offset, scale: scale, center: c0, pad: g.alignmentPadding(at: scale))
        let n = ResizeMath.normalized(u, in: a.contentSize)
        let uNew = ResizeMath.denormalized(n, in: b.contentSize)
        let r = ResizeMath.retarget(scale: scale, old: a, new: b, u: uNew, header: 0, focus: .center, alignment: al)
        var c = ResizeCommit()
        c.current = b; c.previous = a; c.anchorOld = u; c.anchorNew = uNew; c.normalizedAnchor = n; c.isOpen = true
        return (c, r.offset, r.scale, n)
    }

    /// Normalized centre of what F draws at `size` under `c`.
    func drawnNormalized(_ c: ResizeCommit, size: CGSize, offset: CGPoint, scale: CGFloat, limits: ZoomLimits) -> (n: CGPoint, r: (offset: CGPoint, scale: CGFloat, pad: CGPoint), content: CGSize) {
        let p = ResizeMath.presented(c, size: size)
        let r = ResizeMath.resolve(size: size, offset: offset, scale: scale, insetsAnimated: c.current.insets, commit: c, limits: limits, alignment: al, paging: [])
        let centre = ResizeMath.unobscuredCenter(viewport: size, insets: p.insets, header: 0)
        let u = ResizeMath.anchor(offset: r.offset, scale: r.scale, center: centre, pad: r.pad)
        return (CGPoint(x: u.x / p.contentSize.width, y: u.y / p.contentSize.height), r, p.contentSize)
    }

    @Test func reflowKeepsNormalizedCentreAtEveryT() {
        // The user's vertical image (width = viewport width, height 5x): iPhone portrait -> landscape.
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 2100), EdgeInsets(top: 68, leading: 0, bottom: 34, trailing: 0))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 3880), EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
        let lim = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let cases: [(CGPoint, CGFloat)] = [(CGPoint(x: 0, y: 2100 * 0.4 - 473), 1), (CGPoint(x: 210, y: 1200), 2), (CGPoint(x: 0, y: -48), 1)]
        for (offset, scale) in cases {
            let (c, o, s, n) = reflowCommit(from: a, to: b, offset: offset, scale: scale)
            for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                let size = CGSize(width: ResizeMath.lerp(a.viewport.width, b.viewport.width, t), height: ResizeMath.lerp(a.viewport.height, b.viewport.height, t))
                let d = drawnNormalized(c, size: size, offset: o, scale: s, limits: lim)
                let g = ResizeMath.geometry(viewport: size, content: d.content, insets: ResizeMath.presented(c, size: size).insets, alignment: al)
                let bnds = g.bounds(at: d.r.scale)
                #expect(d.r.offset.y >= bnds.y.min - 1e-9 && d.r.offset.y <= bnds.y.max + 1e-9)
                // preserved to < 1 pt of the drawn content, unless clamped at a bound
                let ey = abs(d.n.y - n.y) * d.content.height * d.r.scale
                let onBound = abs(d.r.offset.y - bnds.y.min) < 1e-6 || abs(d.r.offset.y - bnds.y.max) < 1e-6
                #expect(ey < 1 || onBound, "t=\(t) offset=\(offset) ey=\(ey)")
                #expect(abs(d.n.x - n.x) * d.content.width < 1, "x preserved")
                #expect(d.r.scale == scale, "absolute limits: scale kept")
            }
        }
    }

    @Test func reflowSmallerThanViewportCentresAndClampsOnlyAsNeeded() {
        // Short content (height 100 at width 420) that the viewport can show whole; zoom enabled -> centred.
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 100))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 185))
        let lim = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let (c, o, s, n) = reflowCommit(from: a, to: b, offset: CGPoint(x: 0, y: 0), scale: 1)
        #expect(abs(n.y - 0.5) < 1e-9 && abs(n.x - 0.5) < 1e-9)
        let d = drawnNormalized(c, size: b.viewport, offset: o, scale: s, limits: lim)
        #expect(abs(d.n.y - 0.5) < 1e-9 && d.r.offset.y == 0 && abs(d.r.pad.y - (420 - 185) / 2) < 1e-9)
        // Near the bottom in landscape, back to portrait: the normalized centre would need a negative offset -> clamped to the edge
        let (c2, o2, s2, _) = reflowCommit(from: b, to: a, offset: CGPoint(x: 0, y: 3880 - 420 - 20), scale: 1)
        let d2 = drawnNormalized(c2, size: a.viewport, offset: o2, scale: s2, limits: lim)
        #expect(d2.r.offset.y == 0)
    }

    @Test func reflowFitStaysFit() {
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 2100))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 3880))
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        let fitA = ResizeMath.fitScale(content: a.contentSize, viewport: a.viewport, insets: a.insets)!
        let (c, o, s, _) = reflowCommit(from: a, to: b, offset: .zero, scale: fitA)
        let d = drawnNormalized(c, size: b.viewport, offset: o, scale: s, limits: lim)
        #expect(abs(d.r.scale - 420 / 3880) < 1e-9)
    }

    @Test func insetChangeRules() {
        let content = CGSize(width: 100, height: 3000)
        let v = CGSize(width: 100, height: 600)
        let old = ResizeMath.geometry(viewport: v, content: content, insets: EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0), alignment: .topLeading)
        let new = ResizeMath.geometry(viewport: v, content: content, insets: EdgeInsets(top: 50, leading: 0, bottom: 300, trailing: 0), alignment: .topLeading)
        // at the start edge stays at the start edge; elsewhere unchanged
        #expect(ResizeMath.insetChange(offset: CGPoint(x: 0, y: -50), scale: 1, old: old, new: new, anchor: nil).y == -50)
        #expect(ResizeMath.insetChange(offset: CGPoint(x: 0, y: 700), scale: 1, old: old, new: new, anchor: nil).y == 700)
        // bottom anchor pins the bottom: point at the unobscured bottom stays there
        let o = ResizeMath.insetChange(offset: CGPoint(x: 0, y: 700), scale: 1, old: old, new: new, anchor: .bottom)
        #expect(abs(o.y - 1000) < 1e-9)
    }
}

@MainActor
@Suite(.serialized)
struct ResizeStateTests {
    func vp(_ w: CGFloat, _ h: CGFloat, _ safe: EdgeInsets = EdgeInsets()) -> ViewportMetrics { ViewportMetrics(size: CGSize(width: w, height: h), safeArea: safe) }
    func date(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }

    @Test(arguments: OSPath.allCases) func midMotionResizeInterruptsThenPreservesCenter(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(vp(390, 800))
        s.setContentOffset(CGPoint(x: 0, y: 1000), animated: true)
        s.setViewport(vp(390, 400))
        #expect(s.phase == .idle)
        s.closeResize()
        #expect(s.contentOffset.y + 200 == 400)   // the center (offset 0 + 400) is preserved; the animation was stopped at offset 0
    }

    @Test(arguments: OSPath.allCases) func watchAnimatesThenSettles(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(vp(390, 800))
        s.setViewport(vp(390, 400))
        #expect(s.isClockRunning)
        s.probe.record(CGPoint(x: 0, y: 100), 1, size: CGSize(width: 390, height: 600))
        s.step(to: date(1))
        #expect(s.phase == .animating)
        s.probe.record(CGPoint(x: 0, y: 200), 1, size: CGSize(width: 390, height: 400))
        s.step(to: date(2)); s.step(to: date(3)); s.step(to: date(4))
        #expect(s.phase == .idle && !s.isClockRunning)
    }

    @Test(arguments: OSPath.allCases) func unanimatedResizeEndsSilently(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(vp(390, 800))
        s.setViewport(vp(390, 400))
        s.probe.record(.zero, 1, size: CGSize(width: 390, height: 400))
        s.step(to: date(1))
        #expect(s.phase == .idle && !s.isClockRunning && !s.peek.metrics.resize.isOpen)
    }

    @Test(arguments: OSPath.allCases) func insetOnlyKeyboardAtTopKeepsOffsetAndNotifiesOnce(path: OSPath) {
        let s = makeState(path)
        let d = InsetDelegate(); s.delegate = d
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(vp(390, 800))
        s.track(offset: CGPoint(x: 0, y: 200), zoom: 1)
        d.log.removeAll()
        s.setViewport(vp(390, 800, EdgeInsets(top: 0, leading: 0, bottom: 300, trailing: 0)))
        #expect(s.contentOffset.y == 200 && s.adjustedContentInset.bottom == 300)
        #expect(d.log.filter { $0 == "inset" }.count == 1 && d.log.first == "inset")
        #expect(!s.peek.metrics.resize.isOpen)
    }

    @Test(arguments: OSPath.allCases) func contentInsetStartsAtStartEdge(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(vp(390, 800))
        s.contentInset = EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        #expect(s.contentOffset.y == -60 && s.adjustedContentInset.top == 60)
    }

    /// Normalized centre of the state's drawn geometry at the committed viewport.
    func normalizedCentre(_ s: ZTronScrollState) -> CGPoint {
        let m = s.peek.metrics, z = s.zoomScale, o = s.contentOffset, i = m.adjustedContentInset
        let v = m.viewportSize, k = m.contentSize
        let w = v.width - i.leading - i.trailing, h = v.height - i.top - i.bottom
        let pad = CGPoint(x: max(0, w - z * k.width) / 2, y: max(0, h - z * k.height) / 2)
        return CGPoint(x: ((o.x + i.leading + w / 2 - pad.x) / z) / k.width, y: ((o.y + i.top + h / 2 - pad.y) / z) / k.height)
    }

    /// D16 through the state: the viewport changes first, the reflowed content size lands later (as SwiftUI reports
    /// them); the normalized centre survives, at 1x and zoomed, at the middle and near the top.
    @Test(arguments: OSPath.allCases) func reflowAfterViewportKeepsNormalizedCentre(path: OSPath) {
        for (y, zoom) in [(CGFloat(2100 * 0.4 - 473), CGFloat(1)), (1200, 2), (-48, 1)] {
            let s = makeState(path)
            s.scrollAxes = .vertical
            s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
            s.setContentSize(CGSize(width: 420, height: 2100))
            s.setViewport(vp(420, 912, EdgeInsets(top: 68, leading: 0, bottom: 34, trailing: 0)))
            s.track(offset: CGPoint(x: 0, y: y), zoom: zoom)
            let n0 = normalizedCentre(s)
            s.setViewport(vp(776, 420, EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)))
            #expect(s.peek.metrics.resize.isOpen)
            // Mid-transition before the content size lands: the drawn normalized centre is already n0.
            let mid = CGSize(width: 598, height: 666)
            s.setContentSize(CGSize(width: 776, height: 3880))
            s.setContentSize(CGSize(width: 776, height: 3880))   // idempotent
            let c = s.peek.metrics.resize
            #expect(abs(c.anchorNew.y - n0.y * 3880) < 1e-6 && abs(c.anchorNew.x - n0.x * 776) < 1e-6)
            let r = ResizeMath.resolve(size: mid, offset: s.peek.targetOffset, scale: s.peek.targetZoom,
                                       insetsAnimated: c.current.insets, commit: c, limits: s.zoomLimits,
                                       alignment: s.contentAlignment, paging: [])
            let pm = ResizeMath.presented(c, size: mid)
            let um = ResizeMath.anchor(offset: r.offset, scale: r.scale, center: ResizeMath.unobscuredCenter(viewport: mid, insets: pm.insets, header: 0), pad: r.pad)
            #expect(abs(um.y / pm.contentSize.height - n0.y) * pm.contentSize.height * r.scale < 1, "mid-transition")
            s.closeResize()
            let n1 = normalizedCentre(s)
            #expect(abs(n1.y - n0.y) * 3880 * zoom < 1, "y=\(y) zoom=\(zoom) n0=\(n0) n1=\(n1)")
            #expect(abs(n1.x - n0.x) * 776 * zoom < 1)
            #expect(s.zoomScale == zoom)
            // and back to portrait
            s.setViewport(vp(420, 912, EdgeInsets(top: 68, leading: 0, bottom: 34, trailing: 0)))
            s.setContentSize(CGSize(width: 420, height: 2100))
            s.closeResize()
            let n2 = normalizedCentre(s)
            #expect(abs(n2.y - n0.y) * 2100 * zoom < 1 && abs(n2.x - n0.x) * 420 * zoom < 1, "back: \(n2) vs \(n0)")
            #expect(abs(s.contentOffset.y - y) < 1e-6, "round trip restores the offset")
        }
    }

    @Test(arguments: OSPath.allCases) func fixedSizeContentIsUnaffectedByTheNormalizedRule(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 1500, height: 1000))
        s.setViewport(vp(420, 912))
        s.track(offset: CGPoint(x: 300, y: 200), zoom: 1)
        s.setViewport(vp(776, 420))
        s.setContentSize(CGSize(width: 1500, height: 1000))   // unchanged: no-op
        let c = s.peek.metrics.resize
        #expect(c.anchorOld == c.anchorNew && abs(c.normalizedAnchor.x - c.anchorOld.x / 1500) < 1e-12)
        s.closeResize()
        #expect(abs(s.contentOffset.x + 388 - (300 + 210)) < 1e-9 && abs(s.contentOffset.y + 210 - (200 + 456)) < 1e-9)
    }

    @Test(arguments: OSPath.allCases) func pagingResizeEndsSnapped(path: OSPath) {
        let s = makeState(path)
        s.isPagingEnabled = true
        s.scrollAxes = .horizontal
        s.setContentSize(CGSize(width: 1200, height: 800))
        s.setViewport(vp(400, 800))
        s.track(offset: CGPoint(x: 400, y: 0), zoom: 1)
        s.setViewport(vp(300, 800))
        s.closeResize()
        #expect(s.contentOffset.x == 300)
    }
}
