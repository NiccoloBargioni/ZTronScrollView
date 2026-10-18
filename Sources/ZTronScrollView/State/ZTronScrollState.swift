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

    /// Clock source for motion start times; tests inject a deterministic one. Same timebase as `step(to:)` dates.
    var now: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }

    // Non-observed motion state.
    private struct ClockMotion {
        var x: AxisMotion, y: AxisMotion, zoom: AxisMotion?
        /// Content-space point kept at the viewport center while zooming.
        var zoomCenter: CGPoint
    }
    private var motion: ClockMotion?
    private var transactionToken: UInt64?
    private var generation: UInt64 = 0
    private var settleTicks = 0
    private var batchDepth = 0
    private var batchStart: (CGPoint, CGFloat)?
    private var pendingEndNotification = false

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
    public var isScrollAnimating: Bool { storage.isScrollAnimating }
    public var isZoomAnimating: Bool { storage.isZoomAnimating }
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
    func batch(_ body: () -> Void) {
        if batchDepth == 0 {
            let s = storage.snapshot()
            batchStart = (s.presentationOffset, s.presentationZoom)
        }
        batchDepth += 1
        storage.beginBatch()
        body()
        storage.endBatch()
        batchDepth -= 1
        guard batchDepth == 0 else { return }
        let s = storage.snapshot()
        let moved = batchStart.map { $0.0 != s.presentationOffset || $0.1 != s.presentationZoom } ?? false
        batchStart = nil
        if moved {
            #if DEBUG
            ZTronRenderCounters.increment("didScroll")
            #endif
            delegate?.scrollViewDidScroll(self)
        }
        if pendingEndNotification {
            pendingEndNotification = false
            delegate?.scrollViewDidEndScrollingAnimation(self)
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

    func setMetrics(_ metrics: ScrollMetrics) { batch { storage.metrics = metrics } }

    /// Measured, unscaled content size (cold, `!=`-guarded by the storage).
    func setContentSize(_ size: CGSize) {
        batch { var m = storage.snapshot().metrics; m.contentSize = size; storage.metrics = m }
    }

    /// Where content sits on an axis where it is smaller than the viewport (design §5). Not observed.
    var contentAlignment: UnitPoint = .topLeading

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
    }
    func setPhase(_ phase: ZTronScrollPhase) { batch { storage.phase = phase } }

    /// Frame clock tick. No-op while nothing runs.
    func step(to date: Date) {
        guard storage.snapshot().isClockRunning else { return }
        batch {
            unanimated {
                if let m = motion { stepClockMotion(m, at: date.timeIntervalSinceReferenceDate) }
                if transactionToken != nil { probeTick() }
                if motion == nil && transactionToken == nil { storage.isClockRunning = false }
            }
        }
    }

    private func stepClockMotion(_ m: ClockMotion, at t: TimeInterval) {
        let s = storage.snapshot()
        let sx = m.x.sample(at: t), sy = m.y.sample(at: t)
        var offset = CGPoint(x: sx.position, y: sy.position)
        var zoom = s.presentationZoom
        var settled = sx.isSettled && sy.isSettled
        if let zm = m.zoom {
            let sz = zm.sample(at: t)
            zoom = sz.position
            let v = s.metrics.viewportSize
            offset = CGPoint(x: m.zoomCenter.x * zoom - v.width / 2, y: m.zoomCenter.y * zoom - v.height / 2)
            settled = sz.isSettled
        }
        writeBoth(offset: offset, zoom: zoom)
        if settled {
            motion = nil
            storage.isScrollAnimating = false
            storage.isZoomAnimating = false
            if transactionToken == nil { storage.phase = .idle }
            pendingEndNotification = true
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
                    zoom: nil, zoomCenter: .zero)
                storage.targetOffset = offset
                startAnimating(scroll: true, zoom: false)
            } else {
                unanimated { writeBoth(offset: offset, zoom: s.presentationZoom) }
            }
        }
    }

    /// UIKit `setZoomScale(_:animated:)`; keeps the visible center fixed (SPEC S7). Not clamped in M2.
    public func setZoomScale(_ scale: CGFloat, animated: Bool) {
        guard scale.isFinite, scale > 0 else { return }
        batch {
            cancelMotion()
            let s = storage.snapshot()
            let v = s.metrics.viewportSize, z0 = s.presentationZoom
            let center = CGPoint(x: (s.presentationOffset.x + v.width / 2) / z0,
                                 y: (s.presentationOffset.y + v.height / 2) / z0)
            if animated, scale != z0 {
                motion = ClockMotion(x: .rest(position: s.presentationOffset.x), y: .rest(position: s.presentationOffset.y),
                                     zoom: .spring(CriticalSpring(origin: z0, target: scale), start: now()),
                                     zoomCenter: center)
                storage.targetZoom = scale
                startAnimating(scroll: false, zoom: true)
            } else {
                let offset = CGPoint(x: center.x * scale - v.width / 2, y: center.y * scale - v.height / 2)
                unanimated { writeBoth(offset: offset, zoom: scale) }
            }
        }
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
            cancelMotion()
            let s = storage.snapshot()
            unanimated {
                storage.targetOffset = s.presentationOffset
                storage.targetZoom = s.presentationZoom
            }
            if wasMoving || s.phase == .animating { storage.phase = .idle }
            storage.isClockRunning = false
        }
    }

    private func cancelMotion() {
        motion = nil
        transactionToken = nil
        settleTicks = 0
        probe.pending = nil
        storage.isScrollAnimating = false
        storage.isZoomAnimating = false
        if storage.snapshot().phase == .animating { storage.phase = .idle }
        storage.isClockRunning = false
    }

    private func startAnimating(scroll: Bool, zoom: Bool) {
        storage.phase = .animating
        storage.isScrollAnimating = scroll
        storage.isZoomAnimating = zoom
        storage.isClockRunning = true
    }
}
