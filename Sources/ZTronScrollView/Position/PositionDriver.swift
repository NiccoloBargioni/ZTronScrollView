import SwiftUI
import ZTronScrollPhysics

/// How a `scrollPosition` modifier reaches the client's value: a read (the container's body reads it, so a change
/// re-evaluates the container only) and a write-back that answers whether it wrote.
struct PositionBinding {
    var read: () -> ZTronScrollPosition
    var write: (ZTronScrollPosition) -> Bool
    var anchor: UnitPoint?

    /// `scrollPosition(_:anchor:)`.
    init(_ binding: Binding<ZTronScrollPosition>, anchor: UnitPoint?) {
        read = { binding.wrappedValue }
        write = { binding.wrappedValue = $0; return true }
        self.anchor = anchor
    }

    /// `scrollPosition(id:anchor:)`: the id binding carries no serial (0) and a write that would not change it is skipped.
    init<ID: Hashable>(id binding: Binding<ID?>, anchor: UnitPoint?) {
        read = {
            guard let id = binding.wrappedValue else { return ZTronScrollPosition() }
            return ZTronScrollPosition(request: .id(AnyHashable(id), nil), serial: 0, isPositionedByUser: false)
        }
        write = { position in
            let new = position.viewID(type: ID.self)
            if let new, let old = binding.wrappedValue, old == new { return false }
            if new == nil, binding.wrappedValue == nil { return false }
            binding.wrappedValue = new
            return true
        }
        self.anchor = anchor
    }
}

/// Keeps a client's position binding and the scroll view in step (design M6 §4). Cold: it is only called from the
/// container's body-time reads, the release hook, the clock's settle and layout changes, never per frame.
///
/// - A changed value is applied once: `lastApplied` / `lastWritten` hold `(request, serial)` of the last request taken and
///   the last value written back, so a write-back is never applied again and a new `scrollTo` (new serial) always is.
/// - Write-back happens at the release target decided and when the user's motion settles (≤ 2 per gesture, the second
///   only when it differs), and never after a programmatic scroll (`interventionBegan` clears the user-motion flag).
/// - A request that cannot be applied yet (no layout, id not registered, lazy content) is held as `pending` and retried
///   on every layout change; a touch or any other scroll command drops it.
@MainActor
final class PositionDriver {
    struct Key: Equatable {
        var request: ZTronScrollPosition.Request?
        var serial: UInt64
    }

    weak var state: ZTronScrollState?
    private(set) var binding: PositionBinding?
    private(set) var lastApplied: Key?
    private(set) var lastWritten: Key?
    private var seenSerial: UInt64 = 0
    private var pending: ZTronScrollPosition.Request?
    private var userMotion = false
    /// The animation of the transaction the change arrived in (`withAnimation { position = … }`), live for one run-loop turn.
    private var transactionAnimation: Animation?
    private var didApplyInitialOffset = false

    /// Write-backs and applied requests (tests and the demo read them; the render counters carry the same numbers in DEBUG).
    private(set) var writes = 0
    private(set) var applied = 0

    var hasPending: Bool { pending != nil }

    func bind(_ binding: PositionBinding?) {
        self.binding = binding
        if binding == nil { pending = nil; userMotion = false }
    }

    private var ticketValue: Double = 0
    private var ticketFor: ZTronScrollPosition?

    /// A number that changes whenever the bound value does (read in the container's body, cold).
    func ticket(for position: ZTronScrollPosition?) -> Double {
        if position != ticketFor {
            ticketFor = position
            ticketValue += 1
        }
        return ticketValue
    }

    /// The transaction a container update runs in (the `.transaction` hook calls this, and only runs when something below it
    /// animates, which is what ``PositionTicket`` is for): remembers its animation for the request that arrives in the same turn.
    func noteTransaction(_ transaction: Transaction) {
        guard let animation = transaction.animation, !transaction.disablesAnimations else { return }
        transactionAnimation = animation
        DispatchQueue.main.async { [weak self] in self?.transactionAnimation = nil }
    }

    // MARK: Client → scroll view

    /// The binding's value changed (or appeared): scrolls to what it asks for unless it is the value written back or already taken.
    func receive(_ position: ZTronScrollPosition?) {
        guard let position else { return }
        seenSerial = position.serial
        guard let request = position.request else {
            lastWritten = nil
            lastApplied = nil
            return
        }
        let key = Key(request: request, serial: position.serial)
        if key == lastWritten { return }                    // our own write-back read again
        lastWritten = nil                                    // the binding no longer holds what we wrote
        guard key != lastApplied else { return }
        lastApplied = key
        apply(request)
    }

    private func apply(_ request: ZTronScrollPosition.Request) {
        pending = nil
        userMotion = false
        let animation = transactionAnimation
        transactionAnimation = nil
        if !perform(request, animation: animation) { pending = request }
    }

    /// `false` when it cannot be done yet.
    private func perform(_ request: ZTronScrollPosition.Request, animation: Animation?) -> Bool {
        guard let state else { return true }
        let snapshot = state.peek
        guard snapshot.metrics.viewportSize.width > 0, snapshot.metrics.viewportSize.height > 0,
              snapshot.metrics.contentSize.width > 0, snapshot.metrics.contentSize.height > 0 else { return false }
        let mode: ZTronScrollAnimation? = animation.map { .swiftUI($0) }
        if case let .id(id, anchor) = request {
            guard state.targets.frame(of: id) != nil else { return false }
            noteApplied()
            state.scrollTo(id: id, anchor: anchor ?? binding?.anchor, animation: mode, ambient: false)
            return true
        }
        noteApplied()
        let g = state.makeZoomGeometry(snapshot.metrics)
        let z = snapshot.presentationZoom, o = snapshot.presentationOffset
        let bx = g.x.bounds(at: z), by = g.y.bounds(at: z)
        var target = o
        switch request {
        case .id: break
        case let .point(p), let .xy(p): target = g.clamped(p, at: z)
        case let .x(v): target.x = bx.clamped(v)
        case let .y(v): target.y = by.clamped(v)
        case let .edge(e):
            switch e {
            case .top: target.y = by.min
            case .bottom: target.y = by.max
            case .leading: target.x = bx.min
            case .trailing: target.x = bx.max
            }
        }
        if let animation {
            withAnimation(animation) { state.scroll(to: target) }
        } else {
            state.setContentOffset(target, animated: false)
        }
        return true
    }

    private func noteApplied() {
        applied += 1
        #if DEBUG
        ZTronRenderCounters.increment("position.applied")
        #endif
    }

    // MARK: Layout

    /// A content size, viewport or target frame changed: the one-time initial offset, then a held request.
    func layoutChanged() {
        guard let state else { return }
        applyInitialOffsetIfNeeded(state)
        guard let request = pending else { return }
        pending = nil
        if !perform(request, animation: nil) { pending = request }
    }

    /// `defaultScrollAnchor(_:for: .initialOffset)`: once, at the first layout with content and a viewport.
    private func applyInitialOffsetIfNeeded(_ state: ZTronScrollState) {
        guard !didApplyInitialOffset else { return }
        let m = state.peek.metrics
        guard m.viewportSize.width > 0, m.viewportSize.height > 0, m.contentSize.width > 0, m.contentSize.height > 0 else { return }
        didApplyInitialOffset = true
        guard let a = state.initialOffsetAnchor else { return }
        let g = state.makeZoomGeometry(m), z = state.peek.presentationZoom
        let bx = g.x.bounds(at: z), by = g.y.bounds(at: z)
        var o = state.peek.presentationOffset
        if state.scrollAxes.contains(.horizontal) { o.x = bx.min + a.x * (bx.max - bx.min) }
        if state.scrollAxes.contains(.vertical) { o.y = by.min + a.y * (by.max - by.min) }
        if o != state.peek.presentationOffset { state.setContentOffset(o, animated: false) }
    }

    /// Any scroll command or touch ran: a held request is superseded, and what moves next is not the user's.
    func interventionBegan() {
        pending = nil
        userMotion = false
    }

    // MARK: Scroll view → client

    /// A release decided where its motion lands (`landing`): write that position now.
    func releaseDecided(_ landing: CGPoint) {
        guard binding != nil, let state else { return }
        userMotion = state.isClockRunning
        report(at: landing)
    }

    /// The clock stopped with nothing running: the user's motion settled where it is.
    func settled() {
        guard userMotion, let state else { return }
        userMotion = false
        report(at: state.peek.presentationOffset)
    }

    private func report(at offset: CGPoint) {
        guard let binding, let state else { return }
        let request = describe(offset: offset, in: state)
        let key = Key(request: request, serial: seenSerial)
        guard key != lastWritten else { return }
        let value = ZTronScrollPosition(request: request, serial: seenSerial, isPositionedByUser: true)
        lastWritten = key
        lastApplied = nil                                    // asking for the earlier request again is a new request
        if binding.write(value) {
            writes += 1
            #if DEBUG
            ZTronRenderCounters.increment("position.writes")
            #endif
        }
    }

    /// The `ztronScrollID` view whose frame holds the point of the viewport named by the anchor, else the offset.
    private func describe(offset: CGPoint, in state: ZTronScrollState) -> ZTronScrollPosition.Request {
        let m = state.peek.metrics
        let g = state.makeZoomGeometry(m), z = state.peek.presentationZoom
        let a = binding?.anchor ?? .topLeading
        let viewportPoint = CGPoint(x: g.x.insets.start + g.x.adjustedViewportLength * a.x,
                                    y: g.y.insets.start + g.y.adjustedViewportLength * a.y)
        var u = ZoomSolver.contentPoint(under: viewportPoint, offset: offset, scale: z, geometry: g)
        // A point on the boundary of two frames belongs to the one the anchor looks into.
        let nudge: CGFloat = 0.25
        u.x += (0.5 - a.x) * 2 * nudge
        u.y += (0.5 - a.y) * 2 * nudge
        if let id = state.targets.target(containing: u) { return .id(id, nil) }
        return .point(offset)
    }
}

extension TargetRegistry {
    /// The smallest registered frame that contains `point` (half-open, like `CGRect.contains`); `nil` when none does.
    func target(containing point: CGPoint) -> AnyHashable? {
        var best: (id: AnyHashable, area: CGFloat, origin: CGPoint)?
        for (id, frame) in frames where frame.contains(point) {
            let area = frame.width * frame.height
            if let b = best {
                let smaller = area < b.area
                let tie = area == b.area && (frame.minY < b.origin.y || (frame.minY == b.origin.y && frame.minX < b.origin.x))
                if !(smaller || tie) { continue }
            }
            best = (id, area, frame.origin)
        }
        return best?.id
    }
}

/// An animatable that changes with every new position request, so that an update made inside `withAnimation` evaluates the
/// transaction at the container (`.transaction` runs only for animating descendants) and the driver can take the animation.
/// It draws nothing; its `body` runs a few times during the animation, which is nothing next to a scroll. Apply it through
/// ``PositionTicketLeaf``, never to the container or to anything that holds the content.
struct PositionTicket: GeometryEffect {
    var ticket: Double
    var animatableData: Double {
        get { ticket }
        set { ticket = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform() }
}

/// ``PositionTicket`` on a clear leaf in the container's background. As a wrapper of the container, even with a ticket that
/// never changed, it made SwiftUI on iOS 17.5 interpolate the layout under it in the keyboard's transaction: the first frame
/// paired the new keyboard inset with the old frame (the viewport observer read 360 pt + a 230 pt inset), the resize watch
/// reported `.animating`, `TransformHost` blocked its content (`allowsHitTesting(false)`), UIKit disabled user interaction on
/// the focused `TextField` and it resigned (`PanUITests.testControlsUsable`, M6 s3). The leaf sees the same transaction and
/// moves nothing but itself.
struct PositionTicketLeaf: View {
    let ticket: Double
    var body: some View { Color.clear.modifier(PositionTicket(ticket: ticket)).allowsHitTesting(false) }
}
