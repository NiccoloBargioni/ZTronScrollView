import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
@Suite(.serialized)
struct TransformTests {
    static func commit(viewport: CGSize, content: CGSize, insets: EdgeInsets = EdgeInsets()) -> ResizeCommit {
        var c = ResizeCommit()
        c.current = .init(viewport: viewport, contentSize: content, insets: insets)
        c.previous = c.current
        return c
    }

    static func effect(offset: CGPoint, scale: CGFloat, commit: ResizeCommit, probe: PresentationBox? = nil,
                       limits: ZoomLimits = ZoomLimits()) -> ContentTransform {
        ContentTransform(offset: offset, scale: scale, insets: commit.current.insets, commit: commit, limits: limits,
                         alignment: .center, paging: [], probe: probe)
    }

    @Test func effectMatrixMatchesFormula() {
        let box = PresentationBox()
        let c = Self.commit(viewport: CGSize(width: 100, height: 100), content: CGSize(width: 20, height: 30))
        let e = Self.effect(offset: CGPoint(x: 30, y: 70), scale: 2, commit: c, probe: box)
        let t = e.effectValue(size: c.current.viewport)
        // pad = (100 - 2*20) * 0.5 = 30 on x, (100 - 2*30) * 0.5 = 20 on y
        #expect(t.m11 == 2 && t.m22 == 2 && t.m12 == 0 && t.m21 == 0 && t.m31 == 30 - 30 && t.m32 == 20 - 70)
        let m = ContentTransform.matrix(offset: e.offset, scale: e.scale, pad: CGPoint(x: 30, y: 20))
        let p = CGPoint(x: 10, y: 10).applying(m)
        #expect(p == CGPoint(x: 2 * 10 + 30 - 30, y: 2 * 10 + 20 - 70))
        #expect(box.pending?.offset == CGPoint(x: 30, y: 70))
        #expect(box.pending?.zoom == 2)
        #expect(box.pending?.size == c.current.viewport)
        #expect(box.frames == 1)
    }

    /// User report 2026-10-19 (D21): the effect is drawn at a pixel-rounded size (288.0 for a 288.125 pt 16:9 box under
    /// a 62 pt bar). Within a pixel of the committed viewport, with the commit closed, the target is drawn as is: an
    /// overscrolled target (rubber band, bounce) stays overscrolled and the probe records the target. A real resize
    /// still takes the resize path and clamps.
    @Test func pixelRoundedSizeStillDrawsTheTargetUnclamped() {
        let box = PresentationBox()
        let c = Self.commit(viewport: CGSize(width: 402, height: 288.125), content: CGSize(width: 402, height: 1206),
                            insets: EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0))
        let target = CGPoint(x: -40, y: -90)              // 40 pt past the leading edge, 28 pt past the top
        let e = Self.effect(offset: target, scale: 1, commit: c, probe: box)
        #expect(e.isPlainFrame(size: CGSize(width: 402, height: 288)))
        let r = e.resolved(size: CGSize(width: 402, height: 288))
        #expect(r.offset == target && r.scale == 1)
        _ = e.effectValue(size: CGSize(width: 402, height: 288))
        #expect(box.pending?.offset == target)
        // Insets within a pixel of the committed ones are the same frame too (animatable rounding).
        var e2 = e
        e2.insets = EdgeInsets(top: 62.25, leading: 0, bottom: 0, trailing: 0)
        #expect(e2.isPlainFrame(size: CGSize(width: 402, height: 288.125)))
        // A real size change is a resize frame: realised from the intent and clamped (x bounds collapse to 0).
        #expect(!e.isPlainFrame(size: CGSize(width: 402, height: 500)))
        let r2 = e.resolved(size: CGSize(width: 402, height: 500))
        #expect(r2.offset.x == 0 && r2.offset.y >= -62)
        // An open commit never takes the plain path.
        var open = c; open.isOpen = true
        #expect(!Self.effect(offset: target, scale: 1, commit: open).isPlainFrame(size: CGSize(width: 402, height: 288.125)))
    }

    @Test func pixelSnapOnlyAtRestAt2xAnd3x() {
        #expect(ContentGeometry.snap(10.3, scale: 2) == 10.5)
        #expect(ContentGeometry.snap(10.4, scale: 3) == 10.333333333333334)
        #expect(ContentGeometry.snap(10.3, scale: 1) == 10)
    }

    @Test func scaleNeverSnapped() {
        let c = Self.commit(viewport: CGSize(width: 100, height: 100), content: CGSize(width: 500, height: 500))
        let e = Self.effect(offset: .zero, scale: 1.37, commit: c)
        #expect(e.effectValue(size: c.current.viewport).m11 == 1.37)
    }

    @Test func animatableDataRoundTrip() {
        let c = Self.commit(viewport: CGSize(width: 100, height: 100), content: CGSize(width: 500, height: 500))
        var e = Self.effect(offset: CGPoint(x: 1, y: 2), scale: 3, commit: c)
        e.insets = EdgeInsets(top: 4, leading: 5, bottom: 6, trailing: 7)
        let d = e.animatableData
        e.offset = .zero; e.scale = 1; e.insets = EdgeInsets()
        e.animatableData = d
        #expect(e.offset == CGPoint(x: 1, y: 2) && e.scale == 3 && e.insets == EdgeInsets(top: 4, leading: 5, bottom: 6, trailing: 7))
        var half = d
        half.scale(by: 0.5)
        #expect(half.s == 1.5 && (d - half).s == 1.5 && d.magnitudeSquared > half.magnitudeSquared)
    }

    @Test func alignmentPaddingOnlyWhenContentFits() {
        let v = CGSize(width: 400, height: 800)
        func pad(_ c: CGSize, _ a: UnitPoint) -> CGPoint {
            ResizeMath.geometry(viewport: v, content: c, insets: EdgeInsets(), alignment: a).alignmentPadding(at: 1)
        }
        #expect(pad(CGSize(width: 500, height: 2000), .center) == .zero)
        #expect(pad(CGSize(width: 200, height: 2000), .center) == CGPoint(x: 100, y: 0))
        #expect(pad(CGSize(width: 200, height: 400), .topLeading) == .zero)
    }

    @Test(arguments: OSPath.allCases) func resizePreservesVisibleCenter(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 844), safeArea: EdgeInsets()))
        s.track(offset: CGPoint(x: 0, y: 500), zoom: 1)
        let before = CGPoint(x: s.contentOffset.x + 195, y: s.contentOffset.y + 422)
        s.setViewport(ViewportMetrics(size: CGSize(width: 844, height: 390), safeArea: EdgeInsets()))
        s.closeResize()
        // x: 390 pt of content in an 844 pt viewport cannot be centered (no zoom): the offset clamps to 0.
        #expect(s.contentOffset.x == 0 && s.contentOffset.y + 195 == before.y)
        #expect(s.peek.targetOffset == s.contentOffset)
        // zoomed (a scale outside the zoom range is clamped on resize, so the range must allow it)
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        s.track(offset: CGPoint(x: 100, y: 800), zoom: 2)
        // zoom is enabled, so content centers: 780 pt of content in 844 pt leaves a 32 pt pad on the left
        let u = CGPoint(x: (100 + 422 - 32) / 2, y: (800 + 195) / 2.0)
        s.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 844), safeArea: EdgeInsets()))
        s.closeResize()
        #expect(s.zoomScale == 2)
        #expect(CGPoint(x: (s.contentOffset.x + 195) / 2, y: (s.contentOffset.y + 422) / 2) == u)
    }

    @Test(arguments: OSPath.allCases) func resizeStopsMotionAtPresentation(path: OSPath) {
        let s = makeState(path)
        s.setViewport(ViewportMetrics(size: CGSize(width: 100, height: 100), safeArea: EdgeInsets()))
        s.setContentOffset(CGPoint(x: 0, y: 500), animated: true)
        #expect(s.phase == .animating)
        s.setViewport(ViewportMetrics(size: CGSize(width: 200, height: 100), safeArea: EdgeInsets()))
        #expect(s.phase == .idle)
        #expect(s.isClockRunning)   // the resize watch
        s.closeResize()
        #expect(!s.isClockRunning)
    }

    /// D79: after a drawn catch the effect draws its model copy (`pinned(_:)`: the host's values) instead of SwiftUI's
    /// interpolation, until that interpolation reaches the model within 0.01 pt (zoom 1e-5): that ends its latch for the
    /// catch, and later interpolations are drawn. No pin: the effect itself.
    @Test func aPinnedEffectDrawsItsModelUntilItsInterpolationReachesIt() {
        let box = PresentationBox()
        let c = Self.commit(viewport: CGSize(width: 390, height: 800), content: CGSize(width: 390, height: 3000))
        let model = Self.effect(offset: CGPoint(x: 0, y: -40), scale: 1, commit: c, probe: box)
        #expect(model.pinned(nil).pin == nil)
        let atModel = model.effectValue(size: c.current.viewport)
        let pin = CatchPin()
        var e = model.pinned(CatchPin.Ref(seq: 1, pin: pin))
        #expect(e.pinModel == model.animatableData)
        e.animatableData.oy = -75                                     // the residual SwiftUI 17.x keeps through the catch
        #expect(e.effectValue(size: c.current.viewport) == atModel, "drawn at the model")
        #expect(box.pending?.offset == CGPoint(x: 0, y: -40), "the probe records what is drawn")
        #expect(e.effectValue(size: c.current.viewport) == atModel, "still")
        e.animatableData.s = 1 + 2e-5
        e.animatableData.oy = -40
        #expect(e.effectValue(size: c.current.viewport) == atModel, "the zoom has not reached the model yet")
        e.animatableData.s = 1 + 5e-6
        e.animatableData.oy = -40.005
        _ = e.effectValue(size: c.current.viewport)
        #expect(box.pending?.offset == CGPoint(x: 0, y: -40.005), "converged: the interpolation is drawn")
        e.animatableData.oy = -60
        _ = e.effectValue(size: c.current.viewport)
        #expect(box.pending?.offset == CGPoint(x: 0, y: -60), "the latch ended for this catch: a later animation is drawn")
        var next = model.pinned(CatchPin.Ref(seq: 2, pin: pin))
        next.animatableData.oy = -60
        #expect(next.effectValue(size: c.current.viewport) == atModel, "a new catch pins again")
        var other = model.pinned(CatchPin.Ref(seq: 1, pin: CatchPin()))
        other.animatableData.oy = -60
        #expect(other.effectValue(size: c.current.viewport) == atModel, "latches are per view (pin)")
    }

    /// D79: the per-key latches and `resolve`: each key ends on its own convergence.
    @Test func eachKeyEndsOnItsOwnConvergence() {
        let ref = CatchPin.Ref(seq: 4, pin: CatchPin())
        #expect(ref.resolve(.content, interpolated: -75, model: -40) == -40)
        #expect(ref.resolve(.refresh(.top), interpolated: -40.009, model: -40) == -40.009, "within 0.01: converged")
        #expect(ref.resolve(.refresh(.top), interpolated: -75, model: -40) == -75, "ended for this catch")
        #expect(ref.resolve(.content, interpolated: -60, model: -40) == -40, "the content's latch still holds")
        #expect(ref.resolve(.content, interpolated: -40, model: -40) == -40)
        #expect(ref.resolve(.content, interpolated: -60, model: -40) == -60, "and now ended too")
        #expect(ref.resolve(.headerSlot, interpolated: 12, model: 0) == 0, "every key latches on its own")
    }
}
