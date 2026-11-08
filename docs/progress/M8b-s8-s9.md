# M8b-s8-s9 handoff · 2026-11-08 · Opus 5.5 · xhigh
Status: done. Builder s9-d75-lift: D75 part 2, the `.headerFollows` lift (9ebe1bd, f7138c0, 49c3d65, 90ce814, 99402c8,
7f57020). The header rides on the top edge of content that fits, on both header slots and the top refresh indicator. K2
shipped, hide only. R2 fixed. `.stretch` growing by `L` at rest is s10.

Defect fixed (before = c56ee93, `.headerFollows` drew as `.headerPinned`): the key 17.5
`fixed-rest-preserve-rows-rows5-rowsto10-acenter-ffollows` rested with a 69.3 pt gap between the header and the content
(79.2 pt on 27.0 and forced). It now rests at seam ≤ 0.333 on 3 lanes and moves together (14 frames, ≤ 0.115 per frame).

Changed:
- `ScalingHeader/HeaderLift.swift` (new):
  - `HeaderLiftBase` (animatable `TransformVector`, catch-pinned `.lift(slot)`) and `HeaderLiftShift` (animatable
    `ContentShape`) evaluate `ContentTransform.resolved` with the lift alignment `(0, liftY)`, the content's padding term
    for term. `HeaderLiftHost` is a hot leaf, S4-safe because `content` is the placeholder. It sits on the header's front
    slot, `.slideBehind`'s background slot and the top refresh indicator. There is no wrapper and no preference.
  - `LiftSpan` / `LiftTrack` (R2): the header slot sits between the safe areas, so the effects rebuild the content's
    viewport from the drawn slot height along the content's resize track (`ResizeCommit.previous` / `current`). A
    safe-area step shifts each track by its own step. `LiftSpan()` is the identity for the viewport-sized refresh slot.
- `HeaderMath.lift`; `obscuredDelta` + L (refresh top, `scrollTo`, resize centre); `ZTronHeaderGeometry.lift` (public, 0
  unless lifting) and the reader report it.
- `ZTronScrollState.applyViewport` inset-only branch:
  - Before, an inset change followed the turn's animation only when R changed. It now also follows when the aligned pad
    of fitting content moves (`alignedPadMoves`): an app-animated `.safeAreaInset` or a keyboard.
  - K2 (`KeyboardInsetFollow`, `Render/ViewportSpaces.swift`): a hiding keyboard with no transaction is written in
    `.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)`.
  - A shown keyboard is left alone: its report lands inside UIKit's keyboard animation block, which Core Animation
    interpolates. With K2 on show too (90ce814), the header ran 43 pt ahead on 27.0 and 70 pt ahead on 17.5 (99402c8).
- Lab (f7138c0): `-ZTronSeamZoomable 1` (extra `zoomable`), `SeamLabUITests.testPinch`, `measure.sh pinch`.
- SPEC S10: `.headerFollows` built, `ZTronHeaderGeometry.lift`, and the viewport bullet on inset changes that move
  aligned fitting content.
- Tests: `HeaderFittingContentTests` (+ lift rows, refresh hold, app-animated `.safeAreaInset`, keyboard show/hide on both
  paths); `HeaderMathTests.liftTrackFollowsTheContentsTrack` (event-log numbers of R2).

Decisions:
- K2 hide only: measured above; Core Animation already carries the shown keyboard.
- R2 via the content's own track rather than the last two commits: the step commit made the pair degenerate (gap 15.8 at
  49c3d65).

Measurements (seam lab, ffollows; seam = content top − header bottom; per-frame step as a fraction of the move):

| row | before c56ee93 | 27.0 pref | 17.5 | 27.0 forced |
|---|---|---|---|---|
| KEY rows5→10 acenter (rest seam) | 79.2 / 69.3 / 79.2 gap | 0.333, 14 fr ≤ 0.101 | 0.333, 14 fr ≤ 0.115 | 0.333, 14 fr ≤ 0.101 |
| rows internal / bottom 10→5 | header still | ≤ 0.165 / 27 fr 0.07 | same | same |
| height04 vbottom (R2) | lift error 15.8 | 0.167 | 0.167 | 0.167 |
| height04 / width (lateral) | — | 0.167 / ≤ 0.282 | same | same |
| rotate / rotatel | — | ≤ 0.167, lat ≤ 0.28, 18–19 fr 0.096 | same | same |
| kbfake (inset-only) | content 75 pt in 1 frame | 0.167, 70 fr 0.027 | 0.167, 57 fr | 0.167, 70 fr |
| kbreal show / hide | 1-frame step | ≤ 0.67, show over ~25 fr / K2 hide | ≤ 0.67, together | ≤ 0.67 |
| fitting top→follows→pinned→top | — | 30 fr 0.059 | same | same |
| pull hold-follow | header still, gap 211 | ≤ 0.333 | ≤ 0.333 | ≤ 0.333 |
| snap | — | 0.167 | 0.167 | 0.167 |

Extended rows (27.0 pref / 27.0 forced; 7f57020, chain-i), all ffollows:
- `.slideBehind` rows 13 fr 0.101 / rotate 20 fr 0.097, seam ≤ 0.2; zoomable rows / rotate the same.
- `.fit`, `.capped(0.25)`, `.refit` rows (13–16 fr ≤ 0.097), rotate (18–22 fr ≤ 0.13), width (69–75 fr ≤ 0.033): seam ≤ 0.51,
  lateral ≤ 0.371; `.fit` width grow 70 fr 0.031.
- Pinch (pixel column, x = 60): forced header and content together (≤ 0.67). Preferred: a 44–49 pt gap during the finger
  zoom, the same with `fpinned` (no lift). It is the top overscroll, drawn as openGap. The forced path scrolls the zoomed
  content up instead, `fpinned` and `ftop` alike. That is a pre-existing pinch difference between the 15–16 and 17+ paths
  (open item 45), not the lift.
- `slide-hold-opengap`: the −30 pt one-frame header step at the hold start (D71 hold·a), as on the plain hold row.

`fpinned` / `ftop` core re-runs (27.0, 17.5) match s8: pinned rows 13–14 fr ≤ 0.115, header still, gap 79.2 / 69.3 by
design; bottom 10→5 clamp 27 fr 0.057 after the scenario's 1-frame scroll-to-bottom setup; `plain` 1 frame (unanimated by
design).

Earlier steps' keys (7f57020):
- s1, 17.5 `rtrig40`: residual 2.0, half 0.67 (s8: 2.0 / 0.67).
- s2, 27.0 `rows5-rowsto10-internal`: 28/28 fr, 0.059, land 452 ms.
- s3, 17.5 `hreset4-fdown`: dip 0.66, seam 0.5, 0 frames over 1.
- s4, forced `noheader-hold-height04-instant`: 36 fr, 0 seam.
- s5, forced `fit-half-preserve-width-grow`: seam 0.5, 0.036.
- s6, 27.0 `pull-text-ksize`: seam 0.167, 0.063 per vsync (s8 read 0.038; a finger pull, its speed differs per run).
- s7, forced `fit-rest-stretch-width-hold-grow-ksize`: seam ≤ 0.5, ≤ 0.078.
- s8, bottom `ftop` clamp: 27 fr 0.057.

Demo UI (HeaderUITests, RefreshUITests, ZoomUITests, SeamLabUITests): 56/56 on 27.0, 17.5 and 27.0 forced. The forced lane
ran at load ~800 from other sessions, and still passed.

Open:
- Re-run after D71 merges: `pull-…-ffollows-hold-opengap` (the −30 pt one-frame header step at the hold start is D71's
  hold·a), `hold-follow`, `hold-hoverlay` on 3 lanes, and the extended `pull-…-ffollows-slide-hold-opengap`.
- Open item 44: `HeaderFallbackSlotTests.aRuntimeOverflowChangeFollowsTheSameSequence` q0.5 fails standalone at f7138c0
  too: an order or timing dependence that predates s9.
- `hoverlay` gap 101.8 and fling `rows10` openGap bounce (gap 50) are the overlay indicator and bounce designs, not lift.
- Open item 45 (new): the pinch on the forced path scrolls the zoomed content up, while 17+ overscrolls 44 pt at the top
  (fpinned / ftop alike, no lift). It needs its own step.
- Intermittent `HeaderFittingContentTests.aTouchDuringAContentSizeAnimationKeepsTheCurve` (`.headerPinned`, no lift):
  7 of 8 iterations pass, and the failing one drew 4 frames in 0.5 s (display-link starvation at load ~20). Stall class.

Next:
1. s10 (`d75-stretch`): `.stretch` grows by `L` at rest.
2. After D71 merges, re-run the hold rows above.
3. Item 43 (15–16 ksize width hold) is unchanged.

Tests: unit, 24 suites (244 tests), `scripts/test.sh` on its own simulators, 27.0 and 17.5. The only failure is open item 44
(q0.5, both paths), plus the intermittent stall above on 27.0 only. HeaderMathTests and HeaderFittingContentTests have
new tests. Demo UI 56/56 × 3 lanes. Seam lab: 3 lanes (chain-g), extended (chain-i), keys and pinch (chain-j).
Usage: n/a (workflow subagent)
