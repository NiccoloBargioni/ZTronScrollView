# M8b-s4 handoff · 2026-10-27 · Opus 5.5 integrator, stage 2 (seamless header: measure and verify)
Status: partial. The seam matrix (27.0 preferred, 17.5 preferred, 27.0 forced) passes every listed requirement scenario.
Three runs fail: one documented 15/16 limit and two combination scenarios added in this stage (open). Branch
`m8b3-seamless-measure` (from `m8b3-seamless` 836751c). Main is not merged in: the lead session merges.
Changed:
- `ScalingHeader/HeaderMeasure.swift`: the 15/16 `.fit` measuring pass is armed in the resize commit's own update when the
  committed width differs from the last measured one. Before, it was armed through `onChange` plus an `@State` write, one
  update later. The report carries the width it was armed for, so a measurement at a new width is always delivered, and
  `measuredWidth` is `@State`. DEBUG events `meas` / `nat` (`ZTronRenderCounters.event`).
- `ScalingHeader/HeaderHost.swift`: DEBUG event in `setHeaderNatural`.
- Demo `SeamLabScreen.swift`:
  - `-ZTronSeamRefresh <s>`: a `.system` refresher with trigger 60, for refresh holds.
  - `-ZTronSeamScrollBand <f>`: `seam.scroll` targets that point of the band.
  - `-ZTronSeamWidthThenScroll <s>` and `-ZTronSeamWidthWithScroll 1`: a scroll command during, or in the same
    `withAnimation` as, the width change.
  - `-ZTronSeamInfo 2`: the state's event log in `seam.info`.
- `scripts/seam/baseline.sh`: extras `refresh`, `band`, `combo`, `together`.
- Test `HeaderLayoutFrameTests.aSizeChangeCommitsTheNewRestingHeightInsideItsLayout`: R is committed by the synchronous
  layout of a new size, on both paths.
- `docs/SPEC.md` S10 "Seamless edges": the 15/16 measuring-pass rule; known limits for the 15-path `.fit` in the band
  and for a scroll command overlapping an animated resize.
Decisions (none numbered; the lead assigns D-numbers):
- 15/16 `.fit` arms on a stale width, not through `onChange`. The event log of the forced rotation showed the cause: the
  sequence was arm → close (`tick-never-animated`) → measure. The measurement then arrived as an idle inset change after
  UIKit's rotation block, and the header and content jumped 98 pt at once. Now the measurement joins the open resize
  ("vp inset folded").
- The landscape blue band below an uncapped header taller than the viewport is not a seam. It is the scroll view's own
  frame clip: the lab lays the view out in the safe area, and it clips at the bottom safe area. The content top (422)
  is below that clip. This answers spike C's "why 382".
Open:
1. Scroll command overlapping an animated resize (27.0, combo / together):
   - Issued 0.5 s in, it ends the resize (M5 intervention). The content takes the committed geometry at once: 26.5 pt
     gap, 48 pt lateral.
   - Issued in the size change's own `withAnimation`, the resize drops the scroll, but the scroll's target already
     changed the header's held `o′` in that animated transaction. The header lands at once: 45 pt, hJ 1.00.
   - Fixing it needs a design decision. Options: keep the last rendered `o′` across the update that opens a resize, and
     make an intervention close the resize without the content snap.
2. The 15/16 `.fit` inside the band jumps on an app-driven resize (documented limit, forced: 45 pt). Rotations are now
   seamless there.
3. `ProofUITests.testNoClockTicksAtRest` on 27.0 preferred is flaky: `transform.effect` was 2 in the suite run. It then
   passed 3 of 3 alone and 18 of 18 with ProofUITests ×3. It passes forced. It was also listed as pre-existing in DBG-s1.
4. The cost of `compositingGroup` on a real 15/16 device is unmeasured.
5. The held `o′` at a clock-tick close is fine, because a tick close is unanimated. Only the transaction cases in item 1
   fail.
Next:
1. Decide item 1 (user or lead).
2. Real 15/16 device check (item 4).
3. Merge main (lead).
Tests:
- Seam matrix, 79 runs: 76 pass, 3 fail as above. See `scratchpad/seam/final-table.md` (session scratchpad).
- Header unit suites (54 tests) on 27.0 and 17.5: green.
- Full unit suite `scripts/test.sh -only-testing:ZTronScrollViewTests`: 727 tests in 64 suites, green on 27.0 and on 17.5.
- `HeaderUITests` + `ResizeUITests` + `ProofUITests` + `RefreshUITests` (43 tests):
  - 27.0 forced: 43/43.
  - 17.5 preferred: 43/43.
  - 27.0 preferred: 42/43; the failure is the `testNoClockTicksAtRest` flake (Open 3).
Usage: not measured.
