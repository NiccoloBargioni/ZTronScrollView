import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class RefreshProbeBox {
    var specs: [RefresherDecl] = []
    var reach: [ReachEdgeDecl] = []
}

struct RefreshEnvironmentProbe: View {
    let box: RefreshProbeBox
    @Environment(\.ztronRefreshSpecs) private var specs
    @Environment(\.ztronReachEdges) private var reach
    var body: some View {
        box.specs = specs
        box.reach = reach
        return Color.clear
    }
}

private struct MyLoader: View {
    @Binding var state: ZTronRefreshState
    init(_ state: Binding<ZTronRefreshState>) { _state = state }
    var body: some View { Text("\(state.dragPosition)") }
}

/// M8b-2 (design M8b §1.2, test list item 2): the shapes the user guaranteed compile exactly as spelled and land on the
/// overload they should, the completion handler ends the refresh once from any thread, and the twins carry the same
/// declarations in the environment.
@MainActor
@Suite(.serialized)
struct RefreshAPITests {
    func load() async {}

    // MARK: the mandatory shapes (user, 2026-10-19)

    @Test func theDefaultLoaderShapeIsTheAsyncOverloadWithTheDefaultStyle() async {
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher { await load() }
        let decl = try! #require(v.config.refreshers.first)
        #expect(v.config.refreshers.count == 1)
        #expect(decl.spec.style == .default && !decl.spec.overlay && decl.spec.indicator == nil)
        #expect(decl.spec.configuration == .default && decl.edges == nil)
    }

    @Test func aTrailingClosureWithoutAwaitIsStillTheAsyncOverload() {
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher { print("sync body") }
        #expect(v.config.refreshers.count == 1 && v.config.refreshers[0].spec.indicator == nil)
    }

    @Test func theCompletionShapeIsPickedByArity() {
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher { done in done() }
        #expect(v.config.refreshers.count == 1 && v.config.refreshers[0].spec.style == .default)
    }

    @Test func theCustomViewShapeStoresAnIndicator() async {
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher(refreshView: { MyLoader($0) }) { await load() }
        let decl = try! #require(v.config.refreshers.first)
        #expect(decl.spec.indicator != nil && decl.spec.style == .default)
        let w: ZTronScrollView<Color> = ZTronScrollView { Color.clear }
            .refresher(refreshView: { state in Text("\(state.wrappedValue.dragPosition)") }, overlay: true) { done in done() }
        #expect(w.config.refreshers[0].spec.indicator != nil && w.config.refreshers[0].spec.overlay)
    }

    @Test func everyArgumentSpellingCompilesAndMembersChain() {
        let v: ZTronScrollView<Color> = ZTronScrollView([.vertical, .horizontal]) { Color.clear }
            .refresher(style: .system, overlay: true, configuration: .loadMore) { await load() }
            .refresher(style: .default, configuration: ZTronRefreshConfiguration(triggerDistance: 80)) { done in done() }
            .refresher(edges: [.top, .bottom]) { edge in _ = edge }
            .scrollTargetBehavior(.paging)
            .zoomRange(min: .absolute(1), max: .absolute(3))
        #expect(v.config.refreshers.count == 3)
        #expect(v.config.refreshers[2].edges == [.top, .bottom])
        #expect(v.config.behavior != nil)
    }

    @Test func noHeaderRefreshEntryPointExists() {
        // The scaling header has no refresh API of its own (amendment 2026-10-19): the symbols are not there.
        #if canImport(ZTronScrollViewHeaderRefreshSymbols)
        #error("pullToRefresh must not exist")
        #endif
        let mirror = Mirror(reflecting: ZTronScrollView { Color.clear })
        #expect(!mirror.children.contains { $0.label == "pullToRefresh" })
    }

    // MARK: the completion handler

    @Test func theCompletionHandlerEndsTheActionOnceFromAnyThread() async {
        final class Calls: @unchecked Sendable { var n = 0 }
        let calls = Calls()
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher { done in
            calls.n += 1
            DispatchQueue.global().async { done(); done() }
            DispatchQueue.global().async { done() }
        }
        await v.config.refreshers[0].spec.action(.top)     // returns only after `done` resumed the continuation
        #expect(calls.n == 1)
    }

    @Test func aCompletionHandlerCalledSynchronouslyEndsTheActionToo() async {
        let v: ZTronScrollView<Color> = ZTronScrollView { Color.clear }.refresher { done in done() }
        await v.config.refreshers[0].spec.action(.top)
    }

    // MARK: the twins

    @Test func twinsWriteTheEnvironmentAndTheInnerOneComesLater() {
        let box = RefreshProbeBox()
        let w = host(RefreshEnvironmentProbe(box: box)
            .ztronRefresher(style: .system) { await load() }
            .ztronRefresher(refreshView: { MyLoader($0) }, overlay: true) { done in done() }
            .ztronRefresher(edges: .bottom, configuration: .loadMore) { _ in }
            .ztronRefresher(style: .default) { done in done() })
        // Modifiers apply from the inside out: the probe sees the innermost call first in the list.
        #expect(box.specs.count == 4)
        #expect(box.specs[0].spec.style == .default && box.specs[0].spec.indicator == nil)
        #expect(box.specs[1].edges == .bottom)
        #expect(box.specs[2].spec.indicator != nil && box.specs[2].spec.overlay)
        #expect(box.specs[3].spec.style == .system)
        unhost(w)
    }

    @Test func aViewWithoutTwinsSeesNothing() {
        let box = RefreshProbeBox()
        let w = host(RefreshEnvironmentProbe(box: box))
        #expect(box.specs.isEmpty && box.reach.isEmpty)
        unhost(w)
    }

    @Test func reachEdgeTwinsWriteTheEnvironment() {
        let box = RefreshProbeBox()
        let w = host(RefreshEnvironmentProbe(box: box)
            .onZTronScrollReachEdge(.bottom, threshold: 200) {}
            .onZTronScrollReachEdge(.top) {})
        #expect(box.reach.map(\.edge) == [.top, .bottom] && box.reach.map(\.threshold) == [0, 200])
        unhost(w)
    }
}
