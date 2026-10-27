import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M8b-2 (design M8b §1.3, test list item 5): indicator placement for the three looks on the four edges, then the hosted
/// wiring: the container hook installs the coordinator, begin / end draw the indicator without running a content body,
/// the accessibility action starts the refresh once, and the reach-edge twins register watchers.
@MainActor
@Suite(.serialized)
struct RefreshIndicatorTests {
    let viewport = CGSize(width: 400, height: 800)
    let base = EdgeInsets(top: 50, leading: 0, bottom: 34, trailing: 0)

    func place(_ edge: Edge, _ style: ZTronRefreshStyle = .system, overlay: Bool = false, refreshing: Bool = false,
               drag: CGFloat = 0.3, pull: CGFloat = 30, header: CGFloat = 0) -> RefreshPlacement? {
        RefreshIndicatorMath.placement(edge: edge, style: style, overlay: overlay, refreshing: refreshing, dragPosition: drag,
                                       pull: pull, length: 60, viewport: viewport, base: base, header: header)
    }

    // MARK: placement

    @Test func systemIsCentredInTheGapOnEveryEdge() {
        let top = place(.top)!
        #expect(top.frame == CGRect(x: 0, y: 35, width: 400, height: 60))
        #expect(top.clip == CGRect(x: 0, y: 50, width: 400, height: 30) && top.opacity == 0.3)
        let bottom = place(.bottom)!
        #expect(bottom.frame == CGRect(x: 0, y: 721, width: 400, height: 60))
        #expect(bottom.clip == CGRect(x: 0, y: 736, width: 400, height: 30))
        let leading = place(.leading)!
        #expect(leading.frame == CGRect(x: -15, y: 50, width: 60, height: 716))
        #expect(leading.clip == CGRect(x: 0, y: 50, width: 30, height: 716))
        let trailing = place(.trailing)!
        #expect(trailing.frame == CGRect(x: 355, y: 50, width: 60, height: 716))
        #expect(trailing.clip == CGRect(x: 370, y: 50, width: 30, height: 716))
    }

    @Test func defaultIsGluedToTheContentEdgeAndFollowsThePull() {
        let top = place(.top, .default)!
        #expect(top.frame == CGRect(x: 0, y: 20, width: 400, height: 60), "its far edge is the content's edge: base + pull")
        #expect(top.clip == CGRect(x: 0, y: 50, width: 400, height: 30) && top.opacity == 1)
        let far = place(.top, .default, pull: 150)!
        #expect(far.frame.maxY == 50 + 150 && far.clip.maxY == 200)
        let bottom = place(.bottom, .default)!
        #expect(bottom.frame.minY == 766 - 30 && bottom.clip.minY == 736)
        #expect(place(.leading, .default)!.frame.maxX == 30 && place(.trailing, .default)!.frame.minX == 370)
    }

    @Test func overlayFloatsOverTheContentAndSitsAtTheIndicatorHeightWhileRefreshing() {
        let pulling = place(.top, .system, overlay: true)!
        #expect(pulling.frame == CGRect(x: 0, y: 20, width: 400, height: 60), "centre at min(pull, L) − L/2 from the base")
        #expect(pulling.clip.minY == 50 && pulling.clip.maxY == 800 - 0, "clipped at the base only, not to the gap")
        #expect(pulling.opacity == 0.5)
        let refreshing = place(.top, .default, overlay: true, refreshing: true, drag: 1, pull: 0)!
        #expect(refreshing.frame == CGRect(x: 0, y: 50, width: 400, height: 60) && refreshing.opacity == 1)
        let rest = place(.top, .default, overlay: true, pull: 0)
        #expect(rest == nil, "an overlay at rest is outside its base")
        let bottom = place(.bottom, .system, overlay: true, refreshing: true)!
        #expect(bottom.frame == CGRect(x: 0, y: 706, width: 400, height: 60))
        // Open item 18: a base beyond the viewport (a `.stretch` band below the landscape screen) keeps the indicator
        // there, its clip never shorter than it (was nil: no layer for a rotation to interpolate).
        let below = place(.top, .default, overlay: true, refreshing: true, drag: 1, pull: 0, header: 900)!
        #expect(below.frame == CGRect(x: 0, y: 950, width: 400, height: 60) && below.clip == below.frame)
        #expect(place(.top, .default, overlay: true, pull: 0, header: 900) == nil, "at rest still outside its base")
    }

    @Test func noPullNoIndicatorAndAHoldKeepsItWhereTheGapIs() {
        #expect(place(.top, pull: 0) == nil && place(.top, pull: -20) == nil)
        // At rest with a 60 pt hold open the displayed pull against the hold-less bounds is 60: the gap is the hold.
        let held = place(.top, .system, refreshing: true, drag: 1, pull: 60)!
        #expect(held.frame == CGRect(x: 0, y: 50, width: 400, height: 60) && held.opacity == 1)
        #expect(held.clip == CGRect(x: 0, y: 50, width: 400, height: 60))
        // A user who scrolled the content back up: the gap shrinks, the indicator is clipped with it.
        let shrinking = place(.top, .default, refreshing: true, drag: 1, pull: 20)!
        #expect(shrinking.clip == CGRect(x: 0, y: 50, width: 400, height: 20))
        #expect(place(.top, .default, refreshing: true, drag: 1, pull: 0) == nil)
    }

    @Test func theLiveHeaderHeightMovesTheTopBase() {
        let with = place(.top, .system, header: 200)!
        #expect(with.frame.minY == 35 + 200 && with.clip.minY == 250)
        #expect(place(.bottom, .system, header: 200) == place(.bottom, .system), "only the top edge counts the header")
    }

    @Test func aDegenerateViewportDrawsNothing() {
        let none = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: false, dragPosition: 1,
                                                  pull: 30, length: 60, viewport: .zero, base: EdgeInsets())
        #expect(none == nil)
    }

    // MARK: hosted

    final class Gate: @unchecked Sendable { var runs = 0 }

    func hosted(_ path: OSPath, specs: (ZTronScrollView<StatefulContent>) -> ZTronScrollView<StatefulContent>,
                counts: BodyCount) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(specs(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }))
        }
        pump(0.3)
        return (s, w)
    }

    @Test(arguments: OSPath.allCases) func theContainerHookInstallsTheCoordinatorAndTheSpecs(path: OSPath) {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let refresh = try! #require(s.refresh)
        #expect(Set(refresh.specs.keys) == [.top] && refresh.bouncesVertical && !refresh.bouncesHorizontal)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aViewWithoutARefresherHasNoEnginesAndNoBounceForce(path: OSPath) {
        let counts = BodyCount()
        let (s, w) = hosted(path, specs: { $0 }, counts: counts)
        let refresh = try! #require(s.refresh)
        #expect(refresh.specs.isEmpty && !refresh.bouncesVertical)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theRefreshableBridgeInstallsASystemRefresherOnTheTopEdge(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }.refreshable { })
        }
        pump(0.3)
        let spec = try! #require(s.refresh?.specs[.top])
        #expect(spec.style == .system && s.refresh?.specs.count == 1)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func anExplicitRefresherBeatsRefreshable(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .refresher(style: .default) { }
                .refreshable { })
        }
        pump(0.3)
        #expect(s.refresh?.specs[.top]?.style == .default, "the member (.default) wins over .refreshable (.system)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func beginAndEndDrawTheIndicatorWithoutRunningAContentBody(path: OSPath) async {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let base = counts.bodies
        s.beginRefreshing()
        pump(0.3)
        let refresh = try! #require(s.refresh)
        #expect(refresh.states[.top]?.mode == .refreshing && gate.runs == 0, "beginRefreshing runs no action")
        #expect(s.refreshHoldInset.top == 60, "the hold the indicator keeps open")
        s.endRefreshing()
        pump(0.8)
        #expect(refresh.states[.top]?.mode == .notRefreshing && s.refreshHoldInset.top == 0)
        #expect(counts.bodies == base, "refresh state never re-evaluates the content")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theAccessibilityActionStartsTheRefreshOnce(path: OSPath) async {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let refresh = try! #require(s.refresh)
        RefreshAccessibility.perform(.top, on: refresh)
        RefreshAccessibility.perform(.top, on: refresh)
        for _ in 0..<30 { await Task.yield() }
        #expect(gate.runs == 1, "a second activation while refreshing is a no-op")
        #expect(refresh.triggerSerial == 1, "one haptic / one trigger")
        unhost(w)
    }

    @Test func accessibilityStringsAndNames() {
        #expect(RefreshAccessibility.label(for: .top) == "Refresh" && RefreshAccessibility.label(for: .leading) == "Refresh")
        #expect(RefreshAccessibility.label(for: .bottom) == "Load more" && RefreshAccessibility.label(for: .trailing) == "Load more")
        #expect(RefreshAccessibility.value(for: .refreshing) == "Refreshing" && RefreshAccessibility.value(for: .pulling) == "Pulling")
        #expect(RefreshAccessibility.value(for: .notRefreshing) == "Idle")
        #expect(RefreshAccessibility.name(of: .trailing) == "trailing")
    }

    @Test(arguments: OSPath.allCases) func reachEdgeTwinsRegisterWatchersAndUpdateInPlace(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        final class Hits { var n = 0 }
        let hits = Hits()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .onZTronScrollReachEdge(.bottom, threshold: 10) { hits.n += 1 })
        }
        pump(0.3)
        #expect(s.reachEdgeWatchers.count == 1 && s.reachEdgeWatchers[0].edge == .bottom && s.reachEdgeWatchers[0].threshold == 10)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theHolderReconcilesWatchersInPlace(path: OSPath) {
        let s = makeState(path)
        let holder = RefreshHolder(state: s)
        func decl(_ e: Edge, _ t: CGFloat) -> ReachEdgeDecl { ReachEdgeDecl(edge: e, threshold: t, perform: {}) }
        holder.reach = [decl(.bottom, 10), decl(.top, 0)]
        holder.syncReach(state: s)
        let first = s.reachEdgeWatchers
        #expect(first.count == 2)
        holder.reach = [decl(.bottom, 50), decl(.top, 0)]
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.count == 2 && s.reachEdgeWatchers[0] === first[0] && s.reachEdgeWatchers[0].threshold == 50,
                "same edge at the same position keeps its watcher (and its arming)")
        holder.reach = [decl(.bottom, 50), decl(.leading, 0)]
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.count == 2 && s.reachEdgeWatchers[0] === first[0] && s.reachEdgeWatchers[1] !== first[1])
        holder.reach = []
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.isEmpty)
    }
}
