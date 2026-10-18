import Foundation
import SwiftUI
import Testing
import ScrollArbitration
@testable import ZTronScrollView

@MainActor
@Suite(.serialized)
struct ArbitrationTests {
    struct Rig {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let arbiter: ReferenceScrollArbiter
        let delegate: ReleaseDelegate
    }

    func make(_ path: OSPath, axes: Axis.Set = [.horizontal, .vertical], content: CGSize = CGSize(width: 300, height: 900),
              offset: CGPoint = CGPoint(x: 0, y: 300), withArbiter: Bool = true) -> Rig {
        let s = makeState(path)
        let d = ReleaseDelegate()
        s.delegate = d
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: content, displayScale: 2))
        s.track(offset: offset, zoom: 1)
        d.log.removeAll()
        let c = PanCoordinator(state: s, axes: axes)
        let a = ReferenceScrollArbiter(pagingAxis: .horizontal)
        if withArbiter { c.setArbiter(a) }
        return Rig(state: s, coord: c, arbiter: a, delegate: d)
    }

    @discardableResult
    func swipe(_ r: Rig, dx: CGFloat, dy: CGFloat, t: TimeInterval = 100, end: Bool = true) -> CGPoint {
        r.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: t, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: dx, height: dy), startLocation: CGPoint(x: 50, y: 100), time: t + 0.02))
        // The recognition sample does not move the content (no jump); the next one does.
        r.coord.handle(.dragChanged(translation: CGSize(width: dx * 1.5, height: dy * 1.5), startLocation: CGPoint(x: 50, y: 100), time: t + 0.03))
        let mid = r.state.peek.presentationOffset
        if end {
            r.coord.handle(.dragEnded(translation: CGSize(width: dx, height: dy), time: t + 0.04, fallbackVelocity: nil))
        }
        return mid
    }

    // MARK: registration

    @Test(arguments: OSPath.allCases) func registerUpdateUnregister(path: OSPath) {
        let r = make(path)
        let p = r.coord.participant!
        p.register(frame: CGRect(x: 10, y: 20, width: 100, height: 200))
        #expect(p.isRegistered)
        p.update(frame: CGRect(x: 110, y: 20, width: 100, height: 200))
        p.update(frame: CGRect(x: 110, y: 20, width: 100, height: 200))     // unchanged: no call
        p.unregister()
        p.unregister()                                                       // second is a no-op
        p.update(frame: CGRect(x: 0, y: 0, width: 1, height: 1))            // ignored while unregistered
        let kinds = r.arbiter.log.map { e -> String in
            switch e {
            case .register: "register"
            case let .update(_, _, known): "update\(known)"
            case let .unregister(_, known): "unregister\(known)"
            default: "other"
            }
        }
        #expect(kinds == ["register", "updatetrue", "unregistertrue"])
    }

    @Test(arguments: OSPath.allCases) func noArbiterMeansNoParticipant(path: OSPath) {
        let r = make(path, withArbiter: false)
        #expect(r.coord.participant == nil)
        #expect(r.coord.environment().hasArbiter == false)
        let mid = swipe(r, dx: 0, dy: -40)
        #expect(r.delegate.log.contains("willBeginDragging"))
        #expect(mid.y > 300, "mid \(mid) end \(r.state.peek.presentationOffset)")
        #expect(r.arbiter.log.isEmpty)
    }

    @Test(arguments: OSPath.allCases) func removingArbiterUnregisters(path: OSPath) {
        let r = make(path)
        r.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        r.coord.setArbiter(nil)
        #expect(r.coord.participant == nil)
        if case .unregister = r.arbiter.log.last {} else { Issue.record("not unregistered") }
    }

    // MARK: canFollow

    @Test(arguments: OSPath.allCases) func canFollowAtEveryEdge(path: OSPath) {
        // Content 300x900 in a 100x200 viewport: x in 0...200, y in 0...700.
        var keep: [Rig] = []
        func p(_ off: CGPoint) -> ArbitrationParticipant { let r = make(path, offset: off); keep.append(r); return r.coord.participant! }
        defer { _ = keep }
        let origin = p(.zero)
        #expect(!origin.canFollow(.right) && origin.canFollow(.left))
        #expect(!origin.canFollow(.down) && origin.canFollow(.up))
        let end = p(CGPoint(x: 200, y: 700))
        #expect(end.canFollow(.right) && !end.canFollow(.left))
        #expect(end.canFollow(.down) && !end.canFollow(.up))
        let mid = p(CGPoint(x: 100, y: 350))
        for d in [FingerDirection.left, .right, .up, .down] { #expect(mid.canFollow(d)) }
        // Half a point from the edge counts as at the edge; a full point does not.
        #expect(!p(CGPoint(x: 0.4, y: 0.4)).canFollow(.right))
        #expect(p(CGPoint(x: 1, y: 1)).canFollow(.right))
        // Rubber band is never following.
        #expect(!p(CGPoint(x: -20, y: -20)).canFollow(.right))
        #expect(!p(CGPoint(x: 220, y: 720)).canFollow(.left))
    }

    @Test(arguments: OSPath.allCases) func canFollowRespectsAxesFitAndEnabled(path: OSPath) {
        let rv = make(path, axes: .vertical); let v = rv.coord.participant!
        #expect(!v.canFollow(.left) && !v.canFollow(.right) && v.canFollow(.up))
        let rf = make(path, content: CGSize(width: 100, height: 150), offset: .zero); let fits = rf.coord.participant!
        for d in [FingerDirection.left, .right, .up, .down] { #expect(!fits.canFollow(d)) }
        let off = make(path, offset: CGPoint(x: 100, y: 350))
        off.state.isScrollEnabled = false
        for d in [FingerDirection.left, .right, .up, .down] { #expect(!off.coord.participant!.canFollow(d)) }
        #expect(!off.coord.participant!.isZoomEnabled)
    }

    // MARK: ownership

    @Test(arguments: OSPath.allCases) func participantKeepsFollowableSwipe(path: OSPath) {
        let r = make(path)
        r.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let mid = swipe(r, dx: -40, dy: 0)               // finger left, content can follow
        #expect(r.delegate.log.contains("willBeginDragging"))
        #expect(mid.x > 0, "mid \(mid)")
    }

    @Test(arguments: OSPath.allCases) func containerIgnoresWholeSequence(path: OSPath) {
        let r = make(path, offset: .zero)
        r.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let phase = r.state.phase
        // Finger right at the left edge: cannot follow, the pager takes it.
        r.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: 100, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 30, height: 0), startLocation: CGPoint(x: 50, y: 100), time: 100.02))
        r.coord.handle(.dragChanged(translation: CGSize(width: 90, height: 0), startLocation: CGPoint(x: 50, y: 100), time: 100.04))
        r.coord.handle(.frame(time: 100.05))
        r.state.step(to: Date(timeIntervalSinceReferenceDate: 100.06))
        #expect(r.state.peek.presentationOffset == .zero && r.state.peek.targetOffset == .zero)
        #expect(r.state.phase == phase)
        #expect(!r.state.isTracking && !r.state.isDragging && !r.state.isDecelerating)
        #expect(r.delegate.log.isEmpty)
        #expect(!r.state.catchLocksContent)
        #expect(r.arbiter.log.filter { if case .owner = $0 { return true } else { return false } }.count == 1)  // asked once
        r.coord.handle(.dragEnded(translation: CGSize(width: 90, height: 0), time: 100.1, fallbackVelocity: CGVector(dx: 900, dy: 0)))
        #expect(r.state.phase == phase && r.delegate.log.isEmpty && !r.state.isClockRunning)
        #expect(r.state.peek.presentationOffset == .zero)
        #expect(!r.coord.isSequenceActive)
        // The next swipe in the other direction is the participant's.
        swipe(r, dx: -40, dy: 0, t: 101)
        #expect(r.delegate.log.contains("willBeginDragging"))
    }

    @Test(arguments: OSPath.allCases) func offAxisSwipeStaysWithParticipant(path: OSPath) {
        let r = make(path, offset: .zero)
        r.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        swipe(r, dx: 3, dy: 40)                          // mostly vertical, rule 1
        #expect(r.delegate.log.contains("willBeginDragging"))
    }

    @Test(arguments: OSPath.allCases) func touchDuringMotionStaysWithParticipant(path: OSPath) {
        // Content cannot follow a rightward finger at x = 0, but the vertical fling is moving: rule 3.
        let r = make(path, offset: CGPoint(x: 0, y: 300))
        r.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        r.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: 100, touchCount: 1))
        var t = 100.0
        for i in 1...8 {
            t += 0.015
            let ty = -CGFloat(i) * 15
            r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: ty), startLocation: CGPoint(x: 50, y: 100), time: t))
            r.state.step(to: Date(timeIntervalSinceReferenceDate: t))
        }
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -120), time: t, fallbackVelocity: nil))
        #expect(r.state.isDecelerating)
        r.delegate.log.removeAll()
        let y0 = r.state.peek.presentationOffset.y
        // Catch, then a rightward swipe: the sticky motion flag makes the participant the owner.
        r.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: t + 0.1, touchCount: 1))
        #expect(r.coord.caughtUndecided && r.coord.participant!.isMovingWithoutFinger)
        r.coord.handle(.dragChanged(translation: CGSize(width: 30, height: 0), startLocation: CGPoint(x: 50, y: 100), time: t + 0.12))
        r.coord.handle(.dragChanged(translation: CGSize(width: 45, height: 0), startLocation: CGPoint(x: 50, y: 100), time: t + 0.14))
        #expect(!r.coord.caughtUndecided)
        #expect(r.delegate.log.contains("willBeginDragging"))
        #expect(r.state.peek.presentationOffset.y >= y0)
        let last = r.arbiter.log.last
        if case let .owner(_, _, _, _, _, _, _, _, _, result) = last { #expect(result == .participant) } else { Issue.record("no owner call") }
    }
}
