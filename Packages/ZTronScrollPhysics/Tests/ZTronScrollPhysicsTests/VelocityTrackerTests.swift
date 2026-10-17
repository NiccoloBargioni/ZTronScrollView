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

    @Test func pauseBeforeLiftGivesZero() {
        let times = hz120(from: 0, to: 24)                                       // last sample at 0.2 s
        let t = tracker(times: times) { 1500 * CGFloat($0) }
        #expect(t.velocity(at: 0.2 + 0.070) == 0)                                // 70 ms rest > 64 ms timeout
        #expect(t.velocity(at: 0.2 + 0.050) != 0)
    }

    @Test func jitterWithinRestDistanceGivesZero() {
        var t = VelocityTracker()
        for k in 0...24 { t.add(position: 1500 * CGFloat(k) / 120, at: TimeInterval(k) / 120) }   // moving until 0.2 s
        let rest: CGFloat = 1500 * 24 / 120
        for k in 1...10 {                                                       // 83 ms of ±0.3 pt jitter at 120 Hz
            t.add(position: rest + (k.isMultiple(of: 2) ? 0.3 : -0.3), at: 0.2 + TimeInterval(k) / 120)
        }
        #expect(t.velocity(at: t.latest!.time) == 0)
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

    @Test func invalidConfigurationFallsBack() {
        let t = VelocityTracker(window: -1, restTimeout: .nan)
        #expect(t.window == 0.100)
        #expect(t.restTimeout == 0.064)
    }
}
