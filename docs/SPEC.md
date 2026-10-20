# ZoomScroll: Specification & Orchestration

This is the single source of truth for building **ZoomScroll**, a pure-SwiftUI replacement for UIScrollView, with Claude Code on a Max 20x plan.

| Part | Sections | What it covers |
|---|---|---|
| I · Specification | S1–S16 | What to build. Written as instructions to the implementing agent. |
| II · Orchestration | O1–O10 | How to build it while using as little of your plan as possible, by hand or on autopilot. |
| III · Files | F1–F7 | Files you create once: settings, scripts, hook, subagents, CLAUDE.md, progress templates. |

**How to use it:**
- Commit this file to the repo as `docs/SPEC.md`.
- Sessions read only the sections their task names, by line range. `grep -n '^## [SOF][0-9]' docs/SPEC.md` lists every section with its line number. Never load the whole file into a session.
- **Target spend:** ~0.85–1.25 weekly Max 20x limits run by hand, ~0.95–1.5 on autopilot. These are estimates; calibrate them as described in O7.

---

# Part I · Specification

## S1 · Role and goal

You are a senior iOS engineer who knows UIScrollView's exact behavior and SwiftUI's rendering, invalidation, gesture and availability model in depth.

Build `ZoomScrollView`, a pure-SwiftUI reimplementation of UIScrollView + UIScrollViewDelegate for arbitrary SwiftUI content.

UIScrollView behavior to reproduce:
- pan with momentum and fling acceleration
- rubber-band bounce
- pinch-zoom with zoom bounce
- paging and directional lock
- insets and indicators
- programmatic scrolling and zooming

On top of that:
- **The entire SwiftUI ScrollView API through iOS 27**: every initializer shape, modifier, type and behavior, including ScrollViewReader. Use the same names wherever Swift allows (S8).
- **A refresh facade** in the style of Refresher (S9).
- **A scaling header** in the style of Exyte's ScalingHeaderScrollView (S10).

Requirements:
- Deploys to iOS/iPadOS 15.0. Newer, better APIs are used behind availability checks, each with a working fallback.
- `contentOffset` and `zoomScale` are observable and always equal what's on screen, frame by frame, whatever drives the motion.
- Every change not driven directly by a finger is animated.
- Scrolling, zooming, refreshing and header collapse never re-evaluate the content's body. Only views that explicitly depend on offset/zoom update, and only when that dependency changes.
- On rotation and any other viewport resize, the visible center is preserved.

## S2 · Hard constraints

- **Allowed imports:** SwiftUI, Combine, Observation (gated) and Foundation. CoreGraphics value types are fine. Also ScrollArbitration (S16), a small shared package that itself imports only SwiftUI and Foundation.
- **Not allowed:** UIKit/AppKit, *Representable types, UIHostingController, CADisplayLink, introspection, Mirror/reflection into SwiftUI internals, private API. Don't wrap SwiftUI's ScrollView. The one exception is the MC spike app (S16), which no library target depends on.
- **Minimum deployment:** iOS/iPadOS 15.0, the lowest Xcode 27 accepts.
  - Every newer API sits behind `if #available` / `@available`.
  - Each gated API has a fallback that keeps the same public API and behavior.
  - Document any behavioral difference a fallback can't avoid.
- **Language and isolation:** Swift 6 language mode. UI state is @MainActor. Physics types are Sendable value types.
- **Content:** any `View`, built once by the caller. Impose no protocol, Equatable or id requirements on it.
- **Ambiguity:** match the native SwiftUI ScrollView first, then UIScrollView. Note the decision; don't stop to ask.

## S3 · Availability strategy

| Capability | Preferred (gated) | Fallback |
|---|---|---|
| Per-property observation | Observation (17) | one ObservableObject per channel: offset, zoom, metrics, phase |
| Layout without proposal changes | `Layout` (16) | `fixedSize` on scrollable axes + top-leading viewport frame |
| Geometry callbacks | `onGeometryChange` (16) | GeometryReader + PreferenceKey |
| Render-time child effects | `visualEffect` (17) | leaf modifier reading geometry |
| Raw touches: catch, centroid, timestamps | `SpatialEventGesture` (18) | `DragGesture(minimumDistance: 0)` |
| Pinch | `MagnifyGesture` (17) + live centroid (18) | `MagnificationGesture` + drag-location focal estimate |
| Pointer / indirect / pencil input | gesture input kinds (27) | — |
| Curves | `Spring` / `UnitCurve` (17) | own closed forms |
| Animation completion | `Transaction.addAnimationCompletion` (17) | presentation probe settled for 2 frames |
| Unanimated writes | `withTransaction(\.disablesAnimations, true)` (17) | `withTransaction(Transaction)` |
| Keyboard scrolling | `focusable` + `onKeyPress` (17) | hidden Buttons with `keyboardShortcut` |
| Accessibility zoom | `accessibilityZoomAction` (16) | named accessibility actions |
| Haptics (refresh trigger) | `sensoryFeedback` (17) | none; document it |
| Coordinate spaces | `NamedCoordinateSpace` (17) | `coordinateSpace(name:)` |
| Subview-aware containers | `Group(subviews:)`, container values (18) | explicit child modifiers |
| Frame clock | `TimelineView(.animation)` (15) | — |

- The public API is identical on every OS. Reader APIs give the same update granularity everywhere. On 17+, direct property reads also auto-track.
- Add a DEBUG/test switch that forces each fallback on newer OSes, so CI exercises every path.
- Xcode 27 builds for iOS 15 but only runs and debugs iOS 17+. Also smoke-test iOS 15/16 with Xcode 26.x.

## S4 · Performance contract (top priority)

1. **Offset and zoom are render-time transforms only.** The content's proposal, size and layout never change while scrolling, zooming, refreshing or collapsing a header.
2. **Content identity is structurally stable:** no AnyView, no conditionals around it, no changing `.id`. Its @State, animations and gestures survive zoom, rotation and paging.
3. **Hot values (offset, zoom, velocity) are read only in leaf scopes:**
   - the transform modifier (its `content` placeholder isn't re-evaluated)
   - the overlays: indicators, refresh indicators, the scaling header
   - opt-in readers

   The container's own body never reads hot values.
4. **Re-render tiers.** Verify each with counters, on every OS path:
   | Reader | Updates when |
   |---|---|
   | content with no dependency | never, due to scroll, zoom, refresh or header collapse |
   | transform modifier, scroll indicators | every frame of motion |
   | refresh indicator, header subviews reading collapse progress | every frame of a pull or a collapse |
   | view reading only zoom | zoom changes only, not pure panning |
   | `ZoomScrollReader` / geometry-change modifiers | only when the derived Equatable value changes |
   | view reading phase / flags | phase transitions only |
5. **Hot and cold values stay separate:** separate stored properties on 17+, separate channels on 15–16. Never put them in one struct, which would wake every reader every frame. Guard writes with `!=` and publish at most once per frame.
6. **Never mirror hot values into a parent's state through a Binding.** That re-runs the parent body and rebuilds the content every frame. Document why.
7. **Zero idle cost:** the frame clock is paused whenever nothing moves.

## S5 · Architecture (recommended; deviate only with a stated reason)

### View structure

- **Viewport (outer view):**
  - Fills the proposal.
  - Owns the gestures (`.contentShape(Rectangle())`), clipping of both drawing and hit-testing, the overlays (indicators, refresh indicators, scaling header), and the frame-clock driver.
  - Observes its size and safe-area insets, keyboard included.
  - Gestures use this untransformed coordinate space, never the transformed content's.
- **Content layout:**
  - Viewport-sized. Like ScrollView, it proposes `nil` on scrollable axes and the viewport length on the others, and places the content at the origin.
  - Measures the unscaled content size.
  - Publishes two coordinate spaces: one for the untransformed content (frames there don't change while scrolling) and one for the viewport.
- **Transform host:**
  - A ViewModifier on that layout container. It reads the target values and applies one Animatable `GeometryEffect` covering translation, scale and alignment padding.
  - At rest, pixel-snap the result using `displayScale`.

### Target vs. presentation values

The transform is driven by *target* values. The public `contentOffset`/`zoomScale` are *presentation* values.

- Finger tracking and the physics clock write both, every frame, unanimated.
- Transaction-driven changes write only the target, inside the caller's transaction, so SwiftUI interpolates the transform in lockstep with the rest of the UI. These include:
  - client `withAnimation`
  - `withAnimation { proxy.scrollTo(…) }`
  - position bindings
  - rotation
  - content-size and inset changes
- During transaction-driven motion:
  - A zero-size probe inside the transformed content reports the presentation value every animation frame. Verify that it really fires per frame.
  - The phase stays `.animating` until completion.
- A touch during any motion sets target = presentation, unanimated, so the motion stops exactly where it is.

### Model, physics and clock

- **Model:** `@MainActor final class ZoomScrollState` (iOS 15+).
  - It is the single source of truth.
  - Observation-backed on 17+, channel-backed on 15–16.
  - The delegate is held weakly and never observed. The delegate-callback modifiers (S11, Amendment 2026-10-19 (user)) store their closures cold next to it; neither is observed.
  - Inject it into the environment so descendants can opt in.
- **Physics:**
  - Pure, unit-tested value types: velocity tracker, decay, critically damped spring, rubber band, target resolution, zoom solver.
  - Each axis is independent.
  - Use closed-form functions of elapsed time from the frame timestamp. No Euler integration over a variable dt.
- **Frame clock:**
  - `TimelineView(.animation(paused:))` in a tiny driver view → `onChange(of: context.date)` → `state.step(to:)`. Paused when idle.
  - Check for a one-frame lag between tick and render. If there is one, compute the presentation value from the timeline date inside the transform modifier and publish it in the same tick.
  - Verify 120 Hz on ProMotion devices. This may need the Info.plist key `CADisableMinimumFrameDurationOnPhone`.
- **Derived readers:**
  - They run their content closure only when the derived value changes.
  - They must not go stale when the caller's closure captures other changing inputs. One approach: a probe computes the value and writes the reader's state via `onChange`.

## S6 · Physics & behavior (UIScrollView parity; defaults match native SwiftUI ScrollView)

### Geometry

- `contentOffset` = the top-left of the visible area, in zoomed content coordinates.
- `contentSize` = unscaled size × `zoomScale`.
- `adjustedContentInset` = `contentInset` + safe area, per `contentInsetAdjustmentBehavior`.
- Per axis: min = −inset(start); max = max(min, contentSize + inset(end) − viewport).
- Content smaller than the viewport is placed per `defaultScrollAnchor(_:for: .alignment)`. Default: native behavior, or `.center` when zooming is enabled (Photos-like).

### Pan

- **Recognition:** DragGesture with ~10 pt hysteresis.
  - Set the baseline at recognition so the content doesn't jump.
  - offset = baseline − translation. Never accumulate deltas.
  - Support axes, scroll enabled and directional lock.
- **Rubber band** past an edge: f(x) = (1 − 1/(x·c/d + 1))·d, with c = 0.55 and d = the viewport length on that axis.
  - When catching content mid-bounce, invert it (x = f·d / (c·(d − f))) to rebuild the baseline without a jump.
- **Bounce:** support SwiftUI's `ScrollBounceBehavior` (.automatic, .always, .basedOnSize) per axis, plus UIKit-style bounces/alwaysBounce knobs.
- **Release velocity:**
  - Use your own tracker over the last ~100 ms of timestamped samples.
  - It is ≈ 0 if the finger rested for ~50–80 ms before lifting (tune this).
  - `DragGesture.Value.velocity` (17+) is only a fallback.
- **Release in bounds:**
  - Decay with decelerationRate r per ms (.normal 0.998, .fast 0.99).
  - Position: x(t) = x₀ + v₀·(r^(1000t) − 1)/(1000·ln r). Rest point: x₀ − v₀/(1000·ln r). Units: v₀ in pt/s, t in s.
  - Before starting, resolve the target: first the scroll target behavior, then the delegate's `willEndDragging` (velocity in pt/ms).
  - If the target changed, re-solve r′ = exp(−v₀/(1000·Δ)) so the motion lands exactly on it.
  - Fall back to a critically damped spring seeded with v₀ if the direction disagrees, v₀ ≈ 0, or r′ is implausible (e.g. outside 0.98…0.9995).
- **Decay that crosses an edge:** at the crossing, hand off to a critically damped spring toward the edge, carrying the current velocity. Without bounce, stop at the edge.
- **Release out of bounds:** spring back, seeded with the release velocity. As in UIKit, this counts as decelerating (`willDecelerate == true`).
- **Spring starting point:** critically damped, mass 1, stiffness ≈ 100. Calibrate against the native feel.
- **Fling acceleration:** a quick fling that starts while still decelerating in the same direction carries over the remaining momentum. Cap it, and calibrate against a native ScrollView.
- **Rest:** stop when |v| and the remaining distance fall below thresholds, then snap to pixels.
- **Touch during motion:** a touch during deceleration, bounce or animation stops the motion instantly.
  - That touch must not activate content controls.
  - Implement this by disabling content hit-testing while the content moves without a finger, via a leaf modifier.
- **Paging:** `isPagingEnabled` behaves the same as `.scrollTargetBehavior(.paging)`. Page size = viewport size; at most one page per gesture.

### Programmatic

- **Commands:** `setContentOffset(_:animated:)`, `scrollRectToVisible(_:animated:)` (with minimal movement), `scrollToTop(animated:)`, and every SwiftUI positioning API in S8.
- **Two animation paths:**
  - Explicit `animated:` / `animation:` runs on the physics clock. The default approximates UIKit's (~0.3 s); Spring/UnitCurve can override it.
  - `withAnimation` runs as a transaction (S5).
- Retargeting preserves velocity. `didEndScrollingAnimation` fires on completion.
- **`stopScrollingAndZooming()`:** the offset stays where it is, except that a bouncing view returns to the edge and a paging view settles on a page boundary.

### Zoom

- **Pinch**, run simultaneously with pan:
  - The content point under the pinch centroid stays under it, including two-finger panning while pinching.
  - Error ≤ 0.5 pt on 18+. Document the accuracy of the fallbacks.
  - Focal math includes insets and alignment padding.
- **Limits:** absolute, or relative to fit/fill (recomputed on resize). Zooming is enabled iff max > min. The default is 1…1, as in UIKit.
- **Past the limits, with `bouncesZoom`:**
  - Apply resistance in log space.
  - On release, spring to the nearest limit, anchored at the last centroid, while the offset settles into bounds.
  - `isZoomBouncing` is true during this. `didEndZooming(atScale:)` fires after the bounce.
  - No zoom momentum.
- `setZoomScale(_:animated:)` anchors at the visible center.
- `zoom(to:animated:)` fits and centers the rect.
- Optional double-tap-to-zoom helper (off by default).

### Also

- **Indicators:** the iOS look (thin capsule, minimum length, shrinks while rubber-banding, fades after idle), plus flash, per-axis visibility and insets.
- **Refresh:** see S9. It replaces any simpler pull-to-refresh.
- **Keyboard scrolling:** arrows, space, page up/down, home/end.
- **Accessibility:** scroll and zoom actions, and page announcements.
- **Helpers built as leaf modifiers:**
  - `.zoomScrollCounterScaled()` keeps a constant on-screen size (e.g. map pins).
  - sticky and parallax helpers
  - a quantized-zoom LOD reader
- **UIKit APIs that don't apply** (document the mapping):
  - contentLayoutGuide/frameLayoutGuide → coordinate spaces
  - pan/pinch gesture recognizers → phase and flags
  - tvOS-only APIs are out of scope

## S7 · Rotation & resize: the visible center is preserved (hard requirement)

- **Scope:** every viewport size change, including rotation, Split View/Slide Over, Stage Manager window resizes, and fold/unfold on foldables.
- **Definition:** the visible center is the content point (in unscaled content coordinates) at the center of the unobscured viewport. The unobscured viewport is the bounds inset by `adjustedContentInset`, plus a scaling header's current height (S10). After the resize, the same point must be at the new unobscured center.
- **Zoom:** if it was at fit before, it stays at fit after (recomputed). Otherwise keep the `zoomScale`, clamped to the new limits.
- **Bounds:** clamp only as much as the content edges require. Never leave the offset out of bounds.
- **Reflowing content** (content that reflows on the non-scrolling axis): keep the item at the center (the nearest registered target), and the relative position within it.
- **Paging / view-aligned:** the centered page or target stays current and is re-snapped.
- **Scaling header:** keeps its collapse progress.
- **Motion in progress** stops at its presentation value first.
- **Animate in lockstep with the system transition:** no jump frame, no lag.
  - Suggested approach: make the GeometryEffect a pure function of its own `size` (the animated viewport size), the committed target values, and the viewport size they were committed for.
  - Then commit the re-derived target without animating again.
- **Override:** only an explicit developer `defaultScrollAnchor(_:for: .sizeChanges)` may override this; document that. Content-size and inset changes follow `.sizeChanges` semantics.
- **Coverage:** must work on every OS path, including the iOS 15 geometry fallback.

## S8 · SwiftUI ScrollView API parity (iOS 13 → 27)

SwiftUI's own implementations are private and tied to its UIKit-backed ScrollView. Use these strategies, in order:

1. **Environment-backed modifiers work unchanged**, wherever they're applied. Read the public EnvironmentValues (gated):
   - `isScrollEnabled` (`scrollDisabled`)
   - `horizontal/verticalScrollIndicatorVisibility` (`scrollIndicators`)
   - `horizontal/verticalScrollBounceBehavior` (`scrollBounceBehavior`)
   - `scrollDismissesKeyboardMode` (`scrollDismissesKeyboard`)
   - `refresh` (`refreshable`, routed through the refresh facade, S9)

   Safe-area modifiers (`safeAreaInset`, `safeAreaPadding`, `safeAreaBar`) feed `adjustedContentInset` naturally. Audit EnvironmentValues for any other public scroll-related key.
2. **Scroll-view-level modifiers with private state** get two forms:
   - Members of `ZoomScrollView` with the same name and signature, returning `ZoomScrollView`. That way `ZoomScrollView { … }.scrollTargetBehavior(.paging).scrollPosition($pos)` just works, even on OSes older than SwiftUI's own version.
   - A `zoomScroll`-prefixed View modifier (environment-backed) that works anywhere above the scroll view. It also applies SwiftUI's native modifier when available, so one call site configures native and zoom scroll views alike.

   Unprefixed spellings only bind when applied directly to the ZoomScrollView; document this.
3. **Content-level modifiers** are `zoomScroll`-prefixed and dual-mode: our implementation inside a ZoomScrollView (detected via the environment), SwiftUI's native one otherwise.
4. **Types:** accept SwiftUI's own value types on OSes where they exist and can be constructed or inspected publicly. Otherwise mirror them 1:1 with a `ZoomScroll` prefix, plus conversions.
   - Never rely on overload or shadowing tricks that make existing call sites ambiguous.
   - Adopt a technique that lets SwiftUI's original spellings bind unambiguously (including on content) only if compile tests prove it.

**Inventory.** Implement every item and track it in the parity matrix (API → strategy → min OS → fallback → tests).

- **Creation**
  - `ScrollView(_:showsIndicators:content:)` / `ScrollView(_:content:)` shapes; default axis `.vertical`.
  - `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` → `ZoomScrollViewReader` / `ZoomScrollViewProxy` with the identical API. The proxy:
    - searches every ZoomScrollView inside the reader (first match wins, like SwiftUI)
    - forwards to native ScrollViews inside through an internal SwiftUI ScrollViewReader
    - honors `withAnimation`
  - Targets are registered with `.zoomScrollID(_:)`, which also applies `.id(_:)`. SwiftUI's explicit ids aren't publicly observable.
- **Position**
  - `scrollPosition(_:anchor:)` with `ScrollPosition` (scrollTo id/edge/point/x/y; viewID, point, edge, isPositionedByUser)
  - `scrollPosition(id:anchor:)`
  - `defaultScrollAnchor(_:)`
  - `defaultScrollAnchor(_:for:)` + `ScrollAnchorRole` (initialOffset, sizeChanges, alignment)
- **Targets**
  - `scrollTargetBehavior(_:)`, `scrollTargetLayout(isEnabled:)`, `ScrollTarget`
  - `ScrollTargetBehavior` with its Context, Properties and PropertiesContext
  - `PagingScrollTargetBehavior`, `ViewAlignedScrollTargetBehavior` (limit behaviors incl. alwaysByOne/alwaysByFew), `AnyScrollTargetBehavior`
  - Custom behaviors' `updateTarget(_:context:)` must run with real velocity and geometry.
- **Transitions**
  - Both `scrollTransition` overloads, `ScrollTransitionPhase`, `ScrollTransitionConfiguration` (animated, interactive, identity, threshold).
  - Evaluate them at render time (`visualEffect` on 17+) so no bodies re-run; use a leaf-modifier fallback on 15–16.
- **Observation**
  - `onScrollGeometryChange(for:of:action:)` + `ScrollGeometry`
  - `onScrollPhaseChange` (both overloads) + `ScrollPhase` + `ScrollPhaseChangeContext`
  - `onScrollVisibilityChange(threshold:_:)`
  - `onScrollTargetVisibilityChange(idType:threshold:_:)`
- **Indicators**
  - `scrollIndicators(_:axes:)`, `scrollIndicatorsFlash(onAppear:)`, `scrollIndicatorsFlash(trigger:)`, `ScrollIndicatorVisibility`, `showsIndicators:`
- **Content & insets**
  - `contentMargins(_:_:for:)` (scroll content vs. indicators), `safeAreaPadding`
  - `scrollClipDisabled(_:)`, `scrollContentBackground(_:)`, `ScrollContentOffsetAdjustmentBehavior`
  - Every `containerRelativeFrame` overload, resolved against this viewport.
- **Behavior**
  - `scrollDisabled`
  - `scrollBounceBehavior(_:axes:)` + `ScrollBounceBehavior`
  - `scrollDismissesKeyboard(_:)` + `ScrollDismissesKeyboardMode`
  - `scrollInputBehavior(_:for:)` + `ScrollInputKind` / `ScrollInputBehavior`
  - `refreshable` (via S9)
- **Edge effects (26+)**
  - `scrollEdgeEffectStyle(_:for:)`, `scrollEdgeEffectHidden(_:for:)`, `ScrollEdgeEffectStyle`
  - `safeAreaBar(edge:alignment:spacing:content:)`, plus `backgroundExtensionEffect()` inside content
  - Emulate the soft/hard edge treatment in pure SwiftUI, with a plain fallback.
- **Containers (27+)**
  - `swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)` + `swipeActionsContainer()`
  - `reorderable()` + `reorderContainer(for:isEnabled:move:)`
  - Both must work inside the view, including edge auto-scroll during a reorder drag if public API allows it (otherwise document the gap).
- **Lazy containers**
  - SwiftUI's Lazy stacks/grids rely on a native ScrollView to be lazy, so here they load eagerly.
  - Provide virtualizing equivalents driven by `visibleRect`: `ZoomLazyVStack`, `ZoomLazyHStack`, `ZoomLazyVGrid`, `ZoomLazyHGrid`, with `pinnedViews`.
  - `scrollTo` for items that aren't materialized yet: jump to an estimated position, then refine as items appear.
- **System integrations that observe the UIKit scroll view**
  - Large-title collapse, `toolbarMinimizationBehavior`, `tabBarMinimizeBehavior`, status-bar tap to scroll to top.
  - Verify what's achievable in pure SwiftUI, document the rest, and expose hooks.

## S9 · Refresh facade

One refresh engine sits behind every pull-to-refresh entry point:
- SwiftUI's `.refreshable`, read from `@Environment(\.refresh)`. Its default style is `.system`.
- A Refresher-shaped API (below), so code written for Refresher on a SwiftUI `ScrollView` ports by swapping in `ZoomScrollView`.
- ~~The scaling header's `pullToRefresh` / `pullToLoadMore` (S10).~~ **Amendment 2026-10-19 (user): removed.** The scaling header
  has no pull-to-refresh, load-more or reach-edge API of its own. A header-equipped scroll view *is* a `ZTronScrollView`, so the two
  entry points above (the `refresher(…)` members / `ztronRefresher` twins, and `.refreshable`) plus `onZTronScrollReachEdge` are the
  only refresh and reach-edge API, with or without a header. The indicator's place relative to the header is in S10 "Refresh with
  the header". (Amendment text uses the repo names of the CLAUDE.md map; unamended text keeps the `ZoomScroll` spelling.)

If both `.refreshable` and an explicit refresher are set, the explicit one wins. Document this.

### API

Provide same-name members on `ZoomScrollView` and `zoomScroll`-prefixed View twins, per S8 strategy 2.

- **`refresher(style:overlay:action:)` with an async action.** Refreshing ends when the action returns.
- **The same, with a completion-handler action:** `(_ done: @escaping () -> Void) -> Void`. `done` is idempotent and safe to call from any thread; it hops to the main actor.
- **`refresher(refreshView:overlay:action:)`** with a custom indicator built from a `Binding<ZoomRefreshState>`.

**Mandatory shapes — Amendment 2026-10-19 (user).** The amendment removed only the scaling header's own refresh entry points; these two spellings
are guaranteed on `ZTronScrollView` (and as `ztronRefresher` twins): `.refresher { await load() }` — trailing closure, default loader (`.default`
style, built-in indicator) — and `.refresher(refreshView: { state in MyLoader(state) }) { await load() }` — custom view plus action. The
completion-handler forms are the same shapes with `{ done in … }` (overloads resolve by closure arity). Nothing here needs UIKit or introspection.

**Styles:**
- `.system` looks and moves like UIRefreshControl.
- `.default` lets the indicator follow the pull with its own, more flexible animation.
- `overlay: true` floats the indicator over fixed content, such as a header image, without pushing the content down.

**`ZoomRefreshState`:**
- `mode`: `.notRefreshing`, `.pulling`, `.refreshing`
- `modeAnimated`: the same value, delivered with animation
- `dragPosition`: 0…1 progress toward the trigger
- `style`
- `edge`

**`ZoomRefreshConfiguration`:**
- trigger distance
- indicator height / hold offset
- trigger mode: `.whilePulling` (fires as the threshold is crossed, like UIRefreshControl) or `.onRelease`
- minimum visible time
- reset animation
- allowed edges

Calibrate the defaults side by side with UIRefreshControl.

**Programmatic control:** `beginRefreshing()` and `endRefreshing()` on `ZoomScrollState`. Both animate the indicator in and out.

### Edges

- Top pull = refresh.
- Bottom pull = load more, with configurable bottom content padding while it's active.
- Horizontal scroll views get leading/trailing equivalents.
- Add `onZoomScrollReachEdge(_:threshold:perform:)`. It covers "did reach bottom" and fires once per arrival. Amendment 2026-10-19 (user):
  it is the only reach-edge API; the scaling header's former `scrollViewDidReachBottom` is gone.

### Behavior

- **Bounce:** attaching a refresher makes its edge bounce even when the content is shorter than the viewport, as UIKit does when a refresh control is set.
- **Pull:** uses the normal rubber band. `dragPosition` = pull ÷ trigger distance, clamped to 0…1.
- **While refreshing:**
  - The offset holds so the indicator stays visible below the top adjusted inset.
  - The user can still scroll away and back.
  - On completion, animate back to rest unless the user is tracking.
- **One action per pull.** Only one refresh runs at a time. Never call the action twice for one pull. Cancel the async task when the view disappears.
- **Disabled** while `zoomScale` is above minimum (configurable) and while scrolling is disabled.
- **Haptic at trigger:** `.sensoryFeedback` on iOS 17+. On iOS 15–16 there is no haptic, because UIKit isn't allowed; document this.
- **Accessibility:** add named "Refresh" and "Load more" accessibility actions, since VoiceOver and Switch Control users can't pull. Announce state changes.
- **Parity:** `didScroll` fires during the pull, and phase changes follow SwiftUI's rules.
- **Performance:**
  - Indicators live in the viewport overlay.
  - During a pull, only the indicator (including a custom one) updates per frame.
  - Content bodies never re-evaluate because of refresh state.

## S10 · Scaling header

> **Amendment 2026-10-19 (user).** This section is rewritten. The header is no longer a separate container type that mirrors
> ScalingHeaderScrollView's modifiers: it is one member on `ZTronScrollView`, `withScalingHeader(size:scalingBehavior:…)`; the
> header **precedes the content** (the first thing, above it, also on a horizontal scroll view); and the two reactions to a pull
> past the top are `.preserve` and `.stretch`. The refresh and reach-edge API is S9's only (no `pullToRefresh` /
> `pullToLoadMore` / `scrollViewDidReachBottom` here). Rules carried over from the previous text are tagged *(kept)*; the rest is
> new. Amendment text uses the repo names (CLAUDE.md map: `ZTron…`, `ztronScroll…`, `onZTronScroll…`); unamended text elsewhere in
> this document keeps the original `ZoomScroll` spelling. Porting from the reference is by the migration table at the end, not by
> swapping a type.

A banner-style header laid out as the first thing of the scroll view, above the content. It collapses from its resting height to a
minimum as the content scrolls up (shrinking from the bottom, its top edge pinned), stays at the minimum while the content scrolls by,
and reacts to a pull past the top either not at all (`.preserve`) or by growing with the pull (`.stretch`). The reference (Exyte) reaches the
underlying UIScrollView through UIKit introspection; that is forbidden here (S2) and this design uses none of it, nor reflection or private
API: the header is driven by our own offset state through a leaf modifier. (Amendment 2026-10-19 (user): confirmed, no introspection anywhere.)

### API (amended)

```swift
extension ZTronScrollView {
    /// Installs a scaling header above the content. Returns the same view type: every other member keeps working in
    /// any order, and the header-equipped view is still a ZTronScrollView (state, twins, readers, refresher, delegate).
    public func withScalingHeader<Header: View>(
        size: ZTronHeaderSize,
        scalingBehavior: ZTronHeaderScalingBehavior = .preserve,
        snap: ZTronHeaderSnap = .disabled,
        fade: ZTronHeaderFade? = nil,
        @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self
}
public enum ZTronHeaderSize: Equatable, Sendable {
    case fixed(min: CGFloat = 0, max: CGFloat)     // resting height = max, collapses to min; no measurement
    case aspectRatio(CGFloat, min: CGFloat = 0)    // resting height = width ÷ ratio (ratio = width/height, SwiftUI's convention); no measurement
    case fit(min: CGFloat = 0)                     // resting height = the header's ideal height at the scroll view's width (measured)
}
public enum ZTronHeaderScalingBehavior: Sendable { case preserve, stretch }
public struct ZTronHeaderSnap: Equatable, Sendable {
    public static let disabled: Self
    public static func immediately(at positions: [CGFloat] = [0, 1]) -> Self            // positions are collapse progress: 0 expanded, 1 collapsed
    public static func afterFinishAccelerating(at positions: [CGFloat] = [0, 1]) -> Self
}
public struct ZTronHeaderFade: Equatable { public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self }
public struct ZTronHeaderGeometry: Equatable, Sendable {
    public var progress: CGFloat        // 0 expanded … 1 collapsed
    public var height: CGFloat          // live height, stretch included
    public var stretch: CGFloat         // ≥ 0; always 0 under .preserve
    public var minHeight: CGFloat
    public var restingHeight: CGFloat   // the resolved resting height (the former `maxHeight`)
    public var width: CGFloat           // the scroll view's width
    public static func quantizedProgress(steps: Int) -> (ZTronHeaderGeometry) -> Int   // a transform for the reader: round(progress · steps)
}
/// Handle passed to the header builder. It exposes NO geometry, hot or cold: geometry is delivered only inside a reader scope.
public struct ZTronHeaderProxy: Equatable { }
/// Re-renders its content only when `transform(geometry)` changes (every frame for the identity form).
public struct ZTronHeaderGeometryReader<Value: Equatable, Content: View>: View {
    public init(_ header: ZTronHeaderProxy? = nil, of transform: @escaping (ZTronHeaderGeometry) -> Value,
                @ViewBuilder content: @escaping (Value) -> Content)
    public init(_ header: ZTronHeaderProxy? = nil, @ViewBuilder content: @escaping (ZTronHeaderGeometry) -> Content)
        where Value == ZTronHeaderGeometry
}
public enum ZTronHeaderSnapTarget: Equatable, Sendable { case expanded, collapsed, progress(CGFloat), height(CGFloat) }
extension ZTronScrollState {
    public var headerGeometry: ZTronHeaderGeometry? { get }               // hot (tracked on 17+); nil without a header; read it in leaves only
    public func snapHeader(to target: ZTronHeaderSnapTarget, animated: Bool = true)   // clamps; called before the first layout it applies at the first layout
}
extension ZTronScrollGeometry { public var header: ZTronHeaderGeometry? }  // for ZTronScrollReader / onScrollGeometryChange transforms
```

Call site (the user's sketch, kept):

```swift
ZTronScrollView(.vertical, showsIndicators: false) { … }
    .withScalingHeader(size: .aspectRatio(16/9), scalingBehavior: .stretch, fade: .linear(to: .black)) { header in
        Image("banner").resizable().scaledToFill()
            .overlay(alignment: .bottomLeading) { BannerTitle(header) }      // the "sticky overlay"
    }
struct BannerTitle: View {
    let header: ZTronHeaderProxy                                             // installed through the initializer
    var body: some View {
        ZTronHeaderGeometryReader(header, of: \.height) { h in Text("Title").font(.system(size: 17 + 0.1 * h)) }
    }
}
```

**The reactive-geometry pattern (why not an ObservableObject).** The header builder runs once, cold. Live geometry reaches a child only
through `ZTronHeaderGeometryReader`, a derived reader of the S4 tier table built on the same engine as `ZTronScrollReader` (tracked reads
on 17+, channel subscription on 15–16). Reasons (design M8b §2.5): an `ObservableObject` invalidates every observer every frame whatever
property it reads, so a quantized or "collapsed past 50 %" child could never be cheaper than per frame; an `@Observable` object is 17+
only and its per-property tracking buys nothing here because `height`, `progress` and `stretch` change together every frame; and an
object handed to the builder invites hot reads in the builder's own scope, which would re-run the whole header body per frame. The proxy
makes that impossible by construction. Children that take the proxy in their initializer, as in the sketch, update only inside their
reader scopes; children without a reader never update because of scrolling.

**Size variants.**
- `.fixed(min:max:)`: resting height `max`, collapse band `max − min`. Labels are mandatory (no positional `(100, 150)`), so the bounds
  can't be swapped silently.
- `.aspectRatio(r, min:)`: resting height `W / r`, `W` = the scroll view's (viewport) width. Recomputed when `W` changes (rotation) as a
  discrete inset change (S7 rules: the visible centre is preserved with the header captured). This is the "fit" case computed instead of
  measured and the right choice for an image banner: `.aspectRatio(16/9)` equals what an `Image` with `.aspectRatio(16/9, contentMode: .fit)`
  would measure to, without measurement machinery.
- `.fit(min:)`: resting height = the header's ideal height at width `W` (height proposed `nil`), measured per "Natural height" below
  *(kept)*; re-measured on width, Dynamic Type and (16+) header content changes, each a discrete inset change. Prefer `.fixed` /
  `.aspectRatio` when the height is known.
- `min` defaults to 0 (the header can collapse to nothing). `min ≥ resting` → fixed-height header ("Degenerate range").

**Removed API (amendment: replaced, never duplicated).** `pullToRefresh`, `pullToLoadMore` → `refresher(…)` / `ztronRefresher` /
`.refreshable` (S9); `scrollViewDidReachBottom` → `onZTronScrollReachEdge(.bottom)` (S9); `hideScrollIndicators` → `showsIndicators: false`
/ `scrollIndicators(.hidden)`; `height(min:max:)` → `size:`; `allowsHeaderGrowth` → `scalingBehavior: .stretch`; `allowsHeaderCollapse` →
always on (collapse = shrink from the bottom; the reference's slide-up mode is not offered); `setHeaderSnapMode` + `headerSnappingPositions`
→ `snap:`; `initialSnapPosition`, `snapHeaderToState` → `state.snapHeader(to:animated:)`; `collapseProgress(Binding)` →
`ZTronHeaderGeometryReader(of: \.progress)` or `ZTronScrollReader(of: { $0.header?.progress })` (S4.6 forbids mirroring a hot value into a
parent Binding); `scrollToTop(resetScroll:)` → `state.scrollToTop(animated:)`. There is no `ZTronScalingHeaderScrollView` type. Snap
positions and progress share one convention (0 = expanded, 1 = collapsed); the reference's inverse snap convention is gone.

### Behavior

**Placement: the header precedes the content (amended).**
- The header is the first thing of the scroll view: it occupies the first `R` points (its resting height) of the viewport's height, below
  the safe area and any `safeAreaInset` bar the app placed above, and the content starts below it. It is never laid out inside the content:
  its resting height is reserved as part of `adjustedContentInset.top` (`aci.top = safe.top + R + contentInset.top (+ refresh hold)`), the
  content's proposal, size and layout never change while the header collapses or stretches (S4.1), the header is drawn in the viewport
  layer above the content (z-order), and accessibility reads it before the content (sort priority).
- **Horizontal scroll views:** the header is stacked above the horizontally scrolling content, full viewport width, the same way (a top
  inset of `R`); the content's height proposal is the viewport height minus the header. The header is driven by the **vertical** offset
  only, so on a view whose `axes` exclude `.vertical` it is a fixed banner: no collapse, no stretch, `progress` 0, `stretch` 0 (`.stretch`
  is inert there; documented). With both axes, or when zoomed content pans vertically (D15), the vertical offset drives it as on a
  vertical view.
- `W` = the viewport width on every axis configuration.

**Geometry (amended; exact rules).** `top0 = safe.top` (the header's top edge, fixed); `R` resting height; `min`; `band = max(0, R − min)`;
`o′` = the header-relative offset = content offset + `aci.top` **excluding** the refresh hold, so rest is `o′ = 0`, a pull past the top is
`o′ < 0` and scrolling up is `o′ > 0` (the pan's rubber band already applies to `o′`, which gives the pull its feel); `c = clamp(o′, 0, band)`
(collapse travel); `g = max(0, −o′)` (overflow).

| | `.preserve` | `.stretch` |
|---|---|---|
| live height `h` | `R − c` | `R − c + g` |
| header frame / proposal | `(0, top0, W, h)` / `(W, h)`, clipped | same |
| top edge | pinned at `top0`, always | pinned at `top0`, always |
| pull past the top (`g > 0`) | no consequence on the header: height `R`; the content pulls away and a gap `g` opens between the header's bottom and the content's top (the scroll view's background shows; a refresh indicator lives there) | the header grows by `g` from its bottom edge; a `scaledToFill` child zooms in with the pull; the header's bottom edge stays glued to the content's top (no gap) |
| scroll up (`0 < o′ ≤ band`) | shrinks from the bottom, top pinned: `h = R − c` | same |
| past the band | `h = min`; the content scrolls by under it; with `min = 0` it has vanished | same |
| `progress` / `stretch` | `band > 0 ? c / band : 0` / `0` | same / `g` |

- The header is **clipped** to its frame and **proposed its live height**: an `.overlay(alignment: .bottom…)` inside it is laid out against
  the live frame, so it sticks to the moving bottom edge during both collapse and stretch (the "sticky overlay") and reads the live height
  through the reader to resize its own children. Laying the header out at a new height is a layout pass over the header subtree only; no
  body in the header or in the content is re-evaluated by it (a `GeometryReader` inside the header would be: that is why the reader exists).
- `fade:` draws a linear gradient from clear (at `start · h` from the top) to `color` (at the bottom edge) over the header, inside the live
  frame, above the header and below any refresh indicator. It has no hot reads: it follows the frame by layout.
- `h ≤ 0.5` ⇒ hidden from hit-testing and accessibility *(kept)*. Zoom: the header lives in viewport space and ignores the zoom scale *(kept)*.
- Nothing here forces bounce: `.stretch` shows only when the vertical axis can bounce (scrollable content with `.automatic`, or
  `scrollBounceBehavior(.always)`); DEBUG prints a note when `.stretch` is set on a view whose vertical axis cannot bounce. A refresher still
  forces bounce on its edge (S9).

**Natural height (`.fit`) (kept, adapted).** Measure the ideal height directly, never from the height on screen (which would feed back): on
16+ a `Layout` asks the single header instance for its ideal size while placing it at the live height; on 15 the host runs one measuring
layout pass (the header at its ideal height, cropped to the live frame, so nothing visible changes) at the first layout and on width or
Dynamic Type change, and caches the result; 15 cannot see header *content* changes (documented gap; use `.aspectRatio`/`.fixed`, or change
the header's identity). Never a hidden second copy. A new resting height is a discrete inset change (S7), never per frame.

**Zero height, degenerate range (kept).** `min` 0 → the header compresses to zero at full collapse and is hidden from hit-testing and
accessibility; a header made only of flexible views has (nearly) no natural height under `.fit` (DEBUG warning naming the fix: `.fixed`,
`.aspectRatio`, or `.frame(idealHeight:)`); `min ≥ R` (including `.fixed` with `min > max`) → fixed height `min`, no band, `progress` 0,
snapping off, `.stretch` still grows; DEBUG warning when both bounds were given that way.

**Refresh with the header (amended).** Only S9's API. The indicator placement follows from the live header height: with `.stretch` the
hold `H` stretches the header by `H` and the indicator floats over the stretched band (overlay placement whatever `overlay:` says, because
there is no gap); with `.preserve` the indicator sits in the gap between the header's bottom and the content's top (height `H` while
refreshing). Load-more at the bottom is unaffected by the header.

**Snapping (kept; convention amended).** Only inside the band; positions as collapse progress (0 expanded, 1 collapsed; default `[0, 1]`).
`.immediately` resolves the release target to the nearest position, velocity-aware, through the normal target pipeline after the user's
target behavior (design M8b Q3), so `willEndDragging` sees the snapped target. `.afterFinishAccelerating` animates to the nearest position
once deceleration ends inside the band. `state.snapHeader(to:animated:)` clamps `.height`/`.progress` to the range; called before the
first layout it applies at the first layout (replaces `initialSnapPosition`).

**Interaction (kept).** The header stays interactive (its buttons work); drags that start on it scroll the content; the content scrolls
under it.

**The live header height counts as part of the top inset (kept)** for scroll-indicator insets, pinned section headers in the ZTronLazy
stacks, `scrollTo` anchors (evaluated at the target), refresh-indicator placement and the visible centre (S7).

**Performance (amended tier table, S4.4).** The header builder runs once per cold change (install, resting height, width, Dynamic Type);
the header's frame modifier is a leaf that updates every frame of collapse/stretch and never re-evaluates the header's body;
`ZTronHeaderGeometryReader` content updates only when its derived value changes (every frame for the identity form, at most `steps + 1`
times per full collapse for `quantizedProgress(steps:)`); header children without a reader and all content never update because of
scrolling. Verify with render counters on both OS paths.

### Migration from ScalingHeaderScrollView (amended)

| Reference | ZTronScrollView |
|---|---|
| `ScalingHeaderScrollView { header } content: { content }` | `ZTronScrollView { content }.withScalingHeader(size: …) { _ in header }` |
| `.height(min: a, max: b)` | `size: .fixed(min: a, max: b)`; no 150/350 defaults *(kept)*: pass them |
| `.allowsHeaderGrowth()` | `scalingBehavior: .stretch` |
| `.allowsHeaderCollapse()` | the default (shrink from the bottom); the slide-up mode is not offered |
| `.setHeaderSnapMode(.immediately)` + `.headerSnappingPositions(snapPositions: [0, 0.5, 1])` | `snap: .immediately(at: [1, 0.5, 0])` (positions inverted: ours are collapse progress) |
| `.initialSnapPosition(initialSnapPosition: 0)` | `state.snapHeader(to: .collapsed, animated: false)` |
| `.snapHeaderToState(state: $s, animated:)` | `state.snapHeader(to:animated:)` |
| `.collapseProgress($p)` | `ZTronHeaderGeometryReader(header, of: \.progress) { p in … }` |
| `.scrollToTop(resetScroll: $b)` | `state.scrollToTop(animated: true)` |
| `.pullToRefresh(isActive:perform:)` / `.pullToLoadMore(isActive:contentOffset:perform:)` | `.refresher(…)` / `.refresher(edges: [.bottom], …)` (S9) |
| `.scrollViewDidReachBottom(perform:)` | `.onZTronScrollReachEdge(.bottom, perform:)` (S9) |
| `.hideScrollIndicators()` | `showsIndicators: false` |
| header closure receiving the progress every frame | `ZTronHeaderGeometryReader(header) { geo in … }` around the part that needs it |

## S11 · Public API (target shape; refine names if needed)

```swift
// Signatures only; everything iOS 15+ unless gated.
public struct ZoomScrollView<Content: View>: View {
    // ScrollView's shapes; zooming stays off until a zoom range is set.
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true,
                @ViewBuilder content: () -> Content)
    public init(_ axes: Axis.Set = .vertical, state: ZoomScrollState,
                @ViewBuilder content: () -> Content)
}
extension ZoomScrollView {   // S8 strategy 2: same-name members returning Self, e.g.
    public func scrollTargetBehavior(_ behavior: some ZoomScrollTargetBehavior) -> Self
    public func scrollPosition(_ position: Binding<ZoomScrollPosition>, anchor: UnitPoint? = nil) -> Self
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> Self
    public func zoomRange(min: ZoomScale, max: ZoomScale) -> Self   // .fit, .fill, .absolute(_)
    // S9 refresh facade (Refresher-shaped)
    public func refresher(style: ZoomRefreshStyle = .default, overlay: Bool = false,
                          action: @escaping () async -> Void) -> Self
    public func refresher(style: ZoomRefreshStyle = .default, overlay: Bool = false,
                          action: @escaping (_ done: @escaping () -> Void) -> Void) -> Self
    public func refresher<V: View>(refreshView: @escaping (Binding<ZoomRefreshState>) -> V,
                                   overlay: Bool = false,
                                   action: @escaping () async -> Void) -> Self
    // …one per inventory item, each with a `zoomScroll`-prefixed View-level twin
}

// S10 scaling header — Amendment 2026-10-19 (user): one member instead of a container type; full signatures in S10 "API".
extension ZTronScrollView {
    public func withScalingHeader<Header: View>(size: ZTronHeaderSize, scalingBehavior: ZTronHeaderScalingBehavior = .preserve,
                                                 snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil,
                                                 @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self
}
// ZTronHeaderSize (.fixed(min:max:) / .aspectRatio(_:min:) / .fit(min:)), ZTronHeaderScalingBehavior (.preserve / .stretch),
// ZTronHeaderSnap, ZTronHeaderFade, ZTronHeaderGeometry, ZTronHeaderProxy (exposes no geometry), ZTronHeaderGeometryReader,
// ZTronHeaderSnapTarget: see S10. No `height(min:max:)` and no `ZTronScalingHeaderScrollView`; the rules of the former doc
// comment (natural height, zero height, min ≥ max → fixed height, no 150/350 defaults) now live in S10 "Size variants" and
// "Zero height, degenerate range".

// Nested scrolling — Amendment 2026-10-20 (N-a/N-b, D28; behaviour in S12 "Nested ZTronScrollViews"):
public enum ZTronNestedScrollOwner: Sendable, Hashable { case inner, outer }
public struct ZTronNestedScrollPolicy: Sendable {
    public static let automatic: Self             // = .innerWhileScrollable (default): inner while it can follow, outer at its edge
    public static let innerWhileScrollable: Self
    public static let innerWhenZoomed: Self       // inner iff zoomScale > minimumZoomScale (rubber-bands at its edge), outer at min zoom
    public static let inner: Self                 // the container never takes a drag that starts here
    public static let outer: Self                 // this view never pans a shared on-axis drag (pinches stay)
    public static let independent: Self           // no arbitration with the nested container: both follow (today's behaviour)
    public static func custom(_ decide: @escaping @MainActor @Sendable (ZTronNestedScrollContext) -> ZTronNestedScrollOwner) -> Self
}
@MainActor public struct ZTronNestedScrollContext {   // built cold at the decision, never in a body
    public let geometry: ZTronScrollGeometry          // non-tracked snapshot of the inner (contentOffset, zoomScale, visibleRect, …)
    public let minimumZoomScale: CGFloat
    public let fingerDirection: FingerDirection       // ScrollArbitration's; not re-exported: naming it needs `import ScrollArbitration`
    public let canFollow: Bool                        // what .innerWhileScrollable would answer
    public init(geometry: ZTronScrollGeometry, minimumZoomScale: CGFloat, fingerDirection: FingerDirection, canFollow: Bool)
}
extension ZTronScrollView { public func nestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> Self }   // on the inner
extension View { public func ztronNestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> some View }   // environment twin; propagates; the member wins

@MainActor public final class ZoomScrollState {   // Observation-backed on 17+, channels on 15–16
    public private(set) var contentOffset: CGPoint        // presentation, hot
    public private(set) var zoomScale: CGFloat            // presentation, hot
    public private(set) var phase: ZoomScrollPhase        // mirrors ScrollPhase
    public var geometry: ZoomScrollGeometry { get }       // mirrors ScrollGeometry + zoomScale; tracks all hot values
    // + isTracking, isDragging, isDecelerating, isZooming, isZoomBouncing, isScrollAnimating, isZoomAnimating
    public weak var delegate: (any ZoomScrollViewDelegate)?   // never observed
    // UIKit commands: setContentOffset(_:animated:), setZoomScale(_:animated:), zoom(to:animated:),
    // scrollRectToVisible(_:animated:), scrollToTop(animated:), stopScrollingAndZooming(), flashScrollIndicators()
    // Refresh: beginRefreshing(), endRefreshing()
    // Scaling header (Amendment 2026-10-19 (user)): headerGeometry (hot, nil without a header), snapHeader(to:animated:);
    // ZoomScrollGeometry gains `header: ZTronHeaderGeometry?` for reader / geometry-change transforms.
}

public struct ZoomScrollViewReader<Content: View>: View {
    public init(@ViewBuilder content: @escaping (ZoomScrollViewProxy) -> Content)
}
public struct ZoomScrollViewProxy {
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil)   // identical to ScrollViewProxy
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint?, animation: ZoomScrollAnimation?)
}

// Derived observation on every OS: re-renders only when the mapped value changes.
public struct ZoomScrollReader<Value: Equatable, Content: View>: View {
    public init(_ state: ZoomScrollState? = nil,
                of transform: @escaping (ZoomScrollGeometry) -> Value,
                @ViewBuilder content: @escaping (Value) -> Content)
}
// ZoomScrollViewDelegate: 1:1 with UIScrollViewDelegate, all optional, receiving ZoomScrollState:
// didScroll, willBeginDragging, willEndDragging(withVelocity: /* pt/ms */, targetContentOffset: inout),
// didEndDragging(willDecelerate:), willBeginDecelerating, didEndDecelerating, didEndScrollingAnimation,
// willBeginZooming, didZoom, didEndZooming(atScale:), shouldScrollToTop, didScrollToTop,
// didChangeAdjustedContentInset. viewForZooming is replaced by the zoom range.
```

**Delegate call order must match UIKit:**
- **Scrolling:** willBeginDragging → didScroll… → willEndDragging → didEndDragging(willDecelerate:) → [willBeginDecelerating → didScroll… → didEndDecelerating].
- **Zoom:** willBeginZooming → didZoom (+ didScroll)… → [bounce] → didEndZooming(atScale:).
- **`didScroll`** fires for every offset change (including zoom, programmatic, transaction-driven motion and refresh pulls), at most once per frame.
- **SwiftUI-style callbacks** (phase, geometry, visibility) fire in the same order relative to these as in native.

### Delegate callbacks as modifiers — Amendment 2026-10-19 (user)

Every `UIScrollViewDelegate` method also exists as a modifier, an alternative to the delegate object. Names follow CLAUDE.md
(`onZTronScroll…`). Each is a member of `ZTronScrollView` returning `Self` (binds to that view only) and a same-name `View`
modifier (environment-backed; binds to every `ZTronScrollView` below it, nesting included, like the M7 observer twins). Applied
directly to a `ZTronScrollView` the member wins, so there is no ambiguity. Closures are `@MainActor` and receive the
`ZTronScrollState`, like the delegate.

| UIScrollViewDelegate | Modifier (member on `ZTronScrollView` → `Self`; twin on `View` → `some View`) |
|---|---|
| `scrollViewDidScroll(_:)` | `onZTronScrollDidScroll(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewDidZoom(_:)` | `onZTronScrollDidZoom(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewWillBeginDragging(_:)` | `onZTronScrollWillBeginDragging(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewWillEndDragging(_:withVelocity:targetContentOffset:)` | `onZTronScrollWillEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ velocity: CGPoint /* pt/ms */, _ targetContentOffset: inout CGPoint) -> Void)` |
| `scrollViewDidEndDragging(_:willDecelerate:)` | `onZTronScrollDidEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ willDecelerate: Bool) -> Void)` |
| `scrollViewWillBeginDecelerating(_:)` | `onZTronScrollWillBeginDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewDidEndDecelerating(_:)` | `onZTronScrollDidEndDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewDidEndScrollingAnimation(_:)` | `onZTronScrollDidEndScrollingAnimation(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `viewForZooming(in:)` | — no modifier: replaced by `zoomRange(min:max:)` |
| `scrollViewWillBeginZooming(_:with:)` | `onZTronScrollWillBeginZooming(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` (no zoom view) |
| `scrollViewDidEndZooming(_:with:atScale:)` | `onZTronScrollDidEndZooming(_ action: @MainActor @escaping (ZTronScrollState, _ scale: CGFloat) -> Void)` |
| `scrollViewShouldScrollToTop(_:)` | `onZTronScrollShouldScrollToTop(_ predicate: @MainActor @escaping (ZTronScrollState) -> Bool)` |
| `scrollViewDidScrollToTop(_:)` | `onZTronScrollDidScrollToTop(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |
| `scrollViewDidChangeAdjustedContentInset(_:)` | `onZTronScrollDidChangeAdjustedContentInset(_ action: @MainActor @escaping (ZTronScrollState) -> Void)` |

Coexistence with a delegate object:
- Both fire, from the same call sites, with the cadence and order above (`didScroll`/`didZoom` at most once per frame): the delegate
  first, then the modifiers in application order (environment twins outermost first, then the members).
- `willEndDragging`: `targetContentOffset` is threaded through the delegate, then each modifier in that order; the last value is the
  target the release lands on.
- `shouldScrollToTop`: the answer is the conjunction of the delegate's and every predicate's (any veto wins; `true` when none is set).
- Several modifiers of one kind all fire (they append, never replace), so a wrapper view can add its own without hiding the app's.
- Modifier closures are stored cold (config / environment, like the M7 observer boxes), never observed, replaced on every body
  evaluation of their owner (no stale closures) and removed when the view disappears. Attaching them re-evaluates no content body (S4).
- Velocity is in pt/ms as in UIKit and the delegate (`ZTronScrollPhaseChangeContext.velocity`, M7, stays pt/s like native SwiftUI).
- Design: M8-chrome §7b (task M8-8, on M7's `ObserverHub`).

## S12 · Gestures & content interaction

- **Recognizers:** pan with DragGesture, and pinch with MagnifyGesture (17+) or MagnificationGesture, composed simultaneously.
- **On 18+, also attach a simultaneous `SpatialEventGesture`** as a raw-touch observer. Use it for:
  - the touch-down "catch"
  - the exact multi-touch centroid
  - timestamped samples for the velocity tracker
  - one-finger-lift transitions

  On older OSes, use the S3 fallbacks.
- **On 27+, consider gesture input kinds** for pointer/indirect input (e.g. trackpad or mouse panning).
- **Choose between `.gesture`, `.simultaneousGesture` and `.highPriorityGesture` empirically** against the tests below. Arbitration changes between releases, so run them on 15/16 (Xcode 26.x), 17, 18 and 27.
  - A tap on a Button in the content fires. A pan that starts on a Button scrolls and doesn't fire it.
  - These keep working inside the content: Toggle, Slider (horizontal drag vs. vertical scroll), TextField, a nested horizontal native ScrollView, and (27+) swipe-action and reorderable rows.
  - Buttons in a scaling header work, and drags that start on the header scroll the content.
  - Lifting one finger mid-pinch continues as a pan.
  - Content scrolled outside the viewport receives no touches.
- **Approximate** `delaysContentTouches` and `canCancelContentTouches`, and document the gap.

### Inside a pager (ScrollArbitration)

When ZoomScroll sits in a page of a pager that provides a `ScrollArbiter` (ZTronPages does), it takes every swipe it can follow and the pager takes the rest. With no arbiter in the environment, the default, nothing in this subsection applies.

- **Contract.** Use ScrollArbitration 1.x exactly as S16 defines it. MC builds, proves and freezes it before M1.
- **Who wins.** The arbiter decides once per swipe, with the S16 rules:
  - swipes more than 30° off the pager's axis, and pinches, are ZoomScroll's;
  - a touch that catches either side's motion belongs to the side that was moving;
  - otherwise ZoomScroll gets the swipe if it can follow it along the pager's axis, and the pager gets it if not.
- **Register.** Read `@Environment(\.scrollArbiter)`. While on screen, register the viewport with its frame in `.named(arbiter.coordinateSpaceName)`; update the frame when it changes (a cold path, never per scroll frame); unregister on disappear.
- **Answer `canFollow(_:)`** from the presentation offset, adjusted insets, zoom, axes and scroll enabled: `true` only if the content can move with a finger going that way without rubber-banding. Content that fits on that axis answers `false`. `isMovingWithoutFinger` is true during deceleration, bounce and animation; `isZoomEnabled` mirrors the zoom range.
- **Ask before panning.** When the pan reaches its ~10 pt hysteresis (S6), call `owner(ofDragFrom:translation:touchCount:participant:)` with the start point in the arbiter's space.
  - `.participant`: proceed normally.
  - `.container`: ignore the whole touch sequence until every finger lifts. No baseline, offset change, rubber band, indicator flash, delegate callback or phase change.
  - Pinches don't ask: two-finger gestures are always ZoomScroll's.
- **Gesture names (iOS 18+).** Attach the pan, the pinch and the raw-touch observer with the `name:` variants of the gesture modifiers, using `scrollArbitrationGestureName`, so the pager's UIKit pan can run alongside them. On iOS 15–17 the pager handles this on its side.
- **Touch during motion.** The S6 catch still applies; the arbiter agrees, because a moving ZoomScroll owns the touch.
- **Scope.** The decision is made when each swipe starts. Reaching an edge partway through a swipe does not hand it to the pager; the next swipe pages. Mid-swipe takeover is deferred on both sides.

### Nested ZTronScrollViews — Amendment 2026-10-20 (N-a/N-b, D28; design `docs/design/NESTED-arbitration.md`)

A `ZTronScrollView` is the container of the `ZTronScrollView`s in its content, with nothing to declare: the same S16 rules, the same participant
code path as a ZTronPages pager. It is a pure-SwiftUI case (both recognizers are SwiftUI gestures in one hosting view on every OS 15+); the iOS ≤ 17 UIKit-pan
starvation of the pager case does not apply, and no gesture names are needed.

- **Default on.** With no modifier the policy is `.automatic` (= `.innerWhileScrollable`, UIScrollView parity): the inner takes a swipe it can follow on the
  outer's paging axis, the outer takes the rest; swipes more than 30° off the outer's axis and pinches are the inner's; a side that is moving keeps its catch.
  Different axes (a vertical list in a horizontal pager) fall out of rule 1. `.independent` restores the former behaviour (both follow the same drag).
- **Policy.** It replaces only the rule-5 answer inside the participant's `canFollow`; rules 1–4 always run. `.innerWhenZoomed` = the inner follows iff
  `zoomScale > minimumZoomScale`: at its edge while zoomed it rubber-bands and the page stays; at the minimum zoom the outer takes every on-axis swipe (the
  "pager unless zoomed" idiom). `.automatic` pages at the zoomed image's edge (UIScrollView). `.inner`, `.outer`, `.custom` (non-tracked
  `ZTronNestedScrollContext`) as in S11. Declared on the inner (`nestedScrollPolicy`) or by environment (`ztronNestedScrollPolicy`, member wins); the same
  answer feeds a ZTronPages pager that asks this view. `.independent` opts out of the nested container only: an external arbiter is still answered.
- **Outer side.** The outer's paging axis is its single *effective* axis (D15); an outer effective on two axes decides with the translation's dominant axis and
  no direction tolerance. A scroll-disabled or axis-less outer is not a container (the inner behaves as if alone; `ztronScrollDisabled(true)` on the outer is
  the "switch it off" idiom). The inner's frame is registered in a named space on the outer's *content*, so it does not change while the outer scrolls and
  registration stays cold (S4); the touch is converted to content coordinates at the ask.
- **D7 tracking timing.** An outer that contains at least one `ZTronScrollView` defers `beginTracking` (so `isTracking`, `willBeginDragging`) from touch-down
  to the owner decision at the hysteresis — the same deferral an inner already has under any arbiter. An outer with no inner behaves as before.
- **Decided once per swipe**, on both sides; the loser ignores the whole sequence (no baseline, offset change, rubber band, indicator, delegate or phase change).
  No mid-swipe hand-off in v1 (`synthesizePan` stays the route for a later `handsOffAtEdge`). Pinch while the outer owns the drag: the outer's DragGesture ends on
  the second finger and releases (settles or pages); the inner's pinch zooms. A pinch that starts on the inner, with both fingers down together, zooms it under
  every policy (demo UI test); a pinch whose second finger lands while the outer is already dragging cannot be scripted in XCUITest and stays a device check
  (the outer locks its content, `.disabled`, while it drags, so the inner's pinch is expected to start only after the drag ends).
- **`.independent` is not "both move".** Nobody is told to ignore the sequence, both recognize the drag, but the outer's drag starts at its hysteresis and
  locks its content, which cuts the inner's drag after a few points: on a zoomed image the outer pages and the image moves ~3 pt (demo UI test,
  `docs/progress/NESTED-s2.md`). That is the pre-N-a behaviour, kept.
- **Nested scroll views measure themselves independently.** On the fallback path (`GeometryReader` + preference keys, iOS 15 and whenever `onGeometryChange`
  is unavailable or forced off) the content-size and viewport preferences travel to every ancestor; each `ZTronScrollView` clears them for its ancestors
  (`MeasurementIsolation`, D30), otherwise an outer scroll view measures its inner's size and never scrolls.
- **Three levels (ZTronPages → outer → inner) are phase 2.** Each view talks only to its nearest container. When the pager wins a swipe, the middle view's `canFollow`
  does not yet OR in "an inner under the touch can follow", so that inner may still pan under the pager's swipe. Not needed for the scenario; known limitation.

## S13 · Pitfalls

- Driving `.position`, `.padding`, `.frame` or any other layout input from offset, zoom, refresh or header state.
- Wrapping the content in a GeometryReader (it changes the content's proposal).
- Applying `.drawingGroup()` to the content (zoom becomes blurry).
- Wrapping per-frame writes in `withAnimation` (double interpolation and lag).
- Taking release velocity from the last event only.
- Using `Date()` for time instead of the frame timestamp.
- Accumulating deltas through the rubber band (causes drift).
- Calling a newer API on an older OS path, or letting a fallback silently change behavior.

## S14 · Deliverables & acceptance

### 1. Design note first (≤ 1 page)

View tree, data flow, target/presentation model, re-render tiers, formulas, gesture composition, availability matrix, limitations.

### 2. A Swift package plus a demo app

The package is `ZoomScroll` (iOS 15+), plus the local `Packages/ZoomScrollPhysics` (see F1) and the shared `ScrollArbitration` 1.0.0 (S16, built in MC).

The demo app includes:
- **Core scrolling**
  - a large generated grid with coordinate labels (to check zoom, focal accuracy, sharpness and rotation)
  - a long list in the virtualized lazy stack, with pinned headers
  - a horizontal pager
  - a view-aligned carousel with scroll transitions
  - content full of controls
  - ScrollViewReader and ScrollPosition jump menus
- **Refresh and header**
  - a refresher gallery: system, default, overlay on an image, custom indicator, completion-handler variant, load-more, `.refreshable` mapping
  - a scaling-header profile screen (`.fixed` size, `.preserve`, avatar scale and title fade through the reader, both snap modes, system refresher) — Amendment 2026-10-19 (user): names per S10
  - a banner screen (`.aspectRatio(16/9)`, `.stretch`, fade, title font from the live height, overlay refresher, horizontal-axis toggle) — the former map-style header
- **Instrumentation**
  - a live state/phase readout and an event log of delegate + SwiftUI callbacks
  - per-tier render counters, measured fps, and an OS-path switch
- **Side-by-side screens** running the same code against:
  - each SwiftUI API group on a native ScrollView
  - Refresher on a native ScrollView, and `.refreshable` on a native ScrollView
  - ScalingHeaderScrollView

### 3. Swift Testing unit tests

Run each test on both the preferred and the forced-fallback paths.

- **Physics:**
  - decay projection
  - a re-solved target landing exactly
  - the rubber band: monotonic, always < d, and its inverse round-trips
  - spring settling
  - clamping with insets
  - the velocity tracker (a pause gives 0)
- **Zoom and layout:**
  - focal-point invariance
  - resize anchoring (center, fit, reflow, paging, scaling header)
  - target behaviors (paging, viewAligned limits, custom)
- **Callbacks:** delegate and SwiftUI-callback order.
- **Refresh:**
  - trigger thresholds per style and per trigger mode
  - `done` is idempotent; the task is cancelled on disappear; the action runs once per pull
  - the offset hold, and the animated return after refreshing
  - refresh is blocked while zoomed
- **Scaling header** (Amendment 2026-10-19 (user): names per S10):
  - height and progress math across the band for `.preserve` and `.stretch` (overflow: gap vs growth, top edge pinned, content top), the three `size` variants (`.aspectRatio` = `W / r` and its change on rotation), snapping (both modes, with velocity, positions as collapse progress)
  - `state.snapHeader(to:)`, including clamping `.height` / `.progress` to the resolved range and the before-first-layout case
  - inset-dependent placement: indicators, pinned headers, `scrollTo`, refresh indicator (in the gap under `.preserve`, over the stretched band under `.stretch`)
  - horizontal scroll view: header stacked above, fixed; both axes: driven by the vertical offset
  - render counters: header builder 0 runs and content body 0 runs per collapse / stretch; reader content runs == distinct derived values; `quantizedProgress(steps:)` ≤ steps + 1; header `@State` survives
  - natural height (`.fit`): re-measured on width (rotation), Dynamic Type and (16+) content changes, with the inset changing discretely; the 15 measuring pass gives the same resting height
  - zero-height cases: full collapse to 0, hidden from hit-testing and accessibility; a flexible-only `.fit` header, plus the DEBUG warning; `min` ≥ resting: fixed height, progress 0, no snapping, `.stretch` still grows
  - delegate modifiers (S11 amendment): each fires at the same site and in the same order as the delegate; `willEndDragging` target threading; `shouldScrollToTop` conjunction; attaching all of them re-evaluates no content body
- **Arbitration** (with `ReferenceScrollArbiter`):
  - registration, frame updates and unregistration
  - `canFollow` at every edge, zoomed in and at fit, with insets, with content that fits, and with scrolling disabled
  - a `.container` sequence leaves offset, phase, indicators and delegate untouched
  - pinches and touches during motion stay with ZoomScroll
  - with no arbiter, behavior is unchanged

### 4. Parity matrix

Every S8 inventory item and every S9/S10 API → strategy, min OS, fallback, test, and status (full / approximate / impossible, with the reason).

### 5. Acceptance report

For each item, state how it was verified (counters, `Self._printChanges()`, the SwiftUI Instruments template, or the side-by-side screens).

- **No content re-renders:** 0 content body evaluations, on every OS path, during:
  - a 3-second fling
  - a rubber band
  - a pinch with bounce
  - an animated programmatic scroll
  - `withAnimation { proxy.scrollTo }`
  - a rotation
  - a pull and a refresh
  - a header collapse
- **Readers:** a zoom-only reader doesn't update during pure panning; a quantized reader updates only when its bucket changes.
- **Pinch:** focal error ≤ 0.5 pt on 18+; report the fallback error.
- **Rotation:** keeps the visible center within 1 pt, with no jump frame. Check it at fit, zoomed in, near edges, in a pager, mid-deceleration, and with a scaling header.
- **Targets:** a fling lands exactly on a target modified by the delegate, a behavior, or header snapping.
- **Catch:** a touch during deceleration stops it without triggering a Button.
- **Ports:** these behave like the originals once ported by swapping the container type:
  - Apple's documentation examples for each SwiftUI scroll API
  - Refresher's examples
  - ScalingHeaderScrollView's examples, ported by the S10 migration table (Amendment 2026-10-19 (user)): `withScalingHeader(size: .fixed(min: 150, max: 350), …)` where they relied on its defaults, refresh through S9
- **Idle and fps:** no clock ticks at rest; fps on ProMotion is reported.
- **Inside a pager:** in ZTronPages, each swipe goes to ZoomScroll when it can follow it and to the pager otherwise, on 15/16 (Xcode 26.x), 17, 18 and 27. ZTronPages' G-14 suite runs the same checks from its side.

### 6. Known limitations of pure SwiftUI

Each one verified and stated honestly. Degrade gracefully; never fake them.

## S15 · Milestones

Budgets are in O4.

| # | Milestone |
|---|---|
| M0 | setup: Part III files; package skeleton `ZoomScroll` + `Packages/ZoomScrollPhysics` |
| MC | contract lock: ScrollArbitration 1.0.0, proven against a UIKit pager spike (S16) |
| M1 | availability scaffolding + physics + tests |
| M2 | container/transform + render-count proof (all OS paths) |
| M3 | pan/decay/bounce + delegate |
| M4 | zoom |
| M5 | rotation/resize |
| M6 | targets, positions, readers |
| M7 | observation APIs and transitions |
| M8 | indicators, insets, edge effects, keyboard, accessibility |
| M8b | refresh facade + scaling header |
| M9 | lazy containers |
| M10 | demo + parity matrix + report |

If you can run commands, build and test after each milestone. Ship complete code, with no TODOs or placeholders.

## S16 · ScrollArbitration contract (shared with ZTronPages)

ScrollArbitration is the only code ZoomScroll shares with the ZTronPages pager. MC builds it, proves it against a small UIKit pager spike, and freezes it as 1.0.0 before M1 starts. After that, both projects treat it as read-only.

### Package

- **Name:** `ScrollArbitration`, one library product of the same name. Swift 6 language mode.
- **Platforms:** iOS 15 and macOS 12. macOS exists only so the tests run on the host.
- **Imports:** SwiftUI and Foundation. No UIKit, no dependencies.
- **Size:** about 200–300 lines, plus tests.
- **Home:** built in `Packages/ScrollArbitration` (F1). At the end of MC it moves to its own Git repository, tagged `1.0.0`. ZoomScroll and ZTronPages both depend on it with `.upToNextMinor(from: "1.0.0")`.

### Public API (frozen at 1.0.0)

```swift
public enum FingerDirection: Sendable, Hashable { case left, right, up, down }   // screen space
public enum ScrollOwner: Sendable, Hashable { case participant, container }
public struct ScrollArbitrationToken: Sendable, Hashable { /* opaque */ }

@MainActor public protocol ScrollArbitrationParticipant: AnyObject {
    func canFollow(_ direction: FingerDirection) -> Bool   // false at an edge: no rubber-banding
    var isMovingWithoutFinger: Bool { get }                // deceleration, bounce, animation
    var isZoomEnabled: Bool { get }
}

@MainActor public protocol ScrollArbiter: AnyObject {
    var coordinateSpaceName: String { get }
    func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken
    func update(_ token: ScrollArbitrationToken, frame: CGRect)
    func unregister(_ token: ScrollArbitrationToken)
    func owner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int,
               participant: ScrollArbitrationToken) -> ScrollOwner
}

extension EnvironmentValues { public var scrollArbiter: (any ScrollArbiter)? }   // nil by default
public let scrollArbitrationGestureName = "ScrollArbitration.participant"

// The rules as a pure function. Every arbiter must decide through it.
public struct ScrollArbitrationInput: Sendable, Equatable {
    public var pagingAxis: Axis
    public var directionTolerance: Double            // degrees from the paging axis; default 30
    public var translation: CGSize                   // finger movement: +width right, +height down
    public var touchCount: Int
    public var participantCanFollow: Bool            // canFollow(fingerDirection(translation, along: pagingAxis))
    public var participantMovingAtTouchDown: Bool
    public var participantZoomEnabled: Bool
    public var containerMovingAtTouchDown: Bool
}
public enum ScrollArbitrationRules {
    public static func fingerDirection(_ translation: CGSize, along axis: Axis) -> FingerDirection
    public static func decide(_ input: ScrollArbitrationInput) -> ScrollOwner
}

// A complete, drawing-free arbiter for tests on both sides.
@MainActor public final class ReferenceScrollArbiter: ScrollArbiter { /* see below */ }
```

Declare the environment key's `defaultValue` as a computed property, so it compiles under Swift 6 strict concurrency on every toolchain.

### Rules (normative)

- **Decision order.** `decide` returns the first match:
  1. The translation is more than `directionTolerance` off the paging axis → `.participant`. Exactly at the tolerance counts as on-axis.
  2. Two or more touches and zoom enabled → `.participant`.
  3. The participant was moving without a finger at touch-down → `.participant`.
  4. The container was moving at touch-down → `.container`.
  5. The participant can follow the finger along the paging axis → `.participant`.
  6. Otherwise → `.container`.
- **Directions** are screen space and ignore layout direction; right-to-left is the participant's concern inside `canFollow`. `fingerDirection` uses the sign of the translation along the paging axis.
- **Once per sequence.** A sequence runs from the first finger down to the last finger up, as the arbiter sees it. The first `owner` call in a sequence decides through `decide`. Every later call in the same sequence returns the same owner, whatever its arguments, and the container's own decision goes through the same cache.
- **Overlapping participants.** The arbiter uses the smallest frame containing the start point; ties go to the most recent registration.
- **Unknown tokens.** `owner` returns `.container`; `update` and `unregister` ignore them.
- **Coordinates.** Frames and start points are in `.named(coordinateSpaceName)`. Registration and frame updates are cold-path calls: on appear, on geometry change and on disappear, never per scroll frame.
- **Threading.** Everything runs on the main actor; no call blocks or re-enters the arbiter.
- **No arbiter.** A participant with no arbiter in its environment behaves exactly as a standalone scroller.
- **Gesture name.** On iOS 18+, participants name their gestures `scrollArbitrationGestureName`. Containers may let their own recognizers run alongside recognizers with that name.

### Reference arbiter

`ReferenceScrollArbiter` implements every rule above in pure Swift and draws nothing. It exposes:
- settable `pagingAxis`, `directionTolerance` and `isContainerMoving`
- `beginSequence()` and `endSequence()`, to model fingers going down and up
- a log of every `register`, `update`, `unregister` and `owner` call, for assertions

### Contract tests (`scripts/test-arbitration.sh`, on the host)

- every combination of rules 1–6, including both sides of the 30° boundary
- direction mapping on both axes
- sequence caching: the first call decides, later calls return the same owner even with different arguments, and a new sequence decides afresh
- overlapping participants, unknown tokens, and register/unregister lifetimes
- a clean build with Xcode 27 and with Xcode 26.6, under Swift 6 strict concurrency

### Spike: proving the contract against UIKit (MC only)

Some questions only a real UIKit pager can answer. They match ZTronPages' device checks EG-11 and EG-13.

- **Where:** `Packages/ScrollArbitration/Spike/ArbitrationSpike.xcodeproj`, an app plus a UI-test target. It is the only place in this repo where UIKit is allowed. No library target depends on it, and it travels with the contract repository as an example.
- **What it builds:**
  - a horizontally paging `UIScrollView` with three pages, each a `UIHostingController`
  - in each page, a SwiftUI stand-in participant registered with an arbiter that decides through `ScrollArbitrationRules`
  - the stand-in has an always-on touch observer (`SpatialEventGesture` on 18+, `DragGesture(minimumDistance: 0)` below), a pan `DragGesture`, and a toggle that sets `canFollow`
  - a SwiftUI `Button`, and an on-screen log of which side moved in each sequence
- **Questions:**
  1. iOS 18+: with the participant's gestures named and the paging pan allowed to run alongside them, does the pan begin exactly when the arbiter answers `.container`, and stay idle for `.participant`?
  2. iOS 18+: does a SwiftUI `Button`'s press recognizer stay out of `.began` and `.changed` unless the press turns into a drag? ZTronPages' rule 5 depends on it.
  3. iOS 15–17: does the page's SwiftUI gesture handling leave the paging pan free to begin, and do the participant's gestures end cleanly when the pan cancels their touches?
  4. Inside a page, do start points from `DragGesture(coordinateSpace: .named(...))` match the arbiter's space within 0.5 pt?
  5. Is the decision made exactly once per sequence, whichever side asks first?
- **Runs:**
  - UI tests with scripted `XCUICoordinate` drags at 0°, 20°, 40° and 90°, with `canFollow` on and off, plus pinches and taps on the button.
  - On iOS 17, 18, 26 and 27 with Xcode 27: `scripts/test-spike.sh`.
  - On iOS 15 and 16 with Xcode 26.6, run by you: `SPIKE_DEVELOPER_DIR=<Xcode 26.6>/Contents/Developer SPIKE_DEST=<iOS 15 or 16 simulator> scripts/test-spike.sh`.
- **Outcome:** `docs/design/MC-contract.md` records every answer on every OS. A "no" either changes the contract before the freeze or names the fallback ZTronPages will use (its EG-11 and EG-13 rows). Then tag `1.0.0`.

### Freeze and change control

- After 1.0.0, neither project edits the package from its own repository.
- A change is a contract revision: a new tag (minor for additions, major for anything else), both specs updated (this section and ZTronPages 7.8), and both projects' arbitration tests re-run.
- MC is done when the contract tests pass on both toolchains, every spike question has an answer per OS, `docs/design/MC-contract.md` is committed, `1.0.0` is tagged, and ZoomScroll's `Package.swift` depends on that tag.

---

# Part II · Orchestration

## O1 · Why this plan is cheap

1. **Sonnet does the typing; stronger models do the thinking.**
   - Default sessions run Sonnet 5.5 at medium effort with an Opus 5.5 *advisor*, which Claude consults only at decision points.
   - Fable 5.1 runs only in short design/review sessions that produce written docs.
2. **Never pay twice for context.**
   - Each model has its own prompt cache, so switching `/model` mid-session re-reads the whole conversation uncached. Start a new session instead.
   - Changing effort keeps the cache on Opus 5.5, Sonnet 5.5 and Fable 5.1 on a subscription.
   - `/clear` costs nothing.
   - To abandon a path, use `/rewind` (it keeps the cache) instead of `/compact`.
3. **Raw logs never reach the model.** Every build and test goes through a filter that returns only errors, failing tests and the exit code (F3, F4).
4. **Cheap models do chores.** Haiku 5.5 subagents run tests, triage logs, scout files and update the parity matrix.
5. **Fan out only parallel, mechanical work**, with the `ultracode:` keyword per prompt (O5). Never turn on `/effort ultracode` for a whole session.
6. **Keep contexts small.**
   - `CLAUDE.md` stays under ~60 lines.
   - Sessions read only the sections of this file that O4 lists.
   - Short sessions with handoff notes replace marathons.
7. **Measure every session** (O7), and stop when a milestone overruns its budget.

## O2 · Model routing

| Role | Run by hand with | On autopilot | Use for |
|---|---|---|---|
| **Builder** (default) | `claude --model sonnet --advisor opus` | `builder` agent | Implementing from design docs; most fixes |
| **Builder, hard step** | same session, then `/effort high` (cache-safe) | `builder` with high effort | A tricky step |
| **Builder on Opus** | `claude --model opus` | `builder` with model opus | Where O4 says Opus builds |
| **Architect** | `claude --model fable` (high effort by default) | `architect` agent | Design note; designs for MC, M1, M2, M8b and M9; M5; final review |
| **Debugger** | `claude --model opus --effort high` | `debugger` agent | Escalations: perf contract, gesture arbitration, flaky behavior |
| **Clerk / chores** | `claude --model haiku --effort low` | `clerk`, `scout`, `test-runner` | M0 leftovers, docs, matrix, test runs |
| **Fan-out workers** | automatic via `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` | same | `ultracode:` batches |

Rules:
- **One model per session.** To change model, write the handoff, `/clear`, and relaunch.
- **Escalation ladder:**
  1. Retry once with the filtered error.
  2. Consult the advisor once.
  3. Still stuck: stop, write the handoff, and open a Debugger session with the escalation template (O3). Never let a third attempt happen in the same context.
- **Advisor cost:** the advisor re-reads the full conversation uncached, at its own model's rates, on every call. Keep Builder sessions short. Use a Fable advisor (`--advisor fable`) only for the hardest step, with a context under ~100K tokens.
- **Opus advisor pairing:** Opus 5.5 is a better advisor for Sonnet than Fable is on cost: its input is 2.5× cheaper.
- **Effort:** raise it inside a session instead of switching models.

## O3 · Session protocol & templates

**Start:**
1. Launch with the role's command (O2).
2. Paste a template below, filled in.

**During the session:**
- Work one step at a time.
- If a step goes the wrong way, press Esc and use `/rewind`.
- At a natural break with context over ~150K, either `/compact` or end the session.

**End:**
1. Write the handoff to `docs/progress/M<n>-s<k>.md` (template in F7).
2. Commit.
3. Log `/usage` (O7).
4. Run `/clear`.

**After a break of more than an hour:** the main cache has expired. Start fresh from the handoff rather than resuming a large session.

**Builder kickoff:**
```
M<n> · <title> · Builder
Read: docs/SPEC.md sections <from O4's Read column> (by line range), docs/design/<doc>,
docs/progress/<last handoff>. Nothing else up front.
Do: <3–6 scope bullets>
Out of scope: <list>
Done when: <acceptance checks>; touched suites green via test-runner; committed.
Budget: ~<x>% of the weekly limit. 2 failed attempts → advisor once → still stuck: stop and hand off.
Finish: handoff in docs/progress/M<n>-s<k>.md; reply in ≤8 lines.
```

**Architect (Fable), no production code:**
```
Architect session. Write docs/design/M<n>-<topic>.md (≤2 pages): types and signatures, data flow,
formulas, edge cases, the test list, and the risks to check on device.
Read: docs/SPEC.md sections <list>. Reply in ≤8 lines.
```

**Escalation (Opus):**
```
Debug only. Problem: <one line>. Repro: <script + test name>. Evidence: <filtered lines>.
Tried: <hypothesis → result, ×2>. Fix the root cause with the smallest patch plus a regression test.
No refactors. Reply in ≤10 lines.
```

**Final review (Fable):**
```
Review `git diff <tag>..HEAD` against docs/SPEC.md S4, S7, S8, S9 and S10.
Report only blocking issues as `file:line — problem — fix` (≤25 lines). No rewrites, no style notes.
```

## O4 · Milestone budgets

Budgets are % of **one** weekly Max 20x limit. The **Read** column lists the only sections of this file each milestone needs.

| # | Work | Read | Sessions | Budget |
|---|---|---|---|---|
| M0 | Part III files; package skeleton | F1–F7 | You copy Part III by hand; Clerk (Haiku) for leftovers | 0–1% |
| MC | ScrollArbitration contract: package, reference arbiter, contract tests, UIKit spike, freeze 1.0.0 | S12, S16 | Architect: `design/MC-contract.md` → Builder; you run the iOS 15/16 spike tests | 3–5% |
| M1 | Availability scaffolding + physics + tests | S2, S3, S5, S6 | Architect: design note + `design/M1-physics.md` → Builder; host tests only | 6–9% |
| M2 | Container/transform + render-count proof (all OS paths) | S3, S4, S5, S11 | Architect: `design/M2-render.md` → Builder; Debugger if counts fail | 7–10% |
| M3 | Pan/decay/bounce + delegate + pager arbitration | S6, S11, S12, S16 | Builder | 8–10% |
| M4 | Zoom | S6, S12 | Builder | 5–7% |
| M5 | Rotation/resize | S7 | Architect, one session (design + implement; small but subtle) | 5–7% |
| M6 | Targets, positions, readers | S8, S11 | Builder on Opus for the core and **one exemplar per API kind** → `ultracode:` batch for the rest | 8–11% |
| M7 | Observation APIs + transitions | S8 | Builder; `ultracode:` batch for the dual-mode content modifiers | 6–8% |
| M8 | Indicators, insets, edge effects, keyboard, a11y | S6, S8 | Builder; `ultracode:` batch (independent features) | 6–9% |
| M8b | Refresh facade + scaling header | S9, S10 | Architect: `design/M8b-refresh-header.md` → Builder | 6–9% |
| M9 | Lazy containers | S8 | Architect: `design/M9-virtualization.md` → Builder on Opus | 9–13% |
| M10 | Demo + parity matrix + report | S14 | `ultracode:` batch for demo screens; `clerk` for matrix/report; Architect final review | 6–8% |
| R | Device-feedback fix rounds, batched per milestone | — | Builder; Debugger when needed | 10–15% |
| | **Total** | | Fable ≈ 18–25%, well under its 50% cap | **~85–122%** |

## O5 · Ultracode, only where it pays

- **Never turn on `/effort ultracode` for a session.** Use the keyword for a single task: `ultracode: …`.
- **Use it only for:**
  - M6–M8 parity batches
  - M10 demo screens
  - test generation
  - fallback-path checks
- **Write an exemplar first.** Opus or Sonnet writes one complete example per API kind: a same-name member, its prefixed twin, the mirrored type, and its tests. The batch then copies the pattern.
- **Keep runs small.** `workflowSizeGuideline` is set to `small` (fewer than 5 agents). Ask for "medium" in the prompt only for the largest parity batch.
- **Choose a model per stage.**
  - Implementation runs on Sonnet (the default).
  - Ask for Haiku on inventory and triage stages.
  - Verification is build + tests through the scripts. Add reviewer agents only if something fails.
- **Try a slice first.** Run 3 APIs, check per-agent tokens in `/workflows`, then run the rest.
- **Save good runs.** In `/workflows`, select the run and press `s`, saving it as e.g. `/parity-batch`. Rerunning it with new args skips re-planning.
- **Resume rather than restart.** Relaunching the same run returns saved results for completed agents.
- **Long builds:** if a batch's tests take more than 5 minutes, launch that session with `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h claude`. Otherwise keep the 5-minute default.
- **Run big batches early in your weekly cycle.** A run paused by the 5-hour limit resumes by itself. One blocked by the weekly limit fails.

**Batch prompt:**
```
ultracode: implement <API list> following the exemplar in <file> and docs/SPEC.md S8.
One agent per API on Sonnet; inventory/triage stages on Haiku. Each agent verifies with
scripts/build.sh and scripts/test.sh -only-testing:<suite>. Keep it small.
Report a table API → status in ≤15 lines.
```

## O6 · Weekly cadence

| Week | Milestones | Planned use |
|---|---|---|
| 1 | M0, MC, M1–M3 | ~24–35% |
| 2 | M4–M7 | ~24–33% |
| 3 | M8, M8b, M9 | ~21–31% |
| 4 | M10 + reserve: device-feedback rounds, polish | ~16–23% |

- Schedule Fable sessions at the start of a week.
- Test on device yourself after each milestone. Collect all issues into one list and fix them in **one** session, not many small ones.
- Run iOS 15/16 checks yourself on Xcode 26.x simulators, since Xcode 27 only runs and debugs iOS 17+. Paste back only the failures.
- Compressing the plan to 2 weeks (~50% per week) is fine usage-wise. Your device testing is the real bottleneck.

## O7 · Measure and stop rules

- **Run `/usage` at the start and end of every session**, and log it in `docs/progress/usage-log.md` (F7).
  - Its breakdown flags anything costing 10% or more of recent usage (long context, cache misses).
  - The `Prompt cache (main)` line shows the hit ratio and the likely cause of the last miss. Aim for about 90% or more of input served from cache.
- **Calibrate after M2.** Planned spend for M0–M2, including MC, is 16–25%. Your actual ÷ planned is your multiplier for the rest of the plan. If it's above 1.3:
  - move more work to Sonnet
  - make fewer advisor calls
  - shorten sessions
- **Stop rules:**
  - A session that reaches 1.5× its share of the milestone budget: stop, write the handoff, re-plan.
  - A milestone that reaches 1.5× its budget: re-scope in an Architect or Debugger session before continuing.

## O8 · Autopilot (Remote Control + /goal)

**Why not a cloud session?**
- Anthropic-hosted cloud sessions run on Ubuntu x86_64 VMs with no Xcode, so they can't build or test a SwiftUI iOS package.
- Self-hosted environments, which could route cloud sessions to your own Mac, are Team/Enterprise only.

**What works instead:** run the session on your Mac and steer it from your phone with Remote Control. An orchestrator session delegates to the F5 role agents and keeps going with `/goal`.

**Cost:** expect roughly 10–25% more usage than running the plan by hand, because the orchestrator itself uses tokens.

### Prerequisites

**On the Mac:**
- Xcode 27 with an iOS Simulator runtime.
- Claude Code ≥ v2.1.293 (`claude update`).
- `brew install tmux jq` (the hook needs `jq`).
- All Part III files in place.

**On your phone:**
- The Claude app, signed in with the same account.
- In Claude Code, run `/config` and turn on **Push when Claude decides** and **Push when actions required**.

**Optional:** pair your iPhone in Xcode (Window → Devices) and turn on automatic signing for the Demo target. Then each milestone's demo build can be installed on the phone for you to test.

### Launch

Keep the Mac plugged in and awake. It doesn't work while asleep, but it reconnects when it wakes. Closing the lid sleeps the Mac unless it's in clamshell mode with an external display.

```bash
cd ~/path/to/ZoomScroll
tmux new -s zoomscroll
caffeinate -is claude --model sonnet --advisor opus --permission-mode auto --remote-control "ZoomScroll autopilot"
```

If auto mode isn't available on your account, use `--permission-mode acceptEdits`. The few remaining permission prompts will reach your phone and wait for your answer.

Detach with `Ctrl-b d`; the session keeps running. Reattach later with `tmux attach -t zoomscroll`.

### Start (in that session)

```text
/autocompact 200k
```

```text
/goal Following docs/SPEC.md O8, milestones M0–M10 (including MC and M8b) are all marked done in docs/progress/STATE.md, each with its acceptance checks passing in a test-runner report and a committed handoff — or stop after 250 turns, or when STATE.md says PAUSED.
```

`/autocompact 200k` keeps the orchestrator's context lean; without it, it can grow toward the 1M window before compacting.

`/goal` starts working right away. A small, cheap model checks after every turn whether the condition is met, so Claude keeps going without you prompting each step.

### Orchestrator rules

You orchestrate the ZoomScroll build: plan, delegate, verify, record. Don't write production code yourself.

**Sources of truth:** this file (Part I for what to build; O3 templates; O4 milestones, budgets and Read lists; O5 workflows) and `docs/progress/STATE.md`.

**Loop.** Take the first milestone not marked done in STATE.md:
1. **Design.** If O4 lists an Architect step, run `architect` to write `docs/design/M<n>-*.md`. If Fable isn't available (limit reached), run it with model opus at high effort instead.
2. **Build.** Split the milestone into 2–5 tasks small enough for one agent run. Run `builder` once per task, one at a time, with the O3 Builder kickoff filled in (including O4's Read sections). Where O4 says Opus builds, run `builder` with model opus.
3. **Verify.** After each task, run `test-runner` on the touched suites.
   - On failure, give `builder` one retry with the failures.
   - If it fails again, run `debugger` with the O3 escalation template.
4. **Workflows.** Before any batch that O5 marks for a workflow, ask me to approve it (one question). If I approve, use a small workflow: Sonnet workers, Haiku for inventory, exemplar first, a 3-item slice before the rest.
5. **Milestone end.** Run the full suite via `test-runner`. Have `clerk` update `docs/parity-matrix.md` and STATE.md. Commit, and push if a remote exists.
6. **Gate.** Send me a push notification, then ask one question covering:
   - device feedback (if an iPhone is paired, build and install the demo with xcodebuild and xcrun devicectl first);
   - my current weekly usage % (I read it in Settings → Usage).

   Record both in STATE.md. If the milestone ran over 1.3× its O4 budget, shorten tasks, cut advisor calls, and keep more work on `builder`. Turn my device feedback into the next milestone's first task.

**Stop**, write PAUSED (with the reason) in STATE.md, and ask me when:
- this week's usage passes 35%;
- a milestone passes 1.5× its budget;
- `debugger` fails twice on the same problem;
- a spec decision is ambiguous and costly to reverse.

**Context hygiene:**
- Keep your own context lean. Read STATE.md, handoffs and only the sections of this file you need; not code or logs.
- Agents report in ≤10 lines.
- Never run /model in this session.

### Steering from your phone

- **Open the session:** Claude app → **Code** → **ZoomScroll autopilot** (computer icon, green dot).
- **Gates and questions** arrive as push notifications and stay open until you answer.
- **Check usage:** run `/usage` from the phone.
- **Check progress:** ask "status?" or open `docs/progress/STATE.md`.
- **Pause:** send "pause". To end the run, send `/goal clear`.

## O9 · Never do these (they silently burn usage)

- **Switch `/model` mid-session.** It re-reads everything uncached.
- **Use `opusplan`.** Every plan-mode toggle is a model switch.
- **Give a skill a `model:` that differs from the session's.** That turn becomes a model switch. Use `context: fork` if a skill needs another model.
- **Leave `/effort ultracode` on, or use agent teams.** Agent teams use roughly 7× the tokens.
- **Feed raw output into context.** That means raw `xcodebuild`, pasted full logs, and simulator screenshots: images add tokens, and piling them up forces cache rebuilds.
- **Run unattended in ways that fire on their own:**
  - `claude -p` with Fable bills overflow to usage credits without asking.
  - Scheduled `/loop` tasks and idle `/goal` check-ins send your full context each time. The autopilot's goal is fine because the session works continuously.
- **Resume a huge session after a long break.** Start fresh from the handoff.
- **Run parallel Claude Code instances on this repo.**
- **Load this whole file, or re-read files just written.**

## O10 · Where not to save

- **Fable design work** for MC, M1, M2, M5, M8b and M9, and the final review. It's cheap insurance against expensive rework.
- **Render-count proofs and the acceptance checks.** They are the point of the package.
- **Your own testing on real hardware:** ProMotion, rotation, gesture feel, refresh and header feel. It costs zero tokens and gives the strongest signal.
- **Escalating to Opus after two failed attempts.** It's cheaper than a third Sonnet loop.

---

# Part III · Files to create once

## F1 · Repo layout

```
ZoomScroll/
├─ Package.swift                   # ZoomScroll (SwiftUI) library + tests, iOS 15+; depends on ScrollArbitration
├─ Packages/ZoomScrollPhysics/     # pure Swift (Foundation/CoreGraphics), iOS + macOS
├─ Packages/ScrollArbitration/     # shared contract (S16), SwiftUI + Foundation; Spike/ holds the UIKit spike app
├─ Demo/                           # demo app (Xcode project)
├─ docs/
│  ├─ SPEC.md                      # this file
│  ├─ design/                      # Architect design docs
│  ├─ progress/                    # STATE.md, TEMPLATE.md, usage-log.md, handoffs
│  └─ parity-matrix.md
├─ scripts/                        # run-filtered.sh, build.sh, test.sh, test-physics.sh
├─ .claude/                        # settings.json, hooks/filter-build.sh, agents/*.md
└─ CLAUDE.md
```

Physics lives in its own local package so its tests run on the Mac host with `swift test`. That means no simulator boot and tiny output. ScrollArbitration follows the same pattern until MC moves it to its own repository.

## F2 · `.claude/settings.json`

```json
{
  "model": "sonnet",
  "autoContinueAtUsageLimit": true,
  "workflowSizeGuideline": "small",
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet",
    "ZS_SCHEME": "ZoomScroll",
    "ZS_DEST": "platform=iOS Simulator,name=YOUR_SIMULATOR"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/filter-build.sh" }
        ]
      }
    ]
  }
}
```

Then:
- **Placeholders:** replace `YOUR_SIMULATOR` with a device from `xcrun simctl list devices available`. Check the scheme name with `xcodebuild -list`.
- **Permissions:** with `/permissions`, allow `scripts/build.sh`, `scripts/test.sh`, `scripts/test-physics.sh`, `scripts/test-arbitration.sh`, `scripts/test-spike.sh` and `git commit`, so runs don't stall on prompts.
- **Usage credits:** keep them off (Settings → Usage), or set a monthly spend cap. Then nothing bills beyond your plan without your say-so.
- **MCP servers:** disable any you have (`/mcp`). This project needs none; use `git`, `gh` and `xcrun simctl` from the CLI instead.
- **Code intelligence:** if your plugin catalog has a Swift code-intelligence (sourcekit-lsp) plugin, install it. Symbol lookups replace grep-then-read, and type errors surface without a build.

## F3 · Scripts (`chmod +x scripts/*.sh`)

`scripts/run-filtered.sh` keeps the full log on disk and prints only what Claude needs:

```bash
#!/bin/bash
log="$(mktemp -t zoomscroll-log)"
"$@" >"$log" 2>&1
rc=$?
grep -E '(error|warning):|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*|Test Case .* failed|Executed [0-9]+ tests?|✘|Test run with' "$log" \
  | awk '!seen[$0]++' | head -n 120
echo "exit=$rc · full log: $log"
exit "$rc"
```

`scripts/build.sh`:

```bash
#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
exec scripts/run-filtered.sh xcodebuild build -quiet \
  -scheme "${ZS_SCHEME:-ZoomScroll}" -destination "generic/platform=iOS Simulator"
```

`scripts/test.sh`, usage `scripts/test.sh [-only-testing:Target/Suite ...]`:

```bash
#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
: "${ZS_DEST:?set ZS_DEST in .claude/settings.json}"
exec scripts/run-filtered.sh xcodebuild test -quiet \
  -scheme "${ZS_SCHEME:-ZoomScroll}" -destination "$ZS_DEST" "$@"
```

`scripts/test-physics.sh` runs host tests in seconds:

```bash
#!/bin/bash
cd "$(dirname "$0")/../Packages/ZoomScrollPhysics" || exit 1
exec ../../scripts/run-filtered.sh swift test "$@"
```

`scripts/test-arbitration.sh` runs the contract tests on the host:

```bash
#!/bin/bash
cd "$(dirname "$0")/../Packages/ScrollArbitration" || exit 1
exec ../../scripts/run-filtered.sh swift test "$@"
```

`scripts/test-spike.sh` runs the MC spike's UI tests. Set `SPIKE_DEVELOPER_DIR` to an Xcode 26.x and `SPIKE_DEST` to an iOS 15 or 16 simulator for the legacy runs:

```bash
#!/bin/bash
cd "$(dirname "$0")/../Packages/ScrollArbitration/Spike" || exit 1
: "${ZS_DEST:?set ZS_DEST in .claude/settings.json}"
[ -n "$SPIKE_DEVELOPER_DIR" ] && export DEVELOPER_DIR="$SPIKE_DEVELOPER_DIR"
exec ../../../scripts/run-filtered.sh xcodebuild test -quiet \
  -project ArbitrationSpike.xcodeproj -scheme ArbitrationSpike \
  -destination "${SPIKE_DEST:-$ZS_DEST}" "$@"
```

## F4 · Hook: `.claude/hooks/filter-build.sh` (`chmod +x`, needs `jq`)

A safety net in case an agent calls `xcodebuild` or `swift build|test` directly: it routes the call through the filter. It auto-approves only plain, unchained invocations. Anything with pipes, `;`, `&`, `$(` or backticks goes through the normal permission flow.

```bash
#!/bin/bash
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
case "$cmd" in
  *run-filtered*|*'|'*|*';'*|*'&'*|*'$('*|*'`'*) echo '{}'; exit 0 ;;
esac
if [[ "$cmd" =~ ^(xcodebuild|swift\ (build|test))([[:space:]]|$) ]]; then
  wrapped="\"${CLAUDE_PROJECT_DIR:-$PWD}/scripts/run-filtered.sh\" $cmd"
  jq --arg c "$wrapped" '{hookSpecificOutput: {hookEventName: "PreToolUse",
      permissionDecision: "allow", updatedInput: (.tool_input + {command: $c})}}' <<<"$input"
else
  echo '{}'
fi
```

## F5 · Subagents (`.claude/agents/`)

`test-runner.md`:

```markdown
---
name: test-runner
description: Builds and runs tests via scripts/ and returns only failures. Use after every code change.
tools: Bash, Read, Grep
model: haiku
effort: low
---
Run only scripts/build.sh, scripts/test.sh or scripts/test-physics.sh with the arguments you're given; never raw xcodebuild.
Reply in ≤15 lines: PASS or FAIL, then each error or failing test as `file:line — message`.
If output was cut, grep the full-log path it printed for the first error's context (≤10 lines). Don't propose fixes.
```

`scout.md`:

```markdown
---
name: scout
description: Finds where code or spec text lives. Returns paths and line ranges only.
tools: Read, Grep, Glob
model: haiku
effort: low
---
Answer with file paths and line ranges (≤20 lines). Quote at most 3 lines per hit. Never summarize whole files.
```

`clerk.md`:

```markdown
---
name: clerk
description: Updates docs/parity-matrix.md, docs/progress/STATE.md, usage-log.md and reports from code, test results and handoffs.
tools: Read, Grep, Glob, Edit, Write
model: haiku
effort: low
---
Edit only files under docs/ except docs/SPEC.md. Change only the affected rows. Reply with what changed in ≤5 lines.
```

`architect.md`:

```markdown
---
name: architect
description: Writes design docs for hard milestones. No production code.
tools: Read, Grep, Glob, Write
model: fable
effort: high
---
Read only the docs/SPEC.md sections (by line range) and handoffs named in your task. Write the requested docs/design/ file (≤2 pages):
types and signatures, data flow, formulas, edge cases, the test list, and risks to check on device.
Reply in ≤8 lines with the file path and any open questions.
```

`builder.md`:

```markdown
---
name: builder
description: Implements one scoped task from a design doc, with tests, then commits and writes a handoff.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
effort: medium
---
Follow CLAUDE.md. Read only the docs/SPEC.md sections named in your task, by line range. Do only that task, one step at a time:
edit → scripts/build.sh or scripts/test-physics.sh → scripts/test.sh -only-testing:<suite> → git commit.
After 2 failed attempts at the same problem, consult the advisor once; if it still fails, stop and report.
Finish with a handoff in docs/progress/ (template: docs/progress/TEMPLATE.md).
Reply in ≤10 lines: status, files changed, tests run, open issues.
```

`debugger.md`:

```markdown
---
name: debugger
description: Fixes one problem the builder couldn't. Root cause, smallest patch, regression test.
tools: Read, Grep, Glob, Edit, Write, Bash
model: opus
effort: high
---
Debug only; no refactors. Reproduce with the scripts, find the root cause, apply the smallest fix,
add a regression test, commit. Reply in ≤10 lines: cause, fix, test.
```

Notes on the subagents:
- Keep their inputs small. Haiku 5.5 costs 5× more per token once a prompt passes 100K tokens.
- If your full simulator test run regularly takes more than 5 minutes, set `cacheTtl: 1h` in the `experimental` frontmatter field of `test-runner` and `builder` (Claude Code ≥ v2.1.248). Subagent caches otherwise expire after 5 minutes, and the agent re-pays its whole context after each slow run. Leave it at the default if runs are short: the 1-hour cache costs more for short bursts.

## F6 · `CLAUDE.md` (stays tiny; loaded every session)

```markdown
# ZoomScroll — pure-SwiftUI UIScrollView replacement (iOS 15+)

Spec and plan: docs/SPEC.md. Read only the sections your task names; `grep -n '^## [SOF][0-9]' docs/SPEC.md`
lists them with line numbers. Designs: docs/design/. Handoffs and state: docs/progress/.

## Non-negotiables
- Library imports only SwiftUI, Combine, Observation (gated), Foundation and ScrollArbitration (SPEC S16). No UIKit/AppKit, *Representable, CADisplayLink, reflection or private API; UIKit appears only in the MC spike app.
- ScrollArbitration's public API is frozen at 1.0.0 after MC (SPEC S16). Never change it from this repo.
- iOS 15 minimum. Every newer API is behind `if #available`, with a fallback that keeps the same API and behavior.
- Scrolling, zooming, refreshing and header collapse never re-evaluate content bodies; offset/zoom are render-time transforms only (SPEC S4).
- Rotation preserves the visible center (SPEC S7).

## Commands (never run raw xcodebuild)
- Physics tests (host, fast): `scripts/test-physics.sh`
- Contract tests (host, fast): `scripts/test-arbitration.sh`
- Build: `scripts/build.sh`
- Tests: `scripts/test.sh -only-testing:<Target/Suite>`. Run only the suites you touched; run the full suite at milestone end.
- Prefer the `test-runner` subagent for builds and tests. Use `scout` to locate code and `clerk` for docs/ bookkeeping.

## Working rules (token budget matters)
- One step at a time: edit → build → test → commit. Commit at every green state.
- Locate before reading: grep or `scout` first, then read line ranges. Don't re-read files you just wrote.
- Don't paste code or logs into replies; reference file:line. Keep final replies to 8 lines or fewer unless asked.
- After 2 failed attempts at the same problem, consult the advisor once. If still stuck, stop and write the handoff.
- Start no workflows unless the prompt contains `ultracode` or asks for a workflow.
- No screenshots unless asked; verify with render counters, logs and tests.
- End every session with a handoff in docs/progress/ (template: docs/progress/TEMPLATE.md).

# Compact instructions
Keep: decisions and their reasons, open issues, failing tests, file paths, next steps. Drop: logs, file contents, exploration.
```

## F7 · Progress files (`docs/progress/`)

`TEMPLATE.md` (the handoff):

```
# M<n>-s<k> handoff · <date> · <model · effort>
Status: done | partial — <what's left>
Changed: <module/file — one line each>
Decisions: <choice — why>
Open: <bugs, flaky tests, device checks pending>
Next: <first 3 steps>
Tests: <command → result>
Usage: weekly <a>% → <b>% · cache hit <c>%
```

`STATE.md`:

```markdown
# STATE
Status: RUNNING
Current: M0

| Milestone | Status | Budget % | Used % (my readings) | Notes |
|---|---|---|---|---|
| M0 | todo | 0–1 | | |
| MC | todo | 3–5 | | |
| M1 | todo | 6–9 | | |
| M2 | todo | 7–10 | | |
| M3 | todo | 8–10 | | |
| M4 | todo | 5–7 | | |
| M5 | todo | 5–7 | | |
| M6 | todo | 8–11 | | |
| M7 | todo | 6–8 | | |
| M8 | todo | 6–9 | | |
| M8b | todo | 6–9 | | |
| M9 | todo | 9–13 | | |
| M10 | todo | 6–8 | | |

Open issues:
Device feedback queue:
```

`usage-log.md`:

```
| Date | Session | Model · effort | Weekly % (start → end) | Cache hit | Notes |
|---|---|---|---|---|---|
```

---

## References

**Claude Code and plans:**
- Prompt caching: https://code.claude.com/docs/en/prompt-caching
- Manage costs: https://code.claude.com/docs/en/costs
- Advisor tool: https://code.claude.com/docs/en/advisor
- Dynamic workflows and ultracode: https://code.claude.com/docs/en/workflows
- Model configuration: https://code.claude.com/docs/en/model-config
- Cloud environments: https://code.claude.com/docs/en/cloud-environments
- Self-hosted environments: https://code.claude.com/docs/en/self-hosted-environments
- Remote Control: https://code.claude.com/docs/en/remote-control
- `/goal`: https://code.claude.com/docs/en/goal
- Fable on Max: https://support.claude.com/articles/15424964-claude-fable-models-on-your-plan

**Apple:**
- Scroll views: https://developer.apple.com/documentation/swiftui/scroll-views
- SwiftUI updates: https://developer.apple.com/documentation/updates/swiftui

**Reference libraries** (behavior and API shape only):
- Refresher: https://github.com/gh123man/SwiftUI-Refresher
- ScalingHeaderScrollView: https://github.com/exyte/ScalingHeaderScrollView
- Exyte, "SwiftUI Tutorial – Scaling Header": https://exyte.com/blog/swiftui-tutorial-scaling-header
