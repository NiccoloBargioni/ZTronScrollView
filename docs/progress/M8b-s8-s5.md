# M8b-s8-s5 handoff · 2026-11-04 · Opus 5.5 · xhigh
Status: done. Builder s5-i15b-d78: open item 15 (b) fixed (D78, 432f2fe…106c216): the 15–16 header resolves from its own
slot, so an app-animated resize lays it out at its final `R(W, H)` in the animated pass and the viewport commit re-sets
nothing. Every acceptance row PASSES on 27.0 forced, 27.0 preferred, 17.5 forced and 17.5 preferred. Item 15 (c) (`combo`)
stays open, queued as a fix (not the header path; evidence below).

Changed:
- `ScalingHeader/HeaderMath.swift`: `overflowLimit(_:containerHeight:)` extracted from `metrics` (432f2fe, pure refactor);
  `isCommittedViewport(width:container:_:)`, shared by 16+'s `layoutResting` and the 15 box's height fit (71cc6d1).
- `ScalingHeader/HeaderFrameModifier.swift`: `HeaderSlotReader` (a cold `GeometryReader` around the 15 path's frame leaf, a
  pass-through on 16+; DEBUG counter `header.slot`, event `slot WxH`, note `header.slot.size`); `HeaderFrameModifier(slot:)`;
  `HeaderFallbackPlan(live, slot:)` resolves non-`.fit` sizes at `HeaderMath.liveHeight(width: W, containerHeight: H)`
  (fec83e3); the `.fit` plan (`init(box:)`) and `HeaderFallbackFrame`'s two ideal-ratio boxes: the inner measuring box
  (the content's ratio, reports `N` unlimited through `noteBox`, DEBUG event `box fit w|h WxH q R`) and the outer layout box
  (ideal height clamped at `L − m′`, at the committed viewport never below the committed `R − m′`) (71cc6d1, d89c745, 106c216).
- `ScalingHeader/HeaderHost.swift`: the host applies `HeaderSlotReader` (fec83e3).
- `ScalingHeader/HeaderMeasure.swift`: `HeaderMeasuringPass` re-arms on a width change only while the header has no metrics
  (C18, 71cc6d1); its first measurement is adopted at once (d89c745).
- Tests: `HeaderFallbackSlotTests` (new: slot counters, the slot = the committed container at rest, the animated pass final
  for a capped height / a width that turns the limit off / a `.fit` width in the band, a `.fit` content change in the band, a
  runtime overflow change, every committed run-loop turn from launch has the header, and `aWidthChangeIsDrawnWithTheContent`,
  the drawn header and content per frame from the presentation layer tree, both paths); `HeaderLayoutFrameTests` (the slot
  plan, the `.fit` box plan, `R` in both fits); `HeaderMathTests` (`overflowLimit`); `HeaderReviewD16Tests` (the forced
  `withKnownIssue` removed: an overflow-limited `R` is final in the animated pass on both paths).
- Docs: SPEC S10 (`.fit(min:)`, Natural height, the `.fit` resting height, the D78 bullet replacing the two 15-path known
  limits, item 15 (c) as open and queued, not a limit; S-test list); Orchestration D78, item 15 (b) FIXED with the table,
  15 (c) with its evidence, session log.

Decisions:
- D78 as designed (A: the cold slot reader; C: the `.fit` ideal-ratio box), with two amendments found while building:
  - The `.fit` box reports `N(W)` unlimited, as 16+'s ideal-size query, and the state applies the limit. With the limit
    clamped into the reported value, a runtime overflow change (`.capped(0.25)` → `.uncapped`) resolved from a stored natural
    = the old limit and was adopted a turn later as a content change (offset kept, then animated: 160.9 → 145.1 pt on 15;
    16+: 145.0 at once).
  - The measuring pass adopts its first measurement at once. Deferred to the next run-loop turn, the first committed turn
    on the 15 path had the header at 0.01 pt and no metrics (at 7206175 too; seam lab forced showed it once). Probe:
    a `CFRunLoopObserver` after Core Animation's commit (`HeaderFallbackSlotTests.TurnSampler`); a per-1/60-s pump cannot see it.
- Rejected (d89c745 → 106c216): the limit offered to a single box as a height proposal (`frame(idealHeight: (1 − q)(L − m′))`).
  The layouts were identical, but an animated narrowing that leaves the limit (402 → 241 pt, `.capped(0.25)`, half collapsed)
  drew the header at its final size from the first frame on the forced path: seam 29.3 pt, lateral 160.7 pt in the hosted
  presentation tree (29.3 / 159.3 in the seam lab, 28.7 on 17.5). The marker layer keeps its identity and has no Core
  Animation animation (SwiftUI sets model frames per frame); its size was final while its position animated. Variants
  (hosted, 27.0): the outer frame's width nil in the width fit was worse (widening failed too); the box `W` wide at rest (ideal
  width scaled by (N − m′)/(R − m′), no overflow) still failed; no `frame(idealHeight:)` passed the narrowing and failed the
  widening into the limit. Fix: two boxes, the clamp for layout and a measuring box for `N`. The SwiftUI mechanism that loses
  the animation is unknown; `aWidthChangeIsDrawnWithTheContent` guards it on both paths.
- At the committed viewport the layout box's clamp is `max(L, R_c) − m′`, as 16+'s `layoutResting`: with the plain clamp, a
  runtime tightening cut the stack to the new limit one pass before the state committed it
  (`aRuntimeOverflowChangeFollowsTheSameSequence`, forced, q 0).
- C7: no `noteBox` skip while pulled, no adopt-at-release; the D79 pin (`live.pinned(.headerFallback)`) is kept.

Measurements (seam lab `scripts/seam/baseline.sh`; before = 7206175 (`b27f`, `b175f`), after = 106c216 (`a27f3`, `a27f4`,
`a175f3`, `a175f4`); preferred = 71cc6d1's build (`a27p`, `a175p`: d89c745 and 106c216 change only 15-path code, which 16+
does not run); forced = `-ZTronForceAllFallbacks`; cell = |seam| pt / lateral pt / largest 60 Hz step as a fraction of the
header's change; `-` = no lateral move or no net change; PASS = ≤ 1 / ≤ 1 / < 0.5):

| row (`…-forced` on the forced lanes) | 27.0 forced before | 27.0 forced after | 27.0 preferred | 17.5 forced before | 17.5 forced after | 17.5 preferred |
|---|---|---|---|---|---|---|
| `aspect-half-preserve-width-capped25` (S-RS-2) | 29.3 / 159.3 / 1.00 | 0.52 / 0.17 / 0.03 | 0.50 / 0.29 / 0.03 | 28.7 / 0.32 / 1.00 | 0.50 / 0.33 / 0.02 | 0.50 / 0.28 / 0.02 |
| `aspect-half-preserve-width-capped25-slide1` | 29.3 / 159.3 / 1.00 | 0.17 / 0.17 / 0.02 | 0.17 / 0.17 / 0.02 | | | |
| `aspect-rest-preserve-width-capped-height04` | 70.0 / - / 1.00 | 0.33 / - / 0.03 | 0.33 / - / 0.03 | 69.3 / - / 1.00 | 0.50 / - / 0.03 | 0.50 / - / 0.03 |
| `aspect-half-preserve-width-capped-height04` | 35.2 / - / 1.00 | 0.50 / - / 0.03 | 0.33 / - / 0.03 | | | |
| `aspect-rest-preserve-width-refit-height025` | 31.3 / - / 1.00 | 0.33 / - / 0.03 | 0.33 / - / 0.03 | | | |
| `fixed-rest-preserve-width-capped-height04` | 84.2 / - / 1.00 | 0.33 / - / 0.02 | 0.33 / - / 0.02 | 88.5 / - / 1.00 | 0.50 / - / 0.03 | 0.50 / - / 0.03 |
| `aspect-rest-preserve-width-capped-height04-vland` | 114.8 / 0.33 / 1.00 | 0.33 / 0.38 / 0.10 | 0.33 / 0.33 / 0.10 | | | |
| `fit-half-preserve-width` | 45.2 / 159.3 / 1.00 | 0.50 / 0.28 / 0.03 | 0.50 / 0.17 / 0.03 | 44.5 / 0.18 / 1.00 | 0.67 / 0.33 / 0.03 | 0.67 / 0.33 / 0.03 |
| `fit-rest-preserve-width` | 0.33 / 0.34 / 0.03 | 0.33 / 0.37 / 0.03 | 0.33 / 0.38 / 0.03 | | | |
| `fit-half-preserve-width-capped25` | 29.3 / 159.3 / 1.00 | 0.50 / 0.20 / 0.03 | 0.50 / 0.32 / 0.03 | 28.7 / 0.28 / 1.00 | 0.50 / 0.28 / 0.03 | 0.50 / 0.33 / 0.02 |
| `fit-half-preserve-width-slide1` | 0.17 / 0.34 / 0.03 | 0.17 / 0.34 / 0.05 | 0.17 / 0.34 / 0.03 | | | |
| `fit-half-preserve-width-vretarget` | 45.2 / 159.3 / 1.00 | 0.33 / 0.17 / 0.04 | 0.50 / 0.17 / 0.04 | | | |
| `fit-half-preserve-rotate-sticky` | 0.17 / 0.49 / 0.10 | 0.17 / 0.49 / 0.10 | 0.17 / 0.49 / 0.10 | | | |
| **`fit-half-preserve-width-grow`** (KEY: a `.fit` content change in the band) | 0.17 / - / - (not re-measured: the header kept its height) | 0.50 / - / 0.04 | 0.50 / - / 0.04 | 0.17 / - / - (not re-measured) | 0.50 / - / 0.04 | 0.50 / - / 0.04 |
| `fit-rest-preserve-width-grow` | 0.50 / - / 0.03 | 0.50 / - / 0.03 | 0.50 / - / 0.03 | | | |
| `fit-half-preserve-scroll-band` | 0.50 / - / 0.03 | 0.50 / - / 0.03 | 0.50 / - / 0.03 | | | |
| `aspect-rest-preserve-width` | 0.33 / 0.20 / 0.03 | 0.33 / 0.20 / 0.03 | 0.33 / 0.20 / 0.03 | | | |
| `aspect-rest-preserve-rotate-capped` | 0.17 / 0.33 / 0.10 | 0.17 / 0.32 / 0.10 | 0.17 / 0.32 / 0.10 | | | |
| `aspect-half-preserve-scroll-band-capped25` | 0.50 / - / 0.03 | 0.50 / - / 0.03 | 0.50 / - / 0.03 | | | |
| `aspect-rest-preserve-pull-capped25-opengap` (`.openGap`: the gap is the pull, by design; header still) | 102.0 / - / - | 102.0 / - / - | 102.0 / - / - | | | |

Notes on the table:
- The rotation and landscape rows' 0.10 is the rotation's own frame rate (header and content step together).
- `fit-half-preserve-width-slide1` forced read 0.214 in `a27f3`: one 267 ms recorder / host hitch (frame 240 → 241, header and
  content stepped together, seam 0.195) while the 17.5 unit run started; re-run in `a27f4`: 0.05.
- d89c745 (the rejected single box) regressed `fit-half-preserve-width-capped25` forced to 29.3 / 159.3 / 1.00 (27.0) and
  28.7 / 0.28 / 1.00 (17.5); 106c216 is the after column.
- Hosted drawn geometry (`aWidthChangeIsDrawnWithTheContent`, 40 frames of 1/60 s, `withAnimation(.linear(0.5))`, width 402 ↔
  241.33, both paths, 27.0 and 17.5): seam ≤ 0.16 pt, lateral 0, largest step 1.96 of 29.33 pt (`.capped(0.25)`, q 0.5), 6.02
  of 90.33 (`.uncapped`, q 0), 3.0 of 45.0 (`.uncapped`, q 0.5); at d89c745 the capped narrowing read seam 29.25, lateral
  160.67, one step of 29.33.
- Counters (`HeaderFallbackSlotTests`, both paths, 27.0 and 17.5): 90 steps of scrolling, collapsing and pulling: `header.slot`
  0, `header.builder` 0, content bodies 0, the frame leaf 90 bodies; a window resize: `header.slot` 1 on the forced path, 0 on
  16+, builder 0, content bodies 0, header content bodies 0, `R` = `min(W · 9/16, L)`.
- Key scenarios of the earlier steps, re-run at 106c216:
  - s2 (27.0 preferred `fixed-rest-preserve-rows-rows5-rowsto10-internal`, `rows.py`): fade-in 28 frames, step 0.059, landing
    452 ms; fade-out 28 frames, 0.059, 450 ms; late step 0; content top fixed (= s2's 28 / 28, 0.059, 453 / 450 ms).
  - s3 (forced `aspect-rest-stretch-fling-hold-hsys60-hend1p5-hreset4-fdown`, `catchcheck.py`): fall beyond the reset 0.66,
    spinner 20 on every frame, step vs centred 0.67, header seam 0.5, 0 frames > 1 (s4's after: 0.01 / 20 / 0.67 / 0.5, 0;
    the fall is one pixel either way, acceptance ≤ 1).
  - s4 (forced `fixed-rest-preserve-width-noheader-hold-height04-instant`, `holdgap.py --edge top`): 56/56 in place, 0 missing /
    over / tint / ghost (= s4's 57/57).
  - s1 (17.5 `aspect-rest-stretch-pull-refresh-rtrig40`, `handover.py`, two runs on 2026-11-07, load 12–55): residual 2.0 / 2.0, half 0.67 / 0.67, ramp step 0.227 / 0.214,
    mixed 11 / 12 (= s3's and s4's record 2.0 / 0.67 / 0.21 / 11–12: no regression from this step; the 2.0 is under Open).

Open:
- Item 15 (c) (`combo`, open, queued as a fix by the user's rule; not this mechanism, D78 design §1.4): a scroll command
  during an open animated resize calls `beginIntervention()` (`State/ZTronScrollState.swift` 365) → `closeResize()` (1137),
  which writes the final metrics and offset unanimated: the content snaps while the header keeps animating. Lateral, back
  segment: forced 50.0 pt (`base27f`), forced with spike A 52.1 (`spkAB27f`), 27.0 preferred 53.3 with a 29.8 pt gap and a
  31.2 pt content step (fraction 0.25, `ctlC27`), so 16+ too. Direction: close or retarget the resize inside the app's
  animated transaction instead of unanimated; needs its own design.
- s1's key on 17.5 (`rtrig40`) reads residual 2.0 pt against item 31's 1 pt (one frame pair before the trigger, the glyph
  clipped at the band's edge: drawn 10 → 12.67 rows, centre +4 vs predicted +2). s1 read 0.67–0.92 there on 2026-11-03; s3, s4
  and this step read 2.0 since 2026-11-04 with the before and after code alike. The library is identical between s1's
  848759a and c1ec40f (only `Demo/ZTronScrollViewDemo/SeamLabScreen.swift` changed: s2 / s3 lab extras), and this step changes
  header code only, so it is not this step's. Not settled: whether it is the lab screen's diff or the 17.5 lane; check by
  running 848759a and HEAD on the same 17.5 simulator back to back.
- 16+ lays the `.fit` header out at pixel-rounded sizes (`R` 135.675 vs 135.75 at 241.33 pt), the 15 path does not: 0.075 pt,
  a quarter of a pixel, pre-existing (not D78); recorded so a future exact-equality test does not read it as a 15–16 difference.
- Real 15.0 / 16.0 checks (M1 lane), per fix (i15b §10):
  - A, the slot reader (non-`.fit`): the §7 rows S-RS-2 (`aspect-half-preserve-width-capped25`, `-slide1`), the height rows
    (`…-capped-height04`, `-refit-height025`, `fixed-…-capped-height04`, `-vland`) PASS natively with no first-frame landing;
    DEBUG `slot WxH` precedes the first animated frame of a resize (closure timing); `header.slot` 0 while scrolling or pulling.
  - C, the `.fit` boxes: DEBUG `box fit w|h WxH q R` gives `R = W · 9/16` and `L` when capped, in the width fit during a resize
    and the height fit at rest and in the band (confirms `aspectRatio(nil, .fit)`'s ideal-ratio semantics and
    `fixedSize(horizontal:)` under a fixed height); `fit-half-preserve-width`, `-capped25`, `-vretarget`, `-rotate-sticky`
    PASS; `fit-half-preserve-width-grow` seamless (header and inset move together); no dropped frames during a collapse with
    the demo's profile header (the per-frame box reader's cost).
  - The measuring box (`N` unlimited) and the 106c216 fix: `HeaderFallbackSlotTests.aWidthChangeIsDrawnWithTheContent`'s
    scenario in the app (`fit-half-preserve-width-capped25` narrowing and widening), and a runtime overflow change
    (`.capped(0.25)` → `.uncapped` at rest): the header follows the commit in the same transaction as the inset.
  - The first measurement at once: launch with a `.fit` header, the header and its inset in the first frame.
  - 16.0 (the `Layout` path): the same rows show no regression; the wrapper is a pass-through there.
  - Both: item 15 (c)'s combo, to record how the native runtime treats the M5 snap (expected: as 27.0).

Next:
1. M8b-s8's remaining steps per `docs/design/M8b-s8-plan.md` (s6 on).
2. A design for item 15 (c) (the M5 intervention inside the app's animated transaction).
3. The real 15/16 checks above with the M1 lane.

Tests:
- Unit, the 18 header suites (`HeaderFallbackSlotTests`, `HeaderReviewD16Tests`, `HeaderLayoutFrameTests`, `HeaderFitTests`,
  `HeaderMathTests`, `HeaderSlideBehindTests`, `HeaderStretchScaleTests`, `HeaderResizeTests`, `HeaderHeightResizeTests`,
  `HeaderSafeAreaInsetTests`, `HeaderKeyboardTests`, `HeaderPullBehaviorTests`, `ScalingHeaderHostedTests`,
  `HeaderFadeHostedTests`, `HeaderFadeMathTests`, `HeaderInsetConsumerTests`, `HeaderStateTests`, `ScalingHeaderAPITests`;
  `scripts/test.sh -only-testing:ZTronScrollViewTests/<suite>`): 140 tests passed on 27.0 (509 s) and 17.5 (503 s) at 106c216.
- Unit, whole `ZTronScrollViewTests` at 106c216: 884 tests in 86 suites passed with 8 known issues on 27.0 (1139 s, 2026-11-04)
  and 17.5 (1099 s, 2026-11-07; the 2026-11-04 17.5 run was stopped by the user's pause and re-run).
- Demo UI (`HeaderUITests` + `ResizeUITests`, 29 tests, `scripts/test-demo-ui.sh`): 29 / 29 on 27.0 preferred, 17.5 preferred and
  27.0 forced at 106c216.
- Seam lab: the table above (`scripts/seam/baseline.sh`; `rows.py`, `catchcheck.py`, `holdgap.py`, `handover.py`).
Usage: not measured in this subagent.
