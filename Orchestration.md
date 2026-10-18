# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-10-18 · Status: **M0 done · MC package + spike done (freeze BLOCKED on a decision) · M1 done · M2 (a) done → next: M2 (b)**

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
| M2 (b) render path, (c) demo proof | todo | next steps in `docs/progress/M2-s1.md` "Next" |
| M2 build … M10 | todo | |

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
1. [x] **M2 design** — done 2026-10-18 (Fable, 61 K tokens = 2% of the Fable bucket, 0 pts all-models). Prompt kept for reference:
   ```
   Architect session. Write docs/design/M2-render.md (≤3 pages): ZTronScrollState storage (Observation 17+ /
   one ObservableObject per channel 15–16; hot vs cold separation), target vs presentation, frame clock driver
   (TimelineView(.animation(paused:)) → step(to:), one-frame-lag check), content layout (Layout 16+ / fixedSize
   fallback), transform host GeometryEffect + pixel snapping, presentation probe for transaction motion (how it
   publishes without mutating state during view update), coordinate spaces, ZTronScrollReader, DEBUG render
   counters, and the Demo app + UI-test target (hand-written objectVersion-77 pbxproj, local package ref) that
   proves S4's re-render tiers on both OS paths (launch arg forces fallbacks). Include the test list.
   Read: docs/SPEC.md l.58–157 (S3–S5), l.483–580 (S11), l.619–629 (S13); docs/design/design-note.md;
   docs/design/M1-physics.md §6. Reply in ≤8 lines.
   ```
2. [x] **MC spike** — done 2026-10-18 (Sonnet builder, 139 K tokens, ~2 pts weekly). Freeze is blocked: see Open items #1.
   Original prompt (for re-runs, e.g. after a contract change):
   ```
   MC · spike · Builder
   Read: docs/design/MC-contract.md §5–6 only (l.257–373), docs/SPEC.md l.846–873. Nothing else up front.
   Do: build Packages/ScrollArbitration/Spike/ArbitrationSpike.xcodeproj exactly per §5 (hand-written pbxproj,
   synchronized groups, local package ref ../..); run scripts/test-spike.sh with
   SPIKE_DEST='id=B87DE726-E502-4737-B668-3D06AAE1EFA8' (17.5), 'id=886FEBE5-8E75-416D-B17D-C964E4845163' (18.6),
   'id=106C8DF9-C3EC-43A2-B7EB-BA7BA43CBA25' (26.5), 'id=C937B8D9-6878-4FC1-9C91-0EF7CD081EFA' (27.0);
   fill §6. A "no" → propose the contract change or the ZTronPages fallback; stop and ask before changing the API.
   Done when: spike tests ran on 4 OSes, §6 filled, `git tag ScrollArbitration-1.0.0`, committed.
   Out of scope: library code. Budget ~3% weekly; 2 failed attempts → advisor once → stop and hand off.
   ```
3. [ ] **M2 build** — Builder (Sonnet + Opus advisor), 2–3 sessions; Debugger (Opus, high) only if render counts fail:
   ```
   M2 · Render path · Builder
   Read: docs/design/M2-render.md (all), docs/SPEC.md l.83–105 (S4). Nothing else up front.
   Do (one session each, commit between): (a) §1–2, §8–9 ZTronScrollState + ZTronScrollReader + unit tests §11;
   (b) §3–7 clock, layout host, transform host, probe, coordinate spaces; (c) §10 Demo project + render-proof
   screen + UI tests + new scripts/test-demo-ui.sh <destination> [--forced] (filtered, like test.sh).
   First resolve M2-render.md open questions Q1–Q5 below by taking the doc's proposal unless a test disproves it.
   Done when: unit tests green on both OS paths; UI proof green on iOS 27.0 + 17.5, preferred + forced.
   ```
   M2 open questions (from the architect): Q1 name of the transaction-driven offset setter (proposed
   `scroll(to: CGPoint)`; clashes conceptually with `proxy.scrollTo(id)`); Q2 `ZTronScrollGeometry` lazy view vs
   Equatable snapshot struct (spec: mirrors `ScrollGeometry`); Q3 `.transaction{}` + `addAnimationCompletion`
   catching model-driven `withAnimation` is unverified — 2-frame settle detector stays as safety net everywhere;
   Q4 `scripts/test-demo-ui.sh` (assumed above); Q5 whether the proof also exercises `ignoredByLayout()`.
4. [ ] M3 (pan/decay/bounce/delegate/arbitration) … M10 per SPEC O4 (l.970–990).

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
- 2026-10-14: one ultracode workflow (11 Opus/Fable agents, 1.64 M subagent tokens, 55 min) built MC + M1 and
  exhausted the weekly limit during its last fix agent. Don't fan out builders: follow SPEC O2 routing (Sonnet
  builds, Fable designs, Opus debugs) and O5 (workflows only for parity/demo batches, small, exemplar first).
- Separate "Weekly · Fable" bucket exists on this plan: Fable design work did not move the all-models % (2026-10-18).
  So run every Architect step on Fable (O2) — it is the cheapest place for thinking-heavy work right now.

## Session log
| Date | Session | Work | Weekly % |
|---|---|---|---|
| 2026-10-14 | Opus 5.5 ultracode #1 | M0; MC package; M1 (workflow) | → 100% (limit hit) |
| 2026-10-18 | Opus 5.5 #2 (orchestrator) | recovered MC/M1, M2 design (Fable), MC spike (Sonnet) | 72% → 74% |
