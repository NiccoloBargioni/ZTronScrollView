# M8b-s8-s3 handoff · 2026-11-04 · Opus 5.5 · xhigh
Status: done. Builder s3-refresh-33-catch: open item 33 (the catch where it is drawn, D79), the 17.5 header residual,
and item 32 during a reset. One pre-existing defect found and recorded: open item 42.

Changed:
- `State/ZTronScrollState.swift`: the drawn-motion window (`noteSwiftUIDrawnMotion`, `drawnAway`, closed by every
  intervention, motion, token, resize or the probe reaching the model); `interrupt(catching:)` adopts the drawn offset
  and zoom and takes the pin's number after the write; `catchSeq` / `catchPinRef` / `clearPin`; the 17+ reset token
  (`catchable(_:)`, cut at the catch); `stopScrollingAndZooming` keeps the window.
- `Refresh/CatchableReset.swift` (new): `DrawnResetToken` and `CatchableResetAnimation` (iOS 17 `CustomAnimation`,
  delegates to the base, finished once the token is cut).
- `Render/CatchPin.swift` (new): per-effect latches; `ContentTransform.pinned(_:)`; DEBUG events (C17).
- `Render/ContentTransform.swift`, `Refresh/RefreshIndicators.swift` (`RefreshPlacementEffect`),
  `ScalingHeader/HeaderMath.swift` + `HeaderFrameModifier.swift` (the header's six effects): draw the model while pinned.
- `Refresh/RefreshCoordinator.swift`: opens the window and wraps the reset (`state.catchable`) at the two D39
  `withAnimation` calls and the reset's mode switch.
- `Gesture/PanCoordinator.swift`: a drawn-away state counts as moving (pan and pinch environments); 17.x rebase of the
  synthesized touch-down + recognition in one `handle()`; `endCaughtTouch` at the end of a caught touch;
  `Gesture/ReleasePipeline.swift`: `endCaughtTouch` (spring back from beyond the bounds); `Gesture/PinchSession.swift`:
  `rearm(env:)`.
- `Availability/ZTronCapability.swift`, `ZTronAvailability.swift`: `customAnimation` (iOS 17, gated, forced on the
  forced lane).
- Tests: `DrawnCatchTests` (new, 14 tests × 2 paths, one hosted body count), `TransformTests`, `HeaderMathTests`,
  `AvailabilityTests`.
- `scripts/seam/catchcheck.py`: the header seam section, the centred look past L (`ZS_CATCH_L`).
- Docs: Orchestration D79, item 33 FIXED, item 42; SPEC S9 (reset sub-bullet) and S10 (amendment 2026-11-04).

Decisions:
- D79 (Orchestration). The catch is at touch-down, not at the drag's recognition: measured on 27.0, the touch-down's
  `.idle → .tracking` turns off TransformHost's pixel snap (an unanimated 1/8 pt step) and that step cancels SwiftUI's
  reset under the finger on 18+, and the refresh engine's touch-down re-grab saw pull 0 (spinner look lost).
- 17+ ends the reset at the catch (`CustomAnimation`): without it 17.5 kept the reset's rest in the header's effects for
  2.7 s and the pin drew an app's animation of the same inputs at its final value (`cinset40`: the header 41 pt in one
  frame; the plan's risk, so fixed before committing). With it every 17.5 pin ends at the next update.
- The pin stays: the 15–16 path's only mechanism (no `CustomAnimation`) and a one-update guard on 17+.
- A caught tap springs back from beyond the bounds (`endCaughtTouch`), as UIKit.

Measurements (seam lab, `aspect-rest-*-fling-hold[-follow]-hsys60-hend1p5-hreset4-fdown`, `catchcheck.py`; before = c1ec40f,
after = this commit; load 5–9 for the after lanes):

| row | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|
| S fall beyond the reset (pt) | 0.68 → −0.66 | 0.66 → 0.67 | 2.0 → 0.67 |
| S spinner drawn (pt) | 12–13.3 → 20 | 16–20 → 20 | 13.3–17.3 → 20 |
| S spinner step vs centred (pt) | 4.67 → 0.0 | 10.34 → 0.67 | 4.0 → 0.34 |
| S header seam catch → rest (pt, frames > 1) | 0.5, 0 → 0.5, 0 | 27.83, 131 → 0.5, 0 | 0.5, 0 → 0.5, 0 |
| P fall beyond the reset (pt) | 26.66 → 0.67 | 20.0 → 0.67 | 2.0 → 1.33 (0.67, 0.68) |
| P over / spinner (pt) | 0 / 12–12.7 → 0 / 19.3–20 | 11 / 6–14.7 → 0 / 20 | 0 / 8.7–14 → 0 / 20 |
| F seam (pt) / vanish frames | 0.17 / 2 → 0.33 / 0 | 29.17 (114 > 1) / 2 → 0.17 / 0 | 0.33 / 0 → 0.33 / 0 |
| P / F open-gap excess (pt) | → 0.0 / 0.33 | → 0.0 / 0.17 | → 0.0 / 0.33 |
| over / jumps / vanish (S, P, F after) | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| first drawn after the catch vs caught (pt) | −317.33 vs −317.4 | −310.00 vs −310.1 | −315.33 vs −315.3 |
| pins end | first evaluation | next update (before the 17+ cut: header 2.7 s) | first evaluation |
| s1 key `rtrig40` (17.5): residual / half / ramp / mixed | | 2.0 / 0.67 / 0.21 / 11–12, = before (c1ec40f, 2 runs each) | |

Notes on the table:
- forced P 1.33: the reset's own 2-pixel-row step 4 frames before the touch (a 25 ms recording gap before it); two other
  forced P runs read 0.67 and 0.68. The literal criterion (drop over the 4 frames ≤ the reset's own motion + 1 pt) holds:
  2.0 ≤ 1.0 + 1.
- `rtrig40` reads residual 2.0 today on 17.5 for both the before and the after code (s1 read 0.67–0.92 on 2026-11-03).
- `cinset40` (an app inset animation 0.1 s after the catch): every lane shows one-frame steps at the app's write, with or
  without a catch (no-catch controls `…-hend1p5-fdown-cinset40` on all three lanes): open item 42, pre-existing. On 17.5
  the pins end before that write (t121 vs t130) and the header follows the app's curve as in the control.

Open:
- Item 42 (pre-existing, every lane): an app-animated `contentInset` write during a pull or its retraction is drawn in one
  frame (`txAnim:false`), and it ends a carried retraction at once. Next: carry the app's transaction to the inset-only path
  for direct state writes; re-measure `cinset40`.
- Real 15/16 (M1 Mac lane), D79 there is the pin alone:
  - `…-hreset4-fdown` S / P / F: fall beyond the reset ≤ 1, spinner 20, seam ≤ 1, no over;
  - `info` events: whether the pins end at their first evaluation (15/16 drop the reset's rest at the unanimated write,
    as 27.0) or later (they keep it, as 17.5 without the cut); if later, `cinset40` draws an app animation of the same
    inputs at its final value while a pin holds (17.5 before the cut: the header 41 pt in one frame), a 15–16 difference
    to fix there (no `CustomAnimation`);
  - a tap during the reset: the content springs back from where it was caught;
  - the observer path's touch-down (UIKit touch observer) is the catch: no drag may start from the model.
- Found and reverted: a touch-down at rest makes an unanimated 1/8 pt step (the snap toggle) that cancels any in-flight
  SwiftUI animation of the content on 18+ (harmless today: nothing else animates the content under a finger).

Next:
1. Item 42 (design the transaction carry, then build).
2. The real 15/16 checks above with the M1 lane.
3. M8b-s8's remaining steps per `docs/design/M8b-s8-plan.md`.

Tests:
- Unit, whole `ZTronScrollViewTests` (`scripts/test.sh -only-testing:ZTronScrollViewTests`): 866 tests / 83 suites passed on
  27.0 and on 17.5 (9 known issues), at 9f12dbc's code.
- Demo UI (`scripts/test-demo-ui.sh`, RefreshUITests + HeaderUITests + PanUITests + NestedPagerUITests +
  UIKitObserverUITests, 61 tests): 27.0 forced 61/61 (1 skipped); 27.0 preferred 1 failure, `HeaderUITests.
  testAppBannerPullGrowsTheImage` (no light edge below the picture: that simulator was in dark appearance; set to light, it
  passes alone with this code and with c1ec40f); 17.5 1 failure, `PanUITests.testControlsUsable` ("no keyboard focus" at
  typeText): it fails alone with c1ec40f too (pre-existing, DBG-s6's 17.5 red).
- Seam lab: the table above; `s1`'s key scenario unchanged.
Usage: not measured in this subagent.
