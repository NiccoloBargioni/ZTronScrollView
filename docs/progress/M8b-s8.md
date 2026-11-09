# M8b-s8 fixer r2 handoff · 2026-11-09 · Opus 5.5 · xhigh
Status: done for this round's findings. R1-RC1-1, -2, -3 and -4 (= open item 47) are fixed and re-measured. Items 43, 44,
45, 46 and 48 are unchanged (not in this round).

Changed:
- 5a10e38, R1-RC1-1 / -2 / -3: a resize's reflow moves the content shape's plain base (`ScrollMetrics.shapeBase`,
  `metrics.shapeModel`), never the shape effects' animatable data. On 27.0 the unanimated `cs open` write cancelled a D75
  shape animation in flight (0.72–0.90 of the change in one frame at the resize open, the whole change on the back leg);
  `TurnOrigin.shapeAnimated` keeps a turn's animated content-size change in the shape effects, so a resize opened later in
  the turn starts its track from the committed content size (the C-F2 double count: +145 pt, 1.2 of the change, hosted
  17.5 / 27.0; R1-RC1-3's 12.2 pt reversal and 50 ms hold on hosted 27.0 are gone with it).
  Files: Render/ContentShape.swift, Render/ContentTransform.swift (one line), ScalingHeader/HeaderFrameModifier.swift,
  ScalingHeader/HeaderLift.swift, State/ScrollStateTypes.swift, State/ZTronScrollState.swift.
- b1a4a13: seam lab extra `rtw<s>` (`-ZTronSeamRowsThenWidth <s>`): with `rowsto`, the width also toggles, animated,
  `<s>` s into the rows animation (the re-check's scratch knob, now in the demo and `scripts/seam/baseline.sh`).
- a3f190c, R1-RC1-4 / open item 47: `HeaderStretchLiftShift`'s lift memo strips the layout animation with
  `.animation(nil, value: memo.jumps)` (only in the update that stepped the lift) instead of a `.transaction` closure, and
  counts no step while a resize is open or in the update that closes it. SwiftUI kept the closure of the carrier's last
  evaluation and ran it on later transactions that reached the stack, so a lift step before an app-animated narrowing drew
  the `.stretch` `.headerFollows` stack at its final width from the first frame (lab 155–159 pt lateral, intermittent on
  every lane; hosted 161 pt).
- Tests: `HeaderFittingContentTests.aResizeOpenedDuringARowsAnimationKeepsItsCurve` (HeaderFittingResizeTests.swift;
  3 turn cases × 2 paths × 2 fittings), `aStretchingFollowingHeaderNarrowsAfterALiftStep` (old code fails on 17.5 and 27.0);
  `aStretchingFollowingHeaderNarrowsWithTheContent` no longer has a known issue.
- Docs: Orchestration item 47 fixed, item 46 note, session log. SPEC unchanged (behaviour as specified; these were defects).

Decisions:
- The reflow is a plain input (`base`) of `ContentShapeShift`, not a write of its animatable data: on 27.0 an unanimated
  write of an Animatable's data cancels its animation; 17.5 composes it additively, which is why only 17.5 passed before.
- The lift memo is keyed by a step counter (`.animation(nil, value:)`, iOS 15+), so it can only act in the update whose
  key changed; a `.transaction` closure is retained by SwiftUI beyond the evaluation that installed it.

Measured (seam lab, PASS = |seam| ≤ 1, lateral ≤ 1, no step ≥ 0.5 of the change):
- R1-RC1-1, `fixed-rest-preserve-rows-rows5-rowsto10-acenter-ffollows-rtw0p15`: step 0.269 of the change on
  27.0 (a3f190c; 0.269 at 5a10e38), forced 0.101 (a3f190c; 0.101–0.125 at 5a10e38), 17.5 0.115–0.163 (5a10e38; a3f190c
  does not touch this path). Were 0.72 then 1.0 (back leg) on 27.0 and 0.65 / 1.0 forced. The largest steps cross the
  3 frames the analyzer cannot classify while the inserted rows fade (present in the plain rows scenario too; 21–27 pt
  over 4 frames, the curve's own speed).
- R1-RC1-4, at a3f190c: `fixed-rest-stretch-width-acenter-ffollows-rows5` lateral 0.335 / 0.376 / 0.367 (27.0, 3 runs),
  forced 0.375, 17.5 0.284; `-ksize` 0.666 (27.0 × 2); `-ksize-text` 0.666 (27.0), 0.269 (forced), 0.667 (17.5);
  `fixed-rest-stretch-rows-rows5-rowsto10-acenter-ffollows-rtw0p15` lateral 0.377 (27.0), 0.377 (forced), 0.284 (17.5)
  (were 155–159 on every lane).
- Hosted (R1-RC1-2 / -3): every turn case 0.071–0.072 of the change per frame on 17.5 and 27.0, no reversal, seam ≤ 1.

Open:
- Item 46 (`.stretch` `.headerFollows` rotation) is unchanged by the memo fix: 27.0 lateral 348, 17.5 seam 69 / lateral 341.
- Items 43, 44, 45, 48: unchanged.

15/16 checks (real devices):
- R1-RC1-1: rows that change animated while the app animates a width change keep centred content on the rows' curve; no
  step at the width change's start, none on the way back.
- R1-RC1-4: an app-animated width change of a `.stretch` `.headerFollows` header: its sides stay on the content's from the
  first frame (also right after an unanimated rows change).

Next:
1. Item 46: the span-based lift for the chain (Orchestration item 46), re-measure the 6 rotate scenarios on 3 lanes.
2. Item 48 (17.5 keyboard over centred fitting content).
3. Items 43 and 45.

Tests:
- Touched unit set (14 suite names, 113 tests in 12 suites) at a3f190c: 27.0 green, 17.5 green (0 known issues).
- Resize set (ResizeMath/ResizeState/HeaderResize/ResizeCommitLayout/HeaderHeightResize/ResizeExtrapolation/
  ResizeSafeAreaStep, 47 tests in 7 suites): 27.0 and 17.5 green.
- Demo UI HeaderUITests + ResizeUITests at a3f190c: 32/32 on 27.0 preferred, 27.0 forced and 17.5 (load ≤ 150).
- Seam lab at a3f190c: lanes fx2e-27 / fx2e-27f (load ≤ 175) plus fx2d (27.0 × 2, 17.5) from the interrupted attempt.
Usage: not measured.

# M8b-s8 fixer r1 handoff · 2026-11-09 · Opus 5.5 · xhigh
Status: partial. C-F1, C-F2, C-F3 and C-F4 are fixed. S-REV-S8-1 (open item 47) and S-REV-S8-2 (open item 48) are not fixed.
Items 43 and 46 were not attempted. Item 44 is pre-existing.

Changed:
- 16e484f, C-F1, D79 drawn-motion window:
  - `PresentationBox.restSeen` / `armRest()` in State/ScrollStateTypes.swift.
  - `ContentTransform.restModel` and `CatchPin.tracksRest()`, used in the content effect.
  - `ZTronScrollState`: `noteSwiftUIDrawnMotion` arms the latch, and `drawnAway` closes the window once the drawing is at rest.
- 2da5dc7, C-F3 and C-F4: `HeaderMath.obscuredDelta` for `.stretch` with `L > 0` uses `visibleHeight + translation` at `o′ − L`. The `HeaderLiveInput.lift` doc is updated.
- 65df4f4, C-F2: `ContentShapeShift.delta` keeps `pad(drawn) − pad(committed)` on `ResizeMath.presented` geometry while a resize is open.
- Tests:
  - DrawnCatchTests: 2 new tests.
  - HeaderFittingContentTests: the C-F3 test, plus the narrowing tests for item 47 (headerFollows is a known issue; the topAligned control is not).
  - ContentShapeResizeTests: new suite.
- Docs:
  - SPEC S9 has the C-F1 amendment and S10 has the C-F3 amendment.
  - Orchestration: open items 47 and 48, plus notes on 43, 44 and 46.

Decisions:
- C-F1 closes the window when the content effect draws its own target values (a rest latch), not on a timer. This covers both a steady clamp and an app-animated inset.
- C-F2 corrects only the open-resize path. Closed slow-path frames are unchanged.
- The `ulpStable` resize targets and a 1e-6 lift memo were tried for item 47. Neither changed anything, so both were reverted (patch kept in scratch `fix1/ulpstable.patch`).

Open:
- Item 47 (S-REV-S8-1): the 27.0 lab shows 159 pt lateral. The hosted narrowing test fails on 27.0 and 17.5, on the narrow leg only. Bisect plan is in Orchestration.
- Item 48 (S-REV-S8-2): on 17.5, two same-turn bottom-inset writes (34→370→336) give a +17 pt wrong-way step.
- Item 44: pre-existing (fails at ee0eaed).
- Items 43 and 46: unchanged.

15/16 checks (real devices):
- C-F1: a tap after a refresh reset that came to rest is a plain tap, also while an inset animates.
- C-F2: rows that change while you rotate keep centred content on its curve, with no step at the rotation start.
- C-F3: the scroll indicator's top follows the drawn bottom of a stretching `.headerFollows` header past the band.

Next:
1. Item 47: in the hosted test, force each `L > 0`-only piece (scale `s`, the y −L placement, carrier re-evaluation) to its `L = 0` value until the narrowing passes.
2. Item 48: log both inset writes' transactions on 17.5, then fix and re-measure kbreal-info.
3. Items 46 and 43, with item 47's finding.

Tests:
- Touched unit set (11 suites requested, 95 tests in 10 suites):
  - 17.5: green (2 known issues = item 47).
  - 27.0: 5 frame-count failures at load 285–480. All 5 pass alone at load 46.
- Full 27.0 suite at HEAD: 926 tests, 89 suites, 22 issues in 6 tests at load 200–330.
  - Item 44.
  - Two frame-count tests.
  - Two tests that pass alone.
  - `RefreshRetractTests.aResetThatSwiftUIAnimatesCarriesTheIndicatorWithTheContent`: order-dependent and pre-existing. It fails in the same 4-test set at ee0eaed and passes alone at ee0eaed, 16e484f and HEAD.
- C-F1: DrawnCatchTests 16/16 on 27.0.
- C-F2: ContentShapeResizeTests on 27.0 and 17.5.
- Demo UI (HeaderUITests, RefreshUITests): NOT run. The machine-wide UI lock was held by session UIKITPAN-s4 for over 2 h (30 min wait timed out).
- Seam lab: rec2 (27.0) for the width rows only. Run the 3-lane lab and demo UI before merging.
Usage: not measured.
