import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// Pinch + pan interplay through the coordinator with synthetic two-touch sequences (18+ semantics: the spatial
/// observer reports the true centroid; docs/design/PHYSICS-calibration.md "Pinch + pan"). UIScrollView semantics:
/// the content point under the centroid stays under it while the centroid moves and the scale changes; the one-finger
/// drag never also moves the content; a pinch begun mid-pan and a one-finger lift continue without a jump; both fingers
/// up never fling.
@MainActor
@Suite(.serialized)
struct PinchPanTests {
    final class Clock { var t: TimeInterval = 100 }
    /// The adapter's `Began` flag: the magnify gesture reports `.began` once before its first `.changed`.
    final class GestureBox { var began = false }
    @MainActor struct Rig {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ZoomDelegate
        let clock: Clock
        let gesture = GestureBox()
        var now: TimeInterval {
            get { clock.t }
            nonmutating set { clock.t = newValue }
        }
        func geometry() -> ZoomGeometry { state.makeZoomGeometry() }
        /// Unscaled content point under viewport point `p` right now.
        func under(_ p: CGPoint) -> CGPoint {
            ZoomSolver.contentPoint(under: p, offset: state.contentOffset, scale: state.zoomScale, geometry: geometry())
        }
        func tick() { now += 1.0 / 60; state.step(to: Date(timeIntervalSinceReferenceDate: now)) }
    }

    func make(_ path: OSPath = .preferred, limits: ClosedRange<CGFloat> = 1...3) -> Rig {
        let s = makeState(path)
        let d = ZoomDelegate()
        s.delegate = d
        let clock = Clock()
        s.now = { clock.t }
        s.zoomLimits = ZoomLimits(min: .absolute(limits.lowerBound), max: .absolute(limits.upperBound))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 200, height: 400), contentSize: CGSize(width: 2000, height: 4000), displayScale: 2))
        s.track(offset: CGPoint(x: 500, y: 1000), zoom: 1)
        d.log.removeAll()
        let c = withOSPath(path) { PanCoordinator(state: s, axes: [.horizontal, .vertical]) }
        c.pinch.centroidSource = .spatial
        return Rig(state: s, coord: c, delegate: d, clock: clock)
    }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // Spatial observer + gestures as the adapters deliver them.
    func twoFingersDown(_ r: Rig, at c: CGPoint) {
        r.coord.handle(.touchDown(location: c, time: r.now, touchCount: 2))
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
    }
    func centroid(_ r: Rig, _ c: CGPoint) { r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now)) }
    /// A magnify-gesture sample as the adapter delivers it: `.began` once per gesture, then `.changed`.
    func magnify(_ r: Rig, _ m: CGFloat, at c: CGPoint) {
        if !r.gesture.began {
            r.gesture.began = true
            r.coord.handlePinch(.began(centroid: c, time: r.now))
        }
        r.coord.handlePinch(.changed(magnification: m, centroid: c, time: r.now))
    }

    // MARK: 1. scale only

    @Test func scaleOnlyKeepsTheContentPointUnderTheCentroid() {
        let r = make()
        let c = CGPoint(x: 60, y: 150)
        twoFingersDown(r, at: c)
        let u = r.under(c)
        for m in [1.1, 1.3, 1.7, 2.2, 2.6] as [CGFloat] {
            magnify(r, m, at: c); r.tick()
            #expect(abs(r.state.zoomScale - m) < 1e-9)
            #expect(Self.dist(r.under(c), u) < 0.5, "m = \(m)")
        }
    }

    // MARK: 2. translate only (no magnification change: the magnify gesture may stay silent)

    @Test func twoFingerTranslateFollowsTheCentroidOneToOne() {
        let r = make()
        let c0 = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c0)
        magnify(r, 1.5, at: c0); r.tick()
        let u = r.under(c0)
        let o0 = r.state.contentOffset
        var c = c0
        for d in [CGVector(dx: -8, dy: -20), CGVector(dx: -12, dy: -25), CGVector(dx: 5, dy: -30)] {
            c = CGPoint(x: c.x + d.dx, y: c.y + d.dy)
            centroid(r, c)
            // Immediate (no clock tick needed) and exact: the offset moved by −Δcentroid.
            #expect(Self.dist(r.under(c), u) < 0.5)
            #expect(abs(r.state.contentOffset.x - o0.x - (c0.x - c.x)) < 1e-6)
            #expect(abs(r.state.contentOffset.y - o0.y - (c0.y - c.y)) < 1e-6)
            r.tick()
        }
        #expect(abs(r.state.zoomScale - 1.5) < 1e-9)
    }

    @Test func twoFingersMovingBeforeTheMagnifyGestureRecognizesPanTheContent() {
        let r = make()
        let c0 = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c0)
        let u = r.under(c0)
        let o0 = r.state.contentOffset
        centroid(r, CGPoint(x: 100, y: 196))            // under the 10 pt centroid hysteresis: nothing moves
        #expect(r.state.contentOffset == o0)
        centroid(r, CGPoint(x: 100, y: 170))
        #expect(abs(r.state.contentOffset.y - (o0.y + 30)) < 1e-6 && r.state.contentOffset.x == o0.x)
        #expect(Self.dist(r.under(CGPoint(x: 100, y: 170)), u) < 0.5)
        #expect(r.state.isZooming && r.state.zoomScale == 1)
    }

    // MARK: 3. scale + translate

    @Test func scaleAndTranslateTogetherKeepTheAnchor() {
        let r = make()
        var c = CGPoint(x: 80, y: 120)
        twoFingersDown(r, at: c)
        let u = r.under(c)
        var m: CGFloat = 1
        for i in 0..<12 {
            m += 0.12
            c = CGPoint(x: c.x + 3, y: c.y + (i % 2 == 0 ? -9 : -4))
            if i % 3 == 0 { centroid(r, c) }            // centroid-only event between magnify events
            magnify(r, m, at: c)
            r.tick()
            #expect(Self.dist(r.under(c), u) < 0.5, "step \(i)")
        }
    }

    // MARK: 4. pan → pinch → pan, no double application, no jump

    @Test func pinchBegunMidPanDoesNotJumpAndThePanDoesNotAlsoMove() {
        let r = make()
        let start = CGPoint(x: 100, y: 300)
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: start, time: r.now))
        r.tick()
        let beforePinch = r.state.contentOffset
        #expect(beforePinch.y == 1030)                   // 40 − 10 hysteresis
        // Second finger lands: the pinch begins at the centroid of both touches; the drag keeps reporting.
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        #expect(r.state.contentOffset == beforePinch, "no jump when the pinch begins")
        let u = r.under(c)
        magnify(r, 1.4, at: c); r.tick()
        let pinched = r.state.contentOffset
        #expect(Self.dist(r.under(c), u) < 0.5)
        // The one-finger DragGesture keeps moving (it is one of the two fingers): it must not move the content.
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -140), startLocation: start, time: r.now))
        r.tick()
        #expect(r.state.contentOffset == pinched, "pan translation not applied on top of the pinch")
        // Centroid moves with the fingers: only the pinch moves the content, exactly by −Δcentroid.
        let c2 = CGPoint(x: 100, y: 150)
        centroid(r, c2)
        #expect(abs(r.state.contentOffset.y - (pinched.y + 50)) < 1e-6 && r.state.contentOffset.x == pinched.x)
        // One finger lifts: the pan continues from the remaining finger without a jump.
        let remaining = CGPoint(x: 100, y: 120)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        let afterLift = r.state.contentOffset
        #expect(!r.state.isZooming && r.state.zoomScale == 1.4)
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -140), startLocation: start, time: r.now))
        #expect(r.state.contentOffset == afterLift, "same translation as the last one: nothing moves")
        r.now += 0.016
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -170), startLocation: start, time: r.now))
        #expect(abs(r.state.contentOffset.y - (afterLift.y + 30)) < 1e-6, "then 1:1 from where the content is")
        // That remaining finger can still fling: from the speed of its own movement since the hand-off.
        r.now += 0.016
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -200), startLocation: start, time: r.now))
        r.now += 0.016
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -230), time: r.now, fallbackVelocity: nil))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(r.state.isDecelerating)
    }

    @Test func oneFingerLiftWhenTheDragGestureDiedContinuesFromTheSpatialFinger() {
        let r = make()
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 2, at: c); r.tick()
        let remaining = CGPoint(x: 120, y: 240)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        let o = r.state.contentOffset
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 200), time: r.now)
        #expect(abs(r.state.contentOffset.y - (o.y + 40)) < 1e-6 && r.state.contentOffset.x == o.x)
        #expect(abs(r.state.zoomScale - 2) < 1e-9)
    }

    // MARK: 5. both fingers up: zoom bounce / settle, never a pan fling

    @Test func releasingBothFingersNeverFlings() {
        let r = make()
        let start = CGPoint(x: 100, y: 300)
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: start, time: r.now))
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        magnify(r, 1.5, at: c); r.tick()
        // Fast two-finger movement right before the lift (the drag reports it at speed).
        for i in 1...4 {
            r.now += 0.016
            r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40 - CGFloat(i) * 40), startLocation: start, time: r.now))
            centroid(r, CGPoint(x: 100, y: 200 - CGFloat(i) * 40))
        }
        let o = r.state.contentOffset
        // Magnify ends first, then the drag, then the spatial observer reports no fingers (any order must hold).
        r.coord.handlePinch(.ended(time: r.now))
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -200), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.state.isDecelerating && r.state.phase == .idle)
        #expect(r.state.contentOffset == o)
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
        #expect(r.delegate.log.contains("didEndDragging(false)"))
    }

    @Test func panReleaseDoesNotCancelTheZoomBounce() {
        let r = make(limits: 1...2)
        let start = CGPoint(x: 100, y: 300)
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: start, time: r.now))
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        magnify(r, 3, at: c); r.tick()                  // past the limit (resisted)
        #expect(r.state.zoomScale > 2)
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        #expect(r.state.isZoomBouncing)
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -200), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(r.state.isZoomBouncing && !r.state.isDecelerating)
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        #expect(abs(r.state.zoomScale - 2) < 1e-9 && r.state.phase == .idle)
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
    }

    // MARK: 6. staggered lift: one finger up, the other a few ms later (how real fingers leave the glass; criterion C)

    /// The DragGesture died on the second finger (R1): the pan restarted from the remaining finger has no DragGesture
    /// to end it. The last finger up must end the sequence: nothing tracks, nothing moves afterwards, the clock stops.
    @Test(arguments: OSPath.allCases) func lastFingerUpEndsTheSynthesizedPanAndNothingMovesAfterIt(path: OSPath) {
        let r = make(path)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 2, at: c); r.tick()
        r.now += 0.016
        let remaining = CGPoint(x: 120, y: 240)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        #expect(!r.state.isZooming && abs(r.state.zoomScale - 2) < 1e-9)
        // The remaining finger jitters under a point while leaving (the pan follows it 1:1: that is finger motion;
        // a full point per frame is 62 pt/s, a pan that decelerates like any one-finger pan) …
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120.5, y: 240.5), time: r.now)
        // … then lifts: the observer reports no fingers; no DragGesture event will ever come.
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.coord.isSequenceActive, "the sequence is over")
        #expect(!r.state.isTracking && !r.state.isDragging && !r.state.isDecelerating)
        #expect(r.state.phase == .idle && !r.state.isClockRunning)
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
        let rest = r.state.contentOffset
        r.delegate.log.removeAll()
        for _ in 0..<60 { r.tick() }
        #expect(r.state.contentOffset == rest && abs(r.state.zoomScale - 2) < 1e-9)
        #expect(r.delegate.log.isEmpty, "no motion after the last finger left: \(r.delegate.log)")
    }

    /// The DragGesture survived and follows the finger that leaves last. Its pinch-phase samples (one finger of a
    /// spread, at speed) are not a pan: a lift a few ms after the hand-off never flings, neither from the tracker nor
    /// from the gesture's own velocity.
    @Test(arguments: OSPath.allCases) func liftRightAfterTheHandOffDoesNotFlingFromThePinchVelocity(path: OSPath) {
        let r = make(path)
        let start = CGPoint(x: 100, y: 300)
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: start, time: r.now))
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        magnify(r, 1.5, at: c); r.tick()
        // Fast spread right before the lift: the drag's finger moves at 2500 pt/s.
        var t = CGSize(width: 0, height: -40)
        for i in 1...4 {
            r.now += 0.016
            t = CGSize(width: 0, height: -40 - CGFloat(i) * 40)
            r.coord.handle(.dragChanged(translation: t, startLocation: start, time: r.now))
            centroid(r, CGPoint(x: 100, y: 200 - CGFloat(i) * 20))
        }
        // The other finger lifts; the drag's finger stays 20 ms more without moving, then lifts.
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 100, y: 100), time: r.now))
        let o = r.state.contentOffset
        r.now += 0.02
        r.coord.handle(.dragEnded(translation: t, time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.state.isDecelerating && r.state.phase == .idle && !r.state.isTracking)
        #expect(Self.dist(r.state.contentOffset, o) <= 0.25, "at most the pixel snap")
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
        #expect(abs(r.state.zoomScale - 1.5) < 1e-9)
    }

    /// Released past the limit with one finger still down: the bounce keeps running (the hand-off is not a new finger
    /// landing on moving content), settles at the limit, and only then does the pan continue from that finger, from
    /// where the bounce settled.
    @Test(arguments: OSPath.allCases) func handOffDuringAZoomBounceKeepsTheBounce(path: OSPath) {
        let r = make(path, limits: 1...2)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 3, at: c); r.tick()                  // past the limit (resisted)
        #expect(r.state.zoomScale > 2)
        let remaining = CGPoint(x: 120, y: 240)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        #expect(r.state.isZoomBouncing && r.state.phase == .decelerating, "the hand-off must not catch the bounce")
        // The finger drifts during the bounce: the bounce owns the offset.
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 230), time: r.now)
        #expect(r.state.isZoomBouncing)
        while r.state.isZoomBouncing && r.now < 110 { r.tick() }
        #expect(abs(r.state.zoomScale - 2) < 1e-9 && r.delegate.log.contains("didEndZooming(2.0)"))
        // Still down: the pan continues 1:1 from where the bounce settled (the drift during it is not replayed).
        let o = r.state.contentOffset
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 200), time: r.now)
        #expect(Self.dist(r.state.contentOffset, o) < 1e-6, "the first sample after the bounce is the new zero")
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 170), time: r.now)
        #expect(abs(r.state.contentOffset.y - (o.y + 30)) < 1e-6 && r.state.contentOffset.x == o.x)
        r.now += 0.5
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(r.state.phase == .idle && !r.state.isTracking && !r.coord.isSequenceActive)
    }

    /// The last finger leaves while the bounce still runs: the sequence ends, the bounce finishes by itself.
    @Test(arguments: OSPath.allCases) func lastFingerUpDuringTheBounceLetsItSettle(path: OSPath) {
        let r = make(path, limits: 1...2)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 3, at: c); r.tick()
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 120, y: 240), time: r.now))
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(r.state.isZoomBouncing && !r.state.isTracking && !r.coord.isSequenceActive)
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        #expect(abs(r.state.zoomScale - 2) < 1e-9 && r.state.phase == .idle)
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
        // A later single finger pans normally.
        let o = r.state.contentOffset
        let s = CGPoint(x: 100, y: 300)
        r.coord.handle(.touchDown(location: s, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: s, time: r.now))
        #expect(abs(r.state.contentOffset.y - (o.y + 30)) < 1e-6)
    }

    /// The DragGesture followed the remaining finger but had not passed its hysteresis when the other finger lifted
    /// (anchor-thumb pinch): it recognizes under the synthesized pan. It takes over without a jump and its own
    /// velocity at the lift is not used.
    @Test(arguments: OSPath.allCases) func lateDragGestureUnderASynthesizedPanTakesOverWithoutAJump(path: OSPath) {
        let r = make(path)
        let landing = CGPoint(x: 100, y: 300)              // the thumb's touch-down, long before the pinch
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 2, at: c); r.tick()
        let remaining = CGPoint(x: 100, y: 296)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 100, y: 292), time: r.now)
        let o = r.state.contentOffset
        // The real drag recognizes: its translation is relative to the landing point, not to the hand-off.
        r.now += 0.016
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -12), startLocation: landing, time: r.now))
        #expect(Self.dist(r.state.contentOffset, o) < 1e-6, "no jump when the drag takes over")
        r.now += 0.016
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -42), startLocation: landing, time: r.now))
        #expect(abs(r.state.contentOffset.y - (o.y + 30)) < 1e-6, "then 1:1")
        // A pause, then the lift: the gesture's own velocity is ignored, the tracker says rest.
        r.now += 0.1
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -42), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -5000)))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.state.isDecelerating && r.state.phase == .idle && !r.coord.isSequenceActive)
        #expect(!r.delegate.log.contains("willBeginDecelerating"))
    }

    /// The DragGesture followed the finger that lifted first and reports its end after the hand-off: stale. The
    /// synthesized pan goes on from the remaining finger and ends on its lift.
    @Test(arguments: OSPath.allCases) func staleDragEndUnderASynthesizedPanIsIgnored(path: OSPath) {
        let r = make(path)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 2, at: c); r.tick()
        let remaining = CGPoint(x: 120, y: 240)
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: remaining, time: r.now))
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 220), time: r.now)
        let o = r.state.contentOffset
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -150), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -3000)))
        #expect(r.state.contentOffset == o && r.state.isTracking && r.coord.isSequenceActive, "stale end ignored")
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 200), time: r.now)
        #expect(abs(r.state.contentOffset.y - (o.y + 20)) < 1e-6)
        r.now += 0.1
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.state.isDecelerating && r.state.phase == .idle && !r.coord.isSequenceActive)
    }

    // MARK: 7. overscroll at the one-finger lift (D23): the pan holds it, nothing springs back under a finger

    /// Two-finger pan past the edge (rubber-banded under the pinch like a one-finger drag, D24), then one finger lifts
    /// with the scale in range: no bounce, no snap. The remaining finger pans on from the same rubber band (the pan
    /// inverts it: no jump), and only its lift springs the content back into bounds.
    @Test(arguments: OSPath.allCases) func oneFingerLiftKeepsTheOverscrollInThePanInsteadOfSnappingBack(path: OSPath) {
        let r = make(path)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 1.5, at: c); r.tick()
        let moved = CGPoint(x: 1000, y: 200)                 // both fingers slide right by 900 pt: 100 pt past the edge
        centroid(r, moved)
        let band = RubberBand(dimension: 200)                // the pan's band: viewport width, c 0.55
        let displaced = band.displacement(forOverscroll: -100)   // −43.1 pt, not −100
        #expect(abs(r.state.contentOffset.x - displaced) < 1e-6, "rubber-banded past the leading edge: \(r.state.contentOffset) vs \(displaced)")
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: moved, time: r.now))
        #expect(!r.state.isZoomBouncing && !r.state.isZooming, "no bounce while a finger is down")
        #expect(abs(r.state.contentOffset.x - displaced) < 1e-6, "no snap at the lift")
        #expect(r.delegate.log.contains("didEndZooming(1.5)"))
        // The pan took the finger: same spot, nothing moves; 20 pt further, the same band (raw overscroll 120).
        r.now += 0.016
        r.coord.synthesizePan(location: moved, time: r.now)
        #expect(abs(r.state.contentOffset.x - displaced) < 1e-6, "continuity through the hand-off")
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 1020, y: 200), time: r.now)
        #expect(abs(r.state.contentOffset.x - band.displacement(forOverscroll: -120)) < 1e-6, "same band as the pinch: \(r.state.contentOffset)")
        // The last finger lifts after a pause: the release springs the overscroll back, zoom unchanged.
        r.now += 0.1
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(r.state.isDecelerating, "spring back on the clock")
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        #expect(abs(r.state.contentOffset.x) < 1e-6 && r.state.phase == .idle)
        #expect(abs(r.state.zoomScale - 1.5) < 1e-9)
    }

    /// An axis that does not bounce (here `.basedOnSize` on an axis the content fits) stays clamped under the pinch:
    /// the two-finger pan cannot drag the content off its edge there, while the bouncing axis still overscrolls.
    @Test(arguments: OSPath.allCases) func nonBouncingAxisStaysClampedUnderThePinch(path: OSPath) {
        let r = make(path)
        r.state.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 200, height: 400), contentSize: CGSize(width: 200, height: 4000), displayScale: 2))
        r.state.track(offset: CGPoint(x: 0, y: 1000), zoom: 1)
        r.coord.settings.bounceX = .basedOnSize
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        centroid(r, CGPoint(x: 150, y: 260))                 // right 50 (fitting, non-bouncing), down 60 (bouncing)
        #expect(r.state.contentOffset.x == 0, "clamped on the non-bouncing axis: \(r.state.contentOffset)")
        #expect(abs(r.state.contentOffset.y - 940) < 1e-6, "follows on the bouncing axis")
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 150, y: 260), time: r.now))
        #expect(r.state.contentOffset.x == 0 && !r.state.isZoomBouncing)
    }

    /// Nobody takes the remaining finger (the container owns the swipe, scrolling disabled): the overscroll has no pan
    /// to spring it back, so the pan's rubber-band return runs as a deceleration, scale unchanged.
    @Test(arguments: OSPath.allCases) func overscrollWithoutAPanSpringsBackAtTheLift(path: OSPath) {
        let r = make(path)
        r.state.isScrollEnabled = false                      // the pan ignores the sequence
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 1.5, at: c); r.tick()
        centroid(r, CGPoint(x: 1000, y: 200))
        #expect(abs(r.state.contentOffset.x - RubberBand(dimension: 200).displacement(forOverscroll: -100)) < 1e-6)
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 1000, y: 200), time: r.now))
        #expect(r.state.isDecelerating && !r.state.isZooming && r.state.phase == .decelerating, "no pan: the rubber band returns")
        #expect(r.delegate.log.contains("willBeginDecelerating"))
        while r.state.isClockRunning && r.now < 110 { r.tick() }
        #expect(abs(r.state.contentOffset.x) < 1e-6 && abs(r.state.zoomScale - 1.5) < 1e-9 && r.state.phase == .idle)
    }

    // MARK: 8. the magnify gesture's trailing sample after the lift (D25)

    /// The user's video: fingers held still at 2×, one lifts, the view jumps to ≈ 4× in one frame. SwiftUI delivers the
    /// magnify gesture's last `.changed` (cumulative magnification 2) after the observer's count change already handed
    /// the pinch off; it must change nothing, and the remaining finger then pans 1:1.
    @Test(arguments: OSPath.allCases) func trailingMagnifySampleAfterTheLiftDoesNotJump(path: OSPath) {
        let r = make(path, limits: 1...4)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 2, at: c); r.tick()
        let o = r.state.contentOffset
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 120, y: 200), time: r.now))
        // The gesture's trailing sample and then its end, as the adapter delivers them.
        r.coord.handlePinch(.changed(magnification: 2.05, centroid: CGPoint(x: 120, y: 200), time: r.now))
        r.coord.handlePinch(.ended(time: r.now))
        #expect(abs(r.state.zoomScale - 2) < 1e-9, "scale unchanged: \(r.state.zoomScale)")
        #expect(r.state.contentOffset == o && !r.state.isZooming && !r.state.isZoomBouncing)
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 180), time: r.now)
        #expect(abs(r.state.contentOffset.y - (o.y + 20)) < 1e-6 && abs(r.state.zoomScale - 2) < 1e-9, "pans 1:1 at 2×")
    }

    // MARK: 9. second finger down again during the one-finger continuation (D29)

    /// Pinch to 1.5×, lift one finger, pan on with the other, then put the second finger back: the pinch resumes from
    /// the current scale and offset with no jump and no release motion, whichever gesture reports next (the old magnify
    /// gesture with its cumulative magnification, or a new one), and the fingers then zoom and pan 1:1 from there.
    @Test(arguments: OSPath.allCases) func secondFingerDownDuringTheContinuationResumesWithoutASnap(path: OSPath) {
        let r = make(path, limits: 1...4)
        let c = CGPoint(x: 100, y: 200)
        twoFingersDown(r, at: c)
        magnify(r, 1.5, at: c); r.tick()
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 120, y: 200), time: r.now))
        r.coord.handlePinch(.ended(time: r.now))         // the adapter's `.ended` after the hand-off (D25)
        r.now += 0.016
        r.coord.synthesizePan(location: CGPoint(x: 120, y: 170), time: r.now)   // the remaining finger pans 30 pt
        let o = r.state.contentOffset
        #expect(abs(r.state.zoomScale - 1.5) < 1e-9)
        // The second finger lands: the observer sees two fingers at their centroid.
        r.now += 0.3
        let c2 = CGPoint(x: 100, y: 170)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c2, time: r.now))
        #expect(r.state.contentOffset == o && abs(r.state.zoomScale - 1.5) < 1e-9, "nothing moves at the touch")
        #expect(!r.state.isDecelerating && r.state.phase != .decelerating && r.state.phase != .animating, "no release motion")
        let u = r.under(c2)
        // The old magnify gesture keeps reporting its cumulative magnification (1.5, then 1.65).
        r.coord.handlePinch(.changed(magnification: 1.5, centroid: c2, time: r.now))
        #expect(abs(r.state.zoomScale - 1.5) < 1e-9 && Self.dist(r.state.contentOffset, o) < 1e-6, "first sample: no jump")
        r.now += 0.016
        r.coord.handlePinch(.changed(magnification: 1.65, centroid: c2, time: r.now)); r.tick()
        #expect(abs(r.state.zoomScale - 1.65) < 1e-9, "then relative: \(r.state.zoomScale)")
        #expect(Self.dist(r.under(c2), u) < 0.5, "anchored under the centroid")
        // Two-finger pan from there: 1:1.
        let o2 = r.state.contentOffset
        centroid(r, CGPoint(x: 100, y: 150))
        #expect(abs(r.state.contentOffset.y - (o2.y + 20)) < 1e-6 && r.state.contentOffset.x == o2.x)
        #expect(r.state.isZooming && r.state.phase == .interacting)
    }

    // MARK: iOS 15–17 estimate (documented gap)

    @Test func dragFollowEstimateMovesTheCentroidWithTheTrackedFinger() {
        let r = make()
        r.coord.pinch.centroidSource = .startLocationPlusDrag
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.began(centroid: c, time: r.now))
        r.coord.handlePinch(.changed(magnification: 1.5, centroid: nil, time: r.now)); r.tick()
        let u = r.under(c)
        // The drag's translation at the pinch start is the estimate's base; both fingers then move together by
        // (0, −30): the tracked finger's drag reports it → the centroid estimate follows.
        r.coord.handlePinch(.panTranslation(.zero, time: r.now))
        r.coord.handlePinch(.panTranslation(CGSize(width: 0, height: -30), time: r.now))
        #expect(Self.dist(r.under(CGPoint(x: 100, y: 170)), u) < 0.5)
        // Only the other finger moves (pure scale around a moving centroid): the estimate cannot see it — the true
        // centroid moves by half the finger's travel; the error is bounded by that half-travel.
    }
}
