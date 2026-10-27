# UIKIT-pan · An opt-in recognizing UIKit pan for two approved scenarios (D60; design, answers recorded; U1 done in UIKITPAN-s1; next: U2)

**Decision (user, 2026-10-27).** A UIKit pan recognizer is approved for exactly two scenarios, both with 100 % test coverage:
- **N**: a `ZTronScrollView` inside SwiftUI's own vertical `ScrollView` on iOS 26+. This is Open item 13(a): today the page never scrolls
  under a drag that starts on the ZTron view (D47 / DBG-s8).
- **S**: a pager inside a `.sheet`. Today a vertical drag on a horizontal pager never moves the sheet (D36).

It is a new SPEC S2 exception next to D31. ScrollArbitration stays frozen (S16), and S4 and S7 hold. Revised once after a three-lens
adversarial review: correctness, testability, and scope/API (31 findings, all folded in below).

**Opt-in (user, 2026-10-27, with the §9 answers).** The path exists only in views under one opt-in modifier,
`ztronScrollUIKitPan(_:)` (§3). A view without it runs today's code: no UIKit object, no new gesture, no detector. The §9
recommendations are accepted; the modifier replaces Q2's `.offAxis` overload and settles Q4.

Sources:
- this session's four reader reports: the gesture stack on main 9e60063; DBG-s8 on `claude/confident-babbage-6acfe7`; SHEET-s1/s2, DBG-s7
  (`claude/suspicious-elbakyan-3d1622`) and SHEET-s3 (`claude/sweet-payne-efd027`); the branch landscape and the coverage gates;
- MC-contract, UIKIT-touch-observer.md (D31, D33), ZTRONPAGES-integration.md.

No production code. The SPEC and CLAUDE.md are edited in U5 (§7).

## 1. Why a UIKit pan alone fixes neither scenario

**The failure.** A *recognized* SwiftUI drag under the finger takes the touch:
- In a native page (N): from the 26 SDK, the first recognizer to begin wins, and ties go to SwiftUI (D47).
- In a sheet (S): the sheet declines to move on 17.5, 26.x and 27.0 (D36). On 18.0–18.6 it shares the drag and both move (D46).

**Pan and observer are both such drags.** The touch observer is a recognized drag too: `SpatialEventGesture` on main's 18+, and the armed
`DragGesture(minimumDistance: 0)` on 15–17 (and 18–27 once D37 lands). Measured:
- a lone `SpatialEventGesture` blocks the native page (26.5, DBG-s8);
- the same freezes the sheet (27.0, SHEET-s1).

**Measured harmless:**
- in a native page: `MagnifyGesture`, `Button`, `Tap`, `LongPress` (DBG-s8);
- in a sheet: `MagnificationGesture`, `TapGesture(count: 2)` (P10, P11) and masked gestures. The library's own `MagnifyGesture` and
  `SpatialTapGesture` in a sheet are question Q6;
- the never-recognizing D31 observer (sheet, 17.5).

**So the "UIKit path" replaces both drags.** It is the D31 passive observer plus one recognizing UIKit pan. The pinch stays SwiftUI but is
used for recognition only: its values come from the observer. The double tap stays SwiftUI.

**What has to change, and what doesn't.** Arbitration rules (S16), the release physics, refresh and header code consume
`PanEvent` / `PinchEvent` and are not edited (`PanCoordinator.handle` l.176, `handlePinch` l.401, `synthesizePan` l.426). Three places do
change:
- **`PanSession`** gains `.declined` (§2).
- **`PanCoordinator`:** the yield gate drops events only for `.always`; `centroidSource` and the pinch value source follow the path latched
  at touch-down (§3).
- **`PinchGestureAdapter`:** the recognition-only switch follows that same latch.

## 2. The UIKit path

| Role | SwiftUI path (today, unchanged) | UIKit path |
|---|---|---|
| Pan | `DragGesture(minimumDistance: 10)` (`PanGestureAdapter.swift:88-110`) | one `UIPanGestureRecognizer`, axis-aware |
| Observer | `SpatialCatchGesture` 18+ · armed `DragCatchGesture` 15–17 · D31 on 15–16 | D31 recognizer + `TouchObserverCore`, every OS, `name` = `scrollArbitrationGestureName` |
| Pinch | `MagnifyGesture` / `MagnificationGesture` | same type, recognition only (values and centroid from the observer) |
| Double tap | `SpatialTapGesture(count: 2)` · `TapGesture` on 15 | unchanged. On 15 its location falls back to the visible centre, because `panStart` is written only by the SwiftUI pan |
| SwiftUI pan and observer | attached | still attached, disabled (`isEnabled: false` on 18+, `.subviews` below): the `yields` switch with a second input, so the structure never changes |

**Install.** Where the recognizer lives depends on the OS:
- **18+:** `UIGestureRecognizerRepresentable` through `.gesture(_:)` on the viewport. This is the DBG-s8 shape, and SwiftUI hit-tests it,
  so occlusion and covering bars behave like SwiftUI. It is attached only in an opted-in view whose scenario this OS and SDK can run
  (§3), with `isEnabled = false` unless the sequence's latch picks the UIKit path. The opt-in is latched per view, so the branch around
  the gesture modifier never flips and the content keeps its identity (S4).
- **15–17 (S only):** D31's window route. A zero-size anchor in `.background { if active { Anchor() } }` keeps the content's identity, and
  the anchor exists only while S applies (`.inSheet` latched, not yielding). A window recognizer bypasses SwiftUI hit-testing, so `shouldReceive(touch)` requires both "the
  touch began inside the viewport rect" and `anchor.isDescendant(of: touch.view)`. `isDescendant` is public UIKit, and `touch.view` is
  UIKit's own hit-test result. With that test, a sheet presented over the view and UIKit bars are rejected. A SwiftUI overlay inside the same
  hosting view still passes; that limitation is documented.
- **Both routes:** the shell's enable also reads `@Environment(\.isEnabled)`. A `.disabled` ancestor, and an outer ZTron view's D11 lock,
  therefore cancel this pan as they cut a SwiftUI one (this also keeps `.independent` intact, S12).

**Recognizer and delegate.** The recognizer is configured with:
- `maximumNumberOfTouches = 1`;
- `cancelsTouchesInView = false` (D11's `.disabled` still guards content controls);
- no delays;
- touch types `.direct` and `.pencil`;
- `name = scrollArbitrationGestureName`.

The delegate reads the `g` argument, never `self`, so a test subclass can inject translation and velocity. Its answers:
- `shouldRecognizeSimultaneouslyWith`: `true` for `other.name == scrollArbitrationGestureName` (nested ZTron views and ZTronPages UIKit
  pagers, S16). For any other recognizer it is spike variable **V**: always `true` (the measured FB18199844 shape), always `false`, or `true`
  except while this pan has taken a drag along the detected scroller's axis. Q2/Q3 pick the variant for which exactly one of the page/sheet
  and the ZTron view moves, in every row.
- `shouldRequireFailureOf` and `shouldBeRequiredToFailBy`: `false`.
- `gestureRecognizerShouldBegin`: the core's decision. A `false` answer is also the only source of `.declined`, because UIKit sends no
  action for `.failed`.

**Axis rule (pure core).** A view *can move on* an axis iff `axes.contains(axis)` and at least one of these holds:
- its bounds are scrollable on that axis;
- its bounce behaviour is `.always`;
- `alwaysBounce` is set for that axis;
- a refresher bounces it on that axis.

The core is given those raw inputs. It never uses `env.bouncesX` / `bouncesY`: `.automatic` makes them true for every declared axis, so a
1× zoomer would take every drag.

The dominant axis comes from the translation when its length is ≥ 8 pt, otherwise from `velocity(in:)`, because the first call can come at
0–1 pt (ZTRONPAGES note B). The boundary is 45°, and a tie goes to the other axis. It is one constant on every OS and speed (C2, user
2026-10-28). In N this is a documented deviation from native, whose nested boundary moves with OS and speed (UIKITPAN-s1 Q3 / Q3e). Inside
the band, native hands the drag to the inner scroll view and a ZTron view hands it to the page:
- **horizontal ZTron view:** drags of 50–70° from horizontal on 26.x and 50° on 27.0, mostly fast ones (slow drags match native);
- **vertical ZTron view:** drags of 10–40° from horizontal on 26.x and 30–40° on 27.0 (below 30° native moves nothing on 27.0).

Precedence, first match wins:
1. **Decline everything** if the view is disabled, if it yields to the sheet, if `\.isEnabled` is false, or if the observer has counted ≥ 2
   touches in this sequence (see "Second finger").
2. **Participant of a one-axis container** (nested ZTron view, `env.hasArbiter`): accept a drag more than the container's tolerance (30°)
   off its paging axis when the view can move on the cross axis. Rule 1 gives that drag to this view, so declining it would leave it dead:
   the review's 30–45° hole on a list page.
3. **Otherwise:** accept iff the view can move on the dominant axis. This is axis-level: at an edge the view keeps the drag and rubber-bands,
   so rule 5 still decides ZTron-in-ZTron.
4. **Same axis as the detected native scroller (N):** if V cannot make "exactly one moves" hold for a scrollable same-axis view (Q3), that
   view stays on the SwiftUI path, which already gives native nesting parity on 26+ (list 50, page 0; DBG-s8). Only a view that cannot move
   on the page's axis then takes the UIKit path. This is decided by S2's "match native", not asked.

**Decline (`PanEvent.declined`, new).** The shell emits it when `shouldBegin` answers `false`. The core forwards it once per sequence. What
it does depends on the session:

| Session state | Effect |
|---|---|
| `touching(caught: true)` | zero-velocity settle (paging and targets snap; plain views stay) on the state clock, with **no** drag delegate callbacks (`willBeginDragging` never fired); clears `caughtUndecided` |
| `touching(caught: false)` | nothing until `touchesEnded` |
| `awaitingDecision` | nothing until `touchesEnded` |

In every state the arbiter is told: an internal `NestedScrollArbiter.participantDeclined(token)` marks the token for the rest of the
sequence, so `containerOwner` resolves past it, to `.container` when nobody else is under the point. A 30–45° drag on a 1× zoomer page then
pages instead of dying, and rule 3 cannot hand a caught swipe back to a view that declined. This is additive and internal; the frozen
protocol is unchanged. An external arbiter, such as a UIKit-hosted pager, is not told, and its rule 1 still picks a declined participant.
That is documented (T3 is a recipe only).

**Mapping (pure `UIKitPanCore`, Foundation only).** The shell's action is one line:
`core.handle(stateRaw:translation:velocity:time:)`. Every raw state is an arm of the core's truth table, unknown values included:

| Raw state | Emits |
|---|---|
| began / changed | `.dragChanged(translation, startLocation, time)` |
| ended | `.dragEnded(translation, time, fallbackVelocity: velocity)` |
| cancelled | `.cancelled` (dropped once after the core's own reset) |
| possible / failed / unknown | nothing |

`time` is `Date().timeIntervalSinceReferenceDate` at delivery: the clock D31 and `SpatialCatchGesture` already use, one clock for samples
and lift (D14). A start sample shorter than the hysteresis is harmless, because `PanSession.baseline` credits only `|t₀| − h`.

**Second finger.** When the observer reports ≥ 2 touches in a sequence:
1. An active pan gets `.dragEnded` exactly once.
2. The shell resets the recognizer (`isEnabled` off and on).
3. The core swallows the `.cancelled` that the reset itself produces.
4. `shouldBegin` answers `false` until every touch lifts, so the remaining finger always runs through `synthesizePan` and the
   `touchesEnded` → `dragEnded` conversion (`PanCoordinator.swift:197-201`). That is the 18+ shape.

A unit test pins that `heldRelease` (D29) is never set on this path. On 15–17 the SwiftUI `DragGesture` survives a second finger instead;
the UIKit path deliberately uses the 18+ shape on every OS.

## 3. Activation: the opt-in, then exactly the approved scenarios

**The opt-in (user, 2026-10-27).** One public modifier gates the whole path. It is environment-backed, so it propagates, and the innermost
value wins:

```swift
public struct ZTronUIKitPan: OptionSet, Sendable {
    public static let inNativeScrollView: ZTronUIKitPan   // N
    public static let inSheet: ZTronUIKitPan              // S
}
extension View {
    public func ztronScrollUIKitPan(_ scenarios: ZTronUIKitPan) -> some View
}
```

- The environment default is `[]`. There is no default argument: the app names each scenario, and `[]` turns the path off in a subtree.
- **Latched per view.** The set is read once, at the view's first body evaluation, into a `@State` reference box (a plain final class, so
  storing the value triggers no update and no second body). A later change applies to views created after it. A live view keeps its set,
  never re-runs a content body for it and never resets content state. In DEBUG it logs once when the environment and its latch differ.
- `ztronScrollYieldsToSheet(_ yields: Bool)` is unchanged and stays live. There is no `ZTronSheetYield`.
- It lives in `Gesture/UIKit/ZTronUIKitPanOptIn.swift` (SwiftUI only), so C1's folder rule covers it.

What a view builds, by latched set:

| Latched set | 15–17 | 18–25 | 26+, built with the 26 SDK |
|---|---|---|---|
| `[]` (the default) | today's code | today's code | today's code |
| `.inSheet` | window pan + D31 observer while not yielding | representable pan (disabled until a sequence picks it) + D31 observer while active | as 18–25 |
| `.inNativeScrollView` | today's code | today's code | representable pan + detector leaf; D31 observer while N holds |
| both | as `.inSheet` | as `.inSheet` | the union of the two rows |

"Today's code" means byte-identical structure: no recognizer, anchor, detector or new modifier. On 26+ built with an older SDK,
`.inNativeScrollView` builds nothing, as on 18–25. The DEBUG counter `uikitpan.made` (recognizers and anchors created) proves it on every
existing screen (§6 C3).

**Per sequence.** The decision is latched per sequence at the observer's touch-down, never mid-sequence. This replaces R6's fixed-at-init
rule for three reads only: the pinch recognition-only switch, `centroidSource` and the yield gate. First match wins:
1. yielding to the sheet (`ztronScrollYieldsToSheet(true)`) → inert (SHEET-s2 unchanged);
2. `.inSheet` latched → UIKit path (S);
3. `.inNativeScrollView` latched and N holds → UIKit path (N);
4. otherwise → SwiftUI path.

N holds when all of these are true:
- the app was built with the iOS 26 SDK or later (`#if compiler(>=6.2)`, the `isInBuildSDK` pattern of `ZTronCapability.swift:103-106`). D47
  is gated by the linked SDK, and the package's tools-version 6.0 also builds with older Xcodes;
- `#available(iOS 26, *)`;
- `onGeometryChange(for: Bool.self) { $0.bounds(of: .scrollView(axis: .vertical)) != nil }` (iOS 17 API), on a leaf in the viewport's
  background, reports true. Its action runs only when the Bool flips, so nothing is per frame;
- the same-axis clause of the axis rule allows it.

N is vertical-only: the approved scenario is SwiftUI's own vertical `ScrollView`. Horizontal scrollers, `List`, `Form` and `TabView(.page)`
stay off (§9 Q3); U1's Q4 table records what they would detect, for a later widening.

**Flips.** A flip of the yield or of the detector re-runs the adapter body once, never the content's (SHEET-s2 precedent; C3 asserts
`content.body` 0 on every flip). A drag in flight on the path being switched off ends like a cancelled touch. A change of the opt-in is not
a flip: the latch ignores it.

**S, set by the app.** The app writes `.ztronScrollUIKitPan(.inSheet)` once, on the pager or on the sheet's root. Every ZTron view below it
takes the path, because each one's observer would otherwise hold the sheet (§1). At every detent:
- **Horizontal pager:** vertical drags go to the sheet (expand at medium; collapse or dismiss at large); horizontal drags page.
- **Vertical ZTron list page:** keeps its vertical drags. D36's "no top-edge hand-off" stays documented. Drags of 30–45° are the list's
  (rule 1, axis rule step 2), and flatter drags page.
- **1× zoomer** (fits on both axes):
  - drags within 45° of the pager's axis page (a declined participant is skipped);
  - steeper drags go to the sheet;
  - once zoomed it pans, and D28 arbitrates against the pager.

ZTronPages cannot detect a sheet and never sets the opt-in itself: that would put the UIKit pan on every pager, outside S. Its docs show
the one line. `.inSheet` outside a sheet is allowed (the A/B lane uses it); a vertical drag on a horizontal view then moves nothing, as
today. On iOS 15 there are no detents (`presentationDetents` is 16+), so S there means dismissal only.

## 4. Spike first (U1)

U1 must answer these before anything is built. The library's D31, `PanEvent` and coordinator are internal, so the probe stack is demo-only,
in `Demo/ZTronScrollViewDemo/Probes/` (DBG-s8 precedent, §9 Q6):
- a copy of the passive observer;
- a demo pager whose x offset the probe pan drives (snap on `.ended` and on decline; body re-runs are acceptable in a probe);
- the library's own pinch and double-tap types.

The readout gains:
- an x channel: `offX`, `offXMin/Max`, `bothX`, `page`;
- counters: `uikitpan.shouldBegin.yes/no`, `.began`, `.changed`, `.ended`, `.cancelled`, `.declined`, `.reset`.

Every question has a pass criterion:

| Q | Question | Lanes | Pass |
|---|---|---|---|
| Q1 | Declining pan + observer + library pinch/double tap over horizontal paging content in a sheet; vertical drags at medium and at large | 17.5, 18.5, 26.5, 27.0 | sheet expands / collapses / dismisses as the no-gesture pane (P5); pager x range ≤ 0.5 pt |
| Q2 | Horizontal drag in the sheet, per variant V; also on a zoomed zoomer page, mid-content and at its edge | same | page index +1 (or the zoomer pans, per the arbiter), `topMin == topMax`, not dismissed, no frame where top and pager x both move > 0.5 pt |
| Q3 | N with the representable route, per variant V, D31 installed: carousel (cross-axis), list (same axis), 1× zoomer, at 0° / 40° / 50° / 90° and 150–2500 pt/s; native carousel and native list baselines | 26.0.1, 26.1, 26.2, 26.5, 27.0 | exactly one of page and ZTron view moves in every row, matching the native baseline's choice |
| Q4 | `bounds(of: .scrollView(axis:))` read inside a ZTron viewport within: native vertical and horizontal `ScrollView`, `List`, `Form`, `TabView(.page)`, a sheet, a ZTron outer | 26.5, 27.0 | table recorded (it feeds §9 Q3) |
| Q5 | `UIPanGestureRecognizer` begin distance; first `shouldBegin` translation; lift order (observer `touchesEnded` vs the pan's `.ended`); a second touch at `maximumNumberOfTouches = 1` | all lanes | recorded; the 8 pt switch and the swallow rule confirmed |
| Q6 | The library's `MagnifyGesture` and `SpatialTapGesture` alone in a sheet | 17.5, 26.5, 27.0 | the sheet moves |
| Q7 | Controls on the UIKit path (Button tap, drag from a Button, Slider, Toggle, TextField, wheel, Stepper, segmented Picker); `.disabled` ancestor; drags from a nav bar, a tab bar, a pinned header | 17.5, 26.5, 27.0 | taps fire; drags do not fire controls; control drags stay the control's; covered or disabled → pan 0 |
| Q8 | 18.x regime (D46) with the UIKit path in a sheet | 18.0, 18.5, 18.6 | no frame where top and pager x both move |
| Q9 | Covered view: a sheet over an N carousel (plain, and the S pager), drag horizontally over the carousel's rect | 26.5, 27.0, 17.5 (window route) | carousel `cx` 0, its `uikitpan.began` 0 |

If Q1 or Q2 fails on a lane, S has no UIKit-pan answer on that OS: report it and stop for that OS. If no variant V passes Q3 for the same
axis, axis-rule step 4 applies.

## 5. Build sessions (after U1)

| Session | Owns | Done when | Est. |
|---|---|---|---|
| **U1** spike (Opus) | `Demo/…/Probes/*`, sheet and native-page probe screens (port DBG-s8 `MixedProbe` / `MixedTopology`), readout counters, handoff `UIKITPAN-s1.md` | Q1–Q9 answered with numbers per lane | 2.5–3 % |
| **U2** core (Sonnet builder) | `Gesture/UIKit/UIKitPanCore.swift` (axis rule, raw-state table, second finger, swallow, decline), `PanSession.swift` (`.declined` transitions, settle effect), `NestedScrollArbiter.swift` (`participantDeclined`), unit suites | 100 % kind-0 regions from unit tests alone; exhaustive truth tables | 2–2.5 % |
| **U3** shell + wiring (Sonnet builder) | `Gesture/UIKit/UIKitPanRecognizer.swift` (both routes), `PanGestureAdapter.swift` (opt-in latch read, second input to the `yields` switch, detector leaf, representable attach), `PanCoordinator.swift` (latch, yield gate, `centroidSource`), `PinchGestureAdapter.swift` (recognition-only per latch), `ZTronCapability` / `ZTronAvailability` (`.uikitPan`, SDK gate), `Gesture/UIKit/ZTronUIKitPanOptIn.swift` (option set, modifier, environment key, latch box, DEBUG `uikitpan.made`), shell tests on a real `UIWindow`, both gate scripts (+ a gate self-test) | unit suites green on 17.5 / 18.5 / 26.5 / 27.0; scope gate clean | 4–5 % |
| **U4** demo + UI matrix (Sonnet builder; lanes via test-runner) | `NativePageScreen` + `UIKitPanUITests` (DBG-s8's strict test passes opted in; its `XCTExpectFailure` stays for the row without the opt-in), sheet pager content + `SheetPagerUITests`, `UIKitControlsContent` on both paths, covered-view screens, native baselines | §6 matrix green; coverage gate 100 % | 4–5 % |
| **U5** docs (clerk) | SPEC S2, S3, S8, S11, S12 and S14 (§7 text), NESTED §6.1, SHEET-spike, parity rows, Orchestration (item 13 closed, D47 texts, D60, renumber the duplicate D47), ZTRONPAGES §5 items 3–4 | — | 0.5–1 % |

Order: U1 → U2 → U3 → U4 → U5 (U5 can draft in parallel). Total ≈ 13.5–16.5 % (the opt-in adds ≈ 0.5 % to U3).

Neither session touches `Packages/ScrollArbitration` or `ZTronScrollPhysics`. The unmerged D34/D37 (confirmed) and D40 / SHEET-s3's D47
(unconfirmed) rewrite the same `GestureAttach` switch (6 conflict hunks against main). Settle their merge before U3 (§9 Q7). The UIKit path
does not depend on them, because it disables the SwiftUI observer.

## 6. "100 % test coverage": definition and gates (accepted, §9 Q5)

**C1 · code.** Every file under `Sources/ZTronScrollView/Gesture/UIKit/` (the new files and D31's) at 100 % kind-0 regions, lines and
functions. The total is the union of the unit run and the coverage lanes below.
- Swift emits no LLVM branch counters. Regions do give `??` and `||` right-hand sides, ternary arms and one-line `guard`-`else` bodies their
  own regions (measured on the 27.0 profile).
- So the gate also requires every `&&` / `||` right-hand-side region to run on both outcomes: 0 < count < the count of the enclosing
  condition.
- D31's `?? .zero` (`UIKitTouchObserver.swift:50`) becomes a `guard`, with a deallocated-coordinator shell test.
- The opt-in file is unit-tested on its own: environment default `[]`, innermost value wins, first value wins in the latch box, the
  DEBUG log fires once.

Gate mechanics for `scripts/coverage-uikit.sh`:
- `build-for-testing` once per lane, every run and re-run as `test-without-building` into that lane's folder;
- `llvm-profdata merge` of every `Coverage.profdata` in a folder (today the script takes only the newest, so a re-run silently replaces a
  lane);
- `llvm-cov export -format=text`, regions keyed by (file, range), maximum over duplicate records;
- a recursive glob;
- regions only the unit run covers are listed (D33).

The scope gate's `SCOPED` regex also matches UIKit type names (`UIView`, `UIWindow`, `UITouch`, `UIGestureRecognizer…`,
`UIPanGestureRecognizer`, `UIGestureRecognizerRepresentable`), because SwiftUI re-exports UIKit. A self-test proves that a SwiftUI-only file
using one of them fails the gate.

**C2 · not reachable by XCUI.** These are covered by direct calls on a real `UIWindow` (D33 precedent) and listed by the gate:
- delegate methods UIKit never calls;
- the second-finger reset: XCUI cannot land a finger during a one-finger drag.

The real `.cancelled` route is deterministic: a DEBUG timer flips `ztronScrollYieldsToSheet` from false to true during a held XCUI drag. UIKit cancels a recognizer
whose `isEnabled` goes false, and `.cancelled` passes the yield gate.

**C3 · behaviour.** One strict UI test per cell, with a native baseline where one exists (a native carousel or list in the page; a native
paging `ScrollView` in a sheet, 17+). Angles are strict at 40° and 50°, while 44° and 46° are printed only: they sit 0.27 pt from the tie at
XCUI's first sample.

| Scenario | Topologies | Drags and checks |
|---|---|---|
| N | under `.inNativeScrollView`: horizontal ZTron carousel, vertical ZTron list, zoomer at 1× and zoomed, `ztronScrollDisabled(true)` carousel, `UIKitControlsContent`, a sheet over the carousel, nav / tab bar overlap | vertical, horizontal, 40°, 50° at 150–2500 pt/s; drag from a Button; tap; pinch (one `pinch.began`, focal error ≤ 30 pt, also after a flip); catch during the carousel's deceleration, then a vertical drag; `content.body` 0 |
| S | horizontal pager (1× zoomer, zoomed zoomer, list, Buttons, `UIKitControlsContent`) at medium and large, `.inSheet` | vertical (expand, collapse, dismiss); horizontal (page +1, `topMin == topMax`); 35° and 40° on the list page (list scrolls, pager 0); 35° on the Button page (pages); zoomer at its edge per the arbiter; catch during a page settle, then a vertical drag (page snaps, sheet moves); mid-drag flip (DEBUG timer); `.independent` row |
| A/B release | a non-paging horizontal carousel with and without `.ztronScrollUIKitPan(.inSheet)` (a demo launch argument), on 18.5 | flings at 600 and 1500 pt/s, no hold; final position read at `phase == idle`; \|Δ\| ≤ max(5 %, 8 pt) over 3 runs. A native carousel is printed as a reference only, with tolerance from the parity row D49 settles on |
| Opt-in gate | every N and S topology without the modifier; an inner `ztronScrollUIKitPan([])` under an opted-in sheet; `.inNativeScrollView` alone on 17.5 and 18.5 | today's behaviour (N: page 0 under a ZTron drag, DBG-s8's expected failure kept for this row; S: sheet frozen, D36); `uikitpan.made` 0. Latch: switch the opt-in on and off after the view appears, then drag: nothing changes, `content.body` 0, one DEBUG log; re-present the sheet: the new set applies |
| Regression | every existing suite, without the opt-in | full unit suite and full demo UI suite; `uikitpan.made` 0 at every suite's end (one shared teardown check) |

**Lanes.** Private clones, staggered starts, 26.0 run alone:

| Purpose | What runs |
|---|---|
| Coverage | unit on 17.5, 18.5 and 27.0; new UI suites on 17.5, 18.5, 26.5 and 27.0, preferred and forced |
| Behaviour only | N suite on 26.0.1, 26.1 and 26.2; S suite on 18.0 and 18.6 |
| Full regression | 17.5, 18.5 and 27.0 × 2 paths (≈ 8–9 h at today's load) |

`-ZTronForceAllFallbacks` does not turn the UIKit path off. Forced lanes run it with every other fallback forced (D31 observer,
`MagnificationGesture`, `TapGesture`), which is the 15–16 shape on 17.5. This is an explicit exception to D31 R4 while the path is active.
There is no force flag for this path: lanes opt in through the demo screens, as apps do.

**C4 · not runnable here.** Reported by the gate as "user run", never as passed:
- iOS 15/16 (macOS 27): the 15-only arms are the `TapGesture` double tap at the visible centre, and the sheet without detents;
- real fingers;
- a second finger landing during a UIKit pan (D20/D23/D25/D29 order), together with Open item 8's device check.
- a build with an SDK older than iOS 26 run on 26+: `.inNativeScrollView` must build nothing there (the other `#if compiler` arm),
  unless an Xcode 16.x is installed on this Mac.

## 7. SPEC S2 amendment and CLAUDE.md text (applied in U5)

> **Amendment 2026-10-27 (user, D60): the opt-in UIKit pan.**
> - **Replaces, for N and S only,** D31's "only on iOS 15.0–16.x", "never for … gesture recognition", "runs only under
>   `#unavailable(iOS 17)`" and "iOS 18+ keeps `SpatialEventGesture`".
> - **Opt-in.** Only a view under `ztronScrollUIKitPan(_:)`, with a scenario that its OS and SDK can run, builds any of this. Every other
>   view keeps the pure-SwiftUI structure. The set is latched per view at its first body.
> - **Scenarios.** (N) `.inNativeScrollView`: iOS 26+ in apps built with the iOS 26 SDK or later, for a view inside SwiftUI's vertical
>   `ScrollView` (detected with `bounds(of: .scrollView(axis: .vertical))`). (S) `.inSheet`: iOS 15+, declared by the app, because a sheet
>   cannot be detected.
> - **Allowed in `Sources/ZTronScrollView/Gesture/UIKit/`:**
>   - one `UIPanGestureRecognizer` per opted-in view (one touch, cancels and delays nothing, named `scrollArbitrationGestureName`,
>     simultaneous at least with every recognizer of that name, `shouldBegin` decided by the pure core);
>   - installed through `UIGestureRecognizerRepresentable` on 18+, attached disabled and enabled per sequence;
>   - installed by D31's anchor and window route on 15–17, present only while S applies, with `shouldReceive` requiring
>     `anchor.isDescendant(of: touch.view)`;
>   - the D31 observer on every OS while the path is active, also named.
> - **Deviation (N).** One 45° axis boundary on every OS. Native's nested boundary moves with OS and speed, so drags of 50–70° on a
>   horizontal view and of 10–40° on a vertical view go to the page, where native gives them to the inner scroll view (§2).
> - **Flags.** None for this path. `-ZTronForceAllFallbacks` leaves it on.
> - **Gates.** 100 % kind-0 regions, lines and functions over the lane union, plus the widened scope gate.
> - **Still forbidden:** `UIScrollView`, `UIHostingController`, matching recognizers by class or private name, our own superview or class
>   walks, private API.

CLAUDE.md's non-negotiable predates D31 as well. U5 replaces its second sentence with (§9 Q6, accepted):

> No AppKit, CADisplayLink, reflection or private API. UIKit and `*Representable` only in `Sources/ZTronScrollView/Gesture/UIKit/`
> under SPEC S2's exceptions (D31's touch observer, D60's opt-in pan), and in demo probes and samplers.

## 8. Risks

- **R1.** S rests on unmeasured UIKit behaviour: how the sheet's private flex interaction treats a pan that fails, or one that begins. Q1,
  Q2 and Q8 decide. If they fail, S stays D36 on that OS.
- **R2.** Simultaneity with non-ZTron recognizers can produce double motion: the page's own pan (same axis, diagonals), the two
  `_UIFlexInteraction` pans that 26 and 27 put on every window, wheels and Sliders. V and the Q3 / Q7 rows decide, and step 4 is the measured
  fallback.
- **R3.** The representable's interplay with SwiftUI masks, `.disabled` and hit-testing is unmeasured (Q7 and Q9). The window route keeps
  the same-hosting-view overlay limitation.
- **R4.** Detection arrives after the first layout, so a drag in the very first frame takes the SwiftUI path, which is today's behaviour.
- **R5.** UIKit sample cadence and velocity: the A/B lane measures them, they are not assumed.
- **R6.** A tap during a page settle leaves the pager between pages on the SwiftUI path (`PanSession.swift:121-123`). That needs a separate
  parity check against native. The UIKit path settles on decline.
- **R7.** Merge entanglement (§5) and the duplicate D47 numbers: U5 renumbers one.
- **R8.** Lanes are costly and flaky under host load (300–1000): ≈ 8–9 h of regression plus the coverage and behaviour lanes. Use private
  clones and read every flake against load.
- **R9.** The opt-in is static per view. An app that toggles it at runtime sees no change on live views (a DEBUG log says so). Apps
  that never opt in keep D47 and D36 as documented limitations; ZTronPages' docs show the `.inSheet` line.

## 9. Questions and the user's answers (2026-10-27)

The user accepted every recommendation and added the opt-in gate (§3).
1. **OS range of S:** 15+, the window route on 15–17 (17.5 runs it here; 15/16 are the user's runs, dismissal only on 15). Accepted.
2. **API for S:** superseded by the opt-in: `.ztronScrollUIKitPan(.inSheet)`. There is no `ZTronSheetYield`, and the Bool
   `ztronScrollYieldsToSheet` is unchanged.
3. **N parents:** SwiftUI's vertical `ScrollView` only. Accepted. Widening needs a new decision after U1's Q4 table; it would also turn
   ZTRONPAGES T4 from "unsupported" into "UIKit path".
4. **Inert recognizer on 18+:** settled by the opt-in. The disabled recognizer exists only in opted-in views, and runtime detection stays.
5. **100 % definition:** C1–C4 (§6), plus the opt-in gate rows. Accepted.
6. **UIKit in demo probes** for U1, and the CLAUDE.md wording (§7): accepted.
7. **Merge order:** land D34/D37 (confirmed) before U3: accepted. D40 and SHEET-s3's D47 (unconfirmed) had no recommendation and stay
   open. They edit the same `GestureAttach` switch, so they block U3, not U1 or U2.
8. **C2, the same-axis boundary in N (after U1, user 2026-10-28):** one 45° rule on every OS, with the band documented as a deviation
   from native (§2, §7). Per-OS constants (80° on 26.x, 60° on 27.0) were not taken, and neither option reproduces native's speed
   dependence. Axis rule step 4 never applies: V ctl gives "exactly one moves" for a same-axis view.
