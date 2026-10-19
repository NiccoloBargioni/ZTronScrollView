import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// `scrollTo(id:)` math and animation modes (M6 session 1, test 6). Viewport 100 x 200, content 300 x 900, so the
/// vertical bounds are 0...700 and the horizontal ones 0...200 (before insets and zoom).
@MainActor
@Suite(.serialized)
struct ScrollToTests {
    func make(_ path: OSPath, inset: EdgeInsets = EdgeInsets(), zoom: CGFloat = 1, offset: CGPoint = .zero)
        -> ZTronScrollState {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900),
                                   contentInset: inset, displayScale: 2))
        s.track(offset: offset, zoom: zoom)
        return s
    }

    /// Scrolls with `animation: nil` (the unanimated path) and reads where it landed.
    @discardableResult
    func land(_ s: ZTronScrollState, _ id: String, anchor: UnitPoint?) -> CGPoint {
        #expect(s.scrollTo(id: id, anchor: anchor, animation: nil, ambient: false))
        return s.peek.presentationOffset
    }

    let item = CGRect(x: 0, y: 400, width: 100, height: 100)

    // MARK: nil anchor: the minimal scroll

    @Test(arguments: OSPath.allCases) func nilAnchorScrollsJustEnoughFromAbove(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 0))
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 300))         // its bottom (500) meets the viewport bottom (200 + 300)
    }

    @Test(arguments: OSPath.allCases) func nilAnchorScrollsJustEnoughFromBelow(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 600))
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 400))         // its top meets the viewport top
    }

    @Test(arguments: OSPath.allCases) func nilAnchorLeavesAVisibleTargetAlone(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 350))
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 350))
        let t = make(path, offset: CGPoint(x: 0, y: 300))                    // exactly fitting at the bottom edge
        t.targets.register("a", frame: item)
        #expect(land(t, "a", anchor: nil) == CGPoint(x: 0, y: 300))
    }

    @Test(arguments: OSPath.allCases) func nilAnchorAlignsTheStartOfATargetLargerThanTheViewport(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 0))
        s.targets.register("a", frame: CGRect(x: 0, y: 400, width: 100, height: 300))
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 400))
        let t = make(path, offset: CGPoint(x: 0, y: 650))
        t.targets.register("a", frame: CGRect(x: 0, y: 400, width: 100, height: 300))
        #expect(land(t, "a", anchor: nil) == CGPoint(x: 0, y: 400))
    }

    @Test(arguments: OSPath.allCases) func nilAnchorMovesEachAxisIndependently(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 0))
        s.targets.register("a", frame: CGRect(x: 150, y: 20, width: 100, height: 50))       // right of the viewport, inside it vertically
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 150, y: 0))                         // x: 250 - 100
    }

    // MARK: anchors

    @Test(arguments: OSPath.allCases) func anchorsPlaceThePointOfTheTargetOnThePointOfTheViewport(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 0))
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: .top) == CGPoint(x: 0, y: 400))
        #expect(land(s, "a", anchor: .center) == CGPoint(x: 0, y: 350))                     // 400 + 50 - 100
        #expect(land(s, "a", anchor: .bottom) == CGPoint(x: 0, y: 300))
        #expect(land(s, "a", anchor: UnitPoint(x: 1, y: 0)) == CGPoint(x: 0, y: 400))       // x: 0 + 100 - 100
        #expect(land(s, "a", anchor: UnitPoint(x: 0.5, y: 0.25)) == CGPoint(x: 0, y: 400 + 25 - 50))
    }

    @Test(arguments: OSPath.allCases) func theResultIsClampedToTheBounds(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 300))
        s.targets.register("end", frame: CGRect(x: 0, y: 850, width: 100, height: 50))
        s.targets.register("start", frame: CGRect(x: 0, y: 10, width: 100, height: 50))
        #expect(land(s, "end", anchor: .top) == CGPoint(x: 0, y: 700))
        #expect(land(s, "end", anchor: nil) == CGPoint(x: 0, y: 700))
        #expect(land(s, "start", anchor: .center) == CGPoint(x: 0, y: 0))                   // 10 + 25 - 100 < 0
        s.targets.register("beyond", frame: CGRect(x: 0, y: 5000, width: 100, height: 50))
        #expect(land(s, "beyond", anchor: .top) == CGPoint(x: 0, y: 700))
    }

    // MARK: insets

    static let inset = EdgeInsets(top: 20, leading: 0, bottom: 30, trailing: 0)

    @Test(arguments: OSPath.allCases) func insetsShrinkTheVisibleArea(path: OSPath) {
        // Bounds -20...730; the unobscured area is 150 pt tall.
        let s = make(path, inset: Self.inset, offset: CGPoint(x: 0, y: -20))
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 330))                         // bottom 500 meets 200 - 30
        #expect(land(s, "a", anchor: .top) == CGPoint(x: 0, y: 380))                        // top lands under the top inset
        #expect(land(s, "a", anchor: .bottom) == CGPoint(x: 0, y: 330))
        #expect(land(s, "a", anchor: .center) == CGPoint(x: 0, y: 400 + 50 - 20 - 75))
        let t = make(path, inset: Self.inset, offset: CGPoint(x: 0, y: 600))
        t.targets.register("a", frame: item)
        #expect(land(t, "a", anchor: nil) == CGPoint(x: 0, y: 380))                         // 400 - 20
    }

    @Test(arguments: OSPath.allCases) func insetsMoveTheClampBounds(path: OSPath) {
        let s = make(path, inset: Self.inset, offset: CGPoint(x: 0, y: 300))
        s.targets.register("first", frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        s.targets.register("last", frame: CGRect(x: 0, y: 850, width: 100, height: 50))
        #expect(land(s, "first", anchor: .top) == CGPoint(x: 0, y: -20))
        #expect(land(s, "last", anchor: .bottom) == CGPoint(x: 0, y: 730))                  // 900 - 200 + 30
        s.targets.register("tiny-gap", frame: CGRect(x: 0, y: 5, width: 100, height: 50))
        #expect(land(s, "tiny-gap", anchor: .top) == CGPoint(x: 0, y: -15))
    }

    @Test(arguments: OSPath.allCases) func aTargetHiddenUnderTheTopInsetIsBroughtOut(path: OSPath) {
        let s = make(path, inset: Self.inset, offset: CGPoint(x: 0, y: 410))                // viewport shows 410...610, the inset hides 410...430
        s.targets.register("a", frame: item)
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 380))
    }

    // MARK: zoom

    @Test(arguments: OSPath.allCases) func zoomScalesTheFramesAndIsNeverChanged(path: OSPath) {
        // 2.5x: content 750 x 2250, bounds 0...650 and 0...2050; the frame 400...450 is drawn at 1000...1125.
        let s = make(path, zoom: 2.5, offset: .zero)
        s.targets.register("a", frame: CGRect(x: 0, y: 400, width: 40, height: 50))
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 925))                         // 1125 - 200
        #expect(land(s, "a", anchor: .top) == CGPoint(x: 0, y: 1000))
        #expect(land(s, "a", anchor: .center) == CGPoint(x: 0, y: 1000 + 62.5 - 100))
        #expect(s.zoomScale == 2.5 && s.peek.targetZoom == 2.5)
        s.targets.register("far", frame: CGRect(x: 280, y: 880, width: 20, height: 20))      // the end corner of the content
        #expect(land(s, "far", anchor: .top) == CGPoint(x: 650, y: 2050))
        #expect(s.zoomScale == 2.5)
    }

    @Test(arguments: OSPath.allCases) func aTargetLargerThanTheViewportOnlyBecauseOfZoomAlignsItsStart(path: OSPath) {
        let s = make(path, zoom: 2.5, offset: .zero)
        s.targets.register("a", frame: CGRect(x: 0, y: 400, width: 40, height: 100))        // 250 pt tall at 2.5x > 200
        #expect(land(s, "a", anchor: nil) == CGPoint(x: 0, y: 1000))
    }

    @Test(arguments: OSPath.allCases) func contentThatFitsStaysWhereItIs(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))                      // zooming on: small content is centered
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 100)))
        s.targets.register("a", frame: CGRect(x: 0, y: 20, width: 100, height: 20))
        #expect(land(s, "a", anchor: .bottom) == .zero)
        #expect(land(s, "a", anchor: nil) == .zero)
    }

    // MARK: motion and unknown ids

    @Test(arguments: OSPath.allCases) func anUnknownIDDoesNothing(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 100))
        #expect(!s.scrollTo(id: "nope", anchor: .top, animation: nil, ambient: false))
        #expect(!s.scrollTo(id: "nope", anchor: nil, animation: nil, ambient: true))
        #expect(s.peek.presentationOffset == CGPoint(x: 0, y: 100) && s.peek.targetOffset == CGPoint(x: 0, y: 100) && s.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func aKnownIDBeforeTheFirstLayoutIsHandledButMovesNothing(path: OSPath) {
        let s = makeState(path)
        s.targets.register("a", frame: item)
        #expect(s.scrollTo(id: "a", anchor: .top, animation: nil, ambient: false))
        #expect(s.peek.presentationOffset == .zero && s.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func aMotionWithoutAFingerStopsFirstAndTheMinimalScrollStartsWhereItStopped(path: OSPath) {
        let s = make(path, offset: CGPoint(x: 0, y: 0))
        s.targets.register("a", frame: item)
        s.setContentOffset(CGPoint(x: 0, y: 600), animated: true)
        s.now = { 100.2 }
        s.step(to: Date(timeIntervalSinceReferenceDate: 100.2))
        let stopped = s.peek.presentationOffset.y
        #expect(stopped > 330 && stopped < 400)                                              // in flight, with the item (400...500) inside the view
        #expect(s.scrollTo(id: "a", anchor: nil, animation: nil, ambient: false))
        #expect(s.peek.presentationOffset.y == stopped)                                      // minimal scroll: already visible, stays where it stopped
        #expect(s.phase == .idle && !s.isClockRunning)
    }

    // MARK: animation modes

    @Test(arguments: OSPath.allCases) func nilAnimationIsUnanimated(path: OSPath) {
        let s = make(path)
        s.targets.register("a", frame: item)
        s.scrollTo(id: "a", anchor: .top, animation: nil, ambient: false)
        let p = s.peek
        #expect(p.presentationOffset == CGPoint(x: 0, y: 400) && p.targetOffset == p.presentationOffset)
        #expect(s.phase == .idle && s.activeTransactionToken == nil && !s.isClockRunning)
    }

    @Test(arguments: OSPath.allCases) func uikitAnimationRunsOnTheClock(path: OSPath) {
        let s = make(path)
        s.targets.register("a", frame: item)
        s.scrollTo(id: "a", anchor: .top, animation: .uikit, ambient: false)
        #expect(s.phase == .animating && s.isScrollAnimating && s.isClockRunning && s.activeTransactionToken == nil)
        #expect(s.peek.targetOffset == CGPoint(x: 0, y: 400) && s.peek.presentationOffset == .zero)
        for i in 1...300 { s.step(to: Date(timeIntervalSinceReferenceDate: 100 + Double(i) / 60)) }
        #expect(abs(s.peek.presentationOffset.y - 400) < 0.5 && s.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func swiftUIAnimationAndTheAmbientTransactionTakeTheTransactionPath(path: OSPath) {
        let s = make(path)
        s.targets.register("a", frame: item)
        s.scrollTo(id: "a", anchor: .top, animation: .swiftUI(.linear(duration: 0.4)), ambient: false)
        #expect(s.activeTransactionToken != nil && s.phase == .animating)
        #expect(s.peek.targetOffset == CGPoint(x: 0, y: 400) && s.peek.presentationOffset == .zero)   // the effect interpolates
        let t = make(path)
        t.targets.register("a", frame: item)
        _ = withAnimation(.easeOut(duration: 0.4)) { t.scrollTo(id: "a", anchor: .top, animation: nil, ambient: true) }
        #expect(t.activeTransactionToken != nil && t.peek.targetOffset == CGPoint(x: 0, y: 400) && t.phase == .animating)
    }

    // MARK: hosted: the render path

    struct BodyProbe: View {
        let counts: BodyCount
        var body: some View {
            counts.bodies += 1
            return Color.clear.frame(height: 0)
        }
    }

    struct Column: View {
        let state: ZTronScrollState
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Color(white: CGFloat(i) / 10).frame(height: 100).ztronScrollID(i)
                    }
                    BodyProbe(counts: counts)
                }
            }
        }
    }

    @Test(arguments: OSPath.allCases) func hostedScrollToAnimatesOnlyInsideWithAnimationAndNeverRunsContentBodies(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never                                  // the hosting window has a top safe area
        let counts = BodyCount()
        let w = withOSPath(path) { host(Column(state: s, counts: counts)) }
        pump(0.2)
        #expect(s.targets.frames.count == 10)
        let bodies = counts.bodies
        // Ambient inside withAnimation: the effect interpolates (many frames), the content body never runs.
        ZTronRenderCounters.reset()
        _ = withAnimation(.linear(duration: 0.5)) { s.scrollTo(id: 6, anchor: .top, animation: nil, ambient: true) }
        pump(1.5)
        #expect(s.contentOffset.y == 600 && s.phase == .idle)
        #expect(ZTronRenderCounters.value("transform.effect") >= 10)
        // Unanimated: one jump.
        ZTronRenderCounters.reset()
        s.scrollTo(id: 2, anchor: .top, animation: nil, ambient: false)
        pump(0.3)
        #expect(s.contentOffset.y == 200 && s.phase == .idle)
        #expect(ZTronRenderCounters.value("transform.effect") < 10)
        // The state clock.
        ZTronRenderCounters.reset()
        s.scrollTo(id: 8, anchor: .top, animation: .uikit, ambient: false)
        pump(1.5)
        #expect(abs(s.contentOffset.y - 800) < 0.5 && s.phase == .idle && !s.isClockRunning)
        #expect(counts.bodies == bodies)
        unhost(w)
    }
}
