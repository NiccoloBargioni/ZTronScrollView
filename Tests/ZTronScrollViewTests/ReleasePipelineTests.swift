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
    /// Finger moving up/left at `(vx, vy)` pt/s (content offset increases) for 120 ms ending at `lift`.
    func tracker(vx: CGFloat = 0, vy: CGFloat, lift: TimeInterval = 100) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = lift - 0.12 + Double(i) * 0.015
            let dt = CGFloat(time - (lift - 0.12))
            t.add(CGPoint(x: -vx * dt, y: -vy * dt), at: time)
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
        var tr = PointVelocityTracker()
        let zero = CGVector(dx: 0, dy: 0)
        func v(_ fallback: CGVector?, x: Bool = true, y: Bool = true, gated: Bool = true, tracker: PointVelocityTracker? = nil,
               lift: TimeInterval = 1) -> CGVector {
            ReleasePipeline.velocity(tracker: tracker ?? tr, liftTime: lift, fallback: fallback, enabledX: x, enabledY: y, gated: gated)
        }
        // < 2 samples: the gesture's own velocity, gated on the vector of its enabled components (BTN-s2/s3: 250 pt/s, inclusive).
        #expect(v(CGVector(dx: 0, dy: 250)) == CGVector(dx: 0, dy: 250))
        #expect(v(CGVector(dx: 0, dy: 249)) == zero)
        #expect(v(CGVector(dx: 0, dy: -249), gated: false) == CGVector(dx: 0, dy: -249))
        #expect(v(CGVector(dx: 200, dy: 200)) == CGVector(dx: 200, dy: 200))                 // |v| = 283
        #expect(v(CGVector(dx: 200, dy: 200), y: false) == zero)                              // one axis: 200 < 250
        #expect(v(CGVector(dx: 300, dy: 200), x: false) == CGVector(dx: 0, dy: 0))            // y alone: 200 rests
        #expect(v(CGVector(dx: 300, dy: 200), y: false) == CGVector(dx: 300, dy: 0))
        #expect(v(nil) == zero)
        #expect(v(nil, gated: false) == zero)
        for i in 0...6 { tr.add(CGPoint(x: 0, y: CGFloat(i) * 10), at: 0.9 + Double(i) * 0.015) }
        let fit = v(CGVector(dx: 0, dy: 250), lift: 0.99)
        #expect(fit.dx == 0 && abs(fit.dy - 666) < 40)
        // An event-free pause before the lift no longer zeroes the release (P1): same value after 210 ms of rest.
        #expect(v(CGVector(dx: 0, dy: 250), lift: 1.2) == fit)
        // A disabled axis is 0 even with samples; the fallback never leaks into a tracked release.
        #expect(v(CGVector(dx: 500, dy: 500), y: false, lift: 0.99) == zero)
        // A slow finger (200 pt/s) rests when gated; the ungated path (target behaviors) keeps the fit.
        var slow = PointVelocityTracker()
        for i in 0...8 { slow.add(CGPoint(x: 0, y: CGFloat(i) * 3), at: 0.9 + Double(i) * 0.015) }
        #expect(v(nil, tracker: slow, lift: 1.02) == zero)
        #expect(abs(v(nil, gated: false, tracker: slow, lift: 1.02).dy - 200) < 1e-6)
        // A 45° finger at (200, 200) flings on two axes (|v| = 283) and rests on one (BTN-s3).
        var diagonal = PointVelocityTracker()
        for i in 0...8 { diagonal.add(CGPoint(x: CGFloat(i) * 3, y: CGFloat(i) * 3), at: 0.9 + Double(i) * 0.015) }
        let d = v(nil, tracker: diagonal, lift: 1.02)
        #expect(abs(d.dx - 200) < 1e-6 && abs(d.dy - 200) < 1e-6)
        #expect(v(nil, x: false, tracker: diagonal, lift: 1.02) == zero)
        #expect(v(nil, y: false, tracker: diagonal, lift: 1.02) == zero)
    }

    /// BTN-s3 P3: the natural-release gate is decided once on the vector over the enabled axes. A 45° release at
    /// (200, 200) pt/s (|v| = 283) decelerates both axes on a two-axis view; the same finger rests on a horizontal-only
    /// view and under a lock on x (one axis counts only itself: 200 < 250).
    @Test(arguments: OSPath.allCases) func diagonalNaturalReleaseGatesTheVector(path: OSPath) {
        var (s, d) = make(path, at: CGPoint(x: 50, y: 300))
        var (mx, my) = s.endDrag(request(CGPoint(x: 50, y: 300)), tracker: tracker(vx: 200, vy: 200), env: Self.env, settings: ReleaseSettings())
        #expect(mx.willDecelerate && my.willDecelerate && s.phase == .decelerating)
        #expect(abs((d.seenVelocity?.x ?? 0) - 0.2) < 0.02 && abs((d.seenVelocity?.y ?? 0) - 0.2) < 0.02)
        #expect(mx.endPosition > 50 && my.endPosition > 300)
        // Horizontal-only view: 200 pt/s on its own axis rests; y is not driven.
        let horizontal = PanSessionTests.env { $0.axes = .horizontal }
        (s, d) = make(path, at: CGPoint(x: 50, y: 300))
        (mx, my) = s.endDrag(request(CGPoint(x: 50, y: 300)), tracker: tracker(vx: 200, vy: 200), env: horizontal, settings: ReleaseSettings())
        #expect(!mx.willDecelerate && !my.willDecelerate && s.phase == .idle)
        #expect(d.seenVelocity == CGPoint(x: 0, y: 0))
        #expect(s.peek.presentationOffset == CGPoint(x: 50, y: 300))
        // Directional lock on x: same rule.
        (s, d) = make(path, at: CGPoint(x: 50, y: 300))
        (mx, my) = s.endDrag(request(CGPoint(x: 50, y: 300)) { $0.lock = .horizontal }, tracker: tracker(vx: 200, vy: 200), env: Self.env, settings: ReleaseSettings())
        #expect(!mx.willDecelerate && !my.willDecelerate && d.seenVelocity == CGPoint(x: 0, y: 0))
    }

    /// BTN-s3: past the gate every enabled axis decelerates from its own component, however small: a 15° release
    /// at (300, 80) pt/s moves y too (native: vy 48-112 pt/s still moves y 38-64 pt).
    @Test(arguments: OSPath.allCases) func shallowReleaseMovesTheSlowAxis(path: OSPath) {
        let (s, d) = make(path, at: CGPoint(x: 0, y: 300))
        let (mx, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vx: 300, vy: 80), env: Self.env, settings: ReleaseSettings())
        #expect(mx.willDecelerate && my.willDecelerate)
        #expect(abs((d.seenVelocity?.y ?? 0) - 0.08) < 0.01)
        #expect(my.endPosition > 300 && my.endPosition < 400)
        run(s)
        #expect(s.peek.presentationOffset.y > 300)
    }

    /// A target-behavior release stays ungated: (170, 170) pt/s (|v| = 240) rests naturally but reaches the behavior.
    @Test(arguments: OSPath.allCases) func targetBehaviorReleaseStaysUngatedOnTwoAxes(path: OSPath) {
        var (s, d) = make(path, at: CGPoint(x: 50, y: 300))
        s.endDrag(request(CGPoint(x: 50, y: 300)), tracker: tracker(vx: 170, vy: 170), env: Self.env, settings: ReleaseSettings())
        #expect(d.seenVelocity == CGPoint(x: 0, y: 0) && s.phase == .idle)
        (s, d) = make(path, at: CGPoint(x: 50, y: 300))
        s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never))
        s.endDrag(request(CGPoint(x: 50, y: 300)), tracker: tracker(vx: 170, vy: 170), env: Self.env, settings: ReleaseSettings())
        #expect(abs((d.seenVelocity?.x ?? 0) - 0.17) < 0.02 && abs((d.seenVelocity?.y ?? 0) - 0.17) < 0.02)
    }

    /// BTN-s2: a natural release at 200 pt/s rests (no deceleration, willEndDragging sees 0); the same drag under a
    /// scroll-target behavior (the paging knob) still gets its ungated velocity.
    @Test(arguments: OSPath.allCases) func slowNaturalReleaseRestsButATargetBehaviorSeesTheVelocity(path: OSPath) {
        var (s, d) = make(path)
        var (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 200), env: Self.env, settings: ReleaseSettings())
        #expect(!my.willDecelerate && s.phase == .idle && !s.isClockRunning)
        #expect(d.seenVelocity == CGPoint(x: 0, y: 0))
        #expect(d.log == ["willEndDragging", "didEndDragging(false)"])
        #expect(s.peek.presentationOffset.y == 300)
        // The paging knob: the ungated 200 pt/s (0.2 pt/ms) reaches the delegate; below the knob's 300 pt/s flick
        // threshold the page snaps back (a spring, not a rest).
        var knob = ReleaseSettings(); knob.isPagingEnabled = true
        (s, d) = make(path, at: CGPoint(x: 0, y: 210))
        (_, my) = s.endDrag(request(CGPoint(x: 0, y: 210)) { $0.dragStart = CGPoint(x: 0, y: 200) }, tracker: tracker(vy: 200), env: Self.env, settings: knob)
        #expect(abs((d.seenVelocity?.y ?? 0) - 0.2) < 0.02)
        #expect(my.willDecelerate && my.endPosition == 200)
        // A custom behavior likewise.
        (s, d) = make(path)
        s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never))
        s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 200), env: Self.env, settings: ReleaseSettings())
        #expect(abs((d.seenVelocity?.y ?? 0) - 0.2) < 0.02)
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
