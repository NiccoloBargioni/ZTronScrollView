import SwiftUI

// `scrollContentIntegralOverlay` (member, SPEC S8-2a) and `ztronScrollContentIntegralOverlay` (environment twin, S8-2b),
// SPEC S11 amendment 2026-10-21 (user), design M6b §3. Every call appends one overlay; the container draws the twins
// first (outermost first, lowest), then the members in call order, all above the content. No native counterpart: a
// SwiftUI `ScrollView` below a twin ignores it (its own `.overlay` is the viewport's).

// MARK: Member

extension ZTronScrollView {
    /// Draws `content` as a part of the scroll view's content: laid out in the unscaled content space, under the scroll
    /// and zoom transform, so it scrolls and zooms with the content like a marker drawn on a map.
    ///
    /// The overlay's `overlayAnchor` point is pinned on the content point `anchor`, and `size` is resolved against the
    /// content's size: origin = anchor point − `overlayAnchor` × overlay size. The frame follows the content's drawn size
    /// whenever it changes (a reflow on rotation, a list that grows, an image swap), in the same layout pass and with the
    /// same animation as the content; scrolling and zooming never re-run its body. With the default `.fillMaxSize` the
    /// overlay covers the content exactly and the anchors are ignored: the bare call is SwiftUI's `.overlay` applied to
    /// the content, in content space. (A sized overlay with no anchors given lands its top-leading corner on the content's
    /// centre; pass `overlayAnchor: .center` for `.overlay(alignment: .center)` parity.)
    ///
    /// - Several calls stack in order; these members draw above the ``SwiftUI/View/ztronScrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)``
    ///   twins. Re-applying a call with a new anchor or size moves the same overlay (its `@State` survives).
    /// - The overlay does not extend the scrollable range: like `.overlay` on a view inside a native `ScrollView`, a part
    ///   that hangs outside the content is reachable only as far as the content scrolls (the viewport clips it).
    /// - It receives touches like content, above it: a `Button` in it fires on tap, a pan that starts on it scrolls, a
    ///   pinch on it zooms. Apply `.allowsHitTesting(false)` inside `content` to opt out; the host itself is transparent.
    /// - `ztronScrollID` inside it registers a content-space frame: the overlay is a scroll target.
    /// - An `Equatable` overlay (a `Text`, an `Image`, a `Color` included) is diffed with `==`: while a re-evaluation of
    ///   the call site gives a value `==` to the one shown, its body does not run again.
    /// - A `ZTronScrollView` inside the overlay does not inherit the
    ///   ``SwiftUI/View/ztronScrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)`` twins.
    ///
    /// - Parameters:
    ///   - anchor: The content point the overlay is pinned on (default `.center`). A `.relative` anchor is clamped to the
    ///     content (``ZTronUnitPoint``); `.absolute` is not, and is the way to pin a point outside the content.
    ///   - overlayAnchor: The overlay's own point placed on `anchor` (default `.topLeading`, UIKit's `frame.origin`). Not
    ///     clamped: a point outside the overlay's frame (a callout's tail) is legitimate.
    ///   - size: The overlay's size against the content's size (default `.fillMaxSize`): `.fillMaxWidth(height:)` /
    ///     `.fillMaxHeight(width:)` with the free axis `.ideal`, `.aspectRatio`, `.absolute` or `.relative` (a fraction of
    ///     the content's length on that axis), `.relative` fractions of both axes, `.absolute`, `.ideal`
    ///     (``ZTronContentOverlaySize``).
    ///   - scaling: `.withContent` (default) scales with the zoom; `.counterScaled` keeps a constant on-screen size.
    ///   - content: The overlay; evaluated at the call, like SwiftUI's `overlay`.
    public func scrollContentIntegralOverlay<V: View>(anchor: ZTronContentOverlayAnchor = .center,
                                                      overlayAnchor: UnitPoint = .topLeading,
                                                      size: ZTronContentOverlaySize = .fillMaxSize,
                                                      scaling: ZTronContentOverlayScaling = .withContent,
                                                      @ViewBuilder content: () -> V) -> Self {
        var copy = self
        copy.config.contentOverlays.append(ContentOverlayDecl(key: "member.\(config.contentOverlays.count)", anchor: anchor,
                                                              overlayAnchor: overlayAnchor, size: size, scaling: scaling,
                                                              content: content()))
        return copy
    }
}

// MARK: Twin

extension View {
    /// Environment twin of ``ZTronScrollView/scrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)``:
    /// every `ZTronScrollView` below this view draws the overlay as a part of its content (in its unscaled content space,
    /// scrolling and zooming with it; nested scroll views in the content included, each with its own copy). Twins draw
    /// below the members; the outermost twin is the lowest. No native counterpart: a SwiftUI `ScrollView` below ignores it.
    ///
    /// Same placement, sizing, hit-testing, `Equatable` and scrollable-range rules as the member. A `ZTronScrollView`
    /// drawn inside a content-integral overlay does not inherit these twins (a twin holding a scroll view would
    /// otherwise draw itself again inside it).
    public func ztronScrollContentIntegralOverlay<V: View>(anchor: ZTronContentOverlayAnchor = .center,
                                                           overlayAnchor: UnitPoint = .topLeading,
                                                           size: ZTronContentOverlaySize = .fillMaxSize,
                                                           scaling: ZTronContentOverlayScaling = .withContent,
                                                           @ViewBuilder content: () -> V) -> some View {
        modifier(ContentOverlayTwinModifier(decl: ContentOverlayDecl(key: 0, anchor: anchor, overlayAnchor: overlayAnchor,
                                                                     size: size, scaling: scaling, content: content())))
    }
}

/// The twin's declaration goes down the environment (appended, so the outermost twin comes first). Its identity is the
/// `@State` token: stable across re-evaluations of the call site.
struct ContentOverlayTwinModifier: ViewModifier {
    /// The call's declaration; its `key` is replaced by the token.
    let decl: ContentOverlayDecl
    @State private var key = ObserverKey()

    func body(content: Content) -> some View {
        var decl = self.decl
        decl.key = AnyHashable(key)
        return content.transformEnvironment(\.ztronScrollConfig) { $0.contentOverlays.append(decl) }
    }
}
