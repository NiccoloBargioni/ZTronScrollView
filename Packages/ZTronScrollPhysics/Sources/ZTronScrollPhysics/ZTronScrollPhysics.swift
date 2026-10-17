// ZTronScrollPhysics: the pure, closed-form physics that drives `ZTronScrollView` (SPEC S5, S6).
//
// There is deliberately no `ZTronScrollPhysics` type: a type named like its module would shadow the module, and
// `ZTronScrollPhysics.Decay` could then no longer pick this package's `Decay` over a client's own `Decay`.
//
// Every type in this module is a `Sendable` value type that imports only Foundation and CoreGraphics.
// Axes are independent (`CGFloat` per axis; 2D helpers only compose two axes) and every motion is a
// closed-form function of elapsed time: sampling never integrates, so any frame can be evaluated in any order.
//
// Units: positions in points (`pt`), velocities in points per second (`pt/s`), time in seconds
// (`TimeInterval`), deceleration rate `r` per millisecond, zoom scale dimensionless.
// The delegate's `willEndDragging(withVelocity:)` uses `pt/ms`; convert with `Velocity.pointsPerMillisecond(_:)`.
//
// Sign convention: offsets grow toward the content end and velocity is `d(offset)/dt`, so a finger moving
// up (content moving toward its end) produces a positive offset velocity.
//
// Clocks: the package is epoch-agnostic but never mixes clocks.
// - A motion (`AxisMotion`, `ZoomMotion`) takes its `start`, its precomputed crossing times and every sample time
//   from one clock. Sampling at exactly `start + settlingTime` settles for any clock magnitude, including
//   `Date`-based values around 8e8 s (the settle comparison allows a few ulps of the sample time).
// - A `VelocityTracker` takes every sample and its lift time from one gesture clock.
// - Velocities (`pt/s`) and durations (`s`) are clock-independent, so they are the only values that cross clocks.
// Canonical clock for the SwiftUI layer: seconds since a per-view session origin. It rebases each source once:
// `TimelineView` `context.date` and `DragGesture.Value.time` are `Date` (use `timeIntervalSinceReferenceDate`),
// while `SpatialEventCollection.Event.timestamp` is system uptime (offset it by the `Date` − uptime difference
// measured once per session). Small session times also keep full sub-microsecond resolution.
//
// Numeric guards: `NaN`/`±inf` inputs become `0` (velocities, position deltas) or the nearest valid default
// (rates, scales); `t < 0` samples the start state; a time after settling samples the end state exactly.
