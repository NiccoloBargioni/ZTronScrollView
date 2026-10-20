import SwiftUI

/// A lazy view over a scroll state's storage (SPEC S11, design §8). Each getter reads exactly one storage property
/// (tracked on 17+, records the channel on 15-16), except `visibleRect`, which reads offset, zoom and metrics.
/// A geometry made by `peekGeometry()` reads without tracking. `==` compares every value (tracked reads).
@MainActor
public struct ZTronScrollGeometry: Equatable {
    let storage: any StateStorage
    let isTracked: Bool

    init(storage: any StateStorage, isTracked: Bool = true) {
        self.storage = storage
        self.isTracked = isTracked
    }

    /// Presentation offset in scaled viewport points (UIKit `contentOffset`).
    public var contentOffset: CGPoint { isTracked ? storage.presentationOffset : storage.snapshot().presentationOffset }
    /// Presentation zoom scale.
    public var zoomScale: CGFloat { isTracked ? storage.presentationZoom : storage.snapshot().presentationZoom }
    /// Interaction phase (`ZTronScrollPhaseReader` derives from this; not part of `==`).
    public var phase: ZTronScrollPhase { isTracked ? storage.phase : storage.snapshot().phase }
    /// Content size at scale 1 (measured below the transform).
    public var contentSize: CGSize { metrics.contentSize }
    /// `adjustedContentInset`: developer inset + the safe area on the adjusted edges.
    public var contentInsets: EdgeInsets { metrics.adjustedContentInset }
    /// Viewport size.
    public var containerSize: CGSize { metrics.viewportSize }
    /// The visible region in unscaled content coordinates.
    public var visibleRect: CGRect {
        let o = contentOffset, s = max(zoomScale, .leastNonzeroMagnitude), c = containerSize
        return CGRect(x: o.x / s, y: o.y / s, width: c.width / s, height: c.height / s)
    }

    private var metrics: ScrollMetrics { isTracked ? storage.metrics : storage.snapshot().metrics }

    public nonisolated static func == (l: Self, r: Self) -> Bool {
        MainActor.assumeIsolated { l.isEqual(to: r) }
    }

    private func isEqual(to r: Self) -> Bool {
        let l = self
        return l.contentOffset == r.contentOffset && l.zoomScale == r.zoomScale && l.contentSize == r.contentSize
            && l.contentInsets == r.contentInsets && l.containerSize == r.containerSize
    }
}

// MARK: Value geometry (M7)

extension ZTronScrollGeometry {
    /// A geometry made from values (tests, bridges, the hub's frozen per-delivery copy). Every read returns what was given.
    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets = EdgeInsets(), containerSize: CGSize,
                zoomScale: CGFloat = 1) {
        var snapshot = StorageSnapshot()
        snapshot.presentationOffset = contentOffset
        snapshot.targetOffset = contentOffset
        snapshot.presentationZoom = zoomScale
        snapshot.targetZoom = zoomScale
        snapshot.metrics.contentSize = contentSize
        snapshot.metrics.adjustedContentInset = contentInsets
        snapshot.metrics.viewportSize = containerSize
        self.init(snapshot: snapshot)
    }

    /// A frozen copy of `snapshot`: later writes to the state never change it.
    init(snapshot: StorageSnapshot) {
        self.init(storage: SnapshotStorage(snapshot), isTracked: false)
    }

    /// The viewport in scaled space: `contentOffset` and `containerSize` (native `ScrollGeometry.bounds`). Under zoom it
    /// differs from `visibleRect`, which is in unscaled content space.
    public var bounds: CGRect { CGRect(origin: contentOffset, size: containerSize) }
}

/// A `StateStorage` that only holds a snapshot: the backing of a value geometry. Writes mutate its private copy.
@MainActor
final class SnapshotStorage: StateStorage {
    private var v: StorageSnapshot
    init(_ snapshot: StorageSnapshot) { v = snapshot }

    var targetOffset: CGPoint { get { v.targetOffset } set { v.targetOffset = newValue } }
    var targetZoom: CGFloat { get { v.targetZoom } set { v.targetZoom = newValue } }
    var presentationOffset: CGPoint { get { v.presentationOffset } set { v.presentationOffset = newValue } }
    var presentationZoom: CGFloat { get { v.presentationZoom } set { v.presentationZoom = newValue } }
    var metrics: ScrollMetrics { get { v.metrics } set { v.metrics = newValue } }
    var phase: ZTronScrollPhase { get { v.phase } set { v.phase = newValue } }
    var isScrollAnimating: Bool { get { v.isScrollAnimating } set { v.isScrollAnimating = newValue } }
    var isZoomAnimating: Bool { get { v.isZoomAnimating } set { v.isZoomAnimating = newValue } }
    var isClockRunning: Bool { get { v.isClockRunning } set { v.isClockRunning = newValue } }
    var isTracking: Bool { get { v.isTracking } set { v.isTracking = newValue } }
    var isDragging: Bool { get { v.isDragging } set { v.isDragging = newValue } }
    var isDecelerating: Bool { get { v.isDecelerating } set { v.isDecelerating = newValue } }
    var isZooming: Bool { get { v.isZooming } set { v.isZooming = newValue } }
    var isZoomBouncing: Bool { get { v.isZoomBouncing } set { v.isZoomBouncing = newValue } }
    func snapshot() -> StorageSnapshot { v }
    func beginBatch() {}
    func endBatch() {}
}
