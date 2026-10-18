import SwiftUI

/// Raw-touch observer (design M3-pan §8): touch-down "catch" and last-finger-up. SpatialEventGesture on 18+,
/// `DragGesture(minimumDistance: 0)` otherwise. Emits `PanEvent`s through `send`; holds no logic.
final class CatchObserverState: @unchecked Sendable {   // touched on the main thread only
    var activeCount = 0
    var down = false
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
                        now: @escaping @Sendable () -> TimeInterval) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                let active = events.filter { $0.phase == .active }.map(\.location)
                MainActor.assumeIsolated {
                    let wasDown = observer.down
                    observer.activeCount = active.count
                    if !wasDown, let first = active.first {
                        observer.down = true
                        send(.touchDown(location: first, time: now(), touchCount: active.count))
                    } else if wasDown, active.isEmpty {
                        observer.down = false
                        send(.touchesEnded(time: now()))
                    }
                }
            }
            .onEnded { _ in
                MainActor.assumeIsolated {
                    guard observer.down else { return }
                    observer.down = false
                    observer.activeCount = 0
                    send(.touchesEnded(time: now()))
                }
            }
    }
}
