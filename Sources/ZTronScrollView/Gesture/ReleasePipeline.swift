import SwiftUI
import ZTronScrollPhysics

// Release pipeline (design M3-pan §5): tracker velocity -> fling acceleration -> target (paging / M6 hook) ->
// delegate willEndDragging -> ReleaseSolver -> deceleration or immediate rest. The per-axis steps are pure.

struct ReleaseInput {
    var origin: CGFloat
    var dragStart: CGFloat
    /// pt/s
    var velocity: CGFloat
    var bounds: AxisBounds
    var bounces: Bool
    var rate: DecelerationRate
    var pageLength: CGFloat?
    var thresholds: RestThresholds
}

enum ReleasePipeline {
    /// Tracker velocity (pt/s) when it has >= 2 samples, else the gesture's own velocity, else 0.
    static func velocity(tracker: VelocityTracker, liftTime: TimeInterval, fallback: CGFloat?) -> CGFloat {
        tracker.count >= 2 ? tracker.velocity(at: liftTime) : (fallback ?? 0)
    }

    /// Carries the momentum of a motion stopped by a quick catch (same direction), capped.
    static func accelerated(_ v: CGFloat, caughtVelocity: CGFloat, caughtAt: TimeInterval?, liftTime: TimeInterval,
                            _ f: FlingAcceleration) -> CGFloat {
        guard let caughtAt else { return v }
        return f.combine(release: v, remainingAtCatch: caughtVelocity, touchDuration: liftTime - caughtAt)
    }

    /// Paging target (one page max); `nil` otherwise (M6 inserts `ZTronScrollTargetBehavior` here).
    static func proposedTarget(_ i: ReleaseInput) -> CGFloat? {
        guard let page = i.pageLength else { return nil }
        return PagingSolver.target(current: i.origin, dragStart: i.dragStart, velocity: i.velocity, pageLength: page,
                                   bounds: i.bounds)
    }

    /// Natural rest point of the decay, clamped to the bounds.
    static func naturalRest(_ i: ReleaseInput) -> CGFloat {
        i.bounds.clamped(TargetSnapping.projectedRest(origin: i.origin, velocity: i.velocity, rate: i.rate))
    }

    static func motion(_ i: ReleaseInput, target: CGFloat?, at t: TimeInterval) -> AxisMotion {
        ReleaseSolver.resolve(ReleaseContext(origin: i.origin, velocity: i.velocity, bounds: i.bounds, rate: i.rate,
                                             bounces: i.bounces, thresholds: i.thresholds, target: target), at: t)
    }
}

struct ReleaseSettings: Equatable {
    var rate: DecelerationRate = .normal
    var isPagingEnabled = false
    var fling = FlingAcceleration()
    var thresholds = RestThresholds()
    var displayScale: CGFloat = 2
}

extension ZTronScrollState {
    /// Lift: runs the whole release (design §5). `tracker` holds finger locations (offset velocity = -finger velocity). Delegate order: didScroll (pending) -> willEndDragging ->
    /// didEndDragging(willDecelerate:) -> [willBeginDecelerating, clock...]. Returns the motions it started.
    @discardableResult
    func endDrag(_ r: ReleaseRequest, tracker: PointVelocityTracker, env: PanEnvironment,
                 settings: ReleaseSettings) -> (x: AxisMotion, y: AxisMotion) {
        flushPendingScroll()
        let lift = r.liftTime.isFinite ? r.liftTime : now()
        func axisVelocity(_ t: VelocityTracker, fallback: CGFloat?, caught: CGFloat, enabled: Bool) -> CGFloat {
            guard enabled, !r.zeroVelocity else { return 0 }
            // The tracker and DragGesture speak finger motion; content offset moves the opposite way.
            let v = -ReleasePipeline.velocity(tracker: t, liftTime: lift, fallback: fallback)
            return ReleasePipeline.accelerated(v, caughtVelocity: caught, caughtAt: r.caughtAt, liftTime: lift, settings.fling)
        }
        let enabledX = env.isScrollEnabled && env.axes.contains(.horizontal) && (r.lock == nil || r.lock == .horizontal)
        let enabledY = env.isScrollEnabled && env.axes.contains(.vertical) && (r.lock == nil || r.lock == .vertical)
        let vx = axisVelocity(tracker.x, fallback: r.fallbackVelocity?.dx, caught: r.caughtVelocity.dx, enabled: enabledX)
        let vy = axisVelocity(tracker.y, fallback: r.fallbackVelocity?.dy, caught: r.caughtVelocity.dy, enabled: enabledY)
        let rate = settings.rate
        let ix = ReleaseInput(origin: r.origin.x, dragStart: r.dragStart.x, velocity: vx, bounds: env.boundsX,
                              bounces: env.bouncesX, rate: rate,
                              pageLength: settings.isPagingEnabled && enabledX ? env.viewport.width : nil,
                              thresholds: settings.thresholds)
        let iy = ReleaseInput(origin: r.origin.y, dragStart: r.dragStart.y, velocity: vy, bounds: env.boundsY,
                              bounces: env.bouncesY, rate: rate,
                              pageLength: settings.isPagingEnabled && enabledY ? env.viewport.height : nil,
                              thresholds: settings.thresholds)
        let tx = ReleasePipeline.proposedTarget(ix), ty = ReleasePipeline.proposedTarget(iy)
        let natural = CGPoint(x: ReleasePipeline.naturalRest(ix), y: ReleasePipeline.naturalRest(iy))
        var proposed = CGPoint(x: tx ?? natural.x, y: ty ?? natural.y)
        delegate?.scrollViewWillEndDragging(self, withVelocity: CGPoint(x: vx / 1000, y: vy / 1000),
                                            targetContentOffset: &proposed)
        let targetX = (tx != nil || proposed.x != natural.x) ? proposed.x : nil
        let targetY = (ty != nil || proposed.y != natural.y) ? proposed.y : nil
        // The motion runs on the state clock. `lift` is a gesture event time, which may use another time base
        // (iOS 27: DragGesture.Value.time is uptime-based): starting there settles the fling on its first tick.
        let start = now()
        let mx = ReleasePipeline.motion(ix, target: targetX, at: start)
        let my = ReleasePipeline.motion(iy, target: targetY, at: start)
        let willDecelerate = mx.willDecelerate || my.willDecelerate
        delegate?.scrollViewDidEndDragging(self, willDecelerate: willDecelerate)
        if willDecelerate {
            beginDeceleration(x: mx, y: my, at: start, displayScale: settings.displayScale)
        } else {
            let snapped = PixelSnap.snap(CGPoint(x: mx.endPosition, y: my.endPosition), displayScale: settings.displayScale)
            track(offset: snapped, zoom: peek.presentationZoom)
            endTracking()
        }
        return (mx, my)
    }
}
