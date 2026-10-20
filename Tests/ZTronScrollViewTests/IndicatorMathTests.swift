import SwiftUI
import Testing
@testable import ZTronScrollView

/// M8-1 (design M8 §2, §10): the pure thumb geometry. Viewport points, per axis; no OS path is involved (the
/// `ChromeSample` tests below drive the same math through the state over both paths).
struct IndicatorMathTests {
    /// V 800, C 3200 → extent 3200, track 794, length 198.5, range 2400 unless a test changes them.
    func thumb(V: CGFloat = 800, C: CGFloat = 3200, s: CGFloat = 1, aci: (CGFloat, CGFloat) = (0, 0),
               ind: (CGFloat, CGFloat) = (0, 0), o: CGFloat, other: Bool = false) -> IndicatorThumb? {
        IndicatorMath.thumb(viewport: V, content: C, zoom: s, inset: (start: aci.0, end: aci.1),
                            indInset: (start: ind.0, end: ind.1), offset: o, otherVisible: other)
    }

    func close(_ a: CGFloat?, _ b: CGFloat, _ tol: CGFloat = 1e-9) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    @Test func lengthIsTheViewportFractionOfTheTrack() {
        let t = thumb(o: 0)
        #expect(close(t?.length, 198.5) && close(t?.origin, IndicatorStyle.edgeGap))
    }

    @Test func positionIsLinearAndEndsAtTheEndGap() {
        #expect(close(thumb(o: 1200)?.origin, 300.75))
        let end = thumb(o: 2400)
        #expect(close(end.map { $0.origin + $0.length }, 800 - IndicatorStyle.edgeGap), "pinned to the end gap at the end rest position")
        #expect(close(end?.origin, 598.5))
    }

    @Test func lengthNeverBelowTheMinimum() {
        #expect(close(thumb(C: 80_000, o: 0)?.length, IndicatorStyle.minLength))
        // A track shorter than the minimum length: the thumb fills the track, never overflows it.
        #expect(close(thumb(V: 40, C: 4000, o: 0)?.length, 34))
    }

    @Test func nothingWhenTheContentDoesNotExceedTheViewport() {
        #expect(thumb(C: 700, o: 0) == nil)
        #expect(thumb(C: 800, o: 0) == nil, "exactly fitting content is not scrollable")
        #expect(thumb(V: 0, o: 0) == nil)
        #expect(thumb(V: .nan, o: 0) == nil && thumb(o: .infinity) == nil)
        #expect(thumb(V: 5, C: 4000, o: 0) == nil, "no track left between the gaps")
        // Insets alone can make the extent exceed the viewport (UIKit: content + inset > bounds).
        #expect(thumb(V: 800, C: 700, aci: (100, 100), o: -100) != nil)
    }

    @Test func offsetConventionIsZeroAtTheStartRestPositionOfTheAdjustedInset() {
        // A 100 pt top inset: rest is offset −100. The extent grows by the inset, o′ = o + 100.
        let rest = thumb(aci: (100, 0), o: -100)
        #expect(close(rest?.origin, IndicatorStyle.edgeGap))
        #expect(close(rest?.length, 794 * 800 / 3300))
        let end = thumb(aci: (100, 0), o: 2400)
        #expect(close(end.map { $0.origin + $0.length }, 800 - IndicatorStyle.edgeGap))
        // A bottom inset extends the range at the end.
        let bottom = thumb(aci: (0, 60), o: 2460)
        #expect(close(bottom.map { $0.origin + $0.length }, 800 - IndicatorStyle.edgeGap))
    }

    @Test func indicatorInsetsShrinkTheTrackFromBothEnds() {
        let t = thumb(ind: (50, 20), o: 0)
        #expect(close(t?.origin, 53), "the start inset plus the gap")
        #expect(close(t?.length, 724.0 / 4.0), "fraction × track 800 − 70 − 6")
        let end = thumb(ind: (50, 20), o: 2400)
        #expect(close(end.map { $0.origin + $0.length }, 800 - 20 - IndicatorStyle.edgeGap))
    }

    @Test func aVisibleOtherAxisShortensTheTrackByItsThicknessAndGap() {
        let alone = thumb(o: 2400)!
        let shared = thumb(o: 2400, other: true)!
        let cost = IndicatorStyle.thickness + IndicatorStyle.edgeGap
        #expect(close(shared.origin + shared.length, alone.origin + alone.length - cost))
        #expect(close(shared.length, 800.0 / 3200.0 * (794 - cost)))
    }

    @Test func zoomScalesTheExtentLive() {
        #expect(thumb(C: 1000, s: 4, o: 0) == thumb(C: 4000, o: 0))
        let zoomed = thumb(C: 1000, s: 2, o: 0)!, more = thumb(C: 1000, s: 4, o: 0)!
        #expect(more.length < zoomed.length, "zooming in makes the thumb shorter")
        #expect(thumb(C: 700, s: 2, o: 0) != nil, "zoom makes a fitting content scrollable")
        #expect(thumb(C: 1000, s: -3, o: 0) == thumb(C: 1000, s: 1, o: 0), "a non-positive scale counts as 1")
    }

    @Test func rubberBandShrinksAndPinsAtTheStart() {
        let rest = thumb(o: 0)!
        let pulled = thumb(o: -50)!
        #expect(close(pulled.length, rest.length - 50) && close(pulled.origin, IndicatorStyle.edgeGap))
        #expect(close(thumb(o: -5000)?.length, IndicatorStyle.minLengthRubber), "never below the rubber minimum")
        #expect(close(thumb(o: -5000)?.origin, IndicatorStyle.edgeGap))
    }

    @Test func rubberBandShrinksAndPinsAtTheEnd() {
        let rest = thumb(o: 2400)!
        let pulled = thumb(o: 2450)!
        #expect(close(pulled.length, rest.length - 50))
        #expect(close(pulled.origin + pulled.length, 800 - IndicatorStyle.edgeGap), "stays pinned to the end gap")
        #expect(close(thumb(o: 9999)?.length, IndicatorStyle.minLengthRubber))
    }

    @Test func geometryIsContinuousAcrossTheEdges() {
        for edge in [CGFloat(0), 2400] {
            let inside = thumb(o: edge + (edge == 0 ? 0.001 : -0.001))!, outside = thumb(o: edge + (edge == 0 ? -0.001 : 0.001))!
            #expect(abs(inside.origin - outside.origin) < 0.01 && abs(inside.length - outside.length) < 0.01)
        }
    }

    // MARK: layout over both axes

    func metrics(viewport: CGSize = CGSize(width: 400, height: 800), content: CGSize, aci: EdgeInsets = EdgeInsets()) -> ScrollMetrics {
        var m = ScrollMetrics()
        m.viewportSize = viewport
        m.contentSize = content
        m.adjustedContentInset = aci
        return m
    }

    func layout(_ m: ScrollMetrics, offset: CGPoint = .zero, zoom: CGFloat = 1, resolved: ResolvedIndicators = ResolvedIndicators(),
                axes: Axis.Set, zoomEnabled: Bool = false, track: EdgeInsets = EdgeInsets()) -> IndicatorLayout {
        IndicatorMath.layout(offset: offset, zoom: zoom, metrics: m, trackInsets: track, resolved: resolved, axes: axes,
                             zoomEnabled: zoomEnabled)
    }

    @Test func aVerticalViewDrawsOnlyTheVerticalThumb() {
        let l = layout(metrics(content: CGSize(width: 400, height: 3000)), axes: .vertical)
        #expect(l.horizontal == nil)
        #expect(l.vertical == IndicatorMath.thumb(viewport: 800, content: 3000, zoom: 1, inset: (0, 0), indInset: (0, 0),
                                                  offset: 0, otherVisible: false))
    }

    @Test func twoVisibleThumbsShortenEachOther() {
        let m = metrics(content: CGSize(width: 1000, height: 3000))
        let l = layout(m, offset: CGPoint(x: 300, y: 700), axes: [.horizontal, .vertical])
        #expect(l.horizontal == IndicatorMath.thumb(viewport: 400, content: 1000, zoom: 1, inset: (0, 0), indInset: (0, 0),
                                                    offset: 300, otherVisible: true))
        #expect(l.vertical == IndicatorMath.thumb(viewport: 800, content: 3000, zoom: 1, inset: (0, 0), indInset: (0, 0),
                                                  offset: 700, otherVisible: true))
        // A hidden other axis does not take a track.
        let hidden = layout(m, offset: CGPoint(x: 300, y: 700),
                            resolved: ResolvedIndicators(horizontal: .hidden, vertical: .automatic), axes: [.horizontal, .vertical])
        #expect(hidden.horizontal == nil)
        #expect(hidden.vertical == IndicatorMath.thumb(viewport: 800, content: 3000, zoom: 1, inset: (0, 0), indInset: (0, 0),
                                                       offset: 700, otherVisible: false))
    }

    @Test func visibilityDecidesWhichThumbsDraw() {
        let m = metrics(content: CGSize(width: 1000, height: 3000))
        for (v, draws) in [(ZTronScrollIndicatorVisibility.automatic, true), (.visible, true), (.hidden, false), (.never, false)] {
            let l = layout(m, resolved: ResolvedIndicators(horizontal: v, vertical: v), axes: [.horizontal, .vertical])
            #expect((l.horizontal != nil) == draws && (l.vertical != nil) == draws, "\(v)")
        }
        // `.visible` never draws a thumb on an axis the content does not exceed.
        let fits = layout(metrics(content: CGSize(width: 400, height: 3000)),
                          resolved: ResolvedIndicators(horizontal: .visible, vertical: .visible), axes: [.horizontal, .vertical])
        #expect(fits.horizontal == nil && fits.vertical != nil)
    }

    @Test func anAxisOutsideTheViewsAxesDrawsOnlyWhenZoomMovesIt() {
        let wide = metrics(content: CGSize(width: 1000, height: 3000))
        #expect(layout(wide, axes: .vertical).horizontal == nil)
        #expect(layout(wide, axes: .vertical, zoomEnabled: true).horizontal != nil, "D15: zoom-enabled pan moves on any exceeded axis")
    }

    @Test func zoomLengthensTheExtentInTheLayout() {
        let m = metrics(content: CGSize(width: 400, height: 500))
        #expect(layout(m, axes: .vertical).vertical == nil)
        #expect(layout(m, zoom: 3, axes: .vertical).vertical != nil)
    }

    @Test func trackInsetsAddTheAdjustedSafeAreaThePropertyAndTheViewMargins() {
        var m = metrics(content: CGSize(width: 400, height: 3000))
        m.contentInset = EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        m.adjustedContentInset = EdgeInsets(top: 79, leading: 0, bottom: 34, trailing: 0)      // 59 pt bar + 34 pt home indicator
        m.indicatorInsets = EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 2)
        let t = IndicatorMath.trackInsets(m, extra: EdgeInsets(top: 7, leading: 0, bottom: 1, trailing: 0))
        #expect(t == EdgeInsets(top: 71, leading: 0, bottom: 35, trailing: 2))
        // The refresh hold is part of the adjusted inset but not of the track.
        m.refreshHold = EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        m.adjustedContentInset.top = 139
        #expect(IndicatorMath.trackInsets(m, extra: EdgeInsets()) == EdgeInsets(top: 64, leading: 0, bottom: 34, trailing: 2))
        // A content inset alone (no safe area applied) does not move the track.
        m.refreshHold = EdgeInsets()
        m.adjustedContentInset = EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        #expect(IndicatorMath.trackInsets(m, extra: EdgeInsets()) == EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 2))
    }

    @Test func trackInsetsTakeEffectOnTheThumb() {
        let m = metrics(content: CGSize(width: 400, height: 3000))
        let plain = layout(m, axes: .vertical).vertical!
        let inset = layout(m, axes: .vertical, track: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)).vertical!
        #expect(inset.origin == plain.origin + 59 && inset.length < plain.length)
    }

    // MARK: overshoot (the sample's bounds)

    @Test func overshootIsTheSignedDistanceOutsideTheBounds() {
        var m = metrics(content: CGSize(width: 400, height: 3000), aci: EdgeInsets(top: 100, leading: 0, bottom: 0, trailing: 0))
        // y bounds: −100 … 2200 (3000 − 800), x bounds: 0 … 0 (the content fits).
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 0, y: -130), zoom: 1, metrics: m) == CGPoint(x: 0, y: -30))
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 0, y: 2260), zoom: 1, metrics: m) == CGPoint(x: 0, y: 60))
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 0, y: 500), zoom: 1, metrics: m) == .zero)
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 12, y: 0), zoom: 1, metrics: m) == CGPoint(x: 12, y: 0))
        #expect(ChromeSample.overshoot(offset: CGPoint(x: -7, y: 0), zoom: 1, metrics: m) == CGPoint(x: -7, y: 0))
        // Zoom moves the end bound: 3000 × 2 − 800.
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 0, y: 5300), zoom: 2, metrics: m) == CGPoint(x: 0, y: 100))
        m.adjustedContentInset = EdgeInsets()
        #expect(ChromeSample.overshoot(offset: CGPoint(x: 0, y: -1), zoom: 1, metrics: m) == CGPoint(x: 0, y: -1))
    }

    @Test func theThumbShrinksByExactlyTheSamplesOvershoot() {
        let m = metrics(content: CGSize(width: 400, height: 3000))
        let rest = layout(m, offset: .zero, axes: .vertical).vertical!
        let o = ChromeSample.overshoot(offset: CGPoint(x: 0, y: -45), zoom: 1, metrics: m)
        let pulled = layout(m, offset: CGPoint(x: 0, y: -45), axes: .vertical).vertical!
        #expect(abs(rest.length - pulled.length - abs(o.y)) < 1e-9)
    }
}
