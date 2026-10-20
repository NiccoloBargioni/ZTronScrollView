import SwiftUI
import ZTronScrollPhysics

/// Mirrors `PagingScrollTargetBehavior`: pages one container long, at most one page per fling.
///
/// It is the release-pipeline form of `isPagingEnabled` (design M6 §4): both resolve to the same `PagingSolver` call per
/// enabled axis, from the offset at the lift, the offset where the drag began and the release velocity. The only
/// difference is the page length (D27): this public behavior pages by the UNOBSCURED container length like SwiftUI's
/// `.paging`; the UIKit knob pages by the viewport length. With zero insets they coincide.
public struct ZTronPagingScrollTargetBehavior: ZTronScrollTargetBehavior, ZTronSnappingBehavior {
    enum PageLength { case container, viewport }
    let pageLength: PageLength

    public init() { pageLength = .container }
    init(pageLength: PageLength) { self.pageLength = pageLength }

    /// What `isPagingEnabled` resolves to inside the pipeline: pages one viewport long.
    static var viewportPages: ZTronPagingScrollTargetBehavior { ZTronPagingScrollTargetBehavior(pageLength: .viewport) }

    @MainActor
    public func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        let info = context.info
        let length = pageLength == .viewport && info.viewport != .zero ? info.viewport : context.containerSize
        var origin = target.rect.origin
        // `PagingSolver` works in offset space (page boundaries at `bounds.min + n · pageLength`); the rect is in SwiftUI's
        // content space, `offset + inset.start`.
        if context.axes.contains(.horizontal) {
            origin.x = PagingSolver.target(current: info.origin.x, dragStart: info.dragStart.x, velocity: info.rawVelocity.dx,
                                           pageLength: length.width, bounds: info.boundsX) + info.insets.leading
        }
        if context.axes.contains(.vertical) {
            origin.y = PagingSolver.target(current: info.origin.y, dragStart: info.dragStart.y, velocity: info.rawVelocity.dy,
                                           pageLength: length.height, bounds: info.boundsY) + info.insets.top
        }
        target.rect.origin = origin
        target.anchor = nil
    }

    @MainActor
    public func properties(context: PropertiesContext) -> Properties {
        Properties(limitsVelocity: true)
    }
}

extension ZTronScrollTargetBehavior where Self == ZTronPagingScrollTargetBehavior {
    /// Pages one container long (SwiftUI's `.paging`).
    public static var paging: ZTronPagingScrollTargetBehavior { ZTronPagingScrollTargetBehavior() }
}

extension AnyZTronScrollTargetBehavior {
    /// `isPagingEnabled` inside the pipeline: paging by the viewport length (UIKit).
    static var pagingKnob: AnyZTronScrollTargetBehavior { AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior.viewportPages) }
}
