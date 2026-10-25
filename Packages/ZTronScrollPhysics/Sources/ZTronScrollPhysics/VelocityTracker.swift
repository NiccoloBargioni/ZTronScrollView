import CoreGraphics
import Foundation

/// Release-velocity estimator for one axis (SPEC S6 "Release velocity"), with UIKit's release rule as measured in
/// docs/progress/BTN-s2.md.
///
/// **Estimator:** an exponentially weighted least-squares line through the samples inside the window `[e − window, e]`:
///
///     v = Σ w·(t − t̄)·(x − x̄) / Σ w·(t − t̄)²     w = exp(−(e − t) / τ)
///
/// with weighted means `t̄`, `x̄` and `τ = timeConstant`. A single late event cannot dominate, and irregular delivery
/// (coalesced events, 60 vs 120 Hz) is handled by the true timestamps. If `Σ w·(t − t̄)² < 1e-9 s²` (all samples at
/// one instant) or fewer than 2 samples lie in the window, the result is `0`.
///
/// **Evaluation point (P1):** the release velocity comes from the touch *moves* only; the lift time and any event-free
/// pause before it never matter to UIKit. The fit is therefore evaluated at `e = min(max(lift, newest), newest +
/// liftTolerance)`: a lift within one frame of the newest sample keeps the lift-anchored fit (the calibration below was
/// recorded that way), a later lift is treated as if it had happened one frame after the last move.
///
/// **Gate (P2):** UIKit does not decelerate unless the pan recognizer's velocity, which is the finger's displacement over
/// its last ``gateSpan`` (50 ms) of moves, reaches ``minimumDecelerationVelocity`` (250 pt/s, inclusive). A slow drag
/// held still, a drag that ends in jitter, or a drag that slows to a crawl before the finger leaves the screen rests
/// where it is; a drag that paused for a second and then lifted still flings. ``velocity(at:)`` applies the gate,
/// ``ungatedVelocity(at:)`` is the fit alone, ``gateVelocity`` is the gating quantity.
///
/// Calibration (docs/design/PHYSICS-calibration.md): the native `ScrollView` release velocity equals the *unweighted*
/// least-squares slope over the last 100 ms within 1 % on every recorded fling; the former `τ = 40 ms` weighting
/// under-estimated fast flicks by 14 % because a flick's last event is always slower (the finger stops to lift). The
/// default `τ = 1 s` therefore makes the weights nearly uniform inside the window.
///
/// Timestamps must come from the gesture's own clock, one source per tracker (`DragGesture.Value.time` as
/// `timeIntervalSinceReferenceDate`, or `SpatialEventCollection.Event.timestamp`, which is uptime), never mixed and
/// never the delivery time `Date()`; the lift time must use the same clock. Any epoch works because only time
/// differences enter the fit. Positions are in `pt`, times in `s`, the result in `pt/s`.
public struct VelocityTracker: Sendable, Equatable {
    /// One timestamped position.
    public struct Sample: Sendable, Equatable {
        /// `s`, the tracker's gesture clock.
        public var time: TimeInterval
        /// `pt`.
        public var position: CGFloat

        public init(time: TimeInterval, position: CGFloat) {
            self.time = time
            self.position = position
        }
    }

    /// `s`: samples older than `e − window` are ignored (`e` = the evaluation point).
    public var window: TimeInterval = 0.100
    /// `s`: a lift later than the newest sample by more than this is evaluated at `newest + liftTolerance` (one frame
    /// at 60 Hz); an event-free pause before the lift does not change the result (BTN-s2, P1).
    public var liftTolerance: TimeInterval = 1.0 / 60
    /// `pt/s`: ``velocity(at:)`` is `0` unless `|gateVelocity|` reaches this (UIKit: 250 pt/s, BTN-s2, P2). `0` turns
    /// the gate off.
    public var minimumDecelerationVelocity: CGFloat = 250
    /// `s`: the span of the finger's last moves whose displacement defines ``gateVelocity`` (UIKit's pan velocity).
    public var gateSpan: TimeInterval = 0.050
    /// `s`: `τ` of the weight `exp(−age / τ)`.
    public var timeConstant: TimeInterval = 1.0
    /// Maximum retained samples (120 Hz × 100 ms = 12 samples, plus margin). The oldest sample is dropped first.
    public var capacity: Int = 24

    private var samples: [Sample] = []

    /// Creates a tracker; a non-finite or non-positive `window` falls back to 100 ms, a non-finite or negative
    /// `minimumDecelerationVelocity` to 250 pt/s (`0` disables the gate).
    public init(window: TimeInterval = 0.100, minimumDecelerationVelocity: CGFloat = 250) {
        self.window = window.isFinite && window > 0 ? window : 0.100
        self.minimumDecelerationVelocity = minimumDecelerationVelocity.isFinite && minimumDecelerationVelocity >= 0
            ? minimumDecelerationVelocity : 250
        samples.reserveCapacity(capacity + 1)
    }

    /// Removes every sample (call at touch-down).
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Appends a sample. Non-finite positions or times and times earlier than the newest sample are ignored;
    /// a sample with the newest sample's timestamp replaces its position (coalesced delivery).
    public mutating func add(position: CGFloat, at time: TimeInterval) {
        guard position.isFinite, time.isFinite else { return }
        if let last = samples.last {
            if time < last.time { return }
            if time == last.time {
                samples[samples.count - 1].position = position
                return
            }
        }
        samples.append(Sample(time: time, position: position))
        let limit = Swift.max(capacity, 2)
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }

    /// The newest sample, if any.
    public var latest: Sample? { samples.last }

    /// Number of retained samples.
    public var count: Int { samples.count }

    /// The natural release velocity in `pt/s` at `liftTime` (`s`, gesture clock): ``ungatedVelocity(at:)`` when
    /// `|gateVelocity| >= minimumDecelerationVelocity`, else `0` (the finger rests where it is). A lift earlier than
    /// the newest sample is treated as the newest sample's time; a lift later than `newest + liftTolerance` as that.
    public func velocity(at liftTime: TimeInterval) -> CGFloat {
        abs(gateVelocity) >= minimumDecelerationVelocity ? ungatedVelocity(at: liftTime) : 0
    }

    /// The weighted least-squares fit alone (no gate), evaluated at
    /// `min(max(liftTime, newest.time), newest.time + liftTolerance)`. `0` with fewer than 2 samples in the window.
    public func ungatedVelocity(at liftTime: TimeInterval) -> CGFloat {
        guard let newest = samples.last else { return 0 }
        let tolerance = liftTolerance.isFinite && liftTolerance >= 0 ? liftTolerance : 1.0 / 60
        let lift = liftTime.isFinite ? Swift.max(liftTime, newest.time) : newest.time
        let e = Swift.min(lift, newest.time + tolerance)

        let windowStart = e - window
        guard let firstInWindow = samples.firstIndex(where: { $0.time >= windowStart }),
              samples.count - firstInWindow >= 2 else { return 0 }

        // Weighted least squares on times relative to the evaluation point (small magnitudes keep precision).
        let tau = timeConstant.isFinite && timeConstant > 0 ? timeConstant : 1.0
        var sw: CGFloat = 0, st: CGFloat = 0, sx: CGFloat = 0
        for s in samples[firstInWindow...] {
            let w = CGFloat(exp(-(e - s.time) / tau))
            sw += w
            st += w * CGFloat(s.time - e)
            sx += w * s.position
        }
        guard sw > 0 else { return 0 }
        let tMean = st / sw, xMean = sx / sw
        var num: CGFloat = 0, den: CGFloat = 0
        for s in samples[firstInWindow...] {
            let w = CGFloat(exp(-(e - s.time) / tau))
            let dt = CGFloat(s.time - e) - tMean
            num += w * dt * (s.position - xMean)
            den += w * dt * dt
        }
        guard den >= 1e-9 else { return 0 }
        return (num / den).finiteOrZero
    }

    /// UIKit's pan velocity in `pt/s`: the displacement over the last ``gateSpan`` of moves,
    /// `(newest.position − x(newest.time − gateSpan)) / gateSpan`, with `x(t)` linearly interpolated between the two
    /// samples around `t` and clamped to the oldest retained sample when `t` precedes it (a drag shorter than
    /// `gateSpan` under-reads, as UIKit's does). `0` with fewer than 2 samples.
    public var gateVelocity: CGFloat {
        guard samples.count >= 2, let newest = samples.last else { return 0 }
        let span = gateSpan.isFinite && gateSpan > 0 ? gateSpan : 0.050
        let t = newest.time - span
        var reference = samples[0].position
        if t > samples[0].time {
            // The first sample at or after `t`; it has a predecessor because samples[0].time < t.
            if let j = samples.firstIndex(where: { $0.time >= t }) {
                let a = samples[j - 1], b = samples[j]
                let dt = b.time - a.time
                let f = dt > 0 ? CGFloat((t - a.time) / dt) : 1
                reference = a.position + (b.position - a.position) * f
            } else {
                reference = newest.position
            }
        }
        return ((newest.position - reference) / CGFloat(span)).finiteOrZero
    }

    /// Velocity in `pt/s` of the last movement: ``ungatedVelocity(at:)`` at the newest sample's time, no gate. UIKit
    /// seeds the spring-back from a rubber band with the pan recognizer's velocity whatever its size
    /// (docs/design/PHYSICS-calibration.md).
    public var lastMotionVelocity: CGFloat {
        guard let newest = samples.last else { return 0 }
        return ungatedVelocity(at: newest.time)
    }
}

/// Two independent ``VelocityTracker`` axes fed with shared timestamps; each axis applies its own gate.
public struct PointVelocityTracker: Sendable, Equatable {
    public var x: VelocityTracker
    public var y: VelocityTracker

    public init(window: TimeInterval = 0.100, minimumDecelerationVelocity: CGFloat = 250) {
        x = VelocityTracker(window: window, minimumDecelerationVelocity: minimumDecelerationVelocity)
        y = VelocityTracker(window: window, minimumDecelerationVelocity: minimumDecelerationVelocity)
    }

    /// Removes every sample on both axes.
    public mutating func reset() {
        x.reset()
        y.reset()
    }

    /// Adds `p` (`pt`) at `time` (`s`); each axis applies its own guards.
    public mutating func add(_ p: CGPoint, at time: TimeInterval) {
        x.add(position: p.x, at: time)
        y.add(position: p.y, at: time)
    }

    /// Gated release velocity in `pt/s` per axis (``VelocityTracker/velocity(at:)``).
    public func velocity(at liftTime: TimeInterval) -> CGVector {
        CGVector(dx: x.velocity(at: liftTime), dy: y.velocity(at: liftTime))
    }

    /// The fits alone, no gate (``VelocityTracker/ungatedVelocity(at:)``).
    public func ungatedVelocity(at liftTime: TimeInterval) -> CGVector {
        CGVector(dx: x.ungatedVelocity(at: liftTime), dy: y.ungatedVelocity(at: liftTime))
    }
}
