# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-10-18 (session 2 end, weekly 88%) · Status: **M0–M4 done · physics calibrated (unit) · M5 rotation:
ZTronMapKit geometry ported, still FAILS the user's full-screen tree → fix it first (step 1)** · MC freeze blocked (user decision).
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
| M4 (b) pinch adapter + demo | done* | pinch adapter, double tap, ZoomScreen, ZoomUITests 6/6 on 27.0 pref+forced, 17.5 pref; full-suite 27 forced / 17.5 forced pending (`M4-s2.md`) |
| M5 design | done | `docs/design/M5-resize.md` (+ orchestrator resolutions C1–C3, Q1–Q3 at the end) |
| M6–M9 designs | done | `docs/design/{M6-targets,M7-observation,M8-chrome,M8b-refresh-header,M9-virtualization}.md`, each ending with "Orchestrator resolutions" (read those first) and a builder-session split with file ownership + sequencing |
| M5 (a) state + render | done | `docs/progress/M5-s1.md`: ResizeMath/Commit, TransformHost above layout host (C1 gate: Proof 6/6, demo UI 20/20 on 27.0), 134 unit tests on 27.0 + 17.5 |
| User scenario s1 | done | D15: zoom-enabled pan moves on any axis the zoomed content exceeds; demo `-ZTronScreen image` + `ImageUITests` 4/4 on 27.0 + 17.5, preferred + forced (`docs/progress/USER-s1.md`) |
| M5 (b) gestures + demo | partial | `docs/progress/M5-s2.md` s3: D17 ZTronMapKit geometry verbatim (`CenterGeometry`) + sticky `resizeIntent`; unit round trips exact; screen-space UI tests added (markers): 16:9 tree even rotations exact (0.05 pt), user's full-screen tree FAILS (reflow lands idle, `cidle`>0) — fix in `setContentSize` idle path next; (C) pinch-end probe test added, not run; PanCoordinator rebase still todo |
| M6 … M10 | todo | SPEC O4 l.970–990 |

Test totals now: `ZTronScrollViewTests` **118** green on iOS 27.0 and 17.5 (both OS paths) · M2 `ProofUITests` 6/6 ·
physics 99 · arbitration 39. Designs: `docs/design/{design-note,M1-physics,MC-contract,M2-render,M3-pan,M4-zoom}.md`.

## Next steps (in order; prompts are ready to paste)
1. [ ] **Rotation centre in the user's full-screen tree (criteria A+B)** — Fable builder (D16), main checkout (the user's
   ZTronTesting app compiles this tree live via `../ZTronScrollView`: keep it building at every step):
   ```
   Fix the visible-centre bug for -ZTronResizeUserTree2 (user's exact full-screen tree). Read docs/progress/M5-s2.md
   section s3 first (measured errors + diagnosis): the reflowed content size lands while no resize is open, so the
   idle .sizeChanges path in ZTronScrollState.setContentSize moves the view and the sticky resizeIntent is realised
   from the wrong start. Fix: realise resizeIntent (ResizeMath.realize / CenterGeometry, verbatim ZTronMapKit) on the
   idle reflow too, or capture it before an idle reflow; fix the test's visibleCentre (double-counted safe-area
   insets). Acceptance = screen-space ResizeUITests (markers via XCUIElement.frame): odd rotations keep the marker
   under the visible centre ≤1 pt; 2×/4× rotations restore every marker ≤0.5 pt and zoom exactly; 27.0 + 17.5,
   preferred + --forced. Never touch /Users/admin/Documents/ZTronMapKit (snapshot: scratchpad ztronmapkit-ref/).
   ```
2. [ ] **Pinch-release animation (criterion C)** — run `ZoomUITests/testPinchInsideLimitsReleasesWithoutMotion`
   (added, never run); suspects: `handOffToPan` synthesized pan on first-finger lift, the bounce-back spring/kick from
   `dff908b`. No motion allowed when zoom and offset are in range.
3. [ ] Re-run the full demo UI suite after the physics commits (`dff908b`, `9091f20`) on 27.0 + 17.5, both paths;
   PagerUITests "trailing edge pages" still fails on 27.0 --forced and 17.5 (`M4-s2.md`).
4. [ ] M5 (b) remainder (PanCoordinator resize rebase, adjusted insets into pan/pinch env) → M6–M9 builds from the
   ready designs (`docs/design/M6…M9`), M10. Sequencing per each design's resolutions.

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

## Session log
| Date | Session | Work | Weekly % |
|---|---|---|---|
| 2026-10-14 | Opus 5.5 ultracode #1 | M0; MC package; M1 (workflow) | → 100% (limit hit) |
| 2026-10-18 | Opus 5.5 #2 orchestrator | recovered MC/M1; M2–M9 designs (Fable); MC spike; M2–M4 builds; M5 (a); zoomed-axes + user image demo; physics calibration (Fable); ZTronMapKit re-centering port (Fable, user tree still failing) | 72% → 88% |
