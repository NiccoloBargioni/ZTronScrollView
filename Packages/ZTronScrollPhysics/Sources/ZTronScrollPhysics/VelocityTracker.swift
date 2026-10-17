import CoreGraphics
import Foundation

/// Release-velocity estimator for one axis (SPEC S6 "Release velocity").
///
/// **Estimator:** an exponentially weighted least-squares line through the samples inside the window
/// `[lift − window, lift]`:
///
///     v = Σ w·(t − t̄)·(x − x̄) / Σ w·(t − t̄)²     w = exp(−(lift − t) / τ)
///
/// with weighted means `t̄`, `x̄` and `τ = timeConstant` (`40 ms`). A single late event cannot dominate, irregular
/// delivery (coalesced events, 60 vs 120 Hz) is handled by the true timestamps, and the weighting tracks a fling that
/// accelerates in its last 30–50 ms. If `Σ w·(t − t̄)² < 1e-9 s²` (all samples at one instant) the result is `0`.
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

    /// `s`: samples older than `lift − window` are ignored.
    public var window: TimeInterval = 0.100
    /// `s`: if the newest sample is older than this at lift, or the finger moved less than ``restDistance`` during
    /// it, the finger is considered resting and the velocity is `0` (SPEC S6: 50–80 ms, tune on device).
    public var restTimeout: TimeInterval = 0.064
    /// `pt` moved inside ``restTimeout`` that still counts as resting.
    public var restDistance: CGFloat = 1.0
    /// `s`: `τ` of the weight `exp(−age / τ)`.
    public var timeConstant: TimeInterval = 0.040
    /// Maximum retained samples (120 Hz × 100 ms = 12 samples, plus margin). The oldest sample is dropped first.
    public var capacity: Int = 24

    private var samples: [Sample] = []

    /// Creates a tracker; non-finite or non-positive durations fall back to the defaults.
    public init(window: TimeInterval = 0.100, restTimeout: TimeInterval = 0.064) {
        self.window = window.isFinite && window > 0 ? window : 0.100
        self.restTimeout = restTimeout.isFinite && restTimeout > 0 ? restTimeout : 0.064
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

    /// Release velocity in `pt/s` at `liftTime` (`s`, gesture clock; a lift earlier than the newest sample is
    /// treated as the newest sample's time).
    ///
    /// `0` when fewer than 2 samples lie in the window, the newest sample is older than ``restTimeout``, or the
    /// displacement over the last ``restTimeout`` (measured against the position interpolated at
    /// `lift − restTimeout`) stays below ``restDistance``.
    public func velocity(at liftTime: TimeInterval) -> CGFloat {
        guard let newest = samples.last else { return 0 }
        let lift = liftTime.isFinite ? Swift.max(liftTime, newest.time) : newest.time
        if lift - newest.time > restTimeout { return 0 }

        let windowStart = lift - window
        guard let firstInWindow = samples.firstIndex(where: { $0.time >= windowStart }),
              samples.count - firstInWindow >= 2 else { return 0 }

        if isResting(lift: lift, newest: newest) { return 0 }

        // Weighted least squares on times relative to the lift (small magnitudes keep precision).
        let tau = timeConstant.isFinite && timeConstant > 0 ? timeConstant : 0.040
        var sw: CGFloat = 0, st: CGFloat = 0, sx: CGFloat = 0
        for s in samples[firstInWindow...] {
            let w = CGFloat(exp(-(lift - s.time) / tau))
            sw += w
            st += w * CGFloat(s.time - lift)
            sx += w * s.position
        }
        guard sw > 0 else { return 0 }
        let tMean = st / sw, xMean = sx / sw
        var num: CGFloat = 0, den: CGFloat = 0
        for s in samples[firstInWindow...] {
            let w = CGFloat(exp(-(lift - s.time) / tau))
            let dt = CGFloat(s.time - lift) - tMean
            num += w * dt * (s.position - xMean)
            den += w * dt * dt
        }
        guard den >= 1e-9 else { return 0 }
        return (num / den).finiteOrZero
    }

    /// True when every position since `lift − restTimeout` (including the interpolated position at that instant)
    /// lies within ``restDistance`` of the newest position.
    private func isResting(lift: TimeInterval, newest: Sample) -> Bool {
        let restStart = lift - restTimeout
        var maxDeviation: CGFloat = 0
        var reference: CGFloat?
        for (i, s) in samples.enumerated().reversed() {
            if s.time >= restStart {
                maxDeviation = Swift.max(maxDeviation, abs(s.position - newest.position))
                continue
            }
            // `s` is the last sample before the rest window; interpolate toward the next one.
            let next = samples[i + 1]
            let span = next.time - s.time
            let f = span > 0 ? CGFloat((restStart - s.time) / span) : 0
            reference = s.position + (next.position - s.position) * f
            break
        }
        let ref = reference ?? samples[0].position
        maxDeviation = Swift.max(maxDeviation, abs(ref - newest.position))
        return maxDeviation < restDistance
    }
}

/// Two independent ``VelocityTracker`` axes fed with shared timestamps.
public struct PointVelocityTracker: Sendable, Equatable {
    public var x: VelocityTracker
    public var y: VelocityTracker

    public init(window: TimeInterval = 0.100, restTimeout: TimeInterval = 0.064) {
        x = VelocityTracker(window: window, restTimeout: restTimeout)
        y = VelocityTracker(window: window, restTimeout: restTimeout)
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

    /// Release velocity in `pt/s` per axis.
    public func velocity(at liftTime: TimeInterval) -> CGVector {
        CGVector(dx: x.velocity(at: liftTime), dy: y.velocity(at: liftTime))
    }
}
