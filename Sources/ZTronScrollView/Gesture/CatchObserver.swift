import SwiftUI

/// Raw-touch observer (design M3-pan §8): touch-down "catch" and last-finger-up. SpatialEventGesture on 18+,
/// `DragGesture(minimumDistance: 0)` otherwise. Emits `PanEvent`s through `send`; holds no logic.
final class CatchObserverState: @unchecked Sendable {   // touched on the main thread only
    var activeCount = 0
    var down = false
    /// Mean of the active touches (18+), local coordinates.
    var centroid: CGPoint?
    /// Start location of the live pan (15-17 centroid base, double-tap fallback).
    var panStart: CGPoint?
}

enum CatchObserver {
    /// Whether the 18+ observer is used (S3 capability fallback: forced fallbacks use the drag).
    static var usesSpatial: Bool {
        if #available(iOS 18, *) { return ZTronAvailability.isAvailable(.spatialEvents) }
        return false
    }
}

enum DragCatchGesture {
    @MainActor
    static func gesture(observer: CatchObserverState, send: @escaping @MainActor (PanEvent) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                MainActor.assumeIsolated {
                    guard !observer.down else { return }
                    observer.down = true
                    send(.touchDown(location: value.startLocation, time: value.time.timeIntervalSinceReferenceDate,
                                    touchCount: 1))
                }
            }
            .onEnded { value in
                MainActor.assumeIsolated {
                    observer.down = false
                    send(.touchesEnded(time: value.time.timeIntervalSinceReferenceDate))
                }
            }
    }
}

@available(iOS 18, *)
enum SpatialCatchGesture {
    @MainActor
    static func gesture(observer: CatchObserverState, send: @escaping @MainActor (PanEvent) -> Void,
                        pinch: @escaping @MainActor (PinchEvent) -> Void = { _ in },
                        synthesize: @escaping @MainActor (CGPoint, TimeInterval) -> Void = { _, _ in },
                        now: @escaping @Sendable () -> TimeInterval) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                let active = events.filter { $0.phase == .active }.map(\.location)
                MainActor.assumeIsolated {
                    let wasDown = observer.down
                    let previous = observer.activeCount
                    observer.activeCount = active.count
                    if !active.isEmpty {
                        let n = CGFloat(active.count)
                        observer.centroid = CGPoint(x: active.map(\.x).reduce(0, +) / n, y: active.map(\.y).reduce(0, +) / n)
                    }
                    if active.count != previous {
                        pinch(.fingerCountChanged(count: active.count, remaining: observer.centroid, time: now()))
                    } else if active.count >= 2 {
                        pinch(.fingerCountChanged(count: active.count, remaining: observer.centroid, time: now()))
                    } else if active.count == 1, let c = observer.centroid {
                        synthesize(c, now())
                    }
                    if !wasDown, let first = active.first {
                        observer.down = true
                        send(.touchDown(location: first, time: now(), touchCount: active.count))
                    } else if wasDown, active.isEmpty {
                        observer.down = false
                        observer.centroid = nil
                        send(.touchesEnded(time: now()))
                    }
                }
            }
            .onEnded { _ in
                MainActor.assumeIsolated {
                    guard observer.down else { return }
                    observer.down = false
                    observer.activeCount = 0
                    observer.centroid = nil
                    send(.touchesEnded(time: now()))
                }
            }
    }
}
