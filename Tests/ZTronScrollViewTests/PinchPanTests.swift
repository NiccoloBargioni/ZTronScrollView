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
    @MainActor struct Rig {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ZoomDelegate
        let clock: Clock
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

    func make(limits: ClosedRange<CGFloat> = 1...3) -> Rig {
        let s = makeState(.preferred)
        let d = ZoomDelegate()
        s.delegate = d
        let clock = Clock()
        s.now = { clock.t }
        s.zoomLimits = ZoomLimits(min: .absolute(limits.lowerBound), max: .absolute(limits.upperBound))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 200, height: 400), contentSize: CGSize(width: 2000, height: 4000), displayScale: 2))
        s.track(offset: CGPoint(x: 500, y: 1000), zoom: 1)
        d.log.removeAll()
        let c = withOSPath(.preferred) { PanCoordinator(state: s, axes: [.horizontal, .vertical]) }
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
    func magnify(_ r: Rig, _ m: CGFloat, at c: CGPoint) { r.coord.handlePinch(.changed(magnification: m, centroid: c, time: r.now)) }

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
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -170), startLocation: start, time: r.now))
        #expect(abs(r.state.contentOffset.y - (afterLift.y + 30)) < 1e-6, "then 1:1 from where the content is")
        // That remaining finger can still fling.
        r.now += 0.05
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -260), time: r.now, fallbackVelocity: nil))
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
