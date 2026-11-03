# PICKER · Hit-view decline for wheel and date pickers (spike PICKER-s1, 2026-11-04)

Scope: Orchestration.md open items 37 (18.x), 38 (nested inner, pager page, a view that holds scroll views) and 39 (26+);
D84 (the picker absorbs the drag, as in a native `ScrollView`), D86 (the non-shared pan stays `.simultaneous`), D74 (parity
without appeal; scoped UIKit at 100 % coverage is acceptable). Builds on D31 (`Gesture/UIKit/UIKitTouchObserver.swift`), U1 C2 / C3
(`docs/progress/UIKITPAN-s1.md`) and U2's decline (`PanEvent.declined`, `NestedScrollArbiter.participantDeclined`).
Prototype: branch `claude/picker-hitview-spike`, off by default (`ZTRON_PICKER_DECLINE`). Measurements: §5.

## 1. Problem

A vertical drag that starts on a `Picker(.wheel)` or a `DatePicker(.wheel)` inside a `ZTronScrollView` turns the wheel and also
scrolls the content (y = 50 for a 60 pt drag on 18.x and 26+, 1 on 17.5; DBG-s4 Open 3). The SwiftUI pan is a
`.simultaneousGesture(DragGesture)`, so it recognizes alongside the picker's own `UIScrollView` pan. D86 measured that no other
SwiftUI attach keeps Buttons, sliders and the wheel working together, so the fix cannot live in the attach.

## 2. Mechanism

The attach stays exactly as it is (`PanGestureAdapter.swift`, D86). Two additions:

1. **Probe.** The D31 window recognizer gains a probe-only mode (`feedsCore: false`) and is installed on 17+ as well when the
   feature is on. On 15–16 it is the D31 observer itself and does both jobs. At the first finger of a sequence (no other touch of
   the event is still down) it walks `touch.view` and its superviews and asks one question: is one of them a `UIPickerView` or a
   `UIDatePicker`? It reports the answer with `PanCoordinator.touchSequenceBegan(onPicker:)`. It uses public classes only, a
   `superview` walk, no class names, no private API and no reflection. The recognizer stays passive, as in D31: it never leaves
   `.possible`, never cancels or delays touches, recognizes simultaneously with everything, and cannot prevent or be prevented.
2. **Decline.** The coordinator reads the report once, at the first drag sample of the sequence:
   - Within 45° of vertical (`abs(dy) >= abs(dx)`): the picker owns the drag. The coordinator feeds `.declined` to the session
     (U2: a caught motion settles where the catch stopped it, with no drag callbacks), tells a nested container
     (`participantDeclined`, U2) and drops every drag sample of the sequence up to its `.dragEnded`. The touch-down, the
     observer's lift and a cancel still pass, so tracking, the catch and the arbiter's sequence open and close as before.
   - Flatter: the wheel's pan fails across its axis in UIKit, so the drag stays the scroll views'. A horizontal pager, or a two-axis
     view, pans or pages from the wheel as it would natively. The 45° cone is U1 C2's cross-axis cone.

There is no viewport filter. A view's drag samples exist only for touches that SwiftUI routes to that view, so a report about a
picker elsewhere is never read, and the next sequence overwrites it. In a nested or paged topology every ZTron view under the finger
gets the same report from its own probe, so all of them decline, whichever SwiftUI pan reports first. This matches the native
result, where the wheel takes the drag and no scroll view moves.

What it leaves alone, by construction: a sequence that does not start on a picker. Buttons (ButtonDragUITests), sliders and
steppers never see a different pan, because only the report changes, and only for picker touches.

## 3. Files (prototype)

- `Gesture/UIKit/UIKitTouchObserver.swift`: `feedsCore`, `reportsPickers`, the report in `touchesBegan`, `beginsSequence`,
  `isInPicker`. In DEBUG it also records the class chain it saw (`picker.chain`), as a measurement only: names are observed,
  never matched.
- `Gesture/PanCoordinator.swift`: `touchSequenceBegan(onPicker:)`, `pickerAbsorbs(_:)` at the top of `handle(_:)`.
- `Gesture/PanGestureAdapter.swift`: the `PickerDecline` gate (compile-time `ZTRON_PICKER_DECLINE`) and the anchor attach,
  `enabled: uikit || PickerDecline.isOn`, `feedsCore: uikit`. Both inputs are static per view, so the content keeps its identity.
- Tests: `PickerDeclineTests` (coordinator, nested arbiter, pager, caught motion, cone, latch), `PickerProbeRuleTests` (the rule
  on real `UIPickerView` / `UIDatePicker` / plain views, probe-only feeds nothing). Demo: `-ZTronControlsWheels`,
  `-ZTronControlsTopology nested|pager`, probe counters in `Info`. UI: `UIKitControlsUITests.testWheels*`;
  `scripts/test-demo-ui.sh --picker` builds with the flag and makes the required fixes strict.

## 4. What it would take to ship (needs the user)

- **SPEC S2 / S16 text.** D31's UIKit exception covers a passive observer on 15–16 only. This puts the same passive recognizer
  on every OS, in every `ZTronScrollView`, and widens what it looks at to the hit view's class. That is a SPEC S2 amendment and a
  `ZTronCapability.uikitTouchObserver` doc change. Not written here (ask first).
- **Default on.** Replace the compile-time gate with "always on". There is no API change, and the demo flag goes away.
- **Coverage.** `scripts/coverage-uikit.sh` lists `PickerProbeRuleTests`. The report lines in `touchesBegan` are covered only by a
  `--picker` UI lane (`--dd`). The gate run is a builder-session step.
- **15–16.** The report shares the D31 recognizer there. Verify on the M1 lane.

## 5. Measurements

TBD (filled from the lanes).

## 6. Open

TBD.
