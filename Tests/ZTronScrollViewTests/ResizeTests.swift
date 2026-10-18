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

    /// Commit from `a` to `b` with the intent captured from (`offset`, `scale`) in `a`, exactly as setViewport does.
    func commit(from a: ResizeCommit.Snapshot, to b: ResizeCommit.Snapshot, offset: CGPoint, scale: CGFloat,
                intent: ResizeIntent? = nil, limits: ZoomLimits = ZoomLimits(min: .absolute(0.01), max: .absolute(8)))
        -> (ResizeCommit, CGPoint, CGFloat, ResizeIntent) {
        let n = intent ?? ResizeMath.intent(offset: offset, scale: scale, in: a, header: 0, focus: .center, alignment: al)
        var c = ResizeCommit()
        c.current = b; c.previous = a; c.intent = n; c.isOpen = true
        let r = ResizeMath.resolve(size: b.viewport, offset: offset, scale: scale, insetsAnimated: b.insets, commit: c,
                                   limits: limits, alignment: al, paging: [])
        return (c, r.offset, r.scale, n)
    }

    // MARK: ZTronMapKit geometry, verbatim (D17)

    @Test func centreGeometryVerbatim() {
        let k = CGSize(width: 400, height: 1000), v = CGSize(width: 200, height: 300)
        let n = CenterGeometry.normalizedCenter(contentOffset: CGPoint(x: 100, y: 400), viewport: v, contentSize: k)!
        #expect(abs(n.x - 0.5) < 1e-12 && abs(n.y - 0.55) < 1e-12)
        let o = CenterGeometry.contentOffset(normalizedCenter: n, viewport: v, contentSize: k)
        #expect(abs(o.x - 100) < 1e-9 && abs(o.y - 400) < 1e-9)
        // clamped into [0, content - viewport]; smaller-than-viewport axis -> 0
        #expect(CenterGeometry.contentOffset(normalizedCenter: CGPoint(x: 1, y: 0), viewport: v, contentSize: k) == CGPoint(x: 200, y: 0))
        #expect(CenterGeometry.contentOffset(normalizedCenter: CGPoint(x: 0.5, y: 0.5), viewport: v, contentSize: CGSize(width: 100, height: 100)) == .zero)
        #expect(CenterGeometry.normalizedCenter(contentOffset: .zero, viewport: v, contentSize: CGSize(width: 0, height: 100)) == nil)
        #expect(CenterGeometry.contentOffset(normalizedCenter: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), viewport: CGSize(width: -1, height: 10), contentSize: k) == .zero)
    }

    @Test func libraryOffsetMappingRoundTrips() {
        let ins = EdgeInsets(top: 40, leading: 10, bottom: 30, trailing: 20)
        let pad = CGPoint(x: 5, y: 0)
        let o = CGPoint(x: -10, y: 123)
        let m = ResizeMath.mapKitOffset(o, insets: ins, header: 15, pad: pad)
        #expect(m == CGPoint(x: -5, y: 178))
        #expect(ResizeMath.libraryOffset(m, insets: ins, header: 15, pad: pad) == o)
        #expect(ResizeMath.unobscuredViewport(CGSize(width: 390, height: 800), insets: ins, header: 15) == CGSize(width: 360, height: 715))
    }

    /// (A): realising the sticky intent in the original geometry gives back the original offset and scale exactly,
    /// whatever clamping happened in between (fit, zoomed, every edge, content smaller than the viewport).
    @Test func intentRoundTripsThroughEvenRotations() {
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        let ins = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let insL = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        let a = CGSize(width: 393, height: 852), b = CGSize(width: 852, height: 393)
        for content in [CGSize(width: 393, height: 3000), CGSize(width: 1200, height: 900), CGSize(width: 200, height: 100)] {
            let gA = ResizeMath.geometry(viewport: a, content: content, insets: ins, alignment: al)
            let fit = ResizeMath.fitScale(content: content, viewport: a, insets: ins)!
            for scale in [fit, 1, 2.5, 4] {
                let range = lim.resolve(unscaledContentSize: content, viewportSize: a, insets: ResizeMath.axisInsets(ins))
                guard range.contains(scale) else { continue }
                let bnds = gA.bounds(at: scale)
                let offsets = [CGPoint(x: bnds.x.min, y: bnds.y.min), CGPoint(x: bnds.x.max, y: bnds.y.max),
                               CGPoint(x: bnds.x.min, y: bnds.y.max), CGPoint(x: bnds.x.max, y: bnds.y.min),
                               CGPoint(x: (bnds.x.min + bnds.x.max) / 2, y: bnds.y.min + (bnds.y.max - bnds.y.min) * 0.9)]
                for o0 in offsets {
                    let sA = snap(a, content, ins), sB = snap(b, content, insL)
                    let (_, o1, s1, n) = commit(from: sA, to: sB, offset: o0, scale: scale, limits: lim)
                    let gB = ResizeMath.geometry(viewport: b, content: content, insets: insL, alignment: al)
                    let bb = gB.bounds(at: s1)
                    #expect(o1.x >= bb.x.min - 1e-9 && o1.x <= bb.x.max + 1e-9 && o1.y >= bb.y.min - 1e-9 && o1.y <= bb.y.max + 1e-9)
                    // back with the SAME intent (sticky), not one re-derived from the clamped landscape state
                    let (_, o2, s2, _) = commit(from: sB, to: sA, offset: o1, scale: s1, intent: n, limits: lim)
                    #expect(abs(o2.x - o0.x) < 1e-6 && abs(o2.y - o0.y) < 1e-6, "content=\(content) s=\(scale) o0=\(o0) o2=\(o2)")
                    #expect(abs(s2 - scale) < 1e-9)
                    if scale == fit { #expect(abs(s1 - ResizeMath.fitScale(content: content, viewport: b, insets: insL)!) < 1e-12) }
                }
            }
        }
    }

    @Test func fitStaysFitAndNonFitKeepsScale() {
        let content = CGSize(width: 400, height: 800)
        let a = snap(CGSize(width: 400, height: 800), content), b = snap(CGSize(width: 800, height: 400), content)
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        let (_, _, s, _) = commit(from: a, to: b, offset: .zero, scale: 1, limits: lim)
        #expect(abs(s - 0.5) < 1e-9)
        let (_, _, s2, _) = commit(from: a, to: b, offset: .zero, scale: 2, limits: lim)
        #expect(s2 == 2)
        let (_, _, s3, _) = commit(from: a, to: b, offset: .zero, scale: 9, limits: lim)
        #expect(s3 == 4)
    }

    @Test func invarianceAcrossTheCommit() {
        var rng = SystemRandomNumberGenerator()
        let content = CGSize(width: 390, height: 3000)
        let a = snap(CGSize(width: 390, height: 844), content), b = snap(CGSize(width: 844, height: 390), content)
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        for (offset, scale) in [(CGPoint(x: 0, y: 500), CGFloat(1)), (CGPoint(x: 0, y: 0), 1), (CGPoint(x: 100, y: 800), 2)] {
            var old = ResizeCommit(); old.current = a; old.previous = a
            let (new, o, s, _) = commit(from: a, to: b, offset: offset, scale: scale, limits: lim)
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

    // MARK: Reflowing content (D16/D17): the normalized centre is relative to the zoomed content

    /// Normalized centre of what F draws at `size` under `c`.
    func drawnNormalized(_ c: ResizeCommit, size: CGSize, offset: CGPoint, scale: CGFloat, limits: ZoomLimits) -> (n: CGPoint, r: (offset: CGPoint, scale: CGFloat, pad: CGPoint), content: CGSize) {
        let p = ResizeMath.presented(c, size: size)
        let r = ResizeMath.resolve(size: size, offset: offset, scale: scale, insetsAnimated: c.current.insets, commit: c, limits: limits, alignment: al, paging: [])
        let n = ResizeMath.intent(offset: r.offset, scale: r.scale, in: .init(viewport: size, contentSize: p.contentSize, insets: p.insets),
                                  header: 0, focus: .center, alignment: al).normalizedCenter
        return (n, r, p.contentSize)
    }

    @Test func reflowKeepsNormalizedCentreAtEveryT() {
        // The user's vertical image (width = viewport width, height 5x): iPhone portrait -> landscape.
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 2100), EdgeInsets(top: 68, leading: 0, bottom: 34, trailing: 0))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 3880), EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
        let lim = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let cases: [(CGPoint, CGFloat)] = [(CGPoint(x: 0, y: 2100 * 0.4 - 473), 1), (CGPoint(x: 210, y: 1200), 2), (CGPoint(x: 0, y: -48), 1)]
        for (offset, scale) in cases {
            let (c, o, s, n) = commit(from: a, to: b, offset: offset, scale: scale, limits: lim)
            for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                let size = CGSize(width: ResizeMath.lerp(a.viewport.width, b.viewport.width, t), height: ResizeMath.lerp(a.viewport.height, b.viewport.height, t))
                let d = drawnNormalized(c, size: size, offset: o, scale: s, limits: lim)
                let g = ResizeMath.geometry(viewport: size, content: d.content, insets: ResizeMath.presented(c, size: size).insets, alignment: al)
                let bnds = g.bounds(at: d.r.scale)
                #expect(d.r.offset.y >= bnds.y.min - 1e-9 && d.r.offset.y <= bnds.y.max + 1e-9)
                let ey = abs(d.n.y - n.normalizedCenter.y) * d.content.height * d.r.scale
                let onBound = abs(d.r.offset.y - bnds.y.min) < 1e-6 || abs(d.r.offset.y - bnds.y.max) < 1e-6
                #expect(ey < 1 || onBound, "t=\(t) offset=\(offset) ey=\(ey)")
                #expect(abs(d.n.x - n.normalizedCenter.x) * d.content.width < 1, "x preserved")
                #expect(d.r.scale == scale, "absolute limits: scale kept")
            }
        }
    }

    @Test func reflowSmallerThanViewportCentresAndClampsOnlyAsNeeded() {
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 100))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 185))
        let lim = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let (c, o, s, n) = commit(from: a, to: b, offset: CGPoint(x: 0, y: 0), scale: 1, limits: lim)
        #expect(abs(n.normalizedCenter.y - 0.5) < 1e-9 && abs(n.normalizedCenter.x - 0.5) < 1e-9)
        let d = drawnNormalized(c, size: b.viewport, offset: o, scale: s, limits: lim)
        #expect(abs(d.n.y - 0.5) < 1e-9 && d.r.offset.y == 0 && abs(d.r.pad.y - (420 - 185) / 2) < 1e-9)
        let (_, o2, _, _) = commit(from: b, to: a, offset: CGPoint(x: 0, y: 3880 - 420 - 20), scale: 1, limits: lim)
        #expect(o2.y == 0)
    }

    @Test func reflowFitStaysFit() {
        let a = snap(CGSize(width: 420, height: 912), CGSize(width: 420, height: 2100))
        let b = snap(CGSize(width: 776, height: 420), CGSize(width: 776, height: 3880))
        let lim = ZoomLimits(min: .fit, max: .absolute(4))
        let fitA = ResizeMath.fitScale(content: a.contentSize, viewport: a.viewport, insets: a.insets)!
        let (_, _, s, _) = commit(from: a, to: b, offset: .zero, scale: fitA, limits: lim)
        #expect(abs(s - 420 / 3880) < 1e-9)
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
            #expect(c.intent != nil && abs(c.intent!.normalizedCenter.y - n0.y) < 1e-6)
            let r = ResizeMath.resolve(size: mid, offset: s.peek.targetOffset, scale: s.peek.targetZoom,
                                       insetsAnimated: c.current.insets, commit: c, limits: s.zoomLimits,
                                       alignment: s.contentAlignment, paging: [])
            let pm = ResizeMath.presented(c, size: mid)
            let um = ResizeMath.intent(offset: r.offset, scale: r.scale, in: .init(viewport: mid, contentSize: pm.contentSize, insets: pm.insets),
                                       header: 0, focus: .center, alignment: s.contentAlignment).normalizedCenter
            #expect(abs(um.y - n0.y) * pm.contentSize.height * r.scale < 1, "mid-transition")
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
        #expect(c.intent != nil && abs(c.intent!.normalizedCenter.x - (300 + 210) / 1500) < 1e-12)
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

    // MARK: (A) even rotations restore the initial offset and scale (D17 sticky intent)

    /// Portrait <-> landscape N times through the full watch (probe at the final size, ticks until the commit closes).
    func rotate(_ s: ZTronScrollState, to size: CGSize, safe: EdgeInsets, content: CGSize?, t: inout TimeInterval) {
        s.setViewport(vp(size.width, size.height, safe))
        if let content { s.setContentSize(content) }
        s.probe.record(s.peek.targetOffset, s.peek.targetZoom, size: size)
        for _ in 0..<4 { t += 1; s.step(to: date(t)) }
        #expect(!s.peek.metrics.resize.isOpen)
    }

    @Test(arguments: OSPath.allCases) func evenRotationsRestoreOffsetAndZoomExactly(path: OSPath) {
        let p = CGSize(width: 393, height: 852), l = CGSize(width: 852, height: 393)
        let sp = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), sl = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        // (fixed content, reflowed landscape content)
        let shapes: [(CGSize, CGSize?)] = [(CGSize(width: 393, height: 3000), nil), (CGSize(width: 1200, height: 900), nil),
                                           (CGSize(width: 393, height: 1965), CGSize(width: 852, height: 4260))]
        for (content, reflowed) in shapes {
            for zoom in [CGFloat(0), 1, 2.5] {      // 0 = at fit
                let s = makeState(path)
                s.zoomLimits = ZoomLimits(min: .fit, max: .absolute(4))
                s.setContentSize(content)
                s.setViewport(vp(p.width, p.height, sp))
                let z = zoom == 0 ? s.zoomScale : zoom
                if zoom != 0 { s.setZoomScale(zoom, animated: false) }
                let g = s.makeZoomGeometry()
                let b = g.bounds(at: z)
                let offsets = [CGPoint(x: b.x.min, y: b.y.min), CGPoint(x: b.x.max, y: b.y.max),
                               CGPoint(x: b.x.min + (b.x.max - b.x.min) * 0.3, y: b.y.min + (b.y.max - b.y.min) * 0.95)]
                for o0 in offsets {
                    s.setContentOffset(o0, animated: false)
                    let z0 = s.zoomScale, o0 = s.contentOffset
                    var t: TimeInterval = 0
                    for n in 1...4 {
                        let landscape = n % 2 == 1
                        rotate(s, to: landscape ? l : p, safe: landscape ? sl : sp, content: landscape ? reflowed : (reflowed == nil ? nil : content), t: &t)
                        if !landscape {
                            #expect(abs(s.contentOffset.x - o0.x) < 1e-6 && abs(s.contentOffset.y - o0.y) < 1e-6,
                                    "n=\(n) content=\(content) z=\(z0) o0=\(o0) got \(s.contentOffset)")
                            #expect(s.zoomScale == z0, "n=\(n) zoom \(s.zoomScale) != \(z0)")
                        } else {
                            #expect(s.resizeIntent != nil)
                        }
                    }
                }
            }
        }
    }

    @Test(arguments: OSPath.allCases) func interactionBetweenRotationsResetsTheIntent(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 393, height: 3000))
        s.setViewport(vp(393, 852))
        s.setContentOffset(CGPoint(x: 0, y: 2148), animated: false)   // bottom edge
        var t: TimeInterval = 0
        rotate(s, to: CGSize(width: 852, height: 393), safe: EdgeInsets(), content: nil, t: &t)
        #expect(s.resizeIntent != nil)
        s.track(offset: CGPoint(x: 0, y: 1000), zoom: 1)              // a pan: the intent is dropped
        #expect(s.resizeIntent == nil)
        rotate(s, to: CGSize(width: 393, height: 852), safe: EdgeInsets(), content: nil, t: &t)
        // back in portrait the centre of the panned view (1000 + 196.5) is preserved, not the pre-rotation offset
        #expect(abs(s.contentOffset.y - (1196.5 - 426)) < 1e-6)
        s.setContentOffset(.zero, animated: false)
        #expect(s.resizeIntent == nil)
    }

    // MARK: (B) the user's full-screen tree: several geometry updates per rotation in ONE run-loop turn

    /// Runs `body` as one run-loop turn of the state: SwiftUI delivers the updates synchronously, the end-of-turn hop
    /// runs afterwards (here: directly).
    func turn(_ s: ZTronScrollState, _ body: () -> Void) { body(); s.endOfTurn() }

    /// The intent of the drawn state (ZTronMapKit normalized centre + scale, via the library mapping).
    func drawnIntent(_ s: ZTronScrollState) -> ResizeIntent {
        let m = s.peek.metrics
        return ResizeMath.intent(offset: s.contentOffset, scale: s.zoomScale,
                                 in: .init(viewport: m.viewportSize, contentSize: m.contentSize, insets: m.adjustedContentInset),
                                 header: m.headerObscured, focus: .center, alignment: s.contentAlignment)
    }

    /// Settles a resize the way the demo's full-screen tree does: the probe reports the final size only (the
    /// transition never passes through the effect), the watch closes on the first tick ("never animated").
    func settle(_ s: ZTronScrollState, size: CGSize, t: inout TimeInterval) {
        s.probe.record(s.peek.targetOffset, s.peek.targetZoom, size: size)
        for _ in 0..<4 { t += 1; s.step(to: date(t)) }
        #expect(!s.peek.metrics.resize.isOpen)
    }

    /// One rotation of the user's tree as measured on iOS 27.0 (NavigationStack > GeometryReader > two-axis scroller,
    /// image as wide as the GeometryReader), all in ONE turn: the new orientation's safe area lands on the OLD size,
    /// the GeometryReader width loses the side inset and the content reflows (idle), then the size changes and the
    /// content reflows again (open).
    struct MeasuredRotation { var preSafe: EdgeInsets; var preContent: CGSize; var size: CGSize; var safe: EdgeInsets; var content: CGSize }
    static let user2ToLandscape = MeasuredRotation(
        preSafe: EdgeInsets(top: 0, leading: 62, bottom: 20, trailing: 0), preContent: CGSize(width: 340, height: 1020),
        size: CGSize(width: 874, height: 402), safe: EdgeInsets(top: 0, leading: 62, bottom: 20, trailing: 62), content: CGSize(width: 750, height: 2250))
    static let user2ToPortrait = MeasuredRotation(
        preSafe: EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0), preContent: CGSize(width: 874, height: 2622),
        size: CGSize(width: 402, height: 874), safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), content: CGSize(width: 402, height: 1206))

    func replay(_ s: ZTronScrollState, _ r: MeasuredRotation, t: inout TimeInterval) {
        let oldSize = s.peek.metrics.viewportSize
        turn(s) {
            s.setViewport(vp(oldSize.width, oldSize.height, r.preSafe))   // 'vp inset'
            s.setContentSize(r.preContent)                                 // 'cs idle'
            s.setViewport(vp(r.size.width, r.size.height, r.safe))        // 'vp size': the commit opens
            s.setContentSize(r.content)                                    // 'cs open'
        }
        #expect(s.peek.metrics.resize.isOpen)
        settle(s, size: r.size, t: &t)
    }

    /// The measured sequence with the real numbers, 4 rotations: odd rotations preserve the normalized centre of the
    /// drawn state (no clamp is needed in this tree), even rotations restore the offset and zoom exactly.
    @Test(arguments: OSPath.allCases) func userTree2MeasuredSequenceRestoresExactly(path: OSPath) {
        let s = makeState(path)
        s.scrollAxes = [.horizontal, .vertical]
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        s.setContentSize(CGSize(width: 402, height: 1206))
        s.setViewport(vp(402, 874, EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)))
        s.setZoomScale(2.2254, animated: false)
        let o0 = CGPoint(x: 67.38, y: 1293.49)
        s.setContentOffset(o0, animated: false)
        #expect(s.contentOffset == o0 && s.zoomScale == 2.2254)
        let n0 = drawnIntent(s).normalizedCenter
        #expect(abs(n0.x - 0.3) < 1e-3 && abs(n0.y - 0.65) < 1e-3, "the zoomed detail at (30 %, 65 %): \(n0)")
        var t: TimeInterval = 0
        for n in 1...4 {
            replay(s, n % 2 == 1 ? Self.user2ToLandscape : Self.user2ToPortrait, t: &t)
            #expect(s.resizeIntent != nil, "n=\(n)")
            #expect(s.zoomScale == 2.2254, "n=\(n) zoom \(s.zoomScale)")
            if n % 2 == 1 {
                let n1 = drawnIntent(s).normalizedCenter
                #expect(abs(n1.x - n0.x) < 1e-6 && abs(n1.y - n0.y) < 1e-6, "n=\(n) \(n1) vs \(n0)")
            } else {
                #expect(abs(s.contentOffset.x - o0.x) < 1e-6 && abs(s.contentOffset.y - o0.y) < 1e-6, "n=\(n) \(s.contentOffset)")
            }
        }
    }

    /// The safe area of the new orientation settles AFTER the size change, in the same turn: folded into the open commit
    /// (the resize stays open), the target realises the intent against the NEW insets.
    @Test(arguments: OSPath.allCases) func insetOnlyChangeWhileResizeOpenFoldsIntoTheCommit(path: OSPath) {
        let s = makeState(path)
        s.scrollAxes = [.horizontal, .vertical]
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let content = CGSize(width: 1500, height: 3000), l = CGSize(width: 852, height: 393)
        s.setContentSize(content)
        s.setViewport(vp(393, 852, EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)))
        s.setZoomScale(2, animated: false)
        s.setContentOffset(CGPoint(x: 400, y: 1200), animated: false)
        let n0 = drawnIntent(s)
        let newInsets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        var t: TimeInterval = 0
        turn(s) {
            s.setViewport(vp(l.width, l.height, EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)))
            #expect(s.peek.metrics.resize.isOpen)
            s.setViewport(vp(l.width, l.height, newInsets))
            #expect(s.peek.metrics.resize.isOpen, "the inset-only change did not close the resize")
            #expect(s.peek.metrics.resize.current.insets == newInsets && s.adjustedContentInset == newInsets)
        }
        settle(s, size: l, t: &t)
        let e = ResizeMath.realize(n0, viewport: l, content: content, insets: newInsets, header: 0, focus: .center,
                                   limits: s.zoomLimits, alignment: s.contentAlignment)
        #expect(abs(s.contentOffset.x - e.offset.x) < 1e-6 && abs(s.contentOffset.y - e.offset.y) < 1e-6, "\(s.contentOffset) vs \(e.offset)")
        #expect(s.zoomScale == 2 && e.scale == 2)
        // and it is NOT the offset of the first (incomplete) insets
        let e0 = ResizeMath.realize(n0, viewport: l, content: content, insets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0),
                                    header: 0, focus: .center, limits: s.zoomLimits, alignment: s.contentAlignment)
        #expect(abs(e0.offset.x - e.offset.x) > 1)
    }

    /// Leaves the post-resize settle window (D19: three run-loop turns after the close) the way the app does: the hops run.
    func leaveSettleWindow(_ s: ZTronScrollState) { for _ in 0..<3 { s.endOfTurn() } }

    /// A content change with no resize in the same turn, once the settle window is over, is an app action (the list
    /// grew): the offset is kept (UIKit `.sizeChanges` rule) and the sticky intent is dropped, so the next rotation
    /// preserves the centre of the CURRENT state, not the stale intent.
    @Test(arguments: OSPath.allCases) func idleChangeAfterTheWindowFollowsTheRuleAndDropsTheIntent(path: OSPath) {
        let s = makeState(path)
        s.scrollAxes = [.horizontal, .vertical]
        let p = CGSize(width: 393, height: 852), l = CGSize(width: 852, height: 393)
        s.setContentSize(CGSize(width: 1200, height: 3000))
        s.setViewport(vp(p.width, p.height))
        s.setContentOffset(CGPoint(x: 300, y: 1000), animated: false)
        var t: TimeInterval = 0
        turn(s) { s.setViewport(vp(l.width, l.height)) }
        settle(s, size: l, t: &t)
        leaveSettleWindow(s)
        #expect(s.resizeIntent != nil, "leaving the window alone keeps the intent")
        let stale = s.resizeIntent!
        let o1 = s.contentOffset
        let taller = CGSize(width: 1200, height: 4000)
        turn(s) { s.setContentSize(taller) }
        #expect(s.contentOffset == o1, "growing list keeps the offset")
        #expect(s.resizeIntent == nil, "the sticky intent is stale")
        let nCur = drawnIntent(s).normalizedCenter
        turn(s) { s.setViewport(vp(p.width, p.height)) }
        settle(s, size: p, t: &t)
        let n2 = drawnIntent(s).normalizedCenter
        #expect(abs(n2.x - nCur.x) < 1e-6 && abs(n2.y - nCur.y) < 1e-6, "\(n2) vs \(nCur)")
        #expect(abs(s.contentOffset.y - 1000) < 1e-6 && abs(s.contentOffset.x - 300) < 1e-6)
        let staleY = ResizeMath.realize(stale, viewport: p, content: taller, insets: EdgeInsets(), header: 0, focus: .center,
                                        limits: s.zoomLimits, alignment: s.contentAlignment).offset.y
        #expect(abs(s.contentOffset.y - staleY) > 100, "not the stale intent (\(staleY))")
    }

    // MARK: (C) the post-resize settle window (D19)

    /// Portrait, zoomed, off-centre; rotated to landscape with the first (incomplete) safe area. Returns the intent.
    func zoomedPortraitRotatedToLandscape(_ s: ZTronScrollState, insets: EdgeInsets, t: inout TimeInterval) -> ResizeIntent {
        s.scrollAxes = [.horizontal, .vertical]
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        s.setContentSize(CGSize(width: 1500, height: 3000))
        s.setViewport(vp(393, 852, EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)))
        s.setZoomScale(2, animated: false)
        s.setContentOffset(CGPoint(x: 400, y: 1200), animated: false)
        let n0 = drawnIntent(s)
        turn(s) { s.setViewport(vp(852, 393, insets)) }
        settle(s, size: CGSize(width: 852, height: 393), t: &t)
        #expect(s.resizeIntent == n0)
        return n0
    }

    /// Slow reflow (M5 section 9): the reflowed content size lands in the turn AFTER the resize closed. It is still the
    /// resize: the sticky intent is realised in the new geometry (criterion B) and kept, so rotating back restores the
    /// initial offset and zoom exactly (criterion A).
    @Test(arguments: OSPath.allCases) func lateReflowAfterCloseRestoresTheIntent(path: OSPath) {
        let s = makeState(path)
        var t: TimeInterval = 0
        let lInsets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        let n0 = zoomedPortraitRotatedToLandscape(s, insets: lInsets, t: &t)
        let o1 = s.contentOffset
        let reflowed = CGSize(width: 1500, height: 3200), l = CGSize(width: 852, height: 393)
        turn(s) { s.setContentSize(reflowed) }
        let e = ResizeMath.realize(n0, viewport: l, content: reflowed, insets: lInsets, header: 0, focus: .center,
                                   limits: s.zoomLimits, alignment: s.contentAlignment)
        #expect(abs(s.contentOffset.x - e.offset.x) < 1e-6 && abs(s.contentOffset.y - e.offset.y) < 1e-6, "\(s.contentOffset) vs \(e.offset)")
        #expect(s.zoomScale == 2 && e.scale == 2)
        #expect(abs(s.contentOffset.y - o1.y) > 50, "not the keep-offset rule (\(o1))")
        #expect(s.resizeIntent == n0, "the settle keeps the intent")
        turn(s) {
            s.setViewport(vp(393, 852, EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)))
            s.setContentSize(CGSize(width: 1500, height: 3000))
        }
        settle(s, size: CGSize(width: 393, height: 852), t: &t)
        #expect(abs(s.contentOffset.x - 400) < 1e-6 && abs(s.contentOffset.y - 1200) < 1e-6, "\(s.contentOffset)")
        #expect(abs(s.zoomScale - 2) < 1e-6)
    }

    /// The safe area of the new orientation settles in the turn AFTER the resize closed: realised against the new insets
    /// (not `insetChange`), the intent is kept and the way back is exact.
    @Test(arguments: OSPath.allCases) func lateInsetSettleAfterCloseRestoresTheIntent(path: OSPath) {
        let s = makeState(path)
        var t: TimeInterval = 0
        let first = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        let n0 = zoomedPortraitRotatedToLandscape(s, insets: first, t: &t)
        let o1 = s.contentOffset
        let newInsets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59), l = CGSize(width: 852, height: 393)
        turn(s) { s.setViewport(vp(l.width, l.height, newInsets)) }
        #expect(s.adjustedContentInset == newInsets)
        let e = ResizeMath.realize(n0, viewport: l, content: CGSize(width: 1500, height: 3000), insets: newInsets, header: 0,
                                   focus: .center, limits: s.zoomLimits, alignment: s.contentAlignment)
        #expect(abs(s.contentOffset.x - e.offset.x) < 1e-6 && abs(s.contentOffset.y - e.offset.y) < 1e-6, "\(s.contentOffset) vs \(e.offset)")
        #expect(s.zoomScale == 2 && e.scale == 2)
        #expect(abs(s.contentOffset.x - o1.x) > 1, "not the inset-change rule (\(o1))")
        #expect(s.resizeIntent == n0, "the settle keeps the intent")
        turn(s) { s.setViewport(vp(393, 852, EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))) }
        settle(s, size: CGSize(width: 393, height: 852), t: &t)
        #expect(abs(s.contentOffset.x - 400) < 1e-6 && abs(s.contentOffset.y - 1200) < 1e-6, "\(s.contentOffset)")
        #expect(abs(s.zoomScale - 2) < 1e-6)
    }

    /// A clock motion running into a rotation: the idle content change captured the turn origin one tick before the
    /// interrupt, so the intent is captured from the interrupted presentation (where the content stopped), in the
    /// origin's geometry.
    @Test(arguments: OSPath.allCases) func interruptedMotionCapturesTheIntentFromThePresentation(path: OSPath) {
        let s = makeState(path)
        s.scrollAxes = [.horizontal, .vertical]
        let content = CGSize(width: 1200, height: 3000), p = CGSize(width: 393, height: 852)
        s.setContentSize(content)
        s.setViewport(vp(p.width, p.height))
        var t = 100.0
        s.now = { t }
        s.setContentOffset(CGPoint(x: 300, y: 1000), animated: true)
        t += 0.02; s.step(to: date(t))
        let origin = ResizeCommit.Snapshot(viewport: p, contentSize: content, insets: EdgeInsets())
        var interruptedAt = CGPoint.zero
        turn(s) {
            s.setContentSize(CGSize(width: 1200, height: 3200))      // origin captured: presentation at this tick
            t += 0.02; s.step(to: date(t))                           // the motion moves on
            interruptedAt = s.peek.presentationOffset
            s.setViewport(vp(p.height, p.width))                      // interrupt + the resize opens
        }
        #expect(interruptedAt != .zero && interruptedAt.y > 0)
        let expected = ResizeMath.intent(offset: interruptedAt, scale: 1, in: origin, header: 0, focus: .center,
                                         alignment: s.contentAlignment)
        #expect(s.resizeIntent == expected, "\(String(describing: s.resizeIntent)) vs \(expected)")
    }
}
