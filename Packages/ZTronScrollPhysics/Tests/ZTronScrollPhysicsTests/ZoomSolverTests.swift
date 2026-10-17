import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct ZoomSolverTests {
    let insets = (x: AxisInsets(start: 10, end: 20), y: AxisInsets(start: 47, end: 34))

    private func geometry(viewport: CGSize = CGSize(width: 390, height: 844),
                          content: CGSize = CGSize(width: 1200, height: 1800),
                          alignment: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> ZoomGeometry {
        ZoomGeometry(viewportSize: viewport, unscaledContentSize: content, insets: insets, alignment: alignment)
    }

    /// Viewport position of unscaled content point `u` (rendering model `p = s·u + pad(s) − offset`).
    private func viewportPoint(of u: CGPoint, offset: CGPoint, scale: CGFloat, geometry: ZoomGeometry) -> CGPoint {
        let pad = geometry.alignmentPadding(at: scale)
        return CGPoint(x: scale * u.x + pad.x - offset.x, y: scale * u.y + pad.y - offset.y)
    }

    @Test func focalPointInvariance() {
        var rng = SplitMix64(seed: 0x5A7E_C0DE)
        for trial in 0..<500 {
            let alignments: [CGFloat] = [0, 0.5, 1, CGFloat.random(in: 0...1, using: &rng)]
            let geometry = ZoomGeometry(
                viewportSize: CGSize(width: .random(in: 200...1400, using: &rng), height: .random(in: 200...1400, using: &rng)),
                unscaledContentSize: CGSize(width: .random(in: 50...4000, using: &rng), height: .random(in: 50...4000, using: &rng)),
                insets: (AxisInsets(start: .random(in: 0...60, using: &rng), end: .random(in: 0...60, using: &rng)),
                         AxisInsets(start: .random(in: 0...60, using: &rng), end: .random(in: 0...60, using: &rng))),
                alignment: CGPoint(x: alignments[trial % 4], y: alignments[(trial / 4) % 4]))
            let s = CGFloat.random(in: 0.2...6, using: &rng), s2 = CGFloat.random(in: 0.2...6, using: &rng)
            let offset = CGPoint(x: .random(in: -2000...2000, using: &rng), y: .random(in: -2000...2000, using: &rng))
            let p = CGPoint(x: .random(in: 0...geometry.x.viewportLength, using: &rng),
                            y: .random(in: 0...geometry.y.viewportLength, using: &rng))
            let u = ZoomSolver.contentPoint(under: p, offset: offset, scale: s, geometry: geometry)
            expectClose(viewportPoint(of: u, offset: offset, scale: s, geometry: geometry), p, 1e-6)
            let newOffset = ZoomSolver.offset(keeping: u, under: p, scale: s2, geometry: geometry, clamped: false)
            expectClose(ZoomSolver.contentPoint(under: p, offset: newOffset, scale: s2, geometry: geometry), u, 1e-6,
                        "trial \(trial)")
            expectClose(viewportPoint(of: u, offset: newOffset, scale: s2, geometry: geometry), p, 1e-6)
            // Clamped variant stays in bounds.
            let clamped = ZoomSolver.offset(keeping: u, under: p, scale: s2, geometry: geometry, clamped: true)
            let b = geometry.bounds(at: s2)
            #expect(b.x.clamped(clamped.x) == clamped.x && b.y.clamped(clamped.y) == clamped.y)
        }
    }

    @Test func twoFingerPanKeepsAnchor() {
        let geometry = geometry()
        let startCentroid = CGPoint(x: 200, y: 400), startOffset = CGPoint(x: 300, y: 500)
        let u = ZoomSolver.contentPoint(under: startCentroid, offset: startOffset, scale: 1.5, geometry: geometry)
        for (centroid, scale) in [(CGPoint(x: 220, y: 380), 1.6), (CGPoint(x: 150, y: 600), 2.4),
                                  (CGPoint(x: 330, y: 120), 0.9)] as [(CGPoint, CGFloat)] {
            let offset = ZoomSolver.pinch(anchor: u, centroid: centroid, scale: scale, geometry: geometry)
            expectClose(ZoomSolver.contentPoint(under: centroid, offset: offset, scale: scale, geometry: geometry), u, 1e-9)
        }
        // Pure two-finger pan (scale unchanged) moves the content with the fingers.
        let panned = ZoomSolver.pinch(anchor: u, centroid: CGPoint(x: 250, y: 430), scale: 1.5, geometry: geometry)
        expectClose(panned, CGPoint(x: startOffset.x - 50, y: startOffset.y - 30), 1e-9)
    }

    @Test func limitsFitFillResolve() {
        let content = CGSize(width: 1000, height: 2000)
        let limits = ZoomLimits(min: .fit, max: .fill)
        let portrait = limits.resolve(unscaledContentSize: content, viewportSize: CGSize(width: 390, height: 844),
                                      insets: (.zero, .zero))
        expectClose(portrait.lowerBound, 0.39, 1e-12)
        expectClose(portrait.upperBound, 0.422, 1e-12)
        let inset = limits.resolve(unscaledContentSize: content, viewportSize: CGSize(width: 390, height: 844),
                                   insets: (.zero, AxisInsets(start: 47, end: 34)))
        expectClose(inset.lowerBound, 763.0 / 2000, 1e-12)                       // inset-adjusted height now limits
        expectClose(inset.upperBound, 0.39, 1e-12)
        let landscape = limits.resolve(unscaledContentSize: content, viewportSize: CGSize(width: 844, height: 390),
                                       insets: (.zero, .zero))                    // recomputed per viewport
        expectClose(landscape.lowerBound, 0.195, 1e-12)
        expectClose(landscape.upperBound, 0.844, 1e-12)
        let photos = ZoomLimits(min: .fit, max: .absolute(3))
            .resolve(unscaledContentSize: content, viewportSize: CGSize(width: 390, height: 844), insets: (.zero, .zero))
        #expect(photos.upperBound == 3)
        // min above max: the minimum wins and zooming is disabled.
        let inverted = ZoomLimits(min: .fill, max: .fit)
            .resolve(unscaledContentSize: content, viewportSize: CGSize(width: 390, height: 844), insets: (.zero, .zero))
        #expect(inverted.lowerBound == inverted.upperBound)
        expectClose(inverted.lowerBound, 0.422, 1e-12)
    }

    @Test func zoomEnabledIffMaxGreaterThanMin() {
        let size = CGSize(width: 390, height: 844)
        let defaults = ZoomLimits().resolve(unscaledContentSize: size, viewportSize: size, insets: (.zero, .zero))
        #expect(defaults == 1...1)
        #expect(!ZoomLimits.isZoomEnabled(defaults))
        #expect(ZoomLimits.isZoomEnabled(1...3))
        #expect(!ZoomLimits.isZoomEnabled(ZoomLimits(min: .fit, max: .fit)
            .resolve(unscaledContentSize: CGSize(width: 2000, height: 2000), viewportSize: size, insets: (.zero, .zero))))
        #expect(!ZoomLimits.isZoomEnabled(ZoomLimits(min: .absolute(-1), max: .absolute(.nan))
            .resolve(unscaledContentSize: size, viewportSize: size, insets: (.zero, .zero))))
    }

    @Test func resistanceIsLogSymmetricAndBounded() {
        let limits: ClosedRange<CGFloat> = 1...4
        #expect(ZoomSolver.resisted(rawScale: 2.5, limits: limits) == 2.5)
        #expect(ZoomSolver.resisted(rawScale: 4, limits: limits) == 4)
        var previousAbove: CGFloat = 4, previousBelow: CGFloat = 1
        for k in [1.001, 1.01, 1.5, 2, 10, 1000, 1e12] as [CGFloat] {
            let above = ZoomSolver.resisted(rawScale: 4 * k, limits: limits)
            let below = ZoomSolver.resisted(rawScale: 1 / k, limits: limits)
            expectClose(log(above / 4), -log(below / 1), 1e-12)                  // symmetric in log space
            #expect(above > previousAbove && above < 4 * CGFloat(M_E))           // bounded by L·e^(logDimension)
            #expect(below < previousBelow && below > 1 / CGFloat(M_E))
            #expect(above < 4 * k)                                               // resisted, not amplified
            previousAbove = above
            previousBelow = below
            expectClose(ZoomSolver.unresisted(shownScale: above, limits: limits), 4 * k, 4 * k * 1e-6)
        }
        let wide = ZoomSolver.resisted(rawScale: 40, limits: limits, logDimension: 2)
        #expect(wide > ZoomSolver.resisted(rawScale: 40, limits: limits) && wide < 4 * exp(2))
        #expect(ZoomSolver.resisted(rawScale: 0, limits: limits) == 1)
        #expect(ZoomSolver.resisted(rawScale: .nan, limits: limits) == 1)
        #expect(ZoomSolver.resisted(rawScale: .infinity, limits: limits) == 4)
    }

    @Test func bounceBackEndsAtNearestLimit() {
        let geometry = geometry()
        let limits: ClosedRange<CGFloat> = 0.5...3
        // Over-zoomed with the anchor well inside: no residual, the anchor stays under the centroid all the way.
        let centroid = CGPoint(x: 195, y: 420)
        let offset = CGPoint(x: 1500, y: 2400)
        let motion = ZoomSolver.bounceBack(from: 3.6, limits: limits, lastCentroid: centroid, offset: offset,
                                           geometry: geometry, at: 1)
        #expect(motion.residual.x.target == 0 && motion.residual.y.target == 0)
        let first = motion.sample(at: 1, geometry: geometry)
        expectClose(first.scale, 3.6, 1e-12)
        expectClose(first.offset, offset, 1e-9)
        var previousScale = first.scale
        for t in grid(0.02, 1.2, count: 60) {
            let s = motion.sample(at: 1 + TimeInterval(t), geometry: geometry)
            #expect(s.scale <= previousScale)
            previousScale = s.scale
            expectClose(ZoomSolver.contentPoint(under: centroid, offset: s.offset, scale: s.scale, geometry: geometry),
                        motion.anchor, 1e-6)
        }
        let end = motion.sample(at: 100, geometry: geometry)
        #expect(end.isSettled)
        expectClose(end.scale, 3, 1e-12)

        // Under-zoomed near a corner: the offset also settles into bounds(L).
        let corner = ZoomSolver.bounceBack(from: 0.3, limits: limits, lastCentroid: CGPoint(x: 20, y: 60),
                                           offset: CGPoint(x: -200, y: -300), geometry: geometry, at: 0)
        let settled = corner.sample(at: 100, geometry: geometry)
        #expect(settled.isSettled)
        expectClose(settled.scale, 0.5, 1e-12)
        #expect(geometry.clamped(settled.offset, at: settled.scale) == settled.offset)
        expectClose(corner.sample(at: 0, geometry: geometry).offset, CGPoint(x: -200, y: -300), 1e-9)
        #expect(!corner.sample(at: 0.05, geometry: geometry).isSettled)
        #expect(corner == corner)
    }

    /// The final snap of a zoom bounce is invisible wherever the content is scrolled: content under every viewport
    /// corner moves by less than `thresholds.distance` per axis (centroid at the center and at both far corners, the
    /// worst case), and the settle time does not depend on the scroll position. The zoomed-coordinate offset itself
    /// jumps by `δ·s·u` pt (≈ 4 pt at offset 9000); the simultaneous scale snap cancels it.
    @Test(arguments: [CGPoint(x: 195, y: 420), .zero, CGPoint(x: 390, y: 844)])
    func bounceBackFinalSnapIsInvisible(centroid: CGPoint) {
        let geometry = ZoomGeometry(viewportSize: CGSize(width: 390, height: 844),
                                    unscaledContentSize: CGSize(width: 4000, height: 4000))
        let thresholds = RestThresholds()
        let corners = [CGPoint.zero, CGPoint(x: 390, y: 0), CGPoint(x: 0, y: 844), CGPoint(x: 390, y: 844)]
        var settleTimes: [TimeInterval] = []
        for offset in [CGPoint(x: 600, y: 600), CGPoint(x: 3000, y: 3000), CGPoint(x: 9000, y: 9000),
                       CGPoint(x: 10_000, y: 10_000)] {
            let motion = ZoomSolver.bounceBack(from: 3.6, limits: 0.5...3, lastCentroid: centroid, offset: offset,
                                               geometry: geometry, at: 5)
            #expect(motion.residual.x.target == 0 && motion.residual.y.target == 0, "\(offset)")
            let settle = settlingTime(of: motion, geometry: geometry, thresholds: thresholds)
            settleTimes.append(settle)
            let before = motion.sample(at: 5 + settle - 1e-6, geometry: geometry, thresholds: thresholds)
            let after = motion.sample(at: 5 + settle, geometry: geometry, thresholds: thresholds)
            #expect(!before.isSettled && after.isSettled)
            #expect(after.scale == 3)
            for corner in corners {
                let u = ZoomSolver.contentPoint(under: corner, offset: before.offset, scale: before.scale,
                                                geometry: geometry)
                let shown = viewportPoint(of: u, offset: after.offset, scale: after.scale, geometry: geometry)
                #expect(abs(shown.x - corner.x) < thresholds.distance && abs(shown.y - corner.y) < thresholds.distance,
                        "offset \(offset) corner \(corner): moved to \(shown)")
            }
        }
        #expect(settleTimes.allSatisfy { abs($0 - settleTimes[0]) < 1e-6 }, "\(settleTimes)")
    }

    @Test func setZoomScaleAnchorsVisibleCenter() {
        let geometry = geometry()
        let limits: ClosedRange<CGFloat> = 0.25...4
        let offset = CGPoint(x: 400, y: 700)
        let center = geometry.visibleCenter
        let u = ZoomSolver.contentPoint(under: center, offset: offset, scale: 1, geometry: geometry)
        let zoomed = ZoomSolver.zoom(to: 2.5, anchoredAtVisibleCenterOf: offset, currentScale: 1, limits: limits,
                                     geometry: geometry)
        #expect(zoomed.scale == 2.5)
        expectClose(ZoomSolver.contentPoint(under: center, offset: zoomed.offset, scale: 2.5, geometry: geometry), u, 1e-9)
        let capped = ZoomSolver.zoom(to: 10, anchoredAtVisibleCenterOf: offset, currentScale: 1, limits: limits,
                                     geometry: geometry)
        #expect(capped.scale == 4)
        let floor = ZoomSolver.zoom(to: 0.01, anchoredAtVisibleCenterOf: offset, currentScale: 1, limits: limits,
                                    geometry: geometry)
        #expect(floor.scale == 0.25)
        #expect(geometry.clamped(floor.offset, at: 0.25) == floor.offset)
    }

    @Test func zoomToRectFitsAndCenters() {
        let geometry = geometry(content: CGSize(width: 2000, height: 2000))
        let rect = CGRect(x: 600, y: 900, width: 300, height: 150)
        let result = ZoomSolver.zoom(toFit: rect, limits: 0.1...8, geometry: geometry)
        // Inset-adjusted viewport: 390 − 30 = 360, 844 − 81 = 763.
        expectClose(result.scale, 360.0 / 300, 1e-12)
        let mid = ZoomSolver.contentPoint(under: geometry.visibleCenter, offset: result.offset, scale: result.scale,
                                          geometry: geometry)
        expectClose(mid, CGPoint(x: rect.midX, y: rect.midY), 1e-9)
        let topLeft = viewportPoint(of: rect.origin, offset: result.offset, scale: result.scale, geometry: geometry)
        let bottomRight = viewportPoint(of: CGPoint(x: rect.maxX, y: rect.maxY), offset: result.offset,
                                        scale: result.scale, geometry: geometry)
        #expect(topLeft.x >= insets.x.start - 1e-9 && bottomRight.x <= 390 - insets.x.end + 1e-9)
        #expect(topLeft.y >= insets.y.start - 1e-9 && bottomRight.y <= 844 - insets.y.end + 1e-9)
        #expect(ZoomSolver.zoom(toFit: rect, limits: 0.1...1, geometry: geometry).scale == 1)
        #expect(ZoomSolver.zoom(toFit: CGRect(x: 10, y: 10, width: 0, height: 0), limits: 0.1...8,
                                geometry: geometry).scale == 8)
    }

    @Test(arguments: [false, true])
    func resizePreservesVisibleCenter(atFit: Bool) {
        let content = atFit ? CGSize(width: 1000, height: 1500) : CGSize(width: 2000, height: 3000)
        let portrait = ZoomGeometry(viewportSize: CGSize(width: 390, height: 844), unscaledContentSize: content)
        let landscape = ZoomGeometry(viewportSize: CGSize(width: 844, height: 390), unscaledContentSize: content)
        let fitLimits = ZoomLimits(min: .fit, max: .absolute(4))
        func scale(for g: ZoomGeometry) -> CGFloat {
            atFit ? fitLimits.resolve(unscaledContentSize: content,
                                      viewportSize: CGSize(width: g.x.viewportLength, height: g.y.viewportLength),
                                      insets: (.zero, .zero)).lowerBound : 1
        }
        let s0 = scale(for: portrait), s1 = scale(for: landscape)
        let offset = portrait.clamped(CGPoint(x: 800, y: 1200), at: s0)
        let u = ZoomSolver.contentPoint(under: portrait.visibleCenter, offset: offset, scale: s0, geometry: portrait)
        let rotated = ZoomSolver.offset(preservingVisibleCenterFrom: portrait, offset: offset, scale: s0,
                                        to: landscape, newScale: s1)
        let u2 = ZoomSolver.contentPoint(under: landscape.visibleCenter, offset: rotated, scale: s1, geometry: landscape)
        expectClose(u2, u, 1e-6)
        if atFit { expectClose(u, CGPoint(x: 500, y: 750), 1e-9) }                // fit + center alignment
        let back = ZoomSolver.offset(preservingVisibleCenterFrom: landscape, offset: rotated, scale: s1,
                                     to: portrait, newScale: s0)
        expectClose(back, offset, 1e-6)
    }

    @Test func degenerateContentSizeGuards() {
        let empty = ZoomLimits(min: .fit, max: .fill)
            .resolve(unscaledContentSize: .zero, viewportSize: CGSize(width: 390, height: 844), insets: (.zero, .zero))
        #expect(empty == 1...1)
        let nanLimits = ZoomLimits(min: .fit, max: .fill)
            .resolve(unscaledContentSize: CGSize(width: CGFloat.nan, height: 500),
                     viewportSize: CGSize(width: 390, height: 844), insets: (.zero, .zero))
        expectClose(nanLimits.lowerBound, 844.0 / 500, 1e-12)                    // the usable axis decides
        let geometry = ZoomGeometry(viewportSize: CGSize(width: CGFloat.nan, height: 0), unscaledContentSize: .zero)
        let p = ZoomSolver.contentPoint(under: CGPoint(x: 10, y: 10), offset: .zero, scale: 0, geometry: geometry)
        #expect(p == CGPoint(x: 10, y: 10))                                       // scale 0 → 1
        let zoomed = ZoomSolver.zoom(toFit: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), limits: 0...0,
                                     geometry: geometry)
        #expect(zoomed.scale == 1 && zoomed.offset.x.isFinite && zoomed.offset.y.isFinite)
        let motion = ZoomSolver.bounceBack(from: .nan, limits: -1...0, lastCentroid: CGPoint(x: CGFloat.nan, y: 0),
                                           offset: .zero, geometry: geometry, at: .nan)
        let sample = motion.sample(at: 10, geometry: geometry)
        #expect(sample.scale.isFinite && sample.offset.x.isFinite && sample.offset.y.isFinite)
    }
}
