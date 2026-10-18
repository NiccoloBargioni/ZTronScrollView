import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class ReleaseDelegate: ZTronScrollViewDelegate {
    var log: [String] = []
    var retarget: CGPoint?
    var seenVelocity: CGPoint?
    var seenTarget: CGPoint?
    func scrollViewDidScroll(_ s: ZTronScrollState) { log.append("didScroll") }
    func scrollViewWillBeginDragging(_ s: ZTronScrollState) { log.append("willBeginDragging") }
    func scrollViewWillEndDragging(_ s: ZTronScrollState, withVelocity v: CGPoint, targetContentOffset: inout CGPoint) {
        log.append("willEndDragging"); seenVelocity = v; seenTarget = targetContentOffset
        if let retarget { targetContentOffset = retarget }
    }
    func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate d: Bool) { log.append("didEndDragging(\(d))") }
    func scrollViewWillBeginDecelerating(_ s: ZTronScrollState) { log.append("willBeginDecelerating") }
    func scrollViewDidEndDecelerating(_ s: ZTronScrollState) { log.append("didEndDecelerating") }
    func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState) { log.append("didEndScrollingAnimation") }
}

@MainActor
@Suite(.serialized)
struct ReleasePipelineTests {
    static let env = PanSessionTests.env()
    func make(_ path: OSPath, at offset: CGPoint = CGPoint(x: 0, y: 300)) -> (ZTronScrollState, ReleaseDelegate) {
        let s = makeState(path)
        let d = ReleaseDelegate()
        s.delegate = d
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
        s.track(offset: offset, zoom: 1)
        s.beginTracking(); s.beginDragging()
        d.log.removeAll()
        return (s, d)
    }
    /// Finger moving up at `v` pt/s (content offset increases) for 120 ms ending at `lift`.
    func tracker(vy: CGFloat, lift: TimeInterval = 100) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = lift - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: 0, y: -vy * CGFloat(time - (lift - 0.12))), at: time)
        }
        return t
    }
    func request(_ origin: CGPoint, lift: TimeInterval = 100, edit: (inout ReleaseRequest) -> Void = { _ in }) -> ReleaseRequest {
        var r = ReleaseRequest(origin: origin, dragStart: origin, liftTime: lift, fallbackVelocity: nil)
        edit(&r)
        return r
    }
    func run(_ s: ZTronScrollState, to end: TimeInterval = 110, dt: TimeInterval = 1.0 / 60) {
        var t = 100.0
        while t < end && s.isClockRunning {
            t += dt
            s.step(to: Date(timeIntervalSinceReferenceDate: t))
        }
    }

    @Test func velocityTrackerVsFallback() {
        var tr = VelocityTracker()
        #expect(ReleasePipeline.velocity(tracker: tr, liftTime: 1, fallback: 250) == 250)
        #expect(ReleasePipeline.velocity(tracker: tr, liftTime: 1, fallback: nil) == 0)
        for i in 0...6 { tr.add(position: CGFloat(i) * 10, at: 0.9 + Double(i) * 0.015) }
        let v = ReleasePipeline.velocity(tracker: tr, liftTime: 0.99, fallback: 250)
        #expect(abs(v - 666) < 40)
        // rested 80 ms before the lift -> ~0
        #expect(ReleasePipeline.velocity(tracker: tr, liftTime: 1.2, fallback: 250) == 0)
    }

    @Test func flingAccelerationCapsAndNeedsQuickCatch() {
        let f = FlingAcceleration()
        #expect(ReleasePipeline.accelerated(1000, caughtVelocity: 800, caughtAt: 99.9, liftTime: 100, f) == 1800)
        #expect(ReleasePipeline.accelerated(1000, caughtVelocity: 800, caughtAt: 99.0, liftTime: 100, f) == 1000)   // slow touch
        #expect(ReleasePipeline.accelerated(1000, caughtVelocity: -800, caughtAt: 99.9, liftTime: 100, f) == 1000)  // opposite
        #expect(ReleasePipeline.accelerated(11_000, caughtVelocity: 5000, caughtAt: 99.95, liftTime: 100, f) == 12_000)
        #expect(ReleasePipeline.accelerated(1000, caughtVelocity: 800, caughtAt: nil, liftTime: 100, f) == 1000)
    }

    @Test(arguments: OSPath.allCases) func inBoundsDecayRestsAtProjectedPointSnapped(path: OSPath) {
        let (s, d) = make(path)
        let tr = tracker(vy: 1000)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tr, env: Self.env, settings: ReleaseSettings())
        #expect(my.willDecelerate && s.phase == .decelerating && s.isDecelerating && !s.isTracking && !s.isDragging)
        #expect(d.log == ["willEndDragging", "didEndDragging(true)", "willBeginDecelerating"])
        #expect(abs((d.seenVelocity?.y ?? 0) - 1.0) < 0.1)                     // pt/ms
        run(s)
        let rest = my.endPosition
        #expect(s.phase == .idle && !s.isDecelerating && !s.isClockRunning)
        #expect(abs(s.peek.presentationOffset.y - rest) <= 0.25)
        let snapped = s.peek.presentationOffset.y * 2
        #expect(abs(snapped - snapped.rounded()) < 1e-9)                       // pixel snap, scale 2
        #expect(d.log.last == "didEndDecelerating")
    }

    /// Regression (iOS 27): gesture event times use another time base than the state clock (uptime vs Date).
    /// The deceleration must start on the state clock, not settle on its first tick.
    @Test(arguments: OSPath.allCases) func liftTimeInAnotherTimeBaseStillDecelerates(path: OSPath) {
        let (s, d) = make(path)
        let tr = tracker(vy: 1000, lift: 5)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300), lift: 5), tracker: tr, env: Self.env, settings: ReleaseSettings())
        #expect(abs((d.seenVelocity?.y ?? 0) - 1.0) < 0.1)
        s.step(to: Date(timeIntervalSinceReferenceDate: 100 + 1.0 / 60))
        #expect(s.phase == .decelerating && s.isDecelerating)
        #expect(s.peek.presentationOffset.y > 300 && s.peek.presentationOffset.y < 320)
        run(s)
        #expect(s.phase == .idle && abs(s.peek.presentationOffset.y - my.endPosition) <= 0.25)
    }

    @Test(arguments: OSPath.allCases) func delegateRetargetLandsExactly(path: OSPath) {
        let (s, d) = make(path)
        d.retarget = CGPoint(x: 0, y: 420)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(abs(my.endPosition - 420) < 1e-6)
        run(s)
        #expect(s.peek.presentationOffset.y == 420)
    }

    @Test(arguments: OSPath.allCases) func retargetAgainstVelocityFallsBackToSpring(path: OSPath) {
        let (s, d) = make(path)
        d.retarget = CGPoint(x: 0, y: 200)       // moving up (+) but target below
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        guard case .spring = my else { Issue.record("expected spring, got \(my)"); return }
        #expect(my.endPosition == 200)
        run(s, to: 112)
        #expect(s.peek.presentationOffset.y == 200)
    }

    @Test(arguments: OSPath.allCases) func outOfBoundsReleaseSpringsBackAndDecelerates(path: OSPath) {
        let (s, d) = make(path, at: CGPoint(x: 0, y: -40))
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: -40)), tracker: PointVelocityTracker(), env: Self.env, settings: ReleaseSettings())
        guard case .spring = my else { Issue.record("expected spring"); return }
        #expect(d.log.contains("didEndDragging(true)") && s.phase == .decelerating)
        run(s, to: 115)
        #expect(s.peek.presentationOffset.y == 0 && s.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func decayCrossingEdgeHandsOffToSpring(path: OSPath) {
        let (s, _) = make(path, at: CGPoint(x: 0, y: 650))
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 650)), tracker: tracker(vy: 3000), env: Self.env, settings: ReleaseSettings())
        guard case let .decay(_, _, handoff) = my, let h = handoff else { Issue.record("expected hand-off, got \(my)"); return }
        #expect(h.edge == 700 && h.bounces)
        run(s, to: 115)
        #expect(s.peek.presentationOffset.y == 700)
    }

    @Test(arguments: OSPath.allCases) func noBounceStopsAtEdge(path: OSPath) {
        let (s, _) = make(path, at: CGPoint(x: 0, y: 650))
        var env = Self.env; env.bouncesY = false
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 650)), tracker: tracker(vy: 3000), env: env, settings: ReleaseSettings())
        guard case let .decay(_, _, handoff) = my else { Issue.record("expected decay"); return }
        #expect(handoff?.bounces == false)
        run(s, to: 115)
        #expect(s.peek.presentationOffset.y == 700)
    }

    @Test(arguments: OSPath.allCases) func slowReleaseRestsImmediatelyAndSnaps(path: OSPath) {
        let (s, d) = make(path, at: CGPoint(x: 0, y: 300.3))
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300.3)), tracker: PointVelocityTracker(), env: Self.env, settings: ReleaseSettings())
        #expect(!my.willDecelerate && s.phase == .idle && !s.isTracking && !s.isClockRunning)
        #expect(s.peek.presentationOffset.y == 300.5)
        #expect(d.log.contains("didEndDragging(false)") && !d.log.contains("willBeginDecelerating"))
    }

    @Test(arguments: OSPath.allCases) func pagingMovesOnePageAndAFlick(path: OSPath) {
        var set = ReleaseSettings(); set.isPagingEnabled = true
        // slow drag past half a page -> next page
        var (s, _) = make(path, at: CGPoint(x: 0, y: 130))
        var (_, my) = s.endDrag(request(CGPoint(x: 0, y: 130)) { $0.dragStart = CGPoint(x: 0, y: 0) }, tracker: PointVelocityTracker(), env: Self.env, settings: set)
        #expect(my.endPosition == 200)
        // hard flick never skips more than one page
        (s, _) = make(path, at: CGPoint(x: 0, y: 210))
        (_, my) = s.endDrag(request(CGPoint(x: 0, y: 210)) { $0.dragStart = CGPoint(x: 0, y: 200) }, tracker: tracker(vy: 6000), env: Self.env, settings: set)
        #expect(my.endPosition == 400)
        // negative flick
        (s, _) = make(path, at: CGPoint(x: 0, y: 190))
        (_, my) = s.endDrag(request(CGPoint(x: 0, y: 190)) { $0.dragStart = CGPoint(x: 0, y: 200) }, tracker: tracker(vy: -6000), env: Self.env, settings: set)
        #expect(my.endPosition == 0)
    }

    @Test(arguments: OSPath.allCases) func catchAccelerationAddsMomentum(path: OSPath) {
        let (s, d) = make(path)
        let r = request(CGPoint(x: 0, y: 300)) { $0.caughtAt = 99.9; $0.caughtVelocity = CGVector(dx: 0, dy: 1000) }
        s.endDrag(r, tracker: tracker(vy: 1000), env: Self.env, settings: ReleaseSettings())
        #expect(abs((d.seenVelocity?.y ?? 0) - 2.0) < 0.2)
    }

    /// D14: the gesture's event clock differs from the state clock; the catch duration uses the state clock only.
    @Test(arguments: OSPath.allCases) func catchAccelerationIgnoresEventClockOffset(path: OSPath) {
        let (s, d) = make(path)
        let r = request(CGPoint(x: 0, y: 300), lift: 5000) { $0.caughtAt = 99.9; $0.caughtVelocity = CGVector(dx: 0, dy: 1000) }
        s.endDrag(r, tracker: tracker(vy: 1000, lift: 5000), env: Self.env, settings: ReleaseSettings())
        #expect(abs((d.seenVelocity?.y ?? 0) - 2.0) < 0.2)
    }

    @Test(arguments: OSPath.allCases) func lockedAxisAndZeroVelocityCancel(path: OSPath) {
        let (s, d) = make(path)
        s.endDrag(request(CGPoint(x: 0, y: 300)) { $0.zeroVelocity = true }, tracker: tracker(vy: 3000), env: Self.env, settings: ReleaseSettings())
        #expect(d.seenVelocity == CGPoint.zero && s.phase == .idle)
        let (s2, d2) = make(path)
        s2.endDrag(request(CGPoint(x: 0, y: 300)) { $0.lock = .horizontal }, tracker: tracker(vy: 3000), env: Self.env, settings: ReleaseSettings())
        #expect(d2.seenVelocity?.y == 0)
    }

    @Test(arguments: OSPath.allCases) func interruptCapturesVelocityAndEndsDeceleration(path: OSPath) {
        let (s, d) = make(path)
        s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1000), env: Self.env, settings: ReleaseSettings())
        s.now = { 100.1 }
        s.interrupt()
        #expect(s.lastInterruptedVelocity.dy > 100 && s.lastInterruptedVelocity.dy < 1000)
        #expect(s.phase == .idle && !s.isDecelerating)
        #expect(d.log.last == "didEndDecelerating")
        #expect(s.peek.targetOffset == s.peek.presentationOffset)
    }
}
