import SwiftUI

extension ZTronScrollView {
    /// Installs a scaling header above the content (SPEC S10). Returns the same view type: every other member keeps
    /// working in any order, and the header-equipped view is still a `ZTronScrollView` (state, twins, readers, refresher,
    /// delegate). A later call replaces the header.
    ///
    /// The header precedes the content: its resting height is reserved in `adjustedContentInset.top` (the content starts
    /// below it, also on a horizontal scroll view, where it is a fixed banner), it is drawn above the content with its top
    /// edge pinned below the safe area, and it collapses to `min` by shrinking from the bottom as the content scrolls up.
    /// A pull past the top moves it down with the content under `.preserve` (a gap opens above it) and grows it under
    /// `.stretch` (only when the vertical axis can bounce: scrollable content, `scrollBounceBehavior(.always)` or a
    /// refresher). Its bottom edge stays on the content's top edge in every animation: collapse, pulls, refresh holds,
    /// snaps, `scrollTo`, rotations and animated resizes.
    ///
    /// The builder runs once per cold change (install, a parent rebuild), never while scrolling: it receives a
    /// ``ZTronHeaderProxy`` and its children read the live geometry through ``ZTronHeaderGeometryReader``. Refresh is S9's
    /// `refresher(…)` (with `.stretch` the indicator floats over the stretched band, with `.preserve` it sits in the gap
    /// above the header).
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
}
