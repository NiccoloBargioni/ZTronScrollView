# M8b-s8-s2 handoff · 2026-11-04 · Opus 5.5 · xhigh
Status: done. Builder s2-content-anim-stall (retry: the first builder died on a network drop; its WIP restored from
`scratchpad/s8/s3/s2-wip`, kept there). Open item 34 is closed. The stall is the hosted test process's: in the app the
content's own animations draw on every display frame on all three lanes. No library change.

Changed:
- Tests: `Support/AppFrameDriver.swift` (new). `AppFrameDriver` is a running `TimelineView(.animation)` beside the hosted
  view, outside the library. `hostDriven(_:driven:size:)` hosts a view with it. `ContentAnimationTickTests` (new, fa9525d;
  777630a prints the bar's last drawn height):
  - `referenceTicksDriven`: plain SwiftUI in the driven rig.
  - `rowChangeTicks`: no header, `.compress` and `.slideBehind`; internal and external changes; rows inserted or grown, in
    both directions, on both paths. Gates: ≥ 20 frames, step < 0.5, `hval` ≥ 20, S4 counters.
  - `undrivenNoStallBeyondTheLayerGroup`: the asynchronous path, against plain, grouped and native references.
- Demo (b8b0b71, b32b40b): `SeamLabScreen` takes `-ZTronSeamRows n`, `-ZTronSeamRowsTo m` (seam.width toggles the count in
  `withAnimation(.easeInOut(duration: 0.5))`), `-ZTronSeamRowsInternal 1` (a model that only the content observes),
  `-ZTronSeamRowsPlain 1`, `-ZTronSeamRowsGrow 1` (rows 60 → 120 pt, no insertion) and `-ZTronSeamRowsHost native|plain`
  (reference hosts). `SeamLabUITests.testRows` added.
- Scripts: `measure.sh rows`. `baseline.sh` extras `rows<n>`, `rowsto<m>`, `internal`, `plain`, `rgrow`, `hnative`,
  `hplain`. `rows.py` (new) reads per frame the opacity of the first changed row, or row 0's height with `rgrow`. It splits
  segments by direction and reports `rest`, `landMs` and `lateStep` per stimulus.
- Docs: Orchestration open item 34 (closed, with numbers) and a session log row. d75 design: §2.3 amendment, R1 resolved,
  a §9.2 note (host drawn-frame gates through `hostDriven`), §10 item 7 (the real 15/16 check).

Decisions:
- No D81. Nothing in the library changed, so there is no structural decision.
- Hosted gates that count drawn frames host through `hostDriven`. An app-less process has no update cycle: SwiftUI draws
  animation frames off the main thread there, and the main-thread pass they then need never comes. Undriven runs stay
  only to test the asynchronous path itself.

Cause (measured; full bisect table in `scratchpad/s8/notes.md`, section `s2-content-anim-stall`). These are undriven rig
results:
- An animated insertion stops after 1–2 evaluations in plain SwiftUI too, on 27.0 and 17.5.
- A grow runs off the main thread to the end (29–30 evaluations, last drawn value = the end value). On 27.0 it stalls under
  a `geometryGroup()` or a `compositingGroup()` in plain SwiftUI too. On 17.5 it runs to the end under both groups.
- A native `ScrollView` ticks on the main thread through `UIScrollView` layout passes.
- 25 suspects were bisected. Only the content and header layer groups matter, and only in the rig.

Measurements (before = the defect as reported, or the scenario at 24f07af, which has no library change since; after = HEAD):

| scenario | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|
| rig, undriven (the defect): `uval` / `uframe` in 0.5 s, insert / grow | 1 / 1 (grow under the groups) | 1 / 29–30 async | 1 / 30 (no header), 2 (header) |
| rig, driven (`hostDriven`; the 17.5 column covers both paths): `uval`, `uframe` / drawn / step / `hval` | 24–29 / 24–28 / 0.06 / 24–28 | 27–29 / 27–28 / 0.06 / 27–28 | 28–30 / 27–29 / 0.06 / 27–28 |
| S4: kept rows' bodies (insert) / `header.builder` (internal) | 0 / 0 | 0 / 0 | 0 / 0 |
| app `…-rows5-rowsto10` fade in / out: frames in 0.5 s, step, landing (ms) | 28 / 28, 0.059, 445 / 452 (re-record) | 28 / 28, 0.059, 457 / 450 | 28 / 28, 0.059, 452 / 452 |
| `-internal` | 28 / 28, 0.059, 448 / 448 | 28 / 28, 0.059, 453 / 452 | 28 / 28, 0.059, 452 / 450 |
| `-noheader` | 28 / 28, 0.059, 447 / 450 | 28 / 28, 0.059, 455 / 450 (re-record) | 28 / 28, 0.059, 448 / 450 |
| `-rgrow` (60 → 120 pt) | 27 / 27, 0.067, 435 / 448 | 28 / 28, 0.056, 448 / 447 | 27 / 27, 0.067, 450 / 448 |
| `-rgrow-internal` | 27 / 27, 0.067, 433 / 450 | 28 / 28, 0.056, 452 / 450 | 27 / 27, 0.067, 433 / 450 |
| `-rgrow-noheader` | 27 / 27, 0.067, 452 / 448 | 28 / 28, 0.056, 450 / 450 | 27 / 27, 0.067, 448 / 450 |
| header seam during the rows' animation (pt) | 0.0 | 0.167 | 0.0 |
| references, internal insert: native / plain (landing ms) | native 27 / 27 frames, **2187 / 2458** (late last level); plain 448 / 452 | native 450 / 452; plain 452 / 452 | — |
| no regression: `aspect-rest-preserve-width` | \|seam\| 0.333, lateral 0.268, hJ 0.026 (M8b-s5: 0.33 / 0.27 / 0.026) | | |
| no regression: `aspect-rest-preserve-rotate` | gap 0.0, overlap 0.077, lateral 0.1 | | |
| s1 key `aspect-rest-stretch-pull-refresh-rtrig40` (`handover.py`): residual / half / ramp / mixed | | 2.0 / 0.67 / 0.214 / 12 (s3 / s4: 2.0 / 0.67 / 0.19–0.23 / 11–13) | |
| s3 key `…-fling-hold-hsys60-hend1p5-hreset4-fdown` (`catchcheck.py`): fall / spinner / step vs centred / seam | | 0.67 / 19.3–20 / 0.33 / 0.5, 0 frames > 1 (s4: 0.67 / 20 / 0.67 / 0.5, 0) | |
| s4 key `fixed-rest-preserve-width-noheader-hold-height04-instant` (`holdgap.py --edge top`) | | | 57 / 57 in place, 0 missing / over / tint / ghost (s4 after: the same) |

Notes on the table:
- The app columns are the same before and after: the library did not change. The lab runs at b8b0b71 / b32b40b (HEAD's
  library). Landing is measured from the change's first drawn frame. The 0.5 s ease-in-out moves under one 8-bit level in
  its last ~50 ms.
- Re-recorded at load < 25:
  - 27.0 external fade-out: the first run had a 535 ms recorder hole at load ~200 (18 frames, step 0.082).
  - 17.5 `-noheader`: the first run had a 77 ms recorder gap (25 frames, step 0.209).
- Late last level. In both 17.5 internal runs recorded at load 413 (a concurrent build), every animation frame was drawn on
  the 17 ms cadence, but the last level waited for the test's next XCUI event, 1.8–2.0 s later:
  - fade: opacity 0.984 → 0.992 and 0.004 → 0;
  - grow: row 0 at 119.33 → 120 and 60.67 → 60 pt (2 px), landing 2257 / 2452 and 2293 / 2482 ms.
  It is SwiftUI's own: on 27.0 at load 5 the native `ScrollView` (`-internal-hnative`) shows it (2187 / 2458 ms). Below
  load 25, ZTron, native and plain all land on time on 17.5, and ZTron lands on time in every 27.0 and forced run.
  Undriven, the rig's asynchronous path draws the end value wherever it runs (`last 100.00`), so the rig does not
  reproduce it.
- ContentOverlayTests failed once on 27.0 (`motionRunsNoContentNoOverlayNoHostNoPlacement`: the zoom bounce had not ended
  in its 1.2 s pump) at load 413. Run alone afterwards: 30 / 30.

Open:
- None for item 34.
- Real 15/16 (M1 lane):
  - `ContentAnimationTickTests`: the driven gates ≥ 20. The undriven printout shows whether 15–16's `compositingGroup()`
    stalls the rig as 27.0's `geometryGroup()` does.
  - Seam lab `fixed-rest-preserve-rows-rows5-rowsto10` with `-internal`, `-noheader`, `-rgrow` and the
    `-hnative` / `-hplain` references: ≥ 20 frames in 0.5 s, step < 0.5, landing ~450 ms, seam ≤ 1 pt, and no late last
    level in ZTron where native has none (d75 §10 item 7).
- For s8's later steps (d75 s8–s10) and M8b-s9 (D77's group):
  - host every drawn-frame gate through `hostDriven`;
  - when D77 adds or changes a layer group above the content, update `ContentAnimationTickTests.ReferenceHost.grouped` to
    the same group, so the undriven comparison stays like-for-like.

Next:
1. M8b-s8's next step per `docs/design/M8b-s8-plan.md`.
2. The real 15/16 checks above with the M1 lane.

Tests:
- Unit, 27.0 then 17.5 (`scripts/test.sh`, own simulators):
  - `ContentAnimationTickTests`: 3 / 3 on both at fa9525d and again at 777630a.
  - TransformTests, LayoutHostTests, ContentOverlayTests, ParentReevaluationTests, CounterTests, HeaderStateTests: 17.5
    62 / 62. 27.0: 61 / 62 at load 413, then ContentOverlayTests alone 30 / 30.
- Demo UI (`scripts/test-demo-ui.sh`, ProofUITests + SeamLabUITests, 16 tests, b32b40b): 27.0 preferred 16 / 16, 17.5
  16 / 16, 27.0 forced 16 / 16.
- Seam lab: lanes a27 / a27r / a27f / a175 / a175c (`scripts/seam/baseline.sh`, `rows.py`, `holdgap.py`, `handover.py`,
  `catchcheck.py`), the table above.
Usage: not measured in this subagent.
