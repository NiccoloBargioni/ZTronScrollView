# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-11-02 (header behaviors closer on `claude/cool-stonebraker-0015c9`: D68–D70 final, handoff `docs/progress/M8b-s7.md`; our open item 24 renumbered 27; open items 27–33; next free on this branch D75 (D71 DBG-s12, D72–D74 main) and open item 34) · previous: 2026-10-20 05:05 (side session M8b-s0 acting as orchestrator: step 3, D27 and the integrated verification of the fan-out green at f985f95; weekly all-models 44% ·
Fable 79%; 2026-10-19 session 3 + s3-C ended at 20% · 39%) · Status: **M0–M4 done ·
physics calibrated (unit) · M5 rotation: user full-screen tree PASSES criteria A+B on 27.0 + 17.5 (D18/D19) · criterion C
fixed in code (D20, staggered lift; probe + ZoomUITests 7/7 on 27.0 pref+forced, 17.5 pref) · user bounce report fixed
(D21, pixel-rounded effect size: 16:9 trees drew clamped + stayed `.animating`) · double-tap snap (D22) and
one-finger-lift snap (D23) fixed · programmatic zoom calibrated against native (D22 final, `ZoomTiming`), user device
checks DONE on the device (C, D21, D22, D25) · pinch overscroll rubber band (D24) · step 3 DONE 2026-10-20 (demo UI 42/42 on 27.0
both paths; 17.5 both paths green except the known Q3 pager case) · M6 (a) + N-a done → next = step 4** · MC freeze
blocked (user decision). **M8b/M8 designs amended 2026-10-19 per the user's three decisions (side session M8b-s0, D26): M8b-3 and
M8-8 build from the amended SPEC S9/S10/S11 + `docs/design/M8b-refresh-header.md` §2–3 + `M8-chrome.md` §7b.**
## RESUME HERE (2026-11-02 14:20, M8b-3 lead session, branch `claude/cool-stonebraker-0015c9`, pushed to origin)
- State: header behaviors D68–D70 built and closed (`docs/progress/M8b-s7.md`, 55c1881); the user's rulings committed (13c46d0, see
  Next step 6 (a)). Batch **M8b-s8** was launched and STOPPED by the user during its design phase (shutdown); nothing of it was
  committed; its scratch worktrees, simulators and processes were removed. Tree clean at this commit.
- 2026-11-02 14:35: batch M8b-s8 RE-LAUNCHED from base af2e66c (script `m8b-s8-workflow-r2.js` in the folder below, already
  re-pointed). If it is no longer running and `docs/progress/M8b-s8.md` does not exist, re-run it from the start the same way.
- 2026-11-02 16:05: USER RULING D76 (Decisions): `.stretch` content becomes an enum option, default `.keepTextMagnified`,
  still to be made crisp. Workflow `d76-magnified-eval` (script `d76-eval-workflow.js` in the folder below) evaluates crisp
  magnification beside M8b-s8 (pure SwiftUI, then a scoped UIKit path; nothing of it is built before the user accepts it).
  M8b-s8 is stopped when it reaches its plan stage and resumed in the same session with `m8b-s8-workflow-r3.js` (designers
  cached; the architect, builders, reviewers and closer carry the D76 ruling). In a new session: run the evaluation script
  fresh, then r3 fresh (its designers re-run).
- 2026-11-03 10:40: USER RULING D77 (Decisions): item 29 takes the public route, route P is documented, both in M8b-s9 after
  M8b-s8 (with D76's crisp path if accepted). M8b-s8's plan is committed (febf007, 10 steps); its builders run (same run ID,
  r3). The Mac slept 2026-11-02 18:30 → 11-03 10:12 (dark wakes only) and the batch crawled; a 24 h `caffeinate` now keeps it
  awake. The plan's other questions (§9 2–5) went unanswered: their defaults are built.
- 2026-11-03 23:55: USER ACCEPTED D76's crisp path (Decisions, D76): the scoped UIKit raster engine of `d76-magnified.md` (in the
  folder below until M8b-s9 commits it under `docs/design/`; §11 = the skeptic's re-measurement, verdict "partly", its measured
  repairs folded into §5). Built in M8b-s9 with D77′; one S2 / S14 / S16 / F6 / CLAUDE.md amendment names all three scoped UIKit
  exceptions (D31, D77′, D76). Its four open gaps are closed beside M8b-s8 by workflow `d76-gaps` (script `d76-gaps-workflow.js`
  in the folder below; one spike at a time; results go to `d76-magnified.md` §12):
  - the probes' accessibility elements (D77′'s probe too);
  - one text size at ×1.29;
  - the redraw cost at large pulls;
  - 17.5's 1/255 after a release.
- How to re-run batch M8b-s8 from the start. Its workflow script (persistent copy):
  `~/Library/Application Support/Claude/side-session-notes/local_f8af3d20-fa63-46a8-9079-ddf859cc4879/m8b-s8-resume/m8b-s8-workflow.js`
  (a new session cannot resume the old run id; run the script fresh, after re-pointing its `SP` / `S8` constants to the new
  session's scratchpad and `BASE` to this commit; the old `/private/tmp` scratchpad is gone after a reboot, so its references to
  `${SP}/api/notes.md`, `${SP}/fu/suites/step.sh`, `${SP}/fu/notes.md` must point to the copies in that same folder:
  `api-notes-M8b-s7-builders.md`, `step.sh`, `fu-notes.md`; `QUEUE.md` there lists the batch contents).
- Batch M8b-s8 contents (user rulings 2026-11-02; nothing is accepted as a limit): D63 becomes an enum parameter of
  `withScalingHeader`, default = D63 (D75; D74 is SHEET's on main); FIX items 15 (b) (15–16 overflow-limited R lands in one frame,
  incl. width, F6 rows), 27 (15–16 reveal after an instant resize), 28 (`.stretch` text blur, ALL lanes), 29 (15–16 blend modes vs a
  `.slideBehind` header), 31 + 32 (`.stretch` `.system` spinner steps; proposed: centre the pull look in the band), 33 (17.5
  `.preserve` re-catch arrow over the content: triage, then fix).
- Machine rules: ONE demo UI suite at a time machine-wide via `mkdir "$(git rev-parse --git-common-dir)/ztron-ui-lane.lock"`
  (owner file, trap release); seam-lab runs go through SeamLabUITests, so they take it too; unit runs one at a time per session.
- M1 Mac (user): runs iOS 15.0 / 16.0 simulators; pending: Remote Login + an SSH connection in the Claude app + its macOS/Xcode
  versions; then a read-only verification session there on the pushed branch (fixes stay on this Mac).
- Merge notes (main moved to 71c9380+): `docs/progress/M8b-s7.md` merge section (250 pt/s release gate, BTN item 11, iOS 26+
  hosting rule, renumber open items 27–33 if main uses them).

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
| MC freeze (tag 1.0.0) | waiting (user) | Open item 1 decided 2026-10-25 (D50: option (a), no contract change); tag after the user actions of item 5 (own repo, iOS 15/16 + Xcode 26.6 runs) |
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
| M8b (2) refresher API | done | `docs/progress/M8b-s2.md`: members `refresher` ×5 (async / completion / custom view ×2 / edge-aware) + `ztronRefresher` twins + `onZTronScrollReachEdge` (twin), `RefreshResolver` (member ?? twin ?? `.refreshable` bridge, per edge, narrowed to the scrolled axes), `RefreshOverlay` (cold host, the one container hook) → `RefreshIndicatorsHost` → `RefreshEdgeIndicator` (`ChromeLeaf` on offset + metrics, alive while pulling / refreshing / retracting with the content (D39); `.system` / `.default` / `overlay` / custom `Binding<ZTronRefreshState>`), haptic 17+, named accessibility elements, demo `-ZTronScreen refresh` (8 sections) + `RefreshUITests` **11/11 on 27.0 preferred + forced and 17.5 preferred**; found and fixed a double action at the lift (`liftedThisTouch` in M8b-1's coordinator, `RefreshLiftTests`); unit **582/582** on 27.0 + 17.5; device risks R1–R3, R9, R10 open |
| M8b (3) scaling header | done (merged into main at f3ea9c7, 2026-10-27) | `docs/progress/M8b-s3.md`, branch `claude/cool-stonebraker-0015c9` (main merged in at 80e2e08): `withScalingHeader(size:scalingBehavior:snap:fade:header:)` returning `Self` (type-erased builder), `ScalingHeader/` (types, pure `HeaderMath`, spec, cold host, hot frame leaf on `.target` + `.metrics`, D11 gate leaf, `.fit` measure: `HeaderLayout` 16+ / measuring pass 15, snap, reader, API), resting height in `adjustedContentInset.top`, `.preserve` / `.stretch`, both snap modes through the M6 pipeline (compose hook after the behavior, before `willEndDragging`), refresher gap / overlay over the stretched band, inset consumers (indicators, `scrollTo` at the target, resize), D51 (a resize keeps the header's place; the M5 header term is `h − R`); demo `profile` + `banner`, `HeaderUITests` **9/9 on 27.0 and 17.5, preferred and forced**, `content.body` 0 and `header.builder` 0 in every run; device risks R4–R10 open, R5 seam under a rotation with `.aspectRatio` / `.fit` (Open 1) |
| M8b (3) seamless header | done (branch `claude/cool-stonebraker-0015c9`, main 9e60063 merged in; not merged into main) | `docs/progress/M8b-s4.md` (seam matrix), `M8b-s5.md` (review d16 fixes; section "M8b-s6 (close)"), `M8b-s6.md` (lead): D61 `.preserve` moves with the content + `ZTronHeaderBackground` (`.ambientBlur` / `.frostedGlass` / `.color` / `.view`); D62 the seamless mechanism (layout-driven `R(W, H)` with inputs bit-stable across the resize commit, slot between the safe areas, rigid layer groups, `.fit` adopted in the commit or the change's transaction, refresh indicator at the presented geometry, unclamped resize progress + safe-area steps); D63 top alignment of fitting content under a header (user to confirm); D64 the overflow container excludes the keyboard; D65 pull behaviour modifier (`.openGap` default, `.followContent` = D61). Shared fixes found by the checks: resize retargets near the drawn size (`ResizeCommit.outer`), app-animated safe-area changes, content interaction gate leaf (open item 17, pre-existing on main), refresh indicator layer group (open item 18). Seam lab (`scripts/seam`, analyzer v2.2) on 27.0 / 17.5 / forced: rotations, width / height / spring / retarget / bottom-pinned resizes, pulls, refresh holds, snaps, `withAnimation` scrolls: |seam| <= 0.67 pt, lateral <= 0.7 pt, no one-frame step; keyboard gap 0 / overlap <= 0.3; known limits in SPEC S10 (open items 15, 16, 18, 22; 19 fixed, 20 resolved by D66, 21 fixed, follow-ups reviewed and fixed 2026-11-01). Tests at f4622af: unit 785/785 on 27.0 + 17.5 (1 known issue); demo UI 175 per lane: 27.0 pref 1 load flake, 17.5 the 2 pre-existing, forced 0 (`M8b-s6.md`) |
| M8b header behaviors (D68–D70) | done (branch `claude/cool-stonebraker-0015c9`, 859f58b…HEAD; not merged into main) | `docs/progress/M8b-s7.md` (5 workflow builders, design `docs/design/M8b-header-behaviors.md`): `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)` + the deprecated `scalingBehavior:` overload; D68 `collapse: .slideBehind(parallax:backdrop:)` (header behind the content, background slot, clipped at the scroll view's frame); D69 `.stretch` = a render-time scale (`HeaderStretchEffect` + `HeaderStretchClip`; the user's aspect-fit banner now grows); D70 split fade `ZTronHeaderFade { rest, collapse, pull }` drawn per frame by `HeaderFadeOverlay`; SPEC S10 amended; demo `appbanner` (the user's setup) + `HeaderUITests`; unit 837/82 suites on 27.0 + 17.5 (9 known); seam lab PASS on 27.0 / 17.5 / forced (design §7 risks all measured); open items 28, 29, 30. Fixer round 1 (2c6bba8…): S-RS-1 / item 30 fixed (the `.stretch` hold's indicator goes up with the content, clipped to the band: 168–275 → 0 frames over the content), C-RC-1 / C-RC-3 fixed, C-RC-2 / S-RS-2 in SPEC S10 and item 15 (b); unit 839/82 suites on 27.0 + 17.5 (9 known). Fixer round 2 (e0d2a8b…): R1-RC1-1 fixed (a short `.stretch` hold centres the `.system` spinner in the band; `holdOffset` 20 / 30: 0 / 10 → 20 pt of it drawn), seam lab `hsys<H>` / `hend<s>` + `spinner.py`, open item 31. Re-check 2: R1-RC1-1 confirmed fixed on 3 lanes; new LOW RC2-1 = open item 32 (a re-grab during the `.system` band retraction steps the spinner), pre-existing 17.5 `.preserve` re-catch = item 33. Closer (2026-11-02): our item 24 renumbered 27 (main's 24–26 are other sessions'); open items 27–33 (27, 28, 29, 31, 32 wait on the user, 33 on triage, 30 fixed); suites: full unit last at fixer round 1 (839 / 82 suites, 27.0 + 17.5), full demo UI at 9170ca3 (182 per lane: 27.0 p 0 failures, 17.5 the 2 pre-existing, forced 0), fixer round 2 targeted (refresh-indicator suites 50 / 3 + demo UI Refresh + Header + Proof 38/38 on 3 lanes) |
| M7 (a) observer hub | done | `docs/progress/M7-s1.md` (b0ab38a): `State/ObserverHub.swift` (geometry / phase / visibility / target-visibility boxes, frozen geometry per pass, `!=`-guarded, phase queue flushed last, ≤ 4 deferred passes, DEBUG counters) + `deliverObservers()` in `deliverPending` after the delegate + `setPhase` → `enqueuePhase`; `ZTronScrollGeometry` value init + `bounds` + 18+ bridge; member + twin `onScrollGeometryChange` / `onZTronScrollGeometryChange` (recipes → one box per scroll view, nesting works) and content `onZTronScrollVisibilityChange`; Q1 measured against native (native `0→0` then `0→-62`, ours `-62→-62`), Q4 unprefixed members ship; 48/48 in the touched suites + DelegateOrder/Reader/Counter/TargetRegistry on 27.0 + 17.5, both paths; open: `storage.phase =` sites still bypass the queue (session 2) |
| M8 (1) chrome exemplar | done | `docs/progress/M8-s1.md`: `Chrome/{ChromeConfig,ChromeLeaf,ScrollIndicators,NativeChromeBridges}.swift` = the M8 pattern (member on `ZTronScrollView` + `ztron…` twin writing the env AND applying the native modifier, type mirror with gated conversions, hot values only through `ChromeLeaf`): `ChromeLeaf` (declared channels offset / zoom / phase / metrics, `ChromeSample.overshoot`), scroll indicators (`scrollIndicators(_:axes:)` + twin, `scrollIndicatorsFlash(onAppear:/trigger:)` + twins, `ZTronScrollIndicatorVisibility` ⇄ native 16 / 16.4, `ZTronScrollState.scrollIndicatorInsets` (in `ScrollMetrics`) / `flashScrollIndicators()`, `IndicatorMath`, fade `IndicatorController` on one-shot timers + one SwiftUI animation), overlay inside the viewport root before `.ignoresSafeArea`; `showsIndicators:` precedence MEASURED on a hosted native ScrollView (an explicit `.visible` beats the flag; design §2 corrected); 79 new tests in 6 suites + unit **477/477 on 27.0 and 17.5** (both OS paths, committed tree 5b9a6f7 = 17fc47a + M8-1); device risk 3 (constants vs UIKit) open |
| M6 (c) targets session 3 | done | `docs/progress/M6-s3.md` (8ad77c2, 17fc47a, 07d8f54): `Position/{ZTronScrollPosition,PositionDriver,ScrollPositionModifiers}` (write-back only at the release target and at settle, ≤ 2 per gesture, held/pending requests, `withAnimation` through a `PositionTicket` effect), `scrollPosition` ×2 member + twins (18+/17+ native halves), `DefaultScrollAnchor` + `ZTronScrollAnchorRole` (initialOffset / sizeChanges / alignment), `ScrollPosition` / `ScrollAnchorRole` bridges; demo `-ZTronScreen targets` (6 sections) + `TargetsUITests` **7/7 on 27.0 preferred + forced and 17.5 preferred**; closed R4 (SwiftUI's context velocity is pt/ms, D32), R5 (`.alwaysByOne` = first item beyond the lift; all four limits equal SwiftUI's on 27.0) and Open 4 (proxy first match = frame order, the upper scroll view like SwiftUI); full unit suite **480** green on 27.0 + 17.5 (both OS paths) |
| M6b content-integral overlay | done | `docs/progress/M6b-s1.md` + `M6b-s2.md` (revision R6: unit types, free-axis lengths) + `M6b-s3.md` (R7: clamp diagnostics) (branch `m6b-content-overlay`, fast-forwarded): member `scrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)` + twin `ztronScrollContentIntegralOverlay`, `ZTronContentOverlayAnchor` / `…Size` / `…Scaling`, host = `Layout` on 16+ / `GeometryReader` + alignment guides on 15, public `ztronScrollCounterScaled(anchor:)` (S6 helper), `ChannelStorage.targetZoomChannel`; `ContentOverlayTests` 21, unit 637 on 27.0 + 17.5 (one load flake re-run green); `ContentOverlayUITests` 4/4 + `ResizeUITests` 13/13 on 27.0 + 17.5 both paths; overlay bodies 0 through drag, 4 rotations and pinch (D41) |
| UIKit observer (a) core | done | `docs/progress/UIKIT-s1.md` (5aba0db): `Gesture/UIKit/TouchObserverCore.swift` (pure; `TouchSample` → `[ObserverOutput]` in SpatialCatchGesture's order, pair magnification continuous across pair changes, no NaN/inf, timestamps = the shell's `now()`), `ZTronCapability.uikitTouchObserver` (`#unavailable(iOS 17)`, internal `preferredOSCeiling`) + public DEBUG `forceUIKitTouchObserver(_:)`, `ZTronScrollState.usesUIKitTouchObserver` (`let`, never with spatial events); `TouchObserverCoreTests` 37 (core 27 + spatial-equivalence 6 + gating 4) + AvailabilityTests; **core 100 % lines / regions / functions** (llvm-cov on the unit profdata: `xccov` lists no library files for this SwiftPM scheme); unit **520/520** on 27.0 + 17.5 in a clean worktree. Next = (b) shell + wiring + UI tests + gates |
| UIKit observer (b) shell | done | `docs/progress/UIKIT-s2.md` (9330cff): `Gesture/UIKit/UIKitTouchObserver.swift` (109 lines: passive window recognizer + anchor view + representable), wiring (`GestureAttach.observer` nil on the observer path, `CatchArming` bypassed, `PinchGestureAdapter` recognition-only, `PanCoordinator.init` `.spatial`), demo `-ZTronForceUIKitObserver` / `-ZTronShowToggle` / `-ZTronCancelProbe` + counters, `UIKitObserverUITests` 8/8 on 27.0 + 17.5 (preferred + forced), `UIKitObserverShellTests` 5, `scripts/coverage-uikit.sh` (llvm-cov, union of unit + 27.0 ×2 + 17.5 UI runs) → **100 % lines in both files**, `scripts/check-uikit-scope.sh` (comment-stripping grep gate) clean; unit **587/587** on 27.0 + 17.5 (clean worktree at 76823c4). D33. Open: the user's real 15/16 run; (c) docs |
| M7 (b) observation session 2 | done | `docs/progress/M7-s2.md` (607f40a + docs commit): phase observers ×2 (member + twin; `ZTronScrollState.writePhase` is the one place the phase changes, queued and flushed after the delegate; `holdingPhase` orders `willBeginDragging` / `willBeginDecelerating` before their transition), `ZTronScrollPhaseChangeContext` (geometry at the flush, velocity pt/s, nil without a motion) + 18+ bridges, `onScrollTargetVisibilityChange` (member + twin, typed `TypedTargetVisibilityBox`, recomputed on registry frame changes), demo `EventLogScreen` (delegate + modifiers + phase + geometry + target visibility in one log, native twin on 18+) + `ObservationUITests` **3/3 on 27.0 preferred + forced and 17.5 preferred** (the native test skips < 18); R2 measured: after the drag begins native and ours agree, at touch-down native coalesces `idle>tracking>interacting` into `idle>interacting` for a synthesized drag; 108/108 in the touched suites (+ DelegateOrder, ReleasePipeline, PinchPan, Counter) on 27.0 + 17.5 both OS paths |
| M8-8 delegate modifiers | done | same handoff: `Observation/DelegateModifiers.swift` (13 members + 13 twins, `viewForZooming` none), `DelegateObserverBox` list in `ObserverHub`, `notifyX` wrappers at all 13 sites (delegate first, then the boxes in registration order; `willEndDragging` threads the `inout` target; `shouldScrollToTop` = conjunction), 14 parity rows (13 + `viewForZooming`); `ZTronScrollState.scrollToTop(animated:)` added because `shouldScrollToTop` / `didScrollToTop` had no call site (M8-7 can reuse it); `DelegateModifierTests` 16 |
| SHEET sheet cooperation | done | `docs/progress/SHEET-s1.md` (spike), `docs/progress/SHEET-s2.md` (API): `View.ztronScrollYieldsToSheet(_ yields: Bool = true)` (environment-backed; pan / observer / pinch / double tap attached with `GestureMask.subviews` while true, `isEnabled:` on 18+; coordinator gate for the 15–16 UIKit observer; drag / pinch in flight ≡ cancelled touch; deceleration settles); default ≙ `.scrolls` without hand-off (documented, S12 amendment, D36); `SheetUITests` Y1–Y6 + `SheetYieldTests` (26 cases) green on 27.0 + 17.5 preferred / forced / uikit; open: the user's real 15/16 run |
| M7 (c) … M10 | todo | M7 session 3 (transitions, R1 first), M8-2…7, M9, M10: SPEC O4 l.970–990 |

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
   M6 (a) done 2026-10-20 (`docs/progress/M6-s1.md`, 7243121), D27 in 96671ed, M6 (b) done 2026-10-20 (`docs/progress/M6-s2.md`, 612b068) → M6 (c) session 3 done 2026-10-20 (`docs/progress/M6-s3.md`, 07d8f54): M6 is complete (open: R5 on 17.5, lazy content = M9). M7 (a) done 2026-10-20 (`docs/progress/M7-s1.md`, b0ab38a) → M7 session 2 + M8-8 done 2026-10-20 (`docs/progress/M7-s2.md`) → next in M7: session 3 (transitions, R1 first). M8b-1 done 2026-10-20 (`docs/progress/M8b-s1.md`); M8 (1) chrome exemplar done 2026-10-20 (`docs/progress/M8-s1.md`) → M8b-2 done 2026-10-20 (`docs/progress/M8b-s2.md`) → M8b-3 (scaling header) done 2026-10-25 on branch `claude/cool-stonebraker-0015c9` (`docs/progress/M8b-s3.md`, D51; merge = user); next in M8: M8-2 (ContentMargins, ContainerRelativeFrame, ClipAndBackground) on the M8-1 pattern.
5. [ ] **UIKit touch observer for iOS 15–16 (D31)** — **(a) done 2026-10-20 (`docs/progress/UIKIT-s1.md`, 5aba0db), (b) done 2026-10-20 (`docs/progress/UIKIT-s2.md`, 9330cff)**; next = (c) docs + the user's real 15/16 run. After the M6/M7/M8 sessions have committed: session (a) Sonnet builder
   `docs/design/UIKIT-touch-observer.md` §builder split (core `Gesture/UIKit/TouchObserverCore.swift` + `TouchObserverCoreTests`
   100 %, `ZTronCapability.uikitTouchObserver`, state let); then (b) shell + wiring + `UIKitObserverUITests` + the two gate
   scripts, coverage chased to 100 % on 27.0 and 17.5 with `-ZTronForceUIKitObserver`; (c) docs. Open questions answered (R1–R6 in the design note).
6. [ ] **M8b header behaviors (D68–D70): the user decides, checks on a device, then merges** — built 2026-11-02, closed 2026-11-02
   (`docs/progress/M8b-s7.md`, branch `claude/cool-stonebraker-0015c9` at the closer's docs commit; not merged into main). Next, in order:
    (a) **USER RULINGS 2026-11-02 (done deciding): every open item here is FIXED, none is accepted as a limit** ("Animations skip are
    not acceptable"; 28 and 29 "will be fixed"): batch **M8b-s8** = items 15 (b), 27, 28, 29, 31, 32, 33 (triage, then fix if ours),
    and D63 becomes an enum parameter of `withScalingHeader` defaulting to D63 (item 15 (a); D75 if free). The 15–16 fixes are to
    be confirmed on real iOS 15.0 / 16.0 on the user's M1 Mac once its SSH connection exists (branch pushed to origin for it);
   (b) the user runs the `appbanner` screen (or their own banner) on a device: pull (the image grows from its top centre, its bottom
   on the content), a refresh hold, scrolling during a refresh, rotation in a hold, `.slideBehind` under their bar;
   (c) the user merges into main with the merge notes in M8b-s7 (main's 250 pt/s release gate and its re-derived `HeaderStateTests`,
   BTN open item 11, the iOS 26+ hosting rule for the three new hosted suites, our open items 28–33 against main's next free number,
   D71 (another branch) and D72–D74 (main) taken), then the full unit suite and demo UI on 27.0 / 17.5 / forced.

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
   before 1.0.0 (e.g. an additive hand-off callback). The spike suggests (a). Don't tag until decided. **DECIDED (user, 2026-10-25, D50): option (a)** — ZTronPages drives its pager with a SwiftUI pan on iOS 15–17 while the participant drops the drag on `.container`; no contract change. The tag now waits only for the user actions of item 5.
2. Spike notes for ZTronPages: hosting views swallow `touchesBegan` (use a never-recognizing observer recognizer);
   the container's first ask can carry < 10 pt so rule 1 near 30° is noisy; on 18.6 an unnamed
   `UIKitResponderGestureRecognizer` reaches `.began` on taps, so key rule 5 on the arbiter's answer. Does ZTronPages
   host its pager through a Representable? One arbiter per page or one in pager space? (`ZTronPages.swift`:
   `/Users/admin/Documents/ZombieTron/ZombieTron/ZombieTron/Utils/Pages/`). **User 2026-10-25:** ZTronPages is not implemented yet; write a ZTronPages integration design that overcomes this limitation (D50 fallback on 15–17, names on 18+) and folds in these notes. Design session proposed. **DESIGN WRITTEN (2026-10-25, PAGES-s0, `docs/design/ZTRONPAGES-integration.md`, branch `claude/upbeat-mendeleev-3a9d67`, proposal, no D-number yet):** recommends ZTronPages = a paging `ZTronScrollView` on every OS (D28 nested arbitration, pure SwiftUI, so note E / D47 cannot occur); the UIKit pager (own `UIScrollView`, names 18+, Q3-s1 `cancel` ≤ 17) as a recipe only; 8 open questions, Q1 = may ZTronPages depend on ZTronScrollView (S16 premise).
3. Not measured yet: fps / `clock.lagFrames`, 120 Hz on device; confirm 27.0 *preferred* really uses Observation
   storage (its counters equal the forced path's); `phaseReaderOnTransitionsOnly` UI test still to add. **User 2026-10-25:** left undecided for now.
4. Minor: `AvailabilityTests.minimumOSTableMatchesSDK` only cross-checks two hand-kept tables; the
   `ZTronScrollPhysics` enum shares its module's name and top-level names (`Velocity`, `Decay`) are generic. **CLOSED (user, 2026-10-25): OK as is.**
5. User actions: push ScrollArbitration to its own repo + tag 1.0.0, then switch both projects to
   `.upToNextMinor(from: "1.0.0")`; iOS 15/16 + Xcode 26.6 runs; device checks (ProMotion, gesture feel). **User 2026-10-25:** later.
6. ~~27.0 + all fallbacks forced: a second copy of the content on a parent re-evaluation~~ RESOLVED 2026-10-20
   (`docs/progress/DBG-s1.md`): gesture/completion paths were chosen in bodies from the process-wide switch
   (`CatchObserver.usesSpatial` → `CatchArmingProbe`'s `if let` around the content), so a re-evaluation outside the
   test's `withOSPath` scope flipped the branch on 18+. Now `let` flags on `ZTronScrollState` (R6). App/real 15–16
   never flipped (the set is fixed at launch). New open: `ProofUITests.testNoClockTicksAtRest` red on a fresh 27.0
   simulator at fd3d17a with and without the patch (DBG-s1 Open). **CLOSED (user, 2026-10-25): OK.**
7. ~~~45 UIKit "Observation tracking feedback loop detected" warnings in the full 27.0 unit run~~ RESOLVED 2026-10-25
   (`docs/progress/DBG-s9.md`, D52): 203 at HEAD 80e2e08 (673 tests), 0 after (676/676 on 27.0 ×2 and 17.5). Not the library:
   iOS 26+ UIKit counts Observation-tracking invalidations per object address (threshold 40) and clears the counts through
   `UIApplication.shared`, which is nil in the package test process, so they never cleared; each native SwiftUI `ScrollView`
   window costs its window 2 counted invalidations and windows reuse the freed address, so after ~20 such windows every
   later window there warned. Test windows holding a `UIScrollView` are now kept for the run (`ScrollViewWindows`,
   `HostWindowTests`), and `scripts/run-filtered.sh` fails any run that prints the warning. Possible follow-up (user): a
   host-app unit-test target would give the tests a real `UIApplication` and remove the cause instead of avoiding it.
8. N-a/N-b handoffs: `docs/progress/NESTED-s1.md`, `NESTED-s2.md` (N-b done 2026-10-20; SPEC S11/S12 amendment + parity row written). Still open: user device check of the pager + zoomer on `.innerWhenZoomed` incl. a second finger landing during an outer-owned drag (not scriptable in XCUITest), ZTronPages adoption (R6), three-level phase 2. **User 2026-10-25:** stays open until ZTronPages exists.
9. M6 s3 leftovers (`docs/progress/M6-s3.md`): R5 on 17.5 (SwiftUI's `scrollPosition(id:)` reported 0 in the aligned comparison, only ours is asserted there); `scrollTo(point:)` is an offset, not SwiftUI's content-space point (untested against native); native `ScrollPosition` bridge exercised on 18+ only through a hosted `ScrollView` (edge); lazy content (R2) is M9's; the full demo UI suite was not re-run (TargetsUITests only). **User 2026-10-25: compare against native** — behavioural parity is mission-critical wherever the native version shows no defect (R5 on 17.5, `scrollTo(point:)` vs SwiftUI's content-space point, the `ScrollPosition` bridge). Comparison session proposed.
10. **Sheets (SHEET-s1, 2026-10-21, `docs/design/SHEET-spike.md`, `docs/progress/SHEET-s1.md`)**: inside a `.sheet` a drag that starts on a `ZTronScrollView` never moves or dismisses the sheet (content always wins at every detent; not ZTron-specific: any recognized SwiftUI `DragGesture` / `SpatialEventGesture` does the same; header / grabber drags still work). Pure-SwiftUI fix measured: mask the gestures with `including: .subviews` per detent (`ztronScrollYieldsToSheet(_:)`, ~1–1.5 %); live top-edge hand-off needs UIKit. DECIDED (user, 2026-10-21): both: the limitation text + parity rows are written (SPEC S8/S11/S12 amendment 2026-10-21, D36) and `ztronScrollYieldsToSheet(_:)` goes to a builder session. **BUILT (SHEET-s2, 2026-10-21, `docs/progress/SHEET-s2.md`)**: the flag masks pan / observer / pinch / double tap with `.subviews` (iOS 18+ `isEnabled:`), a drag / pinch in flight ends like a cancelled touch, a deceleration settles on its own; `SheetUITests` Y1–Y6 + `SheetYieldTests` green on 27.0 + 17.5 (preferred, forced, `--uikit`); open: the user's real 15/16 run. Found on the way: SwiftUI `.scrollDisabled` did not stop a `ZTronScrollView` (`.ztronScrollDisabled` did) — FIXED by DBG-s6 (D38; the reader never ran), and the "9 pt residual offset" was the harness readout resizing the viewport, not the library. **CLOSED (user, 2026-10-25): OK** — `ztronScrollYieldsToSheet(_:)` merged into main (cdca45e, unit 673/673 on 27.0 + 17.5).
15. **Scaling header limits (M8b-s4…s6, D62, SPEC S10 "Seamless edges")**: (a) **USER RULING 2026-11-02: D63 becomes an enum parameter of `withScalingHeader`, default = D63's behaviour (D75 if free; scheduled in M8b-s8)**; was "D63 needs the user's yes": under a scaling header, content that fits is top-aligned vertically (alternative: the header follows the centred content, a gap above it, `.stretch` grows by the pad at rest); (b) **USER 2026-11-02: FIX (no animation skips or 15–16 look differences are accepted as limits); scheduled in M8b-s8.** 15/16 path only: an overflow-limited `R` (`.capped` / `.refit`) lands in one frame at the commit of an app-driven animated resize (forced lane 70 / 35 / 31 pt, 84 pt `.fixed`, 115 pt landscape; a width change lands the width too: `.capped(0.25)` half covered,
402 → 241 pt, seam 29.3 pt and lateral 159.3 pt in one frame, closing over 1.1 s, `.compress` and `.slideBehind(1)` alike, S-RS-2 of the
header behaviors review, 2026-11-02), and a `.fit` header inside the band steps on app-driven resizes; rotations are seamless there; possible fix: a cold slot-level reader (resizes only) around the 15-path frame; (c) a scroll command issued while an animated resize is open (`combo`) is not seamless (the M5 intervention snaps the content); (d) `compositingGroup` cost on a real iOS 15/16 device unmeasured; (e) `ZTronScrollState.stepDrawn` is a heuristic over the last three drawn sizes (bounded by the step it misjudges).
16. **Keyboard and the scaling header (D64, 2026-10-27)**: (a) iOS 15/16 runtimes unverified on this host: the 15 path (the probe in the viewport preference) is measured on the 27.0 forced lane, the 16+ path (`KeyboardProbeLayout`) on 17.5 and 27.0; (b) with an engaged limit the header can be taller than the region above the keyboard (landscape `.capped(0.5)`: 191 pt over 178 pt; `.refit` 382 pt): the content is reachable by scrolling (the header collapses); a direct consequence of D64; (c) not the header, seen before D64 too: while the keyboard animates, the container's clip follows its frame (SwiftUI animates it in the keyboard's curve, the keyboard moves on its own), so for several frames a band of the background shows between the content's last row and the keyboard's top (seam lab, 17.5 and 27.0).
17. ~~Per-frame content-overlay placements in a pinch after a rotation round trip (27.0 preferred under host load,
   `ContentOverlayUITests.testCounterScaledMarkerKeepsItsScreenSize`, M8b-s6 core check finding 3)~~ FIXED 2026-10-27 on
   branch `claude/overlay-place-fix` (from 79a5896; `docs/progress/M8b-s5.md` "Overlay placement fix"): pre-existing on main
   9e60063. `TransformHost`'s per-frame body re-created `.disabled(blocked)` (an environment transform), which on 27.0
   re-laid out every control in the content on every scroll / zoom frame, and with it the overlay `Layout` holding the
   demo banner's `Button`. The gate is now its own leaf (`ContentInteractionGate`, one `Bool`); regression unit test
   `ContentOverlayTests.motionFramesDoNotLayOutControlsAgain`. 17.5 never showed it (hosted or UI).
18. **D65 `.openGap` limits (2026-10-27)**: (a) ~~the hold indicator during a rotation that takes the gap below the screen~~
   FIXED 2026-10-27 (D65 review fixes, 8b5d3ad + 5b32f97; `docs/progress/M8b-s5.md` "D65 review fixes"). The first text ("not
   drawn") was wrong: on the way to landscape the indicator vanished at once, and on the way BACK it was drawn at its final
   portrait place over the header Core Animation was still shrinking (27.0 / 17.5 / forced, 5-8 frames, up to 79 pt off the gap),
   then drifted into the gap. Root cause: SwiftUI drew no layer for the indicator while its place was outside the viewport (no
   marker layer in the hosted layer tree, `RefreshIndicatorLayerTests`), so Core Animation had nothing to interpolate; `.stretch`
   the same (its overlay placement was nil there). The indicator box is now its own layer group (17+ `geometryGroup()`, 15–16
   `compositingGroup()` only under a scaling header since the final check, 53b272c: grouped in every view, the 15–16 group kept
   a headerless view's custom indicator from blending with what is behind it), still laid out at the clip's place (a
   render-time translation, 8b5d3ad, broke `withAnimation` resizes: 88 pt), and an overlay clip is never shorter than the
   indicator. Seam lab, rotation during a hold (uncapped 16:9, frames with
   the gap on the screen): see the handoff table; width hold unchanged (within 0.5 pt). (b) iOS 15/16 runtimes unverified here
   (the forced lane on 27.0 only), as item 16 (a).
19. **Headerless twin of item 18 (2026-10-28, reported by the D65 final check, pre-existing)**: ~~a view WITHOUT a header, a top
   refresh hold, a rotation to landscape and back: S7 scrolls the gap off the screen in landscape (the placement is nil there), and
   on the way back the indicator is drawn at its final place over the content for about 14 frames~~ FIXED 2026-10-28 (779acb1 +
   008aa87, `RefreshIndicators.swift`; notes `scratchpad/i19/notes-build.md`). In the gap, while refreshing (the hold, the spinner's
   retraction), the placement is kept whatever the pull: the indicator's box (a layer group) keeps its far edge on the content's
   edge (`[pull - max(L, hold, pull), pull]`), so it moves rigidly with the content off the screen too, and an outer group from the
   edge's base on clips the drawing to the gap (nothing visible while the gap is closed or covered: no change at rest or for
   pull > 0). `.system` keeps going with the content's edge below 0 (continuous) until it sits at the hold's rest place (H/2 before
   the edge). A pull or its release still ends at 0 (rig body runs unchanged). Seam lab (`holdgap.py`: frames with the indicator's
   place on the screen in place / over the content / missing, new `testRotateFromLandscape` for leading / trailing): 27.0 top
   66/73 in place, 16 over, 4 missing -> 73/73, 0, 0; bottom 67/74, 0, 4 -> 73/73; leading 49/61, 15, 9 -> 84/84; trailing 67/79, 0,
   9 -> 81/81; 17.5 top 50/55, 16, 3 -> 55/55; bottom 50/59, 0, 5 -> 59/59; leading 53/61, 15, 6 -> 54/54; trailing 53/64, 0, 9 ->
   63/63 (max deviation <= 0.75 pt). Overlay control and the header rotate-hold scenarios (item 18 (a)) unchanged (all 9 PASS,
   = the final check). Tests: `RefreshIndicatorTests.aHoldScrolledAwayKeepsItsBoxOnTheContentsEdge`,
   `aLargerHoldRestsTheSystemIndicatorInItsMiddle`, `RefreshIndicatorLayerTests.aHeaderlessHoldScrolledAwayKeepsItsIndicatorOnTheContentsEdge`.
20. **15–16: a custom refresh indicator without a header has no layer off the screen (2026-10-28, the remainder of item 19)**: ~~the
   final check of D65 keeps it ungrouped on 15–16 (a compositing group isolates its blend modes), so SwiftUI drops its layer while
   its gap is off the viewport and a rotation back draws it at once at its final place (forced lane, unchanged: top 9 frames over the
   content, leading 15; `withKnownIssue` in the layer test). The built-in indicator is grouped there and keeps its layer. A spike
   grouping every 15–16 indicator removed most of it (forced top 0 over, leading 79/79 in place) but the 15–16 headerless CONTENT
   itself tears in a rotation (its group is only under a header, review d16), so the indicator cannot be rigid with it there either.
   Lead / user decision: blend-mode parity (now) or the rotation (group custom indicators too; the blend test would change on 15–16).~~
   RESOLVED 2026-10-28 by D66 (2121913; notes `scratchpad/i19b/notes-build.md`): still ungrouped (blend modes kept, no layer off the
   screen: the layer test's `withKnownIssue` stays), but hidden (opacity 0) for a resize that begins with nothing of it visible,
   shown when the resize is drawn frame by frame or, for a rotation, in a 0.1 s reveal of its own. Forced lane, headerless hold
   (holdgap: in place / judged, over, missing): top rotation 70/77, 9, 7 -> 72/79, 0, 7; leading 68/79, 15, 9 -> 67/79, 0, 9;
   trailing 66/79, 0, 10 -> 66/78, 0, 9; bottom 68/81, 3, 10 -> 67/80, 3, 10 (those 3 at the first rotation's start: the 15–16
   headerless content lands at once, as before); a `withAnimation` resize shows it at once (height 0.4 and back 59/59 in place).
   17+ and the built-in indicator unchanged. Test `RefreshIndicatorTests.aResizeThatBeganWithNothingVisibleHidesItUntilItIsDrawnFrameByFrameOrOver`.
   Amended 2026-11-01 (review of item 21 follow-ups, 18620ed; D66 amended): that 0.1 s reveal was drawn as a translucent fade
   over the content still sliding in (SwiftUI animates what an Animatable modifier's body derives with the same transaction:
   the "0 for 85 %" hold became a 0.1 s fade from ~0.18 s into the 0.3 s rotation; holdgap saw only opaque white: forced
   leading 4 frames at 33-82 % at a19ea0f, 7 at 8f902f4; the bottom's 3 were the status bar's battery icon). The reveal now
   waits out the rotation (plain opacity, a 0.15 s fade after 0.3 s) and D66's gate reads the boxes' latched group. Forced lane,
   headerless rotations top / bottom / leading / trailing: 0 frames over (opaque or translucent), 0 off (was 0 / 3 / 3 / 3, up
   to 205 pt), missing 7 / 15 / 10 / 9 -> 23 / 30 / 23 / 24 (hidden through the rotation back, opaque 0.17-0.18 s after it
   lands: the price of no layer off the screen). iPad rotations (0.4 s) not measured.
21. **An animated resize during a hold draws the indicator over the content (2026-10-28, review of open item 19, pre-existing)**:
   ~~a headerless hold, the scroll view's height animated to 0.4 top-pinned and back (easeInOut 1.2 s): S7 takes the gap off the
   screen and back; during the open resize the leaf took the pull from the committed target and `RefreshResizeEffect` moved the
   placement by the inset / size change only, not by the content's S7 offset change: the indicator vanished at once on the way out
   and was drawn at its final place over the content still sliding in (holdgap.py: 57 frames over the content, about 1.1 s; 27.0,
   17.5 and forced, before and after item 19)~~ FIXED 2026-10-28 (a04c279 + 8b9cbcc, `RefreshIndicators.swift`; notes
   `scratchpad/i19b/notes-build.md`). The outer region is laid out as the drawn viewport from the committed base (plus a margin of
   the committed cross length on each side) and the box sits in a frame of the drawn viewport's size inside it, so the render-time
   moves are functions of the drawn size (`RefreshResizeEffect`): `.cross` at the leaf (centred in the drawn width / height, outside
   the groups: inside the 15–16 region group it was not drawn per frame, forced `.stretch` width 80.5 pt off), `.region` to the
   presented base, `.box` with the content's edge as `ContentTransform` draws it (`ResizeMath.resolve` at that size; an overlay with
   its base; `.followContent` less the bound's move). Identity at the committed size: rotations unchanged. Seam lab (holdgap.py: in place / judged,
   over, missing), height 0.4 and back, headerless top: 27.0 33/61, 57, 16 -> 59/59, 0, 0; 17.5 31/56, 57, 15 -> 58/58, 0, 0;
   forced 28/52, 47, 15 -> 59/59, 0, 0. The same at the bottom edge: 57 -> 0 frames over (27.0, 17.5, forced), the horizontal lab's
   leading gap in a width change 47 -> 0 (their missing frames are the gap beyond the shrinking scroll view, which holdgap's window
   base counts; forced bottom keeps ~10 more clipped frames at the end of the growth than 17+: the ungrouped indicator, item 20);
   headerless width 176/176 -> 178/178; `.openGap` / `.followContent` / `.stretch` height 0.4 and the `.stretch` width resize in
   place (lateral <= 0.34 pt; forced 80.5 pt at a04c279, fixed by 8b9cbcc); rotations unchanged (headerless, 4 edges, 0 over;
   item 18 (a) rotate-hold 9/9 PASS).
   Tests: `RefreshIndicatorLayerTests.anAnimatedResizeDuringAHoldKeepsTheIndicatorOnTheContentsEdge` (presented tree every 0.05 s,
   height and width, both paths: before 11 / 7 samples over the content), `RefreshResizeEffectTests` (cross / region / box deltas).
   Review 2026-10-28 (a19ea0f): a commit that moved the base (a top-pinned height change takes the bottom off the home
   indicator, inset 34 -> 0) left the box's effect at the committed size on 15-16, so a forced bottom overlay jumped 500 pt
   mid-content; the region's base is a render-time translation now and the cross move the box's (SPEC S9; test
   `anAnimatedResizeThatMovesTheBaseKeepsTheHoldOnItsDrawnEdge`). Verified 2026-11-01: drawn 84/143, 59 missing, a 500 pt step
   -> 157/157, 0 missing, largest step 0.10 of the travel (the forced recording's repeated frames; 17.5 / 27.0 0.025).
   Follow-ups 2026-11-01 (18620ed + the review commit): D66's reveal (item 20), `holdgap.py` sees a translucent probe and only
   a probe-sized ring (the battery icon and a lab button were 'over'); seam lab 3 lanes x 21 scenarios: 0 frames over, the
   rest as at a19ea0f (`M8b-s6.md` "Review of item 21 follow-ups").
   Fix round 2 2026-11-01 (27bc80f, review MEDIUM, pre-existing at 8f902f4): the symptom a19ea0f fixed for a resize ("a bottom
   hold in the gap vanished at once") remained for an app-animated bottom `.safeAreaInset` (seam lab kbfake, 150 pt). That is an
   inset-only change (the viewport extends over the inset: only `aci.bottom` moves, 128 -> 278 hosted), reported after the
   layout pass that animates the container's frame and written unanimated, so the indicator's region clip jumped to the new base
   while the container's clip (its frame) followed the app's curve: the gap hold vanished on the first frame (all 3 lanes) and an
   overlay jumped 150 pt. `ZTronScrollState.insetFollow` keeps the turn's animation; `RefreshBaseFollow` makes the leaf draw that
   base move in it (overlay always, the gap only where the content's edge stays), set BELOW `RefreshPlacementEffect` (its own
   `pull` lands at once: interpolating it re-animated the values its body derives every frame, which lagged most of the change).
   Seam lab (kbseam.py: frames judged / bad > 1 pt, gap vs the frame's drawn bottom, overlay vs its rest distance): gap 27.0
   26 bad -> 146 / 0, forced 26 -> 139 / 0, 17.5 26 -> 146 / 0; overlay 137 / 0, 119 / 0, 137 / 0 (worst 0.67 pt); controls
   unchanged (height04-hbottom, forced rotate-hbottom, forced height04-hbottom-hoverlay). Test
   `RefreshIndicatorLayerTests.anAnimatedSafeAreaInsetSlidesTheHoldWithTheFrame` (c5ffc4a 4/4 fail, fix 4/4).
27. **USER 2026-11-02: FIX (no animation skips or 15–16 look differences are accepted as limits); scheduled in M8b-s8.** **15–16: D66's reveal also delays an instant resize (2026-11-01, review LOW, not measured, OPEN; user decision)** (numbered 24
   on this branch until 2026-11-02, renumbered because main's 24–26 belong to other sessions; main reserves 27 for it): 18620ed's reveal (opacity
   0 for 0.3 s, then a 0.15 s fade) follows every resize the watch closes undrawn, and an instant (unanimated) resize closes
   undrawn exactly as a system rotation does ("never animated": SwiftUI lays out the final state once in both). So on the
   ungrouped path (15–16 or forced, a custom indicator, no header) a hold whose gap was off the screen and comes on it in an
   instant layout change (a toolbar hidden without animation) shows an empty gap for 0.3 s and is opaque after ~0.45 s (a19ea0f:
   ~0.1 s; before D66: at once). Not fixed: nothing pure-SwiftUI tells the two apart (the transaction has no animation in both, the
   watch closes one turn in for both); an orientation-flip heuristic would give single-axis system resizes (iPad Split View /
   Stage Manager, Core Animation-interpolated, no iPad lane) back the item 20 symptom (drawn over the content), which is worse
   than a late reveal. Options: accept; or reveal at once when the size change is single-axis and measure on an iPad lane first.
28. **USER ACCEPTED 2026-11-03 (D76): the fix is the scoped UIKit raster engine of `d76-magnified.md`, built in M8b-s9.** **USER 2026-11-02: FIX (no animation skips or 15–16 look differences are accepted as limits); scheduled in M8b-s8.** **USER RULING 2026-11-02 (D76): an option, not a look change: default `.keepTextMagnified` (magnified as with D69, made crisp); the layout grow that keeps text at its point size is the other case.** **`.stretch` pull blurs text in the header while pulled (2026-11-01, header behaviors step 3 / D69, measured, OPEN; user
   decision)**: the stretch is a render-time scale (D69), so Core Animation scales the header layer's bitmap: a 24 pt
   text's edge width grows 1.25x (17.5) to 1.8x (27.0, forced) at s = 1.25 (seam lab `-ZTronSeamHeaderText 1`, all lanes, not
   only 15-16). Transient (pull and refresh hold), images unaffected in kind. A re-raster would re-run the header body (S4).
   Options: accept and document in SPEC S10 (proposed); or a user opt-in that re-lays the header at the pulled height.

29. **USER RULING 2026-11-03 (D77): the public route (G + a probe turning off the public `allowsGroupOpacity`), built in
   M8b-s9; route P documented, not built; the three pre-existing 15–16 blend differences only P closes stay by this ruling.**
   **USER 2026-11-02: FIX (no animation skips or 15–16 look differences are accepted as limits); scheduled in M8b-s8.** **15–16: a content child's blend mode does not reach a `.slideBehind` header (2026-11-02, header behaviors step 4 / D68,
   from the code, not pixel-measured, OPEN; user decision)**: the content scrolls over the header; on 15–16 its layer group is a
   `compositingGroup()` (`ContentLayerGroup`, needed for rigid rotations), so a `.blendMode` inside the content composites
   within the content, while on 17+ (`geometryGroup()`) it blends with the header behind. The mirror of SPEC S10 "15–16 layer
   groups" for the header. Options: accept and document in S10 (proposed, with the step 6 amendment); or measure with a
   pixel UI test on the forced lane first.

30. **A programmatic hold's opening draws the indicator over the content under a `.stretch` header (2026-11-02, header
   behaviors step 6 seam lab, measured, pre-existing)**: FIXED 2026-11-02 by the header behaviors' fixer round 1 (S-RS-1, 2c6bba8,
   `RefreshIndicatorMath.inStretchBand`; SPEC S10 "Refresh with the header"): the `.stretch` band's indicator is drawn only over the
   band and on its far end (the header's drawn bottom) once the band is shorter than the indicator, also while refreshing, with the
   gap's box and region (item 19). The same fix covers the reviewer's S-RS-1 (a hold the content is scrolled out of drew the
   indicator over the content the whole time: seam lab fling 168 / 170 / 168–275 frames on 27.0 / 17.5 / forced, all collapse modes,
   now 0). Opening, all `.stretch` hold scenarios (fling-hold k 0 / 0.25 / 1, appbanner, rotate-hold, width-hold, height 0.4): the
   probe stays 20.3–20.8 pt inside the band on 27.0, 17.5 and forced, 0 frames below the header's bottom (before: 27.0 9–11 frames, up
   to 37 pt). ~~`beginRefreshing` at rest (the lab's `-ZTronSeamHold 1`, 0.8 s
   after launch) animates the hold's inset 0 → 60 pt, but the indicator (the lab's opaque 20 pt square) is drawn at its final
   place in the stretched band from the first frame: the content and the header's bottom slide down under it, so for 13–17
   frames (about 0.25 s) its bottom is up to 40 pt below the header's bottom, over the content's top. Appbanner lab rotate-hold:
   27.0 15 frames (max 39.8 pt), 17.5 17 (39.9), forced 13 (39.9). The same before D68–D70: the M8b-s6 follow-up baseline
   `aspect-rest-stretch-rotate-uncapped-hold` 27.0 14 frames / 35.7 pt, 17.5 15 / 39.7 (`scratchpad/fu/seam`), b4's g27 14 /
   37.6. `probe.py`'s default window (−80, +6) counted those frames as missing, so earlier steps read "missing = before the hold";
   `--window=-80,40` shows them. Steady hold: the probe sits 20.3 pt inside the band. Not measured: a finger pull's hold (the
   content comes up to the hold, so the band never closes under the indicator), `.preserve`, a hold's retraction. A headerless
   hold keeps its far edge on the content's edge and is clipped to the gap (item 19), so it does not show this. Options: give the
   `.stretch` band's indicator item 19's treatment (box far edge on the header's drawn bottom, clipped to `[top0, top0 + g]`);
   or accept for programmatic openings.~~

31. ~~**A `.stretch` pull that triggers below `indicatorHeight` moves the `.system` spinner at the trigger** (2026-11-02, header
   behaviors fixer round 2 / R1-RC1-1, non-default configuration; USER 2026-11-02: fix, scheduled in M8b-s8)~~ **FIXED 2026-11-03
   (M8b-s8 s1, 8e0f364; drawn as measured once item 41 was fixed, 782513b; no D-number, plan C8)**: the band's `.system` pull look
   hands over to the refreshing look by the trigger (`center = min(s, L) − L/2 + max(0, L·dragPosition − p)/2`: the slide-in look
   for `T ≥ L`, `min(s, L)/2` from `p = T` on) and the band's / overlay's pull opacity is `min(1, max(p/L, dragPosition))` (L2: 1
   at the trigger). The designer's centred pull look (L1) is not built: an established look stays (plan §9 Q3 offers it as an
   option). Seam lab (`scripts/seam/handover.py`; 27.0 / 17.5 / forced, two runs where two numbers): `rtrig40` largest
   |Δcentre − Δpredicted| 0.83, 0.83 / 0.92, 0.67 / 1.0 pt (before, 61c7e21 lab on 88828d7: 9.67 / 10.33 / 9.67, at the
   trigger), centre − band/2 from the trigger on ≤ 0.33 / 1.0 / 0.67 (before 10.0 / 10.33 / 10.0), largest one-frame opacity
   rise 0.31, 0.21 / 0.29, 0.29 / 0.40 of the rise to the trigger (before 0.60 / 0.62 / 0.60); `rtrig30` 1.17, 1.0 / 1.0 / 1.0
   (before 10.33 / 10.0 / 10.0), centre ≤ 0.33 / 0.67 / 0.0, opacity rise 0.36, 0.34 / 0.30 / 0.27 (before 0.82 / 0.84 / 0.82);
   0 frames over the content, 0 jumps, 0 vanishings on every run. The 1.17 is one pre-trigger frame of a 6 pt band step; the
   same measurement reads 0.67–1.0 on the before's unchanged default pulls. Default trigger (`pull-refresh`): per band the
   drawn centre and height equal the before's (27.0: all; 17.5 / forced: 1–2 bands one pixel row apart, as two runs of the same
   code are). Was: the spinner moved `(L − T)/2` (10 pt at T 40) and the opacity stepped `T/L → 1` in the trigger's frame.
   Real 15/16 (M1 Mac lane): math (`RefreshIndicatorMath`), the same on every OS; check `rtrig40` / `rtrig30` (no centre step,
   opacity 1 at the trigger).

32. ~~**Re-grabbing the content during a `.stretch` `.system` spinner's retraction steps it** (2026-11-02, header behaviors
   recheck 2 / RC2-1, default configuration; USER 2026-11-02: fix, scheduled in M8b-s8)~~ **FIXED 2026-11-03 (M8b-s8 s1,
   8e0f364; no D-number)**: the engine carries the refreshing look through a catch of the retraction (`RefreshEngine.carried`,
   refresh design §3.2: until the pull fires, the lift (the retraction goes on with the look), a cancel or the content back at
   rest) and `holdsPlacement` holds the band placement for every built-in style (L3: the `.default` band end no longer drops to
   `H/L`, the sibling of item 31). Seam lab, 27.0 / 17.5 / forced: `regrab-rdur0p2` vanishings 0 / 0 / 0 frames (before 26 / 26
   / 30), the spinner drawn 20 pt whenever the band is 20 pt or more; `fling-hold-hsys60-hend1p5` 0 over, 0 jumps, 0 vanishings,
   20 pt at rest; `.default` band end (`hdef30` / `hdef45-hend1p5`) largest one-frame fall 0.09, 0.09 / 0.08, 0.13 / 0.06, 0.16
   (before 0.16, 0.22 / 0.22, 0.21 / 0.11, 0.20). Was: the spinner switched to the pull look in one frame (`(L − s)/2`, opacity
   `1 → s/L`). The catch during a SwiftUI reset (`hreset4`) is s3's (D79). Real 15/16: engine + math; check `regrab-rdur0p2` (no
   vanish) and `hdef30-hend1p5` (no opacity step).

33. **USER 2026-11-02: FIX (no animation skips or 15–16 look differences are accepted as limits); scheduled in M8b-s8.** **17.5 `.preserve`: after a re-catch the spring back draws the pull-look arrow over the content (2026-11-02, header behaviors
   recheck 2, measured on 17.5 only, pre-existing, OPEN; needs triage)**: in the `.preserve` control of the 17.5 re-grab lane
   (`recheck2/seam/g175`, the scratch lab's 4 s `resetAnimation`, a fling down after `endRefreshing`) the
   arrow is drawn 1.3–10 pt over the content in frames 334–341 while the content springs back after the catch; 27.0 shows 0 such
   frames, forced was not judged for it. Not from fixer rounds 1–2 (the gap code is unchanged by them); whether it predates
   D68–D70 is not checked. Crops `scratchpad/api/recheck2/px/pres175.png`. Next: reproduce on 17.5 at the base 54f8650 and
   classify against item 19's gap rule.

41. **The arrow → spinner cross-fade and a begin's look switch were never drawn (2026-11-03, M8b-s8 s1, measured; pre-existing
   for the cross-fade; FIXED; numbered 36 in 170c1d3 / 542f59c and 39 in 8558f70 / d114c6f / 782513b: M9-s1 took 36, main
   37–38, INTEG-s2 39–40)**: before, at every trigger on every lane the arrow was drawn at full intensity on one frame and the
   spinner on the next (the 0.15 s `modeAnimated` cross-fade never drawn), and a `beginRefreshing()` while the pull look was
   drawn (fb4c52e's `RefreshLookSwitch`) landed in one frame (`rbegin50-pd80`: 11 pt on 27.0 / 17.5 / forced). Causes (NSLog and
   test squares, 27.0): (a) a `Group` hands `.animation(_:value:)` to its branch, so the swap ran unanimated → a `ZStack`;
   (b) SwiftUI resolves ancestors' opacity and geometry animations at the leaves, so the inserted spinner, a new leaf, started at
   their end values (a `GeometryEffect` shift also blanked the indicator 1–2 frames after a begin, 16 of 20 runs) → the switch is
   drawn frame by frame (`RefreshLookFade`: an animatable weight, the shift as centre guides, the opacity a factor, identity
   outside a switch); (c) a stack that took the spinner's size drew the fading arrow 0.67–1 pt off → both glyphs in a 24 pt
   square; (d) the arrow the cross-fade removes kept its last geometry relative to the box's layer group, which moves with the
   content: after a `T < L` trigger it went on with the content up to 8 pt off band/2 for 0.15 s → `RefreshGlyphBoundary`
   (782513b), an identity `GeometryEffect` around the glyphs. After (27.0 / 17.5 / forced): the cross-fade spans 5–6 frames,
   starting 1–3 frames after the trigger's stalled frame (item 35; the stall itself unchanged, 30–77 ms); a begin glides in 8–10
   frames, largest step 2.3–3.3 pt (0.21–0.29 of its 11 pt), 0 blank frames in 7 runs. Real 15/16 (M1 Mac lane): SwiftUI
   semantics the forced lane does not emulate; check (a) mixed arrow / spinner frames over 0.15 s at a trigger, (b)
   `rtrig300-rbegin50-pd80`: the glide, no blank frame, (c) `rtrig40` / `rtrig30`: the arrow at band/2 right after the trigger,
   (d) a flexible custom indicator keeps its size through a begin during a retraction.

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
  Open item 1. Design `docs/design/UIKIT-touch-observer.md`, resolutions R1–R6 at its end (user, 2026-10-20: rect-only
  overlay filter; `.direct` + `.pencil`; MagnificationGesture for recognition only; ForceAllFallbacks turns the observer
  off; gates run by the orchestrator/test-runner, no hook/CI yet; cancelled-line scheme accepted); starts after the
  M6/M7/M8 sessions commit; ≈ 3–3.5 Sonnet builder sessions.
- D32 (2026-10-20, M6-s3, measured in `TargetsUITests.testNativeAndZTronTargetVelocityUnits`; **user decision 2026-10-20: match SwiftUI**)
  SwiftUI's `ScrollTargetBehaviorContext.velocity` is points per MILLISECOND (UIKit's `willEndDragging` unit; the same real swipe
  reads 0.6 natively and 644 pt/s in ours, on 27.0 and 17.5). `ZTronScrollTargetBehaviorContext.velocity` is therefore pt/ms too
  (`decideTarget` divides its pt/s by 1000; `TargetReleaseInfo.rawVelocity`, `PagingSolver` and the physics stay pt/s;
  `ZTronScrollTargetBehaviorContext(native)` passes SwiftUI's value through), so a behavior ported from SwiftUI sees the same numbers.
- D33 (2026-10-20, UIKIT-s2, measured on 27.0 + 17.5) D31 shell facts. (1) UIKit asks a never-recognizing recognizer `canBePrevented(by:)` but never
  `canPrevent(_:)` nor the delegate's `shouldRecognizeSimultaneouslyWith`; those answers are pinned by `UIKitObserverShellTests`, the UI test asserts `canPrevent == 0`.
  (2) `touchesCancelled` is not produced by a presented sheet or by the window / root view refusing touches; sending the app to Settings mid-press (`-ZTronCancelProbe`,
  4 s hold) produces it on both simulators, so R6 is not needed for the gate (the test still skips where a runtime delivers none). (3) On the observer path
  `GestureAttach.observer` is nil (SwiftUI has no public `EmptyGesture`). (4) The scope gate ignores comments (plain grep hits prose at HEAD). (5) The coverage gate runs
  `llvm-cov` over the derived-data dirs (the demo scheme instruments the package) and takes the union of unit + UI runs on both OSes (`--also-dest`); run it with
  `scripts/coverage-uikit.sh --run --dest <27.0> --also-dest <17.5>` before any commit touching `Gesture/UIKit/` (≈ 25 min).
- D35 (2026-10-21, user report "Refresher … if I pull down slowly, the refresh triggers but only the final part of the view shows"; `docs/progress/USER-s5.md`;
  D34 is DBG-s3's, on its branch) The display of a refresh must not depend on the speed of the pull. Measured with the DEBUG refresh trace on 27.0 and
  17.5 (`RefreshUITests.testASlowPullShowsTheWholeIndicatorUntilTheLift`, default / custom / system): the reveal (visible thickness = min(pull, indicator
  height)) and the whole indicator at the trigger were right at every speed; the speed-dependent part was the action returning under the finger. A slow pull
  outlives the action (0.6 s), and the engine dropped the refreshing look at once (spinner → ring, mode `.notRefreshing`, announce "Refresh complete") and
  opened no hold at the lift, so the indicator was gone at release; a fast pull lifts first, holds, and shows the spinner. `UIRefreshControl` keeps a refresh
  that ends mid-drag on screen until the touch ends (S9: "unless the user is tracking"). Rule now: an action that returns while the finger is down changes
  nothing on screen (`mode` stays `.refreshing`, `dragPosition` 1); at the lift, if the indicator has been refreshing for `minimumVisibleTime` counted from the
  TRIGGER the refresh just ends (no hold, the content springs back to rest), otherwise the hold opens for the time that is missing (`finishing(until: trigger +
  minimumVisibleTime)`); an action still running at the lift behaves as before. Unchanged and shared by both speeds: at the end of a refresh, and at a
  release below the trigger, the indicator still disappeared at once instead of retracting with the content (`USER-s5.md` Open 1; done in D39).
- D36 (2026-10-21, user decision after the SHEET-s1 spike, `docs/design/SHEET-spike.md`) Bottom sheets. Measured: a drag that starts on a `ZTronScrollView` never moves the sheet, on 27.0 and 17.5, all five gesture paths (any recognized SwiftUI drag or `SpatialEventGesture` does that; pinch / double tap do not; masking with `including: .subviews` frees the sheet). Decided: (1) the default is documented as a limitation (`.scrolls` without hand-off; SPEC S12 "Inside a bottom sheet", S8 behavior bullet, two parity rows); (2) `View.ztronScrollYieldsToSheet(_ yields: Bool = true)` (S11) is built: environment-backed, masks the whole gesture set with `.subviews` while true, driven by the app from its detent selection (`selection != .large` ≙ `.resizes`); (3) no live top-edge hand-off (needs UIKit), recipe via the delegate (lift with offset < -60) instead. Builder brief in `docs/progress/SHEET-s1.md` Next. Implemented in SHEET-s2 (`docs/progress/SHEET-s2.md`): a deceleration in flight at the flip is not interrupted (settles, clock stops); the 15–16 UIKit observer's events are dropped at the coordinator while the flag is true.
- D38 (2026-10-21, DBG-s6, `docs/progress/DBG-s6.md`; D34 and D37 are on the DBG-s5 branch) SwiftUI's `scrollDisabled(_:)` now stops a `ZTronScrollView` (it did nothing before, on every OS path, in a sheet or not;
  `ztronScrollDisabled(_:)` worked because it also writes our own key). Root cause: `NativeScrollEnabledReader` was a `ViewModifier` whose body returned its content; SwiftUI never evaluated that
  body (measured: a body counter stayed 0 on 27.0, the same code as a leaf `View` ran once and followed every flip), so `PanCoordinator.nativeScrollEnabled` was always `true`. Fix: a leaf `View` in a background reads
  `\.isScrollEnabled` (`PanGestureAdapter.swift` `NativeEnabledBridge`, `ScrollEnvironment.swift`). Behavior change for apps: `.scrollDisabled(true)` on a `ZTronScrollView` or on any ancestor (a Form, a screen root) now disables
  it, as SPEC S8-1 always said (the nested R7 idiom with a native `scrollDisabled` works too). A disabled view never moves from a drag; a viewport change still moves it (visible centre kept, S7). The 9 pt "residual offset" of
  SHEET-s1 V6b/V8b was that: the harness readout grew by three lines and shrank the viewport by 18 pt. Rule for the library: an environment reader is a leaf `View` (background), never a `ViewModifier` that only returns `content`.
- D39 (2026-10-21, USER-s6, follow-up of D35 / `USER-s5.md` Open 1, `docs/progress/USER-s6.md`; D34 / D37 are on the DBG-s5 branch) The refresh indicator retracts with the content, as
  `UIRefreshControl` keeps the spinner glued to the content edge until the gap closes (before, the engine went idle and the leaf was removed on the frame the content was still sliding back).
  Engine phase `.retracting(RetractLook, until:)` + effect `.retract(look?)`, entered where the engine used to go idle with the content still pulled (> 0.5 pt): a lift below the trigger or a
  cancelled one (look `.pull`: ring / arrow with the falling progress), the end of a refresh at the lift or by `resetAnimation` and the early-return release of D35 (look `.spinner`: a display-only
  override of the built-in indicator, `ZTronRefreshState` unchanged). In it `mode` is `.notRefreshing` and `dragPosition` follows `pull ÷ trigger` down to 0; it ends at pull ≤ 0.5, when a new pull takes
  over, or after 3 s. NOT "settled and not tracking" (the first flush after the lift runs before the release motion starts). Not entered for `sequenceEnd` / a missed lift, a disabled edge,
  `resetAnimation: nil`, or a pull already gone; an overlay edge keeps its own formula (slides out with the pull). Deviation from the proposal, measured on 27.0: the default reset
  `.swiftUI(.easeOut(0.3))` JUMPS the state's offset to rest in the call (`writeBoth` in the inset-only rule: presentation 0 at +0 ms, no clock, no flush) while SwiftUI draws the content 60 → 0
  over ~0.3 s from +60…100 ms (`state.probe`), so sampling the state cannot follow it. Hence: the retraction's effects are applied in ONE `withAnimation(resetAnimation)` and the leaf draws through an
  animatable placement (`RefreshPlacementEffect`, `pull` = `animatableData`), so SwiftUI interpolates the indicator in the content's transaction; and while an edge retracts the engine is fed
  `max(state pull, last drawn pull)` and sampled on a 30 Hz beat when the frame clock is idle, so it ends when the DRAWN content is at rest (no guess of the animation's length). Clock-driven motions
  (the release pipeline, `.uikit` reset) are sampled by the frames as proposed.
- D41 (2026-10-21, M6b-s1; the user's request + refinements R1–R5 in `docs/design/M6b-content-overlay.md`; D40 is taken on another branch)
  Content-integral overlay: an overlay laid out in the unscaled content space by LAYOUT, never by state. The host is the first modifier on the
  content (`.overlay(alignment: .topLeading)`), so it gets the content's size in the same pass, sits under the transform (scrolls and zooms
  with the content at render time) and inside both content spaces (a `ztronScrollID` in it is a target). A reflow is one layout pass whose
  frames SwiftUI interpolates with the content's curve, so the overlay stays glued to its content point every frame with nothing written
  to the state (measured ≤ 6e-14 pt vs a content marker across drag, 4 rotations and a pinch). The iOS 15 host is a `GeometryReader`
  because its closure was measured flat under `ContentTransform` (scroll, zoom, `.disabled` flips; 17.5 / 27.0, both paths). Re-render
  rules (the user's non-negotiable): no user body, no host body during motion; equal `Equatable` overlays keep their `AnyView` (an
  `EquatableView` inside `AnyView` did not gate the body); `.counterScaled` is a leaf on the target zoom alone (new
  `targetZoomChannel` on 15–16). Accepted cost, documented in S4: on 16+ an overlay holding a control is re-placed (layout only) about
  twice per gesture by the content gate's `.disabled` flips. Overlays do not extend the scrollable range; the overlay subtree drops the twin
  list (no recursion).
  Revision (user, 2026-10-21, M6b-s2, design R6): `.fillMaxWidth(height:)` / `.fillMaxHeight(width:)` take the free axis as
  `ZTronContentOverlayLength` (`.ideal` = SwiftUI decides, `.aspectRatio`, `.absolute`, `.relative` = fraction of the content on that
  axis); every `.relative` runs on a clamped unit type (`ZTronUnitLength` / `ZTronUnitSize` / `ZTronUnitPoint`, because SwiftUI's
  `UnitPoint` does not clamp); `ZTronContentOverlaySize` is a struct of static constructors with canonical equality (equal iff it draws
  the same frame), so `.fillMaxWidth(16/9)` still compiles. The user kept the twin environment-only (no `Self`-returning twin member).
  Revision R7 (user, 2026-10-21, M6b-s3: "Clamping should at least produce a log"): every silent normalization of caller input is
  reported in DEBUG builds by `ZTronDiagnostics` (NSLog, caller `#fileID:#line` through defaulted `fileID:line:` parameters on the clamping
  inits, size constructors, both modifiers and `ztronScrollCounterScaled`; literals re-reported with the enclosing call's location; once
  per site and value, ≤ 8 values per site, 512 keys); compiled out in release.
- D50 (2026-10-25, user, Open item 1) ScrollArbitration stays as frozen: on iOS 15–17 ZTronPages drives its pager with a
  SwiftUI pan (or a recognizer outside the hosting view) while a participant answering `.container` drops its drag (spike
  option (a), MC-contract §6 note E); 18+ keeps the gesture-name route. No contract change, so 1.0.0 can be tagged once the
  package has its own repo (user, item 5). A ZTronPages integration design that realises this comes first (item 2).
- D52 (2026-10-25, DBG-s9, `docs/progress/DBG-s9.md`, Open item 7) UIKit's "Observation tracking feedback loop detected" must
  stay at 0: `scripts/run-filtered.sh` (used by `scripts/test.sh`) counts it in the full log and a run that prints it exits 1
  with an `error:` line naming the objects. In the unit tests the warning came from the app-less process (UIKit's counts never
  clear and are keyed by address), so on iOS 26+ test windows holding a `UIScrollView` and their scroll views stay allocated
  until the process exits, retired (hidden, content dropped) by `unhost` or the next test's `host()` (`ScrollViewWindows`);
  a test whose native scroll view appears after `host()` and is never unhosted calls `keepIfScrolling` itself. No library change.
- D51 (2026-10-25, M8b-s3 builder; refines SPEC S7 for the scaling header) A resize (rotation, a `size` or `.fit` change) keeps the
  header's place: `o′ ≤ 0` (rest, a pull, a refresh hold) is kept, inside the band the collapse progress (`o′ = p · band_new`), and a
  collapsed header stays collapsed with the visible centre BELOW its minimum height preserved. Carried by the M5 intent
  (`ResizeIntent.header`, `ResizeCommit.Snapshot.header`, interpolated with the drawn size), so the transform effect realises it per
  frame and the sticky intent restores it exactly. The M5 header term is `h − R` (the resting height is in `adjustedContentInset.top`
  since M8b-3), negative while collapsed; `ScrollMetrics.headerObscured` is not used by the header (M9 reads `HeaderMath.obscuredDelta`).
  The user may veto: the alternative (centre rule everywhere) moves the header's progress on every rotation.
- D59 (2026-10-25, user, M8b-s3; numbered at the merge 2026-10-27, cited as D52 on the M8b-3 branch, which collided with
  DBG-s9) Header overflow policy `ZTronHeaderOverflow` on `withScalingHeader`: `.uncapped` (default: the size's own resting height,
  even taller than the container, so the content starts below the screen), `.capped(fraction:)` (at most that fraction of the
  container's height) and `.refit` (`.aspectRatio(r)` becomes the aspect fit inside `W × H`, `.fixed` / `.fit` limited to `H`);
  `min` is limited the same way. Resolved against the container below the adjusted safe area of each orientation, inside the same
  resize commit. Code: `ScalingHeader/HeaderTypes.swift`, `HeaderMath.swift`; tests `HeaderMathTests`, `HeaderResizeTests`.
- D61 (2026-10-26, user, M8b seamless header; numbered 2026-10-27) `.preserve` reverses A1: under a pull past the top the header
  moves down with the content at its resting height (no gap between header and content; the gap, and a `.preserve` refresh
  indicator, open above it). Since D65 this pull is the opt-in `ZTronHeaderPullBehavior.followContent`; the default `.openGap`
  is A1's still header again. `withScalingHeader(…, background: ZTronHeaderBackground? = nil)` wraps the header content in a container
  that fills the live frame in every animation: `.ambientBlur(radius:)` (a blurred, scaled-to-fill second instance of the header; its
  body runs per cold change, its readers are cold), `.frostedGlass(radius:)` (the system Material closest to the radius, approximate),
  `.color(_:)`, `.view { }`. Code: `ScalingHeader/HeaderTypes.swift`, `HeaderFrameModifier.swift`; SPEC S10.
- D62 (2026-10-27, lead, M8b-s4…s6; requirement: user 2026-10-26, "mission critical") Seamless scaling header: its frame comes from
  layout (`HeaderSlotLayout` on 16+, iOS 13 modifiers on 15/16), `h = (1 − p)·R(W, H) + p·min + stretch`, with `R(W, H)` and the D59
  policy resolved by layout against its slot (proposed between the safe areas) exactly as by the state, and `p` / stretch / the
  `.preserve` translation bit-stable across the unanimated resize commit; rigid layer groups (`geometryGroup` 17+, `compositingGroup`
  on 15/16 only with a header, latched) make system rotations follow Core Animation; `.fit` measurements are adopted in the viewport
  commit or in the transaction of the change that caused them; the refresh indicator is drawn at the presented geometry during a
  resize; the M5 resize progress is no longer clamped (spring overshoot, additive retargets) and a safe-area-only step shifts the open
  transition. Rejected after measuring: a render-time mask edge (spike B, `spike/seam-b-render-mask`: masks sticky overlays) and the
  state-driven height (one-frame jumps of 35–90 pt). Spikes A / C: `spike/seam-a-layout-header`, `spike/seam-c-rigid-group`. Limits: open item 15.
- D63 (2026-10-27, review d16 fixer; USER RULING 2026-11-02: an option, not a yes/no: an enum parameter of `withScalingHeader` whose default is this behaviour; open item 15 (a)) Under a scaling header, content smaller than the
  viewport is top-aligned vertically (horizontal alignment kept), whatever `defaultScrollAnchor(_:for: .alignment)` or the zoom
  default says, so it starts at the header's bottom edge (centred, it sat 119 pt below the header). One computed
  `ZTronScrollState.contentAlignment` feeds ContentTransform, ResizeMath and RefreshMath. SPEC S6 / S10 "Content that fits".
- D64 (2026-10-27, lead; clarifies D59, whose container is "below the adjusted safe area of each orientation") The overflow
  container excludes the keyboard: the `.capped` fraction, `.refit`'s `H`, the `.fixed` / `.fit` limit and the `min` limit are resolved
  against the region between the safe areas WITHOUT the keyboard's part of the bottom one, so the system keyboard never changes `R`
  or `min` and there is no header animation to match (before: landscape `.capped(0.5)` R 191 -> 89 with the keyboard up; its
  dismissal animated the header's slot in the keyboard's animation, which never reaches the container's `.transaction` hook, while
  the content's inset landed at once: an 85-95 pt gap closing over ~30 frames, 27.0). The content's adjusted inset still includes
  the keyboard (it scrolls above it; S8 unchanged); app-provided safe areas (`.safeAreaInset`, bars) still count (their animated
  path is drawn in the turn's animation since eebb2a4). Mechanism: the header's slot also ignores the `.keyboard` region on the
  bottom edge; a cold zero-height probe on the container's bottom edge ignores the same region, so its height is the keyboard's
  extension above the keyboard-free safe area (`ScrollMetrics.keyboardExtension`, 0 without a keyboard), recorded from its own
  layout pass on 16+ (`KeyboardProbeLayout`: a geometry action of its own reached the state after the viewport's on 27.0) and
  carried by the viewport preference on 15 / forced; `HeaderMath.containerHeight` gives it back. With an engaged limit the header
  can be taller than the region above the keyboard (landscape `.capped(0.5)`: 191 pt over 178 pt): it collapses as the content
  scrolls. Code: `Render/ViewportSpaces.swift`, `ZTronScrollView.swift`, `ScalingHeader/HeaderMath.swift`; tests `HeaderKeyboardTests`,
  `HeaderMathTests`; seam lab `kbreal` / `kbrotate`; SPEC S10 "Overflow".
- D65 (2026-10-27, user: "I would like the scaling header (open gap / follow content) to become a viewmodifier that defaults to
  .openGap") The pull of a `.preserve` scaling header is a setting, `public enum ZTronHeaderPullBehavior: Hashable, Sendable {
  case openGap, followContent }`, default `.openGap`: the environment twin `View.ztronScalingHeaderPullBehavior(_:)` (every
  `ZTronScrollView` below it; it travels in `ztronScrollConfig.headerPull`, the innermost twin wins) and the member
  `ZTronScrollView.scalingHeaderPullBehavior(_:)` (wins; order-independent with `withScalingHeader`, which stays member-only).
  `.openGap` restores the pre-D61 math (bd6ee6a^): the header stays still at its resting place and height (translation 0), the
  gap opens between its bottom edge and the content's top (`HeaderMath.gapBelow`, pre-D61 `contentGap`), the `.preserve` top
  refresh indicator sits there at the plain base `aci.top − hold` (`refreshTop` nil; it follows the inset in a resize,
  `RefreshResizeEffect` `baseFollowsInset`), `obscuredDelta` is `h − R` (0 under a pull: the indicators' track starts at the
  still header's bottom). `.followContent` is D61 unchanged. `.stretch` ignores the setting; a banner (no vertical axis) is
  unaffected (it keeps D61's translation, reachable only through D15's zoomed vertical pan). Mechanism: the container's body,
  which already reads `envConfig` for the other config twins (a View body, not a modifier returning bare content), resolves
  member, else twin, else `.openGap` into `HeaderSizing.pull` → `HeaderMetrics.pull`, so a change is a cold spec change
  (`headerSpecChanged()` through `onChangeCompat(of: sizing)`): no content body runs (the header builder runs once, as for any
  container re-evaluation, R7), and during a live pull the header takes the new mode's place in that update (animated if the
  change is). Both header paths read `HeaderLiveInput.translation` (16+ `HeaderSlotLayout` placement, 15/16 `HeaderTranslation`);
  with `.openGap` it is always 0, so the live input under a pull differs from the rest's in `o′` only (no per-frame cost, D62
  bit-stability untouched); background and fade are inside the framed stack in both modes. Code: `ScalingHeader/HeaderTypes.swift`,
  `HeaderMath.swift`, `HeaderSpec.swift`, `ScalingHeaderAPI.swift`, `Modifiers/ScrollConfigTwins.swift`, `ZTronScrollView.swift`;
  tests `HeaderMathTests`, `HeaderInsetConsumerTests`, `HeaderLayoutFrameTests`, `HeaderPullBehaviorTests`, `HeaderUITests`
  (`testProfileOpenGapHeaderStaysStillUnderAPull`; the D61 test runs with `-ZTronHeaderPull followContent`); demo
  `-ZTronHeaderPull`, seam lab `-ZTronSeamPull` (`opengap` / `follow`, `analyze.py --open-gap pull|hold`); SPEC S10. Measured
  (27.0, 17.5, 27.0 forced; pull, pull + refresh hold + end, rotation during a hold, snap, `withAnimation` scroll through the band,
  `.ambientBlur` pull, `.stretch` pull, both modes): `.openGap` header still under the pull (header bottom and height within 0.5 pt
  of rest, gap − pull within 0.33 pt), every other seam within 0.67 pt, lateral within 0.17 pt, no one-frame step above 0.25;
  limits: open item 18.
- D66 (2026-10-28, lead; open item 20) On iOS 15–16 (and the forced fallbacks) a custom refresh indicator in a view WITHOUT a
  scaling header stays ungrouped, which keeps its blend modes (final check of D65), so SwiftUI keeps no layer for it off the screen
  and a rotation or resize that takes its gap off the screen and back drew it over the content. On that path, while a resize is open
  and the indicator had no visible extent when it began, it is drawn at opacity 0: no group, no identity change, no body run (opacity
  only, `RefreshResizeReveal` in `RefreshPlacementEffect`). Amended by measurement (the builder, same day):
  "until the resize closes, then show it" changed nothing in a rotation (the resize watch closes one run-loop turn into it,
  M5-s2, while Core Animation runs the rotation; logged: hidden, then shown 1 ms later: top 10 / leading 15 frames over the content)
  and hid the indicator through a `withAnimation` resize that open item 21 draws in place (height 0.4 and back: 16 frames missing).
  So it is shown at once when the resize is drawn frame by frame (`phase == .animating` while open), and a resize that closes
  undrawn (a rotation) shows it in a 0.1 s animation of its own (opacity 0 for 85 % of it), set by `.transaction` (the close is
  written with `disablesAnimations`, which ignored `.animation(_:value:)` and a delayed opacity animation). Measured, forced lane,
  headerless hold: rotations 0 frames over the content, the missing frames those it already had on the way out (a longer reveal
  only added missing frames: 0.3 s 43 / 38, 0.6 s 63 / 61 for top / leading). Code `Refresh/RefreshIndicators.swift`; test
  `RefreshIndicatorTests.aResizeThatBeganWithNothingVisibleHidesItUntilItIsDrawnFrameByFrameOrOver`; SPEC S10 "15–16 layer groups".
  Amended 2026-11-01 (review of item 21 follow-ups, 18620ed; the semantics above unchanged, only the reveal's curve): the 0.1 s
  reveal was drawn over the content. SwiftUI animates the values an Animatable modifier's body derives (its inner opacity)
  with the transaction's animation, delay included, so the 85 % hold was a 0.1 s fade from ~0.18 s into the 0.3 s rotation
  (forced leading: 4 frames at 33-82 % opacity over the content, invisible to the opaque-only `holdgap.py` of the time). The
  reveal is now plain opacity with `RefreshResizeReveal.afterTransition` (`.linear(duration: 0.15).delay(0.3)`, set by the
  same `.transaction`; the transaction fires 1 ms into the resize, an iPhone rotation lasts 0.3 s): it fades in once the
  rotation has landed the content. The gate reads the boxes' latched group decision (`RefreshGroupLatched`, the `GroupLatch`
  of the group itself) instead of computing it live. Forced headerless rotations (4 edges): 0 frames over, translucent
  included, 0 off; missing 23-30 (opaque 0.17-0.18 s after the rotation lands; delay 0.4: 27-43). Test
  `RefreshIndicatorLayerTests.theFifteenIndicatorGroupIsOnlyUnderAHeader` (gate note `refresh.d66`).
- D68 (2026-11-01, user request 2026-11-01; lead decisions 2026-11-01; built 2026-11-02, M8b-s7) Scaling-header collapse
  modes: `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)`, `collapse: ZTronHeaderCollapseBehavior =
  .compress` (a struct: `.compress`, `.slideBehind` = parallax 0.5, `.slideBehind(parallax: CGFloat = 0.5, backdrop: Color? =
  nil)`, parallax clamped to 0…1, NaN → 0.5). `.slideBehind` keeps the resting height `R`, is drawn BEHIND the content (the
  container's always-present `.background(alignment: .top)` slot beside the `.compress` overlay slot, both after
  `.ignoresSafeArea` with the same safe-area pair) and moves up by `k · c`; band `R` (`min` ignored), progress / snap positions
  = the covered fraction; `backdrop:` = a color behind the content in its own space (nil → `Color.clear`, structure fixed);
  clipped at the scroll view's frame, not at `top0`; touches reach the uncovered band; a runtime mode switch re-installs the
  header (`@State` reset, accepted); a header change that keeps the insets but changes the band keeps the progress. 16+
  `HeaderSlotLayout` places at `minY + t_g − k·p·h`, 15 / forced `HeaderTranslation` is a `GeometryEffect` (same formula from its
  size). SPEC S10 "Collapse (D68)". Final (closer, 2026-11-02): built, reviewed (correctness + seamless), fixed in two rounds and
  re-checked twice; review C-RC-1 (doc comment) and C-RC-3 (collapse-aware DEBUG note) fixed, C-RC-2 (banners under D15's zoomed
  pan are covered) in SPEC S10; limits: open item 29 (15–16 blend modes), S-RS-2 (item 15 (b), the same under `.compress`). Not
  merged into main.
- D69 (2026-11-01, user request 2026-11-01, built 2026-11-01, M8b-s7) `pull:` (the former `scalingBehavior:`, same type
  `ZTronHeaderScalingBehavior`; the old label is a deprecated overload WITHOUT a default that forwards to `pull:`, renamed to the
  new member without `collapse:` so the fix-it maps the label) and `.stretch` = a render-time scale: the layout height never
  includes the stretch (`liveHeight`, `stateHeight`, `HeaderFallbackPlan`), the leaf draws the framed stack through
  `HeaderStretchEffect` (`GeometryEffect`, `s = (h + g)/h` from its own size, anchored top-centre) and clips it with
  `HeaderStretchClip` (`W × h·s`, `Path(rect)`), Animatable on `o′`. Replaces the relayout growth, which left an aspect-fit image
  unchanged (the user's banner never grew). `ZTronHeaderGeometry.height` is the drawn height; readers inside the header are scaled.
  Limits: text / vector art blur while pulled (open item 28), +0.125 pt in-motion bias at a non-integer `R` (accepted).
  SPEC S10 "Pull `.stretch` as a scale (D69)". Refresh under `.stretch` (fixer rounds 1–2, 2c6bba8 / e0d2a8b; SPEC S10 "Refresh
  with the header"): a hold's indicator (not an `overlay:` refresher) is drawn only over the stretched band, on its far end (the
  content's top), and goes up with the content when the hold is scrolled away (S-RS-1, HIGH, pre-existing since M8b-3, and item 30:
  168–275 → 0 frames over the content on 27.0 / 17.5 / forced); a `.system` spinner is centred in the band (`min(s, L)/2`, the
  gap's place) while refreshing and retracting (R1-RC1-1). Final (closer, 2026-11-02): open items 28 (text blur), 31 and 32 (the
  `.system` spinner's steps at a low trigger and at a re-grab during its retraction) wait on the user. Not merged into main.
- D70 (2026-11-01, user request 2026-11-01 "rest + per-direction, crossfaded", built 2026-11-02, M8b-s7) Split fade:
  `ZTronHeaderFade { rest, collapse, pull: Gradient? }`, `Gradient.linear(to:from:)` (start clamped), `init(rest:collapse:pull:)`,
  `.linear(to:from:)` = the same gradient in every state. Weights collapse `p`, pull `min(1, g / (R/2))` with `R` the stack's
  layout height (follows an animated resize); one gradient for one colour (stops at the union of the starts: exact), the
  over-operator pair with 8 cosine-spaced interior stops for two; `nil` = no fade in that state; `start` 1 = no visible fade. Drawn
  per frame by `HeaderFadeOverlay` in the header's leaf before the stretch effect (it stretches / moves with the header); the
  cold host fade is gone; the pull rides the live input only when `pull != rest` (`HeaderLiveInput.geometry` strips it for the
  layout). SPEC S10 `fade:` paragraph. Final (closer, 2026-11-02): no review finding; design risk 4 (gradient lag) none on 27.0 /
  17.5 / forced (opacity error ≤ 0.023, steps equal the model within 0.01); the resize step found in step 5 fixed (c0a3342). Not
  merged into main.
- D76 (user, 2026-11-02, on the M8b-s8 i28 design) `.stretch`'s header content is an OPTION, not a look change: an enum
  parameter of `withScalingHeader` (beside D75's), default `.keepTextMagnified` (the user's name) = D69's look, the whole header
  (text, symbols, controls, images) magnified by `s` while pulled. The other case (name proposed by the batch) is the i28 design:
  the stack laid out at `(W·s, h_L·s)`, top-centred and clipped, so text keeps its point size and stays crisp while the aspect-fit
  image grows exactly as with D69. The default must still be crisp: open item 28 stays a FIX for `.keepTextMagnified`. The i28
  designer found no pure-SwiftUI lever that re-rasterizes a magnified leaf (group changes, `\.displayScale`, `drawingGroup`
  variants; `drawingGroup` draws platform views as placeholders, which D74's rule refuses). So workflow `d76-magnified-eval`
  evaluates pure SwiftUI once more, then a scoped UIKit raster path (D31's pattern: active only for `.stretch` +
  `.keepTextMagnified` while pulled, 100 % line coverage, capability + force flag, `scripts/check-uikit-scope.sh`). SPEC S2 / S16
  and the CLAUDE.md non-negotiables change only after the user accepts that evaluated design. Docs: the i28 design (grow) and
  `d76-magnified.md` (evaluation), committed under `docs/design/` by the batch.
  **ACCEPTED (user, 2026-11-03): the crisp path is the scoped UIKit raster engine.**
  - Where: `Sources/ZTronScrollView/ScalingHeader/UIKit/`.
  - What it does: while the header is drawn magnified, its drawn layers get `contentsScale` = native·s and its platform views
    `contentScaleFactor` = native·s; every value is restored exactly at rest.
  - Gating: capability `.headerRasterDensity`, DEBUG flag `-ZTronForceRasterDensityOff`, 100 % line coverage and the scope gate.
  - Measured: text goes from ×1.37–1.79 of native to ×0.89–1.04; 0 px at rest on 27.0.
  - Rule text: `d76-magnified.md` §5, with §11.5's repairs. M8b-s9 applies it as one amendment together with D77′'s probe.
  - §11's open gaps are build acceptance items, not limits:
    - the probes add nothing to the accessibility tree;
    - A1: inside native text's own ±0.12 pt envelope at every size and frame;
    - A9 counts the redraw;
    - 17.5 is 0 px at rest after a release.
- D77 (user, 2026-11-03, on the M8b-s8 i29 design) Item 29 takes the PUBLIC route (the design's D77′): on the 15–16 path one
  layer group G around the content and the `.slideBehind` slot, plus a 0 × 0 `UIViewRepresentable` probe that turns off the public
  `allowsGroupOpacity` on G's layer and on the header's group. It fixes item 29 and makes 15–16 fades equal 17+. G moves every
  content leaf per frame (+1.1–1.5 ms per step at 100 rows, +11–15 ms at 1 000–1 500 non-lazy rows, 27.0 sim under load,
  i29 §6.5), accepted with the route. NOT built: route P (the probe also turns off the PRIVATE `allowsGroupBlending` by key;
  15–16 equals 17+ in every pixel at no per-frame cost; App Review 2.5.1 risk for every linking app). By this ruling the three
  pre-existing 15–16 blend differences only P closes stay (a content blend against what is behind the scroll view, a header's
  own blend, an indicator's blend under a header): a recorded decision, not a known limit. The user asked that route P be
  DOCUMENTED for a future switch: mechanism, measurements, spike patch and switch steps go into the repo
  (`docs/design/D77-route-P.md`, the patch under `docs/design/spikes/`), and SPEC S10 points to it. The probe needs the S16 /
  CLAUDE.md scoped-UIKit exception (accepted with the route; verbatim text written by the build batch). Built in M8b-s9 after
  M8b-s8 closes, together with D76's crisp `.keepTextMagnified` if the user accepts that design; then the custom headerless
  indicator is grouped (i29 §5.5) to close item 27's 15–16 rotation-start residual.
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
| 2026-10-20 | Sonnet 5.5 side session M8-1 (Builder) | chrome exemplar: `Chrome/{ChromeConfig,ChromeLeaf,ScrollIndicators,NativeChromeBridges}`, indicators (member + twin + mirror + hot leaf + fade controller + state API), 3 hunks in `ZTronScrollView` / `ZTronScrollState` / `ScrollMetrics`; `showsIndicators:` order measured on a hosted native ScrollView; 79 new tests; verified in a clean worktree at e650494 (other sessions had in-flight edits in the shared files) | all 48% · Fable 85% at the end (all sessions together; this one is Sonnet, ~530 K context tokens, mostly waiting on shared simulators) |
| 2026-10-20 | Sonnet 5.5 side session M6-s3 (Builder) | M6 session 3: Position driver + `scrollPosition` ×2, `defaultScrollAnchor` + roles, bridges, TargetsScreen/TargetsUITests; R4 (D32), R5, Open 4 closed; found and fixed a 17.5 xctest crash (iOS 18 type in a class's stored property); verified in a clean worktree because M7/M8 edits were live in the shared checkout | not measured |
| 2026-10-20 | Sonnet 5.5 side session UIKIT-s1 (Builder, session (a)) | D31 core: `TouchObserverCore` + `TouchObserverCoreTests` (core 100 %), `uikitTouchObserver` capability + `forceUIKitTouchObserver`, state `let`; two deviations from the design sketch (batch time parameter; magnification continuous across pair changes); coverage must be read with llvm-cov (xccov omits library files); unit 520/520 ×2 in a clean worktree |
| 2026-10-20 | Sonnet 5.5 side session M8b-2 (Builder) | refresher API + resolver + indicators + accessibility + demo `refresh`; `RefreshUITests` found a double action at the lift (M8b-1 coordinator, fixed); verified in clean worktrees (HEAD 615d43f + this change) because other sessions had in-flight edits; 582 unit tests ×2 OS | not measured |
| 2026-10-20 | Sonnet 5.5 side session UIKIT-s2 (Builder, session (b)) | D31 shell: `UIKitTouchObserver.swift`, wiring, demo probes, `UIKitObserverUITests`, both gate scripts (coverage 100 % lines, scope clean); `touchesCancelled` produced by backgrounding the app mid-press (sheet / window toggles do not); dedicated simulators, clean worktree at 76823c4; unit 587/587 ×2; one flaky default-path test noted (`testControlsUsable` forced 27.0 under load) | not measured |
| 2026-10-21 | Sonnet 5.5 side session SHEET-s1 (measurement spike) | ZTronScrollView in a bottom sheet: `SheetScreen` + `SheetUITests` (54 characterization tests), results ours vs native on 27.0 + 17.5 × 5 paths, mechanism (sheet's flex pan begins but declines; any SwiftUI drag freezes the sheet), pure-SwiftUI yield by gesture mask measured, recommendation in `docs/design/SHEET-spike.md`; no library change; clean worktree + private simulator clones | not measured |
| 2026-10-21 | Sonnet 5.5 side session SHEET-s2 (Builder) | `View.ztronScrollYieldsToSheet(_:)`: env key + masks in `GestureAttach` / `PinchGestureAttach` (`isEnabled:` on 18+, `including: .subviews` below), coordinator gate + `cancelForSheetYield()`, `CatchObserverState.reset()`; `SheetYieldTests` (14, 26 cases) + `SheetUITests` Y1–Y6 (sheet expands at medium, content scrolls at large, native C1/C2 equivalence, Button tappable, flip during a fling) on 27.0 + 17.5 × preferred / forced / uikit, private fresh simulators; parity row set; handoff `docs/progress/SHEET-s2.md` | not measured |
| 2026-10-21 | Sonnet 5.5 side session USER-s5 (Builder, user report) | slow-pull refresher bug: DEBUG `RefreshTrace` + `refresh.trace` readout, slow/fast probe UI tests (27.0 + 17.5), root cause = action returning under the finger (D35), engine fix + 6 unit tests, `RefreshSlowPullTests` | all 40% → 66% (all sessions together, not separable) · Fable 100% (not this session) |
| 2026-10-21 | Sonnet 5.5 side session DBG-s6 (Debugger) | SwiftUI `scrollDisabled` did nothing to a `ZTronScrollView`: root cause = the `ViewModifier` reader's body never evaluated (D38), leaf-`View` fix, `NativeScrollEnabledTests` (red before / green after, 595/595 unit ×2 OS), `ScrollDisabledUITests` 12 (outside / inside sheet / parent / toggled / vs native) on 27.0 + 17.5 preferred + forced; the 9 pt offset explained (viewport resize); clean worktree + private simulator clones | not measured |
| 2026-10-21 | Sonnet 5.5 side session USER-s6 (Builder, follow-up of USER-s5) | the refresh indicator retracts with the content (engine `.retracting`, animatable leaf placement in the reset transaction, drawn-content beat; D39): `RefreshRetractTests` ×21, RefreshUITests probe + short-pull test; edited in a detached worktree, re-verified at c19bb2e + patch on private 27.0 / 17.5 clones | not measured (host at load 300–900) |
| 2026-10-21 | Opus 5.5 side session M6b-s1 (Orchestrator, ultracode: L1 builder + 2 reviewers + fixer, L2 builder + reviewer + fixer) | content-integral overlay built in a private worktree and fast-forwarded (D41): library + `ContentOverlayTests`, demo flags on the resize screen + `ContentOverlayUITests`; unit 637 on 27.0 + 17.5, UI 17/17 per lane on 4 lanes; handoff `docs/progress/M6b-s1.md` |
| 2026-10-21 | Opus 5.5 side session M6b-s2 (Orchestrator, ultracode: builder + reviewer + fixer) | content-overlay API revision R6 (D41 revision): free-axis lengths for `fillMaxWidth` / `fillMaxHeight`, clamped unit types for every `.relative`, canonical size equality; unit 645 on 27.0 + 17.5, UI 17/17 on 4 lanes (one load flake per OS re-run green); handoff `docs/progress/M6b-s2.md` |
| 2026-10-21 | Opus 5.5 side session M6b-s3 (Orchestrator, ultracode: builder + reviewer + fixer) | content-overlay revision R7 (D41 revision): DEBUG clamp / normalization diagnostics with the caller's location (`ZTronDiagnostics`); unit 659 on 27.0 + 17.5, UI smoke 4/4, release build clean; handoff `docs/progress/M6b-s3.md` |
| 2026-10-25 | Opus 5.5 side session DBG-s9 (Debugger) | Open item 7 resolved (D52): the 27.0 unit run's feedback-loop warnings (203 at 80e2e08) came from UIKit's never-cleared, address-keyed invalidation counts in the app-less test process (UIApp nil) plus native-`ScrollView` windows reusing one address; scroll-view windows + scroll views kept allocated (retired after their test, iOS 26+), `HostWindowTests` (red without the keeper), warning guard in `run-filtered.sh`; unit 676/676 with 0 warnings on 27.0 ×2 + 17.5; private clones | not measured |
| 2026-10-25 | Opus 5.5 side session PAGES-s0 (Architect, design only) | ZTronPages integration design (`docs/design/ZTRONPAGES-integration.md`): T1–T8 per-OS matrix, options A–D, B recommended (paging ZTronScrollView container), spike notes A–E, acceptance A1–A12, split P-a…P-d; handoff `PAGES-s0.md` | not measured |
| 2026-10-25 | Opus 5.5 side session M8b-s3 (Builder) | scaling header (M8b-3): `ScalingHeader/` 9 files + state / pipeline / resize / indicator / refresh / scrollTo hooks, 8 unit suites, demo `profile` + `banner`, `HeaderUITests` 9/9 on 27.0 + 17.5 × preferred + forced; D51; main merged into the branch, not into main | not measured |
| 2026-10-27 | Opus 5.5 integrator stage 2 (M8b-s4) | seam matrix on 27.0 / 17.5 / forced (79 runs), lab refresh / band / combo options, 15/16 `.fit` rotation fix, SPEC S10 known limits, final table `scratchpad/seam/final-table.md` | not measured |
| 2026-10-27 | Opus 5.5 fixer (M8b-s5, review d16) | 9 review findings (7 fixed, 1 fixed + documented 15–16 difference, 1 documented 15-path limit), async-renderer crash in `HeaderSlotLayout`, seam lab `horizontal` / `grow` options and re-measurements, `HeaderReviewD16Tests` | not measured |
| 2026-10-27 | Opus 5.5 side session M8b-s6 (lead, ultracode: closer + verifier + fixer, then a core check: reviewer + full suites) | main merged (D52 → D59), the review finding the d16 fixer never received (an animated height change engaging `.capped`: header slot between the safe areas), refresh indicator during resizes, M5 resize progress unclamped + safe-area steps (spring / retarget / bottom-pinned resizes), D61–D63, open item 15, handoff `docs/progress/M8b-s6.md` | not measured |
| 2026-10-27 | Opus 5.5 workflow subagent (overlay placement root cause) | open item 17: per-frame overlay placements root-caused (the content gate's `.disabled` re-created per frame) and fixed (`ContentInteractionGate`), pre-existing on main; hosted regression test; handoff `docs/progress/M8b-s5.md` "Overlay placement fix" | not measured |
| 2026-10-28 | Opus 5.5 workflow subagent (D65 review fixes) | open item 18 (a) fixed: the refresh indicator box is a layer group laid out at its clip (rotations that take the gap / `.stretch` band below the screen keep it; a translation variant broke `withAnimation` resizes and was replaced), `.stretch` overlay clip; `ProofUITests` content.body 1 (forced) = the quiet-period harness's own parent update (main's library too, native `ScrollView` 6/6), settle label in its own leaf; `HeaderSafeAreaInsetTests` judged per elapsed frame + stalled-sampler test; seam lab 60 runs (27.0 / 17.5 / forced); handoff `docs/progress/M8b-s5.md` "D65 review fixes" | not measured |
| 2026-10-28 | Opus 5.5 workflow subagent (D65 final check fixes) | the 15–16 refresh indicator group isolated a custom indicator's blend modes in every view (forced lane, no header: a `.difference` probe drew white): `RefreshIndicatorGroup`, 15–16 `compositingGroup()` only under a scaling header (latched), 17+ unchanged; demo `blend` / `blendOverlay` + `RefreshUITests` pixel test, `RefreshIndicatorLayerTests` latch test; item 18 (a) seam rotate-hold 9/9 PASS; unit 785 green on 27.0 + 17.5; Refresh/Header/Proof UI 32/32 × 3 lanes; open item 19 (headerless twin, pre-existing) recorded; handoff `docs/progress/M8b-s5.md` "Final check fixes" | not measured |
| 2026-10-28 | Opus 5.5 side session M8b-s6 (lead, cont.: ultracode workflows keyboard+overlay, D65 build+review+suites, final check) | D64 keyboard seam, open item 17 cherry-picked from `claude/overlay-place-fix`, D65 pull behaviour, analyzer `--open-gap` per-segment reference, handoff `docs/progress/M8b-s6.md` | not measured |
| 2026-10-28 | Opus 5.5 workflow subagent (open item 19 builder) | open item 19 fixed: while refreshing, the gap indicator keeps its placement whatever the pull (box group with its far edge on the content's edge, region group from the base clipping to the gap; `.system` continuous below 0 to its hold rest place), so S7 rotations move it with the content; 15–16 group the built-in indicator too, a headerless custom one stays ungrouped (open item 20); seam lab `-ZTronSeamHoldEdge` / `-ZTronSeamHoldOverlay`, `testRotateFromLandscape`, `holdgap.py`; headerless 4 edges 27.0 + 17.5: 0 frames over the content, all in place (before: up to 16 frames over, 3-9 missing); item 18 (a) rotate-hold 9/9 PASS; unit 788 green on 27.0 + 17.5; Refresh/Header/Proof UI 32/32 × 3 lanes; no D-number; notes `scratchpad/i19/notes-build.md` | not measured |
| 2026-10-28 | Opus 5.5 workflow subagent (review of open item 19: A, B, open item 21, D66) | A: a scrolled-away custom indicator leaves VoiceOver's tree (`accessibilityHidden`; XCUITest lists hidden elements, so the demo reads its own `VoiceOverTree`); B: no indicator body while it draws nothing (`BuiltRefreshIndicator`, rig away 20 -> 3, other phases unchanged); open item 21 fixed (box on the content's drawn edge during an animated resize, region at the presented base, cross centring at the leaf: 57 -> 0 frames over on 27.0 / 17.5 / forced); D66 implemented and amended by measurement (item 20 resolved: forced rotations 9 / 15 -> 0 over); unit 793 green on 27.0 + 17.5 (9 known issues); Refresh/Header/Proof UI 33/33 x 3 lanes; seam lab 3 lanes; notes `scratchpad/i19b/notes-build.md` | not measured |
| 2026-11-01 | Opus 5.5 workflow subagent (fix round 2 of the item 21 follow-ups review) | MEDIUM fixed (27bc80f): a hold during an app-animated bottom `.safeAreaInset` (an inset-only change written unanimated) slides out clipped by the frame instead of vanishing (gap) or jumping 150 pt (overlay): `ZTronScrollState.insetFollow` + `RefreshBaseFollow`, the base move drawn in the turn's animation below `RefreshPlacementEffect`; seam lab kbfake 27.0 / forced / 17.5: 26 bad frames -> 0 (gap), overlay 0 bad, worst 0.67 pt; controls unchanged; LOW (D66 reveal after an instant resize) recorded as open item 24 (renumbered 27 on 2026-11-02; 22 and 23 are DBG-s10 / DBG-s12 on main); unit 796 green on 27.0 + 17.5 (9 known issues, 0 feedback loops); Refresh/Header/Proof/Resize UI 46/46 x 3 lanes (27.0 pref, 17.5, 27.0 forced); `scripts/seam/insetgap.py`; no D-number; notes `scratchpad/fu/fx2/` | not measured |
| 2026-11-01 | Opus 5.5 workflow subagent (review of item 21 follow-ups) | A: a19ea0f's 15-16 bottom overlay fix verified (forced: 84/143, a 500 pt step -> 157/157); B: D66's reveal waits out the rotation (plain opacity, 0.15 s after 0.3 s: the Animatable 0.1 s hold was a translucent fade over the content, 4-7 frames forced leading), `holdgap.py` counts a translucent probe and only a probe-sized ring; C: D66's gate reads the latched group (`RefreshGroupLatched`, layer test); seam lab 21 scenarios x 3 lanes: 0 frames over, forced rotations 0 off, missing 23-30 (was 7-15), the rest as at a19ea0f; unit 795 green on 27.0 (9 known issues), Refresh/Header/Indicator 258 green on 17.5; D66 + SPEC S9/S10 amended, no D-number; notes `scratchpad/fu/notes.md` | not measured |
| 2026-11-01/02 | Opus 5.5 workflow subagents b1–b5 (header behaviors, design §6 steps 1–6) | D68 `.slideBehind(parallax:backdrop:)`, D69 `.stretch` as a render-time scale (the user's aspect-fit banner grows), D70 split fade drawn per frame; `collapse:` / `pull:` API + deprecated `scalingBehavior:`; demo `appbanner` (the user's setup) + UI tests; SPEC S10 amended; design §7 risks measured on 27.0 / 17.5 / forced; open items 28, 29, 30 (30 pre-existing: a programmatic `.stretch` hold opening draws its indicator over the content); unit 837/82 suites on 27.0 + 17.5; handoff `docs/progress/M8b-s7.md` | not measured |
| 2026-11-02 | Opus 5.5 workflow subagent (header behaviors fixer round 1) | S-RS-1 (HIGH, pre-existing) + open item 30 fixed (2c6bba8): the `.stretch` hold's refresh indicator is drawn only over the stretched band and on its far end (`RefreshIndicatorMath.inStretchBand`, gap box / region of item 19), so a hold the content is scrolled out of goes up with it and a programmatic opening rides the content's top; seam lab finger fling out of a held refresh (new `testFling`, `probeover.py`): 168 / 170 / 168-275 -> 0 frames over the content on 27.0 / 17.5 / forced, opening 0 frames below the header's bottom, seams unchanged; C-RC-1 / C-RC-3 fixed (fbdc743: doc comment, collapse-aware DEBUG note), C-RC-2 in SPEC S10, S-RS-2 recorded (SPEC S10 + item 15 (b)); unit 839/82 on 27.0 + 17.5 (9 known); Refresh/Header/Proof UI 38/38 x 3 lanes; handoff `docs/progress/M8b-s7.md` "Fixer round 1" | not measured |
| 2026-11-02 | Opus 5.5 workflow subagent (header behaviors fixer round 2) | R1-RC1-1 (LOW, from S-RS-1) fixed (e0d2a8b): a refreshing `.system` spinner in the `.stretch` band is centred (`min(s, L)/2`, the gap's place; scrolled away the gap's rigid rule) and keeps that placement through its retraction (`RefreshIndicatorMath.holdsPlacement`); `holdOffset` 20 / 30 drew 0 / 10 of its 20 pt, now 20 centred on 27.0 / 17.5 / forced; seam lab `hsys<H>` / `hend<s>` + `scripts/seam/spinner.py` (05bc64f, 2860977): 0 frames over the content, 0 one-frame jumps, 0 vanishings in 21 recordings, seams as recheck1; open item 31 (trigger below `indicatorHeight`, non-default); unit Refresh* 50/3 on 27.0 + 17.5; Refresh/Header/Proof UI 38/38 x 3 lanes; handoff `docs/progress/M8b-s7.md` "Fixer round 2" | not measured |
| 2026-11-02 | Opus 5.5 workflow subagent (header behaviors closer) | docs only: our open item 24 renumbered 27 (main's 24–26 are other sessions'; main's 27+ checked free, `git log --all` too); open items 32 (RC2-1, re-check 2: a re-grab during the `.stretch` `.system` retraction steps the spinner) and 33 (17.5 `.preserve` re-catch arrow, pre-existing, triage); D68–D70 rows final; Next step 6 (user decisions first, device check, merge); `M8b-s7.md` final results (build steps, review findings and their fate, suites per lane, design §7 risks per lane, open items, merge notes); STATE row; parity rows for `withScalingHeader`, the refresh indicator under a header and 15–16 layer groups; SPEC S10 amendment wording (retraction at the default `holdOffset`, item 32); leftover workflow simulators and derived data removed | not measured |
| 2026-11-03 | Opus 5.5 workflow subagent (M8b-s8 s1, builder s1-refresh-31-32, resumed twice) | open items 31 and 32 fixed (8e0f364: the engine's carried spinner look, L2, L3, the C8 handover; lab `rtrig` / `hdef` / `rdur` / `rbegin` + `handover.py`, 61c7e21); a begin during a retraction switches in the cross-fade (fb4c52e); open item 41 found and fixed (170c1d3 … 782513b, 285a535: the cross-fade and the begin's switch drawn: `ZStack`, 24 pt square, `RefreshLookFade`, `RefreshGlyphBoundary`); unit Refresh* 124/124 on 27.0 + 17.5, `RefreshUITests` 17/17 on 3 lanes; SPEC S10 amended (both known limits removed); handoff `M8b-s8-s1.md` | – |
