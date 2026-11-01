# BOTTOMSHEET · ZTronScrollView inside lucaszischka/BottomSheet (measurement spike, 2026-10-21)

> **Merged as docs only (INTEG-s1, 2026-11-01).** The screen, `BottomSheetUITests` and the remote package pin stay on branch
> `claude/nervous-fermi-60dcbf` until the user accepts a remote dependency in the Demo; its scrollDisabled commit was dropped (D38, DBG-s6, had fixed it
> on main first). Measured before `ztronScrollYieldsToSheet` (D36, SHEET-s2) was built: re-measure with it before deciding the recipe.


Question (user): "test against https://github.com/lucaszischka/BottomSheet". That package is a pure-SwiftUI bottom sheet (not
`UISheetPresentationController`, so a different arbitration problem from SHEET-spike.md). It draws the sheet itself; the drag indicator and
the header carry a `DragGesture`; `enableContentDrag()` adds a `highPriorityGesture(DragGesture)` on the main content; `enableAppleScrollBehavior()`
wraps the content in its own UIKit scroll view (UIScrollViewWrapper). Measured, not designed. **No library change** (the `scrollDisabled`
bridge fix of D38 (DBG-s6) is exercised, see §3). Handoff: `docs/progress/BOTTOMSHEET-s1.md`.
Code: `Demo/ZTronScrollViewDemo/BottomSheetScreen.swift` (`-ZTronScreen bottomsheet`), `Demo/ZTronScrollViewDemoUITests/BottomSheetUITests.swift`
(characterization tests that print `BS …` lines, plus two asserting tests A1/A2).

## 1. Method

- Dependency: the Demo project links `https://github.com/lucaszischka/BottomSheet.git` pinned to revision `3d1238d` (3.1.1 + 5 commits, MIT; the repo's
  tags are mixed, `v2.6.0` is the newest `v`-tag and not the newest release). The pin is in `project.pbxproj` and `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
  The library target (`Package.swift`, `Sources/`) does not depend on it; remove the three pbxproj hunks and the screen to drop it.
- Screen: the sheet's main content is a `ZTronScrollView` (80 rows of 44 pt), SwiftUI's `ScrollView` with `-ZTronBSNative`, or plain rows inside
  the library's own wrapper with `-ZTronBSApple` (reference). Positions: bottom `.relativeBottom(0.125)`, middle `.relative(0.4)`, top `.relativeTop(0.75)`.
  Args: `-ZTronBSStart`, `-ZTronBSContentDrag`, `-ZTronBSContentDragNotTop`, `-ZTronBSYield none|ztronNotTop|nativeNotTop`, `-ZTronBSSizeAnchor top`,
  and the existing DEBUG `-ZTronPanGestureMode`.
- Oracle = the app: a display-link sampler records the main content's top in window coordinates (it moves with the sheet) and the content offset, and
  counts frames where only the sheet / only the content / both moved; the sheet's position path comes from the binding. XCUI frames are the cross-check.
- Matrix: iOS 27.0 (iPhone 18 Pro clone) and 17.5 (iPhone 15 Pro clone); ours on preferred and `--forced`, native and the wrapper on preferred only.
  15/16 runtimes do not run on this Mac: not measured. Drags as in SHEET-spike §1.

## 2. Results (drag starting on the scroll view; "sheet" = the sheet followed the finger, "scrolls" = the content offset changed)

| Case | 27.0 ours | 27.0 native | 17.5 ours | 17.5 native |
|---|---|---|---|---|
| H1/H2 drag on the sheet's header (control) | sheet moves (middle↔top) | – | same | – |
| S1–S3 no `enableContentDrag` | scrolls, sheet fixed | identical | identical | identical |
| S3c at top, offset 0, drag down | rubber band, sheet fixed | identical | identical | identical |
| C1/C2 `enableContentDrag()` | **scrolls, sheet never moves** | **sheet moves, never scrolls** | **sheet moves, never scrolls** (dragBegan 0, even at top) | **scrolls, sheet never moves** |
| Y1 content drag + scroll off below top (`.ztronScrollDisabled` = `.scrollDisabled`, identical rows) | **dead**: neither moves, at any position | middle→top ✓; at top never scrolls ✗; pull down at offset 0 collapses ✓ | middle→top ✓; at top never scrolls ✗ (sheet bounces); pull down collapses ✓ | middle→top ✓; at top scrolls ✓; pull down rubber-bands |
| R1 content drag **only below top** + scroll off below top | **dead** (as Y1) | middle→top ✓, top scrolls ✓, pull down rubber-bands | **middle→top ✓, top scrolls ✓, pull down rubber-bands: identical to native** | same as ours |
| R2/R3 R1 with the pan attached as `.high` / `.gesture` (DEBUG knob) | **identical to native** (✓ ✓ ✓) | – | identical to default | – |
| P1–P4 content drag always on, pan `.high` / `.gesture` | sheet takes the drag, never scrolls (= native 27.0; no rubber band at top) | – | unchanged (sheet takes the drag) | – |
| `enableAppleScrollBehavior` wrapper (S1–S3, reference) | pull down at offset 0 collapses; upward drags neither scrolled nor expanded under the synthetic drag (not investigated) | – | same | – |
| H2 → H3 sheet top→middle (viewport 561→276 pt) | offset shifts 0→135 (visible centre kept, S7) vs **0** with `defaultScrollAnchor(.top, for: .sizeChanges)` | native keeps the offset (C1c/Y1d: `off` 0..0 across the same resize) | shift 90 vs **0** | – |

Preferred and `--forced` agree row by row on each OS. Both rows named Y1 for ours (`.ztronScrollDisabled` vs SwiftUI `.scrollDisabled`) are identical on
every lane: the D38 (DBG-s6) fix works in a third-party sheet (`testA2_…` asserts it, green on the four lanes).

## 3. Reading

- **Without `enableContentDrag` the view is a drop-in** for the native `ScrollView` inside BottomSheet on both OSes (S1–S3 identical); the sheet moves by its
  header / indicator (H1/H2). Asserted by `testA1_…`, green on 27.0 and 17.5, preferred and `--forced`.
- **`enableContentDrag()` makes the content and the sheet compete, and the winner flips with the OS for ours and for the native view alike**: on 27.0 our
  `simultaneousGesture` pan wins over the sheet's `highPriorityGesture` (sheet frozen) while the UIKit scroll view loses; on 17.5 the parent's high-priority
  drag wins over our pan (our drag never begins) while the UIKit scroll view wins. BottomSheet's README says the option "has no effect or even makes the sheet glitch" with a
  `ScrollView`/`List`; that holds, per OS, for the native view too. Mechanism is inferred from the outcomes (dragBegan, pan events, sheet frames), not from a recognizer trace.
- **Disabling our view does not yield the drag on 27.0** (Y1, R1): `.ztronScrollDisabled` / `.scrollDisabled` switch the *effect* off; the pan stays attached and
  recognized, so the sheet's drag never starts (same finding as SHEET-spike §4 V6/V8). On 17.5 the sheet wins regardless, so the recipe works there.
- **The recipe that reproduces Apple's behaviour with this sheet** is `enableContentDrag(position != top)` + `.ztronScrollDisabled(position != top)` (R1): it works today on
  17.5 (identical to native) and on 27.0 only when the pan is attached as `.high` or `.gesture` (the DEBUG `-ZTronPanGestureMode`; the shipped default is `.simultaneous` on every OS).
- **Viewport resizes shift the offset** (sheet detent changes): the library keeps the visible centre (S7), the native view keeps the offset. For a sheet that is
  rarely wanted; `defaultScrollAnchor(.top, for: .sizeChanges)` (member or twin) makes it 0 (H3).

## 4. Recommendation (nothing implemented; for the user)

1. **Document now** (SPEC S12 sheet recipes / README): inside BottomSheet use the view without `enableContentDrag`, and `.defaultScrollAnchor(.top, for: .sizeChanges)`;
   do not combine `enableContentDrag()` with a scroll view (library limitation, differs per OS). The position-switched recipe (R1) works on 17.5 and on 27.0 once the yield exists.
2. **Decide with the sheet yield work** (SHEET-spike §5, `ztronScrollYieldsToSheet`): the same gap shows here on 27.0, so a yield that masks the pan
   (`including: .subviews`) while the view is disabled / yielding would fix R1 for BottomSheet *and* the system sheet. Alternative or complement: per-OS default pan attachment
   (design §8 chose `.simultaneous` empirically; R2/R3 show `.high` / `.gesture` make a pure-SwiftUI parent's drag win on 27.0 as it already does on 17.5) — this changes the arbitration
   with every parent gesture, so it needs its own measurement round, not a one-line switch.
3. Not covered: Buttons inside the content under the sheet's high-priority gesture; iPad / floating / landscape layouts; 15/16 runtimes; the wrapper's upward-scroll behaviour.
