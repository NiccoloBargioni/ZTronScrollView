# SHEET · ZTronScrollView inside a bottom sheet (measurement spike, 2026-10-21)

Question (user): how does a `ZTronScrollView` behave inside a SwiftUI `.sheet` with `presentationDetents([.medium, .large])`
(iOS 16+; a plain `.sheet` on 15)? Native reference: a SwiftUI `ScrollView` cooperates with `UISheetPresentationController`
(top of content → a down drag moves / dismisses the sheet; scrolled content scrolls; at medium an up drag expands the sheet first
unless `presentationContentInteraction(.scrolls)`; `interactiveDismissDisabled`). Nothing in SPEC/designs/tests covered sheets.
Measured, not designed. **No library change.** Handoff: `docs/progress/SHEET-s1.md`. Code: `Demo/ZTronScrollViewDemo/SheetScreen.swift`
(`-ZTronScreen sheet`), `Demo/ZTronScrollViewDemoUITests/SheetUITests.swift` (characterization tests; they print `SHEET …` / `SHEETREC …` lines).

## 1. Method

- Screen: a button presents a sheet holding either a `ZTronScrollView` (80 rows of 44 pt) or, with `-ZTronSheetNative`, SwiftUI's `ScrollView`
  with the same rows. Args: `-ZTronSheetDetents medium,large|large`, `-ZTronSheetStart medium|large`, `-ZTronSheetInteraction scrolls|resizes|default`
  (iOS 16.4), `-ZTronSheetNoDismiss`, plus the experiment switches `-ZTronSheetYield …`, `-ZTronSheetPlain …`, `-ZTronSheetIntrospect`.
- Oracle = the app, not XCUI snapshots: a display-link sampler (`SheetProbe`) records, per frame, the sheet content's top in window coordinates
  and the content offset (ours: `ZTronScrollState.contentOffset`; native: `GeometryReader` in a named space), and counts frames where only
  the sheet moved / only the content moved / both (> 0.5 pt). So a sheet that moved during a drag and came back is visible. XCUI frames
  (snapshot button, scroller, `Row 0`) are the cross-check (`Row 0` offset = content offset − 11 pt of border).
- Gestures: `press(forDuration: 0.05, thenDragTo:, withVelocity: .slow, thenHoldForDuration: 0.3)` unless "flick" (`.fast`, no hold); drags start 24 pt
  inside the scroller's top (down) or 60 pt above its bottom (up). Offsets in pt; sheet top in window pt (27.0: medium 415, large 62; 17.5: 399 / 69).
- Matrix: iOS 27.0 (iPhone 18 Pro clone) and 17.5 (iPhone 15 Pro clone), private simulator clones, clean worktree at ecca598 + the two demo files.
  Ours on all five paths: 27.0 preferred (SpatialEventGesture) and `--forced`, 17.5 preferred, `--forced`, `--forced --uikit` (the shipped 15–16 shape,
  D31). Native on the preferred runs. iOS 15/16 runtimes do not run on this Mac: not measured there.
- Harness note: the first pass read native offsets as 0 (preference-based readout never fired); fixed in pass 2 (direct write from the
  `GeometryReader`). Every number below is from pass 2 or later for native. All runs green (the tests only assert that the harness worked).

## 2. Results (ours vs native)

"sheet" = top range seen while the finger was down and after (pt). Ours is identical on all five paths (the `c.pan.ev.cancel` counter differs on 17.5 only).

| Case | Native, 27.0 | Native, 17.5 | **Ours** (27.0 and 17.5, every path) |
|---|---|---|---|
| A1 medium, offset 0, drag down 250 | sheet 415→885, **dismissed**; content untouched | 399→852, dismissed | **sheet never moves** (415..415); content rubber-bands to −104 (−100) and returns; not dismissed |
| A2 same, flick | dismissed | dismissed | rubber band −104, sheet fixed |
| A3 large, offset 0, down 250 | sheet 62→415 (**collapses to medium**) | 69→399 | content rubber-bands −113 (−112); sheet stays large |
| A4 large only, down 250 | sheet follows to 302 (+240), springs back to 62; not dismissed | 309, back to 69 | rubber band −113; sheet fixed |
| B1 large, scrolled to 660, down 150 | content 660→520; sheet fixed | same | **identical** |
| B2 same, up 150 | content 660→800; sheet fixed | same | **identical** |
| C1 medium, offset 0, up 250 (default interaction) | **sheet expands first** (415→62), content stays 0 | 399→69 | **content scrolls 0→250 (240), sheet stays medium** |
| C2 same, `.scrolls` | content 0→250, sheet fixed | 0→237 | identical to native |
| C3 same, `.resizes` | = C1 (default is `.resizes`) | = C1 | = C1 row (content scrolls, sheet fixed) |
| D1a large, scrolled, down 700 (past the top) | content to 0, overscroll −16; sheet fixed | same | **identical** |
| D1b then a new drag down 250 from the top | **sheet collapses** 62→415 | 69→399 | rubber band −96…−109, sheet fixed |
| D2 one 520 pt drag from 220 across the top | content to 0, overscroll −132; **sheet does not take over mid-gesture** | −131 | **identical** |
| E1 medium, `interactiveDismissDisabled`, down 300 | sheet follows with resistance to 506 (+91) and returns; stays | +87 | content bounce −120 (−115); sheet never moves |
| E2 large only, noDismiss, down 250 | sheet 62→142 (+80), returns | +79 | bounce −113; sheet fixed |
| H1 control: drag starts on the sheet header (outside the scroller) | dismissed | dismissed | **dismissed too**: the sheet itself is fine with our view inside |

Counts: `both` (sheet and content moved in the same frame) is 0 in every case above; no double movement exists. The three feared failure modes
reduce to one: **a drag that starts on a ZTronScrollView never reaches the sheet** (content always wins, at every detent, in both directions).

## 3. Mechanism

- It is not specific to ZTronScrollView. Controls (`-ZTronSheetPlain`, no scroll view, a pane with one SwiftUI gesture) on both OSes:
  `.simultaneousGesture(DragGesture(minimumDistance: 10))`, `…(minimumDistance: 0)`, `.gesture(…)`, `.highPriorityGesture(…)` each leave the sheet
  frozen for a 250 pt drag (sheet 415..415 / 399..399, gesture saw 53–61 changes); the same pane **without** a gesture is dismissed (415→885 / 399→852).
  A recognized SwiftUI drag anywhere under the finger takes the touch away from the sheet. (SpatialEventGesture also freezes it; MagnificationGesture and a double tap do not: §4.)
- 27.0 (passive target/action hooks on every recognizer in the window's view tree, `-ZTronSheetIntrospect`): the sheet's pan is
  `_UIFlexInteractionPanGestureRecognizer` on the `UIWindow` (delegate `_UIFlexInteraction`). With ours it **does begin and delivers 54–60 changes**
  (the whole drag) and the sheet still does not move: the recognizer is not failed or blocked, the interaction declines to move the sheet (the reason is
  private). With the native `ScrollView` the `UIScrollViewPanGestureRecognizer@HostingScrollView` also begins (c56) and the flex pan acts first when the
  sheet should win (C1: flex began at 1584 ms, scroll pan 145 ms later); when the scroll view should win (M3: large, scrolled) only the scroll pan fires.
  So the sheet arbitrates with a `UIScrollView` it can inspect; a SwiftUI gesture is just "someone else claimed the touch".
- 17.5: SwiftUI's `UIKitGestureRecognizer@_UIHostingView` is the recognizer that begins for ours (and for the plain controls); the sheet's own pan is not
  in the window's view tree (private), so its recognizer could not be hooked. Outcome identical to 27.0. The 15–16 UIKit observer path (D31, passive,
  stays `.possible`) behaves like the others, so it does not interfere with the sheet; the SwiftUI pan alone freezes it.
- Note E (MC-contract §6, Open item 1) is the same family: a recognized SwiftUI drag on the hosting view starves a UIKit pan on ≤ 17. Here it starves
  the sheet's pan on 27.0 as well.

## 4. What is fixable in pure SwiftUI (measured)

| Experiment (ours unless "plain") | 27.0 | 17.5 | Reading |
|---|---|---|---|
| V1/V7 SwiftUI `.scrollDisabled(true)` on our view | content still scrolls 0→250, sheet fixed | same | **`scrollDisabled` did not disable ZTronScrollView** (a library bug, not the sheet: fixed in DBG-s6 / D38, V1/V7 now read like V6/V8; §6); and effect gating would not free the sheet anyway |
| V6/V8 `.ztronScrollDisabled(true)` | content does not scroll, **sheet still fixed** | same | the gesture stays attached and recognized: switching the *effect* off does not yield |
| V2 `.allowsHitTesting(false)` at medium, on at large | up 250 at medium: **sheet expands** (415→62); at large content scrolls 0→240 and back | same | works, but taps and buttons in the content die at medium |
| P7 plain pane, `simultaneousGesture(drag, including: .subviews)` | up 250: sheet expands 415→62 | 399→69 | **masking the gesture frees the sheet**; subview gestures stay |
| P8 same, mask switched by detent (`.subviews` at medium, `.all` at large) | medium: expands; then at large the gesture runs again (57 changes), sheet fixed | same | the per-state yield works on both OSes |
| P9 SpatialEventGesture (plain, unmasked) | **sheet frozen** (415..415, 61 events) | n/a (iOS 18+) | the 27.0 observer freezes the sheet like the pan |
| P10 MagnificationGesture / P11 double tap (plain, unmasked) | sheet **dismissed** (415→885) | dismissed (399→852) | pinch and double tap do not take the drag |
| P12 pan + 0-distance drag + SpatialEventGesture (27.0) + pinch + double tap, all masked by detent | medium, up 250: **sheet expands** (415→62); then at large they run again (123 events), sheet fixed | 399→69; 118 events (also on `--forced --uikit`) | the library-shaped yield works as a set |
| V3 pull release (delegate: lift with offset < −60 → detent change / dismiss) | medium: rubber band, then the sheet **dismisses** after the lift; large: **medium** after the lift (content keeps its visible centre: offset 59–74) | same | emulation without a library change; no finger tracking, no velocity |
| V4 / V5 pull release, large / noDismiss | detent → medium / stays | same | respects `interactiveDismissDisabled` only because the closure checks it |

What is **not** fixable without UIKit: the live top-edge hand-off. The sheet decides at touch-down whether it gets the sequence; once a SwiftUI drag
is recognized it never does (P1–P4, D2 even for native: no mid-gesture hand-off). A view that is a gesture region cannot know the drag direction before
the gesture starts, so "yield only for a downward drag at offset 0" cannot be expressed. The sheet cannot be told our offset (it asks UIScrollViews).

## 5. Recommendation (for the user to decide; nothing implemented)

1. **Document now**: SPEC S12 (and a parity-matrix row for `presentationContentInteraction`, which is not a ScrollView API) — inside a sheet a
   `ZTronScrollView` behaves like `.scrolls` at every detent: drags that start on it never move or dismiss the sheet; the grabber / header / non-scroll
   regions still do (H1). Status: approximate. `interactiveDismissDisabled` needs nothing (content drags cannot dismiss anyway).
2. **Small API, small cost (~1–1.5 %)** — `ztronScrollYieldsToSheet(_ yields: Bool)` (environment-backed, name open): while `true` the view attaches
   its drag-class gestures (pan, observer / spatial events, pinch, double tap) with `including: .subviews`, so the sheet gets the drag and controls inside
   keep working; the app drives it from its detent selection (`yields: detent != .large` ≙ native `.resizes`; never ≙ `.scrolls`). Evidence: P7, P8, P12.
   Verify in the builder session: Buttons stay tappable while masked, the UIKit-observer path (15–16) needs no change, catch/inertia state when the flag flips
   mid-motion, fallbacks on 15 (`GestureMask` exists there).
3. **Collapse-from-the-top at the largest detent**: no API; a docs recipe — `onZTronScrollEndDragging` + offset < −60 → change the detent selection or
   dismiss (V3–V5 measured; no live tracking, no flick velocity). Live tracking would need UIKit (out of S2).
4. Decisions needed from the user: accept (1)+(2) as an S8/S12 amendment? Name? Should the flag also exist as a modifier on the sheet content
   (`.presentationContentInteraction`-aware: read `ZTronScrollView`'s own detent from the environment is not possible; selection stays the app's)?

## 6. Findings outside the question

- `.scrollDisabled(_:)` (SwiftUI) had no effect on a `ZTronScrollView` in the sheet (V1, V7: content scrolled 250 pt on 27.0 and 17.5 with it `true`);
  `.ztronScrollDisabled(_:)` works (V6, V8). **Resolved by DBG-s6 (`docs/progress/DBG-s6.md`, D38)**: not sheet-specific (the same outside a sheet, every
  OS path); the bridge's reader was a `ViewModifier` returning its content, whose body never ran, so `PanCoordinator.nativeScrollEnabled` stayed `true`.
  Fixed (a leaf `View` in a background); `ScrollDisabledUITests` covers it inside and outside a sheet.
- After a drag with `.ztronScrollDisabled(true)` the offset reads 9 (V6b/V8b; 0 before): **not the pan's slack and not a library fault.** The readout `Text`
  above the scroller grew from nothing to three lines at the first snapshot, the viewport shrank by 18 pt and the offset followed by half of it (the
  visible centre is kept, SPEC S7). With a fixed-height readout the offset stays 0; DBG-s6 pins both (`testDisabledViewFollowsItsViewportNotTheFinger`).
- Under load (up to 634) every run was green; no flake seen in these tests.

## 7. iOS 18.x (DBG-s7, 2026-10-21; D46, `docs/progress/DBG-s7.md`): §2 and §3 are 17.5 / 27.0 facts

§1–§6 were measured on 27.0 and 17.5 only (DBG-s7 re-checked 26.0, 26.5 and 27.0 with the new S1 / D1 / start-at-top tests: same as §2). DBG-s7 ran the same cases on 18.0, 18.2, 18.4, 18.5 and 18.6 (iPhone 16 Pro clones, preferred; 18.5 also `--forced`) after
two demo UI tests went red there. The numbers below are 18.5 preferred; the other four runtimes and the `--forced` path agree on every probe case
(A1, B1, D1a, P1, P3: identical sheet ranges and final offsets, `pc` 41–57), no flake.

**What differs: SwiftUI 18.x shares a drag between the sheet's pan and a `.simultaneousGesture` drag.** Plain pane, no scroll view (controls, 250 pt drag down at medium):

| Control | 17.5 / 27.0 (§3) | 18.0 – 18.6 |
|---|---|---|
| P1 `.simultaneousGesture(DragGesture(minimumDistance: 10))`, P2 distance 0, P9 `SpatialEventGesture` | sheet frozen | **sheet dismissed** (410 → 874) while the gesture sees 56–61 changes |
| P3 `.gesture(DragGesture)`, P4 `.highPriorityGesture(DragGesture)` | sheet frozen | sheet frozen (410..410), gesture sees 41–57 changes |
| P5 nothing, P10 magnify, P11 double tap | dismissed | dismissed |
| P7 / P8 / P12 masked with `.subviews` | sheet free | sheet free (P12a: 410 → 72, then back at medium) |

ZTronScrollView attaches its observer and pan with `.simultaneousGesture` (M3 §8), so on 18.x it is the P1 row: the sheet takes the drag **with** the view. The sheet moves under the
finger, the pan's local translation stays near 0 (inferred from `dragBegan` 1 and offsets that move by no more than the 10 pt slack while the sheet travels 140–800 pt), so the content
does not follow the finger. `testTheSheetTreatsOursLikeAPlainSimultaneousDrag` pins "ours = P1" on every OS and prints P3 (`sheetMoved` ours / plain-simultaneous / plain-gesture).

Across runtimes (`testTheSheetTreatsOursLikeAPlainSimultaneousDrag` = S1: does a 250 pt drag down at medium move the sheet; D1a: large, scrolled to row 15, 700 pt down):

| Runtime | S1 ours / plain `.simultaneousGesture` / plain `.gesture` | D1a ours | First pane layout |
|---|---|---|---|
| 17.5 (preferred, `--forced`, `--forced --uikit`) | frozen / frozen / frozen | content to 0 (−16), sheet fixed | 28 x 68, then 393 x 419 (detent) |
| 26.0, 26.5, 27.0 | frozen / frozen / frozen | content to 0 (−16), sheet fixed | 402 x 436 (detent) |
| 18.0, 18.2, 18.4, 18.5 (+ `--forced`), 18.6 | **moved / moved** / frozen | **sheet dismissed**, content 660 | 402 x 768 (large), then 402 x 430 |

Ours against native, 18.5 (sheet top in window pt: medium 410, large 72, gone 874):

| Case | Native | Ours |
|---|---|---|
| A1 / A2 medium, offset 0, down 250 / flick | dismissed | dismissed |
| A3 large, offset 0, down 250 | collapses to medium (72 → 410) | the same (72 → 410) |
| A4 large only, down 250 | follows to 312, springs back | the same, and the content overscrolls 4 pt (§2: sheet fixed, content −113 on 27.0 / 17.5) |
| B1 large, scrolled to 660, down 150 | content 660 → 520, sheet fixed | **sheet follows to 212 (+140), content stays 660** |
| B2 same, up 150 | content 660 → 800, sheet fixed | content 660 → 791, sheet 63..72 |
| C1 medium, offset 0, up 250 (default / `.resizes`) | sheet expands (410 → 72) | the same |
| C2 same, `.scrolls` | content 0 → 240, sheet fixed | **sheet expands (410 → 72)**: `.scrolls` has no effect on a view that is not a `UIScrollView` |
| D1a large, scrolled to 660, down 700 | content to 0 (−16), sheet fixed | **sheet dismissed (72 → 874)**, content stays 660 |
| D2 one 520 pt drag from offset 220 across the top | content to 0 (−132), sheet fixed | **sheet follows to 582 (past medium)**, content stays 220 |
| E1 / E2 `interactiveDismissDisabled` | sheet follows with resistance (+89 / +80), returns | the same, plus a content rubber band (−17 / −79) in the same frames (`both` 63 / 53) |
| H1 drag from the header | dismissed | dismissed |

Reading: up drags and drags from the top behave like native's default (the sheet expands, collapses or dismisses); **a drag down on content that is scrolled (B1, D1a, D2) moves or dismisses
the sheet and scrolls nothing**, which is the cost of the shared drag (native scrolls the content to its top first). "Content always wins" (§2) is false on 18.x; the S12 default is not `.scrolls` there.

**S7 follows the sheet's resizes, and the sheet's own first layout is one.** `ScrollDisabledScreen` now prints the pane's size trail (`sz`), the first offsets (`ot`) and the viewport (`vp`): the pane is laid out
at 402 x 768 (large) first and at 402 x 430 (medium) right after, for a native `ScrollView` too (18.x only: 26.5 and 27.0 lay out at the detent size, 402 x 436, from the start; 17.5 shows a degenerate 28 x 68 pane and then 393 x 419, the detent size). The first layout has no centre rule, the second is a resize:
a view that has never been touched opens a medium sheet at offset (768 − 430) / 2 = 169 (`ot=169`, one `didScroll`, `vp` 376). While the sheet is dragged the offset follows the viewport frame by frame
(169, 166, 164, … 0 at `vp` 714, back to 169 at 376; a native `ScrollView` keeps its offset). A disabled view (`scrollDisabled`, `ztronScrollDisabled`) never begins a drag (`dragBegan` 0, D38 holds in a
sheet on 18.x) but moves exactly like that. `defaultScrollAnchor(.top, for: .sizeChanges)` (S7's one override) removes the movement: offset 0, no `didScroll` through every resize.

**Experiment: the exclusive attach restores the 17.5 / 27.0 behaviour (measured on 18.5 only, not shipped).** The DEBUG switch `-ZTronPanGestureMode gesture` (M3 §8; the demo tests forward
`TEST_RUNNER_ZS_DEMO_PANMODE=gesture`) attaches the observer and the pan in one `.gesture`. Then, ours on 18.5 (sheet top / content): A1 sheet fixed at 410, content rubber band −36; A3 fixed at 72,
content −112; **B1 content 660 → 520, sheet fixed (= native)**; B2 660 → 800; C1 / C2 sheet fixed at medium, content 169 → 409 (`.scrolls`); **D1a content to 0 (−16), sheet fixed (= native)**; D1b −108;
D2 content to 0 (−132), sheet fixed (= native); E1 sheet fixed; H1 (header) still dismissed; `scrollDisabled` at medium leaves the sheet fixed too (the disabled view's recognized drag still freezes it, as
on 27.0); `testSheetMediumStartsAtTheTop` still reads 169 (the first-layout transient does not depend on the attach); `testTheSheetTreatsOursLikeAPlainSimultaneousDrag` goes red as it should (ours =
plain `.gesture`, the sheet is frozen). What that costs elsewhere (ancestors and nested views starved by an exclusive child, native `ScrollView` ancestors no longer sharing the drag) is DBG-s5's measurement
(`docs/progress/DBG-s5.md`, branch `claude/sharp-banach-dadf23`), not repeated here.

Consequences for the plan: (1) SHEET-s2's `ztronScrollYieldsToSheet(_:)` (branch `claude/strange-mendel-e1528c`, not merged, never run on 18.x) frees the sheet as designed, but its `false` is not `.scrolls` on 18.x:
the unmasked gestures still share the drag. (2) Restoring "content wins" on 18.x means attaching the pan exclusively (`.gesture`, P3), with the costs DBG-s5 measured for ancestors and nested views: a separate, measured
follow-up. (3) The presentation transient wants a library answer of its own (treat it as the first layout) or the app-side anchor above.
