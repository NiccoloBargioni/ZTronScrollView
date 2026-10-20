import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class ObsModel: ObservableObject { @Published var label = "a" }

struct CountedContent: View {
    let counter: Counter
    var body: some View {
        counter.runs += 1
        return VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Color.blue.frame(height: 100) } }
    }
}

/// M7 session 1, view level (design §7 T3, T4, T12 and the Q4 compile test): the member and the twin on hosted trees.
@MainActor
@Suite(.serialized)
struct ObservationModifierTests {
    private func hosted<V: View>(_ path: OSPath, _ view: V) -> UIWindow {
        let w = withOSPath(path) { host(view) }
        pump(0.2)
        return w
    }

    // MARK: T3

    @Test(arguments: OSPath.allCases) func observersAttachedAddNoContentBodiesWhileScrollingAndZooming(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        var geometry = 0, visibility: [Bool] = [], phases = 0
        let w = hosted(path, ZTronScrollView(.vertical, state: s) { CountedContent(counter: c).onZTronScrollVisibilityChange { visibility.append($0) } }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, _ in geometry += 1 }))
        _ = s.observers.addPhase(PhaseObserverBox { _, _, _ in phases += 1 })
        let base = c.runs
        let initialGeometry = geometry
        #if DEBUG
        let deliveries = s.observers.deliveries
        #endif
        for i in 0..<120 {
            s.track(offset: CGPoint(x: 0, y: CGFloat(i % 200)), zoom: 1 + CGFloat(i % 60) / 100)
            pump(0.004)
        }
        pump(0.1)
        #expect(c.runs == base, "content body ran \(c.runs - base) times while scrolling")
        #expect(geometry > initialGeometry)
        #if DEBUG
        #expect(s.observers.deliveries > deliveries)
        #endif
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theModifierBodiesRunOnlyWithTheirParent(path: OSPath) {
        struct Parent: View {
            let state: ZTronScrollState
            @ObservedObject var model: ObsModel
            let counter: Counter
            var body: some View {
                counter.values.append(model.label)
                return ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, _ in })
            }
        }
        let s = makeState(path)
        let model = ObsModel(), c = Counter()
        let w = hosted(path, Parent(state: s, model: model, counter: c))
        let parentRuns = c.values.count
        for i in 0..<60 { s.track(offset: CGPoint(x: 0, y: CGFloat(i)), zoom: 1); pump(0.004) }
        #expect(c.values.count == parentRuns, "the parent rebuilt while scrolling")
        unhost(w)
    }

    // MARK: T4

    @Test(arguments: OSPath.allCases) func aParentRebuildReplacesTheMemberActionClosure(path: OSPath) {
        struct Parent: View {
            let state: ZTronScrollState
            @ObservedObject var model: ObsModel
            let seen: Counter
            var body: some View {
                ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { [label = model.label] _, new in
                        seen.values.append("\(label)\(Int(new))")
                    })
            }
        }
        let s = makeState(path)
        let model = ObsModel(), seen = Counter()
        let w = hosted(path, Parent(state: s, model: model, seen: seen))
        // The registration reports (v, v) of the settled state (under the safe area: -62, not 0).
        let first = seen.values
        #expect(first == ["a\(Int(s.peek.presentationOffset.y))"], "initial call once: \(first)")
        model.label = "b"; pump(0.2)
        #expect(seen.values == first, "a rebuild is not a re-seed: \(seen.values)")
        s.track(offset: CGPoint(x: 0, y: 30), zoom: 1); pump(0.05)
        #expect(seen.values.last == "b30", "the new closure ran: \(seen.values)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aParentRebuildReplacesTheTwinActionClosure(path: OSPath) {
        struct Parent: View {
            let state: ZTronScrollState
            @ObservedObject var model: ObsModel
            let seen: Counter
            var body: some View {
                ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                    .onZTronScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { [label = model.label] _, new in
                        seen.values.append("\(label)\(Int(new))")
                    })
            }
        }
        let s = makeState(path)
        let model = ObsModel(), seen = Counter()
        let w = hosted(path, Parent(state: s, model: model, seen: seen))
        let first = seen.values
        #expect(first == ["a\(Int(s.peek.presentationOffset.y))"], "initial call once: \(first)")
        model.label = "b"; pump(0.2)
        #expect(seen.values == first, "a rebuild is not a re-seed: \(seen.values)")
        s.track(offset: CGPoint(x: 0, y: 30), zoom: 1); pump(0.05)
        #expect(seen.values.last == "b30", "the new closure ran: \(seen.values)")
        #expect(seen.values.count == first.count + 1, "seeded once: \(seen.values)")
        unhost(w)
    }

    // MARK: Visibility modifier

    @Test(arguments: OSPath.allCases) func contentVisibilityReportsPerItemAndFollowsScrolling(path: OSPath) {
        let s = makeState(path)
        let log = Counter()
        let w = hosted(path, ZTronScrollView(.vertical, state: s) {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    Color.blue.frame(height: 100).onZTronScrollVisibilityChange(threshold: 0.5) { log.values.append("\(i):\($0)") }
                }
            }
        })
        // The viewport spans the safe area: at rest the visible rect is -62...138, so item 1 shows 38 %.
        #expect(Set(log.values) == ["0:true", "1:false", "2:false", "3:false"], "initial: \(log.values)")
        log.values.removeAll()
        s.track(offset: CGPoint(x: 0, y: 150), zoom: 1); pump(0.1)      // 150...350
        #expect(Set(log.values) == ["0:false", "1:true", "2:true", "3:true"], "scrolled: \(log.values)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func contentVisibilityStopsWhenTheViewDisappears(path: OSPath) {
        struct Gate: View {
            @ObservedObject var model: ObsGate
            let state: ZTronScrollState
            let log: Counter
            var body: some View {
                ZTronScrollView(.vertical, state: state) {
                    VStack(spacing: 0) {
                        if model.shown { Color.blue.frame(height: 100).onZTronScrollVisibilityChange { log.values.append("\($0)") } }
                        Color.red.frame(height: 400)
                    }
                }
            }
        }
        let s = makeState(path)
        let model = ObsGate(), log = Counter()
        let w = hosted(path, Gate(model: model, state: s, log: log))
        #expect(log.values == ["true"])
        model.shown = false; pump(0.2)
        s.track(offset: CGPoint(x: 0, y: 150), zoom: 1); pump(0.1)
        #expect(log.values == ["true"], "removed with the view: \(log.values)")
        unhost(w)
    }

    // MARK: T12

    @Test(arguments: OSPath.allCases) func twinsOutsideAScrollViewAreHarmless(path: OSPath) {
        var geometryCalls = 0
        let w = hosted(path, Color.red.frame(width: 100, height: 100)
            .onZTronScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, _ in geometryCalls += 1 })
            .onZTronScrollVisibilityChange { _ in })      // iOS 18+ applies SwiftUI's own (it may report a state; not ours to judge)
        pump(0.1)
        #expect(geometryCalls == 0)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aTwinAboveNestedScrollViewsObservesBoth(path: OSPath) {
        let outer = makeState(path), inner = makeState(path)
        var calls: [String] = []
        let w = hosted(path, ZTronScrollView(.vertical, state: outer) {
            VStack(spacing: 0) {
                Color.green.frame(height: 100)
                ZTronScrollView(.horizontal, state: inner) {
                    HStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Color.orange.frame(width: 100, height: 100) } }
                }
                .frame(height: 100)
                Color.green.frame(height: 400)
            }
        }
        .onZTronScrollGeometryChange(for: CGFloat.self, of: { $0.zoomScale }, action: { _, new in calls.append("z\(new)") }))
        pump(0.2)
        #expect(calls.count == 2, "each scroll view seeds its own box: \(calls)")
        #expect(!outer.observers.isEmpty && !inner.observers.isEmpty)
        outer.track(offset: .zero, zoom: 2)
        inner.track(offset: .zero, zoom: 3)
        #expect(calls.count == 4, "\(calls)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theBoxesLeaveWithTheView(path: OSPath) {
        struct Gate: View {
            @ObservedObject var model: ObsGate
            let state: ZTronScrollState
            var body: some View {
                if model.shown {
                    ZTronScrollView(.vertical, state: state) { CountedContent(counter: Counter()) }
                        .onZTronScrollGeometryChange(for: CGFloat.self, of: { $0.zoomScale }, action: { _, _ in })
                } else {
                    Color.clear
                }
            }
        }
        let s = makeState(path)
        let model = ObsGate()
        let w = hosted(path, Gate(model: model, state: s))
        #expect(!s.observers.isEmpty)
        model.shown = false; pump(0.2)
        #expect(s.observers.isEmpty)
        unhost(w)
    }

    // MARK: Q4 (compile test): the member and SwiftUI's 18+ View extension in one chain

    @Test(arguments: OSPath.allCases) func unprefixedMembersAndTheNativeExtensionShareAChain(path: OSPath) {
        let s = makeState(path)
        var memberCalls = 0
        let w = hosted(path, ZTronScrollView(.vertical, state: s) { CountedContent(counter: Counter()) }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, _ in memberCalls += 1 })
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }, action: { _, _ in memberCalls += 1 }))
        #expect(memberCalls == 2, "both unannotated spellings bound to the ZTronScrollView member")
        unhost(w)
    }

    // MARK: Q1 side by side (design resolutions): the initial call of a native ScrollView vs ours

    @available(iOS 18, *)
    @Test func theInitialCallIsAValueValueCallLikeNative() {
        var native: [String] = []
        let nativeWindow = host(ScrollView { VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Color.blue.frame(height: 100) } } }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { old, new in native.append("\(old)->\(new)") }))
        pump(0.3)
        unhost(nativeWindow)
        var ours: [String] = []
        let s = makeState(.preferred)
        let w = host(ZTronScrollView(.vertical, state: s) { VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Color.blue.frame(height: 100) } } }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { old, new in ours.append("\(old)->\(new)") }))
        pump(0.3)
        unhost(w)
        // Measured on 27.0: native ["0.0->0.0", "0.0->-62.0"]: (v, v) at registration, before the safe area lands, then the
        // settled value as a change. Ours registers after the viewport commit and reports the settled (v, v) once; both end on
        // the same value (documented in the parity matrix).
        let parts = { (e: String) in e.components(separatedBy: "->") }
        #expect(native.first.map { Set(parts($0)).count == 1 } == true, "native initial call is (v, v): \(native)")
        #expect(ours.first.map { Set(parts($0)).count == 1 } == true, "initial call is (v, v): \(ours)")
        #expect(ours.last.map(parts)?.last == native.last.map(parts)?.last, "same settled value: native \(native) vs ours \(ours)")
    }
}

@MainActor
final class ObsGate: ObservableObject { @Published var shown = true }
