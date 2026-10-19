import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// A custom behavior that records what the pipeline hands it (M6 session 1, tests 1 and 2).
@MainActor
final class BehaviorLog {
    var contexts: [ZTronScrollTargetBehaviorContext] = []
    var targets: [ZTronScrollTarget] = []
    var propertiesContexts: [ZTronScrollTargetBehaviorPropertiesContext] = []
    var order: [String] = []
}

struct RecordingBehavior: ZTronScrollTargetBehavior {
    let log: BehaviorLog
    var limitsVelocity = false
    var edit: @MainActor (inout ZTronScrollTarget) -> Void = { _ in }

    @MainActor func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        log.contexts.append(context)
        log.targets.append(target)
        log.order.append("updateTarget")
        edit(&target)
    }

    @MainActor func properties(context: PropertiesContext) -> Properties {
        log.propertiesContexts.append(context)
        return Properties(limitsVelocity: limitsVelocity)
    }
}

@MainActor
final class OrderedDelegate: ZTronScrollViewDelegate {
    let log: BehaviorLog
    var retarget: CGPoint?
    var seenTarget: CGPoint?
    var seenVelocity: CGPoint?
    init(_ log: BehaviorLog) { self.log = log }
    func scrollViewWillEndDragging(_ s: ZTronScrollState, withVelocity v: CGPoint, targetContentOffset: inout CGPoint) {
        log.order.append("willEndDragging")
        seenVelocity = v
        seenTarget = targetContentOffset
        if let retarget { targetContentOffset = retarget }
    }
}

@MainActor
@Suite(.serialized)
struct TargetBehaviorTests {
    static let env = PanSessionTests.env()

    func make(_ path: OSPath, at offset: CGPoint = CGPoint(x: 0, y: 300), zoom: CGFloat = 1) -> (ZTronScrollState, BehaviorLog, OrderedDelegate) {
        let s = makeState(path)
        let log = BehaviorLog()
        let d = OrderedDelegate(log)
        s.delegate = d
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
        s.track(offset: offset, zoom: zoom)
        s.beginTracking(); s.beginDragging()
        return (s, log, d)
    }

    /// Finger moving up at `v` pt/s (content offset increases) for 120 ms ending at `lift`.
    func tracker(vy: CGFloat, lift: TimeInterval = 100) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = lift - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: 0, y: -vy * CGFloat(time - (lift - 0.12))), at: time)
        }
        return t
    }

    func request(_ origin: CGPoint, dragStart: CGPoint? = nil, lift: TimeInterval = 100) -> ReleaseRequest {
        ReleaseRequest(origin: origin, dragStart: dragStart ?? origin, liftTime: lift, fallbackVelocity: nil)
    }

    func run(_ s: ZTronScrollState, to end: TimeInterval = 112, dt: TimeInterval = 1.0 / 60, each: () -> Void = {}) {
        var t = 100.0
        while t < end && s.isClockRunning {
            t += dt
            s.step(to: Date(timeIntervalSinceReferenceDate: t))
            each()
        }
    }

    /// A retargeted decay lands on its target to within rounding (1e-13), not bit for bit.
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }

    // MARK: 1 · pipeline

    @Test(arguments: OSPath.allCases) func behaviorSeesVelocityGeometryAndAxes(path: OSPath) {
        let (s, log, d) = make(path)
        s.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: log))
        s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1000), env: Self.env, settings: ReleaseSettings())
        #expect(log.contexts.count == 1)
        let c = log.contexts[0]
        // The accelerated velocity the delegate sees in pt/ms, in pt/s here.
        #expect(abs(c.velocity.dy - (d.seenVelocity?.y ?? 0) * 1000) < 1e-6)
        #expect(abs(c.velocity.dy - 1000) < 100 && c.velocity.dx == 0)
        #expect(c.contentSize == CGSize(width: 300, height: 900))
        #expect(c.containerSize == CGSize(width: 100, height: 200))
        #expect(c.axes == [.horizontal, .vertical])
        // The original target is the natural rest of the fling (clamped), sized like the container.
        #expect(c.originalTarget.rect.size == CGSize(width: 100, height: 200) && c.originalTarget.anchor == nil)
        #expect(c.originalTarget.rect.origin == CGPoint(x: 0, y: 700))
        #expect(log.propertiesContexts.count == 1 && log.propertiesContexts[0].axes == [.horizontal, .vertical])
    }

    @Test(arguments: OSPath.allCases) func contentSizeIsTheZoomedSize(path: OSPath) {
        let (s, log, _) = make(path, zoom: 2.5)
        s.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: log))
        s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1000), env: Self.env, settings: ReleaseSettings())
        #expect(log.contexts[0].contentSize == CGSize(width: 750, height: 2250))
        #expect(log.contexts[0].info.zoomScale == 2.5)
    }

    @Test(arguments: OSPath.allCases) func axesFollowWhatThePanDrives(path: OSPath) {
        let (s, log, _) = make(path)
        var env = Self.env
        env.axes = [.vertical]
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.x = 90; $0.rect.origin.y = 420 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        let (mx, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1000), env: env, settings: ReleaseSettings())
        #expect(log.contexts[0].axes == [.vertical])
        #expect(near(my.endPosition, 420))
        #expect(mx.endPosition == 0)               // the horizontal axis is not driven: the behavior cannot move it
    }

    @Test(arguments: OSPath.allCases) func mutatingTheRectOriginMovesTheEndPosition(path: OSPath) {
        let (s, log, _) = make(path)
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = 420 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(abs(my.endPosition - 420) < 1e-6)
        run(s)
        #expect(s.peek.presentationOffset.y == 420)
    }

    @Test(arguments: OSPath.allCases) func anchorPlacesTheRectAlongTheContainer(path: OSPath) {
        let (s, log, _) = make(path)
        var move = RecordingBehavior(log: log)
        // A 500 pt rect starting at 100 with its anchor at the bottom: the container ends at 100 + (500 - 200).
        move.edit = { $0.rect = CGRect(x: 0, y: 100, width: 100, height: 500); $0.anchor = UnitPoint(x: 0, y: 1) }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(abs(my.endPosition - 400) < 1e-6)
    }

    @Test(arguments: OSPath.allCases) func targetIsClampedToTheBounds(path: OSPath) {
        let (s, log, _) = make(path)
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = 5000 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(my.endPosition == 700)
    }

    @Test(arguments: OSPath.allCases) func nonFiniteTargetFallsBackToTheNaturalRest(path: OSPath) {
        let (s, log, _) = make(path)
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = .nan }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(my.endPosition == 700)
        let (s2, log2, _) = make(path)
        s2.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: log2))
        let (_, plain) = s2.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(plain.endPosition == 700)
    }

    @Test(arguments: OSPath.allCases) func willEndDraggingRunsAfterAndCanOverride(path: OSPath) {
        let (s, log, d) = make(path)
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = 420 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        // The delegate sees the behavior's result ...
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(log.order == ["updateTarget", "willEndDragging"])
        #expect(d.seenTarget?.y == 420 && near(my.endPosition, 420))
        // ... and overrides it.
        let (s2, log2, d2) = make(path)
        var move2 = RecordingBehavior(log: log2)
        move2.edit = { $0.rect.origin.y = 420 }
        s2.targetBehavior = AnyZTronScrollTargetBehavior(move2)
        d2.retarget = CGPoint(x: 0, y: 250)
        let (_, my2) = s2.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(d2.seenTarget?.y == 420 && near(my2.endPosition, 250))
    }

    @Test(arguments: OSPath.allCases) func untouchedTargetKeepsTheNaturalDecay(path: OSPath) {
        // A behavior that leaves the target alone must not change how the fling plays out (edge bounce included).
        let (s, log, _) = make(path, at: CGPoint(x: 0, y: 650))
        s.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: log))
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 650)), tracker: tracker(vy: 3000), env: Self.env, settings: ReleaseSettings())
        guard case let .decay(_, _, handoff) = my, let h = handoff else { Issue.record("expected the natural decay with an edge hand-off, got \(my)"); return }
        #expect(h.edge == 700 && h.bounces)
    }

    @Test(arguments: OSPath.allCases) func limitsVelocityCapsAFlingToOneContainerLength(path: OSPath) {
        // Without the flag a 10 000 pt/s fling runs to the end of the content (700) ...
        let (free, freeLog, _) = make(path)
        free.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: freeLog))
        let (_, unlimited) = free.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 10_000), env: Self.env, settings: ReleaseSettings())
        #expect(unlimited.endPosition == 700)
        // ... with it the behavior sees the capped fling: one container (200 pt) from the lift, never more.
        let (s, log, d) = make(path)
        var limited = RecordingBehavior(log: log)
        limited.limitsVelocity = true
        s.targetBehavior = AnyZTronScrollTargetBehavior(limited)
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 10_000), env: Self.env, settings: ReleaseSettings())
        let c = log.contexts[0]
        #expect(c.velocity.dy < 10_000 / 10)                                     // capped (about 2 containers per second)
        #expect(abs(c.originalTarget.rect.origin.y - 500) < 1e-6)               // 300 + one container
        #expect(abs(my.endPosition - 500) < 1e-6)
        #expect((d.seenVelocity?.y ?? 0) > 9)                                    // the delegate still sees the gesture's velocity
        run(s)
        #expect(abs(s.peek.presentationOffset.y - 500) <= 0.5)
    }

    @Test(arguments: OSPath.allCases) func limitsVelocityLeavesSlowFlingsAlone(path: OSPath) {
        let (s, log, _) = make(path)
        var limited = RecordingBehavior(log: log)
        limited.limitsVelocity = true
        s.targetBehavior = AnyZTronScrollTargetBehavior(limited)
        s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 300), env: Self.env, settings: ReleaseSettings())
        let c = log.contexts[0]
        #expect(abs(c.velocity.dy - 300) < 30)
        #expect(abs(c.originalTarget.rect.origin.y - (300 + 300 * 0.4995)) < 20)  // the plain natural rest
    }

    @Test(arguments: OSPath.allCases) func releaseTargetHookFiresOncePerReleaseWithTheLandingPoint(path: OSPath) {
        let (s, log, _) = make(path)
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = 420 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        var landings: [CGPoint] = []
        s.onReleaseTargetDecided = { landings.append($0) }
        let (mx, my) = s.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1500), env: Self.env, settings: ReleaseSettings())
        #expect(landings == [CGPoint(x: mx.endPosition, y: my.endPosition)] && near(my.endPosition, 420))
        run(s)
        #expect(landings.count == 1)                                             // never per frame
        // Without a behavior, too: the natural landing point.
        let (s2, _, _) = make(path)
        var plain: [CGPoint] = []
        s2.onReleaseTargetDecided = { plain.append($0) }
        let (_, my2) = s2.endDrag(request(CGPoint(x: 0, y: 300)), tracker: tracker(vy: 1000), env: Self.env, settings: ReleaseSettings())
        #expect(plain.count == 1 && plain[0].y == my2.endPosition)
    }

    // MARK: 2 · .paging ≡ isPagingEnabled

    /// The legacy `isPagingEnabled` formula (M3), the reference for the equivalence: `PagingSolver` from the lift offset,
    /// the offset where the drag began and the release velocity, one page = the container length, bounds 0...700.
    func legacyPage(origin: CGFloat, dragStart: CGFloat, velocity: CGFloat) -> CGFloat {
        PagingSolver.target(current: origin, dragStart: dragStart, velocity: velocity, pageLength: 200,
                            bounds: AxisBounds(min: 0, max: 700))
    }

    static let pagingTable: [(origin: CGFloat, start: CGFloat, vy: CGFloat)] = [
        (130, 0, 0), (110, 0, 0), (100, 0, 0), (0, 0, 0), (70, 200, 0), (250, 200, 0), (340, 200, 0),
        (210, 200, 6000), (190, 200, -6000), (210, 200, 400), (190, 200, -400), (210, 200, 250), (190, 200, -250),
        (610, 600, 3000), (690, 600, 8000), (30, 0, -2000), (400, 400, 301), (400, 400, -301), (400, 400, 299),
    ]

    @Test(arguments: OSPath.allCases) func pagingBehaviorEqualsTheKnobOverTheTable(path: OSPath) {
        for row in Self.pagingTable {
            // The knob: no behavior, `isPagingEnabled` through the release settings.
            let (knobState, _, knobDelegate) = make(path, at: CGPoint(x: 0, y: row.origin))
            var knob = ReleaseSettings(); knob.isPagingEnabled = true
            let (_, byKnob) = knobState.endDrag(request(CGPoint(x: 0, y: row.origin), dragStart: CGPoint(x: 0, y: row.start)),
                                                tracker: tracker(vy: row.vy), env: Self.env, settings: knob)
            // The explicit behavior, knob off.
            let (behaviorState, _, _) = make(path, at: CGPoint(x: 0, y: row.origin))
            behaviorState.targetBehavior = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior())
            let (_, byBehavior) = behaviorState.endDrag(request(CGPoint(x: 0, y: row.origin), dragStart: CGPoint(x: 0, y: row.start)),
                                                        tracker: tracker(vy: row.vy), env: Self.env, settings: ReleaseSettings())
            let velocity = (knobDelegate.seenVelocity?.y ?? 0) * 1000
            let expected = legacyPage(origin: row.origin, dragStart: row.start, velocity: velocity)
            #expect(near(byKnob.endPosition, expected), "knob \(row)")
            #expect(near(byBehavior.endPosition, expected), "behavior \(row)")
        }
    }

    @Test(arguments: OSPath.allCases) func pagingNeverSkipsAPageAndOnlyDrivesEnabledAxes(path: OSPath) {
        let (s, _, _) = make(path, at: CGPoint(x: 0, y: 210))
        s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior())
        let (mx, my) = s.endDrag(request(CGPoint(x: 0, y: 210), dragStart: CGPoint(x: 0, y: 200)), tracker: tracker(vy: 9000),
                                 env: Self.env, settings: ReleaseSettings())
        #expect(near(my.endPosition, 400) && mx.endPosition == 0)
        // Horizontal scrolling disabled: the x axis is not paged (page length 100 would otherwise snap 130 to 100).
        let (s2, _, _) = make(path, at: CGPoint(x: 130, y: 210))
        s2.targetBehavior = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior())
        var env = Self.env; env.axes = [.vertical]
        let (mx2, _) = s2.endDrag(request(CGPoint(x: 130, y: 210), dragStart: CGPoint(x: 0, y: 200)), tracker: tracker(vy: 0),
                                  env: env, settings: ReleaseSettings())
        #expect(mx2.endPosition == 130)
    }

    @Test(arguments: OSPath.allCases) func pagingFlickBackAtTheFirstPageDoesNotBounce(path: OSPath) {
        // The page target equals the clamped natural rest here; the knob retargeted the motion anyway, so it must not
        // run into the edge and spring back (the legacy behavior, kept by the snapping flag).
        for byKnob in [true, false] {
            let (s, _, _) = make(path, at: CGPoint(x: 0, y: 190))
            var settings = ReleaseSettings()
            if byKnob { settings.isPagingEnabled = true } else { s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior()) }
            let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 190), dragStart: CGPoint(x: 0, y: 200)), tracker: tracker(vy: -6000),
                                    env: Self.env, settings: settings)
            #expect(near(my.endPosition, 0))
            var lowest: CGFloat = 0
            run(s, to: 115) { lowest = min(lowest, s.peek.presentationOffset.y) }
            #expect(lowest > -1e-6 && abs(s.peek.presentationOffset.y) < 1e-6, "byKnob \(byKnob)")
        }
    }

    @Test(arguments: OSPath.allCases) func explicitBehaviorBeatsTheKnob(path: OSPath) {
        let (s, log, _) = make(path, at: CGPoint(x: 0, y: 130))
        var move = RecordingBehavior(log: log)
        move.edit = { $0.rect.origin.y = 123 }
        s.targetBehavior = AnyZTronScrollTargetBehavior(move)
        var knob = ReleaseSettings(); knob.isPagingEnabled = true
        let (_, my) = s.endDrag(request(CGPoint(x: 0, y: 130), dragStart: CGPoint(x: 0, y: 0)), tracker: tracker(vy: 0), env: Self.env, settings: knob)
        #expect(near(my.endPosition, 123))                                       // the knob alone would have paged to 200
        #expect(log.contexts.count == 1)
    }

    @Test(arguments: OSPath.allCases) func effectiveBehaviorFollowsTheKnobAndTheExplicitBehavior(path: OSPath) {
        let s = makeState(path)
        #expect(s.effectiveTargetBehavior == nil)
        s.isPagingEnabled = true
        #expect(s.effectiveTargetBehavior?.base is ZTronPagingScrollTargetBehavior)
        let log = BehaviorLog()
        s.targetBehavior = AnyZTronScrollTargetBehavior(RecordingBehavior(log: log))
        #expect(s.effectiveTargetBehavior?.base is RecordingBehavior)
        s.targetBehavior = nil
        #expect(s.effectiveTargetBehavior?.base is ZTronPagingScrollTargetBehavior)
        s.isPagingEnabled = false
        #expect(s.effectiveTargetBehavior == nil)
    }

    @Test func pagingPropertiesLimitTheVelocity() {
        let p = ZTronPagingScrollTargetBehavior().properties(context: ZTronScrollTargetBehaviorPropertiesContext(
            axes: .horizontal, contentSize: .zero, containerSize: .zero))
        #expect(p.limitsVelocity && p.limitsScrolls && p != .default)
        #expect(ZTronScrollTargetBehaviorProperties.default.limitsVelocity == false)
        var q = ZTronScrollTargetBehaviorProperties()
        q.limitsScrolls = true
        #expect(q.limitsVelocity)
    }

    @Test func erasingKeepsTheBaseAndNeverNests() {
        let paging = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior())
        let twice = AnyZTronScrollTargetBehavior(paging)
        #expect(twice.base is ZTronPagingScrollTargetBehavior)
        #expect(twice.snapsTarget && paging.snapsTarget)
        #expect(AnyZTronScrollTargetBehavior(RecordingBehavior(log: BehaviorLog())).snapsTarget == false)
    }

    @Test func staticSpellingResolvesThroughOurProtocol() {
        func accepts(_ behavior: some ZTronScrollTargetBehavior) -> Bool { behavior is ZTronPagingScrollTargetBehavior }
        #expect(accepts(.paging))
        let concrete: ZTronPagingScrollTargetBehavior = .paging
        #expect(concrete.properties(context: ZTronScrollTargetBehaviorPropertiesContext(axes: .vertical, contentSize: .zero, containerSize: .zero)).limitsVelocity)
    }
}
