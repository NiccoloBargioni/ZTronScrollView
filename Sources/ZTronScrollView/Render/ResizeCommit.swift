import SwiftUI

/// What the transform effect needs to map the animated viewport `size` to an offset/scale (design M5 section 2). Cold;
/// lives in `ScrollMetrics`, so a commit publishes on `.metrics` once.
struct ResizeCommit: Equatable, Sendable {
    struct Snapshot: Equatable, Sendable {
        var viewport: CGSize = .zero
        var contentSize: CGSize = .zero
        var insets: EdgeInsets = EdgeInsets()
    }
    struct Paging: Equatable, Sendable {
        var x: Int?
        var y: Int?
    }
    /// The geometry the committed target values are expressed in.
    var current = Snapshot()
    /// The geometry the transition started from (== `current` unless the viewport size changed).
    var previous = Snapshot()
    /// Scaling-header height at commit (unobscured center only).
    var header: CGFloat = 0
    /// Unscaled content point kept at the focus point: `anchorOld` at the start of the transition, `anchorNew` at the
    /// end. They differ only for a registry-target reflow.
    var anchorOld = CGPoint.zero
    var anchorNew = CGPoint.zero
    /// `anchorOld` normalized to the content size it was captured in, clamped into [0, 1]^2 (D16, ported from
    /// ZTronMapKit's `normalizedCenter`). Content that reflows with the viewport is re-anchored from it:
    /// `anchorNew = normalizedAnchor * newContentSize`. Equals `anchorOld / contentSize` for fixed-size content.
    var normalizedAnchor = CGPoint(x: 0.5, y: 0.5)
    /// Page kept current when paging is enabled.
    var pagingIndex = Paging()
    /// The point of the unobscured rect that is preserved (center unless `defaultScrollAnchor(for: .sizeChanges)`).
    var focus = UnitPoint.center
    /// True from the commit until `closeResize()`; the effect clamps while open.
    var isOpen = false
}
