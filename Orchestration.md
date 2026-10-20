# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-10-20 05:05 (side session M8b-s0 acting as orchestrator: step 3, D27 and the integrated verification of the fan-out green at f985f95; weekly all-models 44% ·
Fable 79%; 2026-10-19 session 3 + s3-C ended at 20% · 39%) · Status: **M0–M4 done ·
physics calibrated (unit) · M5 rotation: user full-screen tree PASSES criteria A+B on 27.0 + 17.5 (D18/D19) · criterion C
fixed in code (D20, staggered lift; probe + ZoomUITests 7/7 on 27.0 pref+forced, 17.5 pref) · user bounce report fixed
(D21, pixel-rounded effect size: 16:9 trees drew clamped + stayed `.animating`) · double-tap snap (D22) and
one-finger-lift snap (D23) fixed · programmatic zoom calibrated against native (D22 final, `ZoomTiming`), user device
checks DONE on the device (C, D21, D22, D25) · pinch overscroll rubber band (D24) · step 3 DONE 2026-10-20 (demo UI 42/42 on 27.0
both paths; 17.5 both paths green except the known Q3 pager case) · M6 (a) + N-a done → next = step 4** · MC freeze
blocked (user decision). **M8b/M8 designs amended 2026-10-19 per the user's three decisions (side session M8b-s0, D26): M8b-3 and
M8-8 build from the amended SPEC S9/S10/S11 + `docs/design/M8b-refresh-header.md` §2–3 + `M8-chrome.md` §7b.**
## Resume in a new session (cheapest path)
1. Launch in `/Users/admin/Documents/ZTronScrollView` with the role's model (SPEC O2, l.897–918): Builder
   `claude --model sonnet --advisor opus`, Architect `claude --model fable`, Debugger `claude --model opus --effort high`.
   One model per session.
2. Read **only** this file, then the step you're doing and the files *it* names. `CLAUDE.md` loads by itself.
   Never read `docs/SPEC.md` whole: `grep -n '^## [SOF][0-9]' docs/SPEC.md` gives the line ranges.
3. Don't re-run green suites to "check": trust the State table and run only what you touch.
4. Before stopping: tick the step, add `docs/progress/M<n>-s<k>.md` (TEMPLATE.md), update the State row here and
   `docs/progress/STATE.md`, then commit.

## State (verified 2026-10-18, Xcode 27.0)
| Milestone | State | Proof / where |
|---|---|---|
| M0 setup | done | Part III files: CLAUDE.md, scripts/, .claude/, docs/progress/ |
| MC package | done | `scripts/test-arbitration.sh` → 39 tests, iOS build clean |
| MC spike | done | `Packages/ScrollArbitration/Spike`, run on 27.0/26.5/18.6/17.5; results in `docs/design/MC-contract.md` §6 |
| MC freeze (tag 1.0.0) | **blocked** | Open item 1 (user decision), then iOS 15/16 + Xcode 26.6 runs (user) |
| M1 physics + availability | done | `scripts/test-physics.sh` → 99 tests; design note `docs/design/design-note.md` |
| M2 render path + proof | done | 0 `content.body` during animated + `withAnimation` scrolls, clock idle at rest, on 27.0 + 17.5, preferred + forced (`docs/progress/M2-s3.md`) |
| M3 (a) pan state + release | done | `Gesture/{PanSession,ReleasePipeline}.swift`, delegate, `ZTronScrollPhaseReader` (`M3-s1.md`) |
| M3 (b) gestures + demo | done | catch fixed; fling acceleration on the state clock (D14). iOS <18 catch observer is now gated (`CatchArming`: attached only while content moves or a seen touch is down), so UIKit controls work on 17.5. PanUITests 7/7 on 17.5 and 27.0, preferred and forced; demo UI 14/14 on 27.0 |
| M3 (c) arbitration | done | participant + 9 unit tests; demo pager stand-in (`PagerScreen`, ReferenceScrollArbiter) + `PagerUITests` green on 27.0; demo now links ScrollArbitration (`M3-s3.md`) |
| M4 (a) zoom state + PinchSession | done | `Gesture/PinchSession.swift`, `zoomRange`, solver-based `setZoomScale` (`M4-s1.md`) |
| M4 (b) pinch adapter + demo | done | pinch adapter, double tap, ZoomScreen; ZoomUITests **7/7** on 27.0 pref+forced, 17.5 pref (2026-10-19, after D20); criterion C staggered-lift fix in PanCoordinator (`M4-s3.md`, 6 new unit tests × 2 OS paths); step 3 re-run 2026-10-20: full suite green on 27.0 both paths and on 17.5 both paths except the known Q3 pager case (`ORCH-s1.md`) |
| M5 design | done | `docs/design/M5-resize.md` (+ orchestrator resolutions C1–C3, Q1–Q3 at the end) |
| M6–M9 designs | done | `docs/design/{M6-targets,M7-observation,M8-chrome,M8b-refresh-header,M9-virtualization}.md`, each ending with "Orchestrator resolutions" (read those first) and a builder-session split with file ownership + sequencing; **M8b amended 2026-10-19** (user decisions: refresh single source, `withScalingHeader` header preceding the content with `.preserve`/`.stretch`, delegate modifiers → SPEC S9/S10/S11/S14, M8b §2–3, M8-chrome §7b/M8-8; `docs/progress/M8b-s0.md`) |
| M5 (a) state + render | done | `docs/progress/M5-s1.md`: ResizeMath/Commit, TransformHost above layout host (C1 gate: Proof 6/6, demo UI 20/20 on 27.0), 134 unit tests on 27.0 + 17.5 |
| User scenario s1 | done | D15: zoom-enabled pan moves on any axis the zoomed content exceeds; demo `-ZTronScreen image` + `ImageUITests` 4/4 on 27.0 + 17.5, preferred + forced (`docs/progress/USER-s1.md`) |
| M5 (b) gestures + demo | partial | `docs/progress/M5-s2.md` s4: D18/D19 — intent captured from the DRAWN geometry (turn origin), inset-only change folds into an open resize, post-resize settle window; screen-space acceptance GREEN for the user's full-screen tree AND the 16:9 tree on 27.0 + 17.5, preferred + forced (odd rotations ≤ 0.56 pt, even rotations offset/zoom exact, markers ≤ 0.17 pt); `ResizeUITests` 11/11 on 27.0 pref+forced, 17.5 11/11 preferred + jump test forced after the monitor change + 27.0 11/11 re-run; `ProofUITests` 6/6; DEBUG jump monitor counts drawn frames only; (C) probe green on 27.0 pref+forced + 17.5 pref before and after D20 (`M4-s3.md`); D21 render-path pixel tolerance (16:9 trees drew clamped and stayed `.animating`; `USER-s2.md`); PanCoordinator rebase still todo |
| M6 (a) targets exemplar | done | `docs/progress/M6-s1.md` (7243121): member + twin `scrollTargetBehavior`, type mirror (`ZTronScrollTargetBehavior` family, SDK names), `.paging` ≡ `isPagingEnabled`, `ZTronScrollViewReader`/proxy `scrollTo` (+ animation overload), `ztronScrollID` + registry (0 writes while scrolling/zooming); 79 new unit tests, unit 275/275 on 27.0 + 17.5, `ZoomUITests` 7/7 on 27.0. Open 1 → D27 implemented in 96671ed (`decideTarget` converts to SwiftUI's target space; public `.paging` pages by the unobscured container, the `isPagingEnabled` knob by the viewport; 284/284 on 27.0 + 17.5 on HEAD + those files) |
| N-a nested arbitration | done | 3e8ae26 (design `docs/design/NESTED-arbitration.md` + resolutions a30a008): `ZTronNestedScrollPolicy`, `nestedScrollPolicy(_:)` / `ztronNestedScrollPolicy(_:)`, internal `NestedScrollArbiter`; `NestedArbitrationTests` 18 on both OS paths; no handoff file (the nested session went idle after the commit). N-b (demo `NestedPagerScreen` + `NestedPagerUITests`) and the SPEC amendment follow step 3 (NESTED-arbitration.md §4); polish (review findings): D15 effective axes for the paging axis, no `@_exported` re-export, `.independent` opts out of the nested container only, public `ZTronNestedScrollContext` init, consistent three-level rig + content-space conversion test; handoff `docs/progress/NESTED-s1.md` |
| N-b nested demo | done | 19361e1 + d5813bd: `NestedPagerScreen` (`-ZTronScreen nestedPager`, `-ZTronNestedPolicy`) + `NestedPagerUITests` **13/13 on 27.0 and 17.5, preferred + forced**; found and fixed D30 (nested scroll views leaked fallback measurements to the outer: outer never scrolled on iOS 15 / forced paths); SPEC S11/S12 amendment, parity row; observed `.independent` = outer pages, image +3 pt; handoff `docs/progress/NESTED-s2.md` |
| M6 (b) targets session 2 | done | `docs/progress/M6-s2.md` (612b068): `ZTronViewAlignedScrollTargetBehavior` + `LimitBehavior`, `NativeBridges.swift`, `ztronScrollTargetLayout`, resize keeps the aligned item (M5 pagingIndex hook); `ViewAlignedTests` 16; 133/133 in the touched suites on 27.0 + 17.5. D27 itself landed in 96671ed. R5 (`.automatic` / alwaysByOne vs native) open for session 3 |
| M8b (1) refresh engine | done | `docs/progress/M8b-s1.md`: pure per-edge `RefreshEngine` + `RefreshCoordinator` (action `Task` once per pull, hold, minimum visible time on a one-shot timer), `ScrollMetrics.refreshHold` folded into `adjustedContentInset` (opened bounds-only at the lift, BEFORE the release reads the bounds, so an over-pull springs to `−(aci.top + H)`; cleared by the M5 inset rule), `beginRefreshing` / `endRefreshing`, `ReachEdgeWatcher` list on the state, axis-wide bounce force + sample / lift hooks in `PanCoordinator`; `RefreshEngineTests` + `RefreshHoldTests` + `ReachEdgeTests` (43 tests, both OS paths) and the whole unit suite (345) green on 27.0 + 17.5; NOT wired into the container yet (M8b-2); device risks R1–R3 open |
| M6 (c) … M10 | todo | SPEC O4 l.970–990; M6 (c) = session 3 (Position, DefaultScrollAnchor, TargetsScreen) |

Test totals now (integrated HEAD f985f95, 2026-10-20 05:00, after the fan-out M6 s2 + DBG-s1 + M8b-1 + N-b/D30 + D29): `ZTronScrollViewTests` **349** (31 suites) green on iOS 27.0 and 17.5 (both OS paths) · demo UI full suite **55 executed + 4 skipped by design per run**: 27.0 preferred 55/55, 27.0 forced 55/55, 17.5 preferred 54/55, 17.5 forced 54/55 (the one failure = `PagerUITests.testPagerArbitration`, spike Q3 on iOS ≤ 17, Open item 1; `ProofUITests.testNoClockTicksAtRest` green on both devices and paths, so DBG-s1's fresh-simulator failure was a device artifact) · physics 111 · arbitration 39.
physics 111 · arbitration 39. Designs: `docs/design/{design-note,M1-physics,MC-contract,M2-render,M3-pan,M4-zoom}.md`.

## Next steps (in order; prompts are ready to paste)
1. [x] **Rotation centre in the user's full-screen tree (criteria A+B)** — done 2026-10-19 (D18/D19, `docs/progress/M5-s2.md` s4):
   measured root cause (one rotation = `vp inset` → `cs idle` → `vp size` → `cs open` in ONE run-loop turn; the intent
   was captured from the half-mutated metrics), fixed by capturing from the drawn geometry (turn origin). Screen-space
   acceptance green on 27.0 + 17.5, preferred + forced, both trees. The user still has to confirm on their own app
   (ZTronTesting compiles `../ZTronScrollView`): rotate ×1…×4 zoomed on a detail; even rotations must land exactly.
2. [x] **Pinch-release animation (criterion C)** — done 2026-10-19 (D20, `docs/progress/M4-s3.md`): the probe
   (`ZoomUITests/testPinchInsideLimitsReleasesWithoutMotion`) was green on 27.0 pref+forced and 17.5 pref BEFORE any
   change (XCUITest lifts both fingers in one batch: no motion, counters 30→30 / 31→31). The staggered lift real fingers
   make had four `PanCoordinator` defects (stuck synthesized pan, fling from pinch-phase velocity, hand-off catching the
   release bounce, late/stale DragGesture jump), fixed + 6 unit tests × 2 OS paths; ZoomUITests 7/7 on 27.0 pref+forced,
   17.5 pref. Confirmed by the user on the device (2026-10-19, main ≥ 1486752).
2b. [x] **User report: bounce "does not work" in the 16:9 image tree** — done 2026-10-19 (D21, `docs/progress/USER-s2.md`):
   not the gesture/physics path (`FittingAxisBounceTests`), the DRAWN frame: pixel-rounded effect size vs unrounded
   committed viewport → every frame at rest clamped by the resize path and the launch resize never closed. Fixed with a
   1 pt tolerance in `ContentTransform.isPlainFrame` and `resizeTick`; demo `ResizeUITests` `testUserTree{Vertical,
   HorizontalAlways}…IsDrawn` + launch phase idle. Confirmed by the user on the device (2026-10-19).
2c. [x] **User reports: double-tap snap (D22) and one-finger-lift snap (D23)** — done 2026-10-19 (`USER-s2.md`).
   User check pending on both (rebuild ZTronTesting against main first). Follow-up left: pinch overscroll is linear,
   native rubber-bands it (D23).
2d. [x] **Programmatic zoom calibrated against native** — done 2026-10-19 (`USER-s3.md`, D22 final): spike `-zoomCal`
   measured UIScrollView's zoom animations (ease-in-out, duration law), `ZoomTiming` replaces the progress spring;
   native fixtures in `NativeCalibrationTests`. Confirmed by the user on the device (2026-10-19): double tap in/out native.
2e. [x] **Pinch overscroll rubber band + didZoom cadence** — done 2026-10-19 (D24, `USER-s4.md`): two-finger slide past an
   edge resists like a one-finger drag, hand-off continuous; didZoom per frame kept by SPEC (documented).
2h. [x] **Second finger down again during the continuation (D29)** — done 2026-10-20 (`USER-s4.md` addendum D29): the old
   magnify gesture's cumulative magnification re-armed the pinch with base 1 at the re-touch; the first sample is the base
   now, and a release after a hand-off is held until the observer confirms a lift or two fingers (coordinator guard).
   Unit-tested both OS paths (XCUITest cannot stagger fingers); full suite 349/349 in a clean worktree. User device check pending.
2f. [x] **Snap at the lift, from the user's video (D25)** — done 2026-10-19 (`USER-s4.md` addendum): the magnify gesture's
   trailing `.changed` after the observer's hand-off re-armed the pinch with base 1 (2× → 4× in one frame). Ignored now.
   **Confirmed by the user on the device (2026-10-19, main 1486752): lifting one finger during the pinch and dragging no
   longer snaps.** The user also confirmed on the device (2026-10-19): the 16:9 bounce (D21), the double tap in and out
   (D22) and criterion C all look native. Side session s3-C closed: nothing of it is pending on the user.
2g. [x] **M8b amendment (design only, side session M8b-s0, Architect)** — done 2026-10-19: the user's three decisions landed in SPEC S9/S10/S11/S14,
   `docs/design/M8b-refresh-header.md` §2–3 (rewritten) and `docs/design/M8-chrome.md` §7b + task M8-8: refresh API single source = S9's `refresher`;
   `ZTronScrollView.withScalingHeader(size:scalingBehavior:snap:fade:) { header in … }` with the header preceding the content (also above a
   horizontal view) and `.preserve` / `.stretch`; every UIScrollViewDelegate method as an `onZTronScroll…` modifier. Header geometry reaches
   children through `ZTronHeaderProxy` + `ZTronHeaderGeometryReader` (reader tier), not an ObservableObject (D26). A1–A10 at the end of the M8b design
   **approved by the user (2026-10-19)**, with two constraints: keep `.refresher { action }` (default loader) and `.refresher(refreshView:action:)`
   as spelled (S9 "Mandatory shapes"), and no introspection anywhere (S2; the S10 mention is the reference's technique). No library or demo code.
   Handoff `docs/progress/M8b-s0.md`.
3. [x] **Full demo UI suite re-run** — done 2026-10-20 at 5eca9a7 (`docs/progress/ORCH-s1.md`): 27.0 preferred 42/42 and 27.0 forced 42/42
   (the earlier 27.0 --forced pager failure of `M4-s2.md` did not recur); 17.5 preferred and forced 41/42 each, the only failure
   `PagerUITests.testPagerArbitration` "swipe at the trailing edge pages" = the known spike Q3 = NO on iOS ≤ 17 (Open item 1, user
   decision). CalibrateUITests' 4 tests skip by design. Two test-runner subagents in parallel, one simulator each, separate derived data
   (`.build/dd-ui27`, `.build/dd-ui175`): ~9 min per run on 27.0, 7–16 min on 17.5 (a 600 s "collecting diagnostics" timeout inflated the forced run).
3b. [x] **Integrated verification after the 2026-10-20 fan-out** — done at f985f95 (`docs/progress/ORCH-s1.md` addendum): unit 349/349 on 27.0 and 17.5; demo UI 55 executed per run,
   27.0 preferred + forced 0 failures, 17.5 preferred + forced only the known Q3 pager case; `NestedPagerUITests` 13/13 everywhere; ZoomUITests/PanUITests green with D29. Two test-runner
   agents were cut off by the 5-hour limit mid-run; the xcodebuild processes finished on their own and the logs were read directly.
4. [ ] M5 (b) remainder (PanCoordinator resize rebase, adjusted insets into pan/pinch env) → M6–M9 builds from the
   ready designs (`docs/design/M6…M9`), M10. Sequencing per each design's resolutions.
   M6 (a) done 2026-10-20 (`docs/progress/M6-s1.md`, 7243121), D27 in 96671ed, M6 (b) done 2026-10-20 (`docs/progress/M6-s2.md`, 612b068) → next = M6 (c) session 3 (Position, DefaultScrollAnchor, TargetsScreen; R5). M8b-1 done 2026-10-20 (`docs/progress/M8b-s1.md`) → next in the M8b split: M8-1 (`ChromeLeaf`), M8b-2 (refresher API, indicators, demo; wires the coordinator into the container), M8b-3.
5. [ ] **UIKit touch observer for iOS 15–16 (D31)** — after the M6/M7/M8 sessions have committed: session (a) Sonnet builder
   `docs/design/UIKIT-touch-observer.md` §builder split (core `Gesture/UIKit/TouchObserverCore.swift` + `TouchObserverCoreTests`
   100 %, `ZTronCapability.uikitTouchObserver`, state let); then (b) shell + wiring + `UIKitObserverUITests` + the two gate
   scripts, coverage chased to 100 % on 27.0 and 17.5 with `-ZTronForceUIKitObserver`; (c) docs. The user answers the design's
   open questions first (overlay filter, pencil, MagnificationGesture kept, ForceAllFallbacks on device, hook/CI, cancel route).

**Builder kickoff template** (any part):
```
M<n> · part (<x>) · Builder
Read: docs/design/M<n>-*.md (all), the latest docs/progress/M<n>-s*.md handoff, the docs/SPEC.md ranges the design
names. Nothing else up front.
Do: part (<x>) exactly as the design assigns it, with unit tests on both OS paths
(scripts/test.sh -only-testing:ZTronScrollViewTests) and demo UI tests via scripts/test-demo-ui.sh <dest> [--forced]
on iOS 27.0 (id=897F9D8D-B10D-4D91-8E22-417A2B9D70AA) and 17.5 (id=7279872B-2799-489C-8D6F-03B4829B6737).
Commit at every green state. Done when: tests green; handoff docs/progress/M<n>-s<k>.md; State row updated.
Budget ~1–2% weekly. 2 failed attempts → advisor once → stop and hand off.
```

## USER ACCEPTANCE CRITERIA (2026-10-18, verbatim — check these before calling M5/M4 done)
- (A) "Rotating any even amount of times should bring me back to the exact initial contentOffset and scale, if no
  action was performed between rotations."
- (B) Preserve the visible centre "using ZTronMapKit geometry, that does that perfectly" (port of
  `ContentGeometry.normalizedCenter` / `contentOffset(normalizedCenter:…)`, D16; never edit ZTronMapKit).
- (C) "When magnification gesture ends it does a weird animation" — must not.
- (D) Physics must feel like native UIScrollView: calibrated against native ScrollView on 27.0 (`dff908b`,
  `docs/design/PHYSICS-calibration.md`); pinch-then-pan with two fingers must behave like UIScrollView (`9091f20`).
- User's real view tree for rotation: `ResizeScreen -ZTronResizeUserTree` (NavigationStack + GeometryReader + 16:9 box
  + both axes + zoom 1…4). The user tests on their own app; demo results alone don't close these.

## Open items
1. **DECISION NEEDED (user): spike Q3 = NO on iOS 17.5** (MC-contract.md §6 note E). Once the SwiftUI page's
   `DragGesture` recognizes, the hosting view's recognizer takes the touch and a UIKit paging pan fails before
   `gestureRecognizerShouldBegin` runs, so a `.container` answer can't move a UIScrollView pager on iOS ≤ 17.
   iOS 18+ works via gesture names (Q1/Q2/Q4/Q5 yes on 18.6/26.5/27.0; start-point Δ = 0.00 pt).
   Options: (a) ZTronPages fallback on 15–17: drive the pager with a SwiftUI pan (or a recognizer outside the
   hosting view) while the participant drops the drag on `.container` — no API change; (b) revise the contract
   before 1.0.0 (e.g. an additive hand-off callback). The spike suggests (a). Don't tag until decided.
2. Spike notes for ZTronPages: hosting views swallow `touchesBegan` (use a never-recognizing observer recognizer);
   the container's first ask can carry < 10 pt so rule 1 near 30° is noisy; on 18.6 an unnamed
   `UIKitResponderGestureRecognizer` reaches `.began` on taps, so key rule 5 on the arbiter's answer. Does ZTronPages
   host its pager through a Representable? One arbiter per page or one in pager space? (`ZTronPages.swift`:
   `/Users/admin/Documents/ZombieTron/ZombieTron/ZombieTron/Utils/Pages/`).
3. Not measured yet: fps / `clock.lagFrames`, 120 Hz on device; confirm 27.0 *preferred* really uses Observation
   storage (its counters equal the forced path's); `phaseReaderOnTransitionsOnly` UI test still to add.
4. Minor: `AvailabilityTests.minimumOSTableMatchesSDK` only cross-checks two hand-kept tables; the
   `ZTronScrollPhysics` enum shares its module's name and top-level names (`Velocity`, `Decay`) are generic.
5. User actions: push ScrollArbitration to its own repo + tag 1.0.0, then switch both projects to
   `.upToNextMinor(from: "1.0.0")`; iOS 15/16 + Xcode 26.6 runs; device checks (ProMotion, gesture feel).
6. ~~27.0 + all fallbacks forced: a second copy of the content on a parent re-evaluation~~ RESOLVED 2026-10-20
   (`docs/progress/DBG-s1.md`): gesture/completion paths were chosen in bodies from the process-wide switch
   (`CatchObserver.usesSpatial` → `CatchArmingProbe`'s `if let` around the content), so a re-evaluation outside the
   test's `withOSPath` scope flipped the branch on 18+. Now `let` flags on `ZTronScrollState` (R6). App/real 15–16
   never flipped (the set is fixed at launch). New open: `ProofUITests.testNoClockTicksAtRest` red on a fresh 27.0
   simulator at fd3d17a with and without the patch (DBG-s1 Open).
7. ~45 UIKit "Observation tracking feedback loop detected" warnings in the full 27.0 unit run since M6 s1 (none on 17.5, none per suite alone): re-check
   after M7 session 1 (hub); suspect the hosted test windows, not the library.
8. N-a/N-b handoffs: `docs/progress/NESTED-s1.md`, `NESTED-s2.md` (N-b done 2026-10-20; SPEC S11/S12 amendment + parity row written). Still open: user device check of the pager + zoomer on `.innerWhenZoomed` incl. a second finger landing during an outer-owned drag (not scriptable in XCUITest), ZTronPages adoption (R6), three-level phase 2.

## Decisions (keep)
- D1 Naming map in CLAUDE.md (ZoomScroll → ZTronScroll, `ztronScroll…` modifiers; matches ZTronPages' `ztronPage()`).
- D2 Package, module and main type are all `ZTronScrollView`.
- D3 `swift-tools-version: 6.0`, Swift 6 mode, Swift-6.0-compatible code so Xcode 26.x builds iOS 15/16; iOS-27-SDK
  symbols behind `#if compiler(>=6.4)` + `#available(iOS 27, *)` (`ZTronCapability.isInBuildSDK`).
- D4 ScrollArbitration is a **path** dependency; freezing = git tag `ScrollArbitration-1.0.0` here.
- D5 Parallel agents never commit; the orchestrator commits. Parallel xcodebuilds pass `-derivedDataPath .build/dd-<name>`.
- D6 `scripts/test.sh`, `test-spike.sh`, `test-demo-ui.sh` run xcodebuild without `-quiet` (it hides Swift Testing results).
- D7 Arbiter semantics: `beginSequence()` snapshots moving-at-touch-down; our participant keeps
  `isMovingWithoutFinger` sticky until the decision (works under either order). With an arbiter, `.tracking` waits
  for the owner decision; without one it fires at touch-down (native).
- D8 `ScrollBounceBehavior` converts one way only → `ztronScrollBounceBehavior(_:axes:)` carries ours (S8 gap).
- D9 `onGeometryChange`: iOS 16 for the `(newValue)` overload only; `(old, new)` is iOS 18.
- D10 Render path: transform host wakes only on the `.target` channel (presentation writes never wake it); the
  fallback layout host uses `Color.clear.overlay(alignment: .topLeading)`, not a flexible frame.
- D11 Content hit-testing gate = `allowsHitTesting(false)` **and** `.disabled(true)` while moving without a finger,
  dragging or catch-locked (`allowsHitTesting` alone doesn't cancel an in-progress Button press).
- D12 Default gesture mode is `.simultaneousGesture` (27.0: `high` breaks Button/Slider). DEBUG launch arg
  `-ZTronPanGestureMode gesture|simultaneous|high`; `-ZTronForceAllFallbacks` forces the 15–16 paths.
- D13 Default zoom range is 1…1 (UIKit); zoom bounce phase is `.decelerating`; content centers when zoom is enabled.
- D14 Gesture event times (`DragGesture.Value.time`, spatial events) are on a different clock from the state clock
  (uptime-based on iOS 27). Use them only for deltas *inside* the velocity tracker; anything compared with or
  scheduled on the state clock uses `state.now()`.
- D15 With zoom enabled (max > min) the pan moves on any axis where the zoomed content exceeds the viewport, even if
  it isn't in `axes` (Photos-like; UIScrollView has no axes). `axes` still drives layout proposal and the pan when
  content fits. Such an axis bounces like `.basedOnSize`. Implemented in `PanEnvironment.effectiveAxes` (PanCoordinator).

- D18 (2026-10-19) The resize intent is captured from what was DRAWN, never from metrics mutated earlier in the same
  run-loop turn: `TurnOrigin` (snapshot + presentation) is remembered before the first idle geometry mutation of a turn
  and a viewport size change later in that turn captures from it (and interpolates from it). `endOfTurn()` is one
  `DispatchQueue.main.async` hop (Foundation; tests call it directly). An inset-only change while a resize is open folds
  into the commit instead of closing it. Measured need: SwiftUI delivers one rotation of a safe-area-dependent tree as
  several updates in one turn, the first ones with no resize open.
- D19 (2026-10-19) Post-resize settle window of 3 run-loop turns after `closeResize()`: idle content/inset changes inside
  it re-realise the sticky intent (ZTronMapKit "restore on every bounds change"; covers the M5 §9 slow reflow); outside
  it the D16 growing-list rule applies and the stale sticky intent is dropped at end of turn (an app action between
  rotations breaks criterion A on purpose). DEBUG `resize.jumpFrames` counts drawn frames (last evaluation of a turn).
- D20 (2026-10-19) Pinch release with a staggered lift (18+): after `handOffToPan(remaining:)` the pan's release
  velocity comes ONLY from the remaining finger's samples since the hand-off (tracker reset, the DragGesture's own
  `velocity` ignored): one finger of a spread is not a pan, UIScrollView never flings out of a pinch; a lift within
  `restDistance` (1 pt / 64 ms) rests, ≥ 1 pt/frame is a one-finger pan and decelerates per the calibrated physics.
  A synthesized pan (DragGesture dead) ends on `touchesEnded` (its release, from the last synthesized translation).
  A release bounce keeps owning the offset until settled; the hand-off feeds no touch-down meanwhile (it would catch =
  cancel the bounce) and the pan restarts where the finger is after the settle (travel during the bounce not replayed).
  A DragGesture appearing under a synthesized pan rebases (no jump); its `dragEnded` arriving under one is stale
  (the lifted finger's) and is dropped. `docs/progress/M4-s3.md`.
- D21 (2026-10-19, user report "bounce does not work in the 16:9 image tree") SwiftUI hands the transform effect and
  the presentation probe a PIXEL-ROUNDED container size (288.0) while the committed viewport is the unrounded layout
  size (288.125 = 402·9/16 + 62 pt bar). Two exact comparisons (0.01 pt) therefore never matched in such trees:
  `ContentTransform.resolved` sent every frame at rest down the resize path, whose result is clamped (no rubber band or
  bounce could be DRAWN on any axis with any behavior although the state rubber-banded), and `resizeTick` never saw
  the resize settle (a launch-time size change stayed open: `.animating` at rest, clock running, presentation = the
  clamped probe frame, content not hit-testable). Rule: within `ContentTransform.pixelTolerance` (1 pt) on size and
  insets IS the committed geometry; a real resize moves by far more. `docs/progress/USER-s2.md`; DEBUG draw-path
  counters `transform.fast/slow/slowClosed/clampedAtRest` + notes; demo `-ZTronResizeBounceAlways`.
- D22 (2026-10-19, user report "double tap animates, then snaps") Programmatic zoom (`zoom(to:animated:)`,
  `setZoomScale(_:animated:)`, double tap) follows native: UIKit's fixed-duration ease-in-out (Bézier 0.42, 0, 0.58, 1)
  on scale and offset alike, `duration = min(0.40 s, 0.125 + 0.19·(zoom ratio − 1))`, symmetric, model scale set at
  once (`ZoomTiming` in ZTronScrollPhysics). Measured on iOS 27.0 with the spike's `-zoomCal` UIScrollView screen (21
  cases; a critically damped spring misses by rms ≥ 0.09, the ease-in-out fits within 0.008). The bug was the progress
  spring settled by point thresholds read as progress (≈ 50 % after ≈ 150 ms, then the end values at once).
  `docs/design/PHYSICS-calibration.md` "Programmatic zoom", `docs/progress/USER-s3.md`.
- D23 (2026-10-19, user report "one-finger lift: ugly snap") A one-finger lift (18+) bounces only a scale past its
  limit; an out-of-bounds offset stays with the pan that continues from the remaining finger (rubber band; its release
  springs back), as UIScrollView does — springing the offset back under a finger still down was the snap. No pan
  taking the finger → the coordinator starts the offset bounce. Non-bouncing axes are clamped under a pinch
  (`PinchEnvironment.bouncesX/Y`). The adapter turns a magnify end with one finger still down into the hand-off event
  (delivery order no longer matters). 15–17 unchanged (no finger count there).
- D24 (2026-10-19) Under a pinch the offset past an edge is rubber-banded per bouncing axis with the pan's band
  (`c` 0.55, `d` viewport; UIScrollView's pan recognizer treats one and two touches alike — not drivable by XCUITest, the
  one-finger measurement is the reference), clamped on a non-bouncing axis; `bouncesZoom` concerns the scale only. The
  hand-off inverts the same band (continuity). `didZoom` stays per frame by SPEC l.41 / M4 §6 (native fires once: its
  `zoomScale` is the model); documented in `docs/design/PHYSICS-calibration.md`. `docs/progress/USER-s4.md`.
- D25 (2026-10-19, user video) After the observer's one-finger hand-off, the magnify gesture's trailing `.changed`
  (cumulative magnification of the ended gesture) is ignored until its `.ended` (`PinchSession.gestureEndPending`); it
  used to start a new session at the current scale with base 1 and multiply it again — the one-frame jump 2× → 4× at
  the lift seen in the recording (frames 0.97 → 0.98 s), the original "ugly snap". `USER-s4.md` addendum.
- D26 (2026-10-19, user amendment, design only — `docs/progress/M8b-s0.md`) Scaling header API = one member
  `ZTronScrollView.withScalingHeader(size: .fixed(min:max:) | .aspectRatio(_:min:) | .fit(min:), scalingBehavior: .preserve | .stretch,
  snap:, fade:) { header in … }` returning `Self` (builder type-erased; no `ZTronScalingHeaderScrollView`, no forwarding file). The header
  PRECEDES the content: its resting height is reserved in `adjustedContentInset.top`, it is drawn in the viewport overlay with its top edge
  pinned, also above a horizontal scroll view (a fixed banner there). Collapse = shrink from the bottom; `.stretch` grows by the rubber-banded
  overscroll, `.preserve` leaves a gap below the header. Live geometry = the TransformHost pattern: a `ViewModifier` leaf on the `.target`
  channel applies an animatable `frame(height:)` to the header placeholder (lockstep with the content transform under transactions; the
  header body is never re-evaluated). Children read it ONLY through `ZTronHeaderGeometryReader(header, of:)`, the existing reader tier over
  `ZTronScrollGeometry.header`; `ZTronHeaderProxy` exposes no geometry, so a hot read in the builder's scope is impossible. Rejected: an
  ObservableObject / @Observable `headerGeo` (object-wide invalidation on 15–16, no derived gating, builder-scope hazard). Refresh API single
  source = S9's `refresher`; every UIScrollViewDelegate method also an `onZTronScroll…` modifier (M8-chrome §7b, task M8-8 on M7's hub:
  delegate first, then modifiers in application order; `willEndDragging` target threaded; `shouldScrollToTop` ANDed).
- D27 (2026-10-20, M6-s1 Open 1, measured in `NativeBridgeTests`; **confirmed by the user 2026-10-20 as implemented in 96671ed: public `.paging`
  pages by the unobscured container like SwiftUI, only the `isPagingEnabled` knob keeps viewport-length pages**) Scroll-target space = SwiftUI's: a behavior sees `rect.origin = contentOffset +
  adjustedContentInset.start` (content coordinates; the inset includes the safe area, the scaling header's resting height and the refresh hold) and
  `containerSize = rect.size = unobscured size`; `ReleasePipeline.decideTarget` is the single conversion point (landing `−= I.start`, velocity cap on the
  unobscured length). Public `.paging` pages by the unobscured length (SwiftUI); the `isPagingEnabled` knob keeps the viewport page length (UIKit) through an
  internal paging behavior; both coincide with zero insets (M3 table unchanged). `docs/design/M6-targets.md` resolutions 2026-10-20. **Implemented in 96671ed** (M6-s1 addendum).
- D28 (2026-10-19/20, NESTED-arbitration R1–R7 + review) Nested `ZTronScrollView`s arbitrate by default (`.automatic` =
  inner while it can follow, UIScrollView parity); `.innerWhenZoomed` is the user's literal rule (outer iff zoom == min);
  the policy only replaces rule 5 inside the participant's `canFollow`, the frozen ScrollArbitration rules do the
  rest (internal `NestedScrollArbiter` wrapping `ReferenceScrollArbiter`, named space on the outer's content).
  `.independent` opts out of the nested container only (an external ZTronPages arbiter is still joined); a
  scroll-disabled or axis-less outer is never a container; the paging axis is the outer's D15 effective axis; no
  Binding API (`.custom` gets a non-tracked `ZTronNestedScrollContext`); no mid-gesture hand-off in v1.
- D29 (2026-10-20, user report "second finger again on screen during the one-finger continuation → snappy animation")
  A pinch session begun by the observer (two fingers reported while the magnify gesture has not begun anew) takes its
  magnification base from its first `.changed` sample instead of 1: SwiftUI's MagnifyGesture ends only when all its
  touches end, so after a re-touch the OLD gesture reports its cumulative magnification and the current scale was
  multiplied by it in one frame (D25's family). `USER-s4.md` addendum D29. Guarded too: a release after a hand-off is held until the
  observer confirms a lift (`touchesEnded`, released from the current time) or two fingers (dropped, the pinch takes over),
  so a DragGesture ending at the second landing before the count change no longer flings.
- D30 (2026-10-20, found by N-b `NestedPagerUITests`, `NESTED-s2.md`) Fallback measurements are per scroll view: on the fallback path (iOS 15, or
  `onGeometryChange` unavailable / forced) `ContentSizeKey` and `ViewportMetricsKey` preferences propagate to every ancestor, so an inner
  `ZTronScrollView` overwrote its container's content size and viewport (outer `ocw` 300 instead of 900: it fit its content and never scrolled, even under
  `.independent`). `MeasurementIsolation` (one `transformPreference` pair per scroll view, outside its receivers) clears both keys for ancestors.
  Red→green: `LayoutHostTests.nestedScrollViewMeasurementsDoNotLeakToTheOuter` on the forced path; demo matrix 6/12 red → 13/13 green; unit 279/279 on 27.0 + 17.5. Nesting on real
  iOS 15/16 was broken until this.
- D31 (2026-10-20, user) SPEC S2 amended: UIKit is allowed only on iOS 15–16, only to observe raw touches, only in
  `Sources/ZTronScrollView/Gesture/UIKit/` (`#if canImport(UIKit) && os(iOS)`, runtime `#unavailable(iOS 17)` or DEBUG
  `-ZTronForceUIKitObserver`): a never-recognizing `UIGestureRecognizer` on the window, installed by a zero-size
  representable at the viewport origin, filtered to the viewport, feeding the existing `PanEvent`/`PinchEvent` stream in
  SpatialCatchGesture's order (touch-down at rest, live centroid, count, magnification from the two touches;
  MagnificationGesture kept for recognition only), so D20/D23/D25/D29 work on 15–16 unchanged. iOS 17 stays pure
  SwiftUI with its documented divergences; 18+ keeps SpatialEventGesture. Gates (user: 100 % coverage of the UIKit
  code): `scripts/coverage-uikit.sh` (100 % line coverage of that directory, union of the unit run and the forced demo
  UI run) + `scripts/check-uikit-scope.sh` (grep), before any commit touching it and at milestone end. Does not touch
  Open item 1. Design `docs/design/UIKIT-touch-observer.md` (open questions at its end); starts after the M6/M7/M8
  sessions commit; ≈ 3–3.5 Sonnet builder sessions.
- D16 (user, 2026-10-18) Physics and the post-rotation re-centering are generated and tested by **Fable 5.1**
  (builder agents with model fable). Re-centering ports ZTronMapKit's normalized-centre discipline
  (ContentGeometry: capture before resize, restore = centre × newContentSize − newViewport/2, clamp, centre smaller
  axes, refit on every bounds change). **Never edit /Users/admin/Documents/ZTronMapKit**; agents read only a
  read-only snapshot (scratchpad `ztronmapkit-ref/`; recreate it with `cp` + `chmod a-w` if the scratchpad is gone).

## Environment
Xcode 27.0 (27A266a), Swift 6.4, macOS 27, 8 cores / 24 GB (≤ 2 simulators at once). Runtimes: iOS 17.5,
18.0–18.6, 26.0–26.5, 27.0; iOS 15/16 can't run on this host. `xcodebuild` can linger after UI runs
(`pkill -f "xcodebuild.*ZTronScrollViewDemo"`). `jq` present; no xcodegen/tuist/gh/tmux.

## Cost notes (read before choosing how to work)
- Fable has its own weekly bucket, but Fable *builders* at high effort also draw on all-models: two in parallel moved
  all-models ~3 pts per 15 min (81 → 84). Design docs on Fable are cheap; run at most one Fable builder at a time.
- Sonnet builders: ~0.5–1 all-models point per part (75–145 K tokens). UI-test debugging is where sessions run long
  (M3 (b): 99 min) — enforce the 2-attempt rule and escalate to the Debugger.
- 2026-10-14: one ultracode workflow (11 Opus/Fable agents, 1.64 M tokens) used the whole remaining weekly budget.
  Don't fan out builders; follow SPEC O2/O5.
- 2026-10-20 05:00: the same session then coordinated four concurrent sessions (M6 s2, DBG-s1, M8b-1, N-b) by message and ran the integrated verification
  (2 unit + 4 demo UI runs): Fable 68% → 79%, all-models 36% → 44% in ~2 h; two runners died at the 5-hour limit. Fable is now the scarce budget: hand the
  orchestration of builds/verification to a Sonnet session and keep Fable for design and physics only. `test-runner` (haiku) may run only the four
  scripts in its definition; demo UI runs need `general-purpose` with the exact `scripts/test-demo-ui.sh` command.
- 2026-10-20: orchestrating step 3 (4 demo UI runs through test-runner subagents) + D27 + bookkeeping from the Fable M8b-s0 session with a
  ~400 K context cost Fable 49% → 68% in one evening (all-models 25% → 36%, the Sonnet M6 s1 session included). Verification-only steps
  belong in a Sonnet session; keep Fable for design and the hard physics.
- 2026-10-19: lean ultracode works: 3 sequential workflows (measure 1 agent → fix+verify 4 → follow-ups+verify 3; one
  Fable builder at a time, review and the two simulators in parallel) = all-models 7% → 10%, Fable 13% → 18%
  in ~3 h (predicted 9–11 all-models points; actual 3). One fix+verify workflow (Fable builder xhigh 38 min + Fable review + 2 Sonnet test runners,
  457 K subagent tokens) ≈ +2 all-models / +4 Fable points. Measure the event order before fixing: it cost 1 agent and
  made the fix land on the first attempt.

## Session log
| Date | Session | Work | Weekly % |
|---|---|---|---|
| 2026-10-14 | Opus 5.5 ultracode #1 | M0; MC package; M1 (workflow) | → 100% (limit hit) |
| 2026-10-18 | Opus 5.5 #2 orchestrator | recovered MC/M1; M2–M9 designs (Fable); MC spike; M2–M4 builds; M5 (a); zoomed-axes + user image demo; physics calibration (Fable); ZTronMapKit re-centering port (Fable, user tree still failing) | 72% → 88% |
| 2026-10-19 | Fable 5.1 #3 side session s3-C | criterion C: probe green (3 configs); staggered-lift fix D20 (PanCoordinator), PinchPanTests 15, ZoomUITests 7/7 ×3; user reports → D21 (pixel-rounded effect size: ContentTransform + resizeTick tolerance), D22 (zoom animation = native ease-in-out, spike `-zoomCal` calibration, ZoomTiming), D23 (hand-off overscroll), D24 (pinch overscroll rubber band, didZoom cadence kept), D25 (lift snap = trailing magnify sample, from the user's video); unit 178 on 27.0 + 17.5, physics 111; ResizeUITests 13/13 (27.0), ZoomUITests + overscroll green on both | all 10% → 20% · Fable 18% → 39% |
| 2026-10-19/20 | Fable 5.1 #3 orchestrator (cont.), ultracode ×3 | NESTED-arbitration design (own session) + resolutions; N-a build + adversarial review + polish (D28); PanUITests flake attributed to concurrent M6 edits | all 10% → 36% · Fable 18% → 69% (all sessions) |
| 2026-10-19 | Fable 5.1 #3 orchestrator, ultracode ×3 | measured the rotation event order; D18/D19 turn-origin capture + settle window; user full-screen tree passes A+B on 27.0 + 17.5; jump monitor = drawn frames; 160 unit tests | all 7% → 10% · Fable 13% → 18% |
| 2026-10-19 | Fable 5.1 #3 side session M8b-s0 (Architect, design only) | user amendment: SPEC S9/S10/S11/S14 + M8b design §2–3 rewritten (`withScalingHeader`, `.preserve`/`.stretch`, proxy + reader geometry, iOS 15 fallback, counter tests, builder split) + M8-chrome §7b/M8-8 delegate modifiers; D26; A1–A10 for the user; no code | all 20% → 25% · Fable 39% → 49% (upper bound: the orchestrator ran concurrently) |
| 2026-10-19/20 | Sonnet 5.5 side session M6-s1 (Builder) | M6 session 1: type mirror, `.paging` ≡ knob, member/twin, reader/proxy/`scrollTo`, `ztronScrollID` registry; 79 new tests; findings in `M6-s1.md` + notes folder: SwiftUI's target space, 27.0 forced-fallback content duplication (pre-existing), sibling `onAppear` order, `EnvironmentValues` retention | all ≈30% → 32% · Fable 58% → 60% (all sessions together) |
| 2026-10-20 | Fable 5.1 side session M8b-s0, resumed as orchestrator | D27 (target space, M6-s1 Open 1) + M6 resolutions; N-a state row + open items 6–8; step 3: full demo UI suite ×4 (27.0/17.5 × preferred/forced) via test-runner subagents, all green except the known Q3 pager case on 17.5; handoff `ORCH-s1.md` | all 25% → 36% · Fable 49% → 68% |
| 2026-10-20 | Sonnet 5.5 side session M8b-1 (Builder) | refresh engine: `Refresh/{RefreshTypes,RefreshEngine,RefreshCoordinator,ReachEdgeWatcher}`, hold in `adjustedContentInset`, `beginRefreshing` / `endRefreshing`, reach-edge list, `PanCoordinator` bounce force + sample / lift hooks; 43 new tests; verified in a clean worktree because other sessions were editing the pinch files in the shared checkout | all 36% → 40% · Fable 68% → 72% (all sessions together; this one is Sonnet) |
| 2026-10-20 | Opus 5.5 side session DBG-s1 (Debugger) | open item 6 root cause (body-time capability reads flip a structural branch when the forced set changes; 18+ only) → `let` flags on the state, `ParentReevaluationTests`; unit 303/303 on 27.0 + 17.5; Proof+Resize UI 27.0 both paths 18/19 (pre-existing `testNoClockTicksAtRest`) | not measured |
| 2026-10-20 (03:00–05:05) | Fable 5.1 side session M8b-s0 as orchestrator (cont.) | coordinated M6 s1 (D27 impl.), M6 s2, DBG-s1, M8b-1, N-b in one checkout by message (file ownership, path commits, simulator split); integrated verification at f985f95: unit 349/349 ×2, demo UI 55/55 ×2 on 27.0 and 54/55 ×2 on 17.5 (known Q3 case); D27 confirmed by the user | all 36% → 44% · Fable 68% → 79% |
