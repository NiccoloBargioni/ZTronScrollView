import Foundation
import SwiftUI
import Testing
import ScrollArbitration
import ZTronScrollPhysics
@testable import ZTronScrollView

@Suite struct PanSessionTests {
    static func env(_ edit: (inout PanEnvironment) -> Void = { _ in }) -> PanEnvironment {
        var e = PanEnvironment()
        e.boundsX = AxisBounds(min: 0, max: 200)
        e.boundsY = AxisBounds(min: 0, max: 700)
        e.viewport = CGSize(width: 100, height: 200)
        edit(&e)
        return e
    }
    func down(_ s: inout PanSession, _ e: PanEnvironment, t: TimeInterval = 1, count: Int = 1) -> [PanEffect] {
        s.handle(.touchDown(location: .zero, time: t, touchCount: count), env: e)
    }
    func drag(_ s: inout PanSession, _ e: PanEnvironment, _ dx: CGFloat, _ dy: CGFloat, t: TimeInterval = 1.1) -> [PanEffect] {
        s.handle(.dragChanged(translation: CGSize(width: dx, height: dy), startLocation: .zero, time: t), env: e)
    }
    func lastOffset(_ fx: [PanEffect]) -> CGPoint? {
        for f in fx.reversed() { if case let .setOffset(p) = f { return p } }
        return nil
    }

    @Test func recognitionDoesNotJump() {
        var s = PanSession()
        let e = Self.env { $0.presentationOffset = CGPoint(x: 30, y: 250) }
        _ = down(&s, e)
        let fx = drag(&s, e, 3, -12)
        #expect(fx == [.beginDragging, .setOffset(CGPoint(x: 30, y: 250))])
    }

    @Test func offsetIsBaselineMinusTranslationNeverAccumulated() {
        var s = PanSession()
        let e = Self.env { $0.presentationOffset = CGPoint(x: 0, y: 250) }
        _ = down(&s, e)
        _ = drag(&s, e, 0, -12)
        // out-of-order / repeated samples give the same answer for the same translation
        let a = lastOffset(drag(&s, e, 0, -100))!
        _ = drag(&s, e, 0, -40)
        let b = lastOffset(drag(&s, e, 0, -100))!
        #expect(a == b)
        #expect(abs(a.y - 338) < 1e-9)
    }

    @Test func axesAndScrollEnabled() {
        var s = PanSession()
        var e = Self.env { $0.axes = .vertical; $0.presentationOffset = CGPoint(x: 10, y: 100) }
        _ = down(&s, e)
        _ = drag(&s, e, 50, -20)
        #expect(lastOffset(drag(&s, e, 80, -60)) == CGPoint(x: 10, y: 140))
        var s2 = PanSession()
        e.isScrollEnabled = false
        #expect(down(&s2, e) == [])
        #expect(drag(&s2, e, 0, -20) == [])
        #expect(s2.handle(.dragEnded(translation: .zero, time: 2, fallbackVelocity: nil), env: e) == [])
        #expect(s2.phase == .idle)
    }

    @Test func directionalLock() {
        func run(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            var s = PanSession()
            let e = Self.env { $0.isDirectionalLockEnabled = true; $0.presentationOffset = CGPoint(x: 50, y: 50) }
            _ = down(&s, e)
            _ = drag(&s, e, dx, dy)
            return lastOffset(drag(&s, e, dx * 2, dy * 2))!
        }
        #expect(run(-20, 5) == CGPoint(x: 70, y: 50))      // 4:1 -> horizontal only
        #expect(run(5, -20) == CGPoint(x: 50, y: 70))      // vertical only
        let free = run(-15, -12)                            // diagonal -> free
        #expect(free.x > 50 && free.y > 50)
    }

    @Test(arguments: [true, false]) func rubberBandAndInverseContinuity(top: Bool) {
        // Catch mid-bounce: presentation past an edge; recognition must reproduce it exactly.
        let overshoot: CGFloat = 37
        let p = top ? CGPoint(x: 0, y: -overshoot) : CGPoint(x: 0, y: 700 + overshoot)
        let e = Self.env { $0.presentationOffset = p }
        var s = PanSession()
        _ = down(&s, e)
        let fx = drag(&s, e, 0, top ? 11 : -11)
        let o = lastOffset(fx)!
        #expect(abs(o.y - p.y) < 1e-6)
        // Continuing to pull further past the edge stays below the viewport length of displacement.
        let far = lastOffset(drag(&s, e, 0, top ? 5000 : -5000))!
        #expect(abs(far.y - (top ? 0 : 700)) < 200 && abs(far.y - (top ? 0 : 700)) > overshoot)
    }

    @Test func noBounceHardClamps() {
        var s = PanSession()
        let e = Self.env { $0.bouncesY = false; $0.presentationOffset = CGPoint(x: 0, y: 10) }
        _ = down(&s, e)
        _ = drag(&s, e, 0, 11)
        #expect(lastOffset(drag(&s, e, 0, 500))!.y == 0)
        #expect(lastOffset(drag(&s, e, 0, -5000))!.y == 700)
    }

    @Test func tapEmitsOnlyEndSequence() {
        var s = PanSession()
        let e = Self.env()
        #expect(down(&s, e) == [.beginTracking])
        #expect(s.handle(.touchesEnded(time: 1.05), env: e) == [.endSequence])
        #expect(s.phase == .idle)
    }

    @Test func catchEmitsCatchBeforeTracking() {
        var s = PanSession()
        let e = Self.env { $0.isMovingWithoutFinger = true }
        #expect(down(&s, e) == [.catchMotion, .beginTracking])
    }

    @Test func dragWithoutTouchDownSynthesizesIt() {
        var s = PanSession()
        let e = Self.env()
        #expect(drag(&s, e, 0, -12) == [.beginTracking, .beginDragging, .setOffset(CGPoint(x: 0, y: 0))])
    }

    @Test func releaseAndCancel() {
        var s = PanSession()
        let e = Self.env { $0.presentationOffset = CGPoint(x: 0, y: 100) }
        _ = down(&s, e)
        _ = drag(&s, e, 0, -12)
        let fx = s.handle(.dragEnded(translation: CGSize(width: 0, height: -60), time: 2, fallbackVelocity: CGVector(dx: 0, dy: -300)), env: e)
        guard case let .release(r) = fx.last else { Issue.record("no release"); return }
        #expect(r.origin == CGPoint(x: 0, y: 148) && r.dragStart == CGPoint(x: 0, y: 100) && r.liftTime == 2)
        #expect(r.fallbackVelocity == CGVector(dx: 0, dy: -300) && !r.zeroVelocity)
        #expect(s.handle(.touchesEnded(time: 2), env: e) == [] && s.phase == .idle)

        var c = PanSession()
        _ = down(&c, e); _ = drag(&c, e, 0, -12)
        guard case let .release(r2) = c.handle(.cancelled, env: e).last else { Issue.record("no release"); return }
        #expect(r2.zeroVelocity && r2.liftTime.isNaN)
    }

    @Test func caughtGestureCarriesCatchData() {
        var s = PanSession()
        let e = Self.env { $0.isMovingWithoutFinger = true; $0.interruptedVelocity = CGVector(dx: 0, dy: 900) }
        _ = down(&s, e, t: 5)
        _ = drag(&s, e, 0, 12)
        guard case let .dragging(d) = s.phase else { Issue.record("not dragging"); return }
        #expect(d.caughtAt == 5 && d.caughtVelocity.dy == 900)
    }

    @Test func arbiterDefersTrackingAndDecides() {
        let e = Self.env { $0.hasArbiter = true; $0.presentationOffset = CGPoint(x: 0, y: 40) }
        var s = PanSession()
        #expect(down(&s, e) == [])
        let ask = drag(&s, e, 0, -12)
        #expect(ask == [.askOwner(start: .zero, translation: CGSize(width: 0, height: -12), touchCount: 1)])
        #expect(drag(&s, e, 0, -20) == [])               // no second question
        #expect(s.decided(.participant, env: e) == [.beginTracking, .beginDragging, .setOffset(CGPoint(x: 0, y: 40))])

        var c = PanSession()
        _ = down(&c, e); _ = drag(&c, e, 0, -12)
        #expect(c.decided(.container, env: e) == [])
        #expect(c.phase == .ignored)
        #expect(drag(&c, e, 0, -30) == [])
        #expect(c.handle(.dragEnded(translation: .zero, time: 2, fallbackVelocity: nil), env: e) == [] && c.phase == .idle)
    }

    @Test func multiTouchIsIgnored() {
        var s = PanSession()
        #expect(down(&s, Self.env(), count: 2) == [])
        #expect(s.phase == .ignored)
    }
}
