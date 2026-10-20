# USER-s4 handoff · 2026-10-19 · Fable 5.1 (side session s3-C, pinch overscroll rubber band + didZoom cadence)
Status: done — (1) the pinch's offset past an edge is now rubber-banded per bouncing axis like a one-finger drag (D24), the
hand-off keeps continuity; (2) didZoom cadence kept per frame by SPEC, documented. User device check pending.
Changed:
- Gesture/PinchSession.swift: `offset(anchor:centroid:scale:env:)` = raw anchor math, then per axis: bouncing → `RubberBand(viewport, c)`
  displacement past the bounds; not bouncing → clamp; `bouncesZoom` no longer touches the offset. `PinchEnvironment.rubberBandCoefficient`
  (from `PanSession.rubberBandCoefficient` via the coordinator).
- Gesture/PanCoordinator.swift: `makePinchEnvironment` passes the coefficient.
- Tests: PinchSessionTests `offsetPastTheBoundsFollowsThePanBouncePerAxis` (×2); PinchPanTests section 7 expectations = the band's
  values (−43.1 pt for 100 pt of overscroll on a 200 pt viewport), continuity through the hand-off exact.
- docs/design/PHYSICS-calibration.md: "Pinch overscroll and didZoom cadence".
Decisions:
- D24 Two-finger overscroll under a pinch = the pan's rubber band (UIScrollView's pan recognizer handles 1 and 2 touches alike);
  not measurable with XCUITest (no two-finger drag API): the one-finger measurement (c 0.55, d viewport) is the reference.
- didZoom stays per frame: SPEC l.41 (`zoomScale` = presentation, frame by frame) and M4 §6 (didZoom then didScroll once per tick).
  Native's once-per-animation cadence follows its model `zoomScale`; a delegate wanting that watches `isZooming` / `didEndZooming`.
Open:
- D25 confirmed by the user on the device (main 1486752): the lift-then-drag gesture no longer snaps.
- Device feel of the two-finger overscroll (resistance identical to one finger) — user check.
- `zoom(to:)` at an unchanged scale: duration law floor (0.125 s), not measured.
Next: 1. User device checks (all of s3-C). 2. Orchestration step 3 (full demo UI re-run on both paths).
## Addendum · D25 (user video, 2026-10-19 12:52): the snap at the lift was the magnify gesture's trailing sample
The user's recording (ZTronTesting, 16:9 tree, main 998add8) shows the real snap: fingers held still at ≈ 2×, one lifts, and in
ONE frame (0.97 → 0.98 s) the view jumps to ≈ 4× and another position, static before and after (no bounce, no animation).
A one-frame scale change at the lift can only be a `.changed` sample applied: on 18+ the spatial observer's count change
hands the pinch off (session released) and SwiftUI then still delivers the magnify gesture's last `.onChanged`, whose
`magnification` is cumulative for the OLD gesture; `PinchSession.handle(.changed)` on an inactive session treated it as "a
change without a began" (the 15–17 fallback), began a new session at the current scale with base 1 and multiplied: 2× · 2.05 ≈
4.1× (then `.ended`/hand-off again, scale past max → a 4.1 → 4 bounce too small to see). The same mechanism was the original
"ugly snap" report; D23 fixed a different, real gap. Fix: `PinchSession.gestureEndPending` — set at the observer's hand-off,
`.changed` samples are ignored while set, cleared by the gesture's `.ended`/`.cancelled` or a new `.began`; the adapter always
sends `.ended` after the hand-off substitution. Tests: PinchSessionTests `trailingChangedAfterTheHandOffIsIgnored`,
PinchPanTests section 8 `trailingMagnifySampleAfterTheLiftDoesNotJump` (both OS paths). The second visible change in the video
(≈ 1.6 s) is a fast drag, continuous at 60 fps. Frames: `ffmpeg -ss 0.88 -t 0.2 -vf fps=60,crop=1290:800:0:120,tile=4x3`.

## Addendum · D29 (user report via the orchestrator, 2026-10-20): second finger down again during the one-finger continuation
Report: "Start magnification with two fingers, lift one finger but continue, second finger again on screen → a snappy animation."
Not expressible in XCUITest (single-touch API; no two-finger composition), so reproduced at the coordinator level with the events
the adapters deliver (PinchPanTests section 9, PinchSessionTests `secondFingerDuringTheContinuationContinuesFromTheCurrentScale`).
Root cause (same family as D25): at the re-touch the spatial observer reports two fingers and re-arms the pinch from the current
geometry (correct), but the gesture that reports next is the OLD magnify gesture — SwiftUI ends a MagnifyGesture only when all its
touches end — with its CUMULATIVE magnification; `PinchSession.apply` used base 1 for the re-armed session, so the first sample
multiplied the current scale by the old gesture's magnification (1.5× · 1.5 = 2.25× in one frame). Fix: a session begun by the
observer (`fingerCountChanged(count ≥ 2)`, or a `.changed` without `.began`) takes its magnification base from its FIRST `.changed`
sample (`Pinch.baseMagnificationPending`); a gesture-begun session keeps base 1. Both OS paths; nothing else changes.
Not done here (shared tree: `PanCoordinator.swift` and `PinchGestureAdapter.swift` carry other sessions' uncommitted edits): the
second hypothesis — if SwiftUI ENDS the one-finger DragGesture when the second finger lands and that `.dragEnded` arrives BEFORE the
observer's count change, the pan is released through the pipeline (a fling from the finger's speed) and the pinch then catches it
(`.catchMotion`): a 1–2 frame release motion. Proposed guard, to implement when the coordinator is free: a `.dragEnded` while
`panContinuedFromPinch` is held until the observer's `.touchesEnded` (then released as today) or dropped at `fingerCountChanged(count ≥ 2)`
(`endDragWithoutDeceleration`). Unit test to add: ordering X (dragEnded, then count 2) → no deceleration, offset continuous.
Tests for D29: see the end of this file. Device confirmation by the user pending.

Tests: `scripts/test.sh -only-testing:ZTronScrollViewTests` → **178/178** (19 suites) on iOS 27.0 and 17.5 after D25 (176 after D24; PinchSessionTests
`offsetPastTheBoundsFollowsThePanBouncePerAxis` ×2 new; `focalPointIsInvariant` now checks the band applied to the exact
focal-invariant offset, and exact invariance inside the bounds); `scripts/test-physics.sh` 111/111 unchanged;
`scripts/test-demo-ui.sh … -only-testing:…/ZoomUITests` → 7/7 on 27.0 preferred and 17.5 preferred. Not run: --forced, full demo suite.
Usage: weekly all-models 16% → 20% · Fable 32% → 39% (whole side session 10% → 20% · 18% → 39%) · cache hit n/a · context 71% of 1 M.
