# PICKER-s2 handoff · 2026-11-07 · Opus 5.5 · modifier + regression run (open items 37, 38, 39)
Status: done. The picker decline is an opt-in public modifier, `View.ztronScrollPickersAbsorbDrags(_:)`, default off, on
`claude/picker-hitview-spike` (base `claude/integ-wave-2-b2` 88548e7). The demo UI suites ran with it on across the whole app. One
regression showed up (nested ZTron views), was found and fixed. Results: `docs/design/PICKER-decline.md` §5.1.

Changed:
- `Sources/ZTronScrollView/Modifiers/ScrollEnvironment.swift`: `ztronScrollPickersAbsorbDrags(_ absorbs: Bool = true)`,
  environment-backed and propagating (like `ztronScrollYieldsToSheet`), key default `false`. Replaces PICKER-s1's compile-time
  `ZTRON_PICKER_DECLINE`.
- `Sources/ZTronScrollView/Gesture/PanGestureAdapter.swift`: reads the value and the outer probe hub. On 17+ only the outermost
  view installs the probe-only window recognizer; a nested view joins the outer hub. Off, nothing is installed on 17+.
- `Sources/ZTronScrollView/Gesture/PickerProbeHub.swift` (new): owner + weak members, `report(onPicker:)`, environment key.
  `ZTronScrollView.swift` sets it on its content (`outer ?? own`, constant per identity).
- `Sources/ZTronScrollView/Gesture/PanCoordinator.swift`: `pickersAbsorbDrags` (a report is read only while true), `pickerProbe`.
- `Sources/ZTronScrollView/Gesture/UIKit/UIKitTouchObserver.swift`: reports to the hub; `reportsPickers` is mutable and
  `updateUIView` mirrors it (15–16, where the D31 recognizer stays while the modifier flips); the anchor takes `feedsCore` /
  `reportsPickers` without defaults (coverage).
- Tests: `PickerDeclineTests` (+ a report while off, hub owner/members, a member that went away), `PickerAbsorbModifierTests`
  (new: environment value; 17+ adds and removes a probe-only recognizer; forced 15–16 shape mirrors the flag; a nested adapter
  joins the outer hub; nested `ZTronScrollView`s install one probe on 17+, two D31 recognizers in the 15–16 shape).
- Demo: `DemoApp.swift` applies the modifier at the root when built with `ZTRON_DEMO_PICKERS_ABSORB`;
  `scripts/test-demo-ui.sh --picker` now passes that flag. `scripts/coverage-uikit.sh` lists `PickerAbsorbModifierTests`.
- Docs: `docs/design/PICKER-decline.md` (§2, §3, §4 rewritten for the modifier; §5.1 regression; §6), this handoff.

Decisions:
- Opt-in modifier, default off (user, 2026-11-07): "we gate the UIKit recognizer behind a view modifier defaults as off, we test it on".
- One probe per tree on 17+: a probe anchor inside a nested ZTron view broke that view's drags on 17.5 and 27.0. Measured per
  level (§5.1): outer-only passes, inner-only fails, and the anchor without its window recognizer still fails. Every probe on a
  window sees the same touches, so one per tree loses nothing.

Open:
1. SPEC S2 / S16 text is not written. Even opt-in, the modifier puts a passive UIKit recognizer on 17+ and adds a public API
   (design §4). Ask the user first.
2. Why a zero-size `UIViewRepresentable` in a nested ZTron view's background breaks its drags on the 17+ gesture set (not on the
   D31 `--uikit` path) is unexplained. Any user `UIViewRepresentable` in that place might do the same; not tested.
3. A nested view with the modifier inside an outer view without it gets no reports (document: modifier around the outermost view).
4. Pre-existing on 17.5, not from this work: `SheetYieldTests.flippingTheFlagCostsTheContentNothingBeyondAnyEnvironmentKey` fails
   alone and in its suite on base 92d41b5 as on this branch (flag 6 / 2 / 1 vs unrelated key 4 / 0 / 0 content bodies). It passed
   in INTEG-s2's full 17.5 run (a fresh-process / ordering effect, D43-like).
5. Harness: a demo crash inside XCTest's logging quarantine (17.5 `HeaderUITests`), same signature as 2026-11-03.
6. 15–16 on real runtimes (M1 lane) still unmeasured; `--uikit --picker` on 27.0 is the stand-in (§5.1).
7. PICKER-s1's open 3–7 stand (design §6).

Next:
1. User: write the SPEC S2 amendment for the opt-in modifier (or leave it a spike).
2. If kept: merge `claude/picker-hitview-spike` into the integration branch; mention the modifier in the README / docs.
3. M1 lane: `UIKitControlsUITests` and `MixedTopologyUITests` with `--picker` on 15.0 / 16.0.

Tests (private clones pk2-*, own derived data, demo UI one lane at a time under `ztron-ui-lane.lock`; passed / failed / skipped):
- Unit, fix 55abc27: 27.0 `ZTronScrollViewTests` 822/822, 0 feedback-loop warnings; 17.5 the touched suites (`PickerDecline`,
  `PickerAbsorbModifier`, `PickerProbeRule`, `UIKitObserverShell`, `UIKitObserverGating`) 33/33. `scripts/check-uikit-scope.sh` clean.
- Demo UI with the modifier on app-wide (`--picker`), before the fix (f3897bc): 27.0 all 219/1/32, 17.5 all 217/3/32 (nested
  MixedTopology ×1 / ×2, a 17.5 XCTest logging crash in Header). A/B 27.0 without `--picker`: MixedTopology 7/0.
- Per-level experiment (scratch worktree, not committed): design §5.1 table.
- After the fix (55abc27): 27.0 MixedTopology + NestedPager + UIKitControls + Pager 42/0/0; 17.5 the same + Header 51/0/0; 18.5
  targeted 150/5/0 (the base's Sheet Y1–Y5, open item 10); 26.5 targeted + ContentOverlay 159/0/0; 27.0 `--uikit --picker` all
  199/0/53 (base 188/0/52).
- Coverage gate (`scripts/coverage-uikit.sh`, `Gesture/UIKit` 100 %): <!-- PICKER-s2 COVERAGE -->
- Logs: shared notes folder `PICKER-s2/`.
Usage: not measured.
