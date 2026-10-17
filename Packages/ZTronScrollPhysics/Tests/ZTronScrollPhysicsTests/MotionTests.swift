import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct BounceResolutionTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var behavior: BounceBehavior
        var bounces: Bool
        var alwaysBounce: Bool
        var isScrollable: Bool
        var isAxisEnabled: Bool
        var expected: Bool
        var testDescription: String {
            "\(behavior) bounces=\(bounces) always=\(alwaysBounce) scrollable=\(isScrollable) enabled=\(isAxisEnabled) → \(expected)"
        }
    }

    /// Expected results for `bounces == true`, indexed by (alwaysBounce, isScrollable, isAxisEnabled) as a 3-bit
    /// number: FFF, FFT, FTF, FTT, TFF, TFT, TTF, TTT. With `bounces == false` every row is `false`.
    static let table: [(BounceBehavior, [Bool])] = [
        (.always,      [true,  true,  true,  true,  true,  true,  true,  true]),
        (.basedOnSize, [false, false, true,  true,  true,  true,  true,  true]),
        (.automatic,   [false, true,  false, true,  true,  true,  true,  true]),
    ]

    static let rows: [Row] = table.flatMap { behavior, expected in
        (0..<16).map { bits in
            let bounces = bits & 8 != 0
            let index = bits & 7
            return Row(behavior: behavior, bounces: bounces, alwaysBounce: index & 4 != 0,
                       isScrollable: index & 2 != 0, isAxisEnabled: index & 1 != 0,
                       expected: bounces && expected[index])
        }
    }

    @Test(arguments: rows)
    func truthTable(row: Row) {
        let configuration = BounceConfiguration(behavior: row.behavior, bounces: row.bounces, alwaysBounce: row.alwaysBounce)
        #expect(configuration.resolve(isAxisEnabled: row.isAxisEnabled, isScrollable: row.isScrollable) == row.expected)
    }

    @Test func bouncesFalseWinsOverAlways() {
        let configuration = BounceConfiguration(behavior: .always, bounces: false, alwaysBounce: true)
        #expect(!configuration.resolve(isAxisEnabled: true, isScrollable: true))
    }

    @Test func automaticBouncesOnEnabledAxisEvenWhenContentFits() {
        #expect(BounceConfiguration().resolve(isAxisEnabled: true, isScrollable: false))
        #expect(!BounceConfiguration(behavior: .basedOnSize).resolve(isAxisEnabled: true, isScrollable: false))
    }
}

@Suite struct EdgeHandoffTests {
    let bounds = AxisBounds(min: 0, max: 1000)

    /// A release whose decay rest point lies past an edge, in both directions (exercises the crossing-time solve with
    /// negative `Δ` / `v₀` and the edge choice).
    struct Crossing: Sendable, CustomTestStringConvertible {
        var origin: CGFloat
        var velocity: CGFloat
        var edge: CGFloat
        /// `+1` when crossing `max` (positive velocity), `−1` when crossing `min`.
        var direction: CGFloat { velocity.signum }
        var testDescription: String { "origin \(origin) v \(velocity) → edge \(edge)" }
    }

    static let crossings = [Crossing(origin: 800, velocity: 3000, edge: 1000),
                            Crossing(origin: 200, velocity: -3000, edge: 0)]

    private func crossingMotion(_ crossing: Crossing, bounces: Bool, start: TimeInterval = 10) throws
        -> (decay: Decay, start: TimeInterval, handoff: AxisMotion.EdgeHandoff, motion: AxisMotion) {
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: crossing.origin, velocity: crossing.velocity,
                                                          bounds: bounds, bounces: bounces),
                                           at: start)
        guard case let .decay(decay, s, handoff?) = motion else {
            throw TestFailure(description: "expected a decay with handoff, got \(motion)")
        }
        return (decay, s, handoff, motion)
    }

    struct TestFailure: Error, CustomStringConvertible { var description: String }

    @Test(arguments: crossings)
    func decayCrossingTimeMatchesPosition(crossing: Crossing) throws {
        let (decay, start, handoff, _) = try crossingMotion(crossing, bounces: true)
        #expect((decay.restPosition - crossing.edge) * crossing.direction > 0)      // rest point past the edge
        #expect(handoff.edge == crossing.edge)
        #expect(handoff.crossingTime > start)
        expectClose(decay.position(at: handoff.crossingTime - start), crossing.edge, 1e-6)
        #expect((decay.position(at: handoff.crossingTime - start - 0.01) - crossing.edge) * crossing.direction < 0)
    }

    @Test(arguments: crossings)
    func handoffSpringStartsAtEdgeWithDecayVelocity(crossing: Crossing) throws {
        let (decay, start, handoff, motion) = try crossingMotion(crossing, bounces: true)
        let tc = handoff.crossingTime
        let atCrossing = motion.sample(at: tc)
        #expect(atCrossing.position == crossing.edge)
        let decayVelocity = decay.velocity(at: tc - start)
        #expect(decayVelocity * crossing.direction > 0)                             // still moving outward
        expectClose(atCrossing.velocity, decayVelocity, 1e-9)                   // C¹: velocity carried over
        let spring = AxisMotion.handoffSpring(decay, start: start, handoff: handoff)
        #expect(spring.origin == crossing.edge && spring.target == crossing.edge)
        #expect(spring.initialVelocity == decayVelocity)
        let eps = 1e-5
        let before = motion.sample(at: tc - eps), after = motion.sample(at: tc + eps)
        expectClose(before.position, after.position, 0.1)
        expectClose(before.velocity, after.velocity, 1)
    }

    @Test(arguments: crossings)
    func noBounceStopsAtEdge(crossing: Crossing) throws {
        let (_, _, handoff, motion) = try crossingMotion(crossing, bounces: false)
        #expect(!handoff.bounces)
        #expect(handoff.edge == crossing.edge)
        #expect(motion.endPosition == crossing.edge)
        #expect((motion.sample(at: handoff.crossingTime - 0.01).position - crossing.edge) * crossing.direction < 0)
        let stop = motion.sample(at: handoff.crossingTime)
        #expect(stop == AxisMotion.Sample(position: crossing.edge, velocity: 0, isSettled: true))
        #expect(motion.sample(at: handoff.crossingTime + 5).position == crossing.edge)
    }

    @Test(arguments: crossings)
    func bounceReturnsToEdge(crossing: Crossing) throws {
        let (decay, start, handoff, motion) = try crossingMotion(crossing, bounces: true)
        let spring = AxisMotion.handoffSpring(decay, start: start, handoff: handoff)
        let peak = abs(spring.initialVelocity) / (spring.omega * CGFloat(M_E))
        // Signed overscroll past the crossed edge (positive = outside the bounds).
        let outside = grid(0.001, 1.5, count: 300).map {
            (motion.sample(at: handoff.crossingTime + TimeInterval($0)).position - crossing.edge) * crossing.direction
        }
        #expect(outside.allSatisfy { $0 >= 0 })                                     // never comes back inside early
        #expect(outside.max()! > 0)
        #expect(outside.max()! <= peak + 1e-9)
        let end = motion.sample(at: handoff.crossingTime + spring.settlingTime())
        #expect(end == AxisMotion.Sample(position: crossing.edge, velocity: 0, isSettled: true))
        #expect(motion.endPosition == crossing.edge)
    }

    @Test func restInsideBoundsHasNoHandoff() {
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: 100, velocity: 500, bounds: bounds), at: 0)
        guard case let .decay(decay, _, handoff) = motion else {
            Issue.record("expected a decay, got \(motion)")
            return
        }
        #expect(handoff == nil)
        #expect(decay.restPosition < 1000)
        #expect(motion.endPosition == decay.restPosition)
    }

    @Test func releaseAtEdgeMovingOutBouncesImmediately() {
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: 0, velocity: -900, bounds: bounds), at: 4)
        guard case let .decay(_, _, handoff?) = motion else {
            Issue.record("expected a decay with handoff, got \(motion)")
            return
        }
        #expect(handoff.crossingTime == 4)
        #expect(handoff.edge == 0)
        #expect(motion.sample(at: 4.05).position < 0)
    }

    @Test(arguments: [(-60, -300), (1080, 400), (1080, -2000)] as [(CGFloat, CGFloat)])
    func releaseOutOfBoundsSpringsBack(origin: CGFloat, velocity: CGFloat) {
        let ctx = ReleaseContext(origin: origin, velocity: velocity, bounds: bounds, target: 500)
        let motion = ReleaseSolver.resolve(ctx, at: 1)
        guard case let .spring(spring, start) = motion else {
            Issue.record("expected a spring, got \(motion)")
            return
        }
        #expect(start == 1)
        #expect(spring.target == bounds.clamped(origin))                       // nearest edge, target ignored
        #expect(spring.initialVelocity == velocity)                             // seeded with the release velocity
        #expect(motion.willDecelerate)                                          // UIKit: willDecelerate == true
        let end = motion.sample(at: 1 + spring.settlingTime())
        #expect(end.isSettled && end.position == bounds.clamped(origin))
    }
}

@Suite struct ProgrammaticAnimationTests {
    @Test(arguments: [0.3, 0.5, 1.0] as [TimeInterval])
    func animatedSettlesNearDuration(duration: TimeInterval) {
        let motion = ReleaseSolver.animated(from: 0, velocity: 0, to: 600, duration: duration, at: 2)
        guard case let .spring(spring, start) = motion else {
            Issue.record("expected a spring, got \(motion)")
            return
        }
        #expect(start == 2)
        expectClose(CGFloat(spring.settlingTime()), CGFloat(duration), CGFloat(duration) * 0.01)
        #expect(motion.sample(at: 2 + duration * 1.02).position == 600)
    }

    @Test func retargetingPreservesVelocity() {
        let motion = ReleaseSolver.animated(from: 100, velocity: -1200, to: 900, duration: 0.3, at: 0)
        let first = motion.sample(at: 0)
        #expect(first.position == 100)
        expectClose(first.velocity, -1200, 1e-6)
        #expect(motion.endPosition == 900)
    }

    @Test func degenerateAnimationsRest() {
        #expect(ReleaseSolver.animated(from: 0, velocity: 0, to: 50, duration: 0, at: 0) == .rest(position: 50))
        #expect(ReleaseSolver.animated(from: 0, velocity: 0, to: 50, duration: .nan, at: 0) == .rest(position: 50))
        #expect(ReleaseSolver.animated(from: 50, velocity: 0, to: 50, duration: 0.3, at: 0) == .rest(position: 50))
        #expect(!AxisMotion.rest(position: 1).willDecelerate)
    }
}

/// The target-path spring fallback (`ReleaseSolver.targetSpring`): never passes a snap target, never leaves the bounds
/// without bounce, and keeps the release velocity whenever that is possible.
@Suite struct TargetSpringTests {
    /// Positions of `motion` every 0.5 ms until it settles (closed forms, so dense sampling stays cheap), plus the
    /// analytic extremum of a spring (`t* = 1/ω − A/B`) so a peak between two samples is not missed, plus the end.
    private func positions(of motion: AxisMotion, start: TimeInterval) -> [CGFloat] {
        func dense(until end: TimeInterval, _ x: (TimeInterval) -> CGFloat) -> [CGFloat] {
            let count = Int((Swift.min(end, 4) / 0.0005).rounded(.up))
            return (0...count).map { x(TimeInterval($0) * 0.0005) }
        }
        switch motion {
        case let .rest(position):
            return [position]
        case let .spring(spring, _):
            var result = dense(until: spring.settlingTime()) { spring.position(at: $0) }
            let a = spring.origin - spring.target, b = spring.initialVelocity + spring.omega * a
            if b != 0 {
                let tStar = 1 / spring.omega - a / b
                if tStar > 0 { result.append(spring.position(at: TimeInterval(tStar))) }
            }
            return result + [motion.sample(at: .infinity).position]
        case let .decay(decay, _, nil):
            return dense(until: decay.duration()) { decay.position(at: $0) } + [motion.sample(at: .infinity).position]
        case .decay:
            return dense(until: 4) { motion.sample(at: start + $0).position }
        }
    }

    @Test func towardTargetSpringIsTheSoftestWithoutOvershoot() throws {
        // Reviewer case: r′ = exp(−3000/50 000) ≈ 0.94 is implausible → spring; ω = 3000/50 = 60.
        let bounds = AxisBounds(min: 0, max: 1000)
        let motion = ReleaseSolver.resolve(ReleaseContext(origin: 950, velocity: 3000, bounds: bounds, bounces: false,
                                                          target: 1000), at: 2)
        guard case let .spring(spring, start) = motion else {
            Issue.record("expected a spring, got \(motion)")
            return
        }
        #expect(start == 2)
        #expect(spring.initialVelocity == 3000)                                  // C¹ at release
        expectClose(spring.omega, 60, 1e-9)
        let xs = positions(of: motion, start: 2)
        #expect(xs.max()! <= 1000 + 1e-9)
        #expect(xs.min()! >= 950 - 1e-9)
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })            // monotone approach
        #expect(motion.sample(at: 2 + spring.settlingTime()) == AxisMotion.Sample(position: 1000, velocity: 0,
                                                                                  isSettled: true))
        // When the default spring already cannot overshoot (|v₀/Δ| ≤ ω₀ = 10), it is kept unchanged.
        let gentle = ReleaseSolver.targetSpring(origin: 0, target: 800, velocity: 50, bounds: AxisBounds(min: 0, max: 5000),
                                                bounces: true)
        #expect(gentle.stiffness == CriticalSpring.defaultStiffness)
    }

    @Test func targetSpringNeverExitsBoundsWithoutBounce() {
        var rng = SplitMix64(seed: 0xB0_0D5)
        let bounds = AxisBounds(min: 0, max: 1000)
        var springs = 0
        for trial in 0..<300 {
            let origin = CGFloat.random(in: 0...1000, using: &rng)
            let velocity = CGFloat.random(in: -12_000...12_000, using: &rng)
            // Mix far targets with targets near the origin and at the edges.
            let candidates: [CGFloat] = [.random(in: -200...1200, using: &rng), origin + .random(in: -60...60, using: &rng),
                                         0, 1000, origin]
            let rawTarget = candidates[trial % candidates.count]
            let motion = ReleaseSolver.resolve(ReleaseContext(origin: origin, velocity: velocity, bounds: bounds,
                                                              bounces: false, target: rawTarget), at: 1)
            if case .spring = motion { springs += 1 }
            let target = bounds.clamped(rawTarget)
            let xs = positions(of: motion, start: 1)
            #expect(xs.allSatisfy { $0 >= bounds.min - 1e-9 && $0 <= bounds.max + 1e-9 },
                    "trial \(trial): origin \(origin) v \(velocity) target \(target) → \(xs.min()!)…\(xs.max()!)")
            // Never passes the target coming from the origin side.
            if target != origin {
                let side = (origin - target).signum
                #expect(xs.allSatisfy { ($0 - target) * side >= -1e-9 }, "trial \(trial) overshot \(target)")
            }
            expectClose(motion.endPosition, target, 1e-6)
            expectClose(motion.sample(at: .infinity).position, target, 1e-6)
        }
        #expect(springs > 100)                                                     // the spring path is exercised
    }

    @Test func awayFromTargetWithoutBounceMeetsTheWall() {
        let bounds = AxisBounds(min: 0, max: 1000)
        // Moving toward max at 3000 pt/s with only 10 pt of room, target behind: the outward speed is reduced.
        let wall = ReleaseSolver.targetSpring(origin: 990, target: 500, velocity: 3000, bounds: bounds, bounces: false)
        #expect(wall.initialVelocity > 0 && wall.initialVelocity < 3000)
        let motion = AxisMotion.spring(wall, start: 0)
        let xs = positions(of: motion, start: 0)
        #expect(xs.max()! <= 1000 + 1e-9)
        #expect(xs.max()! > 999.9)                                                 // uses (almost) all the room
        // Negative direction, and Δ = 0 ("stop here" target): same rule.
        let low = ReleaseSolver.targetSpring(origin: 5, target: 400, velocity: -2000, bounds: bounds, bounces: false)
        #expect(positions(of: .spring(low, start: 0), start: 0).min()! >= -1e-9)
        let here = ReleaseSolver.targetSpring(origin: 997, target: 997, velocity: 2500, bounds: bounds, bounces: false)
        #expect(positions(of: .spring(here, start: 0), start: 0).max()! <= 1000 + 1e-9)
        // With bounce the release velocity is kept (an excursion past the edge is a bounce) ...
        let bouncing = ReleaseSolver.targetSpring(origin: 990, target: 500, velocity: 3000, bounds: bounds, bounces: true)
        #expect(bouncing.initialVelocity == 3000 && bouncing.stiffness == CriticalSpring.defaultStiffness)
        // ... and so it is without bounce when the excursion fits.
        let roomy = ReleaseSolver.targetSpring(origin: 500, target: 200, velocity: 1500, bounds: bounds, bounces: false)
        #expect(roomy.initialVelocity == 1500)
    }

    struct PagingCase: Sendable, CustomTestStringConvertible {
        var originPages: CGFloat
        var velocity: CGFloat
        var testDescription: String { "origin \(originPages)p v \(velocity)" }
    }

    /// Reviewer cases (3.1p @ 8000, 3.9p @ 2000, 3.95p @ 1000 used to overshoot by 23–76 pt) plus a grid, both ways.
    static let pagingCases: [PagingCase] = {
        var cases = [PagingCase(originPages: 3.1, velocity: 8000), PagingCase(originPages: 3.9, velocity: 2000),
                     PagingCase(originPages: 3.95, velocity: 1000), PagingCase(originPages: 3.5, velocity: 1500)]
        for p in [3.02, 3.25, 3.5, 3.75, 3.99] as [CGFloat] {
            for v in [301, 600, 1200, 2500, 5000, 12_000] as [CGFloat] {
                cases.append(PagingCase(originPages: p, velocity: v))
                cases.append(PagingCase(originPages: p, velocity: -v))
            }
        }
        return cases
    }()

    @Test(arguments: pagingCases)
    func pagingTargetIsNeverOvershot(paging: PagingCase) {
        let page: CGFloat = 390
        let bounds = AxisBounds(min: 0, max: page * 9)
        let origin = paging.originPages * page
        let dragStart = (paging.velocity > 0 ? 3 : 4) * page
        let target = PagingSolver.target(current: origin, dragStart: dragStart, velocity: paging.velocity,
                                         pageLength: page, bounds: bounds)
        #expect((target - origin) * paging.velocity > 0)                          // a flick toward the next boundary
        for bounces in [true, false] {
            let motion = ReleaseSolver.resolve(ReleaseContext(origin: origin, velocity: paging.velocity, bounds: bounds,
                                                              bounces: bounces, target: target), at: 0)
            let direction = paging.velocity.signum
            let xs = positions(of: motion, start: 0)
            #expect(xs.allSatisfy { ($0 - target) * direction <= 1e-9 },
                    "overshot \(target) by \(xs.map { ($0 - target) * direction }.max()!) pt (\(motion))")
            #expect(xs.allSatisfy { ($0 - origin) * direction >= -1e-9 })          // never moves backwards
            expectClose(motion.sample(at: 0).velocity, paging.velocity, 1e-9)       // seeded with v₀
            expectClose(motion.endPosition, target, 1e-6)
        }
    }
}

/// Absolute clocks: a sample at exactly `start + settlingTime` settles for `Date`-scale and uptime-scale starts.
@Suite struct AbsoluteClockTests {
    /// Uptime (~1.2e5 s), `timeIntervalSinceReferenceDate` (~8.1e8 s) and Unix-epoch (~1.76e9 s) magnitudes.
    static let bases: [TimeInterval] = [123_456.789, 8.13e8 + 0.123, 1_760_000_000.123]

    private func starts(from base: TimeInterval) -> [TimeInterval] {
        (0..<500).map { base + TimeInterval($0) * 0.008_333_3 }
    }

    @Test(arguments: bases)
    func decayAndSpringSettleAtStartPlusSettlingTime(base: TimeInterval) {
        let decay = Decay(origin: 10, initialVelocity: 1700)
        let spring = CriticalSpring(origin: 13.37, target: 250.25, initialVelocity: -900)
        let td = decay.duration(), ts = spring.settlingTime()
        var unsettled = 0
        for start in starts(from: base) {
            let d = AxisMotion.decay(decay, start: start, handoff: nil).sample(at: start + td)
            let s = AxisMotion.spring(spring, start: start).sample(at: start + ts)
            if d != AxisMotion.Sample(position: decay.restPosition, velocity: 0, isSettled: true) { unsettled += 1 }
            if s != AxisMotion.Sample(position: 250.25, velocity: 0, isSettled: true) { unsettled += 1 }
            // The slack is a few ulps, not a frame: 1 ms early is still moving.
            #expect(!AxisMotion.spring(spring, start: start).sample(at: start + ts - 0.001).isSettled)
        }
        #expect(unsettled == 0)
    }

    @Test(arguments: bases)
    func handoffBounceSettlesAtCrossingPlusSettlingTime(base: TimeInterval) throws {
        let bounds = AxisBounds(min: 0, max: 1000)
        var unsettled = 0
        for start in starts(from: base).prefix(100) {
            let motion = ReleaseSolver.resolve(ReleaseContext(origin: 800, velocity: 3000, bounds: bounds), at: start)
            guard case let .decay(decay, s, handoff?) = motion else {
                Issue.record("expected a handoff, got \(motion)")
                return
            }
            let spring = AxisMotion.handoffSpring(decay, start: s, handoff: handoff)
            let end = motion.sample(at: handoff.crossingTime + spring.settlingTime())
            if end != AxisMotion.Sample(position: 1000, velocity: 0, isSettled: true) { unsettled += 1 }
        }
        #expect(unsettled == 0)
    }

    @Test(arguments: bases)
    func zoomBounceSettlesAtStartPlusSettlingTime(base: TimeInterval) {
        let geometry = ZoomGeometry(viewportSize: CGSize(width: 390, height: 844),
                                    unscaledContentSize: CGSize(width: 1200, height: 1800))
        let reference = ZoomSolver.bounceBack(from: 3.6, limits: 0.5...3, lastCentroid: CGPoint(x: 195, y: 420),
                                              offset: CGPoint(x: 1500, y: 2400), geometry: geometry, at: 0)
        let settle = reference.settlingTime(geometry: geometry)
        expectClose(CGFloat(settle), CGFloat(settlingTime(of: reference, geometry: geometry)), 1e-8)  // first settled
        var unsettled = 0
        for start in starts(from: base).prefix(100) {
            let motion = ZoomSolver.bounceBack(from: 3.6, limits: 0.5...3, lastCentroid: CGPoint(x: 195, y: 420),
                                               offset: CGPoint(x: 1500, y: 2400), geometry: geometry, at: start)
            let sample = motion.sample(at: start + settle, geometry: geometry)
            if !sample.isSettled || sample.scale != 3 { unsettled += 1 }
        }
        #expect(unsettled == 0)
    }
}

/// Elapsed time at which `motion` first reports settled (bisection on the monotone `isSettled` flag), relative to
/// `motion.start`. Independent of `ZoomMotion.settlingTime`, against which it is cross-checked.
func settlingTime(of motion: ZoomMotion, geometry: ZoomGeometry, thresholds: RestThresholds = .init()) -> TimeInterval {
    var lo: TimeInterval = 0, hi: TimeInterval = 60
    for _ in 0..<80 {
        let mid = (lo + hi) / 2
        if motion.sample(at: motion.start + mid, geometry: geometry, thresholds: thresholds).isSettled {
            hi = mid
        } else {
            lo = mid
        }
    }
    return hi
}

@Suite struct ModuleTests {
    /// The module has no type named `ZTronScrollPhysics`, so module-qualified names disambiguate (a same-named type
    /// would shadow the module and make this fail to compile).
    @Test func moduleQualifiedNamesResolve() {
        let decay: ZTronScrollPhysics.Decay = ZTronScrollPhysics.Decay(origin: 0, initialVelocity: 100)
        let rate: ZTronScrollPhysics.DecelerationRate = .fast
        #expect(decay.restPosition > 0 && rate.perMillisecond == 0.99)
    }
}
