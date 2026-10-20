import SwiftUI
import ZTronScrollPhysics

/// One `onZTronScrollReachEdge(_:threshold:perform:)` registration (SPEC S9 "Edges", design M8b §1.3): fires once each
/// time the offset ARRIVES within `threshold` of the edge, and re-arms only when it is more than 1 pt further away than
/// that (hysteresis), so a bounce at the edge or a pixel of jitter never fires twice, and a content append (which moves
/// the end edge away) re-arms it. The state evaluates the registered watchers when it flushes `didScroll` and on every
/// metrics change; a watcher is a class so its owner can update the closure and the threshold in place.
@MainActor
final class ReachEdgeWatcher {
    let edge: Edge
    var threshold: CGFloat
    var perform: () -> Void
    /// `true` while waiting for an arrival; `false` from the firing until the offset leaves by more than the hysteresis.
    private(set) var isArmed = true

    init(edge: Edge, threshold: CGFloat = 0, perform: @escaping () -> Void) {
        self.edge = edge
        self.threshold = max(0, threshold)
        self.perform = perform
    }

    /// Distance from the `edge` bound at `offset` / `zoom` (negative while overscrolled past it).
    static func distance(edge: Edge, offset: CGPoint, zoom: CGFloat, geometry: ZoomGeometry) -> CGFloat {
        let b = geometry.bounds(at: zoom)
        switch edge {
        case .top: return offset.y - b.y.min
        case .bottom: return b.y.max - offset.y
        case .leading: return offset.x - b.x.min
        case .trailing: return b.x.max - offset.x
        }
    }

    /// Advances the arming for the current distance; `true` when this evaluation fires.
    func update(distance d: CGFloat) -> Bool {
        if isArmed {
            guard d <= threshold else { return false }
            isArmed = false
            return true
        }
        if d > threshold + 1 { isArmed = true }
        return false
    }
}
