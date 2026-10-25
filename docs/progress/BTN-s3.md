# BTN-s3 handoff · 2026-10-25 · Opus 5.5 (coordination, docs, UI lanes) + Fable 5.1 builder (physics, D16) · default effort
Status: done. BTN-s2's proposal P1 + P2 is in the physics package and the release pipeline: the release velocity comes
from the touch moves only (an event-free pause never changes it) and a natural release does not decelerate below 250 pt/s.
SPEC S6 amended, D49 revision 2 (landed).

## Changed
- Physics (Fable builder, D16), `Packages/ZTronScrollPhysics/Sources/ZTronScrollPhysics/VelocityTracker.swift`:
  - P1: the fit is evaluated at `e = min(max(lift, newest), newest + liftTolerance)` (`liftTolerance` = 1/60 s). `restTimeout`,
    `restDistance` and `isResting` are gone.
  - P2: `gateVelocity` = displacement over the last `gateSpan` (50 ms) before the newest sample (interpolated, clamped to the oldest
    sample). `minimumDecelerationVelocity` = 250 pt/s, inclusive; 0 turns the gate off.
  - `velocity(at:)` is gated; `ungatedVelocity(at:)` is the fit alone; `lastMotionVelocity` = the ungated fit at the newest sample.
    `PointVelocityTracker` gates per axis and gets `ungatedVelocity(at:)`. The init is now `(window:minimumDecelerationVelocity:)`.
    `AxisMotion.swift` `rubberBandVelocity` doc updated.
- Library, `Sources/ZTronScrollView/Gesture/ReleasePipeline.swift`:
  - `velocity(tracker:liftTime:fallback:gated:)`: the gesture fallback (tracker < 2 samples) is gated on its own magnitude.
  - `endDrag` gates natural releases only (`targetBehavior == nil && !settings.isPagingEnabled`). A scroll-target behavior or the
    paging knob sees the ungated fit and keeps `negligibleReleaseVelocity`. A delegate retarget in `willEndDragging` sees the gated
    velocity. The spring-back seed stays `lastMotionVelocity`, and the catch's fling acceleration runs after the gate.
  - `PanCoordinator.swift`: one comment.
- Tests:
  - Physics:
    - Calibration pinned first (c0bb1d5, green on the old code): fast 3454.0056, medium 1344.1487, plus a new edge fixture from
      run4's ZTron lane 1335.2071 pt/s, 1e-6 relative.
    - New: pause invariance, gate at ±248 / ±252 pt/s at 60 and 120 Hz, a fling slowing to 200 pt/s over its last 50 ms rests,
      `gateVelocity` with < 50 ms of samples and with interpolation, per-axis gate, init fallbacks.
    - `bounceBackAfterAPause…` and `slowDragHeldBeforeLift…` re-asserted: the slow drag is 0 by the gate (≈ 160 pt/s), not by the pause.
  - Library:
    - `ReleasePipelineTests.velocityTrackerVsFallback` updated; new `slowNaturalReleaseRestsButATargetBehaviorSeesTheVelocity`.
    - `PinchPanTests` ×3 (hand-off tests that ended with a 1250–1875 pt/s step and relied on the pause to rest): the finger now crawls
      1 pt/frame before the lift, and the assertions are unchanged.
- UI: `ButtonDragUITests.testDragRunningOffTheScreenEdgeRestsWhereNativeFlings` → `…FlingsLikeNative`. The spike's edge drag now flings
  450 pt vs native 475 on 27.0 (was 64); the test asserts > 300 and 0.7–1.3 × native.
- Docs:
  - SPEC S6 "Release velocity" amendment (2026-10-25).
  - Parity row "Release after an event-free pause": approximate. UIKit's rule matched; estimator G3 differs.
  - `docs/design/PHYSICS-calibration.md` release row.
  - Orchestration D49 revision 2, open item 11, log row; STATE row.

## Decisions
- Gate only natural releases (task brief, D49 revision 2). Target behaviors use velocity to pick a page or snap point, and UIKit's paging
  is not a deceleration.
- A delegate retarget counts as natural. It sees the velocity UIKit would decelerate with, 0 under the gate. What native reports to
  `willEndDragging` for a gated release is still unmeasured (BTN-s2 open 5).
- `lastMotionVelocity` lost the old "< 1 pt in 64 ms" rest check. It differs only for a finger held still with moves delivered for
  64–100 ms; the calibration's bounce-back seeds are unchanged (pinned test).

## Verification
- Calibration, 27.0. Replay: the stored run1 / 3 / 4 finger streams give the same fast / medium / edge velocity (pinned in
  `NativeCalibrationTests`). Live: CalibrateUITests at host load 260–900, a full run plus an interleaved A/B on the same private device
  (base b3bfbfd vs head, 2 rounds, ZTron lane):

  | gesture | metric | base | head | run4 |
  |---|---|---|---|---|
  | medium | decay distance (pt) | 700.3 / 700.3 | 700.3 / 700.3 | 700.3 |
  | edge | decay distance (pt) | 110 / 110 | 110 / 110 | 110 |
  | edge | overshoot (pt) | 40.2 / 37.2 | 40.2 / 37.2 | 37.7 |
  | fast | decay distance (pt) | 1856 / 1857 | 1826 / 1927 | 1738 |
  | slow | post-lift motion | none | none | none |

  So fast / medium / edge are unchanged within run-to-run spread. Under this load the same 4000 pt/s drag gives 3517–3731 pt/s at one
  commit (fast vs catch), so the base itself moved against run4. The recorded "fingers" are delivery-time stamped, so replays of
  high-load runs are approximate.
- `ButtonDragSweepUITests`, ZTron lane, against BTN-s2's native lane on the same OS (`cmp.py`). Wrong fling/rest decisions:
  17.5 53 → 4 of 86, 27.0 54 → 5. Mean |Δx| where both fling: 17.5 92 → 25 pt, 27.0 83 → 36. Every remaining miss is a drag clamped
  at the screen edge at 225–300 pt/s, as the replay predicted. The holds no longer matter: 17.5 centre fast 464 / 445 for holds 0 /
  ≥ 0.05 vs native 448, centre default 303 vs 300.

## Two-axis gate (follow-up, measured the same day)
Demo probes now record both axes (`bd.native`: `ry`, `lock`, `PY` = y pan velocity / translation per callback; `bd.info`: `vely`,
`liftx` / `lifty`), `-ZTronBDHeight`, `-ZTronBDAxes h|v|hv`, and `ButtonDragSweepUITests` mode `diagonal`
(`testDiagonalNative` / `testDiagonalZTron`, opt-in): 200 pt drags from the scroller's centre toward the top-left at 0–90° ×
XCUI 350–700 pt/s, hold 0. Analysis `diag.py` in the notes folder: native's pan velocity at `.ended` (x, y), `isDecelerating`, and
the travel after the lift per axis, scored against three rules.
- **Two-axis `ScrollView`** (42 drags per OS, directional lock off on native): the vector rule `|(vx, vy)| ≥ 250` predicts
  native's motion on both axes in 42 / 42 on 17.5 and 42 / 42 on 27.0; per axis 18 / 19, larger axis 34 / 35. Native rests at
  |v| 244 and flings at 252 (27.0, 0°). Past the gate both axes decelerate from their own components, however small: 15° drags
  with vy 48–112 pt/s move y 38–64 pt. Ours (per axis) differs on 16–17 axis decisions of 42: 30–60° drags with both components
  < 250 rest on both axes where native flings (45° 400–500: native ≈ 100–130 pt per axis, ours 0), and the slow axis of 15° /
  75° drags rests. Where both move, travel differs by 15 pt on average.
- **Horizontal-only `ScrollView`** (`-ZTronBDAxes h`, 30–75° × 400–700): only the scrolling axis counts. 17.5 matches the
  per-axis rule 20 / 20 (vector 4 / 20), and 27.0 15 / 15. For example, 45° at 500 has vx 248 and a 348 vector, and native rests.
  Ours already matches (0 differences). So UIKit gates the velocity restricted to the axes the view scrolls.
- Side finding: on 27.0 the horizontal-only `ScrollView` never begins its pan for a 75° drag (no pan callbacks, offset 0); on
  17.5 it follows the x component (42 pt); ours follows on both (49 pt).

**Proposal P3 (for Fable, D16; not landed):** natural releases gate the vector of the gate velocities over the enabled axes:
`hypot(enabledX ? x.gateVelocity : 0, enabledY ? y.gateVelocity : 0) ≥ minimumDecelerationVelocity`. When it passes, every enabled
axis uses its `ungatedVelocity(at:)`; the gesture fallback is gated the same way over its components. Also consider a 2-D stop rule:
native stops when the vector speed drops under ≈ 10 pt/s, so a slow axis travels its full `0.4995 v`, while ours stops each axis on
its own and loses ≈ 5 pt there. Tests: a 45° drag at 200 + 200 pt/s flings both axes, a 15° drag moves its slow axis, a
horizontal-only view ignores y.

## Open
1. G3, the estimator. UIKit starts at the mean of its last three 50 ms velocities; ours is the 100 ms fit. A lift more than one frame
   after an eased-out drag drops the window's oldest samples: 27.0 4000 pt/s drag 2128 / 1873 / 1988 pt for holds 0 / 0.05 / 0.25 vs
   native ≈ 2350, and the `ButtonDragUITests` centre fast drag held 0.05 s gives 339–351 vs 445 (27.0 single runs at load 200+).
   17.5 is hold-invariant (2132 at every hold).
2. Edge-clamped drags near the gate rest where native flings (17.5 edge 275 / 300; 27.0 also 225 at hold 0.25).
3. Two-axis gate: measured (section above). UIKit gates the vector over the scrolling axes and ours gates per axis; P3 is
   proposed, not landed. 27.0's steep-drag pan refusal on a one-axis view is not mirrored.
4. Device check: ProMotion (120 Hz halves the samples in the 50 ms gate span) and a resting finger that reports small moves.
5. Native `willEndDragging` / `ScrollTargetBehaviorContext.velocity` for a gated release (BTN-s2 open 5).
6. Pre-existing, unrelated:
   - `ProofUITests.testNoClockTicksAtRest` fails 3 of 5 on a fresh 27.0 device at both base and head.
   - `UIKitObserverUITests.testTouchStopsDeceleration` bound 440 failed once at 469 under load, then passed alone (415).

## Next
1. G3 re-calibration on ZTron's own sample stream (CalibrateUITests + `NativeCalibrationTests` fixtures), Fable (D16).
2. Device check (open 4); then decide whether the gate span should be time- or sample-based on 120 Hz.
3. Merge this branch (`claude/vigilant-tharp-9659fb`; it carries the BTN-s1 + s2 merge e32dec2).

## Tests
- `scripts/test-physics.sh` → 117 tests, 18 suites, 0 failures (was 112).
- `ZTronScrollViewTests` (`scripts/test.sh -only-testing:ZTronScrollViewTests`, private devices) → 674 tests, 57 suites, green on 27.0
  (builder) and 17.5.
- Demo UI full suite, preferred path, private `simctl create` devices, staggered lanes, host load 130–950. Each OS: 173 executed,
  11 skipped (opt-in), 160 passed.
  - 27.0 failures: `ProofUITests.testNoClockTicksAtRest` (fresh-device flake, see open 6) and
    `UIKitObserverUITests.testTouchStopsDeceleration` (green alone).
  - 17.5 failures: `PagerUITests.testPagerArbitration` (the known Q3, iOS ≤ 17) and `PanUITests.testControlsUsable` (text-field focus;
    the DBG-s2 fix e8c5674 is not on main). Both fail identically at base b3bfbfd on the same device.
- `ButtonDragUITests` 3/3 on 27.0 after the test update (full-suite lanes on both OSes).
- `CalibrateUITests` 4/4 on 27.0 (`TEST_RUNNER_ZS_CALIBRATE=1`), plus the A/B above.
- `ButtonDragSweepUITests` ZTron lane on 17.5 + 27.0 (`TEST_RUNNER_ZS_BD_SWEEP=1`), 86 drags each. Diagonal mode, both lanes, both
  OSes: two-axis 42 + 42 drags, horizontal-only 20 + 20 drags (`TEST_RUNNER_ZS_BD_AXES=h`); all `Test Case`s passed (no
  assertions).
- Not run: `--forced` / `--uikit` lanes, 18.x, iOS 15/16. 17.5 preferred feeds the tracker from DragGesture, 27.0 from
  SpatialEventGesture, and `UIKitObserverUITests` the observer path.
- Raw data: side-session notes `local_9890573b-…/btn-s3/`. It holds the sweep `.bds` files, `cmp.py` (sweep vs native), `replay.py`
  and `fixtures.py` (old vs new rule on calibration streams), and the A/B calibration JSON + reports.

Usage: not measured.
