import SwiftUI
import Testing
@testable import ZTronScrollView

/// M8b-2 (design M8b §1.2, test list item 2): which refresher answers which edge.
@MainActor
@Suite(.serialized)
struct RefreshResolverTests {
    func decl(_ tag: String, edges: Edge.Set? = nil, style: ZTronRefreshStyle = .default,
              configuration: ZTronRefreshConfiguration = .default) -> RefresherDecl {
        .async(edges: edges, style: style, overlay: false, configuration: configuration, action: { _ in Log.add(tag) })
    }

    /// Which tag a resolved spec runs.
    func tag(_ spec: RefresherSpec?) async -> String? {
        guard let spec else { return nil }
        Log.reset()
        await spec.action(.top)
        return Log.entries.last
    }

    @MainActor enum Log {
        static var entries: [String] = []
        static func add(_ t: String) { entries.append(t) }
        static func reset() { entries = [] }
    }

    let refreshable: @MainActor () async -> Void = { RefreshResolverTests.Log.add("refreshable") }

    @Test func theMemberBeatsTheTwinBeatsRefreshable() async {
        let r = RefreshResolver.resolve(member: [decl("member")], twin: [decl("twin")], refreshable: refreshable, axes: .vertical)
        #expect(Set(r.keys) == [.top])
        let got_member = await tag(r[.top])
        #expect(got_member == "member")
        let t = RefreshResolver.resolve(member: [], twin: [decl("twin")], refreshable: refreshable, axes: .vertical)
        let got_twin = await tag(t[.top])
        #expect(got_twin == "twin")
        let f = RefreshResolver.resolve(member: [], twin: [], refreshable: refreshable, axes: .vertical)
        let got_refreshable = await tag(f[.top])
        #expect(got_refreshable == "refreshable")
        #expect(RefreshResolver.resolve(member: [], twin: [], refreshable: nil, axes: .vertical).isEmpty)
    }

    @Test func refreshableIsTheSystemStyleOnTheStartEdgeWithTheDefaultConfiguration() {
        let r = RefreshResolver.resolve(member: [], twin: [], refreshable: refreshable, axes: .vertical)
        let spec = r[.top]!
        #expect(spec.style == .system && !spec.overlay && spec.configuration == .default && spec.indicator == nil)
    }

    @Test func precedenceIsPerEdge() async {
        // The member names the bottom only: `.refreshable` still answers the top.
        let r = RefreshResolver.resolve(member: [decl("more", configuration: .loadMore)], twin: [], refreshable: refreshable,
                                        axes: .vertical)
        #expect(Set(r.keys) == [.top, .bottom])
        let (top, bottom) = (await tag(r[.top]), await tag(r[.bottom]))
        #expect(top == "refreshable" && bottom == "more")
    }

    @Test func aLaterRefresherReplacesTheEdgesItNamesNeverAccumulates() async {
        let r = RefreshResolver.resolve(member: [decl("first"), decl("second"), decl("bottom", edges: .bottom)], twin: [],
                                        refreshable: nil, axes: .vertical)
        #expect(Set(r.keys) == [.top, .bottom])
        let (top, bottom) = (await tag(r[.top]), await tag(r[.bottom]))
        #expect(top == "second" && bottom == "bottom")
        // The same inside the twin layer: the inner (later) call wins.
        let t = RefreshResolver.resolve(member: [], twin: [decl("outer"), decl("inner")], refreshable: nil, axes: .vertical)
        let got_inner = await tag(t[.top])
        #expect(got_inner == "inner")
    }

    @Test func theStartEdgeFollowsThePrimaryAxis() {
        #expect(RefreshResolver.startEdge(.vertical) == .top)
        #expect(RefreshResolver.startEdge(.horizontal) == .leading)
        #expect(RefreshResolver.startEdge([.horizontal, .vertical]) == .top)
        let h = RefreshResolver.resolve(member: [decl("m")], twin: [], refreshable: refreshable, axes: .horizontal)
        #expect(Set(h.keys) == [.leading], "the member answers the start edge, which also takes .refreshable's place")
        let both = RefreshResolver.resolve(member: [decl("m")], twin: [], refreshable: nil, axes: [.horizontal, .vertical])
        #expect(Set(both.keys) == [.top])
    }

    @Test func allowedEdgesAndExplicitEdgesNarrowToTheScrolledAxes() {
        let loadMore = RefreshResolver.resolve(member: [decl("m", configuration: .loadMore)], twin: [], refreshable: nil, axes: .vertical)
        #expect(Set(loadMore.keys) == [.bottom])
        let none = RefreshResolver.resolve(member: [decl("m", configuration: .loadMore)], twin: [], refreshable: nil, axes: .horizontal)
        #expect(none.isEmpty, "a bottom refresher on a horizontal-only view has no pull to measure")
        let explicit = RefreshResolver.resolve(member: [decl("m", edges: [.top, .leading, .trailing],
                                                             configuration: ZTronRefreshConfiguration(allowedEdges: [.bottom]))],
                                               twin: [], refreshable: nil, axes: [.horizontal, .vertical])
        #expect(Set(explicit.keys) == [.top, .leading, .trailing], "explicit edges beat the configuration's allowedEdges")
        let cfg = ZTronRefreshConfiguration(allowedEdges: [.top, .bottom])
        let two = RefreshResolver.resolve(member: [decl("m", configuration: cfg)], twin: [], refreshable: nil, axes: .vertical)
        #expect(Set(two.keys) == [.top, .bottom])
    }

    @Test func signaturesCompareValuesNotClosures() {
        let a = RefreshResolver.resolve(member: [decl("a")], twin: [], refreshable: nil, axes: .vertical)
        let b = RefreshResolver.resolve(member: [decl("b")], twin: [], refreshable: nil, axes: .vertical)
        #expect(RefreshResolver.signature(a) == RefreshResolver.signature(b))
        let c = RefreshResolver.resolve(member: [decl("c", style: .system)], twin: [], refreshable: nil, axes: .vertical)
        #expect(RefreshResolver.signature(a) != RefreshResolver.signature(c))
    }
}
