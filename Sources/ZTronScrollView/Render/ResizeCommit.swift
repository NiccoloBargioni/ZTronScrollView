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
    /// What the resize preserves (D17, ZTronMapKit geometry): the normalized centre of the zoomed content and the scale.
    /// Sticky across consecutive resizes (`ZTronScrollState.resizeIntent`); nil once the commit is closed.
    var intent: ResizeIntent?
    /// Page kept current when paging is enabled.
    var pagingIndex = Paging()
    /// The point of the unobscured rect that is preserved (center unless `defaultScrollAnchor(for: .sizeChanges)`).
    var focus = UnitPoint.center
    /// True from the commit until `closeResize()`; the effect clamps while open.
    var isOpen = false
}
