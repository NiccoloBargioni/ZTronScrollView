# M8b-s8-s8 handoff · 2026-11-08 · Opus 5.5 · xhigh
Status: done. Builder s8-d75-shape: D75 part 1, which is the `fittingContent:` API, the published alignment and the content's animatable shape
(2db4012, eda4455, e03fc97, 4b8178f, b527241). `.headerFollows` draws as `.headerPinned` until s9 (its lift `liftY` is already
published). The defect is fixed on all three lanes. Before this step, a shrink while scrolled to the bottom drew its clamp in one frame (142 / 161 pt).

Changed:
- API (`ScalingHeader/HeaderTypes.swift`, `ScalingHeaderAPI.swift`, `HeaderSpec.swift`):
  - `public enum ZTronHeaderFittingContent { topAligned, headerFollows, headerPinned }` with the design §7 docs.
  - `withScalingHeader(…, overflow:, fittingContent: = .topAligned, stretchContent:, header:)`.
  - The deprecated `scalingBehavior:` overload forwards `.topAligned`.
  - `HeaderSpec.fitting` and `HeaderSizing.fitting`.
- State (`State/ScrollStateTypes.swift`, `State/ZTronScrollState.swift`, `ZTronScrollView.swift`, `HeaderHost.swift`):
  - `ScrollMetrics.alignment` (`ContentAlignment`: `content`, `liftY`) is resolved by `resolvedAlignment()`:
    - `.topAligned` zeroes y.
    - `.headerPinned` keeps the anchor.
    - `.headerFollows` keeps the anchor and publishes `liftY = a.y` on vertical views.
  - `alignmentChanged()` publishes the alignment in the animation of its turn. It is called from the container hooks
    (`onAppear` / anchor change), `headerSpecChanged()` and `resolveZoomLimits()`.
  - `contentAlignment` is now an accessor of the published value.
  - An alignment ticket (`PositionTicket`) under the container's `.transaction` hook lets an option change reach that
    hook.
- Render (`Render/ContentShape.swift` new; `ContentTransform.swift`, `ContentLayoutHost.swift`):
  - `ContentShape` (VectorArithmetic: size, alignment, liftY) and `ContentShapeShift` (GeometryEffect).
  - `ContentShapeShift` draws `pad(drawn shape) − pad(committed)` in a plain frame. It is 0 while a resize is open.
  - `ContentTransform` draws the pad from the committed shape. The shape is a separate attribute, so the finger and
    clock writes of the offset vector never cancel its animation (27.0 R6).
  - `ContentSizeMeasure` carries the content's `.transaction` hook.
- `setContentSize` adopts the animation of its turn (`animationInTurn`; never in a resize's settle window):
  - The keep / clamp offset (`keptOffset`) is resolved before the metrics publish.
  - The metrics follow the animation when the pad moves (plain curve: a catch must not cut the shape, C10). When only
    the offset moves, they go out inside the clamp's own catchable write (e03fc97, b527241).
  - The clamp is written `catchable` (D79). The shape is not pinned by a catch (C10).
- Lab:
  - Demo flags: `-ZTronSeamAlign center|bottom`, `-ZTronSeamFitting top|follows|pinned`,
    `-ZTronSeamFittingTo <cases>` and `-ZTronSeamStart bottom`.
  - `seam.info` gains `cb=` (content.body) and `hb=` (header.builder).
  - `SeamLabUITests.testFitting`, plus a `start` info line in `testRows` / `testFitting`.
  - `measure.sh` gets the `fitting` scenario.
  - `baseline.sh` extras: `acenter`, `abottom`, `ftop`, `ffollows`, `fpinned` and `fto<a+b>`. Without `fto…`, the fitting test
    cycles pinned, top.
- Tests:
  - `HeaderFittingContentTests` (new, 10 tests × path, hosted drawn frames).
  - `ScalingHeaderAPITests`: the default, the deprecated forward and the sizing.
- SPEC: S2 (alignment sentence), S10 "Content that fits" (D75: the three cases, transitions, catch), and the signature.

Decisions:
- No new D-number; this step builds D75 as ruled.
- The metrics follow the clamp (e03fc97, then b527241).
  - The 15–16 header reads metrics and offset in one animatable input. On the forced lane, an unanimated metrics
    publish in the turn of an animated clamp drew the clamp in one frame. The hosted test did not reproduce it; the
    seam lab did.
  - e03fc97 published the metrics with the plain curve beside the catchable clamp. Two animations for that input in one
    turn dropped frames: hosted forced pinned bottom shrink, 6 iterations, 9–24 frames, step up to 0.76.
  - One catchable write for both fixes that but cuts the shape at a catch (C10): the catch of the pinned clamp stepped
    0.86.
  - b527241 settles it:
    - No pad change: the metrics go out in the clamp's catchable write. The shape has nothing to draw there.
    - A pad change: the metrics take the plain curve.
    - Hosted, 6 iterations on both paths: 30 frames, 0.057 / 0.067, and the catch at 0.064.
- The bounce hosted test measures from the drawn pull's peak. On the preferred path the hosted window may draw the
  finger's write only after the release, and that write is a one-frame step of its own.

Measurements:
- Seam lab: base `fixed-*-preserve-rows-…-acenter`, `.fixed`, `.compress`.
- Before = 9e23270 + this lab.
- Recordings are under the scratch `s8d75/rec/{before,after,fix,reg,base}`.
- Steps are per 60 Hz frame, as a fraction of the change. PASS = |seam| ≤ 1, lateral ≤ 1, step < 0.5.

| scenario | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|
| DEFECT `bottom-…-rows10-rowsto5-ftop` (shrink at the bottom, clamp; b527241 re-run) | 142 pt in 1 frame → 26–27 frames, 0.057, seam 0.167 | 161 pt in 1 frame → 27 frames, 0.057, seam 0.167 | 142 pt in 1 frame → 26–27 frames, 0.057, seam 0.167 (1 frame before e03fc97) |
| `bottom-…-fpinned` (clamp + pad) | content 221 pt 27 frames 0.071, header 142 0.057, then pad 79 0.103 | 231 / 161 pt, 0.073 / 0.058 | as 27.0 |
| KEY `rest-…-rows5-rowsto10-acenter-fpinned` (pad 79 / 69 pt) | 14 moving frames (the pad ends where the content stops fitting), 0.103; header 0 moves; rows 28 frames 0.059, land 450 ms | 0.115; rows as 27.0 | 0.103 |
| `…-fpinned-internal` / `-plain` | as external / 1 frame (unanimated, as native) | same | same |
| `…-ftop` (ext / internal / plain) | content top 0 moves, seam 0; rows 28 frames 0.059 | seam 0.167 | seam 0 |
| `fitting` top → pinned → top | 79 pt each way, 30 frames, 0.059, header still | 69 pt, 29 frames, 0.058 | 79 pt, 30 frames, 0.059 |
| `rotate` / `rotatel` (ftop, fpinned) | 18–21 frames, ≤ 0.099, overlap ≤ 0.09, lateral ≤ 0.32 | ≤ 0.099, overlap 0.33, lateral ≤ 0.2 | ≤ 0.099, overlap ≤ 0.15, lateral ≤ 0.31 |
| `width` (ftop, fpinned) | lateral ≤ 0.17 | ≤ 0.33 | ≤ 0.31 |
| `width-height04` fpinned / ftop | pad 79 pt over 28–29 frames 0.065 / no move | 69 pt 0.067 | 0.065 |
| `width-height04-vbottom` (ftop, fpinned) | header 467 pt over 71 frames 0.024, overlap 0.33 | 455 pt 0.025, 0.33 | 0.024, 0.33 |
| counters (`info`) | option change: cb +0, hb +1 each; external rows change: cb +1, hb +1 (the user's change, as s2) | same | same |

- Earlier steps' key scenarios, re-run on this build:
  - s1, 17.5 `rtrig40` (`handover.py`): residual 2.0, half 0.33 / 0.67, ramp 0.34 / 0.20. Base 9e23270 measured today gives
    2.0 / 0.67 / 0.21.
  - s2, 27.0 `rows5-rowsto10-internal`: 28/28 frames, 0.059, landing 448–452 ms (base the same). One earlier run read 27/27
    with a 0.008 last level at 2.2 s; it did not repeat in two re-runs.
  - s3, 17.5 `…hreset4-fdown` (`catchcheck.py`): fall 0.67, seam 0.5, 0 frames over 1.
  - s4, forced `noheader-hold-height04-instant`: 56/56 in place, 0 missing / over.
  - s5, forced `fit-half-preserve-width-grow`: 0.50 / – / 0.036.
  - s6, 27.0 `pull-text-ksize`: seam 0.167, step 0.038. Crispness was not re-shot; header rendering is untouched.
  - s7, forced `fit-rest-stretch-width-hold-grow-ksize`: seam ≤ 0.5, steps ≤ 0.081.
- Hosted (`HeaderFittingContentTests`, 27.0, both paths):
  - Pinned grow / shrink: 21 moving frames, 0.072.
  - Bottom clamp: top 62 pt and pinned 181 pt, 30 frames, ≤ 0.067.
  - Option change: 30 frames, 0.057.
  - Hold release: 0.165–0.28 of an 89 pt pad.
  - Catch of the clamp: held at the drawn offset, 0.064–0.121.
- Loads: the 17.5 runs measured at load > 300 were re-run below 50 (`175r`). The before lane is the low-load re-recording.

Open:
- `ContentAnimationTickTests`: random `rowChangeTicks` cases stall (uval 3–19) on 27.0 at any load.
  - The same class appears at base 9e23270 (b1-27: 12 issues; current 16–17).
  - Pre-existing; not this step's.
- `HeaderFittingContentTests` under host load > 200: stall-class drops, e.g. forced internal grow at 17 frames, or the bounce
  at 12 frames.
  - It is green at u3 (27.0), u8 / u10 (17.5) and u9 (27.0, both paths).
- Seam-lab recordings sometimes show a "late landing": a 0.5–1.3 pt last step drawn only at the next screen update.
  - Seen in 7 of 103 recordings, unrelated rows included (s3's `hreset4`, `width-height04`).
  - The hosted presentation-layer samples land on the rest value inside the animation.
  - Read as a `recordVideo` artifact, not a drawn step. Check it on a device recording (M1 lane).
- Real iOS 15.0 / 16.0 (design §10) is not run: transaction capture by preference (the `cs follow` event on 15.0),
  ticking, seam, R6 (bounce / hold / pinch), keyboard and S7. The forced lane passes all of these on the 27.0 runtime.

Next:
1. s9 (`d75-lift`): `.headerFollows` lifts the header by `liftY · slack` (17.5 key `…-acenter-ffollows`).
2. Real 15.0 / 16.0: run design §10 items 1–8 on the M1 lane.
3. Re-run `ContentAnimationTickTests` on a quiet host. Its flake is pre-existing and needs its own triage.

Tests:
- `scripts/test.sh`, 76 tests in the 10 touched suites, on 27.0 and 17.5.
  - u9 / u13: green except load-class stalls. The tick suite shows them at base too. `HeaderFittingContentTests` shows
    them only above load ~150.
  - u13-175 (b527241): green.
  - u10-175: `HeaderFittingContentTests` 10/10.
- S7 suites: `ResizeTests`, `HeaderResizeTests`, `ResizeExtrapolationTests`, `ResizeRetargetTests` and
  `RefreshResizeEffectTests`, 25 tests, green on 27.0 and 17.5.
- Demo UI:
  - HeaderUITests + SeamLabUITests: 31/31 on 27.0, 17.5 and 27.0 forced (2db4012).
  - ResizeUITests + HeaderUITests + SeamLabUITests: 44/44 on all three lanes (e03fc97).
Usage: not measured by this builder.
