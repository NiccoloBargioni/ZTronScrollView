# PICKER · Hit-view decline for wheel and date pickers (spike PICKER-s1, 2026-11-04)

Scope: Orchestration.md open items 37 (18.x), 38 (nested inner, pager page, a view that holds scroll views) and 39 (26+);
D84 (the picker absorbs the drag, as in a native `ScrollView`), D86 (the non-shared pan stays `.simultaneous`), D74 (parity
without appeal; scoped UIKit at 100 % coverage is acceptable). Builds on D31 (`Gesture/UIKit/UIKitTouchObserver.swift`), U1 C2 / C3
(`docs/progress/UIKITPAN-s1.md`) and U2's decline (`PanEvent.declined`, `NestedScrollArbiter.participantDeclined`).
Prototype: branch `claude/picker-hitview-spike`. Since PICKER-s2 (2026-11-07, the user's call) it is an opt-in modifier,
`View.ztronScrollPickersAbsorbDrags(_:)`, off by default (§4); SPEC amendment drafted 2026-11-08 (D88, §4). Measurements: §5;
regression with the modifier on: §5.1.

## 1. Problem

A vertical drag that starts on a `Picker(.wheel)` or a `DatePicker(.wheel)` inside a `ZTronScrollView` turns the wheel and also
scrolls the content (y = 50 for a 60 pt drag on 18.x and 26+, 1 on 17.5; DBG-s4 Open 3). The SwiftUI pan is a
`.simultaneousGesture(DragGesture)`, so it recognizes alongside the picker's own `UIScrollView` pan. D86 measured that no other
SwiftUI attach keeps Buttons, sliders and the wheel working together, so the fix cannot live in the attach.

## 2. Mechanism

The attach stays exactly as it is (`PanGestureAdapter.swift`, D86). Two additions:

1. **Probe.** The D31 window recognizer gains a probe-only mode (`feedsCore: false`) and is installed on 17+ as well while
   `ztronScrollPickersAbsorbDrags(true)` is in the view's environment, by the outermost `ZTronScrollView` of a tree only: the
   views nested in it join its `PickerProbeHub` and hear its reports (§5.1: an anchor inside a nested view breaks its drags). On 15–16 it is the D31 observer itself and does both jobs. At the first finger of a sequence (no other touch of
   the event is still down) it walks `touch.view` and its superviews and asks one question: is one of them a wheel, that is a
   `UIPickerView`, or a `UIDatePicker` whose `datePickerStyle == .wheels`? Compact and graphical date pickers are not wheels: a
   vertical drag that starts on them scrolls natively (§5). It reports the answer with
   `PanCoordinator.touchSequenceBegan(onPicker:)`. It uses public classes only, a `superview` walk, no class names, no private API and no reflection. The recognizer stays passive, as in D31: it never leaves
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

## 3. Files

- `Gesture/UIKit/UIKitTouchObserver.swift`: `feedsCore`, `reportsPickers`, the report in `touchesBegan`, `beginsSequence`,
  `isInPicker`, `isWheel`. In DEBUG it also records the class chain it saw (`picker.chain`), as a measurement only: names are observed,
  never matched.
- `Modifiers/ScrollEnvironment.swift`: `View.ztronScrollPickersAbsorbDrags(_ absorbs: Bool = true)`, environment-backed and
  propagating like `ztronScrollYieldsToSheet`; the key defaults to `false`.
- `Gesture/PanCoordinator.swift`: `pickersAbsorbDrags` (the adapter's mirror; a report is read only while it is true),
  `pickerProbe` (its hub), `touchSequenceBegan(onPicker:)`, `pickerAbsorbs(_:)` at the top of `handle(_:)`.
- `Gesture/PickerProbeHub.swift`: the hub (owner + weak members, `report(onPicker:)`) and its environment key. `ZTronScrollView`
  sets it on its content, `outer ?? own`, constant per identity (like `scrollArbiter`).
- `Gesture/PanGestureAdapter.swift`: reads the environment value and the outer hub. `reports = absorbs && (uikit || no outer
  hub)`; the anchor attaches with `enabled: uikit || reports`, `feedsCore: uikit`, `reportsPickers: reports`; a nested view on
  17+ joins the outer hub instead. Off, nothing is installed on 17+ (the shipped path); flipping it adds or removes the anchor
  there, and on 15–16 `UIKitTouchObserverAnchor.updateUIView` updates the D31 recognizer in place.
- Tests: `PickerDeclineTests` (coordinator, nested arbiter, pager, caught motion, cone, latch, a report while off),
  `PickerProbeRuleTests` (the rule on real `UIPickerView`, wheels / compact / inline `UIDatePicker` and plain views; probe-only
  feeds nothing), `PickerAbsorbModifierTests` (the environment value; hosted: 17+ adds and removes a probe-only recognizer,
  the forced 15–16 shape keeps the D31 one and mirrors the flag; a nested pair installs one probe on 17+, two D31 recognizers in
  the 15–16 shape; a nested adapter joins the outer hub), hub tests in `PickerDeclineTests`. Demo:
  `-ZTronControlsWheels`, `-ZTronControlsTopology nested|pager`, probe counters in `Info`, `NativeScrollProbe` (native offsets
  from UIKit, §5). UI: `UIKitControlsUITests.testWheels*`, `testCompactDatePickerDragMeasure`;
  `scripts/test-demo-ui.sh --picker` builds the demo with `ZTRON_DEMO_PICKERS_ABSORB`, which applies the modifier at the app
  root (`DemoApp.swift`), so every screen and every demo UI suite runs with it on, and makes the required fixes strict.

## 4. What shipping takes (needs the user)

- **SPEC S2 / S16 text, opt-in or default.** D31's UIKit exception covers a passive observer on 15–16 only. With the modifier on,
  the same passive recognizer runs on 17+ too and looks at the hit view's class. That needs a SPEC S2 amendment and a
  `ZTronCapability.uikitTouchObserver` doc change even while the modifier is opt-in, and SPEC S2's API list gains
  `ztronScrollPickersAbsorbDrags`. **Drafted 2026-11-08 (user: "Yes, draft it"; D88), for the user's review:** SPEC S2 (a second
  amendment under the D31 one: probe-only on 17+, one per tree, the wheel question, passivity, same gates), S3 (a row), S11 (the API
  line), S12 "Wheel and date pickers" (default, rule, cone, what it leaves alone, placement, default-on as a later call) and S14 (an
  acceptance bullet); the `ZTronCapability.uikitTouchObserver` and modifier doc comments. S16 is unchanged (ScrollArbitration is not
  touched; `participantDeclined` is library-internal). CLAUDE.md's non-negotiables are not changed (ask).
- **Default on (later, if wanted).** Flip the key's `defaultValue` to `true`; the modifier stays as the way out.
- **Coverage.** `scripts/coverage-uikit.sh` lists `PickerProbeRuleTests` and `PickerAbsorbModifierTests` (§5.1 has the gate run).
- **15–16.** The report shares the D31 recognizer there. Verify on the M1 lane.

## 5. Measurements (2026-11-04, private clones, one lane at a time under `ztron-ui-lane.lock`)

Lanes: **p** = `--picker` (flag on), **n** = `--picker --native` (SwiftUI `ScrollView`, the flag is irrelevant there), **b** = no flag
(today's default path). Devices: 17.5 iPhone 15 Pro, 18.5 iPhone 16 Pro, 26.5 iPhone 17 Pro, 27.0 iPhone 18 Pro (clones). Commits:
27.0 `ButtonDragUITests` / `PanUITests` at e1ae28a (the later commits narrow the rule and touch no Button or Pan path); everything else
at c3135d4.

**Q1, backing.** On every OS measured, the hit view of a wheel drag sits under a `UIPickerView` subclass. The probe's chain is the same
on 17.5, 18.5, 26.5 and 27.0 (class names observed, not matched):
- `DatePicker(.wheel)`: `UIPickerTableViewWrapperCell > UIPickerTableView > UIView > UIPickerColumnView > UIView > _UIDatePickerView`.
  `_UIDatePickerView` is a `UIPickerView`; the walk stops there before reaching `UIDatePicker`.
- `Picker(.wheel)`: the same chain, ending in `UIKitPickerView` (SwiftUI's `UIPickerView`).
- A compact `DatePicker`'s calendar popover is also under a `UIDatePicker` (`… > UICalendarView > _UIDatePickerCalendarView >
  UIDatePicker`, 27.0). That is why the rule takes a `UIDatePicker` only in `.wheels` style. Native scrolls from a compact picker (below).

**Q2, the 17.5 `touch.view` trap.** It does not matter here. U1's trap is that SwiftUI content has a drawing view as its hit view. A
wheel's hit view is the picker's own `UIPickerTableViewWrapperCell` on 17.5 as well, and its superview chain reaches the picker. The
probe needs no anchor ancestry and no controller-root rule, because it never asks where the touch is, only what was hit.

**Q3, the suites with the flag.** Every lane is green.

| OS | `UIKitControlsUITests` | `ButtonDragUITests` | `PanUITests` (slider, stepper, buttons) |
|---|---|---|---|
| 17.5 | 21/21 | 3/3 | 20/20 |
| 18.5 | 21/21 | 3/3 | 20/20 |
| 26.5 | 21/21 | 3/3 | 20/20 |
| 27.0 | 21/21 | 3/3 | 20/20 |

- In these lanes the wheel tests' required fixes are asserted, not expected failures. That covers `testWheelDatePickerTurnsTheMonthWheel`
  (items 37 / 39) and `testWheels{Plain,Nested,Pager}{DatePicker,Picker}` (38 for nested and pager).
- 0 UIKit feedback-loop warnings.
- The segmented-drag limitation (DBG-s4 Open 2) is still the one expected failure, and it is unchanged.

**Offsets after a 60 pt wheel drag up** (`y` = the controls' view, `ox` / `oy` = the outer; nested = vertical-in-vertical, pager =
page 0 of a horizontal pager):

| | 17.5 | 18.5 | 26.5 | 27.0 |
|---|---|---|---|---|
| native, every topology, both wheels | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| ZTron + flag, every topology, both wheels | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| ZTron today, date wheel | y = 1 | y = 50 | y = 50 | y = 50 |
| ZTron today, `Picker(.wheel)` | y = 1, turns | **does not turn** | **does not turn** | **does not turn** |

On 18.5 / 26.5 / 27.0 today, a `Picker(.wheel)` drag in a `ZTronScrollView` does not change the selection at all. The content follows
the finger, so the wheel sees about 10 pt of the 60. The 150 pt wheel then snaps back. This is the same in all three topologies. With the
flag the wheel turns.

**Things the decline must leave alone**, measured on all four OSes (both lanes agree):
- A drag that starts on a compact `DatePicker` scrolls: native y = 105 (27.0) / 110, ZTron y = 110. The date does not change.
- A horizontal swipe that starts on page 0's wheel pages: native ox = 376–386, ZTron + flag ox = 376–385. In both the wheel stays put
  (pick = 0). This is what the 45° cone is for.
- A slider drag in the plain and nested topologies moves the slider, with y = 0 and oy = 0.
- Sanity of the readouts: a filler drag gives y = 240 and a filler swipe on the pager gives ox ≈ 380, native and ZTron alike.

**Harness finding.** The native lane's offset reader was a `GeometryReader` preference inside the `ScrollView`. On 27.0 it stayed at 0
while the view scrolled (filler drag 0, pager swipe 0). DBG-s4's native "y = 0" checks therefore proved nothing. The demo now reads
native offsets from UIKit (`NativeScrollProbe`, demo only), and the sanity tests above pin it.

### 5.1 Regression with the modifier on (PICKER-s2, 2026-11-07)

`--picker` applies `ztronScrollPickersAbsorbDrags()` at the demo's root, so every screen of every suite runs with the probe.
Private clones, own derived data, one lane at a time under `ztron-ui-lane.lock`. Host load swung between 6 and 680 during the day.

**Full suites before the nested fix** (f3897bc; passed / failed / skipped):

| Lane | with the modifier | INTEG-s2 base (88548e7, no modifier) |
|---|---|---|
| 27.0, all 252 | 219 / 1 / 32 | 208 / 0 / 32 of 240 |
| 17.5, all 252 | 217 / 3 / 32 | 207 / 1 / 32 of 240 |

The 12 extra tests are PICKER-s1's wheel tests. The failures:
- `MixedTopologyUITests`, a `ZTronScrollView` page holding ZTron views (27.0 and 17.5). A horizontal drag on the carousel moved
  nothing (carousel x = 0; 70 on 27.0 and 58 on 17.5 without the modifier). On 17.5 a vertical drag on the inner list moved the page
  (page 50, list 1) instead of the list. The same build without `--picker`: 7/7, carousel x = 70.
- 17.5 `HeaderUITests.testProfileCollapsesAndSnapsImmediately`: "Lost connection to the application". The demo crashed inside
  XCTest's own logging (`__LIBTRACE_CLIENT_QUARANTINED_DUE_TO_HIGH_LOGGING_VOLUME__` under `-[XCElementSnapshot identifier]`), the
  same signature as a 2026-11-03 crash from before this work: a harness crash, not the probe.

**Which part breaks the nested view** (the three ZTron-page cases; DEBUG launch arguments in a scratch worktree, not committed):

| Variant | 27.0 carousel x | 17.5 carousel x / list y |
|---|---|---|
| modifier on both levels | 0 | 0 / 1 (page 50) |
| modifier off | 70 | 58 / 50 |
| outer page only | 70 | 58 / 50 |
| inner views only | 0 | 0 / 1 (page 50) |
| both levels, recognizer never added to the window | 0 | 0 / 1 (page 50) |

The cause is the probe's anchor, a zero-size `UIViewRepresentable` in the viewport's background, inside a nested ZTron view. The
window recognizer is not the cause, and neither is the coordinator, which does nothing without a picker report. Why the anchor
breaks the inner view's drags is not known. INTEG-s2's 27.0 `--uikit` lane, with the D31 anchor in every view, passed these cases,
so it also takes the 17+ gesture set.

**Fix** (55abc27): on 17+ only the outermost `ZTronScrollView` installs the probe, and nested views join its hub (§2, §3). 15–16 keep
one D31 recognizer per view. A consequence: a nested view with the modifier inside an outer view without it gets no reports, so the
modifier goes around the outermost scroll view.

**After the fix** (55abc27):

| Lane | passed / failed / skipped | Compared with |
|---|---|---|
| 27.0 `MixedTopology`, `NestedPager`, `UIKitControls`, `Pager` | 42 / 0 / 0 | carousel x = 70, list 50, as without the modifier |
| 17.5 the same + `Header` | 51 / 0 / 0 | carousel x = 58, list 50; the Header crash did not recur |
| 18.5 INTEG-s2's targeted set (Sheet, ScrollDisabled, MixedTopology, UIKitControls, NestedPager, Pan, Refresh, ButtonDrag) | 150 / 5 / 0 | base 138 / 5 / 0: the same `SheetUITests` Y1–Y5 (open item 10, D46; Y1 165 ≠ 0, Y2 60 ≠ 69, Y3 0 ≠ 1, Y4 165 ≠ 0, Y5 0 ≠ 1) |
| 26.5 the same + ContentOverlay | 159 / 0 / 0 | base 147 / 0 / 0 |
| 27.0 `--uikit --picker` (the 15–16 shape: D31 recognizer in every view, reporting), all 252 | 199 / 0 / 53 | base `--uikit` 188 / 0 / 52 of 240; every `testWheels*` and ZTron-page case passed |

Unit: 27.0 `ZTronScrollViewTests` 822 / 822 (0 feedback-loop warnings); 17.5 the touched suites 33 / 33. Coverage gate:
`scripts/coverage-uikit.sh` PASS, 100 % lines in every `Gesture/UIKit` file (unit bundle of the gate's suites + 27.0
`UIKitObserverUITests` preferred and `--forced`). The wheel rule (`isWheel`) is covered by the unit run only (`PickerProbeRuleTests`).

The non-nested results of the pre-fix full suites carry over: the fix changes only what a nested view installs.

## 6. Open

1. **User: review the SPEC text** drafted 2026-11-08 (D88, §4). Turning it on by default is a later, separate call.
2. **15–16.** There the report rides on the D31 observer itself (`feedsCore: true`). The 15–16 shape on 27.0 (`--uikit --picker`)
   is green (§5.1); real 15.0 / 16.0 runtimes (M1 lane) are still unmeasured.
3. **Not measured:**
   - a touch on a wheel that catches a decelerating view (ZTron: the catch stops it and settles, with no drag; native is unknown);
   - a pinch whose first finger is on a wheel (the pan's drag samples are dropped; the pinch is unchanged);
   - a wheel in a sheet on 18.x (D46 sheet drag sharing);
   - a wheel in a ZTron inside a native `ScrollView` (N).
4. **The cone is static.** UIKit's cross-axis boundary depends on speed (U1 C2). The 45° rule matched native in the pager swipe above,
   which was a flat fast swipe. Diagonal swipes at 30–60° are not measured.
5. **Other UIKit scrollers** (a `TextEditor`, a `Map`, a web view) under a ZTron drag behave like the wheel did. A general rule would
   name `UIScrollView`, which `scripts/check-uikit-scope.sh` forbids. Out of scope here.
6. **DBG-s4's other native baselines** (Stepper, segmented, Menu, ColorPicker) ran with the broken reader. Re-run the full
   `UIKitControlsUITests --native` lane with `NativeScrollProbe`.
7. Two tests are still measurements, not assertions: `testCompactDatePickerDragMeasure` and
   `testWheelsPagerHorizontalSwipeOnTheWheelMeasure`. Their values are above; turn them into parity assertions when the feature lands.
8. **The nested anchor (PICKER-s2).** Why a zero-size `UIViewRepresentable` in a nested ZTron view's background breaks that view's
   drags on the 17+ gesture set is unexplained (§5.1). A user's own `UIViewRepresentable` in the same place may do the same; untested.
9. **Modifier placement.** With the modifier on an inner view only, under an outer `ZTronScrollView` without it, the inner view joins
   a hub with no probe and hears nothing. The SPEC draft documents "at or above the outermost scroll view" (S12); letting the outer
   install the probe when a member asks for it remains an option.
