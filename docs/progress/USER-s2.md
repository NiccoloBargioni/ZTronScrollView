# USER-s2 handoff · 2026-10-19 · Fable 5.1 (side session s3-C, user reports: bounce "does not work" in the 16:9 image tree; double-tap snap; one-finger-lift snap)
Status: done — three user reports, three root causes measured/read and fixed (D21 render path, D22 zoom animation, D23 pinch hand-off); unit + demo UI tests pin them. User device checks pending.
Changed:
- Render/ContentTransform.swift: `isPlainFrame(size:)` — the fast path (target drawn as is, overscroll included) now
  accepts the committed viewport and insets within `pixelTolerance` = 1 pt instead of 0.01 pt / exact equality; DEBUG
  draw-path probe: counters `transform.fast`, `transform.slow`, `transform.slowClosed`, `transform.clampedAtRest` and
  notes `transform.slow` / `transform.clampedAtRest` (which equality failed, target vs drawn).
- State/ZTronScrollState.swift `resizeTick`: the probe's frame size counts as the committed viewport within the same
  tolerance (else a resize whose final frames are pixel-rounded never settles: the launch-time resize of the 16:9 tree
  stayed open — `.animating` at rest, clock running, presentation = the clamped probe frame, content not hit-testable;
  the first drag closed it with reason "intervention", which is how it showed in the event log).
- Tests/ZTronScrollViewTests/TransformTests.swift: `pixelRoundedSizeStillDrawsTheTargetUnclamped`;
  ResizeTests.swift `ResizeStateTests.pixelRoundedProbeSizeClosesTheResize` (both OS paths).
- Tests/ZTronScrollViewTests/FittingAxisBounceTests.swift (fd48b09): the coordinator path rubber-bands a fitting axis
  with `.always` and `.automatic`, not with `.basedOnSize` (both OS paths).
- Demo ResizeScreen: `-ZTronResizeBounceAlways` (user tree horizontal behavior `.always`), readout `fast= slow=
  slowClosed= clamped=` + notes; ResizeUITests: `testUserTreeVerticalOverscrollIsDrawn`,
  `testUserTreeHorizontalAlwaysBounceIsDrawn` (drawn frames never clamped at rest, no resize path with the commit
  closed, idle phase at rest after launch, spring back).
Decisions:
- D21 Root cause (measured on the demo copy of the user tree, 27.0 preferred, before the fix): SwiftUI hands the
  GeometryEffect a pixel-rounded size — `size=(402.0, 288.0)` — while the committed viewport is the unrounded layout
  size `vp=(402.0, 288.125)` (16:9 box 402×226.125 + 62 pt bar). `ContentTransform.resolved` compared them within
  0.01 pt, so EVERY frame at rest took the resize path (`slow=90 slowClosed=90` of 90 frames in one drag), whose
  result is clamped to the bounds (`clamped=86`: target x −0.5…−86 pt drawn as 0). Hence no rubber band or bounce
  could ever be drawn in that tree, on any axis, with any behavior, although the state rubber-banded (didScroll fired).
  Second symptom of the same cause, in `resizeTick`: the launch-time size change (the bar's safe area landing) opened
  a resize whose probe frames (288.0) never matched the committed viewport (288.125) within 0.01 pt, so it never
  settled: `phase=4 (.animating)` at rest, clock running, presentation = the clamped probe frame (−61.9375), content
  not hit-testable (D11); the first drag closed it ("close reason: intervention" in the event log) — after the
  transform fix alone the drag frames were fast (`fast=87 slow=0 clamped=0`) but the launch phase was still 4. Fix:
  within a pixel is the same frame, in both places. A real resize moves by far more than 1 pt, so the
  no-jump protection for the frames before the observer reports a new size is unchanged.
- Not the cause (ruled out first): the environment key (`transformEnvironment`), `BounceConfiguration.resolve`,
  `PanSession.offset` rubber band, D15 `effectiveAxes`, arbitration (no arbiter in the user's app).
- D22 Double tap "animates, then snaps before the interpolation completes" (read, then reproduced in a unit test):
  `applyZoom` drives the zoom with a critically damped progress spring 0 → 1 but sampled it with the default point
  thresholds (0.5 pt remaining, 10 pt/s): read as progress units the spring is "settled" at ≈ 50 % after ≈ 150 ms
  (ω = √119 ≈ 10.9/s: remaining 0.5 at ωt ≈ 1.7, velocity ≈ 3.4/s < 10) and the settle branch writes `z1`/`endOffset`
  at once. Fix: `ZoomAnimation.thresholds` = the point thresholds divided by the animation's screen travel
  (max(|Δz|·viewport, |Δoffset|, 1)); the zoom glides to the end (≈ 0.9 s for 1 → 8x at stiffness 119; the visible
  motion is over by ≈ 0.7 s). Native `zoom(to:animated:)` is faster (≈ 0.35–0.5 s): stiffness for programmatic
  zooms is a calibration knob, not changed here. Files: State/ZTronScrollState.swift (`ZoomAnimation`, `applyZoom`,
  `stepClockMotion`), Tests/ZoomAnimationTests.swift.
- D23 One-finger lift "ugly snap that would not be there in a native UIScrollView": with the scale in range but the
  pinch offset out of bounds (the pinch's offset is unclamped while `bouncesZoom`; a two-finger slide past an edge),
  `PinchSession.finish` started the zoom bounce at the first lift, springing the content back under the finger still on
  the glass. UIScrollView keeps the overscroll in the pan (rubber band) until the last finger lifts. Fix: `finish(…,
  handingOff: true)` on `fingerCountChanged(count: 1)` bounces only a scale past its limit; the pan continues from the
  remaining finger holding the overscroll (`PanSession.baseline` inverts the rubber band), its release springs back
  (`ReleaseSolver`); when no pan takes the finger (container owns the swipe, scrolling disabled) the coordinator starts
  the offset bounce itself (`springBackOverscrollWithoutPan`). Also: an axis that does not bounce (`.basedOnSize` on a
  fitting axis, `bounces = false`) is now clamped under the pinch too (`PinchEnvironment.bouncesX/Y` from the pan's
  resolution), and the 18+ adapter turns a magnify `.onEnded` with one finger still down into the hand-off event, so the
  order in which SwiftUI delivers the magnify end and the spatial count change no longer matters. 15–17 (no finger
  count): unchanged, the `.ended` path still bounces (documented gap: the remaining finger cannot pan there anyway).
  Files: Gesture/PinchSession.swift, PanCoordinator.swift, PinchGestureAdapter.swift; PinchPanTests section 7.
- Order of likelihood for the user's "snap at one-finger lift" on the tree they tested: pre-D20 stale-baseline jump
  (fixed 755c872), D23 offset spring-back under the finger, D21 clamped drawing (16:9 tree). All three are now fixed;
  the user must rebuild ZTronTesting against main ≥ this session's last commit.
Open:
- User: confirm on ZTronTesting (16:9 tree): horizontal `.always` rubber band at 1x, vertical edge bounce, buttons in
  the content tappable at rest (phase idle). Full-screen tree unaffected (integral size → fast path all along).
- Trees whose viewport is pixel-rounded by more than 1 pt (none known) would still take the slow path at rest: the
  `transform.slowClosed` counter in the ResizeScreen readout shows it.
- Settle detector `probeTick` still compares exactly; fine with the fast path, could tolerate a pixel (defense in depth).
- D22: calibrate the programmatic zoom spring (stiffness/duration) against native `zoom(to:animated:)` on 27.0
  (PHYSICS-calibration.md method); the double tap now glides but is slower than native.
- D23: the pinch's overscroll is linear (unresisted) while native rubber-bands it; the hand-off inversion is continuous
  either way. 15–17: `.ended` with a finger still down still bounces (no finger count on that path).
Next: 1. User device check. 2. Orchestration step 3 (full demo UI re-run on 27.0 + 17.5, both paths; now also covers
this fix). 3. M5 (b) remainder.
Tests: `scripts/test.sh -only-testing:ZTronScrollViewTests` → **174/174** (19 suites) on iOS 27.0 and on 17.5
(`ZS_DEST='id=7279872B-…' … -derivedDataPath .build/dd-u175`); new: TransformTests.pixelRoundedSizeStillDrawsTheTargetUnclamped,
ResizeStateTests.pixelRoundedProbeSizeClosesTheResize, ZoomAnimationTests (1), PinchPanTests section 7 (3), FittingAxisBounceTests (2),
each × 2 OS paths. Demo UI (`scripts/test-demo-ui.sh`): ResizeUITests 13/13 on 27.0 preferred after D21 (the 11 rotation tests also
11/11 on 17.5 on the pre-D21-watch build); ZoomUITests 7/7 + `testUserTree{Vertical,HorizontalAlways}…IsDrawn` 2/2 on 27.0 preferred and
17.5 preferred after D22/D23 (readouts: `fast=120/52 slow=0 clamped=0 phase=0` at rest; before D21: `slow=90 slowClosed=90 clamped=86
phase=4`). Not run: --forced demo UI (Orchestration step 3), 17.5 ResizeUITests on the final build.
Usage: weekly all-models 11% → 14% · Fable 22% → 28% (whole side session 10% → 14% · 18% → 28%) · cache hit n/a · context 52% of 1 M.
