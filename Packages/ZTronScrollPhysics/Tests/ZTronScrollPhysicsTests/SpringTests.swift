import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct SpringTests {
    static let configurations: [CriticalSpring] = [
        CriticalSpring(origin: 0, target: 300),
        CriticalSpring(origin: 500, target: -20, initialVelocity: 4000),
        CriticalSpring(origin: 0, target: 0, initialVelocity: 2500),
        CriticalSpring(origin: -10, target: 0, initialVelocity: 1000, stiffness: 300),
        CriticalSpring(origin: 1000, target: 0, initialVelocity: -6000, stiffness: 50),
        CriticalSpring(origin: 0.2, target: 0, initialVelocity: 2),
    ]

    @Test(arguments: configurations)
    func startsAtOriginWithInitialVelocity(spring: CriticalSpring) {
        #expect(spring.position(at: 0) == spring.origin)
        expectClose(spring.velocity(at: 0), spring.initialVelocity, 1e-9)
        #expect(spring.position(at: -5) == spring.origin)
        #expect(spring.position(at: .infinity) == spring.target)
        #expect(spring.velocity(at: .infinity) == 0)
        // velocity(at:) is the derivative of position(at:).
        let h = 1e-6
        let numeric = (spring.position(at: 0.2 + h) - spring.position(at: 0.2 - h)) / CGFloat(2 * h)
        expectClose(numeric, spring.velocity(at: 0.2), 1e-3)
    }

    @Test(arguments: configurations)
    func settlesAtTarget(spring: CriticalSpring) {
        let T = spring.settlingTime()
        #expect(abs(spring.position(at: T) - spring.target) < 0.5)
        #expect(abs(spring.velocity(at: T)) < RestThresholds().velocity)
        #expect(spring.isSettled(at: T))
    }

    @Test func criticallyDampedNoOvershootWithoutVelocity() {
        let spring = CriticalSpring(origin: 0, target: 300)
        var previous = spring.position(at: 0)
        for t in grid(0.001, 3, count: 300) {
            let x = spring.position(at: TimeInterval(t))
            #expect(x <= 300)
            #expect(x > previous)
            previous = x
        }
    }

    @Test func overshootsThenReturnsWithVelocity() {
        // Edge bounce: starts on the target moving outward, peaks at t = 1/ω with v₀/(ω·e), returns without crossing.
        let bounce = CriticalSpring(origin: 0, target: 0, initialVelocity: 800)
        let omega = bounce.omega
        expectClose(bounce.position(at: TimeInterval(1 / omega)), 800 / (omega * CGFloat(M_E)), 1e-9)
        for t in grid(0.001, 3, count: 300) {
            #expect(bounce.position(at: TimeInterval(t)) > 0)
            #expect(bounce.position(at: TimeInterval(t)) <= 800 / (omega * CGFloat(M_E)) + 1e-9)
        }
        // Approaching with velocity toward the target: crosses exactly once, then returns.
        let overshoot = CriticalSpring(origin: -10, target: 0, initialVelocity: 1000)
        let samples = grid(0, 3, count: 600).map { overshoot.position(at: TimeInterval($0)) }
        let signChanges = zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        #expect(signChanges == 1)
        #expect(samples.max()! > 0)
    }

    @Test(arguments: configurations)
    func settlingTimeBracketsClosedForm(spring: CriticalSpring) {
        let T = spring.settlingTime()
        for t in grid(CGFloat(T), CGFloat(T) + 4, count: 400) {
            #expect(spring.isSettled(at: TimeInterval(t)), "unsettled at \(t) after T = \(T)")
        }
        if T > 0 {
            #expect(!spring.isSettled(at: T - 1e-6))
        } else {
            #expect(spring.isSettled(at: 0))
        }
    }

    @Test func stiffnessScalesSettlingTime() {
        let soft = CriticalSpring(origin: 0, target: 300, stiffness: 25).settlingTime()
        let normal = CriticalSpring(origin: 0, target: 300, stiffness: 100).settlingTime()
        let stiff = CriticalSpring(origin: 0, target: 300, stiffness: 400).settlingTime()
        #expect(soft > normal)
        #expect(normal > stiff)
        #expect(CriticalSpring(origin: 0, target: 0, stiffness: 400).omega == 20)
    }

    @Test func sampleAfterSettlingIsExactTarget() {
        let spring = CriticalSpring(origin: 13.37, target: 250.25, initialVelocity: -900)
        let motion = AxisMotion.spring(spring, start: 7)
        let T = spring.settlingTime()
        for time in [7 + T, 7 + T + 0.5, 1e9, .infinity] {
            let sample = motion.sample(at: time)
            #expect(sample.isSettled)
            #expect(sample.position == 250.25)
            #expect(sample.velocity == 0)
        }
        #expect(!motion.sample(at: 7 + T * 0.5).isSettled)
        #expect(motion.sample(at: 0).position == 13.37)                         // before start → start state
    }

    @Test func nonFiniteInputsFallBack() {
        let spring = CriticalSpring(origin: .nan, target: .infinity, initialVelocity: .nan, stiffness: .nan)
        #expect(spring.origin == 0 && spring.target == 0 && spring.initialVelocity == 0)
        #expect(spring.stiffness == CriticalSpring.defaultStiffness)
        #expect(CriticalSpring(origin: 0, target: 1, stiffness: -4).omega == CriticalSpring.defaultStiffness.squareRoot())
        #expect(spring.settlingTime() == 0)
    }
}
