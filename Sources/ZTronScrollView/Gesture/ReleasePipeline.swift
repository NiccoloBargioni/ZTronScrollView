import SwiftUI
import ZTronScrollPhysics

// Release pipeline (design M3-pan §5, M6 §4): tracker velocity -> fling acceleration -> scroll-target behavior
// (`ZTronScrollTargetBehavior`; the `isPagingEnabled` knob is `.paging`) -> delegate willEndDragging -> ReleaseSolver ->
// deceleration or immediate rest. The per-axis steps are pure.

struct ReleaseInput {
    var origin: CGFloat
    var dragStart: CGFloat
    /// pt/s
    var velocity: CGFloat
    var bounds: AxisBounds
    var bounces: Bool
    var rate: DecelerationRate
    var thresholds: RestThresholds
    /// pt/s, content direction: the finger's last movement velocity (not zeroed by a pause); spring-back seed.
    var rubberBandVelocity: CGFloat = 0
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

    /// Natural rest point of the decay, clamped to the bounds.
    static func naturalRest(_ i: ReleaseInput) -> CGFloat {
        i.bounds.clamped(TargetSnapping.projectedRest(origin: i.origin, velocity: i.velocity, rate: i.rate))
    }

    static func motion(_ i: ReleaseInput, target: CGFloat?, at t: TimeInterval) -> AxisMotion {
        ReleaseSolver.resolve(ReleaseContext(origin: i.origin, velocity: i.velocity, bounds: i.bounds, rate: i.rate,
                                             bounces: i.bounces, thresholds: i.thresholds, target: target,
                                             rubberBandVelocity: i.rubberBandVelocity), at: t)
    }
}

/// Where the scroll-target behavior (and the velocity limit) put the release: the proposed offset the delegate may still
/// change, and per axis whether the behavior retargets the motion even when it proposes the natural landing point.
struct ReleaseTargetDecision {
    var proposed: CGPoint
    var snapsX = false
    var snapsY = false
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
            return ReleasePipeline.accelerated(v, caughtVelocity: caught, caughtAt: r.caughtAt, liftTime: now(), settings.fling)  // state clock (D14)
        }
        let enabledX = env.isScrollEnabled && env.axes.contains(.horizontal) && (r.lock == nil || r.lock == .horizontal)
        let enabledY = env.isScrollEnabled && env.axes.contains(.vertical) && (r.lock == nil || r.lock == .vertical)
        let vx = axisVelocity(tracker.x, fallback: r.fallbackVelocity?.dx, caught: r.caughtVelocity.dx, enabled: enabledX)
        let vy = axisVelocity(tracker.y, fallback: r.fallbackVelocity?.dy, caught: r.caughtVelocity.dy, enabled: enabledY)
        // UIKit seeds the rubber-band spring-back with the pan's last velocity, which a pause does not zero.
        let rawX = enabledX && !r.zeroVelocity ? -tracker.x.lastMotionVelocity : 0
        let rawY = enabledY && !r.zeroVelocity ? -tracker.y.lastMotionVelocity : 0
        let rate = settings.rate
        let ix = ReleaseInput(origin: r.origin.x, dragStart: r.dragStart.x, velocity: vx, bounds: env.boundsX,
                              bounces: env.bouncesX, rate: rate, thresholds: settings.thresholds, rubberBandVelocity: rawX)
        let iy = ReleaseInput(origin: r.origin.y, dragStart: r.dragStart.y, velocity: vy, bounds: env.boundsY,
                              bounces: env.bouncesY, rate: rate, thresholds: settings.thresholds, rubberBandVelocity: rawY)
        let natural = CGPoint(x: ReleasePipeline.naturalRest(ix), y: ReleasePipeline.naturalRest(iy))
        let decision = decideTarget(r, env: env, settings: settings, ix: ix, iy: iy, enabledX: enabledX, enabledY: enabledY,
                                    natural: natural)
        var proposed = decision.proposed
        notifyWillEndDragging(velocity: CGPoint(x: vx / 1000, y: vy / 1000), target: &proposed)
        let targetX = (decision.snapsX || proposed.x != natural.x) ? proposed.x : nil
        let targetY = (decision.snapsY || proposed.y != natural.y) ? proposed.y : nil
        // The motion runs on the state clock. `lift` is a gesture event time, which may use another time base
        // (iOS 27: DragGesture.Value.time is uptime-based): starting there settles the fling on its first tick.
        let start = now()
        let mx = ReleasePipeline.motion(ix, target: targetX, at: start)
        let my = ReleasePipeline.motion(iy, target: targetY, at: start)
        let willDecelerate = mx.willDecelerate || my.willDecelerate
        notifyDidEndDragging(willDecelerate: willDecelerate)
        if willDecelerate {
            beginDeceleration(x: mx, y: my, at: start, displayScale: settings.displayScale)
        } else {
            let snapped = PixelSnap.snap(CGPoint(x: mx.endPosition, y: my.endPosition), displayScale: settings.displayScale)
            track(offset: snapped, zoom: peek.presentationZoom)
            endTracking()
        }
        onReleaseTargetDecided?(CGPoint(x: mx.endPosition, y: my.endPosition))
        return (mx, my)
    }

    /// The scroll-target behavior step (M6 §4, D27). THE one place that converts between the pipeline's offset space and
    /// SwiftUI's target space: the behavior sees `rect.origin = offset + startInset` (content coordinates) and
    /// `rect.size == containerSize == viewport - insets` (the unobscured size); the landing is
    /// `rect.origin + anchor · (rect.size - container) - startInset`, clamped to the bounds. `natural` is the clamped rest
    /// point of the decay; a behavior whose properties limit the velocity sees (and starts from) the natural point of the
    /// capped fling, at most one (unobscured) container length away. Axes the pan does not drive keep the natural rest;
    /// no behavior = natural.
    private func decideTarget(_ r: ReleaseRequest, env: PanEnvironment, settings: ReleaseSettings, ix: ReleaseInput,
                              iy: ReleaseInput, enabledX: Bool, enabledY: Bool, natural: CGPoint) -> ReleaseTargetDecision {
        let behavior = targetBehavior ?? (settings.isPagingEnabled ? AnyZTronScrollTargetBehavior.pagingKnob : nil)
        guard let behavior, enabledX || enabledY else { return ReleaseTargetDecision(proposed: natural) }
        var axes: Axis.Set = []
        if enabledX { axes.insert(.horizontal) }
        if enabledY { axes.insert(.vertical) }
        let snapshot = peek
        let scale = snapshot.presentationZoom
        let content = CGSize(width: snapshot.metrics.contentSize.width * scale, height: snapshot.metrics.contentSize.height * scale)
        let viewport = env.viewport
        let inset = snapshot.metrics.adjustedContentInset
        let startInset = CGPoint(x: inset.leading, y: inset.top)
        let container = CGSize(width: max(0, viewport.width - inset.leading - inset.trailing),
                               height: max(0, viewport.height - inset.top - inset.bottom))
        let properties = behavior.properties(context: ZTronScrollTargetBehaviorPropertiesContext(
            axes: axes, contentSize: content, containerSize: container, environment: targetEnvironment))

        var velocity = CGVector(dx: ix.velocity, dy: iy.velocity)
        var start = natural
        if properties.limitsVelocity {
            // Decay is linear in the velocity: the rest distance per pt/s is a constant of the deceleration rate.
            let distancePerVelocity = TargetSnapping.projectedRest(origin: 0, velocity: 1, rate: ix.rate)
            if enabledX, distancePerVelocity > 0, container.width > 0 {
                let cap = container.width / distancePerVelocity
                if abs(velocity.dx) > cap {
                    velocity.dx = velocity.dx < 0 ? -cap : cap
                    var limited = ix
                    limited.velocity = velocity.dx
                    start.x = ReleasePipeline.naturalRest(limited)
                }
            }
            if enabledY, distancePerVelocity > 0, container.height > 0 {
                let cap = container.height / distancePerVelocity
                if abs(velocity.dy) > cap {
                    velocity.dy = velocity.dy < 0 ? -cap : cap
                    var limited = iy
                    limited.velocity = velocity.dy
                    start.y = ReleasePipeline.naturalRest(limited)
                }
            }
        }

        var info = TargetReleaseInfo()
        info.origin = r.origin
        info.dragStart = r.dragStart
        info.rawVelocity = CGVector(dx: ix.velocity, dy: iy.velocity)
        info.insets = inset
        info.startInset = startInset
        info.viewport = viewport
        info.boundsX = env.boundsX
        info.boundsY = env.boundsY
        info.zoomScale = scale
        info.registry = targets
        let original = ZTronScrollTarget(rect: CGRect(origin: CGPoint(x: start.x + startInset.x, y: start.y + startInset.y),
                                                      size: container), anchor: nil)
        let context = ZTronScrollTargetBehaviorContext(
            originalTarget: original, velocity: velocity, contentSize: content, containerSize: container, axes: axes,
            environment: CapturedTargetEnvironment(values: targetEnvironment), info: info)
        var target = original
        behavior.updateTarget(&target, context: context)
        let anchor = target.anchor ?? .zero
        let landing = CGPoint(x: target.rect.origin.x + anchor.x * (target.rect.width - container.width) - startInset.x,
                              y: target.rect.origin.y + anchor.y * (target.rect.height - container.height) - startInset.y)

        var decision = ReleaseTargetDecision(proposed: natural)
        if enabledX {
            if landing.x.isFinite {
                decision.proposed.x = env.boundsX.clamped(landing.x)
            } else {
                decision.proposed.x = start.x
                #if DEBUG
                ZTronRenderCounters.increment("release.nonFiniteTarget")
                #endif
            }
            decision.snapsX = behavior.snaps(info)
        }
        if enabledY {
            if landing.y.isFinite {
                decision.proposed.y = env.boundsY.clamped(landing.y)
            } else {
                decision.proposed.y = start.y
                #if DEBUG
                ZTronRenderCounters.increment("release.nonFiniteTarget")
                #endif
            }
            decision.snapsY = behavior.snaps(info)
        }
        return decision
    }
}
