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

Tests: see the Orchestration session log row (unit suites on 27.0 and 17.5, final run of this session).
Usage: not measured.
