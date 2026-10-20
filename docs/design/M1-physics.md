# M1 · ZTronScrollPhysics + availability scaffolding (design)

Package `Packages/ZTronScrollPhysics`: `import Foundation` + `CoreGraphics` value types only. Every type is a `Sendable`
struct/enum, each axis is independent (`CGFloat` per axis; 2D helpers only compose two axes), and every motion is a
closed-form function of elapsed time (no Euler steps). Host-testable with `swift test` (macOS 12+, Swift 6.0 toolchain).

**Units everywhere:** positions `pt`, velocities `pt/s`, time `s` (`TimeInterval`), deceleration rate per `ms` (`r`), zoom
scale dimensionless. The delegate's `willEndDragging(withVelocity:)` takes `pt/ms`: convert with `Velocity.pointsPerMillisecond`.
Sign convention: offsets grow toward the content end; velocity is `d(offset)/dt` (a finger moving up = positive offset velocity).

**Clocks:** the package is epoch-agnostic but never mixes clocks. A motion's `start`, crossing times and sample times share
one clock; a `VelocityTracker`'s samples and lift time share one gesture clock; only velocities and durations cross clocks.
Canonical clock for the SwiftUI layer: seconds since a per-view session origin, rebasing `TimelineView` `context.date` and
`DragGesture.Value.time` (`Date`) and `SpatialEventCollection.Event.timestamp` (uptime; offset measured once per session).
The settle comparison allows `max(1e-9, 4·ulp(time))` s, so `sample(at: start + T)` settles even for `Date`-scale clocks
(~8e8 s, ulp ≈ 1.2e-7 s).

**Numeric guards (apply in every initializer / sampler):** `NaN`/`±inf` inputs become `0` (velocity, position delta) or the
nearest valid default (rate, scale); `r ∉ (0, 1)` is clamped to `[0.5, 0.9999]`; `v₀ = 0` → motion is `.rest` at `x₀`;
`Δ = 0` on retarget → spring fallback; viewport or dimension `≤ 0` → rubber band and paging degrade to identity/clamp;
`t < 0` samples the start state; `t` after settling samples the end state exactly (no drift).

## 1. Core value types

```swift
// No `ZTronScrollPhysics` type: a type named like the module shadows it and breaks `ZTronScrollPhysics.Decay`
// disambiguation (the M0 namespace enum was removed; its doc is the file comment of ZTronScrollPhysics.swift).

public enum Velocity {
    /// pt/s → pt/ms (delegate convention). Guards non-finite → 0.
    public static func pointsPerMillisecond(_ v: CGFloat) -> CGFloat
    public static func pointsPerSecond(fromPerMillisecond v: CGFloat) -> CGFloat
}

public struct DecelerationRate: Sendable, Hashable {
    public var perMillisecond: CGFloat                   // r, clamped to [0.5, 0.9999]
    public static let normal = DecelerationRate(perMillisecond: 0.998)
    public static let fast   = DecelerationRate(perMillisecond: 0.99)
    public init(perMillisecond: CGFloat)
    /// k = 1000·ln r  (1/s, negative). Used by every decay formula.
    public var k: CGFloat { get }
    public static let plausibleRange: ClosedRange<CGFloat> = 0.98...0.9995
}

public struct RestThresholds: Sendable, Equatable {
    public var velocity: CGFloat = 4            // pt/s   |v| below this counts as stopped
    public var distance: CGFloat = 0.5          // pt     remaining distance below this snaps to target
    public var negligibleReleaseVelocity: CGFloat = 20   // pt/s  "v₀ ≈ 0" for target resolution
    public init(velocity: CGFloat = 4, distance: CGFloat = 0.5, negligibleReleaseVelocity: CGFloat = 20)
}

public enum PixelSnap {
    /// (x·scale).rounded() / scale; returns x unchanged when scale ≤ 0 or x is non-finite.
    public static func snap(_ x: CGFloat, displayScale: CGFloat) -> CGFloat
    public static func snap(_ p: CGPoint, displayScale: CGFloat) -> CGPoint
}
```

## 2. Velocity tracker (`VelocityTracker.swift`)

```swift
public struct VelocityTracker: Sendable, Equatable {
    public struct Sample: Sendable, Equatable { public var time: TimeInterval; public var position: CGFloat }
    public var window: TimeInterval = 0.100           // samples older than lift − window are ignored
    public var restTimeout: TimeInterval = 0.064      // S6: 50–80 ms, tune on device
    public var restDistance: CGFloat = 1.0            // pt moved inside restTimeout that still counts as "resting"
    public var timeConstant: TimeInterval = 0.040     // weight = exp(−age / timeConstant)
    public var capacity: Int = 24                     // ring buffer; 120 Hz × 100 ms = 12 samples + margin
    public init(window: TimeInterval = 0.100, restTimeout: TimeInterval = 0.064)
    public mutating func reset()
    public mutating func add(position: CGFloat, at time: TimeInterval)   // ignores non-finite, non-monotonic time
    public var latest: Sample? { get }
    /// Release velocity in pt/s at `liftTime`. 0 when: fewer than 2 samples in the window, the newest sample is older
    /// than `restTimeout`, or the displacement over the last `restTimeout` is < `restDistance`.
    public func velocity(at liftTime: TimeInterval) -> CGFloat
}

public struct PointVelocityTracker: Sendable, Equatable {          // two independent axes sharing timestamps
    public var x: VelocityTracker, y: VelocityTracker
    public init(window: TimeInterval = 0.100, restTimeout: TimeInterval = 0.064)
    public mutating func reset()
    public mutating func add(_ p: CGPoint, at time: TimeInterval)
    public func velocity(at liftTime: TimeInterval) -> CGVector   // pt/s
}
```
**Estimator: exponentially weighted least-squares line** through the samples in the window, `v = Σw(t−t̄)(x−x̄) / Σw(t−t̄)²`
with `w = exp(−(lift − t)/τ)`, `τ = 40 ms`. Why: a single late event cannot dominate (S13 "last event only"), irregular
delivery (coalesced events, 60 vs 120 Hz) is handled by true timestamps, it is O(n) closed form, and the exponential
weighting tracks a fling that accelerates in the last 30–50 ms the way UIKit's tracker feels. If `Σw(t−t̄)² < 1e-9`
(all samples at one instant) the result is 0. Timestamps come from the gesture (`DragGesture.Value.time`,
`SpatialEventCollection.Event.timestamp`), never from `Date()`. Fallback on 17+ only when no samples exist:
`DragGesture.Value.velocity` (SDK inlines it as `4·(predictedEndLocation − location)`, pt/s).

## 3. Decay, spring, rubber band, bounds

```swift
public struct Decay: Sendable, Equatable {
    public var origin: CGFloat           // x₀ pt
    public var initialVelocity: CGFloat  // v₀ pt/s
    public var rate: DecelerationRate
    public init(origin: CGFloat, initialVelocity: CGFloat, rate: DecelerationRate = .normal)
    public func position(at t: TimeInterval) -> CGFloat     // x₀ + v₀(e^{kt} − 1)/k   (r^{1000t} = e^{kt})
    public func velocity(at t: TimeInterval) -> CGFloat     // v₀ e^{kt}
    public var restPosition: CGFloat { get }                // x₀ − v₀/k
    public var restDisplacement: CGFloat { get }            // −v₀/k
    /// First t ≥ 0 with position(t) == x; nil if never reached (wrong side, or beyond rest). t = ln(1 + k(x−x₀)/v₀)/k.
    public func time(toReach x: CGFloat) -> TimeInterval?
    /// t at which |v| falls to `speed`: ln(speed/|v₀|)/k; 0 when |v₀| ≤ speed.
    public func time(toSlowTo speed: CGFloat) -> TimeInterval
    public func duration(thresholds: RestThresholds) -> TimeInterval   // max(time(toSlowTo:), time until remaining < distance)
    /// Re-solve so the rest point is exactly `target`: r′ = exp(−v₀ / (1000·Δ)), Δ = target − x₀.
    /// Returns nil (caller uses a spring) when Δ == 0, sign(Δ) ≠ sign(v₀), |v₀| negligible, or r′ ∉ plausibleRange.
    public static func retargeted(origin: CGFloat, initialVelocity: CGFloat, target: CGFloat,
                                  thresholds: RestThresholds = .init()) -> Decay?
}

public struct CriticalSpring: Sendable, Equatable {         // critically damped, mass 1
    public var origin: CGFloat, target: CGFloat, initialVelocity: CGFloat
    public var stiffness: CGFloat = 100                      // ω = √stiffness = 10 /s; calibrate vs native
    public init(origin: CGFloat, target: CGFloat, initialVelocity: CGFloat = 0, stiffness: CGFloat = 100)
    public var omega: CGFloat { get }
    public func position(at t: TimeInterval) -> CGFloat     // target + (A + Bt)e^{−ωt}, A = x₀−target, B = v₀+ωA
    public func velocity(at t: TimeInterval) -> CGFloat     // (B − ω(A + Bt))e^{−ωt}
    public func isSettled(at t: TimeInterval, thresholds: RestThresholds = .init()) -> Bool
    /// Smallest t with |x−target| < distance and |v| < velocity: analytic bound (ln(|A|+|B|/ω)−ln(tol))/ω + 1/ω,
    /// refined by bisection on the closed form (≤ 40 iterations). Not integration.
    public func settlingTime(thresholds: RestThresholds = .init()) -> TimeInterval
}

public struct RubberBand: Sendable, Equatable {
    public var coefficient: CGFloat = 0.55                   // c
    public var dimension: CGFloat                            // d = viewport length on the axis
    public init(dimension: CGFloat, coefficient: CGFloat = 0.55)
    /// f(x) = (1 − 1/(|x|c/d + 1))·d · sign(x). Monotonic, |f| < d. d ≤ 0 → 0.
    public func displacement(forOverscroll x: CGFloat) -> CGFloat
    /// x = |f|·d / (c(d − |f|)) · sign(f). |f| is clamped to d(1 − 1e-6) first (asymptote guard).
    public func overscroll(forDisplacement f: CGFloat) -> CGFloat
}

public struct AxisInsets: Sendable, Equatable { public var start: CGFloat, end: CGFloat; public var total: CGFloat { get } }

public struct AxisBounds: Sendable, Equatable {
    public var min: CGFloat, max: CGFloat
    /// min = −insets.start; max = Swift.max(min, contentLength + insets.end − viewportLength). contentLength is zoomed.
    public init(contentLength: CGFloat, viewportLength: CGFloat, insets: AxisInsets)
    public init(min: CGFloat, max: CGFloat)                  // normalizes max ≥ min
    public var isScrollable: Bool { get }                    // max > min
    public func clamped(_ x: CGFloat) -> CGFloat
    public func overscroll(of x: CGFloat) -> CGFloat         // 0 inside, <0 before min, >0 past max
    public func nearestEdge(to x: CGFloat) -> CGFloat
}

public struct AxisGeometry: Sendable, Equatable {            // everything the solvers need for one axis
    public var viewportLength: CGFloat, unscaledContentLength: CGFloat, insets: AxisInsets
    public var alignment: CGFloat                            // 0 leading, 0.5 center, 1 trailing (UnitPoint component)
    public func contentLength(at scale: CGFloat) -> CGFloat  // unscaled × scale
    public func bounds(at scale: CGFloat) -> AxisBounds
    /// Alignment padding when the content fits: max(0, viewport − insets.total − content·s) × alignment, else 0.
    public func alignmentPadding(at scale: CGFloat) -> CGFloat
    public var visibleCenter: CGFloat { get }                // insets.start + (viewport − insets.total)/2, viewport coords
}
```

## 4. Bounce, targets, paging, fling, axis motion

```swift
public enum BounceBehavior: Sendable, Hashable { case automatic, always, basedOnSize }   // cases of ScrollBounceBehavior (16.4)
// Converts to ScrollBounceBehavior only: SwiftUI's type is opaque and not Equatable, so `.scrollBounceBehavior(_:axes:)`
// cannot be read back without reflection → the SwiftUI layer offers `ztronScrollBounceBehavior(_:axes:)` (own env key).

public struct BounceConfiguration: Sendable, Equatable {
    public var behavior: BounceBehavior = .automatic
    public var bounces: Bool = true                 // UIScrollView.bounces (false wins over everything)
    public var alwaysBounce: Bool = false           // alwaysBounceVertical/Horizontal
    /// bounces == false → false; .always → true; .basedOnSize → isScrollable || alwaysBounce;
    /// .automatic → isAxisEnabled || alwaysBounce (native: a vertical ScrollView bounces vertically even when content fits).
    public func resolve(isAxisEnabled: Bool, isScrollable: Bool) -> Bool
}

public struct FlingAcceleration: Sendable, Equatable {
    public var maximumVelocity: CGFloat = 12_000     // pt/s cap (calibrate vs native)
    public var carryFactor: CGFloat = 1.0            // fraction of remaining momentum carried
    public var maximumCatchDuration: TimeInterval = 0.30   // touch-down → lift must be quicker than this
    /// v = release + carryFactor·remaining if same sign and the touch was quick, else release; clamped to ±maximumVelocity.
    public func combine(release: CGFloat, remainingAtCatch: CGFloat, touchDuration: TimeInterval) -> CGFloat
}

public enum PagingSolver {
    /// Page length = viewport. At most one page away from the page containing `dragStart`; direction from velocity
    /// (|v| > flickVelocity) else from displacement > half page; snapped to the nearest page boundary, clamped to bounds.
    public static func target(current: CGFloat, dragStart: CGFloat, velocity: CGFloat, pageLength: CGFloat,
                              bounds: AxisBounds, flickVelocity: CGFloat = 300) -> CGFloat
}

public enum TargetSnapping {
    /// Nearest candidate to the natural decay rest point (ties → in the direction of travel); nil when no candidates.
    public static func nearest(to projected: CGFloat, candidates: [CGFloat], direction: CGFloat) -> CGFloat?
    public static func projectedRest(origin: CGFloat, velocity: CGFloat, rate: DecelerationRate) -> CGFloat
}

public enum AxisMotion: Sendable, Equatable {
    case rest(position: CGFloat)
    case decay(Decay, start: TimeInterval, handoff: EdgeHandoff?)   // crossing precomputed at release
    case spring(CriticalSpring, start: TimeInterval)
    public struct EdgeHandoff: Sendable, Equatable {
        public var crossingTime: TimeInterval        // absolute; decay.time(toReach: edge) + start
        public var edge: CGFloat
        public var bounces: Bool                     // false → .rest(edge) at crossing (stop at edge)
    }
    public struct Sample: Sendable, Equatable { public var position: CGFloat, velocity: CGFloat, isSettled: Bool }
    /// Pure sampler: before `crossingTime` → decay; at/after it → spring(origin: edge, target: edge,
    /// initialVelocity: decay.velocity(at: tc)) started at tc, or rest(edge) without bounce. Settled ⇒ exact target.
    public func sample(at time: TimeInterval, thresholds: RestThresholds = .init()) -> Sample
    public var endPosition: CGFloat { get }
}

public struct ReleaseContext: Sendable, Equatable {
    public var origin: CGFloat, velocity: CGFloat        // pt, pt/s at lift (after fling combination)
    public var bounds: AxisBounds, rate: DecelerationRate
    public var bounces: Bool, thresholds: RestThresholds
    public var target: CGFloat?                          // resolved by scroll-target behavior / delegate (nil = natural)
}

public enum ReleaseSolver {
    /// S6 order: out of bounds → spring to nearest edge seeded with v (decelerating); target given → retargeted decay or
    /// targetSpring; natural → decay with EdgeHandoff if rest point exits bounds. "|v| negligible" means
    /// |v| < thresholds.negligibleReleaseVelocity (20 pt/s) on both paths → rest (pixel-snapped later).
    public static func resolve(_ ctx: ReleaseContext, at time: TimeInterval) -> AxisMotion
    /// Target-path spring fallback, seeded with v₀ but never past the target (snap/page boundary): toward the target
    /// ω = max(10, |v₀/Δ|) → B = v₀ − ωΔ is 0 or has A's sign → monotone approach, no overshoot (B = 0 is the
    /// exponential with the too-strong rate r′ < 0.98). Away from the target / Δ = 0: ω = 10, never crosses the target;
    /// without bounce |v₀| is cut (bisection) until the excursion E = (|B|/ω)e^{ω|A|/|B| − 1} − |A| fits the room to the edge.
    static func targetSpring(origin: CGFloat, target: CGFloat, velocity: CGFloat, bounds: AxisBounds, bounces: Bool) -> CriticalSpring
    /// Programmatic `animated:` path (~0.3 s UIKit-like): spring with stiffness tuned so settlingTime ≈ duration;
    /// retargeting carries the current velocity (S6 "retargeting preserves velocity").
    public static func animated(from: CGFloat, velocity: CGFloat, to: CGFloat, duration: TimeInterval, at time: TimeInterval) -> AxisMotion
}
```

## 5. Zoom solver

```swift
public enum ZoomBound: Sendable, Equatable { case absolute(CGFloat), fit, fill }

public struct ZoomLimits: Sendable, Equatable {
    public var min: ZoomBound = .absolute(1), max: ZoomBound = .absolute(1)   // UIKit default 1…1 → zoom disabled
    /// fit = Swift.min(vw/cw, vh/ch), fill = Swift.max(…) with the inset-adjusted viewport; recomputed on every resize.
    /// Result normalized so lower ≤ upper; non-finite or ≤ 0 → 1.
    public func resolve(unscaledContentSize: CGSize, viewportSize: CGSize, insets: (x: AxisInsets, y: AxisInsets)) -> ClosedRange<CGFloat>
    public static func isZoomEnabled(_ r: ClosedRange<CGFloat>) -> Bool    // upper > lower
}

public struct ZoomGeometry: Sendable, Equatable {            // 2D view over two AxisGeometry
    public var x: AxisGeometry, y: AxisGeometry
    public func bounds(at scale: CGFloat) -> (x: AxisBounds, y: AxisBounds)
    public func alignmentPadding(at scale: CGFloat) -> CGPoint
    public var visibleCenter: CGPoint { get }
}

public enum ZoomSolver {
    /// Unscaled content point under viewport point p: u = (offset + p − pad(s)) / s.
    public static func contentPoint(under p: CGPoint, offset: CGPoint, scale: CGFloat, geometry: ZoomGeometry) -> CGPoint
    /// Offset that keeps u under p at scale s′: pad(s′) + s′u − p. `clamped` applies bounds(s′).
    public static func offset(keeping u: CGPoint, under p: CGPoint, scale: CGFloat, geometry: ZoomGeometry, clamped: Bool) -> CGPoint
    /// Live pinch: anchor u at gesture start, re-derive each frame from the current centroid (two-finger pan included).
    public static func pinch(anchor u: CGPoint, centroid: CGPoint, scale: CGFloat, geometry: ZoomGeometry) -> CGPoint
    /// Log-space resistance past the limits: e = ln(raw/L) (L nearest limit), shown = L·exp(RubberBand(dimension: logDimension).displacement(e)).
    public static func resisted(rawScale: CGFloat, limits: ClosedRange<CGFloat>, logDimension: CGFloat = 1.0) -> CGFloat
    /// Bounce-back after release past a limit: zoom follows a CriticalSpring in log space from ln(s₀) to ln(L) (no momentum),
    /// offset = pinch(anchor: u_lastCentroid, …) each frame, minus an overscroll residual that decays with its own spring.
    public static func bounceBack(from scale: CGFloat, limits: ClosedRange<CGFloat>, lastCentroid: CGPoint,
                                  offset: CGPoint, geometry: ZoomGeometry, at time: TimeInterval) -> ZoomMotion
    /// setZoomScale: anchor at the visible center (u under geometry.visibleCenter), clamp to limits and bounds.
    public static func zoom(to scale: CGFloat, anchoredAtVisibleCenterOf offset: CGPoint, currentScale: CGFloat,
                            limits: ClosedRange<CGFloat>, geometry: ZoomGeometry) -> (scale: CGFloat, offset: CGPoint)
    /// zoom(to rect): s′ = clamp(min(vw/rect.w, vh/rect.h)) with the inset-adjusted viewport, then center rect.mid.
    public static func zoom(toFit rect: CGRect, limits: ClosedRange<CGFloat>, geometry: ZoomGeometry) -> (scale: CGFloat, offset: CGPoint)
    /// S7 resize: keep the content point that was at the old visible center at the new visible center.
    public static func offset(preservingVisibleCenterFrom old: ZoomGeometry, offset: CGPoint, scale: CGFloat,
                              to new: ZoomGeometry, newScale: CGFloat) -> CGPoint
}

public struct ZoomMotion: Sendable, Equatable {              // sampled by the clock like AxisMotion
    public var logScale: CriticalSpring, start: TimeInterval
    public var anchor: CGPoint, centroid: CGPoint, residual: (x: CriticalSpring, y: CriticalSpring)
    public var endScale: CGFloat                             // the limit itself (exp(ln L) may differ by an ulp)
    public func sample(at time: TimeInterval, geometry: ZoomGeometry, thresholds: RestThresholds) -> (scale: CGFloat, offset: CGPoint, isSettled: Bool)
    public func settlingTime(geometry: ZoomGeometry, thresholds: RestThresholds) -> TimeInterval   // elapsed, s
}
```
Zoom settling is judged on visible content: content point u′ shows at p = s(u′ − u) + centroid + residual, so the scroll
position cancels and a log error δ moves visible content by < δ·extent per axis (extent = larger viewport length). The log
spring settles with thresholds / extent; the final snap moves visible content < `distance` per axis. The zoomed-coordinate
offset may jump by δ·s·u (≈ 4 pt at offset 9000), compensated by the simultaneous scale snap; judging settling on the offset
would lengthen every bounce by ~ln(s·u/extent)/ω with hit-testing disabled, for no visible change.
Accuracy: with the true centroid (18+) the focal error is rounding only (≤ 0.5 pt after pixel snap). On 15–17 the centroid is
estimated from the pan location (single-finger drag) and the pinch's start location; document ≤ a few pt of drift.

## 6. Availability scaffolding (`Sources/ZTronScrollView/Availability/`)

```swift
public enum ZTronCapability: String, CaseIterable, Sendable, Hashable {  // one case per SPEC S3 row (SDK-verified)
    case perPropertyObservation   // @Observable                      iOS 17
    case layoutProtocol           // Layout                           iOS 16
    case geometryChange           // onGeometryChange (back-deployed) iOS 16 — (newValue) overload only; (old, new) is iOS 18
    case visualEffect             // visualEffect                     iOS 17
    case spatialEvents            // SpatialEventGesture              iOS 18 API, used from 26 (D34)
    case magnifyGesture           // MagnifyGesture                   iOS 17
    case liveMagnifyCentroid      // centroid via SpatialEventGesture (API iOS 18, used from 26: D34)
    case gestureInputKinds        // GestureInputKinds (pointer/pencil) iOS 27 — iOS 27 SDK only: `#if compiler(>=6.4)`
    case nativeCurves             // Spring / UnitCurve               iOS 17
    case animationCompletion      // Transaction.addAnimationCompletion iOS 17
    case keyPathTransaction       // withTransaction(\.disablesAnimations, true) iOS 17
    case keyboardScrolling        // focusable + onKeyPress           iOS 17
    case accessibilityZoom        // accessibilityZoomAction          iOS 16
    case sensoryFeedback          // sensoryFeedback                  iOS 17
    case namedCoordinateSpace     // NamedCoordinateSpace             iOS 17
    case subviewContainers        // Group(subviews:), ContainerValues iOS 18
    case scrollBounceBehaviorType // ScrollBounceBehavior iOS 16.4 — BounceBehavior → ScrollBounceBehavior only
    case frameClock               // TimelineView(.animation)         iOS 15 (no fallback; always available)
    public var minimumOS: (major: Int, minor: Int) { get }
    public var hasFallback: Bool { get }                   // false for frameClock, gestureInputKinds (fallback = "—")
    public var isInBuildSDK: Bool { get }                  // false only for SDK-27 APIs built with Xcode 26.x (compiler < 6.4)
}

public enum ZTronAvailability {
    /// Runtime `#available` for the case (switch with a literal `#available` per case) AND not force-fallbacked.
    public static func isAvailable(_ capability: ZTronCapability) -> Bool
    /// Call sites still need the literal check for type-checking:
    /// `if ZTronAvailability.isAvailable(.visualEffect), #available(iOS 17, *) { … } else { fallback }`.
    public static func forceFallback(_ capability: ZTronCapability, _ on: Bool)   // no-op outside DEBUG
    public static func forceAllFallbacks(_ on: Bool)
    public static var forcedFallbacks: Set<ZTronCapability> { get }
    static func replaceForcedFallbacks(with: Set<ZTronCapability>)   // one locked write (test helper's install)
}
// APIs newer than the Xcode 26 SDK (D3): `#available` does not hide symbols from the type checker, so every call site
// of an iOS 27-only API is wrapped in `#if compiler(>=6.4)` + `#available(iOS 27, *)`, fallback in both `#else`
// branches; `osSupports` reports false when compiled out. Reviews reject iOS 27+ symbols outside such a block.
// minimumOS is checked by hand against the SDK swiftinterfaces; the runtime test only discriminates boundaries ≤ the
// running OS (run it on 17.5, 18.x, 26.x, 27.0). An SDK grep script (anchor symbol + `@available` line per capability)
// is still to be added to scripts/ for M-end verification.
// Storage: `final class ForcedFallbackStore: @unchecked Sendable` holding `NSLock` + `Set<ZTronCapability>`, a single
// process-wide instance (`nonisolated(unsafe)`-free; the lock makes it Sendable). Compiled only `#if DEBUG`; the public
// functions exist in release as inert no-ops so the demo's OS-path switch and tests compile unchanged. Not `Mutex`
// (iOS 18) nor `OSAllocatedUnfairLock` (iOS 16): iOS 15 + Swift 6.0 toolchain.
```
Demo: a "Force fallbacks" toggle in the demo settings calls `forceAllFallbacks` and re-creates the view hierarchy (`.id`
on the demo root only, never on content). Tests on simulators ≥ 17 therefore cover every fallback path on this Mac.

**Swift Testing on both paths.** Test support target `ZTronScrollViewTests/Support/OSPath.swift`:
```swift
enum OSPath: CaseIterable, Sendable { case preferred, forcedFallback }
@MainActor func withOSPath<T>(_ path: OSPath, _ body: () throws -> T) rethrows -> T   // installs path's set atomically
// async overload: process-wide FIFO gate; nested calls are recognized by a task-local scope token that must still be
// active (a task outliving its scope acquires the gate normally). Suites reading ZTronAvailability are @MainActor and
// read it only inside withOSPath; no concurrent scopes inside one scope (reported as a test issue).
@Suite(.serialized) struct SomeSuite { @Test(arguments: OSPath.allCases) func x(path: OSPath) async throws { try await withOSPath(path) { … } } }
```
Suites that touch the switch are `.serialized` (process-wide state). Physics-package suites are OS-independent and run
once; main-package suites (availability, layout, readers, callbacks) are parameterized over `OSPath.allCases`.

## 7. Test list (Swift Testing; physics in `Packages/ZTronScrollPhysics/Tests`, scaffolding in `Tests/ZTronScrollViewTests`)

**DecayTests** · `positionMatchesClosedForm` (x(t) vs formula at t = 0, 0.1, 1) · `restPointEqualsFormula` · `velocityDecays`
(monotone |v|, v(0) = v₀) · `zeroVelocityStaysAtOrigin` · `timeToReachInvertsPosition` (round-trip, nil beyond rest / wrong side)
· `durationEndsBelowThresholds` · `nonFiniteInputsAreZeroed` · `rateOutsideOpenIntervalIsClamped` (r ≥ 1, r ≤ 0) ·
`fastRateStopsSooner` · `pointsPerMillisecondConversion`.

**RetargetTests** · `retargetedDecayLandsExactly` (|rest − target| < 1e-6 for Δ ∈ {−800, −1, 1, 800} and v₀ matching sign) ·
`retargetNilWhenDirectionDisagrees` · `retargetNilWhenDeltaZero` · `retargetNilWhenVelocityNegligible` ·
`retargetNilWhenRateImplausible` (tiny Δ with large v₀, huge Δ with tiny v₀) · `releaseSolverUsesSpringWhenRetargetNil`
(ends exactly on target, seeded velocity continuous).

**SpringTests** · `startsAtOriginWithInitialVelocity` · `settlesAtTarget` (|x(T) − target| < 0.5, |v(T)| < 4) ·
`criticallyDampedNoOvershootWithoutVelocity` · `overshootsThenReturnsWithVelocity` (bounce shape) · `settlingTimeBracketsClosedForm`
· `stiffnessScalesSettlingTime` · `sampleAfterSettlingIsExactTarget`.

**RubberBandTests** · `monotonicIncreasing` (x grid 0…10d) · `alwaysBelowDimension` · `inverseRoundTrips` (|x − inv(f(x))| < 1e-6)
· `oddSymmetry` (f(−x) = −f(x)) · `zeroDimensionIsZero` · `inverseClampsNearAsymptote` · `slopeAtZeroIsCoefficient` (f′(0) = c).

**BoundsTests** · `minIsNegativeStartInset` · `maxUsesEndInsetAndViewport` · `maxNeverBelowMin` (content smaller than viewport)
· `clampAndOverscrollSign` · `tinyViewportBounds` (viewport 0 / 1 pt) · `alignmentPaddingOnlyWhenContentFits` ·
`boundsScaleWithZoom`.

**BounceResolutionTests** · one test per (behavior × bounces × alwaysBounce × isScrollable × isAxisEnabled) via a parameterized
truth table (`@Test(arguments:)`), incl. `bouncesFalseWinsOverAlways` and `automaticBouncesOnEnabledAxisEvenWhenContentFits`.

**EdgeHandoffTests** · `decayCrossingTimeMatchesPosition` · `handoffSpringStartsAtEdgeWithDecayVelocity` (C¹ continuity at tc) ·
`noBounceStopsAtEdge` · `bounceReturnsToEdge` (these four in both directions: max edge with v > 0, min edge with v < 0) ·
`restInsideBoundsHasNoHandoff` · `releaseOutOfBoundsSpringsBack` (seeded with v, `isDecelerating` semantics flagged in context).

**TargetSpringTests** · `towardTargetSpringIsTheSoftestWithoutOvershoot` · `targetSpringNeverExitsBoundsWithoutBounce`
(randomized, dense sampling + analytic peak) · `awayFromTargetWithoutBounceMeetsTheWall` · `pagingTargetIsNeverOvershot`.

**AbsoluteClockTests** · `decayAndSpringSettleAtStartPlusSettlingTime` · `handoffBounceSettlesAtCrossingPlusSettlingTime` ·
`zoomBounceSettlesAtStartPlusSettlingTime` (uptime ~1.2e5 s, reference-date ~8.1e8 s, Unix ~1.76e9 s starts).
**ModuleTests** · `moduleQualifiedNamesResolve` (`ZTronScrollPhysics.Decay` compiles).

**VelocityTrackerTests** · `constantMotionGivesExactVelocity` · `pauseBeforeLiftGivesZero` (samples, 70 ms gap, lift) ·
`jitterWithinRestDistanceGivesZero` · `ignoresSamplesOutsideWindow` · `singleLateEventDoesNotDominate` (one outlier) ·
`irregularTimestampsStillFit` (60/120 Hz mixes) · `nonMonotonicTimeIgnored` · `fewerThanTwoSamplesGivesZero` · `pointTrackerAxesIndependent`.

**PagingAndTargetTests** · `pagingAtMostOnePage` (huge fling) · `pagingDirectionFromVelocity` · `pagingDirectionFromHalfPageDisplacement`
· `pagingSnapsToNearestBoundaryAndClamps` · `nearestTargetTieBreaksTowardTravel` · `projectedRestMatchesDecay` · `zeroPageLengthIsClamp`.

**FlingTests** · `sameDirectionQuickFlingCarriesMomentum` · `oppositeDirectionDoesNotCarry` · `slowTouchDoesNotCarry` · `capApplies`.

**RestAndSnapTests** · `pixelSnapAt2xAnd3x` · `snapIgnoresNonPositiveScale` · `motionSettledReportsExactEnd` ·
`negligibleReleaseRests` · `naturalReleaseUsesNegligibleVelocityBoundary` (19 pt/s rests, 21 pt/s decays).

**ZoomSolverTests** · `focalPointInvariance` (random p, s → s′: content point under p unchanged, incl. insets and center/leading
alignment; ≤ 1e-6 unclamped) · `twoFingerPanKeepsAnchor` · `limitsFitFillResolve` (recomputed per viewport) · `zoomEnabledIffMaxGreaterThanMin`
· `resistanceIsLogSymmetricAndBounded` · `bounceBackEndsAtNearestLimit` with anchor kept · `bounceBackFinalSnapIsInvisible`
(offsets up to 10 000 pt) · `setZoomScaleAnchorsVisibleCenter` ·
`zoomToRectFitsAndCenters` · `resizePreservesVisibleCenter` (S7, rotation 390×844 ↔ 844×390 at s = 1 and fit) · `degenerateContentSizeGuards`.

**Scaffolding (main package, parameterized over OSPath, `.serialized`)** · `AvailabilityTests.osSupportsAgreesWithMinimumOS`
(each case vs the literal `#available` result on the running OS; not an SDK check) · `forcedFallbackDisablesCapability` ·
`forceAllThenClearRestoresPreferred` · `frameClockIsNeverFallbacked` · `capabilitiesWithoutFallbackReportIt` ·
`onlySDK27CapabilitiesCanBeCompiledOut` · `replaceForcedFallbacksSwapsTheWholeSet` · `osPathHelperIsBalanced` (nested
`withOSPath` restores the previous set) · `outlivingTaskDoesNotBypassTheGate` · `smokePackageLinks` (existing).
