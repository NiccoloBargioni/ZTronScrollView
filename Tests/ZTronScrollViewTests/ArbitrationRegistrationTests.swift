import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
import ScrollArbitration
@testable import ZTronScrollView

/// The public registration (docs/design/NESTED-mixed.md §1): any `ScrollArbitrationParticipant` object registered with
/// the nearest arbiter through `ZTronScrollArbitrationRegistration` / `ztronScrollArbitrationParticipant(_:)`, here with
/// a fake participant as the inner of a nested `ZTronScrollView` (the outer is the `NestedArbitrationTests` pager), on
/// both OS paths. The decision tests drive the registration the way the modifier does (`setArbiter`, then `register`
/// with the frame); the hosted tests go through the real modifier.
@MainActor
@Suite(.serialized)
struct ArbitrationRegistrationTests {
    /// A scroller that is not ours: answers are plain stored values, every `canFollow` question is recorded.
    @MainActor final class FakePanel: ScrollArbitrationParticipant {
        var follows: Set<FingerDirection> = []
        var isMovingWithoutFinger = false
        var isZoomEnabled = false
        private(set) var asked: [FingerDirection] = []
        func canFollow(_ direction: FingerDirection) -> Bool {
            asked.append(direction)
            return follows.contains(direction)
        }
    }

    typealias Side = NestedArbitrationTests.Side
    typealias Clock = NestedArbitrationTests.Clock

    /// A horizontal 3 × 100 pt pager (the outer) with `fake` registered through the public type at page 0's frame.
    @MainActor struct Harness {
        let outer: Side
        let clock: Clock
        let reg: ZTronScrollArbitrationRegistration
        let fake: FakePanel
        var arbiter: NestedScrollArbiter { outer.coord.nestedArbiter }
        var now: TimeInterval {
            get { clock.t }
            nonmutating set { clock.t = newValue }
        }
        var decisions: Int {
            arbiter.log.filter {
                if case let .owner(_, _, _, _, _, _, _, _, decided, _) = $0 { return decided }
                return false
            }.count
        }
        var sequenceEntries: Int {
            arbiter.log.filter {
                switch $0 {
                case .register, .update, .unregister: return false
                default: return true
                }
            }.count
        }
    }

    enum Order { case outerAsksFirst, registrationAsksFirst }

    let nested = NestedArbitrationTests()
    let start = CGPoint(x: 50, y: 100)
    let page0 = CGRect(x: 0, y: 0, width: 100, height: 200)

    func make(_ path: OSPath, follows: Set<FingerDirection> = [], moving: Bool = false, zoomEnabled: Bool = true,
              axes: Axis.Set = .horizontal) -> Harness {
        let clock = Clock()
        let outer = nested.makeSide(path, axes: axes, content: CGSize(width: 300, height: 200), offset: .zero,
                                    paging: true, clock: clock)
        let fake = FakePanel()
        fake.follows = follows
        fake.isMovingWithoutFinger = moving
        fake.isZoomEnabled = zoomEnabled
        let reg = ZTronScrollArbitrationRegistration()
        reg.participant = fake
        reg.setArbiter(outer.coord.nestedArbiter)      // what the modifier does from its body
        reg.registrar?.register(frame: page0)         // and its frame reader on appear
        outer.clearLogs()
        return Harness(outer: outer, clock: clock, reg: reg, fake: fake)
    }

    // MARK: scripted outer touch

    func down(_ h: Harness, touches: Int = 1) {
        h.outer.coord.handle(.touchDown(location: start, time: h.now, touchCount: touches))
    }

    /// The recognition sample (the outer asks here) and one more.
    func drag(_ h: Harness, dx: CGFloat, dy: CGFloat) {
        h.now += 0.02
        h.outer.coord.handle(.dragChanged(translation: CGSize(width: dx, height: dy), startLocation: start, time: h.now))
        h.now += 0.016
        h.outer.coord.handle(.dragChanged(translation: CGSize(width: dx * 1.5, height: dy * 1.5), startLocation: start,
                                          time: h.now))
        h.outer.state.step(to: Date(timeIntervalSinceReferenceDate: h.now))
    }

    func lift(_ h: Harness, dx: CGFloat, dy: CGFloat) {
        h.now += 0.016
        h.outer.coord.handle(.dragEnded(translation: CGSize(width: dx * 1.5, height: dy * 1.5), time: h.now,
                                        fallbackVelocity: nil))
        h.outer.coord.handle(.touchesEnded(time: h.now))
    }

    /// The UIKit side's question at its own pan slop; `startLocation` is local to the registered view (page 0: = outer's).
    func ask(_ h: Harness, dx: CGFloat, dy: CGFloat, touches: Int = 1) -> ScrollOwner {
        h.reg.owner(ofDragFrom: start, translation: CGSize(width: dx, height: dy), touchCount: touches)
    }

    func kinds(_ arbiter: ReferenceScrollArbiter) -> [String] {
        arbiter.log.map { e -> String in
            switch e {
            case .register: "register"
            case let .update(_, _, known): "update\(known)"
            case let .unregister(_, known): "unregister\(known)"
            default: "other"
            }
        }
    }

    // MARK: register / update / unregister through the public type

    @Test(arguments: OSPath.allCases) func registerUpdateUnregister(path: OSPath) {
        let arbiter = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "reg.test")
        let fake = FakePanel()
        let reg = ZTronScrollArbitrationRegistration()
        reg.participant = fake
        #expect(!reg.isRegistered)                                          // no arbiter yet
        reg.setArbiter(arbiter)
        #expect(!reg.isRegistered && arbiter.log.isEmpty)                   // not placed yet: nothing registered
        let registrar = reg.registrar!
        registrar.register(frame: CGRect(x: 10, y: 20, width: 100, height: 200))
        #expect(reg.isRegistered && arbiter.participant(at: CGPoint(x: 50, y: 100)) != nil)
        registrar.update(frame: CGRect(x: 110, y: 20, width: 100, height: 200))
        registrar.update(frame: CGRect(x: 110, y: 20, width: 100, height: 200))   // unchanged: no call
        #expect(arbiter.participant(at: CGPoint(x: 50, y: 100)) == nil && arbiter.participant(at: CGPoint(x: 150, y: 100)) != nil)
        registrar.unregister()
        registrar.unregister()                                              // second is a no-op
        registrar.update(frame: CGRect(x: 0, y: 0, width: 1, height: 1))     // ignored while unregistered
        #expect(!reg.isRegistered)
        #expect(kinds(arbiter) == ["register", "updatetrue", "unregistertrue"])
    }

    @Test(arguments: OSPath.allCases) func participantSetAfterTheModifierAndClearedLater(path: OSPath) {
        let arbiter = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "reg.test")
        let reg = ZTronScrollArbitrationRegistration()
        reg.setArbiter(arbiter)
        reg.registrar?.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        reg.registrar?.update(frame: CGRect(x: 5, y: 0, width: 100, height: 200))   // placed, still no participant
        #expect(!reg.isRegistered && arbiter.log.isEmpty)
        // The participant arrives after the view appeared: registers with the latest frame.
        let a = FakePanel()
        reg.participant = a
        #expect(reg.isRegistered)
        if case let .register(_, frame) = arbiter.log.last { #expect(frame == CGRect(x: 5, y: 0, width: 100, height: 200)) }
        else { Issue.record("not registered: \(arbiter.log)") }
        reg.participant = a                                                 // same object: nothing
        #expect(kinds(arbiter) == ["register"])
        // Cleared: unregistered; a frame change meanwhile is remembered for the next one.
        reg.participant = nil
        #expect(!reg.isRegistered)
        reg.registrar?.update(frame: CGRect(x: 7, y: 0, width: 100, height: 200))
        #expect(kinds(arbiter) == ["register", "unregistertrue"])
        let b = FakePanel()
        reg.participant = b
        #expect(reg.isRegistered)
        if case let .register(_, frame) = arbiter.log.last { #expect(frame.minX == 7) } else { Issue.record("not registered") }
        // Another object while registered: the old registration goes, the new one comes.
        let c = FakePanel()
        reg.participant = c
        #expect(reg.isRegistered && kinds(arbiter).suffix(2) == ["unregistertrue", "register"])
        // The view disappears: gone; it registers again when the view does (the participant is still set).
        reg.registrar?.unregister()
        #expect(!reg.isRegistered)
        reg.registrar?.register(frame: page0)
        #expect(reg.isRegistered)
        // The participant dies with the registration still placed: it no longer counts as registered, and the next
        // object replaces the stale registration.
        do { let temporary = FakePanel(); reg.participant = temporary }
        #expect(!reg.isRegistered)
        let d = FakePanel()
        reg.participant = d
        #expect(reg.isRegistered)
        withExtendedLifetime((a, b, c, d)) {}
    }

    @Test(arguments: OSPath.allCases) func theArbiterOfTheEnvironmentIsFollowed(path: OSPath) {
        let a = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "reg.a")
        let b = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "reg.b")
        let fake = FakePanel()
        let reg = ZTronScrollArbitrationRegistration()
        reg.participant = fake
        reg.setArbiter(a)
        reg.setArbiter(a)                                                   // same instance: nothing
        reg.registrar?.register(frame: page0)
        #expect(reg.isRegistered && kinds(a) == ["register"])
        // A new instance: unregistered from the old one at once; the new registrar registers when its reader appears.
        reg.setArbiter(b)
        #expect(!reg.isRegistered && kinds(a) == ["register", "unregistertrue"] && b.log.isEmpty)
        reg.registrar?.register(frame: CGRect(x: 1, y: 2, width: 100, height: 200))
        #expect(reg.isRegistered && kinds(b) == ["register"] && kinds(a).count == 2)
        // No arbiter any more: unregistered, and `owner` is ours.
        reg.setArbiter(nil)
        #expect(!reg.isRegistered && kinds(b) == ["register", "unregistertrue"] && reg.registrar == nil)
        #expect(reg.owner(ofDragFrom: start, translation: CGSize(width: -40, height: 0), touchCount: 1) == .participant)
        withExtendedLifetime(fake) {}
    }

    // MARK: owner before registration

    @Test(arguments: OSPath.allCases) func ownerBeforeRegistrationIsParticipant(path: OSPath) {
        let reg = ZTronScrollArbitrationRegistration()
        let fake = FakePanel()
        reg.participant = fake
        // No arbiter at all.
        #expect(reg.owner(ofDragFrom: start, translation: CGSize(width: -40, height: 0), touchCount: 1) == .participant)
        #expect(reg.owner(ofDragFrom: start, translation: CGSize(width: -40, height: 0), touchCount: 2) == .participant)
        // An arbiter, but the view has not appeared: still ours, and the arbiter hears nothing.
        let clock = Clock()
        let outer = nested.makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), offset: .zero,
                                    paging: true, clock: clock)
        reg.setArbiter(outer.coord.nestedArbiter)
        #expect(reg.owner(ofDragFrom: start, translation: CGSize(width: -40, height: 0), touchCount: 1) == .participant)
        #expect(outer.coord.nestedArbiter.log.isEmpty && !outer.coord.nestedArbiter.isSequenceActive)
        // Appeared, then gone: ours again.
        reg.registrar?.register(frame: page0)
        reg.registrar?.unregister()
        #expect(reg.owner(ofDragFrom: start, translation: CGSize(width: -40, height: 0), touchCount: 1) == .participant)
        #expect(outer.coord.nestedArbiter.log.filter { if case .owner = $0 { return true } else { return false } }.isEmpty)
        #expect(fake.asked.isEmpty)
    }

    // MARK: owner through a nested arbiter, the fake as the inner

    /// §1 of NESTED-arbitration with the fake as the inner, in both asking orders: the decision is cached across the
    /// outer's `containerOwner` and the registration's `owner`, and the loser is frozen.
    @Test(arguments: OSPath.allCases, [Order.outerAsksFirst, .registrationAsksFirst])
    func ownerThroughTheNestedArbiter(path: OSPath, order: Order) {
        struct Row {
            let name: String
            var follows: Set<FingerDirection> = []
            var moving = false
            var dx: CGFloat = -40
            var dy: CGFloat = 0
            let expected: ScrollOwner
        }
        let rows = [
            Row(name: "zoom 1, content fits: the outer pages", expected: .container),
            Row(name: "zoomed mid: the fake pans", follows: [.left, .right], expected: .participant),
            Row(name: "zoomed at the edge: the outer pages", follows: [.right], expected: .container),
            Row(name: "off-axis (rule 1): the fake keeps it", dx: 0, dy: -40, expected: .participant),
            Row(name: "moving at touch-down (rule 3): the fake keeps the catch", moving: true, expected: .participant),
        ]
        for row in rows {
            let h = make(path, follows: row.follows, moving: row.moving)
            down(h)
            var owner = ScrollOwner.participant
            switch order {
            case .outerAsksFirst:
                drag(h, dx: row.dx, dy: row.dy)
                owner = ask(h, dx: row.dx, dy: row.dy)
            case .registrationAsksFirst:
                owner = ask(h, dx: row.dx, dy: row.dy)
                drag(h, dx: row.dx, dy: row.dy)
            }
            #expect(owner == row.expected, Comment(rawValue: row.name))
            #expect(h.decisions == 1, Comment(rawValue: row.name))
            #expect(h.arbiter.currentOwner == row.expected, Comment(rawValue: row.name))
            if row.expected == .container {
                #expect(h.outer.dragged && h.outer.offset.x > 0, Comment(rawValue: row.name))
            } else {
                nested.expectLoser(h.outer, offset: .zero, Comment(rawValue: row.name))
            }
            lift(h, dx: row.dx, dy: row.dy)
            #expect(!h.arbiter.isSequenceActive && h.arbiter.currentOwner == nil, Comment(rawValue: row.name))
            #expect(!h.fake.asked.isEmpty, Comment(rawValue: row.name))
        }
    }

    @Test(arguments: OSPath.allCases) func twoFingersFollowTheFakesZoom(path: OSPath) {
        // A pinch on a zoomable scroller never pages (rule 2) ...
        let zooming = make(path, zoomEnabled: true)
        down(zooming, touches: 2)
        #expect(zooming.outer.movementEffects.isEmpty)                      // the outer's pan ignores a two-finger touch-down
        #expect(ask(zooming, dx: -40, dy: 0, touches: 2) == .participant)
        zooming.outer.coord.handle(.touchesEnded(time: zooming.now))
        #expect(!zooming.arbiter.isSequenceActive)
        // ... and on a fixed one the container takes it.
        let fixed = make(path, zoomEnabled: false)
        down(fixed, touches: 2)
        #expect(ask(fixed, dx: -40, dy: 0, touches: 2) == .container)
        fixed.outer.coord.handle(.touchesEnded(time: fixed.now))
        #expect(!fixed.arbiter.isSequenceActive)
    }

    @Test(arguments: OSPath.allCases, NestedArbitrationTests.OuterDisabled.allCases)
    func disabledOuterAnswersParticipantWithoutADecision(path: OSPath, how: NestedArbitrationTests.OuterDisabled) {
        // The fake could not follow, which rule 6 would hand to the outer: a container that cannot take a swipe does not.
        let h = make(path, axes: how == .noAxis ? [] : .horizontal)
        switch how {
        case .state: h.outer.state.isScrollEnabled = false
        case .native: h.outer.coord.nativeScrollEnabled = false
        case .noAxis: break
        }
        #expect(h.arbiter.hasParticipants && !h.arbiter.isArbitrating)
        down(h)
        #expect(!h.arbiter.isSequenceActive)
        #expect(ask(h, dx: -40, dy: 0) == .participant)
        #expect(h.sequenceEntries == 0 && h.decisions == 0 && !h.arbiter.isSequenceActive && h.fake.asked.isEmpty)
        // Re-enabled, the same question decides (the gate is read per touch).
        switch how {
        case .state: h.outer.state.isScrollEnabled = true
        case .native: h.outer.coord.nativeScrollEnabled = true
        case .noAxis: return
        }
        h.outer.coord.handle(.touchesEnded(time: h.now))
        down(h)
        #expect(ask(h, dx: -40, dy: 0) == .container && h.decisions == 1)
    }

    // MARK: sequences begun by an ask

    @Test(arguments: OSPath.allCases) func lazilyBegunSequenceIsSupersededByARealTouchDown(path: OSPath) {
        let h = make(path, follows: [.left, .right])
        // A drag the outer's pan never recognized (a tiny one: the outer saw no touch-down): the ask begins a sequence
        // lazily, the fake wins it, and nothing will tell the arbiter that it ended.
        #expect(ask(h, dx: -40, dy: 0) == .participant)
        #expect(h.arbiter.isSequenceActive && h.arbiter.currentOwner == .participant)
        // The fake is at an edge now, and the next swipe starts with a real touch-down on the outer: a fresh sequence.
        h.fake.follows = []
        down(h)
        #expect(h.arbiter.isSequenceActive && h.arbiter.currentOwner == nil)
        drag(h, dx: -40, dy: 0)
        #expect(ask(h, dx: -40, dy: 0) == .container)
        #expect(h.outer.dragged && h.outer.offset.x > 0)
        #expect(h.decisions == 1, "the log was cleared by the new sequence; one decision")
        lift(h, dx: -40, dy: 0)
        #expect(!h.arbiter.isSequenceActive)
    }

    @Test(arguments: OSPath.allCases) func aSequenceTheOuterBeganIsNotSuperseded(path: OSPath) {
        let h = make(path, follows: [.left, .right])
        down(h)
        #expect(ask(h, dx: -40, dy: 0) == .participant)
        h.fake.follows = []
        h.arbiter.beginSequence()                                          // a no-op while the outer's sequence is active
        #expect(h.arbiter.currentOwner == .participant && h.decisions == 1)
        #expect(ask(h, dx: -40, dy: 0) == .participant, "cached for the whole sequence")
        h.outer.coord.handle(.touchesEnded(time: h.now))
        #expect(!h.arbiter.isSequenceActive)
    }

    @Test(arguments: OSPath.allCases) func registrationSequenceEndedClosesOnlyALazySequence(path: OSPath) {
        let h = make(path, follows: [.left, .right])
        _ = ask(h, dx: -40, dy: 0)                                          // lazy
        #expect(h.arbiter.isSequenceActive)
        h.reg.registrar?.registrationSequenceEnded()
        #expect(!h.arbiter.isSequenceActive)
        down(h)                                                             // the outer's own
        _ = ask(h, dx: -40, dy: 0)
        h.reg.registrar?.registrationSequenceEnded()
        #expect(h.arbiter.isSequenceActive, "the outer ends the sequence it began")
        h.outer.coord.handle(.touchesEnded(time: h.now))
        #expect(!h.arbiter.isSequenceActive)
    }

    // MARK: the real modifier, hosted

    @MainActor final class HostedModel: ObservableObject {
        @Published var show = true
        @Published var lead: CGFloat = 20
        @Published var useB = false
        @Published var unrelated = 0
    }

    /// The registered view sits at (lead, 30) with a 60 × 40 size inside a 200 × 200 box that names both arbiters' spaces.
    struct HostedTree: View {
        @ObservedObject var model: HostedModel
        let a: ReferenceScrollArbiter
        let b: ReferenceScrollArbiter
        let reg: ZTronScrollArbitrationRegistration

        var body: some View {
            let arbiter: ReferenceScrollArbiter = model.useB ? b : a
            return ZStack(alignment: .topLeading) {
                if model.show {
                    Color.clear.frame(width: 60, height: 40)
                        .ztronScrollArbitrationParticipant(reg)
                        .padding(.leading, model.lead).padding(.top, 30)
                }
            }
            .frame(width: 200, height: 200, alignment: .topLeading)
            .coordinateSpace(name: a.coordinateSpaceName)
            .coordinateSpace(name: b.coordinateSpaceName)
            .environment(\.scrollArbiter, arbiter)
        }
    }

    func registered(_ arbiter: ReferenceScrollArbiter) -> [CGRect] {
        arbiter.log.compactMap { if case let .register(_, frame) = $0 { return frame } else { return nil } }
    }

    func updated(_ arbiter: ReferenceScrollArbiter) -> [CGRect] {
        arbiter.log.compactMap { if case let .update(_, frame, true) = $0 { return frame } else { return nil } }
    }

    @Test(arguments: OSPath.allCases) func modifierRegistersAtAppearAndUnregistersAtDisappear(path: OSPath) {
        let a = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "hosted.a")
        let b = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "hosted.b")
        let model = HostedModel()
        let reg = ZTronScrollArbitrationRegistration()
        let fake = FakePanel()
        reg.participant = fake
        let w = host(HostedTree(model: model, a: a, b: b, reg: reg))
        // Appeared: registered once, with the frame in the arbiter's space.
        #expect(reg.isRegistered)
        #expect(registered(a) == [CGRect(x: 20, y: 30, width: 60, height: 40)] && updated(a).isEmpty, "\(a.log)")
        // The UIKit side's `startLocation` is local to the view: (10, 10) there is (30, 40) in the arbiter's space.
        #expect(reg.owner(ofDragFrom: CGPoint(x: 10, y: 10), translation: CGSize(width: -40, height: 0), touchCount: 1) == .container)
        #expect(a.log.contains { if case let .owner(_, _, start, _, _, _, resolved, _, _, _) = $0 { return start == CGPoint(x: 30, y: 40) && resolved != nil } else { return false } })
        // Cold: unrelated re-evaluations of the host do nothing; a frame change is one update.
        let before = a.log.count
        model.unrelated += 1
        pump(0.1)
        #expect(a.log.count == before)
        model.lead = 50
        pump(0.1)
        #expect(updated(a) == [CGRect(x: 50, y: 30, width: 60, height: 40)] && registered(a).count == 1, "\(a.log)")
        model.lead = 70
        model.lead = 90
        pump(0.1)
        #expect(updated(a).count == 2 && updated(a).last == CGRect(x: 90, y: 30, width: 60, height: 40), "\(updated(a))")
        // Another arbiter in the environment: the old one hears the unregistration, the new one the registration with the
        // frame in its own space.
        model.useB = true
        pump(0.1)
        #expect(kinds(a).last == "unregistertrue" && reg.isRegistered)
        #expect(registered(b) == [CGRect(x: 90, y: 30, width: 60, height: 40)], "\(b.log)")
        #expect(reg.registrar?.arbiter === b)
        // The view goes: unregistered; the participant stays set and registers again with the view.
        model.show = false
        pump(0.1)
        #expect(!reg.isRegistered && kinds(b).last == "unregistertrue")
        model.show = true
        pump(0.1)
        #expect(reg.isRegistered && registered(b).count == 2)
        // The participant is cleared: unregistered, the view stays.
        reg.participant = nil
        #expect(!reg.isRegistered && kinds(b).last == "unregistertrue")
        withExtendedLifetime((w, fake)) {}
    }
}
