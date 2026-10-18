import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class ZoomDelegate: ZTronScrollViewDelegate {
    var log: [String] = []
    func scrollViewDidScroll(_ s: ZTronScrollState) { log.append("didScroll") }
    func scrollViewDidZoom(_ s: ZTronScrollState) { log.append("didZoom") }
    func scrollViewWillBeginZooming(_ s: ZTronScrollState) { log.append("willBeginZooming") }
    func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale scale: CGFloat) { log.append("didEndZooming(\(scale))") }
    func scrollViewWillBeginDragging(_ s: ZTronScrollState) { log.append("willBeginDragging") }
    func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate d: Bool) { log.append("didEndDragging(\(d))") }
    func scrollViewWillBeginDecelerating(_ s: ZTronScrollState) { log.append("willBeginDecelerating") }
    func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState) { log.append("didEndScrollingAnimation") }
}

@MainActor
@Suite(.serialized)
struct ZoomStateTests {
    struct Rig {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ZoomDelegate
    }

    func make(_ path: OSPath, limits: ZoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(2)),
              viewport: CGSize = CGSize(width: 100, height: 200), content: CGSize = CGSize(width: 300, height: 900),
              offset: CGPoint = CGPoint(x: 100, y: 300)) -> Rig {
        let s = makeState(path)
        let d = ZoomDelegate()
        s.delegate = d
        s.now = { 100 }
        s.zoomLimits = limits
        s.setMetrics(ScrollMetrics(viewportSize: viewport, contentSize: content, displayScale: 2))
        s.track(offset: offset, zoom: 1)
        d.log.removeAll()
        let c = withOSPath(path) { PanCoordinator(state: s, axes: [.horizontal, .vertical]) }
        return Rig(state: s, coord: c, delegate: d)
    }
    func step(_ s: ZTronScrollState, _ t: TimeInterval) { s.step(to: Date(timeIntervalSinceReferenceDate: t)) }
    func viewport(_ w: CGFloat, _ h: CGFloat) -> ViewportMetrics { ViewportMetrics(size: CGSize(width: w, height: h), safeArea: EdgeInsets()) }

    // MARK: 2. limits

    @Test(arguments: OSPath.allCases) func fitAndFillResolveOnResize(path: OSPath) {
        let r = make(path, limits: ZoomLimits(min: .fit, max: .fill), viewport: CGSize(width: 400, height: 800),
                     content: CGSize(width: 400, height: 800), offset: .zero)
        #expect(r.state.minimumZoomScale == 1 && r.state.maximumZoomScale == 1 && !r.state.isZoomEnabled)
        r.state.setViewport(viewport(800, 400))      // portrait -> landscape
        #expect(r.state.minimumZoomScale == 0.5 && r.state.maximumZoomScale == 2 && r.state.isZoomEnabled)
        r.state.setViewport(viewport(200, 400))
        #expect(r.state.minimumZoomScale == 0.5 && r.state.maximumZoomScale == 0.5)
    }

    @Test(arguments: OSPath.allCases) func defaultIsDisabledAndMinAboveMaxNormalizes(path: OSPath) {
        let s = makeState(path)
        #expect(!s.isZoomEnabled && s.minimumZoomScale == 1 && s.maximumZoomScale == 1)
        s.zoomLimits = ZoomLimits(min: .absolute(3), max: .absolute(2))
        #expect(s.minimumZoomScale == 3 && s.maximumZoomScale == 3 && !s.isZoomEnabled)
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(5))
        #expect(s.isZoomEnabled && s.contentAlignment == .center)
    }

    @Test(arguments: OSPath.allCases) func outOfRangeScaleClampsKeepingTheVisibleCenter(path: OSPath) {
        let r = make(path, limits: ZoomLimits(min: .absolute(1), max: .absolute(4)),
                     content: CGSize(width: 1000, height: 1000), offset: CGPoint(x: 400, y: 600))
        r.state.track(offset: CGPoint(x: 400, y: 600), zoom: 3)
        r.delegate.log.removeAll()
        let center = CGPoint(x: (400 + 50) / 3.0, y: (600 + 100) / 3.0)
        r.state.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(2))
        #expect(r.state.zoomScale == 2)
        let o = r.state.contentOffset
        #expect(abs((o.x + 50) / 2 - center.x) < 1e-9 && abs((o.y + 100) / 2 - center.y) < 1e-9)
        #expect(r.delegate.log == ["didZoom", "didScroll"])
    }

    // MARK: 8. programmatic

    @Test(arguments: OSPath.allCases) func setZoomScaleAnchorsAtTheVisibleCenterWithPadding(path: OSPath) {
        // Content smaller than the viewport at 1x: the pad centers it, so the old pad-less formula is wrong here.
        let r = make(path, limits: ZoomLimits(min: .absolute(0.5), max: .absolute(4)),
                     viewport: CGSize(width: 200, height: 400), content: CGSize(width: 100, height: 100), offset: .zero)
        r.state.setZoomScale(2, animated: false)
        #expect(r.state.zoomScale == 2 && r.state.contentOffset == .zero)      // 200x200 content: pad y 100, centered
        r.state.setZoomScale(10, animated: false)
        #expect(r.state.zoomScale == 4)
        r.state.setZoomScale(0.1, animated: false)
        #expect(r.state.zoomScale == 0.5)
        // Large content: center point kept, and the result stays in bounds.
        let b = make(path, limits: ZoomLimits(min: .absolute(1), max: .absolute(4)), viewport: CGSize(width: 200, height: 400),
                     content: CGSize(width: 1000, height: 1000), offset: CGPoint(x: 100, y: 100))
        b.state.setZoomScale(2, animated: false)
        #expect(b.state.contentOffset == CGPoint(x: 300, y: 400))
    }

    @Test(arguments: OSPath.allCases) func zoomToRectFitsAndCenters(path: OSPath) {
        let r = make(path, limits: ZoomLimits(min: .absolute(1), max: .absolute(4)), viewport: CGSize(width: 200, height: 400),
                     content: CGSize(width: 1000, height: 1000), offset: CGPoint(x: 100, y: 100))
        r.state.zoom(to: CGRect(x: 100, y: 100, width: 100, height: 200), animated: false)
        #expect(r.state.zoomScale == 2 && r.state.contentOffset == CGPoint(x: 200, y: 200))
        r.state.zoom(to: CGRect(x: 0, y: 0, width: 10, height: 10), animated: false)
        #expect(r.state.zoomScale == 4)
        // Animated: ends exactly on the solver result, with didEndScrollingAnimation and no didEndZooming.
        r.delegate.log.removeAll()
        r.state.zoom(to: CGRect(x: 100, y: 100, width: 100, height: 200), animated: true)
        #expect(r.state.isZoomAnimating)
        var t = 100.0
        while r.state.isClockRunning && t < 110 { t += 1.0 / 60; step(r.state, t) }
        #expect(r.state.zoomScale == 2 && r.state.contentOffset == CGPoint(x: 200, y: 200) && r.state.phase == .idle)
        #expect(r.delegate.log.last == "didEndScrollingAnimation" && !r.delegate.log.contains { $0.hasPrefix("didEndZooming") })
    }

    // MARK: 4/6. pinch through the coordinator

    /// Pinch at the viewport center up to `m`, 3 frames, returning the last centroid.
    func pinch(_ r: Rig, to magnifications: [CGFloat], at c: CGPoint = CGPoint(x: 50, y: 100), t0: TimeInterval = 100) {
        r.coord.handlePinch(.began(centroid: c, time: t0))
        for (i, m) in magnifications.enumerated() {
            let t = t0 + 0.016 * Double(i + 1)
            r.coord.handlePinch(.changed(magnification: m, centroid: c, time: t))
            step(r.state, t)
        }
    }

    @Test(arguments: OSPath.allCases) func bounceBackAnchorsAndSettlesOnTheLimit(path: OSPath) {
        let r = make(path, content: CGSize(width: 2000, height: 4000), offset: CGPoint(x: 500, y: 1000))
        let c = CGPoint(x: 50, y: 100)
        let u = ZoomSolver.contentPoint(under: c, offset: r.state.contentOffset, scale: 1, geometry: r.state.makeZoomGeometry())
        pinch(r, to: [1.2, 1.6, 2.0, 3.2])
        #expect(r.state.isZooming && !r.state.isZoomBouncing && r.state.zoomScale > 2 && r.state.zoomScale < 3.2)
        r.coord.handlePinch(.ended(time: 100.1))
        #expect(r.state.isZoomBouncing && r.state.isZooming && r.state.phase == .decelerating)
        #expect(!r.delegate.log.contains { $0.hasPrefix("didEndZooming") }, "end only after the bounce")
        var t = 100.1
        var last = r.state.zoomScale
        while r.state.isClockRunning && t < 110 {
            t += 1.0 / 60; step(r.state, t)
            let z = r.state.zoomScale
            #expect(z <= last + 1e-12, "no overshoot")
            last = z
            let p = ZoomSolver.contentPoint(under: c, offset: r.state.contentOffset, scale: z, geometry: r.state.makeZoomGeometry())
            #expect(hypot(p.x - u.x, p.y - u.y) < 1e-6)
        }
        #expect(r.state.zoomScale == 2 && !r.state.isZoomBouncing && !r.state.isZooming && r.state.phase == .idle)
        let b = r.state.makeZoomGeometry().bounds(at: 2)
        #expect(b.x.clamped(r.state.contentOffset.x) == r.state.contentOffset.x && b.y.clamped(r.state.contentOffset.y) == r.state.contentOffset.y)
        #expect(r.delegate.log.last == "didEndZooming(2.0)")
    }

    @Test(arguments: OSPath.allCases) func delegateOrderAndCoalescing(path: OSPath) {
        let r = make(path, content: CGSize(width: 2000, height: 4000), offset: CGPoint(x: 500, y: 1000))
        r.coord.handlePinch(.began(centroid: CGPoint(x: 50, y: 100), time: 100))
        r.coord.handlePinch(.changed(magnification: 1.1, centroid: CGPoint(x: 50, y: 100), time: 100.01))
        r.coord.handlePinch(.changed(magnification: 1.2, centroid: CGPoint(x: 50, y: 100), time: 100.02))
        #expect(r.delegate.log == ["willBeginZooming"], "didZoom/didScroll wait for the tick")
        step(r.state, 100.03)
        #expect(r.delegate.log == ["willBeginZooming", "didZoom", "didScroll"])
        r.coord.handlePinch(.changed(magnification: 1.5, centroid: CGPoint(x: 50, y: 100), time: 100.04))
        r.coord.handlePinch(.ended(time: 100.05))
        #expect(r.delegate.log.suffix(1) == ["didEndZooming(1.5)"] || r.delegate.log.suffix(1) == ["didScroll"])
        #expect(!r.state.isZooming)
        // Frames after the end: no stray callbacks.
        let n = r.delegate.log.count
        step(r.state, 100.06)
        #expect(r.delegate.log.suffix(r.delegate.log.count - n).allSatisfy { $0 == "didZoom" || $0 == "didScroll" })
        // One tick never produces two of the same callback.
        #expect(r.delegate.log.filter { $0 == "didZoom" }.count <= 2)
    }

    @Test(arguments: OSPath.allCases) func programmaticZoomFiresNoDidEndZooming(path: OSPath) {
        let r = make(path)
        r.state.setZoomScale(2, animated: false)
        #expect(r.delegate.log == ["didZoom", "didScroll"])
        r.state.setZoomScale(1, animated: true)
        var t = 100.0
        while r.state.isClockRunning && t < 110 { t += 1.0 / 60; step(r.state, t) }
        #expect(!r.delegate.log.contains { $0.hasPrefix("didEndZooming") || $0 == "willBeginZooming" })
        #expect(r.delegate.log.last == "didEndScrollingAnimation")
    }

    @Test(arguments: OSPath.allCases) func combinedReleaseWithABounceEndsDraggingWithoutDeceleration(path: OSPath) {
        let r = make(path, content: CGSize(width: 2000, height: 4000), offset: CGPoint(x: 500, y: 1000))
        let down = CGPoint(x: 50, y: 100)
        r.coord.handle(.touchDown(location: down, time: 100, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -20), startLocation: down, time: 100.02))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -30), startLocation: down, time: 100.03))
        pinch(r, to: [1.5, 3.2], t0: 100.04)
        let before = r.state.contentOffset
        // Pan updates while pinching are dropped: the pinch owns the offset.
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -60), startLocation: down, time: 100.09))
        #expect(r.state.contentOffset == before)
        r.coord.handlePinch(.ended(time: 100.1))
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -60), time: 100.1, fallbackVelocity: nil))
        #expect(r.delegate.log.contains("didEndDragging(false)") && !r.delegate.log.contains("willBeginDecelerating"))
        #expect(r.state.isZoomBouncing)
    }

    // MARK: 5. one-finger lift

    @Test(arguments: OSPath.allCases) func oneFingerLiftRebasesThePan(path: OSPath) {
        let r = make(path, content: CGSize(width: 2000, height: 4000), offset: CGPoint(x: 500, y: 1000))
        let down = CGPoint(x: 50, y: 100)
        r.coord.handle(.touchDown(location: down, time: 100, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -20), startLocation: down, time: 100.02))
        let drag = CGSize(width: 4, height: -30)
        r.coord.handle(.dragChanged(translation: drag, startLocation: down, time: 100.03))
        pinch(r, to: [1.2, 1.5], t0: 100.04)
        let presentation = r.state.peek.presentationOffset
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 60, y: 100), time: 100.1))
        #expect(!r.coord.isPinching && !r.state.isZooming && r.state.zoomScale == 1.5)
        // The next sample with the unchanged translation does not jump.
        r.coord.handle(.dragChanged(translation: drag, startLocation: down, time: 100.11))
        #expect(r.coord.effectsLog.last == .setOffset(presentation))
        #expect(r.state.peek.presentationOffset == presentation)
        // And it keeps following: 10 pt more finger movement moves the content 10 pt.
        r.coord.handle(.dragChanged(translation: CGSize(width: 4, height: -40), startLocation: down, time: 100.12))
        #expect(abs(r.state.peek.presentationOffset.y - (presentation.y + 10)) < 1e-9)
    }

    @Test(arguments: OSPath.allCases) func deadDragGestureContinuesThroughSynthesizedPan(path: OSPath) {
        let r = make(path, content: CGSize(width: 2000, height: 4000), offset: CGPoint(x: 500, y: 1000))
        pinch(r, to: [1.2, 1.5])
        let presentation = r.state.peek.presentationOffset
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 60, y: 100), time: 100.1))
        #expect(r.state.isTracking)
        #expect(r.state.peek.presentationOffset == presentation, "starting the pan must not jump")
        r.coord.synthesizePan(location: CGPoint(x: 60, y: 80), time: 100.12)
        r.coord.synthesizePan(location: CGPoint(x: 50, y: 70), time: 100.14)
        let o = r.state.peek.presentationOffset
        #expect(abs(o.x - (presentation.x + 10)) < 1e-9 && abs(o.y - (presentation.y + 30)) < 1e-9)
    }

    // MARK: 7. reader tiers

    @Test(arguments: OSPath.allCases) func readersTrackOnlyTheirChannel(path: OSPath) {
        let s = makeState(path)
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        let zoomOnly = Counter(), offsetOnly = Counter()
        let w1 = host(ZTronScrollReader(s, of: { $0.zoomScale }) { _ -> Color in zoomOnly.runs += 1; return Color.clear })
        let w2 = host(ZTronScrollReader(s, of: { $0.contentOffset }) { _ -> Color in offsetOnly.runs += 1; return Color.clear })
        let zBase = zoomOnly.runs, oBase = offsetOnly.runs
        for i in 1...100 { s.writeDragOffset(CGPoint(x: 0, y: CGFloat(i))); step(s, 100 + Double(i) / 100) }
        pump(0.1)
        #expect(zoomOnly.runs == zBase)
        #expect(offsetOnly.runs > oBase)
        let o2 = offsetOnly.runs
        s.writePinch(scale: 1.5, offset: s.peek.presentationOffset)     // scale-only frame: the offset channel stays quiet
        pump(0.1)
        #expect(offsetOnly.runs == o2 && zoomOnly.runs == zBase + 1)
        _ = (w1, w2)
    }
}
