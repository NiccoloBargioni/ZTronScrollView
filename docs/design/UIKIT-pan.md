# UIKIT-pan · An opt-in recognizing UIKit pan for two approved scenarios (D60; design, U1 folded in; C2 rule to confirm; next: U2 core)

**Decision (user, 2026-10-27).** A UIKit pan recognizer is approved for exactly two scenarios, both with 100 % test coverage:
- **N**: a `ZTronScrollView` inside SwiftUI's own vertical `ScrollView` on iOS 26+. This is Open item 13(a): today the page never scrolls
  under a drag that starts on the ZTron view (D47 / DBG-s8).
- **S**: a pager inside a `.sheet`. Today a vertical drag on a horizontal pager never moves the sheet (D36).

It is a new SPEC S2 exception next to D31. ScrollArbitration stays frozen (S16), and S4 and S7 hold. Revised once after a three-lens
adversarial review: correctness, testability, and scope/API (31 findings, all folded in below).

**Opt-in (user, 2026-10-27, with the §9 answers).** The path exists only in views under one opt-in modifier,
`ztronScrollUIKitPan(_:)` (§3). A view without it runs today's code: no UIKit object, no new gesture, no detector. The §9
recommendations are accepted; the modifier replaces Q2's `.offAxis` overload and settles Q4.

**Spike U1 (UIKITPAN-s1, done; corrections accepted by the user 2026-10-28).** S passed on every OS measured (17.5, 18.0–18.6, 26.5,
27.0). N gives "exactly one moves" once the pan shares touches only with its own name (V ctl). U1's corrections C1–C7 are folded in (§4 lists
where), with a narrow S2 allowance (§7). The N angle rule is open: the user answered C2 twice, 15 s apart, per-OS constants here and one
45° rule to the spike session (§9).

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
  `SpatialTapGesture(count: 2)` alone in a sheet (U1 Q6: 17.5, 26.5, 27.0);
- the never-recognizing D31 observer (sheet, 17.5).

**So the "UIKit path" replaces both drags.** It is the D31 passive observer plus one recognizing UIKit pan. The pinch stays SwiftUI but is
used for recognition only: its values come from the observer. The double tap stays SwiftUI.

**What has to change, and what doesn't.** Arbitration rules (S16), the release physics, refresh and header code consume
`PanEvent` / `PinchEvent` and are not edited (`PanCoordinator.handle` l.176, `handlePinch` l.401, `synthesizePan` l.426). Three places do
change:
- **`PanSession`** gains `.declined` (§2).
- **`PanCoordinator`:** the yield gate drops events only while the view yields to the sheet; `centroidSource` and the pinch value source follow the path latched
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
  (§3). UIKit binds a touch to the recognizers that are enabled when it begins, so the pan is enabled ahead of the touch (review M-3).
  `isEnabled` follows the path's static inputs: the opt-in latch, not yielding, `.inSheet` or the N detector, and `\.isEnabled`. The
  representable's update applies it when one of them flips. The SwiftUI pan and observer are disabled from the same inputs. The
  per-sequence latch (§3) only snapshots those inputs for the coordinator's three reads. The opt-in is latched per view, so the branch
  around the gesture modifier never flips and the content keeps its identity (S4).
- **15–17 (S only):** D31's window route. A zero-size anchor in `.background { if active { Anchor() } }` keeps the content's identity, and
  the anchor exists only while S applies (`.inSheet` latched, not yielding). A window recognizer bypasses SwiftUI hit-testing, so
  `shouldReceive(touch)` requires that the touch began inside the viewport rect and that one of these holds (U1 C3):
  - `anchor.isDescendant(of: touch.view)`;
  - `controllerRoot(anchor) === controllerRoot(touch.view)`, with both roots non-nil. `controllerRoot` walks `superview` until
    `next is UIViewController`, so it returns the root view of the nearest view controller. A walk that reaches the top without finding a
    view controller answers no, so two nil roots never match. It uses public UIKit only.

  `shouldReceive` forwards to `receives(hitView: UIView?, location: CGPoint, anchor: UIView) -> Bool`, which unit tests call on a real
  `UIWindow` (§6 C2).

  The second test is required. On 17.5, UIKit's hit view for the view's own drags is a SwiftUI drawing view beside the anchor, so the
  first test alone rejects them, in a sheet and on a plain screen. The class names U1 logged there are observed, never matched. Both
  tests reject a sheet presented over the view (Q9), and the bars lie outside the viewport rect. A SwiftUI overlay inside the same
  hosting view still passes: that is the pinned-header row that fails on 17.5, and the limitation is documented. This is the one
  superview walk that S2 allows (§7).
- **Both routes:** the shell's enable also reads `@Environment(\.isEnabled)`. U1 measured that this read is required (U1 C6): a `.disabled`
  ancestor disables neither the representable (26.5, 27.0) nor the window recognizer (17.5). With the read, a `.disabled` ancestor and an
  outer ZTron view's D11 lock cancel this pan as they cut a SwiftUI one (this also keeps `.independent` intact, S12).

**Recognizer and delegate.** The recognizer is configured with:
- `maximumNumberOfTouches = 1`;
- `cancelsTouchesInView = false` (D11's `.disabled` still guards content controls);
- no delays;
- touch types `.direct` and `.pencil`;
- `name = scrollArbitrationGestureName`.

The delegate reads the `g` argument, never `self`, so a test subclass can inject translation and velocity. Its answers are U1's winning
variant, **V ctl** (U1 C1):
- `shouldRecognizeSimultaneouslyWith`: `true` only for `other.name == scrollArbitrationGestureName`, that is the D31 observer, nested ZTron
  views and ZTronPages UIKit pagers (S16). It is `false` for every other recognizer. Sharing with them (the FB18199844 shape) moved the page
  and the view together at 40–90°, and Sliders and wheels together with the view (Q3, Q7). The D31 observer answers `true` itself, so it
  still sees every touch.
- `shouldRequireFailureOf(other)`: `true` iff `other.view is UIControl`. On 26+ a `UISlider` carries its own `UIPanGestureRecognizer`.
- `shouldBeRequiredToFailBy`: `false`.
- `shouldReceive(touch)`: `false` when `touch.view is UISlider` or `touch.view is UISwitch`, because on 17.5 a `UISlider` tracks touches
  with no recognizer. On the window route the receive rule above applies too. A drag that starts on any other `UIControl` pans, as in
  `UIScrollView`.
- `gestureRecognizerShouldBegin`: the core's decision. A `false` answer is also the only source of `.declined`, because UIKit sends no
  action for `.failed`.

Measured:
- V ctl passes every Q7 row on 26.5 and 27.0, and every row on 17.5 except the pinned header (the window route's overlay limitation);
- without the control rules (V off), a Slider drag stayed dead in 1 run of 5 on 27.0;
- V off passes S (Q1, Q2, Q8) and N's "exactly one moves" (Q3) on every lane. Q9 ran V axis.

V ctl ran only in Q7. Elsewhere it is inferred to equal V off, because no touch in those rows starts on a `UIControl`. U4's S and N
suites are its first measurement there.

**Axis rule (pure core).** A view *can move on* an axis iff `axes.contains(axis)` and at least one of these holds:
- its bounds are scrollable on that axis;
- its bounce behaviour is `.always`;
- `alwaysBounce` is set for that axis;
- a refresher bounces it on that axis.

The core is given those raw inputs. It never uses `env.bouncesX` / `bouncesY`: `.automatic` makes them true for every declared axis, so a
1× zoomer would take every drag.

**The direction vector (review F-3, M-1).** Step 2, the cones, `.askOwner` and the directional lock all read one *direction*: the
finger's displacement since the observer's touch-down, that is `location(in:)` in viewport space minus `startLocation`. They never read
UIKit's `translation(in:)`, for two reasons:
- **The translation is bent.** U1's Q5 rows fit a per-axis rule: UIKit subtracts its 10 pt hysteresis on each axis separately, so the
  translation bends toward the dominant axis. At 40° it read (1.7, 0) at 150 pt/s and (21.7, 16.3), that is 36.9°, at 2500 pt/s. A fast
  10° drag would read 0°.
- **It cannot be too short.** At UIKit's first `shouldBegin` the displacement is the whole travel: ≈ 10 pt or more (Q5: 10.3, 17.7 and
  41 pt at 150, 600 and 2500 pt/s).

`velocity(in:)` remains the fallback below 8 pt, for a sequence whose touch-down the observer missed. XCUI cannot produce one, so it is
listed in §6 C2. U1's probe decided with the translation or the velocity, so U4's sweep is the first measurement of the displacement
rule.

The translation stays the offset input (F1). `.dragChanged` gains an optional `direction` associated value, internal to the library and
nil on the SwiftUI path. `PanSession` stores it in `Pending` for the ask and the lock. U2's truth-table rows use Q5's measured vectors.

**Acceptance cones.** Each axis has a cone, a half-angle around it. A drag lies in the cone when its angle to that axis is strictly less
than the half-angle; a tie goes outside. The half-angles are:

| Where | Horizontal | Vertical |
|---|---|---|
| N holds (§3), iOS 26.x | 45° | 85° |
| N holds, iOS 27.0 and later | 45° | 65° |
| otherwise (S included) | 45° | 45° |

The table is keyed on whether N holds, not on which scenario picked the path. A view with both scenarios latched, inside a sheet's native
vertical `ScrollView`, takes the S path and the N cones. In N the page is vertical, so the horizontal cone is the one across the page's
axis.

The N values are per-OS constants (U1 C2 option b; whether (b) stands is open, §9 item 8). Each boundary sits halfway between two angles that U1 separated at slow speed, so no
measured row is a tie:
- **Across the page:** a native inner carousel took 40° and the page took 50° in the Q3e sweep, on both OSes. Q3 disagrees at 50°: there
  the carousel took 50° at 600 pt/s on every lane, and at 150 pt/s on 26.5 and 27.0, where slow 50° therefore split between runs (§6 C3
  prints it).
- **Along the page, 26.x:** a native inner list took every angle from 10° to 80° above horizontal (Q3e), and nothing moved at 0° (Q3), so
  85° puts the boundary at 5°.
- **Along the page, 27.0:** nothing moved at 20°, and the native list took 30°, so 65° puts the boundary at 25°.

U1 wrote option (b) as 80° and 60°, with ties inside, as its probe's `<=` had them. The design keeps ties outside, so the same rule reads
85° and 65° (review C-4). The two agree on every measured row and differ only at 5–10° (26.x) and 25–30° (27.0) above horizontal, which
no lane measured. U4's first N sweep is that measurement.

Later OSes use 27.0's value until a newer runtime is measured (R10). These are `#available` arms in the shell, and the pure core takes
the cone as an input. UIKit's dependence on speed is not reproduced. Medium and fast drags lock to the inner carousel at 50–70° on 26.x
and at 50° on 27.0, and on 27.0 a fast 30° drag moves neither the list nor the page (R11).

Precedence, first match wins:
1. **Decline everything** if the view is disabled, if it yields to the sheet, if `\.isEnabled` is false, or if the observer has counted ≥ 2
   touches in this sequence (see "Second finger").
2. **Participant of a one-axis container** (nested ZTron view, `env.hasArbiter`): accept a drag more than the container's tolerance (30°)
   off its paging axis when the view can move on the cross axis. Rule 1 gives that drag to this view, so declining it would leave it dead:
   the review's 30–45° hole on a list page.
3. **Otherwise:** accept iff the view can move on an axis whose cone holds the drag. This is axis-level: at an edge the view keeps the drag
   and rubber-bands, so rule 5 still decides ZTron-in-ZTron. A view that can move on both axes accepts every drag in N, as a native
   two-axis scroller does.

The earlier step 4 is gone (U1 C2). It sent a same-axis view back to the SwiftUI path when no variant gave "exactly one moves". U1 found
that V off gives exactly one in every row (V ctl is inferred to match).

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

`participantDeclined` assumes the participant's `shouldBegin` runs before the container's `.began` ask. U1 never measured that order.
U2 pins the reverse order with a unit row whose result is defined: the container's session revives when the participant declines after
the ask.

**Mapping (pure `UIKitPanCore`, Foundation only).** The shell's action is one line:
`core.handle(stateRaw:translation:velocity:time:)`. Every raw state is an arm of the core's truth table, unknown values included:

| Raw state | Emits |
|---|---|
| began / changed | `.dragChanged(translation, startLocation, time)` |
| ended | `.dragEnded(translation, time, fallbackVelocity: velocity)` |
| cancelled | `.cancelled`, unless the reset's swallow is armed (see "Second finger") |
| possible / failed / unknown | nothing |

The clock and the start point:
- `time` is `Date().timeIntervalSinceReferenceDate` at delivery. D31 and `SpatialCatchGesture` already use this clock, so samples and
  lift share one clock (D14).
- `startLocation` is the observer's touch-down location in viewport space, as `DragGesture.Value.startLocation` is on the SwiftUI path.
  It is not `location(in:)` minus the translation: that point sits ≈ 10 pt along the drag (Q5), and the arbiter resolves the owner by
  this point.

**Full credit of the first sample (F1, found while folding U1).** `PanSession.baseline` credits the recognition sample beyond the first
`h` = 10 pt, because SwiftUI's translation includes the gesture's hysteresis. UIKit's translation already excludes it (Q5).
- **Rule:** on the UIKit path, `beginDrag` builds the baseline from a zero translation, so the content moves by the whole `t₀` at
  recognition, as a `UIScrollView` does. A per-sequence input from the latch selects this.
- **Why:** the SwiftUI rule would hold the content 10 pt behind the finger for a whole fast drag (`t₀` ≈ 31 pt at 2500 pt/s).
- **Tests:** U2 pins both rules, and the A/B lane would show the difference.

**Lift (U1 C5).** The observer's `touchesEnded` comes before the pan's `.ended`, in the same event, on every lane. So the pan's `.ended` is the
release, with UIKit's velocity. Main already keeps it that way:
- a `.dragging` session ignores `.touchesEnded`;
- the coordinator converts `touchesEnded` into `dragEnded` only for a synthesized pan (`synthesizedPanStart != nil`,
  `PanCoordinator.swift:197-201`), and on the UIKit path that pan exists only after a reset.

U2 pins this ordering with truth-table rows. The defensive case has no XCUI route and is listed in §6 C2: an active pan with no `.ended` or
`.cancelled` before the next touch-down ends as `.cancelled`.

**Second finger.** When the observer reports ≥ 2 touches in a sequence:
1. An active pan gets `.dragEnded` exactly once.
2. The shell resets the recognizer (`isEnabled` off and on).
3. **The reset arms the swallow, not the timing (U1 C4).** The shell arms "drop the next `.cancelled`" only when the reset finds the pan in
   `.began` or `.changed`. U1 measured exactly one `.cancelled` per such reset:
   - on 17.5 and 18.x it arrives inside the `isEnabled = false` call;
   - on 26.x and 27.0 it arrives after that call returns, before the next main-queue turn.

   A reset in `.possible` produces nothing and does not arm. The arm clears when the sequence ends.
4. `shouldBegin` answers `false` until every touch lifts. U1 found that after a reset the finger still down never begins the pan again,
   and that two touches landing together never begin it (it stays `.possible`). The remaining finger runs through `synthesizePan` and the
   `touchesEnded` → `dragEnded` conversion. That is the 18+ shape.

A unit test pins that no release stays held (`heldRelease` is nil) after any `handle` call returns on this path. The converted lift sets
and applies it in the same call (`PanCoordinator.swift:338-341`, `261-268`). On 15–17 the SwiftUI `DragGesture` survives a second finger instead;
the UIKit path deliberately uses the 18+ shape on every OS. A second finger landing during an active pan cannot be scripted in XCUI; it
stays a device check (§6 C4).

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
| `.inSheet` | window pan + D31 observer while not yielding | representable pan (enabled while the path applies) + D31 observer while it applies | as 18–25 |
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
  background, reports true. Its action runs only when the Bool flips, so nothing is per frame. U1 Q4 (26.5, 27.0): only SwiftUI's own
  `ScrollView` sets it; `List`, `Form`, `TabView(.page)`, a sheet and a ZTron outer read nothing (U1 C7).

N is vertical-only: the approved scenario is SwiftUI's own vertical `ScrollView`. Horizontal scrollers, `List`, `Form` and `TabView(.page)`
stay off (§9 Q3). Widening them needs another detector, because `bounds(of:)` sees none of them (U1 C7).

**Flips.** A flip of the yield or of the detector re-runs the adapter body once, never the content's (SHEET-s2 precedent; C3 asserts
`content.body` 0 on every flip). The D31 observer's attach comes and goes with these flips. So U3 rewrites it in the anchor's form,
`content.background(alignment: .topLeading) { if enabled { Anchor() } }`, and no flip changes the content's structure (review C-8). A drag in flight on the path being switched off ends like a cancelled touch. A change of the opt-in is not
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

## 4. Spike U1 (done: UIKITPAN-s1, 2026-10-27)

U1 answered the nine questions on private simulator clones with a demo-only probe stack. Everything it produced is on
`claude/keen-lichterman-cfa1e6` (fa007c1, not merged):
- the handoff `docs/progress/UIKITPAN-s1.md`, and the full tables in `docs/progress/UIKITPAN-s1-tables.md`;
- the probes in `Demo/ZTronScrollViewDemo/Probes/`;
- the harness `UIKitPanProbeUITests` (it skips unless `ZS_UKP=1`) and `scripts/uikitpan-table.py`.

| Q | Question | Lanes | Result |
|---|---|---|---|
| Q1 | S, vertical drags declined: the sheet behaves as the no-gesture pane P5, pager x span ≤ 0.5 pt | 17.5, 18.0, 18.5, 18.6, 26.5, 27.0 | PASS on every lane, at both detents, for V on and V off |
| Q2 | S, horizontal: page +1; the zoomer pans mid-content and pages at its edge; top fixed, not dismissed, no double motion | same | PASS 8/8 for each V on every lane |
| Q3 | N, per V: exactly one of page and view moves; carousel, list, 1× zoomer; 0/40/50/90° at 150–2500 pt/s | 26.0.1, 26.1, 26.2, 26.5, 27.0 | Only V off gives exactly one in every row (V ctl inferred, §2); V on and V axis move both. Native boundaries differ by OS and speed (Q3e sweep) → per-OS cones (§2) |
| Q4 | What `bounds(of: .scrollView(axis:))` sees inside a ZTron viewport | 26.5, 27.0 | Only a native `ScrollView`, vertical or horizontal. `List`, `Form`, `TabView(.page)`, a sheet and a ZTron outer read nothing |
| Q5 | Begin distance, first translation, lift order, second touch, reset | all | Begins after ≈ 10 pt of travel, which the translation excludes; the 8 pt switch holds; the observer lifts before the pan's `.ended`; two touches never begin the pan; one `.cancelled` per reset of an active pan (synchronous on ≤ 18, asynchronous on 26+) |
| Q6 | The library's pinch and double tap alone in a sheet | 17.5, 26.5, 27.0 | PASS |
| Q7 | Controls on the UIKit path, `.disabled`, bars, a pinned header | 17.5, 26.5, 27.0 | V ctl passes every row on 26.5 and 27.0. On 17.5 every row passes except the pinned header (the window route's overlay limitation). `.disabled` needs the `\.isEnabled` read |
| Q8 | 18.x sharing (D46) with the UIKit path in a sheet | 18.0, 18.5, 18.6 | PASS: no frame where the sheet and the pager both move |
| Q9 | A sheet over an N carousel | 17.5 (window route), 26.5, 27.0 | PASS: the carousel stays at 0 and its pan never begins |

U1's corrections are folded into this design:

| Correction | What changed | Where |
|---|---|---|
| C1 | V ctl | §2, delegate |
| C2 | per-OS cones, with step 4 removed (user, 2026-10-28) | §2, axis rule |
| C3 | the window route's controller-root test | §2 install, §7 |
| C4 | the swallow is armed by the reset | §2, second finger |
| C5 | lift order | §2, lift |
| C6 | the `\.isEnabled` read is required | §2, install |
| C7 | detection sees only SwiftUI's `ScrollView` | §3, §9 Q3 |

F1 is not U1's. It came from applying Q5's numbers to `PanSession.baseline` (full credit of the first sample, §2).

U1 did not measure iOS 15 and 16 (no runtime here), a second finger landing during an active pan, or real fingers (§6 C4).

**Conflicting C2 record (review C-3).** U1's branch tip 0038ea9 records C2 option (a), one 45° rule, in its copy of this design (§2,
§7, §9 item 8), in its handoff and in Orchestration item 14. This design records option (b). The user gave the two answers 15 s apart
on 2026-10-27, (b) here and then (a) to the spike session. Which one stands is open (§9).

## 5. Build sessions

| Session | Owns | Done when | Est. |
|---|---|---|---|
| **U1** spike (Opus) | done: UIKITPAN-s1, `claude/keen-lichterman-cfa1e6` (fa007c1); §4 | Q1–Q9 answered per lane | done |
| **U2** core (Sonnet builder) | `Gesture/UIKit/UIKitPanCore.swift` (axis rule with the cone as an input, raw-state table, second finger, reset-armed swallow, decline, lift-order rows, dangling-pan cancel), `PanSession.swift` (`.declined` transitions, settle effect, F1 full-credit baseline per sequence), `NestedScrollArbiter.swift` (`participantDeclined`), unit suites | 100 % kind-0 regions from unit tests alone; exhaustive truth tables | 2–2.5 % |
| **U3** shell + wiring (Sonnet builder) | `Gesture/UIKit/UIKitPanRecognizer.swift` (both routes; V ctl delegate; `receives(hitView:location:anchor:)`; `#available` cone arms; observer touch-down as `startLocation`; the direction vector; `isEnabled` from the static inputs), `PanGestureAdapter.swift` (opt-in latch read, second input to the `yields` switch, detector leaf, representable attach, D31 observer attach in the anchor form), `PanEvent` (`direction`), `PanCoordinator.swift` (latch, yield gate, `centroidSource`), `PinchGestureAdapter.swift` (recognition-only per latch), `ZTronCapability` / `ZTronAvailability` (`.uikitPan`, SDK gate; `.uikitPan` is excluded from `forceAllFallbacks`, pinned by a unit test), `Gesture/UIKit/ZTronUIKitPanOptIn.swift` (option set, modifier, environment key, latch box, DEBUG `uikitpan.made`), shell tests on a real `UIWindow`, both gate scripts (+ a gate self-test) | unit suites green on 17.5 / 18.5 / 26.5 / 27.0; scope gate clean | 4–5 % |
| **U4** demo + UI matrix (Sonnet builder; lanes via test-runner) | `NativePageScreen` + `UIKitPanUITests` (DBG-s8's strict test passes opted in; its `XCTExpectFailure` stays for the row without the opt-in), sheet pager content + `SheetPagerUITests`, `UIKitControlsContent` on both paths, covered-view screens, native baselines | §6 matrix green; coverage gate 100 % | 4–5 % |
| **U5** docs (clerk) | SPEC S2, S3, S8, S11, S12 and S14 (§7 text), NESTED §6.1, SHEET-spike, parity rows, Orchestration (item 13 closed, D47 texts, D60, renumber the duplicate D47), ZTRONPAGES §5 items 3–4 | — | 0.5–1 % |

Order: U2 → U3 → U4 → U5 (U5 can draft in parallel). U2–U5 ≈ 11–13.5 % (the opt-in adds ≈ 0.5 % to U3). The probe harness on U1's
branch must reach U4: port the probes and the harness, or merge the branch with 0038ea9's doc hunks reconciled with this design. Its
native sweep rows are U4's baselines. U5 amends UIKITPAN-s1.md's C2 and Next lines to the C2 rule that stands.

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
`UIPanGestureRecognizer`, `UIGestureRecognizerRepresentable`, `UIControl`, `UISlider`, `UISwitch`, `UIViewController`, `UIResponder`),
because SwiftUI re-exports UIKit. A self-test proves that a SwiftUI-only file
using one of them fails the gate.

**C2 · not reachable by XCUI.** These are covered by direct calls on a real `UIWindow` (D33 precedent) and listed by the gate:
- delegate methods UIKit never calls;
- the second-finger reset: XCUI cannot land a finger during a one-finger drag. The swallow is tested with both timings: on the 17.5 and
  18.5 unit lanes the `.cancelled` comes inside the call, and on the 27.0 lane it comes after the call returns (U1 Q5);
- the dangling-pan cancel (an active pan with no `.ended` before the next touch-down);
- `controllerRoot` reaching the top without a view controller (a bare `UIWindow` with no root view controller);
- `receives(hitView:location:anchor:)` on a real `UIWindow`, one call per outcome: a hit view that is an ancestor of the anchor
  (`isDescendant` true), a sibling under the same controller root (root true), a view under another view controller (both roots
  non-nil, false), a bare window (nil root), a `UISlider`, a `UISwitch`, a nil view, and a location outside the rect;
- the direction's velocity fallback (no observer touch-down in the sequence).

The real `.cancelled` route is deterministic: a DEBUG timer flips `ztronScrollYieldsToSheet` from false to true during a held XCUI drag. UIKit cancels a recognizer
whose `isEnabled` goes false, and `.cancelled` passes the yield gate.

**C3 · behaviour.** One strict UI test per cell, with a native baseline where one exists (a native carousel or list in the page; a native
paging `ScrollView` in a sheet, 17+). The angles differ by scenario:
- **S:** strict at 40° and 50°. 44° and 46° are printed only, because they sit 0.27 pt from the tie at XCUI's first sample.
- **N:** U1's sweep, 10–80° above horizontal in 10° steps, at 150 and 2500 pt/s as Q3e ran it, compared with the native baseline on each
  lane. 0°, 40°, 50° and 90° also run at 600 pt/s, as Q3 baselined them. Every cell is strict except these, which are printed:
  - cells where native depends on speed: 50–70° for a carousel at 600 and 2500 pt/s on 26.x; on 27.0, 50° for a carousel at 600 and
    2500 pt/s, and fast 30° for a list;
  - the slow 50° carousel on 26.5 and 27.0, which split between runs.

  Fast 40° on the 27.0 list is strict, because native took it at both speeds. If U4 reproduces Q3f's miss there, it is a ZTron defect,
  marked `XCTExpectFailure` with a reason. Each measured angle lies ≥ 5° from a cone boundary for the direction vector (§2).

| Scenario | Topologies | Drags and checks |
|---|---|---|
| N | under `.inNativeScrollView`: horizontal ZTron carousel, vertical ZTron list, zoomer at 1× and zoomed, `ztronScrollDisabled(true)` carousel, `UIKitControlsContent`, a sheet over the carousel, nav / tab bar overlap | 0°, 40°, 50° and 90° at 150, 600 and 2500 pt/s, and the sweep above; drag from a Button; Slider drag and Toggle tap (V ctl: the control acts alone, page and view 0); tap; pinch (one `pinch.began`, focal error ≤ 30 pt, also after a flip); catch during the carousel's deceleration, then a vertical drag; a tap on a covering sheet and on the nav bar, during the carousel's deceleration and at rest (its pan never begins; whether the observer catches is printed, R3); the first drag after appear and after a detector flip moves the view (M-3); `content.body` 0 and content `@State` kept across a detector flip (C-8) |
| S | horizontal pager (1× zoomer, zoomed zoomer, list, Buttons, `UIKitControlsContent`) at medium and large, `.inSheet` | vertical (expand, collapse, dismiss); horizontal (page +1, `topMin == topMax`); 35° and 40° on the list page at 150 and 2500 pt/s (list scrolls, pager 0); 35° and 40° on the 1× zoomer page at 150 and 2500 pt/s (pages, zoomer 0); 35° on the Button page (pages); on 17.5, a sheet presented over an `.inSheet` view (its pan never begins) and the hosting view embedded as a child of an app view controller (R3); the first drag after appear and after a yield flip moves the pager (M-3); `content.body` 0 and content `@State` kept across a yield flip on 17.5 (C-8); zoomer at its edge per the arbiter; catch during a page settle, then a vertical drag (page snaps, sheet moves); mid-drag flip (DEBUG timer); Slider drag and Toggle tap on the controls page (V ctl); `.independent` row |
| A/B release | a non-paging horizontal carousel with and without `.ztronScrollUIKitPan(.inSheet)` (a demo launch argument), on 18.5 | flings at 600 and 1500 pt/s, no hold; final position read at `phase == idle`; \|Δ\| ≤ max(5 %, 8 pt) over 3 runs. During the drag, finger travel minus content travel is equal on both paths within 1 pt (F1: both lag by UIKit's or SwiftUI's ≈ 10 pt hysteresis only). A native carousel is printed as a reference only, with tolerance from the parity row D49 settles on |
| Opt-in gate | every N and S topology without the modifier; an inner `ztronScrollUIKitPan([])` under an opted-in sheet; `.inNativeScrollView` alone on 17.5 and 18.5; `.inNativeScrollView` on 26.5 and 27.0 inside `List`, `Form`, `TabView(.page)` and on a plain screen (N false: today's behaviour, `content.body` 0); both scenarios latched on 17.5, 18.5, 26.5 and 27.0, in a sheet and in a sheet's native vertical `ScrollView` (S path, N cones where N holds) | today's behaviour (N: page 0 under a ZTron drag, DBG-s8's expected failure kept for this row; S: sheet frozen, D36); `uikitpan.made` 0. Latch: switch the opt-in on and off after the view appears, then drag: nothing changes, `content.body` 0, one DEBUG log; re-present the sheet: the new set applies |
| Regression | every existing suite, without the opt-in | full unit suite and full demo UI suite; `uikitpan.made` 0 at every suite's end (one shared teardown check) |

**Lanes.** Private clones, staggered starts, 26.0 run alone:

| Purpose | What runs |
|---|---|
| Coverage | unit on 17.5, 18.5 and 27.0; new UI suites on 17.5, 18.5, 26.5 and 27.0, preferred and forced |
| Behaviour only | N suite on 26.0.1, 26.1 and 26.2; S suite on 18.0 and 18.6 |
| Full regression | 17.5, 18.5 and 27.0 × 2 paths (≈ 8–9 h at today's load) |

`-ZTronForceAllFallbacks` does not turn the UIKit path off: `.uikitPan` is excluded from it, like `.uikitTouchObserver` (U3 pins this).
Forced lanes run the path with the other fallbacks forced (`MagnificationGesture`; `DragCatch` in place of `SpatialCatch` on 18+). This
is an explicit exception to D31 R4 while the path is active.
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
>   - one `UIPanGestureRecognizer` per opted-in view: one touch, cancels and delays nothing, named `scrollArbitrationGestureName`;
>     `shouldBegin` is decided by the pure core;
>   - its delegate (D60 user allowance, 2026-10-28):
>     - simultaneous only with recognizers of that name;
>     - it requires the failure of a recognizer whose `view is UIControl`;
>     - it refuses touches whose `view is UISlider` or `is UISwitch`.
>
>     These are checks against public UIKit control types, never against a recognizer's class;
>   - installed through `UIGestureRecognizerRepresentable` on 18+, enabled while the path applies;
>   - installed by D31's anchor and window route on 15–17, present only while S applies, with `shouldReceive` requiring a touch inside
>     the viewport rect and either `anchor.isDescendant(of: touch.view)` or the same non-nil `controllerRoot`. That is a `superview`
>     walk until `next is UIViewController` (D60 user allowance, 2026-10-28; this route only);
>   - the D31 observer on every OS while the path is active, also named.
> - **Flags.** None for this path. `-ZTronForceAllFallbacks` leaves it on.
> - **Gates.** 100 % kind-0 regions, lines and functions over the lane union, plus the widened scope gate.
> - **Still forbidden:**
>   - `UIScrollView` and `UIHostingController`;
>   - matching recognizers by their class or by a private name, and matching any view by a private class name;
>   - every superview or class walk except `controllerRoot` above;
>   - private API.

CLAUDE.md's non-negotiable predates D31 as well. U5 replaces its second sentence with (§9 Q6, accepted):

> No AppKit, CADisplayLink, reflection or private API. UIKit and `*Representable` only in `Sources/ZTronScrollView/Gesture/UIKit/`
> under SPEC S2's exceptions (D31's touch observer, D60's opt-in pan), and in demo probes and samplers.

## 8. Risks

- **R1.** S rests on UIKit's private sheet interaction. U1 measured it on 17.5, 18.0–18.6, 26.5 and 27.0, where it passed. iOS 15/16
  and real fingers are not measured (§6 C4), and a new OS can change it: the S suite runs on every new runtime before release.
- **R2.** Double motion with non-ZTron recognizers. V ctl removed it in every U1 row: the page's pan, the sheet's pans, Sliders, wheels.
  A drag that starts on a `UIControl` other than a Slider or a Switch pans, as in `UIScrollView`. Controls in apps that track touches
  without a recognizer, as the 17.5 Slider does, could still move together with the view.
- **R3.** Hit-testing. U1 Q7 and Q9 measured both routes: covered views, the bars and `.disabled` (with the `\.isEnabled` read). The window
  route keeps the same-hosting-view overlay limitation (the pinned header on 17.5). `controllerRoot` assumes the view controller hierarchy
  that SwiftUI builds; a hosting view embedded as a child of an app's own view controller is a C3 row in U4. On the UIKit path the D31
  observer is a window recognizer filtered only by the viewport rect (D31 R1), on every OS. So a touch on a covering sheet, a bar or an
  overlay inside that rect starts a sequence and can catch a decelerating view, while the pan itself never begins there (review M-4). C3
  prints it. Applying `receives(…)` to the observer's touch-down would remove it, but that widens the walk's allowance from the pan to
  the observer.
- **R4.** Detection arrives after the first layout, so a drag in the very first frame takes the SwiftUI path, which is today's behaviour.
- **R5.** UIKit sample cadence and velocity: the A/B lane measures them, they are not assumed.
- **R6.** A tap, or a touch on a Slider or a Switch, during a page settle leaves the pager between pages on both paths
  (`PanSession.swift:121-123`). UIKit asks `shouldBegin` only after its hysteresis, so there is no `.declined`, and the UIKit path settles
  only on a declined drag. The parity check against native covers both paths.
- **R7.** Merge entanglement (§5) and the duplicate D47 numbers: U5 renumbers one.
- **R8.** Lanes are costly and flaky under host load (300–1000): ≈ 8–9 h of regression plus the coverage and behaviour lanes. Use private
  clones and read every flake against load.
- **R9.** The opt-in is static per view. An app that toggles it at runtime sees no change on live views (a DEBUG log says so). Apps
  that never opt in keep D47 and D36 as documented limitations; ZTronPages' docs show the `.inSheet` line.
- **R10.** The cones are measured constants. Q3e agreed on 26.0.1, 26.2 and 26.5 (Q3 differs on 26.5 at slow 50°), and 27.0 differs. An OS newer than 27.0 uses 27.0's values until it is
  swept, and the N suite's sweep rows catch a change. Each new runtime needs a U1-style Q3e sweep before release.
- **R11.** Native boundaries depend on speed:
  - medium and fast drags lock to the inner native carousel at 50–70° on 26.x and at 50° on 27.0;
  - on 27.0 a fast 30° drag moves neither the list nor the page, where a slow one moves the list.

  The cones reproduce the slow boundary only. Those cells are printed, not gated (§6 C3, the carousel and list cells both), and the
  difference is a documented deviation from S2's "match native".

## 9. Questions and the user's answers (2026-10-27)

The user accepted every recommendation and added the opt-in gate (§3).
1. **OS range of S:** 15+, the window route on 15–17 (17.5 runs it here; 15/16 are the user's runs, dismissal only on 15). Accepted.
2. **API for S:** superseded by the opt-in: `.ztronScrollUIKitPan(.inSheet)`. There is no `ZTronSheetYield`, and the Bool
   `ztronScrollYieldsToSheet` is unchanged.
3. **N parents:** SwiftUI's vertical `ScrollView` only. Accepted. Widening needs a new decision and another detector, because U1's Q4
   found that `bounds(of:)` sees no `List`, `Form` or `TabView(.page)`. It would also turn ZTRONPAGES T4 from "unsupported" into "UIKit path".
4. **Inert recognizer on 18+:** settled by the opt-in. The disabled recognizer exists only in opted-in views, and runtime detection stays.
5. **100 % definition:** C1–C4 (§6), plus the opt-in gate rows. Accepted.
6. **UIKit in demo probes** for U1, and the CLAUDE.md wording (§7): accepted.
7. **Merge order:** land D34/D37 (confirmed) before U3: accepted. D40 and SHEET-s3's D47 (unconfirmed) had no recommendation and stay
   open. They edit the same `GestureAttach` switch, so they block U3, not U1 or U2.

**After U1 (user, 2026-10-27, 23:21 UTC).** The user accepted U1's corrections C1–C7 with two choices:
- per-OS angle constants for N (U1 C2 option b);
- a narrow S2 allowance: the window route's `controllerRoot` walk, and V ctl's checks against public UIKit control types.

Both are folded into §2 and §7. F1 came from folding the corrections in, and needs no decision. A three-lens review of the fold (with a
skeptic) found 17 real defects, all fixed. They are cited as "review X-n".

8. **Open: which C2 rule stands.** Fifteen seconds after the answer above, the user told the spike session "C2: keep one 45° axis rule
   and document the 40–70° band as a deviation from native" (23:22 UTC). The spike session committed that as 0038ea9. This design
   follows (b) until the user confirms one.
   - **If (a):** the cone table collapses to 45° everywhere, and §2's derivation becomes the deviation band. In it, our view gives the
     page drags that native gives the inner view:
     - a horizontal view gives up the medium and fast drags of 50–70° on 26.x and of 50° on 27.0, and the slow 50° drags in the runs
       where native took them on 26.5 and 27.0;
     - a vertical view gives up 10–40° on 26.x and 30–40° on 27.0. §6 C3's N
     cells in the band become deviation rows, printed, and §7 gets 0038ea9's "Deviation (N)" bullet.
   - **Either way:** the direction vector, F1 and every other fix stand.
