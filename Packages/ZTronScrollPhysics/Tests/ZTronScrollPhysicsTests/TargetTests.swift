import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct PagingAndTargetTests {
    let page: CGFloat = 390
    var bounds: AxisBounds { AxisBounds(min: 0, max: 390 * 9) }

    @Test func pagingAtMostOnePage() {
        let start = 3 * page
        for displacement in [0.2, 0.9, 1.6, 2.7] as [CGFloat] {
            let forward = PagingSolver.target(current: start + displacement * page, dragStart: start, velocity: 50_000,
                                              pageLength: page, bounds: bounds)
            #expect(forward == 4 * page)
            let backward = PagingSolver.target(current: start - displacement * page, dragStart: start, velocity: -50_000,
                                               pageLength: page, bounds: bounds)
            #expect(backward == 2 * page)
        }
        // A slow release after dragging two pages still moves at most one page.
        #expect(PagingSolver.target(current: start + 2 * page, dragStart: start, velocity: 0, pageLength: page,
                                    bounds: bounds) == 4 * page)
    }

    @Test func pagingDirectionFromVelocity() {
        let start = 3 * page
        #expect(PagingSolver.target(current: start + 50, dragStart: start, velocity: 800, pageLength: page,
                                    bounds: bounds) == 4 * page)
        #expect(PagingSolver.target(current: start + 50, dragStart: start, velocity: -800, pageLength: page,
                                    bounds: bounds) == 3 * page)
        #expect(PagingSolver.target(current: start, dragStart: start, velocity: -800, pageLength: page,
                                    bounds: bounds) == 2 * page)
        #expect(PagingSolver.target(current: start - 300, dragStart: start, velocity: 800, pageLength: page,
                                    bounds: bounds) == 3 * page)
    }

    @Test func pagingDirectionFromHalfPageDisplacement() {
        let start = 3 * page
        func target(_ displacement: CGFloat) -> CGFloat {
            PagingSolver.target(current: start + displacement * page, dragStart: start, velocity: 100,
                                pageLength: page, bounds: bounds)
        }
        #expect(target(0.4) == 3 * page)
        #expect(target(0.6) == 4 * page)
        #expect(target(-0.4) == 3 * page)
        #expect(target(-0.6) == 2 * page)
    }

    @Test func pagingSnapsToNearestBoundaryAndClamps() {
        let partial = AxisBounds(min: 0, max: 4 * page + 100)                     // last page is partial
        #expect(PagingSolver.target(current: 4 * page + 20, dragStart: 4 * page, velocity: 2000, pageLength: page,
                                    bounds: partial) == partial.max)
        #expect(PagingSolver.target(current: -30, dragStart: 0, velocity: -2000, pageLength: page,
                                    bounds: partial) == 0)
        let inset = AxisBounds(min: -20, max: 3 * page - 20)                      // pages at −20 + n·390
        #expect(PagingSolver.target(current: page - 20 + 250, dragStart: page - 20, velocity: 0, pageLength: page,
                                    bounds: inset) == 2 * page - 20)
        #expect(PagingSolver.target(current: page - 20 + 1e-9, dragStart: page - 20, velocity: 2000,
                                    pageLength: page, bounds: inset) == 2 * page - 20)
    }

    @Test func zeroPageLengthIsClamp() {
        for length in [0, -390, .nan, .infinity] as [CGFloat] {
            #expect(PagingSolver.target(current: -50, dragStart: 0, velocity: 900, pageLength: length,
                                        bounds: bounds) == 0)
            #expect(PagingSolver.target(current: 500, dragStart: 0, velocity: 900, pageLength: length,
                                        bounds: bounds) == 500)
        }
    }

    @Test func nearestTargetTieBreaksTowardTravel() {
        let candidates: [CGFloat] = [0, 100, 200, .nan]
        #expect(TargetSnapping.nearest(to: 150, candidates: candidates, direction: 1) == 200)
        #expect(TargetSnapping.nearest(to: 150, candidates: candidates, direction: -1) == 100)
        #expect(TargetSnapping.nearest(to: 150, candidates: candidates, direction: 0) == 100)
        #expect(TargetSnapping.nearest(to: 40, candidates: candidates, direction: 1) == 0)
        #expect(TargetSnapping.nearest(to: 9999, candidates: candidates, direction: -1) == 200)
        #expect(TargetSnapping.nearest(to: 10, candidates: [], direction: 1) == nil)
        #expect(TargetSnapping.nearest(to: 10, candidates: [.nan], direction: 1) == nil)
    }

    @Test func projectedRestMatchesDecay() {
        for rate in [DecelerationRate.normal, .fast] {
            let projected = TargetSnapping.projectedRest(origin: 120, velocity: -2400, rate: rate)
            #expect(projected == Decay(origin: 120, initialVelocity: -2400, rate: rate).restPosition)
            expectClose(projected, 120 + 2400 / (1000 * log(rate.perMillisecond)), 1e-9)
        }
    }
}

@Suite struct FlingTests {
    let fling = FlingAcceleration()

    @Test func sameDirectionQuickFlingCarriesMomentum() {
        #expect(fling.combine(release: 2000, remainingAtCatch: 1500, touchDuration: 0.1) == 3500)
        #expect(fling.combine(release: -2000, remainingAtCatch: -1500, touchDuration: 0.1) == -3500)
        let half = FlingAcceleration(carryFactor: 0.5)
        #expect(half.combine(release: 2000, remainingAtCatch: 1500, touchDuration: 0.1) == 2750)
    }

    @Test func oppositeDirectionDoesNotCarry() {
        #expect(fling.combine(release: 2000, remainingAtCatch: -1500, touchDuration: 0.1) == 2000)
        #expect(fling.combine(release: 2000, remainingAtCatch: 0, touchDuration: 0.1) == 2000)
    }

    @Test func slowTouchDoesNotCarry() {
        #expect(fling.combine(release: 2000, remainingAtCatch: 1500, touchDuration: 0.5) == 2000)
        #expect(fling.combine(release: 2000, remainingAtCatch: 1500, touchDuration: 0.30) == 2000)
        #expect(fling.combine(release: 2000, remainingAtCatch: 1500, touchDuration: .nan) == 2000)
    }

    @Test func capApplies() {
        #expect(fling.combine(release: 9000, remainingAtCatch: 8000, touchDuration: 0.1) == 12_000)
        #expect(fling.combine(release: -9000, remainingAtCatch: -8000, touchDuration: 0.1) == -12_000)
        #expect(fling.combine(release: 20_000, remainingAtCatch: 0, touchDuration: 1) == 12_000)
        #expect(FlingAcceleration(maximumVelocity: 5000).combine(release: 4000, remainingAtCatch: 4000,
                                                                touchDuration: 0) == 5000)
        #expect(fling.combine(release: .infinity, remainingAtCatch: 100, touchDuration: 0.1) == 0)
    }
}

@Suite struct RestAndSnapTests {
    @Test func pixelSnapAt2xAnd3x() {
        #expect(PixelSnap.snap(10.26, displayScale: 2) == 10.5)
        #expect(PixelSnap.snap(10.1, displayScale: 2) == 10)
        expectClose(PixelSnap.snap(10.26, displayScale: 3), 31.0 / 3, 1e-12)
        expectClose(PixelSnap.snap(-0.2, displayScale: 3), -1.0 / 3, 1e-12)
        #expect(PixelSnap.snap(CGPoint(x: 1.3, y: -2.8), displayScale: 2) == CGPoint(x: 1.5, y: -3))
        for x in grid(-50, 50, count: 101) {
            let snapped = PixelSnap.snap(x * 1.37, displayScale: 3)
            expectClose((snapped * 3).rounded(), snapped * 3, 1e-9)               // on the 1/3 pt grid
            #expect(abs(snapped - x * 1.37) <= 1.0 / 6 + 1e-12)
        }
    }

    @Test func snapIgnoresNonPositiveScale() {
        for scale in [0, -2, .nan, .infinity] as [CGFloat] {
            #expect(PixelSnap.snap(10.26, displayScale: scale) == 10.26)
        }
        #expect(PixelSnap.snap(.nan, displayScale: 2).isNaN)
        #expect(PixelSnap.snap(.infinity, displayScale: 2) == .infinity)
    }

    @Test func motionSettledReportsExactEnd() {
        let decay = Decay(origin: 10, initialVelocity: 1700)
        let motion = AxisMotion.decay(decay, start: 5, handoff: nil)
        let T = decay.duration()
        for time in [5 + T, 5 + T + 1, .infinity] {
            let sample = motion.sample(at: time)
            #expect(sample == AxisMotion.Sample(position: decay.restPosition, velocity: 0, isSettled: true))
        }
        let moving = motion.sample(at: 5 + T * 0.9)
        #expect(!moving.isSettled)
        #expect(abs(moving.position - decay.restPosition) < 0.5 * 10)              // already close to rest
        #expect(motion.sample(at: 0) == AxisMotion.Sample(position: 10, velocity: 1700, isSettled: false))
        #expect(AxisMotion.rest(position: 4).sample(at: 99) == AxisMotion.Sample(position: 4, velocity: 0, isSettled: true))
    }

    @Test func negligibleReleaseRests() {
        let bounds = AxisBounds(min: 0, max: 1000)
        #expect(ReleaseSolver.resolve(ReleaseContext(origin: 300, velocity: 0, bounds: bounds), at: 0)
            == .rest(position: 300))
        #expect(ReleaseSolver.resolve(ReleaseContext(origin: 300, velocity: 0.5, bounds: bounds), at: 0)
            == .rest(position: 300))
        #expect(ReleaseSolver.resolve(ReleaseContext(origin: 300, velocity: 3, bounds: bounds, target: 300.2), at: 0)
            == .rest(position: 300.2))
        #expect(ReleaseSolver.resolve(ReleaseContext(origin: .nan, velocity: .nan, bounds: bounds), at: .nan)
            == .rest(position: 0))
    }

    /// The natural path uses the same "`v₀ ≈ 0`" as the target path: `|v| < negligibleReleaseVelocity` (20 pt/s)
    /// rests (`willDecelerate == false`) instead of creeping up to 10 pt over 1.5 s.
    @Test func naturalReleaseUsesNegligibleVelocityBoundary() {
        let bounds = AxisBounds(min: 0, max: 1000)
        func motion(_ v: CGFloat, _ thresholds: RestThresholds = .init()) -> AxisMotion {
            ReleaseSolver.resolve(ReleaseContext(origin: 300, velocity: v, bounds: bounds, thresholds: thresholds), at: 0)
        }
        for v in [1.5, 10, 19, -19, 19.99] as [CGFloat] {
            #expect(motion(v) == .rest(position: 300), "v = \(v)")
            #expect(!motion(v).willDecelerate)
        }
        for v in [20, 21, -21, 100] as [CGFloat] {
            guard case let .decay(decay, _, nil) = motion(v) else {
                Issue.record("v = \(v): expected a decay, got \(motion(v))")
                continue
            }
            #expect(decay.initialVelocity == v)
            #expect(motion(v).willDecelerate)
        }
        // The boundary follows the configured threshold.
        let strict = RestThresholds(negligibleReleaseVelocity: 5)
        #expect(motion(4, strict) == .rest(position: 300))
        #expect(motion(10, strict).willDecelerate)
    }
}
