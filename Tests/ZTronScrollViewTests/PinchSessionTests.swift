import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// Pure `PinchSession` tests (design M4 §8, items 1, 3 and the release decision of 4).
@Suite struct PinchSessionTests {
    static func env(content: CGSize = CGSize(width: 1000, height: 2000), limits: ClosedRange<CGFloat> = 0.5...4,
                    insets: (x: AxisInsets, y: AxisInsets) = (.zero, .zero), bounces: Bool = true,
                    scale: CGFloat = 1, offset: CGPoint = CGPoint(x: 200, y: 300)) -> PinchEnvironment {
        var e = PinchEnvironment()
        e.limits = limits
        e.isZoomEnabled = limits.upperBound > limits.lowerBound
        e.bouncesZoom = bounces
        e.presentationScale = scale
        e.presentationOffset = offset
        e.geometry = ZoomGeometry(viewportSize: CGSize(width: 400, height: 800), unscaledContentSize: content,
                                  insets: insets)
        return e
    }

    private func lcg(_ seed: inout UInt64) -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 11) / CGFloat(1 << 53)
    }

    @Test(arguments: [false, true]) func focalPointIsInvariant(smallContentWithInsets: Bool) {
        // Small content at low scales: alignment padding is non-zero; insets are non-zero.
        let e = smallContentWithInsets
            ? Self.env(content: CGSize(width: 300, height: 500), limits: 0.25...4,
                       insets: (AxisInsets(start: 10, end: 20), AxisInsets(start: 44, end: 34)), offset: CGPoint(x: 0, y: -44))
            : Self.env()
        var s = PinchSession()
        var seed: UInt64 = 42
        let c0 = CGPoint(x: 150, y: 400)
        _ = s.handle(.began(centroid: c0, time: 0), env: e)
        let u = ZoomSolver.contentPoint(under: c0, offset: e.presentationOffset, scale: 1, geometry: e.geometry)
        var worst: CGFloat = 0, worstFocal: CGFloat = 0, inBounds = 0
        var c = c0
        for i in 1...300 {
            c.x += (lcg(&seed) - 0.5) * 12      // two-finger pan while spreading
            c.y += (lcg(&seed) - 0.5) * 12
            let m = exp((lcg(&seed) - 0.5) * 6)  // 0.05x ... 20x: crosses both limits (resisted)
            let fx = s.handle(.changed(magnification: m, centroid: c, time: Double(i) * 0.01), env: e)
            guard case let .setZoom(scale, offset)? = fx.last else { Issue.record("no setZoom"); return }
            // The emitted offset is the pan's rubber band applied, per axis, to the exact focal-invariant offset (D24).
            let raw = ZoomSolver.offset(keeping: u, under: c, scale: scale, geometry: e.geometry, clamped: false)
            let b = e.geometry.bounds(at: scale)
            func banded(_ x: CGFloat, _ bounds: AxisBounds, _ viewport: CGFloat) -> CGFloat {
                bounds.clamped(x) + RubberBand(dimension: viewport, coefficient: e.rubberBandCoefficient)
                    .displacement(forOverscroll: bounds.overscroll(of: x))
            }
            let expected = CGPoint(x: banded(raw.x, b.x, e.geometry.x.viewportLength),
                                   y: banded(raw.y, b.y, e.geometry.y.viewportLength))
            worst = max(worst, hypot(offset.x - expected.x, offset.y - expected.y))
            if b.x.overscroll(of: raw.x) == 0, b.y.overscroll(of: raw.y) == 0 {
                // Inside the bounds the content point under the centroid is exactly invariant.
                let p = ZoomSolver.contentPoint(under: c, offset: offset, scale: scale, geometry: e.geometry)
                worstFocal = max(worstFocal, hypot(p.x - u.x, p.y - u.y))
                inBounds += 1
            }
        }
        #expect(worst < 1e-6, "worst band deviation \(worst)")
        #expect(worstFocal < 1e-9, "worst focal error in bounds \(worstFocal) over \(inBounds) frames")
        #expect(inBounds > 0)
    }

    @Test func resistanceIsSymmetricInLogSpace() {
        let e = Self.env(limits: 1...3)
        let hi = PinchSession.shownScale(startScale: 1, magnification: 6, env: e)     // 2x max
        let lo = PinchSession.shownScale(startScale: 1, magnification: 0.5, env: e)    // min / 2
        #expect(abs(abs(log(hi / 3)) - abs(log(lo / 1))) < 1e-12)
        #expect(hi > 3 && hi < 6 && lo < 1 && lo > 0.5)
        for raw in [0.2, 0.5, 1.5, 3, 4.5, 9] as [CGFloat] {
            let shown = ZoomSolver.resisted(rawScale: raw, limits: 1...3)
            #expect(abs(ZoomSolver.unresisted(shownScale: shown, limits: 1...3) - raw) < 1e-9 * raw)
        }
    }

    /// D24: past the bounds, a bouncing axis rubber-bands with the pan's band (viewport dimension, c 0.55), a
    /// non-bouncing axis is clamped; `bouncesZoom` has no say over the offset.
    @Test(arguments: [true, false]) func offsetPastTheBoundsFollowsThePanBouncePerAxis(bouncesZoom: Bool) {
        var e = Self.env(limits: 1...3, bounces: bouncesZoom, offset: .zero)   // at the start edges
        e.bouncesX = true
        e.bouncesY = false
        let g = e.geometry
        // A two-finger slide of (+150, +150) from the start edges: raw offset (−150, −150) on both axes.
        var s = PinchSession()
        _ = s.handle(.began(centroid: CGPoint(x: 100, y: 100), time: 0), env: e)
        _ = s.handle(.changed(magnification: 1, centroid: CGPoint(x: 100, y: 100), time: 0.01), env: e)
        let fx = s.handle(.fingerCountChanged(count: 2, remaining: CGPoint(x: 250, y: 250), time: 0.02), env: e)
        guard case let .setZoom(_, offset)? = fx.last else { Issue.record("no setZoom: \(fx)"); return }
        let b = g.bounds(at: 1)
        let band = RubberBand(dimension: g.x.viewportLength)
        #expect(abs(offset.x - (b.x.min + band.displacement(forOverscroll: -150))) < 1e-9, "x rubber-banded: \(offset)")
        #expect(offset.y == b.y.min, "y clamped: \(offset)")
    }

    @Test func withoutBouncesZoomTheScaleAndOffsetAreClamped() {
        let e = Self.env(limits: 1...3, bounces: false)
        #expect(PinchSession.shownScale(startScale: 1, magnification: 6, env: e) == 3)
        #expect(PinchSession.shownScale(startScale: 1, magnification: 0.1, env: e) == 1)
        var s = PinchSession()
        _ = s.handle(.began(centroid: CGPoint(x: 10, y: 10), time: 0), env: e)
        let fx = s.handle(.changed(magnification: 9, centroid: CGPoint(x: 10, y: 10), time: 0.1), env: e)
        guard case let .setZoom(scale, offset)? = fx.last else { Issue.record("no setZoom"); return }
        #expect(scale == 3 && offset == e.geometry.clamped(offset, at: 3))
        // Past the limit without bounce there is nothing to spring back: the pinch just ends at the limit.
        let end = s.handle(.ended(time: 0.2), env: e)
        #expect(end.contains(.endZooming(atScale: 3)))
        #expect(!end.contains { if case .bounce = $0 { true } else { false } })
    }

    @Test func releaseInsideLimitsEndsAtOnceAndPastThemBounces() {
        let e = Self.env(limits: 1...2, offset: CGPoint(x: 300, y: 600))
        var inside = PinchSession()
        _ = inside.handle(.began(centroid: CGPoint(x: 200, y: 400), time: 0), env: e)
        let fx = inside.handle(.changed(magnification: 1.5, centroid: CGPoint(x: 200, y: 400), time: 0.1), env: e)
        #expect(fx.first == .beginZooming)
        #expect(inside.handle(.ended(time: 0.2), env: e) == [.endZooming(atScale: 1.5)])
        #expect(inside.phase == .released)

        var past = PinchSession()
        _ = past.handle(.began(centroid: CGPoint(x: 200, y: 400), time: 0), env: e)
        _ = past.handle(.changed(magnification: 3.2, centroid: CGPoint(x: 200, y: 400), time: 0.1), env: e)
        let end = past.handle(.cancelled, env: e)
        guard case let .bounce(req)? = end.first, end.count == 1 else { Issue.record("expected one bounce: \(end)"); return }
        #expect(req.scale > 2 && req.scale < 3.2 && req.lastCentroid == CGPoint(x: 200, y: 400))
    }

    @Test func disabledZoomAndBadSamplesProduceNothing() {
        var s = PinchSession()
        let off = Self.env(limits: 1...1)
        #expect(s.handle(.began(centroid: .zero, time: 0), env: off) == [])
        #expect(s.handle(.changed(magnification: 2, centroid: .zero, time: 0), env: off) == [])
        var t = PinchSession()
        let e = Self.env()
        _ = t.handle(.began(centroid: .zero, time: 0), env: e)
        #expect(t.handle(.changed(magnification: .nan, centroid: nil, time: 0), env: e) == [])
        #expect(t.handle(.changed(magnification: -1, centroid: nil, time: 0), env: e) == [])
    }

    @Test func caughtMotionAndOneFingerLift() {
        var e = Self.env()
        e.isMovingWithoutFinger = true
        var s = PinchSession()
        #expect(s.handle(.began(centroid: CGPoint(x: 50, y: 50), time: 0), env: e) == [.catchMotion])
        _ = s.handle(.changed(magnification: 1.2, centroid: nil, time: 0.1), env: e)
        let lift = s.handle(.fingerCountChanged(count: 1, remaining: CGPoint(x: 60, y: 70), time: 0.2), env: e)
        #expect(lift.last == .handOffToPan(remaining: CGPoint(x: 60, y: 70)))
        #expect(lift.count == 2)
    }

    @Test func estimatedCentroidFollowsPanTranslation() {
        var e = Self.env()
        e.isMovingWithoutFinger = false
        var s = PinchSession()
        s.centroidSource = .startLocationPlusDrag
        let c0 = CGPoint(x: 100, y: 200)
        _ = s.handle(.began(centroid: c0, time: 0), env: e)
        _ = s.handle(.panTranslation(CGSize(width: 5, height: 5), time: 0.01), env: e)
        let fx = s.handle(.changed(magnification: 1.5, centroid: nil, time: 0.02), env: e)
        guard case let .setZoom(scale, offset)? = fx.last else { Issue.record("no setZoom"); return }
        let moved = s.handle(.panTranslation(CGSize(width: 15, height: -5), time: 0.03), env: e)
        guard case let .setZoom(scale2, offset2)? = moved.last else { Issue.record("no setZoom on pan"); return }
        #expect(scale2 == scale)
        // The centroid moved by (10, -10): the offset moves by the opposite amount.
        #expect(abs(offset2.x - (offset.x - 10)) < 1e-9 && abs(offset2.y - (offset.y + 10)) < 1e-9)
        #expect(PinchSession.estimatedCentroid(start: c0, panAtStart: .zero, panNow: CGSize(width: 3, height: 4))
                == CGPoint(x: 103, y: 204))
    }
}
