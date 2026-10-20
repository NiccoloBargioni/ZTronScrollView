import SwiftUI
import ZTronScrollPhysics

/// Mirrors `ViewAlignedScrollTargetBehavior` (design M6 §4): a release lands where one of the scroll view's registered
/// targets (`ztronScrollID`, inside a `ztronScrollTargetLayout`) aligns with the container. The candidates are computed in
/// SwiftUI's target space (D27): `c = s·lower + pad + a·s·length - a·W`, with `W` the unobscured container length and `a`
/// the alignment point (`anchor`, default the leading edge); the pipeline converts the landing back to an offset.
public struct ZTronViewAlignedScrollTargetBehavior: ZTronScrollTargetBehavior, ZTronSnappingBehavior {
    /// Mirrors `ViewAlignedScrollTargetBehavior.LimitBehavior`. `.always` is `.alwaysByOne` (pre-18 semantics).
    public struct LimitBehavior: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case automatic, alwaysByOne, alwaysByFew, never }
        let kind: Kind

        public static let automatic = LimitBehavior(kind: .automatic)
        public static let always = LimitBehavior(kind: .alwaysByOne)
        public static let alwaysByOne = LimitBehavior(kind: .alwaysByOne)
        public static let alwaysByFew = LimitBehavior(kind: .alwaysByFew)
        public static let never = LimitBehavior(kind: .never)
    }

    public var limitBehavior: LimitBehavior
    /// Which point of the items aligns with the same point of the container (`nil` = the leading edge; SwiftUI 26's `anchor:`).
    public var anchor: UnitPoint?

    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
        anchor = nil
    }

    public init(limitBehavior: LimitBehavior, anchor: UnitPoint?) {
        self.limitBehavior = limitBehavior
        self.anchor = anchor
    }

    public init(anchor: UnitPoint?) {
        limitBehavior = .automatic
        self.anchor = anchor
    }

    /// `.automatic`: a compact horizontal size class limits a fling to a few items, otherwise it does not limit (R5, Q4).
    static func resolved(_ limit: LimitBehavior, sizeClass: UserInterfaceSizeClass?) -> LimitBehavior.Kind {
        guard limit.kind == .automatic else { return limit.kind }
        return sizeClass == .compact ? .alwaysByFew : .never
    }

    @MainActor
    public func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        let info = context.info
        guard let registry = info.registry, registry.layoutEnabled, !registry.frames.isEmpty else { return }
        let kind = Self.resolved(limitBehavior, sizeClass: context.horizontalSizeClass)
        let a = target.anchor ?? anchor ?? registry.state?.alignmentAnchor ?? .topLeading
        let geometry = registry.state?.makeZoomGeometry()
        let scale = info.zoomScale
        var origin = target.rect.origin
        if context.axes.contains(.horizontal) {
            let candidates = Self.candidates(registry.alignedOffsets(
                axis: .horizontal, anchor: a.x, scale: scale, pad: geometry?.x.alignmentPadding(at: scale) ?? 0,
                container: context.containerSize.width), bounds: info.boundsX, shift: info.insets.leading)
            if let chosen = Self.choose(kind, candidates: candidates, natural: origin.x, origin: info.origin.x + info.insets.leading,
                                        dragStart: info.dragStart.x + info.insets.leading, velocity: context.velocity.dx,
                                        container: context.containerSize.width) {
                origin.x = chosen
            }
        }
        if context.axes.contains(.vertical) {
            let candidates = Self.candidates(registry.alignedOffsets(
                axis: .vertical, anchor: a.y, scale: scale, pad: geometry?.y.alignmentPadding(at: scale) ?? 0,
                container: context.containerSize.height), bounds: info.boundsY, shift: info.insets.top)
            if let chosen = Self.choose(kind, candidates: candidates, natural: origin.y, origin: info.origin.y + info.insets.top,
                                        dragStart: info.dragStart.y + info.insets.top, velocity: context.velocity.dy,
                                        container: context.containerSize.height) {
                origin.y = chosen
            }
        }
        target.rect.origin = origin
    }

    @MainActor
    public func properties(context: PropertiesContext) -> Properties {
        Properties(limitsVelocity: Self.resolved(limitBehavior, sizeClass: context.environment.horizontalSizeClass) != .never)
    }

    /// Retargets only when there is something to align with; without targets the plain decay (edge bounce included) runs.
    @MainActor
    func snaps(_ info: TargetReleaseInfo) -> Bool {
        guard let registry = info.registry else { return false }
        return registry.layoutEnabled && !registry.frames.isEmpty
    }

    // MARK: Pure selection (unit-tested)

    /// The candidate offsets (D27 space) the bounds can reach, ascending and distinct: a target the content cannot scroll
    /// far enough to align lands on the bound (as a partial last page does).
    static func candidates(_ raw: [(id: AnyHashable, offset: CGFloat)], bounds: AxisBounds, shift: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = []
        for c in raw.map({ bounds.clamped($0.offset - shift) + shift }) where c.isFinite {
            if let last = out.last, abs(last - c) < 1e-6 { continue }
            out.append(c)
        }
        return out
    }

    /// The landing candidate for one axis, or `nil` (leave the target alone). All values in the target space.
    static func choose(_ kind: LimitBehavior.Kind, candidates: [CGFloat], natural: CGFloat, origin: CGFloat, dragStart: CGFloat,
                       velocity: CGFloat, container: CGFloat) -> CGFloat? {
        guard !candidates.isEmpty else { return nil }
        let direction: CGFloat = velocity > 0 ? 1 : (velocity < 0 ? -1 : 0)
        func nearestIndex(_ x: CGFloat) -> Int {
            var best = 0
            for (i, c) in candidates.enumerated() where abs(c - x) < abs(candidates[best] - x) { best = i }
            return best
        }
        let start = nearestIndex(dragStart)
        switch kind {
        case .never, .automatic:
            return TargetSnapping.nearest(to: natural, candidates: candidates, direction: direction)
        case .alwaysByOne:
            if direction == 0 { return candidates[nearestIndex(origin)] }
            return candidates[min(max(start + Int(direction), 0), candidates.count - 1)]
        case .alwaysByFew:
            let reachable = candidates.filter { abs($0 - candidates[start]) <= container + 1e-6 }
            return TargetSnapping.nearest(to: natural, candidates: reachable, direction: direction)
        }
    }
}

extension ZTronScrollTargetBehavior where Self == ZTronViewAlignedScrollTargetBehavior {
    /// Aligns the release with the scroll view's targets (SwiftUI's `.viewAligned`).
    public static var viewAligned: ZTronViewAlignedScrollTargetBehavior { ZTronViewAlignedScrollTargetBehavior() }

    public static func viewAligned(limitBehavior: ZTronViewAlignedScrollTargetBehavior.LimitBehavior) -> ZTronViewAlignedScrollTargetBehavior {
        ZTronViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }

    public static func viewAligned(anchor: UnitPoint?) -> ZTronViewAlignedScrollTargetBehavior {
        ZTronViewAlignedScrollTargetBehavior(anchor: anchor)
    }

    public static func viewAligned(limitBehavior: ZTronViewAlignedScrollTargetBehavior.LimitBehavior,
                                   anchor: UnitPoint?) -> ZTronViewAlignedScrollTargetBehavior {
        ZTronViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior, anchor: anchor)
    }
}
