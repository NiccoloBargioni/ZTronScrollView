# USER-s3 handoff · 2026-10-19 · Fable 5.1 (side session s3-C, programmatic zoom calibrated against native)
Status: done — native `UIScrollView` zoom animations measured on iOS 27.0 (21 cases), modelled (`ZoomTiming`: UIKit ease-in-out,
duration from the zoom ratio), wired into `applyZoom`; fixtures + unit tests; see Tests. User device check pending.
Changed:
- Packages/ScrollArbitration/Spike: `ZoomCalibrationViewController.swift` (`-zoomCal`: UIScrollView 300×360 / 600×600 / 1…8,
  buttons set125 … set8, rect8, back, reset, save; CADisplayLink samples [t, modelScale, presentationScale, offsets]; writes
  Documents/cal/native-zoom-<case>.json), SceneDelegate `-zoomCal`, `ZoomCalibrationUITests` (opt-in TEST_RUNNER_ZS_CALIBRATE=1).
- scripts/fetch-calibration.sh (optional bundle id), scripts/compare-zoom-calibration.py (window, model jump, delegate events,
  fits: critical spring ω / ease-in-out / ease-out / ease-in / linear with fitted duration; `--fixture` prints Swift literals).
- Packages/ZTronScrollPhysics: `ZoomTiming.swift` (`UnitBezier` with `.easeInOut`, `ZoomTiming(start:duration:curve:)`,
  `duration(from:to:)`, `sample(at:)`); `ZoomTimingTests` (3), `NativeCalibrationTests` zoom fixtures + reproduction test (4 cases).
- Sources/ZTronScrollView/State/ZTronScrollState.swift: `ZoomAnimation.timing` replaces the progress spring (and the D22
  first-pass travel-scaled thresholds); `stepClockMotion` samples it.
- Tests/ZTronScrollViewTests/ZoomAnimationTests.swift: native durations (24 frames for 8×, 19 for 2×), ease-in-out half way at
  half time, no frame > 10 %, last frame a glide.
- docs/design/PHYSICS-calibration.md: section "Programmatic zoom" (table, findings, model, open items).
Decisions:
- D22 (final) Native programmatic zoom = fixed-duration UIKit ease-in-out (Bézier 0.42, 0, 0.58, 1) on scale and offset
  alike; `duration = min(0.40, 0.125 + 0.19·(r − 1))`, r = zoom ratio, symmetric; model scale jumps at once. Not a spring:
  the best critically damped fit misses by rms 0.09–0.10. Our `ZoomAnimation` keeps its anchor-sliding semantics (identical
  to native's linear interpolation of both quantities under one curve).
- UIKit stays in the spike app (CLAUDE.md): the calibration instrument is a spike screen, not a demo one.
Open:
- `didZoom` cadence during the animation: native once, ours per frame (readers/delegates see every frame).
- `zoom(to:)` without a scale change (pure offset) and `setContentOffset(animated:)` durations not measured (floor 0.125 s).
- 120 Hz device: native frames would be 8 ms; the model is time-based, nothing to change, but unmeasured.
Next: 1. User check on the device (double tap in and out: native feel). 2. Orchestration step 3 (full demo UI re-run).
Tests: `scripts/test-physics.sh` → 111/111 (host; new ZoomTimingTests 3 + NativeCalibrationTests.programmaticZoomReproducesNativeEaseInOut ×4);
`scripts/test.sh -only-testing:ZTronScrollViewTests` → 175/175 on iOS 27.0 and on 17.5 (ZoomAnimationTests 2 × 2 OS paths);
`scripts/test-demo-ui.sh … -only-testing:…/ZoomUITests` → 7/7 on 27.0 preferred and 17.5 preferred (double tap at 0.40 s);
spike: `TEST_RUNNER_ZS_CALIBRATE=1 ZS_DEST='id=897F9D8D-…' scripts/test-spike.sh -only-testing:ArbitrationSpikeUITests/ZoomCalibrationUITests`
→ 21 cases recorded in two runs (.build/cal/zoom27, zoom27b), analysed with scripts/compare-zoom-calibration.py. Not run: --forced paths,
17.5 spike measurement (iOS 17 native behaviour assumed equal).
Usage: weekly all-models 14% → 16% · Fable 28% → 32% (whole side session 10% → 16% · 18% → 32%) · cache hit n/a · context 62% of 1 M.
