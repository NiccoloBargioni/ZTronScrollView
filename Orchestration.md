# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-10-18 · Status: **M0 done · MC package + spike done (freeze BLOCKED on a decision) · M1 done · M2 done · M3 design + (a) done, (b) partial → next: finish (b) catch test/17.5, then (c)**

## Resume in a new session (cheapest path)
1. Launch in `/Users/admin/Documents/ZTronScrollView` with the role's model (SPEC O2, l.897–918):
   Builder `claude --model sonnet --advisor opus`, Architect `claude --model fable`. One model per session.
2. Read **only**: this file → the "Next steps" item you're doing → the files *it* names. `CLAUDE.md` loads by
   itself. Never read `docs/SPEC.md` whole: `grep -n '^## [SOF][0-9]' docs/SPEC.md` gives line ranges.
3. Don't re-run green suites to "check"; trust the table below and run only what you touch.
4. Before stopping: tick the step here, add `docs/progress/M<n>-s<k>.md` (TEMPLATE.md), update `docs/progress/STATE.md`, commit.

## State (all verified 2026-10-18 on Xcode 27.0)
| Milestone | State | Proof |
|---|---|---|
| M0 setup | done | Part III files (CLAUDE.md, scripts/, .claude/, docs/progress/) |
| MC package | done | `scripts/test-arbitration.sh` → 39 tests / 4 suites green, iOS build clean, 0 warnings |
| MC spike | done | `Packages/ScrollArbitration/Spike` ran on 27.0 / 26.5 / 18.6 / 17.5; results + notes A–E in `docs/design/MC-contract.md` §6 (l.361–); handoff `docs/progress/MC-spike.md` |
| MC freeze (tag 1.0.0) | **blocked** | Q3 = NO on iOS 17.5 → user decision (see Open items #1); also iOS 15/16 + Xcode 26.6 runs (user) |
| M1 physics | done | `scripts/test-physics.sh` → 99 tests / 16 suites green |
| M1 availability | done | `scripts/test.sh -only-testing:ZTronScrollViewTests` → 16 tests green (iPhone 18 Pro, iOS 27.0) |
| M1 design note | done | `docs/design/design-note.md` (S14.1), `docs/design/M1-physics.md` |
| M2 design | done | `docs/design/M2-render.md` (decisions R1–R7, test list §11, device risks §12) |
| M2 (a) state/reader | done | `Sources/ZTronScrollView/State/` · 41 tests green (iOS 27.0) · handoff `docs/progress/M2-s1.md` |
| M2 (b) render path | done | `Sources/ZTronScrollView/Render/` + root view · 56 tests green on both OS paths (iOS 27.0) · handoff `docs/progress/M2-s2.md` |
| M2 (c) demo + UI render proof | done | `Demo/ZTronScrollViewDemo.xcodeproj`, `scripts/test-demo-ui.sh` · 6 UI tests green on iOS 27.0 + 17.5, preferred + forced · handoff `docs/progress/M2-s3.md` |
| M3 (a) pan session + release + state | done | `Sources/ZTronScrollView/Gesture/{PanSession,ReleasePipeline}.swift`, state additions, `ZTronScrollPhaseReader` · 90 unit tests green (27.0, both paths), demo proof 6/6 · handoff `docs/progress/M3-s1.md` |
| M3 (b) adapter + demo | partial | coordinator/adapter/observer/env/gate/demo in; 27.0 simultaneous UI 6/7 (catch test open); 17.5 + forced not run · `docs/progress/M3-s2.md` |
| M3 (c) arbitration | partial | unit done (docs/progress/M3-s3.md); demo pager + UI test todo |
| M3 build … M10 | todo | |

Commits: `1aa3321` M0 · `21ae371` MC package + M1.

## Where things are
- Contract: `Packages/ScrollArbitration/Sources/ScrollArbitration/` (Rules, ReferenceScrollArbiter, LogEntry,
  Environment). S16 API exactly, plus additive A1–A5 (MC-contract.md §1): public `ScrollArbitrationInput.init`,
  `ReferenceScrollArbiter.init(pagingAxis:directionTolerance:coordinateSpaceName:)`, `log`/`clearLog()`,
  `participant(at:)` + `containerOwner(ofDragFrom:translation:touchCount:)`, `isSequenceActive`/`currentOwner`.
- Physics: `Packages/ZTronScrollPhysics/Sources/ZTronScrollPhysics/` — `Decay`, `CriticalSpring`, `RubberBand`,
  `VelocityTracker`/`PointVelocityTracker`, `AxisGeometry`/`AxisBounds`/`AxisInsets`, `AxisMotion` +
  `ReleaseSolver`/`ReleaseContext`, `BounceBehavior`/`BounceConfiguration`, `PagingSolver`, `TargetSnapping`,
  `FlingAcceleration`, `ZoomLimits`/`ZoomGeometry`/`ZoomSolver`/`ZoomMotion`, `PixelSnap`, `RestThresholds`.
  Formulas and units: `docs/design/M1-physics.md` §1–5.
- Availability: `Sources/ZTronScrollView/Availability/` — `ZTronCapability` (one case per S3 row + min OS),
  `ZTronAvailability` resolver with DEBUG-only force-fallback switch. Test helper running both OS paths:
  `Tests/ZTronScrollViewTests/Support/OSPath.swift`.

## Decisions (keep)
- D1 Naming map in CLAUDE.md (ZoomScroll → ZTronScroll, `ztronScroll…` modifiers; matches ZTronPages' `ztronPage()`).
- D2 Package, module and main type are all `ZTronScrollView`, at `/Users/admin/Documents/ZTronScrollView`.
- D3 `swift-tools-version: 6.0`, Swift 6 mode, code kept Swift-6.0-compatible so Xcode 26.x builds iOS 15/16.
  iOS-27-SDK-only symbols go behind `#if compiler(>=6.4)` + `#available(iOS 27, *)` (see `ZTronCapability.isInBuildSDK`).
- D4 ScrollArbitration stays a **path** dependency; freezing = git tag `ScrollArbitration-1.0.0` here. Moving to
  its own repo is a user action.
- D5 Parallel agents never commit; whoever orchestrates commits after verification.
- D6 `scripts/test.sh` / `test-spike.sh` run xcodebuild **without** `-quiet` (it hides Swift Testing results).
  Parallel xcodebuilds must each pass `-derivedDataPath .build/dd-<name>` (scripts forward extra args).
- D7 Arbiter semantics (MC-contract.md §3): `beginSequence()` snapshots "moving at touch-down" for every
  participant + container; repeated begin = no-op; `owner()` outside a sequence decides afresh, uncached.
  Spike uses **one ReferenceScrollArbiter per page** (page-local coordinate space).
- D8 `ScrollBounceBehavior` converts one way only (ours → SwiftUI's); the env value can't be read back without
  reflection → `ztronScrollBounceBehavior(_:axes:)` carries ours (S8 parity gap, documented in design-note.md).
- D9 `onGeometryChange` capability = iOS 16 only for the `(newValue)` overload; the `(old, new)` overload is iOS 18.

## Next steps (in order; kickoff prompts are ready to paste)
Done so far (details in the State table + handoffs): M2 design (Fable) · MC spike (Sonnet) · M2 (a)(b)(c) (Sonnet;
M2 render proof green on iOS 27.0 + 17.5, preferred + forced: 0 `content.body` during animated and `withAnimation`
scrolls, clock idle at rest — counters in `docs/progress/M2-s3.md`).
The MC spike prompt is in git history (`git show 1faa1f0:Orchestration.md`) if the contract changes and it must re-run.

1. [x] **M3 design** — done: `docs/design/M3-pan.md` (§12 = orchestrator resolutions of its open questions). Covers the pan state machine, gestures, release pipeline, catch, delegate +
   phase order, phase reader, pager participant, test list, and a split into builder sessions (a/b/c).
2. [ ] **M3 (b) finish** — Debugger (`claude --model opus --effort high`, SPEC O2 escalation: gesture flakiness):
   ```
   Debug only. Problem: PanUITests.testCatchDuringDecelerationDoesNotFireButton fails on iOS 27.0 (preferred,
   simultaneous mode): Button fires and the fling isn't stopped; pan.catch = 0 but pan.movingAtEvent = 1.
   Repro: scripts/test-demo-ui.sh 'id=897F9D8D-B10D-4D91-8E22-417A2B9D70AA' -only-testing:ZTronScrollViewDemoUITests/PanUITests
   Evidence/tried: docs/progress/M3-s2.md "Open" (read the pan.ev.* counters first; then try the DragGesture(min 0)
   observer via -ZTronForceAllFallbacks; consider a slower demo fling; XCUI waits for quiescence before taps).
   Fix the root cause with the smallest patch + keep the test strict. Then run PanUITests on 27.0 --forced and on
   17.5 (id=7279872B-2799-489C-8D6F-03B4829B6737) both paths; record the working gesture mode per OS in M3-s2.md.
   Keep ZTronScrollViewTests (90) and the M2 proof (6) green. Reply in ≤10 lines.
   ```
3. [ ] **M3 (c) arbitration** — Builder (Sonnet + Opus advisor) with the kickoff template below, part (c) of
   `docs/design/M3-pan.md` §10 (uses §12 resolutions; arbitration type names are FingerDirection/ScrollOwner/…).
   Builder kickoff template (any milestone part):
   ```
   M<n> · part (<x>) · Builder
   Read: docs/design/M<n>-*.md (all), the latest docs/progress/M<n>-s*.md handoff, docs/SPEC.md sections the
   design names (by line range). Nothing else up front.
   Do: part (<x>) exactly as the design assigns it, with unit tests on both OS paths
   (scripts/test.sh -only-testing:ZTronScrollViewTests) and demo UI tests via scripts/test-demo-ui.sh <dest> [--forced]
   on iOS 27.0 (id=897F9D8D-B10D-4D91-8E22-417A2B9D70AA) and 17.5 (id=7279872B-2799-489C-8D6F-03B4829B6737).
   Commit at every green state. Done when: tests green; handoff docs/progress/M<n>-s<k>.md; Orchestration.md State
   row updated. Budget ~1–2% weekly. 2 failed attempts → advisor once → stop and hand off.
   ```
4. [ ] M4 zoom (Fable design doc first, then Builder) → M5 rotation/resize (Architect on Fable, one session: design + implement) → M6–M10 per
   SPEC O4 (l.970–990). Write a Fable design doc before each milestone; it is nearly free on the all-models bucket.

M2 leftovers to fold into M3: public phase reader (then add the skipped `phaseReaderOnTransitionsOnly` UI test);
confirm iOS 27.0 *preferred* really uses Observation storage (its counters equal the forced path's); fps +
`clock.lagFrames` not measured yet; offsets not clamped to bounds until M3; `xcodebuild` lingers ~minutes after UI runs.

## Open items
1. **DECISION NEEDED (user): spike Q3 = NO on iOS 17.5** (MC-contract.md §6 note E). When the SwiftUI page attaches
   a recognized `DragGesture`, the hosting view's `UIKitGestureRecognizer` takes the touch and the UIKit paging pan
   fails before `gestureRecognizerShouldBegin` runs, so a `.container` answer can't move a UIScrollView pager on
   iOS ≤ 17. (18+ is fine via gesture names: Q1/Q2/Q4/Q5 yes on 18.6/26.5/27.0; Q4 Δ = 0.00 pt everywhere.)
   Options: (a) ZTronPages fallback on 15–17 — the pager is driven by a SwiftUI pan (or its own recognizer
   outside the hosting view) and the participant ends its drag when `owner(...)` says `.container`; no API change.
   (b) contract revision before 1.0.0 (e.g. an additive hand-off callback). Spike suggests (a). Don't tag
   `ScrollArbitration-1.0.0` until decided; then also run iOS 15/16 + Xcode 26.6 (user).
   Other spike notes: touchesBegan on the UIScrollView is swallowed by hosting views (spike uses a never-recognizing
   observer recognizer, note A); the container's first ask can carry < 10 pt translation so rule 1 near 30° is
   noisy (40° row recorded, 55°/90° asserted, note B); on 18.6 an unnamed `UIKitResponderGestureRecognizer`
   reaches `.began` during taps → ZTronPages rule 5 should key on the arbiter's answer, not recognizer state
   (note D); 26.5 page-1 rows unverified (harness: `-startPage 1` ignored in that run).
- Minor review leftovers (M1): `AvailabilityTests.minimumOSTableMatchesSDK` only cross-checks two hand-kept
  tables (doesn't read the SDK); `public enum ZTronScrollPhysics` shares the module name, and top-level names like
  `Velocity`/`Decay` are generic (consider a rename before M2 depends on them).
- MC design open questions (for ZTronPages): does it host its pager through a Representable (if so, add that
  configuration to the spike)? One arbiter per page or one in pager space? `ZTronPages.swift` lives in
  `/Users/admin/Documents/ZombieTron/ZombieTron/ZombieTron/Utils/Pages/`.
- User actions: push ScrollArbitration to its own repo and tag 1.0.0, then switch both projects to
  `.upToNextMinor(from: "1.0.0")`; run `scripts/test-arbitration.sh` and the spike on Xcode 26.6 / iOS 15–16;
  device checks (ProMotion, gesture feel).

## Environment (verified)
Xcode 27.0 (27A266a), Swift 6.4, macOS 27, 8 cores / 24 GB (run ≤2 simulators at once). Runtimes: iOS 17.5,
18.0–18.6, 26.0–26.5, 27.0; iOS 15/16 runtimes can't run on this host. Default `ZS_DEST`: iPhone 18 Pro, iOS 27.0.
`jq` present; no xcodegen/tuist/gh/tmux.

## Cost notes (read before choosing how to work)
- 2026-10-18: Sonnet builders cost ~0–1 pt per part (80–140 K tokens each); MC spike ~2 pts (139 K, long sim runs).
  UI-test debugging is where sessions run long (M3 (b): 99 min) — cap it with the 2-attempt rule, escalate to Debugger.
  Orchestrator polling every 10–15 min was negligible. This is the cheap way to run the rest of the plan.
- 2026-10-14: one ultracode workflow (11 Opus/Fable agents, 1.64 M subagent tokens, 55 min) built MC + M1 and
  exhausted the weekly limit during its last fix agent. Don't fan out builders: follow SPEC O2 routing (Sonnet
  builds, Fable designs, Opus debugs) and O5 (workflows only for parity/demo batches, small, exemplar first).
- Separate "Weekly · Fable" bucket exists on this plan: Fable design work did not move the all-models % (2026-10-18).
  So run every Architect step on Fable (O2) — it is the cheapest place for thinking-heavy work right now.

## Session log
| Date | Session | Work | Weekly % |
|---|---|---|---|
| 2026-10-14 | Opus 5.5 ultracode #1 | M0; MC package; M1 (workflow) | → 100% (limit hit) |
| 2026-10-18 | Opus 5.5 #2 (orchestrator) | recovered MC/M1; M2 + M3 designs (Fable); MC spike; M2 (a)(b)(c), M3 (a)(b-partial) (Sonnet) | 72% → 76% |
