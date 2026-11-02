# M8b-s7 handoff · 2026-11-02 · Opus 5.5 workflow builders b1–b5 (header behaviors, D68–D70)

Status: done; not merged into main (the user merges). Branch `claude/cool-stonebraker-0015c9`, base 54f8650.
Remaining: the user's device check of the `appbanner` screen, and decisions on open items 28, 29 and 30.

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
- **30 (new, pre-existing):** a programmatic hold's opening under `.stretch` draws the indicator over the content.
  - When it happens: the 0 → 60 pt animated inset, with the indicator drawn at its final place in the band from the first frame.
  - Measured: 13–17 frames, up to 40 pt below the header's bottom.
  - The M8b-s6 baseline before D68 shows the same thing.
  - It was hidden by `probe.py`'s default window. Use `--window=-80,40`.
- **Load flake:** the 17.5 full unit run had one failure at load ~400, `HeaderSafeAreaInsetTests.aStalledSamplerJudgesTheDrawnCurve`
  (forced). Re-run alone at load 8 it passed 3/3.
- **Device check by the user** (Orchestration Next step 6): the `appbanner` pull, a refresh hold, rotation in a hold, and
  `.slideBehind` under their bar.

## Merge notes (main is ahead; do not merge from here)
- **Release gate:** main has a 250 pt/s release gate (UIKit's release counts moves only, BTN-s2) and BTN open item 11. Re-run
  `HeaderUITests` + `RefreshUITests` after the merge. The appbanner finger pull holds before it releases.
- **iOS 26+ hosting rule:** `HostingViews.track` is absent on this branch. `HeaderStretchScaleTests`, `HeaderSlideBehindTests`
  and `HeaderFadeHostedTests` host `UIHostingController` directly. Wire them through the helper.
- **Open item numbers:** our item 24 is main's 27. Items 28–30 here follow on from it; renumber after main's.
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
