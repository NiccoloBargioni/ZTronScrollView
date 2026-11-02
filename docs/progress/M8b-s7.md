# M8b-s7 handoff · 2026-11-02 · Opus 5.5 workflow: builders b1–b5, two reviewers, two fixer rounds, two re-checks, closer (header behaviors, D68–D70)

Status: **done and closed; not merged into main** (the user merges). Branch `claude/cool-stonebraker-0015c9`, base 54f8650,
commits e35cc02…127e064 plus the closer's docs commit. Main has moved on (ec5179b at closing). Do not merge it from here.
**Needs the user, in this order:**
1. Decisions on open items 32, 31, 28, 29 and 27 (see "Open items").
2. The device check of the `appbanner` screen.
3. The merge (see "Merge notes").

Item 33 needs triage, not a decision.

Design: `docs/design/M8b-header-behaviors.md`. §7 holds each risk's measured result; §8 holds the lead decisions.
Spec: SPEC S10, amended 2026-11-02 by step 6 and by both fixer rounds. The closer corrected the wording on the retraction at the
default `holdOffset` and added item 32's limit. Orchestration has D68, D69 and D70 (final) and open items 27–33.

## Final results

### Build steps
| step | commits | built |
|---|---|---|
| design | e35cc02 | `docs/design/M8b-header-behaviors.md`: D68–D70, §6 build steps, §7 risks, §8 lead decisions |
| 1 API | 859f58b | `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)`, a deprecated `scalingBehavior:` overload, `ZTronHeaderCollapseBehavior`, the `ZTronHeaderFade { rest, collapse, pull }` set |
| 2 math | 58cbe32 | mode-aware `HeaderMath` (`band`, `visibleHeight` = R − c + stretch, `layoutHeight`, `collapseTranslation`, `stretchScale`) and `HeaderFadeMath` (8 cosine-spaced interior stops, not the design's 6). `.compress` is bit-identical. |
| 3 D69 | 9a3ebf5, 3ce5000, ca2a6a9, b7940ab | `.stretch` as a render-time scale (`HeaderStretchEffect` + `HeaderStretchClip`); the stretch is out of the layout height; render counters through a hold; lab `-ZTronSeamHeaderText`; open item 28 |
| 4 D68 | e4f85eb, 81bcc34, f33f0f7 | `.slideBehind`: the background slot; `HeaderSlotLayout` (16+) and `HeaderTranslation` (15 / forced); the backdrop; the clip at the scroll view's frame; `keepProgress` when only the band changes; S7 unit tests; open item 29 |
| 5 D70 | adc93e9, c0a3342, 5cc71bc | the split fade drawn per frame in the header's leaf (`HeaderFadeOverlay`); the pull weight's R is the animated layout height. This fixed a one-frame step from 0.54 to 0.90 during an animated resize. Pixel UI test. |
| 6 appbanner + docs | 5ad0919, 9ebc73b, 9170ca3 | the demo `appbanner` (the user's setup) and 2 UI tests; seam lab `-ZTronSeamAppBanner`, also under a bar; the SPEC S10 amendment; D68–D70; open item 30 |
| fixer round 1 | 2c6bba8, fbdc743, 9ead301, 469f301 | S-RS-1 and item 30 (`RefreshIndicatorMath.inStretchBand`); C-RC-1 and C-RC-3; seam lab `testFling` and `probeover.py`; SPEC S10 for C-RC-2 and S-RS-2 |
| fixer round 2 | e0d2a8b, 05bc64f, 2860977, 127e064 | R1-RC1-1 (`.system` spinner centred in the band, `holdsPlacement`); seam lab `hsys<H>` / `hend<s>` and `spinner.py`; open item 31 |
| closer | the docs commit | item 24 renumbered 27; items 32 and 33; final docs (this file, Orchestration, STATE, parity rows, SPEC S10 wording) |

### Review findings and their fate
| id | severity | finding | fate |
|---|---|---|---|
| S-RS-1 | HIGH | Under `.stretch` the refresh indicator stayed at `top0 + R` (overlay placement) during a hold, so content scrolled during a refresh was drawn under it. Pre-existing since M8b-3 (bd6ee6a). | **Fixed** (2c6bba8, together with item 30). The skeptic did not refute it. Re-check 1, 3 lanes: 0 frames over the content (was 168 / 170 / 275), also under `fdown`, a `withAnimation` scroll, a snap and a rotation from landscape. |
| S-RS-2 | LOW | 15/16 path (forced): an app-animated width change with `.capped(0.25)` lands the header in one frame: 29.3 pt seam, 159.3 pt lateral. Pre-existing; the item 15 (b) / F6 mechanism. `.compress` gives the same numbers. | **Documented, not fixed**: SPEC S10 "Known limit (review d16)" and Orchestration item 15 (b). The fix needs item 15 (b)'s cold slot-level reader. Re-check 1 reproduced the documented numbers. |
| C-RC-1 | LOW | The `withScalingHeader` doc comment pinned the top edge and kept the bottom on the content even under `.slideBehind`. | **Fixed** (fbdc743). |
| C-RC-2 | LOW | SPEC: a `.slideBehind` banner "only changes the z-order", which ignores D15's zoomed vertical pan (c > 0). | **Fixed** in SPEC S10 (469f301). |
| C-RC-3 | LOW | The DEBUG `HeaderMath.warning` did not know the collapse mode (it reported min > max as a fixed header of height min). | **Fixed** (fbdc743) and tested in `HeaderMathTests`. |
| R1-RC1-1 (re-check 1) | LOW | Introduced by S-RS-1: the `.system` spinner was cut or missing when `holdOffset` < 40 (H 30: 10 of 20 pt, H ≤ 20: none). | **Fixed** (e0d2a8b). Re-check 2: host math and seam lab on 3 lanes, 20 pt drawn and centred for H 20 / 25 / 30. |
| RC2-1 (re-check 2) | LOW | Introduced by e0d2a8b: grabbing the content again during the `.system` band retraction steps the spinner by `(L − s)/2` and its opacity from 1 to `s/L` in one frame. Default configuration. | **Open, item 32** (user decision). |
| re-check 2, note 2 | – | 17.5 `.preserve`: after a re-catch the pull-look arrow is drawn over the content during the spring back. Pre-existing. | **Open, item 33** (triage). |
| re-check 2, note 4 | – | SPEC wording: at the default `holdOffset` the end's retraction changed too, not only a hold partly scrolled away. | **Fixed** in SPEC S10 (closer). |

Re-check notes that are not findings:
- A load artefact in the hold's opening: the first step was 0.43–0.73 of the change at load 113–497 and 0.13–0.27 at normal load.
- `ovl` 50–79 in the compress fling rows: the analyzer reads the content's green top row sliding under the header.
- Rotation probe steps and `spinner.py` "over" frames during rotations: the rotation itself. A rotation recording with no indicator gives 74 such frames.
- An `overlay:` refresher under `.stretch` drawn over the content (179 frames): by design, and the path is unchanged.
- The band's `.default` retraction with H < L steps its opacity from 1 to `H/L`. This is pre-existing and was kept on purpose. It is noted under item 31.

### Suites per lane
Unit tests run both OS paths on each simulator, so "forced" applies to the demo UI and the seam lab only.

| suite | code | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|---|
| unit, full (`scripts/test.sh`) | 9170ca3 | 837 / 82 suites, 0 failures, 9 known issues, 0 feedback loops | 837 / 82, 0 failures, 9 known, 0 feedback loops | – |
| demo UI, full (`scripts/test-demo-ui.sh`, SeamLabUITests excluded) | 9170ca3 | 182 run, 5 skipped, **0 failed** | 182 run, 5 skipped, 2 failed, both pre-existing on 17.5 (`PagerUITests.testPagerArbitration`, `PanUITests.testControlsUsable`), **0 new** | 182 run, 24 skipped, **0 failed** |
| unit, full | fixer round 1 (2c6bba8 + fbdc743) | 839 / 82, green, 9 known | 839 / 82, green, 9 known | – |
| demo UI Refresh + Header + Proof | fixer round 1 | 38/38 | 38/38 | 38/38 |
| unit `RefreshIndicatorTests` + `RefreshRetractTests` + `RefreshIndicatorLayerTests` | fixer round 2 (e0d2a8b) | 50 / 3, green (8 known) | 50 / 3, green | – |
| demo UI Refresh + Header + Proof | fixer round 2 | 38/38 | 38/38 | 38/38 |
| seam lab (`scripts/seam`) | steps 3–6, fixers, re-checks | PASS: appbanner 6 scenarios; fixer 1: 10; fixer 2: 11; re-check 1: 11 + 4; re-check 2: 9. The re-grab lane FAILS (item 32). | PASS: 6; 8; 5; 9 + 4; 9. The re-grab lane FAILS (item 32). | PASS: 6; 8; 5; 10 + 4; 9. The re-grab lane FAILS (item 32). |

Notes on the suites:
- The final HEAD (127e064, and the closer's docs commit) has had no full unit or demo UI run. Round 2 changed only
  `Refresh/RefreshIndicators.swift` and lab files, and the suites that cover them ran green.
- Run the full suites after the merge (merge notes).
- One earlier load flake: `HeaderSafeAreaInsetTests.aStalledSamplerJudgesTheDrawnCurve` (forced) failed in a 17.5 run at load
  ~400 (library c0a3342). Run alone at load 8 it passed 3/3, and it passed in the 9170ca3 full runs.
- Logs: `scratchpad/api/suites/logs/{unit27,unit175,ui27p,ui175p,ui27f}.full.log`.

### Design §7 risk checklist per lane (decision 5)
| risk | 27.0 preferred | 17.5 | 27.0 forced (the 15–16 path) | verdict |
|---|---|---|---|---|
| 1 hit-testing through the content to a background header | `testSlideBehindHeaderButtonTapsOnlyWhereUncovered` passes (UI 29/29) | passes | passes | none. A tap lands only where the header is uncovered; the overflow above the frame takes no touches; a drag on the uncovered header scrolls. |
| 2 background slot top on 15 / forced | ruler `top0 − k·c` within 0.34 pt | 0.44 pt | 0.33 pt; `HeaderSlideBehindTests` on both paths | none (worst step 0.12 of the move) |
| 3 clip inside a group during a rotation in a stretch hold | rotate holds \|seam\| ≤ 0.5, lateral ≤ 0.25; appbanner rotate-hold passes | appbanner rotate-hold passes | the same as preferred (jumps ≤ 0.24); `Path(rect)`, no mask layer | none. Real 15/16 devices are unmeasured. |
| 4 gradient lag | opacity error ≤ 0.023, steps equal the model within 0.01; appbanner fade 0.017 | appbanner 0.016 | appbanner 0.017 | none. The bias has the same sign rising and falling. The pixel UI test error is ≤ 0.011. |
| 5 `.slideBehind` under a real navigation bar | UI test band diff 0.0 at half and full cover; lab 0 of 132 frames above the frame under the glass bar | UI test diff 0.0 (the lab draws no bar: 0 of 178) | UI test diff 0.0; lab 0 of 130 | none |
| 6 15–16 `.slideBehind` clip and blend isolation | n/a (17+ `geometryGroup`) | n/a (17+) | the clip holds (unit clip test on both paths, 17 seam scenarios PASS); blend isolation judged from the code only | open item 29 |
| 7 scaled readers and text | a 24 pt text's edge widens 1.64–1.67× at s = 1.25 | 1.25× | 1.76–1.79× | open item 28. The image grows exactly (step 6 pixel lines). |
| 8 mode switch at runtime | covered fraction kept, 0 content body (`aModeSwitchAndABackdropRunNoContentBody`, both OS paths) | the same | the same (forced OS path in the unit test) | accepted (decision 4) |
| S4 | `content.body` 0, `header.builder` 0 through pull, hold, rest, slide, crossfades and resizes | 0 / 0 | 0 / 0 | pass |
| S7 | rotate and rotate-hold PASS; `HeaderResizeTests` keep the covered fraction | PASS | PASS | pass |
| refresh indicator over the content (S-RS-1, after fixer round 1) | 0 frames (was 168) | 0 (was 170) | 0 (was 275) | fixed |
| `.system` spinner in a short `.stretch` hold (R1-RC1-1, after fixer round 2) | 20 pt drawn and centred for H 20 / 25 / 30 | the same | the same | fixed. The re-grab step is item 32. |

### Open items (Orchestration numbers; ours on this branch: 27–33)
- **32 (new, LOW, measured; user decision).** Grabbing the content again during a `.stretch` `.system` spinner's retraction steps
  the spinner by `(L − s)/2` and its opacity from 1 to `s/L` in one frame. This happens with the default configuration.
  - Measured with a 4 s `resetAnimation` in a scratch lab:
    - 27.0: drawn 20 → 0 pt (vanishes for 4 frames).
    - 17.5: a 14.7 pt step against the content.
    - Forced: a 16.7 pt step.
  - 469f301 had no step.
  - Proposed: centre the `.system` pull look in the band. This also removes 31, but it changes the pull look of every `.stretch`
    `.system` refresher.
- **31 (LOW, from the math; non-default; user decision).** A trigger below `indicatorHeight` moves the `.system` spinner by
  `(L − g)/2` at the trigger. Proposed: accept, or apply 32's fix.
- **28 (D69 limit, measured; user decision).** `.stretch` blurs header text while it is pulled or held. Proposed: accept and
  document it, or add an opt-in that re-lays the header out at the pulled height.
- **29 (from the code; user decision).** On 15–16 a content child's blend mode does not reach a `.slideBehind` header. Proposed:
  accept, or measure on the forced lane first.
- **27 (was 24, LOW, not measured; user decision).** On 15–16, D66's reveal also delays an instant resize. Options: accept, or
  reveal at once for single-axis changes after an iPad lane.
- **33 (pre-existing, 17.5 only; triage).** The `.preserve` re-catch draws the pull-look arrow 1.3–10 pt over the content during
  the spring back. Next: reproduce it at 54f8650.
- **30: fixed** in fixer round 1 (S-RS-1).
- **Pending on the user's device** (Orchestration Next step 6 (b)):
  - the `appbanner` pull;
  - a refresh hold, and scrolling during that refresh;
  - rotation in a hold;
  - `.slideBehind` under their bar.

---
Details by step follow.

## Changed (one green step each)
- **Step 1, API** (859f58b):
  - `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)`.
  - The deprecated `scalingBehavior:` overload has no default and forwards to `pull:`. Its `renamed:` leaves out `collapse:`,
    so the fix-it maps the label.
  - New types: `ZTronHeaderCollapseBehavior` (`.compress`, `.slideBehind(parallax:backdrop:)`) and the
    `ZTronHeaderFade { rest, collapse, pull }` set with `Gradient`.
- **Step 2, math** (58cbe32):
  - Mode-aware `HeaderMath`: `band`, `visibleHeight`, `layoutHeight`, `collapseTranslation`, `stretchScale`.
  - `HeaderFadeMath`: weights; one layer for one colour; for two colours an over-operator pair with 8 cosine-spaced
    interior stops (≤ 0.75 % coverage error).
- **Step 3, D69** (9a3ebf5, 3ce5000, ca2a6a9, b7940ab): `.stretch` is now a render-time scale.
  - `HeaderStretchEffect` is a `GeometryEffect` with `s = (h + g)/h`, anchored at the top centre. `HeaderStretchClip` is a
    `W × h·s` `Path(rect)`.
  - The stretch is taken out of `liveHeight`, `stateHeight` and `HeaderFallbackPlan`.
  - `ZTronHeaderGeometry.height` is the drawn height.
- **Step 4, D68** (e4f85eb, 81bcc34, f33f0f7): `.slideBehind`.
  - The container has an always-present `.background(alignment: .top)` slot.
  - Placement: 16+ `HeaderSlotLayout` places the header at `minY + t_g − k·p·h`. On 15 and the forced lane,
    `HeaderTranslation` is a `GeometryEffect`.
  - The backdrop sits at the content root.
  - The inset path keeps the progress when only the band changes.
- **Step 5, D70** (adc93e9, c0a3342, 5cc71bc):
  - `HeaderFadeOverlay` draws the fade per frame in the header's leaf, before the stretch effect. The cold host fade is gone.
  - The pull weight's R is the leaf's animated layout height.
  - The pull rides the live input only when `pull != rest`. `HeaderLiveInput.geometry` strips the pull for layout consumers.
- **Step 6, the user's setup and docs** (5ad0919, 9ebc73b, the docs commit):
  - Demo `-ZTronScreen appbanner` matches the user's setup: `NavigationView` + `GeometryReader` with the "About us" inline
    title, `.aspectRatio(16/9, min: 0)`, `pull: .stretch`, `fade: .linear(to: appBackground)`, `.refit`, and an aspect-fit
    `Image` with `maxWidth: .infinity`.
  - Variants: `-ZTronAppBannerCall deprecated` and `-ZTronAppBannerCollapse compress|slide|slide0|slide1`.
  - UI tests: `testAppBannerPullGrowsTheImage` and `testAppBannerSlideBehindStaysBelowTheBar`.
  - Seam lab `-ZTronSeamAppBanner 1` (baseline extra `appbanner`).
  - SPEC S10, the `.stretch` doc comment, and this file.
- **Lab and demo arguments** added across the steps:
  - Demo: `-ZTronHeaderCollapse`, `-ZTronHeaderBackdrop`, `-ZTronHeaderFade single|split|split2|none`, `-ZTronHeaderPlain 1`.
  - Lab: `-ZTronSeamCollapse compress|slideBehind[:k]`, `-ZTronSeamRuler 1`, `-ZTronSeamFade single|split|split2`,
    `-ZTronSeamPullDrag <pt>`, `-ZTronSeamHeaderText 1`.
  - Baseline extras: `slide`, `slide0`, `slide1`, `ruler`, `fade`, `fade1`, `fade2`, `longpull`, `appbanner`.

## The user's setup (step 6)
Values below are 27.0 preferred; forced is identical. 17.5 gives the same picture at R = 221.06.
- **Rest:** image (0, 116, 402, 226), first row at 342.
- **Finger pull:**
  - smax 100.7.
  - The image's drawn bottom reaches 442.73 = 342 + 100.7.
  - Its drawn width reaches 580.85; W·(R + g)/R = 581.0.
- **Held pull of 60 pt:**
  - Frame (−53.36, 116, 508.73, 286): the top stays put and the image is centred.
  - The first row is at 402.
  - The screenshot's grid lines sit within 0.14 pt of `W/2 + (x − W/2)·s` (17.5: 0.49). The light edge is at 402.00.
- **Deprecated call:** gives the same values.
- **Render counters:** `content.body` 0 and `header.builder` 0 in every phase.
- **Seam lab** (`aspect-…-refit-*-appbanner`, three lanes). Each cell is |seam| / jump:

| scenario | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|
| pull | 0.5 / 0.14 | 0.5 / 0.03 | 0.5 / 0.07 |
| refresh | 0.5 / 0.10 | 0.5 / 0.05 | 0.5 / 0.09 |
| rotate | 0.3 / 0.10 | 0.1 / 0.10 | 0.1 / 0.10 |
| rotate in a hold | 0.5 / 0.13 | 0.5 / 0.20 | 0.5 / 0.18 |
| fade | 0.0 / 0.17 | 0.0 / 0.25 (0.09 per vsync) | 0.0 / 0.09 |
| slideBehind scroll | 0.5 / 0.07 | 0.5 / 0.07 | 0.3 / 0.07 |

  - **Rotate in a hold:** on 27.0 the header-height jump reads 1.08 (forced 1.10). That figure is a normalisation artefact. The
    height goes 286 → 352 → 304 during the rotation's own excursion, a net 18 pt. The largest step is 19 pt, smooth. Its bottom
    edge's jump is 0.12.
  - **Fade err:** 0.017, 0.016 and 0.017 on the three lanes (codec level).
  - **Landscape lateral (33–103 pt):** this is the aspect-fit image's own letterbox inside the full-width `.refit` frame. It is
    the user's content, not an edge misalignment.
  - **Regression lane** (27.0; the earlier steps' key scenarios plus the fade): equal to b4's baselines.

## Fixer round 1 (2026-11-02, after the correctness and seamless reviews)
HEAD before: 9170ca3. Commits: 2c6bba8 (S-RS-1), fbdc743 (C-RC-1, C-RC-3), 9ead301 (seam lab fling), then the docs commit.
Notes: `scratchpad/api/fixer1/` (runners, recordings `seam/f27`, `f175`, `f27f`, analyses `an-*.txt`, `opening.txt`).

- **S-RS-1 (HIGH, pre-existing since M8b-3) and open item 30: fixed** (`Refresh/RefreshIndicators.swift`).
  - Cause: `HeaderMath.refreshTop` forces overlay placement under `.stretch`, and the overlay sat at `[top0 + R, + L]` while
    refreshing whatever the pull. A hold the content was scrolled out of drew it over the content; a programmatic opening drew it
    at its final place while the content slid down under it.
  - Fix: `RefreshIndicatorMath.inStretchBand` (top edge, vertical `.stretch`, a refresher with a hold; an `overlay:` refresher,
    which has no hold, keeps floating over the content) → `placement(band: true)`. The overlay's look, drawn only over the band:
    centre `min(s, L) − L/2`, opacity as the overlay (`p/L`, 1 refreshing), clip `[0, max(0, s)]`. Box `(s − max(s, L, H), s)`
    and region `(0, max(s, along))` are the gap's (item 19), and the resize box follows the content's drawn edge
    (`.box(overlay: false)`). Unchanged: the retraction's `refreshing` (the overlay's), `RefreshBaseFollow` (overlay rule),
    `baseFollowsInset` (true), `refreshTop`.
  - Same frames and drawn part as before under a pull and at the hold's rest (`H ≥ L`). An over-pull past the hold (the
    fling back's bounce) leaves the indicator at the band's top, as a pull does (up to 17 pt above its rest place against the
    header's bottom, not over the content).
  - Tests: `RefreshIndicatorTests.aStretchHoldScrolledAwayIsNeverDrawnOverTheContent` (both collapse modes, both looks, a
    developer inset, `.preserve` control) and `theStretchBandKeepsTheOverlaysLookAndClipsToTheBand`.
- **Seam lab** (new `testFling`, `measure.sh … fling`, extras `fdown` / `fv` / `fb` / `fd` / `slidek<k>`; `probeover.py`: probe
  frames over the content, app frames only). Probe over the content, frames (before = the seamless review, 9170ca3):

| scenario | 27.0 | 17.5 | forced | before 27.0 / 17.5 / forced |
|---|---|---|---|---|
| `aspect-rest-stretch-fling-hold` (compress) | 0 | 0 | 0 | 168 / 170 / 275 |
| `…-fling-hold-slide1` | 0 | 0 | 0 | 169 / 168 / 168 |
| `fixed-rest-stretch-fling-hold-slidek0p25` | 0 | – | – | 168 / – / – |
| `…-fling-refit-hold-appbanner` | 0 | 0 | 0 | 169 / – / – |
| `fixed-rest-preserve-fling-hold` (control) | 0 | – | – | 0 |
| rotate-uncapped-hold, appbanner rotate-hold slide, width-hold, height 0.4, pull-refresh | 0 | 0 | 0 | (opening, item 30) |

  - Hold opening (`probe.py --window=-80,40`, frames before the stimulus): the probe stays 20.3–20.8 pt inside the band on every
    `.stretch` hold scenario and lane, 0 frames below the header's bottom (before, 27.0: 9–11 frames, up to 37 pt).
  - Width-hold / height 0.4 probe deviation 0.67 / 0.33 pt (27.0), 0.50 / 0.17 (17.5), 0.67 / 0.33 (forced); before 58 pt on 27.0
    (the opening).
  - Seam (`table.py`) unchanged against the earlier lanes: gap ≤ 0.5 everywhere; rotate-hold 0.5 / lat 0.1 / hJ 0.25 on all three;
    appbanner rotate-hold lat 34 (letterbox) / hJ 1.08–1.09 (normalisation, as before); width-hold lat ≤ 0.4, hJ ≤ 0.08; forced
    compress fling-hold hJ = cJ 2.46 (the reviewer's run: 2.46; header and content step together). No motion gaps inside a
    stimulus (`fu/gaps3.py`). Loads: 27.0 lane 4–234 (first scenario at 234, its result matches the others), 17.5 4–110, forced 3–90.
- **C-RC-1 (LOW): fixed.** The `withScalingHeader` doc comment states the `.slideBehind` exceptions (top edge moves up with the
  parallax; the content's top edge ends the uncovered part) and the `.stretch` indicator going up with a scrolled hold.
- **C-RC-2 (LOW): fixed in SPEC S10.** Banners under `.slideBehind`: D15's zoomed vertical pan covers them (`c > 0`).
- **C-RC-3 (LOW): fixed.** `HeaderMath.warning(…, collapse:)`: under `.slideBehind`, `.fixed(min:max:)` with `min > max` notes a
  header of height `max` (`min` is ignored), not a fixed header of height `min` (`HeaderMathTests`).
- **S-RS-2 (LOW, pre-existing): recorded, not fixed.** The 15/16 path's width change with `.capped(0.25)` lands the header's width and
  height in one frame (29.3 pt seam, 159.3 pt lateral). Item 15 (b) / F6 mechanism; numbers added to SPEC S10 ("Known limit
  (review d16)") and Orchestration item 15 (b). Its fix is item 15 (b)'s cold slot-level reader.
- Tests: unit full 839 tests / 82 suites green on 27.0 and 17.5 (9 known issues). Demo UI Refresh + Header + Proof (`scripts/test-demo-ui.sh`, machine-wide UI lock): 38/38 on 27.0
  preferred, 17.5 and 27.0 forced (Header 16, Refresh 16, Proof 6).

## Fixer round 2 (2026-11-02, after the re-check of round 1)
HEAD before: 469f301. Commits: e0d2a8b (R1-RC1-1), 05bc64f + 2860977 (seam lab `hsys` / `hend`, `spinner.py`), then the docs
commit. Notes: `scratchpad/api/fixer2/` (runners, recordings `seam/s27`, `s27b`, `s175`, `s27f`, host check `math/`).

- **R1-RC1-1 (LOW, introduced by S-RS-1): fixed** (`Refresh/RefreshIndicators.swift`).
  - Cause: the band placement kept the indicator on the band's far end while refreshing (`[s − L, s]`), so the built-in
    `.system` spinner (20 pt, centred in `L`) was cut at the band's start when `holdOffset` H < `L/2 + 10` (40 at L 60):
    H 30 drew 10 of its 20 pt, H ≤ 20 nothing, for the whole refresh. The `.preserve` gap centres it.
  - Fix: while refreshing, a `.system` spinner in the band is centred, `min(s, L)/2` (the gap's place up to `L`, `[0, L]`
    beyond, as before). Scrolled away it follows the gap's rule: on with the content's edge until it sits `H − rest` before it,
    then rigid, at its rest place in the box (a rotation interpolates it there). The leaf's `refreshing` is now
    `RefreshIndicatorMath.holdsPlacement`: it also keeps the `.system` band's placement through the spinner's retraction, so
    the refresh's end moves nothing (the centre would have jumped `(L − H)/2`) and no longer drops the opacity to `H/L` in one
    frame. Unchanged: the pull's look, `.default`, `overlay:` refreshers, the gap.
  - At the default H = L 60 the rest is the same pixels; a hold partly scrolled away (0 < s < 60) now draws the spinner
    centred in the band instead of on its far end, and the end's retraction keeps it centred and opaque instead of on the
    far end fading `s/L` (the gap's `.system` retraction).
  - Host check (`fixer2/math`, HEAD vs fix): rest drawn 20 pt for H 20–100 (before 0 / 5 / 10 at H 20 / 25 / 30); scrolled
    away: largest step 1.5 × the content's, 0 pt over the content, rigid tail at the rest's place for H 20–100; end: 0 centre
    / opacity step (before: opacity 0.33–0.67 for H 20–40); pull look identical (0 pt).
  - Residual: a non-default `triggerDistance` below `indicatorHeight` moves the spinner `(L − g)/2` at the trigger (open item
    31, from the math).
  - Tests: `RefreshIndicatorTests.aShortStretchHoldCentresTheSystemSpinnerInTheBand` (H 10–100: centred, whole, the gap's
    frame for H ≤ L, no step and rigid when scrolled away, the retraction kept, `holdsPlacement` table, no move at a trigger
    ≥ L); `aStretchHoldScrolledAwayIsNeverDrawnOverTheContent` and `theStretchBandKeepsTheOverlaysLookAndClipsToTheBand`
    follow the centred `.system` spinner (`.default` still rigid / on the far end).
- **Seam lab:** `hsys<H>` (`-ZTronSeamHoldSystem`: the built-in `.system` indicator, L 60, `holdOffset` H, instead of the
  white probe), `hend<s>` (`-ZTronSeamHoldEnd`: `endRefreshing` `s` seconds after the hold began; the hold's action never
  runs, because `beginRefreshing` runs none), `scripts/seam/spinner.py` (the gray spinner against reference columns: drawn
  height and place at the rest, frames over the content, one-frame jumps, vanishings; it reproduces recheck1's pre-fix
  0 / 10 pt). Spinner at the hold's rest (drawn pt / centre in the band):

| scenario | 27.0 | 17.5 | forced | before (27.0, recheck1) |
|---|---|---|---|---|
| `aspect-rest-stretch-fling-hold-hsys20` | 20 / 10.0 | 20 / 9.3 | 20 / 10.0 | 0 / – |
| `…-hsys30` | 20 / 15.3 | 20 / 15.3 | 20 / 15.3 | 10 / 5.0 |
| `…-hsys60-hend1p5` | 20 / 30.0 | 20 / 29.3 | 20 / 30.0 | 20 / 30 (math: unchanged at H = L) |
| `aspect-rest-preserve-fling-hold-hsys30-hend1p5` (control) | 20 / 15.3 | 20 / 14.7 | 20 / 15.3 | 20 / 15.3 |

  - Every recording (27.0: 11, 17.5: 5, forced: 5, incl. `hsys20-slide1`, `hsys30-hend1p5`, `hsys20-hend1p5`): 0 frames over
    the content, 0 one-frame jumps (> 4 pt + 1.5 × the content's move), 0 vanishings. The end's retraction (`hend1p5`): the
    spinner stays centred and whole down to a 20 pt band, then `min(20, band)`, gone with the band (27.0: 30 → 0 in 0.28 s).
  - Seams (`table.py`) as recheck1: `.stretch` gap ≤ 0.5, hJ / cJ ≤ 0.32 (fling rows), ovl 70–79 = the compress fling
    analyzer artefact; `.preserve` control gap 30 = the hold's open gap. Loads ≤ 97.
- **Tests:** unit `RefreshIndicatorTests` + `RefreshRetractTests` + `RefreshIndicatorLayerTests` 50 tests / 3 suites green on
  27.0 and 17.5 (8 known issues: the headerless layer test's). Demo UI Refresh + Header + Proof (machine-wide UI lock): 38/38
  on 27.0 preferred, 17.5 and 27.0 forced (loads 2–17).

## Re-checks (2026-11-02)
- **Re-check 1** (after fixer round 1, HEAD 469f301; own simulators; notes and recordings in `scratchpad/api/recheck1/`).
  - S-RS-1 and item 30 confirmed fixed on 3 lanes (above). C-RC-1, C-RC-2 and C-RC-3 confirmed.
  - S-RS-2 reproduces at the documented numbers.
  - New: R1-RC1-1. It was measured with host math compiled from both revisions and a screen check (`recheck1/px/hs-strip.png`).
    It was fixed in round 2.
  - No regression against the bar: seam gap ≤ 0.5 pt, lateral ≤ 0.3 pt, the probe glued to the header's bottom within 0.67 pt.
- **Re-check 2** (after fixer round 2, HEAD 127e064; own simulators; `scratchpad/api/recheck2/`).
  - R1-RC1-1 confirmed fixed by host math and on 3 lanes × 9 scenarios.
  - New: RC2-1 (item 32). It was measured with three re-grab lanes (`seam/g27`, `g175`, `g27f`) from a scratch copy of HEAD
    (`recheck2/src`, lab `-ZTronSeamHoldReset <s>` / extra `hreset<s>`, which stays outside the repo).
  - Pre-existing on 17.5: item 33 (`recheck2/px/pres175.png`).
  - The diff has no S4, iOS 15 or S7 issue.

## Merge notes (the user merges; main is ahead: 71c9380 at INTEG-s1, ec5179b at closing; do not merge main here)
- **Release gate:** main has a 250 pt/s gate on the release velocity over the last 50 ms. It comes from BTN-s3 (P1 + P2, D49
  rev 2); the header snap is a natural release.
  - Main's `HeaderStateTests` were re-derived in fde9b5d: a release at 150 pt/s from 60 now rests on expanded. Take main's
    version, then re-check this branch's `HeaderStateTests` additions against the gate.
  - After the merge, re-run `HeaderStateTests`, `HeaderUITests` and `RefreshUITests`. The appbanner finger pull holds before it
    releases.
- **BTN open item 11:** main's item 11 is BTN's. This branch has no item 11, so reconcile the open-items list by taking main's
  1–11 and 24–26 and this branch's 15–21 and 27–33.
- **iOS 26+ hosting rule (INTEG-s1, D52 extension):** main hosts views with `UIHostingController(rootView: AnyView(view))` and
  then `HostingViews.track(window)` (`Tests/ZTronScrollViewTests/Support/Unhost.swift`). This branch's `Unhost.swift` has no
  `HostingViews`.
  - `HeaderStretchScaleTests`, `HeaderSlideBehindTests` and `HeaderFadeHostedTests` host `UIHostingController` directly. Wire
    them through the helper.
  - The fixer rounds' tests are pure math and host nothing.
- **Open item numbers:** our item 24 is now 27 on this branch, which is the number main reserves for it.
  - Our 28–33 were free on main and in `git log --all` at closing. Main's next free number is 28, because INTEG-s1 knew only 27.
  - If main has used 28 or later by the merge, renumber ours after main's. Then update the references: SPEC S10 cites 28–32,
    design §7 cites 28 and 29, the parity rows cite 28, 29, 31 and 32, and Orchestration Next step 6 and the D68–D70 rows cite
    27–33.
- **D-numbers:** D68–D70 are ours. D71 is DBG-s12's (another branch). D72, D73 and D74 are main's (D74: SHEET-s3 refused). The
  next free number is D75.
- **After the merge:** run the full unit suite and the full demo UI on 27.0 preferred, 17.5 and 27.0 forced. The final HEAD has
  had only targeted runs since fixer round 1.

## Traps for the next builder
- **The navigation bar needs a title.** 27.0 draws no bar for an empty `NavigationView` title. 17.5 draws none for a U+00A0
  title either, so the 17.5 seam lab has no bar.
- **Reset does not undo a pull.** The demo's Reset (`snapHeader(.expanded)`) leaves a pulled view where it is (S10 Snapping), and
  `setContentOffset` is not clamped: a programmatic pull stays until the next touch. Use `appbanner.rest`.
- **Seam-lab analysis:** count only app frames (`frames.csv` app), because recordings start and end on the home screen.
- **`fade.py --fade single`:** `tfit` is undefined (there is no partner gradient), so read `err` from `--csv`.

Usage: not measured (workflow subagents).
