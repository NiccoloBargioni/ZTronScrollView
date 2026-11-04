import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// D79 (M8b-s8 s3, open item 33): a touch during the library's own SwiftUI-animated write (the D39 refresh reset: the
/// model is at rest at once while the content is drawn back) catches the content where it is DRAWN. The drawn-motion
/// window (`noteSwiftUIDrawnMotion()` / `drawnAway()`), the adoption in `interrupt(catching:)`, the catch at the
/// touch-down (the observer's, and the 17.x synthesized one with its rebase), the pinch's, the caught tap's lift (a caught
/// overscroll springs back, as after a tap on a bounce), and the pin's numbers.
@MainActor
@Suite(.serialized)
struct DrawnCatchTests {
    /// A view held at the top (hold 60), its action completed: the default `.swiftUI` reset cleared the hold inside
    /// `withAnimation` (the model is at rest) while the content is drawn at `y` (the content effect's probe).
    static func resetting(_ path: OSPath, drawnAt y: CGFloat = -40) async -> RefreshRig {
        let r = RefreshRig(path, configs: [.top: ZTronRefreshConfiguration(minimumVisibleTime: 0)])
        r.pullAndRelease(to: 140)
        await r.pumpTasks()
        r.settle()
        r.drawn(r.state.peek.presentationOffset.y)                    // the last frame drawn at the hold
        await r.completeAction()
        r.drawn(y)
        r.pan.effectsLog.removeAll()
        return r
    }

    static func setOffsets(_ log: [PanEffect]) -> [CGPoint] {
        log.compactMap { if case let .setOffset(p) = $0 { return p } else { return nil } }
    }

    // MARK: The window

    @Test(arguments: OSPath.allCases) func theResetOpensTheWindowAndTheDrawingReachingTheModelClosesIt(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -60)
        #expect(r.hold == EdgeInsets() && abs(r.state.peek.presentationOffset.y) < 0.5, "the model is at rest at once")
        #expect(r.state.phase == .idle, "no clock motion: SwiftUI draws the reset")
        #expect(r.state.drawnAway()?.offset == CGPoint(x: 0, y: -60))
        r.drawn(-30)
        #expect(r.state.drawnAway()?.offset == CGPoint(x: 0, y: -30), "the last drawn frame")
        #expect(r.state.drawnAway()?.zoom == 1)
        r.drawn(-0.4)
        #expect(r.state.drawnAway() == nil, "within 0.5 pt: the animation reached the model")
        r.drawn(-30)
        #expect(r.state.drawnAway() == nil, "the window closed: a later drawn / model difference is no drawn motion")
    }

    @Test(arguments: OSPath.allCases) func aRestingViewHasNoWindow(path: OSPath) {
        let r = RefreshRig(path)
        r.drawn(-12)                                                  // a steady difference (a slow-path clamp at rest)
        #expect(r.state.drawnAway() == nil)
        r.touchDown()
        r.drag(CGSize(width: 0, height: 10))
        #expect(!r.pan.effectsLog.contains(.catchMotion))
        #expect(Self.setOffsets(r.pan.effectsLog).first == CGPoint(x: 0, y: 0), "the drag starts from the model")
        #expect(r.state.catchSeq == 0 && r.state.catchPinRef == nil)
    }

    @Test(arguments: OSPath.allCases) func interventionsCloseTheWindow(path: OSPath) async {
        // The user or code moves the view.
        let closers: [(String, @MainActor (RefreshRig) -> Void)] = [
            ("a finger down that did not catch", { $0.state.beginTracking(); $0.state.endTracking() }),
            ("a drag write", { $0.state.beginTracking(); $0.state.writeDragOffset(CGPoint(x: 0, y: -10)); $0.state.endTracking() }),
            ("setContentOffset unanimated", { $0.state.setContentOffset(CGPoint(x: 0, y: 30), animated: false) }),
            ("setContentOffset animated", { $0.state.setContentOffset(CGPoint(x: 0, y: 300), animated: true) }),
            ("scroll(to:)", { $0.state.scroll(to: CGPoint(x: 0, y: 200)) }),
        ]
        for (name, close) in closers {
            let r = await Self.resetting(path)
            #expect(r.state.drawnAway() != nil, "\(name): open")
            close(r)
            r.settle()
            r.drawn(-40)
            #expect(r.state.drawnAway() == nil, "\(name) closes the window")
        }
        let r = await Self.resetting(path)
        r.state.stopScrollingAndZooming()
        r.drawn(-38)                                                  // the next frame of the reset (the probe was reset)
        #expect(r.state.drawnAway() != nil, "stopScrollingAndZooming() leaves the drawn reset alone")
        #expect(abs(r.state.peek.presentationOffset.y) < 0.5 && r.state.catchSeq == 0 && r.state.catchPinRef == nil)
    }

    @Test(arguments: OSPath.allCases) func noDrawnMotionWhileADragAMotionATokenOrAResizeRuns(path: OSPath) async {
        // Each guard on its own: the window re-opened after what it guards began.
        do {
            let r = await Self.resetting(path)
            r.state.beginTracking()
            r.state.noteSwiftUIDrawnMotion()
            r.drawn(-40)
            #expect(r.state.drawnAway() == nil, "tracking (the finger that is down caught or did not, at its touch-down)")
        }
        do {
            let r = await Self.resetting(path)
            r.state.setContentOffset(CGPoint(x: 0, y: 300), animated: true)
            #expect(r.state.phase == .animating)
            r.state.noteSwiftUIDrawnMotion()
            r.drawn(-40)
            #expect(r.state.drawnAway() == nil, "a clock motion")
        }
        do {
            let r = await Self.resetting(path)
            r.state.scroll(to: CGPoint(x: 0, y: 200))
            r.state.noteSwiftUIDrawnMotion()
            r.drawn(-40)
            #expect(r.state.drawnAway() == nil, "a transaction token")
        }
        do {
            let r = await Self.resetting(path)
            r.state.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 700), safeArea: EdgeInsets()))
            r.state.noteSwiftUIDrawnMotion()
            r.drawn(-40, size: CGSize(width: 390, height: 700))
            #expect(r.state.drawnAway() == nil, "an open resize")
        }
        do {
            let r = await Self.resetting(path)
            r.drawn(-40, size: CGSize(width: 390, height: 798))
            #expect(r.state.drawnAway() == nil, "drawn at another viewport size")
            r.drawn(-40, size: CGSize(width: 390.5, height: 800.5))
            #expect(r.state.drawnAway() != nil, "within a pixel of the viewport: the same size")
            r.drawn(-40, zoom: 1.01)
            #expect(r.state.drawnAway() == nil, "drawn at another zoom")
            r.drawn(-40)
            #expect(r.state.drawnAway() != nil, "the zoom and size mismatches do not close the window")
        }
    }

    // MARK: The catch

    @Test(arguments: OSPath.allCases) func theTouchDownCatchesTheContentWhereItIsDrawn(path: OSPath) async {
        // 18+ / 15-16: the observer's touch-down comes before the recognition.
        let r = await Self.resetting(path, drawnAt: -40)
        r.touchDown()
        #expect(r.pan.effectsLog.first == .catchMotion, "a touch during the drawn reset is a catch")
        #expect(r.state.peek.presentationOffset == CGPoint(x: 0, y: -40) && r.state.peek.targetOffset == CGPoint(x: 0, y: -40),
                "the model is the drawn state")
        #expect(r.state.catchLocksContent, "the content is locked for this touch, as under a clock catch")
        #expect(r.state.catchSeq == 1 && r.state.catchPinRef == CatchPin.Ref(seq: 1, pin: r.state.catchPin))
        #expect(r.state.drawnAway() == nil, "the catch closes the window")
        #expect(r.state.lastInterruptedVelocity == .zero)
        r.drag(CGSize(width: 0, height: 10))                            // the recognition sample (the hysteresis)
        let first = Self.setOffsets(r.pan.effectsLog).first
        #expect(first.map { abs($0.y + 40) < 1e-6 && $0.x == 0 } == true, "the drag starts where it was caught: \(String(describing: first))")
        r.drag(CGSize(width: 0, height: 20))
        #expect(r.state.peek.presentationOffset.y < -40, "the finger pulls on from there")
        r.drag(CGSize(width: 0, height: 10))
        #expect(abs(r.state.peek.presentationOffset.y + 40) < 1e-6, "back where the finger caught it")
    }

    @Test(arguments: OSPath.allCases) func theSynthesizedTouchDownCatchesAndRecognizesFromTheCaught(path: OSPath) async {
        // 17.x: no touch-down before the recognition. The synthesized one catches and recognizes in one call: the
        // recognition's write (from the baseline taken before the catch: the model, at rest) becomes the caught
        // presentation, and the drag is rebased on it.
        let r = await Self.resetting(path, drawnAt: -40)
        r.drag(CGSize(width: 0, height: 14))
        #expect(r.pan.effectsLog.first == .catchMotion)
        let writes = Self.setOffsets(r.pan.effectsLog)
        #expect(writes.first.map { abs($0.y + 40) < 1e-6 && $0.x == 0 } == true,
                "the first write is the caught presentation, not the stale baseline's: \(writes)")
        #expect(abs(r.state.peek.presentationOffset.y + 40) < 1e-6 && r.state.catchSeq == 1)
        r.pan.effectsLog.removeAll()
        r.drag(CGSize(width: 0, height: 24))
        let next = Self.setOffsets(r.pan.effectsLog)
        #expect(next.first.map { $0.y < -40 && $0.y > -50 } == true, "10 pt more finger, rubber-banded from the caught: \(next)")
        r.drag(CGSize(width: 0, height: 14))
        #expect(abs(r.state.peek.presentationOffset.y + 40) < 1e-6, "back where the finger caught it")
    }

    @Test(arguments: OSPath.allCases) func aCaughtTapSpringsTheResetBackAtTheLift(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -40)
        r.touchDown()
        r.tick(3)
        #expect(r.state.catchLocksContent && r.state.catchSeq == 1)
        #expect(abs(r.state.peek.presentationOffset.y + 40) < 1e-6, "held where it was drawn while the finger is down")
        r.delegate.log.removeAll()
        r.pan.handle(.touchesEnded(time: r.now))
        #expect(r.state.phase == .decelerating && !r.state.catchLocksContent, "the lift springs the caught overscroll back")
        r.tick()
        #expect(r.state.peek.presentationOffset.y > -40 && r.state.peek.presentationOffset.y < 0, "on its way to rest")
        r.settle()
        #expect(abs(r.state.peek.presentationOffset.y) < 0.5 && r.state.phase == .idle, "at rest")
        #expect(r.hold == EdgeInsets())
    }

    @Test(arguments: OSPath.allCases) func aTapOnABounceSpringsItBackAtTheLiftAndInBoundsStaysPut(path: OSPath) {
        // A clock bounce caught by a tap was left overscrolled (the lift only ended the tracking); UIKit bounces it back.
        let r = RefreshRig(path, configs: [:])
        let rest = r.state.peek.presentationOffset.y
        r.touchDown()
        r.finger(toPull: 40)
        r.lift()
        r.tick(3)
        #expect(r.state.phase == .decelerating && r.state.peek.presentationOffset.y < rest - 10, "the bounce back runs")
        r.touchDown()
        #expect(r.pan.effectsLog.contains(.catchMotion) && r.state.catchSeq == 0, "a clock catch: no pin")
        let caught = r.state.peek.presentationOffset.y
        r.tick(2)
        #expect(r.state.peek.presentationOffset.y == caught, "held under the finger")
        r.pan.handle(.touchesEnded(time: r.now))
        #expect(r.state.phase == .decelerating, "the lift springs it back")
        r.settle()
        #expect(abs(r.state.peek.presentationOffset.y - rest) < 0.5 && r.state.phase == .idle, "at rest")
        // In bounds: a tap on a deceleration leaves the content where it caught it.
        r.state.setContentOffset(CGPoint(x: 0, y: 1200), animated: true)
        r.tick(10)
        r.touchDown()
        let held = r.state.peek.presentationOffset
        r.tick()
        r.pan.handle(.touchesEnded(time: r.now))
        #expect(r.state.phase == .idle && r.state.peek.presentationOffset == held && !r.state.isClockRunning)
    }

    @Test(arguments: OSPath.allCases) func aPinchCatchesTheResetAndZoomsFromWhereItWasDrawn(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -40)
        r.state.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        r.drawn(-40)
        let centre = CGPoint(x: 195, y: 300)
        r.pan.handlePinch(.began(centroid: centre, time: r.now))
        #expect(r.pan.pinchLog.first == .catchMotion && r.state.catchSeq == 1)
        #expect(r.state.peek.presentationOffset == CGPoint(x: 0, y: -40), "caught where it was drawn")
        r.pan.handlePinch(.changed(magnification: 1, centroid: centre, time: r.now))
        #expect(abs(r.state.peek.presentationOffset.y + 40) < 1e-6 && abs(r.state.peek.presentationZoom - 1) < 1e-9,
                "the first sample zooms from the caught presentation: \(r.state.peek.presentationOffset)")
    }

    @Test(arguments: OSPath.allCases) func aClockCatchIsUnchanged(path: OSPath) {
        let r = RefreshRig(path)
        r.state.setContentOffset(CGPoint(x: 0, y: 1200), animated: true)
        r.tick(10)
        #expect(r.state.phase == .animating)
        let at = r.state.peek.presentationOffset
        r.drag(CGSize(width: 0, height: 10))                            // the synthesized touch-down catches the clock
        #expect(r.pan.effectsLog.first == .catchMotion)
        let writes = Self.setOffsets(r.pan.effectsLog)
        #expect(writes.first.map { abs($0.y - at.y) < 1e-6 } == true, "stopped where it was presented: \(writes) / \(at)")
        #expect(r.state.catchSeq == 0 && r.state.catchPinRef == nil, "no pin for a clock catch")
    }

    // MARK: The pin's numbers

    @Test(arguments: OSPath.allCases) func thePinHoldsFromADrawnCatchToTheLibrarysNextSwiftUIWrite(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -40)
        #expect(r.state.catchPinRef == nil, "no catch yet")
        r.touchDown()
        r.drag(CGSize(width: 0, height: 10))
        let ref = r.state.catchPinRef
        #expect(ref?.seq == 1)
        r.lift()
        r.settle()
        #expect(abs(r.state.peek.presentationOffset.y) < 0.5, "the lift returned the content to rest")
        #expect(r.state.catchPinRef == ref, "finger and clock writes keep it (each effect ends its own latch)")
        r.state.noteSwiftUIDrawnMotion()
        #expect(r.state.catchPinRef == nil, "the library's next SwiftUI-animated write is drawn")
        #expect(r.state.clearSeq == 2)
        r.drawn(-25)
        r.touchDown()
        r.drag(CGSize(width: 0, height: 10))
        #expect(r.state.catchSeq == 3 && r.state.catchPinRef?.seq == 3, "a new catch, a new number: every latch starts again")
        r.lift()
        r.settle()
        r.state.scroll(to: CGPoint(x: 0, y: 100))
        #expect(r.state.catchPinRef == nil, "a transaction scroll is drawn by its own animation")
    }

    // MARK: 17+: the catch ends the reset (`CatchableResetAnimation`)

    @Test(arguments: OSPath.allCases) func aDrawnCatchCutsTheResetsAnimationOn17(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -40)
        let reset = await withOSPath(path) { r.state.catchable(.easeOut(duration: 4)) }
        guard #available(iOS 17, *) else {
            #expect(reset == .easeOut(duration: 4), "15-16: the reset as it is (the pin alone)")
            return
        }
        let token = (reset.base as? CatchableResetAnimation)?.token
        #expect((token != nil) == (path == .preferred), "17+ wraps the open window's reset; the forced fallback keeps it")
        #expect(token?.isCut != true, "drawn as the base animation until a catch")
        #expect(await withOSPath(path) { (r.state.catchable(.linear(duration: 1)).base as? CatchableResetAnimation)?.token }
                === token, "one token per window: every animation of the reset is cut together")
        r.touchDown()
        #expect(r.state.catchSeq == 1)
        #expect(token.map { $0.isCut } != false, "the drawn catch cuts it: SwiftUI drops the rest at its next frame")
        let after = await withOSPath(path) { r.state.catchable(.easeOut(duration: 4)) }
        #expect(!(after.base is CatchableResetAnimation), "no window, no wrapping")
    }

    @Test(arguments: OSPath.allCases) func aTouchThatDoesNotCatchLeavesTheResetDrawn(path: OSPath) async {
        let r = await Self.resetting(path, drawnAt: -40)
        let reset = await withOSPath(path) { r.state.catchable(.easeOut(duration: 4)) }
        guard #available(iOS 17, *), let token = (reset.base as? CatchableResetAnimation)?.token else { return }
        r.state.scroll(to: CGPoint(x: 0, y: 100))                 // code moves the view: the window closes, no catch
        #expect(r.state.drawnAway() == nil)
        #expect(!token.isCut, "only a drawn catch ends the reset")
    }

    // MARK: Hosted (S4): a catch runs no content body

    @Test(arguments: OSPath.allCases) func aDrawnCatchRunsNoContentBodyAndOneHostBodyPerWrite(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }.refresher(style: .default) { })
        }
        defer { unhost(w) }
        s.beginRefreshing(edge: .top)
        pump(1.0)
        s.endRefreshing(edge: .top)
        pump(0.08)                                               // a few frames into the default 0.3 s SwiftUI reset
        guard s.drawnAway() != nil else { Issue.record("no drawn reset to catch (\(path))"); return }
        let base = counts.bodies
        ZTronRenderCounters.reset()
        s.interrupt(catching: true)
        #expect(s.catchSeq == 1, "a drawn catch")
        for _ in 0..<10 { s.track(offset: CGPoint(x: 0, y: s.peek.presentationOffset.y - 2), zoom: 1); pump(0.03) }
        pump(0.2)
        #expect(counts.bodies == base, "content.body 0 across the catch and the drag after it (S4)")
        #expect(counts.ids.count == 1 && counts.appears == 1, "the same content")
        let hosts = ZTronRenderCounters.value("transformHost.body")
        #expect(hosts >= 10 && hosts <= 12, "one host body per model write, as without a catch (+1 for the catch): \(hosts)")
    }
}

extension RefreshRig {
    /// The content effect drew `y` (its probe), at the viewport's size unless `size` says otherwise.
    func drawn(_ y: CGFloat, zoom: CGFloat = 1, size: CGSize? = nil) {
        state.probe.record(CGPoint(x: 0, y: y), zoom, size: size ?? viewport)
    }
}
