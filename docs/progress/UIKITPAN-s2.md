# UIKITPAN-s2 handoff · 2026-10-28 · Opus 5.5 · max effort (side session, build session U2 of docs/design/UIKIT-pan.md at 9e6d448)
Status: done. U2's scope from design §5 is complete: the pure core, the session's decline, settle and F1 rules, the revival of a
yielded swipe, the arbiter's `participantDeclined`, and the unit suites. Nothing is wired yet: there is no shell, no opt-in and no
`PanEvent.direction`, so no existing view can reach these paths (the regression run below is unchanged). The reference design is
`docs/design/UIKIT-pan.md` at 9e6d448 on `claude/upbeat-mendeleev-3a9d67`; this branch's copy of the design is still the older
2e2de8e text. No merge was made, and nothing under `Packages/` changed.

Changed:
- `Sources/ZTronScrollView/Gesture/UIKit/UIKitPanCore.swift` (new, CoreGraphics and Foundation only, no `#if`):
  - `UIKitPanCones`: `.standard` 45/45, `.nativePage26` 45/85, `.nativePage27` 45/65 (C2 option b). The shell picks one;
    the core takes it as an input.
  - `UIKitPanCore.decide(_:)`: the axis rule in the design's precedence. Rule 1 declines everything (scroll disabled,
    yielding, `\.isEnabled` false, two touches seen). Rule 2 accepts a drag more than a one-axis container's tolerance off its
    paging axis when the view can move on the cross axis. Rule 3 accepts iff the view can move on an axis whose cone holds the drag.
    "Can move" reads the raw inputs (`AxisInput`), never `bouncesX/Y`.
  - `direction(displacement:velocity:)`: the displacement since the observer's touch-down from 8 pt, else UIKit's velocity.
  - The sequence state machine:
    - `touchDown(at:touchCount:)` returns the dangling-pan `.cancelled`;
    - `touchCountChanged(to:time:)` ends an active pan once and asks for a reset;
    - `willReset(stateRaw:)` arms the swallow only in began/changed;
    - `sequenceEnded()` leaves the pan alone (lift order);
    - `shouldBegin(_:location:velocity:)` forwards `.declined` once per sequence;
    - `handle(stateRaw:translation:velocity:location:time:)` is the raw-state table. Unknown raw values give nothing; after a
      second touch, samples and the `.ended` of an inactive pan are dropped.
- `PanSession.swift`:
  - `PanEvent.declined`. In `touching(caught: true)` it returns `[.settle]` and becomes `caught: false`. Every other phase waits for
    the touch's end, and `.released` goes to idle as for any event.
  - `PanEffect.settle`.
  - `PanEnvironment.translationExcludesHysteresis`, latched at touch-down into `creditsWholeFirstSample` (F1).
  - `yielded`: a pending sample kept current while `.ignored` after an owner decision, and `revive(env:)`.
- `NestedScrollArbiter.swift`: `participantDeclined(_:)`.
  - For the rest of the sequence the reference arbiter sees a `.null` frame for the declined participant, through its public
    `update`. The arbiter mirrors frames, defers updates while a frame is hidden, and restores frames in `endSequence()`.
  - A sequence that is not active begins lazily.
  - If the cached decision was for the declined token, it sets `revived` (`currentOwner` then reads `.container`) and calls the
    container's revive.
- `PanCoordinator.swift`:
  - applies `.settle` as `endDrag(zeroVelocity, notifiesDrag: false)` from the current offset, and clears `caughtUndecided`;
  - on `.declined`, in every session state, tells a `NestedScrollArbiter` (never an external one);
  - adds `reviveAfterParticipantDeclined()`, `hasHeldRelease` (for tests) and a `releaseSettings()` helper.
- `ReleasePipeline.swift`: `endDrag(…, notifiesDrag: Bool = true)` skips willEndDragging and didEndDragging when false.
- Tests:
  - new suites: `UIKitPanCoreTests` (24 tests: truth tables), `UIKitPanSessionTests` and `UIKitPanDeclineTests` (real coordinators,
    the nested arbiter, the core standing in for the shell);
  - `DelegateOrderTests`' effect driver handles `.settle`;
  - `scripts/coverage-uikit.sh` lists `UIKitPanCoreTests`, so the existing line gate covers the new file in `Gesture/UIKit/`.

Decisions (implementation; no new D-number):
- **F1 means "baseline from a zero translation".** Dropping the hysteresis to 0 would make the recognition sample move nothing, so
  `beginDrag` builds the baseline from `.zero` when the sequence credits the whole sample. Q5's rows are pinned: UIKit's 0.3, 7.7 and
  31 pt move the content by all of it, where SwiftUI's rule moves 0, 0 and 21 pt.
- **"Resolve past" uses the frozen API only.** The reference's `participant(at:)` runs inside its own decision, so the arbiter hides
  the declined frame with `.null` instead. Each hide and restore adds an `.update` log entry, which `sequenceEntries`-style filters
  already skip. The decided token is read from the reference log's deciding `.owner` entry; the log is cleared at every sequence begin.
- **Rule 2 uses the arbiter's exact rule-1 numbers** (atan2 in degrees, 1e-9° slack, a zero vector never off-axis, NaN never off-axis),
  so it accepts exactly the drags that the arbiter's rule 1 hands the participant.
- **Cone edge cases.**
  - Ties go outside, with the same slack.
  - A zero direction lies in every cone, as a zero translation is on-axis for the arbiter; NaN lies in none.
  - Under S's 45°/45° an exact 45° lies in neither cone, so even a two-axis view declines it. The case has measure zero and is pinned;
    in N the cones overlap.
- **The settle is a zero-velocity release without drag callbacks.**
  - Paging and targets snap; plain content stays; an overscroll springs back. A moving settle still sends `willBeginDecelerating`
    and `didEndDecelerating`.
  - `catchLocksContent` clears when the settle starts, as on any deceleration, not at the lift.
  - The R6 baseline is pinned unchanged: a tap catch without a decline leaves the pager between pages.
- **Second finger.**
  - The core's `.dragEnded` carries the last translation and UIKit's last velocity, at the observer's count-change time.
  - Touches that land together request no reset, because the pan stays `.possible`.
  - Counts outside a live sequence are ignored, because the observer emits `fingerCountChanged` before its `touchDown`.
- **A raw `.cancelled` with neither an active pan nor an armed swallow still emits `.cancelled`**, as the design's table says
  (UIKit sends none in practice).
- **Revival lives in the session.** `.ignored` after an owner decision keeps the latest sample. `revive` begins the drag exactly
  as a `.participant` answer at that sample would, keeping the catch's `caughtAt`. It runs only when this view's own nested arbiter
  had decided the swipe for the participant that declined.

Shell contract for U3. `UIKitPanCore` expects the shell to forward in this order:
- **Observer outputs, in their order:**
  - `.pinch(.fingerCountChanged(n, …))`: call `core.touchCountChanged(to: n, time:)` and forward its events to `handle`. If it
    `resetsRecognizer`: `core.willReset(stateRaw: g.state.rawValue)`, then `isEnabled = false`, then `isEnabled = true`. Then forward
    the pinch output.
  - `.pan(.touchDown(p, _, n))`: call `core.touchDown(at: p, touchCount: n)` and forward its events before the touch-down.
  - `.pan(.touchesEnded)` and `.pan(.cancelled)`: call `core.sequenceEnded()`, then forward.
- **`gestureRecognizerShouldBegin(g)`:** forward the events of `core.shouldBegin(input, location: g.location(in: viewport),
  velocity: g.velocity(in: viewport))` and answer `begins`.
- **Action:** forward `core.handle(stateRaw: g.state.rawValue, translation:, velocity:, location:, time: Date().timeIntervalSinceReferenceDate)`.
- **Inputs:**
  - `Input.horizontal/vertical`: `isInAxes` from `PanEnvironment.axes` (D15); `isScrollable` from the bounds; `bouncesAlways` =
    behavior `.always` (and the state's `bounces`, as `BounceConfiguration` reads it); `alwaysBounces`; `refresherBounces` from
    `RefreshCoordinator`.
  - `Input.container`: the nested arbiter's paging axis and tolerance while it is one-axis.
  - `PanEnvironment.translationExcludesHysteresis` from the per-sequence latch.

Open:
- The ask (`.askOwner`) and the directional lock still read the translation. Adding `PanEvent.direction` is U3's (design §5); the
  core's `.dragChanged` then also carries `location − startLocation`.
- Not measured, for U4: the decline order on a device (order A, where the participant's `shouldBegin` comes before the container's
  ask, is the assumed one; B is pinned by unit rows), the settle's delegate sequence against native, and F1 on the A/B lane.
- Unit lanes 17.5, 18.5 and 26.5 were not run; only 27.0 was. The core is pure and the coordinator changes are not OS-gated. U3's
  done-when runs all four.
- C2's record on this branch: `UIKITPAN-s1.md` reads option (b) (460e379). This branch's Orchestration item 14 still says "Decision
  needed: C2" from the revert. The design branch's text is the reference.

Next: 1) settle the D34/D37 merges and the D40 / SHEET-s3 D47 decision, which block U3 (§9 Q7; the user confirmed on
2026-11-01 that U3 waits for them); 2) U3, the shell and wiring per
design §5, with the contract above and `PanEvent.direction`; 3) U4 demo and UI matrix, with this branch's U1 probes and harness as
baselines; then U5.

Tests (private iOS 27.0 iPhone 18 Pro device, created for this session and deleted at the end; host load 8–580):
- `scripts/test.sh -only-testing:ZTronScrollViewTests/{UIKitPanCoreTests,UIKitPanSessionTests,UIKitPanDeclineTests,PanSessionTests,
  NestedArbitrationTests,DelegateOrderTests,ReleasePipelineTests}`: 102 tests in 7 suites passed.
- Coverage: `UIKitPanCoreTests` alone with `-enableCodeCoverage YES` gave `UIKitPanCore.swift` 84/84 kind-0 regions (llvm-cov export).
  Every `&&` / `||` right-hand side ran on both outcomes of its left side.
- Full unit suite (`-only-testing:ZTronScrollViewTests`, at e516704): 761 tests in 67 suites passed in 254 s (the target has no
  XCTest cases), with 0 UIKit feedback-loop warnings. The demo UI suite was not run: no shipped path can send `.declined` or set
  the F1 flag until U3 wires them.
