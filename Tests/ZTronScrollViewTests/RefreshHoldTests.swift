import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// The refresh hold as geometry (design M8b §1.3, test list item 3): `adjustedContentInset` includes it, the release
/// springs an over-pull to `-(aci.top + H)`, the reset returns the content to rest only from the start edge, and
/// `beginRefreshing` reveals the indicator without running the action.
@MainActor
@Suite(.serialized)
struct RefreshHoldTests {
    let safeTop = EdgeInsets(top: 59, leading: 0, bottom: 0, trailing: 0)

    /// Completes the running action and lets everything run to rest: the action returns, the minimum visible time passes
    /// (timer), the reset runs, the motion settles.
    func finishRefresh(_ r: RefreshRig) async {
        await r.completeAction()
        r.clock.t += 5
        r.fireWakes()
        r.settle()
    }

    // MARK: adjustedContentInset

    @Test(arguments: OSPath.allCases) func adjustedContentInsetIncludesTheHold(path: OSPath) {
        let r = RefreshRig(path, safe: safeTop)
        #expect(r.aci.top == 59 && r.hold == EdgeInsets() && abs(r.offset.y + 59) < 1e-9)
        r.pullAndRelease(to: 140)
        #expect(r.hold.top == 60, "the top hold")
        #expect(r.aci.top == 119 && r.state.geometry.contentInsets.top == 119, "safe area 59 + hold 60")
        #expect(r.state.peek.metrics.resize.current.insets.top == 119, "the resize commit sees the same inset")
        #expect(r.boundsY.min == -119, "the bounds follow the hold")
        #expect(r.delegate.log.filter { $0 == "inset" }.count == 1, "one adjusted-inset notification, at the lift")
        r.refresh.cancelAll()
        #expect(r.aci.top == 59 && r.hold == EdgeInsets())
        #expect(r.delegate.log.filter { $0 == "inset" }.count == 2)
    }

    @Test(arguments: OSPath.allCases) func theBottomHoldAddsTheLoadMorePadding(path: OSPath) {
        let r = RefreshRig(path, configs: [.bottom: ZTronRefreshConfiguration.loadMore])
        r.state.setContentOffset(CGPoint(x: 0, y: 2200), animated: false)         // the end of 3000 pt in an 800 pt viewport
        r.pullAndRelease(to: 140, edge: .bottom)
        #expect(r.refresh.triggerSerial == 1)
        #expect(r.hold.bottom == 104 && r.aci.bottom == 104 && r.hold.top == 0, "indicator 60 + 44 pt of padding")
        let end: CGFloat = 2200 + 104                       // content 3000 + hold 104 - viewport 800
        #expect(r.boundsY.max == end, "bounds \(r.boundsY), aci \(r.aci), offset \(r.offset)")
        r.settle()
        #expect(abs(r.offset.y - end) < 0.5, "an over-pull at the end springs to the hold position")
    }

    // MARK: The release

    @Test(arguments: OSPath.allCases) func anOverPullReleaseSpringsToTheHoldPosition(path: OSPath) {
        let r = RefreshRig(path, safe: safeTop)
        r.touchDown()
        r.finger(toPull: 150)
        r.lift()
        #expect(r.boundsY.min == -119)
        #expect(r.state.phase == .decelerating, "the over-pull springs on the clock")
        let scrolls = r.delegate.log.filter { $0 == "didScroll" }.count
        r.settle()
        #expect(abs(r.offset.y - (-(59 + 60))) < 0.5, "rests at -(aci.top + H) = -119: \(r.offset.y)")
        #expect(r.state.phase == .idle && r.state.refreshHoldInset.top == 60)
        #expect(r.delegate.log.filter { $0 == "didScroll" }.count > scrolls, "didScroll fired during the spring-back")
    }

    @Test(arguments: OSPath.allCases) func aLiftUnderTheHoldBandScrollsToTheHold(path: OSPath) {
        // The trigger is under the hold: a release at 100 pt of pull cannot reach the 120 pt hold by itself.
        let cfg = ZTronRefreshConfiguration(triggerDistance: 80, indicatorHeight: 120)
        let r = RefreshRig(path, configs: [.top: cfg])
        r.pullAndRelease(to: 100)
        #expect(r.refresh.triggerSerial == 1 && r.hold.top == 120)
        r.settle()
        #expect(abs(r.offset.y + 120) < 0.5, "the indicator is fully shown: \(r.offset.y)")
        #expect(r.state.phase == .idle)
    }

    // MARK: The reset

    @Test(arguments: OSPath.allCases) func clearingReturnsToRestFromTheStartEdge(path: OSPath) async {
        let r = RefreshRig(path, safe: safeTop)
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        #expect(abs(r.offset.y + 119) < 0.5 && r.aci.top == 119)
        await finishRefresh(r)
        #expect(r.hold == EdgeInsets() && r.aci.top == 59)
        #expect(abs(r.offset.y + 59) < 0.5, "back at rest, -aci.top")
        #expect(r.state.phase == .idle && !r.state.isClockRunning)
        #expect(r.delegate.log.filter { $0 == "inset" }.count == 2)
    }

    @Test(arguments: OSPath.allCases) func clearingLeavesAUserWhoScrolledAwayWhereTheyAre(path: OSPath) async {
        let r = RefreshRig(path)
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        r.state.setContentOffset(CGPoint(x: 0, y: 500), animated: false)           // scrolled away while refreshing
        await finishRefresh(r)
        #expect(r.hold == EdgeInsets() && r.aci.top == 0)
        #expect(r.offset.y == 500, "nothing moves: \(r.offset.y)")
        #expect(r.refreshState().mode == .notRefreshing)
    }

    @Test(arguments: OSPath.allCases) func theResetAnimationDecidesHowTheContentReturns(path: OSPath) async {
        // .uikit: the bounds change, then the clock animates the offset to rest.
        let u = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(resetAnimation: .uikit)])
        u.pullAndRelease(to: 140)
        await u.pumpTasks()
        u.settle()
        await u.completeAction()
        u.clock.t += 5
        u.fireWakes()
        #expect(u.hold == EdgeInsets() && u.state.phase == .animating && u.state.isScrollAnimating, "animated on the clock")
        u.settle()
        #expect(abs(u.offset.y) < 0.5 && u.state.phase == .idle)
        // nil: unanimated, at rest at once.
        let n = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(resetAnimation: nil)])
        n.pullAndRelease(to: 140)
        await n.pumpTasks()
        n.settle()
        await n.completeAction()
        n.clock.t += 5
        n.fireWakes()
        #expect(n.hold == EdgeInsets() && abs(n.offset.y) < 0.5 && n.state.phase == .idle)
    }

    // MARK: beginRefreshing / endRefreshing

    @Test(arguments: OSPath.allCases) func beginRefreshingRevealsTheIndicatorAndRunsNoAction(path: OSPath) async {
        let r = RefreshRig(path, safe: safeTop)
        r.state.beginRefreshing()
        #expect(r.hold.top == 60 && r.aci.top == 119)
        #expect(r.engine().phase == .refreshing(since: r.now) && r.refreshState().mode == .refreshing)
        #expect(r.state.isScrollAnimating, "the reveal runs on the clock")
        r.settle()
        #expect(abs(r.offset.y + 119) < 0.5, "scrolled to the hold position: \(r.offset.y)")
        await r.pumpTasks()
        #expect(r.refresh.triggerSerial == 0 && r.gate.started == 0, "UIKit parity: beginRefreshing sends no valueChanged")
        r.state.endRefreshing()
        r.clock.t += 5
        r.fireWakes()
        r.settle()
        #expect(r.hold == EdgeInsets() && abs(r.offset.y + 59) < 0.5 && r.refreshState().mode == .notRefreshing)
        r.state.endRefreshing()                                                     // nothing is refreshing: a no-op
        #expect(r.engine().phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func beginRefreshingAwayFromTheEdgeOnlyChangesTheMode(path: OSPath) {
        let r = RefreshRig(path)
        r.state.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        r.state.beginRefreshing()
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing)
        #expect(r.offset.y == 500 && !r.state.isScrollAnimating, "the indicator spins off screen")
        r.state.endRefreshing()
        r.clock.t += 5
        r.fireWakes()
        #expect(r.hold == EdgeInsets() && r.offset.y == 500)
    }

    @Test(arguments: OSPath.allCases) func beginRefreshingWaitsForTheLiftAndIgnoresMissingRefreshers(path: OSPath) {
        let r = RefreshRig(path)
        r.touchDown()
        r.state.beginRefreshing()
        #expect(r.hold == EdgeInsets() && r.engine().phase == .idle, "never under a finger")
        r.pan.handle(.touchesEnded(time: r.now))
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing, "applied when the touch ends")
        let b = RefreshRig(path)
        b.state.beginRefreshing(edge: .bottom)                                       // only a top refresher exists
        #expect(b.hold == EdgeInsets() && b.engine().phase == .idle)
    }

    // MARK: Bounce

    @Test(arguments: OSPath.allCases) func aRefresherForcesBounceOnItsAxis(path: OSPath) {
        let r = RefreshRig(path, content: CGSize(width: 390, height: 400))
        r.pan.settings.bounceY = .basedOnSize
        #expect(r.pan.peekEnvironment().bouncesY, "short content still bounces with a refresher")
        r.refresh.setSpecs([:])
        #expect(!r.pan.peekEnvironment().bouncesY, ".basedOnSize without a refresher: fitting content does not bounce")
        // Horizontal edges force the horizontal axis only.
        let h = RefreshRig(path, configs: [.leading: ZTronRefreshConfiguration()], axes: .horizontal,
                           content: CGSize(width: 300, height: 800))
        h.pan.settings.bounceX = .basedOnSize
        h.pan.settings.bounceY = .basedOnSize
        let env = h.pan.peekEnvironment()
        #expect(env.bouncesX && !env.bouncesY)
    }

    @Test(arguments: OSPath.allCases) func aHorizontalEdgePullsAndHoldsOnTheXAxis(path: OSPath) {
        let r = RefreshRig(path, configs: [.leading: ZTronRefreshConfiguration()], axes: .horizontal,
                           content: CGSize(width: 1400, height: 800))
        r.pullAndRelease(to: 140, edge: .leading)
        #expect(r.refresh.triggerSerial == 1)
        #expect(r.hold.leading == 60 && r.aci.leading == 60 && r.aci.top == 0)
        r.settle()
        #expect(abs(r.offset.x + 60) < 0.5, "x = \(r.offset.x)")
    }

    // MARK: Rotation

    @Test(arguments: OSPath.allCases) func theHoldStaysInTheInsetWhenTheSafeAreaChanges(path: OSPath) async {
        let r = RefreshRig(path, safe: safeTop)
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        let before = r.aci
        // An unrelated safe-area change recomputes the adjusted inset from its parts: the hold stays in it.
        r.state.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 800),
                                            safeArea: EdgeInsets(top: 47, leading: 0, bottom: 0, trailing: 0)))
        #expect(r.hold.top == 60 && r.aci.top == before.top - 59 + 47 && r.aci.top == 107)
        #expect(r.boundsY.min == -107)
    }
}
