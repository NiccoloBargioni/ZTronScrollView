# M8b-s5 handoff · 2026-10-27 · Opus 5.5 fixer (review d16 of the seamless header)
Status: done for the nine review findings (7 fixed, 1 fixed + documented difference, 1 documented 15/16 limit) plus one
crash found while measuring. Branch `m8b3-seamless-final` from `df36258` (M8b-s4). Main is not merged in.
Changed:
- `ScalingHeader/HeaderMath.swift` `liveHeight`: a banner (no vertical axis) is laid out from layout too (`R(W)`, its
  committed overflow container); `HeaderFrameModifier.swift` `HeaderFallbackPlan`: banners take the aspect box on 15/16.
- `HeaderFrameModifier.swift` `HeaderSlotLayout`: reports a `.fit` measurement only from the main thread (crash, below).
- `.fit` re-measure in the change's transaction: `HeaderHost` records the animated transaction of an update that reaches
  the header content (`.transaction` reader) with its run-loop turn (`ZTronScrollState.headerContentTransaction`,
  `headerTurn`); `adoptHeaderNatural` adopts a measurement of that turn in it (16+: the deferred report; 15 at rest: the
  same update); unanimated as before inside a resize.
- `State/ZTronScrollState.swift` `contentAlignment`: with a scaling header the vertical alignment is the top.
- `ScalingHeader/HeaderSnap.swift`: an expanded target leaves a resting view at or above rest; from the band it goes to
  the top rest (`o′ = −hold`).
- `HeaderTypes.swift`: `material(radius:)` monotonic over the line (`+∞` ultraThick, `−∞` ultraThin, NaN regular);
  `blurRadius` (`+∞` = `maximumBlurRadius` 1000, negative / NaN = 0); docs.
- `State/ZTronScrollReader.swift`: cold readers (`ztronColdReaders` environment): the `.ambientBlur` copy's readers wake
  on the metrics only and show the geometry then (an untracked read), never per frame.
- `Render/ContentTransform.swift` `ContentLayerGroup`: 15–16 `compositingGroup()` only for a view with a header at its
  first render (`GroupLatch`, DEBUG note `content.group`); `TransformHost(hasHeader:)`; capability / group docs.
- Demo `ProofScreen`: counters zeroed after a quiet period (0.5 s without render-counter changes, at most 3 s), fixed
  frames for the texts Reset / Snapshot write, `settle` signal; `ProofUITests.reset` waits for it.
- Demo `SeamLabScreen`: `-ZTronSeamAxis horizontal` (review d16-4), `-ZTronSeamFitGrow 1`; `scripts/seam/baseline.sh`
  extras `horizontal`, `grow`.
- Tests `HeaderReviewD16Tests` (the reviewers' probes, adapted, plus ambient-reader, latch, snap-from-band, radius tests).
- Docs: SPEC S6 alignment line, S10 (content that fits, `.fit` transaction, background readers / radii, 15–16 layer
  groups, banners, 15-path overflow limit, snap), parity row "Header and content layer groups", M8b-s4 Open 3 corrected.
Decisions (unnumbered; the lead assigns D-numbers):
- Content that fits under a header is top-aligned vertically (horizontal alignment kept). Reason: user decision 1 ("no
  gap between the header and the content") and S10 Placement; centring left a 119 pt gap. Needs lead / user
  confirmation: the alternative (the header follows the centred content's top) makes a `.stretch` header grow by `pad`
  at rest.
- 15–16 content group only with a header, latched at the first render (a runtime toggle never changes the content's
  identity). Blend-mode isolation and group opacity are documented 15–16 differences of a header view.
- 15-path overflow limit during an app-driven resize: documented limit (no proportional size in iOS 13 layout modifiers,
  a per-frame GeometryReader is ruled out by S4.6); `withKnownIssue` on the forced lane.
- Ambient copy readers are cold (snapshot per metrics change) instead of documenting doubled per-frame work.
Found while measuring (fixed): `HeaderSlotLayout` called `MainActor.assumeIsolated` from `placeSubviews`, which SwiftUI
also runs on `com.apple.SwiftUI.AsyncRenderer`: the demo trapped (EXC_BREAKPOINT, `_dispatch_assert_queue_fail`) on a
`.fit` header's animated content change inside the band (seam lab `fit-half-preserve-width-grow`, 27.0).
Open:
1. The two M8b-s4 combination scenarios (scroll command overlapping an animated resize) are unchanged (design decision).
2. The 15-path `.fit` in the band on an app-driven resize and the new 15-path overflow-limit item (documented limits).
3. Logic-test host: an inset-only SwiftUI animation of the content transform draws one frame and freezes unless another
   animation runs (both paths); the forced `.fit` re-measure is therefore verified in the seam lab, not by frames in the
   unit test.
4. Real 15/16 device: `compositingGroup` cost (M8b-s4 Open 4).
Next:
1. Lead / user: confirm the top alignment of fitting content under a header.
2. Merge into `m8b3-seamless` / main (lead).
3. Real 15/16 device check.
Tests:
- Unit `scripts/test.sh -only-testing:ZTronScrollViewTests`: 739 tests in 65 suites green on 27.0 and on 17.5 (1 known
  issue: the 15-path overflow limit, `withKnownIssue` on the forced lane).
- `HeaderUITests` + `ResizeUITests` + `ProofUITests`: 29/29 on 27.0 preferred, 27.0 forced and 17.5 preferred.
  `testNoClockTicksAtRest` × 8 (`-test-iterations 8`, 27.0 preferred, load ~5): 8/8; every reset absorbed 5 effect
  evaluations in a 0.6-0.7 s settle (the fixed 0.3 s window counted the ones that spill past it under load).
- Seam lab (analyzer v2.2), 30 rows, all PASS (|seam| <= 0.5 pt, lateral <= 0.4 pt, no step >= 0.5): horizontal width
  (was 90 / 90 / 159 pt, hJ 1.00), horizontal rotation, `.fit` grow at rest / half / `.stretch` on three lanes, `.fit`
  and aspect width / rotation regressions, ambient rotation. Table: `scratchpad/seam/final-table.md`, section "Review d16".
Usage: not measured.

## M8b-s6 (close) · 2026-10-27 · Opus 5.5 closer, branch claude/cool-stonebraker-0015c9 (main already merged)
Changed:
- Task 1 (high): root cause confirmed (unit test red before: `.capped(0.5)`, height to 0.4, header laid out at 138.67 =
  0.5 · (311.33 − 34), then re-set to 155.67 by the commit). The slot subtracted the COMMITTED bottom safe-area inset from a
  proposal that reached the bottom; a top-pinned height change leaves the home indicator (34 → 0 at the commit). Fix: the header
  overlay ignores only the side edges (`ZTronScrollView.swift`), so the slot is proposed the region between the safe areas
  and IS the container (`HeaderSlotLayout`, `HeaderLiveInput.bottomInset` removed). Test `HeaderHeightResizeTests`. Lab:
  `-ZTronSeamAnimateHeight <f>` ported; `baseline.sh` extra `height<digits>` (height04 = 0.4).
- Task 2: `HeaderMath.metrics` (pure, the layout path) + `HeaderMath.warning` (`#if DEBUG`, only `HeaderSizing.resolve`).
- Task 3 (real): during an open app-driven resize the refresh indicator was placed in the committed geometry: `.stretch`
  hold jumped 90 pt (ΔR) and 80.5 pt sideways in one frame, `.preserve` 90.7 pt down (pull from the presentation offset
  against the committed insets) and 80.5 sideways. Fix: `RefreshResizeEffect` (GeometryEffect: presented − committed
  placement at the drawn size, `ResizeMath.presented`) + the pull from the target while the resize is open. Test
  `RefreshResizeEffectTests`. Lab: `-ZTronSeamHold 1` (held refresh, white probe), `scripts/seam/probe.py`.
- Task 4: measured, no jump (forced `.fit` half, rotation, `-ZTronSeamSticky 1` bar: within 0.5 pt of the header bottom in
  every frame; also 27.0 / 17.5 preferred); SPEC S10 notes the pass is never drawn. Nothing to fix.
- Task 5: honest `withScalingHeader` and `ZTronHeaderBackground` docs (limits list → SPEC S10, ambient second instance:
  onAppear / task twice, matchedGeometry / focus ids duplicated, "no body per frame" instead of "nothing runs per frame");
  `.preserve` refresh base = `top0` in `docs/design/M8b-refresh-header.md`.
- Test support: `unhost` keeps windows with a `UITransitionView` on iOS 26+ (`_UICornerProvider` layout invalidations of
  non-screen-sized windows never clear in xctest): the guard flagged 75 warnings in the header suites at 795bf1a (pre-existing,
  from the merge) and 292 in the full run; now 0.
- SPEC S10: slot between the safe areas, refresh during a resize, F6 numbers + a possible 15-path approach, `.fit` pass.
Seam lab (analyzer v2.2; `|seam|` / lateral pt, hJ / cJ; scratchpad `close/seam/{27,17,27f,27t3}/<scenario>/`):
- `aspect-{rest,half}-preserve-width-capped-height04`: 27.0 0.33 / 0.33, hJ 0.026 / 0.028 (was 70 / 35 pt, hJ 0.998);
  17.5 0.5 / 0.5, hJ 0.029 / 0.034 (was a 17.2 pt overlap). 27.0 forced: 70 / 35 pt hJ 1.0 (F6, documented).
- `refit-height025` (limit engaged): 27.0 0.33 hJ 0.112, 17.5 0.33 hJ 0.032, forced 31 pt hJ 1.0 (F6).
- Controls (capped06, refit04 / 06, uncapped04, rest and half): ≤ 0.17 pt, no change, on all three lanes.
- Width regression `aspect-rest-preserve-width`: 27.0 0.33 lat 0.27 hJ 0.026; 17.5 0.5 lat 0.3; forced 0.33 lat 0.2.
- Task 3 after (`27t3`): `.stretch` hold probe −21.0 … −20.33 pt from the header bottom, lateral ≤ 0.33 (both width
  changes); `.preserve` 0.33 / 0.34 pt range; forced the same; `.stretch` hold + capped height04: ≤ 1.2 pt, steps ≤ 0.5;
  `aspect-rest-{preserve,stretch}-pull-refresh` seam ≤ 0.5. Before: `close/seam/27/aspect-rest-*-width-hold`.
- Task 4: `fit-half-preserve-rotate-sticky` 27.0 / 17.5 / forced: seam ≤ 0.21, probe ≤ 0.5, steps ≤ 0.21.
Open:
1. F6 (15/16 overflow limit on an app-driven resize) stays a documented limit; a cold slot-level `GeometryReader` around the
   15-path frame leaf (closure on resizes only) could fix it; not done (restructures the 15 header host).
2. Unchanged: 15-path `.fit` in the band on an app-driven resize; scroll command overlapping a resize (M8b-s4).
3. `ChromeLeafTests.aScriptedScrollAndZoomRunNoContentBodyAndOneLeafBodyPerFrame` counted 24 leaf bodies instead of 20 once in
   the 17.5 full run (a global counter shared with parallel suites); green alone and on 27.0.
Tests (M8b-s6):
- Unit `scripts/test.sh -only-testing:ZTronScrollViewTests`: 747 tests in 68 suites green on 27.0 and on 17.5 (1 known
  issue: F6 on the forced lane); the 27.0 run is clean under the feedback-loop guard.
- `HeaderUITests` + `ResizeUITests` + `ProofUITests` + `RefreshUITests`: 43/43 on 27.0 preferred and 17.5; 27.0 forced 42/43
  (`ProofUITests.testWithAnimationScroll` content.body 1 once; that screen has no header or refresher; ProofUITests forced
  × 3 iterations: 18/18).
Verifier defects (independent verifier on e0ae900, three break probes; all pre-existing mechanisms, fixed):
- vbottom (high): a bottom-pinned animated height change (the scroll view's top leaves the top safe area) put the content
  62 pt below the header (27.0; 59 pt on 17.5), closing over the animation; a `.stretch` hold indicator with it. Root cause
  (DEBUG event trace of the effect's drawn sizes, `-ZTronSeamInfo 2`): SwiftUI reports the change in stages. The animated
  layout reports the new height with the OLD top inset (874 → 373.3 pt, top 62, bottom 34 → 0); the first animated frame
  drops the 62 pt top extension at once (drawn size 874 → 812) and reports top 62 → 0; the bottom extension comes back as a
  step at the end; the reverse change brings the bottom one back in 3–4 pt steps over its last frames and the top one at
  its end. The second report was committed as a new transition from the drawn snapshot, which kept the old top inset under a
  frame that had lost it. Fix: a viewport change that only moves the safe-area extension (`isSafeAreaStep`: size minus the
  insets on the ignored edges unchanged) shifts the open transition (`ResizeMath.shifted`: same progress, both ends moved);
  a step reported before it is drawn (17.5, the end step: reported at 303.85, drawn at 337.67 one frame later) keeps the
  undrawn frame on the old track (`ResizeCommit.stepFallback`, decided by `ZTronScrollState.stepDrawn` from the probe's
  last three drawn sizes; steps no larger than twice the per-frame motion count as drawn).
- vspring (high): `ResizeMath.progress` clamped `t` to [0, 1] while SwiftUI's spring overshoots: content at the end geometry
  under an overshooting header (14.5 pt seam, 13 pt lateral). Fix: `t` is not clamped; content size, insets and header
  geometry are extrapolated along the commit's line.
- vretarget (medium): the same clamp froze the content at the second commit's snapshot while SwiftUI's additive
  composition kept moving the header past it (23 pt). Fixed by the same change (t < 0).
- Lab (committed): `-ZTronSeamBottomPinned 1`, `-ZTronSeamBoth 1`, `-ZTronSeamSpring 1`, `-ZTronSeamRetarget <s>`,
  `-ZTronSeamLandscape 1`; `baseline.sh` extras `vbottom`, `vboth`, `vspring`, `vretarget` (0.5 s), `vland`, `info`
  (diagnostics: `-ZTronSeamInfo 2`); `SeamLabUITests.testWidth` prints the info line after each step.
- Unit tests: `ResizeExtrapolationTests` (overshoot and retarget keep the content on the header bottom, `progress`
  unclamped), `ResizeSafeAreaStepTests` (the staged reports through the state, uncapped and capped, both paths; the
  undrawn-step fallback; `stepDrawn` on the measured size sequences; a real resize is not a step).
- SPEC S10 "Seamless edges": bullets "The resize curve" and "Safe-area steps"; API doc: F6 lands at the commit (the start of
  the resize), not at its end (verifier note).
Seam lab after (27bb9f4; table and recordings in the session scratchpad `close/final-table.md`, `close/seam/F/{27,17,27f}`;
`|seam|` / lateral pt): 29 scenarios × 3 lanes, 71 PASS. New probes on 27.0 / 17.5: vbottom uncapped 0.33 / 0.33 (was 62.2 /
59.2), capped rest 0.33 / 0.33 (53.5 / 59.2), capped half 0.33 / 0.5, refit 0.25 0.5 / 0.33; vspring width 0.33 lat 0.17 /
0.5 lat 0.32 (14.5 lat 13.2 / 14.0 lat 12.2), capped 0.5 / 0.5 (11.3 / 11.2), half capped 0.5 / 0.5 (6.0 / 5.7); vretarget
capped 0.33 / 0.33 (23.2 / 22.0), width 0.33 / 0.33; vboth 0.33 / 0.5, vland 0.33 / 0.5; hJ / cJ ≤ 0.14 everywhere except
refit 0.25 + spring (hJ 0.85–0.89: the frame is shorter than `R` and clips the header, the 26.7 pt one-frame "header" step is
the bouncy frame's own velocity; seam ≤ 0.5, raw frames checked). Hold probes (vbottom, buttons excluded): `.stretch`
indicator within 1.08 / 1.17 pt (was 26.6 / 59.0), `.preserve` 0.67 / 0.33. Forced: uncapped vbottom 0.33, vspring width
0.33, vretarget width 0.33, holds the same; every capped / refit row is F6 (70 / 35 / 31 pt, unchanged; vland 115 pt).
Regressions (width rest / half, capped / refit height, `.fit` grow, horizontal, rotations, pull-refresh, snap, scroll band,
stretch, holds): unchanged, ≤ 0.67 pt on all lanes except F6 rows.
Tests (verifier defects, 27bb9f4 + docs): unit `ZTronScrollViewTests` 27.0: 755 tests in 70 suites green, 1 known issue (F6), 0
feedback-loop warnings; 17.5: 755 tests, 1 issue = the known `ChromeLeafTests` global-counter flake (open item 3), the suite
green alone (13 tests). `HeaderUITests` + `ResizeUITests` + `ProofUITests` + `RefreshUITests`: 43/43 on 27.0 preferred and
on 17.5.
Open (verifier defects): none of the three remains on 16+; on the 15 path the capped / refit rows of the new probes are F6.

### Core check fixes · 2026-10-27 · Opus 5.5 fixer (independent core check of 810d101)
Scratch: session scratchpad `core/fx/` (PROGRESS log `core/PROGRESS.md`, seam recordings `core/fx/seam/{27,17,27f}/<scenario>/`).
1. Retarget near the drawn size (high): root cause as reported. A retarget commit starts from the drawn snapshot, its chord
   can have almost no viewport delta, and the unclamped `t` (−175 hosted) extrapolated every field that is off the old track
   (bottom inset to 3555 pt, a capped `R`). Fix (the review's outer-track design, plus a range bound):
   `ResizeCommit.outer` = the old commit's track at the drawn size (`ResizeMath.slope`: its own `outer` outside its span or on a
   sub-pixel chord), set in `applyViewport` when a retarget arrives while the open transition is still drawn in motion, shifted
   with a safe-area step (also kept in `StepFallback`), cleared in `syncCommit`. `ResizeMath.presented` (and `resolve` through
   it): outside the commit's own span, from the nearer end along the old slope, every field kept within the four snapshots'
   range (`bounded`; without it the bottom inset went to −12.8 pt: that end is the new model value, off the drawn track);
   `progress` clamps a track no longer than `ContentTransform.pixelTolerance`. Unit `ResizeRetargetTests` (state path,
   SwiftUI's additive easeInOut simulated): without a header worst offset error 4.7–15.5 pt (810d101: 194–654; main's clamp:
   10.9–15.5), presented bottom inset within [0, 34] (810d101: −1305…3555), worst one-frame step ≤ 12.7 pt (the retarget's
   first in-span frame: the chord's residual); capped seam 25.2 pt (810d101: 448–516; clamp 45.6), 14.7 pt for drawn + 60
   (66; 21.8); toggle back exact at 0.05–0.9 s; chained retargets bounded; sub-pixel track. Lab (`baseline.sh` extras
   `near1`, `near60`): 27.0 near1 gap 45.3 (810d101: 247.8), near60 overlap 16.3 (98.8); 17.5 29.3 (240.5) / 18.2; forced:
   F6 dominates (70 pt). The residual 15–45 pt is the chord model inside the span (main's level); removing it needs the two
   animations' progress separately (time-based or additive tracks).
2. Animated safe-area change under an engaged limit (medium): confirmed (hosted: the content drawn at its new rest in the
   first frame, the header's slot animated). The report reaches the state after the animated layout pass, outside the
   transaction; the container's `.transaction` hook had seen the animation in the same turn (`txAnim:true`). Fix: the
   inset-only branch of `applyViewport` writes metrics and offset inside `withAnimation(positionDriver.animationInTurn)` when
   the header's resting height changes (`PositionDriver.animationInTurn`, read without consuming); otherwise as before.
   Unit `HeaderSafeAreaInsetTests` (hosted, `.capped(0.25)`, 150 pt inset, both paths): the drawn offset moves over > 30
   frames in steps < 2 pt and lands at rest (before: one frame); unanimated stays one frame. Lab `kbfake-land-capped`: 27.0
   gap 0.0 / overlap 0.3 (was 74.8), 17.5 0.0 / 0.3 (75.0), forced 0.0 / 0.3. System keyboard (`-ZTronSeamKeyboard 1`):
   `txAnim:false` on show and hide in every instrumented run, so this fix does not touch it. Open (pre-existing, found
   here): without `-ZTronSeamInfo` (whose twice-a-second readout changes the timing), the system keyboard's DISMISSAL animates
   the header's slot while the content lands at once: a 85–88 pt gap closing over ~30 frames on this branch (3 runs), 92.5–94.8
   on HEAD d2425d6 (2 runs, A/B); with the info readout, a joint one-frame jump (0 pt, 4 runs, as in the review). The keyboard's
   animation never reaches the container's `.transaction` hook, so fix 2 cannot follow it.
3. Per-frame overlay placements after a rotation round trip (high): reproduced, NOT fixed, root cause not found. Reproducer:
   duty-cycle the demo app (`core/fx/throttle.sh <udid> 50|80 20|15`: SIGSTOP / SIGCONT) while the host is loaded (350–900).
   Failing iterations all pass through a "variant A" rotation (pre-pinch `ovh 6, ovp 10`: one more container evaluation per
   rotation than the usual `ovh 4, ovp 6`); at HEAD d2425d6 3 of 4 variant-A iterations failed (ovp delta 51, 54, 55). Every
   iteration without variant A passed (over 70, on HEAD, the fix build and 9b13637); low host load, even with a 250 ms stop,
   never produced variant A.
   Refuted: the M8b-s6 type layout of `ResizeCommit` (moved behind one reference, `ResizeCommit.tracks`: the fix build still
   failed 2 of 2 variant-A iterations, ovp 42 / 50). Attribution to 749e0b9 is weak: this test's state path is identical in
   9b13637 and 749e0b9 (rotation never animated, resize closed at once, `step:false`, same event log), and exact variant A was
   seen once before 749e0b9 (main, passed) against 9 failures after. Kept: `ResizeCommit.tracks` (the commit copied into the
   effect stays its old size plus a pointer, no new padding; `ResizeCommitLayoutTests`) and a DEBUG probe
   (`contentOverlay.place.changed`, readout `ovpChanged` / `ovpLast`: placements whose bounds or proposal changed). Next: catch a
   variant-A failure with the probe (parent re-layout or subview invalidation?) and run main under the same load.
Seam lab regressions (27.0 / 17.5 / forced, `|seam|` gap / overlap pt): vspring 0.5/0.5, 0.5/0.3, F6 70; vretarget 0.3/0.3,
0.3/0.3, F6 70/48.7; vbottom 0.3/0.3, 0.3/0.3, F6 70.5; width 0.3/0.3 lat 0.2, 0.2/0.5 lat 0.3, 0.3/0.3; capped height 0.4
0.2/0.3, 0.5/0.3, F6 70; rotate capped 0.0/0.2, 0.0/0.3, 0.0/0.2; rotate half 0.2/0.2 on all three. hJ / cJ ≤ 0.13 except
F6 rows. Unchanged from the close table.
Lab additions (committed): `-ZTronSeamRetargetNear <pt>`, `-ZTronSeamNoHeader 1`, `-ZTronSeamStartY <y>`,
`-ZTronSeamFakeKeyboard <pt>`, `-ZTronSeamKeyboard 1`; `baseline.sh` extras `near<digits>`, `kbfake`.
Tests (eebb2a4 + probe and docs): unit `ZTronScrollViewTests` 765 tests in 73 suites green on 27.0 and on 17.5 (1 known
issue: F6 on the forced lane), 0 feedback-loop warnings; `ContentOverlayUITests` + `HeaderUITests` + `ResizeUITests` +
`ProofUITests` + `RefreshUITests`: 47/47 on 27.0 preferred and on 17.5 (host load low: no variant A, see 3).

### Overlay placement fix (open item 17) · 2026-10-27 · Opus 5.5 (branch `claude/overlay-place-fix` from 79a5896)
Finding 3 above, root-caused and fixed. Scratch: session scratchpad `fin/ovl/` (PROGRESS `fin/PROGRESS.md`, tag `[ovl]`).
- Pre-existing: main 9e60063 (+ the probe, uncommitted) under the same throttle and load failed the same way (variant A
  in 3 of 16 iterations, 2 failed: pinch `ovp` delta 45 / 47); 79a5896 failed 6 of 8 variant-A iterations (13 run).
- A subview invalidation, not a parent re-layout: in every failing pinch `ovpChanged` stayed put (bounds and proposal
  unchanged) while `ovp` grew by one per frame. Not Observation: SwiftUI 27.0 does not track an observable read inside
  `placeSubviews` (hosted probe), and the counter-scale leaf never ran inside a placement; `ocs` only tracks the frames.
- Root cause: `TransformHost` (whose body runs on every scroll and zoom frame) applied `.allowsHitTesting(!blocked)
  .disabled(blocked)` inline. `.disabled(_:)` is an environment *transform* (a closure), so each frame handed the content a
  new environment transform; when SwiftUI does not diff it away, every control in the content (the demo banner's
  bordered `Button`) is laid out again on every frame, and the overlay `Layout` holding it is placed (and measures its
  `.ideal` overlays) on every frame. Hosted it is deterministic: a bordered `Button` in the content and one in an overlay,
  20 motion frames: content control 20 layouts, overlay control 40, host 20 (preferred; forced: host 0, controls the
  same), 2 of 2 processes on 27.0. Moving the two modifiers into a leaf with one `Bool` input: 0 (also 0 with
  `.environment(\.isEnabled, value)`, a value write; inline `.disabled` alone churned in one process of two). In the demo
  the churn shows only after a "variant A" rotation (one more container evaluation per rotation under host load, then
  `ovp 10` before the pinch: the extra placements were the same churn); why SwiftUI diffs the transform away otherwise is
  internal (inferred: its per-type comparison state, cf. D43).
- Fix: `ContentInteractionGate(blocked:)` (Render/ContentTransform.swift), the content's twin of `HeaderInteractionGate`:
  its body runs only when `blocked` flips (motion start / end: the test's bound of 2). Regression unit test
  `ContentOverlayTests.motionFramesDoNotLayOutControlsAgain` (both paths).
- Throttled `testCounterScaledMarkerKeepsItsScreenSize` (`throttle.sh` 80/15 ms, host load 200–890; variant A = pre-pinch
  `ovh 6, ovp 10`; "xeval" = `ovh >= 6`, the extra container evaluation per rotation, which the fix does not change):

  | build (27.0 preferred) | iterations | xeval | variant A | failed |
  |---|---|---|---|---|
  | main 9e60063 + probe | 16 | 5 | 3 | 2 (all variant A, `ovp` +45 / +47) |
  | 79a5896 | 13 | 10 | 8 | 6 (all variant A, `ovp` +26…+66) |
  | fix | 28 | 11 | 0 | 0 (pinch `ovp` +2 in all 28) |
  | fix, 17.5 | 16 | 0 | 0 | 0 (2 infra: kAX / terminate) |

  On the unfixed builds xeval without the extra placements (`ovh 6, ovp 6/8`) passed; with the fix every xeval rotation
  stays at `ovp 6`: the extra rotation placements were the same churn. 17.5 never showed xeval, and the hosted
  regression test passes on 17.5 without the fix (2 of 2 processes): 17.5 diffs the per-frame transform away.
Tests (fix): unit `ZTronScrollViewTests` 766 tests / 73 suites on 27.0: 1 known issue (F6), 1 load flake
(`HeaderSafeAreaInsetTests.anAnimatedSafeAreaChange…` preferred, one step 2.21 > 2 at load 890; alone 2 of 2 green),
0 feedback-loop warnings; `ContentOverlayUITests` + `ProofUITests` + `HeaderUITests` 20/20 on 27.0 preferred
(unthrottled); `ContentOverlayUITests` ×6 throttled on 27.0: 23/24 (1 launch infra: "Failed to tap Snapshot"); ×2 on 17.5:
4/6 (2 infra).

### D65 review fixes · 2026-10-27/28 · Opus 5.5 fixer (workflow subagent, branch claude/cool-stonebraker-0015c9 at fb1fe59)
Three confirmed findings of the D65 review, each reproduced, root-caused, fixed and tested. No new D-number.

**1. Open item 18 (`.openGap` hold indicator in a rotation that takes the gap below the screen).** Reproduced on the seam lab
(`aspect-rest-preserve-rotate-hold-opengap`, uncapped 16:9, R 491 pt over a 402 pt landscape viewport): on the way to landscape the
indicator vanished at once; on the way back it was drawn at once at its final portrait place, over the red header Core Animation was
still shrinking, then drifted into the gap. Before (frames with the gap on the screen / indicator in its gap, centre deviation):
27.0 6/25 (23.5 pt), 17.5 5/23 (20.4 pt), forced 5/24 (27.2 pt); `.stretch` 17.5 5/23 (30.2 pt), 27.0 6/25 (28.2 pt).
- Root cause: SwiftUI drew no layer for the indicator while its place was outside the viewport (the hosted layer tree has no
  marker layer in a landscape window, both paths), so Core Animation had nothing to interpolate. `.stretch`: its overlay placement
  was nil there (the clip from a base below the screen to the viewport's far edge is empty).
- Spikes: a laid-out clip box (builder, no change); the box moved by a render-time translation (no change); translation + layer group
  (rotation fixed, but a `withAnimation` width change during the hold drew the indicator 88 pt above the gap, `.stretch` 41 pt,
  for the whole narrowing: the leaf's placement change in that transaction is animated only as layout); the translation animatable
  (no change, hosted mid == end). Kept: the group box laid out with `.position`.
- Fix (8b5d3ad, 5b32f97, `Refresh/RefreshIndicators.swift`): the indicator box (the clip's size, `.clipped()`) is its own layer group
  (`HeaderLayerGroup`: 17+ `geometryGroup()`, 15–16 `compositingGroup()`) `.position`ed at the clip's place; `RefreshClip` (mask
  path) removed; an overlay clip is never shorter than the indicator (`RefreshIndicatorMath.placement`).
- Tests: `RefreshIndicatorLayerTests` (both paths): `.openGap` and `.stretch` marker layer in place in portrait and below the screen
  in landscape (fb1fe59 fails the landscape check on both paths); `anAnimatedResizeMovesTheIndicatorWithTheGap` (presentation tree at
  mid animation part way: fb1fe59 278 pt between 313 and 222, the translation variants 222 = end); `RefreshIndicatorTests` overlay
  base below the viewport.
- Docs: Orchestration open item 18 (a) FIXED with the corrected description; SPEC S10 "Refresh with the header" and "15–16 layer
  groups" (the indicator group's 15–16 blend-mode isolation).

**2. `ProofUITests.testWithAnimationScroll` content.body 1 (forced 27.0, about 1 run in 3 since 952c91a).** Not a library change
in 9e60063..d2425d6, so no library bisect: main 9e60063's library with the branch's `ProofScreen` / `ProofUITests` (952c91a's
quiet-period reset) failed 9 of 10 (`ztronscroll-log.m4L2gMJBE0`). A DEBUG event log showed every failure as `RESET | ProofScreen
body | content body | TAP`: the `settle` write right after the counters were zeroed re-ran `ProofScreen`'s body inside the counted
window, and that parent update re-ran `ProofContent`'s body; nothing ran after the tap (the scroll itself never re-evaluated the
content: S4 holds). A native `ScrollView` in the same place re-ran it in 6 of 6 runs (SwiftUI's comparison of a view holding `@State`,
consistent with D43). Fix (4faa80c, demo only): the settle text lives in `SettleStatus` / `SettleLabel`, held by reference in
`@State`, so `ProofScreen` does not observe it. The content re-run needs host load (at load ~10 fb1fe59 passed 10/10, also with the
app duty-cycled), so the test now checks the cause: a DEBUG `screen.body` counter (`ProofScreen`'s own body, shown in an overlay:
a tenth counter row made `testNoClockTicksAtRest` see a layout pass at rest, 3 of 3) must stay 0 in the counted window. fb1fe59's
harness with that counter fails 3 of 3 (`screen.body` 1); the fix passes (forced 27.0: `testWithAnimationScroll` 20/20, the suite
×3 18/18; 27.0 preferred and 17.5 below).

**3. `HeaderSafeAreaInsetTests.anAnimatedSafeAreaChangeMovesTheContentWithTheHeader` worst step < 2 (27.0, about half the runs).**
`pump(1/60)` is a wall-clock spin that overruns under host load while the animation runs on the render clock, so several frames land
in one sample. Fix (525c123 + this round's last commit, test only): a step is judged against the 60 Hz frames of its own interval and
the one before it (1 pt per frame), because a sample right after a stall can still show the frame in flight when it began and the
next one catches up (a full 27.0 run: 5.6 pt over a 26-frame stall, then 16.8 pt in one frame, both on the easeInOut curve: the
first version, per own interval only, failed there); a step with no stall around it may not carry half the change. New
`aStalledSamplerJudgesTheDrawnCurve` (50 ms stalls every 7th sample: raw steps 4.1-4.3 pt, which the former check failed) passes.

Seam lab (fix round, 20 scenarios × 27.0 preferred / 17.5 / 27.0 forced = 60 runs; table and recordings in the session scratchpad
`pull/fix/final-table.md`, `pull/fix/seam/<lane>/`): 54 PASS; the 6 FAIL are the forced `capped-height04` family at 70 pt, open item
15 (b), pre-existing (the close table's 70.0 / 70.5; fb1fe59 measured here for the two hold variants: same seam, same indicator
numbers). Indicator in a rotation during a hold (uncapped 16:9, frames with the gap on the screen / in place, centre deviation):

| scenario | 27.0 | 17.5 | 27.0 forced |
|---|---|---|---|
| `.openGap` (fb1fe59) | 6/25, 23.5 pt | 5/23, 20.4 pt | 5/24, 27.2 pt |
| `.openGap` (fix) | 22/24, 0.33 pt | 21/23, 0.26 pt | 22/24, 0.31 pt |
| `.stretch` (fb1fe59) | 6/25, 28.2 pt | 5/23, 30.2 pt | - |
| `.stretch` (fix) | 22/23, 0.26 pt | 22/23, 0.75 pt | 23/25, 0.26 pt |
| `.followContent`, `.fixed`, `.capped` controls (fix) | all, ≤ 0.83 pt | all, ≤ 1.19 pt | all, ≤ 0.68 pt |

The misses are the probe merging with the lab's white buttons where the gap leaves the screen (frames inspected). Indicator during a
width resize in a hold (relative to the header's edge): ≤ 0.5 pt in every lane and mode (fb1fe59 0.33 / 0.5). Header / gap / content
seams of the D65 and regression scenarios (vspring, vretarget, vbottom, width, capped-height04, rotate-capped, kbreal): ≤ 0.7 pt,
lateral ≤ 0.4 pt, the largest 60 Hz step 0.26 of the change (rotations, as at fb1fe59; forced `capped-height04` family: item 15 (b),
unchanged).
Tests: unit `ZTronScrollViewTests` 784 tests / 76 suites green on 27.0 (final) and on 17.5 (at 5b32f97; the later test-only change
×2 on 17.5), 1 known issue (F6), 0 feedback-loop warnings; `HeaderUITests` + `RefreshUITests` + `ProofUITests` 31/31 on 17.5 and 30/31
on 27.0 preferred (`RefreshUITests.testRefreshableMapsToTheSystemRefresher` timed out once; ×5 and the suite 14/14 green after);
`ProofUITests` with the final harness ×2 on 27.0 preferred and 17.5 (12/12 each), ×3 forced (18/18).

### Final check fixes · 2026-10-28 · Opus 5.5 fixer (workflow subagent, branch claude/cool-stonebraker-0015c9 at 6e317c2)
One confirmed finding of the D65 final check, reproduced, root-caused, fixed and tested (53b272c). No new D-number.

**15–16 group isolated a custom refresh indicator's blend modes in every view with a refresher.** 5b32f97 applied the
indicator box's layer group (`HeaderLayerGroup`) in every view, header or not; on 15–16 that is `compositingGroup()`, which
composites the indicator alone, so the forced path drew differently from 17+ (`geometryGroup()`, drawing-neutral) and from
fb1fe59. Reproduced with a new demo section (`-ZTronRefreshSection blend | blendOverlay`: no header, a held refresh, a white
20 pt `.difference` indicator over the scroll view's pure blue background / the content's pure green top) and a pixel test,
`RefreshUITests.testACustomIndicatorsBlendModeReachesWhatIsBehindIt` (the centre column of a screenshot): at 6e317c2 forced
27.0 drew it white (`white 339+20`, fails), preferred 27.0 yellow / magenta (blended).
- Fix (`Refresh/RefreshIndicators.swift` `RefreshIndicatorGroup`): 17+ `geometryGroup()` in every view as before; 15–16
  `compositingGroup()` only when the view has a scaling header (`state.headerSpec` or header metrics), where open item 18 needs
  it; without one the box is not grouped (it draws as on 17+). Latched at the box's first frame (`GroupLatch(note:)`, now
  shared with the content's group), so installing or removing the header during a hold never changes the indicator's identity.
  The header case keeps the documented 15–16 difference (SPEC S10 "15–16 layer groups", corrected).
- Tests: the UI pixel test above (fixed: forced 27.0, 27.0 and 17.5 yellow / magenta); unit
  `RefreshIndicatorLayerTests.theFifteenIndicatorGroupIsOnlyUnderAHeader` (per path, header first or not, toggled during the
  hold: 15–16 `none` / `compositing` and never re-decided, 17+ no latch; fails at 6e317c2 on the forced path). A logic-test
  host has no render server, so the drawing itself is checked by the UI test only; a real 15/16 device was not available.
- Open item 18 (a) stays fixed: `RefreshIndicatorLayerTests` green on both paths (the header case keeps its group), and the
  seam lab's rotation during a hold (uncapped 16:9; frames with the gap on the screen / indicator there, centre deviation; no
  frame drawn off its place in any run):

| scenario | 27.0 | 17.5 | 27.0 forced |
|---|---|---|---|
| `.preserve` `.openGap` | 23/26, 0.30 pt | 21/23, 0.23 pt | 23/25, 0.34 pt |
| `.preserve` `.followContent` | 24/24, 0.52 pt | 23/23, 0.94 pt | 24/24, 0.49 pt |
| `.stretch` | 23/24, 0.27 pt | 22/23, 0.27 pt | 23/25, 0.27 pt |

  Seams ≤ 0.5 pt, lateral ≤ 0.14 pt, all 9 PASS (the misses are the probe merging with the lab's white buttons at the screen
  edge, as in the D65 review fixes table).

Not addressed (reported by the final check, pre-existing at fb1fe59): open item 19, the headerless twin of item 18.
Tests: unit `ZTronScrollViewTests` 785 tests / 76 suites green on 27.0 and 17.5, 1 known issue (F6), 0 feedback-loop warnings;
`RefreshUITests` + `HeaderUITests` + `ProofUITests` 32/32 on 27.0 preferred, 17.5 and 27.0 forced (one run each).
