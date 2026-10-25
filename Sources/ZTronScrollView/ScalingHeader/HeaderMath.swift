import SwiftUI

/// Pure scaling-header math (design M8b §2.4), no SwiftUI state. Conventions: `top0` = the header's top edge (the adjusted
/// safe-area top), `R` resting height, `band = max(0, R − min)`, `o′` = the header-relative offset (content offset +
/// `adjustedContentInset.top` − the refresh hold: rest is 0, a pull past the top is negative, scrolling up positive),
/// `c = clamp(o′, 0, band)` the collapse travel and `g = max(0, −o′)` the overflow.
enum HeaderMath {
    /// The metrics `size` resolves to at `width` (the viewport width) and a DEBUG warning when the size is degenerate. `nil`
    /// while the width is unknown or `.fit` is unmeasured.
    static func resolve(size: ZTronHeaderSize, width: CGFloat, natural: CGFloat?,
                        behavior: ZTronHeaderScalingBehavior = .preserve, vertical: Bool = true)
        -> (metrics: HeaderMetrics?, warning: String?) {
        let minimum = max(0, size.minimum.isFinite ? size.minimum : 0)
        var warning: String?
        var resting: CGFloat
        switch size {
        case let .fixed(min, max):
            resting = max.isFinite ? Swift.max(0, max) : 0
            if min > max { warning = "withScalingHeader: .fixed(min: \(min), max: \(max)) has min > max: a fixed header of height \(min)" }
        case let .aspectRatio(ratio, _):
            guard width > 0, width.isFinite else { return (nil, nil) }
            if ratio > 0, ratio.isFinite {
                resting = width / ratio
            } else {
                resting = 0
                warning = "withScalingHeader: .aspectRatio(\(ratio)) needs a positive ratio (width / height)"
            }
        case .fit:
            guard let natural else { return (nil, nil) }
            resting = natural.isFinite ? Swift.max(0, natural) : 0
            if resting < 1 {
                warning = "withScalingHeader: .fit measured a resting height of \(resting): the header has no ideal height (only flexible views). Use .fixed, .aspectRatio or .frame(idealHeight:)"
            }
        }
        // `min ≥ R`: a fixed-height header of height `min` (band 0, progress 0, no snapping; `.stretch` still grows).
        if minimum >= resting { resting = minimum }
        let w = width.isFinite ? Swift.max(0, width) : 0
        return (HeaderMetrics(min: minimum, resting: resting, behavior: behavior, width: w, vertical: vertical), warning)
    }

    /// The live geometry at `o′` (§2.4 table).
    static func geometry(o oPrime: CGFloat, m: HeaderMetrics) -> ZTronHeaderGeometry {
        let o = oPrime.isFinite ? oPrime : 0
        let band = m.band
        let c = min(max(o, 0), band)
        let g = max(0, -o)
        let stretch = m.behavior == .stretch ? g : 0
        return ZTronHeaderGeometry(progress: band > 0 ? c / band : 0, height: max(0, m.resting - c + stretch),
                                   stretch: stretch, minHeight: m.min, restingHeight: m.resting, width: m.width)
    }

    /// The live height at `o′`.
    static func height(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat { geometry(o: oPrime, m: m).height }

    /// The gap between the header's bottom and the content's top a pull opens: `.preserve` `max(0, −o′)`, `.stretch` 0.
    static func contentGap(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        m.behavior == .preserve ? max(0, -(oPrime.isFinite ? oPrime : 0)) : 0
    }

    /// The `o′` of collapse progress `p` (ONE convention: 0 expanded, 1 collapsed).
    static func snapOffset(progress p: CGFloat, m: HeaderMetrics) -> CGFloat {
        m.band * min(max(p.isFinite ? p : 0, 0), 1)
    }

    /// The snap position nearest to `o′`, as an `o′`; `nil` outside the open band `(0, band)`, without a band or without
    /// positions. A tie goes to the more expanded position.
    static func nearestSnap(to oPrime: CGFloat, positions: [CGFloat], m: HeaderMetrics) -> CGFloat? {
        let band = m.band
        guard band > 0, oPrime.isFinite, oPrime > 0, oPrime < band, !positions.isEmpty else { return nil }
        let candidates = positions.map { snapOffset(progress: $0, m: m) }.sorted()
        var best = candidates[0]
        for c in candidates.dropFirst() where abs(c - oPrime) < abs(best - oPrime) { best = c }
        return best
    }

    /// The `o′` a `snapHeader(to:)` target asks for, clamped to the range.
    static func offset(for target: ZTronHeaderSnapTarget, m: HeaderMetrics) -> CGFloat {
        switch target {
        case .expanded: return 0
        case .collapsed: return m.band
        case let .progress(p): return snapOffset(progress: p, m: m)
        case let .height(h): return m.resting - min(max(h.isFinite ? h : m.resting, min(m.min, m.resting)), m.resting)
        }
    }

    // MARK: Metrics-level helpers (offset in the library convention, `ScrollMetrics`)

    /// `A = adjustedContentInset.top − refreshHold.top`: `o′ = o.y + A`.
    static func base(_ metrics: ScrollMetrics) -> CGFloat {
        metrics.adjustedContentInset.top - metrics.refreshHold.top
    }

    /// `o′` for a content offset. A view whose axes exclude `.vertical` is a fixed banner (`o′ ≡ 0`) unless its zoomed
    /// content exceeds the unobscured height and pans vertically (D15).
    static func headerOffset(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> CGFloat {
        guard let header = m.header else { return 0 }
        let o = offset.y + base(m)
        guard o.isFinite else { return 0 }
        if header.vertical { return o }
        let aci = m.adjustedContentInset
        let unobscured = m.viewportSize.height - aci.top - aci.bottom
        return m.contentSize.height * max(zoom.isFinite ? zoom : 1, 0) > unobscured + 0.5 ? o : 0
    }

    /// The live geometry for a content offset, `nil` without a header.
    static func geometry(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> ZTronHeaderGeometry? {
        m.header.map { geometry(o: headerOffset(offset: offset, zoom: zoom, metrics: m), m: $0) }
    }

    /// The header's top edge: the safe-area top the content adjusts for (`aci.top` without the developer inset, the
    /// hold and the reserved resting height).
    static func top0(_ m: ScrollMetrics) -> CGFloat {
        let aci = m.adjustedContentInset
        return max(0, aci.top - m.contentInset.top - m.refreshHold.top - (m.header?.resting ?? 0))
    }

    /// How much the live header differs from the reserved resting height, `h − R` (negative while collapsed, positive while
    /// stretched): the unobscured top edge is `adjustedContentInset.top + delta` (indicators, `scrollTo`, the resize centre).
    static func obscuredDelta(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> CGFloat {
        guard let header = m.header else { return 0 }
        return height(o: headerOffset(offset: offset, zoom: zoom, metrics: m), m: header) - header.resting
    }

    /// The offset (y) that keeps the header's collapse progress across a change of its metrics (`size`, a new `.fit`
    /// measurement, install over an existing header): at or above rest `o′` is kept, inside the band the progress, and a
    /// collapsed header stays collapsed with the content where it was. `nil` when either side has no header (the plain
    /// inset rule applies). The caller clamps.
    static func keepProgress(offsetY: CGFloat, old: ScrollMetrics, new: ScrollMetrics) -> CGFloat? {
        guard let a = old.header, let b = new.header, a.vertical || b.vertical else { return nil }
        let x = offsetY + base(old)
        let next: CGFloat
        if x <= 0 {
            next = x
        } else if x < a.band {
            next = b.band * (x / a.band)
        } else {
            next = max(offsetY + base(new), b.band)
        }
        return next - base(new)
    }

    /// The content offset (y) that puts something where `place(startInset)` says, with the unobscured top edge evaluated at
    /// the TARGET (`scrollTo` anchors, M6 §4): `place` maps a start inset to the offset that satisfies the anchor in a
    /// viewport whose unobscured area starts there. The live header depends on the target offset itself, so this solves
    /// `o = place(aci.top + δ(o + A))`: header at rest first, then collapsed, else the crossing inside the band (bisection;
    /// `place` is non-increasing in the inset, so the crossing is unique).
    static func solveTarget(metrics m: ScrollMetrics, place: (CGFloat) -> CGFloat) -> CGFloat {
        let top = m.adjustedContentInset.top
        guard let header = m.header, header.vertical else { return place(top) }
        let a = base(m), band = header.band
        let expanded = place(top)
        if expanded + a <= 0 || band <= 0 { return expanded }
        let collapsed = place(top - band)
        if collapsed + a >= band { return collapsed }
        var lo: CGFloat = 0, hi = band
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            if place(top - mid) + a - mid > 0 { lo = mid } else { hi = mid }
        }
        return place(top - (lo + hi) / 2)
    }
}
