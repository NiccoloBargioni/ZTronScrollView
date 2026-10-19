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
- Device feel of the two-finger overscroll (resistance identical to one finger) — user check.
- `zoom(to:)` at an unchanged scale: duration law floor (0.125 s), not measured.
Next: 1. User device checks (all of s3-C). 2. Orchestration step 3 (full demo UI re-run on both paths).
Tests: `scripts/test.sh -only-testing:ZTronScrollViewTests` → **176/176** (19 suites) on iOS 27.0 and 17.5 (PinchSessionTests
`offsetPastTheBoundsFollowsThePanBouncePerAxis` ×2 new; `focalPointIsInvariant` now checks the band applied to the exact
focal-invariant offset, and exact invariance inside the bounds); `scripts/test-physics.sh` 111/111 unchanged;
`scripts/test-demo-ui.sh … -only-testing:…/ZoomUITests` → 7/7 on 27.0 preferred and 17.5 preferred. Not run: --forced, full demo suite.
Usage: weekly all-models 16% → 18% · Fable 32% → 36% (whole side session 10% → 18% · 18% → 36%) · cache hit n/a · context 65% of 1 M.
