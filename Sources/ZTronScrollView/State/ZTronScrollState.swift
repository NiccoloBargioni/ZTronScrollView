import SwiftUI
import ZTronScrollPhysics

/// Single source of truth for a scroll view (SPEC S11, design §1-2). Deliberately **not** `ObservableObject` (R1):
/// observing it as a whole would wake every reader every frame. On 17+ direct reads inside any body track the one
/// property read; on 15-16 use `ZTronScrollReader` (same granularity).
@MainActor
public final class ZTronScrollState {
    let storage: any StateStorage
    let usesLayoutProtocol: Bool
    let usesNamedCoordinateSpace: Bool
    let usesGeometryChange: Bool
    let probe = PresentationBox()

    public weak var delegate: (any ZTronScrollViewDelegate)?

    // UIKit knobs (cold, not observed; the pan reads them per event).
    public var isScrollEnabled = true
    public var isPagingEnabled = false
    public var bounces = true
    public var alwaysBounceVertical = false
    public var alwaysBounceHorizontal = false
    public var isDirectionalLockEnabled = false
    public var decelerationRate: ZTronDecelerationRate = .normal
    /// Past the zoom limits a pinch rubber-bands (log space) and springs back on release (SPEC S6).
    public var bouncesZoom = true
    /// Zoom limits as set by the container (`zoomRange`); resolved against the geometry on every resize.
    var zoomLimits = ZoomLimits() { didSet { if zoomLimits != oldValue { resolveZoomLimits() } } }
    private(set) var resolvedZoom: ClosedRange<CGFloat> = 1...1
    public var minimumZoomScale: CGFloat { resolvedZoom.lowerBound }
    public var maximumZoomScale: CGFloat { resolvedZoom.upperBound }
    /// Zooming is enabled iff max > min (default 1...1, as in UIKit).
    public var isZoomEnabled: Bool { ZoomLimits.isZoomEnabled(resolvedZoom) }
    /// Velocity (pt/s) of the motion the last `interrupt()` stopped; zero if nothing was running (fling acceleration).
    private(set) var lastInterruptedVelocity = CGVector.zero

    /// Clock source for motion start times; tests inject a deterministic one. Same timebase as `step(to:)` dates.
    var now: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }

    // Non-observed motion state.
    private enum MotionKind { case animation, deceleration, zoomBounce }
    /// Programmatic zoom: `progress` runs 0 -> 1; scale = z0 + (z1 - z0)·f, and the unscaled point `u` slides from
    /// viewport point `p0` to `p1` (the visible center), so there is no jump at the start.
    private struct ZoomAnimation {
        var progress: AxisMotion
        var u: CGPoint, p0: CGPoint, p1: CGPoint
        var z0: CGFloat, z1: CGFloat
        var endOffset: CGPoint
    }
    private struct ClockMotion {
        var x: AxisMotion, y: AxisMotion
        var zoomAnimation: ZoomAnimation?
        var bounce: ZoomMotion?
        var kind: MotionKind = .animation
        /// Display scale for the pixel snap at the end of a deceleration (0 = no snap).
        var snapScale: CGFloat = 0
    }
    private var motion: ClockMotion?
    private var transactionToken: UInt64?
    private var generation: UInt64 = 0
    private var settleTicks = 0
    private var batchDepth = 0
    private var batchStart: (CGPoint, CGFloat)?
    private var pendingEndNotification = false
    private var pendingEndDecelerating = false
    private var didScrollPending = false
    private var didZoomPending = false
    private var pendingEndZoomScale: CGFloat?
    /// The zoom bounce settled; the coordinator rebases a still-running pan onto the settled offset.
    var onZoomBounceSettled: (() -> Void)?
    /// `beginZooming()` ran but no scale change was written yet (willBeginZooming is deferred to the first change).
    private var willBeginZoomingPending = false
    private var didBeginZooming = false
    private var deferScroll = false

    /// Chooses the storage once; the path never flips afterwards (R6).
    public init() {
        if ZTronAvailability.isAvailable(.perPropertyObservation), #available(iOS 17, *) {
            storage = ObservationStorage()
        } else {
            storage = ChannelStorage()
        }
        usesLayoutProtocol = ZTronAvailability.isAvailable(.layoutProtocol)
        usesNamedCoordinateSpace = ZTronAvailability.isAvailable(.namedCoordinateSpace)
        usesGeometryChange = ZTronAvailability.isAvailable(.geometryChange)
    }

    /// State used by readers created outside any scroll view.
    static let orphan = ZTronScrollState()

    // MARK: Public reads (hot: presentation values; each tracks only itself)

    public var contentOffset: CGPoint { storage.presentationOffset }
    public var zoomScale: CGFloat { storage.presentationZoom }
    public var phase: ZTronScrollPhase { storage.phase }
    public var isTracking: Bool { storage.isTracking }
    public var isDragging: Bool { storage.isDragging }
    public var isDecelerating: Bool { storage.isDecelerating }
    public var isScrollAnimating: Bool { storage.isScrollAnimating }
    public var isZoomAnimating: Bool { storage.isZoomAnimating }
    public var isZooming: Bool { storage.isZooming }
    public var isZoomBouncing: Bool { storage.isZoomBouncing }
    public var geometry: ZTronScrollGeometry { ZTronScrollGeometry(storage: storage) }

    // MARK: Internal reads

    func peekGeometry() -> ZTronScrollGeometry { ZTronScrollGeometry(storage: storage, isTracked: false) }
    var peek: StorageSnapshot { storage.snapshot() }
    var isClockRunning: Bool { storage.isClockRunning }
    var activeTransactionToken: UInt64? { transactionToken }

    /// Runs `transform` against a recording geometry and returns the channels it touched (fallback path only).
    func discoverChannels<V>(_ transform: (ZTronScrollGeometry) -> V) -> Set<StateChannel>? {
        guard let channelStorage = storage as? ChannelStorage else { return nil }
        let recorder = ChannelRecorder()
        channelStorage.recorder = recorder
        defer { channelStorage.recorder = nil }
        _ = transform(ZTronScrollGeometry(storage: storage))
        return recorder.touched
    }

    // MARK: Batches

    /// Everything that writes runs in a batch: at most one publish per channel and one `didScroll` per batch.
    /// `deferScroll`: the outermost batch only marks `didScroll` pending (finger writes, clock ticks); the caller flushes
    /// with `deliverPending()` once per frame.
    func batch(deferScroll defer_: Bool = false, _ body: () -> Void) {
        if batchDepth == 0 {
            let s = storage.snapshot()
            batchStart = (s.presentationOffset, s.presentationZoom)
            deferScroll = defer_
        }
        batchDepth += 1
        storage.beginBatch()
        body()
        storage.endBatch()
        batchDepth -= 1
        guard batchDepth == 0 else { return }
        let s = storage.snapshot()
        if let b = batchStart, b.1 != s.presentationZoom { didZoomPending = true }
        let moved = batchStart.map { $0.0 != s.presentationOffset || $0.1 != s.presentationZoom } ?? false
        batchStart = nil
        if moved { didScrollPending = true }
        if !deferScroll { deliverPending() }
    }

    /// Delegate notifications collected by batches, in UIKit order: didScroll, then the end-of-motion callbacks.
    func deliverPending() {
        if didZoomPending {
            didZoomPending = false
            #if DEBUG
            ZTronRenderCounters.increment("didZoom")
            #endif
            delegate?.scrollViewDidZoom(self)
        }
        if didScrollPending {
            didScrollPending = false
            #if DEBUG
            ZTronRenderCounters.increment("didScroll")
            #endif
            delegate?.scrollViewDidScroll(self)
        }
        if pendingEndDecelerating {
            pendingEndDecelerating = false
            delegate?.scrollViewDidEndDecelerating(self)
        }
        if pendingEndNotification {
            pendingEndNotification = false
            delegate?.scrollViewDidEndScrollingAnimation(self)
        }
        if let scale = pendingEndZoomScale {
            pendingEndZoomScale = nil
            delegate?.scrollViewDidEndZooming(self, atScale: scale)
        }
    }

    /// Finger / clock writes are unanimated (cancels an in-flight SwiftUI animation without a jump).
    func unanimated(_ body: () -> Void) {
        if ZTronAvailability.isAvailable(.keyPathTransaction), #available(iOS 17, *) {
            withTransaction(\.disablesAnimations, true, body)
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, body)
        }
    }

    // MARK: Writers (design §2)

    /// Finger (M3): target and presentation.
    func track(offset: CGPoint, zoom: CGFloat) {
        batch { unanimated { writeBoth(offset: offset, zoom: zoom) } }
    }

    private func writeBoth(offset: CGPoint, zoom: CGFloat) {
        storage.targetOffset = offset
        storage.presentationOffset = offset
        storage.targetZoom = zoom
        storage.presentationZoom = zoom
    }

    func setMetrics(_ metrics: ScrollMetrics) { batch { storage.metrics = metrics }; resolveZoomLimits() }

    /// Measured, unscaled content size (cold, `!=`-guarded by the storage).
    func setContentSize(_ size: CGSize) {
        batch { var m = storage.snapshot().metrics; m.contentSize = size; storage.metrics = m }
        resolveZoomLimits()
    }

    /// Where content sits on an axis where it is smaller than the viewport (design §5). Not observed.
    /// Centered once zooming is enabled (SPEC S6), the native top-leading default otherwise.
    var contentAlignment: UnitPoint { isZoomEnabled ? .center : .topLeading }

    /// Solver geometry for `metrics` (insets are zero until M5 reads content insets).
    func makeZoomGeometry(_ m: ScrollMetrics? = nil) -> ZoomGeometry {
        let m = m ?? storage.snapshot().metrics
        let a = contentAlignment
        return ZoomGeometry(viewportSize: m.viewportSize, unscaledContentSize: m.contentSize,
                            alignment: CGPoint(x: a.x, y: a.y))
    }

    /// Re-resolves fit/fill for the current geometry; a scale outside the new range is clamped around the visible
    /// center (unanimated; one didZoom + didScroll).
    private func resolveZoomLimits() {
        let m = storage.snapshot().metrics
        let range = zoomLimits.resolve(unscaledContentSize: m.contentSize, viewportSize: m.viewportSize,
                                       insets: (.zero, .zero))
        resolvedZoom = range
        let s = storage.snapshot()
        guard !range.contains(s.presentationZoom), m.viewportSize.width > 0, m.viewportSize.height > 0,
              !storage.isZooming else { return }
        let r = ZoomSolver.zoom(to: s.presentationZoom, anchoredAtVisibleCenterOf: s.presentationOffset,
                                currentScale: s.presentationZoom, limits: range, geometry: makeZoomGeometry(m))
        batch { unanimated { writeBoth(offset: r.offset, zoom: r.scale) } }
    }

    /// Viewport size / safe-area change (SPEC S7). Motion stops at its presentation value, then the content point at
    /// the old visible center is placed at the new one: o' = pad' + s*u - c'. Runs in the ambient (system) transaction
    /// so the transform effect animates in lockstep with the rotation. Offsets are not clamped in M2.
    func setViewport(_ viewport: ViewportMetrics) {
        let before = storage.snapshot()
        var m = before.metrics
        m.viewportSize = viewport.size
        m.contentInsets = viewport.safeArea
        guard m != before.metrics else { return }
        let hadViewport = before.metrics.viewportSize.width > 0 && before.metrics.viewportSize.height > 0
        if hadViewport, motion != nil || transactionToken != nil { interrupt() }
        batch {
            let s = storage.snapshot()
            storage.metrics = m
            guard hadViewport, viewport.size.width > 0, viewport.size.height > 0 else { return }
            let old = s.metrics, z = s.presentationZoom
            let c0 = ContentGeometry.visibleCenter(old.viewportSize)
            let c1 = ContentGeometry.visibleCenter(m.viewportSize)
            let p0 = ContentGeometry.pad(viewport: old.viewportSize, content: old.contentSize, scale: z, alignment: contentAlignment)
            let p1 = ContentGeometry.pad(viewport: m.viewportSize, content: m.contentSize, scale: z, alignment: contentAlignment)
            let u = CGPoint(x: (s.presentationOffset.x + c0.x - p0.width) / z, y: (s.presentationOffset.y + c0.y - p0.height) / z)
            let o = CGPoint(x: p1.width + z * u.x - c1.x, y: p1.height + z * u.y - c1.y)
            writeBoth(offset: o, zoom: z)
        }
        resolveZoomLimits()
    }
    func setPhase(_ phase: ZTronScrollPhase) { batch { storage.phase = phase } }

    /// Frame clock tick. No-op while nothing runs.
    func step(to date: Date) {
        guard storage.snapshot().isClockRunning else { return }
        batch(deferScroll: true) {
            unanimated {
                if let m = motion { stepClockMotion(m, at: date.timeIntervalSinceReferenceDate) }
                if transactionToken != nil { probeTick() }
                if motion == nil && transactionToken == nil && !storage.isTracking && !storage.isZooming { storage.isClockRunning = false }
            }
        }
        deliverPending()
    }

    private func stepClockMotion(_ m: ClockMotion, at t: TimeInterval) {
        let s = storage.snapshot()
        if let zb = m.bounce {
            let sample = zb.sample(at: t, geometry: makeZoomGeometry(s.metrics))
            writeBoth(offset: sample.offset, zoom: sample.scale)
            if sample.isSettled {
                motion = nil
                storage.isZoomBouncing = false
                storage.isZooming = false
                if transactionToken == nil, !storage.isTracking { storage.phase = .idle }
                if didBeginZooming { pendingEndZoomScale = sample.scale }
                didBeginZooming = false
                willBeginZoomingPending = false
                onZoomBounceSettled?()
            }
            return
        }
        let sx = m.x.sample(at: t), sy = m.y.sample(at: t)
        var offset = CGPoint(x: sx.position, y: sy.position)
        var zoom = s.presentationZoom
        var settled = sx.isSettled && sy.isSettled
        if let za = m.zoomAnimation {
            let sp = za.progress.sample(at: t)
            settled = sp.isSettled
            if settled {
                zoom = za.z1
                offset = za.endOffset
            } else {
                let f = sp.position
                zoom = za.z0 + (za.z1 - za.z0) * f
                let p = CGPoint(x: za.p0.x + (za.p1.x - za.p0.x) * f, y: za.p0.y + (za.p1.y - za.p0.y) * f)
                offset = ZoomSolver.offset(keeping: za.u, under: p, scale: zoom,
                                           geometry: makeZoomGeometry(s.metrics), clamped: true)
            }
        }
        if settled, m.kind == .deceleration, m.snapScale > 0 {
            offset = PixelSnap.snap(offset, displayScale: m.snapScale)
        }
        writeBoth(offset: offset, zoom: zoom)
        if settled {
            motion = nil
            storage.isScrollAnimating = false
            storage.isZoomAnimating = false
            if m.kind == .deceleration {
                storage.isDecelerating = false
                if transactionToken == nil, !storage.isTracking { storage.phase = .idle }
                pendingEndDecelerating = true
            } else {
                if transactionToken == nil { storage.phase = .idle }
                pendingEndNotification = true
            }
        }
    }

    /// Transaction motion: the transform effect fed `probe`; publish it as presentation (trails the drawn frame).
    private func probeTick() {
        guard let p = probe.pending else { return }
        storage.presentationOffset = p.offset
        storage.presentationZoom = p.zoom
        let s = storage.snapshot()
        settleTicks = (p.offset == s.targetOffset && p.zoom == s.targetZoom) ? settleTicks + 1 : 0
        if settleTicks >= 2, let token = transactionToken { finishTransactionMotion(token: token) }
    }

    /// Ends transaction motion unless `token` is stale (a newer `scroll(to:)` superseded it).
    func finishTransactionMotion(token: UInt64) {
        guard token == transactionToken else { return }
        batch {
            transactionToken = nil
            settleTicks = 0
            let s = storage.snapshot()
            storage.presentationOffset = s.targetOffset
            storage.presentationZoom = s.targetZoom
            if motion == nil {
                storage.isScrollAnimating = false
                storage.phase = .idle
                storage.isClockRunning = false
            }
            pendingEndNotification = true
        }
    }

    // MARK: Public commands (design §9)

    /// UIKit `setContentOffset(_:animated:)`. Not clamped to content bounds in M2. Animated: clock-driven critically
    /// damped spring (omega = 10/s), v0 = 0.
    public func setContentOffset(_ offset: CGPoint, animated: Bool) {
        guard offset.x.isFinite, offset.y.isFinite else { return }
        batch {
            cancelMotion()
            let s = storage.snapshot()
            if animated, offset != s.presentationOffset {
                let t = now()
                motion = ClockMotion(
                    x: .spring(CriticalSpring(origin: s.presentationOffset.x, target: offset.x), start: t),
                    y: .spring(CriticalSpring(origin: s.presentationOffset.y, target: offset.y), start: t),
                    )
                storage.targetOffset = offset
                startAnimating(scroll: true, zoom: false)
            } else {
                unanimated { writeBoth(offset: offset, zoom: s.presentationZoom) }
            }
        }
    }

    /// UIKit `setZoomScale(_:animated:)`: clamped to the zoom range, anchored at the visible center (insets and
    /// alignment padding included, SPEC S6). Programmatic zoom fires no `didEndZooming`; an animated one ends with
    /// `didEndScrollingAnimation`.
    public func setZoomScale(_ scale: CGFloat, animated: Bool) {
        guard scale.isFinite, scale > 0 else { return }
        batch {
            cancelMotion()
            let s = storage.snapshot()
            let g = makeZoomGeometry(s.metrics)
            let r = ZoomSolver.zoom(to: scale, anchoredAtVisibleCenterOf: s.presentationOffset,
                                    currentScale: s.presentationZoom, limits: resolvedZoom, geometry: g)
            let u = ZoomSolver.contentPoint(under: g.visibleCenter, offset: s.presentationOffset,
                                            scale: s.presentationZoom, geometry: g)
            applyZoom(r, anchor: u, animated: animated)
        }
    }

    /// UIKit `zoom(to:animated:)`: fits `rect` (unscaled content coordinates) in the visible area and centers it.
    public func zoom(to rect: CGRect, animated: Bool) {
        batch {
            cancelMotion()
            let s = storage.snapshot()
            let g = makeZoomGeometry(s.metrics)
            let r = ZoomSolver.zoom(toFit: rect, limits: resolvedZoom, geometry: g)
            let finite = rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            let mid = finite ? CGPoint(x: rect.midX, y: rect.midY)
                             : CGPoint(x: g.unscaledContentSize.width / 2, y: g.unscaledContentSize.height / 2)
            applyZoom(r, anchor: mid, animated: animated)
        }
    }

    private func applyZoom(_ r: (scale: CGFloat, offset: CGPoint), anchor u: CGPoint, animated: Bool) {
        let s = storage.snapshot()
        let g = makeZoomGeometry(s.metrics)
        guard animated, r.scale != s.presentationZoom || r.offset != s.presentationOffset else {
            unanimated { writeBoth(offset: r.offset, zoom: r.scale) }
            return
        }
        let z0 = s.presentationZoom
        let pad0 = g.alignmentPadding(at: z0)
        let p0 = CGPoint(x: pad0.x + z0 * u.x - s.presentationOffset.x, y: pad0.y + z0 * u.y - s.presentationOffset.y)
        let anim = ZoomAnimation(progress: .spring(CriticalSpring(origin: 0, target: 1), start: now()),
                                 u: u, p0: p0, p1: g.visibleCenter, z0: z0, z1: r.scale, endOffset: r.offset)
        motion = ClockMotion(x: .rest(position: s.presentationOffset.x), y: .rest(position: s.presentationOffset.y),
                             zoomAnimation: anim)
        storage.targetZoom = r.scale
        startAnimating(scroll: false, zoom: true)
    }

    /// Transaction-driven: writes only the target; animated iff called inside `withAnimation`. The transform effect
    /// interpolates and the probe feeds presentation (parts b/c wire the clock and effect).
    public func scroll(to offset: CGPoint) {
        guard offset.x.isFinite, offset.y.isFinite, offset != storage.snapshot().targetOffset else { return }
        batch {
            cancelMotion()
            generation += 1
            transactionToken = generation
            settleTicks = 0
            probe.pending = nil
            storage.targetOffset = offset
            startAnimating(scroll: true, zoom: false)
        }
    }

    /// UIKit `stopScrollingAndZooming()` / touch during motion: target := presentation, no jump.
    public func stopScrollingAndZooming() { interrupt() }

    func interrupt() {
        batch {
            let wasMoving = motion != nil || transactionToken != nil
            if let m = motion {
                let t = now()
                lastInterruptedVelocity = CGVector(dx: m.x.sample(at: t).velocity, dy: m.y.sample(at: t).velocity)
                if m.kind == .deceleration { pendingEndDecelerating = true }
                if m.bounce != nil, didBeginZooming { pendingEndZoomScale = storage.snapshot().presentationZoom }
                if m.bounce != nil { didBeginZooming = false; willBeginZoomingPending = false }
            } else {
                lastInterruptedVelocity = .zero
            }
            cancelMotion()
            let s = storage.snapshot()
            unanimated {
                storage.targetOffset = s.presentationOffset
                storage.targetZoom = s.presentationZoom
            }
            if wasMoving || s.phase == .animating { storage.phase = .idle }
            storage.isClockRunning = storage.isTracking || storage.isZooming
        }
    }

    // MARK: Gesture hooks (M3, driven by the pan coordinator)

    /// Finger down (after `interrupt()` on a catch): flags, phase `.tracking`, clock keeps flushing `didScroll`.
    /// A touch caught a moving scroll view: content stays non-hit-testable until that touch ends, so its lift cannot
    /// fire a Button. Read by `TransformHost`, which re-renders on the phase change that always accompanies it.
    var catchLocksContent = false

    func beginTracking() {
        batch {
            storage.isTracking = true
            storage.phase = .tracking
            storage.isClockRunning = true
        }
    }

    /// Recognized drag: `willBeginDragging`, phase `.interacting`.
    func beginDragging() {
        batch {
            storage.isDragging = true
            storage.phase = .interacting
        }
        delegate?.scrollViewWillBeginDragging(self)
    }

    /// Sequence over without a deceleration (tap, ignored sequence, released at rest). No delegate.
    func endTracking() {
        catchLocksContent = false
        batch {
            storage.isTracking = false
            storage.isDragging = false
            if motion == nil, transactionToken == nil, !storage.isZooming {
                if storage.phase == .tracking || storage.phase == .interacting { storage.phase = .idle }
                storage.isClockRunning = false
            }
        }
    }

    /// Finger write: target and presentation, unanimated; `didScroll` coalesced to the next `step(to:)` / flush.
    func writeDragOffset(_ p: CGPoint) {
        guard p.x.isFinite, p.y.isFinite else { return }
        batch(deferScroll: true) {
            unanimated {
                storage.targetOffset = p
                storage.presentationOffset = p
            }
        }
    }

    /// Delivers the `didScroll` a drag write left pending (before `willEndDragging`).
    func flushPendingScroll() { deliverPending() }

    /// Finger-free release motion on the clock (kind `.deceleration`): flags cleared, phase `.decelerating`,
    /// `willBeginDecelerating`. Settles with a pixel snap, `didEndDecelerating`, phase `.idle`. The target channel is
    /// left alone (it equals the presentation) so the transform host sees one write per tick, never a jump to the end.
    func beginDeceleration(x: AxisMotion, y: AxisMotion, at time: TimeInterval, displayScale: CGFloat? = nil) {
        catchLocksContent = false
        batch {
            cancelMotion()
            motion = ClockMotion(x: x, y: y, kind: .deceleration,
                                 snapScale: displayScale ?? storage.snapshot().metrics.displayScale)
            storage.isTracking = false
            storage.isDragging = false
            storage.isDecelerating = true
            storage.phase = .decelerating
            storage.isClockRunning = true
        }
        delegate?.scrollViewWillBeginDecelerating(self)
    }

    // MARK: Zoom gesture hooks (M4, driven by the pan coordinator)

    /// Pinch recognized: `isZooming`, phase `.interacting`, the clock flushes didZoom/didScroll. `willBeginZooming`
    /// waits for the first write that changes the scale.
    func beginZooming() {
        batch {
            storage.isZooming = true
            storage.phase = .interacting
            storage.isClockRunning = true
        }
        willBeginZoomingPending = true
        didBeginZooming = false
    }

    /// Finger write: unanimated; `didZoom` + `didScroll` coalesce to the next `step(to:)` (render-time transform only).
    func writePinch(scale: CGFloat, offset: CGPoint) {
        guard scale.isFinite, scale > 0, offset.x.isFinite, offset.y.isFinite else { return }
        if willBeginZoomingPending, scale != storage.snapshot().presentationZoom {
            willBeginZoomingPending = false
            didBeginZooming = true
            delegate?.scrollViewWillBeginZooming(self)
        }
        batch(deferScroll: true) { unanimated { writeBoth(offset: offset, zoom: scale) } }
    }

    /// Pinch over without a bounce: `didEndZooming(atScale:)` (when `willBeginZooming` fired), flags cleared.
    func endZooming(atScale scale: CGFloat) {
        flushPendingScroll()
        batch {
            storage.isZooming = false
            storage.isZoomBouncing = false
            if motion == nil, transactionToken == nil {
                if !storage.isTracking { storage.phase = .idle; storage.isClockRunning = false }
                else if storage.phase == .interacting { storage.phase = storage.isDragging ? .interacting : .tracking }
            }
            if didBeginZooming { pendingEndZoomScale = scale }
            didBeginZooming = false
            willBeginZoomingPending = false
        }
    }

    /// Release past a limit (or out of bounds): the zoom spring runs on the clock, phase `.decelerating`;
    /// `isZoomBouncing` while the scale differs from the end scale. Settles with `didEndZooming`.
    func beginZoomBounce(_ m: ZoomMotion, at time: TimeInterval) {
        batch {
            cancelMotion()
            motion = ClockMotion(x: .rest(position: storage.snapshot().presentationOffset.x),
                                 y: .rest(position: storage.snapshot().presentationOffset.y),
                                 bounce: m, kind: .zoomBounce)
            storage.isZooming = true
            storage.isZoomBouncing = abs(m.logScale.target - m.logScale.origin) > 1e-12
            storage.phase = .decelerating
            storage.isClockRunning = true
        }
    }

    /// A pan release that must not start a deceleration (a pinch owns the offset): `didEndDragging(false)`.
    func endDragWithoutDeceleration() {
        flushPendingScroll()
        let wasDragging = storage.isDragging
        if wasDragging { delegate?.scrollViewDidEndDragging(self, willDecelerate: false) }
        endTracking()
    }

    private func cancelMotion() {
        if motion?.bounce != nil {
            storage.isZoomBouncing = false; storage.isZooming = false
            didBeginZooming = false; willBeginZoomingPending = false
        }
        motion = nil
        transactionToken = nil
        settleTicks = 0
        probe.pending = nil
        storage.isScrollAnimating = false
        storage.isZoomAnimating = false
        storage.isDecelerating = false
        let phase = storage.snapshot().phase
        if phase == .animating || phase == .decelerating { storage.phase = .idle }
        storage.isClockRunning = false
    }

    private func startAnimating(scroll: Bool, zoom: Bool) {
        storage.phase = .animating
        storage.isScrollAnimating = scroll
        storage.isZoomAnimating = zoom
        storage.isClockRunning = true
    }
}
