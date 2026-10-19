import SwiftUI
import ZTronScrollPhysics

/// Mirrors `PagingScrollTargetBehavior`: pages one container long, at most one page per fling.
///
/// It is the release-pipeline form of `isPagingEnabled` (design M6 §4): both resolve to the same `PagingSolver` call per
/// enabled axis, from the offset at the lift, the offset where the drag began and the release velocity, so the end
/// positions of the knob and of `.scrollTargetBehavior(.paging)` are identical.
public struct ZTronPagingScrollTargetBehavior: ZTronScrollTargetBehavior, ZTronSnappingBehavior {
    public init() {}

    @MainActor
    public func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        let info = context.info
        var origin = target.rect.origin
        if context.axes.contains(.horizontal) {
            origin.x = PagingSolver.target(current: info.origin.x, dragStart: info.dragStart.x, velocity: info.rawVelocity.dx,
                                           pageLength: context.containerSize.width, bounds: info.boundsX)
        }
        if context.axes.contains(.vertical) {
            origin.y = PagingSolver.target(current: info.origin.y, dragStart: info.dragStart.y, velocity: info.rawVelocity.dy,
                                           pageLength: context.containerSize.height, bounds: info.boundsY)
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
