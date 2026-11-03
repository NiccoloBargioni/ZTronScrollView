# M8b-s8 build plan (architect, 2026-11-03)

Base `72ca7fc` on `claude/cool-stonebraker-0015c9`. Inputs: the five designs committed beside this file
(`M8b-s8-refresh-27-31-32-33.md`, `M8b-s8-i15b-15path-resize.md`, `M8b-s8-i28-stretch-blur.md`,
`M8b-s8-d75-short-content.md`, `M8b-s8-i29-blend-slidebehind.md`) and the D76 evaluation (`M8b-s8-d76-magnified.md`).
Where this plan amends a design (§3), the plan wins. Spike artifacts (patches, tools, tables) persist in the shared notes
folder `m8b-s8-resume/s8-spikes/<design>/`; the scratch copies vanish at a reboot.

## 0. Outcome

| built (10 steps, each a green commit) | not built |
|---|---|
| Refresh items 31, 32 (s1), 33 + its 17.5 header residual (s3, D79), 27 (s4, D80) | i29 / D77: blocked, needs the user's decision (§4) |
| New open item 34, content animations stall after one frame (s2) | Item 27's 15-16 rotation-start residual: blocked on D77 (§4) |
| Item 15 (b), the 15-16 header from its own slot (s5, D78) | Item 15 (c) (`combo`): stays open (i15b §1.4) |
| D76 `stretchContent:` with `.keepTextMagnified` (default, D69) and `.keepTextSize` (s6, s7): item 28's grow case | The crisp `.keepTextMagnified`: M8b-s9 (user ruling, §7) |
| D75 `fittingContent:` (s8, s9, s10) | New open item 35, the main-thread stall at a refresh trigger: recorded, not built |

## 1. Numbering

Checked against main and `git log --all` on 2026-11-03: main's last used is D74 (SHEET-s3 refused); INTEG-s1 (d294ecf)
reserved D75 and items 27-33 for this line and calls D76 / open item 34 next free, so D76 (the user's ruling here) and
everything after it must be re-checked at merge (D-numbers collide across sessions). `claude/dbg-refresh-reversal` holds D71
(DBG-s12, not on main, not here); `claude/sheet-s4-parity` (paused) adds no number.

| number | what | step |
|---|---|---|
| D75 | `fittingContent:` (D63 becomes an option, user ruling) | s8-s10 |
| D76 | `stretchContent:` (user ruling) | s6, s7 |
| D77 | reserved: i29 route P (D77′ = G + public probe); pending the user | not built |
| D78 | i15b: `HeaderSlotReader` + the `.fit` ideal-ratio box | s5 |
| D79 | catch where it is drawn: drawn-motion window, adoption at the drawn offset, 17.x rebase, `CatchPin` on every offset-following effect | s3 |
| D80 | item 27: the ungrouped headerless gap indicator drawn behind the content; D66 retired | s4 |
| D81 | reserved for s2 if its fix is a structural decision (else unused) | s2 |
| open item 34 | SwiftUI animations inside the content stop after one frame (d75 §2.3) | s2 |
| open item 35 | main-thread stall right after a refresh trigger (refresh §8, "candidate 34"): profile on an idle machine | recorded only |

Items 31 and 32 are fixes, no D-number.

## 2. Order, dependencies, key scenarios

| step | depends on | key scenario (later builders re-run it on this lane) |
|---|---|---|
| s1-refresh-31-32 | – | 17.5 `aspect-rest-stretch-pull-refresh-rtrig40` |
| s2-content-anim-stall | – | `ContentAnimationTickTests` + 27.0 `fixed-rest-preserve-rows-rows5-rowsto10-internal` |
| s3-refresh-33-catch | s1 (the carry; item 32's re-grab during a reset is judged here) | 17.5 `aspect-rest-stretch-fling-hold-hsys60-hend1p5-hreset4-fdown` |
| s4-refresh-27-behind | s3 (same effect, pin first) | forced `fixed-rest-preserve-width-noheader-hold-height04-instant` |
| s5-i15b-d78 | s3 (keeps the pin reads) | forced `fit-half-preserve-width-grow` |
| s6-d76-api-16 | s3 (pin on the paired effects) | 27.0 `fixed-rest-stretch-pull-text-ksize` (crispness + seam) |
| s7-d76-15-ui | s5, s6 | forced `fit-rest-stretch-width-hold-grow-ksize` |
| s8-d75-shape | s2 (≥ 20-frame gates), s6 (parameter order) | 27.0 `fixed-rest-preserve-rows-rows5-rowsto10-acenter-fpinned` |
| s9-d75-lift | s3 (pinned TV), s5 (slot H), s8 | 17.5 `fixed-rest-preserve-rows-rows5-rowsto10-acenter-ffollows` |
| s10-d75-stretch | s6, s7, s9 | forced `fixed-rest-stretch-pull-acenter-ffollows-rows5` |

Extras such as `rows5`, `rowsto10`, `acenter`, `ffollows`, `ksize` are added by the step that needs them (C19); the names
are suggestions, the builder fixes them in `scripts/seam/baseline.sh` and records them in its handoff.

## 3. Conflicts and resolutions

- **C1, the `withScalingHeader` signature.** Final: `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:
  fittingContent:stretchContent:header:)`. D76 lands first (s6) with `stretchContent:` after `overflow:`; D75 (s8) inserts
  `fittingContent:` before it. The deprecated `scalingBehavior:` overload forwards both defaults; its `renamed:` / DocC
  link follow the new signature (tested in `ScalingHeaderAPITests`).
- **C2, header effects that follow the offset.** Six follow `o′`: `HeaderStretchEffect`, `HeaderStretchClip`,
  `HeaderTranslation`, `HeaderSlotLayout`, `HeaderFallbackFrame` and `HeaderFadeOverlay` (the refresh design lists five; the
  fade overlay's `animatableData` is `live.offset` too). s3 makes all six read `live.pinned(key)`. s6 turns five of them
  (all but `HeaderTranslation`) into `AnimatablePair(o′, m)`: the pin replaces only `o′`, `m` stays interpolated. s9's
  `HeaderLiftBase` takes the same pinned `TV` as `ContentTransform`. Any future effect that animates the offset takes the pin.
- **C3, `ContentTransform.swift` (DBG-s12 edits it on another branch).** Minimal hunks only: s3 (the stored copy, the
  `effectValue` lines, `TransformHost`'s arguments), s8 (`pad` from the committed shape). New types go in new files:
  `Render/CatchPin.swift` (s3), `Render/ContentShape.swift` (s8), `ScalingHeader/HeaderLift.swift` (s9).
- **C4, `RefreshIndicators.swift`.** s1 (placement) → s3 (pin on `RefreshPlacementEffect.pull`) → s4 (layer slot, D66 deleted)
  → s9 (base `+ L` per frame).
- **C5, `ZTronScrollView.swift`.** s2 (only if the stall's fix is in the container) → s4 (behind slot, `RefreshHolder` hoisted)
  → s9 (`HeaderLiftHost` on both header slots).
- **C6, `HeaderFallbackPlan` / `HeaderFallbackFrame`.** s3 (pin read) → s5 (slot, box) → s6 (pair) → s7 (pulled parameters)
  → s10 (`L`).
- **C7, `.fit` while pulled.** i15b §11 says `noteBox` skips frames with `g > 0` and measures at release; i28 §4.8 supersedes
  it: under D69 (`g_l = 0`, s5) a pull does not change the box's layout, and from s7 the box uses the pulled parameters and
  reports `box.height / s_l`, measured in layout. No skip, no adopt-at-release.
- **C8, items 31 / 32 (an established look stays the default).** The refresh design's L1 (the band's `.system` pull look
  centred) changes a look every app sees today; under the user's rule (a fix that changes an established look becomes an
  option, the old look the default) it is not built. Built: the engine carry (§3.2), L2 (opacity
  `min(1, max(p/L, dragPosition))`, overlay centre `−L/2 + L·min(1, max(p/L, dragPosition))`), L3 (`holdsPlacement` for every
  style in the band) and, instead of L1, a handover for the band `.system` pull look:
  `center = min(s, L) − L/2 + max(0, L·dragPosition − p)/2` (`s` the pull, `p = max(0, s)`, `dragPosition = min(1, p/T)`).
  It equals today's slide-in look for `T ≥ L` (every default: `L·dragPosition ≤ p`), reaches the refreshing look `min(s, L)/2`
  exactly at `p = T`, equals it for every `p ≥ T` (the release trigger mode's `.armed` state included), and is continuous and
  monotone in `s`. `.default` positions already agree. The item 32 re-grab keeps the refreshing placement through the carry,
  so it needs no L1. The designer's centred look is offered to the user as an option (§9 Q3).
- **C9, item 27's option.** `refresher(…, fallbackLayer:)` (refresh §5.3) trades blend fidelity for rotations; under the
  parity-without-appeal ruling it is not built. The behind slot fixes the instant resize and D66's 20-frame delay after a
  rotation; the rotation-start residual (15-16, custom headerless indicator, 4-7 frames) needs a layer that does not isolate
  blends, which only route P provides (i29 §5.5): blocked on D77, recorded with the evidence of refresh §5.1 and i29 §3.
- **C10, refresh before D75.** D75's shape is a separate animatable attribute that the catch pin does not touch (a
  content-size animation runs through a catch, as UIKit's content size changes do); `HeaderLiftBase` takes the pinned `TV`
  (else a catch during an inset animation opens a `Δslack · a` seam).
- **C11, D71 (DBG-s12, not here).** Not cherry-picked (it edits `ContentTransform` and `AxisGeometry` on a branch that merges
  on its own). The lift and the shape call the very slack function `ContentTransform.resolved` uses, term for term, so both
  sides follow D71 when it merges. Until then a hold narrows the slack for content and header alike: s9 / s10 judge the
  header-content seam and the indicator in hold rows, not the content's own `hold · a` motion (D71's). Merge note §6.
- **C12, numbering:** §1.
- **C13, `.headerFollows` + `.stretch` + `.keepTextMagnified`.** The header grows by `L` at rest, so it is magnified at rest.
  Its text blur belongs to M8b-s9 (reviewers do not report `.keepTextMagnified` blur in this batch); M8b-s9's crisp path
  gates on `g_s > 0` (`g + L > 0`) and covers `0 < m < 1`.
- **C14, s6 before s7.** Between s6 and s7 the 15 path (forced) draws both cases as D69 (`m` treated as 0 there). Internal
  state between commits of one batch, stated in s6's commit message, removed in s7.
- **C15, the D76 evaluation.** Its evaluators could not write report files; `M8b-s8-d76-magnified.md` is assembled from
  their notes. The lead may replace it with their full structured reports.
- **C16, the slot height (i15b §11).** s5 adds a hosted test `|slot.H − committed container| ≤ 0.5` at rest in both
  orientations: s9's lift reconstructs the viewport as `slot + dv`, and the two definitions must not diverge.
- **C17, no spike flags in production.** The refresh spike's `SpikeFlags` are not ported. DEBUG-only events (catch, rebase,
  pin start / end per key, slot, box) go through `ZTronRenderCounters`, so the lab and the tests read them; `NSLog` only in
  scratch builds.
- **C18, `HeaderMeasuringPass`.** s5: `stale` re-arms only while `metrics.header == nil` (i15b §4). s7: the width guard for a
  Dynamic Type change during a pull with `g_l > 0` (i28 §4.8), dropped if the D78 box already covers Dynamic Type.
- **C19, seam-lab additions per step.** s1 `rtrig<T>` (+ `hdef<n>` if missing); s2 `rows<n>`, `rowsto<m>`, `internal`,
  `plain`, test `rows`; s3 `hreset<s>`, `catchcheck.py`; s4 `instant`, `clearrow`; s6 `text`, `hh<pt>`, `long`,
  `extra<list>`, `ksize`, `switch<d>` and the i28 tools; s8 `acenter`, `abottom`, `ftop`, `ffollows`, `fpinned`, start
  `bottom`, test `fitting`; s9 `zoomable`, test `pinch`. Each from the matching spike patch in `s8-spikes/`.
- **C20, the stall first.** s2 comes before s3 / s8: its suspects include `TransformHost` / `ContentTransform`, so the pin and
  the shape land on the fixed structure, and `ContentAnimationTickTests` then guards every later step. A later D77′ (G, a
  `compositingGroup()` above the transform) must pass it too (d75 §11: a group beneath an animated effect stalled it).

## 4. Blocked: i29 / D77 (needs the user)

Evidence (i29 §0, §3, §4; convincing, so no build step): the 15-16 content group (`compositingGroup()`) has
`allowsGroupOpacity` and `allowsGroupBlending` on; 17+'s `geometryGroup()` has both off. Every public 15-16 boundary that keeps
the rows' layers (needed for a rigid rotation; every other modifier culls, lateral 397 pt) is a flattening group, and every one
isolates blends. A group holding header and content (G) fixes item 29 (0 failing frames, seams as today) but fades header and
content as ONE image: under an ancestor `.opacity(0.5)` G draws (0, 128, 127) where 17+ and today's 15-16 draw (64, 128, 63),
a new 15-16 difference. Route P (a 0 × 0 `UIViewRepresentable` probe clearing both flags on each 15-16 group) equals 17+ in
every probe pixel at no per-frame cost, but needs UIKit, a `Representable` and one PRIVATE `CALayer` key set by KVC (App
Review 2.5.1 risk for every linking app). D77′ = G + the public `allowsGroupOpacity` only: item 29 and the fades as 17+, the
S10 blends-behind differences stay. If the user accepts P or D77′, build it after this batch per i29 §8 (with C20's tick test),
then group the custom headerless indicator (i29 §5.5) to close item 27's rotation-start residual.

## 5. Step briefs

Every step: edit → `scripts/build.sh` → the touched unit suites (27.0, then 17.5) → commit; measure before (the commit before
the step's first) and after on the three lanes (27.0 preferred, 17.5, 27.0 forced); demo UI suites of the touched areas;
re-run the key scenario (§2) of every earlier step on its lane at the end. Thresholds: |seam| ≤ 1 pt, lateral ≤ 1 pt, no
60 Hz step ≥ 0.5 of the change, refresh indicator 0 frames over the content (translucent counts). S4 counters unchanged
unless the brief says otherwise.

### s1-refresh-31-32: the carried spinner look and the trigger handover (slide-in look kept)
Read: refresh §3 (3.1-3.4), §4, §6 steps 1, 2, 5, §7 (rows 31, 32, `.default`); this plan C8 (wins over L1).
Change:
1. `Refresh/RefreshEngine.swift`: the carry exactly as refresh §3.2 (`carried: RetractLook?`; `sample` ~l.174 and the lift's
   fire path ~l.201 no longer emit `.retract(nil)` for a `.spinner` retraction; it ends at fire, at the lift
   (`retractAfterPull` retracts with the carried look), at cancel, at a pull ending at or below 0, in the rest guard).
2. `RefreshIndicatorMath.placement` / `holdsPlacement` (`Refresh/RefreshIndicators.swift`): L2, L3 and the C8 handover
   `center = min(s, L) − L/2 + max(0, L·dragPosition − p)/2` for the band's non-refreshing `.system` look. NOT L1.
3. Programmatic begin during a `.pull` retraction (refresh §4 / step 5): the switch from the pull look to the refreshing look
   follows the look's own `modeAnimated` cross-fade (0.15 s) for the opacity and, in the band `.system` below `L`, the centre:
   an animatable look weight `w` in `RefreshPlacementEffect`, exactly 0 / 1 outside that switch (every other path bit-identical).
4. Lab: demo `-ZTronSeamRefreshTrigger <T>`, extra `rtrig<T>` (port from `s8-spikes/refresh-27-31-32-33/spike.patch`, no spike
   flags); `hdef<n>` (built-in `.default` indicator, hold offset n, like `hsys<n>`) if the lab lacks one.
Tests: `RefreshEngineTests` (re-grab → lift / fire / push back / cancel; `.pull` retraction re-grab unchanged),
`RefreshRetractTests`, `RefreshHoldTests`, `RefreshIndicatorTests` (T 30 / 40 / 50 band `.system`: no centre or opacity step at
the trigger, `min(s, L)/2` from it on; overlay T 40; `T ≥ L` bit-identical to HEAD for s ∈ {5, 20, 40, 60, 90}, both styles,
band, overlay and gap; carried re-grab at s 10 / 20 / 30 / 45: 0 pt, opacity 1; `.default` band end H 20 / 30 / 45: no opacity
step; the begin weight: monotone, no step ≥ 0.5); demo `RefreshUITests` in full on 3 lanes (plus a begin during a retraction).
Acceptance (3 lanes; `spinner.py`, `analyze.py`):
- Item 31: `aspect-rest-stretch-pull-refresh-rtrig40` and `-rtrig30`: no centre step against the band at the trigger
  (|Δcentre − Δpredicted| ≤ 1 pt every frame, predicted from the drawn band by the formula), centre = band/2 ± 1 pt from the
  trigger on, opacity 1 at the trigger with no step ≥ 0.5 of its change, 0 over, no vanish / jumps (HEAD: 27.0 10 → 26.7 pt,
  17.5 10.3 pt).
- Item 32: `aspect-rest-stretch-fling-hold-hsys60-hend1p5` (re-grab of the clock retraction): no vanish, no jump, spinner 20 pt
  through the re-grab, 0 over. (The re-grab during a SwiftUI reset needs s3.)
- `.default` band end (`…-hold-hdef<n>-hend1p5`): no opacity step.
- No regression: `aspect-rest-stretch-pull-refresh` (default T ≥ L) spinner frames equal to HEAD within 0.1 pt; the M8b-s6/s7
  refresh rows (docs/progress/M8b-s7.md).
Docs: Orchestration items 31, 32 fixed (per-lane numbers); SPEC S10 band look sentence if it describes T < L.

### s2-content-anim-stall: open item 34, SwiftUI animations inside the content stop after one frame
Read: d75 §2.3, §6 R1, §8 row 0, §10 item 7; this plan C3, C20.
Defect (d75 spike, unmodified chain, 27.0 + 17.5, preferred + forced): in a hosted rig a `withAnimation(.easeInOut(duration:
0.5))` row change (5 → 10) inside a `ZTronScrollView` evaluates an `Animatable` modifier in the content (`uval`) and an effect
on the growing rows' frame (`uframe`) twice, never again; the drawing lands in one frame at the next render. Pure SwiftUI in
the same rig: 30-31 evaluations. Ruled out: `FrameClockDriver`, `ContentLayerGroup`, `ScrollContentLayout` (15 path too),
`CompletionObserver`'s `.transaction`, the library's whole reaction to the size change. Everything ticks while
`ContentTransform` itself animates.
Work:
1. New hosted `ContentAnimationTickTests` (port the `D75SpikeTests` sampler from `s8-spikes/d75-short-content/spike.patch`):
   a plain row change, `uval` / `uframe` evaluations over 0.5 s; without a header, with one (`.compress`, `.slideBehind`), and
   an `Animatable` inside the header builder.
2. Bisect, one DEBUG flag per suspect: `TransformHost` / `ContentTransform` (the idle animatable effect above the content, its
   `state.probe`), `ContentInteractionGate`, `NamedSpaceModifier`s, `HeaderContentReserve`, `ContentOverlayHost`,
   `ContentSizeMeasure`'s measurement, `MeasurementIsolation`, `ViewportObserver`, the overlays, `PanGestureAdapter`,
   `.clipped()` / `.contentShape`, the container's `.transaction` hook. Table per suspect and lane in notes.md.
3. Fix with no API change, keeping `positionDriver.animationInTurn` and `state.probe` semantics, S4 and the 15-path
   structure; D81 only if the fix is a structural decision.
4. Lab: demo `-ZTronSeamRows n`, `-ZTronSeamRowsTo m` (seam.width toggles the count in `withAnimation`),
   `-ZTronSeamRowsInternal 1`, `-ZTronSeamRowsPlain 1`; `testRows` in `SeamLabUITests`, `rows` in `scripts/seam/measure.sh`;
   extras `rows<n>`, `rowsto<m>`, `internal`, `plain`.
Tests: `ContentAnimationTickTests`, `TransformTests`, `LayoutHostTests`, `ContentOverlayTests`, `ParentReevaluationTests`,
`CounterTests`, `HeaderStateTests`; demo `ProofUITests`, `SeamLabUITests` (3 lanes).
Acceptance (3 lanes): `uval` and `uframe` ≥ 20 evaluations in 0.5 s for the plain row change, without and with a header (both
collapse modes), and the header-content animation ≥ 20; S4 counters unchanged; app proof: `fixed-rest-preserve-rows-rows5-
rowsto10` and `-internal` (and `-noheader`): the rows' own animation drawn on ≥ 20 frames in 0.5 s, no step ≥ 0.5 (rig = app).
No regression: `aspect-rest-preserve-width`, `aspect-rest-preserve-rotate` on one lane. If no fix after the bisect: blocked with
the table; item 34 stays open with that evidence (no SPEC known limit).
Docs: Orchestration open item 34 (fixed with numbers, or open with evidence).

### s3-refresh-33-catch: catch where it is drawn (D79), the 17.5 header residual, item 32 during a reset
Read: refresh §1, §2 (2.1-2.4), §4, §6 step 3, §7 (rows 33, 33 + 32, 33 header, 33 log), §8 (17.x pin and app animations,
header pin, rebase), §10; this plan C2, C3, C17.
Change (refresh §2.1 + §2.3):
- `ZTronScrollState`: `noteSwiftUIDrawnMotion()` / `drawnAway()`; `interrupt()` (~l.1440) adopts the drawn offset / zoom when no
  motion or token runs; the window closes in `beginIntervention`, `cancelMotion`, `scroll(to:)` and at convergence.
- `PanCoordinator`: both environments (~l.164, ~l.392) count a drawn-away state as moving without a finger; the rebase after a
  catch in the same call (~l.253).
- `RefreshCoordinator`: `noteSwiftUIDrawnMotion()` before the two D39 `withAnimation` (~l.281, ~l.411).
- `CatchPin` in `Render/CatchPin.swift` (lock-protected like the probe). `ContentTransform` draws the stored model copy while
  pinned and ends the pin within 0.01 pt / 1e-5 (C3: minimal hunk); `RefreshPlacementEffect` pins `pull` the same way.
- Header (C2): `HeaderLiveInput.catchPin` + `pinned(_:)` set in `HeaderFrameModifier.wake()`; SIX effects read
  `live.pinned(key)`, one latch each, `HeaderFadeOverlay` included; no pin → `self` bit-identical (D62 untouched).
- C17: no spike flags; DEBUG events (catch, rebase, pin per key) via `ZTronRenderCounters`.
- Lab: demo `-ZTronSeamHoldReset <s>`, extra `hreset<s>`; `catchcheck.py` into `scripts/seam/` (from `s8-spikes/refresh-…`).
Tests: new `DrawnCatchTests` (window opens / closes; `drawnAway` nil while tracking, with a motion or token, an open resize, a
size or zoom mismatch, within 0.5 pt; adoption), `PanSessionTests` + `CatchArmingTests` (synthesized touch + recognition with a
drawn catch: the first `.setOffset` is the caught presentation; a clock catch unchanged; a tap at rest with
`transform.clampedAtRest` is no catch), `TransformTests` (pinned `effectValue`, convergence ends it), `HeaderMathTests`
(`pinned(_:)` re-derives at the model `o′`, per-key convergence, no pin = self), `HeaderLayoutFrameTests`,
`HeaderFadeHostedTests`, `RefreshIndicatorTests`, `RefreshEngineTests`; demo `RefreshUITests`, `HeaderUITests`, `PanUITests`,
`NestedPagerUITests`, `UIKitObserverUITests` (3 lanes; catch semantics feed arbitration).
Acceptance (3 lanes; `catchcheck.py`, `spinner.py`, `analyze.py`):
- `aspect-rest-preserve-fling-hold-hsys60-hend1p5-hreset4-fdown`: the band's drop over the 4 frames before the catch ≤ the
  reset's own motion + 1 pt; overFrames 0, jumps [], vanish [] (HEAD: 20.7 / 22.7 pt on 17.5, 25.3 pt on 27.0).
- `aspect-rest-stretch-fling-hold-hsys60-hend1p5-hreset4-fdown`: as above; spinner 20 pt on every frame of the catch; its step
  against the content within 1 pt of −(band step)/2.
- Header: that stretch row and `aspect-rest-preserve-follow-fling-hold-hsys60-hend1p5-hreset4-fdown`: |seam| ≤ 1 pt on every
  frame from the catch to the next rest (HEAD 17.5: 29.5 pt for 2.2 s); `opengap` rows with `--open-gap` (gapExcess ≤ 1 pt).
- DEBUG events: the content's first drawn offset after the catch within 0.5 pt of the caught one; 27.0 / forced: no pin past
  the first evaluation.
- Risk (17.5): an app inset animation 0.1 s after a catch (hosted or lab): no step ≥ 0.5; if one shows, fix it first.
- Counters: content bodies 0 across a catch; `transformHost.body` per frame unchanged. No regression: s1's key scenario.
Docs: Orchestration D79 (incl. "every offset-animatable effect reads the pin"), item 33 fixed incl. the 17.5 header residual;
SPEC S9 / S10 catch paragraph.

### s4-refresh-27-behind: the ungrouped headerless gap indicator behind the content (D80)
Read: refresh §5.1, §5.2, §5.4, §6 step 4, §7 (rows 27), §8 (item 27, hoisted holder), §10; this plan C9, §4.
Change (refresh §5.2): when `!state.usesGeometryGroup`, a `.background(RefreshOverlay(…, layer: .behind)
.ignoresSafeArea(.all, edges:))` slot after the transform host (`ZTronScrollView.swift` ~l.153); `RefreshHolder` hoisted to
`ScrollContainer` (`@StateObject`, passed to both slots; the front slot keeps `onAppear` wiring, `cancelAll`, accessibility,
haptics; the behind host lays out leaves only and never reads `pan.refresh`); `RefreshLayerMath.draws(layer:kind:overlay:)`
(pure) from the latched kind; D66 deleted (`RefreshResizeReveal`, its `reveal` input, the `boxes` gate). 17+ preferred builds
today's tree. C9: no `fallbackLayer:`.
Lab: demo `-ZTronSeamInstant 1` (extra `instant`), `-ZTronSeamClearFirstRow 1` (extra `clearrow`; `holdgap.py` counts the probe
seen through the clear row as over).
Tests: new `RefreshLayerMathTests` (every kind × overlay × layer; the latch while boxes exist), `RefreshIndicatorLayerTests`,
`RefreshResizeEffectTests`, `RefreshIndicatorBodyTests`, `RefreshHoldTests`; demo `RefreshUITests` in full on 3 lanes (blend
sections: yellow over the gap's blue behind, magenta over the content in front; VoiceOver tree; haptic serial; begin / end).
Acceptance (`holdgap.py`):
- Forced `fixed-rest-preserve-width-noheader-hold-height04-instant`: missing 0, over 0, tintOver 0, ghost 0 (HEAD: 27 missing).
- Forced `fixed-rest-preserve-rotate-noheader-hold`, `fixed-rest-preserve-rotatel-noheader-hold-horizontal-hleading`: over 0,
  tintOver 0, ghost 0, no missing frame after a rotation's end (HEAD: 20); the rotation-start residual ≤ the spike's (top 7;
  leading 4 + 5, 3 off), recorded as item 27's residual, blocked on D77.
- Forced `…-height04-instant-hoverlay`, `…-rotate-noheader-hold-hoverlay` (`--overlay`): drawn in every judged frame, largest
  step ≤ 0.5 of the travel.
- Forced, the instant and rotate rows with `clearrow`: 0 frames seen through; if not 0, numbers in the handoff (D77-tied).
- 27.0 preferred and 17.5: the same rows unchanged from HEAD. Counters: content bodies 0 across a rotation and an instant
  resize; leaf evaluations per frame ≤ 2 per edge on the ungrouped path. No regression: s3's key scenario.
Docs: Orchestration D80 (D66 superseded), item 27 fixed for instant resizes and the post-rotation delay, the start residual
open and blocked on D77; SPEC S10 D66 paragraph → D80.

### s5-i15b-d78: the 15-16 header resolves from its own slot (D78, item 15 (b))
Read: i15b §0, §1, §2 (2.1-2.4), §4, §5, §6, §7, §9, §11; this plan C7, C16, C18.
Change: i15b §4 / §6 steps 1-4: `HeaderMath.overflowLimit` (pure refactor); `HeaderSlotReader` (cold `GeometryReader` around
the 15-path leaf, DEBUG `header.slot`), `HeaderFrameModifier.slot`, `HeaderFallbackFrame.slot` / `reporter`,
`HeaderFallbackPlan(live, slot:)` slot branch for non-`.fit` sizes; the `.fit` ideal-ratio box (both fits;
`HeaderMath.isCommittedViewport` shared with `layoutResting`; `noteBox`; the report as 16+); `HeaderMeasuringPass` `stale` only
while `metrics.header == nil`; the `HeaderHost` one-line swap. C7: no `noteBox` skip while pulled, no adopt-at-release. C16:
the slot-height test. Keep s3's pin reads through the restructure.
Tests: new `HeaderFallbackSlotTests` (both OS paths: capped height change, S-RS-2 width there and back, `.fit` width in the band
uncapped / `.capped(0.25)` × q 0.5 / 1, `.fit` content change in the band, S4 motion counters, root-hosted window resize, C16),
`HeaderReviewD16Tests` (forced `withKnownIssue` removed), `HeaderLayoutFrameTests` (plan tests), `HeaderFitTests`,
`HeaderMathTests`, `HeaderSlideBehindTests`, `HeaderStretchScaleTests`, `HeaderResizeTests`, `HeaderHeightResizeTests`,
`HeaderSafeAreaInsetTests`, `HeaderKeyboardTests`, `HeaderPullBehaviorTests`, `ScalingHeaderHostedTests`, a launch test (the
header in the first frame); demo `HeaderUITests`, `ResizeUITests` (3 lanes).
Acceptance: i15b §7. Forced: the overflow / width rows (`aspect-half-preserve-width-capped25`, `…-capped25-slide1`,
`aspect-rest-preserve-width-capped-height04`, `aspect-half-preserve-width-capped-height04`,
`aspect-rest-preserve-width-refit-height025`, `fixed-rest-preserve-width-capped-height04`,
`aspect-rest-preserve-width-capped-height04-vland`), the `.fit` rows (`fit-half-preserve-width`, `fit-rest-preserve-width`,
`fit-half-preserve-width-capped25`, `fit-half-preserve-width-slide1`, `fit-half-preserve-width-vretarget`,
`fit-half-preserve-rotate-sticky`, `fit-half-preserve-width-grow`, `fit-rest-preserve-width-grow`,
`fit-half-preserve-scroll-band`) and the controls: PASS (HEAD: seams up to 45.2 pt, step 1.00). 27.0 preferred: the same
rows, no regression. 17.5 preferred and forced: the six rows of i15b §7. Counters: scroll / collapse / pull `header.slot` 0 and
`header.builder` 0; resize `header.slot` ≥ 1 on forced, 0 on 16+; `content.body` 0. No regression: s3's key scenario on forced,
s4's key scenario.
Docs: SPEC S10 (~618, 771-783, 991-996); Orchestration D78, item 15 (b) fixed with the table, 15 (c) open (i15b §1.4).

### s6-d76-api-16: `stretchContent:` on the 16+ path, and the i28 seam-lab port
Read: i28 §0, §1.3, §2.4, §3, §4.1-4.7, §4.9-4.12, §5 steps 1-3 (+ the lab part of step 5), §6, §7, §8; this plan C1, C2,
C13, C14, C19, §7.
User ruling D76 (binding): an enum parameter of `withScalingHeader`, default `.keepTextMagnified` = D69 bit for bit, the other
case the grow; doc comments for both; a runtime change is seamless; the crisp path attaches later at `HeaderStretchEffect`
(`g_s`) without an API change; no UIKit / introspection / reflection; `.keepTextMagnified` blur is not a finding in this batch.
Change (i28 §5 steps 1-3): `HeaderMath.grownSize` / `stretchClip` / `grownSidePad`; `public enum ZTronHeaderStretchContent {
keepTextMagnified, keepTextSize }` with the i28 §4.1 docs (names pending §9 Q5); `stretchContent:` after `overflow:` (C1); the
deprecated overload forwards the default; `HeaderSpec.stretchContent` render-only; `HeaderLiveInput.layoutShare` (`m`, set in
`wake()` through a `let` helper); five effects to `AnimatablePair(o′, m)` with the pin on `o′` only (C2); the path-aware clip;
the fade's `R = layoutHeight − g_l`; `HeaderSlotLayout`'s proposal `grownSize(W, h, g_l)`. C14: on the 15 path both cases draw
as D69 until s7 (say so in the commit message).
Lab (C19, from `s8-spikes/i28-stretch-blur/` and `m8b-s8-resume/`): demo `-ZTronSeamStretchContent magnified|size`,
`-ZTronSeamStretchSwitch <delay>,<duration>`, `-ZTronSeamHoldHeight`, `-ZTronSeamHoldProbe 0`, `-ZTronSeamTextLong`,
`-ZTronSeamHeaderExtra field,toggle,spinner`; extras `text`, `hh<pt>`, `long`, `extra<list>`, `ksize`, `switch<d>`;
`scripts/seam/` `edges.py` (threshold mode), `shot.sh`, `textbox.py`, `mixseq.sh`, `mixan.py`, `framediff.py`.
Tests: `HeaderStretchScaleTests` (math; the `.keepTextSize` arms of `aPullIsARenderTimeScaleOfTheRestingLayout`,
`aStretchHoldKeepsTheScaleAcrossAnAnimatedWidthChange`, `aStretchHoldIsBitStableAcrossTheUnanimatedCommit`,
`theUsersAspectFitImageGrowsWithThePull`; new `aMixIsTheSameDrawnFrame`, `anAnimatedSwitchMorphsInsideTheFrame`), new
`theDefaultIsD69BitForBit` (layer frames + drawn rect under a 60 pt hold vs a pre-change reference), `HeaderFadeHostedTests`,
`HeaderLayoutFrameTests`, `HeaderReviewD16Tests`, `HeaderMathTests`, `ScalingHeaderAPITests`; demo `HeaderUITests` (3 lanes).
Acceptance (i28 §6) on 27.0 preferred and 17.5, both cases; forced: both cases equal to HEAD's D69:
- Crispness (lossless PNG, `edges.py`): `.keepTextSize` text held at 60 / 120 pt and an animated 120 pt pull: ratios vs rest
  ≤ 1.10, text box = rest; `.keepTextMagnified` pixel-identical to D69.
- `appbanner` / `refit` held at 60 pt and a finger pull: image rows = D69's ± ⅓ pt in both cases.
- Seam rows per case: `fixed-rest-stretch-pull-text`, `aspect-rest-stretch-rotate-uncapped-hold`, `aspect-rest-stretch-width-
  hold`, `aspect-rest-stretch-pull-refit-appbanner`, `fixed-rest-stretch-rotate-hold-text`, `fit-rest-stretch-rotate-hold-
  text`, `aspect-rest-stretch-pull-fade`, `aspect-rest-stretch-pull-longpull`, an inset view (`-ZTronSeamInset 40`): thresholds,
  and none worse than its D69 baseline by > 0.1 pt.
- Switch: `fixed-rest-stretch-hold-text-switch4` (frame constant, hJ / cJ 0, `textbox.py` monotone, no step ≥ 0.5),
  `…-switch1` (`--held` monotone, max step ≤ 0.05 of the change), `…-switch0` (one frame of the text only).
- Counters: `content.body`, `header.builder`, `header.content` at install value through a hold, an animated and a finger pull;
  an option switch adds exactly 1 to `header.builder`. Platform views (`extra…`): no ⊘ pixels; `.keepTextSize` keeps them sized.
- No regression: s3's key scenario on 17.5 with and without `ksize`.
Docs: SPEC S10 API lines for the parameter; Orchestration D76 "16+ built".

### s7-d76-15-ui: `.keepTextSize` on the 15-16 path (on D78), demo, UI tests, docs
Read: i28 §2.5, §4.8, §5 steps 4-6, §6, §7, §9; i15b §2.2, §11; this plan C7, C14, C18.
Change: i28 §4.8 on s5's slot and box: `HeaderFallbackPlan` pulled parameters (non-`.fit`: min = max height `h + g_l`,
`sidePad = grownSidePad`, applied as `.padding(.horizontal, −sidePad)` outside the chain; `.fit` while pulled: §4.8's table,
report `box.height / s_l`, continuity at `g_l → 0`); C18 width guard; remove C14's stopgap. Demo: a `stretchContent` picker on
the header demo screen; `scripts/seam/rulerx.py` (new: per-frame x of the ruler marks).
Tests: the fallback arms of s6's tests; new `aFitHeaderPulledMeasuresAtTheSlotWidth` (`.fallback`; reported R = natural height
at W while held; four regimes via `.capped` and `min`), `aFitContentChangeDuringAHoldIsMeasuredInLayout`;
`HeaderSlideBehindTests`, `HeaderFallbackSlotTests`, `HeaderStretchScaleTests`, `HeaderFadeHostedTests`,
`HeaderLayoutFrameTests`, `HeaderReviewD16Tests`; demo `HeaderUITests`: `testAppBannerPullGrowsTheImage` (both cases), new
`testKeepTextSizeKeepsHeaderTextCrisp` (lossless PNG held at 60 pt, edge ratio ≤ 1.10; the seam-lab check if XCUI capture is
lossy), `testStretchContentSwitchKeepsTheFrame`, `testStretchContentSwitchDuringADrag`; `RefreshUITests`, `ProofUITests`
(3 lanes).
Acceptance: i28 §6 in full on all three lanes for both cases (forced included), incl. `fit-rest-stretch-width-hold-grow` (forced
is the gate) and `fixed-rest-stretch-width-hold-text`. No regression: s5's and s3's key scenarios on forced.
Docs (i28 §5 step 6): SPEC S10 (D69 → D76: two cases, the mix, the switch; API lines ~479, 527, 561; the "Header behaviors from
the same live input" bullet); Orchestration D76 as built; item 28: "grow case fixed; `.keepTextMagnified` crisp path in
M8b-s9".

### s8-d75-shape: `fittingContent:`, the published alignment, the content's animatable shape
Read: d75 §0, §1, §2.1, §2.2 items 1-3, §3, §4, §5, §6 (R1, R3, R6), §7, §8 steps 1-3, §9; this plan C1, C3, C10, C19, C20.
Change (d75 §8 steps 1-3): `public enum ZTronHeaderFittingContent { topAligned, headerFollows, headerPinned }` with d75 §7
docs (names pending §9 Q4); `fittingContent: … = .topAligned` after `overflow:`, BEFORE `stretchContent:` (C1); the deprecated
overload forwards `.topAligned`; `HeaderSpec.fitting` / `HeaderSizing.fitting` (a change runs `headerSpecChanged()`);
`contentAlignment` zeroes y for `.topAligned` only; `.headerFollows` draws as `.headerPinned` until s9.
`ScrollMetrics.alignment` (`content`, `liftY`), `alignmentChanged()` in `withAnimationIfAny(positionDriver.animationInTurn)`
from `headerSpecChanged()` and the container hooks; `contentAlignment` becomes an accessor. `ContentShape` +
`ContentShapeShift` in `Render/ContentShape.swift` (own attribute outside `ContentTransform`, whose `animatableData` stays `TV`
and draws `pad` from the committed shape: C3); `setContentSize` writes metrics, commit and the clamped offset in
`withAnimationIfAny(animationInTurn)`; the content `.transaction` hook in `ContentSizeMeasure`. C10: the shape is not pinned.
Lab: demo `-ZTronSeamAlign center|bottom`, `-ZTronSeamFitting top|follows|pinned`, `-ZTronSeamStart bottom`; `testFitting`,
measure.sh `fitting`; extras `acenter`, `abottom`, `ftop`, `ffollows`, `fpinned`, start `bottom`.
Tests: new `HeaderFittingContentTests` (default = D63; `.headerPinned` pad = slack·a; d75 §9.2 for `.topAligned` /
`.headerPinned`: grow / shrink 300 ↔ 600 animated, external and internal, ≥ 20 drawn frames in 0.5 s, max step ≤ 0.25 of the
change, header still; plain = one frame, exact; shrink at the bottom: clamp and pad on one curve; rows inserted during a bounce
and a hold release: no step ≥ 0.5; option change `top → pinned` animated; a catch during a content-size animation),
`HeaderReviewD16Tests`, `DefaultScrollAnchorTests`, `ZoomStateTests`, `ResizeSafeAreaStepTests`, `RefreshIndicatorLayerTests`,
`TransformTests`, `ResizeTests`, `ScalingHeaderAPITests`, `ContentAnimationTickTests`; demo `HeaderUITests`, `SeamLabUITests`.
Acceptance (3 lanes), d75 §9.1 with `ftop` and `fpinned` (base rows 5 → 10, `acenter`, fixed size, compress): `rows` (external,
`internal`, `plain`), rows at the bottom (`fixed-bottom-preserve-rows-rows10-rowsto5-acenter-ftop`: HEAD's 62 pt one-frame
clamp now animated), `fitting` (top → pinned → top), `rotate`, `rotatel`, `width` (+ `height04`, + bottom-pinned): thresholds,
contentBody 0, headerBody 0 but one build per option change. If s2 ended blocked, report the pad-only ≥ 20-frame gates against
open item 34. No regression: s2's and s3's key scenarios; the S7 rotation suites.
Docs: Orchestration D75 "API, alignment, shape built"; SPEC withScalingHeader signature (~498).

### s9-d75-lift: `.headerFollows` (the lift), refresh base + L, keyboard
Read: d75 §2.2 items 4, 6, 7, §6 (R2, R4, R5, R6), §8 steps 4 and 6, §9, §10, §11; refresh §10 (d75 bullet); this plan C4,
C10, C11, C16, §6.
Change (d75 §8 step 4): `ScalingHeader/HeaderLift.swift`: `HeaderLiftBase` (animatable `TV`, s3's pinned `TV`),
`HeaderLiftShift` (animatable `ContentShape`, plain zoom and insets), `HeaderLiftHost` (hot leaf reading `.target`, `.metrics`,
`.phase` like `TransformHost`) on BOTH header slots, no wrapper, no preference; `HeaderMath.lift(…)` pure, `L = a_h · slack`
from the same function `ContentTransform.resolved` uses at `slot + dv` (C11); `refreshTop` / plain base / `obscuredDelta` + L;
`RefreshIndicators` base + L per frame; `ZTronHeaderGeometry` / `ZTronHeaderGeometryReader` report the drawn header. K2
(step 6): measure `kbrotate` with `kbreal` and `kbfake` first; only if a step ≥ 0.5 shows, add `KeyboardInsetFollow`
(`.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)`) as its own green commit. R2: if the bottom-pinned height row
shows a lift error, carry `dv` in `ResizeCommit` and interpolate it with the slot's progress.
Lab: demo `-ZTronSeamZoomable 1` (extra `zoomable`); `testPinch` (XCUI `pinch(withScale: 2, velocity: 1)`), measure.sh `pinch`.
Tests: `HeaderMathTests` (lift), `HeaderFittingContentTests` (`.headerFollows`: seam ≤ 1 pt every drawn frame for grow, shrink,
`top → follows`, `follows ↔ pinned`, pinch; forced "lift at rest = slack·a"; a hold in `.headerFollows`: indicator base = drawn
header bottom ± 0.5 pt, 0 over, `.openGap` and `.followContent`, both collapse modes), `HeaderFallbackSlotTests` (C16),
`RefreshIndicatorTests`, `RefreshIndicatorLayerTests`, `HeaderKeyboardTests`, `ReaderTests`, `ZoomStateTests`,
`DrawnCatchTests` (a catch during an inset animation: no `Δslack·a` seam); demo `HeaderUITests`, `RefreshUITests`,
`ZoomUITests`, `SeamLabUITests` (3 lanes).
Acceptance (3 lanes), d75 §9.1 with `ffollows` (and `fpinned` / `ftop` re-run): rows (external, internal, plain), rows at the
bottom, `fitting` (top → follows → pinned → top), `rotate`, `rotatel`, `width` (+ `height04`, + bottom-pinned: R2), `kbrotate`
(`kbreal`, `kbfake`), `pull` with a refresh hold (`opengap`, `follow`, `hoverlay`), fling / snap / scroll with 10 rows
(unchanged), the extended rows on 27.0 preferred + forced (`slide…` × rows / rotate / pull; fit / capped / refit × rows /
rotate / width; `zoomable` × rotate / rows / pinch): thresholds (follows: header bottom = content top), indicator 0 over,
contentBody 0, headerBody 0 but option changes. Holds (C11): judge the header-content seam and the indicator, not the content's
own `hold · a` motion; list the hold rows to re-run after D71 merges. No regression: s3's key scenario with `ffollows` on 17.5,
s8's key scenarios.
Docs: Orchestration D75 "lift built" (and K2 if shipped).

### s10-d75-stretch: `.stretch` takes L in both D76 cases, demo page, docs
Read: d75 §2.2 item 5, §7, §8 steps 5, 7, 8, §9, §10 item 5; i28 §4.3-4.8, §8 (d75 bullet); this plan C13, §7.
Change (d75 §8 step 5 on D76 as built): in `.headerFollows` `.stretch` grows by `g + L`: `g_l = m·(g + L)`,
`g_s = (1 − m)·(g + L)`; `.keepTextMagnified` scales by `(h + g + L)/h`; `.keepTextSize` uses `grownSize(…, stretch: g + L)`;
`L` evaluated per frame inside `HeaderSlotLayout`'s animatable data (16+) and the 15 path's `Animatable` frame (never
layout-interpolated: 25 pt off at the fit / overflow kink). C13: a code comment at `HeaderStretchEffect` for M8b-s9 (gate on
`g_s > 0`, cover `0 < m < 1`). Demo (d75 step 7): catalog page "Short content" (three cases, Add / Remove rows animated and
plain, a zoomable variant). Docs (d75 step 8): SPEC S10 (D63 → D75, the three pictures; the final signature with both new
parameters), the public doc comments (d75 §7), Orchestration D75 as built.
Tests: `HeaderFittingContentTests` (`.stretch` × both cases: height at rest `h + L`, compression starts after the content moved
up `L`, seam ≤ 1 pt; `.keepTextSize` crisp at rest), `HeaderStretchScaleTests`, `HeaderPullBehaviorTests`,
`HeaderLayoutFrameTests`, `HeaderFallbackSlotTests`; demo `HeaderUITests`, `SeamLabUITests`, `RefreshUITests` (3 lanes). The
full suites run in the Check phase.
Acceptance (3 lanes, both D76 cases): `fixed-rest-stretch-rows-rows5-rowsto10-acenter-ffollows` (+ `ksize`),
`fixed-rest-stretch-pull-acenter-ffollows-rows5`, the same with a refresh hold (`opengap`, `follow`, `hoverlay`),
`fixed-rest-stretch-rotate-acenter-ffollows-rows5`, a switch during a held pull (`switch1`): thresholds, indicator 0 over;
`.keepTextSize` text ratio ≤ 1.10 at rest and pulled; counters. No regression: the key scenarios of s6, s7, s9.

## 6. Merge notes

- **Numbering** (§1): re-check main and `git log --all` before the merge; renumber D75-D81 / items 34-35 if taken.
- **DBG-s12 (`claude/dbg-refresh-reversal`, D71 `7fafb2e` + `1c102c3`).** It edits `ContentTransform.swift` and
  `AxisGeometry.swift`. This batch's `ContentTransform` hunks: s2 (if the fix is there), s3 (pin), s8 (`pad` from the
  committed shape); expect mechanical conflicts. After the merge re-run: s9 / s10's `.headerFollows` hold rows (C11), s3's
  catch rows (the pin copies whatever `TV` holds), d75 §9.2's hold case "(with D71)".
- **SHEET-s4** (pending): s3 changes `PanCoordinator`'s environments and adds a rebase; if SHEET-s4 lands gesture changes,
  re-run `SheetUITests` on 18.x and the whole demo UI suite (gesture-priority memory).
- ScrollArbitration's public API is untouched by every step.

## 7. M8b-s9 (the crisp `.keepTextMagnified`)

The D76 evaluation (`M8b-s8-d76-magnified.md`): no pure-SwiftUI route; the scoped UIKit / Core Animation re-raster prototype
is crisp on three lanes with 0 px at rest, seams within the thresholds and hit testing intact; it needs the user's ruling (S16
exceptions: UIKit, a `UIViewRepresentable`, KVO). Attach point: `HeaderStretchEffect`, i.e. the magnified share `g_s`; it must
cover the animated switch (`0 < m < 1`) and D75's `.headerFollows` + `.stretch` header magnified at rest (`g + L > 0`, C13).

## 8. Real iOS 15.0 / 16.0 (the user's M1 lane)

Per design: refresh §11, i15b §10, i28 §9, d75 §10, i29 §12 (if D77 is accepted). Plus, from this plan: s1's handover with
T < L (`rtrig40`) on 15.0; s2's `ContentAnimationTickTests` on 15.0 / 16.0 (is the stall there before the fix, and gone after);
s3's catch rows (15 / 16 keep or drop a residual like 17.x?); s4's instant / rotate / `clearrow` rows on real 15 (UIKit's
rotation).

## 9. Questions for the user

1. **D77 (item 29; also item 27's 15-16 rotation-start residual).** Route P (UIKit + `UIViewRepresentable` + one PRIVATE
   `CALayer` key set by KVC, only on the 15-16 path; App Review 2.5.1 risk for every linking app), D77′ (the same probe with
   the public `allowsGroupOpacity` only: item 29 and fades as 17+, the S10 blends-behind differences stay), or neither (item 29
   stays blocked with its evidence)?
2. If route P is refused: add `refresher(…, fallbackLayer:)` (`.preservesBlendModes` default / `.layerGroup`) as a stopgap
   for the custom headerless indicator's 15-16 rotations? Plan default: no (it trades one 17+ behaviour for another).
3. Items 31 / 32: the plan keeps today's slide-in `.system` band pull look (unchanged for trigger ≥ indicator height) and
   removes the T < L step with a handover. Do you want the designer's centred band pull look instead, or as an option?
4. D75 names: `fittingContent:` with `.topAligned` (default) / `.headerFollows` / `.headerPinned`, or `shortContent:` /
   `.belowHeader` / `.withHeader` / `.headerAtRest`? Ship `.headerPinned` as a third case (default: yes)?
5. D76 names: `stretchContent:` / `ZTronHeaderStretchContent` with `.keepTextMagnified` (default) / `.keepTextSize` (or
   `.keepTextPointSize`, `.growLayout`, `.relayout`); placed right after `fittingContent:` (as ruled) or after `pull:`?
