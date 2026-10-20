import CoreGraphics
import Foundation

// Pure core of the iOS 15-16 touch observer (SPEC S2 amendment 2026-10-20, D31; design UIKIT-touch-observer.md §3/§5).
// No UIKit and no `#if`: it compiles everywhere and is covered 100 % by `TouchObserverCoreTests`. The UIKit shell
// (session b) only turns `UITouch`es into `TouchSample`s and forwards the outputs to the coordinator.

/// One touch as the shell reports it: `id` is stable for the touch's lifetime (the shell hashes the `UITouch`
/// identity; UIKit may reuse it after the touch ended), `location` is in the viewport's local space.
struct TouchSample: Equatable {
    enum Phase: Equatable { case began, moved, ended, cancelled }
    var id: UInt
    var phase: Phase
    var location: CGPoint
}

/// What the core hands to the coordinator, in order: `.pan` → `PanCoordinator.handle`, `.pinch` → `handlePinch`,
/// `.synthesize` → `synthesizePan` (one-finger continuation after a pinch, M4 §4).
enum ObserverOutput: Equatable {
    case pan(PanEvent)
    case pinch(PinchEvent)
    case synthesize(CGPoint, TimeInterval)
}

/// Touch bookkeeping that reproduces `SpatialCatchGesture`'s emission order from raw touch phases (§3 of the design), so
/// `PanCoordinator`, `PanSession` and `PinchSession` (D20/D23/D25/D29) run unchanged on iOS 15-16.
///
/// - A touch is ours iff its `began` location is inside the viewport; decided once, kept for its lifetime. Samples of
///   touches that began outside (or that never began) are dropped by id.
/// - The pinch magnification is the distance ratio of the two OLDEST active touches, relative to the distance when that
///   pair took over. A pair change under a live pinch (a lifted finger was one of the two) continues from the
///   magnification already reached, so `PinchSession`'s `magnification / base` does not jump.
/// - Timestamps are the shell's `now()` at delivery (D14); `UITouch.timestamp` never enters the core.
struct TouchObserverCore: Sendable {
    private struct Tracked: Sendable {
        var location: CGPoint
        var order: Int
    }

    private struct Pair: Sendable {
        var first: UInt
        var second: UInt
        var baseDistance: CGFloat

        /// `carried` × the spread since the pair took over; nil while the fingers coincide. Two fingers that landed
        /// on one point take the first spread as their reference.
        mutating func ratio(distance d: CGFloat, carried: CGFloat) -> CGFloat? {
            if baseDistance <= 0 { baseDistance = d }
            guard d > 0 else { return nil }
            return carried * d / baseDistance
        }
    }

    private var touches: [UInt: Tracked] = [:]
    private var nextOrder = 0
    private var pair: Pair?
    private var pinchLive = false
    /// Magnification at which the current pair took over (1 for a pinch's first pair).
    private var carried: CGFloat = 1
    private var lastMagnification: CGFloat = 1

    /// A touch sequence is in progress (`touchDown` sent, `touchesEnded` / `cancelled` not yet).
    private(set) var isDown = false
    /// Mean of the active touches; the last one stays after the final lift until `touchesEnded` is emitted.
    private(set) var centroid: CGPoint?
    var activeCount: Int { touches.count }

    /// Drops everything. A live sequence is closed with `.cancelled` for pan and pinch (view removed mid-touch).
    @discardableResult
    mutating func reset() -> [ObserverOutput] {
        let live = isDown
        self = TouchObserverCore()
        return live ? [.pan(.cancelled), .pinch(.cancelled)] : []
    }

    /// One delivery of touch samples (`touchesBegan` / `Moved` / `Ended` / `Cancelled`), `time` = the shell's `now()`.
    mutating func handle(_ samples: [TouchSample], viewport: CGRect, time: TimeInterval) -> [ObserverOutput] {
        let previousCount = touches.count
        let wasDown = isDown
        var cancelled = false
        var moved = false
        for sample in samples {
            switch sample.phase {
            case .began:
                guard viewport.contains(sample.location) else { continue }
                // A `began` for a live id (its end was missed) replaces the old touch.
                if touches.updateValue(Tracked(location: sample.location, order: nextOrder), forKey: sample.id) != nil {
                    moved = true
                }
                nextOrder += 1
            case .moved:
                guard touches[sample.id] != nil else { continue }
                touches[sample.id]?.location = sample.location
                moved = true
            case .ended:
                touches[sample.id] = nil
            case .cancelled:
                if touches[sample.id] != nil { cancelled = true }
            }
        }
        if cancelled {
            self = TouchObserverCore()
            return [.pan(.cancelled), .pinch(.cancelled)]
        }

        let ordered = touches.sorted { $0.value.order < $1.value.order }
        let count = ordered.count
        if count > 0 {
            let n = CGFloat(count)
            centroid = CGPoint(x: ordered.map(\.value.location.x).reduce(0, +) / n,
                               y: ordered.map(\.value.location.y).reduce(0, +) / n)
        }

        var pairChanged = false
        if count >= 2 {
            let (a, b) = (ordered[0], ordered[1])
            if !pinchLive {
                pinchLive = true
                lastMagnification = 1
            }
            if pair?.first != a.key || pair?.second != b.key {
                pairChanged = true
                carried = lastMagnification
                pair = Pair(first: a.key, second: b.key, baseDistance: Self.distance(a.value.location, b.value.location))
            }
        }

        var out: [ObserverOutput] = []
        if count != previousCount {
            out.append(.pinch(.fingerCountChanged(count: count, remaining: centroid, time: time)))
        } else if count >= 2, moved || pairChanged {
            let d = Self.distance(ordered[0].value.location, ordered[1].value.location)
            if let m = pair?.ratio(distance: d, carried: carried) {
                lastMagnification = m
                out.append(.pinch(.changed(magnification: m, centroid: centroid, time: time)))
            }
        } else if count == 1, moved {
            out.append(.synthesize(ordered[0].value.location, time))
        }

        if !wasDown, let first = ordered.first {
            isDown = true
            out.append(.pan(.touchDown(location: first.value.location, time: time, touchCount: count)))
        } else if wasDown, ordered.isEmpty {
            isDown = false
            centroid = nil
            out.append(.pan(.touchesEnded(time: time)))
        }
        if pinchLive, count < 2 {
            pinchLive = false
            pair = nil
            out.append(.pinch(.ended(time: time)))
        }
        return out
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
