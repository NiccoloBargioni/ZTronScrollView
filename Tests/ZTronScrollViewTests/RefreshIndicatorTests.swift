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
        #expect(place(.top, pull: 0) == nil && place(.top, pull: -20) == nil, "a pull (or its release) ends at 0")
        // Refreshing, no gap: nothing drawn, the clip is empty (open item 19: the placement, and the layer, stay).
        for pull: CGFloat in [0, -20] {
            let none = place(.top, refreshing: true, drag: 1, pull: pull)!
            #expect(none.visibleLength(vertical: true) == 0 && none.clip.height == 0, "pull \(pull): \(none)")
        }
        // At rest with a 60 pt hold open the displayed pull against the hold-less bounds is 60: the gap is the hold.
        let held = place(.top, .system, refreshing: true, drag: 1, pull: 60)!
        #expect(held.frame == CGRect(x: 0, y: 50, width: 400, height: 60) && held.opacity == 1)
        #expect(held.clip == CGRect(x: 0, y: 50, width: 400, height: 60))
        // A user who scrolled the content back up: the gap shrinks, the indicator is clipped with it.
        let shrinking = place(.top, .default, refreshing: true, drag: 1, pull: 20)!
        #expect(shrinking.clip == CGRect(x: 0, y: 50, width: 400, height: 20))
        #expect(place(.top, .default, refreshing: true, drag: 1, pull: 0)!.visibleLength(vertical: true) == 0)
    }

    /// Open item 19: a hold whose gap left the viewport (the content scrolled past the base, S7 in a rotation) keeps its
    /// placement: the box's far edge on the content's edge, the indicator where the hold rests it against that edge
    /// (`.system`: H/2 before it once the pull is past -H, continuous through 0; `.default`: glued to it), nothing visible
    /// (the clip is empty, the region starts at the base). At rest and for any pull > 0 the visible part is unchanged.
    @Test func aHoldScrolledAwayKeepsItsBoxOnTheContentsEdge() {
        for edge in [Edge.top, .bottom, .leading, .trailing] {
            let vertical = edge == .top || edge == .bottom
            let along: CGFloat = vertical ? 800 : 400
            let b: CGFloat = [Edge.top: 50, .bottom: 34, .leading: 0, .trailing: 0][edge]!
            /// Position along d (from the base into the viewport) of a viewport coordinate on the pull axis.
            func d(_ v: CGFloat) -> CGFloat { edge == .top || edge == .leading ? v - b : along - b - v }
            func span(_ r: CGRect) -> (CGFloat, CGFloat) {
                let a = vertical ? (d(r.minY), d(r.maxY)) : (d(r.minX), d(r.maxX))
                return (min(a.0, a.1), max(a.0, a.1))
            }
            for style in [ZTronRefreshStyle.system, .default] {
                var previous: (pull: CGFloat, centre: CGFloat)?
                for pull: CGFloat in [-400, -100, -60, -30, -1, -0.01, 0, 0.01, 1, 30, 60, 100] {
                    let label = "\(edge) \(style) pull \(pull)"
                    guard let pl = place(edge, style, refreshing: true, drag: 1, pull: pull) else {
                        Issue.record("\(label): no placement")
                        continue
                    }
                    let box = span(pl.box), frame = span(pl.frame), region = span(pl.region)
                    #expect(abs(box.1 - pull) < 1e-9, "\(label): the box ends on the content's edge \(box)")
                    #expect(box.0 <= min(0, pull - 60) + 1e-9 && box.0 <= frame.0 + 1e-9, "\(label): box holds the indicator's near part \(box) \(frame)")
                    #expect(abs(region.0) < 1e-9 && region.1 >= max(pull, along) - 1e-9, "\(label): region from the base \(region)")
                    let centre = (frame.0 + frame.1) / 2
                    let expected: CGFloat = style == .default ? pull - 30 : pull > 0 ? pull / 2 : pull - min(60, -pull) / 2
                    #expect(abs(centre - expected) < 1e-9, "\(label): centre \(centre), expected \(expected)")
                    if pull <= 0 {
                        #expect(pl.visibleLength(vertical: vertical) == 0, "\(label): nothing visible")
                    } else {
                        #expect(abs(pl.visibleLength(vertical: vertical) - min(pull, 60)) < 1e-9,
                                "\(label): visible \(pl.visibleLength(vertical: vertical)) as before")
                        let clip = span(pl.clip)
                        #expect(abs(clip.0) < 1e-9 && abs(clip.1 - pull) < 1e-9, "\(label): the gap \(clip)")
                    }
                    if let previous, previous.pull >= -1, pull <= 1 {
                        #expect(abs(centre - previous.centre) <= abs(pull - previous.pull) * 1.5 + 1e-9,
                                "\(label): continuous through 0 (\(previous) -> \(centre))")
                    }
                    previous = (pull, centre)
                }
                // Rigid with the content past -H: the indicator's distance to the content's edge is the rest one.
                let rest = place(edge, style, refreshing: true, drag: 1, pull: 60)!
                let away = place(edge, style, refreshing: true, drag: 1, pull: -400)!
                let restSpan = span(rest.frame), awaySpan = span(away.frame)
                #expect(abs((restSpan.0 - 60) - (awaySpan.0 + 400)) < 1e-9, "\(edge) \(style): rest place against the edge")
            }
        }
    }

    /// A hold larger than the indicator (`holdOffset`): `.system` rests at H/2 and keeps that place against the content's
    /// edge when scrolled away; the box reaches back H.
    @Test func aLargerHoldRestsTheSystemIndicatorInItsMiddle() {
        let rest = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                  pull: 100, length: 60, viewport: viewport, base: base, hold: 100)!
        #expect(rest.frame.midY == 50 + 50 && rest.clip == CGRect(x: 0, y: 50, width: 400, height: 100))
        #expect(rest.box == rest.clip, "at rest the box is the gap")
        let away = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                  pull: -300, length: 60, viewport: viewport, base: base, hold: 100)!
        #expect(away.frame.midY == 50 - 300 - 50 && away.box == CGRect(x: 0, y: 50 - 400, width: 400, height: 100))
        #expect(away.visibleLength(vertical: true) == 0)
    }

    /// D66: a resize that began with nothing of the indicator visible (its last frame with the resize closed) hides it
    /// until the resize is drawn frame by frame (`.animating`: shown at once) or closes without that (a system rotation:
    /// `.revealing` once, shown after the transition). A resize that began visible never hides.
    @Test func aResizeThatBeganWithNothingVisibleHidesItUntilItIsDrawnFrameByFrameOrOver() {
        let r = RefreshResizeReveal()
        // A rotation: open one turn, never animated.
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
        #expect(r.look(open: true, visible: false, animating: false) == .hidden, "began with nothing visible")
        #expect(r.look(open: true, visible: true, animating: false) == .hidden, "latched, whatever the target pull says")
        #expect(r.look(open: false, visible: true, animating: false) == .revealing, "closed undrawn: shown after the transition")
        #expect(r.look(open: false, visible: true, animating: false) == .shown)
        // A withAnimation resize: drawn frame by frame from its second tick.
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
        #expect(r.look(open: true, visible: false, animating: false) == .hidden)
        #expect(r.look(open: true, visible: false, animating: true) == .shown, "drawn frame by frame: the box keeps it in place")
        #expect(r.look(open: true, visible: true, animating: false) == .shown)
        #expect(r.look(open: false, visible: true, animating: false) == .shown, "no delayed reveal")
        // Began visible: never hidden.
        #expect(r.look(open: true, visible: false, animating: false) == .shown)
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
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
