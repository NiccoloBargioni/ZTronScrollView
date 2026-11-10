# M8b-cost-fold handoff · 2026-11-10 · Opus 5.5 · workflow fixer and closer
Status: done with open items. The D76 cost rounds' tip-line results are folded (steps 1-3), the fold review's three confirmed
findings are handled (F1 fixed, F3 fixed, F5 a message count only), and the full hosted and demo UI suites ran at HEAD. NOT
folded: HT6 (its ScrollTo row is red) and the D76 engine. Branch `claude/cool-stonebraker-0015c9`, not merged, not pushed.
Range: 4e47af8 → 1f11bfb (5 commits) + this docs commit. Recipe: side-session notes `m8b-s8-resume/d76-magnified.md` §17.5.
Decisions: F1 is fixed by moving the warm change, not by dropping it: the warm-up keeps its C2 purpose, and the drawing leaves
take no warm state. F2 rides on the same fix (same structure, no row possible: item 64). F5 is a commit-message count, so it
is recorded here, not rewritten in history. Usage: not read.

## What was folded
| commit | what |
|---|---|
| 0ce0213 | cost4-T (§16.5 item 1). The D11 hit-testing halves are leaves of their own outside the layer groups (`ContentHitGate` above the transform host's geometry modifiers, `HeaderHitGate` outside the header's layer group), so a phase edge no longer re-configures the content's or the header's drawn layers. `FirstUseWarm` (new file), the frame clock's warm tick, `HeaderTranslation.animatableData = live.effectData`, the HeaderUITests header-button catch row. |
| 6dfc6f4 | D11 narrowed (ruling 16.11.1, as a fix): `.disabled` only while a drag is recognized; hit-testing unchanged. InteractionGateTests (hosted), InteractionGateUITests, PressScrollHook and the PanScreen / HeaderScreens hooks; SPEC S6 "Touch during motion" and the S4 table ("of a drag"); Orchestration D11. |
| 0d796b1 | cost5-A, exactly `git diff c19ea29 dc0e8fb -- Sources Tests`: cuts 1, 2, 4 (a stored `objectWillChange`, `ContainerHooks`, the `headerSlotsAttached` latch), the fixed cut3 (`RefreshHooks` / `RefreshHookValues` on an always-present leaf, two RefreshIndicatorTests), A2 (`PanGestureMode.current`, `PinchGestureAdapter.dragFollow` as static lets). F5: the message says 13 classes, the diff stores `objectWillChange` in 14 (`git grep -n 'Stored (cost4-A)'`); none has a `@Published` field, and `IndicatorController.isShown` sends in `willSet` as `@Published` did. |
| 7a89524 | Fold review F1, fixed (below). |
| 1f11bfb | Fold review F3, fixed: `InteractionGate.hitBlocked` / `.disabled` are the one definition that all four gate leaves read, and InteractionGateTests checks them. The content's hit predicate is no longer an inline copy that no test reached. No behaviour change. |

The D11 look change (intended, ruling 16.11.1): controls in the content and the header no longer render disabled during a
deceleration or an app-animated scroll (pan rows, banner and profile header Buttons, any content Button or Toggle that moves
without a finger). They still never fire from a catch: hit-testing is unchanged. A press that began before an app-animated
`scroll(to:)` fires on lift, as in a UIScrollView. Nothing changes at rest (A2: 0 px).

## F1: the warm-up drew an app's appear-time animation (fixed, 7a89524)
- Cause: `FirstUseWarm`'s zero-duration `withAnimation` ran in `TransformHost` and `HeaderFrameModifier` themselves. SwiftUI
  runs the inner appear actions first, so the warm's update re-ran those leaves after the app's own `onAppear` had already
  moved the state. An appear-time `withAnimation { scroll(to:) }` was therefore drawn in the warm's transaction: the content
  jumped to the target, and the phase went `.idle` at the first frame on both paths (the CompletionObserver attached its
  completion to the zero-duration animation).
- Fix: the warm change lives in leaves of its own that draw nothing. `ContentWarmLeaf` sits in `FrameClockDriver`'s
  background and carries its own `ContentTransform` (`warmOnly`: identity, no probe, no counters). `HeaderWarmLeaf` sits in
  the header frame leaf's background and builds its own `HeaderFrameChain` from an input without metrics. The slot-size
  note skips a slot without metrics. The drawing leaves no longer hold any warm state.
- Regression test: `FirstUseWarmTests.anAppearTimeAmbientScrollRunsItsDuration` (both paths). On 27.0 it is red on 0d796b1
  (idle y = 600 at 0.05 / 0.30 / 0.60 s) and green on the tip 4e47af8 and on 7a89524; it is also green on 17.5 at HEAD.
- F2 (the header leaf's half, unconfirmed): it has the same structure, and the same fix moves it. There is no appear-time
  header row, because a header row cannot be written: an appear-time `scroll(to:)` under a scaling header is dropped on every
  build since the tip (new open item 64).
- Not re-measured: C2's first-pull cost with the warm in leaves. The C2 lever on 27.0 p is HT6 anyway (not folded). Round 6
  re-measures both together.

## Tests at HEAD 1f11bfb (private clones: iPhone 18 Pro 27.0 set to light, a new iPhone 15 Pro 17.5)
Hosted, `scripts/test.sh` with no `-only-testing`:
- **27.0: 933 tests / 91 suites, 34 issues (11 known); load 1.7 → 50.**
  - Red: item 44 (q0.5, both paths), item 54 (forced), the load-flaky `anAnimatedWidthChangeAtHalfCoverKeepsTheParallax`
    (bodies), and `ContentAnimationTickTests.rowChangeTicks` preferred `.slideBehind`: 4 cases stalled at uval 5-10.
  - `rowChangeTicks` is the known stall class (M8b-s8-s8.md "Open", item 34's rig stall), present since 9e23270.
- **17.5: 933 / 91, 24 issues (8 known); load 50 → 3.4.**
  - Red: item 44, item 54 (both paths), `rowChangeTicks` preferred `.slideBehind` (stall), and two extra rows:
    - `HeaderStretchContentTests.aSwitchDuringAFingerPullKeepsTheSeam` p (4 unsynced frames against a bound of 3);
    - `HeaderFittingContentTests.aStretchingHeaderFollowsRowChangesAcrossTheKink` p `.keepTextSize` (19 moving frames
      against a bound of 20).
  - Those four suites re-run alone on 17.5 (41 tests) are 41/41 on HEAD and 41/41 on 0d796b1. So the two extra rows are
    order- or load-flaky, not a fold regression.
- Last full runs, for comparison: ee0eaed (918 tests; 27.0 2 failures = item 44, 17.5 5) and the builder at 0d796b1 (932;
  only 44, 54 and the parallax row). The +1 test function is FirstUseWarmTests (+15 since ee0eaed: InteractionGate,
  RefreshIndicator, FirstUseWarm).
- `HeaderStretchScaleTests.aStretchHoldKeepsTheScaleAcrossAnAnimatedWidthChange` `.keepTextSize` was red in two 2-suite runs
  (FirstUseWarm + HeaderStretchScale) on 27.0. It was red on 0d796b1 (both paths) and on 7a89524 (preferred), green on the
  tip, 0ce0213 and 6dfc6f4 when run alone, and green in both full runs at HEAD and in the 7-suite runs. It is order-dependent;
  folded into item 65.
- Touched suites per step (27.0 and 17.5, 41 tests / 7 suites): only item 44 red.

Demo UI, full suite (`scripts/test-demo-ui.sh`, no `-only-testing`), under the machine lock:
- **27.0 (light clone): 207 tests, 5 skipped, 0 failures** (3335 s, load 22.7 at the start).
- **17.5: 207, 5 skipped, 2 failures = the 2 known**: `PagerUITests.testPagerArbitration` (the Q3 pager case) and
  `PanUITests.testControlsUsable` ('Text' after typeText; see Open). 2562 s, load 17.5.
- **27.0 forced (`--forced`): 207, 25 skipped, 0 failures** (2938 s, load 22.9).
- Compared with ee0eaed (186 per lane, 17.5 the same 2 known): +21 tests per lane (InteractionGateUITests, the HeaderUITests
  catch row and the rows added since); no new red.

## NOT folded
- HT6 (cost5-C): `State/ScrollStateTypes.swift` drawn sink; `State/ZTronScrollState.swift` scroll(to:) feed, `drawnTick`,
  `armDrawnFeed`, `startAnimating(clock:)`; the LayoutHost / Proxy / ScrollTo / TargetPresentation test rewrites
  (b5fc769 / a2933de).
  - Its red row: `ScrollToTests.hostedScrollToAnimatesOnlyInsideWithAnimationAndNeverRunsContentBodies`, red on 27.0 and 17.5,
    both paths (an ambient `withAnimation` scroll never reaches 600 / idle; §17.2 C4).
  - HT6V carried the in-place warm-up, so F1's mechanism (an ambient scroll drawn in the warm's transaction) is a candidate
    cause. Re-run that row on HT6 rebased onto 7a89524 first.
- The D76 engine (E) and every §17.2 E2 scope-gate hit; the scratch labs (AppearLab, CostLab, DemoApp CostScreenDelay /
  costnative / applab cases, SeamLabScreen CostLab lines).

## Open
- Item 60, C2: passes on 27.0 p D/R and on 17.5 D/R only WITH HT6, which is not folded. It fails 27.0 f at n. The warm leaves
  are not measured.
- Item 62, appear: cost5-A's cuts are folded, and the appear still fails against native on every lane measured (27.0 p cold
  zt 66.3 vs 31.1 ms, 17.5 D cold zt 36.9 vs 34.8). Closing it needs the container's distinct types cut by about 3-4x.
- Item 64 (new): an app's appear-time `withAnimation { scroll(to:) }` under a scaling header is dropped (the content stays at
  rest, phase idle). Seen on the tip, 0d796b1 and HEAD, both paths, 27.0.
- Item 65 (new): order-dependent header rows in full or partial runs (above): aStretchHold `.keepTextSize` (27.0),
  aSwitchDuringAFingerPull and aStretchingHeaderFollowsRowChangesAcrossTheKink (17.5). They pass alone on HEAD and on 0d796b1.
- PanUITests.testControlsUsable on 17.5: pre-existing ('no keyboard focus' on the tip, 5/5). With D11 narrowed, the field
  sometimes gets focus, and XCUI then reports the app non-idle for 60 s. Unclassed (review F4, unconfirmed).
- Real iOS 15 / 16: unmeasured (§17.8 checklist).

## Next (round 6)
1. HT6: rebase it onto 7a89524, root-cause its red ScrollTo row (check F1's mechanism first), fold it, and re-measure C2 on
   27.0 p, 27.0 f and 17.5 with the warm leaves.
2. The 15-16 path's normal-speed start frame (27.0 f n fails: HT6V r0 4.9 ms against NT 4.78).
3. The engine: rebase E onto the tip (its base is 36 Sources commits old), then the start row and fast p95. Pending user
   answers: the §17.7 criteria changes (16 valid pairs, NT r0 per batch, "final tree only") and the fittingScroll draft.

Tests: the hosted full runs and lane logs are in the side-session notes `m8b-s8-resume/d76-fold/` (full/, r175-*, f1*, bis-s*,
uifull/), with timestamped notes in PROGRESS.md.
