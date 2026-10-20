# UIKIT-s1 handoff · 2026-10-20 · Sonnet 5.5 (side session, session (a) of docs/design/UIKIT-touch-observer.md, D31)
Status: done — session (a): pure core + availability + state flag + tests, committed 5aba0db. Not started (by design): the UIKit shell,
the anchor representable, the adapters' / `PanCoordinator.init` wiring, `DemoApp`, UI tests, the two gate scripts (session (b)), docs (c).
Changed:
- `Gesture/UIKit/TouchObserverCore.swift` (new, Foundation + CoreGraphics only, no `#if`): `TouchSample`, `ObserverOutput`, `TouchObserverCore`.
- `Availability/ZTronCapability.swift`: `case uikitTouchObserver` (`minimumOS` 15.0, internal `preferredOSCeiling` 17.0, `isGated` true).
- `Availability/ZTronAvailability.swift`: `osSupports` = `#unavailable(iOS 17)`; public `forceUIKitTouchObserver(_:)` (DEBUG, inert in release);
  `isAvailable` returns true when it is on; `ForcedFallbackStore.observerOn`.
- `State/ZTronScrollState.swift` (2 hunks): `let usesUIKitTouchObserver = isAvailable(.uikitTouchObserver) && !usesSpatialEvents`, chosen once at init.
- Tests: `TouchObserverCoreTests.swift` (new: 3 suites, see below), `AvailabilityTests.swift` (OS table + 3 new tests), `Support/OSPath.swift`
  (`RunningOS.shipsPreferred(_:)`).
## API session (b) wires (differs from the design's sketch in two places, marked ★)
- `TouchSample { id: UInt, phase: .began/.moved/.ended/.cancelled, location: CGPoint }` — ★ no `time` field.
- `mutating func handle(_ samples: [TouchSample], viewport: CGRect, time: TimeInterval) -> [ObserverOutput]` — ★ ONE delivery time per call:
  the shell passes the adapter's `now()` (`Date().timeIntervalSinceReferenceDate`), D14. `UITouch.timestamp` never enters the core. Call it once per
  `touchesBegan/Moved/Ended/Cancelled` with the batch's touches of type `.direct` / `.pencil` (R2), `location` already in the anchor's space,
  `viewport = CGRect(origin: .zero, size: peek.metrics.viewportSize)`.
- Outputs, in order: `.pan(PanEvent)` → `coordinator.handle`, `.pinch(PinchEvent)` → `handlePinch`, `.synthesize(p, t)` → `synthesizePan(p, t)`.
- Read-only for syncing `CatchObserverState` / the double-tap fallback: `isDown`, `centroid`, `activeCount`.
- `@discardableResult mutating func reset() -> [ObserverOutput]`: `[.pan(.cancelled), .pinch(.cancelled)]` when a sequence was live (view removed
  mid-touch), else `[]`. ★ Returns the cancels instead of staying silent so `dismantleUIView` / `didMoveToWindow(nil)` can forward them.
- `ZTronAvailability.forceUIKitTouchObserver(true)` is public for the demo; `-ZTronForceUIKitObserver` = `forceFallback(.spatialEvents, true)` +
  `forceUIKitTouchObserver(true)`, in any order relative to `forceAllFallbacks` (the on-switch is separate from the forced set and wins over it).
- `PanCoordinator.init` (session b): `if state.usesUIKitTouchObserver { pinch.centroidSource = .spatial }` before the existing chain.
## Emission (what the tests pin; = SpatialCatchGesture's order)
Per delivery: pinch part, then pan part, then the pinch end. Count change → `fingerCountChanged(count, remaining: centroid)` (also 0, with the last
centroid); no count change and ≥ 2 touches that moved → `.changed(m, centroid)` where the spatial path sends `fingerCountChanged` (the magnify
gesture's `.changed` is replaced by this); one touch that moved → `.synthesize`; first touch → `touchDown(first = oldest, touchCount)`; last lift →
`touchesEnded`; `.pinch(.ended)` when a pinch was live and the count drops below 2 (after `touchesEnded` on 2→0). Cancel of an own touch → both
`.cancelled`, everything dropped. Foreign (began outside) / unknown / empty → nothing. `m = carried × d / d0`, `d` = distance of the two OLDEST touches.
## Decisions
- ★ Pair change under a live pinch (a lifted finger was one of the two oldest, or a swap in one delivery) keeps the magnification already reached
  (`carried = lastMagnification`) instead of the design table's "next `.changed` = 1": `PinchSession.apply` divides by its own `baseMagnification`, so a 1 would
  jump the scale back to the pinch start (the D25 family). A re-touch from < 2 fingers starts at 1 and the session takes the first sample as its base (D29).
- Coincident fingers (`d0 == 0`): nothing is emitted while `d == 0`; the first spread becomes the reference (ratio 1). `d == 0` later in a pinch emits
  nothing and the ratio resumes against the unchanged base. No NaN/inf ever leaves the core.
- A `began` for a live id (its end missed, id reused) replaces the touch and counts as a move; no foreign-id bookkeeping (a foreign touch is simply unknown).
- The viewport rect is a parameter of every call (rotation / resize): contains is min-inclusive, max-exclusive.
- `uikitTouchObserver` is the first capability whose preferred path is the OLD-OS one, hence the internal `preferredOSCeiling` and the test helper
  `RunningOS.shipsPreferred`; on 17+ hosts `shipsEveryCapability` (OS-minimum only) is unchanged, the observer is excluded where "preferred" is asserted.
## Tests
- `TouchObserverCoreTests` (27): tap, drag, delivery time on every output, drag outside, viewport filter (once at `began`, edges, per-call rect),
  foreign touches, pinch ratio/centroid, two down at once, third finger, pair change with and without count change, coincident / crossing fingers,
  staggered lift + one-finger continuation + no `.changed` after the lift (D25), re-touch (D29), both up at once, new sequence, cancel (mid-pinch, single,
  foreign), defensive (unknown ids, empty batch, replaced `began`), `reset` live/idle.
- `TouchObserverSpatialEquivalenceTests` (6): scripted tap / drag / staggered / re-touch / simultaneous / three-finger sequences through the core and
  through a line-for-line model of `SpatialCatchGesture.onChanged`; common events must be equal batch by batch.
- `UIKitObserverGatingTests` (state flag on both OS paths; `-ZTronForceUIKitObserver` shapes: all fallbacks + observer = the shipped 15–16 shape; observer alone;
  spatial wins on 18+). `AvailabilityTests`: table row `(15, 0)`, `uikitTouchObserverIsAnOldOSCapability`, `forcingEverythingKeepsTheObserverOff` (R4),
  `forceUIKitTouchObserverMakesItAvailableOnEveryOS`.
## Coverage (measured)
`TouchObserverCore.swift`: **100 % lines (106/106), 100 % regions (64/64), 100 % functions (18/18)** by the three suites of `TouchObserverCoreTests.swift`
alone (`-only-testing` those suites, `-enableCodeCoverage YES -resultBundlePath`, 27.0).
**Finding for session (b) / `coverage-uikit.sh`:** with this SwiftPM scheme `xcrun xccov view --report --json` (and `--archive --file-list`) on the
`.xcresult` lists **no files of the library target** (target `ZTronScrollView`: 0 files; also with `CLANG_COVERAGE_MAPPING=YES`), only the test files. The
library IS instrumented: read the profile directly,
`xcrun llvm-cov report -instr-profile=<DD>/Build/ProfileData/<UDID>/Coverage.profdata <DD>/Build/Products/Debug-iphonesimulator/ZTronScrollViewTests.xctest/ZTronScrollViewTests`
(`llvm-cov show … <file>` for uncovered lines), with `-derivedDataPath <DD>` passed to `scripts/test.sh`. The demo app's coverage will need the same route (its
`.app` binary + the demo's `Coverage.profdata`); check early that the demo scheme instruments the package target (design risk 4).
## Open
- Shell, wiring, demo, UI tests, gates: session (b). Real iOS 15/16 run: the user's.
- `design-note.md` availability row, parity-matrix row, SPEC S14 line mention the two ★ deviations: session (c).
- Session (b) should assert in the UI tests that `.changed` carries the centroid the readout logs (design `testPinchZoomsAroundCentroid`).
Next: 1. Session (b): `UIKitTouchObserver.swift` (recognizer + anchor + representable), `PanGestureAdapter` / `PinchGestureAdapter` / `PanCoordinator.init` wiring, `DemoApp` arg.
2. `UIKitObserverUITests` on 27.0 + 17.5 with `-ZTronForceUIKitObserver` (+ `-ZTronForceAllFallbacks`). 3. `scripts/coverage-uikit.sh` (llvm-cov route above) + `scripts/check-uikit-scope.sh`.
Tests: shared tree had other sessions' uncommitted edits, so verified in a clean `git worktree` at b091ab1 + my files overlaid (staged blobs byte-identical):
`ZS_DEST=… scripts/test.sh -derivedDataPath .build/dd -only-testing:ZTronScrollViewTests` → **520 tests in 44 suites passed on iOS 27.0 and on 17.5**
(both OS paths inside the suites); targeted 27.0 run of the 4 touched suites 56/56 first.
Usage: weekly n/a (side session) · cache hit n/a
