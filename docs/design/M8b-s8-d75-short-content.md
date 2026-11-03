# D75: fitting content under a scaling header becomes an option (`withScalingHeader(…, fittingContent:)`)

> Committed by the M8b-s8 architect (2026-11-03) from the designer's scratch doc, unchanged below this note. Build order, numbering and the architect's amendments: [M8b-s8-plan.md](M8b-s8-plan.md) (they win where they differ). Scratch paths (`s8/d75-short-content/…`, `scratchpad/s8/…`) are gone after a reboot; the text artifacts (patches, tools, tables) persist in the shared notes folder `m8b-s8-resume/s8-spikes/d75-short-content/`.

Designer d75-short-content (M8b-s8), 2026-11-02. Base 09226f4. Spike worktree (removed at the end) and numbers in
`s8/notes.md` § d75-short-content. D-number D75 (Orchestration batch line 25; D76 is i28's, D77 i29's, D78 i15b's).
New open items: next free number at merge (34+; i29 proposes 34).

## 0. Summary

- **Decision (D75).** D63 becomes `fittingContent: ZTronHeaderFittingContent = .topAligned`, a parameter of
  `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:header:)` (D76's `.stretch`-content
  enum, ruled the same day, goes right after it; both defaulted). Three cases:
  `.topAligned` (D63, default), `.headerFollows` (item 15 (a)'s alternative: the content keeps its alignment, the header
  rides on its top edge, the gap opens above the header; `.stretch` fills that gap by growing), `.headerPinned` (the
  pre-D63 look: the header stays, the content keeps its alignment below it, the gap opens between them). Each one is the
  look of a native construction: header in the content (`.headerFollows`), header as a safe-area inset (`.headerPinned`),
  a stretchy-header library (`.topAligned`).
- **Root cause of "D63 is all or nothing".** The vertical alignment padding is applied to the content only
  (`ContentTransform`, `pad = slack · a`), and the header's geometry has no input for it (it is a function of `o′` and the
  slot). D63 had to zero the content's vertical alignment for every header (`ZTronScrollState.contentAlignment`).
- **Root cause of the transitions (measured, §1).** The padding is drawn from the COMMITTED content size, which a measurement
  callback writes after the layout pass, outside the transaction. Every animated content-size change moves fitting,
  aligned content in ONE frame (119 pt for 300 ↔ 600 pt rows in the spike). The same write clamps the offset unanimated:
  shrinking content while scrolled to the bottom jumps 62 pt in one frame TODAY in the default mode (181 pt in
  `.headerFollows`). The alignment and the option are cold values that no channel publishes, so a run-time change only
  shows at the next scroll frame.
- **Approach.** (1) The content's alignment and the header's lift alignment are published metrics; (2) the content's
  shape (size and both alignments) is an animatable attribute of its own (`ContentShapeShift`), adopted in the
  transaction the change came in (the container's and the content's `.transaction` hooks see it, internal and external
  changes alike: measured), separate from the transform vector that the finger and the clock write every frame (27.0
  cancels an in-flight animation on an unanimated write to its attribute); (3) the lift `L = slack · a_h` mirrors the
  content's two attributes on both header slots, evaluated per frame at the viewport size the slot stands for, so the
  header's expression is the content's term for term (seam 0); `.stretch` takes `L` as extra growth at rest in both of
  D76's `.stretch`-content cases (crisp); (4) the refresh indicator's base and `obscuredDelta` add `L`; (5) keyboard inset changes follow UIKit's
  keyboard curve. Everything else (collapse, pull behaviours, snap, fade, overflow, zoom) is unchanged.
- **Measured.** Offset clamp adopted in the content's transaction: 240 → 421 pt over 30 frames, max step 12.1 pt (0.07 of
  the change), header/content seam within ±0.1 pt, 27.0 preferred and forced, internal and external changes.
- **Pre-existing stall (step 0, §2.3).** In the hosted rig, SwiftUI animations INSIDE the content stop after one frame
  whenever the library's transform is not animating: the user's own `withAnimation` row change too, on the unmodified
  library, 27.0 and 17.5, preferred and forced (pure SwiftUI ticks 30 frames in the same rig). It blocks the pad-only
  animations' gate, not the design; it is fixed first, as its own open item.

## 1. Evidence (spike, hosted, 27.0 sim `d75-27` and 17.5 sim `d75-175`, preferred + forced; drawn layer frames per display frame)

Rig: `D75SpikeTests` (scratch only). A 402 × 874 window, `.fixed(min: 64, max: 240)`, `.defaultScrollAnchor(.center,
for: .alignment)`, content = 5 or 10 rows of 60 pt (300 / 600 pt; the fitting region is 874 − 302 − 34 = 538 pt), the
header a marker color, the first row another; every display frame a `CADisplayLink` reads both layers' frames from the
presentation tree. `aci.top` = 302. Changes: `withAnimation(.easeInOut(duration: 0.5))` on an `@ObservedObject` inside the
content (internal) or on a value the content closure reads (external); unanimated; shrink while scrolled to the bottom.

| case (27.0, preferred and forced identical) | content top | header bottom | one-frame step |
|---|---|---|---|
| base, `.headerPinned` (pre-D63 look), grow animated | 421 → 302 | 302 | 119 pt = 1.00 of the change |
| base, `.headerFollows` (lift from the committed pad), grow animated | 421 → 302 | 421 → 302 | 119 pt, seam 0 |
| base, `.topAligned` (D63, today), shrink animated at the bottom | 240 → 302 | 240 → 302 | 62 pt = 1.00 |
| base, `.headerFollows`, shrink animated at the bottom | 240 → 421 | 240 → 421 | 181 pt = 1.00 |
| adopted in the transaction, every mode, shrink animated at the bottom | 240 → 421 / 302 | follows | 12.1 pt = 0.07, 30 frames, seam [−0.1, 0.1] |

- **Who sees the transaction.** In the turn of `setContentSize` the container's `.transaction` hook
  (`PositionDriver.animationInTurn`) and a `.transaction` hook on the content root BOTH carry the animation, for internal
  (`@ObservedObject` inside the content) and external changes (`csTx` = `contentTx` = 1 in all 16 animated runs).
  Unanimated changes: the content hook reports no animation (`contentTx` 0).
- **The content's own animation stops in the rig (§2.3).** A `GeometryEffect` on the content's own frame (where SwiftUI
  animates the frame size of the user's row change) was evaluated twice (300, 300.6) and never again in a 0.5 s
  animation, in the BASELINE too (fix 0, with and without a header, 27.0 preferred and forced): not a D75 effect.
- **Header slot size.** The header slot is the region between the safe areas: an effect on it gets 778 pt, not the 874 pt
  viewport (first spike: lift 71 pt instead of 119). The lift reconstructs the viewport as `slot + (V − container)`
  (committed `HeaderMath.containerHeight`), exact at rest and in SwiftUI-driven resizes with fixed safe insets (§6 R2).

## 2. Approach

### 2.1 Semantics (exact)

`slack = max(0, V − aci.top − aci.bottom − c·s)` (as `AxisGeometry.alignmentPadding`; with D71 a refresh hold does not
narrow it), `a` = the alignment anchor's `y`.

| case | content alignment `a_c` | lift alignment `a_h` | content `pad_y` | header |
|---|---|---|---|---|
| `.topAligned` | 0 | 0 | 0 | geometry(`o′`) (today) |
| `.headerFollows` | `a` | `a` | `slack·a` | geometry(`o′`) moved down by `L = slack·a`; `.stretch`: geometry(`o′ − L`) |
| `.headerPinned` | `a` | 0 | `slack·a` | geometry(`o′`) (today); the gap `slack·a` lies below it |

- The horizontal alignment is the anchor's in every case (unchanged).
- `.headerFollows`: `.preserve .openGap` = the lifted header stays, a pull opens the gap below it (refresh indicator
  there); `.preserve .followContent` = the header moves with the pull, the gap above grows (`L + g`); `.stretch` = the header
  grows by `L` at rest and by `L + g` pulled, and compresses only once the content has moved up by `L`
  (`o″ = o′ − L`); `.compress` / `.slideBehind`: both slots get `L`.
- Default alignment is `.topLeading` for a non-zoomable view: there all three cases are the same picture. They differ
  with `.defaultScrollAnchor(.center | .bottom, for: .alignment)` or a zoomable view (centre by default).
- Content that overflows: `slack = 0`, `L = 0`: identical to today in every case.
- A horizontal-only view's header is a banner the content lays out below (`HeaderContentReserve`, M8b-3) and never
  moves vertically: `.topAligned` keeps D63 (`y = 0`), `.headerPinned` and `.headerFollows` both keep the content's
  alignment below the banner with `L = 0` (the lift is vertical-only, as the spike's `metrics.header.vertical` guard).
- Two alignments, not a weight: `.topAligned → .headerFollows` animates `a_c` and `a_h` together (seam 0 throughout);
  `.topAligned → .headerPinned` animates `a_c` only (header still); `.headerFollows ↔ .headerPinned` animates `a_h` only
  (header slides, content still). A single `weight · pad` would dip the header in `.topAligned → .headerPinned`.

### 2.2 Mechanism

1. **Published alignment.** `ScrollMetrics.alignment: ContentAlignment { content: UnitPoint; liftY: CGFloat }` written
   by the state (`alignmentChanged()`): from `headerSpecChanged()` (option change, `HeaderSizing.fitting`) and from the
   container's `onAppear` / `onChangeCompat(of:)` hooks when the anchor or the zoom default changes, as
   `headerSpecChanged()` is wired (today a cold value nobody publishes; never a write during a body). Written with
   `withAnimationIfAny(positionDriver.animationInTurn)`, so `withAnimation { fitting = … }` animates.
   `contentAlignment` stays as a read-only accessor of `metrics.alignment.content` (its D63 rule moves into
   `alignmentChanged()`), so `ResizeMath` / `RefreshMath` / the solver and the five test files that read it
   (`HeaderReviewD16Tests`, `DefaultScrollAnchorTests`, `ZoomStateTests`, `ResizeSafeAreaStepTests`,
   `RefreshIndicatorLayerTests`) keep compiling unchanged.
2. **The content's shape is its own animatable attribute.** `ContentShape = (contentWidth, contentHeight, ax, ay, liftY)`
   is the animatable data of a second effect, `ContentShapeShift`, right outside `ContentTransform` in `TransformHost`:
   `Δpad = pad(TV, S_anim) − pad(TV, S_committed)` in a plain frame (0 while a resize draws: a resize's reflow is the
   commit's, D17), with the zoom and the insets as PLAIN inputs (not the offset: `Δpad` does not depend on it, so a
   finger or a bounce never updates this effect). `ContentTransform` keeps
   `TV` as its animatable data and draws `pad(TV_anim, S_committed)`. Why two attributes and not
   `AnimatablePair<TransformVector, ContentShape>` in one: on 27.0 an unanimated write cancels the in-flight animation
   of the attribute it lands on (17.5 keeps it: refresh-27 item 33). The finger and the clock write `TV` unanimated every
   frame (a pull, a bounce, a hold release), so a shape animation in the same attribute would jump to its end at the
   first such frame: rows inserted when a refresh ends, while the hold releases, is the common case. In its own
   attribute the shape animation runs through them; the second-order cross term (both animating at once) is the same on
   the header (item 4), so it never opens a seam.
3. **Adoption in the transaction.** `setContentSize` writes metrics, commit and the clamped offset in
   `withAnimationIfAny(positionDriver.animationInTurn)` (today: `unanimated`). The content gets its own hook:
   `ContentSizeMeasure` adds `.transaction { state.positionDriver.noteTransaction($0) }` (cold leaf; S4: no body). With
   no animation in the turn nothing changes (unanimated content changes stay instantaneous, as native).
4. **The lift mirrors the content's two attributes.** `ScalingHeader/HeaderLift.swift` (new): on both header slots
   (`HeaderOverlay` in the `.overlay` and the `.background` slot of `ScrollContainer`, no wrapper, no preference) two
   `GeometryEffect`s: `HeaderLiftBase` (animatable `TV`: `L(TV_anim, S_committed)`) and `HeaderLiftShift` (animatable
   `ContentShape`, plain zoom and insets: `L(TV, S_anim) − L(TV, S_committed)`), `L = a_h · slack`, `slack` from
   `ContentTransform.resolved(size: slot + dv)` (`dv` = committed `V − containerHeight`). With `a_h = a_c` the header's
   expression is the content's term for term: seam 0 under any mix of animated, unanimated and cancelled writes. The
   hot leaf `HeaderLiftHost` reads what `TransformHost` reads (`.target`, `.metrics`, `.phase`), so a pinch (`c·s`) moves
   it per frame with the content; a catch pins `HeaderLiftBase`'s `TV` with `ContentTransform`'s (refresh-27's pin).
5. **`.stretch`.** D76 (user ruling, 2026-11-02) makes the header content under `.stretch` an enum parameter of
   `withScalingHeader` beside this one: `.keepTextMagnified` (default, D69's look made crisp) and i28's layout grow.
   Both take `L` as extra growth at rest. `.keepTextMagnified`: `HeaderStretchEffect` takes `L` from the same inputs and
   scales by `(h + g + L)/h`, so D76's crisp path must be active whenever `g + L > 0`, not only while pulled (a
   `.headerFollows` header is magnified at rest). Layout grow: `grownSize(…, stretch: g + L)`, `L` computed inside
   `HeaderSlotLayout` from its `animatableData` (16+) and an `Animatable` frame modifier (15): a layout-interpolated `L`
   is linear in the progress, the real one is not at the fit/overflow kink (spike: 25 pt mid-transition for 300 → 600),
   so `L` must be evaluated per frame, not interpolated.
6. **Refresh and readers.** `HeaderMath.refreshTop` and the plain base add `L` when `a_h > 0`; the indicator evaluates it
   per frame with the same function (its overlay is viewport-sized: exact). `obscuredDelta`, `ZTronHeaderGeometry` and
   `ZTronHeaderGeometryReader` report the drawn header (committed `L`).
7. **Keyboard.** A keyboard inset arrives without a SwiftUI transaction (`txAnim:false` in the D64 logs) and moves
   `slack` by the keyboard height: with `a > 0` the content (and in `.headerFollows` the header) moves `kb·a` (≈ 168 pt
   centred), with or without a header (pre-existing for aligned fitting content). Not measured by this spike: if the
   update lands inside UIKit's keyboard animation block, Core Animation interpolates the transform (as in a rotation)
   and nothing is needed; the step-6 gate measures it first (seam lab `kbrotate` with the real keyboard, and
   `-ZTronSeamFakeKeyboard`), and K2 ships only if a step ≥ 0.5 is seen. Fix: the state writes a keyboard-driven
   inset change in UIKit's keyboard curve (`.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)`, iOS 13+;
   `KeyboardInsetFollow`), as SwiftUI's own keyboard avoidance re-centres a native ScrollView's content (parity).
   `.topAligned` with top content: no change (pad 0, offset kept).

### 2.3 A pre-existing stall: SwiftUI animations inside the content stop after one frame (step 0)

Found by the spike, NOT caused by D75: measured on the unmodified library chain (fix 10: no spike code in the path).

- **The user's own content animation stalls.** In a `withAnimation(.easeInOut(duration: 0.5))` row change (5 → 10 rows),
  an `Animatable` modifier inside the content driven by the same state (`uval`) and an effect on the growing rows' frame
  (`uframe`) are evaluated twice (start, +20–30 ms: 300.0, 300.6) and never again. The drawn content stays at the start
  until something else renders; then the final state appears in ONE frame (the next change's first frame: 119 pt).
  No header and with one, 27.0 preferred and forced (m6, the unmodified chain); 17.5 preferred and forced show the same
  2 evaluations on the spike chain without the clock (m5).
- **Pure SwiftUI ticks in the same rig** (window, run loop, `onGeometryChange` starting an animation): 30–31 evaluations
  for captured, fresh and re-boxed animations, the effect as sibling or ancestor of the measured view, an effect on an
  animated frame (30), and beside a paused or a running `TimelineView(.animation)` (31 / 31). Only a `geometryGroup()`
  beneath the animated effects stalled (2).
- **Ruled out** (each removed from the unmodified chain, 27.0 and 17.5, preferred and forced, all still 1–2
  evaluations; m7 = 27.0, m7-175 = 17.5): the
  library's clock (`FrameClockDriver`, m5), the content's layer group (`ContentLayerGroup`, m4 / m7), the spike's
  instrumentation (m6), the content `Layout` (`ScrollContentLayout` → the 15 path, m7), `CompletionObserver`'s
  `.transaction` (m7), and **the library's whole reaction to the change** (`setContentSize` returning at once: no state
  write at all, m7). Pure SwiftUI with an ancestor effect whose input `onGeometryChange` writes plainly or with
  `disablesAnimations` during the animation ticks (30 / 30 on both OSes, m7 / m7-175). So a STATIC part of the container's structure around
  the content stops the content's animations; what remains to bisect is listed in step 0.
- **Everything ticks while the library's own transform animates** in the same window: shrinking at the bottom (the
  clamp animated), the content, the user's `uval` / `uframe` and the D75 shift all run 30–32 evaluations.

Consequences. (1) D75's adoption works where frames are produced (the clamp: 30 frames, step 0.07, seam ±0.1), but the
pad-only and option-change animations cannot pass the ≥ 20-frame gate until the stall is fixed. (2) Today a user's own
animated change inside a `ZTronScrollView` that changes the content's size (rows inserted or expanding with
`withAnimation`) freezes after one frame in the rig (changes that keep the size were not measured).
Step 0 fixes it first, as its own open item (next free number at merge), with the gate: `uval` / `uframe` ≥ 20
evaluations in 0.5 s for a plain row change, without and with a header, on the three lanes, and a seam-lab `rows` run
in the app (drawn frames from the recording) to confirm the app behaves as the rig.

## 3. Alternatives (measured or rejected with the reason)

- **Lift interpolated by layout** (the header leaf runs once in the transaction, SwiftUI lerps its frame): exact only while
  `L` is linear in the progress; crossing fit/overflow it is not (`max(0, ·)`): 25 pt seam at mid-transition for
  300 → 600 (computed from the spike's numbers: pad 0 at progress 0.79 while the lerp still holds 25 pt). Rejected.
- **Pad from the content's drawn frame** (an effect at the content frame + the header via a preference read in the
  transaction): the frame is the layout frame at scale 1, while the pad depends on `c·s` and on the insets (render-time:
  a pinch, a keyboard, a hold), so it cannot serve those paths; the header needs the same value per frame and a
  preference delivers committed values only (it cannot follow an implicit `.animation(_:value:)` inside the content).
  The rig's measurement (2 evaluations) is the §2.3 stall, not an argument. Rejected on the design grounds.
- **Re-express the pad change as an offset animation** (offset animations are proven): a transient offset past the rest
  position reads as a pull (`o′ < 0`): `.stretch` grows, the refresh engine and the pull fade see a pull, delegates see a
  scroll. Rejected.
- **Exclude the keyboard from the slack (K1)**: no motion at all, but centred content stays behind the keyboard while a
  native ScrollView re-centres it above. Rejected for parity (K2 above).
- **Header inside the content's transform** (the header would follow every content motion for free): changes z-order,
  hit testing, `.slideBehind`, D62's layout-driven header and S4's leaf structure. Rejected (scope, risk).
- **A `Layout` measuring the content** (to get the size in the layout pass): re-ran content bodies on 17.5 before
  (memory: content wrappers). Rejected.
- **One weight `w · pad` instead of two alignments**: dips the header in `.topAligned → .headerPinned`. Rejected.

## 4. Files and types

| file | change |
|---|---|
| `ScalingHeader/HeaderTypes.swift` | `public enum ZTronHeaderFittingContent { topAligned, headerFollows, headerPinned }` + docs (§7) |
| `ScalingHeader/HeaderSpec.swift` | `HeaderSpec.fitting`, `HeaderSizing.fitting` (Equatable: a change runs `headerSpecChanged()`) |
| `ScalingHeader/ScalingHeaderAPI.swift` | `fittingContent:` after `overflow:` (defaulted: source-compatible, no deprecation; D76's `.stretch`-content parameter right after it); doc; the deprecated `scalingBehavior:` overload keeps its parameters (forwards `.topAligned`), its DocC link moves to `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:header:)` |
| `State/ScrollStateTypes.swift` | `ScrollMetrics.alignment` (`ContentAlignment`) |
| `State/ZTronScrollState.swift` | `alignmentChanged()`; `contentAlignment` reads the published value; `setContentSize` adopts `animationInTurn` (metrics, commit, clamp); keyboard inset follow (if step 6 ships) |
| `Render/ContentTransform.swift` | `ContentShape` + `ContentShapeShift` (second effect, own attribute); `resolved` takes the committed shape; `TransformHost` applies both |
| `Render/ContentLayoutHost.swift` | `ContentSizeMeasure`: content `.transaction` hook |
| `ScalingHeader/HeaderLift.swift` (new) | `HeaderLiftBase` + `HeaderLiftShift` effects, `HeaderLiftHost` leaf |
| `ZTronScrollView.swift` | both header slots get `HeaderLiftHost` (no wrapper: the slot keeps its safe-area placement) |
| `ScalingHeader/HeaderFrameModifier.swift` | `.stretch`: `L` into both D76 cases (`.keepTextMagnified`'s scale `(h + g + L)/h`; the layout grow's `HeaderSlotLayout` / 15 frame) |
| `ScalingHeader/HeaderMath.swift` | `refreshTop` / plain base `+ L`; `obscuredDelta` `+ L`; `lift(…)` pure function |
| `Refresh/RefreshIndicators.swift` | base `+ L` per frame (same function) |
| Demo `SeamLabScreen.swift` | `-ZTronSeamRows n`, `-ZTronSeamRowsTo m` (seam.width toggles rows), `-ZTronSeamRowsInternal 1`, `-ZTronSeamRowsPlain 1`, `-ZTronSeamAlign center`, `-ZTronSeamFitting top|follows|pinned` (spiked); `-ZTronSeamZoomable 1`, `-ZTronSeamStart bottom` (step 7) |
| Demo UI tests, `scripts/seam/measure.sh` | `testRows`, `testFitting`; `rows`, `fitting` |
| Demo `HeaderScreens.swift` / catalog | a "Short content" page with the three cases and an Add/Remove rows button |
| Tests | `HeaderFittingContentTests` (new), `HeaderReviewD16Tests` D63 test kept for `.topAligned` |

## 5. iOS 15 availability, S4, S7

- Everything is `GeometryEffect`, `Animatable`, `.transaction`, `withAnimation` and `interpolatingSpring`: iOS 13+. The 15 path
  differs only where it already does (channels instead of Observation, `HeaderFallbackFrame` instead of
  `HeaderSlotLayout`, compositing groups); the forced lane measured the same numbers as preferred (§1).
- S4: no new body runs. The lift leaf wraps the header placeholder (its body re-runs on `.target/.metrics/.phase`, like
  `TransformHost`); the content hook is cold. Counters: `contentBody` 0 (bodies other than the changed row's own) for a
  content-size animation, a pinch, a pull and an option change; `headerBody` 0 for all but the option change, which
  runs the header builder once (a cold spec change, as today). Step 0's fix must keep both.
- S7: rotation keeps the visible centre: fitting content has no scroll range, it is re-aligned in the new viewport by the
  same `ResizeMath` path; the lift follows from the same function at the drawn size (CA interpolates both linearly).

## 6. Risks

- R1 (stall, §2.3): pre-existing; step 0 fixes it before steps 2-4 can pass their ≥ 20-frame gates. If the app does
  not show it (rig-only), step 0 still makes the rig tick (the gates run there) and closes with the seam-lab proof.
- R2: the slot-size reconstruction `slot + dv` assumes fixed safe insets during a SwiftUI-driven resize. A resize that also
  changes them (bottom-pinned height change leaving the home indicator, M8b-s6) moves `dv` at the commit: the lift error is
  `Δsafe · a_h` during the animation (17 pt centred). Gate: seam lab `height` bottom-pinned with fitting centred content.
  Fallback: carry `dv` in `ResizeCommit` (previous and current) and interpolate it with the slot's progress.
- R3: readers (`ZTronScrollGeometry`, delegates, `contentSize`) see the committed shape at once while the drawn pad
  animates: model-based, as UIKit's `contentSize` (no reader reports the drawn pad today either).
- R4: D71 (DBG-s12, not merged) must land first or with it, else a hold narrows the slack and the lifted header moves by
  `hold · a` against the content.
- R5: keyboard curve: SwiftUI's keyboard animation is not public; the spring is an approximation (motion, not a seam).
- R6: refresh-27 measured that 27.0 drops an effect's in-flight residual at the first plain update that changes its
  animated value (17.x keeps it). The shape effect's inputs exclude the offset, so a finger, a bounce or a hold release
  never updates it; only a pinch (zoom, a plain input) or an inset change does, with its animatable data unchanged.
  Gate: hosted "rows inserted during a bounce / a hold release / a pinch" (§9.2) on 27.0 and 17.5, no step ≥ 0.5.

## 7. Doc comments (public)

`ZTronHeaderFittingContent`:
"What a scaling header does with content that fits (shorter than the viewport below the resting header). The content's
vertical alignment comes from `defaultScrollAnchor(_:for: .alignment)` (centre for a zoomable view, top otherwise); with a
top alignment all cases look the same."
- `topAligned`: "The default. The content starts at the header's bottom edge whatever its vertical alignment; its
  horizontal alignment is kept. Header and content behave as they do when the content overflows."
- `headerFollows`: "The content keeps its alignment and the header rides on its top edge, as if it were the content's first
  row: centred content and header are centred together, with the scroll view's background above the header. With
  `.stretch` the header grows into that space instead, as a pull of the same size would make it grow. Pulls, refresh and
  collapse work from there."
- `headerPinned`: "The header stays at its resting place and the content keeps its alignment in the region below it, with
  a gap between the two (the look of a header pinned as a safe-area inset)."

Parameter doc: "`fittingContent`: where content that fits sits relative to the header (`.topAligned`, the default;
`.headerFollows`; `.headerPinned`). A change at run time animates in the transaction it is made in."

## 8. Build steps (each one a green commit: build, the suites it touches, then commit)

| # | step | files | green when |
|---|---|---|---|
| 0 | **Content animations tick** (pre-existing, its own open item; §2.3). Finish the bisect in a hosted rig like `D75SpikeTests` (`uval` / `uframe` evaluations, one flag per suspect, the library's reaction to the change already ruled out): the static pieces still in the path are `TransformHost` / `ContentTransform` (non-animating animatable effect above the content; its `state.probe`), `ContentInteractionGate`, `NamedSpaceModifier`s, `HeaderContentReserve`, `ContentOverlayHost`, `ContentSizeMeasure`'s measurement, `MeasurementIsolation`, `ViewportObserver`, the overlays, `PanGestureAdapter`, `.clipped()` / `.contentShape`, the container `.transaction` hook; then fix it without an API change. Known lever (measured): everything ticks while `ContentTransform` itself animates. | per bisect | hosted `ContentAnimationTickTests` (new): a plain content row change, `uval` / `uframe` ≥ 20 evaluations in 0.5 s, without and with a header, three lanes; S4 counters unchanged; seam-lab `rows` in the app shows the rows' own animation (rig = app) |
| 1 | **API and spec, no new drawing.** `ZTronHeaderFittingContent` (§7 docs), `fittingContent:` after `overflow:` (default `.topAligned`), `HeaderSpec.fitting` / `HeaderSizing.fitting` (Equatable, so a change runs `headerSpecChanged()`). `contentAlignment` zeroes `y` for `.topAligned` only: `.headerPinned` is the pre-D63 picture; `.headerFollows` draws as `.headerPinned` until step 4 (internal state between commits, never released). | `HeaderTypes`, `HeaderSpec`, `ScalingHeaderAPI`, `ZTronScrollState` | `HeaderFittingContentTests` (new: default compiles and is D63; `.headerPinned` pad = `slack·a`), `HeaderReviewD16Tests` (D63 test kept as `.topAligned`), `scripts/build.sh` incl. the demo |
| 2 | **Published alignment.** `ScrollMetrics.alignment` (`content`, `liftY`), `alignmentChanged()` from `headerSpecChanged()` and from the container when the anchor or the zoom default changes, written in `withAnimationIfAny(positionDriver.animationInTurn)`. `contentAlignment` becomes an accessor of `metrics.alignment.content` (callers unchanged). | `ScrollStateTypes`, `ZTronScrollState`, `HeaderHost`, `ZTronScrollView` | hosted: a run-time option change `.topAligned → .headerPinned` animates (drawn frames ≥ 20 in 0.5 s, step ≤ 0.25 of the change); anchor change publishes (`.metrics` subscriber count 1); resize suites unchanged |
| 3 | **Animatable content shape, adopted in the transaction.** `ContentShapeShift` (own attribute, §2.2 item 2) outside `ContentTransform`; `ContentTransform` draws `pad` from the committed shape, the resize path keeps the commit snapshots (D17). `setContentSize` writes metrics, commit and the clamped offset in `withAnimationIfAny(animationInTurn)`; `ContentSizeMeasure` gets the content `.transaction` hook (cold). No animation in the turn: unchanged (instantaneous, as native). | `ContentTransform`, `ContentLayoutHost`, `ZTronScrollState` | hosted grow / shrink / shrink-at-bottom × 3 cases × internal / external × animated / plain, 27.0 preferred + forced and 17.5 (thresholds §9.2); the default mode's clamp (62 pt today) animates; rotation / resize suites (S7) unchanged |
| 4 | **The lift.** `ScalingHeader/HeaderLift.swift`: `HeaderLiftBase` + `HeaderLiftShift` + `HeaderLiftHost` on both slots (no wrapper, no preference; the base takes refresh-27's pinned `TV`); `HeaderMath.lift(…)` (pure); `refreshTop` / plain base / `obscuredDelta` `+ L`; `RefreshIndicators` base `+ L` per frame; `ZTronHeaderGeometry` reports the drawn header. | `HeaderLift` (new), `ZTronScrollView`, `HeaderMath`, `RefreshIndicators`, `HeaderTypes` (`ZTronHeaderGeometry`), `ZTronHeaderGeometryReader` | hosted seam ≤ 1 pt every drawn frame in `.headerFollows` (grow, shrink, option change, pinch on a zoomable view); refresh indicator 0 frames over the content with a hold; unit `HeaderMathTests` for `lift` |
| 5 | **`.stretch` takes `L`** (after D76, both of its cases). `.keepTextMagnified`: `HeaderStretchEffect` scales by `(h + g + L)/h` and D76's crisp path activates on `g + L > 0` (not only while pulled); layout grow: `grownSize(…, stretch: g + L)`, `L` from `HeaderSlotLayout.animatableData` (16+) / the 15 `Animatable` frame. Before D76: not shipped for `.headerFollows` + `.stretch` (the header magnified at rest would be blurred, item 28, which the user refuses): step 5 waits for D76. | `HeaderFrameModifier` (`HeaderStretchEffect`), `HeaderSlotLayout` / `HeaderFallbackFrame` | hosted, both D76 cases: header height at rest = `h + L`, crisp at rest too (D76's own check), compression starts after the content moved up `L`; seam ≤ 1 pt |
| 6 | **Keyboard** (only if the first measurement shows a step ≥ 0.5). `KeyboardInsetFollow`: a keyboard-driven inset change with no transaction in the turn is written in `.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)` (UIKit's keyboard curve; iOS 13+, the same on 15–16). Applies with or without a header (pre-existing for aligned fitting content). | `ZTronScrollState`, `Render/ViewportSpaces.swift` (`ViewportObserver`) | hosted: fake keyboard (`keyboardExtension` 0 → 336) moves centred fitting content over ≥ 15 frames, step ≤ 0.25; seam ≤ 1 pt in `.headerFollows`; top content: no motion |
| 7 | **Demo and lab.** Catalog page "Short content" (three cases, Add / Remove rows animated and not, a zoomable variant). Seam lab: `-ZTronSeamRows n`, `-ZTronSeamRowsTo m`, `-ZTronSeamRowsInternal 1`, `-ZTronSeamAlign center|bottom`, `-ZTronSeamFitting top|follows|pinned`, `-ZTronSeamZoomable 1`; `testRows` and `testFitting` in `SeamLabUITests`, `rows` / `fitting` in `scripts/seam/measure.sh`. | Demo, `SeamLabUITests`, `scripts/seam/measure.sh` | demo builds; the lab matrix (§9.1) |
| 8 | **Docs.** SPEC S10 (D63 → D75, the three pictures; the `withScalingHeader` signature at SPEC:498), the public doc comments (§7), `Orchestration.md` Decisions D75 + the step-0 open item; full suite on the three lanes. | `docs/SPEC.md`, `Orchestration.md`, a `docs/progress/` handoff | full suite green on the three lanes |

## 9. Acceptance per lane (27.0 preferred, 17.5 preferred, 27.0 forced `-ZTronForceAllFallbacks`)

### 9.1 Seam lab (`scripts/seam/measure.sh`, recording + `analyze.py`)

Base: `-ZTronSeamRows 5 -ZTronSeamRowsTo 10 -ZTronSeamAlign center -ZTronHeaderSize fixed -ZTronSeamCollapse compress`,
each row × `-ZTronSeamFitting follows | pinned | top`.

| scenario | extra args | what it checks |
|---|---|---|
| `rows` (new) | none / `-ZTronSeamRowsInternal 1` / `-ZTronSeamRowsPlain 1` | fit ↔ overflow, external and internal, animated and plain |
| `rows` at the bottom | `-ZTronSeamStart bottom` (new value) `-ZTronSeamRows 10 -ZTronSeamRowsTo 5` | the clamp (62 pt one-frame jump today in `top`) |
| `fitting` (new) | `top → follows → pinned → top` animated | run-time option change |
| `rotate`, `rotatel` | none | S7 with fitting content |
| `width` | none / `-ZTronSeamAnimateHeight 0.6` / `-ZTronSeamAnimateHeight 0.6 -ZTronSeamBottomPinned 1` | resize; R2 (safe inset moves with the resize) |
| `kbrotate` | `-ZTronSeamKeyboard 1`; `-ZTronSeamFakeKeyboard 336` | keyboard up, rotation, keyboard down (K2) |
| `pull` | `-ZTronHeaderBehavior stretch`, `-ZTronSeamPull openGap`, `-ZTronSeamPull followContent`; each with `-ZTronSeamRefresh 2 -ZTronSeamHold 1` and `-ZTronSeamHoldOverlay 1` | `.stretch` at rest and pulled; refresh holds (gap, overlay, band) |
| `fling`, `snap`, `scroll` | `-ZTronSeamRows 10` (overflowing) | unchanged behaviour when the content overflows |
| extended (27.0 preferred + forced) | `-ZTronSeamCollapse slideBehind` × `rows`, `rotate`, `pull`; `-ZTronHeaderSize fit | capped | refit` × `rows`, `rotate`, `width`; `-ZTronHeaderSize fit -ZTronSeamFitGrow 1` × `width` (the resting height changes, so `aci.top` and the slack do); `-ZTronSeamZoomable 1` × `rotate`, `rows`, `pinch` (new: `testPinch`, XCUI `pinch(withScale: 2, velocity: 1)`) | collapse modes, sizes, zoomed content |

Thresholds (every row, every lane): |seam| ≤ 1 pt (`follows`: header bottom = content top; `pinned` / `top`: gap =
`slack·a` resp. 0, ± 1 pt), lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change, refresh indicator drawn 0 frames over the
content, the counters `contentBody` 0 and `headerBody` 0 for every transition but `fitting` (one header build: a cold spec
change). Lanes whose load is > ~300 re-run alone before a verdict.

### 9.2 Hosted tests (`HeaderFittingContentTests`, the spike's drawn-frame sampler: presentation-tree frames per display frame)

- grow / shrink 300 ↔ 600 animated (external, internal): content and (follows) header move on ≥ 20 drawn frames in 0.5 s,
  max step ≤ 0.25 of the change, |seam| ≤ 1 pt on every frame (follows), header still (pinned, top).
- plain change: one frame, final position exact (parity with native: an unanimated layout change is instantaneous).
- shrink at the bottom: the clamp and the pad on the same curve (spike: 30 frames, step 0.07, seam ±0.1).
- rows inserted during a clock motion (a pull released into its bounce, a hold release): the shape animation runs
  through the unanimated per-frame `TV` writes on 27.0 (no step ≥ 0.5; the single-attribute variant would jump).
- option change at run time, animated: `top → follows` seam ≤ 1; `top → pinned` header still; `follows ↔ pinned` content still.
- pinch on a zoomable fitting view in `.headerFollows`: seam ≤ 1 pt per frame (the lift reads `c·s`).
- refresh hold in `.headerFollows`: indicator base = the drawn (lifted, `refreshTop + L`) header bottom ± 0.5 pt, 0 frames
  over the content (with D71), `.openGap` and `.followContent`, both collapse modes.
- counters: `contentBody` 0, `headerBody` 0 during all of the above but the option change.

## 10. Real iOS 15.0 / 16.0 (the M1 lane)

1. **Transaction capture.** 15 measures the content size by preference (`onPreferenceChange`), 16 by `onGeometryChange`:
   log `animationInTurn != nil` at `setContentSize` for an animated row change, internal and external (the spike's
   `csTx` / `contentTx`). If 15 delivers the preference a turn later (the container hook already cleared), the content
   hook must carry it: confirm `contentTx` = 1 on 15.0.
2. **Ticking.** The hosted grow test (§9.2) on 15.0 and 16.0: ≥ 20 drawn frames in 0.5 s for the content's own row
   animation AND the pad (§2.3: the stall found on 27.0 / 17.5 must be absent after step 0), under the 15–16
   `compositingGroup` content group with a header.
3. **Seam.** `rows`, `fitting`, `rotate`, `pull` with a hold in `.headerFollows`: |seam| ≤ 1 pt, steps < 0.5, the same
   drawn curve as 17.5 (frame-by-frame overlay of the two recordings: no 15–16 look difference).
4. **Keyboard.** Centred fitting content against the real keyboard on 15.0 / 16.0 (`kbrotate` with
   `-ZTronSeamKeyboard 1`): no step ≥ 0.5, content and keyboard top within 1 frame (with K2 if step 6 shipped it; 15–16
   may land the update inside UIKit's keyboard block where 17+ do not, or the reverse: measure both).
5. **`.stretch` in `.headerFollows`** (after D76), both D76 cases: header at rest `h + L`, crisp on 15.0 / 16.0
   (`.keepTextMagnified`: D76's crisp path active at rest; layout grow: the 15 `Animatable` frame).
6. **S7.** Rotation of centred fitting content in all three cases: visible centre kept, seam ≤ 1 pt.
7. **The stall before step 0.** The unmodified chain's `uval` / `uframe` on 15.0 / 16.0 (does the content's own
   animation stop there too?): tells step 0 whether the cause is OS-specific.
8. **R6 on 15 / 16.** Rows inserted during a bounce, a hold release and a pinch: the shape animation keeps running when
   only plain inputs change (no step ≥ 0.5).

## 11. Interactions with the other s8 designs (shared: `HeaderHost`, `HeaderFrameModifier`, `HeaderSlotLayout` /
`HeaderFallbackFrame`, `GroupLatch`, `ContentTransform`, `RefreshIndicators`)

- **i15b-15path-resize (D78).** No shared lines. The lift reconstructs the viewport as `slot + dv` with
  `dv = V − HeaderMath.containerHeight(…)`: the 15-path slot `H` (D78) and `overflowLimit` must keep that same definition
  (i15b's unit `R0 = 0.25 · 781` and the D75 forced test "lift at rest = `slack·a`" both catch a divergence). Land in
  either order.
- **i28-stretch-blur (D76; user ruling 2026-11-02: `.stretch`'s header content is an enum parameter of
  `withScalingHeader` beside D75's, default `.keepTextMagnified`).** The two parameters are independent; recommended order
  `…overflow:fittingContent:<D76's>:header:`, fixed once by the architect. `.stretch` in `.headerFollows` grows by `g + L`
  in both D76 cases: `.keepTextMagnified` scales by `(h + g + L)/h`, so D76's crisp path (pure SwiftUI, or the scoped
  path `d76-magnified-eval` evaluates) must gate on `g + L > 0`, not on "pulled": a `.headerFollows` header is magnified at
  rest. The layout grow takes `g + L` through `grownSize`, `L` evaluated per frame inside `HeaderSlotLayout.animatableData`
  (16+) / the 15 `Animatable` frame (a layout-interpolated `L` is wrong by up to 25 pt across the fit / overflow kink, §3).
  D75 step 5 lands after D76 (before it, the header magnified at rest would be blurred: item 28).
- **i29-blend-slidebehind (D77).** Both edit `Render/ContentTransform.swift`: D77 `TransformHost` (179-204) and
  `ContentLayerGroup` / `GroupLatch` (232-301); D75 adds `ContentShape` / `ContentShapeShift` (one modifier outside
  `ContentTransform` in `TransformHost`'s chain; `ContentTransform.animatableData` stays `TV`) and `resolved` takes the
  committed shape. Land in either order, rebase the second. §2.3: a `geometryGroup()` beneath an animated
  `GeometryEffect` stops it ticking in the minimal experiment, so D77's outer group G must pass step 0's
  `ContentAnimationTickTests` and D75's hosted grow test (≥ 20 frames) on 27.0 preferred and forced, whichever lands
  second.
- **refresh-27-31-32-33.** Their catch pin stores a copy of `ContentTransform`'s `animatableData` (`TV`); D75's shape is
  a separate attribute the pin does not touch (a content-size animation runs through a catch, as UIKit's content size
  changes do), and `HeaderLiftBase` must take the same pinned `TV` (else a catch during an inset animation opens a seam
  of `Δslack · a`). D75 adds `+ L` to the indicators' base per frame (placement L1-L3 take the base as an input). Theirs
  lands first, D75 step 4 is additive. D71 (DBG-s12: a hold does not narrow the slack) is a prerequisite of step 4 (R4).
- **SHEET-s4.** Not touched (no gesture change).

## 12. Numbering and user questions

- D75 (this design). New open item for the stall (§2.3) if step 0 is split out: next free at merge (34+; i29 proposes 34).
- Questions (taste only; the defaults are in the design):
  1. Parameter and case names: `fittingContent:` with `.topAligned` / `.headerFollows` / `.headerPinned` (default), or
     `shortContent:` / `.belowHeader` / `.withHeader` / `.headerAtRest`.
  2. Ship `.headerPinned` (the pre-D63 look) as a third case (default: yes; it is the look of a header pinned as a
     safe-area inset and costs one alignment value), or only two cases.

## 13. Spike artifacts (scratch, removed with the spike worktree)

- The whole spike as one patch against 09226f4: `s8/d75-short-content/spike.patch` (`git apply` in a scratch worktree;
  step 0 can reuse its rig: `D75SpikeTests` with the `uval` / `uframe` probes and the fix switches in `D75Probe.fix`).

- `Render/D75Spike.swift` (probe, `ContentAlignmentShift`, `HeaderAlignmentLift`, `HeaderLiftHost`, `D75HeaderSlot`),
  edits in `HeaderTypes` / `HeaderSpec` / `ScalingHeaderAPI` / `ZTronScrollState` / `ContentTransform` /
  `ContentLayoutHost` / `ZTronScrollView`, `Tests/ZTronScrollViewTests/D75SpikeTests.swift`, demo `SeamLabScreen` flags.
- Logs (kept): `s8/d75-short-content/logs/m1-27 … m7-27`, `m5-175`, `m7-175` (`D75`, `D75TS`, `D75EXP` lines). Variants:
  fix 0 baseline (spike chain), 1 / 3 / 4 / 5 / 7 / 8 adoption variants, 2 frame pad, 9 no clock, 10 unmodified chain,
  11 unmodified + shift, 12 no `Layout`, 13 no `CompletionObserver`, 14 no group, 16 no `setContentSize` write;
  minimal modes 1-12 (pure SwiftUI).
