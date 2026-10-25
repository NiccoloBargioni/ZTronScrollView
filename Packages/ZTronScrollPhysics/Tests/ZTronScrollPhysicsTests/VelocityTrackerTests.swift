import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct VelocityTrackerTests {
    /// Feeds `x(t)` at the given timestamps.
    private func tracker(times: [TimeInterval], _ x: (TimeInterval) -> CGFloat) -> VelocityTracker {
        var tracker = VelocityTracker()
        for t in times { tracker.add(position: x(t), at: t) }
        return tracker
    }

    private func hz120(from: Int, to: Int) -> [TimeInterval] {
        (from...to).map { TimeInterval($0) / 120 }
    }

    @Test(arguments: [1200, -750, 4000] as [CGFloat])
    func constantMotionGivesExactVelocity(v: CGFloat) {
        let times = hz120(from: 0, to: 24)
        let t = tracker(times: times) { 30 + v * CGFloat($0) }
        expectClose(t.velocity(at: times.last!), v, 1e-6)
        expectClose(t.velocity(at: times.last! + 0.02), v, 1e-6)                // short gap before lift still counts
    }

    /// BTN-s2 P1: an event-free pause before the lift never changes the release; a lift within one frame keeps the
    /// lift-anchored fit.
    @Test func pauseBeforeLiftIsInvariant() {
        let times = hz120(from: 0, to: 24)                                       // last sample at 0.2 s
        let pauses = [0.0, 1.0 / 60, 0.05, 0.07, 0.5, 1.2]
        // Constant motion: every lift gives the same value.
        let linear = tracker(times: times) { 1500 * CGFloat($0) }
        for pause in pauses {
            expectClose(linear.velocity(at: 0.2 + pause), 1500, 1e-6, "pause \(pause)")
        }
        // A decelerating finger: the window's membership depends on the evaluation point, so a lift later than one
        // frame is evaluated at newest + 1/60 (same value for every pause), a lift within one frame stays lift-anchored.
        let t = tracker(times: times) { 1500 * CGFloat($0) - 2000 * CGFloat($0 * $0) }
        let oneFrame = t.ungatedVelocity(at: 0.2 + 1.0 / 60)
        #expect(abs(t.gateVelocity) >= 250 && oneFrame != 0)
        for pause in pauses where pause >= 1.0 / 60 {
            #expect(t.velocity(at: 0.2 + pause) == oneFrame, "pause \(pause)")
        }
        let atNewest = t.ungatedVelocity(at: 0.2), halfFrame = t.ungatedVelocity(at: 0.2 + 1.0 / 120)
        #expect(atNewest != halfFrame && halfFrame != oneFrame)
        #expect(t.velocity(at: 0.1) == atNewest)                                 // a lift before the newest sample
    }

    /// BTN-s2 P2: a finger that stops and jitters before lifting has no pan velocity; the gate (not a rest timeout)
    /// zeroes the release even though the 100 ms fit still sees the earlier motion.
    @Test func jitterAfterMotionIsGatedToZero() {
        var t = VelocityTracker()
        for k in 0...24 { t.add(position: 1500 * CGFloat(k) / 120, at: TimeInterval(k) / 120) }   // moving until 0.2 s
        let rest: CGFloat = 1500 * 24 / 120
        for k in 1...7 {                                                        // 58 ms of ±0.3 pt jitter at 120 Hz
            t.add(position: rest + (k.isMultiple(of: 2) ? 0.3 : -0.3), at: 0.2 + TimeInterval(k) / 120)
        }
        #expect(abs(t.gateVelocity) < 250)
        #expect(t.ungatedVelocity(at: t.latest!.time) != 0)
        #expect(t.velocity(at: t.latest!.time) == 0)
        #expect(t.velocity(at: t.latest!.time + 0.5) == 0)
    }

    @Test(arguments: [60, 120], [248.0, 252.0, -248.0, -252.0] as [CGFloat])
    func gateIsInclusiveAt250(hz: Int, v: CGFloat) {
        let times = (0...(hz / 5)).map { TimeInterval($0) / TimeInterval(hz) }      // 200 ms
        let t = tracker(times: times) { 10 + v * CGFloat($0) }
        expectClose(t.gateVelocity, v, 1e-6)
        expectClose(t.ungatedVelocity(at: times.last!), v, 1e-6)
        if abs(v) >= 250 {
            expectClose(t.velocity(at: times.last!), v, 1e-6)
        } else {
            #expect(t.velocity(at: times.last!) == 0)
        }
    }

    /// A fast drag whose last 50 ms crawl at 200 pt/s rests (UIKit: the pan velocity is the last 50 ms only).
    @Test func fastDragSlowingBelowTheGateRests() {
        let times = hz120(from: 0, to: 24)                                       // 0 ... 0.2 s
        let t = tracker(times: times) { time in
            time <= 0.15 ? 2000 * CGFloat(time) : 300 + 200 * CGFloat(time - 0.15)
        }
        expectClose(t.gateVelocity, 200, 1e-6)
        #expect(t.ungatedVelocity(at: 0.2) > 250)
        #expect(t.velocity(at: 0.2) == 0)
    }

    @Test func gateVelocityWithLessThan50msOfSamplesUnderReads() {
        var t = VelocityTracker()
        #expect(t.gateVelocity == 0)
        t.add(position: 0, at: 1.0)
        #expect(t.gateVelocity == 0)                                             // < 2 samples
        t.add(position: 10, at: 1.0 + 1.0 / 60)                                  // 600 pt/s over 16.7 ms…
        expectClose(t.gateVelocity, 10 / 0.050, 1e-6)                            // …reads 200: clamped to the oldest sample
        t.add(position: 20, at: 1.0 + 2.0 / 60)
        expectClose(t.gateVelocity, 20 / 0.050, 1e-6)
        t.add(position: 30, at: 1.0 + 3.0 / 60)                                  // 50 ms covered: interpolated
        expectClose(t.gateVelocity, 600, 1e-6)
    }

    @Test func gateVelocityInterpolatesBetweenSamples() {
        // 100 pt/s until 0.1 s, then 1000 pt/s until 0.16 s: the gate's 50 ms start at 0.11 s, between two samples of
        // the fast segment.
        let times: [TimeInterval] = [0.04, 0.06, 0.08, 0.1, 0.115, 0.13, 0.145, 0.16]
        let t = tracker(times: times) { time in time <= 0.1 ? 100 * CGFloat(time) : 10 + 1000 * CGFloat(time - 0.1) }
        expectClose(t.gateVelocity, 1000, 1e-6)
    }

    @Test func ignoresSamplesOutsideWindow() {
        // −800 pt/s until 0.5 s, then +1000 pt/s until 0.6 s: only the last 100 ms count.
        let times = hz120(from: 0, to: 72)
        let t = tracker(times: times) { time in
            time <= 0.5 ? -800 * CGFloat(time) : -400 + 1000 * CGFloat(time - 0.5)
        }
        expectClose(t.velocity(at: times.last!), 1000, 1e-6)
    }

    @Test func singleLateEventDoesNotDominate() {
        var t = VelocityTracker()
        let times = hz120(from: 0, to: 24)
        for time in times.dropLast() { t.add(position: 1000 * CGFloat(time), at: time) }
        let outlier = 1000 * CGFloat(times.last!) + 15
        t.add(position: outlier, at: times.last!)
        let lastEventOnly = (outlier - 1000 * CGFloat(times[times.count - 2])) * 120          // 2800 pt/s
        let v = t.velocity(at: times.last!)
        #expect(v > 1000)
        #expect(abs(v - 1000) < abs(lastEventOnly - 1000) / 4)
    }

    @Test func irregularTimestampsStillFit() {
        // Mixed 60/120 Hz delivery with coalesced pairs.
        var times: [TimeInterval] = []
        var time: TimeInterval = 1.0
        let hz60: TimeInterval = 1.0 / 60, hz120: TimeInterval = 1.0 / 120
        let steps: [TimeInterval] = [hz60, hz120, hz120, hz60, 0.002, hz120, hz60, 0.011, hz120, 0.004, hz60, hz120]
        for step in steps {
            time += step
            times.append(time)
        }
        let t = tracker(times: times) { 900 * CGFloat($0) - 40 }
        expectClose(t.velocity(at: times.last!), 900, 1e-6)
    }

    @Test func nonMonotonicTimeIgnored() {
        let times = hz120(from: 0, to: 12)
        var t = tracker(times: times) { 600 * CGFloat($0) }
        let before = t.velocity(at: times.last!)
        let count = t.count
        t.add(position: 99_999, at: 0.01)                                         // older than the newest sample
        t.add(position: .nan, at: 0.2)
        t.add(position: 5, at: .infinity)
        #expect(t.count == count)
        #expect(t.velocity(at: times.last!) == before)
        t.add(position: 600 * CGFloat(times.last!), at: times.last!)              // same timestamp replaces in place
        #expect(t.count == count)
        expectClose(before, 600, 1e-6)
    }

    @Test func fewerThanTwoSamplesGivesZero() {
        var t = VelocityTracker()
        #expect(t.velocity(at: 1) == 0)
        t.add(position: 10, at: 1)
        #expect(t.velocity(at: 1) == 0)
        t.add(position: 50, at: 1.2)                                              // first sample is outside the window
        #expect(t.velocity(at: 1.2) == 0)
        t.reset()
        #expect(t.latest == nil && t.count == 0)
    }

    @Test func capacityBoundsTheBuffer() {
        var t = VelocityTracker()
        for k in 0..<100 { t.add(position: CGFloat(k), at: TimeInterval(k) / 240) }
        #expect(t.count == t.capacity)
        #expect(t.latest == VelocityTracker.Sample(time: 99.0 / 240, position: 99))
    }

    @Test func pointTrackerAxesIndependent() {
        var t = PointVelocityTracker()
        for k in 0...12 {
            let time = TimeInterval(k) / 120
            t.add(CGPoint(x: 500 * CGFloat(time), y: k == 6 ? .nan : 200), at: time)
        }
        let v = t.velocity(at: 0.1)
        expectClose(v.dx, 500, 1e-6)
        #expect(v.dy == 0)
        #expect(t.x.count == 13 && t.y.count == 12)
        t.reset()
        #expect(t.velocity(at: 1) == CGVector(dx: 0, dy: 0))
    }

    /// A 2-D tracker moving at `(vx, vy)` pt/s for 200 ms; the lift is 100 ms after the newest sample.
    private func point(_ vx: CGFloat, _ vy: CGFloat) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for k in 0...24 {
            let time = TimeInterval(k) / 120
            t.add(CGPoint(x: vx * CGFloat(time), y: vy * CGFloat(time)), at: time)
        }
        return t
    }

    /// BTN-s3 P3: the gate is the VECTOR of the pan velocity over the scrolling axes; past it every axis decelerates
    /// from its own component, however small.
    @Test func pointTrackerGatesTheVector() {
        let lift = 0.2 + 0.1
        var v = point(300, 200).velocity(at: lift)
        expectClose(v.dx, 300, 1e-6)
        expectClose(v.dy, 200, 1e-6)
        v = point(200, 200).velocity(at: lift)                                   // 45°, |v| = 283: both fling
        expectClose(v.dx, 200, 1e-6)
        expectClose(v.dy, 200, 1e-6)
        #expect(point(170, 170).velocity(at: lift) == CGVector(dx: 0, dy: 0))    // |v| = 240: rest
        let u = point(170, 170).ungatedVelocity(at: lift)
        expectClose(u.dx, 170, 1e-6)
        expectClose(u.dy, 170, 1e-6)
        v = point(300, 80).velocity(at: lift)                                    // 15°: the slow axis still moves
        expectClose(v.dx, 300, 1e-6)
        expectClose(v.dy, 80, 1e-6)
        expectClose(point(300, 80).gateVelocity.dy, 80, 1e-6)
    }

    @Test func pointTrackerGateBoundaryIsInclusiveOnTheVector() {
        let lift = 0.2 + 0.1
        var on = point(150, 200)                                                 // |v| = 250 (up to rounding)
        let speed = hypot(on.gateVelocity.dx, on.gateVelocity.dy)
        expectClose(speed, 250, 1e-6)
        on.minimumDecelerationVelocity = speed                                   // pinned: inclusive at the threshold
        #expect(on.x.minimumDecelerationVelocity == speed && on.y.minimumDecelerationVelocity == speed)
        let v = on.velocity(at: lift)
        expectClose(v.dx, 150, 1e-6)
        expectClose(v.dy, 200, 1e-6)
        on.minimumDecelerationVelocity = speed.nextUp                            // just under: rest
        #expect(on.velocity(at: lift) == CGVector(dx: 0, dy: 0))
        #expect(point(150, 199).velocity(at: lift) == CGVector(dx: 0, dy: 0))    // |v| = 249.2
        #expect(point(176, 176).velocity(at: lift) == CGVector(dx: 0, dy: 0))    // |v| = 248.9
    }

    /// A one-axis view counts only its own axis: a 45° drag at (248, 244) rests on a horizontal-only view.
    @Test func pointTrackerAxisExclusion() {
        let lift = 0.2 + 0.1
        #expect(point(248, 244).velocity(at: lift, x: true, y: false) == CGVector(dx: 0, dy: 0))
        let both = point(248, 244).velocity(at: lift)                            // |v| = 348 on a two-axis view
        expectClose(both.dx, 248, 1e-6)
        expectClose(both.dy, 244, 1e-6)
        let yOnly = point(100, 300).velocity(at: lift, x: false, y: true)
        #expect(yOnly.dx == 0)
        expectClose(yOnly.dy, 300, 1e-6)
        let xOnly = point(300, 100).velocity(at: lift, x: true, y: false)
        expectClose(xOnly.dx, 300, 1e-6)
        #expect(xOnly.dy == 0)
        #expect(point(300, 300).velocity(at: lift, x: false, y: false) == CGVector(dx: 0, dy: 0))
        // The 1-D tracker keeps its own-axis gate.
        #expect(point(248, 244).x.velocity(at: lift) == 0)
        expectClose(point(260, 0).x.velocity(at: lift), 260, 1e-6)
    }

    @Test func invalidConfigurationFallsBack() {
        let t = VelocityTracker(window: -1, minimumDecelerationVelocity: .nan)
        #expect(t.window == 0.100)
        #expect(t.minimumDecelerationVelocity == 250)
        #expect(VelocityTracker(minimumDecelerationVelocity: -5).minimumDecelerationVelocity == 250)
        #expect(VelocityTracker(window: .infinity).window == 0.100)
        let p = PointVelocityTracker(window: 0, minimumDecelerationVelocity: 0)
        #expect(p.x.window == 0.100 && p.y.minimumDecelerationVelocity == 0)   // 0 turns the gate off
        var off = VelocityTracker(minimumDecelerationVelocity: 0)
        for k in 0...24 { off.add(position: 100 * CGFloat(k) / 120, at: TimeInterval(k) / 120) }
        expectClose(off.velocity(at: 0.2), 100, 1e-6)
    }
}
