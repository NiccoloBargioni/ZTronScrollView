import Foundation
import SwiftUI
import Testing
import ScrollArbitration
import ZTronScrollPhysics
@testable import ZTronScrollView

/// The UIKit path below its shell (D60; docs/design/UIKIT-pan.md §2 at 9e6d448), through real coordinators and the nested
/// arbiter: the settle of a declined catch, `NestedScrollArbiter.participantDeclined` in both orders against the
/// container's ask, the second finger and the lift order with `UIKitPanCore` standing in for the shell (U3).
@MainActor
@Suite(.serialized)
struct UIKitPanDeclineTests {
    final class Clock { var t: TimeInterval = 100 }

    @MainActor struct Side {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ReleaseDelegate
        var offset: CGPoint { state.peek.presentationOffset }
        var dragCallbacks: [String] {
            delegate.log.filter { $0 == "willBeginDragging" || $0 == "willEndDragging" || $0.hasPrefix("didEndDragging") }
        }
    }

    func makeSide(_ path: OSPath, axes: Axis.Set, content: CGSize, offset: CGPoint = .zero, limits: ClosedRange<CGFloat> = 1...1,
                  paging: Bool = false, viewport: CGSize = CGSize(width: 100, height: 200), clock: Clock) -> Side {
        let s = makeState(path)
        let d = ReleaseDelegate()
        s.delegate = d
        s.now = { clock.t }
        s.isPagingEnabled = paging
        s.zoomLimits = ZoomLimits(min: .absolute(limits.lowerBound), max: .absolute(limits.upperBound))
        s.setMetrics(ScrollMetrics(viewportSize: viewport, contentSize: content, displayScale: 2))
        s.track(offset: offset, zoom: 1)
        d.log.removeAll()
        let c = withOSPath(path) { PanCoordinator(state: s, axes: axes) }
        c.pinch.centroidSource = .spatial
        return Side(state: s, coord: c, delegate: d)
    }

    func tick(_ clock: Clock, _ sides: Side..., frames: Int = 1) {
        for _ in 0..<frames {
            clock.t += 1.0 / 60
            for s in sides { s.state.step(to: Date(timeIntervalSinceReferenceDate: clock.t)) }
        }
    }

    // MARK: Settle of a declined catch

    enum Content: String, CaseIterable, Sendable { case pager, plain, overscrolled }

    /// A touch catches a moving view and its UIKit pan declines the drag (it goes to the sheet or the page): paging and
    /// targets snap, plain content stays where the catch stopped it, an overscroll springs back. No drag callback fires
    /// (`willBeginDragging` never did); the touch's own end closes the sequence.
    @Test(arguments: OSPath.allCases, Content.allCases) func aDeclinedCatchSettlesWithoutDragCallbacks(path: OSPath, content: Content) {
        let clock = Clock()
        let from: CGFloat = content == .overscrolled ? -30 : 40
        let v = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), offset: CGPoint(x: from, y: 0),
                         paging: content == .pager, clock: clock)
        // In flight toward 100: a spring that the touch-down stops at once.
        v.state.beginDeceleration(x: .spring(CriticalSpring(origin: from, target: 100), start: clock.t), y: .rest(position: 0),
                                  at: clock.t)
        v.delegate.log.removeAll()
        v.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: clock.t, touchCount: 1))
        #expect(v.coord.caughtUndecided && v.state.catchLocksContent && v.offset.x == from)
        v.coord.handle(.declined)
        #expect(!v.coord.caughtUndecided)
        #expect(v.coord.session.phase == .touching(down: clock.t, caught: false))
        tick(clock, v, frames: 120)
        let rest: CGFloat = content == .plain ? 40 : 0
        #expect(abs(v.offset.x - rest) < 0.5, "\(content) rests at \(v.offset.x)")
        #expect(v.dragCallbacks.isEmpty, "\(v.delegate.log)")
        if content == .plain {
            #expect(!v.delegate.log.contains("willBeginDecelerating"), "nothing to settle")
        } else {
            #expect(v.delegate.log.contains("willBeginDecelerating") && v.delegate.log.contains("didEndDecelerating"))
        }
        v.coord.handle(.touchesEnded(time: clock.t))
        #expect(!v.coord.isSequenceActive && !v.state.isTracking && v.state.phase == .idle)
        #expect(v.dragCallbacks.isEmpty)
    }

    /// R6 baseline, unchanged: without a decline a tap that catches a page settle leaves the pager between pages.
    @Test(arguments: OSPath.allCases) func aTapCatchWithoutADeclineStaysBetweenPages(path: OSPath) {
        let clock = Clock()
        let v = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), offset: CGPoint(x: 40, y: 0),
                         paging: true, clock: clock)
        v.state.beginDeceleration(x: .spring(CriticalSpring(origin: 40, target: 100), start: clock.t), y: .rest(position: 0),
                                  at: clock.t)
        v.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: clock.t, touchCount: 1))
        v.coord.handle(.touchesEnded(time: clock.t))
        tick(clock, v, frames: 60)
        #expect(v.offset.x == 40)
    }

    @Test(arguments: OSPath.allCases) func aDeclineWithoutACatchChangesNothing(path: OSPath) {
        let clock = Clock()
        let v = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), offset: CGPoint(x: 40, y: 0),
                         paging: true, clock: clock)
        v.coord.handle(.touchDown(location: CGPoint(x: 50, y: 100), time: clock.t, touchCount: 1))
        v.coord.effectsLog.removeAll()
        v.coord.handle(.declined)
        #expect(v.coord.effectsLog.isEmpty && v.state.isTracking)
        v.coord.handle(.touchesEnded(time: clock.t))
        tick(clock, v, frames: 30)
        #expect(v.offset.x == 40 && v.delegate.log.allSatisfy { $0 == "didScroll" } && !v.coord.isSequenceActive)
    }

    // MARK: participantDeclined

    @MainActor struct Rig {
        let outer: Side
        let inner: Side
        let clock: Clock
        var arbiter: NestedScrollArbiter { outer.coord.nestedArbiter }
        var token: ScrollArbitrationToken { inner.coord.participant!.token! }
    }

    /// Outer: horizontal pager, three 100 pt pages. Inner: a 1× zoomer that fits (it cannot move), page 0.
    func make(_ path: OSPath) -> Rig {
        let clock = Clock()
        let outer = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), paging: true, clock: clock)
        let inner = makeSide(path, axes: [.horizontal, .vertical], content: CGSize(width: 100, height: 200), limits: 1...4,
                             clock: clock)
        inner.coord.setArbiter(outer.coord.nestedArbiter)
        inner.coord.participant?.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        outer.delegate.log.removeAll(); inner.delegate.log.removeAll()
        return Rig(outer: outer, inner: inner, clock: clock)
    }

    let start = CGPoint(x: 50, y: 100)
    /// 35° above horizontal: more than the pager's 30° tolerance, so the arbiter's rule 1 gives it to the inner view,
    /// which cannot move and declines it (the "30–45° hole" on a 1× zoomer page).
    func steep(_ k: CGFloat) -> CGSize { CGSize(width: -40 * k, height: -28 * k) }

    func touchDown(_ r: Rig) {
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        r.outer.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
    }
    /// The outer's pan only: on the UIKit path the inner view's pan never begins once it declined.
    func outerDrag(_ r: Rig, _ k: CGFloat) {
        r.clock.t += 0.016
        r.outer.coord.handle(.dragChanged(translation: steep(k), startLocation: start, time: r.clock.t))
    }
    func lift(_ r: Rig, _ k: CGFloat) {
        r.clock.t += 0.016
        r.outer.coord.handle(.dragEnded(translation: steep(k), time: r.clock.t, fallbackVelocity: nil))
        r.outer.coord.handle(.touchesEnded(time: r.clock.t))
        r.inner.coord.handle(.touchesEnded(time: r.clock.t))
    }
    func expectInnerUntouched(_ r: Rig) {
        #expect(r.inner.offset == .zero && r.inner.dragCallbacks.isEmpty)
        #expect(!r.inner.state.isTracking && !r.inner.state.isDragging && !r.inner.state.isDecelerating)
    }

    /// Without a decline the arbiter hands the steep swipe to the inner view, which cannot follow it: nothing moves.
    @Test(arguments: OSPath.allCases) func baselineTheSteepSwipeDiesOnTheInnerView(path: OSPath) {
        let r = make(path)
        touchDown(r)
        outerDrag(r, 1); outerDrag(r, 1.5)
        #expect(r.arbiter.currentOwner == .participant)
        lift(r, 1.5)
        #expect(r.outer.offset == .zero && r.outer.dragCallbacks.isEmpty)
    }

    /// The order `participantDeclined` assumes: the inner's `shouldBegin` declines before the outer's `.began` asks.
    /// The ask resolves past the inner view, to the container: the pager pages.
    @Test(arguments: OSPath.allCases) func declineBeforeTheAskGivesTheSwipeToTheContainer(path: OSPath) {
        let r = make(path)
        touchDown(r)
        r.inner.coord.handle(.declined)
        #expect(r.arbiter.isSequenceActive)
        outerDrag(r, 1)
        #expect(r.outer.state.isTracking && r.arbiter.currentOwner == nil, "no participant under the point: nothing cached")
        outerDrag(r, 1.5)
        lift(r, 1.5)
        #expect(r.outer.dragCallbacks.first == "willBeginDragging" && r.outer.offset.x > 0)
        expectInnerUntouched(r)
        #expect(!r.arbiter.isSequenceActive)
    }

    /// The reverse order, pinned by a defined result (U1 never measured it): the outer asks first and yields, then the
    /// inner declines; the outer's session revives and drags from its latest sample.
    @Test(arguments: OSPath.allCases) func declineAfterTheAskRevivesTheContainer(path: OSPath) {
        let r = make(path)
        touchDown(r)
        outerDrag(r, 1)
        #expect(r.outer.coord.session.phase == .ignored && r.arbiter.currentOwner == .participant)
        outerDrag(r, 1.2)
        r.inner.coord.handle(.declined)
        #expect(r.arbiter.currentOwner == .container)
        guard case .dragging = r.outer.coord.session.phase else { Issue.record("not revived"); return }
        #expect(r.outer.state.isTracking)
        r.inner.coord.handle(.declined)   // the core sends one per sequence; a second is ignored
        outerDrag(r, 1.5)
        lift(r, 1.5)
        #expect(r.outer.dragCallbacks.filter { $0 == "willBeginDragging" }.count == 1 && r.outer.offset.x > 0)
        expectInnerUntouched(r)
        #expect(r.arbiter.currentOwner == nil && !r.arbiter.isSequenceActive)
    }

    /// The declined frame is hidden for the sequence only; frame updates meanwhile land when it ends.
    @Test(arguments: OSPath.allCases) func theDeclinedFrameComesBackWhenTheSequenceEnds(path: OSPath) {
        let r = make(path)
        touchDown(r)
        r.inner.coord.handle(.declined)
        r.inner.coord.participant?.update(frame: CGRect(x: 100, y: 0, width: 100, height: 200))
        outerDrag(r, 1)
        lift(r, 1)
        #expect(!r.arbiter.isSequenceActive)
        // The inner view is found again, at its new frame (each probe begins and ends its own lazy sequence).
        #expect(r.arbiter.containerOwner(ofDragFrom: CGPoint(x: 150, y: 100), translation: steep(1), touchCount: 1) == .participant)
        r.arbiter.endSequence()
        #expect(r.arbiter.containerOwner(ofDragFrom: start, translation: steep(1), touchCount: 1) == .container)
        r.arbiter.endSequence()
    }

    /// A container whose sequence is not active (≤ 17 without its observer) begins one lazily; it ends with the
    /// participant's.
    @Test(arguments: OSPath.allCases) func aDeclineBeginsALazySequenceThatEndsWithTheParticipant(path: OSPath) {
        let r = make(path)
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        #expect(!r.arbiter.isSequenceActive)
        r.inner.coord.handle(.declined)
        #expect(r.arbiter.isSequenceActive)
        #expect(r.arbiter.containerOwner(ofDragFrom: start, translation: steep(1), touchCount: 1) == .container)
        r.inner.coord.handle(.touchesEnded(time: r.clock.t))
        #expect(!r.arbiter.isSequenceActive)
        #expect(r.arbiter.containerOwner(ofDragFrom: start, translation: steep(1), touchCount: 1) == .participant)
    }

    /// No container to tell: a scroll-disabled outer arbitrates nothing; unknown tokens are ignored.
    @Test(arguments: OSPath.allCases) func declinesTheArbiterCannotUseChangeNothing(path: OSPath) {
        let r = make(path)
        r.outer.coord.settings.isScrollEnabled = false
        r.arbiter.participantDeclined(r.token)
        #expect(!r.arbiter.isSequenceActive)
        r.outer.coord.settings.isScrollEnabled = true
        #expect(r.arbiter.containerOwner(ofDragFrom: start, translation: steep(1), touchCount: 1) == .participant)
        r.arbiter.endSequence()   // the probe began one lazily
        let stale = r.token
        r.inner.coord.participant?.unregister()
        r.arbiter.participantDeclined(stale)
        #expect(!r.arbiter.isSequenceActive)
        // A view alone (no arbiter) has nobody to tell.
        let clock = Clock()
        let alone = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), clock: clock)
        alone.coord.handle(.touchDown(location: start, time: clock.t, touchCount: 1))
        alone.coord.handle(.declined)
        #expect(alone.coord.session.phase == .touching(down: clock.t, caught: false))
    }

    // MARK: Second finger and lift order, with the core in the shell's place

    @MainActor struct Single {
        let side: Side
        let clock: Clock
        var core = UIKitPanCore()
        var coord: PanCoordinator { side.coord }
        var now: TimeInterval { clock.t }
        func advance(_ dt: TimeInterval = 0.016) { clock.t += dt; side.state.step(to: Date(timeIntervalSinceReferenceDate: clock.t)) }
    }

    func single(_ path: OSPath) -> Single {
        let clock = Clock()
        let side = makeSide(path, axes: [.horizontal, .vertical], content: CGSize(width: 2000, height: 4000),
                            offset: CGPoint(x: 500, y: 1000), limits: 1...3, viewport: CGSize(width: 200, height: 400), clock: clock)
        return Single(side: side, clock: clock)
    }

    static let twoAxis: UIKitPanCore.Input = {
        var i = UIKitPanCore.Input()
        i.horizontal = .init(isInAxes: true, isScrollable: true)
        i.vertical = .init(isInAxes: true, isScrollable: true)
        return i
    }()

    /// The shell's forwarding: each core event to `handle`, in order.
    func forward(_ s: Single, _ events: [PanEvent]) { for e in events { s.coord.handle(e) } }
    func act(_ s: inout Single, _ raw: Int, _ t: CGSize, _ v: CGVector = CGVector(dx: 0, dy: -600), at p: CGPoint) {
        if let e = s.core.handle(stateRaw: raw, translation: t, velocity: v, location: p, time: s.now) { s.coord.handle(e) }
    }

    /// §2 "Second finger": the active pan ends once, the reset's one `.cancelled` is swallowed in both timings, the
    /// remaining finger continues through `synthesizePan`, and its lift releases in the same call: no release stays held
    /// after any call returns.
    @Test(arguments: OSPath.allCases, [false, true]) func secondFingerNeverLeavesAReleaseHeld(path: OSPath, afterTheCall: Bool) {
        var s = single(path)
        let start = CGPoint(x: 100, y: 300)
        func held() { #expect(!s.coord.hasHeldRelease) }
        s.coord.handlePinch(.fingerCountChanged(count: 1, remaining: start, time: s.now))
        let opened = s.core.touchDown(at: start, touchCount: 1)
        forward(s, opened)
        s.coord.handle(.touchDown(location: start, time: s.now, touchCount: 1)); held()
        #expect(s.core.shouldBegin(Self.twoAxis, location: CGPoint(x: 100, y: 288), velocity: CGVector(dx: 0, dy: -600)).begins)
        act(&s, UIKitPanCore.RawState.began, CGSize(width: 0, height: -2), at: CGPoint(x: 100, y: 288)); held()
        for k in 1...3 {
            s.advance()
            act(&s, UIKitPanCore.RawState.changed, CGSize(width: 0, height: -2 - 8 * CGFloat(k)), at: CGPoint(x: 100, y: 288 - 8 * CGFloat(k)))
            held()
        }
        // The second finger lands.
        s.advance()
        let c = CGPoint(x: 100, y: 240)
        let second = s.core.touchCountChanged(to: 2, time: s.now)
        #expect(second.resetsRecognizer && second.events.count == 1)
        forward(s, second.events); held()
        s.core.willReset(stateRaw: UIKitPanCore.RawState.changed)
        if !afterTheCall { act(&s, UIKitPanCore.RawState.cancelled, .zero, at: c); held() }
        s.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: s.now)); held()
        if afterTheCall { act(&s, UIKitPanCore.RawState.cancelled, .zero, at: c); held() }
        s.coord.handlePinch(.began(centroid: c, time: s.now)); held()
        s.coord.handlePinch(.changed(magnification: 1.5, centroid: c, time: s.now)); held()
        s.advance()
        // One finger lifts: the pan continues from the other one.
        let remaining = CGPoint(x: 120, y: 260)
        #expect(s.core.touchCountChanged(to: 1, time: s.now).events.isEmpty)
        s.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: s.now)); held()
        for k in 1...2 {
            s.advance()
            s.coord.synthesizePan(location: CGPoint(x: 120, y: 260 - CGFloat(k)), time: s.now); held()
        }
        // The pan's raw state stays cancelled: nothing more comes from it.
        #expect(!s.core.isPanActive)
        s.advance()
        s.core.sequenceEnded()
        s.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: s.now)); held()
        s.coord.handle(.touchesEnded(time: s.now)); held()
        #expect(!s.coord.isSequenceActive && !s.side.state.isTracking && abs(s.side.state.zoomScale - 1.5) < 1e-9)
    }

    /// U1 C5 through the coordinator: the observer's lift comes first and leaves the drag open; the pan's `.ended` is
    /// the release, with UIKit's velocity when the tracker has a single sample; the next touch-down catches the fling.
    @Test(arguments: OSPath.allCases) func theLiftBeforeTheEndedFlingsWithUIKitsVelocity(path: OSPath) {
        var s = single(path)
        let start = CGPoint(x: 100, y: 300)
        let opened = s.core.touchDown(at: start, touchCount: 1)
        forward(s, opened)
        s.coord.handle(.touchDown(location: start, time: s.now, touchCount: 1))
        #expect(s.core.shouldBegin(Self.twoAxis, location: CGPoint(x: 70, y: 300), velocity: .zero).begins)
        s.advance()
        act(&s, UIKitPanCore.RawState.began, CGSize(width: -20, height: 0), CGVector(dx: -1500, dy: 0), at: CGPoint(x: 70, y: 300))
        let o = s.side.offset
        s.core.sequenceEnded()
        s.coord.handle(.touchesEnded(time: s.now))
        #expect(s.side.state.isTracking, "the lift alone does not end the drag")
        guard case .dragging = s.coord.session.phase else { Issue.record("not dragging"); return }
        act(&s, UIKitPanCore.RawState.ended, CGSize(width: -20, height: 0), CGVector(dx: -1500, dy: 0), at: CGPoint(x: 70, y: 300))
        #expect(s.side.state.isDecelerating && !s.side.state.isTracking)
        s.advance(); s.advance()
        #expect(s.side.offset.x > o.x, "finger left at 1500 pt/s: the content keeps moving right")
        // The next touch: no dangling pan, and it catches the fling.
        #expect(s.core.touchDown(at: start, touchCount: 1).isEmpty)
        s.coord.handle(.touchDown(location: start, time: s.now, touchCount: 1))
        #expect(s.coord.caughtUndecided && !s.side.state.isDecelerating)
    }

    /// A pan left open across sequences (no `.ended` or `.cancelled` arrived): the core's `.cancelled` at the next
    /// touch-down releases it at rest before the new touch begins.
    @Test(arguments: OSPath.allCases) func aDanglingPanIsCancelledBeforeTheNextTouchDown(path: OSPath) {
        var s = single(path)
        let start = CGPoint(x: 100, y: 300)
        let opened = s.core.touchDown(at: start, touchCount: 1)
        forward(s, opened)
        s.coord.handle(.touchDown(location: start, time: s.now, touchCount: 1))
        act(&s, UIKitPanCore.RawState.began, CGSize(width: -20, height: 0), at: CGPoint(x: 70, y: 300))
        s.core.sequenceEnded()
        s.coord.handle(.touchesEnded(time: s.now))
        s.advance()
        let open = s.core.touchDown(at: start, touchCount: 1)
        #expect(open == [.cancelled])
        forward(s, open)
        #expect(!s.side.state.isTracking && !s.side.state.isDecelerating && s.side.delegate.log.contains("didEndDragging(false)"))
        s.coord.handle(.touchDown(location: start, time: s.now, touchCount: 1))
        #expect(s.coord.session.phase == .touching(down: s.now, caught: false))
    }
}
