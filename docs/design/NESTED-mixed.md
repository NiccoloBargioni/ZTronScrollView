# NESTED-mixed · Builder briefs for rows A and D of NESTED-arbitration §6 (2026-10-21, pending the user's go)

Scope: `docs/design/NESTED-arbitration.md` §6 rows **A** (a native `ScrollView` or any opaque scroller inside a
ZTronScrollView: a *passive region*) and **D** (a bridged, cooperating `UIScrollView` inside a ZTronScrollView: a public
participant registration + the UIKit recipe). Row B stays caller-side, row C is ZTronPages (nothing to build). Built on
what N-a/N-b landed (D28, D30): `NestedScrollArbiter` (one per outer, `ReferenceScrollArbiter` bookkeeping, content-space
frames), `ArbitrationParticipant` + `ArbitrationRegistration`, `ZTronNestedScrollPolicy`. ScrollArbitration stays frozen
(S16); UIKit stays out of the library (D31 is the only exception and is untouched): rows A and D are pure SwiftUI in
`Sources/`, the UIKit half of D lives in the spike project. Three sessions, in this order: **D1** (library plumbing, shared),
then **A** and **D2** in parallel (disjoint files).

## 1. Shared design (D1 builds it, A and D2 use it)

**Public API** (`Sources/ZTronScrollView/Modifiers/ArbitrationModifiers.swift`, new):

```swift
import ScrollArbitration   // callers import it too: ScrollOwner / ScrollArbitrationParticipant are its types (no re-export, N-a review)

/// One registration with the nearest `ScrollArbiter`: an enclosing ZTronScrollView's nested arbiter, or an external one
/// (ZTronPages'). Own it in your representable's model, hand it to `ztronScrollArbitrationParticipant(_:)` on the
/// representable, set `participant` from `makeUIView`, and ask `owner(...)` from the UIKit side.
@MainActor public final class ZTronScrollArbitrationRegistration {
    public init()
    /// The object the arbiter consults (`canFollow`, `isMovingWithoutFinger`, `isZoomEnabled`). Held weakly. The
    /// registration happens once both this and an arbiter are present; clearing it unregisters.
    public weak var participant: (any ScrollArbitrationParticipant)?
    public var isRegistered: Bool { get }
    /// Once per touch sequence, at the UIKit pan's own slop (`gestureRecognizerShouldBegin`). `startLocation` is local to
    /// the registered view (touch-down: `location(in:) − translation(in:)`, minus `bounds.origin` for a UIScrollView).
    /// `.participant` with no arbiter, while unregistered, or while the container cannot take a swipe.
    public func owner(ofDragFrom startLocation: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner
}
extension View {
    /// Registers `registration` with the nearest arbiter using this view's frame in the arbiter's space; cold
    /// (appear, frame change, disappear). Apply it to the representable (or to the subtree whose frame is the scroller's).
    public func ztronScrollArbitrationParticipant(_ registration: ZTronScrollArbitrationRegistration) -> some View
}
```

**Internals.**
- Extract from `ArbitrationParticipant` the registration half into `Gesture/ArbitrationRegistrar.swift` (internal:
  `arbiter`, `token`, `frame`, `register(frame:)`, `update(frame:)`, `unregister()`, `owner(startLocation:translation:touchCount:)`
  = `frame.origin + startLocation`, exactly today's code). `ArbitrationParticipant` keeps `canFollow` / policy / motion and
  owns a registrar; `ZTronScrollArbitrationRegistration` wraps a registrar whose participant is the caller's object.
- Generalize the frame half of `ArbitrationRegistration` into `ParticipantFrameRegistration(registrar:)` (background
  `GeometryReader`, `.named(arbiter.coordinateSpaceName)`, `onAppear` / `onChange` / `onDisappear`), used by the existing
  modifier (which keeps `policy.joins(arbiter)` and `setArbiter`) and by the public one. The public one reads
  `@Environment(\.scrollArbiter)` and re-registers when the arbiter instance changes, like `setArbiter`.
- `NestedScrollArbiter`: a sequence that began **lazily** (at an ask, ≤ 17 without the outer's observer) is superseded by
  the next real `beginSequence()` instead of blocking it (today `beginSequence` is a no-op while active). An external
  participant cannot call `participantSequenceEnded()`, so a tiny drag the outer's pan never recognized must not leave a
  stale owner for the next swipe. Keep an internal `registrationSequenceEnded()` on the registrar for the D2 contingency (§3).
- `ZTronScrollArbitrationRegistration.owner` = registrar `owner` when registered, else `.participant`; the nested
  arbiter's `isArbitrating` guard already covers a disabled container.
- Hit-testing: when the outer owns the sequence its D11 gate disables the content, so a UIKit participant's touches are
  cancelled by UIKit itself; when the participant owns, the outer is `.ignored` and nothing is gated. No new code.

**D1 tests** (`Tests/ZTronScrollViewTests/ArbitrationRegistrationTests.swift`, both OS paths, the `NestedArbitrationTests`
rig plus a fake participant object): register / update / unregister through the public type, including participant set
after the modifier and cleared later; `owner` before registration = `.participant`; `owner` through a nested arbiter
with the fake answering `canFollow` true / false at zoom 1 / zoomed (rows of §1 of NESTED-arbitration with the fake as
the inner); decision cached across the outer's `containerOwner` and the registration's `owner`, both orders; disabled
outer = `.participant` without a decision; lazily-begun sequence superseded by a real touch-down; existing
`ArbitrationTests` + `NestedArbitrationTests` unchanged and green (the refactor is behaviour-preserving). Budget ≈ 1–1.5 %.

## 2. Brief A · passive region (`ztronNestedScrollRegion`)

**Goal.** A native `ScrollView`, a vanilla `UIScrollView` representable or any view that drags along some axes can tell the
enclosing ZTronScrollView (or an external arbiter) which drags are its own, so cross-axis drags become exclusive (today a
diagonal on a nested horizontal native `ScrollView` moves both; S12 checklist row) and same-axis drags that start on it
stay with it. The region can never be frozen (§6 row A): the modifier's answers are constants, so the container takes an
on-axis swipe only off the region's axes, where the native scroller's own UIKit test already fails its pan.

**Public API** (same file as §1):

```swift
extension View {
    /// Declares this subtree as a scroller the container cannot consult. Drags that start here along `axes` belong to it;
    /// drags along other axes go to the container. `zooms` keeps two-finger sequences here (rule 2).
    public func ztronNestedScrollRegion(_ axes: Axis.Set = [.horizontal, .vertical], zooms: Bool = false) -> some View
}
```
Call site: `ScrollView(.horizontal) { … }.ztronNestedScrollRegion(.horizontal)` inside a vertical ZTronScrollView.

**Behaviour.**
- Internal `PassiveRegionParticipant: ScrollArbitrationParticipant` (`Gesture/PassiveRegionParticipant.swift`, new):
  `canFollow(d)` = `axes` contains `d`'s axis; `isMovingWithoutFinger` = false; `isZoomEnabled` = `zooms`. Registered
  through a `ZTronScrollArbitrationRegistration` + `ParticipantFrameRegistration` (§1); one participant per modifier
  identity (`@StateObject`-style holder), updated when `axes` / `zooms` change (cold).
- Tolerance: `NestedScrollArbiter` tags region tokens (internal `register(_:frame:kind:)`) and, in `prepare`, uses
  `reference.participant(at: start)` to pick **45°** for a region under the start point (UIKit's own dominant-axis test for
  the native scroller: with 30° a drag 30°–45° off the outer's axis would be left to a native scroller that fails its
  pan, and nothing would move). ZTron inners keep 30° (contract default). `prepare` gains the `start` argument.
- With an external arbiter (ZTronPages) the region registers the same way; only `containerOwner` ever resolves it.
- Nothing is automatic: a native `ScrollView` without the modifier behaves as today.

**Tests.**
- Unit `NestedRegionTests` (both OS paths; rig + `addRegion(axes:frame:zooms:)`, the outer's pan events drive
  `containerOwner`): horizontal region in a vertical outer: horizontal → region (outer `.ignored`), vertical → outer,
  44° / 46° off the outer's axis → outer / region; vertical region in a vertical outer always wins when touched, outer
  wins outside it; region overlapping a ZTron inner → smallest frame; `zooms` + two fingers → region; region with a
  `ReferenceScrollArbiter` instead of the nested one; unregister on disappear; `update` count equals frame changes
  (cold); tolerance 30 kept for a ZTron inner in the same outer.
- Demo `NestedNativeScreen` (`-ZTronScreen nestedNative`; `-ZTronNativeRegion off` strips the modifiers): vertical outer,
  row 1 horizontal native `ScrollView` (16 cells) with `.ztronNestedScrollRegion(.horizontal)`, row 2 vertical native
  `ScrollView` (200 pt tall, 1000 pt content) with `.vertical`, row 3 horizontal native without the modifier (control);
  native offsets reported by a GeometryReader + PreferenceKey inside each native content into `stateInfo` (demo-only).
  `NestedNativeUITests`: horizontal swipe on row 1 → native x moves, outer y unchanged; vertical swipe on row 1 → outer
  moves, native x unchanged; 20° off vertical on row 1 → outer only (the same drag on row 3 is recorded, not asserted);
  vertical swipe on row 2 → native y moves, outer unchanged; swipe outside the rows → outer; `content.body` 0 during
  every swipe; 27.0 + 17.5, preferred + forced (`scripts/test-demo-ui.sh`).
- Files owned: `Gesture/PassiveRegionParticipant.swift`, `Gesture/NestedScrollArbiter.swift` (tolerance + `prepare(start)`),
  `Modifiers/ArbitrationModifiers.swift` (region modifier only, after D1), `Tests/…/NestedRegionTests.swift`,
  `Demo/ZTronScrollViewDemo/NestedNativeScreen.swift`, `DemoApp.swift` routing line, `Demo/…UITests/NestedNativeUITests.swift`.
  Budget ≈ 2–3 %. Depends on D1.

## 3. Brief D · cooperating UIScrollView inside ZTronScrollView (D2: recipe + spike)

**Goal.** Prove on device-class simulators that a `UIScrollView` subclass, bridged into a ZTronScrollView page, gets the
full §3 guarantees through the public registration: one owner per swipe, the loser frozen (the UIKit pan returns `false`
from `gestureRecognizerShouldBegin` on `.container`), the policy written as `canFollow`. Deliver the recipe developers copy.

**Home.** `Packages/ScrollArbitration/Spike/ArbitrationSpike.xcodeproj`, a **new app target** `ArbitrationSpikeNested` (+
`ArbitrationSpikeNestedUITests`) that depends on ScrollArbitration *and* on the root ZTronScrollView package (local
reference `../../..`); the existing `ArbitrationSpike` target keeps depending on the contract only, so it still travels
with the contract repository. UIKit is allowed there (CLAUDE.md). `scripts/test-spike.sh` gets a `--scheme` argument
(default unchanged). Open question for the user: this home, or a `Demo/…/UIKitRecipes` folder with the UIKit rule relaxed?

**Recipe** (`Spike/ArbitrationSpikeNested/ArbitratedZoomScrollView.swift` + `NestedZoomerScreen.swift`; the doc copy is
this section):

```swift
final class ArbitratedZoomScrollView: UIScrollView, UIScrollViewDelegate, ScrollArbitrationParticipant {
    let registration = ZTronScrollArbitrationRegistration()           // the SwiftUI side registers it (frame, arbiter)
    var policy: Policy = .uikit                                        // .uikit: zoomed && not at the edge; .innerWhenZoomed
    // image view as the zoom view, minimumZoomScale 1, maximumZoomScale 4, delegate = self
    func canFollow(_ d: FingerDirection) -> Bool {                     // rule 5; rules 1–4 are the arbiter's
        guard isScrollEnabled, zoomScale > minimumZoomScale + 0.001 else { return false }
        if policy == .innerWhenZoomed { return true }
        switch d {                                                     // finger right/down ⇒ offset decreases
        case .right: return contentOffset.x > -adjustedContentInset.left + 0.5
        case .left:  return contentOffset.x < contentSize.width - bounds.width + adjustedContentInset.right - 0.5
        case .down:  return contentOffset.y > -adjustedContentInset.top + 0.5
        case .up:    return contentOffset.y < contentSize.height - bounds.height + adjustedContentInset.bottom - 0.5
        }
    }
    var isMovingWithoutFinger: Bool { isDecelerating || isZoomBouncing || (layer.animationKeys()?.isEmpty == false) }
    var isZoomEnabled: Bool { maximumZoomScale > minimumZoomScale }
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g === panGestureRecognizer else { return super.gestureRecognizerShouldBegin(g) }   // pinches never ask (S12)
        let now = panGestureRecognizer.location(in: self), t = panGestureRecognizer.translation(in: self)
        let start = CGPoint(x: now.x - t.x - bounds.origin.x, y: now.y - t.y - bounds.origin.y)   // viewport-local touch-down
        return registration.owner(ofDragFrom: start, translation: CGSize(width: t.x, height: t.y),
                                  touchCount: panGestureRecognizer.numberOfTouches) == .participant
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
        if #available(iOS 18, *), o.name == scrollArbitrationGestureName { return true }
        return !(o.view is UIScrollView)                               // the hosting view's SwiftUI recognizers (≤ 17 unnamed)
    }
}
struct NestedZoomer: UIViewRepresentable {                             // one per page
    let view: ArbitratedZoomScrollView                                 // owned by a @StateObject model, created up front
    func makeUIView(context: Context) -> ArbitratedZoomScrollView { view.registration.participant = view; return view }
    func updateUIView(_ v: ArbitratedZoomScrollView, context: Context) {}
}
// page: NestedZoomer(view: model.zoomers[i]).ztronScrollArbitrationParticipant(model.zoomers[i].registration)
// outer: ZTronScrollView(.horizontal, state: pager) { HStack(spacing: 0) { pages } }   // pager.isPagingEnabled = true
```

**Spike questions (one row per OS: 17.5, 18.x, 26.x, 27.0; the recorder pattern of `ArbitratedPagingScrollView`).**
1. Pan began ⇔ `.participant`, never on `.container` (Q1 mirrored); exactly one decision per sequence whichever side asks
   first; the outer's `.ignored` sequence leaves its offset / phase / delegate untouched.
2. Translation magnitude at the participant's `gestureRecognizerShouldBegin` (note B measured 0–1 pt and 7–10 pt on the
   container side). If it is routinely < 4 pt, switch the recipe to "begin, ask at the first `.changed` ≥ 10 pt, cancel
   the pan (`isEnabled` toggle) and restore the offset on `.container`", and record which variant each OS needs.
3. ≤ 17: does the outer's SwiftUI pan keep receiving `.changed` while the UIKit pan owns (simultaneous recognition from
   the subclass), so the outer ends the sequence at the lift? If not, make the registrar's `registrationSequenceEnded()`
   public and call it from the pan's `.ended` / `.cancelled` (contingency, §1).
4. A second finger during an outer-owned drag: the UIKit pinch zooms, the outer releases (R1), no stuck sequence.

**UI tests** (`ArbitrationSpikeNestedUITests`, `DragScript`): zoom 1 swipe left → page 1, UIKit offset unchanged; zoom to 4×
(XCUI `pinch(withScale:velocity:)`) → swipe → UIKit offset moves, page stays; swipe at the zoomed edge → pages under
`.uikit`, rubber-bands under `-policy innerWhenZoomed`; swipe starting on the outer outside the zoomer → pages; vertical
swipe at zoom 1 → nothing pages. Record spike question 2's samples in the on-screen log for every drag.

Files owned: the new target's sources and tests, `project.pbxproj`, `scripts/test-spike.sh` (`--scheme`), this file's
results table (§4). Budget ≈ 2–2.5 % plus the spike matrix runs (~25 min per OS). Depends on D1; parallel with A.

## 4. Results (filled by D2) and resolutions

| OS | Q1 pan ⇔ owner | Q2 Δ at shouldBegin (pt) | Q3 outer sees `.changed` (≤ 17) | Q4 second finger | Variant |
|---|---|---|---|---|---|
| 17.5 | | | | | |
| 18.x | | n/a | | | |
| 26.x | | n/a | | | |
| 27.0 | | n/a | | | |

Open for the user: (1) D2's home (spike target with a root-package reference, or a relaxed UIKit rule for a demo recipes
folder); (2) the region default `axes` = both (yield everything) or no default (explicit axes); (3) the 45° region
tolerance, kept or made a parameter. Orchestrator resolutions: to be appended.

## Orchestrator resolutions (2026-10-21, user)
- R1 D2's home: a new `ArbitrationSpikeNested` app target (+ UI-test target) in `Packages/ScrollArbitration/Spike/ArbitrationSpike.xcodeproj`
  with a local reference to the root ZTronScrollView package (`../../..`); the `ArbitrationSpike` target keeps depending on the
  contract only. The UIKit rule (CLAUDE.md, D31) stays as it is: no UIKit in `Sources/` or `Demo/`.
- R2 `ztronNestedScrollRegion(_:zooms:)` defaults `axes` to `[.horizontal, .vertical]` (yield everything).
- R3 The region tolerance is a constant 45° (UIKit's dominant-axis test), not a parameter.
- Sequencing confirmed: D1 (shared plumbing) first; A and D2 in parallel once D1 is green and committed.
