import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// The refresh engine (design M8b §1.3, test list item 1): the pure state machine as values, then the same behavior
/// through the pan, the state and the coordinator on both OS paths.
@MainActor
@Suite(.serialized)
struct RefreshEngineTests {
    // MARK: The state machine as values

    func input(_ pull: CGFloat, tracking: Bool = true, enabled: Bool = true, settled: Bool = true,
               t: TimeInterval = 0) -> RefreshEngine.Input {
        RefreshEngine.Input(pull: pull, isTracking: tracking, enabled: enabled, isSettled: settled, time: t)
    }

    @Test func dragPositionIsPullOverTriggerClamped() {
        let e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        #expect(e.progress(for: 0) == 0 && e.progress(for: -20) == 0)
        #expect(e.progress(for: 25) == 0.25 && e.progress(for: 99) == 0.99)
        #expect(e.progress(for: 100) == 1 && e.progress(for: 640) == 1)
        let zero = RefreshEngine(config: ZTronRefreshConfiguration(triggerDistance: 0), edge: .top)
        #expect(zero.progress(for: 3) == 1 && zero.progress(for: 0) == 0)
    }

    @Test func whilePullingFiresAtTheCrossingOncePerPull() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        #expect(e.handle(.sample(input(0))) == [])
        #expect(e.handle(.sample(input(40))) == [.mode(.pulling, animated: false), .progress(0.4)])
        #expect(e.handle(.sample(input(99))) == [.progress(0.99)])
        #expect(e.phase == .pulling)
        #expect(e.handle(.sample(input(100))) == [.progress(1), .mode(.refreshing, animated: true), .trigger,
                                                  .announce("Refreshing")])
        #expect(e.phase == .triggered && e.firedThisPull)
        #expect(e.handle(.sample(input(180))) == [], "not again while the finger stays down")
        #expect(e.handle(.sample(input(30))) == [], "dragPosition stays 1 while refreshing")
        // The hold opens at the lift, never mid-drag.
        #expect(e.handle(.lift(input(120, t: 5), cancelled: false)) == [.hold(60, reveal: false)])
        #expect(e.phase == .refreshing(since: 5))
        // A second pull during the refresh never fires.
        #expect(e.handle(.sample(input(300, t: 6))) == [])
        #expect(e.handle(.lift(input(300, t: 6.5), cancelled: false)) == [])
        #expect(e.handle(.begin(input(0, tracking: false, t: 7), runAction: true)) == [], "begin while running is a no-op")
        #expect(e.phase == .refreshing(since: 5))
    }

    @Test func aCrossingBetweenSamplesStillCountsAtTheLift() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        #expect(e.handle(.lift(input(130, t: 1), cancelled: false)) ==
                [.progress(1), .mode(.refreshing, animated: true), .trigger, .announce("Refreshing"), .hold(60, reveal: false)])
        #expect(e.phase == .refreshing(since: 1))
    }

    @Test func onReleaseFiresOnlyAtTheLiftAtOrPastTheTriggerAndDisarmsBelow() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(triggerMode: .onRelease), edge: .top)
        #expect(e.handle(.sample(input(150))) == [.mode(.pulling, animated: false), .progress(1)])
        #expect(e.phase == .armed, "crossed, waiting for the lift: no action yet")
        #expect(e.handle(.sample(input(60))) == [.progress(0.6)])
        #expect(e.phase == .pulling, "back below the trigger: disarmed")
        #expect(e.handle(.lift(input(60, t: 1), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
        #expect(e.phase == .retracting(.pull, until: 4) && !e.firedThisPull, "the release springs it back and the indicator goes with it")
        // Past the trigger at the lift: fires then (a new pull takes over from the retraction).
        #expect(e.handle(.sample(input(120))) == [.retract(nil), .mode(.pulling, animated: false), .progress(1)])
        #expect(e.handle(.lift(input(120, t: 2), cancelled: false)) ==
                [.mode(.refreshing, animated: true), .trigger, .announce("Refreshing"), .hold(60, reveal: false)])
        // A cancelled touch never fires.
        var c = RefreshEngine(config: ZTronRefreshConfiguration(triggerMode: .onRelease), edge: .top)
        _ = c.handle(.sample(input(150)))
        #expect(c.handle(.lift(input(150, t: 1), cancelled: true)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
        #expect(c.phase == .retracting(.pull, until: 4), "no action, the indicator retracts")
    }

    @Test func minimumVisibleTimeHoldsTheIndicator() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 0.5), edge: .top)
        _ = e.handle(.lift(input(130, t: 5), cancelled: false))
        #expect(e.handle(.done(input(0, tracking: false, t: 5.2))) == [])
        #expect(e.phase == .finishing(until: 5.5))
        #expect(e.handle(.done(input(0, tracking: false, t: 5.3))) == [], "done is idempotent")
        #expect(e.handle(.sample(input(0, tracking: false, t: 5.49))) == [])
        #expect(e.handle(.sample(input(0, tracking: false, settled: false, t: 6))) == [], "a motion still runs: wait")
        #expect(e.handle(.sample(input(0, tracking: false, t: 6))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .clearHold(atLift: false, animated: true),
                 .announce("Refresh complete")])
        #expect(e.phase == .idle && !e.firedThisPull)
        // A late action ends at once; an early one waits for the remaining time.
        var late = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 0.5), edge: .top)
        _ = late.handle(.lift(input(130, t: 5), cancelled: false))
        #expect(late.handle(.done(input(0, tracking: false, t: 9))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .clearHold(atLift: false, animated: true),
                 .announce("Refresh complete")])
    }

    @Test func theResetWaitsForTheLiftWhileTracking() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.lift(input(130, t: 5), cancelled: false))
        #expect(e.handle(.done(input(80, t: 8))) == [], "the finger is down on a second pull: finishing, not finished")
        #expect(e.phase == .finishing(until: 8))
        #expect(e.handle(.sample(input(90, t: 9))) == [])
        #expect(e.handle(.lift(input(90, t: 10), cancelled: false)) ==
                [.progress(0.9), .mode(.notRefreshing, animated: true), .retract(.spinner),
                 .clearHold(atLift: true, animated: true), .announce("Refresh complete")],
                "the release pipeline springs the offset: bounds only, and the spinner goes with the content")
        #expect(e.phase == .retracting(.spinner, until: 13))
        // A reset that is not due at the lift completes at the first frame past its deadline, finger up.
        var f = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 2), edge: .top)
        _ = f.handle(.lift(input(130, t: 5), cancelled: false))
        _ = f.handle(.done(input(80, t: 5.5)))
        #expect(f.handle(.lift(input(80, t: 6), cancelled: false)) == [])
        #expect(f.handle(.sample(input(0, tracking: false, t: 7))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .clearHold(atLift: false, animated: true),
                 .announce("Refresh complete")])
    }

    /// User report 2026-10-21 (D35): a slow pull outlives the action, which used to drop the refreshing look under the finger
    /// and hold nothing at the lift, so the indicator's fate depended on the speed of the pull.
    @Test func anActionThatReturnsUnderTheFingerKeepsTheRefreshingLookUntilTheLift() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)       // minimum visible time 0.5 s
        _ = e.handle(.sample(input(130, t: 0)))                                      // the crossing, finger down
        #expect(e.phase == .triggered)
        #expect(e.handle(.done(input(140, t: 0.6))) == [], "the action returned under the finger: nothing changes on screen")
        #expect(e.phase == .triggered && e.mode == .refreshing && e.progress == 1 && !e.holdApplied)
        #expect(e.handle(.sample(input(160, t: 1.5))) == [], "still the refreshing look while the finger stays down")
        #expect(e.handle(.sample(input(40, t: 1.8))) == [], "also when the finger comes back")
        // Lifted after the minimum visible time since the trigger: nothing to hold, the refresh just ends.
        #expect(e.handle(.lift(input(160, t: 2), cancelled: false)) ==
                [.mode(.notRefreshing, animated: true), .retract(.spinner), .announce("Refresh complete")])
        #expect(e.phase == .retracting(.spinner, until: 5) && !e.firedThisPull && !e.holdApplied)
        #expect(e.handle(.sample(input(130, t: 3))).contains(.trigger), "the next pull is a new pull")
    }

    /// Open item 32 (M8b-s8): a finger that grabs the content again while the spinner goes back with it keeps the spinner's
    /// look (no `.retract(nil)`: the coordinator's retraction stays `.spinner`, so the indicator keeps the refreshing placement)
    /// until this pull fires, lifts, is pushed back to rest, ends or is cancelled. A `.pull` retraction's re-grab is unchanged.
    @Test func aReGrabbedSpinnerKeepsItsLookUntilThePullEnds() {
        /// An early return lifted past the minimum visible time: the spinner retracts with the content; a finger grabs it at 70.
        func regrabbed() -> RefreshEngine {
            var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
            _ = e.handle(.sample(input(130, t: 0)))
            _ = e.handle(.done(input(140, t: 0.6)))
            _ = e.handle(.lift(input(160, t: 2), cancelled: false))
            #expect(e.handle(.sample(input(80, tracking: false, t: 2.2))) == [.progress(0.8)])
            #expect(e.retractLook == .spinner)
            #expect(e.handle(.sample(input(70, t: 2.3))) == [.mode(.pulling, animated: false), .progress(0.7)],
                    "no .retract(nil): the spinner's look is carried through the re-grab")
            #expect(e.phase == .pulling && e.mode == .pulling && e.retractLook == nil)
            return e
        }
        // Lifted below the trigger: it goes back with the content as a spinner again, and only this pull carries it.
        var a = regrabbed()
        #expect(a.handle(.sample(input(45, t: 2.4))) == [.progress(0.45)])
        #expect(a.handle(.lift(input(45, t: 2.5), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.spinner)])
        #expect(a.phase == .retracting(.spinner, until: 5.5))
        #expect(a.handle(.sample(input(0.2, tracking: false, t: 2.9))) == [.progress(0), .retract(nil)])
        #expect(a.handle(.sample(input(40, t: 4))) == [.mode(.pulling, animated: false), .progress(0.4)])
        #expect(a.handle(.lift(input(40, t: 4.1), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.pull)],
                "a later pull is a plain pull")
        // Pulled to the trigger: the refreshing look takes over in the same place (the carry ends with the mode change).
        var b = regrabbed()
        #expect(b.handle(.sample(input(100, t: 2.4))) ==
                [.progress(1), .mode(.refreshing, animated: true), .retract(nil), .trigger, .announce("Refreshing")])
        #expect(b.phase == .triggered && b.firedThisPull)
        #expect(b.handle(.lift(input(110, t: 2.6), cancelled: false)) == [.hold(60, reveal: false)])
        // Pushed back to rest (or past it) under the finger: an ordinary reset, and the carry ends.
        var c = regrabbed()
        #expect(c.handle(.sample(input(-4, t: 2.4))) == [.progress(0), .mode(.notRefreshing, animated: true), .retract(nil)])
        #expect(c.phase == .idle)
        #expect(c.handle(.lift(input(-4, t: 2.5), cancelled: false)) == [])
        // Cancelled (the view went, a programmatic cancel).
        var d = regrabbed()
        #expect(d.handle(.cancel) == [.retract(nil), .progress(0), .mode(.notRefreshing, animated: false)])
        #expect(d.phase == .idle && d.handle(.cancel) == [])
        // Lifted at rest (the lift's rest guard), the touch ending without a lift, the pull disabled under the finger.
        var g = regrabbed()
        #expect(g.handle(.lift(input(0.3, t: 2.5), cancelled: false)) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .retract(nil)])
        var s = regrabbed()
        #expect(s.handle(.sequenceEnd(input(70, tracking: false, t: 2.5))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .retract(nil)])
        var z = regrabbed()
        #expect(z.handle(.sample(input(70, enabled: false, t: 2.4))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .retract(nil)])
        // A `.pull` retraction's re-grab is unchanged: the pull's own look starts again at once.
        var p = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = p.handle(.sample(input(70, t: 1)))
        #expect(p.handle(.lift(input(70, t: 2), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
        #expect(p.handle(.sample(input(60, t: 2.2))) == [.retract(nil), .mode(.pulling, animated: false), .progress(0.6)])
        #expect(p.handle(.lift(input(60, t: 2.4), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
    }

    @Test func aLiftBeforeTheMinimumVisibleTimeOpensTheHoldForTheTimeThatIsMissing() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 0.5), edge: .top)
        _ = e.handle(.sample(input(130, t: 10)))
        _ = e.handle(.done(input(140, t: 10.1)))
        #expect(e.handle(.lift(input(150, t: 10.2), cancelled: false)) == [.hold(60, reveal: false)])
        #expect(e.phase == .finishing(until: 10.5), "counted from the trigger, not from the lift")
        #expect(e.handle(.sample(input(0, tracking: false, t: 10.4))) == [])
        #expect(e.handle(.sample(input(0, tracking: false, t: 10.5))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .clearHold(atLift: false, animated: true),
                 .announce("Refresh complete")])
        #expect(e.phase == .idle && !e.firedThisPull)
    }

    @Test func aTouchThatEndsWithoutAReleaseHandlesAnEarlyReturnTheSameWay() {
        // The lift was never reported (sequence end / a sample with the finger up): same outcome as the lift.
        var a = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = a.handle(.sample(input(130, t: 0)))
        _ = a.handle(.done(input(130, t: 0.2)))
        #expect(a.handle(.sequenceEnd(input(0, tracking: false, t: 3))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .announce("Refresh complete")])
        #expect(a.phase == .idle && !a.firedThisPull)
        var b = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = b.handle(.sample(input(130, t: 0)))
        _ = b.handle(.done(input(130, t: 0.2)))
        #expect(b.handle(.sample(input(0, tracking: false, t: 3))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .announce("Refresh complete")])
        #expect(b.phase == .idle && !b.firedThisPull)
        // An action still running at the lift behaves as before: the hold opens and waits for `done`.
        var c = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = c.handle(.sample(input(130, t: 0)))
        #expect(c.handle(.lift(input(130, t: 1), cancelled: false)) == [.hold(60, reveal: false)])
        #expect(c.phase == .refreshing(since: 1))
    }

    @Test func beginAndCancel() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        #expect(e.handle(.begin(input(0, tracking: false, t: 3), runAction: false)) ==
                [.progress(1), .mode(.refreshing, animated: true), .hold(60, reveal: true), .announce("Refreshing")])
        #expect(e.phase == .refreshing(since: 3))
        #expect(e.handle(.begin(input(0, tracking: false, t: 4), runAction: true)) == [])
        // Cancel: hold cleared unanimated, indicator at rest, idempotent.
        #expect(e.handle(.cancel) == [.clearHold(atLift: false, animated: false), .progress(0), .mode(.notRefreshing, animated: false)])
        #expect(e.phase == .idle && !e.holdApplied)
        #expect(e.handle(.cancel) == [])
        #expect(e.handle(.done(input(0, tracking: false, t: 5))) == [], "a late done after a cancel is ignored")
        // The accessibility action runs the action.
        #expect(e.handle(.begin(input(0, tracking: false, t: 6), runAction: true)) ==
                [.progress(1), .mode(.refreshing, animated: true), .hold(60, reveal: true), .trigger, .announce("Refreshing")])
        // Cancel while only pulling has no hold to clear.
        var p = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = p.handle(.sample(input(50)))
        #expect(p.handle(.cancel) == [.progress(0), .mode(.notRefreshing, animated: false)])
    }

    @Test func disabledWhilePullingResetsAndNeverTriggers() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(50)))
        #expect(e.handle(.sample(input(60, enabled: false))) == [.progress(0), .mode(.notRefreshing, animated: true)])
        #expect(e.phase == .idle)
        #expect(e.handle(.sample(input(400, enabled: false))) == [], "zoomed / scroll disabled / another edge refreshing")
        #expect(e.handle(.lift(input(400, enabled: false), cancelled: false)) == [])
        #expect(!e.firedThisPull)
    }

    @Test func holdSizes() {
        let c = ZTronRefreshConfiguration(holdOffset: 80, loadMorePadding: 44)
        #expect(RefreshEngine.holdSize(edge: .top, config: ZTronRefreshConfiguration(), overlay: false) == 60)
        #expect(RefreshEngine.holdSize(edge: .top, config: c, overlay: false) == 80, "holdOffset wins over indicatorHeight")
        #expect(RefreshEngine.holdSize(edge: .leading, config: c, overlay: false) == 80)
        #expect(RefreshEngine.holdSize(edge: .bottom, config: c, overlay: false) == 124, "end edges add the load-more padding")
        #expect(RefreshEngine.holdSize(edge: .trailing, config: ZTronRefreshConfiguration.loadMore, overlay: false) == 104)
        #expect(RefreshEngine.holdSize(edge: .bottom, config: c, overlay: true) == 0, "an overlay never pushes the content")
    }

    // MARK: Through the pan, the state and the coordinator

    @Test(arguments: OSPath.allCases) func dragPositionFollowsThePullClamped(path: OSPath) {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(triggerMode: .onRelease)])
        r.touchDown()
        #expect(r.refreshState().dragPosition == 0 && r.refreshState().mode == .notRefreshing)
        for target in [20, 50, 80, 120, 300] as [CGFloat] {
            r.finger(toPull: target)
            let pull = r.pull()
            #expect(abs(pull - target) < 0.01, "the rig drives the displayed pull to \(target): \(pull)")
            #expect(abs(r.refreshState().dragPosition - min(1, pull / 100)) < 1e-9, "pull \(pull)")
            #expect(r.refreshState().mode == .pulling)
        }
        #expect(r.refreshState().dragPosition == 1)
        #expect(r.refreshState().edge == .top && r.refreshState().style == .default)
    }

    @Test(arguments: OSPath.allCases) func whilePullingFiresAtTheCrossingWithTheFingerDownExactlyOnce(path: OSPath) async {
        let r = RefreshRig(path)
        r.touchDown()
        r.finger(toPull: 40)
        r.finger(toPull: 99)
        #expect(r.refresh.triggerSerial == 0)
        r.finger(toPull: 101)                                   // the crossing, the finger still down
        #expect(r.refresh.triggerSerial == 1 && r.state.isTracking)
        #expect(r.engine().phase == .triggered && r.refreshState().mode == .refreshing)
        r.finger(toPull: 200)
        r.finger(toPull: 110)
        r.finger(toPull: 250)
        #expect(r.refresh.triggerSerial == 1, "once per pull")
        await r.pumpTasks()
        #expect(r.gate.started == 1, "the action started while the finger was down")
        r.lift()
        r.settle()
        #expect(r.refresh.triggerSerial == 1 && r.gate.started == 1)
        // A second pull during the refresh never calls the action.
        r.touchDown()
        r.drag(CGSize(width: 0, height: 20))
        r.drag(CGSize(width: 0, height: 300))
        r.lift()
        r.settle()
        await r.pumpTasks()
        #expect(r.refresh.triggerSerial == 1 && r.gate.started == 1)
        #expect(r.announcements == ["Refreshing"])
    }

    @Test(arguments: OSPath.allCases) func onReleaseFiresOnlyAtTheLiftAtOrPastTheTrigger(path: OSPath) async {
        let cfg = ZTronRefreshConfiguration(triggerMode: .onRelease)
        let a = RefreshRig(path, configs: [.top: cfg])
        a.touchDown()
        a.finger(toPull: 160)
        await a.pumpTasks()
        #expect(a.refresh.triggerSerial == 0 && a.gate.started == 0 && a.engine().phase == .armed)
        a.lift()
        await a.pumpTasks()
        #expect(a.refresh.triggerSerial == 1 && a.gate.started == 1 && a.hold.top == 60)
        // Crossed, then back below before the lift: disarmed.
        let b = RefreshRig(path, configs: [.top: cfg])
        b.touchDown()
        b.finger(toPull: 160)
        b.finger(toPull: 70)
        b.lift()
        await b.pumpTasks()
        b.settle()                                              // the indicator retracts with the content
        #expect(b.refresh.triggerSerial == 0 && b.gate.started == 0 && b.hold == EdgeInsets())
        #expect(b.refreshState().mode == .notRefreshing && b.refreshState().dragPosition == 0)
        // Lifted below the trigger.
        let c = RefreshRig(path, configs: [.top: cfg])
        c.pullAndRelease(to: 80)
        await c.pumpTasks()
        #expect(c.refresh.triggerSerial == 0 && c.gate.started == 0 && c.hold == EdgeInsets())
    }

    @Test(arguments: OSPath.allCases) func theHoldOpensAtTheLiftNeverMidDrag(path: OSPath) {
        for mode in [ZTronRefreshTriggerMode.whilePulling, .onRelease] {
            let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(triggerMode: mode)])
            let before = r.boundsY
            r.touchDown()
            r.finger(toPull: 40)
            r.finger(toPull: 130)
            r.finger(toPull: 170)
            r.tick(3)
            #expect(r.state.isTracking && r.pull() > 100)
            #expect(r.hold == EdgeInsets() && r.aci.top == 0 && r.boundsY == before, "\(mode): bounds unchanged under the finger")
            r.lift()
            #expect(r.hold.top == 60 && r.aci.top == 60 && r.boundsY.min == before.min - 60, "\(mode): opened at the lift")
            #expect(r.delegate.log.filter { $0 == "inset" }.count == 1)
        }
    }

    @Test(arguments: OSPath.allCases) func minimumVisibleTimeKeepsTheHoldThenTheTimerClearsIt(path: OSPath) async {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 3)])
        r.pullAndRelease(to: 140)
        let since = r.now
        await r.pumpTasks()
        r.settle()                                              // the spring to the hold position, well under 3 s
        #expect(r.now - since < 3 && abs(r.offset.y + 60) < 0.5)
        await r.completeAction()                                      // the action returns early
        guard case let .finishing(until) = r.engine().phase else { Issue.record("not finishing: \(r.engine().phase)"); return }
        #expect(abs(until - (since + 3)) < 1e-9)
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing, "held until the minimum time")
        #expect(r.wakes.count == 1 && abs(r.wakes[0].delay - (until - r.now)) < 1e-9, "one timer for the remaining time")
        r.clock.t += 1.5
        r.fireWakes()                                           // too early: held, a new timer for the rest
        #expect(r.hold.top == 60 && r.wakes.count == 1)
        r.clock.t = until + 0.01
        r.fireWakes()
        #expect(r.hold == EdgeInsets() && r.aci.top == 0)
        #expect(r.refreshState().mode == .notRefreshing && r.engine().retractLook == .spinner, "the spinner goes with the content")
        r.fireWakes()                                           // the content is already at rest: the next beat ends it
        #expect(r.refreshState().dragPosition == 0)
        #expect(r.engine().phase == .idle && abs(r.offset.y) < 0.5, "back at rest")
        #expect(r.announcements == ["Refreshing", "Refresh complete"])
        // An action slower than the minimum ends at once.
        let s = RefreshRig(path)
        s.pullAndRelease(to: 140)
        await s.pumpTasks()
        s.settle()
        s.clock.t += 5
        await s.completeAction()
        #expect(s.hold == EdgeInsets() && s.engine().retractLook == .spinner)
        s.fireWakes()                                           // the content is already at rest: the next beat ends it
        #expect(s.engine().phase == .idle && s.wakes.isEmpty)
    }

    @Test(arguments: OSPath.allCases) func theResetWaitsForTheLiftWhileTracking(path: OSPath) async {
        let r = RefreshRig(path)
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        #expect(r.hold.top == 60 && abs(r.offset.y + 60) < 0.5)
        // A second pull, from the hold position, while the action returns.
        r.touchDown()
        r.drag(CGSize(width: 0, height: 60))
        #expect(r.state.isTracking && r.offset.y < -60)
        r.clock.t += 2
        await r.completeAction()
        r.tick(10)
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing, "the finger is down: nothing resets under it")
        guard case .finishing = r.engine().phase else { Issue.record("expected finishing, got \(r.engine().phase)"); return }
        r.lift()
        #expect(r.hold == EdgeInsets() && r.refreshState().mode == .notRefreshing, "the lift resets")
        #expect(r.boundsY.min == 0, "the release springs to the cleared bounds")
        r.settle()
        #expect(abs(r.offset.y) < 0.5 && r.state.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func doneIsIdempotentFromAnyThread(path: OSPath) async {
        final class Box: @unchecked Sendable { var done: (@Sendable () -> Void)?; var returned = 0 }
        let box = Box()
        let r = RefreshRig(path)
        let inner = RefresherSpec.awaiting { done in box.done = done }
        r.refresh.setSpecs([.top: RefresherSpec(configuration: ZTronRefreshConfiguration(minimumVisibleTime: 3), action: { edge in
            await inner(edge)
            box.returned += 1
        })])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        guard let done = box.done else { Issue.record("the completion action never started"); return }
        // Many threads race to complete the same refresh, twice.
        DispatchQueue.concurrentPerform(iterations: 16) { _ in done() }
        await r.pumpTasks()
        DispatchQueue.global().async { done() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        done()
        await r.pumpTasks()
        #expect(box.returned == 1, "the continuation resumed exactly once")
        guard case .finishing = r.engine().phase else { Issue.record("expected finishing, got \(r.engine().phase)"); return }
        #expect(r.hold.top == 60, "one done: still inside the minimum visible time")
        r.clock.t += 5
        r.fireWakes()
        r.fireWakes()                                           // the retraction ends on the next beat
        #expect(r.hold == EdgeInsets() && r.engine().phase == .idle)
        #expect(r.announcements.filter { $0 == "Refresh complete" }.count == 1)
    }

    @Test(arguments: OSPath.allCases) func disappearCancelsTheTaskAndClearsUnanimated(path: OSPath) async {
        let r = RefreshRig(path)
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        #expect(r.gate.started == 1 && r.hold.top == 60 && abs(r.offset.y + 60) < 0.5)
        r.refresh.cancelAll()
        #expect(r.gate.cancelled == 1, "the action Task is cancelled")
        #expect(r.hold == EdgeInsets() && r.aci.top == 0)
        #expect(r.engine().phase == .idle && r.refreshState().mode == .notRefreshing && r.refreshState().dragPosition == 0)
        #expect(abs(r.offset.y) < 0.5, "at rest at once, no reset animation")
        #expect(r.state.activeTransactionToken == nil && !r.state.isScrollAnimating && r.state.phase == .idle)
        await r.pumpTasks()
        #expect(r.gate.finished == 1 && r.engine().phase == .idle, "the cancelled action's return is not a completion")
        #expect(!r.announcements.contains("Refresh complete"))
        // The same view can refresh again afterwards.
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        #expect(r.gate.started == 2 && r.hold.top == 60)
    }

    @Test(arguments: OSPath.allCases) func nothingPullsWhileZoomedAboveTheMinimum(path: OSPath) async {
        let r = RefreshRig(path)
        r.state.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        r.state.setZoomScale(2, animated: false)
        let rest = r.offset
        r.state.setContentOffset(CGPoint(x: rest.x, y: 0), animated: false)
        r.touchDown()
        r.finger(toPull: 200)
        #expect(r.refresh.triggerSerial == 0 && r.refreshState().dragPosition == 0 && r.refreshState().mode == .notRefreshing)
        r.lift()
        r.settle()
        await r.pumpTasks()
        #expect(r.gate.started == 0 && r.hold == EdgeInsets(), "disablesWhenZoomed")
    }

    @Test(arguments: OSPath.allCases) func oneRefreshAtATimeAcrossEdges(path: OSPath) async {
        // 400 pt of content in an 800 pt viewport: both edges rest at the same offset and both can be pulled.
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(), .bottom: ZTronRefreshConfiguration.loadMore],
                           content: CGSize(width: 390, height: 400))
        r.pan.settings.bounceY = .basedOnSize                  // a fitting axis would not bounce: the refreshers force it
        #expect(r.pull(.top) == 0 && r.pull(.bottom) == 0, "no phantom pull at rest")
        #expect(r.pan.peekEnvironment().bouncesY)
        r.pullAndRelease(to: 140, edge: .top)
        await r.pumpTasks()
        r.settle()
        #expect(r.refresh.triggerSerial == 1 && r.hold.top == 60)
        // Now pull the other end: the first refresh owns the (global) slot.
        r.touchDown()
        r.drag(CGSize(width: 0, height: -400))
        #expect(r.pull(.bottom) > 100, "pulled well past the bottom trigger")
        r.lift()
        r.settle()
        await r.pumpTasks()
        #expect(r.refresh.triggerSerial == 1 && r.gate.started == 1 && r.hold.bottom == 0)
    }
}
