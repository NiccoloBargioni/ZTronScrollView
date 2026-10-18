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
    /// Content size at scale 1 (measured below the transform).
    public var contentSize: CGSize { metrics.contentSize }
    public var contentInsets: EdgeInsets { metrics.contentInsets }
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
