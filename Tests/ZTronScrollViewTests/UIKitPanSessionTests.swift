import Foundation
import SwiftUI
import Testing
import ScrollArbitration
import ZTronScrollPhysics
@testable import ZTronScrollView

/// `PanSession` on the UIKit path (D60; docs/design/UIKIT-pan.md §2 at 9e6d448): `.declined` in every phase and its
/// settle effect, the F1 full credit of UIKit's recognition sample, the revival of a swipe yielded to an inner view that
/// declines it, and the lift order (the observer's lift before the pan's `.ended`).
@Suite struct UIKitPanSessionTests {
    static func env(_ edit: (inout PanEnvironment) -> Void = { _ in }) -> PanEnvironment {
        PanSessionTests.env { $0.presentationOffset = CGPoint(x: 30, y: 250); edit(&$0) }
    }
    static let start = CGPoint(x: 50, y: 100)

    func down(_ s: inout PanSession, _ e: PanEnvironment, t: TimeInterval = 1, count: Int = 1) -> [PanEffect] {
        s.handle(.touchDown(location: Self.start, time: t, touchCount: count), env: e)
    }
    func drag(_ s: inout PanSession, _ e: PanEnvironment, _ dx: CGFloat, _ dy: CGFloat, t: TimeInterval = 1.1) -> [PanEffect] {
        s.handle(.dragChanged(translation: CGSize(width: dx, height: dy), startLocation: Self.start, time: t), env: e)
    }
    func lastOffset(_ fx: [PanEffect]) -> CGPoint? {
        for f in fx.reversed() { if case let .setOffset(p) = f { return p } }
        return nil
    }

    // MARK: .declined

    enum Phase: String, CaseIterable, Sendable { case idle, touching, caught, awaiting, ignored, dragging, released }

    /// Drives a fresh session (hysteresis 10, as in the app) into `phase` through events only.
    func session(in phase: Phase) -> (PanSession, PanEnvironment) {
        var s = PanSession()
        var e = Self.env()
        switch phase {
        case .idle: break
        case .touching: _ = down(&s, e)
        case .caught:
            e.isMovingWithoutFinger = true
            #expect(down(&s, e) == [.catchMotion, .beginTracking])
            e.isMovingWithoutFinger = false
        case .awaiting:
            e.hasArbiter = true
            _ = down(&s, e)
            _ = drag(&s, e, -20, 0)
        case .ignored: _ = down(&s, e, count: 2)
        case .dragging:
            _ = down(&s, e)
            _ = drag(&s, e, -20, 0)
        case .released:
            _ = down(&s, e)
            _ = drag(&s, e, -20, 0)
            _ = s.handle(.dragEnded(translation: CGSize(width: -20, height: 0), time: 1.2, fallbackVelocity: nil), env: e)
        }
        return (s, e)
    }

    /// §2 "Decline": a caught touch settles (once); every other phase waits for the touch's end.
    @Test(arguments: Phase.allCases) func declinedInEveryPhase(phase: Phase) {
        var (s, e) = session(in: phase)
        let before = s.phase
        let fx = s.handle(.declined, env: e)
        switch phase {
        case .caught:
            #expect(fx == [.settle])
            #expect(s.phase == .touching(down: 1, caught: false))
        case .released:
            #expect(fx.isEmpty && s.phase == .idle)
        default:
            #expect(fx.isEmpty && s.phase == before)
        }
        #expect(s.handle(.declined, env: e).isEmpty, "a second decline (impossible from the core) does nothing")
    }

    @Test func aSettledCatchEndsWithTheTouch() {
        var (s, e) = session(in: .caught)
        #expect(s.handle(.declined, env: e) == [.settle])
        #expect(s.handle(.frame(time: 1.3), env: e).isEmpty)
        #expect(s.handle(.touchesEnded(time: 1.5), env: e) == [.endSequence])
        #expect(s.phase == .idle)
    }

    // MARK: F1: full credit of UIKit's recognition sample

    /// U1 Q5: UIKit's translation at `.began` is 0.3 / 7.7 / 31 pt at 150 / 600 / 2500 pt/s (the 10 pt hysteresis
    /// excluded). The UIKit path moves the content by all of it, as a `UIScrollView` does; the SwiftUI rule (its
    /// translation includes the hysteresis) keeps `|t₀| − 10`.
    @Test(arguments: [(0.3, 0.0), (7.7, 0.0), (31.0, 21.0)]) func recognitionCredit(t0: CGFloat, swiftUIMove: CGFloat) {
        var uikit = PanSession()
        _ = down(&uikit, Self.env { $0.translationExcludesHysteresis = true })
        #expect(uikit.creditsWholeFirstSample)
        let moved = lastOffset(drag(&uikit, Self.env(), 0, -t0))!
        #expect(abs(moved.y - (250 + t0)) < 1e-9)
        var swiftUI = PanSession()
        _ = down(&swiftUI, Self.env())
        #expect(!swiftUI.creditsWholeFirstSample)
        #expect(abs(lastOffset(drag(&swiftUI, Self.env(), 0, -t0))!.y - (250 + swiftUIMove)) < 1e-9)
    }

    /// Latched per sequence at the touch-down (a synthesized one too), never read mid-sequence.
    @Test func creditIsLatchedAtTheTouchDown() {
        let uikit = Self.env { $0.translationExcludesHysteresis = true }
        var a = PanSession()
        _ = down(&a, uikit)
        #expect(lastOffset(drag(&a, Self.env(), 0, -31))!.y == 281)
        var b = PanSession()
        _ = down(&b, Self.env())
        #expect(lastOffset(drag(&b, uikit, 0, -31))!.y == 271)
        // The observer missed the touch-down: the synthesized one latches from the first sample's environment.
        var c = PanSession()
        #expect(lastOffset(drag(&c, uikit, 0, -31))!.y == 281)
        // The next sequence reads again.
        _ = c.handle(.dragEnded(translation: CGSize(width: 0, height: -31), time: 1.2, fallbackVelocity: nil), env: uikit)
        _ = c.handle(.touchesEnded(time: 1.2), env: uikit)
        _ = down(&c, Self.env(), t: 2)
        #expect(!c.creditsWholeFirstSample)
    }

    @Test func fullCreditAppliesToTheArbitratedRecognitionToo() {
        var s = PanSession()
        let e = Self.env { $0.hasArbiter = true; $0.translationExcludesHysteresis = true }
        _ = down(&s, e)
        #expect(drag(&s, e, -31, 0) == [.askOwner(start: Self.start, translation: CGSize(width: -31, height: 0), touchCount: 1)])
        let fx = s.decided(.participant, env: e)
        #expect(fx.first == .beginTracking && lastOffset(fx) == CGPoint(x: 61, y: 250))
    }

    // MARK: Revival of a yielded swipe

    /// The owner decision gave the swipe to an inner view (`.container` from this side): the session keeps the
    /// recognition sample current; if that inner view declines (the reverse order), it drags from the latest sample, as
    /// a `.participant` answer would have.
    @Test func aYieldedSwipeRevivesFromItsLatestSample() {
        var s = PanSession()
        var e = Self.env { $0.hasArbiter = true }
        e.isMovingWithoutFinger = true
        #expect(down(&s, e) == [.catchMotion])
        e.isMovingWithoutFinger = false
        #expect(drag(&s, e, -20, -14) == [.askOwner(start: Self.start, translation: CGSize(width: -20, height: -14), touchCount: 1)])
        #expect(s.decided(.container, env: e).isEmpty && s.phase == .ignored)
        #expect(s.yielded?.translation == CGSize(width: -20, height: -14))
        #expect(drag(&s, e, -32, -22, t: 1.2).isEmpty, "still ignored")
        #expect(s.yielded?.translation == CGSize(width: -32, height: -22))
        let fx = s.revive(env: e)
        #expect(fx.first == .beginTracking && fx.contains(.beginDragging))
        // Same baseline as a `.participant` answer at the latest sample (hysteresis 10 along it).
        var twin = PanSession()
        _ = down(&twin, Self.env { $0.hasArbiter = true })
        _ = drag(&twin, e, -32, -22)
        #expect(lastOffset(fx) == lastOffset(twin.decided(.participant, env: e)))
        #expect(s.yielded == nil)
        guard case let .dragging(d) = s.phase else { Issue.record("not dragging"); return }
        #expect(d.caughtAt == 1, "the revived drag keeps the catch")
        #expect(lastOffset(drag(&s, e, -50, -22, t: 1.3)) != nil)
        #expect(s.revive(env: e).isEmpty, "once")
    }

    @Test func reviveIsANoOpUnlessASwipeWasYielded() {
        let e = Self.env()
        for phase in Phase.allCases {
            var (s, _) = session(in: phase)
            let before = s.phase
            #expect(s.revive(env: e).isEmpty, "\(phase)")
            #expect(s.phase == before)
        }
        // A yielded swipe that ended, or a new sequence, cannot revive.
        var s = PanSession()
        let a = Self.env { $0.hasArbiter = true }
        _ = down(&s, a)
        _ = drag(&s, a, -20, 0)
        _ = s.decided(.container, env: a)
        #expect(s.handle(.touchesEnded(time: 2), env: a).isEmpty && s.yielded == nil)
        #expect(s.revive(env: a).isEmpty)
        _ = down(&s, a, t: 3)
        _ = drag(&s, a, -20, 0)
        _ = s.decided(.container, env: a)
        _ = down(&s, a, t: 4)   // ignored: a touch-down mid-sequence is no new sequence
        #expect(s.yielded != nil)
        _ = s.handle(.cancelled, env: a)
        _ = down(&s, a, t: 5)
        #expect(s.yielded == nil && s.revive(env: a).isEmpty)
    }

    // MARK: Lift order (U1 C5)

    /// The observer's lift comes first: a dragging session ignores it, and the pan's `.ended` is the release, with
    /// UIKit's velocity as the fallback.
    @Test func theObserversLiftBeforeTheEndedLeavesTheDragToTheEnded() {
        var s = PanSession()
        let e = Self.env()
        _ = down(&s, e)
        _ = drag(&s, e, -31, 0)
        #expect(s.handle(.touchesEnded(time: 1.2), env: e).isEmpty)
        guard case .dragging = s.phase else { Issue.record("the lift ended the drag"); return }
        let v = CGVector(dx: -1500, dy: 0)
        let fx = s.handle(.dragEnded(translation: CGSize(width: -40, height: 0), time: 1.21, fallbackVelocity: v), env: e)
        guard case let .release(r) = fx.last else { Issue.record("no release: \(fx)"); return }
        #expect(r.fallbackVelocity == v && !r.zeroVelocity && r.liftTime == 1.21)
        #expect(s.phase == .released)
    }
}
