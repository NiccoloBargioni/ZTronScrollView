# ZTronScrollView · Design note (SPEC S14.1)

Pure-SwiftUI UIScrollView replacement, iOS 15+. Names per CLAUDE.md (`ZTronScrollView`, `ZTronScrollState`, …).

## View tree
```
ZTronScrollView<Content>                      body never reads hot values (S4.3)
└─ ViewportView                               fills proposal; .contentShape(Rectangle()); clipped (draw + hit-test)
   ├─ ContentLayoutHost                       Layout (16) | fixedSize+topLeading frame (15): proposes nil on scroll axes
   │  └─ content()  .modifier(TransformHost)  one Animatable GeometryEffect: translate · scale · alignment pad
   │     ├─ PresentationProbe (0×0)           reports presentation value per animation frame (transaction motion)
   │     └─ HitTestGate (leaf)                allowsHitTesting(false) while content moves without a finger
   ├─ Overlays: ScrollIndicators, RefreshIndicator, ScalingHeader   (read hot values in their own leaf bodies)
   ├─ FrameClockDriver: TimelineView(.animation(paused: idle)) → onChange(date) → state.step(to:)
   └─ GestureHost: pan ⊕ pinch ⊕ catch (see Gesture composition), keyboard, accessibility actions
```
Two coordinate spaces are published: `ztronContent` (untransformed; frames stable while scrolling) and `ztronViewport`.

## Data flow
Input (finger, clock tick, command, transaction) → `ZTronScrollState` (`@MainActor`, single source of truth) → channels:
`offset`, `zoom` (hot), `metrics` (content size, insets, viewport; cold), `phase`/flags (cold). Observation-backed on 17+
(separate stored properties), one `ObservableObject` per channel on 15–16. Writes are `!=`-guarded and coalesced to one
publish per frame. `ZTronScrollPhysics` is pure: `state.step(to: date)` samples `AxisMotion` closed forms at `date − t0`.
The delegate (`ZTronScrollViewDelegate`, weak, never observed) is called in UIKit order (S11). Nested scrolling and
directional handoff go through `ScrollArbitration` (frozen 1.0.0).

## Target vs presentation
`TransformHost` is driven by **target** values; public `contentOffset` / `zoomScale` are **presentation** values.
- Finger tracking and the physics clock write both, every frame, unanimated (no `withAnimation` around per-frame writes).
- Transaction-driven changes (client `withAnimation`, `proxy.scrollTo`, position bindings, rotation, size/inset changes)
  write only the target inside the caller's transaction; `PresentationProbe` writes the presentation value each frame;
  phase stays `.animating` until `addAnimationCompletion` (17) fires or the probe is settled for 2 frames (15–16).
- Any touch during motion sets target = presentation (unanimated) and the motion stops where it is.
- Hot values never flow into a parent through a `Binding` (would rebuild the parent body every frame).

## Re-render tiers (verified with counters on every OS path)
| Reader | Updates |
|---|---|
| content with no dependency | never for scroll/zoom/refresh/collapse |
| `TransformHost`, indicators | every frame of motion |
| refresh indicator, header subviews reading progress | every frame of a pull/collapse |
| zoom-only reader (`ztronScrollCounterScaled`, LOD) | zoom changes only |
| `ZTronScrollReader` / geometry-change modifiers | when the derived `Equatable` value changes |
| phase / flag readers | phase transitions only |

## Formulas (details and units in M1-physics.md)
Bounds/axis: `min = −inset.start`, `max = max(min, content·s + inset.end − viewport)`; pad = alignment padding when content fits.
Decay: `x(t) = x₀ + v₀(r^{1000t} − 1)/(1000 ln r)`, `v(t) = v₀ r^{1000t}`, rest `x₀ − v₀/(1000 ln r)`; retarget `r′ = e^{−v₀/(1000Δ)}`.
Spring (critical, m=1, k=100, ω=10): `x(t) = x_T + (A + Bt)e^{−ωt}`, `A = x₀ − x_T`, `B = v₀ + ωA`.
Rubber band: `f(x) = (1 − 1/(xc/d + 1))·d`, `c = 0.55`; inverse `x = f·d/(c(d − f))`.
Zoom focal: content point `u = (o + p − pad(s))/s` stays under `p`: `o′ = pad(s′) + s′u − p`, then clamp.
Resize (S7): keep the content point at the visible center: `o′ = pad′ + s′u_c − c′`, where `c′` is the new visible center.

## Gesture composition
All gestures live on `ViewportView` in the untransformed viewport space, never on the transformed content.
- **Pan**: `DragGesture(minimumDistance: 10)`; baseline set at recognition; `offset = baseline − translation` (never
  accumulated), rubber band applied/inverted at the edges; directional lock and axis mask; release velocity from
  `VelocityTracker` (own samples), `DragGesture.Value.velocity` only as fallback.
- **Pinch**: `MagnifyGesture` (17) with live centroid from `SpatialEventGesture` (used from 26, D34) | `MagnificationGesture` (15) with
  the pan location as focal estimate. Both `.simultaneousGesture` with pan (two-finger pan while pinching).
- **Catch**: `SpatialEventGesture` (used from 26, D34) | `DragGesture(minimumDistance: 0)` (15): first touch stops any motion,
  sets target = presentation, and disables content hit-testing while the content was moving (S6 "touch during motion").
- Keyboard: `focusable` + `onKeyPress` (17) | hidden `keyboardShortcut` buttons. Accessibility: `accessibilityZoomAction`
  (16) | named actions. Refresh and header read the same pan through `ZTronScrollState`, not their own gestures.

## Availability matrix (checked by hand against the Xcode 27 SDK; see M1-physics.md §6 for the resolver)
| Capability | Preferred | Min iOS | Fallback (15+) |
|---|---|---|---|
| per-property observation | `@Observable` | 17 | one `ObservableObject` per channel |
| layout without proposal change | `Layout` | 16 | `fixedSize` + top-leading frame |
| geometry callbacks | `onGeometryChange` `(newValue)` overload; `(old, new)` is 18 | 16 (back-deployed) | `GeometryReader` + `PreferenceKey` |
| render-time child effects | `visualEffect` | 17 | leaf modifier reading geometry |
| raw touches / centroid / timestamps | `SpatialEventGesture` | 26 (API 18; D34) | `DragGesture(minimumDistance: 0)` |
| pinch | `MagnifyGesture` (+ centroid 18) | 17 | `MagnificationGesture` + drag focal estimate |
| input kinds (pointer/pencil) | `GestureInputKinds` (iOS 27 SDK only: `#if compiler(>=6.4)`) | 27 | — (all inputs treated as direct touch) |
| curves | `Spring` / `UnitCurve` | 17 | own closed forms (physics package) |
| animation completion | `Transaction.addAnimationCompletion` | 17 | probe settled 2 frames |
| unanimated writes | `withTransaction(\.disablesAnimations, true)` | 17 | `withTransaction(Transaction)` |
| keyboard scrolling | `focusable` + `onKeyPress` | 17 | hidden `keyboardShortcut` buttons |
| accessibility zoom | `accessibilityZoomAction` | 16 | named accessibility actions |
| haptics | `sensoryFeedback` | 17 | none (documented) |
| coordinate spaces | `NamedCoordinateSpace` | 17 | `coordinateSpace(name:)` |
| subview-aware containers | `Group(subviews:)`, `ContainerValues` | 18 | explicit child modifiers |
| bounce behavior type | `BounceBehavior` → `ScrollBounceBehavior` (one way) | 16.4 | `ztronScrollBounceBehavior(_:axes:)` |
| frame clock | `TimelineView(.animation)` | 15 | — |

## Limitations
- 15–17 pinch focal accuracy is estimated (no live centroid): error can exceed 0.5 pt; 18+ meets ≤ 0.5 pt.
- 15–16: no haptics on refresh trigger; no pointer/pencil distinction below 27 (or when built with Xcode 26.x).
- `.scrollBounceBehavior(_:axes:)` set on an ancestor is not honored: `ScrollBounceBehavior` is opaque and not `Equatable`,
  so it cannot be read back without reflection. Use `ztronScrollBounceBehavior(_:axes:)` (same cases). SPEC S8 parity gap.
- Transaction-driven motion depends on the probe firing per frame; if a one-frame lag is measured, the presentation value is
  computed from the timeline date inside `TransformHost` and published in the same tick (S5).
- iOS 15/16 runtimes cannot run on this Mac: those paths are exercised by the forced-fallback switch here and smoke-tested
  with Xcode 26.x by the user.
