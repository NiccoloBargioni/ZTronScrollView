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
    /// The overflow policy (D59), applied by the layout to its own `W × H` exactly as the state applies it.
    var overflow: ZTronHeaderOverflow = .uncapped
    /// The committed metrics (`nil`: unresolved, the header is not drawn).
    var metrics: HeaderMetrics?
    /// Collapse progress, `.stretch` growth (the scale effect's `g`, D69: never in a layout height) and the `.preserve`
    /// translation (`g` under a pull with `ZTronHeaderPullBehavior.followContent`, D61; always 0 with `.openGap`, D65: the
    /// field then never changes).
    var progress: CGFloat = 0
    var stretch: CGFloat = 0
    var translation: CGFloat = 0
    /// The state's LAYOUT height `h_L` (`layoutHeight(_:progress:)`: `R − p · band`, `R` under `.slideBehind`; D69: the
    /// stretch is drawn by `HeaderStretchEffect`, not laid out): the 15 path's frame where it does not follow the width,
    /// and a banner of a view without the vertical axis keeps it (its content reserve is state-driven too).
    var stateHeight: CGFloat = 0
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
    /// D70: the pull `g = max(0, −o′)` (both pull behaviors), for the fade's pull weight only (`HeaderFadeOverlay`), and
    /// whether it is tracked: only when the fade's pull state differs from its rest (`HeaderFadeMath.tracksPull`), so
    /// every other configuration keeps today's input bit for bit (an `.openGap` pull then changes nothing in it). Like the
    /// progress, the resize intent's anchor while a resize is open. The geometry consumers get `geometry` (no pull).
    var pull: CGFloat = 0
    var tracksPull = false
    /// D79: the catch pin and the model `o′` while it holds (`ZTronScrollState.catchPinRef`, set by
    /// `HeaderFrameModifier.wake()` when the input follows the offset); `nil` otherwise, so the input is bit for bit as
    /// without it (D62). `at(offset:)` carries it: each effect that interpolates `o′` reads `pinned(_:)`.
    var catchPin: HeaderCatchPin?
    /// D76, `m`: the share of the `.stretch` pull that is laid out (`stretchContent:`): 0 for `.keepTextMagnified` (D69:
    /// the whole pull is the scale effect's, bit for bit), 1 for `.keepTextSize` (the stack is laid out grown, nothing is
    /// magnified). Animatable with `offset` in the five consumers that draw the pull (`HeaderSlotLayout`,
    /// `HeaderFallbackFrame`, `HeaderStretchEffect`, `HeaderStretchClip`, `HeaderFadeOverlay`), so an app-animated option
    /// change morphs between the two in the same frame; strictly between 0 and 1 only inside such a change. Set by
    /// `HeaderFrameModifier.wake()`; `at(offset:)` and `pinned(_:)` keep it (the catch pin replaces `o′` only).
    var layoutShare: CGFloat = 0

    var layoutDriven: Bool { metrics?.vertical == true }

    /// D76, `g_l = m · g`: the laid-out share of the stretch (exactly 0 at `m = 0`, exactly `g` at `m = 1`).
    var layoutStretch: CGFloat {
        let g = stretch.isFinite ? Swift.max(0, stretch) : 0
        let m = layoutShare.isFinite ? Swift.min(Swift.max(layoutShare, 0), 1) : 0
        return m == 0 ? 0 : (m == 1 ? g : m * g)
    }

    /// D76, `g_s = g − g_l`: the magnified share of the stretch, `HeaderStretchEffect`'s (exactly `stretch` at `m = 0`:
    /// D69 bit for bit). The crisp `.keepTextMagnified` path (M8b-s9) attaches to this share.
    var scaleStretch: CGFloat {
        let l = layoutStretch
        return l == 0 ? stretch : stretch - l
    }

    /// D79: the input an effect draws: re-derived at the model `o′` (`at(offset:)`) while the pin holds for `key` (after a
    /// drawn catch, until this effect's own interpolation of `o′` reaches the model: `CatchPin`); `self` otherwise.
    func pinned(_ key: CatchPin.Key) -> HeaderLiveInput {
        guard let p = catchPin else { return self }
        let o = p.ref.resolve(key, interpolated: offset, model: p.model)
        return o == offset ? self : at(offset: o)
    }

    /// The input without the fade's pull (`pull`, `tracksPull`): what the slot, the frames and the effects read, so a
    /// tracked pull never re-lays the header out.
    var geometry: HeaderLiveInput {
        guard tracksPull else { return self }
        var c = self
        c.pull = 0
        c.tracksPull = false
        return c
    }

    /// `k`, the `.slideBehind` parallax (D68), 0 under `.compress`: the layout moves the header by
    /// `HeaderMath.collapseTranslation(progress:parallax:layoutHeight:)` (`−k · p · h_L`, from its own `h_L`). Read from the
    /// committed metrics, so it is as bit-stable as they are.
    var parallax: CGFloat { metrics?.collapse.parallax ?? 0 }

    /// `h_L` from the state (`R − p · band`; `R` under `.slideBehind`, whose header keeps its height while the content
    /// covers it, D68). No stretch (D69).
    static func layoutHeight(_ m: HeaderMetrics, progress p: CGFloat) -> CGFloat {
        m.collapse.isSlideBehind ? Swift.max(0, m.resting) : Swift.max(0, m.resting - p * m.band)
    }

    /// `h_v`, what the content leaves uncovered (`HeaderMath.visibleHeight`): `R − p · band + stretch`. The visibility
    /// gate reads it (hidden at ≤ 0.5). Derived from the fields above, so it is as bit-stable as they are.
    var visibleHeight: CGFloat {
        guard let m = metrics else { return 0 }
        return Swift.max(0, m.resting - progress * m.band + stretch)
    }

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
        c.stateHeight = Self.layoutHeight(m, progress: g.progress)
        if c.tracksPull { c.pull = HeaderMath.pullDistance(o: o) }
        return c
    }
}

/// D79: what `HeaderLiveInput` carries while a catch pin holds: the pin and the header offset `o′` of the model.
struct HeaderCatchPin: Equatable {
    let ref: CatchPin.Ref
    let model: CGFloat
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

/// Pure scaling-header math (design M8b §2.4, M8b-header-behaviors §2), no SwiftUI state. Conventions: `top0` = the top of
/// the header's slot (the adjusted safe-area top), `R` resting height, `band` = `max(0, R − min)` (`.compress`) or `R`
/// (`.slideBehind`, `min` ignored), `o′` = the header-relative offset (content
/// offset + `adjustedContentInset.top` − the refresh hold: rest is 0, a pull past the top is negative, scrolling up
/// positive), `c = clamp(o′, 0, band)` the collapse travel and `g = max(0, −o′)` the overflow.
///
/// | | `.preserve` `.openGap` (D65, default) | `.preserve` `.followContent` (D61) | `.stretch` |
/// |---|---|---|---|
/// | top edge | `top0` (still) | `top0 + g` (moves down with the content) | `top0` (pinned) |
/// | drawn height `h` | `R − c` | `R − c` | `R − c + g` (D69: laid out at `R − c`, scaled by `(R + g) / R`) |
/// | bottom edge | `top0 + R − c` | `top0 + g + R − c` | `top0 + R − c + g` |
/// | gap above the header (`gapAbove`, the translation) | 0 | `g`: `[top0, top0 + g]`, the refresh indicator's slot | 0 |
/// | gap below the header (`gapBelow`) | `g`: `[top0 + R, top0 + R + g]`, the refresh indicator's slot | 0 | 0 (the indicator floats over the band) |
/// | content top (viewport y) | `aci.top − hold − o′ = top0 + ci.top + R − c + g` | same | same |
///
/// So the header's bottom edge is the content's top edge on both sides of rest except under an `.openGap` pull, where the
/// gap `g` lies between them (a developer `contentInset.top` adds a constant gap); past the band the content scrolls under
/// the collapsed header. A banner (no vertical axis) translates like `.followContent` whatever the pull behavior says (D65:
/// banners are unaffected; only zoomed content that pans vertically can pull one, D15).
///
/// The collapse mode (D68) changes only the content-up side (`c > 0`); the pull side above is the same in both. `k` is the
/// `.slideBehind` parallax, `h_L` the layout height (what the slot lays the stack out at), `h_v` the visible height (what
/// the content leaves uncovered: the inset consumers' header height), `s` the `.stretch` scale (D69: a render-time scale
/// of the stack laid out at `h_L`, anchored at its top centre):
///
/// | | `.compress` (default) | `.slideBehind(k)` |
/// |---|---|---|
/// | `h_L` (`layoutHeight`) | `R − c` (`(1 − p)·R + p·min`) | `R` |
/// | `h_v` (`visibleHeight`) | `R − c + stretch` | `R − c + stretch` |
/// | collapse translation `t_c` (`collapseTranslation`) | 0 | `−k·c` (`−k·p·h_L` in the layout) |
/// | stretch scale `s` (`stretchScale`) | `(h_L + g) / h_L` = `1 + g/R` under a `.stretch` pull (`c = 0`), else 1 | same |
/// | drawn top / bottom edge | `top0 + t_g` / `+ h_L·s` | `top0 + t_g − k·c` / `+ R·s` |
/// | content top (viewport y) | `top0 + ci.top + R − c + g` (unchanged) | same |
/// | `progress` / geometry `height` | `c / band` / `h_L·s` | `c / R` (covered fraction) / `R·s` |
/// | `obscuredDelta` | `h_v + t_g − R` | same |
/// | z-order | above the content | behind the content |
///
/// `t_g` is the pull translation (`gapAbove`); `gapBelow`, `refreshTop` and every band reader (snap, `offset(for:)`,
/// `keepProgress`, the resize anchor, `solveTarget`) are the same functions of `band` in both modes.
enum HeaderMath {
    /// The metrics `size` resolves to at `width` (the viewport width); `nil` while the width is unknown or `.fit` is
    /// unmeasured. `containerHeight` (the viewport below the adjusted safe area, `HeaderMath.containerHeight`) limits the
    /// resting height and `min` per `overflow`; unknown (≤ 0) limits nothing. Pure and string-free: the header's layout
    /// calls it on every pass (`layoutResting`); the DEBUG diagnostics of a degenerate size are `warning(…)`, which only
    /// the state's cold resolve (`HeaderSizing.resolve`) asks for.
    static func metrics(size: ZTronHeaderSize, width: CGFloat, natural: CGFloat?,
                        behavior: ZTronHeaderScalingBehavior = .preserve,
                        collapse: ZTronHeaderCollapseBehavior.Kind = .compress, pull: ZTronHeaderPullBehavior = .openGap,
                        vertical: Bool = true, containerHeight: CGFloat = 0,
                        overflow: ZTronHeaderOverflow = .uncapped) -> HeaderMetrics? {
        var minimum = max(0, size.minimum.isFinite ? size.minimum : 0)
        var resting: CGFloat
        switch size {
        case let .fixed(_, max):
            resting = max.isFinite ? Swift.max(0, max) : 0
        case let .aspectRatio(ratio, _):
            guard width > 0, width.isFinite else { return nil }
            resting = ratio > 0 && ratio.isFinite ? width / ratio : 0
        case .fit:
            guard let natural else { return nil }
            resting = natural.isFinite ? Swift.max(0, natural) : 0
        }
        // The overflow policy (D59): the size's resting height and `min`, limited by the container.
        let limit = overflowLimit(overflow, containerHeight: containerHeight)
        resting = min(resting, limit)
        minimum = min(minimum, limit)
        // `.slideBehind` ignores `min` (the content covers the whole header, D68), so its `min ≥ R` rule never applies.
        if collapse.isSlideBehind { minimum = 0 }
        // `min ≥ R`: a fixed-height header of height `min` (band 0, progress 0, no snapping; `.stretch` still grows).
        if minimum >= resting { resting = minimum }
        let w = width.isFinite ? Swift.max(0, width) : 0
        return HeaderMetrics(min: minimum, resting: resting, behavior: behavior, collapse: collapse, pull: pull, width: w,
                             vertical: vertical)
    }

    /// The overflow policy's limit `L` on the resting height and `min` (D59) for a container `containerHeight` tall
    /// (`containerHeight(viewport:safe:adjusted:keyboard:)`): `.capped(f)` → `f · H` (`f` clamped to 0…1, 1 when not
    /// finite), `.refit` → `H` (for `.aspectRatio`, `W / r` capped at `H` is the aspect fit of `r` inside `W × H`),
    /// `.uncapped` or an unknown container (≤ 0, not finite) → ∞. `metrics(…)` applies it; the 15–16 `.fit` box
    /// (`HeaderFallbackPlan`, D78) clamps its layout box's ideal height to it (the measuring box inside stays unlimited).
    static func overflowLimit(_ overflow: ZTronHeaderOverflow, containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0, containerHeight.isFinite else { return .infinity }
        switch overflow {
        case .uncapped: return .infinity
        case let .capped(fraction): return containerHeight * (fraction.isFinite ? min(max(fraction, 0), 1) : 1)
        case .refit: return containerHeight
        }
    }

    #if DEBUG
    /// The DEBUG warning for a degenerate `size` or `overflow` (the first that applies), `nil` when there is none or the
    /// size does not resolve (`metrics(…)` is `nil`). Never on the layout path. `collapse`: `.slideBehind` ignores `min`
    /// (`metrics(…)`), so `min > max` resolves to `R = max` there, not to a fixed header of height `min` (C-RC-3).
    static func warning(size: ZTronHeaderSize, width: CGFloat, natural: CGFloat?, containerHeight: CGFloat = 0,
                        overflow: ZTronHeaderOverflow = .uncapped,
                        collapse: ZTronHeaderCollapseBehavior.Kind = .compress) -> String? {
        switch size {
        case let .fixed(min, max):
            if min > max {
                return collapse.isSlideBehind
                    ? "withScalingHeader: .fixed(min: \(min), max: \(max)) has min > max: .slideBehind ignores min, a header of height \(max)"
                    : "withScalingHeader: .fixed(min: \(min), max: \(max)) has min > max: a fixed header of height \(min)"
            }
        case let .aspectRatio(ratio, _):
            guard width > 0, width.isFinite else { return nil }
            if !(ratio > 0 && ratio.isFinite) { return "withScalingHeader: .aspectRatio(\(ratio)) needs a positive ratio (width / height)" }
        case .fit:
            guard let natural else { return nil }
            let resting = natural.isFinite ? Swift.max(0, natural) : 0
            if resting < 1 {
                return "withScalingHeader: .fit measured a resting height of \(resting): the header has no ideal height (only flexible views). Use .fixed, .aspectRatio or .frame(idealHeight:)"
            }
        }
        if containerHeight > 0, containerHeight.isFinite, case let .capped(fraction) = overflow {
            let f = fraction.isFinite ? min(max(fraction, 0), 1) : 1
            if f != fraction { return "withScalingHeader: overflow .capped(fraction: \(fraction)) is outside 0…1, read as \(f)" }
        }
        return nil
    }
    #endif

    /// The live geometry at `o′` (§2.4 table): `progress = c / band`, the drawn `height` (`.compress`: `R − c + stretch`;
    /// `.slideBehind`: `R + stretch`, the content covers it instead of shrinking it).
    static func geometry(o oPrime: CGFloat, m: HeaderMetrics) -> ZTronHeaderGeometry {
        let c = covered(o: oPrime, m: m)
        let band = m.band
        let stretch = stretch(o: oPrime, m: m)
        let height = m.collapse.isSlideBehind ? m.resting + stretch : m.resting - c + stretch
        return ZTronHeaderGeometry(progress: band > 0 ? c / band : 0, height: max(0, height),
                                   stretch: stretch, minHeight: m.min, restingHeight: m.resting, width: m.width)
    }

    /// The drawn height at `o′` (`geometry(…).height`).
    static func height(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat { geometry(o: oPrime, m: m).height }

    /// `c = clamp(o′, 0, band)`: how far the content has scrolled up over the header (NaN / ±∞ read as rest).
    static func covered(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        min(max(oPrime.isFinite ? oPrime : 0, 0), m.band)
    }

    /// The pull past the top at `o′`, `g = max(0, −o′)`, whatever the pull behavior (NaN / ±∞ read as rest): the fade's
    /// pull weight (D70).
    static func pullDistance(o oPrime: CGFloat) -> CGFloat {
        oPrime.isFinite ? max(0, -oPrime) : 0
    }

    /// The `.stretch` growth at `o′`: `g = max(0, −o′)` under `.stretch`, else 0.
    static func stretch(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        m.behavior == .stretch ? max(0, -(oPrime.isFinite ? oPrime : 0)) : 0
    }

    /// `h_v`, the visible height at `o′`: the part of the drawn header the content leaves uncovered, `R − c` plus the
    /// `.stretch` growth (both modes; `.compress`: the live height). What the inset consumers count onto the unobscured
    /// top (`obscuredDelta`) and what the visibility gate reads (hidden at ≤ 0.5).
    static func visibleHeight(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        max(0, m.resting - covered(o: oPrime, m: m) + stretch(o: oPrime, m: m))
    }

    /// `h_L`, the height the slot lays the header stack out at (D68 / D69): `R − c` under `.compress`, `R` under
    /// `.slideBehind`; the `.stretch` growth is NOT in it (it is the render-time `stretchScale`).
    static func layoutHeight(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        max(0, m.collapse.isSlideBehind ? m.resting : m.resting - covered(o: oPrime, m: m))
    }

    /// `t_c`, the `.slideBehind` header's translation at `o′`: `−k·c` (up by the parallax times the covered distance; at
    /// most `k·R`); 0 under `.compress`.
    static func collapseTranslation(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        guard let k = m.collapse.parallax else { return 0 }
        return -k * covered(o: oPrime, m: m)
    }

    /// `t_c` as the layout derives it (D68 §3.2): `−k·p·h` from the progress, the parallax and the pass's own layout height
    /// (`R` at the committed viewport), so an animated resize interpolates it with the content. NaN-safe.
    static func collapseTranslation(progress p: CGFloat, parallax k: CGFloat, layoutHeight h: CGFloat) -> CGFloat {
        let q = p.isFinite ? min(max(p, 0), 1) : 0
        let height = h.isFinite ? max(0, h) : 0
        return -ZTronHeaderCollapseBehavior.Kind.clamp(k) * q * height
    }

    /// `s`, the `.stretch` scale of a stack laid out at `h` grown by `stretch` (D69): `(h + stretch) / h`, 1 without a
    /// stretch, for `h ≤ 0` (a zero resting height) or non-finite input.
    static func stretchScale(layoutHeight h: CGFloat, stretch: CGFloat) -> CGFloat {
        guard h > 0, h.isFinite, stretch > 0, stretch.isFinite else { return 1 }
        return (h + stretch) / h
    }

    /// `s` at `o′` from the committed metrics: `1 + g/R` under a `.stretch` pull (`c = 0` there, so `h_L = R`), else 1.
    static func stretchScale(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        stretchScale(layoutHeight: layoutHeight(o: oPrime, m: m), stretch: stretch(o: oPrime, m: m))
    }

    /// D76, the laid-out share of a pull (`.keepTextSize`): the size a stack laid out at `h` (16+: the slot's `h_L(W, H)`)
    /// is proposed when `stretch` (`g_l`) of the pull is laid out, `(W · s_l, h + g_l)` with `s_l = (h + g_l) / h`, so its
    /// aspect-fit content grows exactly as D69's scale grows it. Exactly `(W, h)` without a laid-out share (`s_l == 1`:
    /// `g_l ≤ 0`, `h ≤ 0`, non-finite input), so `.keepTextMagnified` (`g_l = 0`) proposes D69's size bit for bit.
    static func grownSize(width w: CGFloat, layoutHeight h: CGFloat, stretch gl: CGFloat) -> CGSize {
        let s = stretchScale(layoutHeight: h, stretch: gl)
        guard s != 1 else { return CGSize(width: w, height: h) }
        return CGSize(width: w * s, height: h + gl)
    }

    /// D76, half the width a laid-out share adds (`(s_l − 1) · W / 2`): the 15 path grows the stack outside its slot-wide
    /// frame by this much on each side. For an unlimited `.aspectRatio(r)` (`h = W / r`) it is `g_l · r / 2`, free of `W`.
    /// 0 without a laid-out share or for non-finite input.
    static func grownSidePad(width w: CGFloat, layoutHeight h: CGFloat, stretch gl: CGFloat) -> CGFloat {
        let s = stretchScale(layoutHeight: h, stretch: gl)
        guard s != 1, w.isFinite, w > 0 else { return 0 }
        return (s - 1) * w / 2
    }

    /// D76, the `.stretch` clip of a stack in its LAYOUT frame `rect` with the pull split into a laid-out share `g_l` and a
    /// magnified share `g_s` (`HeaderStretchClip`):
    /// - x / width: on a grown frame (16+, the stack proposed `grownSize`: `rect` is `W · s_l` wide) the centred slot width
    ///   `W = rect.width · (rect.height − g_l) / rect.height`; otherwise (`grownFrame` false, the 15 path's frame is the
    ///   slot's `W`; or no laid-out share) the frame's own `minX` / `width`;
    /// - height: `rect.height · s_eff`, `s_eff = (rect.height + g_s) / rect.height` (`HeaderStretchEffect`'s scale), the
    ///   drawn bottom edge `top + h + g`.
    /// With `g_l = 0` (`.keepTextMagnified`) it is D69's clip exactly (`W × h · s`); with `g_s = 0` the grown frame's `W`
    /// columns at its own height. For `.aspectRatio` and `.fixed` frames interpolated linearly in an animated resize the
    /// derived `W` is exact: `(W(t) + g·r) · (W(t)/r) / (W(t)/r + g) = W(t)`. `displayScale` (> 0): the side inset
    /// `(rect.width − W) / 2` is snapped to the pixel grid. SwiftUI places the grown frame at pixel-rounded edges, so
    /// its width is not exactly `W · s_l` (452 for 452.25 at 3x) and the derived `W` came out up to ⅓ px narrower per side
    /// (i28 R5, hosted: 0.11 pt each side at `g` 30); the snapped inset puts the clip's edges on the slot's pixel edges.
    static func stretchClip(in rect: CGRect, layoutStretch gl: CGFloat, scaleStretch gs: CGFloat, grownFrame: Bool,
                            displayScale: CGFloat = 0) -> CGRect {
        let s = stretchScale(layoutHeight: rect.height, stretch: gs)
        var x = rect.minX, w = rect.width
        if grownFrame, gl > 0, gl.isFinite, rect.height > gl, rect.height.isFinite, rect.width.isFinite {
            w = rect.width * (rect.height - gl) / rect.height
            var inset = (rect.width - w) / 2
            if displayScale > 0, displayScale.isFinite { inset = (inset * displayScale).rounded() / displayScale }
            x = rect.minX + inset
            w = rect.width - 2 * inset
        }
        return CGRect(x: x, y: rect.minY, width: w, height: rect.height * s)
    }

    /// Whether a pull moves the header down with the content: `.preserve` with `ZTronHeaderPullBehavior.followContent`
    /// (D61), and a `.preserve` banner whatever the setting (D65: banners are unaffected by it). `.stretch` never moves.
    static func followsContent(_ m: HeaderMetrics) -> Bool {
        m.behavior == .preserve && (m.pull == .followContent || !m.vertical)
    }

    /// The gap a pull opens ABOVE the header, between `top0` and the header's top edge: `max(0, −o′)` when the header
    /// follows the content (`followsContent`: it moves down by that much, D61), else 0 (`.openGap` keeps it still, D65;
    /// `.stretch` pins its top). Also the header's translation.
    static func gapAbove(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        followsContent(m) ? max(0, -(oPrime.isFinite ? oPrime : 0)) : 0
    }

    /// The header's top edge below `top0` at `o′` (the `.preserve` `.followContent` translation, `gapAbove`; 0 with
    /// `.openGap`, so that header's live input never changes under a pull).
    static func translation(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat { gapAbove(o: oPrime, m: m) }

    /// The gap a pull opens BETWEEN the header's bottom edge and the content's top (pre-D61 `contentGap`, restored by D65):
    /// `max(0, −o′)` for a `.preserve` header that stays still (`.openGap`), else 0 (`.followContent` moves the header with
    /// the content, `.stretch` grows into the gap).
    static func gapBelow(o oPrime: CGFloat, m: HeaderMetrics) -> CGFloat {
        m.behavior == .preserve && !followsContent(m) ? max(0, -(oPrime.isFinite ? oPrime : 0)) : 0
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
        case let .height(h): return m.resting - min(max(h.isFinite ? h : m.resting, m.collapsedHeight), m.resting)
        }
    }

    // MARK: Metrics-level helpers (offset in the library convention, `ScrollMetrics`)

    /// The height of the overflow policy's container: the viewport below the safe area on the adjusted edges (what a
    /// `GeometryReader` around the scroll view, inside the safe area, would report), never negative, WITHOUT the keyboard
    /// (D64): `keyboard` is how far the keyboard's region of the bottom safe area reaches above the keyboard-free one
    /// (`ScrollMetrics.keyboardExtension`, 0 without a keyboard), given back. The header's slot is the same region (its
    /// overlay ignores the `.keyboard` region on the bottom edge), so the layout and the state resolve the same `R`; the
    /// keyboard never changes `R` or `min`, while the content's adjusted inset keeps it (S8).
    static func containerHeight(viewport: CGSize, safe: EdgeInsets, adjusted edges: Edge.Set, keyboard: CGFloat = 0) -> CGFloat {
        let k = keyboard.isFinite ? max(0, keyboard) : 0
        return max(0, viewport.height - (edges.contains(.top) ? safe.top : 0) - (edges.contains(.bottom) ? safe.bottom : 0)) + k
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
    /// stretched band, drawn only over it and on its far end once it is shorter than the indicator, also while
    /// refreshing: `RefreshIndicatorMath.inStretchBand`, S-RS-1); `.preserve` `.followContent` → `top0`, the gap `[top0, top0 + pull]` a pull opens above the header
    /// that moves down with the content (D61), placement as the refresher says. `nil` (the plain base, `aci.top − hold`,
    /// which follows the adjusted inset in a resize) without a vertical header and for `.preserve` `.openGap` (D65): the
    /// header stays still and the gap `[top0 + ci.top + R, … + pull]` opens below it, exactly where the plain base is.
    static func refreshTop(_ m: ScrollMetrics) -> (base: CGFloat, overlay: Bool)? {
        guard let header = m.header, header.vertical else { return nil }
        switch header.behavior {
        case .stretch: return (top0(m) + header.resting, true)
        case .preserve: return header.pull == .followContent ? (top0(m), false) : nil
        }
    }

    /// How far the visible header's bottom edge is from where the resting header's would be (`top0 + R`), `h_v +
    /// translation − R` (`−c` in the band, in both collapse modes: a `.slideBehind` header's covered part is the content's;
    /// under a pull `g` for `.stretch` and `.preserve` `.followContent`, 0 for `.preserve` `.openGap`, whose header stays
    /// still: D65, pre-D61 `h − R`): the unobscured top edge is `adjustedContentInset.top + delta` (indicators,
    /// `scrollTo`, the resize centre).
    static func obscuredDelta(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> CGFloat {
        guard let header = m.header else { return 0 }
        let o = headerOffset(offset: offset, zoom: zoom, metrics: m)
        return visibleHeight(o: o, m: header) + translation(o: o, m: header) - header.resting
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
    /// the slot's proposed height, the region between the adjusted safe areas; `nil`: the committed one). The same
    /// `metrics(…)` as the state's (size, D59 overflow policy, `min ≥ R` rule), so at the committed viewport the layout and
    /// the state agree exactly. `.fit` at the committed width and container keeps the committed `R`: a header content
    /// change moves the header and the content together, in the state's commit (which adopts the measurement).
    static func layoutResting(width w: CGFloat, containerHeight: CGFloat?, natural: CGFloat?,
                              _ live: HeaderLiveInput) -> (resting: CGFloat, min: CGFloat) {
        guard let m = live.metrics else { return (0, 0) }
        let committed = (m.resting, Swift.min(m.min, m.resting))
        guard let size = live.size, w > 0, w.isFinite else { return committed }
        let container = containerHeight.map { $0.isFinite ? Swift.max(0, $0) : 0 } ?? live.committedContainer
        if size.isFit, isCommittedViewport(width: w, container: container, live) { return committed }
        guard let r = metrics(size: size, width: w, natural: natural, behavior: m.behavior, collapse: m.collapse,
                              vertical: m.vertical, containerHeight: container, overflow: live.overflow) else { return committed }
        return (r.resting, Swift.min(r.min, r.resting))
    }

    /// `.fit`'s committed-viewport test (16+ `layoutResting`, the 15–16 box of D78): the layout's width and overflow
    /// container are the committed ones (within 0.5 pt). There the layout keeps the committed `R`, so a header content
    /// change moves the header with the content's inset, in the state's commit; elsewhere (a resize's layout pass) it
    /// follows the content's ideal height at the layout's width.
    static func isCommittedViewport(width w: CGFloat, container: CGFloat, _ live: HeaderLiveInput) -> Bool {
        guard let m = live.metrics else { return false }
        return abs(w - m.width) <= 0.5 && abs(container - live.committedContainer) <= 0.5
    }

    /// The header's live LAYOUT height at a layout size: `h_L = (1 − p) · R(W, H) + p · min(W, H)`, with `p` from the state
    /// and `R`, `min` from the layout. Equal to the state's `R − c` at the committed viewport; inside a resize nothing in
    /// it changes at the unanimated commit while the progress is kept (D51). The `.stretch` growth is not in it (D69): the
    /// stack laid out at `h_L` is drawn scaled by `(h_L + g) / h_L` (`HeaderStretchEffect`), so a pull lays nothing out.
    ///
    /// A banner (a view without the vertical axis) is laid out the same way, so an app-driven animated width change
    /// interpolates it with the content (review d16: it took the state's height, was laid out at `(W_new, R_old)` in the
    /// animated pass and re-set to `R_new` by the unanimated commit: a 90 pt one-frame step and 159 pt lateral in the seam
    /// lab). Its `p` and stretch are 0 except while zoomed content pans vertically (D15). Its overflow container is the
    /// committed one: a banner's adjusted edges exclude the safe area's top and bottom, the header slot's do not.
    ///
    /// `.slideBehind` (D68): `h_L = R(W, H)` at every progress (the content covers the header instead of shrinking it); the
    /// layout moves it up by `collapseTranslation(progress:parallax:layoutHeight:)` of this same height.
    static func liveHeight(width w: CGFloat, containerHeight: CGFloat?, natural: CGFloat?, _ live: HeaderLiveInput) -> CGFloat {
        guard let m = live.metrics else { return 0 }
        let r = layoutResting(width: w, containerHeight: live.layoutDriven ? containerHeight : nil, natural: natural, live)
        if m.collapse.isSlideBehind { return Swift.max(0, r.resting) }
        return Swift.max(0, (1 - live.progress) * r.resting + live.progress * r.min)
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
