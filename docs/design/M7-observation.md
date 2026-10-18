# M7 · Observation + transitions design (SPEC S8 inventory "Transitions", "Observation"; S4 tiers; S11 l.575–580)

Scope: `onScrollGeometryChange`, `onScrollPhaseChange` (×2), `onScrollVisibilityChange`, `onScrollTargetVisibilityChange`, both
`scrollTransition` overloads and their types. Inputs assumed from M5/M6 designs (not code): `ScrollTargetRegistry` protocol + `TargetRegistry`
(`frames` in unscaled `ztronContent` space, `version` cold channel), the `ztronScrollID` frame reporter (onGeometryChange 16+ / GeometryReader+preference 15, D9),
`EnvironmentValues.ztronScrollConfig` overlay + `ScrollViewConfig` (M6 §1–2), `ZTronScrollReader`/`ReaderProbe` (M2 §8), `ZTronScrollPhase` (already
`idle, tracking, interacting, decelerating, animating` = native `ScrollPhase`), `ZTronScrollState.delegate`, `batch`/`deliverPending`, `setPhase`.

## 1. Parity shapes (S8) and the one new mechanism

| API | Native level / min OS | Our shape | Native applied too |
|---|---|---|---|
| `onScrollGeometryChange(for:of:action:)` | scroll-view-level, 18 | member `ZTronScrollView.onScrollGeometryChange(...) -> Self` + twin `View.onZTronScrollGeometryChange(...)` | twin: `#available(iOS 18)` |
| `onScrollPhaseChange` ×2 | scroll-view-level, 18 | member + twin `onZTronScrollPhaseChange` | twin: 18 |
| `onScrollTargetVisibilityChange(idType:threshold:_:)` | scroll-view-level, 18 | member + twin `onZTronScrollTargetVisibilityChange` | twin: 18 |
| `onScrollVisibilityChange(threshold:_:)` | content-level, 18 | dual-mode `View.onZTronScrollVisibilityChange` (env `ztronScrollState != nil` → ours; else native on 18, no-op below) | — |
| `scrollTransition` ×2 | content-level, 17 | dual-mode `View.ztronScrollTransition` (ours inside; native on 17 outside, no-op on 15–16 outside) | — |
| `ScrollGeometry`, `ScrollPhaseChangeContext`, `ScrollTransitionPhase`, `ScrollTransitionConfiguration(.Threshold)`, `VisualEffect` | types | `ZTronScrollGeometry` (extended), `ZTronScrollPhaseChangeContext`, `ZTronScrollTransitionPhase`, `ZTronScrollTransitionConfiguration`, `ZTronVisualEffect` + gated bridges | `Observation/NativeBridges.swift` |

**Mechanism: `ObserverHub` on `ZTronScrollState` (no view updates).** Observers are closures registered on the state and run synchronously inside
`deliverPending()` after the delegate, in a fixed order. The hub does the per-frame work (cheap transforms + `!=`), so observation never touches
SwiftUI's update cycle: no probe views, no tracked reads, one code path on 15–16 and 17+ (`OSPath.allCases` run the same hub). Firing order per
delivery (S11 l.579; the demo event log confirms against native):
`didZoom → didScroll → [didEndDecelerating | didEndScrollingAnimation | didEndZooming] → geometry observers → visibility observers (content, then target) → phase observers`.
Phase transitions are *queued* by `setPhase` and flushed last in the same `deliverPending`, so `willBeginDragging` precedes `.tracking→.interacting`,
`willBeginDecelerating` precedes `→.decelerating`, `didEndDecelerating` precedes `→.idle` regardless of statement order at each call site
(requirement: every `setPhase` happens inside a `batch`, which is already the case for `setPhase`'s own body).

## 2. Types and signatures

```swift
// State/ZTronScrollGeometry.swift (additions) — stays storage-backed; a value init wraps a StorageSnapshot in `SnapshotStorage: StateStorage`
public struct ZTronScrollGeometry: Equatable {
    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets = .init(), containerSize: CGSize, zoomScale: CGFloat = 1)
    public var bounds: CGRect           // CGRect(origin: contentOffset, size: containerSize), scaled (viewport) space — native `bounds`
    // existing: contentOffset, contentSize (unscaled), contentInsets, containerSize, visibleRect (unscaled content space), zoomScale, phase
}
@available(iOS 18, *) extension ZTronScrollGeometry { public init(_ native: ScrollGeometry); public var native: ScrollGeometry /* zoomScale dropped */ }

// Observation/ScrollPhaseChangeContext.swift
public struct ZTronScrollPhaseChangeContext { public let geometry: ZTronScrollGeometry; public let velocity: CGVector? /* pt/s, nil when unknown */ }
@available(iOS 18, *) extension ZTronScrollPhase { public init(_ native: ScrollPhase); public var native: ScrollPhase }
public extension ZTronScrollPhase { var isScrolling: Bool { self != .idle } }   // native parity

// State/ObserverHub.swift (internal)
@MainActor final class ObserverHub {
    struct Token: Hashable { let id: UInt64 }
    func addGeometry(_ box: GeometryObserverBox) -> Token       // box.transform: (ZTronScrollGeometry) -> AnyEquatable, box.action: (old, new) -> Void
    func addPhase(_ box: PhaseObserverBox) -> Token             // box.action: (ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext) -> Void
    func addVisibility(_ box: VisibilityObserverBox) -> Token   // content-level: key UUID, threshold, action (Bool) -> Void, frame: CGRect? (cold, set by reporter)
    func addTargetVisibility(_ box: TargetVisibilityObserverBox) -> Token  // threshold, action ([AnyHashable]) -> Void, reads TargetRegistry
    func remove(_ token: Token)
    func deliver(_ g: ZTronScrollGeometry, registry: TargetRegistry?)       // called from deliverPending after delegate calls; `!=`-guarded per box
    func enqueuePhase(old: ZTronScrollPhase, new: ZTronScrollPhase, velocity: CGVector?); func flushPhase(_ g: ZTronScrollGeometry)
    #if DEBUG var deliveries: Int, fires: [String: Int] #endif
}
// ZTronScrollState additions: `let observers = ObserverHub()`; deliverPending() → `observers.deliver(peekGeometry(), registry:)` then `observers.flushPhase(...)`;
// setPhase(_:) → `observers.enqueuePhase(old:new:velocity: currentVelocity())` (velocity = last tracker/motion sample, pt/s; nil for idle→tracking).
// Boxes are final classes held in @State by the modifiers; the body re-assigns `box.transform/action` on every evaluation (R7 from M2: never stale).

// Observation/ScrollObservers.swift — members (S8-2a) and twins (S8-2b)
extension ZTronScrollView {
    public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ZTronScrollGeometry) -> T, action: @escaping (T, T) -> Void) -> Self
    public func onScrollPhaseChange(_ action: @escaping (ZTronScrollPhase, ZTronScrollPhase) -> Void) -> Self
    public func onScrollPhaseChange(_ action: @escaping (ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext) -> Void) -> Self
    public func onScrollTargetVisibilityChange<ID: Hashable>(idType: ID.Type, threshold: Double = 0.5, _ action: @escaping ([ID]) -> Void) -> Self
}
extension View {   // write an ObserverBox into `ztronScrollConfig.observers` (env overlay, appended, not replaced → nesting works) + native under #available(iOS 18)
    public func onZTronScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ZTronScrollGeometry) -> T, action: @escaping (T, T) -> Void) -> some View
    public func onZTronScrollPhaseChange(_ action: @escaping (ZTronScrollPhase, ZTronScrollPhase) -> Void) -> some View
    public func onZTronScrollPhaseChange(_ action: @escaping (ZTronScrollPhase, ZTronScrollPhase, ZTronScrollPhaseChangeContext) -> Void) -> some View
    public func onZTronScrollTargetVisibilityChange<ID: Hashable>(idType: ID.Type, threshold: Double = 0.5, _ action: @escaping ([ID]) -> Void) -> some View
    // content-level (S8-3), Modifiers/ZTronScrollVisibility.swift
    public func onZTronScrollVisibilityChange(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) -> some View
}
// ScrollContainer registers config.observers + env observers into state.observers on appear and whenever the box set changes (identity-diffed), removes on disappear.

// Transitions/ScrollTransitionTypes.swift
public enum ZTronScrollTransitionPhase: Hashable, Sendable { case topLeading, identity, bottomTrailing
    public var isIdentity: Bool; public var value: Double /* -1, 0, 1 */ }
public struct ZTronScrollTransitionConfiguration: Equatable, Sendable {
    public struct Threshold: Equatable, Sendable {
        public static let visible: Threshold /* = .visible(1) */; public static func visible(_ amount: Double) -> Threshold
        public static let hidden: Threshold; public static let centered: Threshold; public static func inset(by d: CGFloat) -> Threshold
        public static func interpolated(from: Threshold, to: Threshold, fraction: Double) -> Threshold
        public func union(_ o: Threshold) -> Threshold; public func intersection(_ o: Threshold) -> Threshold
        indirect enum Kind: Equatable { case visible(Double), hidden, centered, inset(CGFloat), interpolated(Kind, Kind, Double), union(Kind, Kind), intersection(Kind, Kind) }
    }
    public static let animated: Self /* .animated(.default) */; public static func animated(_ a: Animation) -> Self
    public static let interactive: Self /* .interactive(timingCurve: .easeInOut) */; public static func interactive(timingCurve: ZTronUnitCurve) -> Self
    public static let identity: Self; public func threshold(_ t: Threshold) -> Self
    enum Mode: Equatable { case animated(Animation), interactive(ZTronUnitCurve), identity }; var mode: Mode; var threshold: Threshold   // default .visible
}
public struct ZTronUnitCurve: Equatable, Sendable { public static let linear, easeIn, easeOut, easeInOut: Self; public static func bezier(_ p1: CGPoint, _ p2: CGPoint) -> Self
    public func value(at t: Double) -> Double }                                                       // 17+: `var native: UnitCurve`
public struct ZTronVisualEffect: Equatable, Sendable {   // mirrors EmptyVisualEffect + the VisualEffect ops we can lerp; `empty` is the identity
    public static let empty: Self
    public func offset(_ o: CGSize) -> Self; public func offset(x: CGFloat = 0, y: CGFloat = 0) -> Self
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> Self; public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> Self
    public func rotationEffect(_ a: Angle, anchor: UnitPoint = .center) -> Self
    public func rotation3DEffect(_ a: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center, perspective: CGFloat = 1) -> Self
    public func opacity(_ v: Double) -> Self; public func blur(radius: CGFloat) -> Self; public func brightness(_ v: Double) -> Self
    public func contrast(_ v: Double) -> Self; public func saturation(_ v: Double) -> Self; public func grayscale(_ v: Double) -> Self; public func hueRotation(_ a: Angle) -> Self
    static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self                  // componentwise (angles in radians); anchors/axes taken from `b`
    func apply<V: View>(to v: V) -> some View                                    // fixed canonical order: scale → rotate → rotate3D → offset → opacity → blur → color filters
    @available(iOS 17, *) func apply<E: VisualEffect>(to e: E) -> some VisualEffect   // same order, native ops
}
// Modifiers/ZTronScrollTransition.swift — dual-mode content modifiers (S8-3)
extension View {
    public func ztronScrollTransition(_ configuration: ZTronScrollTransitionConfiguration = .interactive, axis: Axis? = nil,
        transition: @escaping (ZTronVisualEffect, ZTronScrollTransitionPhase) -> ZTronVisualEffect) -> some View
    public func ztronScrollTransition(topLeading: ZTronScrollTransitionConfiguration, bottomTrailing: ZTronScrollTransitionConfiguration, axis: Axis? = nil,
        transition: @escaping (ZTronVisualEffect, ZTronScrollTransitionPhase) -> ZTronVisualEffect) -> some View
}
@available(iOS 17, *) extension ZTronScrollTransitionPhase { public init(_ native: ScrollTransitionPhase); public var native: ScrollTransitionPhase }
@available(iOS 17, *) extension ZTronScrollTransitionConfiguration { public var native: ScrollTransitionConfiguration }   // one way; Threshold maps 1:1
```
Unprefixed `onScrollGeometryChange`/`onScrollPhaseChange`/`onScrollTargetVisibilityChange` bind only on the ZTronScrollView itself (parity matrix note).
Outside a ZTronScrollView the twins apply the native modifier (18+) and the env overlay is harmless. Nested ZTronScrollViews: inner views also register
the inherited boxes (native: every scroll view inside fires). `ZTronScrollReader`/`ZTronScrollPhaseReader` remain the view-based readers; unchanged.

## 3. Data flow

- **Geometry/phase (hub):** gesture/clock → `batch` → `deliverPending`: delegate → `hub.deliver(g)`: for each geometry box `new = transform(g)`;
  `if new != box.last { box.action(old, new) }`. Then visibility boxes (§4), then `flushPhase` runs queued `(old, new, ctx)` with `ctx.geometry = g`.
  `g` is `peekGeometry()` (untracked snapshot): no SwiftUI dependency is created; the modifiers' bodies run only when their parent rebuilds.
- **Content visibility:** `onZTronScrollVisibilityChange` = `.background(FrameReporter(space: ztronContent) { box.frame = $0 })` (same reporter as
  `ztronScrollID`, cold: fires on layout only) + box registered with the env state's hub on appear. Hub computes `visible` from `box.frame` and `g.visibleRect`.
- **Target visibility:** hub reads `registry.frames` (M6) + `registry.version`; `[ID]` result is in layout order (sorted by the axis min then cross axis),
  filtered to ids castable to `ID`. Recomputed when offset/zoom/metrics change **or** `version` changed since the last delivery (frames moved without scroll).
- **Transitions:** `transition(.empty, phase)` is evaluated **once per body evaluation** for the three phases → `(lead, idn, trail)` cold descriptions.
  Per frame only `lerp` runs. Paths: 17+ (and R1 confirmed) `visualEffect { e, proxy in desc(proxy.frame(in: .named(viewport)), proxy.bounds(of: .named(viewport))).apply(to: e) }`
  → pure render time, no body of anything re-runs. 15–16 and `-ZTronForceAllFallbacks`: `ZTronScrollReader(of: { g in desc(frame, g.visibleRect) }) { d in content.apply(d) }`
  where `frame` is the cold reporter frame and `content` is the modifier placeholder (S4-3: not re-evaluated); the reader re-renders only when `d` changes,
  i.e. only while this view crosses the threshold band — fully visible or fully hidden views are silent during panning. `.animated` uses the reader path on
  all OSes with a discrete `@State phase` flipped inside `withAnimation(a)`; `.identity` applies `idn` once.

## 4. Formulas

Axis `a = axis ?? (axes == [.horizontal] ? .horizontal : .vertical)`. `F` = view frame, `V` = `visibleRect` (both unscaled content space); `len(·)` along `a`.
- Visible fraction (content & target visibility): `f = area(F ∩ V) / area(F)`; empty `F` → `f = 0`. `visible = threshold <= 0 ? f > 0 : f >= min(threshold, 1)`.
  No hysteresis (native has none); the `!=` guard on the Bool / `[ID]` is the only filter.
- Threshold progress `p(F, V) ∈ [0, 1]` (1 = "visible per threshold"), per kind, using 1-D fraction `f1 = len(F ∩ V) / len(F)`:
  `visible(k)`: `min(f1 / k, 1)`; `hidden`: `f1 > 0 ? 1 : 0`; `centered`: `1 − min(|mid(F) − mid(V)| / (len(V)/2), 1)`; `inset(d)`: `visible(1)` against `V` shrunk by `d` on both ends;
  `interpolated(a, b, t)`: `(1−t)·p_a + t·p_b`; `union`: `max`; `intersection`: `min`.
- Side `s = mid(F) < mid(V) ? −1 : +1` (topLeading / bottomTrailing). Interactive: `t = curve.value(at: 1 − p)`; `desc = lerp(idn, s < 0 ? lead : trail, t)`.
  Two-config overload: pick the config by `s`. Animated: `phase = p >= 1 ? .identity : (s < 0 ? .topLeading : .bottomTrailing)`, applied with `withAnimation(a)` on change.
- `visibleRect` already divides by `zoomScale` (M2), so a zoomed-in view transitions on its scaled footprint; frames stay unscaled (registry convention).

## 5. Edge cases

- Observers added while moving: first `deliver` seeds `last` and fires the initial call (geometry: `(v, v)`; visibility: current Bool; target: current `[ID]`;
  phase: never initial) — matches native as far as known (Q1). Removal during a callback is safe (hub iterates a copy).
- `transform` that throws no change every frame costs one closure + `==`; a `transform` returning the whole geometry fires every frame — documented, same as native.
- Zero-size container (not yet laid out): hub skips visibility/transition evaluation; geometry observers still receive the metrics-only change.
- Views larger than the viewport: `f1 < 1` always for `.visible`; `.centered` or `.visible(k<1)` are the documented way (native behaves the same).
- Rotation (S7) and content resize: metrics change → one delivery, frames re-reported cold → visibility recomputed once, no per-frame churn.
- `scrollTransition` inside a `ZTronLazyVStack` placeholder: the frame reporter reports on insertion; before that `desc = idn` (no flash of the transition state).
- Lerping rotation3D axis/anchor isn't meaningful: taken from the non-identity description, documented. Canonical op order differs from native call order; documented in the matrix.

## 6. Exemplar plan (O5) and sessions — start after M6 session 1 is committed (shared `ZTronScrollState.swift`, `TargetRegistry`, frame reporter)

**Session 1 — exemplar (one of each shape, fully tested):** `State/ObserverHub.swift` + the ≤10-line hook in `State/ZTronScrollState.swift` (`observers`,
`deliverPending`, `setPhase`); `ZTronScrollGeometry` value init + `bounds`; member+twin `onScrollGeometryChange` (`Observation/ScrollObservers.swift`,
`ScrollViewConfig.observers`, `ScrollContainer` registration); content-level `onZTronScrollVisibilityChange` (`Modifiers/ZTronScrollVisibility.swift`,
reusing the M6 frame reporter); `Observation/NativeBridges.swift` (geometry 18+). Tests T1–T6, T12.
**Session 2 — copy the pattern:** `onScrollPhaseChange` ×2 + context + velocity + ordering at every delegate site (T7–T8), `onScrollTargetVisibilityChange`
member+twin (T9), demo `EventLogScreen` + `ObservationUITests`, parity rows.
**Session 3 — transitions:** `Transitions/{ScrollTransitionTypes,ThresholdMath,VisualEffectDescription}.swift`, `Modifiers/ZTronScrollTransition.swift`
(visualEffect path + reader fallback), bridges 17+, demo `CarouselScreen`, T10–T11, T13, R1–R3 on device. No session touches `Packages/`, `Gesture/`, `Targets/` (M6) or `ScrollArbitration`.

## 7. Tests (Swift Testing, `Tests/ZTronScrollViewTests/Observation*`, over `OSPath.allCases`, `.serialized`; UI on 27.0 and 17.5 ± `-ZTronForceAllFallbacks`)

T1 hub: geometry observer fires only when derived value changes (offset-only transform silent under pure zoom; zoom-only silent under pan); at most once per `deliverPending`.
T2 ordering: a recording delegate + observers see `didScroll` before geometry, visibility before phase, in one delivery (synthetic drag → decelerate → idle).
T3 counters: content body count unchanged across 120 frames with geometry/visibility/phase observers attached; modifier body count = parent rebuild count.
T4 stale-closure: parent rebuild with a new `action` closure → next fire uses the new closure (R7).
T5 visibility math: fractions/threshold table incl. `threshold 0`, empty frame, view larger than viewport, zoom ≠ 1; Bool fires only on flips.
T6 geometry value init / 18+ round trip (`native` ⇄ ours, zoomScale dropped); `bounds` vs `visibleRect` under zoom.
T7 phase: both overloads, `ctx.geometry == peekGeometry()` at flush, `velocity` nil on idle→tracking, non-nil on interacting→decelerating; no initial fire.
T8 phase order at every site: willBeginDragging→(tracking→interacting), willBeginDecelerating→(→decelerating), didEndDecelerating→(→idle), didEndScrollingAnimation→(animating→idle), zoom bounce stays `.decelerating` (D13).
T9 target visibility: `[ID]` layout-ordered, type-filtered, recomputed on `registry.version` bump without motion, initial fire.
T10 threshold math table for every `Threshold` kind + `union/intersection/interpolated`; side sign; `ZTronUnitCurve` endpoints and monotonicity; `lerp` identity at t=0/1.
T11 transition render tier: decorated body count constant during motion on both paths; fallback reader re-render count == number of distinct `desc` values (0 while fully visible).
T12 twins outside a ZTronScrollView compile and are no-ops (<18) / don't crash (18+ smoke); nested ZTronScrollViews both fire.
T13 UI: CarouselScreen cards' reported scale/opacity match the formula at 3 offsets (accessibility values), both OS paths; EventLogScreen order string equals the expected sequence.
Demo: `CarouselScreen` (horizontal, `.viewAligned` from M6, `ztronScrollTransition(.interactive)` scale+opacity, `.animated` row, `.centered` row, native twin side-by-side on 17+/18+);
`EventLogScreen` (delegate + all four callbacks appended to one log with sequence numbers; native ScrollView twin on 18+ for order comparison).
Parity matrix rows: each API → strategy → min OS → fallback → tests (incl. gaps: canonical op order; native closure `(EmptyVisualEffect, ScrollTransitionPhase)` not accepted, see Q3).

## 8. Risks to check on device

- **R1** `visualEffect` proxy updates while our transform host moves content (GeometryEffect-driven). If not, 17+ uses the reader fallback too (same tier table; spec allows).
- **R2** Native firing order and initial-fire behaviour (Q1) via EventLogScreen side-by-side on 18+/27.0; adjust the hub order constant if native differs.
- **R3** Native default thresholds: `.interactive` → `.visible`, `.animated` → `.visible` assumed; compare carousel vs native on 17.5/27.0 and record in the matrix (Q2).
- **R4** `.animated` with `withAnimation` inside the reader path: confirm no implicit animation leaks into sibling layout (wrap in `Transaction` with `disablesAnimations` for the frame reporter).
- **R5** Velocity units: delegate `withVelocity` is UIKit pt/ms-style? `ZTronScrollPhaseChangeContext.velocity` must be pt/s like native; one conversion point in `currentVelocity()`.
- **R6** Hub cost with many visibility boxes (≥200): confirm per-frame `deliver` ≤ 0.2 ms on iPhone 11-class; otherwise add the sorted-by-min index (binary-search the candidate band).

## Open questions
- Q1 Initial fire: geometry `(v, v)` once, visibility/target visibility once, phase never — confirm against native (R2) before freezing.
- Q2 Default thresholds for `.interactive`/`.animated` (R3); and whether native `.hidden` is discrete or interpolates.
- Q3 Offer a gated 17+ overload accepting the native closure `(EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect`? Only possible on the visualEffect path (R1) and
  never on 15–16; proposal: skip, document as a matrix gap (our `ZTronVisualEffect` closure runs everywhere and bridges to native).
- Q4 Member spellings unprefixed (`onScrollGeometryChange`) on `ZTronScrollView` — confirm no ambiguity with SwiftUI's `View` extension on 18+ (compile test in Session 1; fallback: prefix members too).

## Orchestrator resolutions (2026-10-18)
- Q1/Q2 Accept the assumptions as the starting point; Session 1 adds a side-by-side demo check against a native
  ScrollView (17+/18+) and corrects the behaviour if native differs. Record the result in the parity matrix.
- Q3 Accepted: skip the native-`VisualEffect` closure overload (gap: native `VisualEffect` values can't be applied to
  our transform without private API); parity-matrix row "approximate".
- Q4 A compile test (both unprefixed member spellings on `ZTronScrollView` and the 18+ SwiftUI `View` extensions in
  the same call chain) is mandatory before shipping unprefixed members; if ambiguous, ship only the `ztronScroll` twin.
- R1 decides 17+ path: Session 1 measures it first (counter test) and records the choice.
