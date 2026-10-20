import SwiftUI

// M7 observer hub (design docs/design/M7-observation.md §1–§5): observers are closures registered on the state and run
// synchronously inside `deliverPending()`, after the delegate, in a fixed order: geometry, then visibility (content, then
// target), then the queued phase transitions. The hub does the per-frame work (a transform and a `!=`), so observation
// never touches SwiftUI's update cycle: no probe views, no tracked reads, one code path on every OS (S4).

/// Base of every registrable box. Boxes are final classes kept in `@State` by their modifier (or in the container's
/// `MemberObserverStore` for the members); the owning body re-assigns the closures on every evaluation (R7: never stale).
@MainActor
class ObserverBox {
    func add(to hub: ObserverHub) -> ObserverHub.Token { preconditionFailure("abstract") }
}

/// A box that wants the geometry after every delivery. `evaluate` returns whether the action ran.
@MainActor
class GeometryObserverBox: ObserverBox {
    override func add(to hub: ObserverHub) -> ObserverHub.Token { hub.addGeometry(self) }
    func evaluate(_ g: ZTronScrollGeometry) -> Bool { false }
    /// A (re-)registration seeds again: the next evaluation fires the initial call.
    func reset() {}
}

/// `onScrollGeometryChange(for:of:action:)`: `action(old, new)` runs when `transform(geometry)` changes (`!=`), and once
/// with `(v, v)` at the first evaluation after registration (native, as far as known: Q1).
@MainActor
final class TypedGeometryBox<T: Equatable>: GeometryObserverBox {
    var transform: (ZTronScrollGeometry) -> T
    var action: (T, T) -> Void
    private var last: T?

    init(transform: @escaping (ZTronScrollGeometry) -> T, action: @escaping (T, T) -> Void) {
        self.transform = transform
        self.action = action
    }

    override func evaluate(_ g: ZTronScrollGeometry) -> Bool {
        let new = transform(g)
        guard let old = last else {
            last = new
            action(new, new)
            return true
        }
        guard old != new else { return false }
        last = new
        action(old, new)
        return true
    }

    override func reset() { last = nil }
}

/// `onScrollPhaseChange`: runs `action(old, new, context)` for each queued transition (session 2 adds the modifiers).
@MainActor
final class PhaseObserverBox: ObserverBox {
    var action: (ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext) -> Void

    init(action: @escaping (ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext) -> Void) {
        self.action = action
    }

    override func add(to hub: ObserverHub) -> ObserverHub.Token { hub.addPhase(self) }
}

/// `onZTronScrollVisibilityChange` (content level): the view's frame in the unscaled content space (cold: the frame
/// reporter writes it on layout only) against the visible rect.
@MainActor
final class VisibilityObserverBox: ObserverBox {
    var threshold: Double
    var action: (Bool) -> Void
    private(set) var frame: CGRect?
    private(set) var last: Bool?
    var token: ObserverHub.Token?
    weak var hub: ObserverHub?

    init(threshold: Double = 0.5, action: @escaping (Bool) -> Void = { _ in }) {
        self.threshold = threshold
        self.action = action
    }

    override func add(to hub: ObserverHub) -> ObserverHub.Token { hub.addVisibility(self) }

    /// A layout change of the view: recompute once (never per frame).
    func setFrame(_ new: CGRect) {
        guard new != frame else { return }
        frame = new
        hub?.requestDelivery?()
    }

    func reset() { last = nil }

    func evaluate(_ g: ZTronScrollGeometry) -> Bool {
        guard let frame else { return false }
        let visible = VisibilityMath.isVisible(frame: frame, in: g.visibleRect, threshold: threshold)
        guard visible != last else { return false }
        last = visible
        action(visible)
        return true
    }
}

/// `onScrollTargetVisibilityChange`: the ids of the registered targets whose visible fraction reaches the threshold,
/// in layout order (session 2 adds the modifiers; the hub side is here so M8-8 finds one mechanism).
@MainActor
class TargetVisibilityObserverBox: ObserverBox {
    var threshold: Double
    private var lastKey: (rect: CGRect, version: UInt64)?
    private var lastIDs: [AnyHashable]?

    init(threshold: Double = 0.5) { self.threshold = threshold }

    override func add(to hub: ObserverHub) -> ObserverHub.Token { hub.addTargetVisibility(self) }

    /// Called with the visible ids (all registered types); subclasses filter and call their typed action.
    func fire(_ ids: [AnyHashable]) {}
    func reset() { lastKey = nil; lastIDs = nil }

    func evaluate(_ g: ZTronScrollGeometry, registry: TargetRegistry, axes: Axis.Set) -> Bool {
        let visibleRect = g.visibleRect
        if let key = lastKey, key.rect == visibleRect, key.version == registry.version { return false }
        lastKey = (visibleRect, registry.version)
        let horizontal = axes == .horizontal
        let visible = registry.frames.filter {
            VisibilityMath.isVisible(frame: $0.value, in: visibleRect, threshold: threshold)
        }
        .sorted { l, r in
            let lm = horizontal ? (l.value.minX, l.value.minY) : (l.value.minY, l.value.minX)
            let rm = horizontal ? (r.value.minX, r.value.minY) : (r.value.minY, r.value.minX)
            if lm.0 != rm.0 { return lm.0 < rm.0 }
            if lm.1 != rm.1 { return lm.1 < rm.1 }
            return String(describing: l.key) < String(describing: r.key)
        }
        .map(\.key)
        guard visible != lastIDs else { return false }
        lastIDs = visible
        fire(visible)
        return true
    }
}

/// Visible fraction (design §4): `f = area(F ∩ V) / area(F)` in unscaled content space; empty `F` → 0.
/// `visible = threshold <= 0 ? f > 0 : f >= min(threshold, 1)`. No hysteresis (native has none).
enum VisibilityMath {
    static func fraction(frame f: CGRect, in visible: CGRect) -> CGFloat {
        let area = f.width * f.height
        guard area > 0, f.width.isFinite, f.height.isFinite else { return 0 }
        let i = f.intersection(visible)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        return (i.width * i.height) / area
    }

    static func isVisible(frame: CGRect, in visible: CGRect, threshold: Double) -> Bool {
        let f = Double(fraction(frame: frame, in: visible))
        return threshold <= 0 ? f > 0 : f >= min(threshold, 1)
    }
}

@MainActor
final class ObserverHub {
    struct Token: Hashable { let id: UInt64 }

    private var nextID: UInt64 = 0
    private var geometry: [(token: Token, box: GeometryObserverBox)] = []
    private var phase: [(token: Token, box: PhaseObserverBox)] = []
    private var visibility: [(token: Token, box: VisibilityObserverBox)] = []
    private var targets: [(token: Token, box: TargetVisibilityObserverBox)] = []
    /// Boxes registered through the container (identity-diffed by `sync`); the content-level modifiers register on their own.
    private var synced: [ObjectIdentifier: Token] = [:]
    private var pendingPhases: [(old: ZTronScrollPhase, new: ZTronScrollPhase, velocity: CGVector?)] = []
    private var isDelivering = false
    private var redeliver = false
    /// Set by the state: a box asked for an evaluation outside a delivery (a frame changed, a box was added).
    var requestDelivery: (() -> Void)?

    #if DEBUG
    /// Deliveries that ran at least one box, and actions fired by kind ("geometry", "visibility", "target", "phase").
    private(set) var deliveries = 0
    private(set) var fires: [String: Int] = [:]
    private func count(_ kind: String) { fires[kind, default: 0] += 1 }
    #endif

    var isEmpty: Bool { geometry.isEmpty && phase.isEmpty && visibility.isEmpty && targets.isEmpty }
    var hasPhaseObservers: Bool { !phase.isEmpty }

    private func newToken() -> Token {
        nextID += 1
        return Token(id: nextID)
    }

    // MARK: Registration

    func addGeometry(_ box: GeometryObserverBox) -> Token {
        let t = newToken()
        box.reset()
        geometry.append((t, box))
        return t
    }

    func addPhase(_ box: PhaseObserverBox) -> Token {
        let t = newToken()
        phase.append((t, box))
        return t
    }

    func addVisibility(_ box: VisibilityObserverBox) -> Token {
        let t = newToken()
        box.reset()
        box.hub = self
        box.token = t
        visibility.append((t, box))
        return t
    }

    func addTargetVisibility(_ box: TargetVisibilityObserverBox) -> Token {
        let t = newToken()
        box.reset()
        targets.append((t, box))
        return t
    }

    func remove(_ token: Token) {
        geometry.removeAll { $0.token == token }
        phase.removeAll { $0.token == token }
        visibility.removeAll { $0.token == token }
        targets.removeAll { $0.token == token }
        if phase.isEmpty { pendingPhases.removeAll() }
    }

    /// Registers the boxes the container carries (environment twins, then members), removing the ones that left.
    /// Identity-diffed: a box that stays keeps its seed. New boxes are evaluated at once (their initial call).
    func sync(_ boxes: [ObserverBox]) {
        let wanted = Set(boxes.map(ObjectIdentifier.init))
        for (id, token) in synced where !wanted.contains(id) {
            remove(token)
            synced.removeValue(forKey: id)
        }
        var added = false
        for box in boxes where synced[ObjectIdentifier(box)] == nil {
            synced[ObjectIdentifier(box)] = box.add(to: self)
            added = true
        }
        if added { requestDelivery?() }
    }

    // MARK: Delivery

    /// Called from `deliverPending` after the delegate calls (and from `requestDelivery`): every box evaluates a frozen
    /// geometry and fires on a change. A write made by an action defers one more pass (bounded) instead of nesting.
    func deliver(_ state: ZTronScrollState) {
        guard !geometry.isEmpty || !visibility.isEmpty || !targets.isEmpty else { return }
        if isDelivering { redeliver = true; return }
        isDelivering = true
        defer { isDelivering = false }
        var passes = 0
        repeat {
            redeliver = false
            passes += 1
            runPass(state)
        } while redeliver && passes < 4
    }

    private func runPass(_ state: ZTronScrollState) {
        let g = ZTronScrollGeometry(snapshot: state.peek)
        #if DEBUG
        deliveries += 1
        #endif
        // Native reports the initial (v, v) at registration, before the first layout, and the settled value as a change
        // (measured on 27.0: `0 -> 0`, then `0 -> -62`); geometry observers do the same. The frame-based ones wait for a size.
        for entry in geometry {
            if entry.box.evaluate(g) {
                #if DEBUG
                count("geometry")
                #endif
            }
        }
        if g.containerSize.width > 0, g.containerSize.height > 0 {
            for entry in visibility {
                if entry.box.evaluate(g) {
                    #if DEBUG
                    count("visibility")
                    #endif
                }
            }
            for entry in targets {
                if entry.box.evaluate(g, registry: state.targets, axes: state.scrollAxes) {
                    #if DEBUG
                    count("target")
                    #endif
                }
            }
        }
    }

    func enqueuePhase(old: ZTronScrollPhase, new: ZTronScrollPhase, velocity: CGVector?) {
        guard old != new, !phase.isEmpty else { return }
        pendingPhases.append((old, new, velocity))
    }

    /// Runs the queued transitions last in a delivery, so a phase observer sees the matching delegate call before it.
    func flushPhase(_ state: ZTronScrollState) {
        guard !pendingPhases.isEmpty else { return }
        let queued = pendingPhases
        pendingPhases.removeAll()
        let g = ZTronScrollGeometry(snapshot: state.peek)
        for transition in queued {
            let context = ZTronScrollPhaseChangeContext(geometry: g, velocity: transition.velocity)
            for entry in phase {
                #if DEBUG
                count("phase")
                #endif
                entry.box.action(transition.old, transition.new, context)
            }
        }
    }
}
