import SwiftUI

/// D70: one layer of the header's fade: `color` at the opacity `alpha` of each stop's band position `location` (0 the
/// header's top, 1 the band's end), linear in between: exactly what a `LinearGradient` with `gradientStops` draws.
struct HeaderFadeLayer: Equatable {
    struct Stop: Equatable {
        var location: CGFloat
        var alpha: CGFloat
    }

    var color: Color
    /// Sorted by location, from 0 to 1.
    var stops: [Stop]

    /// The gradient's stops: `color.opacity(alpha)` at each location.
    var gradientStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: color.opacity(Double($0.alpha)), location: $0.location) }
    }

    /// The opacity the gradient draws at `u`: linear between the stops, the end stops' beyond them.
    func alpha(at u: CGFloat) -> CGFloat {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if u <= first.location { return first.alpha }
        for (s0, s1) in zip(stops, stops.dropFirst()) where u <= s1.location {
            let span = s1.location - s0.location
            return span > 0 ? s0.alpha + (s1.alpha - s0.alpha) * (u - s0.location) / span : s1.alpha
        }
        return last.alpha
    }
}

/// D70: the fade at one scroll position: `bottom`, and `top` drawn over it when the fade's states have different colors
/// (fixed for a given `ZTronHeaderFade`, so the drawn structure never changes while scrolling).
struct HeaderFadeLayers: Equatable {
    var bottom: HeaderFadeLayer
    var top: HeaderFadeLayer?

    /// The opacity both layers draw together at `u` (`top` over `bottom`: `a + b − a·b`).
    func coverage(at u: CGFloat) -> CGFloat {
        let a = bottom.alpha(at: u), b = top?.alpha(at: u) ?? 0
        return a + b - a * b
    }
}

/// D70's fade math (design M8b-header-behaviors §2, "Fade blend"), pure. The visible band `u ∈ [0, 1]` runs from the
/// header's top (0) to the band's end (1, `bandEnd`). One state's gradient is `α_X(u) = max(0, (u − s_X) / (1 − s_X))`
/// (`s_X` its start; a nil state, or `s_X = 1`, is 0 everywhere). The scroll position blends the rest gradient A with its
/// partner B (`collapse` while the content scrolls up over the header, `pull` while it is pulled past the top) by the
/// weight `t`: `α(u) = (1 − t)·α_A(u) + t·α_B(u)`.
/// - Same color (or one side nil, e.g. `.linear(to:)` in every state): ONE gradient with stops at the breakpoints
///   `{0, s_A, s_B, 1}` and the color at `α(u)` there. Both α are linear between those points, so the gradient IS `α`.
/// - Different colors: two layers, the over-operator corrected: bottom A `a(u) = (1 − t)·α_A(u) / (1 − t·α_B(u))`, top B
///   `b(u) = t·α_B(u)`, so `a + b − a·b = α(u)` and B's share is exact. `a` is rational between the breakpoints: each
///   segment gets `interiorStops` cosine-spaced stops (worst coverage error 0.73 % over t, s_A, s_B ∈ [0, 1); six uniform
///   ones, as first designed, measured 2.6 %).
enum HeaderFadeMath {
    /// The state the rest gradient is blended with.
    enum Partner: Equatable, Sendable { case collapse, pull }

    /// The pull that reaches the pull state fully, as a fraction of the resting height (user 2026-11-01: half of it).
    static let fullPullFraction: CGFloat = 0.5
    /// Interior stops per segment of a two-color bottom layer (cosine spaced: denser at the segment's ends).
    static let interiorStops = 8

    /// The crossfade: collapse `t = p` (the collapse progress; the covered fraction under `.slideBehind`), pull
    /// `t = min(1, g / (R / 2))`, 0 at rest. Exclusive: a pull (`g > 0`) means `p = 0`. `R ≤ 0`: any pull is full.
    static func weight(progress p: CGFloat, pull g: CGFloat, resting R: CGFloat) -> (partner: Partner, t: CGFloat) {
        let pull = g.isFinite ? max(0, g) : 0
        if pull > 0 {
            let full = R.isFinite ? max(0, R) * fullPullFraction : 0
            return (.pull, full > 0 ? min(1, pull / full) : 1)
        }
        return (.collapse, p.isFinite ? min(max(p, 0), 1) : 0)
    }

    /// One state's opacity at `u` (clamped to 0…1): `max(0, (u − s) / (1 − s))`; 0 for a nil state or `s = 1`.
    static func alpha(_ gradient: ZTronHeaderFade.Gradient?, at u: CGFloat) -> CGFloat {
        guard let gradient, gradient.start < 1 else { return 0 }
        let x = u.isNaN ? 0 : min(max(u, 0), 1)
        return max(0, (x - gradient.start) / (1 - gradient.start))
    }

    /// The partner's gradient.
    static func gradient(_ fade: ZTronHeaderFade, _ partner: Partner) -> ZTronHeaderFade.Gradient? {
        partner == .collapse ? fade.collapse : fade.pull
    }

    /// The opacity the blend must draw at `u`: `(1 − t)·α_rest(u) + t·α_partner(u)`.
    static func target(_ fade: ZTronHeaderFade, partner: Partner, t: CGFloat, at u: CGFloat) -> CGFloat {
        (1 - t) * alpha(fade.rest, at: u) + t * alpha(gradient(fade, partner), at: u)
    }

    /// Whether the pull moves the crossfade: the pull state differs from the rest one (D70). Otherwise the live input
    /// does not track the pull at all (`HeaderLiveInput.tracksPull`): `.linear(to:from:)` and a fade equal at rest and
    /// pulled draw exactly as before, and an `.openGap` pull lays nothing out.
    static func tracksPull(_ fade: ZTronHeaderFade?) -> Bool {
        guard let fade else { return false }
        return fade.pull != fade.rest
    }

    /// Whether `fade` is drawn as two layers: the rest gradient and a partner both set, in different colors.
    static func twoLayers(_ fade: ZTronHeaderFade) -> Bool {
        guard let rest = fade.rest else { return false }
        return [fade.collapse, fade.pull].contains { $0 != nil && $0!.color != rest.color }
    }

    /// The layers at collapse progress `p`, pull `g` and resting height `R` (`weight`); `nil` without a fade or when
    /// every state is nil. A fade with `twoLayers` always has a `top` (clear while the partner's color is the rest's
    /// or nil), so the drawn structure is fixed per fade.
    static func layers(fade: ZTronHeaderFade?, progress p: CGFloat, pull g: CGFloat, resting R: CGFloat) -> HeaderFadeLayers? {
        guard let fade, let any = fade.rest ?? fade.collapse ?? fade.pull else { return nil }
        let (partner, t) = weight(progress: p, pull: g, resting: R)
        let a = fade.rest, b = gradient(fade, partner)
        let breaks = Array(Set([0, 1] + [a, b].compactMap { $0.map(\.start) })).sorted()
        if let a, let b, a.color != b.color {
            var locations: [CGFloat] = []
            for (x0, x1) in zip(breaks, breaks.dropFirst()) {
                locations.append(x0)
                for k in 1...interiorStops {
                    let f = CGFloat(k) / CGFloat(interiorStops + 1)
                    locations.append(x0 + (x1 - x0) * (1 - cos(.pi * f)) / 2)
                }
            }
            locations.append(1)
            let bottom = locations.map { u -> HeaderFadeLayer.Stop in
                let d = 1 - t * alpha(b, at: u)
                return .init(location: u, alpha: d > 0 ? min(1, (1 - t) * alpha(a, at: u) / d) : 0)
            }
            let top = breaks.map { HeaderFadeLayer.Stop(location: $0, alpha: t * alpha(b, at: $0)) }
            return HeaderFadeLayers(bottom: HeaderFadeLayer(color: a.color, stops: bottom),
                                    top: HeaderFadeLayer(color: b.color, stops: top))
        }
        let color = (a ?? b ?? any).color
        let single = breaks.map { HeaderFadeLayer.Stop(location: $0, alpha: target(fade, partner: partner, t: t, at: $0)) }
        let clear = twoLayers(fade) ? HeaderFadeLayer(color: color, stops: [.init(location: 0, alpha: 0),
                                                                            .init(location: 1, alpha: 0)]) : nil
        return HeaderFadeLayers(bottom: HeaderFadeLayer(color: color, stops: single), top: clear)
    }

    /// The band's end in the header's local (unscaled) frame of height `h` (the layout's `h_L`): `.compress` the whole
    /// frame (under `.stretch` the gradient is inside the scaled stack, so it stretches with the header); `.slideBehind(k)`
    /// the content's top edge, `h·(1 − (1 − k)·p)` (`R − (1 − k)·c` at the committed `R`): the fade reaches its color
    /// exactly where the content covers the header.
    static func bandEnd(collapse: ZTronHeaderCollapseBehavior.Kind, progress p: CGFloat, layoutHeight h: CGFloat) -> CGFloat {
        let height = h.isFinite ? max(0, h) : 0
        guard let k = collapse.parallax else { return height }
        let q = p.isFinite ? min(max(p, 0), 1) : 0
        return height * (1 - (1 - k) * q)
    }

    /// The gradient's end point (its start is `(0.5, 0)`) for a band ending at `bandEnd` in a frame `frameHeight` tall;
    /// never at the start point (a fully covered header keeps a one-thousandth band).
    static func endPoint(bandEnd: CGFloat, frameHeight: CGFloat) -> UnitPoint {
        guard frameHeight > 0, frameHeight.isFinite, bandEnd.isFinite else { return UnitPoint(x: 0.5, y: 1) }
        return UnitPoint(x: 0.5, y: max(0.001, bandEnd / frameHeight))
    }
}
