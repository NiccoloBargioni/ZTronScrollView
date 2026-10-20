# NESTED · Drag arbitration between nested ZTronScrollViews (design, pending the user's decision)

Scope: a public API that decides which of two nested `ZTronScrollView`s follows a drag. Builds on SPEC S12 "Inside a
pager" (l.600–618), S16 (frozen 1.0.0: nothing here changes it; additive use only), S11, MC-contract §6, M3-pan §7,
`Gesture/ArbitrationParticipant.swift`, `PanCoordinator.swift` (D7, D12, D15), `Modifiers/ScrollEnvironment.swift`,
`Demo/…/PagerScreen.swift`. No production code, no SPEC edit until the user decides (§5).

## 1. Problem and topologies

**Scenario.** Outer `ZTronScrollView(.horizontal)` with `isPagingEnabled`; inner `ZTronScrollView([.horizontal, .vertical])`
with `zoomRange(1…4)` in each page. A drag that starts on the inner must page iff the inner is at zoom 1; otherwise it
pans the zoomed content. Today nothing decides: both views attach `.simultaneousGesture(observer + DragGesture)` (D12),
SwiftUI recognizes both on the same touch, and each moves whatever it can. At zoom 1 the inner fits and only the pager
moves (by luck); at zoom 2 a horizontal drag pans the image **and** pages at once.

**T1 · ZTronScrollView in ZTronScrollView (pure SwiftUI).** Both recognizers are SwiftUI gestures in the same hosting
view, on every OS 15+. Spike note E (iOS ≤ 17: a recognized SwiftUI `DragGesture` makes the hosting view's recognizer
take the touch and a UIKit paging pan fails, Open item 1) is **irrelevant here**: there is no UIKit recognizer to
starve, both gestures keep receiving the touch, and the loser simply ignores its sequence (`PanSession.ignored`, the
path that already exists for `.container`). No gesture names needed (they only matter for UIKit interop on 18+).

**T2 · ZTronScrollView inside ZTronPages (UIPageViewController's UIScrollView pan).** Covered by S12/S16: the inner is a
participant, the pager asks `containerOwner`, one decision per swipe. 18+ via names; ≤ 17 blocked by note E and waiting
for the ZTronPages fallback (Open item 1). Whatever we add for T1 must map onto this without touching the contract.

**What the frozen rules already give** (`ScrollArbitrationRules.decide`, paging axis horizontal, inner at the touch):

| Inner state at touch-down | Finger | Rule | Owner |
|---|---|---|---|
| zoom 1, content fits both axes | horizontal | 5 fails (`canFollow` false) → 6 | outer (pages) |
| zoom 1, tall content at fit width | vertical (> 30° off axis) | 1 | inner (scrolls) |
| zoom 2, not at an edge | horizontal | 5 | inner (pans) |
| zoom 2, **at the edge** in the finger's direction | horizontal | 5 fails → 6 | outer (pages) |
| any | two fingers | 2 | inner (pinch never asks) |
| inner decelerating / bouncing | any | 3 | inner (catch) |
| outer still settling a page | any on-axis | 4 | outer |

So the user's rule falls out of the contract for every row but one: zoomed **and at the edge**. There UIScrollView
(and the contract) page; the literal rule "outer iff zoomScale == 1" rubber-bands instead. Both are offered (§3).
Gap found on the way: `ArbitrationParticipant.isZoomEnabled` is still hard-coded `false` (M3 placeholder; M4 is done),
so rule 2 never fires for a pager that asks first. Fix it in this work.

**UIScrollView reference.** Nested pans recognize simultaneously; the inner follows while it can and the outer moves
when the inner cannot (at touch-down, and in UIKit also mid-gesture when the inner reaches its edge). The contract
deliberately defers the mid-gesture part ("the next swipe pages", S12 Scope); see "hand-off" below.

## 2. Candidate shapes

### A · Declarative policy modifier (environment value, read at decision time)

```swift
// inner side: "how I yield to my container"; propagates, so it can sit on the outer's content too
ZTronScrollView(.horizontal, state: pager) {                 // pager.isPagingEnabled = true
    HStack(spacing: 0) {
        ForEach(photos) { photo in
            ZTronScrollView([.horizontal, .vertical]) { PhotoView(photo) }
                .zoomRange(min: .absolute(1), max: .absolute(4))
                .nestedScrollPolicy(.innerWhenZoomed)          // member; `.ztronNestedScrollPolicy(_:)` is the View twin
                .frame(width: pageWidth)                            // one page per inner
        }
    }
}
```
Cases: `.automatic` (= `.innerWhileScrollable`: contract rules, UIScrollView parity), `.innerWhenZoomed` (the user's
rule: inner iff `zoomScale > minimumZoomScale`, even at its edge), `.inner`, `.outer`, `.independent` (no arbitration,
today's behaviour), `.custom { ctx in … }` (cold geometry + finger direction → `.inner`/`.outer`).

### B · Binding / observable-driven switch, evaluated at touch-down

```swift
ZTronScrollView(.horizontal, state: pager) { … }
    .ztronScrollDisabled(Binding(get: { photoState.zoomScale > 1 }, set: { _ in }))   // read at touch-down, never in a body
```
The UIKit idiom (`pager.isScrollEnabled = zoomScale == 1` from `scrollViewDidZoom`). S4-safe only if the library reads
`wrappedValue` in the event handler. But it is one-sided: it silences the outer and never tells the inner to ignore a
sequence, so at zoom 1 a diagonal drag on a tall-at-fit-width image scrolls the image **and** pages; it has no direction
rule (rule 1), no touch-during-motion rule (3/4), no notion of *which* inner is under the finger (one Bool for all
pages), and a `Binding` whose getter reads a hot value is a trap for callers who put it in a body. Rejected as the public
shape; its use case is served by A's `.custom` and by the existing `ztronScrollDisabled(Bool)`.

### C · Arbiter object in the environment (public class implementing the frozen `ScrollArbiter`)

```swift
@StateObject var arbiter = ZTronNestedScrollArbiter(policy: .innerWhenZoomed)   // decides via ScrollArbitrationRules
ZTronScrollView(.horizontal, state: pager) { … }
    .ztronScrollContainer(arbiter)              // outer: begin/end sequences, ask containerOwner, ignore on .participant
    .environment(\.scrollArbiter, arbiter)      // inner registers through the existing ArbitrationRegistration
```
Exactly the machinery T2 uses, made explicit. Powerful (one object, inspectable log, testable in isolation) but the call
site must know about arbiters, coordinate spaces and two modifiers for the common case, and nothing works until the
developer wires it. Right as the **implementation**, wrong as the **surface**.

### Trade-offs

| | A policy modifier | B binding at touch-down | C arbiter object |
|---|---|---|---|
| Decision time | hysteresis (~10 pt, direction known; D7 `.tracking` waits) | touch-down (no direction) | hysteresis |
| Axis / direction rules | contract rules 1–6 | none | contract rules 1–6 |
| Hand-off mid-gesture | deferred (contract scope); T1 can add it later behind a case | n/a | same as A |
| Bounce ownership | the owner bounces, the other is frozen for the sequence (`.ignored`) | both may bounce | same as A |
| iOS 15 | yes: DragGestures only; ≤ 17 sequence begins lazily at the first ask (observer gated, M3-s3) | yes | yes |
| S4 render contract | arbiter created once per outer identity; policy and frames are cold; decisions in event handlers | depends on the caller's getter | yes |
| ZTronPages (T2) parity | identical: the policy is applied inside the participant's `canFollow` | none | identical |
| Testability | unit with two coordinators + one arbiter; demo UI test | demo only | unit + contract log |
| Default without API | nesting works (UIScrollView rule) | nothing | nothing |
| Surface | 1 enum, 1 modifier (+ member twin) | 1 overload | 1 class, 2 modifiers, env key |

## 3. Recommendation: A on top of C

**Behaviour when nothing is specified.** An outer `ZTronScrollView` is always a container for the `ZTronScrollView`s in
its content (internal arbiter injected into the content's environment, like `ztronScrollState` today) and the policy is
`.automatic` = the contract rules = UIScrollView: the inner follows while it can on the outer's axis, the outer takes the
swipe when the inner cannot, off-axis swipes and pinches stay inside, a moving side keeps its catch. Nested views on
different axes (vertical list, horizontal carousel) get rule 1 for free. `.independent` restores today's behaviour.

**Public signatures** (names per CLAUDE.md; S8 strategy: member on the view + `ztronScroll…` View twin):

```swift
public struct ZTronNestedScrollPolicy: Sendable {
    public static let automatic: Self                 // = .innerWhileScrollable
    public static let innerWhileScrollable: Self      // S16 rules 1–6 (UIScrollView: inner first, outer when it cannot follow)
    public static let innerWhenZoomed: Self           // inner iff zoomScale > minimumZoomScale (+ rules 1–4); outer at min zoom
    public static let inner: Self                     // the container never takes a drag that starts here
    public static let outer: Self                     // this view never pans a shared drag (pinches stay here)
    public static let independent: Self               // no arbitration with the container
    public static func custom(_ decide: @escaping @MainActor (ZTronNestedScrollContext) -> ZTronNestedScrollOwner) -> Self
}
public enum ZTronNestedScrollOwner: Sendable, Hashable { case inner, outer }
public struct ZTronNestedScrollContext {              // built cold inside the decision, never in a body
    public let geometry: ZTronScrollGeometry          // inner's `peekGeometry()`: contentOffset, zoomScale, visibleRect, …
    public let minimumZoomScale: CGFloat
    public let fingerDirection: FingerDirection       // ScrollArbitration's (re-exported)
    public let canFollow: Bool                        // what `.innerWhileScrollable` would answer
}
extension ZTronScrollView { public func nestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> Self }
extension View { public func ztronNestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> some View }   // env twin
```

**Where the policy acts: inside the inner's `canFollow`.** Rules 1–4 are the arbiter's and always run (direction,
pinch, who was moving). The policy only replaces the rule-5 answer: `.innerWhileScrollable` = the current bounds test;
`.innerWhenZoomed` = `zoomScale > minimumZoomScale + ε`; `.inner` = `true`; `.outer` = `false`; `.custom` = the
closure. One code path for T1 and T2: a ZTronPages pager asking the same participant gets the same answer. No contract
change: the participant is ours, `canFollow` is its own business (S16 "right-to-left is the participant's concern").

**Reading the inner's zoomScale without observing it.** `canFollow` already runs inside the arbiter's `owner` call, in
the drag handler, from `coordinator.environment()` (`state.peek`, non-tracking). The context's `geometry` is
`state.peekGeometry()` (`isTracked == false`): no Observation access, no channel subscription, no body involved. The
policy value travels through the environment (cold, body-time) and is forwarded to the participant on body evaluation
like `setArbiter` is today.

**Container side (internal `NestedScrollArbiter: ScrollArbiter`, decides through `ScrollArbitrationRules.decide`).**
- Owned by the outer's `PanCoordinator` (one per view identity), injected with `.environment(\.scrollArbiter, …)` on the
  content and a `.coordinateSpace(name:)` on the outer's **content** (`"ztronScroll.nested.<serial>"`). In the content
  space the inner's frame does not change while the outer scrolls, so registration stays cold (M3-s3 open item on
  per-frame `update` calls disappears). The outer converts its touch into content coordinates at the ask
  (`visibleRect.origin + local / zoomScale`); several inners (one per page) resolve by the contract's smallest-frame rule.
- `pagingAxis` = the outer's single axis; a two-axis outer decides with the dominant axis of the translation and no
  direction tolerance (rule 1 is moot); `isContainerMoving` = the outer's `isMovingWithoutFinger`.
- Sequence: `beginSequence` at the outer's `touchDown` (18+ spatial observer) or lazily at the first ask (≤ 17, gated
  observer); `endSequence` when the outer's `PanSession` emits `.endSequence`. Both sides ask once at their hysteresis;
  the cache makes the second ask free.
- The outer's `PanSession` gains the mirror of `.awaitingDecision` for the container role: `.participant` → `.ignored`
  for the sequence, `.container` → `beginDrag` (deferred tracking, D7). Rubber band, indicators, delegate and phase of
  the loser stay untouched, as `ArbitrationTests.containerIgnoresWholeSequence` already asserts for the inner.
- Three levels (ZTronPages → outer ZTron → inner ZTron) compose: each view talks only to its nearest container. The
  outer's own `canFollow` toward ZTronPages ORs in "an inner under the touch-down point can follow" (the catch observer
  gives the point before the ask). Phase 2; noted, not required for the scenario.

**Hand-off mid-gesture.** Not in v1: the decision is per swipe on both sides, as the contract says, and the inner
rubber-bands at its edge while zoomed under `.innerWhenZoomed`. T1 can add `.innerWhileScrollable(handsOffAtEdge: true)`
later (inner clamps on the paging axis and feeds the residual translation to the outer through a synthesized pan, the
mechanism `synthesizePan` already uses for pinch → pan). T2 cannot without a contract revision.

**Pinch while the outer owns the drag** (M4 R5): the outer's DragGesture dies on the second finger (R1) → release
(page or settle); the inner's pinch zooms. Same as today; a unit test pins it.

## 4. Builder split, tests, budget

| Session | Owns | Tests | Est. |
|---|---|---|---|
| N-a library (Sonnet builder) | new `Gesture/NestedScrollArbiter.swift`; `PanCoordinator.swift` (container role, sequence begin/end, policy forwarding); `PanSession.swift` (container-side `.awaitingDecision`); `ArbitrationParticipant.swift` (policy in `canFollow`, `isZoomEnabled` fix, context); `Modifiers/ScrollEnvironment.swift` + `ZTronScrollView.swift` (policy type, modifier, member, env + named content space injection) | `NestedArbitrationTests` (host, both OS paths): two coordinators + one arbiter driven by scripted events: the 7 rows of §1's table under `.automatic` and `.innerWhenZoomed`; loser's effects log empty; one decision per sequence (log); `.independent` = today's effects; pinch during outer-owned drag; three-level chain sanity; `.custom` receives a non-tracked geometry (render counters 0) | 3–4 % |
| N-b demo (Sonnet builder) | `Demo/…/NestedPagerScreen.swift` (`-ZTronScreen nestedPager`: outer paging ZTronScrollView, page 0 = 16:9 zoomer 1…4 with double tap, page 1 plain), `NestedPagerUITests.swift` | swipe left at zoom 1 → page 1, `content.body` 0; back, double tap to 4× → swipe pans, page stays; swipe at the edge → pages (`.automatic`) / rubber-bands (`-ZTronNestedPolicy innerWhenZoomed`); vertical swipe at zoom 1 → nothing pages. 27.0 + 17.5, preferred + forced | 1.5–2 % |
| docs (clerk) | SPEC S11/S12 amendment after the decision, parity matrix row, handoff, Orchestration D-number | — | 0.5 % |

Neither session touches `Packages/ScrollArbitration` or `ZTronScrollPhysics`. Total ≈ 5–6 % (M3-c sized). N-b
depends on N-a; both after the demo full re-run (Orchestration step 3) so the baseline is green.

## Open questions (for the user)

1. **Default on?** Should nested ZTronScrollViews arbitrate with `.automatic` when nothing is specified (recommended,
   UIScrollView parity), or only after an explicit modifier (`.independent` stays the default)?
2. **Zoomed at the edge:** page (contract / UIKit, `.automatic`) or rubber-band (`.innerWhenZoomed`, the literal
   "outer iff zoomScale == 1")? Which one is the default for a zoomer, or do you want to write the policy per view?
3. **Mid-gesture hand-off** (T1 only, inner edge → outer continues the same swipe): v1, later, or never?
4. **Where the policy is declared:** on the inner / propagated by environment (recommended: it also drives the
   ZTronPages case unchanged), or on the outer only?
5. **Names:** `nestedScrollPolicy` / `ztronNestedScrollPolicy` / `ZTronNestedScrollPolicy`, or the `ztronScrollPropagation`
   family?
6. **ZTronPages (Open item 2):** one arbiter in pager space, with each page declaring the arbiter's named space on its
   own root so participant frames stay page-local and cold (the pager converts its touch). Acceptable on your side?
7. **Binding shape:** anything the `.custom` closure and `ztronScrollDisabled(Bool)` do not cover for you?

## Orchestrator resolutions (2026-10-19, user: "procedi con la build N-a con i default raccomandati")
- R1 Default ON: nested `ZTronScrollView`s arbitrate with `.automatic` (= `.innerWhileScrollable`, UIScrollView
  parity) when nothing is specified; `.independent` restores today's behaviour.
- R2 Zoomed at the edge: `.automatic` pages (contract rule 5 / UIKit). The user's literal rule ("outer iff
  zoomScale == 1", rubber-band at the edge while zoomed) is `.innerWhenZoomed`, declared per view; the demo's zoomer
  page (N-b) uses it, and both policies are unit-tested in N-a.
- R3 Mid-gesture hand-off (inner edge → outer continues the swipe): later, not v1. Keep the `synthesizePan` route open.
- R4 The policy is declared on the inner view (`nestedScrollPolicy` member) or propagated by the environment
  (`ztronNestedScrollPolicy`); the same answer feeds a ZTronPages pager through the unchanged S16 participant.
- R5 Names: `ZTronNestedScrollPolicy`, `ZTronNestedScrollOwner`, `ZTronNestedScrollContext`,
  `ZTronScrollView.nestedScrollPolicy(_:)`, `View.ztronNestedScrollPolicy(_:)`.
- R6 ZTronPages: one arbiter in pager space with page-local participant frames is the proposed integration; it is the
  user's side (Open item 2) and is confirmed when ZTronPages adopts it. Nothing in N-a depends on it.
- R7 No Binding API in v1: `.custom` (non-tracked `ZTronNestedScrollContext`) and `ztronScrollDisabled(Bool)` cover
  the dynamic cases. ScrollArbitration's public API stays frozen (S16).
- Sequencing: N-a now (library + `NestedArbitrationTests`, both OS paths); N-b (demo `NestedPagerScreen` +
  `NestedPagerUITests`) and the docs/SPEC amendment follow once N-a is green and committed.


## 6. Mixed topologies (2026-10-21, user question: native `ScrollView` and bridged `UIScrollView`, both ways)

Shared fact: SwiftUI's `ScrollView` is a `UIScrollView` on iOS, and its pan is a UIKit recognizer whose delegate is
UIKit's. Our side can decide (arbiter), freeze itself (`.ignored`) and, on 15–16, observe (D31); it can never make a
UIKit pan it does not own give up a touch or skip a bounce. The only external levers are `isScrollEnabled`
(`scrollDisabled`, 16+, read by UIKit at touch-down) and SwiftUI gesture priority (fixed when attached, D12). Hence
the §3 guarantees (G1 one owner per swipe decided at the hysteresis with the direction known; G2 the loser frozen: no
motion, bounce or delegate; G3 policy; G4 iOS 15; S4 holds in every row below) degrade per topology:

| Topology | G1 | G2 | G3 | G4 | What it takes |
|---|---|---|---|---|---|
| **A** native `ScrollView` inside ZTron (outer ours) | yes: the outer asks its own arbiter | outer only; same-axis at the inner's edge = outer scrolls **and** inner bounces, so no edge take-over | per-axis constants; an 18+ `onScrollGeometryChange` edge mirror is possible but keeps the double motion | yes | pure SwiftUI, ~1 session: `.ztronNestedScrollPolicy(.inner)` on a native `ScrollView` registers a *passive region participant* (frame from a cold GeometryReader in the outer's content space, `canFollow` = its axes, `isMovingWithoutFinger` false). Rules 1/5 then make cross-axis drags exclusive (today a diagonal moves both; S12's "nested horizontal native ScrollView" row); use a 45° tolerance for native regions, UIKit's own axis test. Same axis: inner wins when touched, outer only outside it |
| **B** ZTron inside native `ScrollView` (outer theirs) | no: UIKit decides at touch-down from `isScrollEnabled`, no direction | inner only; the native outer scrolls whenever its pan begins | zoomed / not zoomed only | 16+; 15 only via the blocker → | caller side today: `ZTronScrollReader(state, of: { $0.zoomScale > 1 }) { zoomed in ScrollView { … }.scrollDisabled(zoomed) }` (derived reader: one re-render per crossing, S4-safe). Library options, both to spike on 15/17/18/27: (i) `.innerWhenZoomed` with no container makes the inner ignore one-finger pans at minimum zoom (else a tall-at-fit image moves with the outer); (ii) while zoomed, arm a `highPriorityGesture(DragGesture(minimumDistance: 10), including:)` blocker through the `GatedGestureAttach` pattern so the UIScrollView pan waits for it; Button/Slider inside zoomed content must be re-checked (D12 risk) |
| **C** bridged `UIScrollView` hosting ZTron (= T2 / ZTronPages) | yes | yes | full (§3, unchanged) | 18+ yes; ≤ 17 = note E, Open item 1 | nothing new in the library. The representable's `UIScrollView` subclass owns a `ReferenceScrollArbiter`, injects it into the hosted content's environment, allows simultaneous recognition with `scrollArbitrationGestureName` (18+), asks `containerOwner` from `gestureRecognizerShouldBegin` (or the first `.changed`, note B) and begins/ends sequences from a passive observer recognizer (note A). The spike app is the recipe |
| **D** bridged `UIScrollView` inside ZTron (inner theirs, cooperating) | yes | yes: its pan returns `false` from `gestureRecognizerShouldBegin` on `.container` | full, written by the caller as `canFollow` | yes | the representable reads `context.environment.scrollArbiter` and the arbiter's `coordinateSpaceName` (both public today), implements `ScrollArbitrationParticipant` on its `UIScrollView` subclass and asks `owner(...)` in `shouldBegin`. Worth a public `ztronScrollArbitrationParticipant(_:)` modifier that registers any participant with the nearest arbiter and keeps its frame cold (~1 session with a spike row). A vanilla `UIScrollView` is row A |

Not reachable: freezing a UIScrollView we do not own, and UIKit in the library beyond D31 (rows C/D are app-side
UIKit, rows A/B pure SwiftUI). Recommendation: C and D are the ZTronPages family and deserve the participant modifier
plus a written recipe; A is cheap and also fixes the diagonal double motion; B stays caller-side (`scrollDisabled`)
unless iOS 15 needs the blocker, which is a spike first. Open: which of A/B/D to brief, and a per-OS spike row for
B's blocker and D's `shouldBegin` timing (note B: the first UIKit sample can be 0–1 pt).

Builder briefs for rows A and D (three sessions: D1 shared plumbing, then A and D2 in parallel): `docs/design/NESTED-mixed.md` (2026-10-21).
