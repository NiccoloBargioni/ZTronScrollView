import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// The refresh indicator retracts with the content (USER-s6, D39). At the end of a refresh, at a release below the trigger and
/// after an early return (D35) the content is still sliding back to rest when the engine lets go of the pull; the indicator
/// goes with it, as `UIRefreshControl` keeps the spinner glued to the content edge until the gap closes, instead of
/// disappearing on that frame. The numbers are those the leaf draws (`RefreshIndicatorMath` over the live state), frame by frame.
@MainActor
@Suite(.serialized)
struct RefreshRetractTests {
    // MARK: The engine as values

    func input(_ pull: CGFloat, tracking: Bool = true, enabled: Bool = true, settled: Bool = true,
               t: TimeInterval = 0) -> RefreshEngine.Input {
        RefreshEngine.Input(pull: pull, isTracking: tracking, enabled: enabled, isSettled: settled, time: t)
    }

    @Test func aPullLetGoBelowTheTriggerRetractsWithTheContentAndEndsWhenThePullIsGone() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(70, t: 1)))
        #expect(e.handle(.lift(input(70, t: 2), cancelled: false)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
        #expect(e.phase == .retracting(.pull, until: 5) && e.retractLook == .pull)
        #expect(e.mode == .notRefreshing && e.progress == 0.7 && e.isActive && !e.isRefreshing && !e.firedThisPull)
        // The first flush after the lift runs before the release motion has started: nothing is settled-and-idle yet, and
        // the pull has not moved. That must not end it.
        #expect(e.handle(.sample(input(70, tracking: false, settled: true, t: 2))) == [])
        #expect(e.handle(.sample(input(45, tracking: false, settled: false, t: 2.1))) == [.progress(0.45)])
        #expect(e.handle(.sample(input(12, tracking: false, settled: false, t: 2.2))) == [.progress(0.12)])
        #expect(e.phase == .retracting(.pull, until: 5), "still going back")
        #expect(e.handle(.sample(input(0.4, tracking: false, t: 2.3))) == [.progress(0), .retract(nil)])
        #expect(e.phase == .idle && e.progress == 0 && e.mode == .notRefreshing && !e.isActive)
    }

    @Test func aLiftThatLeavesNothingToFollowResetsAtOnce() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(0.3, t: 1)))
        #expect(e.handle(.lift(input(0.3, t: 2), cancelled: false)) == [.progress(0), .mode(.notRefreshing, animated: true)])
        #expect(e.phase == .idle)
        // The touch ends without a release (nothing follows the finger), or the edge is no longer enabled: nothing to follow.
        var s = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = s.handle(.sample(input(70, t: 1)))
        #expect(s.handle(.sequenceEnd(input(70, tracking: false, t: 2))) == [.progress(0), .mode(.notRefreshing, animated: true)])
        var d = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = d.handle(.sample(input(70, t: 1)))
        #expect(d.handle(.lift(input(70, enabled: false, t: 2), cancelled: false)) ==
                [.progress(0), .mode(.notRefreshing, animated: true)])
    }

    @Test func aCancelledTouchBelowTheTriggerRetractsToo() {
        // The release pipeline follows a cancelled touch as well (it springs the content back).
        var e = RefreshEngine(config: ZTronRefreshConfiguration(triggerMode: .onRelease), edge: .top)
        _ = e.handle(.sample(input(150, t: 1)))
        #expect(e.phase == .armed)
        #expect(e.handle(.lift(input(150, t: 2), cancelled: true)) == [.mode(.notRefreshing, animated: true), .retract(.pull)])
        #expect(e.retractLook == .pull && e.progress == 1 && !e.firedThisPull)
    }

    @Test func aRetractionEndsAtItsDeadlineWhenNothingMovesTheContent() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(70, t: 1)))
        _ = e.handle(.lift(input(70, t: 2), cancelled: false))
        #expect(e.handle(.sample(input(70, tracking: false, t: 4.9))) == [])
        #expect(e.handle(.sample(input(70, tracking: false, t: 5))) == [.progress(0), .retract(nil)])
        #expect(e.phase == .idle)
    }

    @Test func aNewPullTakesOverFromARetraction() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(70, t: 1)))
        _ = e.handle(.lift(input(70, t: 2), cancelled: false))
        _ = e.handle(.sample(input(30, tracking: false, t: 2.1)))
        // The finger lands on the content that is still coming back and pulls: a normal pull from there.
        #expect(e.handle(.sample(input(40, t: 2.2))) == [.retract(nil), .mode(.pulling, animated: false), .progress(0.4)])
        #expect(e.phase == .pulling && e.mode == .pulling && e.retractLook == nil)
        // Pulled to the trigger it fires, once.
        #expect(e.handle(.sample(input(120, t: 2.3))).contains(.trigger))
        #expect(e.phase == .triggered && e.firedThisPull)
    }

    @Test func aTouchOnTheRetractingIndicatorFiresAtTheLiftWhenPulledToTheTrigger() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 0.5), edge: .top)
        _ = e.handle(.sample(input(130, t: 0)))
        _ = e.handle(.done(input(140, t: 0.6)))
        _ = e.handle(.lift(input(150, t: 2), cancelled: false))                    // the early return: retracting
        #expect(e.retractLook == .spinner)
        // A catch on the content that is still pulled past the trigger, lifted without moving: a position, like any lift.
        #expect(e.handle(.lift(input(125, t: 2.2), cancelled: false)) ==
                [.retract(nil), .mode(.refreshing, animated: true), .trigger, .announce("Refreshing"), .hold(60, reveal: false)])
        #expect(e.phase == .refreshing(since: 2.2))
    }

    @Test func aRefreshThatEndsKeepsTheSpinnerWhileItRetracts() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(minimumVisibleTime: 0.5), edge: .top)
        _ = e.handle(.lift(input(130, t: 5), cancelled: false))                    // the hold opens
        // The action returns after the minimum visible time, the content sits at the hold (60 of the 100 pt trigger).
        #expect(e.handle(.done(input(60, tracking: false, t: 6))) ==
                [.progress(0.6), .mode(.notRefreshing, animated: true), .retract(.spinner),
                 .clearHold(atLift: false, animated: true), .announce("Refresh complete")])
        #expect(e.phase == .retracting(.spinner, until: 9) && e.mode == .notRefreshing && !e.holdApplied && !e.firedThisPull)
        #expect(e.handle(.sample(input(60, tracking: false, t: 6.01))) == [], "the drawn content has not started to move")
        #expect(e.handle(.sample(input(25, tracking: false, t: 6.2))) == [.progress(0.25)])
        #expect(e.handle(.sample(input(0, tracking: false, t: 6.4))) == [.progress(0), .retract(nil)])
        #expect(e.phase == .idle)
    }

    @Test func aRefreshThatEndsAtTheLiftRetractsAndAResetNobodyAnimatesDoesNot() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.lift(input(130, t: 5), cancelled: false))
        _ = e.handle(.done(input(80, t: 8)))                                       // the finger is down: finishing
        #expect(e.handle(.lift(input(90, t: 10), cancelled: false)) ==
                [.progress(0.9), .mode(.notRefreshing, animated: true), .retract(.spinner),
                 .clearHold(atLift: true, animated: true), .announce("Refresh complete")],
                "the release pipeline springs the offset to the cleared bounds: the spinner goes with it")
        #expect(e.retractLook == .spinner)
        // `resetAnimation: nil` snaps the content to rest: there is nothing to follow, as before.
        var n = RefreshEngine(config: ZTronRefreshConfiguration(resetAnimation: nil), edge: .top)
        _ = n.handle(.lift(input(130, t: 5), cancelled: false))
        #expect(n.handle(.done(input(60, tracking: false, t: 6))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .clearHold(atLift: false, animated: true),
                 .announce("Refresh complete")])
        #expect(n.phase == .idle)
        // The user scrolled away while it refreshed: the indicator is not on screen, nothing to follow either.
        var a = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = a.handle(.lift(input(130, t: 5), cancelled: false))
        #expect(a.handle(.done(input(0, tracking: false, t: 6))).contains(.retract(.spinner)) == false)
        #expect(a.phase == .idle)
    }

    @Test func anEarlyReturnReleaseRetractsWithTheSpinnerAndAMissedLiftDoesNot() {
        var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = e.handle(.sample(input(130, t: 0)))
        _ = e.handle(.done(input(140, t: 0.6)))
        #expect(e.handle(.lift(input(160, t: 2), cancelled: false)) ==
                [.mode(.notRefreshing, animated: true), .retract(.spinner), .announce("Refresh complete")])
        #expect(e.phase == .retracting(.spinner, until: 5) && e.progress == 1 && !e.firedThisPull && !e.holdApplied)
        // No lift was reported: nothing springs the offset, so there is nothing to follow.
        var m = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
        _ = m.handle(.sample(input(130, t: 0)))
        _ = m.handle(.done(input(130, t: 0.2)))
        #expect(m.handle(.sample(input(130, tracking: false, t: 3))) ==
                [.progress(0), .mode(.notRefreshing, animated: true), .announce("Refresh complete")])
        #expect(m.phase == .idle)
    }

    @Test func beginCancelAndDisabledWhileRetracting() {
        func retracting() -> RefreshEngine {
            var e = RefreshEngine(config: ZTronRefreshConfiguration(), edge: .top)
            _ = e.handle(.sample(input(70, t: 1)))
            _ = e.handle(.lift(input(70, t: 2), cancelled: false))
            return e
        }
        // The indicator comes back as a refresh: begin is not swallowed by the retraction.
        var b = retracting()
        #expect(b.handle(.begin(input(40, tracking: false, t: 2.3), runAction: false)) ==
                [.retract(nil), .progress(1), .mode(.refreshing, animated: true), .hold(60, reveal: true), .announce("Refreshing")])
        #expect(b.phase == .refreshing(since: 2.3))
        // Cancel drops it at once.
        var c = retracting()
        #expect(c.handle(.cancel) == [.retract(nil), .progress(0)])
        #expect(c.phase == .idle)
        // Zoomed, scroll disabled or another edge refreshing: no pull to follow any more.
        var d = retracting()
        #expect(d.handle(.sample(input(40, tracking: false, enabled: false, t: 2.1))) == [.progress(0), .retract(nil)])
        // A late `done`, a second lift without a pull and a sequence end leave it alone.
        var l = retracting()
        #expect(l.handle(.done(input(40, tracking: false, t: 2.1))) == [])
        #expect(l.handle(.sequenceEnd(input(40, tracking: false, t: 2.2))) == [])
        #expect(l.handle(.lift(input(40, tracking: false, t: 2.3), cancelled: false)) == [])
        #expect(l.retractLook == .pull)
    }

    // MARK: Through the pan, the state and the coordinator

    /// The frames of a retraction are the frames the leaf draws: the indicator thins out as the content comes back, never grows
    /// back, and `dragPosition` is the live pull over the trigger. It lasts several frames: it does not vanish on the first.
    func expectAGradualRetraction(_ frames: [RefreshRig.RetractFrame], look: RefreshEngine.RetractLook, from visible: CGFloat,
                                  _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(frames.count > 8, "\(what): \(frames.count) frames, not one", sourceLocation: sourceLocation)
        guard let first = frames.first else { return }
        #expect(abs(first.visible - visible) < 0.01, "\(what): starts as drawn (\(first.visible))", sourceLocation: sourceLocation)
        for (a, b) in zip(frames, frames.dropFirst()) {
            #expect(b.visible <= a.visible + 0.001, "\(what): never grows back (\(a.visible) → \(b.visible), pull \(b.pull))",
                    sourceLocation: sourceLocation)
            #expect(b.pull <= a.pull + 0.001, "\(what): the content only comes back", sourceLocation: sourceLocation)
        }
        for f in frames {
            #expect(f.look == look && f.mode == .notRefreshing, "\(what): \(String(describing: f.look)) / \(f.mode)",
                    sourceLocation: sourceLocation)
            #expect(abs(f.progress - min(1, f.pull / 100)) < 1e-6, "\(what): progress \(f.progress) follows the pull \(f.pull)",
                    sourceLocation: sourceLocation)
        }
        #expect(frames.contains { $0.visible > 0.5 && $0.visible < visible - 0.5 }, "\(what): thinner than whole on the way",
                sourceLocation: sourceLocation)
    }

    @Test(arguments: OSPath.allCases, [false, true]) func aPullLetGoBelowTheTriggerRetractsWithTheContent(path: OSPath, overlay: Bool) {
        let r = RefreshRig(path, overlay: overlay)
        r.touchDown()
        r.finger(toPull: 80)
        #expect(r.refreshState().mode == .pulling && abs(r.refreshState().dragPosition - 0.8) < 0.01)
        r.lift()
        #expect(r.engine().retractLook == .pull && r.refresh.retractions[.top] == .pull, "the indicator stays")
        #expect(r.refreshState().mode == .notRefreshing, "custom views read an idle edge with a falling dragPosition")
        #expect(r.wakes.isEmpty, "the clock samples: no heartbeat while it runs")
        let frames = r.retractFrames(overlay: overlay)
        expectAGradualRetraction(frames, look: .pull, from: 60, "pull 80, overlay \(overlay)")
        #expect(r.engine().phase == .idle && r.refresh.retractions[.top] == nil, "gone once the content is back")
        #expect(r.refreshState().dragPosition == 0 && r.refreshState().mode == .notRefreshing)
        #expect(abs(r.offset.y) < 0.5 && r.state.phase == .idle)
        #expect(r.gate.started == 0)
    }

    @Test(arguments: OSPath.allCases, [Edge.leading, Edge.bottom]) func everyEdgeRetractsLikeTheTopOne(path: OSPath, edge: Edge) {
        let horizontal = edge == .leading
        let r = RefreshRig(path, configs: [edge: ZTronRefreshConfiguration()], axes: horizontal ? .horizontal : .vertical,
                           content: horizontal ? CGSize(width: 3000, height: 800) : CGSize(width: 390, height: 3000))
        if edge == .bottom { r.state.setContentOffset(CGPoint(x: 0, y: 2200), animated: false) }     // the end of 3000 pt in 800
        r.touchDown()
        r.finger(toPull: 80, edge: edge)
        r.lift()
        #expect(r.engine(edge).retractLook == .pull && r.refreshState(edge).mode == .notRefreshing)
        let frames = r.retractFrames(edge)
        expectAGradualRetraction(frames, look: .pull, from: 60, "\(edge) pull 80")
        #expect(r.engine(edge).phase == .idle && r.refresh.retractions.isEmpty && r.refreshState(edge).dragPosition == 0)
    }

    @Test(arguments: OSPath.allCases) func aRefreshThatEndsAtTheLiftRetractsWithTheSpinner(path: OSPath) async {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        #expect(r.hold.top == 60 && abs(r.offset.y + 60) < 0.5)
        // A second pull from the hold position, while the action returns: the reset waits for the lift.
        r.touchDown()
        r.drag(CGSize(width: 0, height: 60))
        await r.completeAction()
        r.tick(10)
        #expect(r.refreshState().mode == .refreshing && r.hold.top == 60, "nothing resets under the finger")
        let pullAtLift = r.pull()
        r.lift()
        #expect(r.hold == EdgeInsets() && r.engine().retractLook == .spinner, "the lift clears the hold and the spinner stays")
        let frames = r.retractFrames()
        expectAGradualRetraction(frames, look: .spinner, from: min(pullAtLift, 60), "reset at the lift")
        #expect(r.engine().phase == .idle && r.refresh.retractions[.top] == nil && abs(r.offset.y) < 0.5)
        #expect(r.announcements.filter { $0 == "Refresh complete" }.count == 1)
    }

    @Test(arguments: OSPath.allCases) func aRefreshThatEndsOnTheClockRetractsWithTheSpinner(path: OSPath) async {
        // `resetAnimation: .uikit`: the clock animates the offset to rest, so the frames sample the pull.
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0, resetAnimation: .uikit)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        await r.completeAction()                                          // no minimum visible time: the reset runs now
        #expect(r.hold == EdgeInsets() && r.state.phase == .animating)
        #expect(r.engine().retractLook == .spinner && r.refreshState().mode == .notRefreshing)
        #expect(r.wakes.isEmpty, "the clock samples: no heartbeat while it runs")
        let frames = r.retractFrames()
        expectAGradualRetraction(frames, look: .spinner, from: 60, "uikit reset")
        #expect(r.engine().phase == .idle && abs(r.offset.y) < 0.5 && r.state.phase == .idle)
        #expect(r.announcements == ["Refreshing", "Refresh complete"])
    }

    @Test(arguments: OSPath.allCases) func aResetThatSwiftUIAnimatesIsFollowedThroughTheDrawnContent(path: OSPath) async {
        // The default reset: the state's offset jumps to rest and SwiftUI animates the drawing, with the clock idle. The engine
        // follows what was last drawn (the content effect's probe) on its own beat.
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        func drawn(_ y: CGFloat) { r.state.probe.record(CGPoint(x: 0, y: y), 1) }
        drawn(-60)
        await r.completeAction()                                          // no minimum visible time: the reset runs now
        #expect(r.hold == EdgeInsets() && abs(r.offset.y) < 0.5, "the state is already at rest")
        #expect(r.engine().retractLook == .spinner && r.refreshState().mode == .notRefreshing)
        #expect(abs(r.refreshState().dragPosition - 0.6) < 1e-9, "the pull at the hold: 60 of 100")
        #expect(r.pull() == 0 && r.visibleIndicator() == 0, "the state's pull alone is already gone")
        #expect(r.wakes.count == 1, "a beat is armed: the clock is idle")
        var beats = 0
        for y in [-60, -48, -30, -12, -3] as [CGFloat] {
            drawn(y)
            r.clock.t += 1.0 / 30
            r.fireWakes()
            beats += 1
            #expect(r.engine().retractLook == .spinner, "the content is still drawn \(-y) pt away")
            #expect(abs(r.refreshState().dragPosition - (-y) / 100) < 1e-9, "dragPosition \(r.refreshState().dragPosition) at \(y)")
            #expect(r.wakes.count == 1, "one beat at a time")
        }
        drawn(-0.2)
        r.clock.t += 1.0 / 30
        r.fireWakes()
        #expect(r.engine().phase == .idle && r.refresh.retractions[.top] == nil && r.refreshState().dragPosition == 0)
        #expect(r.wakes.isEmpty && beats == 5, "no beat once it is over")
    }

    @Test(arguments: OSPath.allCases) func aContentThatIsNeverDrawnEndsAtTheDeadline(path: OSPath) async {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        r.state.probe.record(CGPoint(x: 0, y: -60), 1)                      // the last drawn frame, and no other
        await r.completeAction()
        let until = r.now + RefreshEngine.retractTimeout
        #expect(r.engine().retractLook == .spinner)
        r.clock.t = until - 0.1
        r.fireWakes()
        #expect(r.engine().retractLook == .spinner, "not yet")
        r.clock.t = until + 0.01
        r.fireWakes()
        #expect(r.engine().phase == .idle && r.refresh.retractions[.top] == nil && r.refreshState().dragPosition == 0)
    }

    @Test(arguments: OSPath.allCases) func aResetNobodyAnimatesLeavesNothingToRetract(path: OSPath) async {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0, resetAnimation: nil)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        await r.completeAction()
        #expect(r.engine().phase == .idle && r.refresh.retractions.isEmpty && r.refreshState().dragPosition == 0)
        #expect(r.wakes.isEmpty && abs(r.offset.y) < 0.5)
    }

    @Test(arguments: OSPath.allCases) func aNewPullTakesOverFromTheRetractionAndCanFire(path: OSPath) async {
        let r = RefreshRig(path)
        r.touchDown()
        r.finger(toPull: 80)
        r.lift()
        r.tick(8)                                                           // mid spring-back
        #expect(r.engine().retractLook == .pull && r.pull() > 0.5)
        // The finger lands on the content that is still coming back, and pulls it on.
        r.touchDown()
        r.drag(CGSize(width: 0, height: 20))
        #expect(r.state.isTracking)
        #expect(r.refresh.retractions[.top] == nil && r.engine().phase == .pulling && r.refreshState().mode == .pulling,
                "a normal pull again: \(r.engine().phase)")
        r.drag(CGSize(width: 0, height: 600))
        #expect(r.refresh.triggerSerial == 1 && r.engine().phase == .triggered, "pulled to the trigger it fires")
        r.lift()
        await r.pumpTasks()
        r.settle()
        #expect(r.gate.started == 1 && r.hold.top == 60)
    }

    @Test(arguments: OSPath.allCases) func beginRefreshingWhileTheIndicatorRetractsIsNotSwallowed(path: OSPath) {
        let r = RefreshRig(path)
        r.touchDown()
        r.finger(toPull: 80)
        r.lift()
        r.tick(8)
        #expect(r.engine().retractLook == .pull)
        r.state.beginRefreshing()
        #expect(r.engine().phase == .refreshing(since: r.now) && r.refresh.retractions[.top] == nil)
        #expect(r.refreshState().mode == .refreshing && r.hold.top == 60)
        r.settle()
        #expect(abs(r.offset.y + 60) < 0.5, "revealed at the hold")
    }

    // MARK: Hosted: the animated reset, drawn for real

    /// `look=` and `vis=` of the leaf lines of the DEBUG trace (`RefreshTrace`: one line per change of what the leaf draws).
    func leafLines() -> [(look: String, vis: Double)] {
        ZTronRenderCounters.events.filter { $0.contains(" rf leaf ") }.map { line in
            func field(_ key: String) -> String {
                line.components(separatedBy: " ").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
            }
            return (field("look"), Double(field("vis")) ?? -1)
        }
    }

    /// The default reset (`.swiftUI`): the state's offset jumps to rest while SwiftUI animates the drawing. In a real hierarchy the
    /// leaf is interpolated by the same transaction, so what it draws thins out frame by frame instead of vanishing at once, and
    /// the engine ends the retraction when the content has been drawn back at rest. No content body runs meanwhile.
    @Test(arguments: OSPath.allCases) func aResetThatSwiftUIAnimatesCarriesTheIndicatorWithTheContent(path: OSPath) async {
        // Async on purpose: the engine's beat is a dispatch timer, which a nested run loop inside a main-queue job never runs.
        func wait(_ seconds: TimeInterval) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        let counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }.refresher { })
        }
        defer { unhost(w); ZTronRenderCounters.eventCapacity = 40; ZTronRenderCounters.reset() }
        await wait(0.3)
        guard let refresh = s.refresh else { Issue.record("no refresh coordinator"); return }
        ZTronRenderCounters.reset()
        ZTronRenderCounters.eventCapacity = 3000
        s.beginRefreshing()
        await wait(1.2)                                                   // revealed at the hold, shown past the minimum time
        #expect(s.refreshHoldInset.top == 60 && refresh.states[.top]?.mode == .refreshing)
        let bodies = counts.bodies
        let before = leafLines().count
        s.endRefreshing()
        await wait(0.1)
        #expect(s.refreshHoldInset.top == 0 && refresh.states[.top]?.mode == .notRefreshing, "the refresh is over")
        await wait(1.5)
        let retracting = leafLines().dropFirst(before).filter { $0.look == "spinner" }
        #expect(retracting.count >= 4, "the indicator thins out over several frames: \(retracting.map { Int($0.vis) })")
        #expect(zip(retracting, retracting.dropFirst()).allSatisfy { $1.vis <= $0.vis + 0.001 }, "never grows back")
        #expect((retracting.first?.vis ?? 0) >= 59 && (retracting.last?.vis ?? 99) < 4, "from whole to nothing")
        let rest = -s.adjustedContentInset.top                               // the test window has a safe area of its own
        let diag = "phase \(String(describing: refresh.engines[.top]?.phase)), retractions \(refresh.retractions), y \(s.contentOffset.y) (rest \(rest))"
        #expect(refresh.engines[.top]?.phase == .idle && refresh.retractions.isEmpty, "gone once the content is back: \(diag)")
        #expect(refresh.states[.top]?.dragPosition == 0 && abs(s.contentOffset.y - rest) < 0.5, "p \(String(describing: refresh.states[.top]?.dragPosition)), \(diag)")
        #expect(counts.bodies == bodies, "retracting never re-evaluates the content")
    }

    @Test(arguments: OSPath.allCases) func theViewDisappearingDropsARetractingIndicatorAtOnce(path: OSPath) {
        let r = RefreshRig(path)
        r.touchDown()
        r.finger(toPull: 80)
        r.lift()
        r.tick(4)
        #expect(r.refresh.retractions[.top] == .pull)
        r.refresh.cancelAll()
        #expect(r.engine().phase == .idle && r.refresh.retractions.isEmpty && r.refreshState().dragPosition == 0)
    }
}
