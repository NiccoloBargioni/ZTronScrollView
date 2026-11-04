# M8b-s8-s4 handoff · 2026-11-04 · Opus 5.5 · xhigh
Status: done. Builder s4-refresh-27-behind: open item 27 fixed for instant resizes and the delay after a rotation (D80: the
ungrouped headerless gap indicator drawn behind the content; D66 retired). The 15–16 rotation residual is ruled by D77 and
scheduled in M8b-s9.

Changed:
- `ZTronScrollView.swift` (`ScrollContainer`): `@StateObject refreshHolder` (one coordinator for both slots); the `.behind`
  slot, `.background(RefreshOverlay(…, layer: .behind).ignoresSafeArea(.all, edges:))` after the transform host, only when
  `!state.usesGeometryGroup`; the front overlay takes the holder.
- `Refresh/RefreshIndicators.swift`: `RefreshOverlay(holder:layer:)` (the front slot wires the coordinator, `cancelAll`,
  accessibility, haptic; the behind slot lays out leaves only, hit testing off); `RefreshLayer`,
  `RefreshLayerMath.draws(layer:kind:overlay:)`; `RefreshIndicatorsHost(layer:)`, `RefreshEdgeIndicator(layer:)`;
  `RefreshGroupLatched(overlay:layer:)` draws the boxes only in its slot (DEBUG note `refresh.slot`, counters
  `refresh.leaf.front` / `refresh.leaf.behind`, `refresh.host.behind.body`). Deleted (D66): `RefreshResizeReveal`, the
  `reveal` input, the boxes' gate and its transaction, the note `refresh.d66`. 29857c0: `RefreshLookSwitch.look(trace:)`
  (only the front leaf traces a switch; the forced `RefreshUITests` read it twice) and the behind slot's pin key.
- `Render/CatchPin.swift`: `Key.refreshBehind(Edge)` (29857c0): each placement effect keeps its own D79 latch, so the slot
  that does not draw never ends the drawn one's pin.
- Tests: `RefreshLayerMathTests` (new: every kind × overlay × layer; the slot latched with the group while the boxes exist, a
  header installed and the indicator swapped during a hold, the next hold latching again; an instant resize draws the gap
  indicator at once at its place, content bodies 0, one leaf per slot and update), `Support/RefreshSlots.swift` (new),
  `RefreshIndicatorLayerTests` and `RefreshIndicatorBodyTests` read the slots, the D66 test removed from
  `RefreshIndicatorTests`.
- Lab (6b00454): demo `-ZTronSeamInstant 1` (extra `instant`: `seam.width` resizes without animation),
  `-ZTronSeamClearFirstRow 1` (extra `clearrow`: the content's first 80 pt along the hold's axis clear), `holdgap.py
  --clear-row <pt>` (the probe seen through the clear row counts as over).
- Docs: Orchestration D80, D66 superseded, open items 20 and 27; SPEC S9 (indicator placement) and S10 (15–16 layer groups).

Decisions:
- D80 as designed (refresh design §5.2); plan C9 kept: no `fallbackLayer:` option (D77's group closes the residual instead).
- Hosted unit tests that need a hold's retraction to end replace the coordinator's `schedule` with a run-loop `Timer`
  (`RefreshLayerMathTests.runLoopTimers`): GCD's main queue never runs inside a synchronous main-actor test's `pump`, so the
  retraction heartbeat (`DispatchQueue.main.asyncAfter`) never fired and the boxes never ended (`.retracting` at progress
  0.6 for 4 s on both paths, the same at 6b00454; with the timer all 8 probe cases end). Not a library defect.

Measurements (seam lab, `holdgap.py`; forced = 27.0 `-ZTronForceAllFallbacks`; before = 6b00454, after = 5323f20; "start" =
frames missing from a rotation's first frame, "return" = inside the rotation that brings the gap back, "after" = after that
rotation's end; frame classes by the analyzer's motion segments, `scratchpad/s8/s4/classify.py`):

| row (27.0 forced unless named) | before | after |
|---|---|---|
| `fixed-rest-preserve-width-noheader-hold-height04-instant` (KEY) | 31/57 in place, **26 missing**, 0 over / tint / ghost | **57/57, 0 missing**, 0 over / tint / ghost |
| `fixed-rest-preserve-rotate-noheader-hold` (top) | 55/77: start 7, return 5, **after 10**; 0 over / off / ghost | 67/75: start 7, return 1, **after 0**; 0 over / off / ghost |
| `…-rotatel-noheader-hold-horizontal-hleading` | 56/80: start 4 + 5, return 4, **after 11**; 0 off | 67/78: start 4 + 4, **after 0**; off 3 (12.3 / 5.2 / 1.3 pt); 0 over / ghost |
| `…-height04-instant-hoverlay` (`--overlay`) | drawn 63/63, step 0 | drawn 62/62, step 0 |
| `…-rotate-noheader-hold-hoverlay` (`--overlay`) | drawn 99/99, largest step 17.45 pt (0.100 of 174) | drawn 112/112, 17.52 pt (0.101) |
| `…-instant-clearrow` (`--clear-row 80`) | 30/59, 29 missing, 0 seen through | 56/56, 0 missing, **0 seen through** |
| `…-rotate-noheader-hold-clearrow` | 54/77: start 6, return 4, after 13; 0 seen through | 68/76: start 6, return 2, after 0; **0 seen through** |
| `…-hleading-clearrow` | 55/79: start 4 + 5, return 4, after 11; 0 seen through | 68/79: start 4 + 5, after 0; off 2 (11.9 / 4.6 pt); **1 frame seen through** (240, the rotation's end, the off frames' moment) |
| `…-rotate-noheader-hold-hbottom` | 54/83: start 8, return 3 + 8, after 10; 0 off / over | 69/85: start 8, return 2 + 3, after 0; off 3 (186–207 pt from the content's edge, which lags 180 pt and lands in one frame at 257 → 258, as before); 0 over |
| `…-rotatel-noheader-hold-horizontal-htrailing` | 56/79: start 4 + 4, return 4, after 11 | 66/78: start 4 + 5, after 0; off 3 (11.9 / 4.6 / 1.4 pt); 0 over |
| `fixed-rest-preserve-width-noheader-hold` (animated width) | 177/177 | 179/179 |
| `fixed-rest-preserve-width-noheader-hold-height04` (animated) | 63/63 | 62/62 |
| `fixed-rest-preserve-fling-noheader-hold` | 26/26 | 65/65 |
| `aspect-rest-stretch-fling-hold`, `fixed-rest-preserve-rotate-hold` (header; `probeover.py`) | 0 over (67 / 133 probe frames); rotate-hold 83/83 | 0 over (69 / 132); 82/82 |
| 27.0 preferred: instant, top, leading, overlays | 56/56, 76/76, 82/82; overlays 61/61 (step 0), 114/114 (0.102) | 57/57, 72/72, 78/78; 62/62 (0), 79/79 (0.101); 0 missing / over / off |
| 17.5: instant, top, leading, overlays | 55/55, 57/57, 58/58; 61/61 (0), 83/83 (0.102) | 57/57, 55/55, 58/58; 61/61 (0), 82/82 (0.102); 0 missing / over / off |
| s3 key, forced (`catchcheck.py`; after = 29857c0): fall beyond the reset / spinner / step vs centred / header seam, frames > 1 | 0.67 / 20 / 0.34 / 0.5, 0 | 0.01 / 20 / 0.67 / 0.5, 0 |
| a catch of a headerless hold's reset, forced `fixed-rest-preserve-fling-noheader-hold-hend1p5-hreset4-fdown` (the probe drawn behind; 29857c0) | 94/94 in place, 0 over / off | 94/94 in place, 0 over / off |
| s3 key, 17.5 `aspect-rest-stretch-fling-hold-hsys60-hend1p5-hreset4-fdown` (`catchcheck.py`): fall beyond the reset / spinner / step vs centred / header seam, frames > 1 | 0.66 / 20 / 0.67 / 0.5, 0 | 0.67 / 20 / 0.67 / 0.5, 0 |
| s1 key, 17.5 `aspect-rest-stretch-pull-refresh-rtrig40` (`handover.py`): residual / half / ramp / mixed | 2.0 / 0.67 / 0.21–0.23 / 12 (3 runs) | 2.0 / 0.67 / 0.19–0.21 / 12–13 (3 runs; one read 2.33, one pixel) |

Notes on the table:
- Before = 6b00454 (the lab commit before D80); after = 5323f20 (29857c0 changes only a DEBUG trace and the pin's latch,
  measured with the catch rows). Rows 1–3 and the regression rows were re-run at load 7–40 (the first runs at
  load up to 661 read the same: 26 / 22 / 25 missing); the overlay and `clearrow` "before" rows are from the first run.
- The rotations' "after" frames are the residual of item 27 (ruled by D77, M8b-s9): "start" frames (the indicator is gone
  from the rotation's first frame: its gap is off the window in the final layout and it keeps no layer), the top's one
  "return" frame (the first frame the gap is back on the screen; 267 before D80 too), leading / trailing "off" frames
  (created at its final place in the viewport's frame, it follows the window's edge while it settles; the spike read 12.0 /
  5.2 / 1.2). The bottom row's "off" frames are measured against the forced headerless content's edge, which is 180 pt off
  in those frames (the content's own 15–16 rotation: it lands in one frame at the rotation's start and end, before and after
  D80); D66 hid the indicator there, D80 draws it at its final place until the content lands.
- Counters: `RefreshLayerMathTests.anInstantResizeDrawsTheGapIndicatorAtOnce` (both paths): 0 content bodies across the
  instant resizes and a rotation's layout (both axes swapped and back); the front and behind leaves evaluated once per update
  each on the forced path (|front − behind| ≤ 1), behind 0 on 17+; `RefreshIndicatorBodyTests`: the indicator's body once
  per drawing leaf frame, front = behind on the forced path.

Open:
- Item 27's 15–16 residual, ruled by D77 (user 2026-11-03) and scheduled in M8b-s9 with the custom headerless indicator's
  group: from a rotation's first frame the indicator is gone (top 7, leading / trailing 4 + 4–5, bottom 8 frames), the top
  edge's return misses 1 frame (2 with `clearrow`), leading / trailing follow the window's edge for 3 frames at the end
  (≤ 12.3 pt), the leading `clearrow` shows the probe through the clear row in 1 frame (240, the same moment). 17+: 0.
- The forced headerless content lands in one frame at a bottom-edge rotation's start and end (its edge 180 pt off, before
  and after: the content's own 15–16 rotation, no content group without a header); D66 hid the indicator through it, D80
  draws it at its final place for the 3 frames before the content lands (186–207 pt from the lagging edge). Not this step's
  (the content's rotation); re-measure this row with D77's groups in M8b-s9.
- Real 15/16 (M1 lane): D80 is the slot itself there (no group, no option):
  - `fixed-rest-preserve-width-noheader-hold-height04-instant` (and `-clearrow`): the indicator at once in its place after the
    instant resize, missing 0, over 0, 0 seen through;
  - `fixed-rest-preserve-rotate-noheader-hold[-hbottom]`, `…-rotatel-noheader-hold-horizontal-hleading|htrailing`: 0 frames over
    (translucent included), none missing after a rotation's end; count the start / return / off frames against the table
    (the residual D77 closes; iPhone rotations are 0.3 s, as the simulator's);
  - the bottom rotation: whether the real 15/16 headerless content also lands in one frame (the forced lane's 180 pt), which
    is what the 3 off frames are measured against;
  - `RefreshUITests.testACustomIndicatorsBlendModeReachesWhatIsBehindIt`: yellow over the gap's blue (behind the content),
    magenta over the content (front, overlay);
  - VoiceOver: a custom indicator's own elements are now before the content in the tree order (the behind slot); the refresh
    element and the announcements are the front slot's, unchanged; check the reading order;
  - the haptic at a trigger, once.
Next:
1. M8b-s9: D77's group for the custom headerless indicator (closes the residual above); re-measure the bottom rotation row.
2. The real 15/16 checks above with the M1 lane.
3. M8b-s8's remaining steps per `docs/design/M8b-s8-plan.md`.
Tests:
- Unit, whole `ZTronScrollViewTests` (`scripts/test.sh -only-testing:ZTronScrollViewTests`): 868 tests / 84 suites passed on
  27.0 and on 17.5 (9 known issues, as before: item 20's 8 and the 15–16 overflow-limited `R` of
  `HeaderReviewD16Tests.anOverflowLimitThatTurnsOnDuringAnAnimatedResizeIsInTheAnimatedPass`), at 5323f20 with the new
  tests; the touched suites (the six `Refresh*`, `DrawnCatchTests`, `TransformTests`: 82 tests) passed on both at 29857c0
  (8 known issues).
- Demo UI (`scripts/test-demo-ui.sh`: RefreshUITests + HeaderUITests + ProofUITests + ResizeUITests, 52 tests): 27.0
  preferred 52/52 and 17.5 52/52; 27.0 forced 51/52 at 5323f20 (`testABeginWhileThePullGoesBackSwitchesTheLookOnce` read the
  switch trace from both slots), fixed in 29857c0: forced RefreshUITests 17/17.
- Seam lab: the table above (`scripts/seam/baseline.sh`, `holdgap.py`, `probeover.py`, `catchcheck.py`, `handover.py`).
Usage: not measured in this subagent.
