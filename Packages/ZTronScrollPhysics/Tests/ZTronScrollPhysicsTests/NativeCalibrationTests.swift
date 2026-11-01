import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

/// Regression fixtures recorded from a native SwiftUI `ScrollView` (UIScrollView-backed) on iOS 27.0, iPhone 18 Pro
/// simulator, by `CalibrateUITests` (docs/design/PHYSICS-calibration.md). Times in s, positions in pt. Each test
/// checks that the physics reproduces the native curve within the calibration tolerances (tracking 1:1, deceleration
/// distance ±5 %, duration ±10 %, rubber band ±10 %, bounce-back ±15 %).
@Suite struct NativeCalibrationTests {
    // MARK: Fixtures

    /// Fast flick: finger (t, y) after the 10 pt recognition, same stream UIKit saw. Native release velocity: 3457 pt/s
    /// (fitted on the deceleration, r = 0.998). The last event (7 pt in 18 ms) is the finger stopping to lift.
    static let fastFingers: [(TimeInterval, CGFloat)] = [(0.0172, 510), (0.0359, 435), (0.0522, 359), (0.0695, 285), (0.0855, 217), (0.1017, 165), (0.1199, 158)]
    static let fastLift: TimeInterval = 0.1337
    static let fastNativeVelocity: CGFloat = 3457

    /// Medium fling. Native release velocity: 1350 pt/s.
    static let mediumFingers: [(TimeInterval, CGFloat)] = [(0.0000, 588), (0.0168, 563), (0.0334, 537), (0.0499, 509), (0.0666, 481), (0.0834, 452), (0.0999, 424), (0.1173, 396), (0.1346, 370), (0.1505, 345), (0.1672, 323), (0.1838, 308)]
    static let mediumLift: TimeInterval = 0.2008
    static let mediumNativeVelocity: CGFloat = 1350

    /// Slow drag (≈ 280 pt/s) held 0.5 s before lifting: native does not decelerate at all.
    static let slowFingers: [(TimeInterval, CGFloat)] = [(0.0331, 536), (0.0501, 532), (0.0666, 528), (0.0834, 523), (0.0998, 518), (0.1169, 513), (0.1338, 509), (0.1504, 503), (0.1678, 498), (0.1845, 493), (0.2011, 488), (0.2180, 483), (0.2345, 477), (0.2508, 472), (0.2676, 466), (0.2846, 461), (0.3011, 455), (0.3179, 449), (0.3344, 444), (0.3514, 438), (0.3676, 432), (0.3846, 427), (0.4010, 421), (0.4178, 415), (0.4347, 410), (0.4514, 404), (0.4682, 398), (0.4846, 392), (0.5015, 387), (0.5181, 381), (0.5350, 375), (0.5517, 370), (0.5681, 364), (0.5846, 358), (0.6017, 353), (0.6183, 347), (0.6350, 342), (0.6511, 336), (0.6675, 331), (0.6841, 325), (0.7010, 320), (0.7178, 315), (0.7343, 310), (0.7509, 304), (0.7677, 299), (0.7843, 295), (0.8009, 290), (0.8172, 285), (0.8339, 280), (0.8508, 276), (0.8672, 272), (0.8843, 267), (0.9004, 263), (0.9169, 260), (0.9342, 256), (0.9509, 253), (0.9672, 250), (0.9843, 248)]
    static let slowLift: TimeInterval = 1.4832

    /// Native deceleration after the fast flick: (t since lift, contentOffset.y); fitted x₀ = 521.1, v₀ = 3457,
    /// r = 0.99800 (rms 0.46 pt). It stops at 2243 after 2.934 s — 4.7 pt short of the analytic rest 2247.7.
    static let fastDecay: [(TimeInterval, CGFloat)] = [(0.0011, 528.33), (0.1341, 927.33), (0.2672, 1236.67), (0.4001, 1473.67), (0.5342, 1655.00), (0.6678, 1794.00), (0.8004, 1900.33), (0.9350, 1981.67), (1.0676, 2044.00), (1.2014, 2091.67), (1.3349, 2128.33), (1.4682, 2156.33), (1.6005, 2177.67), (1.7339, 2194.33), (1.8681, 2206.67), (2.0009, 2216.33), (2.1336, 2223.67), (2.2665, 2229.33), (2.4000, 2233.67), (2.5337, 2237.00), (2.6670, 2239.67), (2.8503, 2242.33), (2.9344, 2243.00)]
    static let fastDecayFit = (origin: CGFloat(521.1), velocity: CGFloat(3457), end: CGFloat(2243), duration: 2.934)

    /// Native deceleration after the medium fling: fitted x₀ = 1309.4, v₀ = 1350, r = 0.99800 (rms 0.27 pt); stops at
    /// 1979 after 2.467 s (4.8 pt short of 1983.8).
    static let mediumDecay: [(TimeInterval, CGFloat)] = [(0.0020, 1312.67), (0.1338, 1467.67), (0.2665, 1588.67), (0.4009, 1681.33), (0.5342, 1752.00), (0.6677, 1806.33), (0.7998, 1848.00), (0.9338, 1879.67), (1.0676, 1904.00), (1.2000, 1922.67), (1.3342, 1937.00), (1.4677, 1948.00), (1.6002, 1956.33), (1.7341, 1963.00), (1.8668, 1967.67), (1.9996, 1971.67), (2.1332, 1974.33), (2.2831, 1977.00), (2.4672, 1979.00)]
    static let mediumDecayFit = (origin: CGFloat(1309.4), velocity: CGFloat(1350), end: CGFloat(1979), duration: 2.467)

    /// Finger log of that drag (400 pt/s outward, then 0.3 s at rest): the spring-back's `B` is this last velocity.
    static let topFingers: [(TimeInterval, CGFloat)] = [(0.0167, 228), (0.0332, 234), (0.0499, 240), (0.0666, 247), (0.0832, 254), (0.1001, 261), (0.1166, 268), (0.1336, 276), (0.1501, 283), (0.1670, 291), (0.1835, 298), (0.2004, 306), (0.2168, 314), (0.2338, 321), (0.2506, 329), (0.2674, 336), (0.2841, 344), (0.3006, 351), (0.3171, 359), (0.3340, 366), (0.3501, 373), (0.3668, 380), (0.3834, 386), (0.4004, 393), (0.4170, 399), (0.4335, 405), (0.4503, 410), (0.4671, 414), (0.4836, 418)]
    static let topLift: TimeInterval = 0.8173

    /// Native return after dragging 190 pt past the top (viewport 600 → shown −89 pt, c = 0.55) with the finger at rest
    /// for 0.3 s before lifting: (t since the first post-lift frame, y). Fits `(−89 − 378·t)·e^(−10.9t)` (rms 0.14):
    /// `B` is the finger's outward drag velocity, kept through the pause. Other amplitudes / speeds (B fits):
    /// 2.7 pt → −160, 8 → −230, 14 → −452, 46 → −406, 126 → −416 at 400 pt/s; 89 pt at 150 → −222, at 1000 → −991;
    /// without the pause → −365. ω = 10.8–11.3 throughout.
    static let topBounce: [(TimeInterval, CGFloat)] = [(0.0000, -89.00), (0.0315, -71.33), (0.0654, -55.67), (0.0985, -43.00), (0.1321, -32.67), (0.1658, -24.67), (0.1988, -18.67), (0.2322, -14.00), (0.2645, -10.33), (0.2984, -7.67), (0.3316, -5.67), (0.3656, -4.33), (0.3991, -3.00), (0.4324, -2.33), (0.4657, -1.67), (0.5158, -1.00), (0.5997, 0.00)]

    /// Native fling into the bottom edge: (t since the last in-bounds frame, overshoot). Velocity before the crossing
    /// ≈ 1204 pt/s; peak overshoot 39 pt; back on the edge after 0.69 s.
    static let edgeBounce: [(TimeInterval, CGFloat)] = [(0.0000, -4.67), (0.0334, 25.00), (0.0668, 36.67), (0.0996, 39.00), (0.1337, 36.67), (0.1666, 32.00), (0.2002, 26.67), (0.2335, 21.67), (0.2670, 17.33), (0.3003, 13.67), (0.3337, 10.33), (0.3670, 8.00), (0.4003, 6.00), (0.4339, 4.67), (0.4663, 3.33), (0.5001, 2.67), (0.5328, 2.00), (0.5670, 1.33), (0.6343, 0.67), (0.6857, 0.00)]
    static let edgeCrossingVelocity: CGFloat = 1204

    // MARK: Programmatic zoom (2026-10-19, spike `-zoomCal`: UIScrollView setZoomScale/zoom(to:) animated, 300×360
    // viewport, 600×600 content). Progress of the zoom view's presentation scale per frame, t from the frame before the
    // first visible change.
    static let zoomSet2: [(TimeInterval, CGFloat)] = [(0.0331, 0.0159), (0.0497, 0.0416), (0.0664, 0.0802), (0.0831, 0.1317), (0.0998, 0.1957), (0.1165, 0.2716), (0.1332, 0.3567), (0.1499, 0.4473), (0.1665, 0.5403), (0.1832, 0.6317), (0.1999, 0.7177), (0.2165, 0.7939), (0.2331, 0.8597), (0.2498, 0.9132), (0.2665, 0.9535), (0.2832, 0.9812), (0.2998, 0.9963), (0.3165, 1.0000)]
    static let zoomSet8: [(TimeInterval, CGFloat)] = [(0.0180, 0.0033), (0.0347, 0.0136), (0.0514, 0.0311), (0.0681, 0.0562), (0.0847, 0.0889), (0.1014, 0.1293), (0.1181, 0.1773), (0.1344, 0.2307), (0.1514, 0.2931), (0.1665, 0.3527), (0.1837, 0.4242), (0.2015, 0.5005), (0.2181, 0.5721), (0.2348, 0.6415), (0.2515, 0.7077), (0.2681, 0.7686), (0.2848, 0.8234), (0.3015, 0.8712), (0.3172, 0.9094), (0.3332, 0.9412), (0.3515, 0.9690), (0.3681, 0.9865), (0.3842, 0.9965), (0.4015, 1.0000)]
    static let zoomBackFrom8: [(TimeInterval, CGFloat)] = [(0.0331, 0.0123), (0.0497, 0.0291), (0.0664, 0.0534), (0.0831, 0.0854), (0.0998, 0.1251), (0.1165, 0.1723), (0.1331, 0.2264), (0.1498, 0.2869), (0.1664, 0.3526), (0.1831, 0.4220), (0.1998, 0.4933), (0.2165, 0.5651), (0.2331, 0.6350), (0.2498, 0.7014), (0.2665, 0.7629), (0.2831, 0.8183), (0.2998, 0.8667), (0.3165, 0.9079), (0.3331, 0.9412), (0.3498, 0.9669), (0.3664, 0.9851), (0.3831, 0.9960), (0.3998, 1.0000)]
    static let zoomRect8: [(TimeInterval, CGFloat)] = [(0.0164, 0.0027), (0.0347, 0.0136), (0.0514, 0.0311), (0.0680, 0.0561), (0.0847, 0.0889), (0.1014, 0.1294), (0.1181, 0.1772), (0.1348, 0.2322), (0.1514, 0.2932), (0.1681, 0.3593), (0.1848, 0.4289), (0.2014, 0.5003), (0.2181, 0.5719), (0.2348, 0.6416), (0.2514, 0.7076), (0.2681, 0.7686), (0.2848, 0.8234), (0.3015, 0.8711), (0.3176, 0.9102), (0.3331, 0.9412), (0.3514, 0.9690), (0.3681, 0.9865), (0.3848, 0.9967), (0.4015, 1.0000)]

    private func tracked(_ fingers: [(TimeInterval, CGFloat)], lift: TimeInterval) -> CGFloat {
        var tracker = VelocityTracker()
        for (t, y) in fingers { tracker.add(position: y, at: t) }
        return -tracker.velocity(at: lift)   // content moves opposite to the finger
    }

    // MARK: Release velocity

    @Test func fastFlickVelocityMatchesNative() {
        let v = tracked(Self.fastFingers, lift: Self.fastLift)
        expectClose(v, Self.fastNativeVelocity, Self.fastNativeVelocity * 0.03, "fast flick")
    }

    @Test func mediumFlingVelocityMatchesNative() {
        let v = tracked(Self.mediumFingers, lift: Self.mediumLift)
        expectClose(v, Self.mediumNativeVelocity, Self.mediumNativeVelocity * 0.03, "medium fling")
    }

    /// Fling into the bottom edge (27.0 calibration run 4, ZTron lane): the lift is 16.6 ms after the newest sample.
    static let edgeFingers: [(TimeInterval, CGFloat)] = [(0.0, 607.67), (0.0167, 587.67), (0.0337, 563.33), (0.05, 537), (0.0668, 509.33), (0.0834, 481), (0.1002, 424), (0.1334, 396.33), (0.1499, 369.67), (0.1669, 345), (0.1835, 323.33), (0.2002, 307.67)]
    static let edgeLift: TimeInterval = 0.2168

    /// The estimator is unchanged by the release rule (BTN-s2, P1 + P2): the content velocity of the recorded flings
    /// is pinned to the pre-change values (a Python port of the estimator agrees to float noise).
    @Test(arguments: [(fastFingers, fastLift, CGFloat(3454.0055837361087)),
                      (mediumFingers, mediumLift, CGFloat(1344.148740801884)),
                      (edgeFingers, edgeLift, CGFloat(1335.207114878925))])
    func releaseVelocityCalibrationUnchanged(fingers: [(TimeInterval, CGFloat)], lift: TimeInterval, pinned: CGFloat) {
        let v = tracked(fingers, lift: lift)
        expectClose(v, pinned, pinned * 1e-6, "pinned release velocity")
    }

    @Test func slowDragHeldBeforeLiftReleasesAtRest() {
        // Rests by the gate (the finger's last 50 ms ran ≈ 160 pt/s < 250), not by the 0.5 s pause: the fit is non-zero.
        var tracker = VelocityTracker()
        for (t, y) in Self.slowFingers { tracker.add(position: y, at: t) }
        #expect(abs(tracker.gateVelocity) > 100 && abs(tracker.gateVelocity) < 250)
        #expect(tracker.ungatedVelocity(at: Self.slowLift) != 0)
        #expect(tracked(Self.slowFingers, lift: Self.slowLift) == 0)
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: 2280, velocity: 0, bounds: AxisBounds(min: 0, max: 5400)), at: 0)
        #expect(motion == .rest(position: 2280))
    }

    // MARK: Deceleration curve, distance, duration, stop rule

    @Test(arguments: [(fastDecay, fastDecayFit), (mediumDecay, mediumDecayFit)])
    func decayReproducesNativeCurve(samples: [(TimeInterval, CGFloat)],
                                    fit: (origin: CGFloat, velocity: CGFloat, end: CGFloat, duration: TimeInterval)) {
        let decay = Decay(origin: fit.origin, initialVelocity: fit.velocity, rate: .normal)
        let motion = AxisMotion.decay(decay, start: 0, handoff: nil)
        // 4 pt over a 3 s, 1700 pt motion (the fit's rms is 0.5 pt; the first frame carries the lift-time ambiguity).
        for (t, y) in samples {
            expectClose(motion.sample(at: t).position, y, 4, "t = \(t)")
        }
        // Distance ±5 %, duration ±10 %: native stops at |v| ≈ 10 pt/s and does not jump to the analytic rest.
        let traveled = motion.endPosition - fit.origin
        expectClose(traveled, fit.end - fit.origin, (fit.end - fit.origin) * 0.05, "distance")
        expectClose(CGFloat(decay.duration()), CGFloat(fit.duration), CGFloat(fit.duration) * 0.10, "duration")
        expectClose(motion.endPosition, fit.end, 3, "stop position")
        #expect(decay.restPosition - motion.endPosition > 3)     // the untraveled remainder is real (≈ 5 pt)
        let settled = motion.sample(at: decay.duration() + 0.001)
        #expect(settled.isSettled && settled.position == motion.endPosition)
    }

    // MARK: Rubber band and bounce-back

    @Test func rubberBandDisplacementMatchesNative() {
        // 200 pt finger travel past the top, 10 pt hysteresis → 190 pt overscroll shown as 89 pt (viewport 600).
        let rb = RubberBand(dimension: 600)
        expectClose(rb.displacement(forOverscroll: 190), 89, 89 * 0.02)
        expectClose(rb.overscroll(forDisplacement: 89), 190, 190 * 0.02)
    }

    @Test func bounceBackAfterAPauseReproducesNativeCurve() {
        let bounds = AxisBounds(min: 0, max: 5400)
        var tracker = VelocityTracker()
        for (t, y) in Self.topFingers { tracker.add(position: y, at: t) }
        // The 0.3 s pause does not zero the release (BTN-s2, P1) and the finger's last 50 ms ran ≈ 260 pt/s, above the
        // gate: the release velocity equals the last-motion fit (same samples in both windows, up to float noise).
        #expect(abs(tracker.gateVelocity) >= 250 && abs(tracker.gateVelocity) < 300)
        expectClose(tracker.velocity(at: Self.topLift), tracker.lastMotionVelocity, 1e-9, "release = last motion")
        let raw = -tracker.lastMotionVelocity                            // the spring-back seed
        // UIKit's own estimate runs ≈ 15 % above the 100 ms fit here (the XCUI drag slows over its last 100 ms):
        // B = −378 vs ours −299; the curves differ by at most ΔB/(ω·e) ≈ 2.7 pt.
        expectClose(raw, -378, 100, "last raw velocity")
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: -89, velocity: 0, bounds: bounds, rubberBandVelocity: raw), at: 0)
        guard case let .spring(spring, _) = motion else {
            Issue.record("expected a spring, got \(motion)")
            return
        }
        for (t, y) in Self.topBounce {
            expectClose(motion.sample(at: t).position, y, 3, "t = \(t)")
        }
        // Bounce-back duration ±15 % of the native 0.60 s; no overshoot past the edge.
        expectClose(CGFloat(spring.settlingTime()), 0.60, 0.60 * 0.15, "bounce-back duration")
        for t in stride(from: 0.0, through: 1.0, by: 0.005) {
            #expect(motion.sample(at: t).position <= 1e-6)
        }
        #expect(motion.willDecelerate)
    }

    // MARK: Edge hand-off

    @Test func smallOverscrollFirstMovesOutwardLikeNative() {
        // 2.67 pt shown after a 400 pt/s outward drag: native reaches −8 pt before returning (B fit −160 for the short
        // drag's lower velocity estimate); with the 400 pt/s velocity the bump is 2.67 + 400/(ω·e) ≈ 16 pt.
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: -2.67, velocity: 0, bounds: AxisBounds(min: 0, max: 5400),
                                                          rubberBandVelocity: -160), at: 0)
        let low = stride(from: 0.0, through: 0.6, by: 0.001).map { motion.sample(at: $0).position }.min()!
        expectClose(low, -8, 2, "outward bump")
        expectClose(motion.sample(at: 0.5).position, -0.4, 0.5)
    }

    @Test func edgeHandoffReproducesNativeOvershootAndSettle() {
        let spring = CriticalSpring(origin: 0, target: 0, initialVelocity: Self.edgeCrossingVelocity)
        let motion = AxisMotion.spring(spring, start: 0)
        let peak = stride(from: 0.0, through: 1.0, by: 0.001).map { motion.sample(at: $0).position }.max()!
        expectClose(peak, 39, 39 * 0.10, "edge overshoot")
        expectClose(CGFloat(spring.settlingTime()), 0.69, 0.69 * 0.15, "edge settle")
        // The crossing frame itself is ambiguous (±1 frame); compare from the first overshoot sample onward.
        let crossing = 0.0334 - 25.0 / Self.edgeCrossingVelocity   // ≈ when the edge was crossed inside that frame
        for (t, y) in Self.edgeBounce.dropFirst(2) {
            expectClose(motion.sample(at: t - crossing).position, y, 3, "t = \(t)")
        }
    }

    // MARK: programmatic zoom

    /// The native zoom animation is UIKit's ease-in-out over the measured duration (0.32 s at 2×, 0.40 s from 4× up),
    /// for setZoomScale in, back out, and zoom(to:); a critically damped spring cannot fit it (rms ≥ 0.09).
    @Test(arguments: [(zoomSet2, 1.0, 2.0), (zoomSet8, 1.0, 8.0), (zoomBackFrom8, 8.0, 1.0), (zoomRect8, 1.0, 8.0)])
    func programmaticZoomReproducesNativeEaseInOut(samples: [(TimeInterval, CGFloat)], from: CGFloat, to: CGFloat) {
        let timing = ZoomTiming(start: 0, duration: ZoomTiming.duration(from: from, to: to))
        var sum: CGFloat = 0, worstSpring: CGFloat = .infinity
        for (t, f) in samples { let d = timing.sample(at: t).progress - f; sum += d * d }
        let rms = (sum / CGFloat(samples.count)).squareRoot()
        #expect(rms < 0.012, "rms \(rms) over \(samples.count) frames, duration \(timing.duration)")
        #expect(timing.sample(at: samples[samples.count - 1].0 + 0.017).isSettled, "over within a frame of the last native change")
        for omega in stride(from: 5.0, through: 40.0, by: 0.5) {
            var e: CGFloat = 0
            for (t, f) in samples { let d = 1 - (1 + omega * t) * exp(-omega * t) - Double(f); e += CGFloat(d * d) }
            worstSpring = min(worstSpring, (e / CGFloat(samples.count)).squareRoot())
        }
        #expect(worstSpring > 0.08, "no critically damped spring fits native: best rms \(worstSpring)")
    }
}
