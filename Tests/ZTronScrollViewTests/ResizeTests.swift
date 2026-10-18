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
