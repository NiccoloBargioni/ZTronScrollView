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
    /// Developer inset on top of the safe area (UIKit `contentInset`); changes follow the inset-only rule (M5 section 6).
    public var contentInset = EdgeInsets() { didSet { if contentInset != oldValue { adjustedInputsChanged() } } }
    /// Which safe-area edges are added to the inset; `.automatic` = the scrollable axes' edges. Set before the view appears.
    public var contentInsetAdjustmentBehavior = ZTronContentInsetAdjustmentBehavior.automatic {
        didSet { if contentInsetAdjustmentBehavior != oldValue { adjustedInputsChanged() } }
    }
    /// `contentInset` + the safe area on the adjusted edges (cold: publishes on the metrics channel).
    public var adjustedContentInset: EdgeInsets { storage.metrics.adjustedContentInset }
    /// Scrollable axes (set by the container); decides the adjusted edges and the paging axes.
    var scrollAxes: Axis.Set = .vertical
    /// A developer `defaultScrollAnchor(_:for: .sizeChanges)` replaces the center rule (the only override of SPEC S7).
    var sizeChangesAnchor: UnitPoint?
    weak var targetRegistry: (any ScrollTargetRegistry)?
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
    // Resize watch (M5 section 8).
    private var isResizeOpen = false
    private var resizeSawAnimation = false
    private var resizeIdleTicks = 0
    private var resizeStableTicks = 0
    private var resizeLast: (CGPoint, CGFloat)?
    /// Sticky resize intent (D17): captured from the last user/programmatic state before the first resize and reused
    /// for every following resize until the user or code moves the view (`beginIntervention()`). Never re-derived
    /// from a clamped post-resize state, so an even number of rotations restores the offset and scale exactly.
    private(set) var resizeIntent: ResizeIntent?
    /// What was actually DRAWN before the first idle geometry mutation of the current run-loop turn (ZTronMapKit
    /// discipline, D16/D17). SwiftUI can deliver one rotation as several updates in ONE turn (the new safe area on the
    /// old size, the GeometryReader's reflowed content, then the size): a resize opening later in that turn captures
    /// its intent from this origin, not from the half-mutated metrics. Cleared by `endOfTurn()` (main-queue hop).
    private struct TurnOrigin {
        var snapshot: ResizeCommit.Snapshot
        var header: CGFloat
        var offset: CGPoint
        var zoom: CGFloat
    }
    private var turnOrigin: TurnOrigin?
    private var turnHopPending = false
    private var resizeOpenedThisTurn = false
    private var idleGeometryChangedThisTurn = false
    /// Post-resize settle window (D19), counted in run-loop turns from `closeResize()`: a content size or inset that
    /// lands a frame after the viewport (slow reflow, M5 section 9; a late safe-area settle) is still part of the
    /// resize, so it realises the sticky intent (ZTronMapKit: restore the normalized centre on every bounds change)
    /// instead of following the idle `.sizeChanges` rule, and does not drop the intent.
    private var postResizeTurns = 0
    private var settledThisTurn = false

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
        beginIntervention()
        batch { unanimated { writeBoth(offset: offset, zoom: zoom) } }
    }

    /// The user or code is about to move the view: any resize in flight commits and the sticky intent is dropped.
    private func beginIntervention() {
        resizeIntent = nil
        turnOrigin = nil                      // the new offset is the truth for the rest of this turn
        idleGeometryChangedThisTurn = false
        settledThisTurn = false
        postResizeTurns = 0
        #if DEBUG
        closeReason = "intervention"
        #endif
        if isResizeOpen { closeResize() }
    }

    // MARK: Turn origin (D16/D17: the resize intent is captured from the drawn geometry)

    /// Called BEFORE an idle geometry mutation (content size or insets while no resize is open, whether or not motion
    /// runs): remembers the drawn geometry and presentation once per turn, so a viewport size change later in the same
    /// turn captures its intent from what is on screen, and schedules the end-of-turn hop.
    private func noteIdleGeometryChange(before old: StorageSnapshot) {
        let m = old.metrics
        guard !isResizeOpen, m.viewportSize.width > 0, m.viewportSize.height > 0 else { return }
        if turnOrigin == nil, m.contentSize.width > 0, m.contentSize.height > 0 {
            turnOrigin = TurnOrigin(snapshot: m.resize.current, header: m.headerObscured,
                                    offset: old.presentationOffset, zoom: old.presentationZoom)
            #if DEBUG
            dbg("origin captured vp:\(f(m.resize.current.viewport)) content:\(f(m.resize.current.contentSize)) insets:\(f(m.resize.current.insets)) o:\(f(old.presentationOffset)) z:\(f(old.presentationZoom))")
            #endif
        }
        idleGeometryChangedThisTurn = true
        scheduleTurnHop()
    }

    /// One main-queue hop per turn: everything SwiftUI delivers synchronously in this turn runs before `endOfTurn()`.
    private func scheduleTurnHop() {
        guard !turnHopPending else { return }
        turnHopPending = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.endOfTurn() } }
    }

    /// The run-loop turn ended: the origin is gone (the next turn draws the mutated geometry). An idle geometry change
    /// that was NOT part of a resize is an app action (a list grew, bars changed): the sticky intent is stale and the
    /// next resize captures from the drawn state; the offset itself followed the `.sizeChanges` rule (kept / clamped, D16).
    func endOfTurn() {
        turnHopPending = false
        turnOrigin = nil
        if idleGeometryChangedThisTurn, !resizeOpenedThisTurn, !isResizeOpen, resizeIntent != nil,
           postResizeTurns == 0, !settledThisTurn {
            resizeIntent = nil
            #if DEBUG
            dbg("intent dropped at end of turn")
            #endif
        }
        idleGeometryChangedThisTurn = false
        resizeOpenedThisTurn = false
        settledThisTurn = false
        if postResizeTurns > 0 {
            postResizeTurns -= 1
            if postResizeTurns > 0 { scheduleTurnHop() }
        }
    }

    /// The settle window is open: a few turns after a close, with the sticky intent still valid, no resize open and
    /// nothing moving. An idle geometry change arriving now realises the intent (`settleOffset`).
    private var isInSettleWindow: Bool {
        postResizeTurns > 0 && resizeIntent != nil && !isResizeOpen
            && motion == nil && transactionToken == nil && !storage.isTracking && !storage.isZooming
    }

    /// `intent` realised in the geometry of `m` (ZTronMapKit `contentOffset(normalizedCenter:)`), clamped in the
    /// library geometry. Marks the turn as settling, so `endOfTurn()` keeps the intent.
    private func settleOffset(_ intent: ResizeIntent, in m: ScrollMetrics) -> (offset: CGPoint, scale: CGFloat) {
        settledThisTurn = true
        let r = ResizeMath.realize(intent, viewport: m.viewportSize, content: m.contentSize, insets: m.adjustedContentInset,
                                   header: m.headerObscured, focus: sizeChangesAnchor ?? .center, limits: zoomLimits,
                                   alignment: contentAlignment)
        let g = ResizeMath.geometry(viewport: m.viewportSize, content: m.contentSize, insets: m.adjustedContentInset,
                                    alignment: contentAlignment)
        return (g.clamped(r.offset, at: r.scale), r.scale)
    }

    #if DEBUG
    // DEBUG event-log instrumentation (resize ordering probe; temporary).
    private var closeReason = "?"
    private func dbg(_ s: String) { ZTronRenderCounters.event(s) }
    private func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
    private func f(_ s: CGSize) -> String { "\(f(s.width))x\(f(s.height))" }
    private func f(_ p: CGPoint) -> String { "(\(f(p.x)),\(f(p.y)))" }
    private func f(_ e: EdgeInsets) -> String { "[\(f(e.top)),\(f(e.leading)),\(f(e.bottom)),\(f(e.trailing))]" }
    #endif

    private func writeBoth(offset: CGPoint, zoom: CGFloat) {
        storage.targetOffset = offset
        storage.presentationOffset = offset
        storage.targetZoom = zoom
        storage.presentationZoom = zoom
    }

    func setMetrics(_ metrics: ScrollMetrics) {
        batch {
            var m = metrics
            m.adjustedContentInset = Self.adjusted(contentInset: m.contentInset, safe: m.safeAreaInsets,
                                                   behavior: contentInsetAdjustmentBehavior, axes: scrollAxes)
            syncCommit(&m, open: false)
            storage.metrics = m
        }
        resolveZoomLimits()
    }

    static func adjusted(contentInset: EdgeInsets, safe: EdgeInsets, behavior: ZTronContentInsetAdjustmentBehavior,
                         axes: Axis.Set) -> EdgeInsets {
        let e = behavior.edges(for: axes)
        return EdgeInsets(top: contentInset.top + (e.contains(.top) ? safe.top : 0),
                          leading: contentInset.leading + (e.contains(.leading) ? safe.leading : 0),
                          bottom: contentInset.bottom + (e.contains(.bottom) ? safe.bottom : 0),
                          trailing: contentInset.trailing + (e.contains(.trailing) ? safe.trailing : 0))
    }

    /// Keeps the committed geometry equal to the metrics unless a resize is in flight (then only `current` moves).
    private func syncCommit(_ m: inout ScrollMetrics, open: Bool) {
        let snap = ResizeCommit.Snapshot(viewport: m.viewportSize, contentSize: m.contentSize, insets: m.adjustedContentInset)
        m.resize.current = snap
        m.resize.header = m.headerObscured
        if !open { m.resize.previous = snap }
    }

    /// Measured, unscaled content size (cold, `!=`-guarded by the storage). A change with the viewport unchanged follows
    /// the `.sizeChanges` rule; during a resize it re-derives the committed target (slow reflow, M5 section 9).
    func setContentSize(_ size: CGSize) {
        let old = storage.snapshot()
        guard size != old.metrics.contentSize else { return }
        let hadContent = old.metrics.contentSize.width > 0 && old.metrics.contentSize.height > 0
        let idle = motion == nil && transactionToken == nil && !storage.isTracking && !storage.isZooming
            && old.metrics.viewportSize.width > 0
        batch {
            var m = old.metrics
            m.contentSize = size
            if isResizeOpen {
                syncCommit(&m, open: true)
                // The reflowed content size is placed by the same intent (D17): the normalized centre is relative to
                // the zoomed content, so the drawn centre follows the reflow; at fit stays at fit.
                let r = ResizeMath.resolve(size: m.resize.current.viewport, offset: old.targetOffset, scale: old.targetZoom,
                                           insetsAnimated: m.resize.current.insets, commit: m.resize, limits: zoomLimits,
                                           alignment: contentAlignment, paging: isPagingEnabled ? scrollAxes : [])
                // Commit and target in ONE unanimated write: the measurement arrives inside the system's rotation
                // transaction, and a metrics publish made there would let the offset animate behind the commit (a
                // frame drawn with the new content size and the old offset, D16).
                unanimated {
                    storage.metrics = m
                    storage.targetOffset = r.offset
                    storage.targetZoom = r.scale
                }
                #if DEBUG
                dbg("cs open \(f(old.metrics.contentSize))->\(f(size)) vp:\(f(old.metrics.viewportSize)) wroteTarget:\(r.offset != old.targetOffset || r.scale != old.targetZoom) o:\(f(r.offset)) z:\(f(r.scale))")
                #endif
                return
            }
            noteIdleGeometryChange(before: old)
            syncCommit(&m, open: false)
            storage.metrics = m
            #if DEBUG
            if !(idle && hadContent) { dbg("cs idle-skip \(f(old.metrics.contentSize))->\(f(size)) vp:\(f(old.metrics.viewportSize)) idle:\(idle) hadContent:\(hadContent) wroteOffset:false") }
            #endif
            guard idle, hadContent else { return }
            #if DEBUG
            ZTronRenderCounters.increment("resize.contentSizeIdle")   // a content-size change with no resize open
            #endif
            if size.width > 0, size.height > 0, isInSettleWindow, let intent = resizeIntent {
                // Slow reflow (M5 section 9): the content size landed a frame after the resize closed. Still the resize:
                // the sticky intent is realised in the new geometry (presentation + target, unanimated), never the
                // keep / clamp rule, and the intent survives the turn.
                let r = settleOffset(intent, in: m)
                if r.offset != old.presentationOffset || r.scale != old.presentationZoom {
                    unanimated { writeBoth(offset: r.offset, zoom: r.scale) }
                }
                #if DEBUG
                dbg("cs settle \(f(old.metrics.contentSize))->\(f(size)) vp:\(f(old.metrics.viewportSize)) turns:\(postResizeTurns) \(f(old.presentationOffset))->\(f(r.offset)) z:\(f(r.scale))")
                #endif
                return
            }
            let gOld = makeZoomGeometry(old.metrics), gNew = makeZoomGeometry(m)
            let z = old.presentationZoom
            var o = old.presentationOffset
            if let a = sizeChangesAnchor {
                let pOld = CGPoint(x: gOld.x.insets.start + (gOld.x.viewportLength - gOld.x.insets.total) * a.x,
                                   y: gOld.y.insets.start + (gOld.y.viewportLength - gOld.y.insets.total) * a.y)
                let u = ZoomSolver.contentPoint(under: pOld, offset: o, scale: z, geometry: gOld)
                o = ZoomSolver.offset(keeping: u, under: pOld, scale: z, geometry: gNew, clamped: true)
            } else {
                o = gNew.clamped(o, at: z)
            }
            if o != old.presentationOffset { unanimated { writeBoth(offset: o, zoom: z) } }
            #if DEBUG
            dbg("cs idle \(f(old.metrics.contentSize))->\(f(size)) vp:\(f(old.metrics.viewportSize)) wroteOffset:\(o != old.presentationOffset) \(f(old.presentationOffset))->\(f(o)) z:\(f(z))")
            #endif
        }
        resolveZoomLimits()
    }

    /// Where content sits on an axis where it is smaller than the viewport (design M2 section 5). Not observed.
    /// Centered once zooming is enabled (SPEC S6), the native top-leading default otherwise.
    var contentAlignment: UnitPoint { isZoomEnabled ? .center : .topLeading }

    /// Solver geometry for `metrics` (adjusted insets included).
    func makeZoomGeometry(_ m: ScrollMetrics? = nil) -> ZoomGeometry {
        let m = m ?? storage.snapshot().metrics
        return ResizeMath.geometry(viewport: m.viewportSize, content: m.contentSize, insets: m.adjustedContentInset,
                                   alignment: contentAlignment)
    }

    /// Re-resolves fit/fill for the current geometry; a scale outside the new range is clamped around the visible
    /// center (unanimated; one didZoom + didScroll). Not while a resize is in flight: the effect clamps and
    /// `closeResize()` commits.
    private func resolveZoomLimits() {
        let m = storage.snapshot().metrics
        let range = zoomLimits.resolve(unscaledContentSize: m.contentSize, viewportSize: m.viewportSize,
                                       insets: ResizeMath.axisInsets(m.adjustedContentInset))
        resolvedZoom = range
        let s = storage.snapshot()
        guard !isResizeOpen, !range.contains(s.presentationZoom), m.viewportSize.width > 0, m.viewportSize.height > 0,
              !storage.isZooming else { return }
        let r = ZoomSolver.zoom(to: s.presentationZoom, anchoredAtVisibleCenterOf: s.presentationOffset,
                                currentScale: s.presentationZoom, limits: range, geometry: makeZoomGeometry(m))
        batch { unanimated { writeBoth(offset: r.offset, zoom: r.scale) } }
    }

    // MARK: Resize (SPEC S7, design M5)

    private func notifyAdjustedInsetChange() { delegate?.scrollViewDidChangeAdjustedContentInset(self) }

    /// `contentInset` / behavior changed: recompute the adjusted inset and apply the inset-only rule.
    private func adjustedInputsChanged() {
        let m = storage.snapshot().metrics
        applyViewport(size: m.viewportSize, safe: m.safeAreaInsets, header: m.headerObscured)
    }

    /// M8b hook: the scaling header's current height shifts the preserved center only.
    func setHeaderObscured(_ h: CGFloat) {
        guard h.isFinite, h >= 0, h != storage.snapshot().metrics.headerObscured else { return }
        batch {
            var m = storage.snapshot().metrics
            m.headerObscured = h
            syncCommit(&m, open: isResizeOpen)
            storage.metrics = m
        }
    }

    /// Registry callback (M6). Since D17 the resize preserves the normalized centre of the whole content (ZTronMapKit
    /// geometry); a target's own reflow no longer re-anchors it.
    func targetFrameDidChange(_ id: AnyHashable) {}

    /// Viewport size / safe-area change (SPEC S7). Motion stops at its presentation value, then the content point at
    /// the old visible center is placed at the new one (see `ResizeMath`). The commit itself never animates: the
    /// transform effect maps the animated container size to the offset/scale in lockstep with the system transition.
    func setViewport(_ viewport: ViewportMetrics) {
        applyViewport(size: viewport.size, safe: viewport.safeArea, header: nil)
    }

    private func applyViewport(size: CGSize, safe: EdgeInsets, header: CGFloat?) {
        guard size.width.isFinite, size.height.isFinite else { return }
        let before = storage.snapshot()
        let old = before.metrics
        let hadViewport = old.viewportSize.width > 0 && old.viewportSize.height > 0
        if size.width <= 0 || size.height <= 0 {
            // Zero size: ignored once laid out; before the first layout only the insets are recorded.
            guard !hadViewport else { return }
        }
        var m = old
        m.viewportSize = size
        m.safeAreaInsets = safe
        m.adjustedContentInset = Self.adjusted(contentInset: contentInset, safe: safe,
                                               behavior: contentInsetAdjustmentBehavior, axes: scrollAxes)
        m.contentInset = contentInset
        if let header { m.headerObscured = header }
        guard m != old || m.adjustedContentInset != old.adjustedContentInset else { return }
        let sizeChanged = size != old.viewportSize
        let insetsChanged = m.adjustedContentInset != old.adjustedContentInset
        guard size.width > 0, size.height > 0 else {
            batch { storage.metrics = m }
            return
        }

        if hadViewport, !sizeChanged, isResizeOpen {
            // An inset-only change while a resize is in flight (the safe area of the new orientation settling after the
            // size change): folded into the open commit, never closing it early. The intent is realised against the
            // unobscured viewport, so the committed target is re-resolved with the new insets; `previous` is kept and
            // metrics + target are written in ONE unanimated block (as in `setContentSize`'s open branch).
            batch {
                let s = storage.snapshot()
                syncCommit(&m, open: true)
                let r = ResizeMath.resolve(size: m.resize.current.viewport, offset: s.targetOffset, scale: s.targetZoom,
                                           insetsAnimated: m.resize.current.insets, commit: m.resize, limits: zoomLimits,
                                           alignment: contentAlignment, paging: isPagingEnabled ? scrollAxes : [])
                #if DEBUG
                dbg("vp inset folded \(f(size)) insets \(f(old.adjustedContentInset))->\(f(m.adjustedContentInset)) o:\(f(r.offset)) z:\(f(r.scale))")
                #endif
                unanimated {
                    storage.metrics = m
                    storage.targetOffset = r.offset
                    storage.targetZoom = r.scale
                }
                if insetsChanged { notifyAdjustedInsetChange() }
            }
            resolveZoomLimits()
            return
        }
        if !hadViewport || !sizeChanged {
            // First layout and inset-only changes: no center rule. At the start edge stays at the start edge.
            if hadViewport { noteIdleGeometryChange(before: before) }
            batch {
                let s = storage.snapshot()
                #if DEBUG
                dbg((hadViewport ? "vp inset" : "vp first") + " \(f(old.viewportSize))->\(f(size)) insets \(f(old.adjustedContentInset))->\(f(m.adjustedContentInset)) insetsChanged:\(insetsChanged)")
                #endif
                syncCommit(&m, open: false)
                storage.metrics = m
                if insetsChanged { notifyAdjustedInsetChange() }
                guard insetsChanged else { return }
                if hadViewport, m.contentSize.width > 0, m.contentSize.height > 0, isInSettleWindow, let intent = resizeIntent {
                    // The safe area of the new orientation settled a frame after the resize closed: still the resize,
                    // the sticky intent is realised against the new insets (see `setContentSize`).
                    let r = settleOffset(intent, in: m)
                    if r.offset != s.presentationOffset || r.scale != s.presentationZoom {
                        unanimated { writeBoth(offset: r.offset, zoom: r.scale) }
                    }
                    #if DEBUG
                    dbg("vp inset settle \(f(size)) insets \(f(old.adjustedContentInset))->\(f(m.adjustedContentInset)) turns:\(postResizeTurns) \(f(s.presentationOffset))->\(f(r.offset)) z:\(f(r.scale))")
                    #endif
                    return
                }
                let gOld = makeZoomGeometry(old), gNew = makeZoomGeometry(m)
                let o = ResizeMath.insetChange(offset: s.presentationOffset, scale: s.presentationZoom, old: gOld, new: gNew,
                                               anchor: sizeChangesAnchor)
                if o != s.presentationOffset {
                    if hadViewport { writeBoth(offset: o, zoom: s.presentationZoom) } else { unanimated { writeBoth(offset: o, zoom: s.presentationZoom) } }
                }
            }
            resolveZoomLimits()
            return
        }

        // A viewport size change: the center rule.
        #if DEBUG
        ZTronRenderCounters.increment("resize.viewport")
        dbg("vp size \(f(old.viewportSize))->\(f(size)) insets \(f(old.adjustedContentInset))->\(f(m.adjustedContentInset)) content:\(f(old.contentSize)) wasOpen:\(isResizeOpen) origin:\(turnOrigin != nil) motion:\(motion != nil) tx:\(transactionToken != nil) intentReused:\(resizeIntent != nil)")
        #endif
        let interrupted = motion != nil || transactionToken != nil
        if interrupted {
            if transactionToken != nil, let p = probe.pending {
                storage.presentationOffset = p.offset
                storage.presentationZoom = p.zoom
            }
            interrupt()
        }
        batch {
            let s = storage.snapshot()
            let commitOld = old.resize
            // What the target / presentation values are expressed in, and which values capture the anchor.
            var offset = s.presentationOffset, scale = s.presentationZoom
            var cap = commitOld.current
            var header = old.headerObscured
            if isResizeOpen {
                if let p = probe.pending {
                    cap = ResizeMath.presented(commitOld, size: p.size)
                    offset = p.offset; scale = p.zoom
                } else {
                    offset = s.targetOffset; scale = s.targetZoom   // not rendered yet: the unclamped target is exact
                }
            } else if let origin = turnOrigin {
                // Same turn as an idle content / inset change (the user's tree: NavigationStack > GeometryReader >
                // scroller): what is on screen is the origin, not the half-mutated metrics (D16). The transition
                // interpolates from it too. A motion interrupted just now stopped at the current presentation (one
                // tick newer than the origin's): that is where the user sees the content, so the anchor comes from it.
                cap = origin.snapshot; header = origin.header
                if !interrupted { offset = origin.offset; scale = origin.zoom }
            }
            turnOrigin = nil
            let al = contentAlignment
            let focus = sizeChangesAnchor ?? .center
            // D17: the intent is captured once, from the state before the first resize, and reused while sticky.
            let intent = resizeIntent
                ?? ResizeMath.intent(offset: offset, scale: scale, in: cap, header: header, focus: focus, alignment: al)
            resizeIntent = intent

            var c = ResizeCommit()
            syncCommit(&m, open: false)
            c.current = m.resize.current
            c.previous = cap
            c.header = m.headerObscured
            c.focus = focus
            c.isOpen = true
            c.intent = intent
            if isPagingEnabled {
                func index(_ o: CGFloat, _ len: CGFloat) -> Int? { len > 0 ? Int((o / len).rounded()) : nil }
                if scrollAxes.contains(.horizontal) { c.pagingIndex.x = index(offset.x, cap.viewport.width) }
                if scrollAxes.contains(.vertical) { c.pagingIndex.y = index(offset.y, cap.viewport.height) }
            }
            let r = ResizeMath.resolve(size: c.current.viewport, offset: offset, scale: scale, insetsAnimated: c.current.insets,
                                       commit: c, limits: zoomLimits, alignment: al, paging: isPagingEnabled ? scrollAxes : [])
            m.resize = c
            m.resizeGeneration = old.resizeGeneration &+ 1
            probe.pending = nil
            isResizeOpen = true
            resizeSawAnimation = false
            resizeIdleTicks = 0
            resizeStableTicks = 0
            resizeLast = nil
            resizeOpenedThisTurn = true
            scheduleTurnHop()
            if insetsChanged { notifyAdjustedInsetChange() }
            unanimated {
                storage.metrics = m
                storage.targetOffset = r.offset
                storage.targetZoom = r.scale
            }
            storage.isClockRunning = true
        }
        resolveZoomLimits()
    }

    /// One clock tick of the resize watch: while the probed container size differs from the committed viewport the
    /// transition runs (`.animating`, presentation follows the probe); once it is stable for two ticks, or was never
    /// animated, the clamped target is committed.
    private func resizeTick() {
        let cur = storage.snapshot().metrics.resize.current
        guard let p = probe.pending else {
            resizeIdleTicks += 1
            #if DEBUG
            if resizeIdleTicks >= 4 { closeReason = "tick-never-rendered"; dbg("tick never-rendered -> close") }
            #endif
            if resizeIdleTicks >= 4 { closeResize() }   // never rendered
            return
        }
        // D21: the effect reports the pixel-rounded container size (288.0 for a 288.125 pt viewport); within a pixel it
        // IS the committed size, else the watch never settles (.animating forever, clamped drawing, clock running).
        let tol = ContentTransform.pixelTolerance
        let animating = abs(p.size.width - cur.viewport.width) > tol || abs(p.size.height - cur.viewport.height) > tol
        if animating {
            #if DEBUG
            if !resizeSawAnimation { dbg("tick animating-start probe:\(f(p.size)) committed:\(f(cur.viewport))") }
            #endif
            resizeSawAnimation = true
            resizeStableTicks = 0
            if storage.phase == .idle { storage.phase = .animating }
        } else if !resizeSawAnimation {
            #if DEBUG
            closeReason = "tick-never-animated"; dbg("tick never-animated probe:\(f(p.size)) -> close")
            #endif
            closeResize()
            return
        }
        storage.presentationOffset = p.offset
        storage.presentationZoom = p.zoom
        if !animating {
            if let l = resizeLast, l.0 == p.offset, l.1 == p.zoom { resizeStableTicks += 1 } else { resizeStableTicks = 0 }
            #if DEBUG
            if resizeStableTicks >= 2 { closeReason = "tick-stable"; dbg("tick stable probe:\(f(p.size)) -> close") }
            #endif
            if resizeStableTicks >= 2 { closeResize() }
        }
        resizeLast = (p.offset, p.zoom)
    }

    /// The transition is over (or superseded by a command or gesture): target := the clamped value the effect draws at
    /// the committed viewport, unanimated; the commit is closed and a paging view ends snapped.
    func closeResize() {
        guard isResizeOpen else { return }
        isResizeOpen = false
        resizeLast = nil
        batch {
            let s = storage.snapshot()
            var m = s.metrics
            let r = ResizeMath.resolve(size: m.resize.current.viewport, offset: s.targetOffset, scale: s.targetZoom,
                                       insetsAnimated: m.resize.current.insets, commit: m.resize, limits: zoomLimits,
                                       alignment: contentAlignment, paging: isPagingEnabled ? scrollAxes : [])
            syncCommit(&m, open: false)
            m.resize.isOpen = false
            m.resize.pagingIndex = .init()
            m.resize.intent = nil
            unanimated {
                storage.metrics = m
                writeBoth(offset: r.offset, zoom: r.scale)
                if storage.phase == .animating, motion == nil, transactionToken == nil { storage.phase = .idle }
            }
            #if DEBUG
            dbg("close reason:\(closeReason) vp:\(f(m.resize.current.viewport)) content:\(f(m.contentSize)) o:\(f(r.offset)) z:\(f(r.scale)) target:\(f(s.targetOffset))")
            closeReason = "?"
            #endif
            if motion == nil, transactionToken == nil, !storage.isTracking, !storage.isZooming { storage.isClockRunning = false }
        }
        // The settle window: a reflow or safe area that lands within the next few turns is still this resize.
        postResizeTurns = 3
        scheduleTurnHop()
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
                if isResizeOpen { resizeTick() }
                if motion == nil && transactionToken == nil && !isResizeOpen && !storage.isTracking && !storage.isZooming { storage.isClockRunning = false }
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
        beginIntervention()
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
