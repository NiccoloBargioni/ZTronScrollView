import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M8b-2 (design M8b §1.3, test list item 5): indicator placement for the three looks on the four edges, then the hosted
/// wiring: the container hook installs the coordinator, begin / end draw the indicator without running a content body,
/// the accessibility action starts the refresh once, and the reach-edge twins register watchers.
@MainActor
@Suite(.serialized)
struct RefreshIndicatorTests {
    let viewport = CGSize(width: 400, height: 800)
    let base = EdgeInsets(top: 50, leading: 0, bottom: 34, trailing: 0)

    func place(_ edge: Edge, _ style: ZTronRefreshStyle = .system, overlay: Bool = false, refreshing: Bool = false,
               drag: CGFloat = 0.3, pull: CGFloat = 30, header: CGFloat = 0) -> RefreshPlacement? {
        RefreshIndicatorMath.placement(edge: edge, style: style, overlay: overlay, refreshing: refreshing, dragPosition: drag,
                                       pull: pull, length: 60, viewport: viewport, base: base, header: header)
    }

    // MARK: placement

    @Test func systemIsCentredInTheGapOnEveryEdge() {
        let top = place(.top)!
        #expect(top.frame == CGRect(x: 0, y: 35, width: 400, height: 60))
        #expect(top.clip == CGRect(x: 0, y: 50, width: 400, height: 30) && top.opacity == 0.3)
        let bottom = place(.bottom)!
        #expect(bottom.frame == CGRect(x: 0, y: 721, width: 400, height: 60))
        #expect(bottom.clip == CGRect(x: 0, y: 736, width: 400, height: 30))
        let leading = place(.leading)!
        #expect(leading.frame == CGRect(x: -15, y: 50, width: 60, height: 716))
        #expect(leading.clip == CGRect(x: 0, y: 50, width: 30, height: 716))
        let trailing = place(.trailing)!
        #expect(trailing.frame == CGRect(x: 355, y: 50, width: 60, height: 716))
        #expect(trailing.clip == CGRect(x: 370, y: 50, width: 30, height: 716))
    }

    @Test func defaultIsGluedToTheContentEdgeAndFollowsThePull() {
        let top = place(.top, .default)!
        #expect(top.frame == CGRect(x: 0, y: 20, width: 400, height: 60), "its far edge is the content's edge: base + pull")
        #expect(top.clip == CGRect(x: 0, y: 50, width: 400, height: 30) && top.opacity == 1)
        let far = place(.top, .default, pull: 150)!
        #expect(far.frame.maxY == 50 + 150 && far.clip.maxY == 200)
        let bottom = place(.bottom, .default)!
        #expect(bottom.frame.minY == 766 - 30 && bottom.clip.minY == 736)
        #expect(place(.leading, .default)!.frame.maxX == 30 && place(.trailing, .default)!.frame.minX == 370)
    }

    @Test func overlayFloatsOverTheContentAndSitsAtTheIndicatorHeightWhileRefreshing() {
        let pulling = place(.top, .system, overlay: true)!
        #expect(pulling.frame == CGRect(x: 0, y: 20, width: 400, height: 60), "centre at min(pull, L) − L/2 from the base")
        #expect(pulling.clip.minY == 50 && pulling.clip.maxY == 800 - 0, "clipped at the base only, not to the gap")
        #expect(pulling.opacity == 0.5)
        let refreshing = place(.top, .default, overlay: true, refreshing: true, drag: 1, pull: 0)!
        #expect(refreshing.frame == CGRect(x: 0, y: 50, width: 400, height: 60) && refreshing.opacity == 1)
        let rest = place(.top, .default, overlay: true, pull: 0)
        #expect(rest == nil, "an overlay at rest is outside its base")
        let bottom = place(.bottom, .system, overlay: true, refreshing: true)!
        #expect(bottom.frame == CGRect(x: 0, y: 706, width: 400, height: 60))
        // Open item 18: a base beyond the viewport (a `.stretch` band below the landscape screen) keeps the indicator
        // there, its clip never shorter than it (was nil: no layer for a rotation to interpolate).
        let below = place(.top, .default, overlay: true, refreshing: true, drag: 1, pull: 0, header: 900)!
        #expect(below.frame == CGRect(x: 0, y: 950, width: 400, height: 60) && below.clip == below.frame)
        #expect(place(.top, .default, overlay: true, pull: 0, header: 900) == nil, "at rest still outside its base")
    }

    @Test func noPullNoIndicatorAndAHoldKeepsItWhereTheGapIs() {
        #expect(place(.top, pull: 0) == nil && place(.top, pull: -20) == nil, "a pull (or its release) ends at 0")
        // Refreshing, no gap: nothing drawn, the clip is empty (open item 19: the placement, and the layer, stay).
        for pull: CGFloat in [0, -20] {
            let none = place(.top, refreshing: true, drag: 1, pull: pull)!
            #expect(none.visibleLength(vertical: true) == 0 && none.clip.height == 0, "pull \(pull): \(none)")
        }
        // At rest with a 60 pt hold open the displayed pull against the hold-less bounds is 60: the gap is the hold.
        let held = place(.top, .system, refreshing: true, drag: 1, pull: 60)!
        #expect(held.frame == CGRect(x: 0, y: 50, width: 400, height: 60) && held.opacity == 1)
        #expect(held.clip == CGRect(x: 0, y: 50, width: 400, height: 60))
        // A user who scrolled the content back up: the gap shrinks, the indicator is clipped with it.
        let shrinking = place(.top, .default, refreshing: true, drag: 1, pull: 20)!
        #expect(shrinking.clip == CGRect(x: 0, y: 50, width: 400, height: 20))
        #expect(place(.top, .default, refreshing: true, drag: 1, pull: 0)!.visibleLength(vertical: true) == 0)
    }

    /// Open item 19: a hold whose gap left the viewport (the content scrolled past the base, S7 in a rotation) keeps its
    /// placement: the box's far edge on the content's edge, the indicator where the hold rests it against that edge
    /// (`.system`: H/2 before it once the pull is past -H, continuous through 0; `.default`: glued to it), nothing visible
    /// (the clip is empty, the region starts at the base). At rest and for any pull > 0 the visible part is unchanged.
    @Test func aHoldScrolledAwayKeepsItsBoxOnTheContentsEdge() {
        for edge in [Edge.top, .bottom, .leading, .trailing] {
            let vertical = edge == .top || edge == .bottom
            let along: CGFloat = vertical ? 800 : 400
            let b: CGFloat = [Edge.top: 50, .bottom: 34, .leading: 0, .trailing: 0][edge]!
            /// Position along d (from the base into the viewport) of a viewport coordinate on the pull axis.
            func d(_ v: CGFloat) -> CGFloat { edge == .top || edge == .leading ? v - b : along - b - v }
            func span(_ r: CGRect) -> (CGFloat, CGFloat) {
                let a = vertical ? (d(r.minY), d(r.maxY)) : (d(r.minX), d(r.maxX))
                return (min(a.0, a.1), max(a.0, a.1))
            }
            for style in [ZTronRefreshStyle.system, .default] {
                var previous: (pull: CGFloat, centre: CGFloat)?
                for pull: CGFloat in [-400, -100, -60, -30, -1, -0.01, 0, 0.01, 1, 30, 60, 100] {
                    let label = "\(edge) \(style) pull \(pull)"
                    guard let pl = place(edge, style, refreshing: true, drag: 1, pull: pull) else {
                        Issue.record("\(label): no placement")
                        continue
                    }
                    let box = span(pl.box), frame = span(pl.frame), region = span(pl.region)
                    #expect(abs(box.1 - pull) < 1e-9, "\(label): the box ends on the content's edge \(box)")
                    #expect(box.0 <= min(0, pull - 60) + 1e-9 && box.0 <= frame.0 + 1e-9, "\(label): box holds the indicator's near part \(box) \(frame)")
                    #expect(abs(region.0) < 1e-9 && region.1 >= max(pull, along) - 1e-9, "\(label): region from the base \(region)")
                    let centre = (frame.0 + frame.1) / 2
                    let expected: CGFloat = style == .default ? pull - 30 : pull > 0 ? pull / 2 : pull - min(60, -pull) / 2
                    #expect(abs(centre - expected) < 1e-9, "\(label): centre \(centre), expected \(expected)")
                    if pull <= 0 {
                        #expect(pl.visibleLength(vertical: vertical) == 0, "\(label): nothing visible")
                    } else {
                        #expect(abs(pl.visibleLength(vertical: vertical) - min(pull, 60)) < 1e-9,
                                "\(label): visible \(pl.visibleLength(vertical: vertical)) as before")
                        let clip = span(pl.clip)
                        #expect(abs(clip.0) < 1e-9 && abs(clip.1 - pull) < 1e-9, "\(label): the gap \(clip)")
                    }
                    if let previous, previous.pull >= -1, pull <= 1 {
                        #expect(abs(centre - previous.centre) <= abs(pull - previous.pull) * 1.5 + 1e-9,
                                "\(label): continuous through 0 (\(previous) -> \(centre))")
                    }
                    previous = (pull, centre)
                }
                // Rigid with the content past -H: the indicator's distance to the content's edge is the rest one.
                let rest = place(edge, style, refreshing: true, drag: 1, pull: 60)!
                let away = place(edge, style, refreshing: true, drag: 1, pull: -400)!
                let restSpan = span(rest.frame), awaySpan = span(away.frame)
                #expect(abs((restSpan.0 - 60) - (awaySpan.0 + 400)) < 1e-9, "\(edge) \(style): rest place against the edge")
            }
        }
    }

    /// A hold larger than the indicator (`holdOffset`): `.system` rests at H/2 and keeps that place against the content's
    /// edge when scrolled away; the box reaches back H.
    @Test func aLargerHoldRestsTheSystemIndicatorInItsMiddle() {
        let rest = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                  pull: 100, length: 60, viewport: viewport, base: base, hold: 100)!
        #expect(rest.frame.midY == 50 + 50 && rest.clip == CGRect(x: 0, y: 50, width: 400, height: 100))
        #expect(rest.box == rest.clip, "at rest the box is the gap")
        let away = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                  pull: -300, length: 60, viewport: viewport, base: base, hold: 100)!
        #expect(away.frame.midY == 50 - 300 - 50 && away.box == CGRect(x: 0, y: 50 - 400, width: 400, height: 100))
        #expect(away.visibleLength(vertical: true) == 0)
    }

    /// S-RS-1 (fixer round 1 of the header behaviors): a held top refresh under a vertical `.stretch` header (R 240, safe top
    /// 62, hold 60, the default L 60), the content scrolled up from the hold's rest through the band and past it. As the
    /// leaf computes it (`base`, `inStretchBand`, `placement`), the indicator's drawn part never reaches below the content's
    /// top, in both collapse modes and both looks; it rests where it did (`[302, 362]`) and then goes up with the header's
    /// drawn bottom (the content's top), clipped to the stretched band. Before: `[302, 362]` at every `o′`, 60 pt over the
    /// content from `o′ = 0` on (the seam lab: the whole time the content was away from the top). `.preserve` the control.
    @Test(arguments: [ZTronHeaderScalingBehavior.stretch, .preserve], [ZTronRefreshStyle.system, .default])
    func aStretchHoldScrolledAwayIsNeverDrawnOverTheContent(behavior: ZTronHeaderScalingBehavior, style: ZTronRefreshStyle) {
        let cfg = ZTronRefreshConfiguration.default
        for collapse in [ZTronHeaderCollapseBehavior.Kind.compress, .slideBehind(parallax: 0.5)] {
            for inset: CGFloat in [0, 16] {
                var h = HeaderMathTests.profile
                h.behavior = behavior
                h.collapse = collapse
                let m = HeaderMathTests.metrics(h, hold: 60, contentInset: inset)
                let (base, overlay) = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false)
                let band = RefreshIndicatorMath.inStretchBand(edge: .top, metrics: m, overlay: false)
                #expect(band == (behavior == .stretch))
                let A = HeaderMath.base(m), top0 = HeaderMath.top0(m)
                var last: (minY: CGFloat, pull: CGFloat)?
                for o in stride(from: CGFloat(-60), through: 300, by: 5) {
                    let offset = CGPoint(x: 0, y: o - A)
                    let contentTop = -offset.y
                    let g = HeaderMath.geometry(o: o, m: h)
                    let headerBottom = top0 + HeaderMath.translation(o: o, m: h) + HeaderMath.collapseTranslation(o: o, m: h) + g.height
                    let pull = RefreshMath.signedPull(edge: .top, offset: offset, zoom: 1, metrics: m, alignment: .center)
                    let label = "\(behavior) \(style) \(collapse) inset \(inset) o′ \(o)"
                    guard let p = RefreshIndicatorMath.placement(
                        edge: .top, style: style, overlay: overlay, band: band, refreshing: true, dragPosition: 1, pull: pull,
                        length: cfg.indicatorHeight, viewport: m.viewportSize, base: base,
                        hold: RefreshEngine.holdSize(edge: .top, config: cfg, overlay: false))
                    else { Issue.record("\(label): no placement while refreshing"); continue }
                    let top = max(p.frame.minY, p.clip.minY), bottom = min(p.frame.maxY, p.clip.maxY)
                    if bottom > top, p.opacity > 0 {
                        #expect(bottom <= contentTop + 1e-9, "\(label): drawn to \(bottom), content top \(contentTop)")
                    }
                    guard behavior == .stretch else { continue }
                    #expect(abs(p.box.maxY - headerBottom) < 1e-9 || o > 0, "\(label): box on the header's bottom \(headerBottom)")
                    #expect(abs(p.box.maxY + inset - contentTop) < 1e-9, "\(label): box \(p.box.maxY) on the content's edge")
                    if o == -60 {
                        #expect(p.frame == CGRect(x: 0, y: 302, width: 402, height: 60), "\(label): rests where it did")
                        #expect(p.visibleLength(vertical: true) == 60)
                    }
                    if let last {
                        let step = p.frame.minY - last.minY
                        if style == .default || (last.pull <= -60 && pull <= -60) {
                            #expect(abs(step - (-5)) < 1e-9, "\(label): moves with the content, no jump")
                        } else {
                            // R1-RC1-1: `.system` is centred in the band (half the content's speed), then catches up with
                            // the content's edge (1.5 times) until it sits where the hold rests it (30 pt before the edge).
                            #expect(step <= 0 && step >= -7.5 - 1e-9, "\(label): step \(step), no jump")
                        }
                    }
                    last = (p.frame.minY, pull)
                }
            }
        }
    }

    /// S-RS-1: the `.stretch` band keeps the overlay's look everywhere it was not drawn over the content: a pull (not
    /// refreshing: slides in from the base, opacity `p/L`, nothing at rest) and a hold at rest are the same frames and the
    /// same drawn part as before; the band only adds the clip to `[0, pull]` and the box on the band's far end. An
    /// `overlay:` refresher (no hold, over the content by choice) is not in the band. A programmatic hold's opening
    /// (open item 30: the pull goes 0 → H on the clock while refreshing) is drawn on the band's far end (`.default`) or
    /// centred in the band (a `.system` spinner, R1-RC1-1), never past the far end.
    @Test func theStretchBandKeepsTheOverlaysLookAndClipsToTheBand() {
        func both(_ refreshing: Bool, _ pull: CGFloat, hold: CGFloat = 60) -> (RefreshPlacement?, RefreshPlacement?) {
            let a = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: true, refreshing: refreshing,
                                                   dragPosition: 0.5, pull: pull, length: 60, viewport: viewport, base: base,
                                                   hold: hold)
            let b = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: true, band: true, refreshing: refreshing,
                                                   dragPosition: 0.5, pull: pull, length: 60, viewport: viewport, base: base,
                                                   hold: hold)
            return (a, b)
        }
        func drawn(_ p: RefreshPlacement) -> ClosedRange<CGFloat> {
            max(p.frame.minY, p.clip.minY)...max(max(p.frame.minY, p.clip.minY), min(p.frame.maxY, p.clip.maxY))
        }
        for pull: CGFloat in [1, 30, 59, 60, 61, 120, 300] {
            let (o, b) = both(false, pull)
            #expect(o!.frame == b!.frame && o!.opacity == b!.opacity && drawn(o!) == drawn(b!), "pull \(pull)")
            #expect(b!.clip.maxY == 50 + pull && b!.box.maxY == 50 + pull, "pull \(pull): clipped to the band")
        }
        #expect(both(false, 0).1 == nil && both(false, -20).1 == nil, "a pull (or its release) ends at 0, as the overlay")
        let (oRest, bRest) = both(true, 60)
        #expect(oRest!.frame == bRest!.frame && drawn(oRest!) == drawn(bRest!) && bRest!.opacity == 1, "the hold at rest")
        let (oBig, bBig) = both(true, 100, hold: 100)
        #expect(oBig!.frame == bBig!.frame && drawn(oBig!) == drawn(bBig!), "a larger hold rests at the band's top, as before")
        // The opening: the band's far end is the content's top; the indicator never passes it. `.default` rides the far
        // end; a `.system` spinner is centred in the band (R1-RC1-1).
        for pull in stride(from: CGFloat(0), through: 60, by: 4) {
            let b = both(true, pull).1!
            #expect(b.frame.midY == 50 + pull / 2 && b.visibleLength(vertical: true) == pull, "opening at \(pull)")
            let d = RefreshIndicatorMath.placement(edge: .top, style: .default, overlay: true, band: true, refreshing: true,
                                                   dragPosition: 0.5, pull: pull, length: 60, viewport: viewport, base: base,
                                                   hold: 60)!
            #expect(d.frame.maxY == 50 + pull && d.visibleLength(vertical: true) == pull, ".default opening at \(pull)")
        }
        // Not in the band: an `overlay:` refresher (no hold), no header, a `.preserve` header, a banner, the other edges.
        var h = HeaderMathTests.banner
        #expect(RefreshIndicatorMath.inStretchBand(edge: .top, metrics: HeaderMathTests.metrics(h, hold: 60), overlay: false))
        #expect(!RefreshIndicatorMath.inStretchBand(edge: .top, metrics: HeaderMathTests.metrics(h), overlay: true))
        #expect(!RefreshIndicatorMath.inStretchBand(edge: .bottom, metrics: HeaderMathTests.metrics(h, hold: 60), overlay: false))
        #expect(!RefreshIndicatorMath.inStretchBand(edge: .top, metrics: HeaderMathTests.metrics(nil, hold: 60), overlay: false))
        #expect(!RefreshIndicatorMath.inStretchBand(edge: .top, metrics: HeaderMathTests.metrics(HeaderMathTests.profile, hold: 60),
                                                    overlay: false))
        h.vertical = false
        #expect(!RefreshIndicatorMath.inStretchBand(edge: .top, metrics: HeaderMathTests.metrics(h, hold: 60), overlay: false))
    }

    /// R1-RC1-1 (fixer round 2 of the header behaviors): under `.stretch` a `.system` refresher with a `holdOffset` below
    /// `L/2 + 10` (L 60: below 40) had its 20 pt spinner on the band's far end (`[s − L, s]`), cut at the band's start for the
    /// whole refresh: H 30 drew 10 of its 20 pt, H 25 5, H ≤ 20 nothing. It is centred in the band now, as in the `.preserve`
    /// gap (the same frame and drawn part for `H ≤ L`), at the band's top for a longer hold, as before. Scrolled away it goes
    /// on with the content (never over it, no step) and then moves rigidly with it, its place in the box the rest's (a
    /// rotation interpolates it there); the refresh's end keeps the placement through the spinner's retraction
    /// (`holdsPlacement`), so nothing moves or fades in one frame. `.default` and the pull's look are unchanged.
    @Test func aShortStretchHoldCentresTheSystemSpinnerInTheBand() {
        let L: CGFloat = 60, spinner: CGFloat = 20
        func band(_ style: ZTronRefreshStyle = .system, refreshing: Bool = true, at s: CGFloat, hold H: CGFloat) -> RefreshPlacement {
            RefreshIndicatorMath.placement(edge: .top, style: style, overlay: true, band: true, refreshing: refreshing,
                                           dragPosition: 1, pull: s, length: L, viewport: viewport, base: base, hold: H)!
        }
        /// The built-in spinner's drawn part (20 pt centred in the frame, inside the box and the region).
        func drawn(_ p: RefreshPlacement) -> (top: CGFloat, length: CGFloat) {
            let a = max(p.frame.midY - spinner / 2, p.box.minY, p.region.minY)
            return (a, max(0, min(p.frame.midY + spinner / 2, p.box.maxY, p.region.maxY) - a))
        }
        for H: CGFloat in [10, 20, 25, 30, 40, 60, 100] {
            let rest = band(at: H, hold: H)
            #expect(rest.frame.midY == 50 + min(H, L) / 2 && rest.opacity == 1, "H \(H): centred, \(rest.frame)")
            #expect(drawn(rest).length == min(spinner, H), "H \(H): the spinner drawn \(drawn(rest).length) pt")
            if H <= L {
                let gap = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true,
                                                         dragPosition: 1, pull: H, length: L, viewport: viewport, base: base,
                                                         hold: H)!
                #expect(rest.frame == gap.frame && rest.clip == gap.clip && rest.box == gap.box, "H \(H): the gap's")
            }
            #expect(band(.default, at: H, hold: H).frame.maxY == 50 + min(H, L), "H \(H): .default on the far end")
            // Scrolled away: no step, never below the content's edge, then rigid at the rest's place in its box.
            var last = rest
            for s in stride(from: H - 1, through: -400, by: -1) {
                let p = band(at: s, hold: H)
                let step = p.frame.midY - last.frame.midY
                #expect(step <= 0 && step >= -1.5 - 1e-9, "H \(H) s \(s): step \(step)")
                let d = drawn(p)
                #expect(d.length == 0 || d.top + d.length <= 50 + s + 1e-9, "H \(H) s \(s): drawn below the content's edge")
                last = p
            }
            #expect(abs((last.frame.midY - last.box.minY) - (rest.frame.midY - rest.box.minY)) < 1e-9,
                    "H \(H): far away at the rest's place in its box")
            // The refresh's end at rest, then the spinner's retraction with the content: the placement is kept.
            let retracting = RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: .spinner, overlay: true,
                                                                 band: true, style: .system)
            var prev = rest
            for s in stride(from: H, through: 0, by: -0.5) {
                let p = band(refreshing: retracting, at: s, hold: H)
                #expect(abs(p.frame.midY - prev.frame.midY) <= 0.5 && p.opacity == 1, "H \(H) retracting at \(s)")
                prev = p
            }
        }
        // The leaf's rule: the gap and the band keep the hold's placement through the spinner's retraction (M8b-s8 L3: the
        // band's `.default` too); an overlay and a pull's retraction do not.
        let cases: [(overlay: Bool, band: Bool, style: ZTronRefreshStyle, keeps: Bool)] = [
            (false, false, .default, true), (false, false, .system, true), (true, true, .system, true),
            (true, true, .default, true), (true, false, .system, false), (true, false, .default, false),
        ]
        for c in cases {
            #expect(RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: .spinner, overlay: c.overlay,
                                                        band: c.band, style: c.style) == c.keeps, "\(c)")
            #expect(!RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: .pull, overlay: c.overlay,
                                                         band: c.band, style: c.style), "\(c)")
            #expect(!RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: nil, overlay: c.overlay,
                                                         band: c.band, style: c.style), "\(c)")
            #expect(RefreshIndicatorMath.holdsPlacement(mode: .refreshing, retract: nil, overlay: c.overlay, band: c.band,
                                                        style: c.style), "\(c)")
        }
        // A refresh triggered by a pull of at least L starts where the pull left it; the pull's look is the overlay's.
        for s: CGFloat in [60, 75, 100, 220] {
            #expect(band(refreshing: false, at: s, hold: 60).frame == band(at: s, hold: 60).frame, "trigger at \(s)")
        }
    }

    // MARK: Open items 31 and 32 (M8b-s8)

    /// The pull look the leaf draws for `T` (the drag position the engine reports at that pull, `progress(for:)`, for the
    /// trigger `dragT`, default `T`).
    func pullLook(_ style: ZTronRefreshStyle = .system, overlay: Bool = true, band: Bool = true, refreshing: Bool = false,
                  at s: CGFloat, trigger T: CGFloat?, dragT: CGFloat? = nil, hold: CGFloat = 60) -> RefreshPlacement? {
        let p = max(0, s), t = dragT ?? T ?? 60
        let drag = p > 0 ? (t > 0 ? min(1, p / t) : 1) : 0
        return RefreshIndicatorMath.placement(edge: .top, style: style, overlay: overlay, band: band, refreshing: refreshing,
                                              dragPosition: drag, pull: s, length: 60, viewport: viewport, base: base,
                                              hold: hold, trigger: T)
    }

    /// Open item 31: with a trigger shorter than the indicator (T < L 60) the band's `.system` pull look slid in from the
    /// band's far end until the trigger and the refreshing look then drew the spinner centred: a 15 / 10 / 5 pt step at
    /// T 30 / 40 / 50, with the opacity going 0.50 / 0.67 / 0.83 → 1 in one frame. C8's handover reaches the refreshing
    /// look's centre `min(s, L)/2` and opacity 1 exactly at the trigger, stays on it past it, and moves monotonically.
    @Test(arguments: [CGFloat(30), 40, 50]) func theBandsSystemPullLookHandsOverToTheRefreshingLookAtAShortTrigger(T: CGFloat) {
        let L: CGFloat = 60
        var last: RefreshPlacement?
        for s in stride(from: CGFloat(0.25), through: 120, by: 0.25) {
            let pull = pullLook(at: s, trigger: T)!, refreshing = pullLook(refreshing: true, at: s, trigger: T)!
            let c = pull.frame.midY - 50
            if s < T {
                // Slides in from the far end, closing the distance to the centre by the trigger.
                #expect(c >= min(s, L) - L / 2 - 1e-9 && c <= min(s, L) / 2 + 1e-9, "T \(T) s \(s): centre \(c)")
                #expect(abs(pull.opacity - Double(s / T)) < 1e-9, "T \(T) s \(s): opacity \(pull.opacity) = s / T")
            } else {
                #expect(abs(c - min(s, L) / 2) < 1e-9 && pull.opacity == 1, "T \(T) s \(s): the refreshing look's place")
                #expect(abs(pull.frame.midY - refreshing.frame.midY) < 1e-9 && pull.clip == refreshing.clip,
                        "T \(T) s \(s): the switch to refreshing moves nothing")
            }
            if let last {
                let step = c - (last.frame.midY - 50)
                #expect(step >= -1e-9 && step <= 0.25 * (0.5 + L / (2 * T)) + 1e-9, "T \(T) s \(s): step \(step)")
                #expect(pull.opacity >= last.opacity - 1e-12 && pull.opacity - last.opacity <= 0.25 / T + 1e-9,
                        "T \(T) s \(s): opacity \(last.opacity) → \(pull.opacity)")
            }
            last = pull
        }
        // At the trigger itself: the pull look (just below) and the refreshing look (fired at T) agree.
        let below = pullLook(at: T - 0.01, trigger: T)!, fired = pullLook(refreshing: true, at: T, trigger: T)!
        #expect(abs(fired.frame.midY - below.frame.midY) < 0.02 && abs(fired.opacity - below.opacity) < 0.001)
        // `.default` keeps its position (glued to the content's edge); its opacity reaches 1 at the trigger too.
        for s: CGFloat in [5, 20, T - 1, T, 45, 90] {
            let d = pullLook(.default, at: s, trigger: T)!
            #expect(d.frame.maxY == 50 + min(s, L) && abs(d.opacity - Double(min(1, max(s / L, s / T)))) < 1e-9, "default \(s)")
        }
    }

    /// Open item 31's analog in an overlay (`refresher(overlay: true)`), T 40: it slid in to `[0, L]` only at `p = L` and
    /// jumped there (20 pt) at the trigger; now it reaches `[0, L]` and opacity 1 at the trigger.
    @Test func theOverlaysPullLookReachesTheRefreshingLookAtAShortTrigger() {
        let T: CGFloat = 40, L: CGFloat = 60
        let rest = pullLook(band: false, refreshing: true, at: 0, trigger: T)!
        var last = pullLook(band: false, at: 0.5, trigger: T)!
        for s in stride(from: CGFloat(1), through: 100, by: 0.5) {
            let p = pullLook(band: false, at: s, trigger: T)!
            #expect(abs(p.frame.midY - (50 - L / 2 + L * min(1, s / T))) < 1e-9 && abs(p.opacity - Double(min(1, s / T))) < 1e-9,
                    "s \(s)")
            #expect(p.frame.midY >= last.frame.midY && p.frame.midY - last.frame.midY <= 0.5 * L / T + 1e-9, "s \(s)")
            if s >= T { #expect(p.frame == rest.frame && p.opacity == 1, "s \(s): at [0, L] from the trigger on") }
            last = p
        }
    }

    /// Every default (`T ≥ L`): the pull looks are today's, bit for bit, in the band, the overlay and the gap.
    @Test func aTriggerAtLeastTheIndicatorLongChangesNothing() {
        let L: CGFloat = 60
        for T: CGFloat in [60, 61, 80, 100, 150, 1000] {
            for s: CGFloat in [-30, 0, 5, 20, 40, 59.5, 60, 90, 300] {
                for style in [ZTronRefreshStyle.system, .default] {
                    for (overlay, band) in [(true, true), (true, false), (false, false)] {
                        for refreshing in [false, true] {
                            let new = pullLook(style, overlay: overlay, band: band, refreshing: refreshing, at: s, trigger: T)
                            let head = pullLook(style, overlay: overlay, band: band, refreshing: refreshing, at: s, trigger: nil,
                                                dragT: T)
                            #expect(new == head, "T \(T) s \(s) \(style) overlay \(overlay) band \(band) refreshing \(refreshing)")
                        }
                    }
                }
                // Today's expressions (09226f4), literally: the slide-in from the far end and `p / L`.
                let p = max(0, s)
                if s > 0, let b = pullLook(at: s, trigger: T) {
                    #expect(b.frame.midY == 50 + (min(s, L) - L / 2) && b.opacity == Double(min(1, p / L)), "band T \(T) s \(s)")
                }
                if let o = pullLook(band: false, at: s, trigger: T) {
                    #expect(o.frame.midY == 50 + (-L / 2 + min(p, L)) && o.opacity == Double(min(1, p / L)), "overlay T \(T) s \(s)")
                }
            }
        }
    }

    /// Open item 32: the spinner going back with the content in the band, grabbed again. The engine carries the spinner's
    /// look through the new pull (`mode` `.pulling`, the retraction still `.spinner`), so the leaf keeps the refreshing
    /// placement: no move, opacity 1 (without the carry the pull look took over: −25 / −20 / −15 / −7.5 pt, opacity
    /// 1 → 0.17 / 0.33 / 0.50 / 0.75 at s 10 / 20 / 30 / 45). In the gap too (its opacity went 1 → s / T).
    @Test(arguments: [ZTronRefreshStyle.system, .default]) func aReGrabbedSpinnerKeepsItsPlacement(style: ZTronRefreshStyle) {
        for (overlay, band) in [(true, true), (false, false)] {
            let retracting = RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: .spinner, overlay: overlay,
                                                                 band: band, style: style)
            let carried = RefreshIndicatorMath.holdsPlacement(mode: .pulling, retract: .spinner, overlay: overlay, band: band,
                                                              style: style)
            #expect(retracting && carried, "\(style) band \(band): the spinner's look holds the placement")
            for s: CGFloat in [10, 20, 30, 45] {
                for T: CGFloat in [40, 100] {
                    let before = pullLook(style, overlay: overlay, band: band, refreshing: retracting, at: s, trigger: T)!
                    let after = pullLook(style, overlay: overlay, band: band, refreshing: carried, at: s, trigger: T)!
                    #expect(after == before && after.opacity == 1, "\(style) band \(band) s \(s) T \(T)")
                }
            }
        }
    }

    /// The band's `.default` refresh end (pre-existing, found by the M8b-s8 design): the spinner's retraction drew the pull's
    /// look, whose opacity is `p / L`: 1 → H / L (0.33 / 0.50 / 0.75 at H 20 / 30 / 45) in one frame. L3 keeps the
    /// refreshing placement through the retraction for every style: nothing moves, the opacity stays 1.
    @Test(arguments: [CGFloat(20), 30, 45]) func theBandsDefaultEndKeepsItsOpacity(H: CGFloat) {
        let held = pullLook(.default, refreshing: true, at: H, trigger: 100, hold: H)!
        let keeps = RefreshIndicatorMath.holdsPlacement(mode: .notRefreshing, retract: .spinner, overlay: true, band: true,
                                                        style: .default)
        for s in stride(from: H, through: 0.5, by: -0.5) {
            let end = pullLook(.default, refreshing: keeps, at: s, trigger: 100, hold: H)!
            #expect(end.opacity == 1, "H \(H) s \(s): opacity \(end.opacity)")
            if s == H { #expect(end == held, "H \(H): the end moves nothing") }
        }
    }

    /// `.easeOut` (cubic-bezier 0, 0, 0.58, 1) at time fraction `x`, as SwiftUI draws the look's cross-fade.
    func easeOut(_ x: Double) -> Double {
        func bez(_ t: Double, _ p1: Double, _ p2: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t }
        var lo = 0.0, hi = 1.0
        for _ in 0..<60 { let m = (lo + hi) / 2; if bez(m, 0, 0.58) < x { lo = m } else { hi = m } }
        return bez((lo + hi) / 2, 0, 1)
    }

    /// The look switch (M8b-s8 s1): `beginRefreshing()` while the pull look is drawn (a pull let go below the trigger, going
    /// back with the content) switched to the refreshing look in one frame: in the band the glyph jumped from the far end to
    /// the centre (15 pt at a 30 pt band) and the opacity from `p / L` to 1. The leaf's tracker decides the switch once, on
    /// the update where `refreshing` turns on, with the shift from the refreshing look's place to where the pull look drew it
    /// and the opacity it drew; the weight then animates to its new target with the look's cross-fade and every frame draws
    /// the glyph that far (`RefreshLookFade`), so it glides and fades in over 0.15 s.
    @Test func aBeginWhileThePullLookIsDrawnGlidesToTheRefreshingLook() {
        let T: CGFloat = 100
        func pulled(_ s: CGFloat) -> RefreshPlacement { pullLook(at: s, trigger: T)! }
        func refreshing(_ s: CGFloat) -> RefreshPlacement { pullLook(refreshing: true, at: s, trigger: T)! }
        let sw = RefreshLookSwitch()
        var look = sw.look(edge: .top, refreshing: false, pull: 34, drawn: pulled(34)) { Issue.record("read off a switch"); return nil }
        #expect(!look.switching && look.target == 1 && look.shift == .zero, "the pull look: nothing to do")
        look = sw.look(edge: .top, refreshing: false, pull: 30, drawn: pulled(30)) { Issue.record("read off a switch"); return nil }
        // The begin: `refreshing` turns on at a 30 pt band.
        let begin = sw.look(edge: .top, refreshing: true, pull: 30, drawn: refreshing(30)) { pulled(30) }
        #expect(begin.switching && begin.target == 0)
        #expect(begin.shift.width == 0 && begin.shift.height == pulled(30).frame.midY - refreshing(30).frame.midY)
        #expect(begin.shift.height == -15, "from the far end (0) to the centre (15)")
        #expect(begin.from == pulled(30).opacity, "the opacity the pull look drew")
        #expect(sw.look(edge: .top, refreshing: true, pull: 30, drawn: refreshing(30)) { nil } == begin,
                "the same update evaluated again: the same decision")
        // The hold's reveal moves the content: the same switch animates on, nothing new is decided.
        let next = sw.look(edge: .top, refreshing: true, pull: 33, drawn: refreshing(33)) { Issue.record("read off a switch"); return nil }
        #expect(!next.switching && next.target == begin.target && next.shift == begin.shift)
        // The glyph's place and opacity along the cross-fade: from the pull look's to the refreshing look's, monotonic, 60 Hz
        // steps under half of the change; at the end the identity and the placement's opacity (bit for bit: the leaf draws as
        // without a switch).
        #expect(pulled(30).opacity == 0.5 && refreshing(30).opacity == 1)
        var last: (y: CGFloat, o: Double)?
        for frame in 0...9 {
            let progress = easeOut(min(1, Double(frame) / 60 / 0.15))
            let w = CGFloat(1 - progress)                                   // from the old target (1) to the new (0)
            let k = RefreshLookFade.remaining(weight: w, target: begin.target)
            let y = RefreshLookFade.position(.zero, shift: begin.shift, remaining: k).y
            let o = RefreshLookFade.opacity(refreshing(30).opacity, from: begin.from, remaining: k)
            if frame == 0 {
                #expect(abs(y - begin.shift.height) < 1e-9, "the first frame draws it where the pull look did")
                #expect(abs(o - 0.5) < 1e-9, "at the pull look's opacity")
            }
            if let last {
                #expect(y >= last.y - 1e-9, "monotonic (\(last.y) → \(y))")
                #expect(y - last.y < 0.5 * abs(begin.shift.height), "no step of half the move or more: \(y - last.y)")
                #expect(o >= last.o - 1e-12, "the opacity: monotonic (\(last.o) → \(o))")
                #expect(o - last.o < 0.5 * 0.5, "no opacity step of half the change or more: \(o - last.o)")
            }
            last = (y, o)
        }
        #expect(RefreshLookFade.remaining(weight: 0, target: 0) == 0)
        #expect(RefreshLookFade.position(CGPoint(x: 3, y: 4), shift: begin.shift, remaining: 0) == CGPoint(x: 3, y: 4))
        for p in [0.0, 0.3, 0.5, 1.0] {
            #expect(RefreshLookFade.opacity(p, from: begin.from, remaining: 0) == p, "outside a switch: the placement's opacity")
        }
        // A second begin later (after the refresh, the pull look drawn again) switches back the other way.
        _ = sw.look(edge: .top, refreshing: false, pull: 20, drawn: pulled(20)) { nil }
        let again = sw.look(edge: .top, refreshing: true, pull: 20, drawn: refreshing(20)) { pulled(20) }
        #expect(again.switching && again.target == 1 && again.shift.height == -20)
    }

    /// No switch to animate: a pull that reaches the trigger (the same place and opacity 1, also below the indicator's
    /// length: open item 31), a leaf that drew nothing before, the gap's `.default` (the same look), the refreshing look
    /// held through a spinner's retraction (open item 32's carry: `refreshing` never turns off). The gap's `.system`
    /// switches its opacity only.
    @Test func aSwitchHappensOnlyWhenTheLookChanges() {
        for T: CGFloat in [40, 60, 100] {
            let sw = RefreshLookSwitch()
            _ = sw.look(edge: .top, refreshing: false, pull: T - 0.5, drawn: pullLook(at: T - 0.5, trigger: T)) { nil }
            _ = sw.look(edge: .top, refreshing: false, pull: T, drawn: pullLook(at: T, trigger: T)) { nil }
            let fire = sw.look(edge: .top, refreshing: true, pull: T, drawn: pullLook(refreshing: true, at: T, trigger: T)) {
                self.pullLook(at: T, trigger: T)
            }
            #expect(!fire.switching && fire.target == 1, "T \(T): the trigger switches in place")
        }
        let fresh = RefreshLookSwitch()
        #expect(!fresh.look(edge: .top, refreshing: true, pull: 0, drawn: pullLook(refreshing: true, at: 0, trigger: 100)) { nil }.switching,
                "a leaf that drew nothing before (a begin from rest)")
        let gapDefault = RefreshLookSwitch()
        _ = gapDefault.look(edge: .top, refreshing: false, pull: 30, drawn: pullLook(.default, overlay: false, band: false, at: 30, trigger: 100)) { nil }
        #expect(!gapDefault.look(edge: .top, refreshing: true, pull: 30,
                                 drawn: pullLook(.default, overlay: false, band: false, refreshing: true, at: 30, trigger: 100)) {
            self.pullLook(.default, overlay: false, band: false, at: 30, trigger: 100)
        }.switching, "the gap's .default draws the same look")
        let gapSystem = RefreshLookSwitch()
        _ = gapSystem.look(edge: .top, refreshing: false, pull: 30, drawn: pullLook(overlay: false, band: false, at: 30, trigger: 100)) { nil }
        let opacityOnly = gapSystem.look(edge: .top, refreshing: true, pull: 30,
                                         drawn: pullLook(overlay: false, band: false, refreshing: true, at: 30, trigger: 100)) {
            self.pullLook(overlay: false, band: false, at: 30, trigger: 100)
        }
        #expect(opacityOnly.switching && opacityOnly.shift == .zero, "the gap's .system: the opacity only (0.3 → 1)")
        let carried = RefreshLookSwitch()
        for s: CGFloat in [40, 30, 20, 25, 35] {
            #expect(!carried.look(edge: .top, refreshing: true, pull: s, drawn: pullLook(refreshing: true, at: s, trigger: 100)) { nil }.switching)
        }
    }

    /// D66: a resize that began with nothing of the indicator visible (its last frame with the resize closed) hides it
    /// until the resize is drawn frame by frame (`.animating`: shown at once) or closes without that (a system rotation:
    /// `.revealing` once, shown after the transition). A resize that began visible never hides.
    @Test func aResizeThatBeganWithNothingVisibleHidesItUntilItIsDrawnFrameByFrameOrOver() {
        let r = RefreshResizeReveal()
        // A rotation: open one turn, never animated.
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
        #expect(r.look(open: true, visible: false, animating: false) == .hidden, "began with nothing visible")
        #expect(r.look(open: true, visible: true, animating: false) == .hidden, "latched, whatever the target pull says")
        #expect(r.look(open: false, visible: true, animating: false) == .revealing, "closed undrawn: shown after the transition")
        #expect(r.look(open: false, visible: true, animating: false) == .shown)
        // A withAnimation resize: drawn frame by frame from its second tick.
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
        #expect(r.look(open: true, visible: false, animating: false) == .hidden)
        #expect(r.look(open: true, visible: false, animating: true) == .shown, "drawn frame by frame: the box keeps it in place")
        #expect(r.look(open: true, visible: true, animating: false) == .shown)
        #expect(r.look(open: false, visible: true, animating: false) == .shown, "no delayed reveal")
        // Began visible: never hidden.
        #expect(r.look(open: true, visible: false, animating: false) == .shown)
        #expect(r.look(open: false, visible: false, animating: false) == .shown)
    }

    @Test func theLiveHeaderHeightMovesTheTopBase() {
        let with = place(.top, .system, header: 200)!
        #expect(with.frame.minY == 35 + 200 && with.clip.minY == 250)
        #expect(place(.bottom, .system, header: 200) == place(.bottom, .system), "only the top edge counts the header")
    }

    @Test func aDegenerateViewportDrawsNothing() {
        let none = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: false, dragPosition: 1,
                                                  pull: 30, length: 60, viewport: .zero, base: EdgeInsets())
        #expect(none == nil)
    }

    // MARK: hosted

    final class Gate: @unchecked Sendable { var runs = 0 }

    func hosted(_ path: OSPath, specs: (ZTronScrollView<StatefulContent>) -> ZTronScrollView<StatefulContent>,
                counts: BodyCount) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(specs(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }))
        }
        pump(0.3)
        return (s, w)
    }

    @Test(arguments: OSPath.allCases) func theContainerHookInstallsTheCoordinatorAndTheSpecs(path: OSPath) {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let refresh = try! #require(s.refresh)
        #expect(Set(refresh.specs.keys) == [.top] && refresh.bouncesVertical && !refresh.bouncesHorizontal)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aViewWithoutARefresherHasNoEnginesAndNoBounceForce(path: OSPath) {
        let counts = BodyCount()
        let (s, w) = hosted(path, specs: { $0 }, counts: counts)
        let refresh = try! #require(s.refresh)
        #expect(refresh.specs.isEmpty && !refresh.bouncesVertical)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theRefreshableBridgeInstallsASystemRefresherOnTheTopEdge(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }.refreshable { })
        }
        pump(0.3)
        let spec = try! #require(s.refresh?.specs[.top])
        #expect(spec.style == .system && s.refresh?.specs.count == 1)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func anExplicitRefresherBeatsRefreshable(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .refresher(style: .default) { }
                .refreshable { })
        }
        pump(0.3)
        #expect(s.refresh?.specs[.top]?.style == .default, "the member (.default) wins over .refreshable (.system)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func beginAndEndDrawTheIndicatorWithoutRunningAContentBody(path: OSPath) async {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let base = counts.bodies
        s.beginRefreshing()
        pump(0.3)
        let refresh = try! #require(s.refresh)
        #expect(refresh.states[.top]?.mode == .refreshing && gate.runs == 0, "beginRefreshing runs no action")
        #expect(s.refreshHoldInset.top == 60, "the hold the indicator keeps open")
        s.endRefreshing()
        pump(0.8)
        #expect(refresh.states[.top]?.mode == .notRefreshing && s.refreshHoldInset.top == 0)
        #expect(counts.bodies == base, "refresh state never re-evaluates the content")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theAccessibilityActionStartsTheRefreshOnce(path: OSPath) async {
        let counts = BodyCount()
        let gate = Gate()
        let (s, w) = hosted(path, specs: { $0.refresher { gate.runs += 1 } }, counts: counts)
        let refresh = try! #require(s.refresh)
        RefreshAccessibility.perform(.top, on: refresh)
        RefreshAccessibility.perform(.top, on: refresh)
        for _ in 0..<30 { await Task.yield() }
        #expect(gate.runs == 1, "a second activation while refreshing is a no-op")
        #expect(refresh.triggerSerial == 1, "one haptic / one trigger")
        unhost(w)
    }

    @Test func accessibilityStringsAndNames() {
        #expect(RefreshAccessibility.label(for: .top) == "Refresh" && RefreshAccessibility.label(for: .leading) == "Refresh")
        #expect(RefreshAccessibility.label(for: .bottom) == "Load more" && RefreshAccessibility.label(for: .trailing) == "Load more")
        #expect(RefreshAccessibility.value(for: .refreshing) == "Refreshing" && RefreshAccessibility.value(for: .pulling) == "Pulling")
        #expect(RefreshAccessibility.value(for: .notRefreshing) == "Idle")
        #expect(RefreshAccessibility.name(of: .trailing) == "trailing")
    }

    @Test(arguments: OSPath.allCases) func reachEdgeTwinsRegisterWatchersAndUpdateInPlace(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        final class Hits { var n = 0 }
        let hits = Hits()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .onZTronScrollReachEdge(.bottom, threshold: 10) { hits.n += 1 })
        }
        pump(0.3)
        #expect(s.reachEdgeWatchers.count == 1 && s.reachEdgeWatchers[0].edge == .bottom && s.reachEdgeWatchers[0].threshold == 10)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theHolderReconcilesWatchersInPlace(path: OSPath) {
        let s = makeState(path)
        let holder = RefreshHolder(state: s)
        func decl(_ e: Edge, _ t: CGFloat) -> ReachEdgeDecl { ReachEdgeDecl(edge: e, threshold: t, perform: {}) }
        holder.reach = [decl(.bottom, 10), decl(.top, 0)]
        holder.syncReach(state: s)
        let first = s.reachEdgeWatchers
        #expect(first.count == 2)
        holder.reach = [decl(.bottom, 50), decl(.top, 0)]
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.count == 2 && s.reachEdgeWatchers[0] === first[0] && s.reachEdgeWatchers[0].threshold == 50,
                "same edge at the same position keeps its watcher (and its arming)")
        holder.reach = [decl(.bottom, 50), decl(.leading, 0)]
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.count == 2 && s.reachEdgeWatchers[0] === first[0] && s.reachEdgeWatchers[1] !== first[1])
        holder.reach = []
        holder.syncReach(state: s)
        #expect(s.reachEdgeWatchers.isEmpty)
    }
}
