# DBG-s6 handoff · 2026-10-21 · Sonnet 5.5 (Debugger) — SwiftUI `scrollDisabled` did nothing to a `ZTronScrollView`
Status: done — fixed at the root, regression tests red before / green after on 27.0 and 17.5; iOS 15/16 runtimes do not run on this Mac (not measured).
Changed:
- `Sources/ZTronScrollView/Modifiers/ScrollEnvironment.swift` — `NativeScrollEnabledReader` is a leaf `View` (was a `ViewModifier` returning its content).
- `Sources/ZTronScrollView/Gesture/PanGestureAdapter.swift` — `NativeEnabledBridge` attaches it with `.background(…)` (one line).
- `Tests/ZTronScrollViewTests/NativeScrollEnabledTests.swift` (new, 3 tests): the real bridge hosted in a window, flipped at run time.
- `Demo/ZTronScrollViewDemo/ScrollDisabledScreen.swift` (new, `-ZTronScreen scrollDisabled`, `DemoApp.swift` one case) + `Demo/ZTronScrollViewDemoUITests/ScrollDisabledUITests.swift` (new, 12 tests).
- Docs: this note, Orchestration (open item 10, D38, log), `docs/parity-matrix.md` (new `scrollDisabled` row), `docs/design/SHEET-spike.md` §4 V1/V7 and §6.
Decisions:
- D38. Root cause: `NativeScrollEnabledReader.body` never ran. Measured on 27.0 with a body counter beside a leaf `View` doing the same read: modifier body 0, leaf 1, and the leaf followed every flip
  (`native.enabled` 1 → 0 with `.scrollDisabled(true)`). Before the fix, inside the content `\.isScrollEnabled` read `false` (so SwiftUI does write and expose it, to the descendants of the modifier, on 27.0 and 17.5), while
  `PanCoordinator.nativeScrollEnabled` stayed `true`: the pan scrolled 240 pt (250 minus its 10 pt slack) outside a sheet, in a sheet, at medium, with the modifier on the view or on a parent, on every path. It is not
  sheet-related and not OS-related; `ztronScrollDisabled` worked only because it also writes `\.ztronScrollIsEnabled`, which the adapter reads in its own body. The reader sits above the content, so a `scrollDisabled` placed on
  a descendant does not disable the outer view and one placed on an ancestor does, as natively. The pan already read the flag per event (`PanCoordinator.peekEnvironment`), so nothing else changed.
- Why a leaf `View`: nothing reads the output of a bare `_ViewModifier_Content`, so the body is presumably never demanded (an inference; the measurement is the counter). Other modifiers in the library return `content.background/onAppear/…` and run. Rule: an
  environment reader is a leaf `View` in a background (as `TargetEnvironmentCapture`, `NativeIndicatorVisibilityReader`). Only the leaf re-evaluates on a change; content bodies are not touched.
- Behavior change for apps (hence D38): `.scrollDisabled(true)` on a `ZTronScrollView` or any ancestor now disables it, as SPEC S8-1 always said.
- The "9 pt residual offset" (SHEET-s1 V6b/V8b) is not the pan's slack and not a library fault: the harness readout (`Text(info)`, up to 3 lines at 9 pt) sits above the scroller and grew from nothing to three lines at the first snapshot,
  shrinking the viewport by 18 pt; the offset follows by half of it because the visible centre is kept (S7). Evidence: the same harness with a fixed-height readout reads 0 after the same drags (`scrollDisabled`, `ztronScrollDisabled`, in a
  sheet), and `testDisabledViewFollowsItsViewportNotTheFinger` (readout allowed to grow, `-ZTronSDGrow`) reads offset = (height before − after) / 2 within 1.5 pt with `didScroll` 0 for the drag and 1 for the resize.
  A disabled view must not move from a drag; it still follows its viewport (UIScrollView keeps its offset on a bounds change, ours keeps the centre by the S7 non-negotiable). No change.
Open:
- The disabled view's SwiftUI drag is still attached and recognized (`pan.ev.drag` 57 on a 250 pt drag, the session ignores every event): switching the effect off does not free a sheet below (SHEET-spike V6/V8). That is `ztronScrollYieldsToSheet` (D36), unchanged.
- A flip to disabled while a finger is down is the `ztronScrollDisabled` path (the session stops following, no momentum); not measured against UIKit's cancel.
- iOS 15: `scrollDisabled` and `isScrollEnabled` do not exist there; `ztronScrollDisabled` is the spelling (our key only). iOS 16: the same code path as 17.5 (no capability gate); not measured.
- Pre-existing reds, not from this change (both reproduced at HEAD f8ed310 without it): `PanUITests.testControlsUsable` on 17.5 ("Neither element nor any descendant has keyboard focus": the `PositionTicket` regression, DBG-s2's fix e8c5674 is on
  `claude/determined-lederberg-7907ea`, not in main); `ProofUITests.testNoClockTicksAtRest` on a fresh 27.0 clone (`clock.tick` 2, the known device artifact: clone a warmed device).
Next:
1. Merge `claude/determined-lederberg-7907ea` (DBG-s2) so `testControlsUsable` is green on 17.5 again.
2. `ztronScrollYieldsToSheet(_:)` (D36 builder session) can rely on `scrollDisabled` working; its tests should not use `scrollDisabled` as a stand-in for the mask.
3. Review other `ViewModifier`s for the same trap when adding readers (none found today: `grep "return content$"` leaves only bodies with real modifiers).
Tests:
- `scripts/test.sh -only-testing:ZTronScrollViewTests` (clean worktree at f8ed310 + the change): red before (`NativeScrollEnabledTests`, 3 issues on 27.0), **595 tests in 53 suites green on 27.0 and 17.5** after.
- `scripts/test-demo-ui.sh … -only-testing:ZTronScrollViewDemoUITests/ScrollDisabledUITests`: 27.0 preferred 12/12, 27.0 `--forced` 10/10 + 2 skipped by design (the native baseline ignores the switches), 17.5 preferred 12/12,
  17.5 `--forced` 10/10 + 2 skipped, 17.5 `--forced --uikit` 10/10 + 2 skipped (its first run lost one test to a launch failure, "Failed to terminate", at host load 700; the re-run is green). Before the fix the `scrollDisabled` cases (on the view, on a parent, in a sheet, at medium) read offset 240–260 (characterization run, 27.0).
- `ProofUITests` + `PanUITests` + `NestedPagerUITests` (render counters, nested `ztronScrollDisabled`): 26 executed on each of 27.0 and 17.5 preferred; the only reds are the two pre-existing ones above (each reproduced at HEAD without the patch).
- Private simulator clones (iPhone 18 Pro 27.0, iPhone 15 Pro 17.5), own derived data per lane, clean worktrees; clones and worktrees removed at the end.
Usage: not measured · host load average 500–1000 during the runs (other sessions).
