import SwiftUI
import Testing
@testable import ZTronScrollView

/// Design M8b §3 test 6 (and the pure halves of 8 / 10): the header math, no state.
@MainActor @Suite struct HeaderMathTests {
    static let profile = HeaderMetrics(min: 64, resting: 240, behavior: .preserve, width: 402)
    static var banner: HeaderMetrics { var m = profile; m.behavior = .stretch; return m }
    /// D61's `.preserve` (the header moves down with the content), opt-in since D65.
    static var following: HeaderMetrics { var m = profile; m.pull = .followContent; return m }

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

    @Test(arguments: [ZTronHeaderScalingBehavior.preserve, .stretch], [ZTronHeaderPullBehavior.openGap, .followContent])
    func theTableAcrossTheBand(behavior: ZTronHeaderScalingBehavior, pull: ZTronHeaderPullBehavior) {
        var h = Self.profile
        h.behavior = behavior
        h.pull = pull
        #expect(Self.profile.pull == .openGap, "D65: the default is .openGap")
        let follows = behavior == .preserve && pull == .followContent
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
            // Content top in the viewport: aci.top − o′; the header's top edge top0 + translation (`.preserve`
            // `.followContent`, D61: it moves down with a pull, the gap opens ABOVE it; `.openGap`, D65: it stays, the gap
            // opens BELOW it), its bottom edge that + h.
            let contentTop = m.adjustedContentInset.top - o
            #expect(contentTop == top0 + 240 + gap - (o > 0 ? o : 0))
            let translation = HeaderMath.translation(o: o, m: h)
            #expect(translation == (follows ? gap : 0), "\(behavior) \(pull): only .followContent translates by the pull")
            #expect(HeaderMath.gapAbove(o: o, m: h) == translation, "the gap above the header is the translation")
            let below = HeaderMath.gapBelow(o: o, m: h)
            #expect(below == (behavior == .preserve && pull == .openGap ? gap : 0), "\(behavior) \(pull): the gap below")
            let gapBelow = contentTop - (top0 + translation + g.height)
            if o <= 0 {
                #expect(gapBelow == below, "\(behavior) \(pull) o′ \(o): the content's top is the header's bottom + gapBelow")
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
        let fixed = HeaderMath.metrics(size: .fixed(min: 64, max: 240), width: 402, natural: nil)
        #expect(fixed?.resting == 240 && fixed?.min == 64)
        #expect(HeaderMath.warning(size: .fixed(min: 64, max: 240), width: 402, natural: nil) == nil)
        let aspect = HeaderMath.metrics(size: .aspectRatio(16.0 / 9.0), width: 402, natural: nil)
        #expect(aspect?.resting == 226.125 && aspect?.min == 0)
        #expect(HeaderMath.metrics(size: .aspectRatio(16.0 / 9.0), width: 0, natural: nil) == nil, "width unknown")
        #expect(HeaderMath.metrics(size: .fit(min: 10), width: 402, natural: nil) == nil, ".fit unmeasured")
        #expect(HeaderMath.warning(size: .aspectRatio(0), width: 0, natural: nil) == nil, "unresolved: no warning yet")
        #expect(HeaderMath.warning(size: .fit(), width: 402, natural: nil) == nil, "unmeasured: no warning yet")
        let fit = HeaderMath.metrics(size: .fit(min: 10), width: 402, natural: 180)
        #expect(fit?.resting == 180 && fit?.min == 10)
        #expect(HeaderMath.warning(size: .fit(min: 10), width: 402, natural: 180) == nil)
        let stretch = HeaderMath.metrics(size: .fixed(max: 100), width: 402, natural: nil, behavior: .stretch, vertical: false)
        #expect(stretch?.behavior == .stretch && stretch?.vertical == false)
    }

    @Test func degenerateRangesAreFixedHeadersThatStillStretch() {
        let m = try! #require(HeaderMath.metrics(size: .fixed(min: 300, max: 200), width: 402, natural: nil, behavior: .stretch))
        #expect(HeaderMath.warning(size: .fixed(min: 300, max: 200), width: 402, natural: nil) != nil,
                "both bounds given the wrong way: DEBUG warning")
        #expect(m.resting == 300 && m.band == 0)
        #expect(HeaderMath.geometry(o: 50, m: m).progress == 0 && HeaderMath.height(o: 50, m: m) == 300)
        #expect(HeaderMath.height(o: -30, m: m) == 330, ".stretch still grows")
        #expect(HeaderMath.nearestSnap(to: 10, positions: [0, 1], m: m) == nil, "no snapping without a band")
        #expect(HeaderMath.metrics(size: .aspectRatio(16.0 / 9.0, min: 400), width: 402, natural: nil)?.resting == 400)
        #expect(HeaderMath.warning(size: .aspectRatio(16.0 / 9.0, min: 400), width: 402, natural: nil) == nil,
                "min ≥ R from a computed size: fixed, no warning")
        #expect(HeaderMath.warning(size: .fit(), width: 402, natural: 0)?.contains(".frame(idealHeight:)") == true,
                "a flexible-only .fit header names the fix")
        #expect(HeaderMath.warning(size: .aspectRatio(0), width: 402, natural: nil) != nil)
        #expect(HeaderMath.metrics(size: .aspectRatio(0), width: 402, natural: nil)?.resting == 0, "a bad ratio: no height")
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
        // `.preserve` `.followContent` (D61): the header keeps R and moves down by the pull: its bottom edge is 40 pt lower
        // too. `.openGap` (D65, the default; pre-D61 `h − R`): it stays still, its bottom edge too.
        let f = Self.metrics(Self.following)
        #expect(HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: -40 - HeaderMath.base(f)), zoom: 1, metrics: f) == 40)
        let o = Self.metrics(Self.profile)
        #expect(HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: -40 - HeaderMath.base(o)), zoom: 1, metrics: o) == 0)
        for p in [f, o] {
            #expect(HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: 100 - HeaderMath.base(p)), zoom: 1, metrics: p) == -100,
                    "collapse is the same in both modes")
        }
    }

    /// D61 (`.followContent`): under a pull `.preserve` translates by `g` with its height `R`; the refresh base is the
    /// slot's top (`top0`), the gap `[top0, top0 + g]` above the header; `.stretch` keeps `top0 + R`, overlay.
    @Test func aFollowingHeaderTranslatesWithThePull() {
        let h = Self.following
        for g in [0, 1, 30, 120] as [CGFloat] {
            #expect(HeaderMath.translation(o: -g, m: h) == g && HeaderMath.height(o: -g, m: h) == 240)
            #expect(HeaderMath.gapAbove(o: -g, m: h) == g && HeaderMath.gapBelow(o: -g, m: h) == 0)
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

    /// D65 (`.openGap`, the default; the pre-D61 math): under a pull the `.preserve` header stays still at its resting
    /// place and height (translation 0), the gap `g` opens between its bottom edge and the content's top, and the refresh
    /// base is the plain one (`refreshTop` nil: `aci.top − hold`, the resting header's bottom edge). `.stretch` ignores the
    /// setting, and so does a banner (D65: unaffected, it keeps the translation).
    @Test func anOpenGapHeaderStaysStillUnderAPull() {
        let h = Self.profile
        #expect(h.pull == .openGap)
        for g in [0, 1, 30, 120] as [CGFloat] {
            #expect(HeaderMath.translation(o: -g, m: h) == 0 && HeaderMath.gapAbove(o: -g, m: h) == 0)
            #expect(HeaderMath.gapBelow(o: -g, m: h) == g && HeaderMath.height(o: -g, m: h) == 240)
            #expect(HeaderMath.geometry(o: -g, m: h).stretch == 0)
        }
        #expect(HeaderMath.gapBelow(o: 50, m: h) == 0 && HeaderMath.gapBelow(o: .nan, m: h) == 0)
        let m = Self.metrics(h, hold: 60)
        #expect(HeaderMath.refreshTop(m) == nil, "the plain base")
        let (base, overlay) = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false)
        #expect(base.top == 302 && !overlay, "aci.top − hold = top0 + R: the resting header's bottom edge")
        #expect(RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: true).1, "placement as the refresher says")
        // `.stretch` is the same in both modes.
        for pull in [ZTronHeaderPullBehavior.openGap, .followContent] {
            var s = Self.banner
            s.pull = pull
            #expect(HeaderMath.translation(o: -40, m: s) == 0 && HeaderMath.gapBelow(o: -40, m: s) == 0
                        && HeaderMath.height(o: -40, m: s) == 280)
            let top = HeaderMath.refreshTop(Self.metrics(s, hold: 60))
            #expect(top?.base == 302 && top?.overlay == true)
        }
        // A banner (no vertical axis) keeps the translation in both modes (only zoomed content that pans pulls it, D15).
        for pull in [ZTronHeaderPullBehavior.openGap, .followContent] {
            var b = Self.profile
            b.vertical = false
            b.pull = pull
            #expect(HeaderMath.translation(o: -40, m: b) == 40 && HeaderMath.gapBelow(o: -40, m: b) == 0, "\(pull)")
        }
    }

    /// The pull behavior rides on the resolved metrics (cold): `metrics(…, pull:)` and `HeaderSizing.resolve` carry it,
    /// the default is `.openGap`, and nothing else in the metrics depends on it.
    @Test func thePullBehaviorIsPartOfTheResolvedMetrics() {
        let a = HeaderMath.metrics(size: .fixed(min: 64, max: 240), width: 402, natural: nil)
        let b = HeaderMath.metrics(size: .fixed(min: 64, max: 240), width: 402, natural: nil, pull: .followContent)
        #expect(a?.pull == .openGap && b?.pull == .followContent && a != b)
        var c = b
        c?.pull = .openGap
        #expect(a == c, "only the pull differs")
        let sizing = HeaderSizing(size: .fixed(min: 64, max: 240), behavior: .preserve, snap: .disabled)
        #expect(sizing.pull == .openGap)
        var following = sizing
        following.pull = .followContent
        #expect(following != sizing)
        #expect(following.resolve(width: 402, natural: nil, vertical: true, containerHeight: 778)?.pull == .followContent)
        #expect(sizing.resolve(width: 402, natural: nil, vertical: true, containerHeight: 778)?.pull == .openGap)
    }

    /// The layout resolves `R(W, H)` with the same size and overflow policy as the state (D59), so the committed resting
    /// height and the layout's agree exactly at the committed viewport, and `liveHeight` equals the state's layout height `R − c` (D69: no stretch).
    @Test(arguments: [ZTronHeaderOverflow.uncapped, .capped(fraction: 0.5), .refit])
    func theLayoutAndTheStateResolveTheSameRestingHeight(overflow: ZTronHeaderOverflow) {
        let safe = EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
        for size in [ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64), .fixed(min: 64, max: 500), .fit(min: 64)] {
            for viewport in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 874), CGSize(width: 750, height: 402)] {
                let container = HeaderMath.containerHeight(viewport: viewport, safe: safe, adjusted: .vertical)
                let natural = viewport.width * 9 / 16
                guard let state = HeaderMath.metrics(size: size, width: viewport.width, natural: natural,
                                                     containerHeight: container, overflow: overflow) else {
                    Issue.record("unresolved \(size)"); continue
                }
                // The slot is proposed the region between the safe areas (M8b-s6): its height is the container.
                let proposedHeight = viewport.height - safe.top - safe.bottom
                for p in [0, 0.25, 1] as [CGFloat] {
                    let live = HeaderLiveInput(size: size, overflow: overflow,
                                               metrics: HeaderMetrics(min: 1, resting: 2, behavior: .preserve, width: 1),
                                               progress: p, committedContainer: 1)
                    let r = HeaderMath.layoutResting(width: viewport.width, containerHeight: proposedHeight,
                                                     natural: natural, live)
                    #expect(r.resting == state.resting && r.min == min(state.min, state.resting),
                            "\(size) \(overflow) \(viewport): layout \(r) vs state \(state.resting) / \(state.min)")
                    let h = HeaderMath.liveHeight(width: viewport.width, containerHeight: proposedHeight,
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
            HeaderMath.metrics(size: size, width: 874, natural: natural, containerHeight: 381, overflow: policy)
        }
        let banner = ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64)
        #expect(r(banner, .uncapped)?.resting == 491.625, "the default keeps W / r")
        #expect(r(banner, .capped(fraction: 0.5))?.resting == 190.5)
        #expect(r(banner, .refit)?.resting == 381, "the aspect fit of 16:9 inside 874 x 381 is 381 tall")
        #expect(r(.aspectRatio(16.0 / 9.0), .refit)?.resting == 381)
        #expect(HeaderMath.metrics(size: banner, width: 402, natural: nil, containerHeight: 778, overflow: .refit)?.resting
                == 226.125, "a header that fits is untouched")
        #expect(r(.fixed(min: 64, max: 500), .refit)?.resting == 381)
        #expect(r(.fixed(min: 64, max: 500), .capped(fraction: 0.6))?.resting == 228.6)
        #expect(r(.fit(), .refit, natural: 600)?.resting == 381)
        let tight = r(.fixed(min: 300, max: 400), .capped(fraction: 0.5))
        #expect(tight?.resting == 190.5 && tight?.min == 190.5 && tight?.band == 0, "min is limited the same way")
        #expect(HeaderMath.metrics(size: banner, width: 874, natural: nil, containerHeight: 0, overflow: .refit)?.resting
                == 491.625, "an unknown container limits nothing")
        let odd = HeaderMath.metrics(size: banner, width: 874, natural: nil, containerHeight: 381, overflow: .capped(fraction: 3))
        let oddWarning = HeaderMath.warning(size: banner, width: 874, natural: nil, containerHeight: 381, overflow: .capped(fraction: 3))
        #expect(odd?.resting == 381 && oddWarning != nil, "a fraction outside 0…1 is clamped, with a DEBUG warning")
        #expect(HeaderMath.warning(size: banner, width: 874, natural: nil, containerHeight: 0, overflow: .capped(fraction: 3)) == nil,
                "no container: the fraction limits nothing, no warning")
        #expect(HeaderMath.containerHeight(viewport: CGSize(width: 874, height: 402),
                                           safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), adjusted: .vertical) == 381)
        #expect(HeaderMath.containerHeight(viewport: CGSize(width: 874, height: 402),
                                           safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), adjusted: []) == 402)
    }

    /// D64 (lead, 2026-10-27): the overflow container excludes the keyboard. With the keyboard up the bottom safe area is
    /// the keyboard's (the scroll view's frame ends at its top); the probe's `keyboard` (how far it reaches above the
    /// keyboard-free safe area) is given back, so the container, and with it `R` and `min` under every policy, is the one
    /// without the keyboard. The slot (frame + the same extension: its overlay ignores the `.keyboard` region) agrees.
    @Test(arguments: [ZTronHeaderOverflow.uncapped, .capped(fraction: 0.5), .refit])
    func theKeyboardIsNotPartOfTheContainer(overflow: ZTronHeaderOverflow) {
        // (viewport, safe area without the keyboard, the keyboard's bottom inset): portrait and landscape, 27.0 sizes.
        let cases: [(CGSize, EdgeInsets, CGFloat)] = [
            (CGSize(width: 402, height: 874), EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), 336),
            (CGSize(width: 874, height: 402), EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), 224),
            (CGSize(width: 393, height: 852), EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), 1000.0 / 3),
        ]
        for (viewport, free, kb) in cases {
            var up = free
            up.bottom = kb
            let ext = kb - free.bottom
            let without = HeaderMath.containerHeight(viewport: viewport, safe: free, adjusted: .vertical)
            let with = HeaderMath.containerHeight(viewport: viewport, safe: up, adjusted: .vertical, keyboard: ext)
            #expect(with == without, "\(viewport): \(with) vs \(without)")
            // The slot: the frame between the safe areas (ending at the keyboard's top), extended by the probe's height.
            let slot = (viewport.height - up.top - up.bottom) + ext
            #expect(slot == with, "\(viewport): slot \(slot) vs state \(with)")
            for size in [ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64), .fixed(min: 300, max: 500), .fit(min: 64)] {
                let a = HeaderMath.metrics(size: size, width: viewport.width, natural: 400, containerHeight: without, overflow: overflow)
                let b = HeaderMath.metrics(size: size, width: viewport.width, natural: 400, containerHeight: with, overflow: overflow)
                #expect(a != nil && a == b, "\(size) \(overflow) \(viewport): \(String(describing: a)) vs \(String(describing: b))")
            }
            // Without the extension the keyboard would shrink the container (the measured defect: R 190.5 -> 89 in landscape).
            #expect(HeaderMath.containerHeight(viewport: viewport, safe: up, adjusted: .vertical) == without - ext)
            // A view that does not adjust its bottom edge (`.never`): its viewport is the frame the keyboard shrank.
            let shrunk = CGSize(width: viewport.width, height: viewport.height - kb)
            #expect(HeaderMath.containerHeight(viewport: shrunk, safe: up, adjusted: [], keyboard: ext)
                    == viewport.height - free.bottom, "\(viewport): .never")
        }
        let base = HeaderMath.containerHeight(viewport: CGSize(width: 402, height: 874),
                                              safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), adjusted: .vertical)
        for bad in [-5, .nan, .infinity] as [CGFloat] {
            #expect(HeaderMath.containerHeight(viewport: CGSize(width: 402, height: 874),
                                               safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), adjusted: .vertical,
                                               keyboard: bad) == base, "a degenerate extension \(bad) counts as none")
        }
    }

    // MARK: D68 / D69 (design M8b-header-behaviors §2, §5 test 1)

    /// The profile header behind the content, parallax `k`, as resolved (`min` 0: ignored).
    static func sliding(_ k: CGFloat = 0.5, _ behavior: ZTronHeaderScalingBehavior = .preserve) -> HeaderMetrics {
        var m = profile
        m.collapse = .slideBehind(parallax: k)
        m.behavior = behavior
        m.min = 0
        return m
    }

    static func delta(_ oPrime: CGFloat, _ m: ScrollMetrics) -> CGFloat {
        HeaderMath.obscuredDelta(offset: CGPoint(x: 0, y: oPrime - HeaderMath.base(m)), zoom: 1, metrics: m)
    }

    @Test func theBandFollowsTheCollapseMode() {
        #expect(Self.profile.band == 176 && Self.profile.collapsedHeight == 64)
        #expect(Self.sliding().band == 240 && Self.sliding().collapsedHeight == 0, ".slideBehind: R")
        var raw = Self.profile
        raw.collapse = .slideBehind(parallax: 0.5)
        #expect(raw.band == 240 && raw.collapsedHeight == 0, "min ignored even when set")
        #expect(HeaderMath.resizeGeometry(Self.metrics(Self.sliding()))?.band == 240, "S7 keeps the covered fraction")
        // Resolved: `.slideBehind` ignores `min`, and so the `min ≥ R` rule (which makes a fixed `.compress` header).
        let sb = ZTronHeaderCollapseBehavior.Kind.slideBehind(parallax: 0.5)
        let m = HeaderMath.metrics(size: .fixed(min: 64, max: 240), width: 402, natural: nil, collapse: sb)
        #expect(m?.min == 0 && m?.resting == 240 && m?.band == 240 && m?.collapse == sb)
        let tall = HeaderMath.metrics(size: .fixed(min: 300, max: 240), width: 402, natural: nil, collapse: sb)
        #expect(tall?.resting == 240 && tall?.band == 240)
        let fixed = HeaderMath.metrics(size: .fixed(min: 300, max: 240), width: 402, natural: nil)
        #expect(fixed?.resting == 300 && fixed?.band == 0, ".compress keeps the min ≥ R rule")
        // The overflow policy resolves R as it does for `.compress` (D59).
        let capped = HeaderMath.metrics(size: .aspectRatio(16.0 / 9.0, min: 64), width: 874, natural: nil, collapse: sb,
                                        containerHeight: 381, overflow: .capped(fraction: 0.5))
        #expect(capped?.resting == 190.5 && capped?.min == 0 && capped?.band == 190.5)
        let refit = HeaderMath.metrics(size: .aspectRatio(16.0 / 9.0), width: 874, natural: nil, collapse: sb,
                                       containerHeight: 381, overflow: .refit)
        #expect(refit?.resting == 381)
        // The layout resolves the same R and min (`layoutResting`), so its `h_L` = R.
        let live = HeaderLiveInput(size: .fixed(min: 64, max: 240), metrics: m, committedContainer: 778)
        let laidOut = HeaderMath.layoutResting(width: 402, containerHeight: 778, natural: nil, live)
        #expect(laidOut.resting == 240 && laidOut.min == 0)
    }

    @Test(arguments: [CGFloat(0), 0.25, 0.5, 1], [ZTronHeaderScalingBehavior.preserve, .stretch])
    func slideBehindGeometry(k: CGFloat, behavior: ZTronHeaderScalingBehavior) {
        let h = Self.sliding(k, behavior)
        let m = Self.metrics(h)
        let top0 = HeaderMath.top0(m)
        for o in [-80, -20, 0, 20, 120, 239, 240, 400] as [CGFloat] {
            let c = min(max(o, 0), 240), g = max(0, -o)
            let geo = HeaderMath.geometry(o: o, m: h)
            let stretch = behavior == .stretch ? g : 0
            #expect(geo.progress == c / 240, "o′ \(o): the covered fraction")
            #expect(geo.height == 240 + stretch, "o′ \(o): the drawn height R (+ g under .stretch)")
            #expect(geo.stretch == stretch && geo.minHeight == 0 && geo.restingHeight == 240)
            #expect(HeaderMath.visibleHeight(o: o, m: h) == 240 - c + stretch)
            #expect(HeaderMath.layoutHeight(o: o, m: h) == 240, "h_L = R: the header keeps its height")
            let tc = HeaderMath.collapseTranslation(o: o, m: h)
            #expect(tc == -k * c && tc >= -k * 240, "t_c = −k·c, at most k·R")
            #expect(abs(HeaderMath.collapseTranslation(progress: geo.progress, parallax: k, layoutHeight: 240) - tc) < 1e-9,
                    "the layout's −k·p·h_L agrees at the committed R")
            // The content's top edge is the visible band's end, the drawn header's top edge t_c above top0 (+ t_g).
            let contentTop = m.adjustedContentInset.top - o
            let t = HeaderMath.translation(o: o, m: h)
            #expect(contentTop == top0 + t + HeaderMath.visibleHeight(o: o, m: h) + HeaderMath.gapBelow(o: o, m: h)
                        - max(0, o - 240), "o′ \(o)")
            #expect(Self.delta(o, m) == -c + stretch + t, "obscuredDelta: h_v + t_g − R")
        }
    }

    @Test func compressKeepsItsTable() {
        // The new helpers on `.compress`: h_L = R − c (no stretch: D69), t_c = 0, h_v = today's live height.
        for behavior in [ZTronHeaderScalingBehavior.preserve, .stretch] {
            var h = Self.profile
            h.behavior = behavior
            for o in [-80, 0, 100, 176, 500] as [CGFloat] {
                let c = min(max(o, 0), 176), g = behavior == .stretch ? max(0, -o) : 0
                #expect(HeaderMath.layoutHeight(o: o, m: h) == 240 - c)
                #expect(HeaderMath.visibleHeight(o: o, m: h) == HeaderMath.height(o: o, m: h))
                #expect(HeaderMath.height(o: o, m: h) == 240 - c + g)
                #expect(HeaderMath.collapseTranslation(o: o, m: h) == 0)
                let drawn = HeaderMath.layoutHeight(o: o, m: h) * HeaderMath.stretchScale(o: o, m: h)
                #expect(abs(drawn - HeaderMath.height(o: o, m: h)) < 1e-9, "the drawn height is h_L · s")
            }
        }
    }

    @Test func theStretchScale() {
        #expect(HeaderMath.stretchScale(layoutHeight: 240, stretch: 60) == 1.25)
        #expect(HeaderMath.stretchScale(layoutHeight: 240, stretch: 0) == 1)
        #expect(HeaderMath.stretchScale(layoutHeight: 0, stretch: 60) == 1, "R = 0: no scale")
        #expect(HeaderMath.stretchScale(layoutHeight: .nan, stretch: 60) == 1)
        #expect(HeaderMath.stretchScale(layoutHeight: 240, stretch: -5) == 1)
        #expect(HeaderMath.stretchScale(layoutHeight: 240, stretch: .infinity) == 1)
        for collapse in [ZTronHeaderCollapseBehavior.Kind.compress, .slideBehind(parallax: 0.5)] {
            var h = Self.banner
            h.collapse = collapse
            for g in [0, 30, 120] as [CGFloat] {
                #expect(abs(HeaderMath.stretchScale(o: -g, m: h) - (1 + g / 240)) < 1e-12, "\(collapse) g \(g): s = 1 + g/R")
                #expect(abs(240 * HeaderMath.stretchScale(o: -g, m: h) - HeaderMath.height(o: -g, m: h)) < 1e-9)
            }
            #expect(HeaderMath.stretchScale(o: 100, m: h) == 1, "no scale while collapsing")
            var preserve = h
            preserve.behavior = .preserve
            #expect(HeaderMath.stretchScale(o: -60, m: preserve) == 1, ".preserve never scales")
            var flat = h
            flat.resting = 0
            flat.min = 0
            #expect(HeaderMath.stretchScale(o: -60, m: flat) == 1, "degenerate R = 0")
        }
    }

    @Test(arguments: [ZTronHeaderScalingBehavior.preserve, .stretch], [ZTronHeaderPullBehavior.openGap, .followContent])
    func thePullSideIsTheSameInBothCollapseModes(behavior: ZTronHeaderScalingBehavior, pull: ZTronHeaderPullBehavior) {
        var a = Self.profile
        a.behavior = behavior
        a.pull = pull
        var b = a
        b.collapse = .slideBehind(parallax: 0.5)
        for hold in [0, 60] as [CGFloat] {
            let ma = Self.metrics(a, hold: hold), mb = Self.metrics(b, hold: hold)
            #expect(ma.adjustedContentInset == mb.adjustedContentInset, "the same reserved R")
            let ra = HeaderMath.refreshTop(ma), rb = HeaderMath.refreshTop(mb)
            #expect(ra?.base == rb?.base && ra?.overlay == rb?.overlay, "\(behavior) \(pull): the refresh base")
            for o in [-120, -40, -0.5, 0] as [CGFloat] {
                #expect(HeaderMath.gapAbove(o: o, m: a) == HeaderMath.gapAbove(o: o, m: b))
                #expect(HeaderMath.gapBelow(o: o, m: a) == HeaderMath.gapBelow(o: o, m: b))
                #expect(HeaderMath.translation(o: o, m: a) == HeaderMath.translation(o: o, m: b))
                #expect(Self.delta(o, ma) == Self.delta(o, mb), "o′ \(o): obscuredDelta under a pull")
                #expect(HeaderMath.stretchScale(o: o, m: a) == HeaderMath.stretchScale(o: o, m: b))
            }
        }
        // In the band both see −c; past `.compress`'s band (176) only `.slideBehind` is still being covered.
        let ma = Self.metrics(a), mb = Self.metrics(b)
        #expect(Self.delta(100, ma) == -100 && Self.delta(100, mb) == -100)
        #expect(Self.delta(200, ma) == -176 && Self.delta(200, mb) == -200 && Self.delta(500, mb) == -240)
    }

    @Test func slideBehindSnapsAndTargetsAreCoveredFractions() {
        let h = Self.sliding()
        #expect(HeaderMath.offset(for: .collapsed, m: h) == 240)
        #expect(HeaderMath.offset(for: .progress(0.5), m: h) == 120)
        #expect(HeaderMath.offset(for: .height(100), m: h) == 140, ".height is the visible height: o′ = R − h")
        #expect(HeaderMath.offset(for: .height(30), m: h) == 210, "below the size's min: min is ignored")
        #expect(HeaderMath.offset(for: .height(-5), m: h) == 240 && HeaderMath.offset(for: .height(500), m: h) == 0)
        #expect(HeaderMath.offset(for: .height(.nan), m: h) == 0)
        #expect(HeaderMath.offset(for: .height(30), m: Self.profile) == 176, ".compress clamps at min")
        #expect(HeaderMath.snapOffset(progress: 0.25, m: h) == 60)
        #expect(HeaderMath.nearestSnap(to: 100, positions: [0, 0.5, 1], m: h) == 120)
        #expect(HeaderMath.nearestSnap(to: 200, positions: [0, 0.5, 1], m: h) == 240)
        // scrollTo solves for the uncovered top at the target, `o = place(top + δ(o′))`, inside the covered band too.
        let m = Self.metrics(h)
        let top = m.adjustedContentInset.top
        let place: (CGFloat) -> CGFloat = { -101 - 0.5 * $0 }
        let y = HeaderMath.solveTarget(metrics: m, place: place)
        let oPrime = y + HeaderMath.base(m)
        #expect(abs(oPrime - 100) < 1e-6, "the crossing at 100 pt covered")
        #expect(abs(y - place(top + Self.delta(oPrime, m))) < 1e-6, "self-consistent at the target")
    }

    @Test func aCollapseModeChangeKeepsTheProgress() {
        let compress = Self.metrics(Self.profile), slide = Self.metrics(Self.sliding())
        func keep(_ oPrime: CGFloat, _ old: ScrollMetrics, _ new: ScrollMetrics) -> CGFloat {
            HeaderMath.keepProgress(offsetY: oPrime - HeaderMath.base(old), old: old, new: new)! + HeaderMath.base(new)
        }
        #expect(keep(-30, compress, slide) == -30 && keep(0, compress, slide) == 0, "at or above rest: o′ kept")
        #expect(keep(88, compress, slide) == 120, "half collapsed → half covered")
        #expect(keep(120, slide, compress) == 88, "and back")
        #expect(keep(200, compress, slide) == 240, "collapsed stays collapsed (covered)")
        #expect(keep(500, compress, slide) == 500, "past the band the content stays where it was")
    }
}
