# ORCH-s1 handoff · 2026-10-20 · Fable 5.1 · max (side session M8b-s0 resumed by the user as orchestrator)
Status: done — Orchestration step 3 (full demo UI re-run) complete; D27 decided; N-a bookkeeping added; nothing left running.
Changed:
- docs/design/M6-targets.md: "Orchestrator resolutions (2026-10-20)" for the M6-s1 handoff's open items (target space, R4 velocity via a session-3 UI test,
  the 27.0 forced duplicate-copy quirk as a Debugger item, proxy first-match accepted for now, conversions/lazy/warnings noted).
- Orchestration.md: D27; N-a state row; step-4 pointer (Open 1 decided); open items 6–8; step 3 ticked with results; M4 (b) row closed; totals; cost note;
  session log. docs/progress/STATE.md current line + M4 row; usage-log row. No library or demo code.
Decisions:
- D27 Scroll-target space = SwiftUI's at one conversion point (`decideTarget`): rect origin = offset + adjusted inset start, container = unobscured size,
  landing −= inset start; public `.paging` by the unobscured length (SwiftUI), the `isPagingEnabled` knob by the viewport (UIKit); identical with zero insets.
- The live M6 s1 session kept its work (my debugger stopped without edits when it found the session active); it landed 7243121/f92f6b4 with 275/275 unit on both simulators.
Step 3 results (HEAD 5eca9a7, two runners in parallel, derived data `.build/dd-ui27` / `.build/dd-ui175`):
- iOS 27.0 preferred: 42/42 executed green (Image 4, Proof 6, Pager 1, Zoom 7, Resize 13, Pan 7; Calibrate 4 skipped by design), ~9 min.
- iOS 27.0 forced: 42/42 green; `PagerUITests.testPagerArbitration` passed (the unexplained 27.0 --forced failure of `M4-s2.md` is gone), ~9 min.
- iOS 17.5 preferred: 41/42; only `PagerUITests.testPagerArbitration` "swipe at the trailing edge pages" (0 vs 1) = known spike Q3 = NO on iOS ≤ 17, ~7 min.
- iOS 17.5 forced: same single known failure; 16 min wall because xcodebuild waited 600 s "collecting diagnostics from simulator" after the last suite.
Open:
- Open item 1 (user): spike Q3 on iOS ≤ 17 decides the 17.5 pager case and the MC freeze.
- Open item 6: 27.0 + forced fallbacks duplicate the content copy on a parent re-evaluation for a frame (M6-s1 Open 3) — one Debugger session.
- Open item 8: N-a has no handoff; N-b (demo `NestedPagerScreen` + UI tests) and the SPEC amendment pending.
- M6-s1 Open 2 (R4 native velocity units) → session 3 UI test; Open 4 (proxy first-match order on 27.0) → session 3 demo comparison.
- Untracked `scripts/cowork-runner.sh` belongs to nobody known; left alone.
Next: 1. Step 4: M5 (b) remainder (PanCoordinator resize rebase, adjusted insets into pan/pinch env) or go straight to M6 (b) session 2 (ViewAligned in the
D27 space; Sonnet builder, kickoff template in Orchestration.md). 2. Debugger session for open item 6 (Opus, high). 3. N-b + NESTED SPEC amendment.
4. M8b-1/-2 (Sonnet) after M6 s1 (done) — M8b-3 (Fable) and M8-8 (after M7 s1) from the amended docs.
Tests: demo UI as above; `ZTronScrollViewTests` 275/275 on 27.0 + 17.5 (M6 s1 session, f92f6b4); physics 111, arbitration 39 unchanged. Nothing run on a device.
Usage: weekly all-models 25% → 36% · Fable 49% → 68% (this resume) · cache hit n/a · context 40% of 1 M.

## Addendum (2026-10-20, 03:00–05:05): fan-out coordination and integrated verification
- Four sessions worked in this checkout at once (M6 s2, DBG-s1, M8b-1, N-b) plus M6 s1 implementing D27; coordinated by message: file ownership, path-scoped commits
  (`git add <paths>` / `git add -p`, temporary index for shared files), simulator split (27.0 vs 17.5) and separate derived data. One collision (M6 s1 vs M6 s2 on the
  pipeline files) was resolved by sequencing: D27 first (96671ed), session 2 on top (612b068). The user confirmed D27 (4409aca).
- Landed: M6 s2 612b068/1fc8e3f; DBG-s1 b528880 (+ c13a12f, f985f95), open item 6 resolved; M8b-1 refresh engine (handoffs 8b20900, 99c9034); N-b 19361e1 + D30 d5813bd +
  5e2ac33; D29 677dd60 (user report, pinch hand-off guard).
- Integrated verification at f985f95 (tree clean): `ZTronScrollViewTests` 349/349 (31 suites) on 27.0 (`.build/dd-u27`) and 17.5 (`.build/dd-u175`); demo UI full suite
  55 executed + 4 skipped per run: 27.0 preferred 55/55 (12.5 min), 27.0 forced 55/55, 17.5 preferred 54/55, 17.5 forced 54/55 — the single failure is the known
  `PagerUITests.testPagerArbitration` (Q3 on iOS ≤ 17). `NestedPagerUITests` 13/13 in all four; `ProofUITests.testNoClockTicksAtRest` green everywhere (DBG-s1's fresh-simulator
  failure was a device artifact); ZoomUITests/PanUITests green with D29.
- Infra: `test-runner` (haiku) refuses scripts other than the four in its definition → demo UI runs go through `general-purpose` with the exact script; `run-filtered.sh`
  writes its summary only at the end (progress is in `$TMPDIR/ztronscroll-log.*`); xcodebuild spends up to 600 s collecting diagnostics after a failed 17.5 run; two runner
  agents were cut off by the 5-hour limit but their xcodebuild processes finished and the logs were read directly.
- Usage: all-models 36% → 44%, Fable 68% → 79%. Next: step 4 from a Sonnet orchestrator session (M5 (b) remainder, M6 s3, M8b-2/-3, M8-8 after M7 s1); M8-1 is running from the parent session.

