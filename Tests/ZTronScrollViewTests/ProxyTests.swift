import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class ProxyBox {
    var proxy: ZTronScrollViewProxy?
    var inner: ZTronScrollViewProxy?
}

/// A column of 100 pt items with `ztronScrollID`s; `ids[i]` is the id of item `i`.
struct IDColumn: View {
    let state: ZTronScrollState
    let ids: [String]
    var body: some View {
        ZTronScrollView(.vertical, state: state) {
            VStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in Color.gray.frame(height: 100).ztronScrollID(id) }
            }
        }
        .frame(height: 100)
    }
}

func columnIDs(_ prefix: String, count: Int = 10, shared: [Int: String] = [:]) -> [String] {
    (0..<count).map { shared[$0] ?? "\(prefix)\($0)" }
}

/// Two `ZTronScrollView`s (100 pt tall each) inside one reader. Item 3 of the first and item 5 of the second are "shared".
struct TwoScrollers: View {
    let a: ZTronScrollState
    let b: ZTronScrollState
    let box: ProxyBox
    var body: some View {
        ZTronScrollViewReader { proxy in
            VStack(spacing: 0) {
                IDColumn(state: a, ids: columnIDs("a", shared: [3: "shared"]))
                IDColumn(state: b, ids: columnIDs("b", shared: [5: "shared"]))
            }
            .onAppear { box.proxy = proxy }
        }
    }
}

/// An outer reader around a scroll view and an inner reader around another; both hold an "x".
struct NestedReaders: View {
    let outerMember: ZTronScrollState
    let innerMember: ZTronScrollState
    let box: ProxyBox
    var body: some View {
        ZTronScrollViewReader { outer in
            VStack(spacing: 0) {
                IDColumn(state: outerMember, ids: columnIDs("o", shared: [3: "x"]))
                ZTronScrollViewReader { inner in
                    IDColumn(state: innerMember, ids: columnIDs("i", shared: [5: "x"]))
                        .onAppear { box.inner = inner }
                }
            }
            .onAppear { box.proxy = outer }
        }
    }
}

@available(iOS 17, *)
struct NativeBelowReader: View {
    let state: ZTronScrollState
    let box: ProxyBox
    let position: Binding<Int?>
    var body: some View {
        ZTronScrollViewReader { proxy in
            VStack(spacing: 0) {
                IDColumn(state: state, ids: columnIDs("z"))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<30, id: \.self) { Color.gray.frame(height: 100).id($0) }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: position)
                .frame(height: 100)
            }
            .onAppear { box.proxy = proxy }
        }
    }
}

@MainActor
final class PositionBox { var value: Int? }

@MainActor
@Suite(.serialized)
struct ProxyTests {
    // MARK: scope (no views)

    @Test(arguments: OSPath.allCases) func scopeSearchesOwnMembersInAppearOrderThenNestedScopes(path: OSPath) {
        let first = makeState(path), second = makeState(path), nested = makeState(path)
        let outer = ProxyScope(), inner = ProxyScope()
        first.targets.register("only-first", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        second.targets.register("only-second", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        first.targets.register("both", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        second.targets.register("both", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        nested.targets.register("both", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        nested.targets.register("only-nested", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        outer.attach(first); outer.attach(second); outer.attach(first)          // attaching twice is a no-op
        inner.attach(nested)
        #expect(outer.members.count == 2)
        #expect(outer.owner(of: "only-second") === second)
        #expect(outer.owner(of: "both") === first)
        #expect(outer.owner(of: "only-nested") == nil)
        outer.attach(child: inner)
        #expect(outer.owner(of: "only-nested") === nested)                        // outer reaches the nested scope
        #expect(outer.owner(of: "both") === first)                                // own members before nested ones
        #expect(inner.owner(of: "both") === nested && inner.owner(of: "only-first") == nil)
        outer.detach(first)
        #expect(outer.owner(of: "both") === second)
        outer.detach(child: inner)
        #expect(outer.owner(of: "only-nested") == nil)
    }

    @Test(arguments: OSPath.allCases) func scopeForgetsReleasedChildren(path: OSPath) {
        let outer = ProxyScope()
        do {
            let inner = ProxyScope()
            let member = makeState(path)
            member.targets.register("gone", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            inner.attach(member)
            outer.attach(child: inner)
            #expect(outer.owner(of: "gone") === member)
        }
        #expect(outer.owner(of: "gone") == nil)
    }

    // MARK: hosted

    /// The hosting window has a top safe area; the states under test ignore it so the offsets read plainly.
    private func plain(_ path: OSPath) -> ZTronScrollState {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        return s
    }

    private func hostedPair(_ path: OSPath) -> (ZTronScrollState, ZTronScrollState, ProxyBox, UIWindow) {
        let a = plain(path), b = plain(path), box = ProxyBox()
        let w = withOSPath(path) { host(TwoScrollers(a: a, b: b, box: box)) }
        pump(0.3)
        return (a, b, box, w)
    }

    @Test(arguments: OSPath.allCases) func anIDOnlyInTheSecondScrollViewScrollsTheSecond(path: OSPath) {
        let (a, b, box, w) = hostedPair(path)
        #expect(a.targets.frame(of: "shared") == CGRect(x: 0, y: 300, width: 200, height: 100))
        #expect(b.targets.frame(of: "shared") == CGRect(x: 0, y: 500, width: 200, height: 100))
        box.proxy?.scrollTo("b7", anchor: .top)
        pump(0.3)
        #expect(b.contentOffset == CGPoint(x: 0, y: 700))
        #expect(a.contentOffset == .zero)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func anIDInBothScrollsTheFirstToAppear(path: OSPath) {
        let (a, _, box, w) = hostedPair(path)
        // "First" is first in appear order (design M6 §5), which SwiftUI does not promise to be tree order: ask the scope.
        guard let members = box.proxy?.scope.members, members.count == 2 else { Issue.record("both scroll views join the scope"); return }
        box.proxy?.scrollTo("shared", anchor: .top)
        pump(0.3)
        let expectFirst = members[0] === a ? CGPoint(x: 0, y: 300) : CGPoint(x: 0, y: 500)
        #expect(members[0].contentOffset == expectFirst)
        #expect(members[1].contentOffset == .zero)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func anUnknownIDGoesToTheNativeProxyAndMovesNothingOfOurs(path: OSPath) {
        let (a, b, box, w) = hostedPair(path)
        ZTronRenderCounters.reset()
        box.proxy?.scrollTo("nowhere", anchor: .center)
        pump(0.2)
        #expect(ZTronRenderCounters.value("proxy.native") == 1)
        #expect(a.contentOffset == .zero && b.contentOffset == .zero)
        box.proxy?.scrollTo("a2", anchor: .top)                                   // a known id never reaches the native proxy
        pump(0.2)
        #expect(ZTronRenderCounters.value("proxy.native") == 1 && a.contentOffset == CGPoint(x: 0, y: 200))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theAnimationOverloadReachesTheOwner(path: OSPath) {
        let (a, b, box, w) = hostedPair(path)
        box.proxy?.scrollTo("b2", anchor: .top, animation: nil)
        pump(0.2)
        #expect(b.contentOffset == CGPoint(x: 0, y: 200) && b.phase == .idle)
        box.proxy?.scrollTo("b8", anchor: .top, animation: .uikit)
        #expect(b.phase == .animating && b.isScrollAnimating && b.activeTransactionToken == nil)
        pump(1.5)
        #expect(abs(b.contentOffset.y - 800) < 0.5 && b.phase == .idle)
        box.proxy?.scrollTo("b1", anchor: .top, animation: .swiftUI(.linear(duration: 0.3)))
        #expect(b.activeTransactionToken != nil)
        pump(1.0)
        #expect(b.contentOffset == CGPoint(x: 0, y: 100) && a.contentOffset == .zero)
        withAnimation(.linear(duration: 0.3)) { box.proxy?.scrollTo("b6", anchor: .top) }      // ambient
        #expect(b.activeTransactionToken != nil)
        pump(1.0)
        #expect(b.contentOffset == CGPoint(x: 0, y: 600))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func nestedScopesSearchOuterToInner(path: OSPath) {
        let outerMember = plain(path), innerMember = plain(path), box = ProxyBox()
        let w = withOSPath(path) { host(NestedReaders(outerMember: outerMember, innerMember: innerMember, box: box)) }
        pump(0.3)
        ZTronRenderCounters.reset()
        // The outer proxy: its own scroll view first ("x" at 300), and it also reaches the nested one.
        box.proxy?.scrollTo("x", anchor: .top)
        pump(0.2)
        #expect(outerMember.contentOffset == CGPoint(x: 0, y: 300) && innerMember.contentOffset == .zero)
        box.proxy?.scrollTo("i7", anchor: .top)
        pump(0.2)
        #expect(innerMember.contentOffset == CGPoint(x: 0, y: 700))
        // The inner proxy only knows its own scope: "x" is its own (at 500), "o4" belongs to the outer scope.
        box.inner?.scrollTo("x", anchor: .top)
        pump(0.2)
        #expect(innerMember.contentOffset == CGPoint(x: 0, y: 500))
        #expect(ZTronRenderCounters.value("proxy.native") == 0)
        box.inner?.scrollTo("o4", anchor: .top)
        pump(0.2)
        #expect(ZTronRenderCounters.value("proxy.native") == 1 && outerMember.contentOffset == CGPoint(x: 0, y: 300))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theScopeFollowsTheViewsLifetime(path: OSPath) {
        final class Flag: ObservableObject { @Published var shown = true }
        struct Host: View {
            let state: ZTronScrollState
            let box: ProxyBox
            @ObservedObject var flag: Flag
            var body: some View {
                ZTronScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        if flag.shown { IDColumn(state: state, ids: columnIDs("s")) }
                        Color.clear
                    }
                    .onAppear { box.proxy = proxy }
                }
            }
        }
        let s = plain(path), box = ProxyBox(), flag = Flag()
        let w = withOSPath(path) { host(Host(state: s, box: box, flag: flag)) }
        pump(0.3)
        box.proxy?.scrollTo("s4", anchor: .top)
        pump(0.2)
        #expect(s.contentOffset.y == 400)
        flag.shown = false
        pump(0.3)
        ZTronRenderCounters.reset()
        box.proxy?.scrollTo("s6", anchor: .top)                                   // the scroll view left: only the native proxy is left
        pump(0.2)
        #expect(ZTronRenderCounters.value("proxy.native") == 1 && s.contentOffset.y == 400)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func nativeScrollViewsInsideTheReaderGetTheIDsWeDoNotKnow(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        let s = plain(path), box = ProxyBox(), position = PositionBox()
        let binding = Binding<Int?>(get: { position.value }, set: { position.value = $0 })
        let w = withOSPath(path) { host(NativeBelowReader(state: s, box: box, position: binding)) }
        pump(0.4)
        guard let native = firstScrollView(in: w.rootViewController!.view) else { Issue.record("no UIScrollView for the native ScrollView"); return }
        let before = native.contentOffset.y
        let ours = s.contentOffset
        ZTronRenderCounters.reset()
        box.proxy?.scrollTo(20, anchor: .top)                                     // an Int id: ours are Strings, so SwiftUI's own proxy scrolls
        pump(0.8)
        #expect(ZTronRenderCounters.value("proxy.native") == 1)
        #expect(s.contentOffset == ours)
        #expect(native.contentOffset.y > before + 1000, "the native ScrollView scrolled: \(before) -> \(native.contentOffset.y)")
        unhost(w)
    }
}
