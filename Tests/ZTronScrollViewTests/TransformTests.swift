import SwiftUI
import Testing
@testable import ZTronScrollView

@MainActor
@Suite(.serialized)
struct TransformTests {
    @Test func effectMatrixMatchesFormula() {
        let box = PresentationBox()
        let e = ContentTransform(offset: CGPoint(x: 30, y: 70), scale: 2, pad: CGSize(width: 5, height: 9), probe: box)
        let t = e.effectValue(size: .zero)
        let m = ContentTransform.matrix(offset: e.offset, scale: e.scale, pad: e.pad)
        #expect(t.m11 == 2 && t.m22 == 2 && t.m12 == 0 && t.m21 == 0 && t.m31 == 5 - 30 && t.m32 == 9 - 70)
        let p = CGPoint(x: 10, y: 10).applying(m)
        #expect(p == CGPoint(x: 2 * 10 + 5 - 30, y: 2 * 10 + 9 - 70))
        #expect(box.pending?.offset == CGPoint(x: 30, y: 70))
        #expect(box.pending?.zoom == 2)
        #expect(box.frames == 1)
    }

    @Test func pixelSnapOnlyAtRestAt2xAnd3x() {
        #expect(ContentGeometry.snap(10.3, scale: 2) == 10.5)
        #expect(ContentGeometry.snap(10.4, scale: 3) == 10.333333333333334)
        #expect(ContentGeometry.snap(10.3, scale: 1) == 10)
    }

    @Test func scaleNeverSnapped() {
        let e = ContentTransform(offset: .zero, scale: 1.37, pad: .zero, probe: nil)
        #expect(e.effectValue(size: .zero).m11 == 1.37)
    }

    @Test func animatableDataRoundTrip() {
        var e = ContentTransform(offset: CGPoint(x: 1, y: 2), scale: 3, pad: CGSize(width: 4, height: 5), probe: nil)
        let d = e.animatableData
        e.offset = .zero; e.scale = 1; e.pad = .zero
        e.animatableData = d
        #expect(e.offset == CGPoint(x: 1, y: 2) && e.scale == 3 && e.pad == CGSize(width: 4, height: 5))
    }

    @Test func alignmentPaddingOnlyWhenContentFits() {
        let v = CGSize(width: 400, height: 800)
        #expect(ContentGeometry.pad(viewport: v, content: CGSize(width: 500, height: 2000), scale: 1, alignment: .center) == .zero)
        #expect(ContentGeometry.pad(viewport: v, content: CGSize(width: 200, height: 2000), scale: 1, alignment: .center)
                == CGSize(width: 100, height: 0))
        #expect(ContentGeometry.pad(viewport: v, content: CGSize(width: 200, height: 400), scale: 1, alignment: .topLeading) == .zero)
        #expect(ContentGeometry.pad(viewport: v, content: .zero, scale: 1, alignment: .center) == .zero)
    }

    @Test(arguments: OSPath.allCases) func resizePreservesVisibleCenter(path: OSPath) {
        let s = makeState(path)
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 844), safeArea: EdgeInsets()))
        s.track(offset: CGPoint(x: 0, y: 500), zoom: 1)
        let before = CGPoint(x: s.contentOffset.x + 195, y: s.contentOffset.y + 422)
        s.setViewport(ViewportMetrics(size: CGSize(width: 844, height: 390), safeArea: EdgeInsets()))
        #expect(CGPoint(x: s.contentOffset.x + 422, y: s.contentOffset.y + 195) == before)
        #expect(s.peek.targetOffset == s.contentOffset)
        // zoomed
        s.track(offset: CGPoint(x: 100, y: 800), zoom: 2)
        let u = CGPoint(x: (100 + 422) / 2, y: (800 + 195) / 2.0)
        s.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 844), safeArea: EdgeInsets()))
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
        #expect(!s.isClockRunning)
    }
}
