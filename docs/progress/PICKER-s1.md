# PICKER-s1 handoff · 2026-11-04 · Opus 5.5 · spike (open items 37, 38, 39)
Status: done (spike). The prototype is on `claude/picker-hitview-spike` (base `claude/integ-wave-2-b2` 88548e7), off by default. It
changes no default path and needs the user's OK to ship (Decisions).
Design + measurements: `docs/design/PICKER-decline.md` (§2 mechanism, §5 per-OS numbers, §6 open).

Changed:
- `Sources/ZTronScrollView/Gesture/UIKit/UIKitTouchObserver.swift`: the D31 recognizer gains `feedsCore` (false = probe-only on
  17+) and `reportsPickers`. At a sequence's first finger it calls `touchSequenceBegan(onPicker:)`. `isInPicker` / `isWheel` match a
  `UIPickerView`, or a `UIDatePicker` in `.wheels` style, through a superview walk with public classes only. `beginsSequence` is new.
  The DEBUG chain note is a measurement only.
- `Sources/ZTronScrollView/Gesture/PanCoordinator.swift`: `touchSequenceBegan(onPicker:)` and `pickerAbsorbs(_:)`. The first drag
  sample within 45° of vertical becomes `.declined` (U2's settle + `participantDeclined`), and the sequence's drag samples are
  dropped up to `.dragEnded`.
- `Sources/ZTronScrollView/Gesture/PanGestureAdapter.swift`: `PickerDecline` (compile-time `ZTRON_PICKER_DECLINE`), and the anchor
  attach `enabled: uikit || PickerDecline.isOn`, `feedsCore: uikit`. The attach modes are untouched (D86).
- `Tests/ZTronScrollViewTests/PickerDeclineTests.swift` (new): `PickerDeclineTests` (10) and `PickerProbeRuleTests` (6).
- Demo `UIKitControlsScreen.swift`:
  - `-ZTronControlsWheels` (date wheel, `Picker(.wheel)`, slider, fillers);
  - `-ZTronControlsTopology nested|pager` (ZTron or native);
  - `Info` adds `ox` / `oy` and the probe counters; `pickerChain`;
  - `NativeScrollProbe`, which reads native offsets from UIKit (demo only).
- `UIKitControlsUITests.swift`:
  - `ZS_PICKER` makes the required fixes strict;
  - 11 `testWheels*` tests (wheels in 3 topologies, slider, readout sanity) and `testCompactDatePickerDragMeasure`.
- `scripts/test-demo-ui.sh`: `--picker` (builds with the flag, sets `ZS_PICKER=1`). `scripts/coverage-uikit.sh` lists
  `PickerProbeRuleTests`.

Decisions (for the user; nothing applied):
- (a) **Ship the decline as the default** on every OS. It needs a SPEC S2 amendment: D31's passive window recognizer on 17+ too,
  reading the hit view's class. It also needs the `ZTronCapability.uikitTouchObserver` doc changed. Recommended: it closes items 37,
  38 and 39 on every OS measured, with no Button or slider cost (D74), and without U3.
- (b) Keep waiting for U3 + a picker pass on the UIKit pan. U3 covers only N and S (D60), so items 37–39 on a plain screen would
  stay open.
- Spike choices: wheels only (a compact / graphical `DatePicker` drag scrolls natively), a static 45° cone (native pages from a flat
  swipe on the wheel), and no viewport filter (§2).

Open:
1. User: (a) or (b), and the SPEC S2 / S16 text (not written: ask first).
2. Coverage gate with a `--picker` lane (`scripts/coverage-uikit.sh --dd`).
3. 15–16 (the report shares the D31 observer there): the M1 lane, or `--uikit --picker` here first.
4. Not measured: a wheel touch that catches a deceleration; a pinch whose first finger is on a wheel; a wheel in a sheet on 18.x
   (D46); a wheel in N; diagonal swipes at 30–60°.
5. Harness: the old native offset reader (a preference) stayed at 0 while native scrolled, so DBG-s4's native "y = 0" baselines
   (Stepper, segmented, Menu, ColorPicker) proved nothing. Re-run `UIKitControlsUITests --native` in full with `NativeScrollProbe`.
6. Today's default on 18.5 / 26.5 / 27.0: a `Picker(.wheel)` drag in a `ZTronScrollView` does not change the selection at all
   (worse than item 37's text says). Add it to items 37 / 39 when they are next edited.
7. `testCompactDatePickerDragMeasure` and `testWheelsPagerHorizontalSwipeOnTheWheelMeasure` are measurements. Turn them into parity
   assertions when the feature lands (values in the design §5).

Next: 1. the user picks (a) or (b); 2. with (a), a builder session: flag → default, SPEC S2 amendment text (after the user's OK),
coverage gate, the full demo UI suite on 17.5 / 18.5 / 26.5 / 27.0 + `--forced` + `--uikit`, and `UIKitControlsUITests --native`;
3. the 15–16 run on the M1 lane.

Tests (private clones, one UI lane at a time under `ztron-ui-lane.lock`):
- unit: the full suite on 27.0, 813/813 (flag off, default path unchanged); the touched suites on 17.5 and 27.0 green;
  `check-uikit-scope.sh` clean;
- `--picker`, every OS (17.5, 18.5, 26.5, 27.0): `UIKitControlsUITests` 21/21, `ButtonDragUITests` 3/3, `PanUITests` 20/20, 0 feedback-loop
  warnings;
- `--native` wheels set (13 tests): 13/13 on all four;
- no-flag wheels set: 27.0 / 18.5 / 26.5 10/13 (the 3 `Picker(.wheel)` tests fail: the wheel does not turn), 17.5 13/13 (y = 1, the
  non-strict expected failures).
Raw logs: the shared notes folder `local_40aafa88-…/PICKER-s1/`.
Usage: not measured.
