import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct ZoomTimingTests {
    @Test func easeInOutIsTheUIKitCurve() {
        let c = UnitBezier.easeInOut
        #expect(c.value(at: 0) == 0 && c.value(at: 1) == 1)
        #expect(abs(c.value(at: 0.5) - 0.5) < 1e-9, "symmetric")
        #expect(abs(c.value(at: 0.25) - 0.1289) < 0.002, "\(c.value(at: 0.25))")   // CSS ease-in-out reference values
        #expect(abs(c.value(at: 0.75) - 0.8711) < 0.002, "\(c.value(at: 0.75))")
        var last: CGFloat = 0
        for i in 1...200 {
            let v = c.value(at: CGFloat(i) / 200)
            #expect(v >= last - 1e-12, "monotonic at \(i)")
            last = v
        }
        #expect(c.value(at: -1) == 0 && c.value(at: 2) == 1 && c.value(at: .nan) == 0, "clamped")
    }

    /// Measured on iOS 27.0 (spike `-zoomCal`, 60 Hz frames): 1.25× 0.167–0.170 s, 1.5× 0.225–0.235 s, 2× 0.310–0.320 s
    /// whatever the start scale, 3×/4×/8× 0.400 s; the same back out.
    @Test func nativeDurationsFollowTheZoomRatio() {
        func d(_ a: CGFloat, _ b: CGFloat) -> TimeInterval { ZoomTiming.duration(from: a, to: b) }
        #expect(abs(d(1, 1.25) - 0.17) < 0.006)
        #expect(abs(d(1, 1.5) - 0.225) < 0.006)
        #expect(abs(d(1, 2) - 0.315) < 0.006 && abs(d(2, 4) - 0.315) < 0.006 && abs(d(4, 8) - 0.315) < 0.006, "ratio, not delta")
        #expect(d(1, 3) == 0.40 && d(1, 4) == 0.40 && d(1, 8) == 0.40, "capped from 3× up")
        #expect(d(2, 1) == d(1, 2) && d(8, 1) == d(1, 8) && d(8, 2) == 0.40, "symmetric")
        #expect(d(1, 1) > 0.1, "a pure offset zoom(to:) still animates")
        #expect(d(0, .nan) > 0)
    }

    @Test func sampleRunsThenSettlesExactly() {
        let z = ZoomTiming(start: 100, duration: 0.4)
        #expect(z.sample(at: 99).progress == 0 && !z.sample(at: 99).isSettled)
        #expect(z.sample(at: 100).progress == 0)
        #expect(abs(z.sample(at: 100.2).progress - 0.5) < 1e-9)
        #expect(z.sample(at: 100.4) == ZoomTiming.Sample(progress: 1, isSettled: true))
        #expect(z.sample(at: 101).progress == 1)
        #expect(ZoomTiming(start: 0, duration: 0).sample(at: 0).isSettled, "no duration: already there")
    }
}
