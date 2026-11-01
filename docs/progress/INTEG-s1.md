# INTEG-s1 handoff · 2026-11-01 · Opus 5.5 (integration session, wave 1 of `docs/design/INTEGRATION-plan.md`)
Status: done — wave 1 (rows 1–8) merged and verified on `claude/integ-wave-1-60dda2`; main fast-forwarded to it (never pushed).
Changed (one merge commit per branch, from main cc4be69):
- d77d05d `elastic-kirch-23bf73` (PARITY-s1, D53–D55, user-confirmed): doc conflicts only; D51–D55 + D59 in numeric order, CONFIRMED text kept.
- fde9b5d `vigilant-tharp-9659fb` (BTN-s1…s3, D49 rev 2): main's items 6–10 kept, BTN's item 11; `HeaderStateTests` re-derived inside the merge (the header
  snap is a natural release and sees the gated velocity: a 150 pt/s release from 60 now rests → expanded; the velocity-aware cases release at 10 with 300 pt/s).
- 5d878b5 `db10891` = sharp-banach stage A (D34 + D37, user-confirmed): `GestureAttach` 18+ `.simultaneous` = observer `isEnabled: on && observerEnabled`,
  pan `isEnabled: on`; D37 after main's D36; its item 11 → 24.
- a4b1338 `ecstatic-ramanujan-bd7af2` (DBG-s2 + content gate): its "D34" → D72, session DBG-s3 → DBG-s3b, handoff → `DBG-s3b.md`, its item 10 → 25
  (only lines the branch added; item 24 and the DBG-s3 log row point at 25).
- d322cfd `awesome-stonebraker-4fe43f` (docs): item 3b says the 17.5 red is fixed by DBG-s2 (item 25).
- c00071e `suspicious-elbakyan-3d1622` (DBG-s7, D46): D46 before D49, item 10 and the sheet parity row = main's SHEET-s2 text + the 18.x clause.
- bc575bc `silly-jang-777448` (NESTED-mixed D1): clean; doc pass: SPEC S11 entry + S16 dependents note, parity row, NESTED-mixed header, D73.
- 1b4b3ce BOTTOMSHEET-s1 docs from `nervous-fermi-60dcbf` (subset of f147d73): design note + handoff with a header note; item 26. 7b5cfbf dropped (D38).
- c7172be test harness only (user-approved, D52 extension, no new D): `HostingViews` in `Tests/…/Support/Unhost.swift` keeps every test
  `UIHostingController` alive on iOS 26+ (root emptied at retirement), used by `host()`, `HeaderFitTests`, `ScalingHeaderHostedTests`.
- Docs: Orchestration (State rows, item 9 merged, item 10 18.5 yield measurement, D38/D39 notes, D52 extension, log row), plan rows 1–8 marked.
Decisions:
- DBG-s9 guard red with stage A (13 warnings in 2 of 6 27.0 unit runs; 0 in 5 runs without it): the armed 18–27 observer puts
  `CatchArmingProbe` / `GatedGestureAttach` on every hosted test view; UIKit's app-less counts are address-keyed and never cleared, and freed
  hosting-view addresses are reused. Escalated; the user approved a harness-only fix under three conditions, all met (Tests).
- Numbers: D72 (ecstatic's "D34"), D73 (NESTED-s3); open items 24–26. Next free: D74, open item 27 (D68–D70 M8b-3, D71 + item 23 DBG-s12, D67 DBG-s11).
Open:
- 18.5: `SheetUITests` Y1–Y5 red on main cc4be69 and on the tip with the same numbers (the yield does not hold on 18.x, D46): pre-existing,
  recorded in item 10; waits on SHEET-s3 (plan row 16).
- 26.5: `PanUITests.testCatchWhileATextInputIsEditedDoesNotFireButton` (DBG-s3b) is timing-bound: XCUI's catching tap lands 0.4–2.1 s after
  `Animate`, the animation ends at ≈ 0.65 s; a tap after the end correctly fires the Button. Tip 1/3 alone (0.41 s pass; 0.95 / 2.1 s red),
  ecstatic head 3/3 (0.38–0.63 s). Test robustness (longer or slower animation), not a library defect.
- 27.0: `ButtonDragUITests.testDragRunningOffTheScreenEdgeFlingsLikeNative` red once in 7 27.0 runs: the pan got 2 drag events in 30 ms
  (1 → 64 pt) under load, then the pause, release velocity 0 (the pre-D49 shape); 3/3 alone (449–450 vs native 461–474). For the BTN owner:
  a two-sample drag that ends in a pause releases at 0.
- The strict 18+ expected failure of DBG-s3b (`testPanStartingOnAButtonWhileATextInputIsEditedScrolls`, the Button fires on lift) still holds
  with the D34 observer on 18.5 (both paths), 26.5 and 27.0: item 25's gap is unchanged.
- Known, not wave 1: `ProofUITests.testNoClockTicksAtRest` (2 ticks) red on fresh 27.0 devices at the base too (item in Orchestration).
- Absorbed branches still to delete (user's yes): see the plan's wave-1 list; nothing was deleted.
Next:
1. Wave 2 of the plan (row 9 sharp-banach stage B, D40, needs the user's one-line ack; then the rows after it).
2. M8b-3 (cool-stonebraker) reconciles item 11 and its header lanes against the 250 pt/s gate (D49 rev 2) when it merges.
3. SHEET-s3 decision (D47 → renumber) for the 18.x yield.
Tests (private clones, staggered, own derived data; the host ran other sessions' lanes too, load 100–1000):
- Unit `ZTronScrollViewTests` with the fix: 27.0 3× (feedback-loop threshold lowered to 5) 753/753, 753/753 + 1 timing flake
  (`PositionTests.settingTheIDScrollsAndAnimatesOnlyInsideWithAnimation`, the animation not started after 0.35 s; 3/3 alone), 753/753;
  17.5 3× 753/753; 0 feedback-loop warnings in all six. Contract `scripts/test-arbitration.sh` 39/39, physics `scripts/test-physics.sh` 119/119.
- App check (condition 2), 27.0 preferred with stage A: 0 warnings in the full demo lane's unified log; with `UIObservationTrackingLoggingEnabled`,
  0 UIKit-tracked invalidations in the demo during PanUITests fling / rubber band / catch on base and tip (2 runs each); an instrumented scratch
  build (NSLog, never committed) counted per pan test exactly 1 arm + 1 disarm, 5–8 `GatedGestureAttach` bodies (5 at rest with a tap only)
  and 3 `CatchArmingProbe` bodies against 118–270 frames; `content.body` 0 everywhere.
- Demo UI, tip c7172be (passed / failed / skipped): 27.0 preferred 199 / 1 / 18 (the button-drag flake above); 27.0 `--forced` 180 / 0 / 39;
  27.0 `--uikit` 180 / 0 / 39; 17.5 preferred 200 / 1 / 18 (`RefreshUITests.testCustomIndicatorFollowsTheModes`, 3/3 alone); 17.5 `--forced` 180 / 0 / 39. 0 feedback-loop warnings in every lane.
  27.0 preferred re-check: Refresh 14/14, Header 9/9, ContentOverlay 3/3, Sheet 62/62, Observation 3/3, Pan 20/20; 17.5 `testControlsUsable` green.
- Targeted, tip: 18.5 preferred 106 / 6 (Sheet Y1–Y5 as on main, P6 launch), `--forced` 87 / 5 / 21 (Y1–Y3, Y5, M3 launch), `--native`
  UIKitControls 9/9; 26.5 preferred 53 / 3 (catch-while-editing timing; ColorPicker + Stepper 3/3 alone), `--native` 9/9.
- After step 3 (m3 5d878b5): 27.0 preferred 173 / 13 / 18, `--forced` 163 / 3 / 38, `--uikit` 159 / 6 / 38; 17.5 preferred 183 / 3 / 18,
  `--forced` 164 / 1 / 38 (17.5 `testControlsUsable`, fixed by row 4). Base cc4be69 27.0 preferred 149 / 19 / 5. The m3 and base failures were
  launch / accessibility timeouts under load plus the known reds; the tip lanes above replace them.
- Skipped: a full UI baseline on main other than 27.0 preferred (other configs attributed by re-running failures alone, and base 18.5 Sheet).
Usage: not measured in this session.
