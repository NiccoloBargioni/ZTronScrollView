import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M7 session 1, hub level (design §7 T1, T2, T5, T6): boxes registered straight on `state.observers`.
@MainActor
@Suite(.serialized)
struct ObservationHubTests {
    final class Log { var entries: [String] = [] }

    /// One log shared by the delegate and the observers, so the order of a delivery is readable.
    final class OrderDelegate: ZTronScrollViewDelegate {
        let log: Log
        init(_ log: Log) { self.log = log }
        func scrollViewDidZoom(_ s: ZTronScrollState) { log.entries.append("didZoom") }
        func scrollViewDidScroll(_ s: ZTronScrollState) { log.entries.append("didScroll") }
        func scrollViewDidEndDecelerating(_ s: ZTronScrollState) { log.entries.append("didEndDecelerating") }
        func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState) { log.entries.append("didEndScrollingAnimation") }
        func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale scale: CGFloat) { log.entries.append("didEndZooming") }
    }

    private func sized(_ path: OSPath, content: CGSize = CGSize(width: 300, height: 900)) -> ZTronScrollState {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: content, displayScale: 2))
        return s
    }

    // MARK: T1

    @Test(arguments: OSPath.allCases) func initialCallIsOldEqualsNewAtRegistrationThenChangesFollow(path: OSPath) {
        let s = makeState(path)
        var calls: [(CGFloat, CGFloat)] = []
        _ = s.observers.addGeometry(TypedGeometryBox<CGFloat>(transform: { $0.containerSize.height }, action: { calls.append(($0, $1)) }))
        s.deliverObservers()
        #expect(calls.count == 1 && calls[0] == (0, 0), "native: (v, v) before the first layout")
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 900), displayScale: 2))
        #expect(calls.count == 2 && calls[1] == (0, 200))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 800), displayScale: 2))
        #expect(calls.count == 2, "the content size is not part of the derived value")
    }

    @Test(arguments: OSPath.allCases) func firesOnlyWhenTheDerivedValueChanges(path: OSPath) {
        let s = sized(path)
        var offsetCalls: [(CGFloat, CGFloat)] = [], zoomCalls: [(CGFloat, CGFloat)] = []
        _ = s.observers.addGeometry(TypedGeometryBox<CGFloat>(transform: { $0.contentOffset.y }, action: { offsetCalls.append(($0, $1)) }))
        _ = s.observers.addGeometry(TypedGeometryBox<CGFloat>(transform: { $0.zoomScale }, action: { zoomCalls.append(($0, $1)) }))
        s.deliverObservers()
        #expect(offsetCalls.count == 1 && zoomCalls.count == 1)
        // A pan: the offset observer fires, the zoom observer is silent.
        s.track(offset: CGPoint(x: 0, y: 40), zoom: 1)
        #expect(offsetCalls.count == 2 && offsetCalls[1] == (0, 40) && zoomCalls.count == 1)
        // A pure zoom (same offset): the offset observer is silent.
        s.track(offset: CGPoint(x: 0, y: 40), zoom: 2)
        #expect(offsetCalls.count == 2 && zoomCalls.count == 2 && zoomCalls[1] == (1, 2))
        s.track(offset: CGPoint(x: 0, y: 40), zoom: 2)
        #expect(offsetCalls.count == 2 && zoomCalls.count == 2, "unchanged: no call")
    }

    @Test(arguments: OSPath.allCases) func atMostOnceAndOnlyAfterTheDelegateInOneDelivery(path: OSPath) {
        let s = sized(path)
        let log = Log()
        let delegate = OrderDelegate(log)          // `delegate` is weak
        s.delegate = delegate
        defer { withExtendedLifetime(delegate) {} }
        _ = s.observers.addGeometry(TypedGeometryBox<CGPoint>(transform: { $0.contentOffset }, action: { _, _ in log.entries.append("geometry") }))
        s.deliverObservers()
        log.entries.removeAll()
        // Many writes in one batch, one delivery.
        s.batch {
            s.track(offset: CGPoint(x: 0, y: 10), zoom: 1)
            s.track(offset: CGPoint(x: 0, y: 20), zoom: 1)
            s.track(offset: CGPoint(x: 0, y: 30), zoom: 1)
        }
        #expect(log.entries == ["didScroll", "geometry"], "log: \(log.entries)")
    }

    @Test(arguments: OSPath.allCases) func aTransformReturningTheGeometryDiffersFromItsOwnPast(path: OSPath) {
        let s = sized(path)
        var calls: [(CGFloat, CGFloat)] = []
        _ = s.observers.addGeometry(TypedGeometryBox<ZTronScrollGeometry>(transform: { $0 }, action: { calls.append(($0.contentOffset.y, $1.contentOffset.y)) }))
        s.deliverObservers()
        s.track(offset: CGPoint(x: 0, y: 25), zoom: 1)
        #expect(calls.count == 2 && calls[1] == (0, 25), "frozen copies: the old value is not a live view (\(calls))")
    }

    @Test(arguments: OSPath.allCases) func removedBoxesStaySilentAndAReRegistrationSeedsAgain(path: OSPath) {
        let s = sized(path)
        var calls = 0
        let box = TypedGeometryBox<CGFloat>(transform: { $0.contentOffset.y }, action: { _, _ in calls += 1 })
        let token = s.observers.addGeometry(box)
        s.deliverObservers()
        s.observers.remove(token)
        s.track(offset: CGPoint(x: 0, y: 40), zoom: 1)
        #expect(calls == 1)
        _ = s.observers.addGeometry(box)
        s.deliverObservers()
        #expect(calls == 2, "seeded again")
    }

    @Test(arguments: OSPath.allCases) func anActionThatWritesDefersOnePassInsteadOfNesting(path: OSPath) {
        let s = sized(path)
        var depth = 0, maxDepth = 0, calls = 0
        _ = s.observers.addGeometry(TypedGeometryBox<CGFloat>(transform: { $0.contentOffset.y }, action: { _, new in
            depth += 1; maxDepth = max(maxDepth, depth); calls += 1
            if new == 40 { s.track(offset: CGPoint(x: 0, y: 60), zoom: 1) }
            depth -= 1
        }))
        s.deliverObservers()
        s.track(offset: CGPoint(x: 0, y: 40), zoom: 1)
        #expect(maxDepth == 1 && calls == 3 && s.peek.presentationOffset.y == 60)
    }

    // MARK: T2

    @Test(arguments: OSPath.allCases) func theOrderOfOneDelivery(path: OSPath) {
        let s = sized(path)
        let log = Log()
        let delegate = OrderDelegate(log)          // `delegate` is weak
        s.delegate = delegate
        defer { withExtendedLifetime(delegate) {} }
        _ = s.observers.addGeometry(TypedGeometryBox<CGPoint>(transform: { $0.contentOffset }, action: { _, _ in log.entries.append("geometry") }))
        _ = s.observers.addPhase(PhaseObserverBox { old, new, _ in log.entries.append("phase \(old)->\(new)") })
        let visible = VisibilityObserverBox(threshold: 0.5) { log.entries.append("visibility \($0)") }
        _ = s.observers.addVisibility(visible)
        visible.setFrame(CGRect(x: 0, y: 100, width: 100, height: 100))
        s.deliverObservers()
        log.entries.removeAll()
        // zoom + scroll + a phase change in one batch, delivered once
        s.batch(deferScroll: true) {
            s.track(offset: CGPoint(x: 0, y: 250), zoom: 1.5)       // visible 166...300: the frame leaves
            s.setPhase(.interacting)
        }
        s.deliverPending()
        #expect(log.entries == ["didZoom", "didScroll", "geometry", "visibility false", "phase idle->interacting"], "log: \(log.entries)")
    }

    @Test(arguments: OSPath.allCases) func phaseTransitionsAreQueuedAndNeverFireInitially(path: OSPath) {
        let s = sized(path)
        var seen: [String] = []
        var velocities: [CGVector?] = []
        _ = s.observers.addPhase(PhaseObserverBox { old, new, ctx in
            seen.append("\(old)->\(new)"); velocities.append(ctx.velocity)
            #expect(ctx.geometry == s.peekGeometry())
        })
        s.deliverObservers()
        #expect(seen.isEmpty)
        s.setPhase(.tracking); s.setPhase(.tracking)
        s.setPhase(.interacting)
        #expect(seen == ["idle->tracking", "tracking->interacting"])
        #expect(velocities.allSatisfy { $0 == nil }, "no motion running: velocity unknown")
    }

    // MARK: T5

    @Test func visibleFractionTable() {
        let v = CGRect(x: 0, y: 100, width: 100, height: 200)      // the visible rect, unscaled content space
        func f(_ r: CGRect) -> CGFloat { VisibilityMath.fraction(frame: r, in: v) }
        #expect(f(CGRect(x: 0, y: 150, width: 100, height: 50)) == 1)
        #expect(f(CGRect(x: 0, y: 50, width: 100, height: 100)) == 0.5)
        #expect(f(CGRect(x: 0, y: 0, width: 100, height: 100)) == 0, "touching edges only")
        #expect(f(CGRect(x: 0, y: 0, width: 100, height: 50)) == 0)
        #expect(f(CGRect(x: 0, y: 150, width: 0, height: 100)) == 0, "empty frame")
        #expect(f(CGRect(x: 0, y: 0, width: 100, height: 800)) == 0.25, "larger than the viewport")
        #expect(f(CGRect(x: 50, y: 250, width: 100, height: 100)) == 0.25)
        #expect(VisibilityMath.isVisible(frame: CGRect(x: 0, y: 0, width: 100, height: 800), in: v, threshold: 0.25))
        #expect(!VisibilityMath.isVisible(frame: CGRect(x: 0, y: 0, width: 100, height: 800), in: v, threshold: 0.5))
        #expect(!VisibilityMath.isVisible(frame: CGRect(x: 0, y: 0, width: 100, height: 800), in: v, threshold: 1), "never fully visible")
        #expect(VisibilityMath.isVisible(frame: CGRect(x: 0, y: 99, width: 100, height: 2), in: v, threshold: 0), "threshold 0: any area")
        #expect(!VisibilityMath.isVisible(frame: CGRect(x: 0, y: 0, width: 100, height: 100), in: v, threshold: 0), "threshold 0: edges alone do not count")
        #expect(VisibilityMath.isVisible(frame: CGRect(x: 0, y: 150, width: 100, height: 50), in: v, threshold: 7), "threshold clamps to 1")
        #expect(!VisibilityMath.isVisible(frame: .zero, in: v, threshold: 0))
    }

    @Test(arguments: OSPath.allCases) func visibilityFiresOnlyOnFlipsAndUsesTheUnscaledVisibleRect(path: OSPath) {
        let s = sized(path)
        var calls: [Bool] = []
        let box = VisibilityObserverBox(threshold: 0.5) { calls.append($0) }
        _ = s.observers.addVisibility(box)
        box.setFrame(CGRect(x: 0, y: 300, width: 100, height: 100))   // below the 200 pt viewport
        #expect(calls == [false], "initial: the current state, once")
        s.track(offset: CGPoint(x: 0, y: 60), zoom: 1)                 // visible 60...260: 0.0 of the frame
        s.track(offset: CGPoint(x: 0, y: 120), zoom: 1)                // 120...320: 0.2
        #expect(calls == [false])
        s.track(offset: CGPoint(x: 0, y: 200), zoom: 1)                // 200...400: 1.0
        #expect(calls == [false, true])
        s.track(offset: CGPoint(x: 0, y: 210), zoom: 1)
        #expect(calls == [false, true], "still visible: no call")
        // zoom 2: the same offset shows half the content (unscaled visible rect 105...205): the frame leaves
        s.track(offset: CGPoint(x: 0, y: 210), zoom: 2)
        #expect(calls == [false, true, false])
        // a layout change recomputes once
        box.setFrame(CGRect(x: 0, y: 150, width: 50, height: 100))   // the visible rect is 50 wide at zoom 2
        #expect(calls == [false, true, false, true])
        box.setFrame(CGRect(x: 0, y: 150, width: 50, height: 100))
        #expect(calls.count == 4)
    }

    // MARK: T6

    @Test func valueGeometryReadsWhatItWasGiven() {
        let g = ZTronScrollGeometry(contentOffset: CGPoint(x: 10, y: 20), contentSize: CGSize(width: 300, height: 900),
                                    contentInsets: EdgeInsets(top: 5, leading: 1, bottom: 6, trailing: 2),
                                    containerSize: CGSize(width: 100, height: 200), zoomScale: 2)
        #expect(g.contentOffset == CGPoint(x: 10, y: 20) && g.zoomScale == 2)
        #expect(g.contentSize == CGSize(width: 300, height: 900) && g.containerSize == CGSize(width: 100, height: 200))
        #expect(g.contentInsets == EdgeInsets(top: 5, leading: 1, bottom: 6, trailing: 2))
        #expect(g.phase == .idle)
        #expect(g == ZTronScrollGeometry(contentOffset: CGPoint(x: 10, y: 20), contentSize: CGSize(width: 300, height: 900),
                                         contentInsets: EdgeInsets(top: 5, leading: 1, bottom: 6, trailing: 2),
                                         containerSize: CGSize(width: 100, height: 200), zoomScale: 2))
        #expect(g != ZTronScrollGeometry(contentOffset: CGPoint(x: 10, y: 21), contentSize: CGSize(width: 300, height: 900),
                                         containerSize: CGSize(width: 100, height: 200)))
    }

    @Test func boundsAreScaledAndVisibleRectIsNot() {
        let g = ZTronScrollGeometry(contentOffset: CGPoint(x: 40, y: 80), contentSize: CGSize(width: 400, height: 900),
                                    containerSize: CGSize(width: 100, height: 200), zoomScale: 2)
        #expect(g.bounds == CGRect(x: 40, y: 80, width: 100, height: 200))
        #expect(g.visibleRect == CGRect(x: 20, y: 40, width: 50, height: 100))
        let flat = ZTronScrollGeometry(contentOffset: CGPoint(x: 40, y: 80), contentSize: CGSize(width: 400, height: 900),
                                       containerSize: CGSize(width: 100, height: 200))
        #expect(flat.bounds == flat.visibleRect)
    }

    @Test(arguments: OSPath.allCases) func aLiveGeometryHasBoundsToo(path: OSPath) {
        let s = sized(path)
        s.track(offset: CGPoint(x: 0, y: 30), zoom: 1)
        #expect(s.peekGeometry().bounds == CGRect(x: 0, y: 30, width: 100, height: 200))
    }

    @available(iOS 18, *)
    @Test func nativeRoundTripDropsTheZoom() {
        let g = ZTronScrollGeometry(contentOffset: CGPoint(x: 10, y: 20), contentSize: CGSize(width: 300, height: 900),
                                    contentInsets: EdgeInsets(top: 5, leading: 1, bottom: 6, trailing: 2),
                                    containerSize: CGSize(width: 100, height: 200), zoomScale: 3)
        let native = g.native
        #expect(native.contentOffset == CGPoint(x: 10, y: 20) && native.contentSize == CGSize(width: 300, height: 900))
        #expect(native.containerSize == CGSize(width: 100, height: 200))
        #expect(native.contentInsets == EdgeInsets(top: 5, leading: 1, bottom: 6, trailing: 2))
        let back = ZTronScrollGeometry(native)
        #expect(back.zoomScale == 1 && back.contentOffset == g.contentOffset && back.contentSize == g.contentSize)
        #expect(back.containerSize == g.containerSize && back.contentInsets == g.contentInsets)
        #expect(back.bounds == native.bounds)
    }
}
