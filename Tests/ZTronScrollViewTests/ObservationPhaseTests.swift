import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M7 session 2 (design §7 T7, T8, T9): phase observers, their order against the delegate at every site, and target visibility.
@MainActor
@Suite(.serialized)
struct ObservationPhaseTests {
    private func sized(_ path: OSPath) -> (ZTronScrollState, SeqLog) {
        let s = makeState(path)
        let log = SeqLog(), d = SeqDelegate(log)
        s.delegate = d
        log.keep = d
        s.now = { 100.2 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        return (s, log)
    }
    /// A phase observer logging `p:<old>><new>` into the same log as the delegate (`d:`).
    private func observePhases(_ s: ZTronScrollState, _ log: SeqLog) {
        _ = s.observers.addPhase(PhaseObserverBox { old, new, _ in log.entries.append("p:\(old)>\(new)") })
    }
    private func step(_ s: ZTronScrollState, _ t: TimeInterval) { s.step(to: Date(timeIntervalSinceReferenceDate: t)) }

    // MARK: T8 — the delegate call precedes the phase transition that belongs to it

    @Test(arguments: OSPath.allCases) func dragDecelerateIdleOrder(path: OSPath) {
        let (s, log) = sized(path)
        observePhases(s, log)
        log.entries.removeAll()
        let drv = PanDriver(s)
        drv.send(.touchDown(location: .zero, time: 100, touchCount: 1))
        var t = 100.0
        for i in 1...8 {
            t += 0.015
            drv.move(-CGFloat(i) * 15, t: t)
            step(s, t)
        }
        drv.send(.dragEnded(translation: CGSize(width: 0, height: -120), time: t, fallbackVelocity: nil))
        var tick = 100.12
        while s.isClockRunning && tick < 110 { tick += 1.0 / 60; step(s, tick) }
        let e = log.entries
        func index(_ name: String) -> Int { e.firstIndex(of: name) ?? -1 }
        #expect(index("p:idle>tracking") >= 0 && index("p:idle>tracking") < index("d:willBeginDragging"))
        #expect(index("p:tracking>interacting") == index("d:willBeginDragging") + 1, "willBeginDragging, then tracking→interacting: \(e)")
        #expect(index("p:interacting>decelerating") == index("d:willBeginDecelerating") + 1, "willBeginDecelerating, then →decelerating: \(e)")
        #expect(index("p:decelerating>idle") == index("d:didEndDecelerating") + 1, "didEndDecelerating, then →idle: \(e)")
        #expect(e.filter { $0.hasPrefix("p:") } == ["p:idle>tracking", "p:tracking>interacting", "p:interacting>decelerating", "p:decelerating>idle"])
    }

    @Test(arguments: OSPath.allCases) func programmaticAnimationOrder(path: OSPath) {
        let (s, log) = sized(path)
        observePhases(s, log)
        log.entries.removeAll()
        s.setContentOffset(CGPoint(x: 0, y: 500), animated: true)
        var t = 100.2
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t) }
        let e = log.entries
        #expect(e.filter { $0.hasPrefix("p:") } == ["p:idle>animating", "p:animating>idle"], "\(e)")
        #expect(e.firstIndex(of: "p:animating>idle") == (e.firstIndex(of: "d:didEndScrollingAnimation") ?? -2) + 1, "didEndScrollingAnimation, then →idle: \(e)")
    }

    @Test(arguments: OSPath.allCases) func theZoomBounceStaysDecelerating(path: OSPath) {
        let host = PinchPanTests()
        let r = host.make(path, limits: 1...2)
        let log = SeqLog()
        let delegate = SeqDelegate(log)
        r.state.delegate = delegate
        log.keep = delegate
        observePhases(r.state, log)
        let c = CGPoint(x: 100, y: 200)
        host.twoFingersDown(r, at: c)
        host.magnify(r, 3, at: c); r.tick()
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        let phases = log.entries.filter { $0.hasPrefix("p:") }
        #expect(phases == ["p:idle>tracking", "p:tracking>interacting", "p:interacting>decelerating", "p:decelerating>idle"]
                || phases == ["p:idle>interacting", "p:interacting>decelerating", "p:decelerating>idle"], "\(phases)")
        #expect(!phases.contains { $0.contains(">animating") }, "the zoom bounce is .decelerating (D13): \(phases)")
        let e = log.entries
        #expect(e.firstIndex(of: "p:decelerating>idle") == (e.firstIndex { $0.hasPrefix("d:didEndZooming") } ?? -2) + 1, "didEndZooming, then →idle: \(e)")
    }

    @Test(arguments: OSPath.allCases) func aCatchEndsTheDecelerationBeforeTheNewTouch(path: OSPath) {
        let (s, log) = sized(path)
        observePhases(s, log)
        s.beginTracking(); s.beginDragging()
        let tr = PointVelocityTracker()
        _ = s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100.2, fallbackVelocity: CGVector(dx: 0, dy: -2000)),
                      tracker: tr, env: PanPathEnv.base, settings: ReleaseSettings())
        log.entries.removeAll()
        s.interrupt()
        s.beginTracking()
        #expect(log.entries.filter { $0.hasPrefix("p:") } == ["p:decelerating>idle", "p:idle>tracking"], "\(log.entries)")
    }

    // MARK: T7 — both overloads, context, no initial call

    @Test(arguments: OSPath.allCases) func contextCarriesTheGeometryAtTheFlushAndTheVelocity(path: OSPath) {
        let (s, _) = sized(path)
        var seen: [(ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext)] = []
        _ = s.observers.addPhase(PhaseObserverBox { seen.append(($0, $1, $2)) })
        #expect(seen.isEmpty, "no initial call")
        let drv = PanDriver(s)
        drv.send(.touchDown(location: .zero, time: 100, touchCount: 1))
        var t = 100.0
        for i in 1...8 {
            t += 0.015
            drv.move(-CGFloat(i) * 15, t: t)
            step(s, t)
        }
        drv.send(.dragEnded(translation: CGSize(width: 0, height: -120), time: t, fallbackVelocity: nil))
        let tracking = seen.first { $0.0 == .idle && $0.1 == .tracking }
        let toDecel = seen.first { $0.0 == .interacting && $0.1 == .decelerating }
        #expect(tracking != nil && tracking?.2.velocity == nil, "idle→tracking: velocity unknown")
        #expect(toDecel?.2.velocity != nil, "interacting→decelerating carries the release velocity")
        if let v = toDecel?.2.velocity { #expect(v.dy > 200, "pt/s, content moving down the offset axis: \(v)") }
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t) }
        let last = seen.last
        #expect(last?.0 == .decelerating && last?.1 == .idle)
        #expect(last?.2.geometry.contentOffset == s.peek.presentationOffset, "geometry at the flush = the settled state")
    }

    @Test(arguments: OSPath.allCases) func bothOverloadsOfTheMemberFire(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        let two = SeqLog(), three = SeqLog()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { CountedContent(counter: Counter()) }
                .onScrollPhaseChange { old, new in two.entries.append("\(old)>\(new)") }
                .onScrollPhaseChange { old, new, context in three.entries.append("\(old)>\(new):\(context.velocity == nil)") })
        }
        pump(0.2)
        s.setContentOffset(CGPoint(x: 0, y: 100), animated: true)
        var t = 100.0
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t) }
        pump(0.05)
        #expect(two.entries == ["idle>animating", "animating>idle"], "\(two.entries)")
        #expect(three.entries.count == 2 && three.entries[0].hasPrefix("idle>animating"), "\(three.entries)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theTwinFiresAndHasNoInitialCall(path: OSPath) {
        let s = makeState(path)
        let log = SeqLog()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { CountedContent(counter: Counter()) }
                .frame(maxWidth: .infinity)
                .onZTronScrollPhaseChange { old, new, _ in log.entries.append("\(old)>\(new)") })
        }
        pump(0.2)
        #expect(log.entries.isEmpty, "no initial call: \(log.entries)")
        s.beginTracking()
        pump(0.05)
        #expect(log.entries == ["idle>tracking"], "\(log.entries)")
        s.endTracking()
        unhost(w)
    }

    // MARK: T9 — target visibility

    private func registry(_ s: ZTronScrollState, _ frames: [(AnyHashable, CGRect)]) {
        for (id, frame) in frames { s.targets.register(id, frame: frame) }
    }

    @Test(arguments: OSPath.allCases) func targetVisibilityIsLayoutOrderedTypeFilteredAndFiresInitially(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 900), displayScale: 2))
        // Registered out of layout order, with a foreign id type among them.
        registry(s, [(2, CGRect(x: 0, y: 200, width: 100, height: 100)), (0, CGRect(x: 0, y: 0, width: 100, height: 100)),
                     (1, CGRect(x: 0, y: 100, width: 100, height: 100)), ("other", CGRect(x: 0, y: 50, width: 100, height: 100)),
                     (3, CGRect(x: 0, y: 300, width: 100, height: 100))])
        var calls: [[Int]] = []
        _ = s.observers.addTargetVisibility(TypedTargetVisibilityBox<Int>(threshold: 0.5) { calls.append($0) })
        s.deliverObservers()
        #expect(calls == [[0, 1]], "initial fire, layout order, the String id filtered out: \(calls)")
        s.track(offset: CGPoint(x: 0, y: 150), zoom: 1)
        #expect(calls.last == [1, 2, 3], "items 1 and 3 are half visible, 2 fully: \(calls)")
        s.track(offset: CGPoint(x: 0, y: 120), zoom: 1)
        #expect(calls.last == [1, 2], "\(calls)")
        let count = calls.count
        s.track(offset: CGPoint(x: 0, y: 125), zoom: 1)
        #expect(calls.count == count, "same list: silent")
    }

    /// PARITY-s1: SwiftUI measures target visibility in the unobscured area (native, 50 pt top inset, offset 250 over 44 pt
    /// rows: rows 7 and 8, not the row 6 behind the inset).
    @Test(arguments: OSPath.allCases) func targetVisibilityLeavesOutWhatTheInsetsCover(path: OSPath) {
        let s = makeState(path)
        var m = ScrollMetrics(viewportSize: CGSize(width: 100, height: 150), contentSize: CGSize(width: 100, height: 4400), displayScale: 2)
        m.contentInset = EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0)
        s.contentInsetAdjustmentBehavior = .never
        s.setMetrics(m)
        registry(s, (0..<100).map { (AnyHashable($0), CGRect(x: 0, y: CGFloat($0) * 44, width: 100, height: 44)) })
        var calls: [[Int]] = []
        _ = s.observers.addTargetVisibility(TypedTargetVisibilityBox<Int>(threshold: 0.5) { calls.append($0) })
        s.track(offset: CGPoint(x: 0, y: 250), zoom: 1)
        #expect(calls.last == [7, 8], "\(calls)")
    }

    @Test(arguments: OSPath.allCases) func aChangeAmongOtherTypesIsSilentForTheTypedBox(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 900), displayScale: 2))
        registry(s, [(0, CGRect(x: 0, y: 0, width: 100, height: 100))])
        var ints = 0, strings: [[String]] = []
        _ = s.observers.addTargetVisibility(TypedTargetVisibilityBox<Int>(threshold: 0.5) { _ in ints += 1 })
        _ = s.observers.addTargetVisibility(TypedTargetVisibilityBox<String>(threshold: 0.5) { strings.append($0) })
        s.deliverObservers()
        #expect(ints == 1 && strings == [[]])
        s.targets.register("a", frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        #expect(ints == 1, "a String id appeared: the Int box has nothing to say")
        #expect(strings == [[], ["a"]])
    }

    @Test(arguments: OSPath.allCases) func theListIsRecomputedWhenFramesMoveWithoutMotion(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 900), displayScale: 2))
        registry(s, [(0, CGRect(x: 0, y: 0, width: 100, height: 100)), (1, CGRect(x: 0, y: 500, width: 100, height: 100))])
        var calls: [[Int]] = []
        _ = s.observers.addTargetVisibility(TypedTargetVisibilityBox<Int>(threshold: 0.5) { calls.append($0) })
        s.deliverObservers()
        #expect(calls == [[0]])
        s.targets.register(1, frame: CGRect(x: 0, y: 100, width: 100, height: 100))     // layout moved it into view, no scroll
        #expect(calls == [[0], [0, 1]], "registry.version bumped: recomputed without motion: \(calls)")
        s.targets.unregister(0)
        #expect(calls.last == [1], "\(calls)")
    }

    @Test(arguments: OSPath.allCases) func memberAndTwinOverTheRegistryOnAHostedView(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let member = SeqLog(), twin = SeqLog()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) {
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in Color.blue.frame(height: 100).ztronScrollID(i) }
                }
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.2) { member.entries.append("\($0)") }
            .frame(maxWidth: .infinity)
            .onZTronScrollTargetVisibilityChange(idType: Int.self, threshold: 0.2) { twin.entries.append("\($0)") })
        }
        pump(0.4)
        // The hosted window leaves ~140 pt of viewport under the status bar: a 0.2 threshold shows two rows at both offsets.
        #expect(member.entries.last == "[0, 1]" && twin.entries.last == "[0, 1]", "member \(member.entries) twin \(twin.entries)")
        s.track(offset: CGPoint(x: 0, y: 200), zoom: 1)
        pump(0.1)
        #expect(member.entries.last == "[2, 3]" && twin.entries.last == "[2, 3]", "member \(member.entries) twin \(twin.entries)")
        unhost(w)
    }
}
