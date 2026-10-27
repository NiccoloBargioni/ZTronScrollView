import SwiftUI
import Testing
@testable import ZTronScrollView

/// Design M8b §3 test 6 (and the pure halves of 8 / 10): the header math, no state.
@MainActor @Suite struct HeaderMathTests {
    static let profile = HeaderMetrics(min: 64, resting: 240, behavior: .preserve, width: 402)
    static var banner: HeaderMetrics { var m = profile; m.behavior = .stretch; return m }

    /// Metrics of a vertical 402 × 874 viewport with a 62 pt safe top, the header reserved on top, optional hold / inset.
    static func metrics(_ header: HeaderMetrics?, hold: CGFloat = 0, contentInset: CGFloat = 0) -> ScrollMetrics {
        var m = ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000))
        m.safeAreaInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        m.contentInset = EdgeInsets(top: contentInset, leading: 0, bottom: 0, trailing: 0)
        m.refreshHold = EdgeInsets(top: hold, leading: 0, bottom: 0, trailing: 0)
        m.header = header
        m.adjustedContentInset = ZTronScrollState.adjusted(contentInset: m.contentInset, safe: m.safeAreaInsets,
                                                           behavior: .automatic, axes: .vertical, hold: m.refreshHold,
                                                           header: header)
        return m
    }

    @Test(arguments: [ZTronHeaderScalingBehavior.preserve, .stretch])
    func theTableAcrossTheBand(behavior: ZTronHeaderScalingBehavior) {
        var h = Self.profile
        h.behavior = behavior
        let band = h.band
        #expect(band == 176)
        let m = Self.metrics(h)
        let top0 = HeaderMath.top0(m)
        #expect(top0 == 62, "the top edge is the safe-area top")
        for o in [-80, -20, 0, 20, band / 2, band, band + 50] as [CGFloat] {
            let g = HeaderMath.geometry(o: o, m: h)
            let c = min(max(o, 0), band), gap = max(0, -o)
            let expectedHeight = behavior == .preserve ? 240 - c : 240 - c + gap
            #expect(g.height == expectedHeight, "h at o′ = \(o)")
            #expect(g.height >= 0)
            #expect(g.progress == c / band)
            #expect(g.stretch == (behavior == .stretch ? gap : 0))
            #expect(g.minHeight == 64 && g.restingHeight == 240 && g.width == 402)
            // Content top in the viewport: aci.top − o′; the header's top edge top0 + translation (user decision
            // 2026-10-26: `.preserve` moves down with a pull, the gap opens ABOVE it), its bottom edge that + h.
            let contentTop = m.adjustedContentInset.top - o
            #expect(contentTop == top0 + 240 + gap - (o > 0 ? o : 0))
            let translation = HeaderMath.translation(o: o, m: h)
            #expect(translation == (behavior == .preserve ? gap : 0), "preserve translates by the pull, stretch is pinned")
            #expect(HeaderMath.gapAbove(o: o, m: h) == translation, "the gap above the header is the translation")
            let gapBelow = contentTop - (top0 + translation + g.height)
            if o <= 0 {
                #expect(gapBelow == 0, "both behaviors keep the header's bottom on the content's top under a pull")
            } else if o <= band {
                #expect(gapBelow == 0, "collapse: the header bottom is glued to the content top")
            } else {
                #expect(gapBelow < 0, "past the band the content scrolls under the header")
            }
        }
    }

    @Test func aZeroMinimumVanishesAtTheEndOfTheBand() {
        let h = HeaderMetrics(min: 0, resting: 200, behavior: .preserve, width: 390)
        #expect(HeaderMath.height(o: 200, m: h) == 0 && HeaderMath.height(o: 500, m: h) == 0)
        #expect(HeaderMath.geometry(o: 500, m: h).progress == 1)
    }

    @Test func sizesResolve() {
        let fixed = HeaderMath.resolve(size: .fixed(min: 64, max: 240), width: 402, natural: nil)
        #expect(fixed.metrics?.resting == 240 && fixed.metrics?.min == 64 && fixed.warning == nil)
        let aspect = HeaderMath.resolve(size: .aspectRatio(16.0 / 9.0), width: 402, natural: nil)
        #expect(aspect.metrics?.resting == 226.125 && aspect.metrics?.min == 0)
        #expect(HeaderMath.resolve(size: .aspectRatio(16.0 / 9.0), width: 0, natural: nil).metrics == nil, "width unknown")
        #expect(HeaderMath.resolve(size: .fit(min: 10), width: 402, natural: nil).metrics == nil, ".fit unmeasured")
        let fit = HeaderMath.resolve(size: .fit(min: 10), width: 402, natural: 180)
        #expect(fit.metrics?.resting == 180 && fit.metrics?.min == 10 && fit.warning == nil)
        let stretch = HeaderMath.resolve(size: .fixed(max: 100), width: 402, natural: nil, behavior: .stretch, vertical: false)
        #expect(stretch.metrics?.behavior == .stretch && stretch.metrics?.vertical == false)
    }

    @Test func degenerateRangesAreFixedHeadersThatStillStretch() {
        let r = HeaderMath.resolve(size: .fixed(min: 300, max: 200), width: 402, natural: nil, behavior: .stretch)
        let m = try! #require(r.metrics)
        #expect(r.warning != nil, "both bounds given the wrong way: DEBUG warning")
        #expect(m.resting == 300 && m.band == 0)
        #expect(HeaderMath.geometry(o: 50, m: m).progress == 0 && HeaderMath.height(o: 50, m: m) == 300)
        #expect(HeaderMath.height(o: -30, m: m) == 330, ".stretch still grows")
        #expect(HeaderMath.nearestSnap(to: 10, positions: [0, 1], m: m) == nil, "no snapping without a band")
        let aspect = HeaderMath.resolve(size: .aspectRatio(16.0 / 9.0, min: 400), width: 402, natural: nil)
        #expect(aspect.metrics?.resting == 400 && aspect.warning == nil, "min ≥ R from a computed size: fixed, no warning")
        let flexible = HeaderMath.resolve(size: .fit(), width: 402, natural: 0)
        #expect(flexible.warning?.contains(".frame(idealHeight:)") == true, "a flexible-only .fit header names the fix")
        #expect(HeaderMath.resolve(size: .aspectRatio(0), width: 402, natural: nil).warning != nil)
    }

    @Test func snapPositionsAreCollapseProgress() {
        let h = Self.profile
        #expect(HeaderMath.snapOffset(progress: 0.5, m: h) == 88)
        #expect(HeaderMath.snapOffset(progress: 3, m: h) == 176 && HeaderMath.snapOffset(progress: -1, m: h) == 0)
        #expect(HeaderMath.nearestSnap(to: 50, positions: [0, 1], m: h) == 0)
        #expect(HeaderMath.nearestSnap(to: 100, positions: [0, 1], m: h) == 176)
        #expect(HeaderMath.nearestSnap(to: 88, positions: [0, 1], m: h) == 0, "a tie goes to the expanded side")
        for o in [-10, 0, 176, 300] as [CGFloat] {
            #expect(HeaderMath.nearestSnap(to: o, positions: [0, 1], m: h) == nil, "only inside the open band")
        }
        // The migration row: the reference's [0, 0.5, 1] is ours [1, 0.5, 0]; the order does not matter.
        #expect(HeaderMath.nearestSnap(to: 60, positions: [1, 0.5, 0], m: h) == 88)
        #expect(HeaderMath.nearestSnap(to: 60, positions: [0, 0.5, 1], m: h) == 88)
        #expect(HeaderMath.nearestSnap(to: 60, positions: [], m: h) == nil)
    }

    @Test func snapTargetsClamp() {
        let h = Self.profile
        #expect(HeaderMath.offset(for: .expanded, m: h) == 0 && HeaderMath.offset(for: .collapsed, m: h) == 176)
        #expect(HeaderMath.offset(for: .progress(0.25), m: h) == 44)
        #expect(HeaderMath.offset(for: .progress(2), m: h) == 176 && HeaderMath.offset(for: .progress(-2), m: h) == 0)
        #expect(HeaderMath.offset(for: .height(100), m: h) == 140)
        #expect(HeaderMath.offset(for: .height(1000), m: h) == 0 && HeaderMath.offset(for: .height(1), m: h) == 176)
    }

    @Test func theHeaderOffsetExcludesTheHold() {
        let h = Self.profile
        let rest = Self.metrics(h)
        #expect(rest.adjustedContentInset.top == 302)
        #expect(HeaderMath.headerOffset(offset: CGPoint(x: 0, y: -302), zoom: 1, metrics: rest) == 0)
        let holding = Self.metrics(h, hold: 60)
        #expect(HeaderMath.headerOffset(offset: CGPoint(x: 0, y: -362), zoom: 1, metrics: holding) == -60,
                "a hold is seen as o′ = −H")
        #expect(HeaderMath.top0(holding) == 62)
        let inset = Self.metrics(h, contentInset: 20)
        #expect(HeaderMath.top0(inset) == 62 && HeaderMath.base(inset) == 322)
    }

    @Test func aViewWithoutTheVerticalAxisIsAFixedBanner() {
        var h = Self.profile
        h.vertical = false
        var m = Self.metrics(h)
        m.contentSize = CGSize(width: 2000, height: 300)
        #expect(HeaderMath.headerOffset(offset: CGPoint(x: 500, y: 100), zoom: 1, metrics: m) == 0, "any o.y")
        #expect(HeaderMath.geometry(offset: CGPoint(x: 500, y: -500), zoom: 1, metrics: m)?.height == 240)
        // D15: zoomed content that exceeds the unobscured height pans vertically and drives the header.
        let zoomed = HeaderMath.headerOffset(offset: CGPoint(x: 0, y: -302 + 50), zoom: 3, metrics: m)
        #expect(zoomed == 50)
    }

    @Test func obscuredDeltaIsTheLiveHeightAgainstTheReservedOne() {
        let m = Self.metrics(Self.banner)
        func delta(_ oPrime: CGFloat) -> CGFloat {
            HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: oPrime - HeaderMath.base(m)), zoom: 1, metrics: m)
        }
        #expect(delta(0) == 0 && delta(100) == -100 && delta(500) == -176 && delta(-40) == 40)
        #expect(HeaderMath.obscuredDelta(offset: .zero, zoom: 1, metrics: Self.metrics(nil)) == 0)
        // `.preserve` (user decision 2026-10-26): the header keeps R and moves down by the pull: its bottom edge is 40 pt
        // lower too.
        let p = Self.metrics(Self.profile)
        #expect(HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: -40 - HeaderMath.base(p)), zoom: 1, metrics: p) == 40)
    }

    /// User decision 2026-10-26 (reverses A1): under a pull `.preserve` translates by `g` with its height `R`; the refresh
    /// base is the slot's top (`top0`), the gap `[top0, top0 + g]` above the header; `.stretch` keeps `top0 + R`, overlay.
    @Test func aPreservedHeaderTranslatesWithThePull() {
        let h = Self.profile
        for g in [0, 1, 30, 120] as [CGFloat] {
            #expect(HeaderMath.translation(o: -g, m: h) == g && HeaderMath.height(o: -g, m: h) == 240)
            #expect(HeaderMath.translation(o: -g, m: Self.banner) == 0 && HeaderMath.height(o: -g, m: Self.banner) == 240 + g)
        }
        #expect(HeaderMath.translation(o: 50, m: h) == 0, "no translation while collapsing")
        #expect(HeaderMath.translation(o: .nan, m: h) == 0)
        let preserve = HeaderMath.refreshTop(Self.metrics(h, hold: 60))
        #expect(preserve?.base == 62 && preserve?.overlay == false, "the gap above the header: [top0, top0 + pull]")
        let stretch = HeaderMath.refreshTop(Self.metrics(Self.banner, hold: 60))
        #expect(stretch?.base == 302 && stretch?.overlay == true, "over the stretched band")
        #expect(HeaderMath.refreshTop(Self.metrics(nil)) == nil)
    }

    /// The layout resolves `R(W, H)` with the same size and overflow policy as the state (D59), so the committed resting
    /// height and the layout's agree exactly at the committed viewport, and `liveHeight` equals the state's `R − c + s`.
    @Test(arguments: [ZTronHeaderOverflow.uncapped, .capped(fraction: 0.5), .refit])
    func theLayoutAndTheStateResolveTheSameRestingHeight(overflow: ZTronHeaderOverflow) {
        let safe = EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
        for size in [ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64), .fixed(min: 64, max: 500), .fit(min: 64)] {
            for viewport in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 874), CGSize(width: 750, height: 402)] {
                let container = HeaderMath.containerHeight(viewport: viewport, safe: safe, adjusted: .vertical)
                let natural = viewport.width * 9 / 16
                guard let state = HeaderMath.resolve(size: size, width: viewport.width, natural: natural,
                                                     containerHeight: container, overflow: overflow).metrics else {
                    Issue.record("unresolved \(size)"); continue
                }
                // The overlay is proposed the viewport below the safe-area top; the layout subtracts the bottom inset.
                let proposedHeight = viewport.height - safe.top
                for p in [0, 0.25, 1] as [CGFloat] {
                    let live = HeaderLiveInput(size: size, overflow: overflow,
                                               metrics: HeaderMetrics(min: 1, resting: 2, behavior: .preserve, width: 1),
                                               progress: p, bottomInset: safe.bottom, committedContainer: 1)
                    let r = HeaderMath.layoutResting(width: viewport.width, containerHeight: proposedHeight - safe.bottom,
                                                     natural: natural, live)
                    #expect(r.resting == state.resting && r.min == min(state.min, state.resting),
                            "\(size) \(overflow) \(viewport): layout \(r) vs state \(state.resting) / \(state.min)")
                    let h = HeaderMath.liveHeight(width: viewport.width, containerHeight: proposedHeight - safe.bottom,
                                                  natural: natural, live)
                    #expect(abs(h - (state.resting - p * state.band)) < 1e-9, "\(size) \(overflow) \(viewport) p \(p): h \(h)")
                }
            }
        }
    }

    /// `scrollTo` anchors are evaluated at the target (M6 §4): the unobscured top edge is `aci.top + h(target) − R`.
    @Test func scrollTargetsSolveForTheHeaderAtTheTarget() {
        let m = Self.metrics(Self.profile)
        let top = m.adjustedContentInset.top, a = HeaderMath.base(m), band: CGFloat = 176
        func delta(_ o: CGFloat) -> CGFloat { HeaderMath.height(o: o + a, m: Self.profile) - 240 }
        // Top anchor of an item at content y: `y − I`.
        let first = HeaderMath.solveTarget(metrics: m) { 0 - $0 }
        #expect(first == -top, "the first item at the top: the header stays expanded (rest)")
        let deep = HeaderMath.solveTarget(metrics: m) { 900 - $0 }
        #expect(deep == 900 - (top - band), "far down: the header is collapsed at the target and the item sits under it")
        #expect(deep + a >= band)
        // Centre anchor inside the band: `y − I − (V − I − b) / 2`, solved consistently.
        let v: CGFloat = 874, b: CGFloat = 34
        func center(_ y: CGFloat) -> (CGFloat) -> CGFloat { { i in y - i - (v - i - b) / 2 } }
        for y in [280, 300, 340, 420] as [CGFloat] {
            let o = HeaderMath.solveTarget(metrics: m, place: center(y))
            #expect(abs(o - center(y)(top + delta(o))) < 0.01, "o = place(aci.top + δ(o)) at y = \(y)")
        }
        #expect(HeaderMath.solveTarget(metrics: Self.metrics(nil)) { 900 - $0 } == 838, "no header: plain")
    }

    @Test func aMetricsChangeKeepsTheProgress() {
        let old = Self.metrics(Self.profile)
        let new = Self.metrics(HeaderMetrics(min: 64, resting: 300, behavior: .preserve, width: 402))
        func keep(_ oPrime: CGFloat) -> CGFloat {
            HeaderMath.keepProgress(offsetY: oPrime - HeaderMath.base(old), old: old, new: new)! + HeaderMath.base(new)
        }
        #expect(keep(0) == 0 && keep(-30) == -30, "at or above rest: o′ kept")
        #expect(keep(88) == 118, "inside the band: progress 0.5 of the new band (236)")
        #expect(keep(500) == 560, "collapsed: the content stays where it was (o kept), still collapsed")
        #expect(HeaderMath.keepProgress(offsetY: 0, old: Self.metrics(nil), new: new) == nil, "install: the plain inset rule")
    }

    /// D59 (user, 2026-10-25): the overflow policy. A full-width 16:9 banner in landscape (874 pt wide, a 381 pt tall
    /// container below the 21 pt bottom safe area) is 491.625 pt uncapped.
    @Test func theOverflowPolicyLimitsTheRestingHeightAndMin() {
        func r(_ size: ZTronHeaderSize, _ policy: ZTronHeaderOverflow, natural: CGFloat? = nil) -> HeaderMetrics? {
            HeaderMath.resolve(size: size, width: 874, natural: natural, containerHeight: 381, overflow: policy).metrics
        }
        let banner = ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64)
        #expect(r(banner, .uncapped)?.resting == 491.625, "the default keeps W / r")
        #expect(r(banner, .capped(fraction: 0.5))?.resting == 190.5)
        #expect(r(banner, .refit)?.resting == 381, "the aspect fit of 16:9 inside 874 x 381 is 381 tall")
        #expect(r(.aspectRatio(16.0 / 9.0), .refit)?.resting == 381)
        #expect(HeaderMath.resolve(size: banner, width: 402, natural: nil, containerHeight: 778, overflow: .refit).metrics?.resting
                == 226.125, "a header that fits is untouched")
        #expect(r(.fixed(min: 64, max: 500), .refit)?.resting == 381)
        #expect(r(.fixed(min: 64, max: 500), .capped(fraction: 0.6))?.resting == 228.6)
        #expect(r(.fit(), .refit, natural: 600)?.resting == 381)
        let tight = r(.fixed(min: 300, max: 400), .capped(fraction: 0.5))
        #expect(tight?.resting == 190.5 && tight?.min == 190.5 && tight?.band == 0, "min is limited the same way")
        #expect(HeaderMath.resolve(size: banner, width: 874, natural: nil, containerHeight: 0, overflow: .refit).metrics?.resting
                == 491.625, "an unknown container limits nothing")
        let odd = HeaderMath.resolve(size: banner, width: 874, natural: nil, containerHeight: 381, overflow: .capped(fraction: 3))
        #expect(odd.metrics?.resting == 381 && odd.warning != nil, "a fraction outside 0…1 is clamped, with a DEBUG warning")
        #expect(HeaderMath.containerHeight(viewport: CGSize(width: 874, height: 402),
                                           safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), adjusted: .vertical) == 381)
        #expect(HeaderMath.containerHeight(viewport: CGSize(width: 874, height: 402),
                                           safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), adjusted: []) == 402)
    }
}
