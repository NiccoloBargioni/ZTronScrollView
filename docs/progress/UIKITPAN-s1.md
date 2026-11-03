# UIKITPAN-s1 handoff · 2026-10-27 · Opus 5.5 · default effort (side session, spike U1 of docs/design/UIKIT-pan.md §4)
Status: done. Q1–Q9 are answered per lane below. Everything is demo-only, with no `Sources/` or `Packages/` change. This branch was
fast-forwarded to the design commit 2e2de8e (`claude/upbeat-mendeleev-3a9d67`) first, so the design and open item 14 are here.

Changed:
- `Demo/ZTronScrollViewDemo/Probes/UIKitPanProbe.swift` (new). It holds:
  - a copy of the D31 passive observer (`ProbeObserver`);
  - the axis-aware `UIPanGestureRecognizer` probe (`ProbePanDriver`) with delegate variants V `on` / `off` / `axis` / `ctl`;
  - both install routes (representable 18+, window anchor 15–17 or `-ZTronProbeRoute window`) and the library's own pinch and double-tap types;
  - a demo scroller driven by the pan (`ProbeModel`: paging snap on `.ended` and on decline) and the arbiter emulation for a zoomer page;
  - `ProbeHub`, which keeps per-frame channel ranges, "both moved" frames, the `uikitpan.*` counters and the Q5 notes (fsb, fsbD, bt, btD, lift, maxT).
- `Demo/ZTronScrollViewDemo/Probes/UIKitPanProbeScreens.swift` (new). The sheet pager (4 pages, page 1 a zoomer) and three screens:
  - `uikitPanPage`: N, DBG-s8's MixedProbe / MixedTopology page with probe, native and plain targets, plus a Q9 cover sheet;
  - `uikitPanPager`: Q5 / Q7, a 2-axis view with controls under a nav bar, a tab bar and a pinned header;
  - `uikitPanDetect`: Q4.
- `SheetScreen.swift`:
  - the x channel (`offX`, `offXMin/Max`, `zxMin/Max`, `bothX`, `page`) and `uikitpan.*` / `probe.*` counters in the readout;
  - the `-ZTronSheetPlain uikitpan` pane, and the plain panes `magnifyLib` and `spatialTap2` (Q6). `DemoApp.swift` gets the three routes.
- `Demo/ZTronScrollViewDemoUITests/UIKitPanProbeUITests.swift` (new). A measurement harness, skipped unless `ZS_UKP=1`, with one `UKP` line per
  row. `scripts/uikitpan-table.py` (new) turns the lines into the tables and verdicts (`--summary` gives the per-lane tables below).
- Raw lines for every lane are in the side-session notes folder (`ukp/*.ukp`). The full tables are `docs/progress/UIKITPAN-s1-tables.md`.

## Answers (pass criteria from design §4)

- **Q1 (S, vertical, declining pan): PASS on every S lane** (17.5, 18.0, 18.5, 18.6, 26.5, 27.0), for V on and V off.
  - At medium and at large, the sheet expands, collapses and dismisses exactly as the no-gesture pane (P5).
  - The pager's x span is 0. The decline comes from `shouldBegin` through the velocity branch (translation < 8 pt).
  - So S has a UIKit-pan answer on every OS measured.
- **Q2 (S, horizontal): PASS 8/8 per V on every S lane.** Rows: page 0 → 1 at slow and fast speed, the zoomed zoomer pans mid-content
  (page stays 1), and at its edge the pager pages 1 → 2. At both detents the sheet top stays fixed (topMin = topMax), nothing is
  dismissed and bothX = 0.
- **Q3 (N): V off is the only variant with "exactly one moves" in every row**, on 26.0.1, 26.1, 26.2, 26.5 and 27.0.
  - V on and V axis double-move: page and carousel both move at 40°, page and list both at 50–90°. The design's V axis equals V on
    for a cross-axis view.
  - "Matches native" fails only in the boundary band: 50° for the carousel, 40° for the list.
  - Q3e (added) shows that UIKit's own boundary there depends on OS and speed (tables below), so step 4 does not apply. The boundary
    is a separate axis-rule correction (C2).
- **Q4:** inside a ZTron viewport, only a native `ScrollView` parent is visible: `SV-` vertical, `S-H` horizontal. `List`, `Form`,
  `TabView(.page)`, a sheet and a ZTron outer all read `---`. `onGeometryChange` agrees with a GeometryReader read on 26.5 and 27.0.
- **Q5 (all lanes):**
  - **Begin distance:** the pan's first `shouldBegin` comes at ≈ 10 pt of finger travel (UIKit's hysteresis: 10.3 / 17.7 / 41 pt for
    the first sample at 150 / 600 / 2500 pt/s).
  - **Translation at that point:** it excludes the hysteresis: 0.3 / 7.7 / 31 pt. Under load, three rows lost a sample: 12.7 pt of
    travel on 18.6, 28 on 26.0.1, 88 on 26.2. Those rows took the translation branch, still with the right axis.
  - **Lift order:** the observer's `touchesEnded` precedes the pan's `.ended` on every lane, in every row where both were recorded.
    One fast 26.2 row recorded only the pan, because the probe logs the observer's lift only after 3 moves.
  - **Second touch:** two touches together (pinch, two-finger tap) never begin the pan (state `.possible`), and a reset then produces
    no `.cancelled`.
  - **Reset of an active pan:** it produces exactly one `.cancelled`, with no `.ended` and no re-begin.
- **Q6: PASS** on 17.5, 26.5 and 27.0. The library's `MagnifyGesture` and `SpatialTapGesture(count: 2)` alone in a sheet leave
  expand, collapse and dismiss exactly as P5.
- **Q7: V ctl passes every row on 26.5 and 27.0.** On 17.5 every row passes except the pinned header, the design's documented
  window-route limitation (a SwiftUI overlay in the same hosting view).
  - V on fires a Button on a drag (17.5) and double-moves the Slider and the wheel.
  - V off on 27.0 leaves a Slider drag dead in 1 of 5 runs (V ctl: 5 of 5 move the slider alone).
  - A `.disabled` ancestor does not stop the pan on either route, so the shell's `\.isEnabled` read is required. With it, pan 0.
  - Drags from the nav bar or the tab bar never begin the pan.
- **Q8 (18.0 / 18.5 / 18.6): PASS.** There is no frame in which the sheet top and the pager x both move (bothX 0 in Q1 and Q2).
  So on 18.x the UIKit path does not show D46's sharing.
- **Q9: PASS** on 17.5 (window route), 26.5 and 27.0, with a plain cover and with the S pager as cover. The covered carousel's x
  span is 0 and its pan never begins. On the window route both receive rules reject the covered touch.

## The winning V, the 8 pt rule, the swallow rule

- **Winning V: off, refined as "ctl".**
  - `shouldRecognizeSimultaneouslyWith` is true only for `scrollArbitrationGestureName` (the window observer answers true itself,
    so it still sees every touch). It is false for every other recognizer.
  - `shouldRequireFailureOf(other)` is true when `other.view is UIControl`; on 26+ UISlider carries its own `UIPanGestureRecognizer`.
  - `shouldReceive` refuses a touch whose hit view is a `UISlider` / `UISwitch`; on 17.5 UISlider tracks touches with no recognizer.
  - V off and V ctl pass S (Q1, Q2, Q8, Q9) and N's "exactly one" (Q3). V ctl is needed for Q7.
- **8 pt switch: confirmed.** The first `shouldBegin` translation is < 8 pt for slow and medium drags on every lane, because UIKit
  subtracts its ≈ 10 pt hysteresis (0.3 pt at 150 pt/s). Velocity then gives the right axis in every row: 0° and 40° → h, 90° → v.
  At 2500 pt/s the translation is 27–31 pt, so the translation branch is used.
- **Swallow rule: confirmed, with a correction to its timing.** A reset (`isEnabled` off and on) of a pan in `.began` / `.changed`
  produces exactly one `.cancelled`. It arrives inside the `isEnabled = false` call on 17.5 and 18.x, and after the call returns
  (before the next main-queue turn) on 26.x and 27.0.
  - So the core must arm "swallow the next `.cancelled`" when the reset finds the pan active, whatever its timing.
  - A reset in `.possible` (the second-touch case) produces nothing and must not arm.
  - After a reset the in-flight finger never re-begins, even without the `shouldBegin` gate.

## Corrections to the design (for U2 / U3; nothing here changes ScrollArbitration)

- **C1 (§2, V).** Use V ctl (above) instead of V axis. The design's V axis is V on for a cross-axis view, and it double-moves at 40°.
- **C2 (§2, axis rule step 4).** Step 4 is not needed: V off gives "exactly one" for a same-axis list. Native parity inside the
  40–70° band is still not reachable with one 45° constant. UIKit's nested boundary depends on OS and speed:
  - **26.0.1 / 26.2 / 26.5 (identical):** a vertical inner list takes every angle 10–80°. A horizontal inner carousel takes
    ≤ 40° slow and up to 70° fast.
  - **27.0:** a horizontal carousel takes ≤ 40° slow and up to 50° fast. A vertical page or list needs ≥ 30° from horizontal
    (≥ 40° fast); below that nothing moves.
  - **Probe with 45° (horizontal) / 60° (vertical), V off (Q3f):** matches native in 30/32 sweep rows on 27.0 (the fast 50° carousel
    row and the fast 40° list row differ) and in 23/32 on 26.5 (fast 50–70° carousel rows, and list rows at 10–30°).
  - **Options (user / U2):** (a) one 45° rule, with the band documented as a deviation; (b) per-OS constants from these tables:
    45° across the page's axis, and for a view on the page's axis 80° on 26.x and 60° on 27.0. Speed dependence (fast drags lock to
    the inner view) is not reproduced by either option.
  - **Decided (user, 2026-10-28): (b), per-OS cones 45° / 85° (26.x) / 65° (27.0+), ties outside; supersedes the 2026-10-27 (a) answer.**
- **C3 (§2, window route).** `anchor.isDescendant(of: touch.view)` rejects the view's own drags on 17.5, in a sheet and on a plain
  screen. UIKit's hit view there is a SwiftUI drawing subview beside the anchor (`CGDrawingView`, `_UIGraphicsView`, `UIView`).
  - The rule that works is OR-ed with it: `controllerRoot(anchor) === controllerRoot(touch.view)`, where `controllerRoot` walks
    superviews until `next is UIViewController`.
  - It uses public API only. It keeps rejecting a sheet over the view (Q9) and the bars (the touch is outside the viewport rect anyway).
- **C4 (§2, second finger / swallow).** The swallow is armed by the reset, not "synchronous", as stated above.
- **C5 (§2, lift order).** The observer's `touchesEnded` precedes the pan's `.ended` in the same event on every lane. On the UIKit
  path the core must let the pan's `.ended` (UIKit velocity) be the release, and apply `touchesEnded → dragEnded`
  (`PanCoordinator.swift:197-201`) only when no UIKit pan is active.
- **C6 (§2, Install, both routes).** Measured: the `\.isEnabled` read is required. The representable route is not disabled by a
  `.disabled` ancestor on 26.5 / 27.0, and neither is the window route on 17.5.
- **C7 (§3, N detection).** `.scrollView(axis: .vertical)` is set only by SwiftUI's own vertical `ScrollView`. `List` / `Form` /
  `TabView(.page)` / a sheet / a ZTron outer are not detected, so widening N beyond the approved parent needs another detector.

## Per-lane results

Generated by `scripts/uikitpan-table.py <ukp dir> --summary` from every lane's `UKP` lines. Lane names: `L<os>` is the main run;
`L17b/c`, `L265b/c`, `L27b–f`, `L262b` and `L260b` are re-runs or add-ons (Q3e/Q3f sweeps, Q7 V repeats). Q8 is Q1 + Q2 on the 18.x lanes.

### Q1 (S, vertical drags declined: expand / collapse / dismiss as the no-gesture pane P5, pager x span ≤ 0.5)

| lane | iOS | uikitpan:off = P5 outcome | uikitpan:on = P5 outcome | max bothX |
|---|---|---|---|---|
| L17 | 17.5 | 3/3 | 3/3 | 0 |
| L180 | 18.0 | 3/3 | 3/3 | 0 |
| L185 | 18.5 | 3/3 | 3/3 | 0 |
| L186 | 18.6 | 3/3 | 3/3 | 0 |
| L265 | 26.5 | 3/3 | 3/3 | 0 |
| L27 | 27.0 | 3/3 | 3/3 | 0 |

### Q2 / Q8 (S, horizontal: page +1, zoomer pans mid-content, pages at its edge; top fixed, not dismissed, bothX 0)

| lane | iOS | V on | V off | max bothX |
|---|---|---|---|---|
| L17 | 17.5 | 8/8 | 8/8 | 0 |
| L180 | 18.0 | 8/8 | 8/8 | 0 |
| L185 | 18.5 | 8/8 | 8/8 | 0 |
| L186 | 18.6 | 8/8 | 8/8 | 0 |
| L265 | 26.5 | 8/8 | 8/8 | 0 |
| L27 | 27.0 | 8/8 | 8/8 | 0 |

### Q3 (N, rows matching UIKit's own nested scroll views; 12 rows = 0/40/50/90° × 150/600/2500 pt/s)

| lane | iOS | target | V on | V off | V axis |
|---|---|---|---|---|---|
| L260 | 26.0.1 | carousel | 7/12 (double 3) ≠ 40°,50° | 10/12 ≠ 50° | 7/12 (double 3) ≠ 40°,50° |
| L260 | 26.0.1 | list | 3/12 (double 6) ≠ 40°,50°,90° | 9/12 ≠ 40° | 9/12 ≠ 40° |
| L260 | 26.0.1 | zoomer | 12/12 | 12/12 | 12/12 |
| L261 | 26.1 | carousel | 7/12 (double 3) ≠ 40°,50° | 10/12 ≠ 50° | 7/12 (double 3) ≠ 40°,50° |
| L261 | 26.1 | list | 3/12 (double 6) ≠ 40°,50°,90° | 9/12 ≠ 40° | 9/12 ≠ 40° |
| L261 | 26.1 | zoomer | 12/12 | 12/12 | 12/12 |
| L262 | 26.2 | carousel | 7/12 (double 3) ≠ 40°,50° | 10/12 ≠ 50° | 7/12 (double 3) ≠ 40°,50° |
| L262 | 26.2 | list | 3/12 (double 6) ≠ 40°,50°,90° | 9/12 ≠ 40° | 9/12 ≠ 40° |
| L262 | 26.2 | zoomer | 12/12 | 12/12 | 12/12 |
| L265 | 26.5 | carousel | 6/12 (double 3) ≠ 40°,50° | 9/12 ≠ 50° | 6/12 (double 3) ≠ 40°,50° |
| L265 | 26.5 | list | 3/12 (double 6) ≠ 40°,50°,90° | 9/12 ≠ 40° | 9/12 ≠ 40° |
| L265 | 26.5 | zoomer | 12/12 | 12/12 | 12/12 |
| L27 | 27.0 | carousel | 6/12 (double 3) ≠ 40°,50° | 9/12 ≠ 50° | 6/12 (double 3) ≠ 40°,50° |
| L27 | 27.0 | list | 3/12 (double 6) ≠ 40°,50°,90° | 9/12 ≠ 40° | 9/12 ≠ 40° |
| L27 | 27.0 | zoomer | 12/12 | 12/12 | 12/12 |

### Q3e / Q3f (N boundary sweep: UIKit's own nested scroll views, and the probe with a 45° / 60° boundary)

movers per angle, slow/fast (P page, T target, - none)

| lane | target | V | extra | 10° | 20° | 30° | 40° | 50° | 60° | 70° | 80° |
|---|---|---|---|---|---|---|---|---|---|---|---|
| L260b | nativeCarousel | - | - | T/T | T/T | T/T | T/T | P/T | P/T | P/T | P/P |
| L260b | nativeList | - | - | T/T | T/T | T/T | T/T | T/T | T/T | T/T | T/T |
| L260b | plain | - | - | P/P | P/P | P/P | P/P | P/P | P/P | P/P | P/P |
| L262b | nativeCarousel | - | - | T/T | T/T | T/T | T/T | P/T | P/T | P/T | P/P |
| L262b | nativeList | - | - | T/T | T/T | T/T | T/T | T/T | T/T | T/T | T/T |
| L262b | plain | - | - | P/P | P/P | P/P | P/P | P/P | P/P | P/P | P/P |
| L265b | nativeCarousel | - | - | T/T | T/T | T/T | T/T | P/T | P/T | P/T | P/P |
| L265b | nativeList | - | - | T/T | T/T | T/T | T/T | T/T | T/T | T/T | T/T |
| L265b | plain | - | - | P/P | P/P | P/P | P/P | P/P | P/P | P/P | P/P |
| L265c | carousel | off | -ZTronProbeBoundary_45,60 | T/T | T/T | T/T | T/T | P/P | P/P | P/P | P/P |
| L265c | list | off | -ZTronProbeBoundary_45,60 | P/P | P/P | P/P | T/T | T/T | T/T | T/T | T/T |
| L27b | nativeCarousel | - | - | T/T | T/T | T/T | T/T | P/T | P/P | P/P | P/P |
| L27b | nativeList | - | - | -/- | -/- | T/- | T/T | T/T | T/T | T/T | T/T |
| L27b | plain | - | - | -/- | -/- | P/- | P/P | P/P | P/P | P/P | P/P |
| L27e | carousel | off | -ZTronProbeBoundary_45,60 | T/T | T/T | T/T | T/T | P/P | P/P | P/P | P/P |
| L27e | list | off | -ZTronProbeBoundary_45,60 | -/- | -/- | T/- | T/- | T/T | T/T | T/T | T/T |
| L27e | nativeCarousel | - | - | T/T | T/T | T/T | T/T | P/T | P/P | P/P | P/P |
| L27e | nativeList | - | - | -/- | -/- | T/- | T/T | T/T | T/T | T/T | T/T |
| L27e | plain | - | - | -/- | -/- | P/- | P/P | P/P | P/- | P/P | P/P |

### Q4 (`bounds(of: .scrollView(axis:))` inside a ZTron viewport: S any, V vertical, H horizontal)

| lane | iOS | none | nativeV | nativeH | list | form | tabPage | sheet | ztron |
|---|---|---|---|---|---|---|---|---|---|
| L265 | 26.5 | --- | SV- | S-H | --- | --- | --- | --- | --- |
| L27 | 27.0 | --- | SV- | S-H | --- | --- | --- | --- | --- |

### Q5 (finger travel at the first shouldBegin, its translation and decision source; lift order; second touch; reset)

| lane | iOS | deg/speed: travel→translation (src) | axis decided | lift order | pinch (2 touches) | reset after 1 change: began/cancelled(sync,async)/ended |
|---|---|---|---|---|---|---|
| L17 | 17.5 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 37 | 150:b1/x1(s1a0)/e0 600:b1/x1(s1a0)/e0 2500:b1/x1(s1a0)/e0 |
| L180 | 18.0 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 35 | 150:b1/x1(s1a0)/e0 600:b1/x1(s1a0)/e0 2500:b1/x1(s1a0)/e0 |
| L185 | 18.5 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 34 | 150:b1/x1(s1a0)/e0 600:b1/x1(s1a0)/e0 2500:b1/x1(s1a0)/e0 |
| L186 | 18.6 | 0°/150:12.7→2.7v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:28.3→18.3t | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 30 | 150:b1/x1(s1a0)/e0 600:b1/x1(s1a0)/e0 2500:b1/x1(s1a0)/e0 |
| L260 | 26.0.1 | 0°/150:10.3→0.3v 0°/600:28.3→18.3t 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 29 | 150:b1/x1(s0a1)/e0 600:b1/x1(s0a1)/e0 2500:b1/x1(s0a1)/e0 |
| L261 | 26.1 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 29 | 150:b1/x1(s0a1)/e0 600:b1/x1(s0a1)/e0 2500:b1/x1(s0a1)/e0 |
| L262 | 26.2 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:88.3→78.3t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls,pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 27 | 150:b1/x1(s0a1)/e0 600:b1/x1(s0a1)/e0 2500:b1/x1(s0a1)/e0 |
| L265 | 26.5 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 28 | 150:b1/x1(s0a1)/e0 600:b1/x1(s0a1)/e0 2500:b1/x1(s0a1)/e0 |
| L27 | 27.0 | 0°/150:10.3→0.3v 0°/600:17.7→7.7v 0°/2500:41.0→31.0t 40°/150:15.2→1.7v 40°/2500:41.2→27.1t 90°/600:17.7→7.7v | h h h h h v | obs<pan:controls | maxT 2 began 0 reset 1 cancelled 0 pinch 29 | 150:b1/x1(s0a1)/e0 600:b1/x1(s0a1)/e0 2500:b1/x1(s0a1)/e0 |

### Q6 (the library's MagnifyGesture / SpatialTapGesture(count: 2) alone in a sheet: outcome = P5)

| lane | iOS | magnifyLib = P5 outcome | spatialTap2 = P5 outcome |
|---|---|---|---|
| L17 | 17.5 | 3/3 | 3/3 |
| L265 | 26.5 | 3/3 | 3/3 |
| L27 | 27.0 | 3/3 | 3/3 |

### Q7 (controls on the UIKit path; per V: rows passing, failing rows)

| lane | iOS | V | rows passing | failing rows |
|---|---|---|---|---|
| L17 | 17.5 | on | 5/9 | buttonDrag sliderDrag toggleTap wheelDrag |
| L17b | 17.5 | axis | 1/2 | disabledRaw |
| L17b | 17.5 | ctl | 10/12 | sliderDrag headerDrag |
| L17b | 17.5 | off | 10/12 | sliderDrag headerDrag |
| L17c | 17.5 | axis | 1/2 | disabledRaw |
| L17c | 17.5 | ctl | 22/24 | headerDrag headerDrag |
| L265 | 26.5 | axis | 1/2 | disabledRaw |
| L265 | 26.5 | off | 11/12 | toggleTap |
| L265 | 26.5 | on | 9/12 | sliderDrag toggleTap wheelDrag |
| L265b | 26.5 | axis | 1/2 | disabledRaw |
| L265b | 26.5 | ctl | 12/12 | - |
| L265b | 26.5 | off | 12/12 | - |
| L265b | 26.5 | on | 10/12 | sliderDrag wheelDrag |
| L27 | 27.0 | axis | 1/2 | disabledRaw |
| L27 | 27.0 | off | 11/12 | toggleTap |
| L27 | 27.0 | on | 9/12 | sliderDrag toggleTap wheelDrag |
| L27b | 27.0 | axis | 1/2 | disabledRaw |
| L27b | 27.0 | off | 11/12 | sliderDrag |
| L27b | 27.0 | on | 10/12 | sliderDrag wheelDrag |
| L27c | 27.0 | axis | 1/2 | disabledRaw |
| L27c | 27.0 | off | 12/12 | - |
| L27c | 27.0 | on | 10/12 | sliderDrag wheelDrag |
| L27d | 27.0 | axis | 1/2 | disabledRaw |
| L27d | 27.0 | ctl | 36/36 | - |
| L27d | 27.0 | off | 24/24 | - |
| L27f | 27.0 | axis | 1/2 | disabledRaw |
| L27f | 27.0 | ctl | 24/24 | - |

### Q9 (a sheet over an N carousel: carousel x span 0 and its pan never begins)

| lane | iOS | cover | carousel x span | carousel began | verdict |
|---|---|---|---|---|---|
| L17 | 17.5 | plain | 0.0 | 0 | PASS |
| L17 | 17.5 | pager | 0.0 | 0 | PASS |
| L265 | 26.5 | plain | 0.0 | 0 | PASS |
| L265 | 26.5 | pager | 0.0 | 0 | PASS |
| L27 | 27.0 | plain | 0.0 | 0 | PASS |
| L27 | 27.0 | pager | 0.0 | 0 | PASS |


## Lane notes

- Private devices (`simctl create`, `ukp-*`): 17.5 iPhone 15 Pro; 18.0 / 18.5 / 18.6 iPhone 16 Pro; 26.0.1 / 26.1 / 26.2 / 26.5
  iPhone 17 Pro; 27.0 iPhone 18 Pro. Each lane booted its device first and shut it down after. 26.0 ran with no other 26.0 device.
- Host load was 100–1000. At 4 concurrent lanes plus about 11 other sessions' simulators, the per-user process limit (4000) was
  hit: `fork` failed, xcodebuild aborted, and the Bash tool died. After that, lanes ran 2–3 at a time. The first 17.5 and 27.0
  runs failed at launch (boot timeout, empty element tree) and were re-run; their rows are kept apart (`ukp/smoke/`).
- Harness fixes made during the run:
  - Q7 values are cumulative per launch, so verdicts use per-row changes.
  - The toggle is tapped at its switch.
  - The tab-bar drag stays on the probe tab; on 17.5 a drag across it selected the other tab.

Open:
- V ctl's `UISlider` / `UISwitch` list is a probe choice. A drag starting on any other `UIControl` still pans, as in UIScrollView.
- Not scriptable in XCUITest: a second finger landing during an active pan. The probe forces the same reset (`-ZTronProbeResetAfter 1`),
  and real second touches came only from pinch and two-finger tap. It is a device check.
- 15 / 16 runs (window route, dismissal only on 15) are the user's: no runtime on this host.
- D40 / SHEET-s3 still block U3 only (unchanged). Settled since: D40 accepted (D84) but not landed as the 26+ default (D86, INTEG-s2 2026-11-03), SHEET-s3 refused (D74).

Next: U2 core per docs/design/UIKIT-pan.md at 9e6d448 (U1 corrections folded in there; C2 = option (b), per-OS cones 45° / 85° (26.x) / 65° (27.0+), user 2026-10-28).

Tests: harness only. `TEST_RUNNER_ZS_UKP=1 scripts/test-demo-ui.sh 'platform=iOS Simulator,id=<udid>'
-only-testing:ZTronScrollViewDemoUITests/UIKitPanProbeUITests[/testQn_…]`, then `scripts/uikitpan-table.py <dir-of-.ukp> --summary`.
Every lane executed its selected tests. The XCTest failures were harness launch failures under load and were re-run. The regular
demo suite is unaffected: the class skips without `ZS_UKP`, and no existing screen changes behaviour (the sheet readout only gains fields).

Usage: not measured
