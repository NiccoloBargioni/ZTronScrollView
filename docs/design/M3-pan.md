# M3 · Pan, release, catch, delegate, pager arbitration (design)

Scope: SPEC S6 (Pan, Release, Touch during motion, Paging), S11 delegate/phase order, S12 (pan + "Inside a pager"), S16 rules.
Zoom (pinch) is M4; scroll target behaviors are M6 (a hook is reserved here). Reads: M2-s2/s3 handoffs, MC-contract §6.
All names follow CLAUDE.md (ZTronScroll…). New code lives in `Sources/ZTronScrollView/Gesture/` unless stated.

## 1. Architecture (data flow)

```
SwiftUI viewport (ScrollContainer)                 view-free, unit-testable                 ZTronScrollState (main actor)
 CatchObserver (Spatial 18+ / Drag(min 0))  ─┐
 Pan DragGesture(minimumDistance: 10)        ├─► PanEvent ─► PanSession.handle(_:env:) ─► [PanEffect] ─► PanCoordinator.apply ─► write offset / delegate / phase
 FrameClockDriver tick                       ┘                                                     │                       └─► ReleasePipeline ─► AxisMotion ×2 ─► beginDeceleration
 ArbitrationParticipant (env arbiter)  ◄──── decide closure ◄───────────────────────────────────────┘
```

- `PanSession` is a pure `struct` state machine: fed gesture values and frame timestamps, returns effects. No SwiftUI, no state object, no clock. Tests drive it with synthetic samples.
- `PanCoordinator` (final class, `@MainActor`, owned by `ScrollContainer` through a `@StateObject` holder next to `StateHolder`) owns one `PanSession`, the `PointVelocityTracker`, the `ArbitrationParticipant`, and applies effects to `ZTronScrollState`. It is the only object that touches both sides.
- `PanGestureAdapter: ViewModifier` is the thin SwiftUI layer: builds the gestures, converts `DragGesture.Value`/`SpatialEventCollection` into `PanEvent`s, forwards to the coordinator. ~80 lines, no logic.
- Offsets written during a drag are render-time transforms only (S4): `state.writeBoth(offset:zoom:)` inside `unanimated { }`, never a content body re-evaluation.

## 2. Types and signatures

```swift
// Gesture/PanSession.swift (internal, Equatable, Sendable)
enum PanEvent: Equatable {
    case touchDown(location: CGPoint, time: TimeInterval, touchCount: Int)   // observer; may be missing on ≤17 for fast swipes
    case dragChanged(translation: CGSize, startLocation: CGPoint, time: TimeInterval)   // pan DragGesture, recognized (≥10 pt)
    case dragEnded(translation: CGSize, time: TimeInterval, fallbackVelocity: CGVector?) // velocity: DragGesture.Value.velocity on 17+
    case touchesEnded(time: TimeInterval)   // last finger up (observer); ends an `.ignored` sequence
    case frame(time: TimeInterval)          // clock tick while a finger is down
    case cancelled                          // gesture cancelled by the system / view disappeared
}
struct PanEnvironment: Equatable {          // snapshot taken by the coordinator before each event (cold values)
    var axes: Axis.Set; var isScrollEnabled: Bool; var isDirectionalLockEnabled: Bool
    var presentationOffset: CGPoint                      // only read at touchDown / recognition
    var boundsX: AxisBounds, boundsY: AxisBounds          // AxisGeometry.bounds(at: zoom), insets included
    var bouncesX: Bool, bouncesY: Bool                    // BounceConfiguration.resolve(...) per axis (§4)
    var viewport: CGSize                                 // RubberBand dimension per axis
    var isMovingWithoutFinger: Bool                      // state.motion != nil || transaction running, and not tracking
    var hasArbiter: Bool
}
enum PanEffect: Equatable {
    case catchMotion                                     // touchDown while moving: state.interrupt() (target := presentation)
    case beginTracking                                   // phase .tracking, isTracking = true (deferred when hasArbiter, §7)
    case askOwner(start: CGPoint, translation: CGSize, touchCount: Int)  // coordinator calls arbiter, then feeds `.decided(owner)`
    case beginDragging                                   // willBeginDragging, phase .interacting, isDragging = true
    case setOffset(CGPoint)                              // presentation + target write, unanimated; didScroll coalesced per frame
    case release(ReleaseRequest)                         // → ReleasePipeline
    case endSequence                                     // isTracking = false; `.ignored` sequences end here with no other effect
}
struct ReleaseRequest: Equatable { var origin: CGPoint; var dragStart: CGPoint; var liftTime: TimeInterval; var fallbackVelocity: CGVector? }

struct PanSession: Equatable {
    enum Phase: Equatable { case idle, touching(down: TimeInterval, caught: Bool), awaitingDecision(Pending), ignored, dragging(Drag), released }
    struct Drag: Equatable { var baseline: CGPoint; var lock: Axis?; var dragStart: CGPoint; var caughtAt: TimeInterval?; var caughtVelocity: CGVector }
    var phase: Phase = .idle
    var rubberBand: (coefficient: CGFloat) = 0.55
    mutating func handle(_ event: PanEvent, env: PanEnvironment) -> [PanEffect]
    mutating func decided(_ owner: ScrollOwner, env: PanEnvironment) -> [PanEffect]   // .participant → beginTracking?+beginDragging+setOffset; .container → phase = .ignored, []
    static func offset(baseline: CGPoint, translation: CGSize, lock: Axis?, env: PanEnvironment) -> CGPoint   // §3 formula, pure
    static func baseline(presentation: CGPoint, translation: CGSize, env: PanEnvironment) -> CGPoint           // inverse rubber band
}
```

```swift
// Gesture/ReleasePipeline.swift (internal, pure except the delegate call made by the coordinator)
struct ReleaseInput { var origin: CGFloat; var dragStart: CGFloat; var velocity: CGFloat /* pt/s */; var bounds: AxisBounds
                      var bounces: Bool; var rate: DecelerationRate; var pageLength: CGFloat?; var thresholds: RestThresholds }
enum ReleasePipeline {
    static func velocity(tracker: VelocityTracker, liftTime: TimeInterval, fallback: CGFloat?) -> CGFloat   // tracker if count ≥ 2 else fallback ?? 0
    static func accelerated(_ v: CGFloat, caughtVelocity: CGFloat, caughtAt: TimeInterval?, liftTime: TimeInterval, _ f: FlingAcceleration) -> CGFloat
    static func proposedTarget(_ i: ReleaseInput) -> CGFloat?          // paging → PagingSolver.target(...); else nil (M6 hook: ZTronScrollTargetBehavior)
    static func motion(_ i: ReleaseInput, target: CGFloat?, at t: TimeInterval) -> AxisMotion   // ReleaseSolver.resolve(ReleaseContext(...), at: t)
}
// Gesture/PanCoordinator.swift
@MainActor final class PanCoordinator: ObservableObject {
    init(state: ZTronScrollState, axes: Axis.Set)
    var settings: PanSettings                       // env + UIKit knobs merged by the adapter (cold)
    func handle(_ event: PanEvent)                  // snapshot env → session.handle → apply effects
    var participant: ArbitrationParticipant?        // §7; nil without an arbiter
    #if DEBUG var effectsLog: [PanEffect] #endif    // tests assert delegate/phase order against it
}
struct PanSettings: Equatable { var isScrollEnabled = true; var isDirectionalLockEnabled = false; var isPagingEnabled = false
    var decelerationRate: DecelerationRate = .normal; var bounce = (x: BounceConfiguration(), y: BounceConfiguration())
    var fling = FlingAcceleration(); var hysteresis: CGFloat = 10; var displayScale: CGFloat = 2 }
```

```swift
// State additions (Sources/ZTronScrollView/State/ZTronScrollState.swift, ScrollStateTypes.swift)
public var isTracking: Bool { get }; public var isDragging: Bool { get }; public var isDecelerating: Bool { get }  // cold channel `.flags`
public var isPagingEnabled: Bool; public var bounces: Bool; public var alwaysBounceVertical: Bool; public var alwaysBounceHorizontal: Bool
public var isDirectionalLockEnabled: Bool; public var decelerationRate: ZTronDecelerationRate /* .normal/.fast → physics DecelerationRate */
public var isScrollEnabled: Bool                 // UIKit knob; AND-ed with the environment (§4)
func beginDeceleration(x: AxisMotion, y: AxisMotion, at t: TimeInterval)   // ClockMotion(kind: .deceleration); target = endPosition; phase .decelerating
func beginTracking(); func endTracking()         // flags + phase .tracking/.idle, no delegate
func writeDragOffset(_ p: CGPoint)               // presentation + target, unanimated, marks didScroll pending
private enum MotionKind { case animation, deceleration }   // ClockMotion gains `kind`; settle → didEndDecelerating vs didEndScrollingAnimation

public protocol ZTronScrollViewDelegate: AnyObject {    // all optional via extension defaults; complete S11 list
    func scrollViewDidScroll(_ s: ZTronScrollState); func scrollViewWillBeginDragging(_ s: ZTronScrollState)
    func scrollViewWillEndDragging(_ s: ZTronScrollState, withVelocity v: CGPoint /* pt/ms */, targetContentOffset: inout CGPoint)
    func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate: Bool); func scrollViewWillBeginDecelerating(_ s: ZTronScrollState)
    func scrollViewDidEndDecelerating(_ s: ZTronScrollState); func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState)
    func scrollViewWillBeginZooming(_ s: ZTronScrollState); func scrollViewDidZoom(_ s: ZTronScrollState); func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale: CGFloat)
    func scrollViewShouldScrollToTop(_ s: ZTronScrollState) -> Bool; func scrollViewDidScrollToTop(_ s: ZTronScrollState)
    func scrollViewDidChangeAdjustedContentInset(_ s: ZTronScrollState)
}
// Public phase reader (unblocks M2's `phaseReaderOnTransitionsOnly`): re-renders only on phase transitions, both storage paths.
public struct ZTronScrollPhaseReader<Content: View>: View {
    public init(_ state: ZTronScrollState? = nil, @ViewBuilder content: @escaping (ZTronScrollPhase) -> Content)
}
```

## 3. Pan formulas and state machine

- Hysteresis = `DragGesture(minimumDistance: 10)`: the first `dragChanged` is the recognition sample (translation ≥ 10 pt, well-conditioned for S16 rule 1; MC note B concerns the container's early sample, not ours).
- **Baseline** at recognition, per axis, with `b = env.bounds`, `rb = RubberBand(dimension: viewport length)`, `p = presentation`:
  `raw0 = p` if `p ∈ [b.min, b.max]`; else `edge = b.nearestEdge(p)`, `raw0 = edge + sign(p − edge) · rb.overscroll(forDisplacement: |p − edge|)` (inverse, catching mid-bounce);
  `baseline = raw0 + translation0` (so `offset(translation0) == p`: no jump).
- **Offset** per axis: `raw = baseline − translation`; if the axis is not in `axes`, is locked out, or `!isScrollEnabled`: `offset = p` (unchanged); else
  `offset = b.clamped(raw) + (bounces ? sign(o) · rb.displacement(forOverscroll: |o|) : 0)`, `o = b.overscroll(of: raw)`. Never accumulate deltas.
- **Directional lock** (`isDirectionalLockEnabled`, both axes enabled): at recognition `lock = |dx| ≥ 2|dy| ? .horizontal : |dy| ≥ 2|dx| ? .vertical : nil` (diagonal start → free, UIKit-like); fixed for the gesture.
- **Session transitions:** idle →(touchDown)→ touching(caught = env.isMovingWithoutFinger → effect `.catchMotion`; `.beginTracking` only if `!hasArbiter`) →(dragChanged)→ `hasArbiter ? awaitingDecision(.askOwner) : dragging` →(decided .participant)→ dragging (`beginTracking` if deferred, `beginDragging`, `setOffset`) | (decided .container) → ignored (drops every event until `touchesEnded`/`dragEnded` → `.endSequence`). dragging →(dragChanged)→ `.setOffset`; →(dragEnded)→ released (`.release`) → idle on `touchesEnded`/next frame. touching →(dragEnded without drag, i.e. tap)→ `.endSequence`. `.cancelled` from dragging behaves as a lift with velocity 0. A `dragChanged` without a prior `touchDown` (≤17 observer missed) synthesizes `touchDown` first.
- **Velocity samples:** the coordinator adds `(location = startLocation + translation, time = value.time)` to `PointVelocityTracker` on each `dragChanged`; `frame` events add nothing but flush `didScroll`. `VelocityTracker.restTimeout` (64 ms) yields ≈ 0 after a rest; `restDistance` 1 pt. Fallback `DragGesture.Value.velocity` (17+) only when `count < 2`.

## 4. Axes, enablement, bounce, bounds

- `isScrollEnabled = state.isScrollEnabled && env` where env = `\.isScrollEnabled` (16+, set by `.scrollDisabled`) AND our own `\.ztronScrollIsEnabled` (15+; `ztronScrollDisabled(_:)` writes both when available). Disabled: no tracking, no delegate; taps still reach content.
- Bounce per axis: `BounceConfiguration(behavior:, bounces: state.bounces, alwaysBounce: state.alwaysBounce{Vertical,Horizontal})`; `behavior` from `\.verticalScrollBounceBehavior`/`\.horizontalScrollBounceBehavior` (16.4+) mapped 1:1 onto `BounceBehavior`, else our `\.ztronScrollBounceBehavior` (default `.automatic`). `bounces = cfg.resolve(isAxisEnabled: axes.contains(axis), isScrollable: bounds.isScrollable)`; `bounces == false` ⇒ hard clamp in §3 and `ReleaseContext.bounces = false`.
- Bounds: `AxisGeometry(viewportLength:, unscaledContentLength:, insets: metrics.contentInsets → AxisInsets, alignment: contentAlignment).bounds(at: zoom)`; computed into `PanEnvironment` on each event (cheap) — M2's unclamped offsets stay for programmatic writes (clamping of `setContentOffset` is M5/M6); only gesture-driven offsets are bounded here. `setViewport` still does not clamp (open until M5 insets).

## 5. Release pipeline (per axis, in order)

1. `v = ReleasePipeline.velocity(...)` (pt/s). 2. Fling acceleration: if `drag.caughtAt != nil` and `sign(v) == sign(caughtVelocity)`, `v = fling.combine(release: v, remainingAtCatch: caughtVelocity, touchDuration: liftTime − caughtAt)` (cap 12 000 pt/s; calibrate on device). `caughtVelocity` = the interrupted `AxisMotion.sample(at: catchTime).velocity`, captured by `interrupt()` and exposed as `state.lastInterruptedVelocity: CGVector`.
3. Target: `t = proposedTarget` (`isPagingEnabled` → `PagingSolver.target(current: origin, dragStart:, velocity: v, pageLength: viewport, bounds:)`, one page max; M6 will insert `ZTronScrollTargetBehavior.updateTarget` before this). `proposed = t ?? TargetSnapping.projectedRest(origin:, velocity: v, rate:)` clamped to bounds.
4. Delegate: `willEndDragging(withVelocity: v/1000, targetContentOffset: &proposed)` once for both axes; per axis `target = (proposed ≠ natural projected rest || t != nil) ? proposed : nil`.
5. `motion = ReleaseSolver.resolve(ReleaseContext(origin:, velocity: v, bounds:, rate:, bounces:, thresholds:, target:), at: liftTime)` — covers in-bounds decay, retargeted decay `r′`, spring fallback, edge hand-off, and out-of-bounds spring-back (which reports `willDecelerate == true`).
6. `willDecelerate = mx.willDecelerate || my.willDecelerate`. Call order: `didEndDragging(willDecelerate)`; if true → `state.beginDeceleration(x:y:at:)` → `willBeginDecelerating` → clock `step(to:)` samples both motions (existing `stepClockMotion`; `kind == .deceleration`) → `didScroll…` → settle → **pixel snap** `round(o · displayScale)/displayScale` (`\.displayScale` stored in `PanSettings`) → `didEndDecelerating`, phase `.idle`, `isDecelerating = false`. If false → snap immediately, phase `.idle`.
- `beginDeceleration` reuses `ClockMotion` (zoom nil); `targetOffset = (x.endPosition, y.endPosition)` so readers of the target channel see the destination once (TransformHost unaffected, S4).

## 6. Touch during motion

- `touchDown` with `isMovingWithoutFinger` → `.catchMotion` → `state.interrupt()` (already: target := presentation, motion nil, phase idle). Then `.beginTracking`. `didEndDecelerating`/`didEndScrollingAnimation` fire on interruption as UIKit does (UIKit fires didEndDecelerating when a touch stops deceleration).
- Content gate (rewritten in DBG-s3, `docs/progress/DBG-s3.md`; D34): `TransformHost` (already subscribed to `.phase`) asks `ContentGatePolicy.lock(phase:isTracking:isDragging:isEditingText:)` (pure, unit-tested) and applies the answer with `ContentGate` + `ContentShield` (leaf modifier changes and an overlay, not a content body evaluation: `content.body == 0` in the demo). The content takes no new touch while it moves without a finger (`phase ∈ {.decelerating, .animating} && !isTracking`, the resize watch's `.animating` included) or while a drag is recognized (`isDragging`); the catching touch therefore never reaches a content Button, and the viewport's simultaneous observer still sees it. Fallback risk: on ≤17 `DragGesture(minimumDistance: 0)` delivers its first value a few ms after touch-down; the gate is already closed because it depends on phase, not on the observer — fine.
  - **Means, not editing a text input:** new touches are blocked by `allowsHitTesting(false)` (reaches SwiftUI and UIKit-backed controls on every OS); `.disabled(true)` is used for a **recognized drag only**, because it is the one thing that ends a press that began under the finger (a pan that started on a Button must not fire it on lift) on every OS. A fling's deceleration, an animated scroll and a resize therefore no longer disable anything. (M3-s2 had `.disabled(blocked)` for all three.)
  - **Means, a text input is being edited** (`TextEditingMonitor`: UIKit's editing notifications by name, no UIKit symbol): `.disabled` and `allowsHitTesting(false)` both make UIKit resign the focused `UITextField` (measured 17.5 + 27.0 with the end-of-editing notification; the second lets SwiftUI give the focus back after the lock), so the gate uses the two levers that leave UIKit alone: the **shield** (a clear, hit-testable overlay with a tap gesture above the viewport: it takes the new touch; SwiftUI controls on every OS, UIKit-backed controls on iOS 27 only) and the **GestureMask `.none`** on the content (ends the press under the finger where SwiftUI honours it: Buttons on 17.5; **not on 27.0**, where a pan that began on a Button can still fire it on lift while a field is edited — a documented gap, SPEC S12).
  - Measured facts behind it (17.5 and 27.0, `docs/progress/DBG-s3.md`): hit-testing off blocks a Button, a Toggle and a TextField statically and dynamically; a catching touch needs nothing more; a Button pressed before the drag is not reached by hit-testing, the shield or a high-priority pan on either OS; `.disabled` reaches it everywhere; the mask only on 17.5.

## 7. Arbitration participant (S12 "Inside a pager", S16)

```swift
// Gesture/ArbitrationParticipant.swift
@MainActor final class ArbitrationParticipant: ScrollArbitrationParticipant {   // exact protocol per MC-contract §1 (frozen)
    init(arbiter: any ScrollArbiter, state: ZTronScrollState, coordinator: PanCoordinator)
    func register(frame: CGRect)   // on appear; frame in .named(arbiter.coordinateSpaceName), read by a cold GeometryReader/onGeometryChange
    func update(frame: CGRect)     // on frame change only (cold)
    func unregister()              // on disappear
    var canFollow: (FingerDirection) -> Bool   // screen direction → axis + sign; see below
    var isMovingWithoutFinger: Bool            // state motion/transaction active && !isTracking, OR caught this sequence and undecided (sticky until decided/lift)
    var isZoomEnabled: Bool                    // false in M3 (zoom range arrives in M4)
    func owner(start: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner   // start = frame.origin + startLocation
}
```
- `canFollow(d)`: finger right/down means content offset decreases: `axes.contains(axis) && isScrollEnabled && offset > bounds.min + 0.5`; finger left/up: `offset < bounds.max − 0.5`. Content that fits (`!bounds.isScrollable`) → false. Rubber band never counts as following. Directions are screen space; M3 assumes LTR (RTL mapping is an open question, S16 says it is ours).
- Pinches never ask (M4 keeps two-finger sequences out of `PanSession`: `touchCount ≥ 2` → no `.askOwner`, no pan).
- `.container` ⇒ `PanSession.ignored`: no baseline, no offset, no indicator flash, no delegate, no phase (tracking was deferred, §3). Decision once per sequence is the arbiter's cache; we ask exactly once (first `dragChanged`).
- iOS 18+: pan, observer (and M4 pinch) attached via the `name: scrollArbitrationGestureName` variants so the pager's UIKit pan runs alongside (spike Q1/Q2/Q5 green on 18.6/26.5/27.0; note D: nothing here depends on recognizer state).
- iOS ≤17 (note E): the participant behaves identically (ignores the sequence) but cannot cancel its SwiftUI DragGesture, so a UIKit paging pan fails. ZTronPages' EG-11/EG-13 fallback (SwiftUI-driven pan or its own observer outside the page) is the container's responsibility; we expose no extra API. Documented limitation; verified only as "participant leaves everything untouched" on 17.5.
- Without an arbiter in the environment: `participant == nil`, `hasArbiter == false`, nothing in this section runs (S16 "No arbiter").

## 8. Gesture composition (SwiftUI adapter) and S12 verification

- Attached to the viewport after `.contentShape(Rectangle())`: `.simultaneousGesture(observer)` then `.simultaneousGesture(pan)`, both with `name:` on 18+. Observer: `SpatialEventGesture(coordinateSpace: .local)` (18+) or `DragGesture(minimumDistance: 0, coordinateSpace: .local)`; pan: `DragGesture(minimumDistance: 10, coordinateSpace: .local)`. Rationale: the spike's `.simultaneousGesture` passed taps-fire/drag-from-button-doesn't on 18.6/26.5/27.0; `.gesture` lets a child drag starve the pan; `.highPriorityGesture` kills Buttons.
- Empirical switch: `PanGestureAdapter.Mode = .simultaneous | .gesture | .highPriority`, DEBUG launch arg `-ZTronPanGestureMode` in the demo, so the S12 checklist (Button tap/drag, Toggle, Slider horizontal vs vertical scroll, TextField, nested horizontal ScrollView, header buttons in M8, one-finger-lift in M4, offscreen content gets no touches) runs as UI tests per OS and the default is changed per OS behind `ZTronAvailability` if needed. `delaysContentTouches`/`canCancelContentTouches` are approximated by the hysteresis + hit-test gate; document the gap in the handoff.
- `didScroll` ≤ 1/frame: `writeDragOffset` sets `didScrollPending`; the clock runs while tracking (`isClockRunning = true` on `beginTracking`, no motion) and `step(to:)` flushes once per tick, also for clock-driven motion (one flush after `stepClockMotion`). Programmatic/transaction writes keep M2's path but go through the same pending flag.

## 9. Tests

Unit (`ZTronScrollViewTests`, both storage paths via `-ZTronForceAllFallbacks` where state is involved):
- PanSessionTests: recognition baseline no-jump (`offset(translation0) == presentation`); offset = baseline − translation, never accumulated (out-of-order translation samples); axes/isScrollEnabled/directional lock (diagonal → free, 2:1 → locked); rubber band apply and inverse continuity when catching mid-bounce (|Δ| < 1e-6 at recognition, both edges); no-bounce hard clamp; tap (touchDown→dragEnded) emits only endSequence; synthesized touchDown on ≤17 ordering.
- ReleasePipelineTests: tracker vs fallback velocity; rest 80 ms → v≈0; in-bounds decay rest point; `willEndDragging` retarget → lands exactly; spring fallback (direction disagrees); out-of-bounds release → spring, `willDecelerate == true`; edge hand-off; paging one page max + flick; fling acceleration cap; pixel snap at rest for displayScale 2/3.
- DelegateOrderTests (fake delegate recording + `effectsLog`): willBeginDragging → didScroll… → willEndDragging → didEndDragging(w) → [willBeginDecelerating → didScroll… → didEndDecelerating]; phase sequence idle→tracking→interacting→decelerating→idle; ≤1 didScroll per `step(to:)`; catch during deceleration fires didEndDecelerating then tracking; `ZTronScrollPhaseReader` renders only on transitions (M2's skipped test).
- ArbitrationTests with `ReferenceScrollArbiter`: register/update/unregister tokens; canFollow at min/max/middle/fits; `.participant` normal; `.container` leaves offset, phase, delegate log, indicator flag and `isTracking` untouched for the whole sequence; one `owner` call per sequence; catch sets isMovingWithoutFinger sticky so rule 3 holds; no arbiter ⇒ identical effects log as standalone.
Demo UI (`scripts/test-demo-ui.sh`, 27.0 and 17.5, preferred + forced): fling (didScroll ≥ 20, phase ends idle, offset within bounds, content.body 0); rubber band (drag past top → offset < min during drag, returns to min); catch without Button fire (fling, tap during deceleration: button counter 0, motion stopped); controls checklist from §8 per mode; pager stand-in page with `ReferenceScrollArbiter` and a fake container decision: `.container` → offset unchanged.

## 10. Builder sessions and file ownership

- **M3-a (state + physics glue):** `Gesture/PanSession.swift`, `Gesture/ReleasePipeline.swift`, `State/ZTronScrollState.swift` (+ `ScrollStateTypes.swift`, `StateStorage.swift`: flags channel, MotionKind, beginDeceleration, beginTracking, writeDragOffset, didScroll coalescing, lastInterruptedVelocity, UIKit knobs, full delegate protocol), `ZTronScrollPhaseReader.swift`; tests PanSessionTests, ReleasePipelineTests, DelegateOrderTests. No SwiftUI gestures.
- **M3-b (SwiftUI adapter + demo):** `Gesture/PanCoordinator.swift`, `Gesture/PanGestureAdapter.swift`, `Gesture/CatchObserver.swift` (18+/fallback), env keys + `ztronScrollDisabled`/`ztronScrollBounceBehavior` modifiers (`Modifiers/`), `TransformHost` hit-test gate, `ScrollContainer` wiring; Demo `PanScreen.swift`, `ControlsScreen.swift`, UI tests; `-ZTronPanGestureMode`.
- **M3-c (arbitration):** `Gesture/ArbitrationParticipant.swift`, `PanCoordinator` decide wiring, frame registration (cold geometry read in the arbiter's named space), named gestures on 18+; ArbitrationTests; demo pager stand-in + UI test. Depends on a and b.

## 11. Risks to check on device

- 120 Hz: two `dragChanged` per frame → confirm one `didScroll` per tick and no transform jitter; `VelocityTracker` window 100 ms holds ~12 samples (capacity 24 ok).
- Fallback observer latency on ≤17 and whether `DragGesture(minimumDistance: 0)` fires at touch-down for a stationary finger (needed for the catch); if not, the catch happens at first movement (document).
- `.simultaneousGesture` vs Slider/TextField/nested ScrollView on 15/16 (Xcode 26.x on older macOS) and 27 input kinds (trackpad); mode switch exists for this.
- The gate (`allowsHitTesting` / `.disabled` / shield / mask toggling inside `TransformHost`) must not re-evaluate content bodies (render counter) nor cancel the catching touch's observer.
- `interrupt()` on catch happens before the arbiter is asked; rule 3 relies on the sticky `isMovingWithoutFinger` — confirm against `ReferenceScrollArbiter` semantics (MC-contract §3) in M3-c.
- Fling acceleration cap and spring stiffness vs native feel; paging flick threshold 300 pt/s.

## 12. Orchestrator resolutions (2026-10-18)
- Q1 Reconcile §2's delegate/phase with the existing `State/ScrollStateTypes.swift` (extend, don't duplicate).
- Q2 Arbitration names are the real ones: `FingerDirection`, `ScrollOwner`, `ScrollArbitrationToken`,
  `ScrollArbitrationParticipant` (copied verbatim from `Packages/ScrollArbitration/Sources`; this doc was corrected).
- Q3 Keep `isMovingWithoutFinger` sticky until the owner decision: `ReferenceScrollArbiter` snapshots it at
  `beginSequence()` (MC-contract §3b), but a real pager may begin its sequence after our catch ran, so sticky is
  the robust choice under both orders.
- Q4 Accepted: with an arbiter present `.tracking` waits for the owner decision (S12 requires `.container` to leave
  phase untouched); without an arbiter it fires at touch-down as native. Document in the parity matrix.
- Q5 Accepted: RTL in `canFollow` deferred (LTR for M3); iOS ≤ 17 pager hand-off is the container's job (MC §6 E).
