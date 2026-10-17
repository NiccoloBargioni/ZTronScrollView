# M2 · Render path: state store, frame clock, layout host, transform, probe, readers, proof harness

Scope: SPEC S3–S5, S11 (state + reader shapes), S13. Names per CLAUDE.md. No gestures (M3), no indicators/refresh/header
(M4+). Everything below is iOS 15+; newer APIs sit behind `ZTronAvailability.isAvailable(.x), #available(iOS n, *)`.
Decisions are numbered **R1…R12**; "verify" marks items the proof harness (§10) must confirm on device.

## 1. `ZTronScrollState` storage

```swift
@MainActor public final class ZTronScrollState {                 // single source of truth; NOT ObservableObject (R1)
    public init()                                                 // storage chosen here, once, via ZTronAvailability
    public private(set) var contentOffset: CGPoint   { storage.presentationOffset }   // hot, presentation
    public private(set) var zoomScale: CGFloat       { storage.presentationZoom }     // hot, presentation
    public private(set) var phase: ZTronScrollPhase  { storage.phase }                // cold: idle, tracking, interacting, decelerating, animating
    public var geometry: ZTronScrollGeometry { get }              // lazy view over storage (§8); each getter tracks only itself
    public var isScrollAnimating: Bool, isZoomAnimating: Bool      // cold flags (M2 subset; the rest in M3)
    public weak var delegate: (any ZTronScrollViewDelegate)?      // never observed
    let storage: any StateStorage                                 // `let`: the path never flips after init
    let usesLayoutProtocol, usesNamedCoordinateSpace, usesGeometryChange: Bool   // also fixed at init (R6)
}

@MainActor protocol StateStorage: AnyObject {   // hot: targetOffset, targetZoom, presentationOffset, presentationZoom
    // cold: metrics (ViewportMetrics + contentSize + displayScale, one struct, changes rarely), phase, flags, isClockRunning
    // every setter: `guard new != old else { return }`; every hot read has a tracked getter and an untracked `peek…`
    func beginBatch(); func endBatch()          // one publish per channel per batch; step/commands/gesture handlers are batches
}
@available(iOS 17, *) final class ObservationStorage: StateStorage   // hand-written ObservationRegistrar, not the @Observable macro (R2)
final class ChannelStorage: StateStorage                               // OffsetChannel, ZoomChannel, MetricsChannel, PhaseChannel: ObservableObject
```

- **R1** `ZTronScrollState` is not `ObservableObject`: `@ObservedObject` on it would wake every reader every frame (S4.5).
  Clients hold it in `@State`/a `let`; on 17+ direct reads inside any body auto-track through the inner registrar; on 15–16
  direct reads are snapshots and clients use `ZTronScrollReader` or the `ztronScroll…` modifiers (same granularity, S3).
- **R2** Observation path is a hand-written registrar class: it gives untracked `peek` getters (needed by §8 first frame and
  by the catch path) and keeps hot values as *separate stored properties* (S4.5). The macro hides its backing storage.
- Channel path: plain stored values, no `@Published`. `beginBatch` arms; the first dirty write of a channel in the batch
  sends `objectWillChange` (before mutating, Combine semantics kept); later writes in the same batch don't. `step(to:)`,
  every command and every geometry callback run inside a batch → at most one publish per channel per frame.
- Selection: `if ZTronAvailability.isAvailable(.perPropertyObservation), #available(iOS 17, *) { ObservationStorage() }
  else { ChannelStorage() }`. The forced-fallback switch therefore exercises channels on 17+ (OSPath.forcedFallback).
- Fallback observers: a single leaf mechanism `ChannelRelay: ObservableObject` (Combine `merge` of the channels a leaf
  needs → one `objectWillChange` per frame). Leaf views/modifiers hold `@ObservedObject var relay`; on the Observation path
  the relay is a shared inert instance that never publishes, so leaf *types* are identical on both paths (no conditionals).

## 2. Target vs presentation (who writes what)

| Writer | Target | Presentation | Transaction |
|---|---|---|---|
| finger (M3) `track(offset:zoom:)` | yes | yes | `withTransaction(disablesAnimations)` (keypath form 17 / `Transaction` value 15) |
| clock `step(to:)` | yes | yes | same, unanimated; samples `AxisMotion` closed forms at `date − t0` (M1) |
| transaction-driven `scroll(to:)`, viewport/content-size/inset change, rotation (S7) | yes | no | the caller's; the Animatable effect interpolates; probe (§6) feeds presentation |
| `interrupt()` (touch during motion, `stopScrollingAndZooming`) | ← presentation (`peek`) | — | unanimated; cancels in-flight SwiftUI animation without a jump |

Velocity lives in the non-observed `AxisMotion` pair inside the state; `didScroll` fires from `endBatch` when
presentation changed (once per frame, all sources, S11). Hot values never flow into a parent through a `Binding` (S4.6).

## 3. Frame clock driver

```swift
struct FrameClockDriver: View {   // leaf in ViewportView's background; 0×0
    @ObservedObject var relay: ChannelRelay      // phase channel only (isClockRunning); inert on 17+
    let state: ZTronScrollState
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !state.isClockRunning)) { ctx in
            Color.clear.frame(width: 0, height: 0)
                .onChangeCompat(of: ctx.date) { state.step(to: $0) }   // 15: onChange(of:perform:); 17: two-arg form
        }
    }
}
```
- `isClockRunning` is a cold flag: set when a motion starts (decay, spring, animated command, transaction motion), cleared
  in `step` when every axis is settled → `paused: true` → TimelineView stops scheduling: zero idle cost (S4.7). Pausing
  re-renders once with the pause date; `step` while nothing moves is a no-op (guard, no publish).
- **Lag detection (R3).** DEBUG counter `lagFrames`: inside the TimelineView closure the leaf compares
  `state.peekOffset()` with `state.expectedOffset(at: ctx.date)`; a mismatch means the value drawn this frame was
  computed for the previous tick. Exposed by the proof screen. Expectation: 0 (writes in `onChange` are applied in the
  same update cycle). If > 0 on device: step one frame ahead, `step(to: date + estimatedFrameInterval)` with the interval
  measured from consecutive timeline dates (120 vs 60 Hz). The spec's alternative (TransformHost sampling from a
  `\.ztronFrameDate` environment set inside the TimelineView) stays plan C: it re-runs the TimelineView closure around the
  content value every frame and needs its own identity proof.
- 120 Hz: demo Info.plist `CADisableMinimumFrameDurationOnPhone = YES`; `minimumInterval: nil` follows the display. Verify.

## 4. Content layout host

Order (inside → out): `content` → size measurement → `ztronContent` coordinate space → `TransformHost` →
`ContentLayoutHost` → viewport (`ztronViewport` space, `.clipped()`, `.contentShape(Rectangle())`).
```swift
@available(iOS 16, *) struct ScrollContentLayout: Layout {      // sizeThatFits: proposal with nil replaced by 0 (fills viewport)
    let axes: Axis.Set                                           // placeSubviews: proposal nil on scrollable axes, viewport length otherwise; at bounds.origin
}
// iOS 15 / forced: content.fixedSize(horizontal: axes.contains(.horizontal), vertical: axes.contains(.vertical))
//                         .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // no viewport-size dependency (R4)
```
- **R4** The fallback uses `maxWidth/maxHeight: .infinity`, not explicit viewport sizes, so neither path reads the
  viewport size in the host body (avoids a 0-sized first frame and a second layout pass). Same proposal as ScrollView:
  `fixedSize` proposes nil on fixed axes and forwards the parent's proposal on the others.
- Measurement is below the transform, so it is unscaled: 16+ `.onGeometryChange(for: CGSize.self) { $0.size } action:`
  (single-value overload); 15 `.background(GeometryReader { Color.clear.preference(ContentSizeKey, $0.size) })` +
  `onPreferenceChange` on the host. Both write `metrics.contentSize` (cold, `!=`-guarded) and never change the proposal.
- Identity: `content` is a stored `Content` value, no `AnyView`, no `.id`. **R6** Path selection inside `ContentLayoutHost`
  and the coordinate-space modifier is an `if` in a `ViewModifier.body(content:)` around the *placeholder*, on `let`
  flags fixed at `ZTronScrollState.init`; the `_ConditionalContent` branch never flips, so content `@State` survives.
  Test `contentStateSurvivesScrollZoomRotation` on both OSPaths guards this.

## 5. Transform host

```swift
struct ContentTransform: GeometryEffect {        // one effect: translation, scale, alignment padding
    var offset: CGPoint, scale: CGFloat, pad: CGSize
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    let probe: PresentationBox?                  // §6; not part of animatableData
    func effectValue(size: CGSize) -> ProjectionTransform {
        probe?.record(offset, scale)             // non-observed write; published by the clock
        return ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: pad.width - offset.x, ty: pad.height - offset.y))
    }   // x_v = s·x_c + pad − o   (design-note focal/resize formulas use the same mapping)
}
struct TransformHost: ViewModifier {             // reads TARGET values; body re-runs per frame only for clock/finger motion
    @ObservedObject var relay: ChannelRelay      // offset + zoom + metrics channels; inert on 17+
    @Environment(\.displayScale) var displayScale
    let state: ZTronScrollState
    func body(content: Content) -> some View { content.modifier(ContentTransform(...snapped if state.phase == .idle...)) }
}
```
- Pixel snapping (`round(v·displayScale)/displayScale`) is applied to translation only, in the modifier body, only when
  `phase == .idle`; the effect stays purely animatable. Scale is never snapped (would move the focal point).
- Why `content` isn't re-evaluated: `body(content:)` receives a `_ViewModifier_Content` placeholder; re-running the
  modifier rebuilds only the chain above it. The wrapped content's body runs only when its own inputs change. Tier-0
  counter proves it on both paths. **R5** No `visualEffect` in M2: `GeometryEffect` is iOS 15 and already render-time;
  `visualEffect` is reserved for counter-scaled children (M3+). `ignoredByLayout()` is evaluated in the proof only if
  hit-testing stays transformed (verify); default is the plain effect.

## 6. Presentation probe (transaction-driven motion)

- `PresentationBox`: a plain `final class` (not observed) holding `pending: (CGPoint, CGFloat)` and `frames: Int`. It is
  written from `effectValue(size:)` on every interpolated frame (the effect *is* the probe: same `animatableData`, no second
  interpolation), never from a view body, so nothing observable mutates during a view update.
- When `scroll(to:)` changes the target inside an animated transaction, the state sets `phase = .animating`,
  `isClockRunning = true`. Each tick: `presentation = box.pending` (`!=`-guarded) → didScroll. The published presentation
  trails the drawn frame by one tick (reporting only; the transform itself is exact).
- Completion: 17+ `.transaction { t in if t.animation != nil && !t.disablesAnimations { t.addAnimationCompletion(criteria: .removed) { state.finishTransactionMotion(token) } } }`
  on the `TransformHost` chain, token = target generation (stale completions ignored). 15–16 / forced: settled when
  `box.pending == target` on 2 consecutive ticks. The settle detector also runs on 17+ as safety net. Finish: phase →
  `.idle`, clock paused, `didEndScrollingAnimation`. Verify that `effectValue` fires every frame (counter `transform.effect`
  ≈ duration × fps) and that the `.transaction` modifier sees model-driven transactions.
- Touch during motion (M3 wires the gesture; M2 ships `interrupt()`): target = `box.pending`, unanimated.

## 7. Coordinate spaces and viewport observation

```swift
public enum ZTronCoordinateSpaces { public static let content: CoordinateSpace; public static let viewport: CoordinateSpace }  // .named(…), iOS 15
@available(iOS 17, *) public extension NamedCoordinateSpace { static var ztronContent: Self; static var ztronViewport: Self }  // sugar, same names
struct ViewportMetrics: Equatable { var size: CGSize; var safeArea: EdgeInsets }
```
- Spaces are declared by a `NamedSpaceModifier` (R6 pattern): `coordinateSpace(.ztronContent)` 17+ /
  `coordinateSpace(name:)` 15. `ztronContent` sits under the effect, so frames read in it don't change while scrolling.
- Viewport size + safe area (keyboard included) are observed in the **viewport's background**, never around content:
  16+ `.onGeometryChange(for: ViewportMetrics.self)`; 15 `GeometryReader` + `PreferenceKey`. `setViewport(_:)` writes
  cold metrics and rewrites the target in the ambient transaction with the S7 resize formula (visible center kept).

## 8. `ZTronScrollReader<Value: Equatable, Content: View>` and `ZTronScrollGeometry`

```swift
public struct ZTronScrollGeometry: Equatable {   // lazy view: contentOffset, contentSize, contentInsets, containerSize, visibleRect, zoomScale
    // each getter reads exactly one storage property (tracked on 17+, records the channel bit on 15–16); `==` reads all
}
public struct ZTronScrollReader<Value: Equatable, Content: View>: View {
    public init(_ state: ZTronScrollState? = nil, of transform: @escaping (ZTronScrollGeometry) -> Value, @ViewBuilder content: @escaping (Value) -> Content)
    @State private var current: Value?
    public var body: some View {
        content(current ?? transform(resolved.peekGeometry()))          // untracked first-frame value: no nil flash
            .background(ReaderProbe(state: resolved, transform: transform) { new in current = new })   // 0×0 leaf
    }
}
```
- `ReaderProbe` reads hot values in its own body (tracked / relay-observed), computes `transform`, and `onChange(of:)`
  writes `current`. Content runs when `current` changes **or** when the caller's body rebuilds the reader (new closures
  are re-applied) → never stale. **R7** No `Equatable` view wrapper that ignores the `content` closure (that is the stale case).
- Channel discovery on 15–16: the first probe evaluation runs `transform` against a recording geometry; the relay then
  subscribes only to the touched channels, so a zoom-only reader is silent during panning on both paths (same tier table).

## 9. Programmatic API in M2 (everything else deferred to M3+)

```swift
public func setContentOffset(_ offset: CGPoint, animated: Bool)   // UIKit twin: animated → clock-driven M1 critically damped spring (ω = 10), v₀ = 0
public func setZoomScale(_ scale: CGFloat, animated: Bool)        // unanimated path needed by the zoom-only tier test; animated shares the spring
public func scroll(to offset: CGPoint)                            // transaction-driven: animated iff called inside withAnimation (name: open question)
public func stopScrollingAndZooming()                             // = interrupt()
func step(to date: Date)                                          // internal; called by FrameClockDriver only
```

## 10. DEBUG counters and the proof harness

- `#if DEBUG @MainActor public enum ZTronRenderCounters { static func increment(_ key: String); static func value(_:) -> Int; static func reset(); static var snapshot: [String: Int] }`.
  Plain dictionary, never observed. Keys: `content.body`, `transformHost.body`, `transform.effect`, `clock.ticks`,
  `clock.lagFrames`, `reader.zoom`, `reader.phase`, `reader.offset`, `didScroll`. Compiled out in release.
- `Demo/ZTronScrollViewDemo.xcodeproj`: hand-written `objectVersion = 77` pbxproj; `PBXFileSystemSynchronizedRootGroup`
  for `Demo/ZTronScrollViewDemo` (SwiftUI App, iOS 15.0, explicit Info.plist with `CADisableMinimumFrameDurationOnPhone`)
  and `Demo/ZTronScrollViewDemoUITests` (XCUITest); `XCLocalSwiftPackageReference` relativePath `..`,
  `XCSwiftPackageProductDependency` `ZTronScrollView`; shared scheme `ZTronScrollViewDemo` with the UI tests in its Test
  action. Launch arguments: `-ZTronForceAllFallbacks` (App init calls `forceAllFallbacks(true)` before any view),
  `-ZTronProof` (opens the proof screen). The app re-creates its root with `.id` on the demo root only.
- Proof screen: a `ZTronScrollView` with counted content (a toggle inside proves identity), a zoom-only reader, a phase
  reader, an offset reader; buttons `Reset`, `AnimatedScroll` (`setContentOffset(animated:)`, 1 s), `WithAnimationScroll`
  (`withAnimation(.linear(duration: 1)) { scroll(to:) }`), `Zoom`, `Snapshot`. `Snapshot` copies counters into `@State`
  shown as `accessibilityValue` on `counter.<key>` identifiers plus `path` (preferred/forcedFallback) and `fps`
  (clock ticks ÷ motion duration). Counters are displayed only after the motion, so the display never perturbs it.
- UI tests (each on preferred and forced paths; destinations iOS 27.0 iPhone 18 Pro, iOS 17.5 iPhone 15 Pro):
  `animatedProgrammaticScroll`: content.body == 0, transformHost.body ≈ clock.ticks (±10 %), clock.ticks ≥ 0.8·60·1 s,
  didScroll == clock.ticks, lagFrames == 0. `withAnimationScroll`: content.body == 0, transformHost.body ≤ 2,
  transform.effect ≈ duration × fps (±25 %), clock.ticks ≈ effect, phase ends `.idle`. `zoomOnlyReaderSilentDuringPan`:
  reader.zoom == 0 after a pan, == 1 after `Zoom`. `phaseReaderOnTransitionsOnly`: reader.phase == 2 (idle→animating→idle).
  `noClockTicksAtRest`: ticks unchanged over 1 s idle. `contentStateSurvives`: toggle still on after scroll + zoom.
  `requestedPathIsActive`: `path` value matches the launch argument. Needs a `scripts/test-demo-ui.sh <destination> [--forced]`.

## 11. Unit tests (Swift Testing, `Tests/ZTronScrollViewTests`, parameterized over `OSPath.allCases`, `.serialized`)

**StateStorageTests** `storageKindFollowsAvailability` · `unchangedWriteDoesNotPublish` · `oneNotificationPerChannelPerBatch` ·
`hotWriteLeavesColdChannelsSilent` · `publicReadsIdenticalOnBothPaths` · `peekIsUntracked` (17+: `withObservationTracking`
around `peek` never fires) · `stateIsNotObservableObject` (compile-time assertion).
**TargetPresentationTests** `clockStepWritesBoth` · `transactionWriteTouchesOnlyTarget` · `interruptSetsTargetToPresentation` ·
`stepWhileIdleIsNoop` · `clockStopsWhenAllAxesSettle` · `settleDetectorNeedsTwoFrames` · `staleCompletionTokenIgnored` ·
`didScrollAtMostOncePerBatch`.
**TransformTests** `effectMatrixMatchesFormula` · `pixelSnapOnlyAtRestAt2xAnd3x` · `scaleNeverSnapped` · `animatableDataRoundTrip`
· `alignmentPaddingOnlyWhenContentFits`.
**LayoutHostTests** (hosted in the test bundle's window) `proposesNilOnScrollableAxes` · `proposesViewportOnCrossAxis` ·
`contentPlacedAtOrigin` · `contentSizeMeasuredUnscaled` (zoom 2× → unchanged) · `viewportMetricsObserved` ·
`contentStateSurvivesScrollZoomRotation` · `contentSpaceFramesStableWhileScrolling`.
**ReaderTests** `contentRunsOnlyWhenDerivedValueChanges` · `notStaleWhenClosureCapturesChangedInput` · `zoomOnlyReaderIgnoresPan`
· `firstFrameHasValue` · `channelDiscoveryMatchesAccessedProperties` (fallback only).
**CounterTests** `resetClears` · `incrementIsMainActorOnly`.

## 12. Risks to check on device

1. 120 Hz: `TimelineView(.animation)` honoring `CADisableMinimumFrameDurationOnPhone`; Low Power Mode drops to 60.
2. One-frame lag between `onChange(of: date)` and render (`lagFrames`); fallback plan B in §3.
3. `effectValue` really called per interpolated frame, also while the app is otherwise idle; probe writes during render safe.
4. Observation tracking inside `ViewModifier.body(content:)` and `.transaction {}` receiving model-driven transactions.
5. Hit-testing on the transformed content (plain effect vs `ignoredByLayout()`); taps land on the drawn position.
6. Fallback host with purely flexible content (`Color` → 10 pt ideal) matches ScrollView; `frame(maxWidth:.infinity)` overflow.
7. Fixed-branch `_ConditionalContent` keeps content `@State` (both paths, after rotation).
8. Combine relay cost per frame on the channel path; one publish per frame confirmed with counters.
9. Pixel snap at rest: visible ≤ 0.5 px settle jump; iOS 15/16 real runtimes only via Xcode 26.x smoke test.
