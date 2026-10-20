import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// One log shared by a delegate and the modifier boxes: `d:` entries are the delegate's, `m:` entries the modifiers'.
@MainActor
final class SeqLog {
    var entries: [String] = []
    /// `ZTronScrollState.delegate` is weak: the log keeps the delegate alive for the test.
    var keep: AnyObject?
    func names(_ tag: String) -> [String] { entries.filter { $0.hasPrefix(tag + ":") }.map { String($0.dropFirst(tag.count + 1)) } }
    /// Every delegate entry is followed at once by the modifier entry of the same call (delegate first, same site).
    var isInterleaved: Bool {
        guard entries.count.isMultiple(of: 2) else { return false }
        for i in stride(from: 0, to: entries.count, by: 2) {
            guard entries[i].hasPrefix("d:"), entries[i + 1] == "m:" + entries[i].dropFirst(2) else { return false }
        }
        return true
    }
}

/// A delegate that logs every method as `d:<name>`; `retarget` / `allowsScrollToTop` steer the two non-void ones.
@MainActor
final class SeqDelegate: ZTronScrollViewDelegate {
    let log: SeqLog
    var retarget: CGPoint?
    var allowsScrollToTop = true
    var seenVelocity: CGPoint?
    init(_ log: SeqLog) { self.log = log }
    func scrollViewDidScroll(_ s: ZTronScrollState) { log.entries.append("d:didScroll") }
    func scrollViewDidZoom(_ s: ZTronScrollState) { log.entries.append("d:didZoom") }
    func scrollViewWillBeginDragging(_ s: ZTronScrollState) { log.entries.append("d:willBeginDragging") }
    func scrollViewWillEndDragging(_ s: ZTronScrollState, withVelocity v: CGPoint, targetContentOffset: inout CGPoint) {
        log.entries.append("d:willEndDragging"); seenVelocity = v
        if let retarget { targetContentOffset = retarget }
    }
    func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate d: Bool) { log.entries.append("d:didEndDragging(\(d))") }
    func scrollViewWillBeginDecelerating(_ s: ZTronScrollState) { log.entries.append("d:willBeginDecelerating") }
    func scrollViewDidEndDecelerating(_ s: ZTronScrollState) { log.entries.append("d:didEndDecelerating") }
    func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState) { log.entries.append("d:didEndScrollingAnimation") }
    func scrollViewWillBeginZooming(_ s: ZTronScrollState) { log.entries.append("d:willBeginZooming") }
    func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale scale: CGFloat) { log.entries.append("d:didEndZooming(\(scale))") }
    func scrollViewShouldScrollToTop(_ s: ZTronScrollState) -> Bool { log.entries.append("d:shouldScrollToTop"); return allowsScrollToTop }
    func scrollViewDidScrollToTop(_ s: ZTronScrollState) { log.entries.append("d:didScrollToTop") }
    func scrollViewDidChangeAdjustedContentInset(_ s: ZTronScrollState) { log.entries.append("d:didChangeAdjustedContentInset") }
}

/// The 13 modifier boxes, each logging `<tag>:<name>` (the same spelling as `SeqDelegate`).
@MainActor
func recordingBoxes(_ log: SeqLog, tag: String = "m", allowsScrollToTop: Bool = true) -> [DelegateObserverBox] {
    func plain(_ kind: DelegateObserverBox.Kind, _ name: String) -> DelegateObserverBox {
        DelegateObserverBox(kind: kind, handler: .plain { _ in log.entries.append("\(tag):\(name)") })
    }
    return [
        plain(.didScroll, "didScroll"), plain(.didZoom, "didZoom"), plain(.willBeginDragging, "willBeginDragging"),
        DelegateObserverBox(kind: .willEndDragging, handler: .willEndDragging { _, _, _ in log.entries.append("\(tag):willEndDragging") }),
        DelegateObserverBox(kind: .didEndDragging, handler: .didEndDragging { _, d in log.entries.append("\(tag):didEndDragging(\(d))") }),
        plain(.willBeginDecelerating, "willBeginDecelerating"), plain(.didEndDecelerating, "didEndDecelerating"),
        plain(.didEndScrollingAnimation, "didEndScrollingAnimation"), plain(.willBeginZooming, "willBeginZooming"),
        DelegateObserverBox(kind: .didEndZooming, handler: .didEndZooming { _, scale in log.entries.append("\(tag):didEndZooming(\(scale))") }),
        DelegateObserverBox(kind: .shouldScrollToTop, handler: .shouldScrollToTop { _ in
            log.entries.append("\(tag):shouldScrollToTop"); return allowsScrollToTop
        }),
        plain(.didScrollToTop, "didScrollToTop"), plain(.didChangeAdjustedContentInset, "didChangeAdjustedContentInset"),
    ]
}

/// M8-8 (design M8-chrome §7b, SPEC S11 "Delegate callbacks as modifiers"): the modifiers fire at the delegate's call sites.
@MainActor
@Suite(.serialized)
struct DelegateModifierTests {
    private func sized(_ path: OSPath) -> (ZTronScrollState, SeqLog, SeqDelegate) {
        let s = makeState(path)
        let log = SeqLog(), d = SeqDelegate(log)
        s.delegate = d
        log.keep = d
        s.now = { 100.2 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        for b in recordingBoxes(log) { _ = s.observers.addDelegate(b) }
        log.entries.removeAll()
        return (s, log, d)
    }
    private func step(_ s: ZTronScrollState, _ t: TimeInterval) { s.step(to: Date(timeIntervalSinceReferenceDate: t)) }

    // MARK: Identical sequences at every site

    @Test(arguments: OSPath.allCases) func dragDecelerateIdleSequenceIsIdentical(path: OSPath) {
        let (s, log, _) = sized(path)
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
        let d = log.names("d")
        #expect(d.first == "willBeginDragging" && d.last == "didEndDecelerating", "log: \(d)")
        for name in ["didScroll", "willEndDragging", "didEndDragging(true)", "willBeginDecelerating", "didEndDecelerating"] {
            #expect(d.contains(name), "missing \(name): \(d)")
        }
        #expect(d == log.names("m"))
        #expect(log.isInterleaved, "log: \(log.entries)")
    }

    @Test(arguments: OSPath.allCases) func pinchBounceSequenceIsIdentical(path: OSPath) {
        let host = PinchPanTests()
        let r = host.make(path, limits: 1...2)
        let log = SeqLog()
        let delegate = SeqDelegate(log)
        r.state.delegate = delegate
        log.keep = delegate
        for b in recordingBoxes(log) { _ = r.state.observers.addDelegate(b) }
        let c = CGPoint(x: 100, y: 200)
        host.twoFingersDown(r, at: c)
        host.magnify(r, 3, at: c); r.tick()                     // past the limit
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        #expect(r.state.isZoomBouncing)
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        let d = log.names("d")
        #expect(d.contains("willBeginZooming") && d.contains("didZoom") && d.contains { $0.hasPrefix("didEndZooming") }, "log: \(d)")
        #expect(d == log.names("m"))
        #expect(log.isInterleaved, "log: \(log.entries)")
    }

    @Test(arguments: OSPath.allCases) func programmaticAnimationSequenceIsIdentical(path: OSPath) {
        let (s, log, _) = sized(path)
        s.setContentOffset(CGPoint(x: 0, y: 500), animated: true)
        var t = 100.2
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t) }
        let d = log.names("d")
        #expect(d.last == "didEndScrollingAnimation" && d.contains("didScroll"), "log: \(d)")
        #expect(d == log.names("m"))
        #expect(log.isInterleaved, "log: \(log.entries)")
    }

    @Test(arguments: OSPath.allCases) func scrollToTopSequenceIsIdentical(path: OSPath) {
        let (s, log, _) = sized(path)
        #expect(s.scrollToTop(animated: true))
        var t = 100.2
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t) }
        let d = log.names("d")
        #expect(d.first == "shouldScrollToTop" && d.last == "didScrollToTop", "log: \(d)")
        #expect(d.contains("didEndScrollingAnimation"))
        #expect(d == log.names("m"))
        #expect(log.isInterleaved, "log: \(log.entries)")
        #expect(abs(s.peek.presentationOffset.y + s.adjustedContentInset.top) < 0.5, "arrived at the top edge")
    }

    @Test(arguments: OSPath.allCases) func scrollToTopWithoutAnimationReportsAtOnce(path: OSPath) {
        let (s, log, _) = sized(path)
        #expect(s.scrollToTop(animated: false))
        #expect(log.names("d") == ["shouldScrollToTop", "didScroll", "didScrollToTop"], "log: \(log.entries)")
        #expect(log.names("d") == log.names("m"))
    }

    @Test(arguments: OSPath.allCases) func insetChangeSequenceIsIdentical(path: OSPath) {
        let (s, log, _) = sized(path)
        s.contentInset = EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0)
        let d = log.names("d")
        #expect(d.contains("didChangeAdjustedContentInset"), "log: \(log.entries)")
        #expect(d == log.names("m"))
        #expect(log.isInterleaved, "log: \(log.entries)")
    }

    // MARK: willEndDragging threading

    @Test(arguments: OSPath.allCases) func willEndDraggingThreadsTheTargetDelegateThenEachModifierAndTheLastWins(path: OSPath) {
        let (s, log, d) = sized(path)
        d.retarget = CGPoint(x: 0, y: 400)
        var seen: [CGFloat] = [], velocity: [CGPoint] = []
        _ = s.observers.addDelegate(DelegateObserverBox(kind: .willEndDragging, handler: .willEndDragging { _, v, target in
            seen.append(target.y); velocity.append(v); target.y = 420
        }))
        _ = s.observers.addDelegate(DelegateObserverBox(kind: .willEndDragging, handler: .willEndDragging { _, _, target in
            seen.append(target.y); target.y = 440
        }))
        s.beginTracking(); s.beginDragging()
        var tr = PointVelocityTracker()
        for i in 0...8 { tr.add(CGPoint(x: 0, y: -1000 * CGFloat(Double(i) * 0.015)), at: 100.2 - 0.12 + Double(i) * 0.015) }
        let (_, my) = s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100.2, fallbackVelocity: nil),
                                tracker: tr, env: PanPathEnv.base, settings: ReleaseSettings())
        // (`sized` registered a recording box first; it does not touch the target.) The probes follow the delegate.
        #expect(seen == [400, 420], "each modifier sees what the previous one left: \(seen)")
        #expect(abs(my.endPosition - 440) < 1e-6, "the last value is where the release lands: \(my.endPosition)")
        #expect((velocity.first?.y ?? 0) > 0.5 && (velocity.first?.y ?? 0) < 1.5, "pt/ms like the delegate: \(velocity)")
        #expect(velocity.first == d.seenVelocity, "the delegate and the modifier see the same velocity")
        _ = log
    }

    // MARK: shouldScrollToTop conjunction

    @Test(arguments: OSPath.allCases) func shouldScrollToTopIsTheConjunction(path: OSPath) {
        func run(delegate: Bool?, predicates: [Bool]) -> Bool {
            let s = makeState(path)
            s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
            let log = SeqLog(), d = SeqDelegate(log)
            if let delegate { d.allowsScrollToTop = delegate; s.delegate = d; log.keep = d }
            for p in predicates {
                _ = s.observers.addDelegate(DelegateObserverBox(kind: .shouldScrollToTop, handler: .shouldScrollToTop { _ in p }))
            }
            return s.notifyShouldScrollToTop()
        }
        #expect(run(delegate: nil, predicates: []), "true when nothing is set")
        #expect(run(delegate: true, predicates: [true, true]))
        #expect(!run(delegate: false, predicates: [true]), "the delegate's veto wins")
        #expect(!run(delegate: true, predicates: [true, false]), "any predicate's veto wins")
        #expect(!run(delegate: nil, predicates: [false]))
    }

    @Test(arguments: OSPath.allCases) func aVetoedScrollToTopMovesNothing(path: OSPath) {
        let (s, log, _) = sized(path)
        let veto = DelegateObserverBox(kind: .shouldScrollToTop, handler: .shouldScrollToTop { _ in false })
        _ = s.observers.addDelegate(veto)
        let before = s.peek.presentationOffset
        #expect(!s.scrollToTop(animated: false))
        #expect(s.peek.presentationOffset == before)
        #expect(!log.entries.contains("d:didScrollToTop") && !log.entries.contains("m:didScrollToTop"))
        #expect(log.names("d") == ["shouldScrollToTop"], "every predicate still ran: \(log.entries)")
    }

    // MARK: Registration order

    @Test(arguments: OSPath.allCases) func boxesRunInRegistrationOrderAndAppend(path: OSPath) {
        let s = makeState(path)
        let log = SeqLog()
        let boxes = (0..<3).map { i in
            DelegateObserverBox(kind: .didScroll, handler: .plain { _ in log.entries.append("box\(i)") })
        }
        s.observers.sync(boxes)
        s.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
        #expect(log.entries == ["box0", "box1", "box2"], "several modifiers of one kind all fire, in order: \(log.entries)")
        // A box that joins later takes its place in the container's order, not the end of the list.
        let late = DelegateObserverBox(kind: .didScroll, handler: .plain { _ in log.entries.append("late") })
        s.observers.sync([late, boxes[0], boxes[1], boxes[2]])
        log.entries.removeAll()
        s.track(offset: CGPoint(x: 0, y: 20), zoom: 1)
        #expect(log.entries == ["late", "box0", "box1", "box2"], "\(log.entries)")
        s.observers.sync([])
        log.entries.removeAll()
        s.track(offset: CGPoint(x: 0, y: 30), zoom: 1)
        #expect(log.entries.isEmpty, "removed on disappear")
    }

    // MARK: View level: member, twin, nesting, stale closure, counters

    private func hosted<V: View>(_ path: OSPath, _ view: V) -> UIWindow {
        let w = withOSPath(path) { host(view) }
        pump(0.2)
        return w
    }

    @Test(arguments: OSPath.allCases) func severalDidScrollMembersAllFireInApplicationOrder(path: OSPath) {
        let s = makeState(path)
        let log = SeqLog()
        let w = hosted(path, ZTronScrollView(.vertical, state: s) { CountedContent(counter: Counter()) }
            .onZTronScrollDidScroll { _ in log.entries.append("member1") }
            .onZTronScrollDidScroll { _ in log.entries.append("member2") }
            .onZTronScrollDidScroll { _ in log.entries.append("member3") })
        log.entries.removeAll()
        s.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
        #expect(log.entries == ["member1", "member2", "member3"], "members append, in application order: \(log.entries)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func environmentTwinsFireBeforeMembersOutermostFirst(path: OSPath) {
        struct Tree: View {
            let state: ZTronScrollState
            let log: SeqLog
            var body: some View {
                let scroll = ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onZTronScrollDidScroll { _ in log.entries.append("member") }
                // A View-typed hop: from here on only the twins apply.
                let view: AnyView = AnyView(scroll)
                return view
                    .onZTronScrollDidScroll { _ in log.entries.append("twin-inner") }
                    .onZTronScrollDidScroll { _ in log.entries.append("twin-outer") }
            }
        }
        let s = makeState(path)
        let log = SeqLog()
        let w = hosted(path, Tree(state: s, log: log))
        log.entries.removeAll()
        s.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
        #expect(log.entries == ["twin-outer", "twin-inner", "member"], "environment twins outermost first, then the members: \(log.entries)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aTwinAboveTwoNestedViewsFiresForBothAndAMemberForItsOwnOnly(path: OSPath) {
        struct Tree: View {
            let outer: ZTronScrollState, inner: ZTronScrollState
            let log: SeqLog
            var body: some View {
                ZTronScrollView(.vertical, state: outer) {
                    ZTronScrollView(.vertical, state: inner) { CountedContent(counter: Counter()) }
                        .onZTronScrollDidScroll { _ in log.entries.append("member-inner") }
                        .frame(height: 100)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)      // a View from here on: the next call is the twin
                .onZTronScrollDidScroll { _ in log.entries.append("twin") }
            }
        }
        let outer = makeState(path), inner = makeState(path)
        let log = SeqLog()
        let w = hosted(path, Tree(outer: outer, inner: inner, log: log))
        log.entries.removeAll()
        outer.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
        #expect(log.entries == ["twin"], "outer moved: \(log.entries)")
        log.entries.removeAll()
        inner.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
        #expect(Set(log.entries) == ["twin", "member-inner"] && log.entries.count == 2, "inner moved: \(log.entries)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aParentRebuildReplacesTheClosure(path: OSPath) {
        struct Parent: View {
            let state: ZTronScrollState
            @ObservedObject var model: ObsModel
            let seen: SeqLog
            var body: some View {
                ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onZTronScrollDidScroll { [label = model.label] _ in seen.entries.append("member-\(label)") }
                    .onZTronScrollDidEndDragging { [label = model.label] _, _ in seen.entries.append("end-\(label)") }
            }
        }
        struct TwinParent: View {
            let state: ZTronScrollState
            @ObservedObject var model: ObsModel
            let seen: SeqLog
            var body: some View {
                ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onZTronScrollDidScroll { [label = model.label] _ in seen.entries.append("twin-\(label)") }
            }
        }
        let s = makeState(path), model = ObsModel(), seen = SeqLog()
        let w = hosted(path, Parent(state: s, model: model, seen: seen))
        model.label = "b"; pump(0.2)
        s.track(offset: CGPoint(x: 0, y: 30), zoom: 1); pump(0.05)
        #expect(seen.entries.last == "member-b" && !seen.entries.contains("member-a"), "member: \(seen.entries)")
        unhost(w)
        let s2 = makeState(path), model2 = ObsModel(), seen2 = SeqLog()
        let w2 = hosted(path, TwinParent(state: s2, model: model2, seen: seen2))
        model2.label = "b"; pump(0.2)
        s2.track(offset: CGPoint(x: 0, y: 30), zoom: 1); pump(0.05)
        #expect(seen2.entries.last == "twin-b" && !seen2.entries.contains("twin-a"), "twin: \(seen2.entries)")
        unhost(w2)
    }

    @Test(arguments: OSPath.allCases) func allThirteenAttachedCostNoBodyEvaluationsWhileScrollingAndZooming(path: OSPath) {
        struct Tree: View {
            let state: ZTronScrollState
            let owner: Counter
            let content: Counter
            var body: some View {
                owner.runs += 1
                return ZTronScrollView(.vertical, state: state) { CountedContent(counter: content) }
                    .onZTronScrollDidScroll { _ in }
                    .onZTronScrollDidZoom { _ in }
                    .onZTronScrollWillBeginDragging { _ in }
                    .onZTronScrollWillEndDragging { _, _, _ in }
                    .onZTronScrollDidEndDragging { _, _ in }
                    .onZTronScrollWillBeginDecelerating { _ in }
                    .onZTronScrollDidEndDecelerating { _ in }
                    .onZTronScrollDidEndScrollingAnimation { _ in }
                    .onZTronScrollWillBeginZooming { _ in }
                    .onZTronScrollDidEndZooming { _, _ in }
                    .onZTronScrollShouldScrollToTop { _ in true }
                    .onZTronScrollDidScrollToTop { _ in }
                    .onZTronScrollDidChangeAdjustedContentInset { _ in }
            }
        }
        let s = makeState(path)
        var scrolls = 0
        let owner = Counter(), content = Counter()
        let w = hosted(path, Tree(state: s, owner: owner, content: content)
            .onZTronScrollDidScroll { _ in scrolls += 1 })
        let ownerBase = owner.runs, contentBase = content.runs
        for i in 0..<120 {
            s.track(offset: CGPoint(x: 0, y: CGFloat(i % 200)), zoom: 1 + CGFloat(i % 60) / 100)
            pump(0.004)
        }
        pump(0.1)
        #expect(scrolls > 50, "the callbacks did run: \(scrolls)")
        #expect(content.runs == contentBase, "content body ran \(content.runs - contentBase) times")
        #expect(owner.runs == ownerBase, "the modifier owner's body ran \(owner.runs - ownerBase) times")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func modifiersCompileAndAreInertOutsideAScrollView(path: OSPath) {
        let log = SeqLog()
        let w = hosted(path, Color.red.onZTronScrollDidScroll { _ in log.entries.append("never") }
            .onZTronScrollShouldScrollToTop { _ in false })
        #expect(log.entries.isEmpty)
        unhost(w)
    }
}
