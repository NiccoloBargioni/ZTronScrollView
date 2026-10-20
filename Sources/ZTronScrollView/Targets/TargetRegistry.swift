import SwiftUI
import ZTronScrollPhysics

/// Identifies one frame reporter (one `ztronScrollID` view instance). Tokens are numbered in creation order: an id
/// shows the frame of its newest active reporter, and falls back to an older one when the newest goes away. SwiftUI can
/// run two copies of the same content at once for a moment (a rebuilt copy registers, then is discarded, and the one
/// that stays never reports again because its frame did not change), and can deliver a replaced view's report or its
/// `onDisappear` after the replacement registered. A token goes inactive on disappear and reports nothing until it appears again.
final class ReporterToken {
    let serial: UInt64
    var isActive = true

    private static let lock = NSLock()
    nonisolated(unsafe) private static var last: UInt64 = 0

    init() {
        Self.lock.lock()
        Self.last += 1
        serial = Self.last
        Self.lock.unlock()
    }
}

/// The scroll targets of one `ZTronScrollView` (`ztronScrollID`, design M6 §2–3): the frame of every registered id in
/// the unscaled `ztronContent` space. Owned by the state; cold and never observed by content: frames are written when
/// layout changes them and never while the view scrolls or zooms (the content space sits below the transform), so
/// `writes` stays flat during motion (R1).
@MainActor
final class TargetRegistry: ScrollTargetRegistry, Equatable {
    private(set) var frames: [AnyHashable: CGRect] = [:]
    /// The last frame each active reporter gave for an id, by reporter serial: the id shows the newest one.
    private var reports: [AnyHashable: [UInt64: CGRect]] = [:]
    /// Frames of ids that disappeared (a screen pushed over this one keeps its views alive and sends `onDisappear`):
    /// restored when the view reappears. Bounded.
    private var retired: [AnyHashable: CGRect] = [:]
    /// `ztronScrollTargetLayout(isEnabled:)` (M6 session 2): when `false` view-aligned behaviors leave the target alone.
    /// Set by ``setLayout(_:enabled:)`` (false while any layout of this scroll view is disabled); tests may set it directly.
    var layoutEnabled = true
    private var disabledLayouts: Set<UInt64> = []
    /// Bumps on every registered, moved or removed frame; pending requests retry on it.
    private(set) var version: UInt64 = 0
    /// Fixed at creation with the state (R6): which frame reporter the targets use.
    let usesGeometryChange: Bool
    weak var state: ZTronScrollState?

    #if DEBUG
    /// Effective writes (a frame that changed, an id that was removed). Flat during scripted scroll and zoom.
    var writes = 0
    #endif

    init(usesGeometryChange: Bool) {
        self.usesGeometryChange = usesGeometryChange
    }

    /// `!=`-guarded: an unchanged frame writes nothing and notifies nobody. With an `owner` (a reporter view) the id shows
    /// the frame of its newest active reporter; without one the frame is set directly.
    func register(_ id: AnyHashable, frame: CGRect, owner: ReporterToken? = nil) {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite else { return }
        guard let owner else {
            reports.removeValue(forKey: id)
            show(id, frame)
            return
        }
        guard owner.isActive else { return }
        reports[id, default: [:]][owner.serial] = frame
        if let newest = reports[id]?.keys.max(), let shown = reports[id]?[newest] { show(id, shown) }
    }

    /// With an `owner`, removes only that reporter's report: the id falls back to the next newest reporter's frame, and
    /// is removed (and retired) when none is left. A reporter that never reported changes nothing.
    func unregister(_ id: AnyHashable, owner: ReporterToken? = nil) {
        if let owner {
            guard var left = reports[id], left.removeValue(forKey: owner.serial) != nil else { return }
            if let newest = left.keys.max(), let shown = left[newest] {
                reports[id] = left
                show(id, shown)
                return
            }
        }
        reports.removeValue(forKey: id)
        guard let old = frames.removeValue(forKey: id) else { return }
        if retired.count >= 1024 { retired.removeAll() }
        retired[id] = old
        version &+= 1
        #if DEBUG
        writes += 1
        #endif
        state?.targetFrameDidChange(id)
    }

    /// The view appeared again after `unregister`: registers its last known frame (a fresh measurement, when the layout
    /// changed meanwhile, supersedes it).
    func restore(_ id: AnyHashable, owner: ReporterToken? = nil) {
        guard frames[id] == nil, let frame = retired[id] else { return }
        register(id, frame: frame, owner: owner)
    }

    private func show(_ id: AnyHashable, _ frame: CGRect) {
        guard frames[id] != frame else { return }
        frames[id] = frame
        retired.removeValue(forKey: id)
        version &+= 1
        #if DEBUG
        writes += 1
        #endif
        state?.targetFrameDidChange(id)
    }

    func frame(of id: AnyHashable) -> CGRect? { frames[id] }

    /// The id of the target that `alignedOffsets` puts nearest `offset` (a resize keeps this item aligned, M5 §6).
    func nearestAligned(axis: Axis, anchor: CGFloat, scale: CGFloat, pad: CGFloat, container: CGFloat, to offset: CGFloat) -> AnyHashable? {
        var best: (id: AnyHashable, distance: CGFloat)?
        for c in alignedOffsets(axis: axis, anchor: anchor, scale: scale, pad: pad, container: container) {
            let d = abs(c.offset - offset)
            if best == nil || d < best!.distance { best = (c.id, d) }
        }
        return best?.id
    }

    /// A `ztronScrollTargetLayout` reports whether it is enabled (`!=`-guarded; cold). The targets count only while no
    /// layout of this scroll view is disabled.
    func setLayout(_ token: ReporterToken, enabled: Bool) {
        if enabled { disabledLayouts.remove(token.serial) } else { disabledLayouts.insert(token.serial) }
        let all = disabledLayouts.isEmpty
        if layoutEnabled != all { layoutEnabled = all }
    }

    func removeLayout(_ token: ReporterToken) { setLayout(token, enabled: true) }

    /// Where each registered target aligns on `axis`, in SwiftUI's target space (D27: content coordinates, the rect
    /// origin of a container `container` long whose `anchor` point sits on the target's `anchor` point), sorted ascending.
    /// `scale` is the zoom and `pad` the alignment padding of content that fits (`x_v = s·x_c + pad - o`).
    func alignedOffsets(axis: Axis, anchor: CGFloat, scale: CGFloat, pad: CGFloat, container: CGFloat)
        -> [(id: AnyHashable, offset: CGFloat)] {
        frames.map { id, frame in
            let lower = axis == .horizontal ? frame.minX : frame.minY
            let length = axis == .horizontal ? frame.width : frame.height
            return (id, TargetScrollMath.alignedOffset(lower: lower, length: length, anchor: anchor, scale: scale, pad: pad,
                                                       container: container))
        }
        .sorted { $0.offset != $1.offset ? $0.offset < $1.offset : String(describing: $0.id) < String(describing: $1.id) }
    }

    /// The target whose frame contains `point`, else the nearest one (distance to its frame); ties go to the target
    /// nearer the content origin, so the answer never depends on dictionary order.
    func nearestTarget(to point: CGPoint) -> (id: AnyHashable, frame: CGRect)? {
        var best: (id: AnyHashable, frame: CGRect, distance: CGFloat)?
        for (id, frame) in frames {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            guard let current = best else { best = (id, frame, distance); continue }
            let nearer = distance < current.distance
            let tie = distance == current.distance
                && (frame.minY < current.frame.minY || (frame.minY == current.frame.minY && frame.minX < current.frame.minX))
            if nearer || tie { best = (id, frame, distance) }
        }
        return best.map { ($0.id, $0.frame) }
    }

    nonisolated static func == (l: TargetRegistry, r: TargetRegistry) -> Bool { l === r }
}

private struct TargetRegistryKey: EnvironmentKey {
    static var defaultValue: TargetRegistry? { nil }
}

extension EnvironmentValues {
    /// The registry of the nearest enclosing `ZTronScrollView` (set on its content).
    var ztronTargetRegistry: TargetRegistry? {
        get { self[TargetRegistryKey.self] }
        set { self[TargetRegistryKey.self] = newValue }
    }
}

/// Scroll-to math (design M6 §4), per axis in offset space: a point `x` of the content is drawn at
/// `s·x + pad − offset` in the viewport, with `s` the zoom and `pad` the alignment padding of content that fits.
/// `frame` is the registered, unscaled frame; the result is clamped to the bounds at the current scale (zoom never changes).
enum TargetScrollMath {
    /// The rect origin (D27 space) that puts the point `anchor` of a target (`lower`, `length`, unscaled) on the point
    /// `anchor` of a `container`-long rect: `s·lower + pad + a·s·length - a·container`.
    static func alignedOffset(lower: CGFloat, length: CGFloat, anchor: CGFloat, scale: CGFloat, pad: CGFloat, container: CGFloat) -> CGFloat {
        let s = scale.isFinite && scale > 0 ? scale : 1
        return s * lower + pad + anchor * s * length - anchor * container
    }

    static func offset(for frame: CGRect, anchor: UnitPoint?, current: CGPoint, scale: CGFloat, geometry g: ZoomGeometry) -> CGPoint {
        CGPoint(x: axisOffset(lower: frame.minX, length: frame.width, anchor: anchor?.x, current: current.x, scale: scale, axis: g.x),
                y: axisOffset(lower: frame.minY, length: frame.height, anchor: anchor?.y, current: current.y, scale: scale, axis: g.y))
    }

    /// - `anchor == nil`: the minimal scroll that shows the frame inside the inset-adjusted viewport (a frame longer
    ///   than the visible length aligns its start).
    /// - `anchor == a`: the point `a` of the frame lands on the point `a` of the visible area.
    static func axisOffset(lower: CGFloat, length: CGFloat, anchor: CGFloat?, current o: CGFloat, scale: CGFloat,
                           axis g: AxisGeometry) -> CGFloat {
        let s = scale.isFinite && scale > 0 ? scale : 1
        let start = s * lower + g.alignmentPadding(at: s)
        let len = s * length
        let end = start + len
        let inset = g.insets
        let visible = g.adjustedViewportLength
        let wanted: CGFloat
        if let a = anchor {
            wanted = start + a * len - inset.start - a * visible
        } else if len > visible {
            wanted = start - inset.start
        } else if start < o + inset.start {
            wanted = start - inset.start
        } else if end > o + g.viewportLength - inset.end {
            wanted = end - (g.viewportLength - inset.end)
        } else {
            wanted = o
        }
        return g.bounds(at: s).clamped(wanted)
    }
}
