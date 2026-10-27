import SwiftUI

extension ZTronScrollView {
    /// Installs a scaling header above the content (SPEC S10). Returns the same view type: every other member keeps
    /// working in any order, and the header-equipped view is still a `ZTronScrollView` (state, twins, readers, refresher,
    /// delegate). A later call replaces the header.
    ///
    /// The header precedes the content: its resting height is reserved in `adjustedContentInset.top` (the content starts
    /// below it, also on a horizontal scroll view, where it is a fixed banner), it is drawn above the content with its top
    /// edge pinned below the safe area, and it collapses to `min` by shrinking from the bottom as the content scrolls up.
    /// A pull past the top keeps it at its resting height under `.preserve` and grows it under `.stretch` (only when the
    /// vertical axis can bounce: scrollable content, `scrollBounceBehavior(.always)` or a refresher). Where a `.preserve`
    /// header's gap opens is ``ZTronHeaderPullBehavior`` (``scalingHeaderPullBehavior(_:)``, or
    /// `View.ztronScalingHeaderPullBehavior(_:)` above the scroll view): `.openGap` (the default) keeps the header still and
    /// the gap opens between its bottom edge and the content; `.followContent` moves the header down with the content and
    /// the gap opens above it. Its bottom edge stays on the content's top edge in collapse, pulls (except an `.openGap`
    /// pull, whose gap is the point), refresh holds, snaps, `scrollTo`, rotations and app-driven animated resizes, with the
    /// known limits below. Content shorter than the viewport is top-aligned under the header.
    ///
    /// The builder runs once per cold change (install, a parent rebuild), never while scrolling: it receives a
    /// ``ZTronHeaderProxy`` and its children read the live geometry through ``ZTronHeaderGeometryReader``. No body in the
    /// header runs because it collapses or stretches; its subtree is laid out again at the live frame (a layout pass) every
    /// frame of a collapse. Refresh is S9's `refresher(…)` (with `.stretch` the indicator floats over the stretched band,
    /// with `.preserve` it sits in the gap: below the header with `.openGap`, above it with `.followContent`).
    ///
    /// Known limits (SPEC S10 "Seamless edges", "Natural height", "15–16 layer groups"):
    /// - iOS 15–16: on an app-driven animated resize (Split View, Stage Manager, a `withAnimation` size change), a `.fit`
    ///   header inside the collapse band and an overflow-limited resting height (`.capped` / `.refit` while the limit sets
    ///   it) land in one frame when the resize is committed, at its start; rotations are seamless. A `.fit` header's content change inside the
    ///   band is not re-measured.
    /// - iOS 15–16: the header and the content are each drawn as one compositing group, so a blend mode inside one does
    ///   not reach the other or what is behind the scroll view.
    /// - A scroll command issued while an animated resize is in flight ends the resize: the content takes the final
    ///   geometry at once while the header still animates.
    /// - `background: .ambientBlur` draws a SECOND instance of the header content: its `onAppear` / `task` run for it
    ///   too, and `matchedGeometryEffect` or focus identifiers inside the header are duplicated (avoid them there, or use
    ///   another background).
    ///
    /// - Parameters:
    ///   - size: `.fixed(min:max:)`, `.aspectRatio(_:min:)` (recommended for banners) or `.fit(min:)` (measured).
    ///   - scalingBehavior: the reaction to a pull past the top.
    ///   - snap: snapping inside the collapse band (positions are collapse progress, 0 expanded … 1 collapsed).
    ///   - fade: an optional gradient over the header toward its bottom edge.
    ///   - background: an optional fill of the header's live frame behind its content (``ZTronHeaderBackground``:
    ///     an ambient blur of the content, a frosted glass, a color or any view), below the content and the fade.
    ///   - overflow: what the resting height does when it does not fit the scroll view's container (the viewport below
    ///     the safe area): `.uncapped` (the default) keeps it, `.capped(fraction:)` limits it to a fraction of the
    ///     container's height, `.refit` fits it into the container (an aspect fit for `.aspectRatio`).
    public func withScalingHeader<Header: View>(size: ZTronHeaderSize, scalingBehavior: ZTronHeaderScalingBehavior = .preserve,
                                                snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil,
                                                background: ZTronHeaderBackground? = nil,
                                                overflow: ZTronHeaderOverflow = .uncapped,
                                                @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self {
        var copy = self
        copy.config.header = HeaderSpec(size: size, behavior: scalingBehavior, snap: snap, fade: fade, background: background,
                                        overflow: overflow, builder: { AnyView(header($0)) })
        return copy
    }

    /// Where the gap a pull past the top opens with this view's `.preserve` scaling header (D65): `.openGap` (the default)
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
