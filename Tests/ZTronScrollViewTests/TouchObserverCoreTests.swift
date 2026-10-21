import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollView

// The iOS 15-16 UIKit touch observer's pure core (SPEC S2 amendment 2026-10-20, D31; design UIKIT-touch-observer.md §3):
// synthetic batches for every row of the mapping table and every defensive branch. This file alone covers
// `Gesture/UIKit/TouchObserverCore.swift` 100 %.

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func began(_ id: UInt, _ x: CGFloat, _ y: CGFloat) -> TouchSample { TouchSample(id: id, phase: .began, location: pt(x, y)) }
private func moved(_ id: UInt, _ x: CGFloat, _ y: CGFloat) -> TouchSample { TouchSample(id: id, phase: .moved, location: pt(x, y)) }
private func ended(_ id: UInt, _ x: CGFloat, _ y: CGFloat) -> TouchSample { TouchSample(id: id, phase: .ended, location: pt(x, y)) }
private func cancelled(_ id: UInt, _ x: CGFloat, _ y: CGFloat) -> TouchSample { TouchSample(id: id, phase: .cancelled, location: pt(x, y)) }

/// A core, its viewport (400 × 800 at the origin) and a clock that advances at every delivery, so a test can see that
/// every output carries the delivery time (D14) and nothing else.
private struct Rig {
    var core = TouchObserverCore()
    var viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
    var now: TimeInterval = 100

    @discardableResult
    mutating func feed(_ samples: TouchSample...) -> [ObserverOutput] { feed(samples) }

    @discardableResult
    mutating func feed(_ samples: [TouchSample]) -> [ObserverOutput] {
        now += 0.25
        return core.handle(samples, viewport: viewport, time: now)
    }

    func count(_ n: Int, _ remaining: CGPoint?) -> ObserverOutput {
        .pinch(.fingerCountChanged(count: n, remaining: remaining, time: now))
    }
    func changed(_ m: CGFloat, _ centroid: CGPoint) -> ObserverOutput {
        .pinch(.changed(magnification: m, centroid: centroid, time: now))
    }
    func down(_ at: CGPoint, _ n: Int) -> ObserverOutput { .pan(.touchDown(location: at, time: now, touchCount: n)) }
    var up: ObserverOutput { .pan(.touchesEnded(time: now)) }
    var pinchEnded: ObserverOutput { .pinch(.ended(time: now)) }
    func synth(_ at: CGPoint) -> ObserverOutput { .synthesize(at, now) }
}

@Suite struct TouchObserverCoreTests {
    // MARK: One finger

    @Test func aTapEmitsCountThenTouchDownThenCountThenEnd() {
        var r = Rig()
        let downOut = r.feed(began(1, 100, 200))
        #expect(downOut == [r.count(1, pt(100, 200)), r.down(pt(100, 200), 1)])
        #expect(r.core.isDown)
        #expect(r.core.activeCount == 1)
        #expect(r.core.centroid == pt(100, 200))

        let upOut = r.feed(ended(1, 100, 200))
        #expect(upOut == [r.count(0, pt(100, 200)), r.up])
        #expect(!r.core.isDown)
        #expect(r.core.activeCount == 0)
        #expect(r.core.centroid == nil)
    }

    @Test func aDragSynthesizesFromTheSingleTouchAtEveryMoveWithTheDeliveryTime() {
        var r = Rig()
        r.feed(began(1, 100, 200))
        let t0 = r.now
        #expect(r.feed(moved(1, 110, 230)) == [r.synth(pt(110, 230))])
        #expect(r.now > t0)                                      // each output carries its own delivery's clock
        #expect(r.feed(moved(1, 130, 260)) == [r.synth(pt(130, 260))])
        #expect(r.core.centroid == pt(130, 260))
    }

    @Test func aFingerDraggedOutsideTheViewportStaysOurs() {
        var r = Rig()
        r.feed(began(1, 100, 200))
        #expect(r.feed(moved(1, -50, 900)) == [r.synth(pt(-50, 900))])
        #expect(r.feed(ended(1, -50, 900)) == [r.count(0, pt(-50, 900)), r.up])
    }

    // MARK: Viewport filter

    @Test func aTouchThatBeganOutsideIsDroppedForItsWholeLifetime() {
        var r = Rig()
        #expect(r.feed(began(1, 500, 100)) == [])
        #expect(r.feed(moved(1, 100, 100)) == [])               // moved inside later: still not ours
        #expect(r.feed(ended(1, 100, 100)) == [])
        #expect(!r.core.isDown)
        #expect(r.core.activeCount == 0)
        #expect(r.core.centroid == nil)
    }

    @Test func theViewportEdgeIsInclusiveAtTheOriginAndExclusiveAtTheFarSide() {
        var r = Rig()
        #expect(r.feed(began(1, 0, 0)) != [])
        r.feed(ended(1, 0, 0))
        #expect(r.feed(began(2, 400, 800)) == [])
        #expect(r.feed(began(3, 399.5, 799.5)) != [])
    }

    @Test func theViewportRectIsTakenFromEachCall() {
        var r = Rig()
        r.viewport = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(r.feed(began(1, 99, 49)) != [])
        r.feed(ended(1, 99, 49))
        #expect(r.feed(began(2, 101, 10)) == [])
    }

    @Test func aForeignTouchDuringOurSequenceChangesNothing() {
        var r = Rig()
        r.feed(began(1, 100, 100))
        #expect(r.feed(began(2, 700, 100)) == [])               // outside: no count change
        #expect(r.feed(moved(2, 710, 100)) == [])
        #expect(r.feed(ended(2, 710, 100)) == [])
        #expect(r.core.activeCount == 1)
        #expect(r.feed(moved(1, 101, 100)) == [r.synth(pt(101, 100))])
    }

    // MARK: Pinch

    @Test func theSecondFingerStartsThePinchAndTheNextMoveCarriesTheDistanceRatio() {
        var r = Rig()
        r.feed(began(1, 100, 100))
        let second = r.feed(began(2, 200, 100))
        #expect(second == [r.count(2, pt(150, 100))])            // no touchDown again: the sequence is already down
        #expect(r.core.activeCount == 2)

        let apart = r.feed(moved(2, 250, 100))                   // 100 pt → 150 pt
        #expect(apart == [r.changed(1.5, pt(175, 100))])
        let closer = r.feed(moved(1, 150, 100))                  // 100 pt → 100 pt again
        #expect(closer == [r.changed(1.0, pt(200, 100))])
        let pinchedIn = r.feed(moved(2, 200, 100), moved(1, 100, 100)) // both move in one batch: 100 pt → 100 pt
        #expect(pinchedIn == [r.changed(1.0, pt(150, 100))])
    }

    @Test func twoFingersInOneBatchDownCountTwoAndTheOldestIsTheFirstTouch() {
        var r = Rig()
        let out = r.feed(began(7, 300, 100), began(3, 100, 100))
        #expect(out == [r.count(2, pt(200, 100)), r.down(pt(300, 100), 2)])
    }

    @Test func aThirdFingerDoesNotChangeThePair() {
        var r = Rig()
        r.feed(began(1, 0, 0), began(2, 30, 40))                 // d0 = 50
        #expect(r.feed(began(3, 300, 300)) == [r.count(3, pt(110, 340 / 3))])
        // The third finger moving: the pair's ratio is unchanged (1), the centroid follows all three.
        let third = r.feed(moved(3, 330, 300))
        #expect(third == [r.changed(1, pt(120, 340 / 3))])
        // One of the pair moving changes the ratio: |(0,0)→(60,80)| = 100 → 2.
        let pair = r.feed(moved(2, 60, 80))
        #expect(pair == [r.changed(2, pt(130, 380 / 3))])
    }

    @Test func liftingTheThirdFingerKeepsThePairAndItsRatio() {
        var r = Rig()
        r.feed(began(1, 0, 0), began(2, 30, 40), began(3, 300, 300))
        r.feed(moved(2, 60, 80))                                 // ratio 2
        #expect(r.feed(ended(3, 300, 300)) == [r.count(2, pt(30, 40))])
        #expect(r.feed(moved(2, 90, 120)) == [r.changed(3, pt(45, 60))])   // 150 / 50: same pair, same reference
    }

    @Test func liftingOneOfTheTwoOldestReBasesTheNewPairWithoutAJump() {
        var r = Rig()
        r.feed(began(1, 0, 0), began(2, 100, 0))
        r.feed(moved(2, 200, 0))                                 // ratio 2 (d: 100 → 200)
        r.feed(began(3, 200, 100))
        // Finger 1 lifts: the pair becomes (2, 3), 100 pt apart; the pinch keeps its magnification (2), not 1.
        let lift = r.feed(ended(1, 0, 0))
        #expect(lift == [r.count(2, pt(200, 50))])
        let next = r.feed(moved(3, 200, 200))                    // (2,3): 100 pt → 200 pt
        #expect(next == [r.changed(4, pt(200, 100))])            // 2 × 2
        #expect(r.feed(moved(3, 200, 200)) == [r.changed(4, pt(200, 100))])   // a repeat of the position: same value
    }

    @Test func aPairChangedWithoutACountChangeKeepsTheMagnification() {
        // One finger lifts and another lands in the same delivery: the count stays 2, the pair is new.
        var r = Rig()
        r.feed(began(1, 0, 0), began(2, 100, 0))
        r.feed(moved(2, 150, 0))                                 // ratio 1.5
        let swap = r.feed(ended(1, 0, 0), began(3, 150, 100))
        #expect(swap == [r.changed(1.5, pt(150, 50))])
        #expect(r.feed(moved(3, 150, 200)) == [r.changed(3, pt(150, 100))])   // 100 → 200 on top of 1.5
    }

    @Test func fingersLandingOnTheSamePointTakeTheFirstSpreadAsTheirReference() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 100, 100))           // d0 = 0
        #expect(r.feed(moved(2, 100, 100)) == [])                // still on one point: nothing to report
        #expect(r.feed(moved(2, 140, 100)) == [r.changed(1, pt(120, 100))])  // first spread = reference
        #expect(r.feed(moved(2, 180, 100)) == [r.changed(2, pt(140, 100))])  // 80 / 40
    }

    @Test func fingersCrossingOnePointReportNothingAndResumeFromTheLastValue() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 300, 100))                               // ratio 2
        #expect(r.feed(moved(2, 100, 100)) == [])                // d == 0
        #expect(r.feed(moved(2, 150, 100)) == [r.changed(0.5, pt(125, 100))])   // 50 / 100 against the unchanged base
    }

    // MARK: Lifts, hand-off, re-touch

    @Test func theStaggeredLiftHandsOffToTheRemainingFingerThenContinuesAndEnds() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 220, 100))
        // 2 → 1: the count event carries the remaining finger, then the pinch ends (closes D25's window).
        let lift = r.feed(ended(2, 220, 100))
        #expect(lift == [r.count(1, pt(100, 100)), r.pinchEnded])
        // One-finger continuation: only synthesized pan samples, never a `.changed` after the lift (D25).
        #expect(r.feed(moved(1, 100, 140)) == [r.synth(pt(100, 140))])
        #expect(r.feed(moved(1, 100, 180)) == [r.synth(pt(100, 180))])
        // Last finger up: no second pinch end.
        #expect(r.feed(ended(1, 100, 180)) == [r.count(0, pt(100, 180)), r.up])
    }

    @Test func aSecondFingerAgainDuringTheContinuationStartsAFreshPinchBase() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 300, 100))                               // ratio 2
        r.feed(ended(2, 300, 100))
        r.feed(moved(1, 100, 140))
        // D29: re-touch = fingerCountChanged(2) (the session re-arms with a pending base) and a ratio from the NEW pair.
        let touch = r.feed(began(5, 100, 240))
        #expect(touch == [r.count(2, pt(100, 190))])
        #expect(r.feed(moved(5, 100, 340)) == [r.changed(2, pt(100, 240))])  // 200 / 100, not 2 × 2
    }

    @Test func bothFingersUpAtOnceCountZeroThenEndThenPinchEnd() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 220, 100))
        let out = r.feed(ended(1, 100, 100), ended(2, 220, 100))
        #expect(out == [r.count(0, pt(160, 100)), r.up, r.pinchEnded])
        #expect(!r.core.isDown)
        #expect(r.core.centroid == nil)
    }

    @Test func aNewSequenceAfterAPinchStartsClean() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 300, 100))
        r.feed(ended(1, 100, 100), ended(2, 300, 100))
        let again = r.feed(began(1, 50, 50), began(2, 150, 50))
        #expect(again == [r.count(2, pt(100, 50)), r.down(pt(50, 50), 2)])
        #expect(r.feed(moved(2, 250, 50)) == [r.changed(2, pt(150, 50))])
    }

    // MARK: Cancel

    @Test func cancelMidPinchCancelsBothAndDropsEveryTouch() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 300, 100))
        let out = r.feed(cancelled(1, 100, 100), cancelled(2, 300, 100))
        #expect(out == [.pan(.cancelled), .pinch(.cancelled)])
        #expect(r.core.activeCount == 0)
        #expect(!r.core.isDown)
        #expect(r.core.centroid == nil)
        // The dead ids produce nothing; a fresh sequence is a fresh touch-down with a fresh pinch.
        #expect(r.feed(moved(1, 120, 100)) == [])
        #expect(r.feed(ended(2, 300, 100)) == [])
        #expect(r.feed(began(1, 100, 100), began(2, 200, 100)) == [r.count(2, pt(150, 100)), r.down(pt(100, 100), 2)])
        #expect(r.feed(moved(2, 220, 100)) == [r.changed(1.2, pt(160, 100))])
    }

    @Test func aSingleTouchCancelledIsACancel() {
        var r = Rig()
        r.feed(began(1, 100, 100))
        #expect(r.feed(cancelled(1, 100, 100)) == [.pan(.cancelled), .pinch(.cancelled)])
        #expect(r.core.activeCount == 0)
    }

    @Test func aCancelledForeignOrUnknownTouchIsIgnored() {
        var r = Rig()
        #expect(r.feed(began(9, 900, 900)) == [])                // outside
        #expect(r.feed(cancelled(9, 900, 900)) == [])
        #expect(r.feed(cancelled(4, 10, 10)) == [])              // never seen
        r.feed(began(1, 100, 100))
        #expect(r.feed(cancelled(9, 900, 900)) == [])            // foreign cancel during our sequence
        #expect(r.core.isDown)
        #expect(r.core.activeCount == 1)
    }

    // MARK: Defensive branches

    @Test func unknownIdsAndEmptyBatchesEmitNothing() {
        var r = Rig()
        #expect(r.feed([]) == [])
        #expect(r.feed(moved(4, 10, 10)) == [])
        #expect(r.feed(ended(4, 10, 10)) == [])
        r.feed(began(1, 100, 100), began(2, 200, 100))
        r.feed(moved(2, 250, 100))
        #expect(r.feed([]) == [])                                // an empty delivery mid-pinch: no phantom sample
        #expect(r.feed(moved(8, 1, 1)) == [])                    // unknown id mid-pinch
        #expect(r.feed(ended(8, 1, 1)) == [])
        #expect(r.core.activeCount == 2)
        r.feed(moved(1, 100, 100))
        #expect(r.feed(moved(2, 250, 100)) == [r.changed(1.5, pt(175, 100))])
    }

    @Test func aBeganForALiveIdReplacesTheTouchAndCountsAsAMove() {
        var r = Rig()
        r.feed(began(1, 100, 100))
        // The end of touch 1 was missed and UIKit reused its id: the new began replaces it (count unchanged).
        #expect(r.feed(began(1, 150, 160)) == [r.synth(pt(150, 160))])
        #expect(r.core.activeCount == 1)
        r.feed(began(2, 250, 160))
        #expect(r.feed(began(2, 350, 160)) == [r.changed(2, pt(250, 160))])   // 100 → 200
    }

    @Test func foreignAndUnknownSamplesInsideAPinchChangeNothing() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        // Nothing of ours moved: a foreign touch lands, a never-seen id ends.
        #expect(r.feed(began(3, 700, 100), ended(4, 5, 5)) == [])
    }

    // MARK: reset

    @Test func resetClosesALiveSequenceWithCancelsAndForgetsEverything() {
        var r = Rig()
        r.feed(began(1, 100, 100), began(2, 200, 100))
        #expect(r.core.reset() == [.pan(.cancelled), .pinch(.cancelled)])
        #expect(r.core.activeCount == 0)
        #expect(!r.core.isDown)
        #expect(r.core.centroid == nil)
        #expect(r.feed(moved(2, 250, 100)) == [])                // forgotten
        #expect(r.feed(began(1, 100, 100)) == [r.count(1, pt(100, 100)), r.down(pt(100, 100), 1)])
    }

    @Test func resetOfAnIdleCoreEmitsNothing() {
        var core = TouchObserverCore()
        #expect(core.reset() == [])
        var r = Rig()
        r.feed(began(1, 100, 100))
        r.feed(ended(1, 100, 100))
        #expect(r.core.reset() == [])
    }
}

// MARK: - Equivalence with the 18+ spatial observer

/// What the two sources have in common: the order of the count / touch-down / lift / synthesized events.
private enum Common: Equatable {
    case count(Int, CGPoint?)
    case synth(CGPoint)
    case down(CGPoint, Int)
    case up
}

/// A line-for-line model of `SpatialCatchGesture.onChanged` (CatchObserver.swift) over the active locations of a batch.
private struct SpatialReference {
    var down = false
    var activeCount = 0
    var centroid: CGPoint?

    mutating func batch(_ active: [CGPoint]) -> [Common] {
        var out: [Common] = []
        let wasDown = down
        let previous = activeCount
        activeCount = active.count
        if !active.isEmpty {
            let n = CGFloat(active.count)
            centroid = CGPoint(x: active.map(\.x).reduce(0, +) / n, y: active.map(\.y).reduce(0, +) / n)
        }
        if active.count != previous {
            out.append(.count(active.count, centroid))
        } else if active.count >= 2 {
            out.append(.count(active.count, centroid))
        } else if active.count == 1, let c = centroid {
            out.append(.synth(c))
        }
        if !wasDown, let first = active.first {
            down = true
            out.append(.down(first, active.count))
        } else if wasDown, active.isEmpty {
            down = false
            centroid = nil
            out.append(.up)
        }
        return out
    }
}

@Suite struct TouchObserverSpatialEquivalenceTests {
    /// The same scripted touches through the core and through the spatial model must produce the same common events in
    /// the same order; the core's `.changed` stands where the spatial path sends its per-batch `.fingerCountChanged`
    /// (the magnify gesture supplies the magnification there) and its `.pinch(.ended)` has no spatial counterpart.
    private func check(_ name: String, _ script: [[TouchSample]], sourceLocation: SourceLocation = #_sourceLocation) {
        var rig = Rig()
        var reference = SpatialReference()
        var live: [UInt: (order: Int, location: CGPoint)] = [:]
        var order = 0
        for (i, batch) in script.enumerated() {
            let produced = rig.feed(batch)
            for s in batch {
                switch s.phase {
                case .began: live[s.id] = (order, s.location); order += 1
                case .moved: live[s.id]?.location = s.location
                case .ended, .cancelled: live[s.id] = nil
                }
            }
            let active = live.values.sorted { $0.order < $1.order }.map(\.location)
            let got: [Common] = produced.compactMap { output in
                switch output {
                case let .pinch(.fingerCountChanged(count, remaining, _)): return .count(count, remaining)
                case let .pinch(.changed(_, centroid, _)): return .count(rig.core.activeCount, centroid)
                case let .synthesize(p, _): return .synth(p)
                case let .pan(.touchDown(location, _, touchCount)): return .down(location, touchCount)
                case .pan(.touchesEnded): return .up
                default: return nil
                }
            }
            #expect(got == reference.batch(active), "\(name) · batch \(i)", sourceLocation: sourceLocation)
        }
    }

    @Test func tap() { check("tap", [[began(1, 50, 60)], [ended(1, 50, 60)]]) }

    @Test func drag() {
        check("drag", [[began(1, 50, 60)], [moved(1, 60, 70)], [moved(1, 80, 90)], [ended(1, 80, 90)]])
    }

    @Test func pinchWithAStaggeredLiftAndOneFingerContinuation() {
        check("staggered", [[began(1, 100, 100)], [began(2, 200, 100)], [moved(2, 250, 120)], [moved(1, 90, 100)],
                            [ended(2, 250, 120)], [moved(1, 90, 150)], [moved(1, 90, 180)], [ended(1, 90, 180)]])
    }

    @Test func reTouchDuringTheContinuation() {
        check("retouch", [[began(1, 100, 100)], [began(2, 200, 100)], [moved(2, 220, 100)], [ended(2, 220, 100)],
                          [moved(1, 100, 130)], [began(3, 220, 130)], [moved(3, 260, 130)], [ended(1, 100, 130)],
                          [ended(3, 260, 130)]])
    }

    @Test func bothUpAtOnceAndTwoDownAtOnce() {
        check("simultaneous", [[began(1, 100, 100), began(2, 200, 100)], [moved(2, 240, 100)],
                               [ended(1, 100, 100), ended(2, 240, 100)]])
    }

    @Test func threeFingers() {
        check("three", [[began(1, 0, 0)], [began(2, 30, 40)], [began(3, 300, 300)], [moved(3, 330, 300)], [moved(1, 10, 0)],
                        [ended(1, 10, 0)], [moved(2, 60, 80)], [ended(3, 330, 300)], [ended(2, 60, 80)]])
    }
}

// MARK: - Gating

/// `ZTronScrollState.usesUIKitTouchObserver`: chosen once at creation, on both OS paths (the `-ZTronForceUIKitObserver`
/// shapes included), and never together with `SpatialEventGesture`.
@MainActor
@Suite struct UIKitObserverGatingTests {
    private func withObserverForcedOn<T>(_ body: () -> T) -> T {
        ZTronAvailability.forceUIKitTouchObserver(true)
        defer { ZTronAvailability.forceUIKitTouchObserver(false) }
        return body()
    }

    @Test(arguments: OSPath.allCases)
    func theStateFlagFollowsTheCapabilityAndNeverMeetsSpatialEvents(path: OSPath) {
        withOSPath(path) {
            let state = ZTronScrollState()
            #expect(state.usesUIKitTouchObserver
                    == (ZTronAvailability.isAvailable(.uikitTouchObserver) && !state.usesSpatialEvents))
            // Native iOS 15-16 uses it on the preferred path; every host here (17+) does not, and all fallbacks forced
            // (DEBUG) turn it off.
            let preferred = path == .preferred || !ZTronAvailability.isForcingSupported
            #expect(state.usesUIKitTouchObserver == (preferred && RunningOS.shipsPreferred(.uikitTouchObserver)))
        }
    }

    @Test func theForcedFlagIsFixedAtCreation() {
        withOSPath(.forcedFallback) {
            let before = ZTronScrollState()
            let after = withObserverForcedOn { ZTronScrollState() }
            let later = ZTronScrollState()
            #expect(!before.usesUIKitTouchObserver)
            #expect(!later.usesUIKitTouchObserver)
            if ZTronAvailability.isForcingSupported {
                #expect(after.usesUIKitTouchObserver)       // the shipped 15-16 shape: every fallback + the observer
                #expect(!after.usesSpatialEvents)
                #expect(!after.usesMagnifyGesture)
            }
            #expect(!before.usesUIKitTouchObserver)         // `let`s: the earlier state did not flip
        }
    }

    @Test func forcedOnWithSpatialEventsAvailableStaysOff() {
        // `-ZTronForceUIKitObserver` alone on an iOS 28+ simulator: spatial events still win, no observer (below 28 they are
        // never used, D36, so the observer takes over there, as on 17.x).
        withOSPath(.preferred) {
            let state = withObserverForcedOn { ZTronScrollState() }
            #expect(state.usesUIKitTouchObserver == (ZTronAvailability.isForcingSupported && !state.usesSpatialEvents))
        }
    }

    @Test func forcedOnWithSpatialEventsForcedOffUsesTheObserverOnEveryHost() {
        withOSPath(.preferred) {
            ZTronAvailability.forceFallback(.spatialEvents, true)
            defer { ZTronAvailability.forceFallback(.spatialEvents, false) }
            let state = withObserverForcedOn { ZTronScrollState() }
            #expect(state.usesUIKitTouchObserver == ZTronAvailability.isForcingSupported)
            // Spatial events are off when forced (DEBUG) and, below iOS 28, everywhere (D36).
            #expect(!state.usesSpatialEvents == (ZTronAvailability.isForcingSupported || !RunningOS.isAtLeast((28, 0))))
        }
    }
}
