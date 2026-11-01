import SwiftUI
import ZTronScrollPhysics

/// The header's `.immediately` snap (design M8b §2.4, Q3): composed AFTER the scroll view's own target behavior in the
/// release pipeline (`endDrag`'s compose hook), before `willEndDragging`. It works on the projected rest the behavior
/// proposed (velocity-aware): a landing inside the open band `(0, band)` moves to the nearest snap position; any other
/// landing is left alone (a paging behavior whose page is longer than the band keeps its page). Offset space: the hook
/// runs where the pipeline is already back from SwiftUI's target space.
@MainActor
struct HeaderSnapBehavior {
    let header: HeaderMetrics
    let positions: [CGFloat]
    let metrics: ScrollMetrics

    /// `nil` unless the view has a header with `.immediately` snapping.
    init?(state: ZTronScrollState) {
        let m = state.peek.metrics
        guard let spec = state.headerSpec, spec.snap.mode == .immediately, let header = m.header else { return nil }
        self.header = header
        self.positions = spec.snap.positions
        self.metrics = m
    }

    /// The snapped landing for the proposed landing `y` (content offset), clamped to `bounds`; `nil` = unchanged.
    func retarget(_ y: CGFloat, bounds: AxisBounds) -> CGFloat? {
        let base = HeaderMath.base(metrics)
        guard header.vertical,
              let snapped = HeaderMath.nearestSnap(to: y + base, positions: positions, m: header) else { return nil }
        let landing = bounds.clamped(snapped - base)
        return abs(landing - y) > 1e-9 ? landing : nil
    }
}

extension ZTronScrollState {
    /// The scaling header's live geometry: hot (tracked on 17+, like `contentOffset`), `nil` without a header. Read it in
    /// leaves only (a reader, a chrome leaf), never in a body that builds content.
    public var headerGeometry: ZTronHeaderGeometry? { geometry.header }

    /// Moves the content so the header shows `target` (`.progress` / `.height` clamped to the range; collapse is limited by
    /// the content's bounds). Called before the first layout, it is applied unanimated at the first layout (replaces the
    /// reference's `initialSnapPosition`); dropped when the header is removed first. Animated on the clock (`.uikit`).
    public func snapHeader(to target: ZTronHeaderSnapTarget, animated: Bool = true) {
        let s = peek
        guard let header = s.metrics.header, s.metrics.viewportSize.height > 0, s.metrics.contentSize.height > 0 else {
            pendingHeaderSnap = target
            return
        }
        pendingHeaderSnap = nil
        var o = HeaderMath.offset(for: target, m: header)
        if o <= 0 {
            // An expanded target (`.expanded`, `.progress(0)`, `.height(R)`): at or above rest the header is already
            // expanded (the rest of a refresh hold at `o′ = −hold`), so a resting view does not move (review d16: the
            // target `o′ = 0` scrolled the content up by the hold and closed the refresh indicator's gap). From inside the
            // band (or while moving) the content goes to its top rest, the hold's gap included.
            let current = HeaderMath.headerOffset(offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics)
            if current <= 0, s.phase == .idle { return }
            o = min(o, -s.metrics.refreshHold.top)
        }
        let y = o - HeaderMath.base(s.metrics)
        let clamped = makeZoomGeometry(s.metrics).y.bounds(at: s.presentationZoom).clamped(y)
        setContentOffset(CGPoint(x: s.presentationOffset.x, y: clamped), animated: animated)
    }

    /// The visible header height at `o′` (`HeaderMath.visibleHeight`, 0 without a header): what the inset consumers count
    /// onto the unobscured top (indicators, `scrollTo`, the refresh base, the resize capture).
    func headerHeight(at oPrime: CGFloat) -> CGFloat {
        peek.metrics.header.map { HeaderMath.visibleHeight(o: oPrime, m: $0) } ?? 0
    }

    /// A `snapHeader(to:)` queued before the layout runs once the header, the viewport and the content are known.
    func applyPendingHeaderSnap() {
        guard let target = pendingHeaderSnap else { return }
        let m = peek.metrics
        guard m.header != nil, m.viewportSize.height > 0, m.contentSize.height > 0 else { return }
        snapHeader(to: target, animated: false)
    }

    /// `.afterFinishAccelerating`: user motion came to rest (a deceleration ended, or a release that did not decelerate)
    /// inside the band, away from every position: animate to the nearest one on the clock.
    func settleHeaderSnap() {
        guard let spec = headerSpec, spec.snap.mode == .afterFinishAccelerating else { return }
        let s = peek
        guard let header = s.metrics.header, header.vertical, s.phase == .idle, !s.isTracking else { return }
        let x = HeaderMath.headerOffset(offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics)
        guard let target = HeaderMath.nearestSnap(to: x, positions: spec.snap.positions, m: header),
              abs(target - x) > 0.5 else { return }
        let y = makeZoomGeometry(s.metrics).y.bounds(at: s.presentationZoom).clamped(target - HeaderMath.base(s.metrics))
        setContentOffset(CGPoint(x: s.presentationOffset.x, y: y), animated: true)
    }
}
