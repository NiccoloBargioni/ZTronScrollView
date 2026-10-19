import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
import ScrollArbitration
@testable import ZTronScrollView

/// Nested ZTronScrollView arbitration (docs/design/NESTED-arbitration.md §1 table, §3, resolutions R1–R7): an outer
/// coordinator (container role, its internal `NestedScrollArbiter`) and an inner coordinator (participant) driven by
/// the same scripted touch, on both OS paths.
@MainActor
@Suite(.serialized)
struct NestedArbitrationTests {
    final class Clock { var t: TimeInterval = 100 }

    @MainActor struct Side {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ZoomDelegate
        var offset: CGPoint { state.peek.presentationOffset }
        var zoom: CGFloat { state.peek.presentationZoom }
        var dragged: Bool { delegate.log.contains("willBeginDragging") }
        /// Effects other than the question itself: a loser must have none for the whole sequence.
        var movementEffects: [PanEffect] {
            coord.effectsLog.filter { if case .askOwner = $0 { return false } else { return true } }
        }
        func clearLogs() { delegate.log.removeAll(); coord.effectsLog.removeAll() }
    }

    @MainActor struct Rig {
        let outer: Side
        let inner: Side
        let clock: Clock
        var arbiter: NestedScrollArbiter { outer.coord.nestedArbiter }
        var now: TimeInterval {
            get { clock.t }
            nonmutating set { clock.t = newValue }
        }
        func tick() {
            now += 1.0 / 60
            outer.state.step(to: Date(timeIntervalSinceReferenceDate: now))
            inner.state.step(to: Date(timeIntervalSinceReferenceDate: now))
        }
        /// Log entries of a sequence (not registration bookkeeping).
        var sequenceEntries: Int {
            arbiter.log.filter {
                switch $0 {
                case .register, .update, .unregister: return false
                default: return true
                }
            }.count
        }
        var decisions: Int {
            arbiter.log.filter {
                if case let .owner(_, _, _, _, _, _, _, _, decided, _) = $0 { return decided }
                return false
            }.count
        }
        func clearLogs() { outer.clearLogs(); inner.clearLogs() }
    }

    enum Order { case innerFirst, outerFirst }

    let viewport = CGSize(width: 100, height: 200)

    func makeSide(_ path: OSPath, axes: Axis.Set, content: CGSize, offset: CGPoint, zoom: CGFloat = 1,
                  limits: ClosedRange<CGFloat> = 1...1, paging: Bool = false, clock: Clock) -> Side {
        let s = makeState(path)
        let d = ZoomDelegate()
        s.delegate = d
        s.now = { clock.t }
        s.isPagingEnabled = paging
        s.zoomLimits = ZoomLimits(min: .absolute(limits.lowerBound), max: .absolute(limits.upperBound))
        s.setMetrics(ScrollMetrics(viewportSize: viewport, contentSize: content, displayScale: 2))
        s.track(offset: offset, zoom: zoom)
        d.log.removeAll()
        let c = withOSPath(path) { PanCoordinator(state: s, axes: axes) }
        c.pinch.centroidSource = .spatial
        return Side(state: s, coord: c, delegate: d)
    }

    /// Outer: horizontal pager, three 100 pt pages. Inner: two-axis zoomer (1…4) registered as page 0 in the outer's
    /// content space. Inner content 100x200 fits the viewport at zoom 1; at zoom 2 it pans in x 0…100, y 0…200.
    func make(_ path: OSPath, policy: ZTronNestedScrollPolicy = .automatic, outerAxes: Axis.Set = .horizontal,
              outerContent: CGSize = CGSize(width: 300, height: 200), outerOffset: CGPoint = .zero,
              innerAxes: Axis.Set = [.horizontal, .vertical], innerContent: CGSize = CGSize(width: 100, height: 200),
              innerOffset: CGPoint = .zero, innerZoom: CGFloat = 1, innerLimits: ClosedRange<CGFloat> = 1...4,
              innerFrame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 200)) -> Rig {
        let clock = Clock()
        let outer = makeSide(path, axes: outerAxes, content: outerContent, offset: outerOffset, paging: true, clock: clock)
        let inner = makeSide(path, axes: innerAxes, content: innerContent, offset: innerOffset, zoom: innerZoom,
                             limits: innerLimits, clock: clock)
        inner.coord.setArbiter(outer.coord.nestedArbiter, policy: policy)
        inner.coord.participant?.register(frame: innerFrame)
        let r = Rig(outer: outer, inner: inner, clock: clock)
        r.clearLogs()
        return r
    }

    func deliver(_ r: Rig, _ event: PanEvent, order: Order) {
        switch order {
        case .innerFirst: r.inner.coord.handle(event); r.outer.coord.handle(event)
        case .outerFirst: r.outer.coord.handle(event); r.inner.coord.handle(event)
        }
    }

    let start = CGPoint(x: 50, y: 100)

    /// One touch seen by both views: down, recognition sample, a second sample, lift.
    func swipe(_ r: Rig, dx: CGFloat, dy: CGFloat, order: Order = .innerFirst, end: Bool = true) {
        deliver(r, .touchDown(location: start, time: r.now, touchCount: 1), order: order)
        r.now += 0.02
        deliver(r, .dragChanged(translation: CGSize(width: dx, height: dy), startLocation: start, time: r.now), order: order)
        r.now += 0.016
        deliver(r, .dragChanged(translation: CGSize(width: dx * 1.5, height: dy * 1.5), startLocation: start, time: r.now),
                order: order)
        r.tick()
        if end { lift(r, dx: dx * 1.5, dy: dy * 1.5, order: order) }
    }

    func lift(_ r: Rig, dx: CGFloat, dy: CGFloat, order: Order = .innerFirst) {
        r.now += 0.016
        deliver(r, .dragEnded(translation: CGSize(width: dx, height: dy), time: r.now, fallbackVelocity: nil), order: order)
        deliver(r, .touchesEnded(time: r.now), order: order)
    }

    /// Eight accelerating samples then a lift: the side that follows decelerates afterwards.
    func fling(_ r: Rig, dx: CGFloat, dy: CGFloat, order: Order = .innerFirst) {
        deliver(r, .touchDown(location: start, time: r.now, touchCount: 1), order: order)
        for i in 1...8 {
            r.now += 0.015
            deliver(r, .dragChanged(translation: CGSize(width: dx * CGFloat(i), height: dy * CGFloat(i)),
                                    startLocation: start, time: r.now), order: order)
            r.outer.state.step(to: Date(timeIntervalSinceReferenceDate: r.now))
            r.inner.state.step(to: Date(timeIntervalSinceReferenceDate: r.now))
        }
        lift(r, dx: dx * 8, dy: dy * 8, order: order)
    }

    func expectLoser(_ s: Side, offset: CGPoint, zoom: CGFloat = 1, _ comment: Comment? = nil) {
        #expect(s.movementEffects.isEmpty, comment)
        #expect(s.delegate.log.isEmpty, comment)
        #expect(s.offset == offset && s.zoom == zoom, comment)
        #expect(!s.state.isTracking && !s.state.isDragging && !s.state.isDecelerating, comment)
    }

    // MARK: §1 table under .automatic (= .innerWhileScrollable)

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func zoom1FitsHorizontalPages(path: OSPath, order: Order) {
        let r = make(path)
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        expectLoser(r.inner, offset: .zero)
        #expect(r.decisions == 1 && r.arbiter.currentOwner == nil && !r.arbiter.isSequenceActive)
    }

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func zoom1TallVerticalScrollsInner(path: OSPath, order: Order) {
        let r = make(path, innerContent: CGSize(width: 100, height: 600), innerOffset: CGPoint(x: 0, y: 200))
        swipe(r, dx: 0, dy: -40, order: order)                                   // rule 1
        #expect(r.inner.dragged && r.inner.offset.y > 200)
        expectLoser(r.outer, offset: .zero)
        #expect(r.decisions == 1)
    }

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func zoomedMidPansInner(path: OSPath, order: Order) {
        let r = make(path, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        swipe(r, dx: -40, dy: 0, order: order)                                   // rule 5
        #expect(r.inner.dragged && r.inner.offset.x > 50)
        expectLoser(r.outer, offset: .zero)
        #expect(r.decisions == 1)
    }

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func zoomedAtEdgePagesUnderAutomatic(path: OSPath, order: Order) {
        let r = make(path, innerOffset: CGPoint(x: 100, y: 100), innerZoom: 2)   // x at its max: cannot follow left
        swipe(r, dx: -40, dy: 0, order: order)                                   // rule 5 fails -> 6
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        expectLoser(r.inner, offset: CGPoint(x: 100, y: 100), zoom: 2)
        #expect(r.decisions == 1)
    }

    @Test(arguments: OSPath.allCases) func twoFingersNeverPage(path: OSPath) {
        let r = make(path)
        // A two-finger touch-down is a pinch: the outer's pan ignores the sequence and never asks.
        deliver(r, .touchDown(location: start, time: r.now, touchCount: 2), order: .outerFirst)
        #expect(r.outer.movementEffects.isEmpty)
        // Rule 2 for a container asking first: the inner zooms, so two fingers are its (the M3 placeholder said no).
        #expect(r.inner.coord.participant!.isZoomEnabled)
        #expect(r.arbiter.containerOwner(ofDragFrom: start, translation: CGSize(width: 40, height: 0), touchCount: 2) == .participant)
        deliver(r, .touchesEnded(time: r.now), order: .outerFirst)
        #expect(!r.arbiter.isSequenceActive)
        let fixed = make(path, innerLimits: 1...1)
        #expect(!fixed.inner.coord.participant!.isZoomEnabled)
        #expect(fixed.arbiter.containerOwner(ofDragFrom: start, translation: CGSize(width: 40, height: 0), touchCount: 2) == .container)
    }

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func innerDeceleratingKeepsTheCatch(path: OSPath, order: Order) {
        // Tall content fits horizontally: a horizontal swipe would page, but the inner is flinging (rule 3).
        let r = make(path, innerContent: CGSize(width: 100, height: 600), innerOffset: CGPoint(x: 0, y: 200))
        fling(r, dx: 0, dy: -15, order: order)
        #expect(r.inner.state.isDecelerating)
        r.clearLogs()
        r.now += 0.1
        let y0 = r.inner.offset.y
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.inner.coord.effectsLog.contains(.catchMotion) && r.inner.coord.effectsLog.contains(.beginDragging))
        #expect(r.inner.offset.y >= y0)
        expectLoser(r.outer, offset: .zero)
        #expect(r.decisions == 1)
    }

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func outerSettlingKeepsTheSwipe(path: OSPath, order: Order) {
        // The inner is zoomed mid (it could follow), but the outer is still settling a page (rule 4).
        let r = make(path, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        fling(r, dx: -15, dy: 0, order: order)                                   // zoom 2 mid: the inner takes this one
        #expect(r.inner.state.isDecelerating || r.inner.state.phase == .animating)
        // Park the inner, then fling the outer itself: at zoom 1 the content fits, so the outer pages.
        r.inner.state.stopScrollingAndZooming()
        r.inner.state.track(offset: .zero, zoom: 1)
        r.now += 0.5
        fling(r, dx: -15, dy: 0, order: order)
        #expect(r.outer.state.isDecelerating || r.outer.state.phase == .animating, "outer settles \(r.outer.state.phase)")
        r.inner.state.track(offset: CGPoint(x: 50, y: 100), zoom: 2)
        r.clearLogs()
        r.now += 0.05
        let x0 = r.outer.offset.x
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.outer.coord.effectsLog.contains(.catchMotion) && r.outer.dragged)
        #expect(r.outer.offset.x >= x0)
        expectLoser(r.inner, offset: CGPoint(x: 50, y: 100), zoom: 2)
        #expect(r.decisions == 1)
    }

    // MARK: §1 table under .innerWhenZoomed

    @Test(arguments: OSPath.allCases, [Order.innerFirst, .outerFirst]) func innerWhenZoomedTable(path: OSPath, order: Order) {
        // zoom 1, fits, horizontal -> outer pages.
        var r = make(path, policy: .innerWhenZoomed)
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        expectLoser(r.inner, offset: .zero)
        #expect(r.decisions == 1)
        // zoom 1, tall content, vertical -> inner (rule 1 is the arbiter's, not the policy's).
        r = make(path, policy: .innerWhenZoomed, innerContent: CGSize(width: 100, height: 600), innerOffset: CGPoint(x: 0, y: 200))
        swipe(r, dx: 0, dy: -40, order: order)
        #expect(r.inner.dragged && r.inner.offset.y > 200)
        expectLoser(r.outer, offset: .zero)
        // zoom 2 mid, horizontal -> inner pans.
        r = make(path, policy: .innerWhenZoomed, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.inner.dragged && r.inner.offset.x > 50)
        expectLoser(r.outer, offset: .zero)
        // zoom 2 AT the edge, horizontal -> inner rubber-bands, the outer stays (the user's literal rule, R2).
        r = make(path, policy: .innerWhenZoomed, innerOffset: CGPoint(x: 100, y: 100), innerZoom: 2)
        swipe(r, dx: -40, dy: 0, order: order, end: false)
        #expect(r.inner.dragged && r.inner.offset.x > 100, "rubber band \(r.inner.offset)")
        expectLoser(r.outer, offset: .zero)
        #expect(r.decisions == 1)
        lift(r, dx: -60, dy: 0, order: order)
        // Settled a hair above the minimum counts as not zoomed.
        r = make(path, policy: .innerWhenZoomed, innerOffset: .zero, innerZoom: 1.0005)
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.outer.dragged)
        #expect(r.inner.movementEffects.isEmpty)
    }

    // MARK: .inner / .outer / .independent / .custom

    @Test(arguments: OSPath.allCases) func innerPolicyNeverPages(path: OSPath) {
        let r = make(path, policy: .inner)                                       // zoom 1, fits: would page
        swipe(r, dx: -40, dy: 0)
        expectLoser(r.outer, offset: .zero)
        #expect(r.inner.coord.effectsLog.contains(.beginDragging))
        #expect(r.arbiter.log.contains {
            if case let .owner(_, _, _, _, _, _, _, _, decided, result) = $0 { return decided && result == .participant }
            return false
        })
    }

    @Test(arguments: OSPath.allCases) func outerPolicyNeverPans(path: OSPath) {
        let r = make(path, policy: .outer, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)   // could follow
        swipe(r, dx: -40, dy: 0)
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        expectLoser(r.inner, offset: CGPoint(x: 50, y: 100), zoom: 2)
        // Off-axis swipes and pinches stay inside (rules 1–2 are not the policy's).
        let v = make(path, policy: .outer, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        swipe(v, dx: 0, dy: -40)
        #expect(v.inner.dragged)
        expectLoser(v.outer, offset: .zero)
    }

    @Test(arguments: OSPath.allCases) func independentIsTodaysBehaviour(path: OSPath) {
        let r = make(path, policy: .independent, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        #expect(r.inner.coord.participant == nil && !r.arbiter.hasParticipants)
        #expect(!r.outer.coord.environment().isContainer && !r.inner.coord.environment().hasArbiter)
        swipe(r, dx: -40, dy: 0)
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        #expect(r.inner.dragged && r.inner.offset.x > 50)
        #expect(r.arbiter.log.isEmpty)
        // Tracking begins at touch-down again, as without any arbiter.
        #expect(r.outer.coord.effectsLog.first == .beginTracking && r.inner.coord.effectsLog.first == .beginTracking)
    }

    @Test(arguments: OSPath.allCases) func customSeesColdGeometryAndDecides(path: OSPath) {
        @MainActor final class Seen { var contexts: [(tracked: Bool, canFollow: Bool, direction: FingerDirection, min: CGFloat, zoom: CGFloat, offset: CGPoint)] = [] }
        let seen = Seen()
        let policy = ZTronNestedScrollPolicy.custom { ctx in
            seen.contexts.append((ctx.geometry.isTracked, ctx.canFollow, ctx.fingerDirection, ctx.minimumZoomScale,
                                  ctx.geometry.zoomScale, ctx.geometry.contentOffset))
            return .outer
        }
        let r = make(path, policy: policy, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)   // could follow
        ZTronRenderCounters.reset()
        swipe(r, dx: -40, dy: 0)
        // No body ran and the context's geometry is the non-tracked `peekGeometry()`.
        let bodies = ZTronRenderCounters.snapshot.filter { $0.key.hasSuffix(".body") }
        #expect(bodies.isEmpty, "\(bodies)")
        #expect(seen.contexts.count == 1)
        if let c = seen.contexts.first {
            #expect(!c.tracked && c.canFollow && c.direction == .left && c.min == 1 && c.zoom == 2
                    && c.offset == CGPoint(x: 50, y: 100))
        }
        #expect(r.outer.dragged && r.outer.offset.x > 0)
        expectLoser(r.inner, offset: CGPoint(x: 50, y: 100), zoom: 2)
        // The other answer.
        let keep = make(path, policy: .custom { _ in .inner })
        swipe(keep, dx: -40, dy: 0)
        expectLoser(keep.outer, offset: .zero)
        #expect(keep.inner.coord.effectsLog.contains(.beginDragging))
    }

    // MARK: pinch while the outer owns the drag (M4 R5)

    @Test(arguments: OSPath.allCases) func pinchDuringOuterOwnedDrag(path: OSPath) {
        let r = make(path)                                                      // zoom 1, fits: the outer pages
        swipe(r, dx: -40, dy: 0, end: false)
        #expect(r.outer.dragged && r.inner.movementEffects.isEmpty)
        // Second finger: the outer's DragGesture dies (R1) -> its sequence releases; the inner pinches.
        let c = CGPoint(x: 50, y: 100)
        r.inner.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        r.outer.coord.cancelIfActive()
        r.inner.coord.handlePinch(.changed(magnification: 1.5, centroid: c, time: r.now))
        r.tick()
        #expect(r.inner.zoom > 1.4, "inner zoom \(r.inner.zoom)")
        #expect(!r.outer.state.isDragging && r.outer.delegate.log.contains { $0.hasPrefix("didEndDragging") })
        #expect(!r.arbiter.isSequenceActive)
        r.inner.coord.handlePinch(.ended(time: r.now))
        r.inner.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        deliver(r, .touchesEnded(time: r.now), order: .innerFirst)
        #expect(!r.inner.coord.isSequenceActive && !r.outer.coord.isSequenceActive)
        // The next swipe decides afresh.
        r.clearLogs()
        swipe(r, dx: -40, dy: 0)
        #expect(r.decisions == 1)
    }

    // MARK: two-axis outer

    @Test(arguments: OSPath.allCases) func twoAxisOuterUsesTheDominantAxis(path: OSPath) {
        // Outer scrolls both ways (offset mid); inner is a vertical list (fits horizontally) under the touch at
        // content point (150, 300).
        func rig() -> Rig {
            make(path, outerAxes: [.horizontal, .vertical], outerContent: CGSize(width: 300, height: 600),
                 outerOffset: CGPoint(x: 100, y: 200), innerAxes: .vertical, innerContent: CGSize(width: 100, height: 400),
                 innerOffset: CGPoint(x: 0, y: 100), innerLimits: 1...1,
                 innerFrame: CGRect(x: 100, y: 200, width: 100, height: 200))
        }
        var r = rig()
        swipe(r, dx: -40, dy: 0)                                                 // horizontal: the list cannot follow
        #expect(r.outer.dragged && r.outer.offset.x > 100)
        expectLoser(r.inner, offset: CGPoint(x: 0, y: 100))
        r = rig()
        swipe(r, dx: 0, dy: -40)                                                 // vertical: the list follows
        #expect(r.inner.dragged && r.inner.offset.y > 100)
        expectLoser(r.outer, offset: CGPoint(x: 100, y: 200))
        r = rig()
        swipe(r, dx: 40, dy: 30)                                                 // 37° off horizontal: dominant axis, no rule 1
        #expect(r.outer.dragged)
        expectLoser(r.inner, offset: CGPoint(x: 0, y: 100))
        if case let .owner(_, _, _, _, _, _, _, input, true, _) = r.arbiter.log.first(where: {
            if case .owner = $0 { return true } else { return false }
        }) ?? .endSequence(id: nil, ended: false) {
            #expect(input?.pagingAxis == .horizontal && input?.directionTolerance == 90)
        }
        // The same diagonal on a single-axis outer is off-axis (rule 1): the inner's.
        let single = make(path, innerContent: CGSize(width: 100, height: 600), innerOffset: CGPoint(x: 0, y: 200))
        swipe(single, dx: 40, dy: 30)
        #expect(single.inner.dragged)
        expectLoser(single.outer, offset: .zero)
    }

    // MARK: sequences

    @Test(arguments: OSPath.allCases) func sequenceBeginsAtTouchDownOrLazilyAndEnds(path: OSPath) {
        let r = make(path, innerOffset: CGPoint(x: 50, y: 100), innerZoom: 2)
        // Outer touch-down begins the sequence; both ends close it.
        r.outer.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        #expect(r.arbiter.isSequenceActive)
        r.outer.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.arbiter.isSequenceActive)
        // A touch the outer never saw (≤ 17 gated observer, inner alone): the inner's ask begins it lazily and the
        // inner's end closes it, so the next touch decides afresh.
        r.inner.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.inner.coord.handle(.dragChanged(translation: CGSize(width: -40, height: 0), startLocation: start, time: r.now))
        #expect(r.arbiter.isSequenceActive && r.arbiter.currentOwner == .participant)
        r.inner.coord.handle(.dragEnded(translation: CGSize(width: -40, height: 0), time: r.now, fallbackVelocity: nil))
        r.inner.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.arbiter.isSequenceActive)
        // Outer-begun sequence: the inner's end does not close it while the outer is still down.
        r.outer.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.inner.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.inner.coord.handle(.touchesEnded(time: r.now))
        #expect(r.arbiter.isSequenceActive)
        r.outer.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.arbiter.isSequenceActive)
    }

    // MARK: three levels: pager (ReferenceScrollArbiter) -> outer -> inner

    @Test(arguments: OSPath.allCases) func threeLevelChainTalksToTheNearestContainer(path: OSPath) {
        func rig(innerZoom: CGFloat, innerOffset: CGPoint) -> (Rig, ReferenceScrollArbiter) {
            let r = make(path, outerOffset: CGPoint(x: 100, y: 0), innerOffset: innerOffset, innerZoom: innerZoom)
            let pager = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "pager")
            r.outer.coord.setArbiter(pager)
            r.outer.coord.participant!.register(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
            r.clearLogs()
            return (r, pager)
        }
        // Inner at zoom 1: the outer can follow (pager -> .participant) and the inner cannot (nested -> .container).
        var (r, pager) = rig(innerZoom: 1, innerOffset: .zero)
        swipe(r, dx: -40, dy: 0)
        #expect(r.outer.dragged && r.outer.offset.x > 100)
        expectLoser(r.inner, offset: .zero)
        #expect(pager.currentOwner == nil && pager.log.contains {
            if case let .owner(_, _, _, _, _, _, _, _, decided, result) = $0 { return decided && result == .participant }
            return false
        })
        // Inner zoomed mid: the inner takes it; the outer ignores; the pager was told the outer owns it (no paging).
        (r, pager) = rig(innerZoom: 2, innerOffset: CGPoint(x: 50, y: 100))
        swipe(r, dx: -40, dy: 0)
        #expect(r.inner.dragged && r.inner.offset.x > 50)
        expectLoser(r.outer, offset: CGPoint(x: 100, y: 0))
        #expect(r.decisions == 1)
    }

    // MARK: default behaviour of a standalone view and of the registration modifier inputs

    enum OuterDisabled: CaseIterable { case state, native, noAxis }

    /// Review finding (N-a): an outer that cannot take the swipe (`.ztronScrollDisabled`, SwiftUI `scrollDisabled`,
    /// no axis) is no container. Zoomed inner at its edge, which rule 6 would otherwise hand to the outer: the inner
    /// rubber-bands as when alone, tracks from touch-down, and the arbiter neither begins nor decides anything.
    @Test(arguments: OSPath.allCases, OuterDisabled.allCases)
    func disabledOuterNeverArbitrates(path: OSPath, how: OuterDisabled) {
        for order in [Order.innerFirst, .outerFirst] { disabledOuterNeverArbitrates(path, how, order) }
    }

    func disabledOuterNeverArbitrates(_ path: OSPath, _ how: OuterDisabled, _ order: Order) {
        let r = make(path, outerAxes: how == .noAxis ? [] : .horizontal, innerOffset: CGPoint(x: 100, y: 100), innerZoom: 2)
        switch how {
        case .state: r.outer.state.isScrollEnabled = false
        case .native: r.outer.coord.nativeScrollEnabled = false
        case .noAxis: break
        }
        #expect(r.arbiter.hasParticipants && !r.outer.coord.environment().isContainer && !r.outer.coord.canTakeSwipe)
        #expect(!r.arbiter.isArbitrating && !r.inner.coord.environment().hasArbiter)
        swipe(r, dx: -40, dy: 0, order: order, end: false)
        #expect(r.inner.dragged && r.inner.offset.x > 100, "rubber band past the edge, as without an outer")
        #expect(r.inner.coord.effectsLog.first == .beginTracking, "tracking from touch-down, no deferral")
        #expect(!r.inner.coord.effectsLog.contains { if case .askOwner = $0 { return true } else { return false } })
        expectLoser(r.outer, offset: .zero)
        #expect(r.sequenceEntries == 0 && !r.arbiter.isSequenceActive && r.decisions == 0)
        lift(r, dx: -60, dy: 0, order: order)
        #expect(!r.arbiter.isSequenceActive && r.sequenceEntries == 0)
        // Re-enabled, the same swipe pages again (the gate is read per touch).
        switch how {
        case .state: r.outer.state.isScrollEnabled = true
        case .native: r.outer.coord.nativeScrollEnabled = true
        case .noAxis: return
        }
        var settle = 0
        while r.inner.state.phase != .idle, settle < 600 { r.tick(); settle += 1 }
        r.clearLogs()
        swipe(r, dx: -40, dy: 0, order: order)
        #expect(r.outer.dragged && r.outer.offset.x > 0 && r.decisions == 1)
    }

    @Test(arguments: OSPath.allCases) func outerWithoutInnersBehavesAsToday(path: OSPath) {
        let clock = Clock()
        let outer = makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), offset: .zero,
                             paging: true, clock: clock)
        #expect(!outer.coord.environment().isContainer)
        outer.coord.handle(.touchDown(location: start, time: clock.t, touchCount: 1))
        #expect(outer.coord.effectsLog.first == .beginTracking && !outer.coord.nestedArbiter.isSequenceActive)
        outer.coord.handle(.dragChanged(translation: CGSize(width: -40, height: 0), startLocation: start, time: clock.t))
        #expect(!outer.coord.effectsLog.contains { if case .askOwner = $0 { return true } else { return false } })
        #expect(outer.coord.nestedArbiter.log.isEmpty)
    }
}
