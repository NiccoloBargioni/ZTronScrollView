import SwiftUI

/// A snapshot's header facts for the resize math (M8b-3): `base` = `adjustedContentInset.top − refreshHold.top` (`o′ = o.y +
/// base`) and the collapse band. Interpolated with the drawn geometry like the insets.
struct HeaderResize: Equatable, Sendable {
    var base: CGFloat
    var band: CGFloat

    static func lerp(_ a: HeaderResize?, _ b: HeaderResize?, _ t: CGFloat) -> HeaderResize? {
        guard let a, let b else { return b ?? a }
        return HeaderResize(base: a.base + (b.base - a.base) * t, band: a.band + (b.band - a.band) * t)
    }
}

/// The state's half of the header's live frame (M8b-3 seamless header, from seam spike A), built by the per-frame leaf
/// from the target offset (or, while a resize is open, from the resize intent's anchor): the layout combines it with the
/// proposed size (`HeaderMath.liveHeight`), so an animated resize interpolates the header with the content.
struct HeaderLiveInput: Equatable {
    /// The container's size spec (`nil`: none, the committed `R` is used).
    var size: ZTronHeaderSize?
    /// The overflow policy (D52), applied by the layout to its own `W × H` exactly as the state applies it.
    var overflow: ZTronHeaderOverflow = .uncapped
    /// The committed metrics (`nil`: unresolved, the header is not drawn).
    var metrics: HeaderMetrics?
    /// Collapse progress, `.stretch` growth and `.preserve` translation (both `g` under a pull).
    var progress: CGFloat = 0
    var stretch: CGFloat = 0
    var translation: CGFloat = 0
    /// The state's height (`R − c + stretch`): a banner of a view without the vertical axis keeps it (its content reserve
    /// is state-driven too).
    var stateHeight: CGFloat = 0
    /// The adjusted safe-area bottom (0 when the content does not adjust for it): the overflow container is the proposed
    /// height minus it (the header's overlay is proposed the viewport below the safe-area top).
    var bottomInset: CGFloat = 0
    /// The container height the committed metrics were resolved against (`HeaderMath.containerHeight`).
    var committedContainer: CGFloat = 0
    /// `.fit`: the committed natural height (the 15 path tells a limited `R` from the natural one).
    var natural: CGFloat?
    /// The header offset `o′` the progress, stretch, translation and state height were derived from, and whether they
    /// follow it. `o′` is the animatable data of the header's layout (16+ `HeaderSlotLayout`, 15 `HeaderFallbackFrame` /
    /// `HeaderTranslation`): a transaction-driven scroll (`withAnimation { scroll(to:) }`, a `scrollTo` under a SwiftUI
    /// animation) interpolates `o′` with the content's offset, and every frame re-derives the rest exactly as the state
    /// does at that `o′`, so the header stays on the content's top across the band's edges (interpolating the height
    /// itself left the header up to 132 pt off the content while the content crossed the band, seam lab). While a resize
    /// is open they do not follow it (the intent's anchor) and `offset` holds the last followed value: the animatable
    /// data does not change at the resize commit.
    var offset: CGFloat = 0
    var followsOffset = false

    var layoutDriven: Bool { metrics?.vertical == true }

    /// The same input at the header offset `o` (an animation frame): re-derived as `HeaderFrameModifier.liveInput` does
    /// when it follows the offset; only `offset` changes otherwise.
    func at(offset o: CGFloat) -> HeaderLiveInput {
        var c = self
        c.offset = o
        guard followsOffset, let m = metrics else { return c }
        let g = HeaderMath.geometry(o: o, m: m)
        c.progress = g.progress
        c.stretch = g.stretch
        c.translation = HeaderMath.translation(o: o, m: m)
        c.stateHeight = Swift.max(0, m.resting - g.progress * m.band + g.stretch)
        return c
    }
}

/// Where the header was when a resize captured its intent.
enum HeaderResizeAnchor: Equatable, Sendable {
    /// At or above rest: `o′ ≤ 0` (a pull or a refresh hold) is kept.
    case top(CGFloat)
    /// Inside the band: the progress is kept (`o′ = p · band` in the new geometry).
    case progress(CGFloat)
    /// Collapsed: the visible centre below the minimum-height header is kept, and the header stays collapsed.
    case collapsed
}

/// Pure scaling-header math (design M8b §2.4), no SwiftUI state. Conventions: `top0` = the top of the header's slot (the
/// adjusted safe-area top), `R` resting height, `band = max(0, R − min)`, `o′` = the header-relative offset (content
/// offset + `adjustedContentInset.top` − the refresh hold: rest is 0, a pull past the top is negative, scrolling up
/// positive), `c = clamp(o′, 0, band)` the collapse travel and `g = max(0, −o′)` the overflow.
///
/// | | `.preserve` | `.stretch` |
/// |---|---|---|
/// | top edge | `top0 + g` (moves down with the content) | `top0` (pinned) |
/// | height `h` | `R − c` | `R − c + g` |
/// | bottom edge | `top0 + g + R − c` | `top0 + R − c + g` |
/// | gap above the header (`gapAbove`) | `g`: `[top0, top0 + g]`, the refresh indicator's slot | 0 (the indicator floats over the band) |
/// | content top (viewport y) | `aci.top − hold − o′ = top0 + ci.top + R − c + g` = the bottom edge (+ `ci.top`) | same |
///
/// So the header's bottom edge is the content's top edge on both sides of rest (a developer `contentInset.top` adds a
/// constant gap); past the band the content scrolls under the collapsed header.
enum HeaderMath {
    /// The metrics `size` resolves to at `width` (the viewport width) and a DEBUG warning when the size is degenerate. `nil`
    /// while the width is unknown or `.fit` is unmeasured. `containerHeight` (the viewport below the adjusted safe area,
    /// `HeaderMath.containerHeight`) limits the resting height and `min` per `overflow`; unknown (≤ 0) limits nothing.
    static func resolve(size: ZTronHeaderSize, width: CGFloat, natural: CGFloat?,
                        behavior: ZTronHeaderScalingBehavior = .preserve, vertical: Bool = true,
                        containerHeight: CGFloat = 0, overflow: ZTronHeaderOverflow = .uncapped)
        -> (metrics: HeaderMetrics?, warning: String?) {
        var minimum = max(0, size.minimum.isFinite ? size.minimum : 0)
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
        // The overflow policy (D52): the size's resting height and `min`, limited by the container.
        if containerHeight > 0, containerHeight.isFinite {
            let limit: CGFloat
            switch overflow {
            case .uncapped: limit = .infinity
            case let .capped(fraction):
                let f = fraction.isFinite ? min(max(fraction, 0), 1) : 1
                if f != fraction { warning = warning ?? "withScalingHeader: overflow .capped(fraction: \(fraction)) is outside 0…1, read as \(f)" }
                limit = containerHeight * f
            case .refit: limit = containerHeight     // .aspectRatio: W / r capped at H is the aspect fit of r inside W × H
            }
            resting = min(resting, limit)
            minimum = min(minimum, limit)
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

    /// The gap a pull opens ABOVE the header, between `top0` and the header's top edge (user decision 2026-10-26):
    /// `.preserve` `max(0, −o′)` (the header moves down with the content by that much), `.stretch` 0 (its top is pinned).
    /// Also the header's translation. There is never a gap between the header's bottom and the content's top.
    static func gapAbove(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        m.behavior == .preserve ? max(0, -(oPrime.isFinite ? oPrime : 0)) : 0
    }

    /// The header's top edge below `top0` at `o′` (the `.preserve` translation, `gapAbove`).
    static func translation(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat { gapAbove(o: oPrime, m: m) }

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

    /// The height of the overflow policy's container: the viewport below the safe area on the adjusted edges (what a
    /// `GeometryReader` around the scroll view, inside the safe area, would report), never negative.
    static func containerHeight(viewport: CGSize, safe: EdgeInsets, adjusted edges: Edge.Set) -> CGFloat {
        max(0, viewport.height - (edges.contains(.top) ? safe.top : 0) - (edges.contains(.bottom) ? safe.bottom : 0))
    }

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

    /// The top refresh indicator's base with a vertical header (SPEC S10 "Refresh with the header"): `.stretch` → the top
    /// of the band it grows into (`top0 + R`), overlay placement forced (there is no gap: the indicator floats over the
    /// stretched band); `.preserve` → `top0`, the gap `[top0, top0 + pull]` a pull opens above the header that moves down
    /// with the content (user decision 2026-10-26), placement as the refresher says. `nil` without a vertical header.
    static func refreshTop(_ m: ScrollMetrics) -> (base: CGFloat, overlay: Bool)? {
        guard let header = m.header, header.vertical else { return nil }
        switch header.behavior {
        case .stretch: return (top0(m) + header.resting, true)
        case .preserve: return (top0(m), false)
        }
    }

    /// How far the live header's bottom edge is from where the resting header's would be (`top0 + R`), `h + translation −
    /// R` (negative while collapsed, the pull `g` under a pull for both behaviors): the unobscured top edge is
    /// `adjustedContentInset.top + delta` (indicators, `scrollTo`, the resize centre).
    static func obscuredDelta(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> CGFloat {
        guard let header = m.header else { return 0 }
        let o = headerOffset(offset: offset, zoom: zoom, metrics: m)
        return height(o: o, m: header) + translation(o: o, m: header) - header.resting
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

    // MARK: Layout-driven live frame (M8b-3 seamless header)

    /// The resting height and minimum at a LAYOUT size: the proposed width `w` and the overflow container (`containerHeight`,
    /// the proposed height below the safe-area top minus the adjusted safe-area bottom; `nil`: the committed one). The same
    /// `resolve` as the state's (size, D52 overflow policy, `min ≥ R` rule), so at the committed viewport the layout and
    /// the state agree exactly. `.fit` at the committed width and container keeps the committed `R`: a header content
    /// change moves the header and the content together, in the state's commit (which adopts the measurement).
    static func layoutResting(width w: CGFloat, containerHeight: CGFloat?, natural: CGFloat?,
                              _ live: HeaderLiveInput) -> (resting: CGFloat, min: CGFloat) {
        guard let m = live.metrics else { return (0, 0) }
        let committed = (m.resting, Swift.min(m.min, m.resting))
        guard let size = live.size, w > 0, w.isFinite else { return committed }
        let container = containerHeight.map { $0.isFinite ? Swift.max(0, $0) : 0 } ?? live.committedContainer
        if size.isFit, abs(w - m.width) <= 0.5, abs(container - live.committedContainer) <= 0.5 { return committed }
        guard let r = resolve(size: size, width: w, natural: natural, behavior: m.behavior, vertical: m.vertical,
                              containerHeight: container, overflow: live.overflow).metrics else { return committed }
        return (r.resting, Swift.min(r.min, r.resting))
    }

    /// The header's live height at a layout size: `h = (1 − p) · R(W, H) + p · min(W, H) + stretch`, with `p` and the
    /// stretch from the state and `R`, `min` from the layout. Equal to the state's `R − c + stretch` at the committed
    /// viewport; inside a resize nothing in it changes at the unanimated commit while the progress is kept (D51).
    ///
    /// A banner (a view without the vertical axis) is laid out the same way, so an app-driven animated width change
    /// interpolates it with the content (review d16: it took the state's height, was laid out at `(W_new, R_old)` in the
    /// animated pass and re-set to `R_new` by the unanimated commit: a 90 pt one-frame step and 159 pt lateral in the seam
    /// lab). Its `p` and stretch are 0 except while zoomed content pans vertically (D15). Its overflow container is the
    /// committed one: a banner's adjusted edges exclude the safe area's top and bottom, the header slot's do not.
    static func liveHeight(width w: CGFloat, containerHeight: CGFloat?, natural: CGFloat?, _ live: HeaderLiveInput) -> CGFloat {
        guard live.metrics != nil else { return 0 }
        let r = layoutResting(width: w, containerHeight: live.layoutDriven ? containerHeight : nil, natural: natural, live)
        return Swift.max(0, (1 - live.progress) * r.resting + live.progress * r.min + live.stretch)
    }

    // MARK: Resize (SPEC S7: the scaling header keeps its collapse progress)

    /// The header's resize geometry for `m` (`nil` without a header driven by the vertical offset).
    static func resizeGeometry(_ m: ScrollMetrics) -> HeaderResize? {
        guard let header = m.header, header.vertical else { return nil }
        return HeaderResize(base: base(m), band: header.band)
    }

    /// Where the header is at a content offset (captured by the resize intent).
    static func resizeAnchor(offsetY: CGFloat, _ g: HeaderResize) -> HeaderResizeAnchor {
        let x = offsetY + g.base
        if x <= 0 { return .top(x) }
        if g.band > 0, x < g.band { return .progress(x / g.band) }
        return .collapsed
    }

    /// The offset (y) that realises `anchor` in `g`: `o′` kept at or above rest, the progress inside the band, and while
    /// collapsed the centre rule's `centred` (computed with the header at its minimum height), kept collapsed.
    static func resizeOffsetY(_ anchor: HeaderResizeAnchor, centred: CGFloat, _ g: HeaderResize) -> CGFloat {
        switch anchor {
        case let .top(x): return x - g.base
        case let .progress(p): return p * g.band - g.base
        case .collapsed: return max(centred, g.band - g.base)
        }
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
