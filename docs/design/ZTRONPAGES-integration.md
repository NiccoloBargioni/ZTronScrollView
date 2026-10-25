# ZTRONPAGES · How the ZTronPages pager must be built so ZTronScrollView pages arbitrate on iOS 15–27 (design, pending the user)

Scope: Orchestration D50 and Open items 1, 2, 8 (user, 2026-10-25: "si stabilisce un design che permetta di superare questa limitazione").
Built on SPEC S12 "Inside a pager" / "Nested" / "Inside a bottom sheet", S16 (frozen 1.0.0: **nothing here changes the public API of
`Packages/ScrollArbitration`**), MC-contract §5–§6 (notes A–E), NESTED-arbitration §1–§6 + R1–R7 (D28), NESTED-mixed, D31, D36.
Read on unmerged branches (nothing merged): Q3-s1 (`claude/spike-q3-descendant-simultaneous`, be292d7: container-side ≤ 17 fix),
DBG-s8 / D47 (`claude/confident-babbage-6acfe7`: 26 SDK recognition order), SHEET-s3 (`claude/sweet-payne-efd027`: 18.x pan
attach, native `TabView` pager measured), DBG-s3/s4/s5 (D34, D37, D40: observer and pan attach per OS). Old ZTronPages
(`ZombieTron/.../Utils/Pages/`, read-only) for intent: a `UIViewControllerRepresentable` over a `UIPageViewController` with SwiftUI
(`UIHostingController`) and UIKit pages, a step topbar or paging dots, `goToPage`, `onCurrentPageChanged`, a bottom-controls inset, and
hand-written rotation fix-ups on the private queuing scroll view. No production code; no SPEC edit until the user decides.

## 0. Recommendation (one paragraph)

**Build ZTronPages as a paging `ZTronScrollView` container on every OS (15–27).** A horizontal `ZTronScrollView` with paging, whose
content is one viewport-sized view per page. Pages that hold `ZTronScrollView`s arbitrate through the nested arbiter that D28 already
ships: both recognizers are SwiftUI gestures in one hosting view, so note E (≤ 17 UIKit-pan starvation) and D47 (26 SDK: first recognizer
to begin wins) cannot occur. The decision is made once per swipe by the frozen `ScrollArbitrationRules`. This *is* D50's "SwiftUI pan" on
15–17, and the same code runs on 18+. The library keeps naming its gestures `scrollArbitrationGestureName` (already done on 18+), so a
UIKit-hosted pager stays possible as a documented recipe (§2.3). That recipe needs ZTronPages' own `UIScrollView` subclass. It uses names
on 18+ and Q3-s1's `cancel` rule on 15–17 (that rule is "a recognizer outside the hosting view"). It is not the core: two physics stacks
and two test matrices for one product. The physics parity, rotation (S7 re-snap), S4, the catch and the iOS 15–16 observer (D31) all
come from ZTronScrollView for free. One premise changes: S16's first line says ScrollArbitration is the *only* code shared with
ZTronPages. Under this design, ZTronPages depends on ZTronScrollView (Open question 1).

## 1. Topologies and the per-OS gesture matrix

Swipe that starts on a `ZTronScrollView` inside a page (zoomer or vertical list). ✓ = arbitrated, one owner per swipe, loser frozen;
✗ = broken; ? = not measured. "Stand-in" = the spike's SwiftUI participant, not a real ZTronScrollView.

| # | Topology | 15–16 | 17 | 18.x | 26–27 | Evidence |
|---|---|---|---|---|---|---|
| T1 | **SwiftUI pager = paging ZTronScrollView** (§2.2) | ✓ expected (D31 observer begins the sequence; real device: user) | ✓ (sequence begins lazily at the first ask) | ✓ | ✓ | N-b `NestedPagerUITests` green on 27.0 + 17.5 (D30) and 18.5 (SHEET-s3 run); `NestedArbitrationTests` both OS paths |
| T2 | SwiftUI-pan pager that implements `ScrollArbiter` itself (`PagerScreen` stand-in) | ✓ expected | ✓ | ✓ | ✓ | `PagerUITests` 27.0 + 17.5; but it brings its own physics and its own observer (D34/D37 control traps) |
| T3 | UIKit pager: ZTronPages' own `UIScrollView` subclass, `UIHostingController` pages | ? (`cancel` rule, unmeasured) | ✗ without the rule (note E); ✓ with Q3-s1 `cancel` (17.5, stand-in) | ✓ names (18.6, stand-in) | ✓ names (26.5, 27.0, stand-in) | MC §6, Q3-s1 |
| T4 | `UIPageViewController`, `TabView(.page)`, native paging `ScrollView` with ZTron pages | ✗ (note E) | ✗ | partial: `TabView` turns, no arbitration | ✗ (D47; `TabView` stays on its tab on 27.0) | SHEET-s3: a vertical ZTron list in a `TabView` pager never turns the page on 17.5 / 27.0 |
| T5 | T1 or T3 inside a `.sheet` | pages ✓; a drag on the pager never moves the sheet (D36); `ztronScrollYieldsToSheet` = inert | same | same (18.x shares the drag in some attach modes: D46 / SHEET-s3) | same | SHEET-s1/s2 |
| T6 | T1 pushed in a `NavigationStack` | ? edge back swipe | ? | ? | ? edge swipe + 26's content back swipe | not measured: risk R1, test A11 |
| T7 | T1 inside a native vertical `ScrollView` | page scrolls beside the pager (row B) | same | same | ✗ the page never scrolls under a drag on the pager (D47) | DBG-s8 |
| T8 | T1 inside a vertical `ZTronScrollView`, or pager → list → zoomer | three levels: the middle view does not OR its inner's `canFollow` → possible double motion (S12 "phase 2") | same | same | same | D28 |

Supported: T1 (the product), T3 as a recipe, T5 with the documented sheet limitation, T6 after A11 passes, and T8 after P-c. T4 is not
supported, because nobody can install the simultaneity rule on a pan whose delegate is private (Q3-s1). T7 on 26+ is D47's limitation.

## 2. Architecture

### 2.1 Options

| | A · dual path (UIKit pager + names on 18+, SwiftUI pan on 15–17) | **B · paging ZTronScrollView (T1)** | C · own SwiftUI-pan pager over the contract (T2) | D · UIKit pager on all OS (T3: names 18+, `cancel` ≤ 17) |
|---|---|---|---|---|
| Arbitration code in ZTronPages | two paths | none: D28's container role | arbiter + sequence + ask | delegate + `shouldBegin` + observer + cancel |
| Paging physics | UIScrollView on 18+ and its own on ≤ 17: they diverge | ZTron `PagingSolver` (S6: `.paging` parity, ≤ 1 page per gesture) | its own, to calibrate | UIScrollView |
| Rotation keeps the page | UIKit fix-ups + its own | S7 + M5 §6 (`pagingIndex` re-snap) | its own | UIKit fix-ups (old ZTronPages l.473–590) |
| Catch / touch during settle (rules 3–4) | two implementations | ZTron catch + `isMovingForNestedArbiter` | its own observer: hits D34/D37 control traps | UIKit + observer recognizer (note A) |
| iOS 15–17 | SwiftUI pan | ✓ | ✓ | `cancel` rule: 17.5 only, stand-in only |
| UIKit in ZTronPages | yes | no | no | yes |
| Depends on ZTronScrollView | no | **yes** (S16 premise) | no | no |
| Test matrix | 2× | 1× (reuses the N-b rig) | 1× + physics calibration | 1× + the spike harness per OS |
| Cost (builder) | ≈ 8–10 % | **≈ 3–4 %** | ≈ 6–8 % | ≈ 5–6 % + 15/16 runs |

**Recommended: B.** C is the fallback if the user refuses the dependency. D is the recipe for an app that must page in UIKit. A is
rejected: it gives the same product two feels and two sets of bugs, and buys nothing that B or D lacks.

### 2.2 B in detail

**Shape** (names are illustrative; ZTronPages' own API is the user's):

```swift
public struct ZTronPagesView<Page: View>: View {
    public init(count: Int, currentPage: Binding<Int>, @ViewBuilder page: @escaping (Int) -> Page)   // also a data-driven init
}
// body, cold except where noted:
GeometryReader { geo in                                       // the page size = the viewport (S6); read cold, outside the scroller
    ZTronScrollView(.horizontal, state: state) {
        HStack(spacing: 0) { ForEach(0..<count, id: \.self) { page($0).frame(width: geo.size.width, height: geo.size.height).ztronScrollID($0) } }
    }
    .scrollTargetBehavior(.paging)                            // ≡ isPagingEnabled (S6); ZTron's member, S8 parity
    .scrollPosition(id: $settledPage)                         // M6-s3; the current-page binding
    .scrollIndicators(.hidden)
}
.onZTronScrollPhaseChange { _, new in if new == .idle { onCurrentPageChanged(settledPage) } }   // settle time, like didFinishAnimating
```
Use count- or data-driven inits rather than a variadic `@ViewBuilder` of pages: `_VariadicView` is underscored SPI, and
`ForEach(subviews:)` is 18+ only. Chrome (topbar, dots, live progress) lives outside the scroller. Live progress comes from
`onZTronScrollGeometryChange(for:of:)` into a leaf (render-time only), never into page bodies (S4). `goToPage(k)` writes the binding or
calls `state.setContentOffset(CGPoint(x: k·w, y: 0), animated:)`. The old bottom-controls inset becomes an environment value or a
content margin per page; it is unrelated to arbitration.

**Where the pan lives.** It is the outer ZTronScrollView's own pan (`PanGestureAdapter`: SwiftUI `DragGesture` + catch observer). It is
attached to the pager's viewport, in the same hosting view as every page. There is no UIKit recognizer, so names are irrelevant here.
D50's "SwiftUI pan" holds on every OS.

**How the arbiter is asked.** ZTronPages asks nothing itself. The outer's `PanCoordinator` is a container as soon as an inner registers
(`env.isContainer`). The inner registers its frame in the outer's *content* space (`NestedScrollArbiter`, named space on the content).
That frame is page-local plus the page origin and does not change while paging, so registration stays cold (S4). R6 is met
automatically. Each side asks once, at its own ≥ 10 pt hysteresis. The inner asks `owner(...)`; the outer asks `containerOwner(...)`
through `nestedStart`. The first ask decides through `ScrollArbitrationRules.decide`; the second hits the cache. When a sequence begins:
- 18+ on main: at the outer's touch-down (`SpatialEventGesture`);
- 15–16: at the D31 window observer's touch-down;
- 17, and 18–27 once D37 is merged (spatial events from 28): lazily at the first ask.

Rule 4 still sees a settling pager in the lazy case, through `caughtUndecided` (`isMovingForNestedArbiter`).

**How the participant drops `.container`.** `PanSession.decided(.container)` sets `.ignored` for the whole sequence: no baseline, offset,
rubber band, indicator, delegate or phase change (`ArbitrationTests.containerIgnoresWholeSequence`). While the outer drags, its D11 gate
disables the content, which cancels the inner's SwiftUI gestures (`cancelIfActive`), so the drop is physical as well as logical. Under
`.participant` the outer is `.ignored` instead, and the inner pans or zooms. A pinch never asks (rule 2: `isZoomEnabled` mirrors the zoom
range since N-a).

**Policy.** The default is `.automatic` (UIScrollView parity: a zoomed page at its edge pages). The user's literal rule ("page iff zoom ==
1") is `.innerWhenZoomed`. ZTronPages can forward a pager-wide default with `.ztronNestedScrollPolicy(_:)`, the environment twin: it
propagates to every page, and a page can still override it with the member.

**Paging physics.** ZTron's `PagingSolver` (M1 §4) moves at most one page from the page containing the drag start. Its direction comes
from velocity above the flick threshold, otherwise from displacement over half a page, and its spring never overshoots the target. It
bounces at the first and last page like UIScrollView. Parity is checked against the native `ScrollView` + `.scrollTargetBehavior(.paging)`
(17+), with a native baseline lane as in BTN-s1/s2 (test A10). That follows Open item 9 ("compare against native"). Peeking carousels use
`ZTronViewAlignedScrollTargetBehavior` (M6-s2). `interPageSpacing` needs `scrollClipDisabled` (S8, not built) or a gap inside the page.

**Page kinds.** ZTronScrollView pages are participants by default (D28). A native `ScrollView` page is NESTED §6 row A
(`ztronNestedScrollRegion`, NESTED-mixed brief A, not built). Until that lands, a diagonal drag can move both. UIKit pages (old
`ZTronPage.uikit`) are `UIViewControllerRepresentable` pages. A cooperating `UIScrollView` inside one is row D (public registration,
NESTED-mixed D1/D2, not built). Lazy pages use `ZTronLazyHStack` (M9, data-driven, virtualizes on 15+; todo). Until M9, the `HStack` is
eager: each page body runs once at build, and S4 holds afterwards.

### 2.3 The UIKit route (T3), recipe only, in ZTronPages' repo (UIKit is never in this library outside D31's directory, SPEC S2)

The pager is ZTronPages' own `UIScrollView` subclass (`isPagingEnabled`, `delaysContentTouches = false`, `canCancelContentTouches =
true`) whose pan delegate it owns. `UIPageViewController` cannot work: its queuing scroll view's pan delegate is private. Pages are
`UIHostingController`s with **one `ReferenceScrollArbiter` per page**, injected with `.environment(\.scrollArbiter, …)`, and
`.coordinateSpace(name:)` is set on each page root. The rules:
- **Observer (note A).** Hosting views swallow `touchesBegan`. A never-recognizing `UIGestureRecognizer` on the scroll view
  (`cancelsTouchesInView = false`, no delays, simultaneous with everything) records the touch-down page and point, sets
  `isContainerMoving = isDecelerating || isDragging`, then calls `beginSequence()` on that page's arbiter. On the last lift it calls
  `endSequence()` and then `clearLog()`.
- **18+.** `shouldRecognizeSimultaneouslyWith` returns `other.name == scrollArbitrationGestureName`. `gestureRecognizerShouldBegin(pan)`
  returns `containerOwner(ofDragFrom:translation:touchCount:) == .container` from the touch-down page's arbiter. Q1/Q2/Q4/Q5 were yes on
  18.6, 26.5 and 27.0. On 26+ this also sidesteps D47, because a simultaneous delegate is Apple's FB18199844 workaround.
- **15–17 (Q3-s1 `cancel`).** `shouldRecognizeSimultaneouslyWith` returns `other.view?.isDescendant(of: touchDownPage.view)`. When the pan
  reaches `.began`, every enabled recognizer inside that page is reset (`isEnabled = false; isEnabled = true`). `descendant` alone is not
  adoptable: it fires a Button under a container-owned drag. The ZTron page maps the reset (no `onEnded` on 17) to `cancelIfActive()`.
  Measured on 17.5 with the stand-in only. Before adoption it needs a real ZTronScrollView page and real 15/16 runs. The D31 window
  observer sits outside the page and never recognizes, so the rule neither grants it simultaneity nor cancels it.
- **Early sample (note B).** `shouldBegin` can fire at 0–1 pt. Ask with `pan.translation(in:)` when its length is ≥ 8 pt, otherwise with
  `pan.velocity(in:)`. The rules read only the angle and the sign, so this is the container's own sample choice and legal under the
  contract. Even then, rule 1 near 30° stays recorded, not asserted.

## 3. The MC spike notes, one by one

| Note | Under B (core) | Under the T3 recipe |
|---|---|---|
| A · hosting views swallow `touchesBegan` | n/a: sequences begin from ZTron's own observer (18+ spatial, 15–16 D31, otherwise lazily). No UIKit in ZTronPages | never-recognizing observer recognizer on the pager (§2.3), in ZTronPages' repo. D31-style, but S2's UIKit exception is this library's and does not cover the pager |
| B · first ask < 10 pt, rule 1 noisy near 30° | n/a: both sides ask at a ≥ 10 pt SwiftUI hysteresis with the `DragGesture` translation; 20° / 40° asserted (A4) | translation ≥ 8 pt or velocity (§2.3); 40° recorded, not asserted |
| C, D · foreign recognizers `.began` on taps (Toggle on 27.0; `UIKitResponderGestureRecognizer` on 18.6) | n/a: no recognizer-state checks anywhere; rule 5 is `canFollow` through `owner(...)` | key rule 5 on the arbiter's answer only; simultaneity by name (18+) or by view ancestry (≤ 17), never by class name or recognizer state |
| E · ≤ 17 UIKit pan starved | cannot occur: no UIKit pan | Q3-s1 `cancel` (§2.3), pending a real page and 15/16 runs |
| Representable or not | none: ZTronPages is a SwiftUI `View`. A UIKit app hosts it in a `UIHostingController`; UIKit pages are representables inside it | a `UIViewControllerRepresentable` around the pager VC puts a hosting view *above* the pager. The spike never measured that (it used the UIKit app lifecycle on purpose): test U3 before adoption |
| One arbiter per page vs. one in pager space (R6) | one: the outer's `NestedScrollArbiter`, frames in the outer's content space (page-local + page origin, cold) | one per page: separate hosting hierarchies would register colliding page-local frames in a single arbiter (MC §5). R6's single arbiter would need a per-page forwarding `ScrollArbiter` adding k·w to frames: legal, gains nothing |

## 4. Acceptance tests (this repo; ZTronPages does not exist yet)

A **stand-in** in the demo: `PagesScreen` (`-ZTronScreen pages`) composes B exactly as in §2.2 (demo-only `DemoPages` view, no library
change). Page 0 is a 16:9 zoomer (1…4, double tap; policy from `-ZTronPagesPolicy automatic|innerWhenZoomed`). Page 1 is a vertical
ZTron list of 40 rows. Page 2 holds a Button, a Slider and a Toggle. Page 3 is static. The readout sits outside the scroller: `page`,
offsets, zoom, `decided` count and first asker from the nested log (DEBUG hook), and `content.body` counters. `PagesUITests`:

| # | Script | Expect |
|---|---|---|
| A1 | swipe left at zoom 1 on page 0 | page 1, zoomer offset 0, one decision, `content.body` 0 during the swipe |
| A2 | double tap to 4×, swipe left | zoomer pans, page stays 0 |
| A3 | zoomed, pan to the trailing edge, then swipe left again | `.automatic`: second swipe pages; `.innerWhenZoomed`: rubber-bands, page 0. The edge reached *during* a swipe never pages that swipe |
| A4 | page 1, drags at 0° / 20° / 40° / 90° off horizontal | 0°, 20° page; 40°, 90° scroll the list, pager x unchanged (rule 1, ≥ 10 pt samples) |
| A5 | pinch on page 0 at zoom 1 | zooms, never pages (rule 2) |
| A6 | fling to page 1, press during the settle | the pager keeps the touch (rule 4); recorded, not asserted (timing) |
| A7 | page 2: tap Button / Toggle; drag that starts on the Button; horizontal drag on the Slider | taps fire; the drag pages and does not fire; Slider vs pager recorded per OS (UIKit: `touchesShouldCancel` keeps controls; S12 row) |
| A8 | rotate on page 2 (landscape and back), also during a settle | still page 2, re-snapped (S7, M5 §6) |
| A9 | `goToPage(3)` button; binding observer | page 3; the binding's reader body runs once per page change, never per frame |
| A10 | native lane: same flings on `ScrollView` + `.scrollTargetBehavior(.paging)` (17+) | same settled page; settle time within the BTN-lane tolerance |
| A11 | `-ZTronPagesHost nav`: pushed in a `NavigationStack`; edge back swipe on page 0 and page 2; 26+ content back swipe | recorded per OS first: decides whether T6 is supported or documented |
| A12 | `-ZTronPagesHost sheet`: in a `.sheet` at medium | page swipes work; a vertical drag on the pager does not move the sheet (D36), recorded |

Matrix: 27.0 and 17.5, preferred and forced, plus the `-ZTronForceUIKitObserver` lane (the 15–16 code path) on both. 18.5 runs once to
check D34/D40/SHEET-s3 interplay. Use private clones staggered per lane (memory note). Real iOS 15/16 and the device feel are left to the
user (Open item 5), including Open item 8's second finger landing while the pager owns a drag (not scriptable). The unit side reuses the
`NestedArbitrationTests` rig: a 4-page outer with a zoomer and a list registered in content space, and a resolution test by smallest frame
across pages. **T3 (only on the user's yes):** U1 the spike pager with a real ZTronScrollView page on 17.5 (`cancel`) and 27.0 (names);
U2 the `pEnd` / `cancelIfActive` mapping; U3 the pager inside a `UIViewControllerRepresentable`. The home is a separate spike project, not
`Packages/ScrollArbitration/Spike`, so the contract package never depends on ZTronScrollView.

## 5. What stays impossible (document; SPEC S12 amendment text when decided)

1. **Pagers whose pan delegate ZTronPages does not own** (`UIPageViewController`, `TabView(.page)`, a native paging `ScrollView`) with
   ZTron pages: no simultaneity or `shouldBegin` rule can be installed. On ≤ 17 note E starves them; on 26+ D47 blocks them; on 18.x they
   move without arbitration. Not supported.
2. **Mid-swipe hand-off** (an edge reached during a swipe): the decision is per swipe (S12 Scope). B could add it later through
   `synthesizePan` (NESTED R3). T3 cannot add it without a contract revision.
3. **Sheets:** a drag that starts on the pager never moves or dismisses the sheet (D36). `ztronScrollYieldsToSheet(true)` makes the pager
   inert to *all* drags, paging included. Pure SwiftUI has no axis-selective yield: a `DragGesture` has no axis, and per-axis attach was
   tried in D47. Recipe: drive `yields` from the detent, as SHEET-s2 does.
4. **A native vertical `ScrollView` around the pager on the 26 SDK:** the page never scrolls under a drag that starts on the pager (D47).
   Use a vertical `ZTronScrollView` parent, which is three levels (P-c) if pages hold ZTron views.
5. **A non-cooperating scroller in a page** (native `ScrollView`, vanilla `UIScrollView`) can never be frozen. On the same axis at its
   edge, both move (NESTED §6 row A).
6. Not provided: page-curl transitions, and looping pages (wrap-around would re-evaluate bodies, S4) in v1.
7. Real iOS 15/16 cannot be run on this Mac (macOS 27). Those results stay the user's.

## 6. Builder split, budget, risks

| Session | Owns | Done when | Est. |
|---|---|---|---|
| **P-b** demo stand-in (Sonnet builder, first: it proves B before ZTronPages exists) | `Demo/ZTronScrollViewDemo/PagesScreen.swift`, `DemoApp.swift` routing line, `Demo/…UITests/PagesUITests.swift`, a DEBUG decision readout if none exists | A1–A12 green or recorded on the §4 matrix, handoff `PAGES-s1.md` | 2–2.5 % |
| **P-c** library phase 2: three levels (Sonnet builder, parallel with P-b, disjoint files) | `Gesture/ArbitrationParticipant.swift` and `PanCoordinator.swift`: a middle view's `canFollow` ORs in "an inner under the touch-down point can follow" (the catch gives the point before the ask); `NestedArbitrationTests` three-level rows | pager → list → zoomer has no double motion on both OS paths; existing arbitration suites unchanged | 2–3 % |
| **P-a** ZTronPages core (after P-b green; home per Open question 2) | `ZTronPagesView` (count and data inits, binding, `goToPage`, settle callback, progress leaf, policy forwarding, chrome slots) | the P-b screen ported onto it stays green | 3–4 % |
| P-d T3 harness (optional, user's yes) | separate spike project, U1–U3 | per-OS rows recorded | 2–3 % + runs |
| docs (clerk) | SPEC S12 "Inside ZTronPages" + the S16 premise line, parity rows, Orchestration, the next free D-number (check `git log --all`) | — | 0.5 % |

Nobody touches `Packages/ScrollArbitration` or `ZTronScrollPhysics`. Total for B ≈ 8–10 % with P-c, or ≈ 6 % without it.

**Risks.**
- R1: back swipes in a `NavigationStack` (edge and 26's content swipe) against a horizontal SwiftUI pan are unmeasured. D47's rule
  (first to begin wins, ties go to SwiftUI) may let the pager steal them on 26+ (A11).
- R2: unmerged D40 (`.adaptive`: the pan becomes a `.gesture` for views that share no drags) and SHEET-s3 (18.x exclusive pan for
  vertical views) must keep `sharesDrag` true for containers and participants. Re-run P-b after either merges.
- R3: M5 (b) is partial (resize rebase in `PanCoordinator`), so rotation during a page settle is the weakest A8 case.
- R4: pages are eager until M9.
- R5: lazy sequences (17, and 18–27 after D37) depend on `caughtUndecided` for rule 4 (A6 is timing-sensitive).
- R6: S16's premise changes (dependency direction).
- R7: Slider and horizontal controls in a horizontal pager are unmeasured (A7).

## Open questions (for the user)

1. **Dependency:** may ZTronPages depend on ZTronScrollView (B, recommended)? That amends S16's "only shared code" premise, not the API.
   If not, C (its own SwiftUI-pan pager over the contract) costs about twice as much and needs its own physics calibration.
2. **Home:** the ZTronPages repo, or a pure-SwiftUI `ZTronPages` library target in this repo (S2 holds)?
3. **One path:** do you accept B on 18+ too (recommended), or do you want a UIKit pager with names on 18+, as D50 literally reads?
4. **UIKit pages and hosts:** is `ZTronPage.uikit` still needed? If yes, NESTED-mixed D1 + A (+ D2) come before P-a.
5. **Zoomer default:** `.automatic` (a zoomed page at its edge pages, UIKit parity) or `.innerWhenZoomed` (Open item 8's device check)?
6. **v1 scope:** topbar / dots / live progress, bottom inset, lazy pages (waits for M9)?
7. **T3:** run P-d (a real ZTron page in a UIKit pager, `cancel` on 17.5, Representable host), or keep the UIKit route documented only?
8. **Q3-s1:** merge its MC-contract note E addendum (docs and spike only, `claude/spike-q3-descendant-simultaneous`) into main?
