import CoreGraphics
import Foundation
import Testing
@testable import ZTronScrollPhysics

@Suite struct RubberBandTests {
    static let dimensions: [CGFloat] = [1, 390, 844, 1366]

    @Test(arguments: dimensions)
    func monotonicIncreasing(d: CGFloat) {
        let band = RubberBand(dimension: d)
        var previous = band.displacement(forOverscroll: 0)
        #expect(previous == 0)
        for x in grid(d / 100, 10 * d, count: 1000) {
            let f = band.displacement(forOverscroll: x)
            #expect(f > previous)
            previous = f
        }
    }

    @Test(arguments: dimensions)
    func alwaysBelowDimension(d: CGFloat) {
        let band = RubberBand(dimension: d)
        for x in grid(0, 10 * d, count: 500) + [1e6, 1e12, 1e300, .greatestFiniteMagnitude] {
            #expect(band.displacement(forOverscroll: x) < d)
            #expect(band.displacement(forOverscroll: -x) > -d)
        }
    }

    @Test(arguments: dimensions)
    func inverseRoundTrips(d: CGFloat) {
        let band = RubberBand(dimension: d)
        for x in grid(-10 * d, 10 * d, count: 801) {
            let back = band.overscroll(forDisplacement: band.displacement(forOverscroll: x))
            #expect(abs(back - x) < 1e-6, "x = \(x) → \(back)")
        }
    }

    @Test func oddSymmetry() {
        let band = RubberBand(dimension: 844)
        for x in grid(0, 5000, count: 200) {
            #expect(band.displacement(forOverscroll: -x) == -band.displacement(forOverscroll: x))
            #expect(band.overscroll(forDisplacement: -x / 10) == -band.overscroll(forDisplacement: x / 10))
        }
    }

    @Test(arguments: [0, -5, .nan, .infinity] as [CGFloat])
    func zeroDimensionIsZero(d: CGFloat) {
        let band = RubberBand(dimension: d)
        #expect(band.displacement(forOverscroll: 120) == 0)
        #expect(band.overscroll(forDisplacement: 40) == 0)
    }

    @Test func inverseClampsNearAsymptote() {
        let d: CGFloat = 844
        let band = RubberBand(dimension: d)
        let atAsymptote = band.overscroll(forDisplacement: d)
        #expect(atAsymptote.isFinite && atAsymptote > 0)
        #expect(atAsymptote == band.overscroll(forDisplacement: d * (1 - 1e-6)))
        #expect(band.overscroll(forDisplacement: 2 * d) == atAsymptote)
        #expect(band.overscroll(forDisplacement: -2 * d) == -atAsymptote)
        #expect(band.overscroll(forDisplacement: .nan) == 0)
        #expect(band.displacement(forOverscroll: .infinity) == 0)              // non-finite delta → 0
    }

    @Test(arguments: [0.55, 0.3, 1.0] as [CGFloat])
    func slopeAtZeroIsCoefficient(c: CGFloat) {
        let band = RubberBand(dimension: 600, coefficient: c)
        let h: CGFloat = 1e-6
        expectClose(band.displacement(forOverscroll: h) / h, c, 1e-6)
        expectClose(band.displacement(forOverscroll: -h) / -h, c, 1e-6)
        #expect(RubberBand(dimension: 600, coefficient: -1).coefficient == 0.55)
    }

    @Test func matchesSpecFormula() {
        let d: CGFloat = 390, c: CGFloat = 0.55
        let band = RubberBand(dimension: d)
        for x in grid(0, 2000, count: 50) {
            let spec = (1 - 1 / (x * c / d + 1)) * d
            expectClose(band.displacement(forOverscroll: x), spec, 1e-9)
        }
    }
}

@Suite struct BoundsTests {
    let insets = AxisInsets(start: 47, end: 34)

    @Test func minIsNegativeStartInset() {
        #expect(AxisBounds(contentLength: 2000, viewportLength: 844, insets: insets).min == -47)
        #expect(AxisBounds(contentLength: 2000, viewportLength: 844, insets: .zero).min == 0)
    }

    @Test func maxUsesEndInsetAndViewport() {
        let bounds = AxisBounds(contentLength: 2000, viewportLength: 844, insets: insets)
        #expect(bounds.max == CGFloat(2000 + 34 - 844))
        #expect(bounds.isScrollable)
    }

    @Test func maxNeverBelowMin() {
        let bounds = AxisBounds(contentLength: 300, viewportLength: 844, insets: insets)
        #expect(bounds.max == bounds.min)
        #expect(!bounds.isScrollable)
        let explicit = AxisBounds(min: 100, max: 20)
        #expect(explicit.min == 100 && explicit.max == 100)
    }

    @Test func clampAndOverscrollSign() {
        let bounds = AxisBounds(contentLength: 2000, viewportLength: 844, insets: insets)   // −47 … 1190
        #expect(bounds.clamped(-100) == -47)
        #expect(bounds.clamped(5000) == 1190)
        #expect(bounds.clamped(300) == 300)
        #expect(bounds.clamped(.nan) == -47)
        #expect(bounds.overscroll(of: -100) == -53)
        #expect(bounds.overscroll(of: 300) == 0)
        #expect(bounds.overscroll(of: 1200) == 10)
        #expect(bounds.overscroll(of: .nan) == 0)
        #expect(bounds.nearestEdge(to: -100) == -47)
        #expect(bounds.nearestEdge(to: 1500) == 1190)
        #expect(bounds.nearestEdge(to: 100) == -47)
        #expect(bounds.nearestEdge(to: 1000) == 1190)
    }

    @Test func tinyViewportBounds() {
        let zero = AxisBounds(contentLength: 500, viewportLength: 0, insets: .zero)
        #expect(zero.min == 0 && zero.max == 500)
        let one = AxisBounds(contentLength: 500, viewportLength: 1, insets: .zero)
        #expect(one.max == 499)
        let negative = AxisBounds(contentLength: 500, viewportLength: -20, insets: .zero)
        #expect(negative.max == 500)
        let garbage = AxisBounds(contentLength: .nan, viewportLength: .infinity, insets: AxisInsets(start: .nan, end: 3))
        #expect(garbage.min == 0 && garbage.max == 3)
        let geometry = AxisGeometry(viewportLength: 0, unscaledContentLength: 0)
        #expect(geometry.bounds(at: 1) == AxisBounds(min: 0, max: 0))
        #expect(geometry.alignmentPadding(at: 1) == 0)
    }

    @Test func alignmentPaddingOnlyWhenContentFits() {
        func geometry(_ content: CGFloat, _ alignment: CGFloat) -> AxisGeometry {
            AxisGeometry(viewportLength: 800, unscaledContentLength: content,
                         insets: AxisInsets(start: 50, end: 50), alignment: alignment)
        }
        #expect(geometry(300, 0.5).alignmentPadding(at: 1) == 200)
        #expect(geometry(300, 0).alignmentPadding(at: 1) == 0)
        #expect(geometry(300, 1).alignmentPadding(at: 1) == 400)
        #expect(geometry(1000, 0.5).alignmentPadding(at: 1) == 0)
        #expect(geometry(300, 0.5).alignmentPadding(at: 3) == 0)                // 900 pt no longer fits
        #expect(geometry(300, 0.5).visibleCenter == 400)
        #expect(AxisGeometry(viewportLength: 800, unscaledContentLength: 10, insets: AxisInsets(start: 100, end: 0))
            .visibleCenter == 450)
    }

    @Test func boundsScaleWithZoom() {
        let geometry = AxisGeometry(viewportLength: 400, unscaledContentLength: 500)
        #expect(geometry.contentLength(at: 2) == 1000)
        #expect(geometry.bounds(at: 2).max == 600)
        #expect(geometry.bounds(at: 0.5).max == 0)
        #expect(geometry.contentLength(at: .nan) == 500)
        #expect(geometry.contentLength(at: -2) == 500)
    }
}
