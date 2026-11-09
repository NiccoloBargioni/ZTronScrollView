# M8b-s8 closer handoff · 2026-11-09 · Opus 5.5 · xhigh (workflow closer)
Status: partial. The batch is built, reviewed, fixed in two rounds and re-checked twice: D75 and D76 (API + grow case) are built,
D78–D80 are built, D77 is ruled for M8b-s9. Items 15 (b), 27 (instant resize, delay after a rotation), 28 (grow case), 31, 32,
33, 41 and 47 are FIXED with numbers; item 34 is closed with no library change. Still OPEN, all FIX under the user's rule (none
is a limit): 15 (c), 35, 42, 43, 44, 45, 46, 48 and recheck 2's 49–53, plus 54. Do not merge before 46 and 48–52 are fixed and the
full suites have run at that HEAD.
Range: base 09226f4 → fc44000 (70 commits; 26 library files, +2448 / −301) + this closer's docs commit. Branch
`claude/cool-stonebraker-0015c9`, not merged; main is at 9110936 (106 commits ahead of the base).

## Designs (docs/design/)
- `M8b-s8-plan.md`: the plan (10 steps, febf007).
- `M8b-s8-d75-short-content.md`: D75, what a header does with content that fits. Two alignments, a published alignment, a
  separate `ContentShapeShift` attribute, and the lift on both header slots.
- `M8b-s8-i15b-15path-resize.md`: D78. The 15–16 header resolves from a cold slot reader; `.fit` uses an ideal-ratio box.
- `M8b-s8-i28-stretch-blur.md`: D76's grow case. One mechanism: the laid-out share `m`, with the magnified share `g_s` as
  the hook for the crisp path.
- `M8b-s8-i29-blend-slidebehind.md`: item 29. Route P / D77′ are measured; ruled D77 (public route, M8b-s9).
- `M8b-s8-refresh-27-31-32-33.md`: D79 (catch where the reset is drawn), D80 (behind slot), the band handover.
- `M8b-s8-d76-magnified.md`: the crisp `.keepTextMagnified` evaluation (accepted 2026-11-03, built in M8b-s9). This closer
  refreshed it to the side-session copy of 2026-11-09 12:40 (§1–16: gaps §12, cost rounds §13–16). The d76-cost workflow
  was still running at closing, so the side-session copy stays canonical until M8b-s9 commits its final version.

## Plan and build steps (handoff per step: docs/progress/M8b-s8-s<k>.md)
| step | result | commits |
|---|---|---|
| s1 refresh 31 / 32 | green; items 31, 32 and 41 (new) fixed | 61c7e21 … 848759a |
| s2 content-animation stall | green; item 34 closed (the hosted rig's stall, not the app's) | b8b0b71 … 7206175 |
| s3 refresh 33 catch | green; D79, item 33 fixed, item 42 new | c1ec40f … 867884f |
| s4 refresh 27 behind | green; D80, item 27 fixed (instant / delay), D66 retired | 6b00454 … 24f07af |
| s5 item 15 (b) | green; D78 | 432f2fe … d291afc |
| s6 D76 16+ | green | 905177c … fce0e34 |
| s7 D76 15–16 + UI | red at close of step: item 43 new | f4eccdc … 9e23270 |
| s8 D75 shape | green | 2db4012 … c56ee93 |
| s9 D75 lift | green; items 44, 45 new (pre-existing) | 9ebe1bd … ce73fa1 |
| s10 D75 stretch | red: rotation, item 46 | a24ac2c … ee0eaed |
| fixer r1 | C-F1, C-F2, C-F3, C-F4 fixed; items 47 and 48 new | 16e484f … fa4278b |
| fixer r2 | R1-RC1-1 … 4 fixed (item 47) | 5a10e38 … fc44000 |

## D75 API as built (Sources/ZTronScrollView/ScalingHeader/ScalingHeaderAPI.swift:78, HeaderTypes.swift:67 / :91)
`withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:stretchContent:header:)`, defined as follows:
- `fittingContent: ZTronHeaderFittingContent = .topAligned`, with three cases:
  - `.topAligned`: D63, the default.
  - `.headerFollows`: the header rides on the aligned content's top, lifted by `L = slack·a`. A `.stretch` header grows by
    `L` at rest instead.
  - `.headerPinned`: the pre-D63 look. The header stays at rest and the gap opens between the header and the content.
- `stretchContent: ZTronHeaderStretchContent = .keepTextMagnified`, with two cases:
  - `.keepTextMagnified`: D69 bit for bit.
  - `.keepTextSize`: the stack is laid out at the grown size, so text keeps its point size.

Both parameters are defaulted, so the change is source-compatible. The deprecated `scalingBehavior:` overload forwards the
two defaults. There is no `refresher(fallbackLayer:)`: that is the plan default, because D77 makes it moot.

## Review findings and their fate
| id | sev | fate |
|---|---|---|
| C-F1 D79 window never closes after an untouched reset | MED | fixed 16e484f (rest latch); a tap after a reset is no catch, hreset4-fdown still catches (drop −0.66 / 0.66, seam 0.17) |
| C-F2 shape remainder dropped when a resize opens | MED | 65df4f4 was wrong on 27.0 (RC1-1) and doubled on 17.5 (RC1-2); fixed for good in 5a10e38 |
| C-F3 obscuredDelta at o′ not o′ − L | LOW | fixed 2da5dc7 (indicator track was up to 119 pt low) |
| C-F4 lift doc contradicts effectData | LOW | fixed 2da5dc7 |
| S-REV-S8-1 stretch follows header narrows ahead (27.0, 159 pt) | HIGH | item 47, fixed a3f190c (≤ 0.67 pt on every lane) |
| S-REV-S8-2 17.5 keyboard +17 pt wrong-way step | MED | item 48, OPEN (UI lock unavailable to measure a fix) |
| RC1-1 / RC1-2 / RC1-3 (rows animation × resize, centred) | HIGH / HIGH / MED | fixed 5a10e38 (lab 0.269 / 0.101 / 0.115 of the change; hosted 0.071–0.072) |
| RC1-4 stretch follows width lateral 155 pt every lane | MED | = item 47, fixed a3f190c |
| RC2-1 rows at the bottom × resize opening mid-flight | HIGH | item 49, OPEN (pre-existing at fa4278b) |
| RC2-2 `.preserve` header at its final width in that scenario | HIGH | item 50, OPEN (pre-existing) |
| RC2-3 rows starting during an open resize | HIGH | item 51, OPEN (pre-existing) |
| RC2-4 shrink + width in one withAnimation, 62 pt header jump | HIGH | item 52, OPEN (pre-existing) |
| RC2-5 the r2 hosted test red on 27.0 (host stalls) | LOW | item 53, OPEN |

## Per-item before → after (27.0 preferred / 17.5 / 27.0 forced unless named; seam lab unless "hosted")
- **15 (a), D75**: built. Rows 5 ↔ 10, pull, holds (opengap / follow / hoverlay) and switch1 give seam ≤ 0.5, no lateral,
  steps ≤ 0.21. The exception is the hold's +30 pt one-frame content step (C11), which is D71's: re-run after D71 merges.
  Rotation fails: item 46.
- **15 (b), D78** (forced before → after; 27.0 preferred after):
  - S-RS-2 `aspect-half-preserve-width-capped25`: 29.3 / 159.3 / 1.00 → 0.52 / 0.17 / 0.03 (27.0 forced) and
    28.7 / 0.32 / 1.00 → 0.50 / 0.33 / 0.02 (17.5 forced).
  - `fixed-rest-…-capped-height04`: 84.2 → 0.33.
  - `fit-half-preserve-width`: 45.2 / 159.3 → 0.50 / 0.28.
  - Full table: Orchestration item 15.
- **15 (c)**: OPEN. A scroll command during an open resize is drawn with a lateral step: 53.3 pt on 27.0 preferred, 50.0
  on forced.
- **27, D80** (forced):
  - Instant resize: 26 frames missing → 0 (clearrow 29 → 0).
  - Rotations, frames missing after the end, top / leading / trailing / bottom: 10 / 11 / 11 / 10 → 0.
  - 17+ were already at 0.
  - The rotation-start residual is ruled under D77 (M8b-s9).
- **28, D76 grow case**: `.keepTextSize` text edge ratio 1.000 against rest, with the text box at rest, on all 3 lanes. Before,
  at s = 1.25: 1.25× on 17.5 and 1.8× on 27.0 and forced. `.keepTextMagnified` is pixel-identical to D69. Its crisp path is
  M8b-s9.
- **29**: ruled D77 (the public route), built in M8b-s9.
- **31**:
  - `rtrig40` largest centre error: 9.67 / 10.33 / 9.67 → 0.83 / 0.92 / 1.0 pt.
  - `rtrig30`: 10.33 / 10.0 / 10.0 → 1.17 (1.0 on re-run) / 1.0 / 1.0.
  - Opacity rise: 0.60 → 0.31.
  - 0 frames over the content.
- **32**: `regrab-rdur0p2` vanishings 26 / 26 / 30 → 0 / 0 / 0; the `.default` band end's one-frame fall is ≤ 0.16.
- **33, D79** (`.stretch` hreset4-fdown): band fall beyond the reset 0.68 / 0.66 / 2.0 → −0.66 / 0.67 / 0.67; spinner
  12–13.3 / 16–20 / 13.3–17.3 → 20 / 20 / 20 pt.
- **34**: closed, no library change. The stall belongs to the hosted rig; the app draws ≥ 20 frames in 0.5 s.
- **41**: the arrow → spinner cross-fade is now drawn (before: one full-intensity arrow frame, then a swap).
- **47** (stretch follows width): lateral 155–159 → 0.335–0.376 (27.0), 0.375 (forced), 0.284 (17.5).
  - `-ksize-text`: 0.666 / 0.667 / 0.269.
  - `rtw0p15`: 0.377 / 0.284 / 0.377.
- **R1-RC1-1** (centred rows × width, rtw0p15): 0.72, then 1.0 → 0.269 (27.0); 0.65 / 1.0 → 0.101 (forced); 0.115–0.163
  (17.5). Hosted: +144.7 pt (1.20) → 0.071.
- **OPEN, with evidence in Orchestration**:
  - 35: trigger stall 30–77 ms.
  - 42: app-animated inset during a pull is drawn in 1 frame.
  - 43: 15–16 `.keepTextSize` `.fit` hold resize. Ruler 309 → 527 px in one frame.
  - 44: test q0.5.
  - 45: 15–16 pinch of fitting content. 17+ overscroll 44–49 pt.
  - 46: rotation. 27.0 lateral 348; 17.5 seam 69 / lateral 341.
  - 48: 17.5 keyboard, +17 pt.
  - 49: 120.8 pt / 0.85 on 27.0, 115.3 forced, 137.3 on 17.5.
  - 50: 157.6 / 158.5 pt lateral.
  - 51: 0.51–0.57 (hosted).
  - 52: 59–62 pt (hosted).
  - 53, 54: tests.

## Suites per lane
Full runs at ee0eaed (before fixer r1 / r2):
| lane | executed | failures |
|---|---|---|
| unit 27.0 | 918 | 2: item 44, both paths; the RefreshRetract failure was a load flake, 2/2 alone |
| unit 17.5 | 918 | 5 at load ≤ 980: item 44, plus 4 that pass alone |
| demo UI 27.0 preferred | 186 | 0 |
| demo UI 17.5 | 186 | 2, both known: PagerUITests.testPagerArbitration, PanUITests.testControlsUsable |
| demo UI 27.0 forced | 186 | 0 (25 skipped) |

Fixer r1 (HEAD dd84274): touched set 95 tests, green on 17.5 and green alone on 27.0. The full 27.0 suite had 22 issues in 6
tests at load 200–330: items 44 and 54, plus frame-count tests that pass alone.

Fixer r2 (a3f190c), green on 27.0 and 17.5:
- touched set: 113 tests in 12 suites;
- resize set: 47 tests;
- demo HeaderUITests + ResizeUITests: 32/32 on 3 lanes.

Recheck 2 (fc44000): seam lab, 13 scenarios × 3 lanes, PASS in the touched area. `aResizeOpenedDuringARowsAnimationKeepsItsCurve`
is red 5/5 on 27.0 (item 53).

Not run at fc44000: the full unit suite and the full demo UI. Run them before merging.

## Real iOS 15.0 / 16.0 (the user's M1 lane): what to check
The per-step lists are in M8b-s8-s1 … s9.md and in the fixer sections below. In short:
1. **D75**
   - Transaction capture: on 15 the content size arrives by preference, and the content hook must still carry the
     animation (`cs follow`, contentTx = 1).
   - Ticking: ≥ 20 frames in 0.5 s under the 15–16 compositingGroup.
   - Seam: rows / fitting / rotate / pull-hold in `.headerFollows`, seam ≤ 1, steps < 0.5. Overlay frame by frame against 17.5.
   - Keyboard: `kbrotate` with `-ZTronSeamKeyboard 1`, with and without K2.
   - `.stretch` at rest: R + L, crisp.
   - S7 in all 3 cases.
   - R6: rows during a bounce, a hold release and a pinch.
2. **D78**
   - Seam-lab rows S-RS-2, capped / refit / fixed, fit-half width and grow.
   - DEBUG "box W×H q R" gives R = W·9/16.
   - The "slot" event comes before the first animated frame.
   - `header.slot` stays at 0 while scrolling.
   - No dropped frames in a collapse.
   - The `.fit` header is in the first frame at launch.
   - 16.0: no regression.
3. **D76**
   - Lossless PNG at 60 / 120 pt with `.keepTextSize`: stem ratio ≤ 1.10.
   - The flex.swift probe: the ideal query is answered at the ideal width.
   - `fit-rest-stretch-width-hold-grow`.
   - mixseq switches, also during a drag.
   - appbanner refit.
   - Rotate-hold seam ≤ 1.
   - 16.0: no side bleed of the grown subview inside the group.
   - `.keepTextMagnified` pixel-equal to D69.
4. **D79**
   - hreset4 S/P/F: fall ≤ 1, spinner 20, seam ≤ 1.
   - The pins end at their first evaluation.
   - A tap during a reset springs back from where it was caught.
   - On the UIKit-observer path the touch-down is the catch.
   - C-F1: a tap after a finished reset is a plain tap.
5. **D80**
   - The instant row and its clearrow.
   - The 4 rotations: does the real headerless content also land in one frame?
   - The blend UI test.
   - VoiceOver order: a custom indicator's elements now come before the content.
   - The haptic fires once.
6. **Items 31 / 32 / 41**
   - `rtrig40` / `rtrig30`: no centre step, opacity 1 at the trigger.
   - `regrab-rdur0p2`: no vanishing.
   - `hdef30-hend1p5`.
   - Mixed arrow / spinner frames over 0.15 s.
   - `rtrig300-rbegin50-pd80` glides.
7. **Fixer rounds**
   - C-F3: the indicator track follows the stretching header's drawn bottom.
   - R1-RC1-1: rows × width, centred.
   - R1-RC1-4: the header's sides stay on the content's in a width change after an unanimated rows change.
   - `.animation(nil, value:)` overrides an explicit withAnimation for the stretch stack in a hold release.
8. **Open items, to see whether they are OS-specific**: 43, 45, 46, 48, 49–52, 15 (c).
   - The "late landing" artefact (7 of 103 recordings): confirm on a device recording.

## Naming questions for the user (defaults built)
1. D75: `fittingContent:` with `.topAligned` / `.headerFollows` / `.headerPinned` (built), or `shortContent:` with
   `.belowHeader` / `.withHeader` / `.headerAtRest`? Should `.headerPinned` ship as a third case (built: yes)?
2. D76: `stretchContent:` / `ZTronHeaderStretchContent` with `.keepTextSize` (built). The alternatives for `.keepTextSize`
   are `.keepTextPointSize`, `.growLayout` and `.relayout`. The parameter sits after `fittingContent:` as ruled (alternative:
   after `pull:`).
3. Items 31 / 32: should the designer's centred `.system` band pull look become an option? Today's slide-in look is kept.
4. D78's DEBUG counter is named `header.slot`.

## Merge notes (carried from M8b-s7, updated)
- Release gate: main's 250 pt/s release gate (BTN-s3, D49 rev 2). Take main's re-derived `HeaderStateTests`, then re-check
  ours, then re-run HeaderStateTests, HeaderUITests and RefreshUITests.
- Hosting: main's iOS 26+ hosting rule (`HostingViews.track`, INTEG-s1). Wire this branch's hosted suites through it:
  HeaderStretchScaleTests, HeaderSlideBehindTests, HeaderFadeHostedTests, HeaderFittingContentTests (+ the
  HeaderFittingResizeTests extension), HeaderStretchContentTests, HeaderFallbackSlotTests, DrawnCatchTests,
  ContentAnimationTickTests.
- Open-item numbers:
  - Main uses up to 40, including BTN's 11, M9-s1's 36, main's 37–38 and INTEG-s2's 39–40.
  - Ours are 15–21, 27–35 and 41–54. Item 41 was numbered 36 in 170c1d3 / 542f59c and 39 in 8558f70 / d114c6f / 782513b.
  - If main has assigned 41+ by the merge, renumber ours after main's and update the references: SPEC S9 / S10, the parity
    rows, Orchestration Next step 6 and the D75–D80 rows.
- D-numbers:
  - Ours: D68–D70 and D75–D80.
  - Elsewhere: D71 is DBG-s12's; D72–D74, D84, D86 and D88 are main's; D82, D85, D87 and D89–D92 are on other branches.
  - Next free here: D81. Re-check main and `git log --all`.
- D71 overlap: D71 (DBG-s12) touches ContentTransform.swift. Our hunks there are minimal (5a10e38: one line). After D71
  merges, re-run the hold scenarios: pull-…-ffollows-hold-opengap, hold-follow, hold-hoverlay, …-slide-hold-opengap.
- After the merge: run the full unit suite and the full demo UI on 27.0 preferred, 17.5 and 27.0 forced.

## Next
1. Fix batch for items 49–52 together with 46, then 48, 42, 43, 45, 15 (c), 35 and the tests 44 / 53 / 54. Orchestration
   Next step 6 (d) has the order.
2. Full suites on 3 lanes at that HEAD.
3. M8b-s9: D76's crisp path and D77.

Cleanup: no simulator or derived data of this workflow is left. The remaining simulators (fx21-*, s5e/s5v-*, u3*, m82*, i2-*, …)
are other sessions', some of them booted. Seam-lab movies (about 5 GB) are kept under scratchpad s8/s6 … s10 and recheck1 as
evidence.
Usage: not measured.

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
