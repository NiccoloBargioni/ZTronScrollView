import SwiftUI

// Scaling header (SPEC S10, amendment 2026-10-19; design M8b §2, M8b-header-behaviors): the public value types. The
// header is installed with `ZTronScrollView.withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)`,
// precedes the content (its resting height is reserved in `adjustedContentInset.top`), reacts to the content scrolling up
// over it with its `ZTronHeaderCollapseBehavior` (`.compress`: it shrinks from the bottom with its top edge pinned;
// `.slideBehind`: it keeps its height and the content slides over it, D68) and to a pull past the top with its
// `ZTronHeaderScalingBehavior` (`.preserve`: it keeps its resting height, and where the gap opens is the
// `ZTronHeaderPullBehavior`, D65: below it by default, or above it when it follows the content; `.stretch`: it grows with
// the pull, its top edge pinned).

/// How tall the header rests and how far it collapses.
public enum ZTronHeaderSize: Equatable, Sendable {
    /// Resting height `max`, collapses to `min`; no measurement. Labels are mandatory so the bounds cannot be swapped.
    case fixed(min: CGFloat = 0, max: CGFloat)
    /// Resting height = the scroll view's width ÷ `ratio` (width / height, SwiftUI's convention), recomputed when the width
    /// changes (rotation) as a discrete inset change. The right choice for an image banner: `.aspectRatio(16/9)` is what an
    /// `Image` with `.aspectRatio(16/9, contentMode: .fit)` would measure to, without measurement machinery.
    case aspectRatio(CGFloat, min: CGFloat = 0)
    /// Resting height = the header's ideal height at the scroll view's width (measured; height proposed `nil`). Re-measured
    /// on width and Dynamic Type changes and, on iOS 16+, when the header's content changes. Prefer `.fixed` /
    /// `.aspectRatio` when the height is known.
    case fit(min: CGFloat = 0)

    var minimum: CGFloat {
        switch self {
        case let .fixed(min, _), let .aspectRatio(_, min), let .fit(min): return min
        }
    }

    var isFit: Bool { if case .fit = self { return true } else { return false } }
}

/// What the resting height does when it does not fit the scroll view's container: the viewport below the safe area the
/// content adjusts for, `W × H` (e.g. a full-width 16:9 banner in landscape: 874 / (16/9) = 491 pt on a 381 pt tall
/// container, so the content starts below the screen). User decision 2026-10-25 (D59).
public enum ZTronHeaderOverflow: Equatable, Sendable {
    /// The size's own resting height, even when it is taller than the container (the content then starts below it).
    /// The default.
    case uncapped
    /// At most `fraction` (0…1) of the container's height; `min` is limited the same way.
    case capped(fraction: CGFloat)
    /// Refit into the container: `.aspectRatio(r)` becomes the aspect fit of `r` inside `W × H` (height `min(W / r, H)`),
    /// `.fixed` and `.fit` are limited to `H`; `min` is limited the same way.
    case refit
}

/// The reaction to a pull past the top (the `pull:` parameter of `withScalingHeader`, formerly `scalingBehavior:`).
public enum ZTronHeaderScalingBehavior: Sendable {
    /// The default. The header keeps its resting height; where the gap a pull opens goes, and the refresh indicator with
    /// it, is ``ZTronHeaderPullBehavior`` (below the header by default, above it when the header follows the content).
    case preserve
    /// The header grows with the (rubber-banded) pull, its top edge pinned and its bottom edge on the content's top edge;
    /// a refresh indicator floats over the stretched band. Only when the vertical axis can bounce (scrollable content,
    /// `scrollBounceBehavior(.always)` or a refresher); inert on a scroll view without the vertical axis (a banner).
    /// The growth is a render-time scale (D69): the header stays laid out at its resting height and is drawn scaled by
    /// `(R + pull) / R` about its top centre, clipped to the scroll view's width, so every child grows with it (an
    /// aspect-fit image too) and no body runs; while pulled, text and vector art in it are drawn as the scaled bitmap.
    case stretch
}

/// What a scaling header does with content that fits (shorter than the viewport below the resting header): the
/// `fittingContent:` parameter of `withScalingHeader` (D75). The content's vertical alignment comes from
/// `defaultScrollAnchor(_:for: .alignment)` (centre for a zoomable view, top otherwise); with a top alignment all cases
/// look the same. Content that overflows is drawn the same in every case. A change at run time animates in the
/// transaction it is made in (`withAnimation`), and lands in one frame otherwise.
public enum ZTronHeaderFittingContent: Hashable, Sendable {
    /// The default. The content starts at the header's bottom edge whatever its vertical alignment; its horizontal
    /// alignment is kept. Header and content behave as they do when the content overflows.
    case topAligned
    /// The content keeps its alignment and the header rides on its top edge, as if it were the content's first row:
    /// centred content and header are centred together, with the scroll view's background above the header. With
    /// `pull: .stretch` the header grows into that space instead, as a pull of the same size would make it grow. Pulls,
    /// refresh and collapse work from there.
    case headerFollows
    /// The header stays at its resting place and the content keeps its alignment in the region below it, with a gap
    /// between the two (the look of a header pinned as a safe-area inset).
    case headerPinned
}

/// What a `pull: .stretch` header's content does while a pull past the top grows the header (the `stretchContent:`
/// parameter of `withScalingHeader`, D76). In both cases the header's frame grows by the pull with its top edge pinned and
/// its bottom edge on the content's top, its sides are cut at the scroll view's width, and an aspect-fit image grows from
/// its top centre; they differ in the content's fixed-size parts (text, symbols, controls, padding, fixed frames).
/// `pull: .preserve` and a banner (no vertical axis) ignore it. A change while the header is pulled (a refresh hold)
/// morphs between the two inside the same frame when it is animated (`withAnimation`), and lands in one frame otherwise.
public enum ZTronHeaderStretchContent: Hashable, Sendable {
    /// The default: the whole header is magnified with the pull, `(R + g) / R` times from its top centre (`R` its resting
    /// height, `g` the pull), its text, symbols and controls included, as if the resting header were zoomed in (D69). No
    /// body runs and the header is not laid out again; hit-testing and accessibility frames are magnified with it.
    case keepTextMagnified
    /// The header is laid out larger with the pull, `(R + g) / R` times its resting width and height, from its top
    /// centre: text, symbols, controls and fixed frames keep their point size (text stays sharp), while an aspect-fit
    /// image (and anything else that follows the size it is offered) grows as with ``keepTextMagnified``. No body runs;
    /// the header is laid out at the grown size every frame of a pull, as it is in a collapse. Text whose width follows
    /// the header's width can re-wrap while pulled: give it the resting width with
    /// `ZTronHeaderGeometryReader(…, of: \.width)`. A `GeometryReader` inside the header sees the grown size.
    case keepTextSize
}

/// What the header does while the content scrolls up over it (the `collapse:` parameter of `withScalingHeader`, D68).
/// A struct, like SwiftUI's `Animation`, so that both `.slideBehind` and `.slideBehind(parallax: 0.3)` can be written.
///
/// Whatever the mode, the header's resting height is reserved in `adjustedContentInset.top`, the content's top edge
/// starts on the header's bottom edge at rest, and snap positions (``ZTronHeaderSnap``) and the geometry's `progress`
/// are fractions of the collapse band (0 expanded … 1 collapsed or fully covered).
public struct ZTronHeaderCollapseBehavior: Equatable, Sendable {
    /// The resolved mode (the backdrop is a drawing detail, not part of it).
    enum Kind: Equatable, Sendable {
        case compress
        case slideBehind(parallax: CGFloat)

        /// `k` for `.slideBehind` (0…1, `clamp`ed again: the case can be written directly), `nil` for `.compress`.
        var parallax: CGFloat? {
            if case let .slideBehind(k) = self { return Self.clamp(k) } else { return nil }
        }

        /// The parallax rule: 0…1, NaN reads as 0.5 (the default).
        static func clamp(_ k: CGFloat) -> CGFloat { k.isNaN ? 0.5 : Swift.min(Swift.max(k, 0), 1) }

        var isSlideBehind: Bool { parallax != nil }
    }

    let kind: Kind
    /// `.slideBehind(…, backdrop:)`: the color drawn behind the content (in its own space), `nil` for none.
    let backdrop: Color?
    /// DEBUG: the parallax as written when it was outside 0…1 or NaN (`HeaderSizing.resolve` notes it); not compared.
    let requestedParallax: CGFloat?

    /// The default: the header shrinks from its bottom edge, its top edge pinned, down to the size's `min` as the content
    /// scrolls up (its bottom edge stays on the content's top edge), then the content scrolls under the collapsed header.
    /// The header's subtree is laid out at the live height, so an overlay pinned to its bottom follows the bottom edge.
    public static let compress = Self(kind: .compress, backdrop: nil, requestedParallax: nil)

    /// `.slideBehind(parallax: 0.5)`: the header keeps its resting height and is drawn BEHIND the content, which slides up
    /// over it; the header moves up at half the content's speed. See ``slideBehind(parallax:backdrop:)``.
    public static let slideBehind = Self(kind: .slideBehind(parallax: 0.5), backdrop: nil, requestedParallax: nil)

    /// The header keeps its resting height and is drawn BEHIND the content, which slides up over it (the content's top
    /// edge leaves the header's bottom edge only by covering it); the header itself moves up by `parallax` times the
    /// distance the content has covered: 0 keeps it still, 1 moves it with the content, 0.5 (the default) at half speed.
    /// The band is the whole resting height: the header is fully covered after scrolling by its height (snap positions
    /// and `progress` are the covered fraction), and the size's `min` is ignored.
    ///
    /// The content is drawn over the header as it is: where it does not paint an opaque background of its own (a clear
    /// `List` row, text on nothing), the header shows through it. `backdrop` fills the content's whole frame with a color,
    /// below the content and moving with it (as part of its scrolling transform, no content body runs); the app's
    /// background color is the recommended value, `nil` (the default) draws nothing.
    ///
    /// As it moves up the header is clipped where the content is, at the scroll view's own frame (not separately at the
    /// safe-area top): nothing of it is drawn or touched outside the scroll view. Touches in the uncovered part reach the
    /// header; covered parts cannot be touched (VoiceOver reaches its elements until it is fully covered). Switching
    /// `collapse:` between `.compress` and `.slideBehind` at run time installs the header again: its builder runs once
    /// more and its `@State` starts over (the content keeps its identity and state).
    ///
    /// - Parameters:
    ///   - parallax: 0…1, clamped (NaN reads as 0.5).
    ///   - backdrop: an optional color drawn behind the content.
    public static func slideBehind(parallax: CGFloat = 0.5, backdrop: Color? = nil) -> Self {
        let k = Kind.clamp(parallax)
        return Self(kind: .slideBehind(parallax: k), backdrop: backdrop, requestedParallax: k == parallax ? nil : parallax)
    }

    /// Equal when the mode (with its parallax as read, after clamping) and the backdrop are equal.
    public static func == (a: Self, b: Self) -> Bool { a.kind == b.kind && a.backdrop == b.backdrop }

    /// `k` for `.slideBehind`, `nil` for `.compress`.
    var parallax: CGFloat? { kind.parallax }
    var isSlideBehind: Bool { kind.isSlideBehind }
}

/// Where the gap a pull past the top opens with a `.preserve` scaling header (D65, user 2026-10-27). Set it for every
/// `ZTronScrollView` below a view with `View.ztronScalingHeaderPullBehavior(_:)`, or on one scroll view with
/// `ZTronScrollView.scalingHeaderPullBehavior(_:)` (the member wins). `.stretch` ignores it (the header grows, there is no
/// gap), and so does a banner (a header on a scroll view without the vertical axis).
public enum ZTronHeaderPullBehavior: Hashable, Sendable {
    /// The default. The header stays still at its resting place and height; the content pulls away from it, so the gap
    /// opens BETWEEN the header's bottom edge and the content's top, and a top refresh indicator sits in that gap (its
    /// base is the resting header's bottom edge, `adjustedContentInset.top` minus the refresh hold).
    case openGap
    /// The header moves down with the content at its resting height (its bottom edge stays on the content's top); the gap,
    /// and a top refresh indicator, open ABOVE it, between the safe-area top and the header's top edge (D61).
    case followContent
}

/// Snapping inside the collapse band. Positions are collapse progress: 0 expanded, 1 collapsed (the reference's inverse
/// convention is gone).
public struct ZTronHeaderSnap: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case disabled, immediately, afterFinishAccelerating }
    let mode: Mode
    let positions: [CGFloat]

    /// No snapping (the default).
    public static let disabled = ZTronHeaderSnap(mode: .disabled, positions: [])
    /// The release target is moved to the nearest position (velocity-aware: it works on the projected rest) through the
    /// scroll-target pipeline, after the scroll view's own target behavior; `willEndDragging` sees the snapped target.
    public static func immediately(at positions: [CGFloat] = [0, 1]) -> Self {
        ZTronHeaderSnap(mode: .immediately, positions: positions)
    }
    /// Once the deceleration ends inside the band, the header animates to the nearest position.
    public static func afterFinishAccelerating(at positions: [CGFloat] = [0, 1]) -> Self {
        ZTronHeaderSnap(mode: .afterFinishAccelerating, positions: positions)
    }
}

/// A gradient over the header toward its bottom edge (the `fade:` parameter of `withScalingHeader`, D70), drawn above the
/// header's content and background and below any refresh indicator, inside the header (it collapses, stretches and moves
/// with it; no body runs because of it).
///
/// One gradient for every state: `.linear(to: color, from: 0.5)`. A gradient per state: `.init(rest:collapse:pull:)`,
/// e.g. `.init(rest: .linear(to: bg), collapse: .linear(to: bg, from: 0), pull: nil)`: `rest` at rest, `collapse` while
/// the content scrolls up over the header, `pull` while it is pulled past the top. The states crossfade, without jumps:
/// the collapse state is reached in proportion to the collapse progress (fully when collapsed or covered), the pull state
/// in proportion to the pull (fully at half the header's resting height). A `nil` state draws no fade.
public struct ZTronHeaderFade: Equatable {
    /// One state's gradient: clear at `start` of the band, `color` at the band's end. The band is the header's frame
    /// (`.compress`; under `.stretch` it stretches with the header) or, under `.slideBehind`, the header's uncovered part:
    /// the gradient reaches its color exactly where the content's top edge covers the header.
    public struct Gradient: Equatable {
        let color: Color
        /// 0…1 (NaN reads as 0.5).
        let start: CGFloat

        /// A linear gradient from clear at `start` (a fraction of the band from the header's top, 0…1, clamped) to `color`
        /// at the band's end.
        public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self {
            Self(color: color, start: start.isNaN ? 0.5 : Swift.min(Swift.max(start, 0), 1))
        }
    }

    /// The gradient at rest (`nil`: none).
    public var rest: Gradient?
    /// The gradient while the content scrolls up over the header, reached fully when it is collapsed (`.compress`) or
    /// covered (`.slideBehind`); `nil`: none.
    public var collapse: Gradient?
    /// The gradient while the content is pulled past the top, reached fully at a pull of half the header's resting
    /// height; `nil`: none.
    public var pull: Gradient?

    /// A gradient per state, crossfaded by the scroll position (see the type). A state left `nil` draws no fade.
    public init(rest: Gradient?, collapse: Gradient? = nil, pull: Gradient? = nil) {
        self.rest = rest
        self.collapse = collapse
        self.pull = pull
    }

    /// The same linear gradient in every state, from clear at `start` (a fraction of the band, 0…1) to `color` at the
    /// band's end: `rest`, `collapse` and `pull` are all `Gradient.linear(to: color, from: start)`.
    public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self {
        let g = Gradient.linear(to: color, from: start)
        return Self(rest: g, collapse: g, pull: g)
    }
}

/// What fills the header's live frame behind the header's content (user decision 2026-10-26), so a header whose content
/// does not cover its frame (an aspect ratio ≤ 1, a `.refit` or aspect-fit content) shows it instead of blank areas. It is
/// drawn below the content and below the `fade:` gradient, clipped to the live frame, and follows that frame in every
/// animation (collapse, `.stretch` growth, the `.preserve` pull, resizes, rotations) by layout: no body in it is
/// re-evaluated per frame, but it is laid out at the live frame each frame of a collapse and the renderer redraws a blur
/// or a material at the new size. Hidden from accessibility and from hit-testing. Known limits: SPEC S10.
public struct ZTronHeaderBackground {
    enum Kind {
        case ambientBlur(radius: CGFloat)
        case frostedGlass(radius: CGFloat)
        case color(Color)
        case view(AnyView)
    }
    let kind: Kind

    /// A blurred, scaled-to-fill second instance of the header's own content (the "ambient" artwork background of a music
    /// player). The copy is the same builder result instantiated a second time: its body runs once more per cold change
    /// of the header (install, a parent rebuild, a size change), never per frame. It is laid out at the live frame, filled
    /// with the content's own aspect ratio (overflow cropped) and blurred by `radius` points with opaque edges (an infinite
    /// radius is the strongest blur, a negative one none). It is a separate instance: its `@State` is its own, its
    /// `onAppear` / `task` run for it too (side effects run twice), and `matchedGeometryEffect` or focus identifiers in
    /// the header content are duplicated (two sources of one id: avoid them in a header with this background). Readers
    /// inside it (``ZTronHeaderGeometryReader``, ``ZTronScrollReader``) are cold: they show the geometry taken when the
    /// copy was built and at each cold change (a resize, a new resting height), never per frame, so the copy never
    /// doubles the header's per-frame reader work.
    public static func ambientBlur(radius: CGFloat = 30) -> Self { Self(kind: .ambientBlur(radius: radius)) }

    /// A backdrop blur of whatever is drawn behind the header, with the system material (`Material`, iOS 15+) whose blur
    /// is nearest to `radius`: about 6 pt `.ultraThinMaterial`, 12 `.thinMaterial`, 20 `.regularMaterial`, 30
    /// `.thickMaterial`, 40 `.ultraThickMaterial`. The radius is APPROXIMATE: the materials' blurs are the system's (they
    /// also differ in tint and vibrancy) and the value only picks the nearest one.
    public static func frostedGlass(radius: CGFloat = 20) -> Self { Self(kind: .frostedGlass(radius: radius)) }

    /// A plain color.
    public static func color(_ color: Color) -> Self { Self(kind: .color(color)) }

    /// Any view, proposed the live frame. Type-erased; built by the caller, once per cold change of the header.
    public static func view<V: View>(@ViewBuilder _ content: () -> V) -> Self { Self(kind: .view(AnyView(content()))) }

    /// The material nearest to a blur radius (`.frostedGlass`), monotonic over the whole line: `+∞` is the thickest,
    /// `−∞` the thinnest, NaN the default's (20, `.regularMaterial`).
    static func material(radius: CGFloat) -> Material {
        let nominal: [(CGFloat, Material)] = [(6, .ultraThinMaterial), (12, .thinMaterial), (20, .regularMaterial),
                                              (30, .thickMaterial), (40, .ultraThickMaterial)]
        let r = radius.isNaN ? 20 : min(max(radius, 0), 1_000)
        return nominal.min { abs($0.0 - r) < abs($1.0 - r) }!.1
    }

    /// The radius `.ambientBlur` blurs with: negative and NaN draw no blur, `+∞` the strongest (`maximumBlurRadius`;
    /// beyond a header's own size every radius looks alike, the blur averages the whole frame).
    static func blurRadius(_ radius: CGFloat) -> CGFloat {
        radius.isNaN ? 0 : min(max(radius, 0), maximumBlurRadius)
    }

    /// The largest `.ambientBlur` radius drawn (an infinite or larger one is read as this).
    static let maximumBlurRadius: CGFloat = 1_000
}

/// What a header child reads through ``ZTronHeaderGeometryReader`` (or `ZTronScrollGeometry.header`).
public struct ZTronHeaderGeometry: Equatable, Sendable {
    /// 0 expanded … 1 collapsed (`.slideBehind`: the covered fraction of the header); 0 when the header cannot collapse.
    public var progress: CGFloat
    /// The drawn height, stretch included: the live height under `.compress` (`restingHeight` shrinking to `minHeight`),
    /// the resting height under `.slideBehind` (the content covers it; it does not shrink). Under a `.stretch` pull the
    /// header is laid out at its resting height and DRAWN scaled by `height / restingHeight` from its top centre (D69),
    /// readers inside it too: a child sized from `height` is scaled once more; size it from `restingHeight` for an
    /// unscaled size.
    public var height: CGFloat
    /// ≥ 0: how much `.stretch` grew the header past its resting height; always 0 under `.preserve` (a pull opens a gap
    /// below a preserved header, or moves it down by that amount with `ZTronHeaderPullBehavior.followContent`).
    public var stretch: CGFloat
    /// The size's `min` as resolved (0 under `.slideBehind`, which ignores it).
    public var minHeight: CGFloat
    /// The resolved resting height (the reference's `maxHeight`).
    public var restingHeight: CGFloat
    /// The scroll view's width.
    public var width: CGFloat
    /// ≥ 0: how far `fittingContent: .headerFollows` moved the header down from its resting place to ride on the top edge
    /// of content that fits (`slack · alignment`, the content's own alignment padding); 0 in the other cases and once the
    /// content overflows. The header's drawn top edge is its resting top edge plus `lift`.
    public var lift: CGFloat = 0

    /// What a reader sees before the header resolves or without a header: all zeros.
    static let unresolved = ZTronHeaderGeometry(progress: 0, height: 0, stretch: 0, minHeight: 0, restingHeight: 0, width: 0)

    /// A reader transform that changes only `steps + 1` times over a full collapse: `round(progress · steps)`.
    public static func quantizedProgress(steps: Int) -> (ZTronHeaderGeometry) -> Int {
        { Int(($0.progress * CGFloat(steps)).rounded()) }
    }
}

/// The handle the header builder receives. It exposes no geometry, hot or cold: a child that takes it in its initializer
/// reads the geometry inside a ``ZTronHeaderGeometryReader`` only, so a hot read in the builder's own scope (which would
/// re-run the whole header every frame) cannot be written.
public struct ZTronHeaderProxy: Equatable {
    let state: ZTronScrollState

    public nonisolated static func == (a: Self, b: Self) -> Bool { a.state === b.state }
}

/// `state.snapHeader(to:)` targets. `.progress` and `.height` are clamped to the header's range.
public enum ZTronHeaderSnapTarget: Equatable, Sendable {
    case expanded, collapsed, progress(CGFloat), height(CGFloat)
}

/// The resolved, cold facts of an installed header (`ScrollMetrics.header`). `resting` is reserved in
/// `adjustedContentInset.top`; collapse and stretch never change it.
struct HeaderMetrics: Equatable, Sendable {
    var min: CGFloat
    var resting: CGFloat
    var behavior: ZTronHeaderScalingBehavior
    /// D68: what the header does as the content scrolls up over it (a cold change, like `behavior`).
    var collapse: ZTronHeaderCollapseBehavior.Kind = .compress
    /// D65: where a `.preserve` header's pull gap opens (`HeaderMath.gapAbove` / `gapBelow`); `.stretch` and banners ignore
    /// it. Resolved from the member, else the environment, else `.openGap` (a cold change, like `behavior`).
    var pull: ZTronHeaderPullBehavior = .openGap
    /// The scroll view's (viewport) width the size was resolved at.
    var width: CGFloat
    /// The vertical offset drives the header (`axes` contain `.vertical`). Off: a fixed banner, except while zoomed content
    /// pans vertically (D15).
    var vertical: Bool = true

    /// The collapse band: how far the content scrolls up over the header until it is collapsed: `R − min` (`.compress`:
    /// the header shrinks to `min`) or `R` (`.slideBehind`: until the content covers it; `min` is ignored, D68). Snap
    /// positions, `progress`, S7's kept progress, `keepProgress` and `scrollTo`'s solve all read it.
    var band: CGFloat { collapse.isSlideBehind ? Swift.max(0, resting) : Swift.max(0, resting - min) }

    /// The visible (uncovered) height at the band's end: `min` (at most `R`) for `.compress`, 0 for `.slideBehind`.
    var collapsedHeight: CGFloat { collapse.isSlideBehind ? 0 : Swift.min(min, resting) }
}
