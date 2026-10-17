# MC · ScrollArbitration 1.0.0 contract design

Scope: SPEC S16 (l.754–873) and S12 "Inside a pager" (l.600–618). This note fixes every point S16 leaves
open, lists the contract tests and plans the UIKit spike. Package: `Packages/ScrollArbitration`
(swift-tools 6.0, Swift 6 mode, iOS 15 / macOS 12, imports SwiftUI + Foundation only). After the spike
answers are recorded in §6 the package is tagged `ScrollArbitration-1.0.0` (D4) and never edited here again.

## 1. Public API

Exactly S16's listing, reproduced here as the frozen surface. Nothing is renamed, re-isolated or re-typed.

```swift
public enum FingerDirection: Sendable, Hashable { case left, right, up, down }   // screen space
public enum ScrollOwner: Sendable, Hashable { case participant, container }
public struct ScrollArbitrationToken: Sendable, Hashable { /* opaque: internal `serial: UInt64`, no public init */ }

@MainActor public protocol ScrollArbitrationParticipant: AnyObject {
    func canFollow(_ direction: FingerDirection) -> Bool
    var isMovingWithoutFinger: Bool { get }
    var isZoomEnabled: Bool { get }
}
@MainActor public protocol ScrollArbiter: AnyObject {
    var coordinateSpaceName: String { get }
    func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken
    func update(_ token: ScrollArbitrationToken, frame: CGRect)
    func unregister(_ token: ScrollArbitrationToken)
    func owner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int,
               participant: ScrollArbitrationToken) -> ScrollOwner
}
extension EnvironmentValues { public var scrollArbiter: (any ScrollArbiter)? }   // nil by default
public let scrollArbitrationGestureName = "ScrollArbitration.participant"

public struct ScrollArbitrationInput: Sendable, Equatable { /* 8 vars exactly as S16 */ }
public enum ScrollArbitrationRules {
    public static func fingerDirection(_ translation: CGSize, along axis: Axis) -> FingerDirection
    public static func decide(_ input: ScrollArbitrationInput) -> ScrollOwner
}
@MainActor public final class ReferenceScrollArbiter: ScrollArbiter { … }
```

Environment key, verbatim shape (computed `defaultValue`: a stored `static var` of the non-`Sendable`
existential `(any ScrollArbiter)?` is rejected under strict concurrency on 6.0 toolchains; a computed getter
satisfies `EnvironmentKey` and is concurrency-safe on every toolchain):

```swift
private struct ScrollArbiterKey: EnvironmentKey {
    static var defaultValue: (any ScrollArbiter)? { nil }
}
extension EnvironmentValues {
    public var scrollArbiter: (any ScrollArbiter)? {
        get { self[ScrollArbiterKey.self] }
        set { self[ScrollArbiterKey.self] = newValue }
    }
}
```

`ScrollArbitrationInput` keeps S16's vars in S16's order; `Axis` is `SwiftUI.Axis` (`@frozen`, so `Sendable`
and `Equatable` are implicit). `ScrollArbitrationToken` wraps an internal `serial: UInt64` (§3g).

### Additions (purely additive; nothing in S16 changes)

| # | Addition | Why it is unavoidable or worth it |
|---|---|---|
| A1 | `ScrollArbitrationInput.init(pagingAxis:directionTolerance:translation:touchCount:participantCanFollow:participantMovingAtTouchDown:participantZoomEnabled:containerMovingAtTouchDown:)`, public, `directionTolerance: Double = 30` | A public struct's memberwise init is internal; without this the type is unusable outside the module. The default implements "default 30". |
| A2 | `ReferenceScrollArbiter.init(pagingAxis: Axis = .horizontal, directionTolerance: Double = 30, coordinateSpaceName: String = "ScrollArbitration.reference")` | S16 says the properties are settable but gives no init. |
| A3 | `public enum ScrollArbitrationLogEntry: Sendable, Equatable` + `ReferenceScrollArbiter.log: [ScrollArbitrationLogEntry]` + `clearLog()` | S16 requires "a log of every register, update, unregister and owner call, for assertions"; the entry type must be public to assert on it. Shape in §3f. |
| A4 | `ReferenceScrollArbiter.participant(at point: CGPoint) -> ScrollArbitrationToken?` and `containerOwner(ofDragFrom:translation:touchCount:) -> ScrollOwner` | `owner` takes a participant token the container does not have; S16 says the container's decision "goes through the same cache". §3c. On the class only, not on the protocol. |
| A5 | `ReferenceScrollArbiter.isSequenceActive: Bool { get }` and `currentOwner: ScrollOwner? { get }` | Read-only; the spike's on-screen log and the "exactly once" tests read them. |

Not added: any public init for `ScrollArbitrationToken` (unknown tokens in tests come from a second arbiter,
§3g), any async API, any notification of decisions (both sides ask; nobody is told).

## 2. `ScrollArbitrationRules` semantics

**Sign conventions.** `translation` is the finger's movement in screen space, SwiftUI `DragGesture.translation`
convention: `+width` = finger moved right, `+height` = finger moved down. `FingerDirection` names the finger, not
the content: finger `.left` means the content should move left, revealing content on the right, so a participant
answers `canFollow(.left)` true iff it can still scroll towards its trailing edge. Layout direction is ignored
here (S16); RTL is the participant's concern in `canFollow`.

**`fingerDirection(_:along:)`** uses only the on-axis component and strict sign tests:
`.horizontal`: `width < 0 → .left`, otherwise `.right`. `.vertical`: `height < 0 → .up`, otherwise `.down`.
So `0`, `-0.0` and NaN map to the positive direction (`.right` / `.down`). This is the only place a zero on-axis
translation matters and it is harmless: a (0, 0) translation is on-axis by the angle rule, so it reaches rule 5
and asks `canFollow(.right)`; a (0, y≠0) translation never reaches rule 5 unless `directionTolerance ≥ 90`.
The off-axis component is never consulted.

**Rule 1 angle math.** With `on` = |on-axis component| and `off` = |off-axis component| (component chosen by
`pagingAxis`): `offAxisDegrees = atan2(off, on) * 180 / .pi`, always in [0, 90]. Rule 1 fires iff
`offAxisDegrees > directionTolerance + 1e-9` (a private `toleranceSlack`). Reason for the slack: a translation
built at the tolerance angle with `tan` or `cos`/`sin` comes back from `atan2` up to a few ulps (≈ 2e-14°)
above it at many tolerances (25° for one), and S16 says exactly at the tolerance is on-axis; 1e-9° is far
above that rounding and far below any meaningful drag angle. Consequences, all normative:
- exactly at the tolerance (up to the slack) → on-axis (not rule 1); `atan2(0, 0) == 0` → a zero translation
  is on-axis;
- `(0, y≠0)` → 90°, participant for any tolerance < 90; `(x≠0, 0)` → 0°, on-axis;
- sign of either component does not change the angle (all four quadrants equal);
- `directionTolerance` is not clamped: ≥ 90 disables rule 1, < 0 makes every non-zero translation rule 1;
- NaN components: `atan2` returns NaN and `NaN > t` is false → on-axis; no special-casing in code.
`decide` evaluates rules 1–6 in S16 order and returns the first match; rule 2 is `touchCount >= 2 &&
participantZoomEnabled`; `touchCount <= 1` (including 0) is single-touch.

## 3. `ReferenceScrollArbiter` behaviour

All members are `@MainActor`. `pagingAxis`, `directionTolerance`, `isContainerMoving` are settable `var`s.
The arbiter never calls back into a participant except `canFollow`, `isMovingWithoutFinger`, `isZoomEnabled`
inside `beginSequence`, `owner` and `containerOwner` (`register`, `update`, `unregister` call none of them);
participants must never call the arbiter from those members (no re-entrancy, S16 threading). The
`ScrollArbitrationParticipant` doc states this as "only from inside the arbiter's own calls".

**Protocol wording of "once per sequence".** S16 says later calls return the same owner "whatever its
arguments"; the participant token is one of those arguments, so the `ScrollArbiter.owner` doc says: within
one touch sequence (first finger down to last finger up, as the arbiter sees it) the first call decides; later
calls from the participant the swipe was resolved to get the same owner whatever the other arguments, every
other participant gets `.container`, an unknown token gets `.container`. Doc-only; (d) below is the detail. Participants are held `weak`; a deallocated participant is treated as unknown.

- **(a) Sequence.** A sequence is the span between `beginSequence()` and the next `endSequence()`, numbered by
  a per-arbiter `Int` starting at 1. `beginSequence()` while a sequence is active is a **no-op** (logged), so
  several touch observers (page observer and pager, §5) may all report finger-down without restarting the cache.
  `endSequence()` with no active sequence is a no-op (logged). `owner` / `containerOwner` **with no active
  sequence** decide afresh on every call through `decide`, cache nothing and log `sequence: nil`; this keeps a
  participant without a touch observer (contract tests, or iOS 15–17 fallbacks) correct, just without the
  once-per-sequence guarantee.
- **(b) Moving at touch-down.** `beginSequence()` snapshots `isMovingWithoutFinger` of every registered
  participant into `movingAtTouchDown: [token: Bool]` and `isContainerMoving` into `containerMovingAtTouchDown`.
  Reason: S6's touch-down catch stops the participant's own motion before its ~10 pt hysteresis, so by the time
  `owner` is called the live value is already false; the pager likewise stops decelerating on touch-down. A token
  with no snapshot (registered after `beginSequence`, or no sequence active) is read live at the `owner` call.
  `participantCanFollow` (via `fingerDirection(translation, along: pagingAxis)`) and `participantZoomEnabled`
  are always read live at the deciding call.
- **(c) Container access.** `participant(at:)` resolves the token under a point with the rule in (d);
  `containerOwner(ofDragFrom:translation:touchCount:)` is `owner(ofDragFrom:translation:touchCount:
  participant: participant(at: start) ?? <unregistered sentinel>)`, i.e. the same code path and cache. No
  participant under the start point → `.container`, not cached (nobody else will ask for that touch). The log
  entry records `askedBy: .container` so tests and the spike can tell which side asked first.
- **(d) Resolution and overlap.** Candidates are the registered participants whose frame `contains` the start
  point (`CGRect.contains`, edges inclusive on min, exclusive on max as CoreGraphics defines). Pick the
  smallest area; ties → the highest serial (most recent registration). If no frame contains the point but the
  caller's token is registered, the caller is resolved (its frame may lag a layout change; it knows the touch
  began inside it). The first call of a sequence stores `(sequence, resolvedToken, owner)`. Later calls in the
  sequence: same resolved token (by resolution or by being the caller) → cached owner, whatever the arguments;
  a different *known* token → `.container` (it is not the participant of this swipe; the decision is not
  re-run); unknown → (e). The container's call hits the cache through the resolved token. `decide` inputs
  always come from the resolved participant, never from a different caller.
- **(e) Unknown tokens.** A token never registered with this arbiter, unregistered, or whose participant was
  deallocated: `owner` returns `.container` without running `decide` and without touching the cache (a sequence
  still undecided stays undecided); `update` and `unregister` do nothing. All three are logged with
  `known: false`.
- **(f) Log entry type.**
  ```swift
  public enum ScrollArbitrationLogEntry: Sendable, Equatable {
      case register(ScrollArbitrationToken, frame: CGRect)
      case update(ScrollArbitrationToken, frame: CGRect, known: Bool)
      case unregister(ScrollArbitrationToken, known: Bool)
      case beginSequence(id: Int, started: Bool)        // started == false: no-op (already active)
      case endSequence(id: Int?, ended: Bool)           // id nil + ended false: no-op (idle)
      case owner(caller: ScrollArbitrationToken, askedBy: ScrollOwner, start: CGPoint, translation: CGSize,
                 touchCount: Int, sequence: Int?, resolved: ScrollArbitrationToken?,
                 input: ScrollArbitrationInput?, decided: Bool, result: ScrollOwner)
  }
  ```
  `decided == true` exactly on the call that ran `decide`; `input` is non-nil only then. `log` is append-only
  and unbounded until `clearLog()` (no cap, no opt-out: either would be extra frozen API, and tests and the
  spike want the full log). A long-lived container using `ReferenceScrollArbiter` must call `clearLog()`
  regularly, e.g. right after each `endSequence()`; the class doc says so.
- **(g) Tokens.** `ScrollArbitrationToken(serial:)` is internal. Serials come from one `@MainActor private
  static var nextSerial: UInt64 = 1` on `ReferenceScrollArbiter`, process-wide and never reused, so a token from
  arbiter A is guaranteed unknown to arbiter B (this is how tests obtain unknown tokens).
- **(h) RTL.** `FingerDirection` and `fingerDirection` are screen-space and layout-direction-blind by contract.
  A participant in an RTL layout translates `.left`/`.right` into its own leading/trailing semantics inside
  `canFollow`; the arbiter and the pager never know.

## 4. Contract tests (`Packages/ScrollArbitration/Tests/ScrollArbitrationTests`, Swift Testing)

Run with `scripts/test-arbitration.sh` (host, macOS). Helper `makeInput(...)` builds a
`ScrollArbitrationInput` with every flag false, `touchCount: 1`, tolerance 30, axis `.horizontal`, translation
(100, 0) unless overridden. A `FakeParticipant` (`@MainActor final class`) has settable
`follow: [FingerDirection: Bool]`, `isMovingWithoutFinger`, `isZoomEnabled` and records every direction
`canFollow` is asked about (`askedDirections`; `canFollowCalls` is its count).

**RulesTests** (`ScrollArbitrationRules.decide`)
1. Rule 1 wins over everything: 31° (100, 60.1) with `containerMovingAtTouchDown: true`, `participantCanFollow:
   false` → `.participant`; same at 29° (100, 55.4) → `.container`.
2. Boundary both sides of 30°: (100, tan(30.1°)·100) → `.participant`; (100, tan(29.9°)·100) → `.container`.
3. Exactly at tolerance is on-axis, robustly: `tolerance = atan2(50, 100) * 180 / .pi` with translation
   (100, 50) → `.container`; `tolerance - 1e-6` → `.participant` (one ulp below is inside the slack).
   3b. Trig-built boundary, both axes: for every whole tolerance 1…89 and 12.34, magnitudes 0.5…2000,
   translations built at the tolerance with `tan` and with `cos`/`sin` → on-axis; built at tolerance + 1e-6° →
   `.participant`. Includes the tolerance-25 case that misclassified without the slack.
4. Degenerate angles: (0, 0) on-axis; (0, 120) and (0, -120) → `.participant`; (-120, 0) on-axis;
   all four sign quadrants of (100, 60.1) → `.participant`; tolerance 90 with (0, 120) → on-axis;
   tolerance -1 with (100, 0) → `.participant`, with (0, 0) → on-axis.
5. Vertical axis: same four cases with components swapped (`pagingAxis: .vertical`).
6. Rule 2: `touchCount: 2, participantZoomEnabled: true` + container moving + cannot follow → `.participant`;
   `touchCount: 3` same; `touchCount: 2`, zoom off → `.container`; `touchCount: 1`, zoom on → `.container`;
   `touchCount: 0` → single-touch.
7. Rule 3: participant moving + container moving + cannot follow → `.participant`.
8. Rule 4: container moving + can follow + zoom on (1 touch) → `.container`.
9. Rule 5: can follow only → `.participant`. 10. Rule 6: all false → `.container`.
11. Truth table: parameterized over all 32 combinations of (offAxis, multiTouchZoom, pMoving, cMoving,
    canFollow) with the expected owner written as a literal table (first match in S16 order), both axes.

**DirectionTests** (`fingerDirection`)
12. Horizontal: (+50, 0) `.right`; (-50, 0) `.left`; (0, 0) `.right`; (-0.0, 80) `.right`; (+1, -500) `.right`
    (off-axis ignored). 13. Vertical: (0, +50) `.down`; (0, -50) `.up`; (0, 0) `.down`; (-500, 1) `.down`.

**ReferenceArbiterTests** (all `@MainActor`)
14. Defaults: `pagingAxis == .horizontal`, `directionTolerance == 30`, `isContainerMoving == false`,
    `coordinateSpaceName` non-empty, `log.isEmpty`, `isSequenceActive == false`, `currentOwner == nil`.
15. `register` returns distinct tokens; two arbiters never return equal tokens; log has `.register` with frame.
16. `update(known)` moves the frame (`participant(at:)` reflects it); `update(unknown)` → no change, logged
    `known: false`. 17. `unregister` → `participant(at:)` nil, later `owner` with it → `.container` with
    `decided: false`; double `unregister` logged `known: false`; a token from another arbiter → same.
18. No sequence: two consecutive `owner` calls with different translations (0° vs 90°, canFollow false) give
    `.container` then `.participant`; both entries `sequence: nil, decided: true`.
19. Caching, participant first: begin; canFollow true, 0° → `.participant`; flip canFollow false, 90° → still
    `.participant`; `containerOwner` same start → `.participant`; `currentOwner == .participant`; end; begin →
    0° → `.container` (fresh). Exactly one `decided: true` per sequence.
20. Caching, container first: begin; `containerOwner` at a point inside the frame, canFollow false → `.container`;
    participant asks with canFollow true → `.container`; new sequence → `.participant`.
21. Snapshot semantics: participant `isMovingWithoutFinger = true`, begin, set false, owner (cannot follow,
    container moving) → `.participant` (rule 3 from the snapshot). `isContainerMoving = true`, begin, set false,
    owner (can follow) → `.container`. Set `isContainerMoving = true` *after* begin → not counted → `.participant`.
    Participant registered after begin is read live.
22. Overlap: A (0,0,300,300) registered first, B (100,100,50,50) second; start (120,120): B asks →
    `.participant`; A asks in the same sequence → `.container`; `participant(at:)` → B. Equal frames A then
    B → B. Start outside both, A asks → A resolved (decides for A). `decide` inputs come from the resolved
    participant (A's `canFollow` not called when B is resolved; checked with the call counter).
23. `containerOwner` with no participant under the point → `.container`, `decided: false`, `resolved: nil`,
    sequence stays undecided (a following participant call still decides).
24. Sequence bookkeeping: `beginSequence` twice → second logged `started: false`, cache kept; `endSequence`
    when idle → `ended: false`; ids 1, 2, 3 across three sequences; `isSequenceActive` toggles.
25. `askedBy`: direct `owner` logs `.participant`, `containerOwner` logs `.container`.
26. Log script: exact `log` equality for register → begin → owner → containerOwner → end → unregister;
    `clearLog()` empties it without touching registrations or the active sequence.
27. Weak participant: deallocate the participant → its token becomes unknown (`.container`, `decided: false`).
30. Finger direction reaches `canFollow`: follow `[.left: false, .right: true]` → (-100, 40) `.container`
    asking `.left`, (100, -40) `.participant` asking `.right`; vertical axis with `[.up: false, .down: true]` →
    `.up` / `.down` likewise, also through `containerOwner` (asserted with the recorded directions).
31. `pagingAxis` is read at each deciding call: (0, -100) is rule 1 when horizontal, on-axis when vertical;
    (-100, 0) is rule 1 when vertical (also via `containerOwner`); changed after `beginSequence` → new value.
32. `directionTolerance` is read at each deciding call: a 20° drag is on-axis at 30, `.participant` at 10 (logged
    `input.directionTolerance == 10`), on-axis again at 45 set after `beginSequence`.
33. Rule 2 through the arbiter: zoom on, cannot follow, container moving → 2 touches `.participant` (logged
    `touchCount == 2`, `participantZoomEnabled == true`), 1 touch `.container`; `isZoomEnabled` toggled after
    `beginSequence` is read live (also when the container asks first).
34. Unknown tokens over a live participant: a foreign and an unregistered token asking at a point inside a
    registered participant's frame → `.container`, `decided: false`, `resolved: nil`, outside and inside a
    sequence; the sequence stays undecided and the registered participant's own call still decides.

**EnvironmentTests** 28. `EnvironmentValues().scrollArbiter == nil`; setting and reading an arbiter round-trips
identity. 29. `scrollArbitrationGestureName == "ScrollArbitration.participant"`.

Toolchains: `scripts/test-arbitration.sh` on Xcode 27 here; the Xcode 26.6 run is a user action
(`DEVELOPER_DIR=<Xcode 26.6>/Contents/Developer scripts/test-arbitration.sh`), result recorded in §6.

## 5. UIKit spike (`Packages/ScrollArbitration/Spike`)

**Layout** (only UIKit in the repo; no library target depends on it):
```
Spike/ArbitrationSpike.xcodeproj/project.pbxproj                 hand-written, objectVersion 77
Spike/ArbitrationSpike.xcodeproj/xcshareddata/xcschemes/ArbitrationSpike.xcscheme   shared scheme (app + UI tests)
Spike/ArbitrationSpike/        AppDelegate.swift, SceneDelegate.swift, PagerViewController.swift,
                               ArbitratedPagingScrollView.swift, StandInPage.swift, StandInModel.swift,
                               SequenceRecorder.swift
Spike/ArbitrationSpikeUITests/ ArbitrationSpikeUITests.swift, DragScript.swift
```
`project.pbxproj`: two `PBXNativeTarget`s (`ArbitrationSpike`, `ArbitrationSpikeUITests`, `TEST_TARGET_NAME =
ArbitrationSpike`), each with one `PBXFileSystemSynchronizedRootGroup` (folder-backed, no file lists to
maintain), `XCLocalSwiftPackageReference` with `relativePath = ../..` plus one `XCSwiftPackageProductDependency`
(`ScrollArbitration`), `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_UIApplicationSceneManifest_Generation =
YES`, `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `SWIFT_VERSION =
6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `TARGETED_DEVICE_FAMILY = 1`, `CODE_SIGN_IDENTITY = ""` /
`CODE_SIGNING_ALLOWED = NO` for the simulator. UIKit app lifecycle (no SwiftUI layer above the pager) so the
measurements are not confounded by an outer hosting view; see open question in the reply if ZTronPages needs the
Representable variant.

**Pager.** `PagerViewController` owns an `ArbitratedPagingScrollView` (horizontal, `isPagingEnabled`,
`delaysContentTouches = false`, `canCancelContentTouches = true`, both recorded as spike constants) with three
`UIHostingController` pages. **One `ReferenceScrollArbiter` per page** (`coordinateSpaceName =
"ScrollArbitration.page"`), injected with `.environment(\.scrollArbiter, arbiter)`; the page root applies
`.coordinateSpace(name: arbiter.coordinateSpaceName)`, so frames are page-local and the pager converts touch
points with `location(in: page.hostingView)`. (A single arbiter across separate hosting hierarchies cannot work:
every page would register the same local frame.) The subclass:
- `touchesBegan/Ended/Cancelled` (calling super): first touch → `arbiter.isContainerMoving = isDecelerating`,
  record the UIKit touch-down point in the page's space, `beginSequence()`; last touch → `endSequence()`.
- `gestureRecognizerShouldBegin(_:)`: for `panGestureRecognizer` only, find the page under
  `location(in: self)`, call `containerOwner(ofDragFrom: touchDownPoint, translation: pan.translation(in:
  hostingView), touchCount: pan.numberOfTouches)`, record who asked first, return `owner == .container &&
  super…`. Other recognizers → super.
- `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` (`UIGestureRecognizerDelegate`, the scroll view
  already is its pan's delegate): on iOS 18+ return `other.name == scrollArbitrationGestureName`; below, the
  default (false). Every `other` seen is kept weakly with its class name for question 2.
- `panGestureRecognizer.addTarget` records every state transition (`possible → began → changed → ended /
  cancelled / failed`) into the current sequence record; `scrollViewDidScroll` / `DidEndDecelerating` record
  `pagerMoved` and the page index.

**Stand-in participant** (`StandInPage`, SwiftUI; `StandInModel: ScrollArbitrationParticipant,
ObservableObject`): registers in `onAppear` with the viewport frame in `.named(arbiter.coordinateSpaceName)`,
`update` on `onChange(of: frame)`, `unregister` in `onDisappear`. Gestures, all attached with the `name:`
variants (`scrollArbitrationGestureName`) on iOS 18+ via `if #available`, plain variants below:
- touch observer: `SpatialEventGesture()` (18+; `beginSequence` on the first `.active` event, `endSequence`
  when none remain, cancelled phases counted) or `DragGesture(minimumDistance: 0, coordinateSpace:
  .named(…))` (below; `onChanged` first value → begin, `onEnded` → end); records the SwiftUI touch-down point;
- pan `DragGesture(minimumDistance: 10, coordinateSpace: .named(…))`: on its first `onChanged` calls
  `owner(ofDragFrom: value.startLocation, translation: value.translation, touchCount: observerTouchCount,
  participant: token)`; `.participant` → moves a 120×120 box by the translation; `.container` → ignores the
  rest of the sequence;
- pinch `MagnifyGesture` (17+) / `MagnificationGesture`: scales the box, never asks;
- `Toggle` "canFollow" (model answers that value for every direction), `Toggle` "participant moving"
  (`isMovingWithoutFinger`), a `Button` "Tap" incrementing a counter, and the sequence log (below).
- composition: `.simultaneousGesture(observer, name:)`, `.simultaneousGesture(pan, name:)`,
  `.simultaneousGesture(pinch, name:)` — `.gesture` vs `.simultaneousGesture` vs `.highPriorityGesture` is
  switched by a launch argument so the S12 empirical choice can be retried without code edits.

**Sequence recorder** (`SequenceRecorder`, `@MainActor`, one per page, fed by both sides and by the arbiter's
`log`): per sequence `id, first (.participant/.container/none), owner, decidedCount, pagerPanStates,
pagerMoved, pageIndexBefore/After, boxMoved, buttonTaps, uikitStart, swiftuiStart, startDelta,
participantEndedCleanly (observer and pan both reached onEnded/cancel), foreignRecognizerBegan (any recognizer
not named scrollArbitrationGestureName reached .began/.changed)`. Rendered as a fixed-grammar line, e.g.
`seq=4 first=container owner=container decided=1 pan=possible>began>changed>ended pagerMoved=1 page=0>1 box=0
button=0 delta=0.31 pEnd=1 foreign=0`.

**Accessibility identifiers.** `pager`; per page `i` ∈ 0…2: `page.i`, `page.i.box`, `page.i.canFollow`,
`page.i.moving`, `page.i.button`, `page.i.buttonCount`; global `pageIndex`, `log.count`, `log.last`,
`log.<n>`, `log.clear`.

**UI-test matrix** (`ArbitrationSpikeUITests`, XCTest; drags are `XCUICoordinate.press(forDuration: 0.05,
thenDragTo:withVelocity: .default, thenHoldForDuration: 0.05)` from the box centre, 120 pt long):
- angles 0° (dx −120, dy 0), 20° (−120, 43.7), 40° (−120, 100.7), 90° (0, −120) × `canFollow` on/off = 8
  drags on page 0, finger leftwards; repeated with +dx on page 1 (both paging directions, rightward = 8 more);
- expected owner: 40°, 90° → `.participant` always; 0°, 20° → `.participant` with canFollow on, `.container`
  off; the test parses `log.last` after each drag and asserts `owner`, `decided=1`, `pagerMoved`/`page` and
  `box` consistent with the owner;
- pinch: `box.pinch(withScale: 1.5, velocity: 1)` → box scaled, `page` unchanged, no `decided` or `owner=
  participant`;
- taps: `button.tap()` ×3 → `buttonCount` 3, no page change; a 0° drag starting on the button with canFollow
  off → page changes, count unchanged; with canFollow on → box moves, count unchanged;
- "participant moving" toggle on + 0° canFollow off → `owner=participant` (rule 3 through the snapshot);
- best-effort catch: fling to page 1 then immediately press-and-hold on page 1 (`isContainerMoving` true at
  touch-down → `.container`); recorded, not asserted (timing-sensitive).
Each test attaches the full `log.<n>` dump as an `XCTAttachment`; `scripts/test-spike.sh` (already present,
`SPIKE_DEST`/`ZS_DEST`) runs the scheme per destination: iOS 17.5, 18.x, 26.x, 27.0 here; 15/16 by the user
with Xcode 26.6.

**How each spike question is measured and recorded**
1. (18+) For every drag: `owner=container ⇒ pan` reaches `began` and `pagerMoved=1`; `owner=participant ⇒
   pan` never contains `began` (ends `failed`/`cancelled`) and `pagerMoved=0`. Asserted on 18+ destinations.
2. (18+) On the drags that start on the button and on the plain taps: `foreign=0` for taps that fire the button
   (the press recognizer is not reported as `.began/.changed` by the pager's simultaneous-recognition query
   while it is a press), and `buttonCount` unchanged on both drags. Recorded per OS, asserted on 18+.
3. (15–17, run on 17.5 here, 15/16 by user) For canFollow-off 0°/20° drags: `pan` reaches `began` and the page
   changes (pager free to begin); `pEnd=1` on the same record (participant observer and pan ended/cancelled
   cleanly) and the next sequence id is `+1` with `decided=1` (no stuck sequence). Asserted on ≤17.
4. Every drag record carries `delta` = distance between the pager's `touchesBegan` point in the hosting view
   and the participant's `DragGesture.startLocation` in `.named(…)`; assert `delta <= 0.5` wherever both
   sides asked; the max per OS is recorded.
5. Every record asserts `decided=1` (count of `decided: true` log entries in that sequence) and the test
   records the distribution of `first=` per OS; the assertion holds for either first asker.

## 6. Spike results (filled in after the runs; one row per OS)

| OS | Q1 pan ⇔ decision (18+) | Q2 button press idle (18+) | Q3 pan free / clean end (≤17) | Q4 max Δ (pt) | Q5 once per sequence; first asker | Notes / fallback |
|---|---|---|---|---|---|---|
| 15.x (user) | n/a | n/a | | | | |
| 16.x (user) | n/a | n/a | | | | |
| 17.5 | n/a | n/a | | | | |
| 18.x | | | n/a | | | |
| 26.x | | | n/a | | | |
| 27.0 | | | n/a | | | |

A "no" either changes this contract before the tag or names the ZTronPages fallback (its EG-11 / EG-13 rows).
Also to record: `scripts/test-arbitration.sh` green on Xcode 27 and on Xcode 26.6 (user action).
