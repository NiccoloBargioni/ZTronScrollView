import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct DecayTests {
    /// SPEC S6 formula written independently: x(t) = x₀ + v₀·(r^(1000t) − 1)/(1000·ln r).
    private func specPosition(_ x0: CGFloat, _ v0: CGFloat, _ r: CGFloat, _ t: CGFloat) -> CGFloat {
        x0 + v0 * (pow(r, 1000 * t) - 1) / (1000 * log(r))
    }

    @Test(arguments: [DecelerationRate.normal, .fast])
    func positionMatchesClosedForm(rate: DecelerationRate) {
        let decay = Decay(origin: 100, initialVelocity: 2000, rate: rate)
        for t in [0.0, 0.1, 1.0] {
            expectClose(decay.position(at: t), specPosition(100, 2000, rate.perMillisecond, CGFloat(t)), 1e-9)
        }
        #expect(decay.position(at: 0) == 100)
    }

    @Test(arguments: [DecelerationRate.normal, .fast])
    func restPointEqualsFormula(rate: DecelerationRate) {
        for v0 in [-3000.0, -50.0, 50.0, 3000.0] as [CGFloat] {
            let decay = Decay(origin: -40, initialVelocity: v0, rate: rate)
            let expected = -40 - v0 / (1000 * log(rate.perMillisecond))
            expectClose(decay.restPosition, expected, 1e-9)
            expectClose(decay.restDisplacement, expected + 40, 1e-9)
            expectClose(decay.position(at: 1_000), expected, 1e-9)
            #expect(decay.position(at: .infinity) == decay.restPosition)
        }
    }

    @Test func velocityDecays() {
        let decay = Decay(origin: 0, initialVelocity: -2500)
        #expect(decay.velocity(at: 0) == -2500)
        var previous = abs(decay.velocity(at: 0))
        for t in grid(0.01, 5, count: 200) {
            let v = decay.velocity(at: TimeInterval(t))
            #expect(v < 0)
            #expect(abs(v) < previous)
            previous = abs(v)
        }
        // velocity(at:) is the derivative of position(at:).
        let h = 1e-6
        let numeric = (decay.position(at: 0.3 + h) - decay.position(at: 0.3 - h)) / CGFloat(2 * h)
        expectClose(numeric, decay.velocity(at: 0.3), 1e-3)
        #expect(decay.velocity(at: .infinity) == 0)
    }

    @Test func zeroVelocityStaysAtOrigin() {
        let decay = Decay(origin: 321, initialVelocity: 0)
        for t in [0.0, 0.5, 10, .infinity] {
            #expect(decay.position(at: t) == 321)
            #expect(decay.velocity(at: t) == 0)
        }
        #expect(decay.restPosition == 321)
        #expect(decay.duration() == 0)
        #expect(decay.time(toReach: 321) == 0)
        #expect(decay.time(toReach: 322) == nil)
    }

    @Test(arguments: [1800.0, -1800.0] as [CGFloat])
    func timeToReachInvertsPosition(v0: CGFloat) throws {
        let decay = Decay(origin: 50, initialVelocity: v0)
        let rest = decay.restPosition
        for f in grid(0, 0.999, count: 50) {
            let x = 50 + (rest - 50) * f
            let t = try #require(decay.time(toReach: x))
            #expect(t >= 0)
            expectClose(decay.position(at: t), x, 1e-6)
        }
        #expect(decay.time(toReach: rest) == nil)                         // reached only at t = ∞
        #expect(decay.time(toReach: rest + v0.signum * 10) == nil)        // beyond rest
        #expect(decay.time(toReach: 50 - v0.signum * 10) == nil)          // wrong side
        #expect(decay.time(toReach: .nan) == nil)
    }

    @Test(arguments: [DecelerationRate.normal, .fast])
    func durationEndsBelowThresholds(rate: DecelerationRate) {
        let thresholds = RestThresholds()
        // Natural fling: ends when |v| < velocity threshold, where it is (UIKit leaves ≈ v/|k| of the rest untraveled).
        let decay = Decay(origin: 0, initialVelocity: 4000, rate: rate)
        let T = decay.duration(thresholds: thresholds)
        #expect(T > 0)
        func slow(_ t: TimeInterval) -> Bool { abs(decay.velocity(at: t)) <= thresholds.velocity * (1 + 1e-9) }
        #expect(slow(T))
        #expect(!slow(T * 0.99))
        #expect(decay.stopPosition(thresholds: thresholds) == decay.position(at: T))
        expectClose(decay.restPosition - decay.stopPosition(thresholds: thresholds), thresholds.velocity / abs(rate.k), 1e-6)
        #expect(Decay(origin: 0, initialVelocity: 1, rate: rate).duration(thresholds: thresholds) == 0)
        // Re-solved decay: also waits for the remaining distance and ends exactly on the rest point.
        let exact = Decay(origin: 0, initialVelocity: 4000, rate: rate, landsOnRestPosition: true)
        let Te = exact.duration(thresholds: thresholds)
        #expect(Te >= T)
        #expect(abs(exact.velocity(at: Te)) <= thresholds.velocity * (1 + 1e-9))
        #expect(abs(exact.restPosition - exact.position(at: Te)) <= thresholds.distance * (1 + 1e-9))
        #expect(exact.stopPosition(thresholds: thresholds) == exact.restPosition)
    }

    @Test func nonFiniteInputsAreZeroed() {
        let decay = Decay(origin: .nan, initialVelocity: .infinity)
        #expect(decay.origin == 0)
        #expect(decay.initialVelocity == 0)
        #expect(decay.position(at: 1) == 0)

        let moving = Decay(origin: 10, initialVelocity: 500)
        #expect(moving.position(at: .nan) == 10)
        #expect(moving.position(at: -1) == 10)
        #expect(moving.velocity(at: -1) == 500)
        #expect(moving.time(toSlowTo: .nan) == .infinity)
        #expect(moving.time(toSlowTo: 0) == .infinity)
        #expect(moving.time(toSlowTo: 600) == 0)
    }

    @Test func rateOutsideOpenIntervalIsClamped() {
        #expect(DecelerationRate(perMillisecond: 1).perMillisecond == 0.9999)
        #expect(DecelerationRate(perMillisecond: 1.5).perMillisecond == 0.9999)
        #expect(DecelerationRate(perMillisecond: 0).perMillisecond == 0.5)
        #expect(DecelerationRate(perMillisecond: -3).perMillisecond == 0.5)
        #expect(DecelerationRate(perMillisecond: .nan).perMillisecond == 0.998)
        #expect(DecelerationRate(perMillisecond: .infinity).perMillisecond == 0.998)
        var rate = DecelerationRate.normal
        rate.perMillisecond = 2
        #expect(rate.perMillisecond == 0.9999)
        for r in [0, 1, 7, -1] as [CGFloat] {
            let k = DecelerationRate(perMillisecond: r).k
            #expect(k.isFinite && k < 0)
        }
        #expect(DecelerationRate.normal.perMillisecond == 0.998)
        #expect(DecelerationRate.fast.perMillisecond == 0.99)
    }

    @Test func fastRateStopsSooner() {
        let normal = Decay(origin: 0, initialVelocity: 3000, rate: .normal)
        let fast = Decay(origin: 0, initialVelocity: 3000, rate: .fast)
        #expect(fast.restDisplacement < normal.restDisplacement)
        #expect(fast.duration() < normal.duration())
    }

    @Test func pointsPerMillisecondConversion() {
        #expect(Velocity.pointsPerMillisecond(1500) == 1.5)
        #expect(Velocity.pointsPerMillisecond(-250) == -0.25)
        #expect(Velocity.pointsPerSecond(fromPerMillisecond: 1.5) == 1500)
        expectClose(Velocity.pointsPerSecond(fromPerMillisecond: Velocity.pointsPerMillisecond(1234.5)), 1234.5, 1e-9)
        #expect(Velocity.pointsPerMillisecond(.nan) == 0)
        #expect(Velocity.pointsPerSecond(fromPerMillisecond: -.infinity) == 0)
    }
}

@Suite struct RetargetTests {
    @Test(arguments: [(-800, -2000), (-1, -20.1), (1, 20.1), (800, 2000)] as [(CGFloat, CGFloat)])
    func retargetedDecayLandsExactly(delta: CGFloat, v0: CGFloat) throws {
        let origin: CGFloat = 300
        let target = origin + delta
        let decay = try #require(Decay.retargeted(origin: origin, initialVelocity: v0, target: target))
        #expect(abs(decay.restPosition - target) < 1e-6)
        #expect(decay.velocity(at: 0) == v0)                                   // velocity continuous at release
        #expect(DecelerationRate.plausibleRange.contains(decay.rate.perMillisecond))
        let motion = AxisMotion.decay(decay, start: 2, handoff: nil)
        let settled = motion.sample(at: 2 + decay.duration() + 0.01)
        #expect(settled.isSettled)
        #expect(abs(settled.position - target) < 1e-6)
    }

    @Test func retargetNilWhenDirectionDisagrees() {
        #expect(Decay.retargeted(origin: 0, initialVelocity: -1000, target: 500) == nil)
        #expect(Decay.retargeted(origin: 0, initialVelocity: 1000, target: -500) == nil)
    }

    @Test func retargetNilWhenDeltaZero() {
        #expect(Decay.retargeted(origin: 120, initialVelocity: 1000, target: 120) == nil)
    }

    @Test func retargetNilWhenVelocityNegligible() {
        // r′ = exp(−10/5000) ≈ 0.998 would be plausible, but 10 pt/s < negligibleReleaseVelocity (20).
        #expect(Decay.retargeted(origin: 0, initialVelocity: 10, target: 5) == nil)
        #expect(Decay.retargeted(origin: 0, initialVelocity: 10, target: 5,
                                 thresholds: RestThresholds(negligibleReleaseVelocity: 5)) != nil)
    }

    @Test func retargetNilWhenRateImplausible() {
        #expect(Decay.retargeted(origin: 0, initialVelocity: 1000, target: 1) == nil)       // r′ = e⁻¹
        #expect(Decay.retargeted(origin: 0, initialVelocity: 25, target: 100_000) == nil)   // r′ ≈ 0.99999975
        #expect(Decay.retargeted(origin: .nan, initialVelocity: 1000, target: 400) == nil)
    }

    @Test func releaseSolverUsesSpringWhenRetargetNil() throws {
        let ctx = ReleaseContext(origin: 500, velocity: 1500, bounds: AxisBounds(min: 0, max: 2000), target: 200)
        let motion = ReleaseSolver.resolve(ctx, at: 3)
        guard case let .spring(spring, start) = motion else {
            Issue.record("expected a spring, got \(motion)")
            return
        }
        #expect(start == 3)
        #expect(spring.target == 200)
        #expect(spring.initialVelocity == 1500)
        let first = motion.sample(at: 3)
        #expect(first.position == 500)
        expectClose(first.velocity, 1500, 1e-9)
        let end = motion.sample(at: 3 + spring.settlingTime() + 1e-3)
        #expect(end.isSettled)
        #expect(end.position == 200)
        #expect(end.velocity == 0)
        #expect(motion.endPosition == 200)
    }

    @Test func releaseSolverRetargetsWhenPlausible() throws {
        let ctx = ReleaseContext(origin: 0, velocity: 2000, bounds: AxisBounds(min: 0, max: 5000), target: 800)
        let motion = ReleaseSolver.resolve(ctx, at: 0)
        guard case let .decay(decay, _, handoff) = motion else {
            Issue.record("expected a decay, got \(motion)")
            return
        }
        #expect(handoff == nil)
        #expect(abs(decay.restPosition - 800) < 1e-6)
        #expect(motion.sample(at: 100).position == decay.restPosition)
        // A target outside bounds is clamped first.
        let clampedCtx = ReleaseContext(origin: 0, velocity: 2000, bounds: AxisBounds(min: 0, max: 600), target: 800)
        expectClose(ReleaseSolver.resolve(clampedCtx, at: 0).endPosition, 600, 1e-6)
    }
}
