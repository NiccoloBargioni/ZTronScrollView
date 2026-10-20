# UIKIT-s2 handoff · 2026-10-20 · Sonnet 5.5 (side session, session (b) of docs/design/UIKIT-touch-observer.md, D31)
Status: done — session (b), committed 9330cff: the UIKit shell, the wiring, the demo probes, `UIKitObserverUITests`, both gate scripts. **Both gates pass:
`scripts/coverage-uikit.sh` 100 % lines in both files, `scripts/check-uikit-scope.sh` 0 violations.** Not started (by design): (c) docs
(parity-matrix row, design-note availability row, S14 §4 line) and the real iOS 15/16 run (the user's, Xcode 26.x).
Changed:
- `Gesture/UIKit/UIKitTouchObserver.swift` (new, 109 lines, whole file inside `#if canImport(UIKit) && os(iOS)`): `UIKitTouchObserverRecognizer`
  (passive: stays `.possible`; `cancelsTouchesInView` / `delaysTouchesBegan` / `delaysTouchesEnded` / `requiresExclusiveTouchType` false;
  `allowedTouchTypes` = direct + pencil (R2); self-delegate; `canPrevent` / `canBePrevented` false; weak anchor / coordinator / `CatchObserverState`;
  `install(on:)` idempotent, resets the core so a live sequence is cancelled; four `touches…` overrides → `forward` → `core.handle(…, time: now())` →
  `deliver` to `coordinator.handle / handlePinch / synthesizePan` + `CatchObserverState` sync), `UIKitTouchAnchorView.didMoveToWindow`,
  `UIKitTouchObserverAnchor` (`UIViewRepresentable`, `dismantleUIView` uninstalls). DEBUG counters `uikit.began/moved/ended/cancelled/canPrevent/canBePrevented`.
- `Gesture/PanGestureAdapter.swift`: on `state.usesUIKitTouchObserver` no SwiftUI observer gesture (`GestureAttach.observer` is now optional, nil there;
  `EmptyGesture` is not public SwiftUI API), `CatchArming` bypassed (`gated` false), no `.panTranslation`; new `UIKitObserverAttach` modifier puts the
  anchor in `.background(alignment: .topLeading)` (zero size, no hit testing). `PinchGestureAdapter.swift`: both closures return early on that path
  (`MagnificationGesture` / `MagnifyGesture` stay attached for recognition only, R3). `PanCoordinator.init`: `centroidSource = .spatial` there.
- Demo: `DemoApp` `-ZTronForceUIKitObserver` (= `forceFallback(.spatialEvents)` + `forceUIKitTouchObserver`); `PanScreen` `-ZTronShowToggle` (Toggle button
  removes / re-adds the scroll view), `-ZTronCancelProbe` (see Findings), counters `pan.ev.drag/cancel`, `phase.tracking` (a phase reader), `uikit.*`,
  `tracking=` and `probe=` in the readout. `UIKitObserverUITests` (8). `PanUITests` / `ZoomUITests` honour `ZS_DEMO_UIKIT=1`; `scripts/test-demo-ui.sh --uikit`.
- `Tests/ZTronScrollViewTests/UIKitObserverShellTests.swift` (5, real `UIWindow`): passive contract, the delegate / `canPrevent` answers, install /
  window move / dismantle / idempotence, `touchesCancelled` with no touches.
- `scripts/check-uikit-scope.sh`, `scripts/coverage-uikit.sh` (below).
Decisions (all small, none needs the user):
- Observer path = `observer: nil` in `GestureAttach` (no `EmptyGesture` in SwiftUI). The default paths keep the same gesture structure (`switch (mode, observer)`).
- Scope gate strips `//` and `/* */` comments before matching: plain `grep` hits prose at HEAD ("as in UIKit.", "UIScrollView parity"). Everything else as designed.
- Coverage gate = llvm-cov (xccov lists no package files, UIKIT-s1): per derived-data dir `Coverage.profdata` + test bundle / demo app `.app` + `.debug.dylib`
  (the demo scheme DOES instrument the package target: design risk 4 did not materialise), union of lines over all bundles, `--also-dest` adds a UI run on a
  second OS. Files not listed by a bundle fail loudly. The report also lists lines no real touch reached ("unit-run only").
- Dedicated simulators for this session (`ztron-uikit-b-27`, `ztron-uikit-b-175`, created with `simctl create`): the shared ones were busy with other sessions' UI runs.
Findings (measured, 27.0 and 17.5):
- UIKit asks `canBePrevented(by:)` (3–4 times per swipe) but NEVER `canPrevent(_:)` or the delegate's `shouldRecognizeSimultaneouslyWith`: they are only consulted
  for a recognizer that recognizes. The UI test asserts `canBePrevented ≥ 1` and `canPrevent == 0`; the answers are pinned by `UIKitObserverShellTests`.
- `touchesCancelled` IS reachable on both simulators, but not by the design's sheet: a sheet, the window / root view not accepting touches, and hiding the root
  view cancelled nothing. What works: `-ZTronCancelProbe` hides the window for 100 ms 300 ms into the press and sends the app to Settings 800 ms in
  (`UIApplication.open(openSettingsURLString)`); the UI test holds the press 4 s, then `app.activate()`. Cancel arrives on 17.5 every time and on 27.0 with the 4 s hold
  (3/3 runs; a 2.5 s hold gave it on 27.0 only once in two), core → `pan.ev.cancel ≥ 1`, phase idle. R6 therefore is NOT needed for the gate; the test still skips
  (R6) on a runtime that delivers no cancel, and `UIKitObserverShellTests.touchesCancelledWithNoTouchesChangesNothing` executes the override directly.
- `pinch(withScale:velocity:)` delivers two real touches: `testPinchZoomsAroundCentroid` asserts the focal error (content point under (150,180) stays within 30 pt), as `ZoomUITests`.
- A press that never moves is a touch-down and a lift at once on this path (`pan.ev.down == 1`, `pan.ev.drag == 0`, phase passed through `.tracking`): the catch no
  longer waits for a drag sample.
Coverage report (`scripts/coverage-uikit.sh --run --dest 27.0 --also-dest 17.5`, clean worktree at 76823c4 + session (b)'s files, unit + UI 27.0 preferred + UI 27.0 forced + UI 17.5 forced):
```
bundle …/dd-unit: 2/2 files of Sources/ZTronScrollView/Gesture/UIKit/ listed, binaries: 1
bundle …/dd-ui: 2/2 …, bundle …/dd-ui-forced: 2/2 …, bundle …/dd-ui-also: 2/2 …
OK   Sources/ZTronScrollView/Gesture/UIKit/TouchObserverCore.swift: 100.0 % lines (99/99)
OK   Sources/ZTronScrollView/Gesture/UIKit/UIKitTouchObserver.swift: 100.0 % lines (62/62)
  unit-run only (R6 / pinned answers / synthetic batch): …/TouchObserverCore.swift:88-89 (a `began` for a live id)
  unit-run only …/UIKitTouchObserver.swift:65 (shouldRecognizeSimultaneouslyWith), :69-74 (canPrevent)
coverage-uikit: PASS (100 % lines in every file)
```
The lines marked "unit-run only" are executed by direct calls / synthetic batches only (UIKit never asks those answers; a replaced `began` needs a missed `ended`);
everything else, `touchesCancelled` and the core's cancel branch included, is reached by real touches in the demo UI runs.
Open:
- Real iOS 15/16 runtimes (the shipped `#unavailable(iOS 17)` gate): the user's run with Xcode 26.x — `UIKitObserverUITests` + `PanUITests` / `ZoomUITests` with `--uikit`
  (and `--uikit --forced` = the shipped shape) on the 15/16 simulators or a device; `testCancelProbe` is a real check there. Device-only checks stay as listed in the design (staggered lift, re-touch, third finger).
- `PanUITests.testControlsUsable` is flaky on the 27.0 forced path under heavy simulator load (toggle tap misses): failed 5 of 14 runs in this worktree during concurrent
  runs of other sessions, passed the last 8 (5 solo, 3 full-class) while the unchanged baseline (3da15b4) passed 14/14 — the forced path is code-identical to HEAD (observer
  gesture attached, `uikit` false); the zero-distance Drag observer is attached unconditionally on 18+ forced and can steal a fast first tap. Re-run on a quiet machine.
- On the fresh 17.5 simulator the same test fails at the text field ("Neither element nor any descendant has keyboard focus") at the unchanged baseline too: environment
  (new device, software keyboard), not this change. `PagerUITests.testPagerArbitration` on 17.5 is the known Q3 case.
- Rect-only filter (R1): a modal presented over a viewport (a sheet in the same window) counts touches inside the viewport rect; not measured.
Next: 1. (c) docs: parity-matrix row, design-note availability row + the two ★ deviations of UIKIT-s1, S14 §4 line. 2. The user's 15/16 run. 3. Before any commit touching
`Gesture/UIKit/` and at milestone end run both gates: `scripts/check-uikit-scope.sh` and `scripts/coverage-uikit.sh --run --dest <27.0> --also-dest <17.5>` (≈ 25 min).
Tests (clean worktree at 76823c4 + session (b)'s files; dedicated simulators):
- Unit, whole target: **587 tests in 51 suites passed on 27.0 and on 17.5**; touched suites 42 (core 27 + spatial-equivalence 6 + gating 4 + shell 5).
- `UIKitObserverUITests` 8/8 on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks` (`testCancelProbe` real with the 4 s hold).
- Default path (no force arg): 27.0 preferred Pan 7 + Zoom 7 + Pager 1 = 15/15; 17.5 preferred Pan 6/7 (keyboard, above) + Zoom 7/7, Pager 0/1 (Q3, known).
  27.0 forced Zoom 7/7, Pager 1/1, Pan 6/7 on the loaded runs then 3/3 full-class solo (flake, above).
- `--uikit` (observer path under the existing suites): 27.0 preferred Pan 7 + Zoom 7 = 14/14; 27.0 forced 13/14 (controls flake); 17.5 Zoom 7/7, Pan 6/7 (keyboard) preferred and forced.
- `scripts/check-uikit-scope.sh` → 93 files, 0 violations (negative test: planted `import UIKit` / `UIScrollView` / unguarded file in a scratch copy → exit 1).
Usage: weekly n/a (side session) · cache hit n/a
