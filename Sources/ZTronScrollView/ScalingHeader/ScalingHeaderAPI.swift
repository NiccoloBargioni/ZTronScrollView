import SwiftUI

extension ZTronScrollView {
    /// Installs a scaling header above the content (SPEC S10), or behind it with `collapse: .slideBehind`. Returns the
    /// same view type: every other member keeps working in any order, and the header-equipped view is still a
    /// `ZTronScrollView` (state, twins, readers, refresher, delegate). A later call replaces the header.
    ///
    /// The header precedes the content: its resting height is reserved in `adjustedContentInset.top` (the content starts
    /// below it, also on a horizontal scroll view, where it is a fixed banner) and its top edge is pinned below the safe
    /// area (except under `.slideBehind`, which moves it up with the parallax as the content covers it). Its reactions are
    /// split by scroll direction:
    /// - `collapse:`, as the content scrolls up over it: `.compress` (the default) draws it above the content and shrinks
    ///   it from the bottom to the size's `min`; `.slideBehind` keeps its height, draws it behind the content, which
    ///   slides over it, and moves it up with a parallax (``ZTronHeaderCollapseBehavior``). `.slideBehind` needs the
    ///   content to paint its own background where it covers the header (or a `backdrop:` color).
    /// - `pull:`, as the content is pulled past its top (only when the vertical axis can bounce: scrollable content,
    ///   `scrollBounceBehavior(.always)` or a refresher): `.preserve` (the default) keeps it at its resting height, and
    ///   where its gap opens is ``ZTronHeaderPullBehavior`` (``scalingHeaderPullBehavior(_:)``, or
    ///   `View.ztronScalingHeaderPullBehavior(_:)` above the scroll view): `.openGap` (the default) keeps the header still
    ///   and the gap opens between its bottom edge and the content; `.followContent` moves the header down with the
    ///   content and the gap opens above it. `.stretch` grows it with the pull.
    ///
    /// Its bottom edge stays on the content's top edge in collapse (under `.compress`; under `.slideBehind` the content's
    /// top edge is where its uncovered part ends, and its own bottom edge is under the content), pulls (except an
    /// `.openGap` pull, whose gap is the point), refresh holds, snaps, `scrollTo`, rotations and app-driven animated
    /// resizes, with the known limits below.
    /// Content shorter than the viewport (below the resting header) is placed by `fittingContent:`: top-aligned under the
    /// header by default.
    ///
    /// The builder runs once per cold change (install, a parent rebuild), never while scrolling: it receives a
    /// ``ZTronHeaderProxy`` and its children read the live geometry through ``ZTronHeaderGeometryReader``. No body in the
    /// header runs because it collapses or stretches; its subtree is laid out again at the live frame (a layout pass) every
    /// frame of a collapse. Refresh is S9's `refresher(…)` (with `.stretch` the indicator floats over the stretched band
    /// and goes up with it when the content is scrolled during a refresh, with `.preserve` it sits in the gap: below the
    /// header with `.openGap`, above it with `.followContent`).
    ///
    /// Known limits (SPEC S10 "Seamless edges", "Natural height", "15–16 layer groups"):
    /// - iOS 15–16: on an app-driven animated resize (Split View, Stage Manager, a `withAnimation` size change), a `.fit`
    ///   header inside the collapse band and an overflow-limited resting height (`.capped` / `.refit` while the limit sets
    ///   it) land in one frame when the resize is committed, at its start; rotations are seamless. A `.fit` header's content change inside the
    ///   band is not re-measured.
    /// - iOS 15–16: the header, the content and a refresh indicator are each drawn as one compositing group, so a blend
    ///   mode inside one does not reach the others or what is behind the scroll view.
    /// - A scroll command issued while an animated resize is in flight ends the resize: the content takes the final
    ///   geometry at once while the header still animates.
    /// - `background: .ambientBlur` draws a SECOND instance of the header content: its `onAppear` / `task` run for it
    ///   too, and `matchedGeometryEffect` or focus identifiers inside the header are duplicated (avoid them there, or use
    ///   another background).
    ///
    /// - Parameters:
    ///   - size: `.fixed(min:max:)`, `.aspectRatio(_:min:)` (recommended for banners) or `.fit(min:)` (measured).
    ///   - collapse: the reaction to the content scrolling up over the header: `.compress` (the default) or
    ///     `.slideBehind` / `.slideBehind(parallax:backdrop:)`. Switching between the two at run time installs the
    ///     header again (its builder runs once more and its `@State` starts over).
    ///   - pull: the reaction to a pull past the top: `.preserve` (the default) or `.stretch`.
    ///   - snap: snapping inside the collapse band (positions are collapse progress, 0 expanded … 1 collapsed; under
    ///     `.slideBehind` the covered fraction).
    ///   - fade: an optional gradient over the header toward its bottom edge: `.linear(to:from:)` in every state, or one
    ///     per state crossfaded by the scroll position (``ZTronHeaderFade/init(rest:collapse:pull:)``).
    ///   - background: an optional fill of the header's live frame behind its content (``ZTronHeaderBackground``:
    ///     an ambient blur of the content, a frosted glass, a color or any view), below the content and the fade.
    ///   - overflow: what the resting height does when it does not fit the scroll view's container (the viewport below
    ///     the safe area): `.uncapped` (the default) keeps it, `.capped(fraction:)` limits it to a fraction of the
    ///     container's height, `.refit` fits it into the container (an aspect fit for `.aspectRatio`).
    ///   - fittingContent: where content that fits (shorter than the viewport below the resting header) sits relative
    ///     to the header (``ZTronHeaderFittingContent``): `.topAligned` (the default) starts it at the header's bottom
    ///     edge; `.headerFollows` keeps its alignment (`defaultScrollAnchor(_:for: .alignment)`) with the header riding on
    ///     its top edge; `.headerPinned` keeps its alignment below the resting header. A change at run time animates in
    ///     the transaction it is made in.
    ///   - stretchContent: with `pull: .stretch`, what the content does while a pull grows the header
    ///     (``ZTronHeaderStretchContent``): `.keepTextMagnified` (the default) magnifies the whole header;
    ///     `.keepTextSize` lays it out larger, so text and controls keep their size and an aspect-fit image still grows.
    ///     A change while the header is pulled morphs between the two inside the same frame when animated
    ///     (`withAnimation`), and lands in one frame otherwise; at rest both draw the same. A change runs the header's
    ///     builder once (a cold change), never its content per frame.
    ///   - header: the header's content, built once per cold change.
    public func withScalingHeader<Header: View>(size: ZTronHeaderSize, collapse: ZTronHeaderCollapseBehavior = .compress,
                                                pull: ZTronHeaderScalingBehavior = .preserve,
                                                snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil,
                                                background: ZTronHeaderBackground? = nil,
                                                overflow: ZTronHeaderOverflow = .uncapped,
                                                fittingContent: ZTronHeaderFittingContent = .topAligned,
                                                stretchContent: ZTronHeaderStretchContent = .keepTextMagnified,
                                                @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self {
        var copy = self
        copy.config.header = HeaderSpec(size: size, behavior: pull, collapse: collapse, snap: snap, fade: fade,
                                        background: background, overflow: overflow, fitting: fittingContent,
                                        stretchContent: stretchContent, builder: { AnyView(header($0)) })
        return copy
    }

    /// The former spelling of
    /// ``withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:stretchContent:header:)``:
    /// `scalingBehavior:` is now `pull:` (same type, same meaning), the header collapses with `.compress`, content that
    /// fits is top-aligned under it (`fittingContent: .topAligned`) and a `.stretch` pull magnifies it
    /// (`stretchContent: .keepTextMagnified`). (The rename lists the new member without `collapse:`, `fittingContent:`
    /// and `stretchContent:`, so the fix-it maps `scalingBehavior:` onto `pull:` label for label.)
    @available(*, deprecated, renamed: "withScalingHeader(size:pull:snap:fade:background:overflow:header:)",
               message: "scalingBehavior: is now pull:")
    public func withScalingHeader<Header: View>(size: ZTronHeaderSize, scalingBehavior: ZTronHeaderScalingBehavior,
                                                snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil,
                                                background: ZTronHeaderBackground? = nil,
                                                overflow: ZTronHeaderOverflow = .uncapped,
                                                @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self {
        withScalingHeader(size: size, pull: scalingBehavior, snap: snap, fade: fade, background: background,
                          overflow: overflow, fittingContent: .topAligned, stretchContent: .keepTextMagnified,
                          header: header)
    }

    /// Where the gap a pull past the top opens with this view's `pull: .preserve` scaling header (D65; it refines
    /// `.preserve`): `.openGap` (the default)
    /// keeps the header still at its resting place and the gap, with the top refresh indicator, opens between the header's
    /// bottom edge and the content's top; `.followContent` moves the header down with the content and opens them above it.
    /// `.stretch` ignores it, and so does a banner (no vertical axis). Wins over the environment twin
    /// `View.ztronScalingHeaderPullBehavior(_:)`; independent of the order of `withScalingHeader` (it survives a later call
    /// that replaces the header). A change is a cold configuration change (no content or header body runs); during a live
    /// pull the header takes the new mode's place in that frame (in the change's animation, if it has one).
    public func scalingHeaderPullBehavior(_ behavior: ZTronHeaderPullBehavior) -> Self {
        var copy = self
        copy.config.headerPull = behavior
        return copy
    }
}
