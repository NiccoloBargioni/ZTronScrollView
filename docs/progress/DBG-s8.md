# DBG-s8 handoff · 2026-10-22 · Sonnet 5.5 (Debugger) — a `ZTronScrollView` inside SwiftUI's own vertical `ScrollView` never scrolls the page on iOS 26+ (DBG-s5 Open 1, Orchestration open item 12 (a))
Status: done — **explained; no pure-SwiftUI remedy inside SPEC S2; documented limitation (D47), no library change.** From iOS 26, in an app linked against the 26 SDK, a drag that starts on a ZTron view inside a native `ScrollView` never scrolls the page,
also when the view is a horizontal carousel that cannot follow a vertical drag. It is SwiftUI/UIKit, not the library: a plain `.simultaneousGesture(DragGesture())` on a colour does the same. What shipped is tests and docs: `MixedTopologyUITests` is strict per
OS and path (the 26+ page scroll is a strict `XCTExpectFailure`; three ZTron-page nesting cases added), the measurement harness (`MixedProbeScreen`, `MixedProbeUITests`, `MixedUIKitProbe`) stays for the next OS, and SPEC S12 / NESTED §6.1 / parity matrix /
Orchestration (D47, open items 12 and 13) say what works. The one deterministic fix found is a UIKit pan recognizer (Apple's own workaround for FB18199844), outside S2: your call (open item 13 (a)). Nothing merged, nothing pushed.

Merge notes (read before integrating): branch `claude/confident-babbage-6acfe7` = `claude/sharp-banach-dadf23` (DBG-s5, b84302c) merged into `main` 9b2d636 (`d20f673`; conflicts only in `Orchestration.md` and `docs/progress/STATE.md`, both additive: D40 now sits before D41, the DBG-s4/s5 STATE rows
after the M6b ones) + this work. **D47** (D42–D46 are on other branches: `git grep -n '^- D4' $(git branch --format='%(refname:short)')`), handoff **DBG-s8** (DBG-s6 is on main, DBG-s7 on `claude/suspicious-elbakyan-3d1622`). The library under `Sources/` is byte-identical to `d20f673`
(the temporary DEBUG `-ZTronPanMinDistance` knob used for the sweep below was removed), so there is nothing to merge in `GestureAttach` / `PanGestureAdapter` for the `ztronScrollYieldsToSheet` session.

What was measured (60 pt vertical or 80 pt horizontal slow drag from the middle of the target, one launch per case; every lane on a private `simctl clone` with its own derived data and `-collect-test-diagnostics never`; host load 20–1000 from other sessions, so a number is
believed when it repeats: the SwiftUI-only controls repeated 5 of 5 on 26.5; a plain native band drag gave 16 instead of 50 once at load 900):
1. **The library on a native page** (`MixedTopologyUITests`, page = pt the page scrolled; carousel = x offset, list = y offset; 26.0.1 / 26.1 each in four configs: preferred, forced, default attach and `-ZTronPanGestureMode simultaneous`, all identical):

   | OS | vertical over the horizontal carousel | horizontal over it | vertical over the vertical list | vertical over a native band |
   |---|---|---|---|---|
   | 17.5 (DBG-s5, re-measured) | page 50, carousel 0 | page 0, carousel 58 | page 50, list 1 | page 50 |
   | 18.5 (`simultaneous`) | **page 50**, carousel 0 | page 0, carousel 58 | page 50, list 0 | page 50 |
   | 26.0.1, 26.1, 26.2, 26.5, 27.0 | **page 0**, carousel 0 | page 0, carousel 58 | page 0, **list 50** | page 50 |

   (Every attach on 26.5: default `adaptive`, `simultaneous`, `gesture`, `high` give these numbers. A `ztronScrollDisabled(true)` carousel: page 0 on 26.5, 50 on 18.5: the disabled view keeps its pan attached.)
2. **No ZTron code at all** (`-ZTronScreen mixedProbe -ZTronMixedVariant …`, a 100 pt colour between two native bands in a native vertical `ScrollView`; page / callbacks of the gesture):

   | gesture on the colour | 18.5 | 26.5 |
   |---|---|---|
   | none | 50 | 50 |
   | `.simultaneousGesture(DragGesture(minimumDistance: 10))` | 50 / 13 | **0** / 12 (27.0: 0) |
   | same with `name: "ScrollArbitration.participant"`, `minimumDistance: 0`, `including: .gesture`, `contentShape` first, `SpatialEventGesture` (26.5 also: drag + magnify) | 50 | **0** |
   | `.gesture(DragGesture(10))`, `.highPriorityGesture(DragGesture(10))` | 0 | 0 |
   | `including: .subviews` / `.none` (gesture off for the view) | 50 / 50 | 50 / 49 |
   | `DragGesture(minimumDistance: 100)` (never recognized in a 60 pt drag) | 50 | 50 |
   | `TapGesture`, `TapGesture(count: 2)`, `LongPressGesture`, `MagnifyGesture`, `onTapGesture`, `Button` | 50 | 50 |
   | `DragGesture(minimumDistance: 12…55)` simultaneous (also in the `.global` space; `.gesture` and `.highPriorityGesture` from 15) | 50 (callbacks 12…3; 0 with `.gesture` / `.highPriorityGesture`) | 50 / **0** callbacks |
   | `DragGesture(10)` that switches itself off in `onChanged` (mask `.subviews`) | 50 | **0** (the page never resumes) |
   | native horizontal `ScrollView` | — | 50 |

3. **Why** (`MixedUIKitProbe`: a window-level recognizer that never begins lists `UITouch.gestureRecognizers`, KVO on `state` / `enabled` / `scrollEnabled` of every recognizer of the touch with the call stack that made the change). The page is a `HostingScrollView` with its
   `UIScrollViewPanGestureRecognizer`; SwiftUI's gestures live in `UIKitResponderGestureRecognizer`s on the ROOT `_UIHostingView`, an ancestor of the scroll view (one per named gesture; `del=UIKitResponderGestureRecognizer` on 18.5, `del=nil` on 26.5).
   - (Times are seconds since launch in one run; the stored traces are later runs of the same cases.) 18.5, `.simultaneousGesture(DragGesture(10))`: pan `0→1` (t = 2.979), responder `0→1` (2.989), both `1→2`, the page scrolls.
   - 26.5, same: pan `0→1` at 2.751 with `GFGestureNodeCoordinatorCreate` frames (the new `Gestures` framework) under the state change, responder `0→1` at 2.764 (the same touch sample), 2 ms later `isTracking` is false and the offset stays 0; there is **no** `cancelled` / `failed`
     notification for the pan, and the touch's recognizer list is `[UIKitResponderGestureRecognizer]` only from then on. A SwiftUI gesture that cancels itself 100 ms later (`drag10-selfdisable`) does not bring the pan back.
   - **The first recognizer to begin owns the touch, a tie goes to SwiftUI**: with `minimumDistance` 12…55 (local or global space) the page's pan begins first and the SwiftUI drag is blocked (page 50, 0 callbacks). An inference from these traces, not documented behaviour.
   - **Gated by the app's linked SDK**, not only the runtime: the same binary on a 26.5 runtime with its `LC_BUILD_VERSION` sdk patched by `vtool` (+ ad-hoc re-sign, own bundle id): sdk 18.5 → simultaneous drag **page 50** (12 callbacks); sdk 26.0 and the real 27.0 → page 0.
     The library's own `.gesture` carousel stays at page 0 even with sdk 18.5 (a plain `.gesture` blocks the page on 18 too). `UIDesignRequiresCompatibility = YES` changes nothing (27.0). Others report the same for iOS 26 (Apple Developer Forums 794212 / 802903, FB18199844); no fixed build is mentioned.
4. **Remedies tried, pure SwiftUI** (none works for flicks): `name:` (no effect), `including:` masks (`.subviews` / `.none` just turn the gesture off), `.gesture` / `.highPriorityGesture` (worse), `isEnabled` flip from `onChanged` (too late), `SpatialEventGesture` (also recognized at the touch-down), a gesture host stretched along
   one axis with its content counter-scaled (`scaleEffect`, a named space, a `frame`) to get a direction-selective `DragGesture`: **does not work**, vertical drags are still recognized (3–9 callbacks), `minimumDistance` is not measured in the gesture's coordinate space. **A larger `minimumDistance` N**
   (temporary DEBUG knob, real carousel, 26.5; XCUI `XCUIGestureVelocity` values with the first touch sample past 10 pt in brackets) lets the page win iff that first sample is shorter than N:

   | vertical drag over the carousel, page scrolled? | 150 (~11 pt) | 300 (14) | 600 (20) | 1000 (16) | 1500 (25) | 2500 (44) |
   |---|---|---|---|---|---|---|
   | N = 10 (today, measured) | no | no | no | no | no | no |
   | N = 16 | yes | yes | no | no | no | no |
   | N = 20 | yes | yes | yes | yes | no | no |
   | N = 24 | yes | yes | yes | yes | no | no |

   (N = 14 / 16 / 20 / 24: the horizontal drag is unchanged, carousel 58 and page 0; N = 14 / 16 / 20: a vertical list in the page then also yields to the page, list 0, as on 18.x; 27.0: N = 16 page 50 for the slow drag.) A flick crosses both thresholds in one sample, so it stays the ZTron view's, and the start of every nested drag
   would pop (or lag) by N − 10 pt: **not shipped**. An enclosing native scroller and its axes can be detected on iOS 17+ with `GeometryProxy.bounds(of: .scrollView(axis:))` (non-nil inside the page: `in=SV-`; nil outside: `out=---`; 26.5, 27.0), which would limit such a heuristic to cross-axis nests.
5. **What works** (not pure SwiftUI): a UIKit `UIPanGestureRecognizer` through `UIGestureRecognizerRepresentable` whose delegate returns `true` from `shouldRecognizeSimultaneouslyWith` (the shape of Apple's workaround for FB18199844, `uikit-pan`) coexists with the page's pan on 26.5 and 27.0: slow vertical drag page 50 with 5 callbacks
   (both follow the finger), 27.0 page 149. Adding `gestureRecognizerShouldBegin` that declines a drag that is not horizontal-dominant (`uikit-pan-axis`) is deterministic and flick-proof: vertical, XCUI 300 / 1500: page scrolls (50 / 391 on 26.5; 50 / 135 on 27.0), 0 callbacks; horizontal 80 pt: page 0,
   14 / 4 callbacks (26.5), 14 / 2 (27.0); 45° at 600: page 209 / 220, 0 callbacks. UIKit is outside S2 (a new amendment would be needed, like D31 for 15–16).
6. **Supported nestings** (`MixedTopologyUITests`, 17.5–27.0): a `ZTronScrollView` page (`-ZTronMixedPage ztron`): vertical drag over the horizontal carousel scrolls the page 50, carousel 0; horizontal drag moves the carousel 58, page 0; a vertical drag over the vertical list scrolls the list 50, page 0 (the arbiter, the same on every OS).

Changed:
- `Demo/ZTronScrollViewDemoUITests/MixedTopologyUITests.swift` — strict per OS (see the table in 1.); `XCTExpectFailure(strict: true)` for the 26+ page scroll; three ZTron-page cases; the readout is parsed (`cx` / `ly` / `py`), the page is measured before the readout changes the layout above it.
- `Demo/ZTronScrollViewDemo/MixedTopologyScreen.swift` — `-ZTronMixedPage ztron` (the page is a vertical `ZTronScrollView`), `py` in the readout.
- `Demo/ZTronScrollViewDemo/MixedProbeScreen.swift` (`-ZTronScreen mixedProbe -ZTronMixedVariant <name>`), `MixedUIKitProbe.swift` (`-ZTronProbe <tag> -ZTronProbeDir <dir>`), `Demo/ZTronScrollViewDemoUITests/MixedProbeUITests.swift` (skipped unless `ZS_VARIANTS` is set; `ZS_VARIANTS='plain,drag10-sim,zt-h^-80x0~1000'`
  = `name[^dxXdy][~velocity]`, `ZS_APP_IDS`, `ZS_PROBE=1` + `ZS_PROBE_DIR`): the measurement harness; re-run it on iOS 28 and on each 26.x / 27.x. UIKit only in the demo.
- Docs: SPEC S12 (new bullet), `design/NESTED-arbitration.md` row B + §6.1, `design/M3-pan.md` §8, `parity-matrix.md` (new row, impossible / documented), Orchestration (D47, open items 12 and 13, log), STATE row, this note.
- Library: nothing.

Decisions: D47 (Orchestration). Why no library change: every pure-SwiftUI lever either does nothing (name, mask, priority, self-cancel, per-axis host) or only helps drags slower than a flick (a larger `minimumDistance`) at the price of the start of every nested carousel drag; the one deterministic lever is UIKit.

Open:
1. **Your call:** amend S2 for iOS 26+ (a UIKit pan recognizer with a simultaneous-recognition delegate and an axis-aware `shouldBegin`, as in `uikit-pan-axis`) or keep the limitation. It would replace the SwiftUI pan on 26+, not just add an observer: a design session, not a patch.
2. A disabled view (`ztronScrollDisabled(true)`) keeps its pan attached and blocks a native page on 26+ (page 0; 18.5: 50). Fix: attach with `GestureMask.subviews` while disabled, on top of the `ztronScrollYieldsToSheet` plumbing (`claude/strange-mendel-e1528c`); `yields: true` already hands every drag to the page.
3. iOS 28 and every 26.x / 27.x fix: re-run `MixedProbeUITests` and the strict `testVerticalDragOverTheCarousel` (it goes red by itself when a page starts to scroll, which is the cue to drop the limitation text).
4. Not measured: 15 / 16 (no runtime), a native `TabView(.page)` / `List` around a ZTron view (does `.scrollView(axis:)` exist there?), a real finger (the ties depend on the touch sample spacing; XCUI gives 11–44 pt first samples).
5. Single runs were taken at host load 300–1000; the first xcodebuild of three fresh lanes died with "Mach error -308 server died" and two 26.x clones hung at 0 % CPU (26.5 + 26.1 + 18.5 at once; 26.2 next to two other lanes): killed and re-run alone, as DBG-s4 warned.

Next: 1. you decide open item 1; 2. a session for open item 2 once `ztronScrollYieldsToSheet` is integrated; 3. iOS 28 beta: re-run the harness.

Tests (the library under `Sources/` is untouched, so no unit run; every lane on a private `simctl clone` with its own derived data and `-collect-test-diagnostics never`, host load 4–1000):
- `MixedTopologyUITests` (7 tests, strict), preferred and forced: **7/7 green on 17.5, 18.5, 26.2, 26.5 and 27.0, both paths** (27.0 forced on its second start: the first start could not find the clone). Before the final form of the file: 26.0.1 and 26.1 four configs each (preferred, forced, default attach,
  `-ZTronPanGestureMode simultaneous`) and 26.5 with `high` and `gesture`, all with the same four numbers; the red/green of the strict wrapper itself: on 27.0 the first form of the file failed `testHorizontalDragOverTheCarousel` by 1 pt (the readout text above the page changed its height before the frame was read), fixed by reading the frame first.
- Whole demo UI suite, 27.0 preferred, tree = the final tests: **Executed 178 = the suite size** (170 at the DBG-s5 tip + 4 `ContentOverlayUITests` from main = 174 at `d20f673`, + 3 ZTron-page cases + the skipped harness test), 166 passed, 6 skipped, 6 failed in 84 min at load 870–1000:
  `RefreshUITests.testOverlayPullSpinsAndRests`, `TargetsUITests.testNativeAndZTronTargetVelocityUnits`, `SheetUITests.testA4_native` / `testC2_ours` ("No matches found" for `sheet.present`), `PanUITests.testSliderDragWorksAgainAfterTheContentMoved` (the fling scrolled 0), `ContentOverlayUITests.testCounterScaledMarkerKeepsItsScreenSize` (65 > 2).
  None touches this change; **all six passed when re-run alone, 2 iterations each (12/12, 4 min, load 600)**, so they are load flakes (the first four are the families DBG-s5 listed). The whole suite on the other OS was not repeated: nothing under `Sources/` changed.
- Harness: `MixedProbeUITests` skipped in the suite (1 of the 6 skipped); every table above came from it or from `MixedTopologyUITests` and is in the side-session notes folder `…/local_fd7eeb70-cef8-4557-bac5-ae8edd2d6acf/dbg-s8/` (outside the repo): `results-all.txt` (every lane's summary and `MIXV` / `MIXED` lines, host load per run), `traces/` (the KVO + call-stack logs quoted above: plain, simultaneous drag 26.5 / 18.5, tap, never-recognized drag, self-cancelling drag, the velocity cases), `scripts/` (`lane3.sh`: clone, run configs, delete the clone; `ONLY=ALL` = the whole suite).
Usage: not measured.
