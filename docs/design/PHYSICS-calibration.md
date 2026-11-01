# Physics calibration vs native `ScrollView` (SPEC S6) · 2026-10-18

User report: "scroll physics is very bad and it does not copy that of a native UIScrollView." Measured, fixed and
re-measured against a native SwiftUI `ScrollView` (UIScrollView-backed) on the iOS 27.0 simulator (iPhone 18 Pro).

## Method

- Demo screen `-ZTronScreen calibrate` (`Demo/ZTronScrollViewDemo/CalibrateScreen.swift`): same content (100 rows ×
  60 pt = 6000 pt, viewport 600 pt; `-ZTronCalibrateShort`: 5 rows, fits) in either our `ZTronScrollView` or, with
  `-ZTronCalibrateNative`, a native `ScrollView` logged through `onScrollGeometryChange` (18+). Both log
  `(uptime, contentOffset.y, phase)` on every change plus every finger event (a simultaneous zero-distance
  `DragGesture`), and write `Documents/cal/<variant>-<gesture>.json`.
- `CalibrateUITests` (opt-in: `TEST_RUNNER_ZS_CALIBRATE=1 scripts/test-demo-ui.sh <dest>
  -only-testing:ZTronScrollViewDemoUITests/CalibrateUITests`) drives identical `XCUICoordinate` gestures on both variants:
  slow drag held 0.5 s before lifting, medium fling (1500 pt/s), fast fling (4000 pt/s), fling into the bottom edge,
  40/100/200/300 pt drags past the top held 0.3 s, catch mid-fling, and the "fits" top/bottom pulls.
- `scripts/fetch-calibration.sh <udid> <dir>` copies the JSON files; `scripts/compare-calibration.py <dir> [--md]`
  reports per gesture: tracking ratio and lag, release velocity, fitted deceleration (v₀, r, distance, duration),
  rubber band displacement / overscroll / implied c, bounce-back duration and overshoot, edge overshoot and settle,
  catch stop latency.
- Caveat: XCUITest waits for the native scroll view to quiesce before the next event, so the native "catch" tap lands
  after the deceleration ended; UIKit's stop-on-touch is instantaneous by construction. Ours is measured at 0 ms.

## Native numbers (iOS 27.0; the fixtures in `NativeCalibrationTests.swift`)

| quantity | native | model |
|---|---|---|
| recognition | first sample of 128 pt moves the content 117 pt | offset moves by \|t₀\| − 10 along t₀ at recognition |
| tracking | 1:1, 2 ms behind the finger event | same (ours 4–6 ms) |
| release velocity | 3457 pt/s (fast), 1350 (medium), 0 after a 0.5 s hold | unweighted least-squares slope over the last 100 ms (±1 %), evaluated at most one frame after the newest sample; the held slow drag is 0 by the 250 pt/s gate on its last 50 ms (≈ 170 pt/s), not by the hold (BTN-s3, SPEC S6 amendment; values pinned in `NativeCalibrationTests`) |
| deceleration | r = 0.99800 per ms (both fits, rms < 0.6 pt) | `DecelerationRate.normal` unchanged |
| decay end | stops at \|v\| ≈ 10 pt/s, 4.7–4.8 pt short of the analytic rest, no jump; 2.93 s / 2.47 s | `RestThresholds.velocity = 10`, natural decays end at `stopPosition` |
| rubber band | 89.0 pt for 190 pt overscroll (c = 0.569 implied, i.e. 0.55 with the 10 pt hysteresis) | unchanged |
| bounce-back | ω = 10.9–11.05 at 45.7 / 89 / 126 pt; durations 0.58 / 0.60 / 0.62 s; `B = v₀ + ωA ≈ −400·sign(A)` pt/s | `CriticalSpring.defaultStiffness = 119`, seed below |
| edge hand-off | crossing ≈ 1204 pt/s → 39 pt overshoot, back in 0.66 s | critically damped ω = 10.9 seeded with the crossing velocity (unchanged shape) |

## Root causes found (in order of impact)

1. **Recognition lost the whole first sample.** The baseline made `offset(t₀) == presentation`, so a fast flick whose
   first `DragGesture` value was 58–128 pt moved nothing for that sample; the content then tracked a frame behind and
   the drag travel ratio was 0.73–0.85 vs native 0.88–0.93. Native credits everything beyond the 10 pt hysteresis.
   Fix: `PanSession.baseline(..., hysteresis: 10)` uses `t₀ · min(1, 10/|t₀|)`.
2. **Release velocity under-estimated fast flicks by 14 %.** The tracker's exponential weighting (τ = 40 ms) favoured the
   last event, which is always slower (the finger stops to lift: 7 pt in 18 ms before a 3457 pt/s fling). Native equals
   the unweighted fit over 100 ms within 1 %. Fix: `VelocityTracker.timeConstant = 1 s`.
3. **Decelerations ran 40 % too long and ended with a jump.** Rest thresholds (4 pt/s, 0.5 pt) made a 3000 pt/s fling
   crawl for 4.0 s (native 2.93 s). Native stops at ≈ 10 pt/s and leaves the last ≈ 5 pt untraveled. Fix: natural
   `Decay` ends at `stopPosition` (where \|v\| < 10 pt/s), re-solved decays (`landsOnRestPosition`) still land exactly.
4. **Bounce-back 25 % too slow.** ω = 10 from rest (0.66–0.75 s) vs native 0.52–0.60 s. Native is ω ≈ 10.9 with a start
   velocity (see the model). Fix: stiffness 119 and the `ReleaseSolver` bounce-back seed.
5. Fling acceleration never applied on the fallback/27 paths: `caughtAt` (event clock) vs `now()` (state clock).
   Fix: the coordinator stamps `touchDown` with `state.now()`.

## Before / after (ours vs native, iOS 27.0; `.build/cal/run0` → `run1`)

| metric | native | before | after | target |
|---|---|---|---|---|
| tracking ratio, medium fling | 0.933 | 0.852 | 0.933 | 1:1 with native |
| tracking ratio, fast flick | 0.88 | 0.731 | 0.879 | |
| tracking lag (ms) medium / fast / slow | 2 / 20 / 20 | 22 / 22 / 38 | 4 / 6 / 22 | ≤ 1 frame |
| fast: fitted v₀ (pt/s) | 3457–3462 | 3051 | 3514 | |
| fast: decay distance (pt) | 1773 | 1522 (−14 %) | 1738 (−2 %) | ±5 % |
| fast: decay duration (s) | 2.93 | 4.02 (+37 %) | 2.93 (0 %) | ±10 % |
| medium: distance / duration | 689 / 2.47 | 666 / 3.62 | 700 (+1.7 %) / 2.48 | |
| rubber band 190 pt overscroll (pt) | 89.0 | 88.9 | 89.0 | ±10 % |
| bounce-back 89 pt (s) | 0.52 | 0.66–0.67 (+27 %) | 0.53 (+2 %) | ±15 % |
| bounce-back 45.7 / 126 pt (s) | 0.50 / 0.53 | – | 0.46 / 0.57 | ±15 % |
| edge hit: overshoot (pt) / settle (s) | 39.0 / 0.66 | 40.1 / 0.75 | 37.7 / 0.67 | |
| catch stop latency (ms) | instantaneous | 0 | 0 | |

(`before`/`after` columns are the ZTron variant; the native column is the same session's native run.)

## Bounce-back model

Fits of `x(t) = (A + B·t)·e^(−ωt)` to the native return from a held rubber band (finger at rest at release):

| A (pt) | ω (1/s) | B (pt/s) | v₀ = B − ωA (pt/s) | rms (pt) |
|---|---|---|---|---|
| −45.7 | 10.90 | −395 | +103 | 0.16 |
| −89.0 | 10.95 | −378 | +596 | 0.20 |
| −126.0 | 11.05 | −435 | +958 | 0.22 |
| +89.0 (bottom) | 10.95 | +378 | −596 | 0.18 |

`B` is roughly constant (`≈ −400·sign(A)` pt/s) while `ω` is fixed, so the native return is not a spring released from
rest (that would be `B = ωA`). See "40 pt check" below for the small-amplitude behaviour that decides the final form.

## Pinch + pan (part 5)

(see the section added by the pinch step)

## Programmatic zoom (2026-10-19, D22)

User report: the double tap "animates, then snaps". Measured native `UIScrollView.setZoomScale(_:animated:)` and
`zoom(to:animated:)` on iOS 27.0 (iPhone 18 Pro) with the spike's `-zoomCal` screen
(`Packages/ScrollArbitration/Spike/ArbitrationSpike/ZoomCalibrationViewController.swift`, UIKit lives in the spike only):
viewport 300 × 360, content 600 × 600, zoom 1 … 8, a `CADisplayLink` sampling the zoom view's presentation-layer scale,
the model `zoomScale` and both offsets every frame. Run: `TEST_RUNNER_ZS_CALIBRATE=1 ZS_DEST='id=<udid>'
scripts/test-spike.sh -only-testing:ArbitrationSpikeUITests/ZoomCalibrationUITests`, then
`scripts/fetch-calibration.sh <udid> <dir> dev.ztron.ArbitrationSpike` and `scripts/compare-zoom-calibration.py <dir>`.

| case | visible duration | ease-in-out fit (duration, rms of progress) | critical spring fit (rms) |
|---|---|---|---|
| 1 → 1.25 | 0.167 s (10 frames) | 0.170 s, 0.005 | — |
| 1 → 1.5 | 0.235 s | 0.225 s, 0.003 | — |
| 1 → 2, 2 → 4, 4 → 8 | 0.316 s (18–19 frames) | 0.310–0.320 s, 0.002–0.008 | ω 11.8, 0.10 |
| 1 → 3 | 0.401 s | 0.400 s, 0.004 | — |
| 1 → 4, 1 → 8, zoom(to:) 1 → 8 | 0.400 s (24 frames) | 0.400 s, 0.004 | ω 9.3, 0.094 |
| back: 2 → 1 / 4 → 1 / 8 → 1 / 8 → 2 / 1.5 → 1 / 1.25 → 1 | 0.317 / 0.400 / 0.401 / 0.417 / 0.233 / 0.167 s | same as the way in | — |

Findings (all cases): the curve is UIKit's `easeInOut` cubic Bézier (0.42, 0, 0.58, 1), not a spring (a critically
damped spring misses by rms 0.09–0.10 whatever ω); the scale and the offset are interpolated with the same curve (so
the anchored content point slides linearly to the visible centre, as our `ZoomAnimation` already did); the model
`zoomScale` jumps to the target at once, `scrollViewDidZoom` fires once at the start and `scrollViewDidEndZooming` at
the end; the duration depends on the zoom **ratio** `r = max / min` (1 → 2, 2 → 4 and 4 → 8 are identical), the same
in both directions: `duration = min(0.40, 0.125 + 0.19 · (r − 1))` is within 5 ms of every case.

Model: `ZoomTiming` (`Packages/ZTronScrollPhysics/Sources/ZTronScrollPhysics/ZoomTiming.swift`, `UnitBezier.easeInOut`,
`ZoomTiming.duration(from:to:)`), used by `ZTronScrollState.applyZoom` for `zoom(to:animated:)`, `setZoomScale(_:animated:)`
and the double tap. Fixtures: `NativeCalibrationTests.zoomSet2 / zoomSet8 / zoomBackFrom8 / zoomRect8` (progress per
frame), reproduced within rms 0.012. Before (D22 first pass): a critically damped progress spring (stiffness 119)
settled by point thresholds read as progress — ≈ 50 % after ≈ 150 ms, then the end values at once (the snap); with
travel-scaled thresholds it glided but took ≈ 0.9 s. Not matched: our `didZoom` still fires every frame of the
animation (native once); `zoom(to:)` without a scale change (a pure offset animation) gets the law's floor, 0.125 s,
not measured.

## Pinch overscroll and didZoom cadence (2026-10-19, D24)

- **Two-finger slide past an edge.** XCUITest has no two-finger drag (only `pinch(withScale:velocity:)`, symmetric about
  the element centre, and `twoFingerTap`), so the native two-finger overscroll could not be driven. UIScrollView's pan
  recognizer handles one and two touches with the same code path, so the reference is the one-finger rubber band already
  measured above (89 pt for 190 pt of overscroll, `c = 0.55` with `d` = viewport). Ours now applies that band to the
  pinch's offset on every axis that bounces (`PinchSession.offset`, D24) instead of following the fingers linearly; a
  non-bouncing axis is clamped (D23). The hand-off to the remaining finger inverts the same band (`PanSession.baseline`),
  so the pan continues from the displaced offset without a jump (PinchPanTests section 7). `bouncesZoom` now concerns
  the scale only.
- **`didZoom` cadence.** Native fires `scrollViewDidZoom` once at the start of an animated zoom (its `zoomScale` is the
  model and jumps at once) and `didEndZooming` at the end. Ours fires it on every frame of the animation and of the
  bounce, by design: SPEC l.41 makes `zoomScale` the presentation value ("always equal what's on screen, frame by
  frame, whatever drives the motion") and M4 §6 flushes didZoom then didScroll once per tick. Kept; a delegate that wants
  the native cadence watches `isZooming` / `didEndZooming`.

## Open

- Native "catch" cannot be measured with XCUITest (quiescence wait); ours stops within the same frame (0 ms).
- Two-finger scrolling without zoom (UIScrollView pans with two fingers): the pan session ignores `touchCount ≥ 2`.
- iOS 15–17 centroid estimate during a pinch follows one finger's drag, not the true centroid (documented gap, M4).
- Programmatic zoom: `zoom(to:)` at an unchanged scale not measured (law floor 0.125 s). Two-finger overscroll not drivable by XCUITest (D24 uses the one-finger band).
