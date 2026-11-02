# M8b-s7 handoff · 2026-11-02 · Opus 5.5 workflow builders b1–b5 (header behaviors, D68–D70)

Status: done; not merged into main (the user merges). Branch `claude/cool-stonebraker-0015c9`, base 54f8650.
Remaining: the user's device check of the `appbanner` screen, and decisions on open items 28 and 29 (30 fixed in the fixer
round 1, below).

Design: `docs/design/M8b-header-behaviors.md`. §7 holds each risk's measured result; §8 holds the lead decisions.
Spec: SPEC S10 amended 2026-11-02. The amendment covers collapse modes, the pull scale, the split fade, the mode-switch
`@State` note and the backdrop requirement. Orchestration has D68, D69 and D70.

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

## Design §7 risk checklist (decision 5: each risk measured on 27.0, 17.5 and forced)
1. **Hit-testing through the content to a background header:** none on all three lanes.
   - `testSlideBehindHeaderButtonTapsOnlyWhereUncovered` passes 29/29 per lane.
   - The header button takes a tap only where it is uncovered.
   - The part above the frame takes no touches.
   - A drag on the uncovered header scrolls.
2. **Background slot top on 15 and forced:** none.
   - `HeaderSlideBehindTests` passes on both paths.
   - The ruler reads the top at `top0 − k·c` within 0.44 pt (17.5), 0.34 (27.0) and 0.33 (forced).
   - The worst step is 0.12 of the move.
3. **Clip inside a group during a rotation in a stretch hold:** none.
   - Forced lane: rotate holds give |seam| ≤ 0.5, lateral ≤ 0.25 and jumps ≤ 0.24, the same as preferred.
   - The clip is a `Path(rect)` with no mask layer on either path.
   - The appbanner rotate-hold passes on all three lanes.
   - Real 15/16 devices are unmeasured.
4. **Gradient lag:** none on all three lanes.
   - Opacity error ≤ 0.023.
   - Every step matches the model within 0.01.
   - The bias has the same sign rising and falling, so there is no lag.
   - Pixel UI test error ≤ 0.011.
   - Appbanner fade error 0.017.
5. **`.slideBehind` under a real navigation bar:** none.
   - `testAppBannerSlideBehindStaysBelowTheBar`: the bar's 38 pt band above the scroll view does not change at half or full
     cover on 27.0, 17.5 or forced (diff 0.0).
   - Seam lab: 0 frames of header above the scroll view's top under the 27.0 glass bar (132 frames) and forced (130).
   - On 17.5 the lab's blank title draws no bar: 0 of 178 frames above the safe-area top. The UI test covers 17.5's real bar.
6. **15–16 `.slideBehind` clip and blend isolation:**
   - The clip holds on the forced lane (unit clip test on both paths; 17 seam scenarios PASS).
   - Blend isolation was judged from the code, not measured: open item 29.
7. **Scaled readers and text:** on every lane the pulled header is drawn as its bitmap, scaled.
   - A 24 pt text's edge widens 1.25× (17.5) to 1.8× (27.0) at s = 1.25: open item 28.
   - The image grows exactly (step 6 pixel lines).
8. **Mode switch:** accepted (decision 4).
   - The switch keeps the covered fraction.
   - No content body runs (`aModeSwitchAndABackdropRunNoContentBody`, both paths).

## Open
- **28:** `.stretch` blurs header text while pulled (D69 limit). Proposed: accept and document.
- **29:** on 15–16 a content child's blend mode does not reach a `.slideBehind` header. Judged from the code, not measured.
- **30 (new, pre-existing): FIXED in the fixer round 1** (below). Was: a programmatic hold's opening under `.stretch` drew the indicator over the content.
  - When it happens: the 0 → 60 pt animated inset, with the indicator drawn at its final place in the band from the first frame.
  - Measured: 13–17 frames, up to 40 pt below the header's bottom.
  - The M8b-s6 baseline before D68 shows the same thing.
  - It was hidden by `probe.py`'s default window. Use `--window=-80,40`.
- **Load flake:** the 17.5 full unit run had one failure at load ~400, `HeaderSafeAreaInsetTests.aStalledSamplerJudgesTheDrawnCurve`
  (forced). Re-run alone at load 8 it passed 3/3.
- **Device check by the user** (Orchestration Next step 6): the `appbanner` pull, a refresh hold, rotation in a hold, and
  `.slideBehind` under their bar.

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

## Merge notes (main is ahead; do not merge from here)
- **Release gate:** main has a 250 pt/s release gate (UIKit's release counts moves only, BTN-s2) and BTN open item 11. Re-run
  `HeaderUITests` + `RefreshUITests` after the merge. The appbanner finger pull holds before it releases.
- **iOS 26+ hosting rule:** `HostingViews.track` is absent on this branch. `HeaderStretchScaleTests`, `HeaderSlideBehindTests`
  and `HeaderFadeHostedTests` host `UIHostingController` directly. Wire them through the helper.
- **Open item numbers:** our item 24 is main's 27. Items 28–31 here follow on from it; renumber after main's.
- **D-numbers:** D68–D70 are ours. D71 is DBG-s12's (another branch); D72 and D73 are on main.

## Traps for the next builder
- **The navigation bar needs a title.** 27.0 draws no bar for an empty `NavigationView` title. 17.5 draws none for a U+00A0
  title either, so the 17.5 seam lab has no bar.
- **Reset does not undo a pull.** The demo's Reset (`snapHeader(.expanded)`) leaves a pulled view where it is (S10 Snapping), and
  `setContentOffset` is not clamped: a programmatic pull stays until the next touch. Use `appbanner.rest`.
- **Seam-lab analysis:** count only app frames (`frames.csv` app), because recordings start and end on the home screen.
- **`fade.py --fade single`:** `tfit` is undefined (there is no partner gradient), so read `err` from `--csv`.

Tests:
- `scripts/test.sh` unit, full: 837 tests, 82 suites, 9 known issues (library = c0a3342). 27.0 green; 17.5 green after the one
  load flake above.
- Demo UI (`scripts/test-demo-ui.sh`, machine-wide UI lock): full `HeaderUITests` 16/16 on 27.0 preferred, 27.0 forced and
  17.5, at 9ebc73b. The 27.0 runs were at load 300–560 from other sessions and still passed.
- Seam lab: 6 appbanner scenarios × 3 lanes, plus the 27.0 regression lane: PASS.

Usage: not measured (workflow builders).
