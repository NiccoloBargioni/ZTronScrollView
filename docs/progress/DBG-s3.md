# DBG-s3 handoff · 2026-10-20 · Sonnet 5.5 · Debugger (`PanUITests.testControlsUsable` on iOS 18.x, the slider step)
Status: done. Root cause measured, fixed (D34, commit 9c27d26), two regression tests red without / green with the fix on 18.5 (both paths), first full demo UI picture for 18.x recorded. Closes (b) of Orchestration open item 10 (DBG-s2, branch `claude/determined-lederberg-7907ea`, not in this tree). **D34 overrides a user amendment and needs the user's confirmation (Open 1).**

Root cause (measured with a temporary UIKit probe in the demo: `UISlider` control events + `UITouch.gestureRecognizers` on every touch; probe, logs and runners are in the notes folder `slider-18x/`):
- The slider is a UIKit `UISlider` (`PlatformViewHost<…SystemSlider>`), touch-based up to iOS 18: it tracks through `touchesBegan/Moved`, not through recognizers.
- On iOS 18.x SwiftUI backs the **observer** gesture with a `UIKitResponderGestureRecognizer` (`cancelsTouchesInView = true`) that goes `.began` with the first touch movement (`SpatialEventGesture` and the zero-distance `DragGesture` alike). UIKit then withdraws the touch from the hit view: in the failing run the window sees `touch began … hitView=UISlider`, the slider gets **no `touchDown` event at all**, and the next move reports `hitView=nil`.
- Without the observer gesture the same drag moves the slider: `SLIDER event touchDown` in the same millisecond as `touch began`, 0.2 → 0.9576; the pan's recognizer (`DragGesture(minimumDistance: 10)`) never leaves `.possible` while the control tracks, so it is harmless.
- It is the observer and not the attach style, `name:`, or the pan. 18.5, slider after the XCUI drag from 0.2: preferred 0.2 → 0.2 ×3; `-ZTronPanGestureMode gesture` / `high` 0.2 → 0.2 ×3 each; forced 0.2 → 0.2 ×3 (the iOS 18 branch of `GestureAttach` ignored the arming flag, so the fallback `DragGesture` observer was attached unconditionally on 18+ forced, 26/27 included); `--uikit` (no SwiftUI observer) 0.2 → 0.9576 ×3.
- Not an 18.5 quirk, not XCUI: 18.0, 18.2, 18.4, 18.5, 18.6 all 0.2 → 0.2 (a native `ScrollView` with the same content passes the same drag on 18.5: 0.9576, whole `testControlsUsable` 3/3).
- Why 26+/27.0 pass: there the UISlider is recognizer-based (`UIPanGestureRecognizer` + `UILongPressGestureRecognizer`, `cancelsTouchesInView = false`), so the observer's cancellation has nothing to cancel: 26.0, 26.5 0.2 → 0.9343, 27.0 0.9438. 17.5 passes because the observer is armed only while content moves (`CatchArming`): 0.9576.
- Excluded from the brief's suspects: the direction lock, the arbiter hand-off, the position ticket (b0ab38a is before it), the keyboard.
Evidence table (preferred path, slider after the drag, one private clone per OS; iPhone 15 / 16 / 17 Pro / 18 Pro):
| OS | 17.5 | 18.0 | 18.2 | 18.4 | 18.5 | 18.6 | 26.0 | 26.5 | 27.0 |
|---|---|---|---|---|---|---|---|---|---|
| before the fix | 0.9576 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.9343 | 0.9343 | 0.9438 |
| after (new slider test) | pass | 2/2 | 2/2 | 2/2 | 2/2 (+ forced) | 2/2 | — | — | — |

Changed (9c27d26 code and tests; docs in the second commit):
- `Availability/ZTronCapability.swift`, `Availability/ZTronAvailability.swift` — `spatialEvents` and `liveMagnifyCentroid`: `minimumOS` 26.0 and `#available(iOS 26, *)` (the API ships in 18; the library uses it from 26, D34). `subviewContainers` stays 18. 18.x takes the iOS 17 raw-touch row.
- `Gesture/PanGestureAdapter.swift` — `GestureAttach`, iOS 18 branch: `simultaneousGesture(observer, name:, isEnabled: observerEnabled)` (the flag was ignored). Comments there and in `CatchObserver.swift`.
- `Tests/ZTronScrollViewTests/AvailabilityTests.swift` — the `minimumOS` table.
- `Demo/ZTronScrollViewDemoUITests/PanUITests.swift` — `testSliderHorizontalDragMovesSliderNotScroller`, `testSliderDragWorksAgainAfterTheContentMoved` (fling, back to the top, then the slider: the arming gate flips back). The check `contains("y=0 ")` in `testVerticalDragOnSliderScrolls` could never fail (the info string has no trailing space): it parses `y=` now.
- `Demo/ZTronScrollViewDemoUITests/PagerUITests.swift` — the trailing edge is `900 − frame.width` (it was `x >= 500`).
- Docs: SPEC S2 amendment note, S3 rows, S12; `design-note.md`, `M3-pan.md`, `M4-zoom.md`; Orchestration D34 + open item 11 + log row; STATE row.
Decisions:
- D34: `SpatialEventGesture` from iOS 26; 18.x uses the armed `DragGesture` observer with the documented iOS 17 divergences (touch-down at rest waits for the first drag sample, count 1, pinch centroid = `startLocation` + drag follow). Chosen because it needs no new UIKit and no new spec row. **It overrides SPEC S2's "iOS 18+ keeps `SpatialEventGesture`" (user amendment 2026-10-20, made before any 18.x run).**
- Not taken, needs the user: the D31 UIKit touch observer on 18.x (SPEC S2 exception widened from 15–16 to 15–16 + 18.x; an availability change, the 100 % gate and the scope gate exist). Measured on 18.5 with `--uikit` (the same code as that option): slider 0.2 → 0.9576 ×3, `PanUITests` 8/9 (only the DBG-s2 keyboard step), `ZoomUITests` 7/7; it would keep touch-down at rest, the live centroid and the finger count on 18.x.
- `PagerUITests`: see the picture. The red on 17.5 that was filed as "the known Q3 case" is this device-width bug (below), not Q3.

First full demo UI picture, iOS 18.5 (iPhone 16 clone, `scripts/test-demo-ui.sh`; the suite is now **84 tests** + the 2 new = 86, 4 skipped by design: `CalibrateUITests` ×4; "63 tests" in the brief is the older size):
| run | tree | result | failure → cause class |
|---|---|---|---|
| preferred | before (ecca598) | 78 pass / 2 fail | `PanUITests.testControlsUsable` slider step → **this repo** (fixed). `PagerUITests.testPagerArbitration`, "swipe at the trailing edge pages" (0 ≠ 1) → **this repo, test**: on a 377 pt viewport the scroller's edge is x 523, the loop stopped at 508 ≥ 500 and the last swipe only scrolled (fixed in the test) |
| forced | before | 77 / 3 | the two above + `ProofUITests.testNoClockTicksAtRest` (`transform.effect` 1 ≠ 0) → **flaky test**, DBG-s1 Open (`transform.effect` 1–2 at rest after Reset): on 27.0 forced, interleaved ×38 per tree, red 5/38 on the unfixed tree and 6/38 on the fixed one (host load 4–870), so unrelated to this change; green in the 18.5 forced run after the fix |
| preferred | after (9c27d26) | 81 / 1 | `PanUITests.testControlsUsable` at the keyboard step ("Neither element nor any descendant has keyboard focus") → **DBG-s2** (PositionTicket wrapper, e8c5674 on another branch) |
| forced | after | 80 / 2 | the same + `TargetsUITests.testNativeAndZTronTargetVelocityUnits` (native 0.7 vs ours 0.3) at host load 300–600 → **load flake**: re-run alone ×6, native 0.6 = ours 0.6 on the fixed tree and on the unfixed tree |
Other runs (fixed tree):
- 18.5 with both fixes (DBG-s2 e8c5674 cherry-picked in a scratch tree): `PanUITests` 10/10 preferred and 10/10 forced (`testControlsUsable`, `testFocusedTextFieldKeepsKeyboardThroughAvoidance`, both new tests included); `testControlsUsable` alone ×5: 5/5 preferred, 5/5 forced.
- 27.0 (iPhone 18 Pro clone), full suite: preferred 86 executed, 5 skipped (the 4 + `UIKitObserverUITests.testCancelProbe`), **0 failures**; forced 86 / 5 skipped / 1 failure = the `testNoClockTicksAtRest` flake. 26.5 (iPhone 17 Pro): `PanUITests` 9/9 preferred and 9/9 forced (new tests included).
- 17.5 (iPhone 15): `PanUITests` 8/9 preferred and forced (only `testControlsUsable` at the keyboard step = DBG-s2); the two new tests pass. `PagerUITests.testPagerArbitration`: the OLD test fails at the same trailing-edge assertion as on 18.5 (2 of 3 runs; the third failed to relaunch), the edge-derived test passes 3/3 preferred and 3/3 forced. **So the demo-suite red on 17.5 labelled "spike Q3" was this geometry bug (iPhone 15 and 16 are both 393 pt wide). Q3 itself (a UIKit pager's pan blocked by a SwiftUI recognizer, open item 1) concerns ZTronPages / the spike, not the SwiftUI stand-in the demo test drives.**
- `PagerUITests.testPagerArbitration` on the 27.0 iPhone 18 Pro Max (440 pt; failed 5/5 before, DBG-s2 Open 5): passes 2/2 with the edge fix.
- Unit (`scripts/test.sh`, private clones): 587 tests / 51 suites green on 18.5, 27.0 and 17.5. `scripts/check-uikit-scope.sh` clean.

Open:
1. **User: confirm D34, or ask for the D31 UIKit observer on 18.x** (above). Either is a few lines in `ZTronCapability` / `ZTronAvailability`; D34's tests and docs then change accordingly.
2. Touch-based UIKit controls on 26+/27.0 under the always-on `SpatialEventGesture` observer are not measured (Stepper, segmented Picker, DatePicker, Menu). The Slider and the Toggle are recognizer-based there. If one fails, `minimumOS` of the two capabilities moves up.
3. `ProofUITests.testNoClockTicksAtRest` is flaky on fresh clones of 18.5 and 27.0 forced (DBG-s1 Open; `transform.effect` 1–2 at rest right after Reset; ~15 % of runs either tree); a session of its own if it matters.
4. The iPhone 16 Pro Max 18.5 pager run was lost (the clone got stuck in creation); the 27.0 Pro Max (same width) passes. 18.1 / 18.3 runtimes are not installed; the five installed 18.x behaved identically.
5. Orchestration's "known Q3 pager case" for 17.5 in the State rows and handoffs (ORCH-s1, M3-s3 notes) is superseded: with the edge fix the demo suite on 17.5 is green except DBG-s2's keyboard step.
Next: 1. user answers Open 1; 2. land DBG-s2 (e8c5674 + its docs) and this branch (they overlap in `PanUITests.swift` and the append-only lines of Orchestration / STATE: keep both sides); 3. then `testControlsUsable` ×5 on 18.5 / 17.5 / 27.0 both paths (it is 1/1 here only in the scratch tree with both changes).
Tests: `scripts/test.sh` full ×3 (587 green); demo UI as listed above, every run on a private clone (`xcrun simctl clone`, own derived data, `-collect-test-diagnostics never`, deleted afterwards); `Executed N tests` checked against the suite size (86 = 84 + 2, 4–5 skipped).
Usage: not measured (about 70 simulator runs on 14 clones; host load average 100–740 from other sessions, taps held up, one load flake above).
