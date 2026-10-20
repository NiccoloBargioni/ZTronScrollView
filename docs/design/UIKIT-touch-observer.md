# UIKIT · Raw-touch observer for iOS 15–16 (design, user amendment 2026-10-20)

Scope: SPEC S2 amendment (l.46–67), S3 rows "Raw touches"/"Pinch" (l.74–79), S12 (l.765), S14 §3/§5 gates. Builds on
`docs/design/M3-pan.md` (CatchObserver, CatchArming), `M4-zoom.md` §2/§4 (centroid sources, one-finger lift), `MC-contract.md`
§6 notes A/E, Orchestration D14/D20/D23/D25/D29, `Gesture/CatchObserver.swift`, `PinchGestureAdapter.swift`, `PanCoordinator.swift`.
Design only; no production code here.

## 1. Problem

On iOS 15–16 the raw-touch observer is `DragGesture(minimumDistance: 0)`: it fires a few ms after touch-down, only while
armed (`CatchArming`, M3), reports one finger and no location after the first sample. Consequences today (M4 §4 table, USER-s4):
the pinch centroid is a guess (`.dragOnly`: viewport centre or the first finger's drag), the finger count is unknown (no
one-finger continuation after a pinch, no re-touch of the second finger, a staggered lift is a plain release), and at rest the
catch / `isTracking` / `touchCount` wait for the first drag sample. iOS 18+ has none of this (`SpatialEventGesture`). The user
allows UIKit **only** to observe touches on 15–16, with 100 % tested code. iOS 17 keeps today's fallbacks (user's choice).

**Not solved here (say it plainly):** Open item 1 / note E. On iOS ≤ 17 our recognized SwiftUI `DragGesture` pan makes the
hosting view take the touch from a UIKit pager's pan. The observer never recognizes, so it changes nothing there; the pan stays a
SwiftUI gesture. ZTronPages' fallback on 15–17 remains the container's job.

## 2. Architecture

```
UIWindow ── addGestureRecognizer ──► UIKitTouchObserverRecognizer (UIGestureRecognizer, stays .possible)   [shell, UIKit]
                                           │ touchesBegan/Moved/Ended/Cancelled → TouchSample(id, phase, local point)
                                           ▼
                                    TouchObserverCore (struct, Foundation + CoreGraphics only)               [core, pure]
                                           │ [ObserverOutput] = .pan(PanEvent) | .pinch(PinchEvent) | .synthesize(CGPoint, t)
                                           ▼
                        PanCoordinator.handle / handlePinch / synthesizePan   (unchanged, OS-independent)
Anchor: UIKitTouchObserverAnchor (UIViewRepresentable, zero-size UIView at the viewport's top-leading corner) installs/removes
the recognizer from didMoveToWindow; one recognizer per ZTronScrollView; each filters to its own viewport.
```

**Recognizer** (`Gesture/UIKit/UIKitTouchObserver.swift`, `import UIKit.UIGestureRecognizerSubclass`):
- `cancelsTouchesInView = false`, `delaysTouchesBegan = false`, `delaysTouchesEnded = false`, `requiresExclusiveTouchType = false`.
- Is its own delegate: `shouldRecognizeSimultaneouslyWith` → true, `shouldBeRequiredToFailBy` → false, `shouldRequireFailureOf` → false;
  overrides `canPrevent(_:)` → false and `canBePrevented(by:)` → false. Never sets `state`; UIKit resets it after the last lift
  (MC note A proved this shape coexists with a UIKit pager and SwiftUI taps on 17.5–27.0).
- The four `touches…` overrides call `super`, then `forward(touches, phase)`: for each touch with `type == .direct || .pencil`
  (indirect / pointer ignored, see Open questions) build `TouchSample(id: ObjectIdentifier(touch), phase, location: touch.location(in: anchorView),
  time: now())` and hand the batch to `core.handle(batch, viewport: CGRect(origin: .zero, size: viewportSize()))`; emitted outputs go to the
  coordinator. `viewportSize()` reads `coordinator.state.peek.metrics.viewportSize` (non-tracking, cold). `touch.location(in: anchorView)` is the
  only geometry call: the anchor sits at the viewport origin, so the result is already the `.local` space the SwiftUI gestures use, rotation and
  window transforms included. No `superview` walks, no class checks.
- Filtering (in the core): a touch is *ours* iff its `began` location lies inside the viewport rect; the decision is made once per touch at
  `began` and kept for its lifetime (a finger dragged outside still belongs to the sequence, as with spatial events). Touches that began outside
  are dropped by id. Several scroll views per window = several recognizers, each with its own rect; nested views both observe the same touch
  (same as 18+, where both viewports' spatial gestures see it). Clipped-away content gets no touches (rect filter).
- ZTronPages coexistence: the recognizer neither delays nor cancels touches, so the pager's own pan and observer behave exactly as without us.

**Anchor and lifecycle:**
- `UIKitTouchObserverAnchor: UIViewRepresentable` → `AnchorView: UIView` (`isUserInteractionEnabled = false`, `isHidden = false`, zero frame).
  Attached by `PanGestureAdapter` as `.background(alignment: .topLeading) { anchor.frame(width: 0, height: 0).allowsHitTesting(false) }`
  on the viewport, only when `state.usesUIKitTouchObserver`. The representable's coordinator holds the `PanCoordinator` weakly and the recognizer strongly.
- `AnchorView.didMoveToWindow`: `window != nil` → if the recognizer's `view !== window`, remove it from its old view and `window.addGestureRecognizer`;
  `window == nil` → remove. Idempotent. Covers first attach, disappear, scene / window moves. `dismantleUIView` removes too and clears the core.
- App backgrounding / system gestures deliver `touchesCancelled` → `.cancelled` to pan and pinch; the core drops every touch.
- Weak references only from the recognizer to the coordinator and the anchor view; the window owns the recognizer, the representable's
  coordinator keeps it alive while the view lives; nothing retains the window.

**Gating** (`ZTronCapability.uikitTouchObserver`, `osSupports` = `#unavailable(iOS 17)`; `ZTronAvailability.isAvailable` as for every
capability, plus a DEBUG `forceUIKitTouchObserver(true)` that makes it available on 17+). `ZTronScrollState` gains
`let usesUIKitTouchObserver = isAvailable(.uikitTouchObserver) && !usesSpatialEvents` (a `let`, fixed at creation, R6). On that path:
no SwiftUI observer gesture is attached (`GatedGestureAttach` gets `EmptyGesture`, `CatchArming` is bypassed: a passive recognizer does not disturb
UIKit controls, which was the reason for arming), `PanCoordinator.init` sets `pinch.centroidSource = .spatial` (the observer provides the centroid),
`PanGestureAdapter` stops sending `.panTranslation`, and `PinchGestureAdapter` sends nothing (recognition only, §3). `forceAllFallbacks` on a real
15–16 device forces `.uikitTouchObserver` too, so the pure 15–16 path (`DragGesture(minimumDistance: 0)` + `.dragOnly`) stays testable there.

**DEBUG launch argument `-ZTronForceUIKitObserver`** (DemoApp, before any view): `ZTronAvailability.forceFallback(.spatialEvents, true)` +
`forceUIKitTouchObserver(true)`. Combined with `-ZTronForceAllFallbacks` it is the shipped 15–16 shape (MagnificationGesture + observer + every
fallback) on the 17.5 and 27.0 simulators; alone it is MagnifyGesture + observer (not shipped, run once for the shell lines). iOS 15/16 runtimes
do not run on macOS 27: the real 15–16 runs are the user's with Xcode 26.x.

## 3. Event mapping (the coordinator code stays OS-independent)

The core reproduces the emission order of `SpatialCatchGesture` (`CatchObserver.swift` l.36–79) exactly, so `PanCoordinator`, `PanSession`,
`PinchSession` and D20/D23/D25/D29 run unchanged. Per batch, with `active` = our touches not ended/cancelled, `previous` = count before the batch:

| Observation | Emitted (in this order) |
|---|---|
| first own touch began (`!down`) | `.pan(.touchDown(location: first active, time, touchCount: active.count))` after the count/centroid outputs below, as spatial does |
| `active.count != previous` | `.pinch(.fingerCountChanged(count:, remaining: centroid, time))` — count 2 from idle begins the pinch session (`PinchSession` l.188, D29, base from the next sample); 2→1 = one-finger hand-off (D20/D23); any→0 before `touchesEnded` |
| `active.count >= 2`, unchanged | `.pinch(.changed(magnification: d / d0, centroid: mean, time))` where `d` = distance between the two oldest active touches, `d0` captured at the last transition to ≥ 2 (a third finger does not change the pair; a pair change re-bases: emitted as `fingerCountChanged` with the new count then the next `.changed` = 1) |
| `active.count == 1`, unchanged, moved | `.synthesize(centroid, time)` → `PanCoordinator.synthesizePan` (one-finger continuation when the DragGesture died, M4 §4) |
| last own touch ended (`down`, `active.isEmpty`) | `.pan(.touchesEnded(time))`; if a pinch was live: `.pinch(.ended(time))` after it (closes D25's `gestureEndPending` window, which the magnify gesture closes on 18+) |
| 2→1 lift | `fingerCountChanged(1, remaining)` then `.pinch(.ended(time))` (the magnify end's role in `PinchGestureAdapter.onEnd`) |
| cancelled (any own touch) | `.pan(.cancelled)`, `.pinch(.cancelled)`, all touches dropped |
| moved touch with unknown id, ended id never began, empty batch | nothing (defensive branches, unit-tested) |

Centroid = mean of the active own touches' local locations, every batch (`observer.centroid` is also kept so `doubleTap` on 15 keeps using it).
Touch count in `touchDown` = own active count (so `touchCount ≥ 2` keeps the pan from asking the arbiter, M3 §7).

**Pinch on 15–16 — decision: the observer is the data source; `MagnificationGesture` stays attached for recognition only.**
Reasons: (S12) the gesture composition that was tuned empirically against child controls keeps the same recognizers, nothing is removed;
(S4) the magnification value's origin changes nothing at render time, zoom stays a coordinator-written transform; (behaviour) the
magnification, the centroid and the count then come from one stream with one timing, which removes the whole D25/D29 family (trailing samples
and cumulative magnification of a gesture that ended on one finger) on this path by construction; the `.changed` ratio is the same math the
gesture computes. `PinchGestureAdapter` on this path ignores the gesture's values (its `began`/`onEnd` closures return early). If a device check
shows the idle `MagnificationGesture` steals anything, dropping it is a one-line change (Open question 3).

**Hand-off, re-touch, staggered lift on 15–16:** the same events the 18+ path receives, so D20 (release velocity from the remaining finger only),
D23 (offset stays with the pan, only the scale bounces), D25 (no trailing sample: the core never emits a `.changed` after the lift) and D29 (re-touch =
`fingerCountChanged(2)` → new base) are enabled by the mapping alone. `heldRelease` (D29 guard) resolves on `touchesEnded` or `fingerCountChanged(2)`
as today.

**Clock (D14).** Spatial callbacks already stamp with the adapter's `now()` (`Date().timeIntervalSinceReferenceDate`), not the event time; the shell
does the same at delivery. `UITouch.timestamp` (uptime-based, like spatial event timestamps) is never emitted; the core may keep it only to order
samples inside one batch. Velocity still comes from the tracker's own deltas.

## 4. What stays divergent on iOS 17 (user's choice)

| Item | iOS 18+ / 15–16 with observer | iOS 17 |
|---|---|---|
| Pinch centroid | exact (mean of touches), ≤ 0.5 pt focal error | `startLocation` + pan-drag follow; error ≤ ½ spread change |
| Finger count / hand-off / re-touch | yes (D20/D23/D25/D29) | one-finger lift ends the pinch; pan continues only if the DragGesture survives; re-touch = new gesture |
| Touch-down at rest (catch, `isTracking`, `touchCount`) | at touch-down | a few ms later, only while `CatchArming` arms the Drag(min 0) observer |
| Pager under a `.container` answer (note E) | 18+: works (names) · 15–16: NOT fixed | not fixed |

## 5. Files and the 100 % coverage design

- `Sources/ZTronScrollView/Gesture/UIKit/TouchObserverCore.swift` — pure. `struct TouchSample { id: UInt (shell: ObjectIdentifier hash), phase, location, time }`,
  `enum ObserverOutput`, `struct TouchObserverCore { mutating func handle(_: [TouchSample], viewport: CGRect) -> [ObserverOutput]; mutating func reset() }`,
  internal: `[id: (location, order)]`, `ownIDs`, `down`, `previousCount`, `pairBase: (a, b, d0)?`, `centroid`. No `#if`: it compiles everywhere and is
  **100 % covered by `Tests/ZTronScrollViewTests/TouchObserverCoreTests.swift`** (synthetic batches for every row of §3 and every defensive branch; both OS
  paths as every unit test).
- `Sources/ZTronScrollView/Gesture/UIKit/UIKitTouchObserver.swift` — the shell, whole file inside `#if canImport(UIKit) && os(iOS)`: recognizer (4 overrides +
  `forward`, 3 delegate answers, 2 `canPrevent` overrides, init), `AnchorView.didMoveToWindow`, representable (`makeUIView`, `updateUIView` = no-op, `dismantleUIView`,
  `Coordinator`), `install(on:)`/`uninstall()`. Target ≤ 120 lines, every line a straight forward or a one-branch guard; the branches live in the core.
- `Sources/ZTronScrollView/Availability/ZTronCapability.swift` + `ZTronAvailability.swift` (new case, `forceUIKitTouchObserver`), `State/ZTronScrollState.swift`
  (one `let`), `Gesture/PanCoordinator.swift` (init), `Gesture/PanGestureAdapter.swift` (attach anchor, `EmptyGesture`, skip `.panTranslation`),
  `Gesture/PinchGestureAdapter.swift` (recognition only). Optional, if `CatchObserver.swift` is free: make `SpatialCatchGesture` call
  `TouchObserverCore.handle` with the spatial locations so there is one emission function; not required for the gate.
- `Demo/ZTronScrollViewDemo/DemoApp.swift` (arg), `Demo/ZTronScrollViewDemoUITests/UIKitObserverUITests.swift` (new), `scripts/coverage-uikit.sh`,
  `scripts/check-uikit-scope.sh`; `docs/parity-matrix.md` row; `docs/design/design-note.md` availability row.

**Shell line coverage by demo UI tests** (`UIKitObserverUITests`, launched with `-ZTronForceUIKitObserver` (+ `-ZTronForceAllFallbacks`) on `ZS_DEST`
and 17.5; asserts through the existing readout / event log, not screenshots):

| Shell lines | Test | Asserts (behaviour) |
|---|---|---|
| init, delegate answers, `install`, `didMoveToWindow(non-nil)`, `makeUIView` | every test's launch (`-ZTronScreen pan`) | the event log shows `down` on the first touch (observer installed) |
| `touchesBegan`, `touchesMoved`, `touchesEnded`, `forward` | `testSwipeScrollsAndLogsTouchDown` (PanScreen swipe) | `down` before `drag`, offset moved, `up` at the end; a Button tap still fires (S12) |
| touch-down at rest | `testPressAtRestSetsIsTracking` (`press(forDuration: 0.4)`) | `isTracking` true with no drag, `touchCount == 1`, `endSequence` on lift |
| catch while decelerating | `testTouchStopsDeceleration` (fling, then press) | phase `.decelerating` → idle at touch-down, no Button fires |
| outside-viewport filter | `testTouchOutsideViewportIgnored` (tap the screen's header above the viewport) | no `down` logged |
| two touches (`forward` with 2 samples, pinch rows) | `testPinchZoomsAroundCentroid` (`pinch(withScale:velocity:)` on ZoomScreen) | scale changed, centroid logged ≈ pinch centre (R3: if the simulator gives one touch, assert the scale only and note it) |
| `canPrevent` / `canBePrevented` | exercised by UIKit during any recognized SwiftUI gesture in the same window (the pan) — verified by a `DEBUG` counter read through the readout | both returned false at least once |
| `didMoveToWindow(nil)`, `uninstall`, `dismantleUIView` | `testHideAndShowReinstalls` (PanScreen toggle `-ZTronShowToggle` removes the scroll view, then re-adds it) | no `down` while hidden, `down` again after re-show |
| `touchesCancelled` | `testCancelProbe`: `press(forDuration: 1.0)` while the screen, under `-ZTronCancelProbe`, presents a `.sheet` 300 ms after the first `down` (UIKit cancels in-flight touches of the covered hierarchy) | event log shows `cancel`, phase idle, no offset change |

**Not reachable by XCUITest** (documented, not faked): staggered lift, re-touch, a second finger landing during a drag (SPEC S12 already records this),
app backgrounding mid-touch and system edge gestures. They need no distinct shell lines (the overrides are phase-agnostic forwards), so the
coverage gate does not depend on them; their **behaviour** is proven in `TouchObserverCoreTests` (the §3 sequences) and in the existing
`PinchSessionTests` / `PanCoordinator` tests, and listed as device checks for the user's real 15/16 run. If the sheet route does not produce
`touchesCancelled` on the simulator, the fallback is a `DEBUG` XCTest in the demo UI test bundle's host-side companion (`UIKitObserverShellTests`,
runs in the demo app process) calling `recognizer.touchesCancelled(Set<UITouch>(), with: nil)` on the live recognizer: this **executes the line
only** (acceptable for the gate, per S14) and is never cited as behaviour coverage; the handoff must say which lines are covered this way.

**`scripts/coverage-uikit.sh [--bundles <unit.xcresult> <ui.xcresult>]`** (uses `ZS_DEST`): (1) `xcodebuild test -scheme ZTronScrollView
-enableCodeCoverage YES -resultBundlePath $out/unit.xcresult -only-testing:ZTronScrollViewTests/TouchObserverCoreTests` (whole target at milestone end);
(2) `cd Demo && xcodebuild test -project … -scheme ZTronScrollViewDemo -enableCodeCoverage YES -resultBundlePath $out/ui.xcresult
-only-testing:ZTronScrollViewDemoUITests/UIKitObserverUITests` with `ZS_DEMO_UIKIT=1` (the tests add the arg), once with `ZS_DEMO_FORCED=1`; (3) for each bundle
`xcrun xccov view --report --json` → files whose path contains `/Sources/ZTronScrollView/Gesture/UIKit/` (fail loudly if the demo bundle lists none: the demo
scheme must gather coverage for the package target); (4) `xcrun xccov view --archive --file <path> <bundle>` per file, union of executed lines across
bundles, uncovered = executable in some bundle and 0 in all; (5) print `file:line` for every uncovered line and the per-file percentage; exit 1 unless every
file is 100 %. Through `scripts/run-filtered.sh` for the build output. **`scripts/check-uikit-scope.sh`**: `grep -rnE 'import UIKit|UIKit\.|UIViewRepresentable'
Sources Packages` must only hit `Sources/ZTronScrollView/Gesture/UIKit/`; each hit file's first non-comment line is `#if canImport(UIKit) && os(iOS)`;
`grep -rnE 'UIScrollView|UIHostingController|NSClassFromString|value\(forKey|Mirror\(' Sources Packages` empty (the MC spike lives under `Packages/ScrollArbitration/Spike`,
excluded by path). Exit 1 on any hit. Both gates: milestone end and before any commit touching the directory (S14 §5); the orchestrator runs them, no CI exists yet.

## 6. Builder split, sequencing, budget, risks

Starts after the running M6/M7/M8 sessions commit (they edit `Sources/` concurrently; this work touches `PanGestureAdapter.swift`,
`PinchGestureAdapter.swift`, `PanCoordinator.swift` init, `ZTronScrollState.swift`, `Availability/`). New directory and scripts conflict with nothing.

- **(a) core + unit tests** (1 session): `Gesture/UIKit/TouchObserverCore.swift`, `Tests/ZTronScrollViewTests/TouchObserverCoreTests.swift`,
  `Availability/ZTronCapability.swift`, `ZTronAvailability.swift`, `State/ZTronScrollState.swift` (the `let`). Exit: unit suite green on 27.0 + 17.5 both
  paths; core at 100 % in the unit bundle (`scripts/coverage-uikit.sh --unit-only`).
- **(b) shell + wiring + demo + UI tests + scripts** (1–2 sessions, after (a) is committed): `Gesture/UIKit/UIKitTouchObserver.swift`, `PanGestureAdapter.swift`,
  `PinchGestureAdapter.swift`, `PanCoordinator.swift` (init), `DemoApp.swift` (+ PanScreen toggle / cancel probe args), `UIKitObserverUITests.swift`,
  `scripts/coverage-uikit.sh`, `scripts/check-uikit-scope.sh`. Exit: both gates green on 27.0; `UIKitObserverUITests` + `ZoomUITests` + `PanUITests` green
  on 27.0 and 17.5 under the force arg (both variants); the full demo suite unchanged without the arg (27.0 55/55, 17.5 54/55).
- **(c) docs** (clerk, ½ session): parity-matrix row, design-note availability row, handoff, Orchestration row + decision, S14 §4 line.

Budget: 3–3.5 builder sessions, ≈ 0.5 M tokens (sonnet builders, one opus consult at most), plus the user's Xcode 26.x run on real iOS 15/16 (the only real verification of the shipped gate `#unavailable(iOS 17)`).

Risks, ranked: (1) `XCUIElement.pinch` may deliver one HID touch on the simulator (R3) → centroid assertion degrades to scale-only, shell lines unaffected.
(2) `didMoveToWindow` may fire with nil first and again after SwiftUI re-parents the anchor (sheet, scene) → the install is idempotent; verify with the
toggle test. (3) Overlay false positives: a SwiftUI overlay in the same hosting view over the viewport is seen as a touch-down (rect filter only);
a touch during deceleration on such an overlay catches (stops) the scroll, 18+ would not (Open question 1). (4) The demo scheme may not gather
coverage for the package target → set "gather coverage for all targets" in the scheme; the script fails loudly. (5) `touchesCancelled` not reachable by the
sheet route → defensive-call coverage, declared. (6) Swift 6: the recognizer is `@MainActor`, the core `Sendable`; `ObjectIdentifier(touch)` as id is
reused by UIKit after a touch ends — the core clears ids at end/cancel, so reuse is safe. (7) Two passive recognizers on one window (ours + ZTronPages')
each see every touch — fine by note A, re-verify on the pager screen under the force arg. (8) The real 15–16 runtime is unverifiable on this Mac.

## Open questions (for the user)

1. Overlay touches: accept the rect-only filter (a tap on a SwiftUI overlay above the viewport counts as a touch-down; it only matters while
   decelerating, where it stops the scroll), or keep `DragGesture(minimumDistance: 0)` as a hit-test confirmation for the catch at the cost of its latency?
2. Pencil and indirect/pointer touches on 15–16: observe `.direct` + `.pencil` only (proposed; pointer input is a 27+ topic, S3), or `.direct` only?
3. Keep `MagnificationGesture` attached on 15–16 for recognition only (proposed), or remove it so the pinch is observer-only?
4. `-ZTronForceAllFallbacks` on a real 15–16 device turns the observer off (keeps the pure path testable there) — agreed?
5. The gates run by the orchestrator/test-runner before commits touching the directory and at milestone end; add a git pre-commit hook or a CI job?
6. If `touchesCancelled` cannot be produced on the simulator, is the "execute the line with an empty set + core tests + your device check" scheme acceptable?

## Orchestrator resolutions (2026-10-20, user: "accetto le risposte proposte dall'architetto")
- R1 Overlay touches: rect-only filter (a touch that begins inside the viewport rect counts, overlays included); no
  `DragGesture(minimumDistance: 0)` confirmation on 15–16.
- R2 Touch types observed on 15–16: `.direct` and `.pencil`; indirect/pointer input stays a 27+ topic (S3).
- R3 `MagnificationGesture` stays attached on 15–16 for recognition only; magnification and centroid come from the observer.
- R4 `-ZTronForceAllFallbacks` turns the observer off, also on a real 15–16 device, so the pure SwiftUI path stays testable there;
  `-ZTronForceUIKitObserver` turns it on on 17+ simulators.
- R5 The two gates (`scripts/coverage-uikit.sh`, `scripts/check-uikit-scope.sh`) are run by the orchestrator / test-runner
  before any commit touching `Gesture/UIKit/` and at milestone end (S14); no pre-commit hook or CI job now (no CI exists),
  revisit when CI appears.
- R6 If `touchesCancelled` cannot be produced on the simulator: executing the override with an empty set counts for the line
  gate only, the behaviour is proven by the core tests, and the user's device check closes it; the coverage report must say so.

