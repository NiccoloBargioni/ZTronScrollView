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
