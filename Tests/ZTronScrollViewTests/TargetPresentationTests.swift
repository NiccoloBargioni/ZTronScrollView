import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class RecordingDelegate: ZTronScrollViewDelegate {
    var didScroll = 0
    var didEnd = 0
    func scrollViewDidScroll(_ state: ZTronScrollState) { didScroll += 1 }
    func scrollViewDidEndScrollingAnimation(_ state: ZTronScrollState) { didEnd += 1 }
}

@MainActor
@Suite(.serialized)
struct TargetPresentationTests {
    private func make(_ path: OSPath) -> (ZTronScrollState, RecordingDelegate) {
        let s = makeState(path)
        let d = RecordingDelegate()
        s.delegate = d
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900)))
        return (s, d)
    }
    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }

    @Test(arguments: OSPath.allCases) func clockStepWritesBoth(path: OSPath) {
        let (s, d) = make(path)
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: true)
        #expect(s.phase == .animating && s.isScrollAnimating && s.isClockRunning)
        #expect(s.peek.targetOffset == CGPoint(x: 0, y: 400))
        s.step(to: date(100.2))
        let p = s.peek
        #expect(p.presentationOffset.y > 0 && p.presentationOffset.y < 400)
        #expect(p.targetOffset == p.presentationOffset)
        #expect(d.didScroll == 1)
    }

    @Test(arguments: OSPath.allCases) func transactionWriteTouchesOnlyTarget(path: OSPath) {
        let (s, d) = make(path)
        s.scroll(to: CGPoint(x: 0, y: 300))
        let p = s.peek
        #expect(p.targetOffset == CGPoint(x: 0, y: 300))
        #expect(p.presentationOffset == .zero)
        #expect(s.phase == .animating && s.isClockRunning)
        #expect(d.didScroll == 0)
    }

    @Test(arguments: OSPath.allCases) func interruptSetsTargetToPresentation(path: OSPath) {
        let (s, _) = make(path)
        s.scroll(to: CGPoint(x: 0, y: 300))
        s.probe.record(CGPoint(x: 0, y: 120), 1)
        s.step(to: date(100.1))
        s.interrupt()
        let p = s.peek
        #expect(p.targetOffset == CGPoint(x: 0, y: 120) && p.presentationOffset == p.targetOffset)
        #expect(p.phase == .idle && !p.isClockRunning && !p.isScrollAnimating)
    }

    @Test(arguments: OSPath.allCases) func stepWhileIdleIsNoop(path: OSPath) {
        let (s, d) = make(path)
        let before = s.peek
        s.step(to: date(101))
        #expect(s.peek == before && d.didScroll == 0 && d.didEnd == 0)
    }

    @Test(arguments: OSPath.allCases) func clockStopsWhenAllAxesSettle(path: OSPath) {
        let (s, d) = make(path)
        s.setContentOffset(CGPoint(x: 20, y: 400), animated: true)
        s.step(to: date(110))
        let p = s.peek
        #expect(p.presentationOffset == CGPoint(x: 20, y: 400) && p.targetOffset == p.presentationOffset)
        #expect(p.phase == .idle && !p.isClockRunning && !p.isScrollAnimating)
        #expect(d.didEnd == 1)
        s.step(to: date(111))
        #expect(d.didEnd == 1)
    }

    @Test(arguments: OSPath.allCases) func settleDetectorNeedsTwoFrames(path: OSPath) {
        let (s, d) = make(path)
        s.scroll(to: CGPoint(x: 0, y: 300))
        s.probe.record(CGPoint(x: 0, y: 150), 1)
        s.step(to: date(100.1))
        #expect(s.peek.presentationOffset.y == 150 && s.phase == .animating)
        s.probe.record(CGPoint(x: 0, y: 300), 1)
        s.step(to: date(100.2))
        #expect(s.phase == .animating)
        s.step(to: date(100.3))
        #expect(s.phase == .idle && !s.isClockRunning && d.didEnd == 1)
        #expect(s.peek.presentationOffset == CGPoint(x: 0, y: 300))
    }

    @Test(arguments: OSPath.allCases) func staleCompletionTokenIgnored(path: OSPath) {
        let (s, d) = make(path)
        s.scroll(to: CGPoint(x: 0, y: 100))
        let first = s.activeTransactionToken!
        s.scroll(to: CGPoint(x: 0, y: 200))
        let second = s.activeTransactionToken!
        #expect(first != second)
        s.finishTransactionMotion(token: first)
        #expect(s.phase == .animating && d.didEnd == 0)
        s.finishTransactionMotion(token: second)
        #expect(s.phase == .idle && d.didEnd == 1)
        #expect(s.peek.presentationOffset == CGPoint(x: 0, y: 200))
    }

    @Test(arguments: OSPath.allCases) func didScrollAtMostOncePerBatch(path: OSPath) {
        let (s, d) = make(path)
        s.batch {
            s.storage.presentationOffset = CGPoint(x: 1, y: 1)
            s.storage.presentationOffset = CGPoint(x: 2, y: 2)
            s.batch { s.storage.presentationZoom = 2 }
        }
        #expect(d.didScroll == 1)
        s.batch { s.storage.presentationOffset = CGPoint(x: 2, y: 2) }
        #expect(d.didScroll == 1)
    }

    @Test(arguments: OSPath.allCases) func zoomKeepsVisibleCenter(path: OSPath) {
        let (s, _) = make(path)
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        s.setContentOffset(CGPoint(x: 50, y: 100), animated: false)
        // center in content space: (50+50, 100+100) = (100, 200)
        s.setZoomScale(2, animated: false)
        #expect(s.peek.presentationOffset == CGPoint(x: 150, y: 300))
        s.setZoomScale(4, animated: true)
        s.step(to: date(110))
        #expect(s.zoomScale == 4 && s.contentOffset == CGPoint(x: 350, y: 700) && s.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func unanimatedSetCancelsMotion(path: OSPath) {
        let (s, _) = make(path)
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: true)
        s.setContentOffset(CGPoint(x: 0, y: 10), animated: false)
        #expect(s.phase == .idle && !s.isClockRunning && s.contentOffset == CGPoint(x: 0, y: 10))
    }
}
