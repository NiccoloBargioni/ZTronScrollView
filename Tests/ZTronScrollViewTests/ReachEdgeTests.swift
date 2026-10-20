import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// `onZTronScrollReachEdge` (SPEC S9 "Edges", design M8b §1.3): once per arrival within `threshold`, re-armed only more
/// than 1 pt away, including after content growth; evaluated at the `didScroll` flush and on metrics changes.
@MainActor
@Suite(.serialized)
struct ReachEdgeTests {
    final class Count { var n = 0 }

    func make(_ path: OSPath, content: CGSize = CGSize(width: 390, height: 3000)) -> ZTronScrollState {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 390, height: 800), contentSize: content, displayScale: 2))
        return s
    }

    func watch(_ s: ZTronScrollState, _ edge: Edge, threshold: CGFloat = 0, _ count: Count) -> ReachEdgeWatcher {
        let w = ReachEdgeWatcher(edge: edge, threshold: threshold) { count.n += 1 }
        s.addReachEdgeWatcher(w)
        return w
    }

    func move(_ s: ZTronScrollState, to y: CGFloat) { s.setContentOffset(CGPoint(x: 0, y: y), animated: false) }

    // MARK: Once per arrival

    @Test(arguments: OSPath.allCases) func firesOncePerArrivalAtTheEnd(path: OSPath) {
        let s = make(path)
        let c = Count()
        let w = watch(s, .bottom, c)
        _ = w
        #expect(c.n == 0, "the top of a 3000 pt list is not the bottom")
        for y in [200, 1000, 2100, 2199] as [CGFloat] { move(s, to: y); #expect(c.n == 0, "y = \(y)") }
        move(s, to: 2200)                                   // max = 3000 − 800
        #expect(c.n == 1)
        move(s, to: 2200)
        move(s, to: 2199.5)                                 // within the hysteresis: still the same arrival
        move(s, to: 2200)
        move(s, to: 2260)                                   // rubber band past the edge
        move(s, to: 2200)
        #expect(c.n == 1, "one firing for the whole stay")
    }

    @Test(arguments: OSPath.allCases) func rearmsOnlyBeyondOnePoint(path: OSPath) {
        let s = make(path)
        let c = Count()
        let w = watch(s, .bottom, c)
        move(s, to: 2200)
        #expect(c.n == 1 && !w.isArmed)
        move(s, to: 2199)                                   // d = 1: not beyond threshold + 1
        #expect(!w.isArmed)
        move(s, to: 2198.9)                                 // d = 1.1: re-armed, nothing fires by leaving
        #expect(w.isArmed && c.n == 1)
        move(s, to: 2200)
        #expect(c.n == 2, "the next arrival fires again")
    }

    @Test(arguments: OSPath.allCases) func refiresAfterContentGrowth(path: OSPath) {
        let s = make(path)
        let c = Count()
        let w = watch(s, .bottom, c)
        move(s, to: 2200)
        #expect(c.n == 1)
        s.setContentSize(CGSize(width: 390, height: 4000))   // a load-more append moves the end edge away
        #expect(w.isArmed && c.n == 1, "re-armed by the metrics change; nothing fires while the end is 1000 pt away")
        move(s, to: 3200)                                    // the new end
        #expect(c.n == 2)
        s.setContentSize(CGSize(width: 390, height: 4000))   // no change, no firing
        s.setContentSize(CGSize(width: 390, height: 4400))
        #expect(c.n == 2 && w.isArmed)
    }

    @Test(arguments: OSPath.allCases) func appendWhileWithinThresholdFiresAgainWhenTheNewEndIsReached(path: OSPath) {
        let s = make(path)
        let c = Count()
        _ = watch(s, .bottom, threshold: 100, c)
        move(s, to: 2100)                                   // d = 100 ≤ 100: arrived
        #expect(c.n == 1)
        move(s, to: 2150)
        #expect(c.n == 1)
        s.setContentSize(CGSize(width: 390, height: 3600))  // d = 650 + ... > 101: re-armed
        move(s, to: 2800)                                   // max = 2800: arrived again
        #expect(c.n == 2)
    }

    // MARK: Threshold, edges, lifecycle

    @Test(arguments: OSPath.allCases) func thresholdAndTopEdge(path: OSPath) {
        let s = make(path)
        move(s, to: 500)
        let c = Count()
        _ = watch(s, .top, threshold: 100, c)
        #expect(c.n == 0)
        move(s, to: 101)
        #expect(c.n == 0)
        move(s, to: 100)                                    // d_top = o − min = 100 ≤ 100
        #expect(c.n == 1)
        move(s, to: -40)                                    // pulled past the top: still the same arrival
        #expect(c.n == 1)
        move(s, to: 300)                                    // away: re-armed
        move(s, to: 0)
        #expect(c.n == 2)
    }

    @Test(arguments: OSPath.allCases) func horizontalEdges(path: OSPath) {
        let s = makeState(path)
        s.scrollAxes = .horizontal
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 390, height: 800), contentSize: CGSize(width: 1390, height: 800), displayScale: 2))
        let lead = Count(), trail = Count()
        _ = watch(s, .leading, lead)
        _ = watch(s, .trailing, trail)
        #expect(lead.n == 1 && trail.n == 0, "at the start the leading edge is reached on the first evaluation")
        s.setContentOffset(CGPoint(x: 400, y: 0), animated: false)
        s.setContentOffset(CGPoint(x: 1000, y: 0), animated: false)   // max = 1390 − 390
        #expect(lead.n == 1 && trail.n == 1)
        s.setContentOffset(CGPoint(x: 500, y: 0), animated: false)
        s.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        #expect(lead.n == 2 && trail.n == 1)
    }

    @Test(arguments: OSPath.allCases) func silentUntilTheFirstLayoutThenFiresOnArrival(path: OSPath) {
        let s = makeState(path)
        let c = Count()
        _ = watch(s, .top, c)
        #expect(c.n == 0, "no viewport, no content: a zero viewport is at every edge")
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 390, height: 800), contentSize: CGSize(width: 390, height: 3000), displayScale: 2))
        s.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        #expect(c.n == 1, "laid out, at the top: the arrival")
    }

    @Test(arguments: OSPath.allCases) func shortContentIsAtBothEdges(path: OSPath) {
        let s = make(path, content: CGSize(width: 390, height: 300))
        let top = Count(), bottom = Count()
        _ = watch(s, .top, top)
        _ = watch(s, .bottom, bottom)
        #expect(top.n == 1 && bottom.n == 1, "nothing to scroll: load-more still has to fire")
    }

    @Test(arguments: OSPath.allCases) func removedWatcherIsSilentAndUpdatesApplyInPlace(path: OSPath) {
        let s = make(path)
        let c = Count(), other = Count()
        let w = watch(s, .bottom, c)
        move(s, to: 2000)
        w.threshold = 250
        w.perform = { other.n += 1 }
        move(s, to: 1900)                                   // d = 300 > 251: stays armed
        move(s, to: 1960)                                   // d = 240 ≤ 250: fires the replaced closure
        #expect(c.n == 0 && other.n == 1)
        s.removeReachEdgeWatcher(w)
        move(s, to: 0)
        move(s, to: 2200)
        #expect(other.n == 1 && s.reachEdgeWatchers.isEmpty)
    }

    // MARK: At the flush

    @Test(arguments: OSPath.allCases) func evaluatedAtTheDidScrollFlushNotPerFingerWrite(path: OSPath) {
        let s = make(path)
        var t: TimeInterval = 100
        s.now = { t }
        s.track(offset: CGPoint(x: 0, y: 2000), zoom: 1)
        let c = Count()
        _ = watch(s, .bottom, c)
        let pan = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        let start = CGPoint(x: 200, y: 600)
        pan.handle(.touchDown(location: start, time: t, touchCount: 1))
        pan.handle(.dragChanged(translation: CGSize(width: 0, height: -10), startLocation: start, time: t))
        pan.handle(.dragChanged(translation: CGSize(width: 0, height: -230), startLocation: start, time: t))
        #expect(s.contentOffset.y > 2200, "the finger rubber-banded the offset past the end")
        #expect(c.n == 0, "finger writes only mark didScroll pending")
        t += 1.0 / 60
        s.step(to: Date(timeIntervalSinceReferenceDate: t))   // the frame's flush
        #expect(c.n == 1)
    }
}
