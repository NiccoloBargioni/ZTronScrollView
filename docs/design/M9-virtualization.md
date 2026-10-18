# M9 · Virtualizing lazy containers (design)

Scope: SPEC 322–325 (lazy containers), S4 (83–105), 472–477 (header height is top inset for pinned headers / scrollTo anchors).
Builds on M2 §4–5/§7 (layout host, transform, viewport observation, readers), M5 §6 (reflow anchor, `.sizeChanges`, registry hook)
and M6 §2 (`TargetRegistry`, `ztronScrollID`, `scrollTo`, `ZTronScrollPosition`). Names per CLAUDE.md. No UIKit, no reflection.

## 1. Principle

A lazy container is an ordinary content view whose **body depends only on cold, bucketed state**: the materialization window
(`LazyWindow`, Equatable) and a layout `version`. Offset/zoom never reach its body (S4-3). Per scroll frame the only work is the
window probe's transform (two binary searches) and, with pinned views, the pinned layer's offset chain. Geometry is a model
(`LazyLayoutModel`, reference type, never observed) that holds one length per *line* (row of lanes) for all N items — estimate
or measured — so the container's size is defined for every item at every time and only changes at flushes (§4).

## 2. Types and signatures

```swift
// Lazy/ZTronLazyStacks.swift — public surface. Same parameter lists as SwiftUI (ViewBuilder form) + data-driven forms.
public struct ZTronLazyVStack<Content: View>: View {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(),
                @ViewBuilder content: () -> Content)                                   // 18+: subviews path (§3); 15–17: eager LazyVStack (documented)
    public init<Data: RandomAccessCollection, ID: Hashable, Row: View>(_ data: Data, id: KeyPath<Data.Element, ID>,
                alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(),
                @ViewBuilder row: @escaping (Data.Element) -> Row) where Content == ZTronLazyRows<Data, ID, Row>   // virtualizes on 15+
    public init<Data, Row>(_ data: Data, …) where Data.Element: Identifiable                                          // id: \.id
    public init<S: RandomAccessCollection, SID: Hashable, R: RandomAccessCollection, RID: Hashable, Header: View, Footer: View, Row: View>(
                sections: S, id: KeyPath<S.Element, SID>, rows: KeyPath<S.Element, R>, rowID: KeyPath<R.Element, RID>,
                alignment:…, spacing:…, pinnedViews:…, @ViewBuilder header: @escaping (S.Element) -> Header,
                @ViewBuilder footer: @escaping (S.Element) -> Footer = { _ in EmptyView() }, @ViewBuilder row: @escaping (R.Element) -> Row)
                where Content == ZTronLazySections<S, SID, R, RID, Header, Footer, Row>
}
public struct ZTronLazyHStack<Content: View>: View   // same inits, VerticalAlignment, axis .horizontal
public struct ZTronLazyVGrid<Content: View>: View {  // + columns: [GridItem]; ZTronLazyHGrid: rows: [GridItem]
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content)
    // + the three data-driven forms above with `columns:` first
}
extension View { public func ztronLazyConfiguration(_ c: ZTronLazyConfiguration) -> some View }   // environment
public struct ZTronLazyConfiguration: Equatable, Sendable {
    public var estimatedLength: CGFloat?   // nil → 44 pt until first measurements, then running mean of measured lines
    public var overscan: CGFloat = 1.0     // × unobscured visible length, each side
    public var bucket: CGFloat = 0.5       // × unobscured visible length; window edges snap to bucket multiples
    public var maxRetargets: Int = 4       // scrollTo refinement bound (§6)
}

// Lazy/LazyLayoutModel.swift — internal, one per container, reference type, not observed
struct LazyWindow: Equatable { var firstBucket: Int; var lastBucket: Int; var crossLength: CGFloat /* lane-resolving dim, snapped */ }
struct LazyLine: Equatable { var kind: Kind /* .items(section, firstItem, count) | .header(section) | .footer(section) */; var length: CGFloat; var isMeasured: Bool }
@MainActor final class LazyLayoutModel: LazyFrameProvider {
    let axis: Axis; var lanes = 1; var spacing: CGFloat; var laneSpacing: CGFloat; var laneLengths: [CGFloat]   // GridItem resolution (same rules as LazyVGrid)
    private(set) var lines: [LazyLine]; private(set) var positions: [CGFloat]  // prefix sums incl. spacing; positions.count == lines.count + 1; total = positions.last
    var measured: [AnyHashable: CGFloat]                 // by id (headers: section id ⊕ role); survives data edits and window churn
    var pending: [(line: Int, length: CGFloat)]          // reported this pass, committed at flush
    var anchorLine: Int; var lastRect: CGRect            // first line intersecting the unobscured top at the last flush; last probe rect
    var origin: CGPoint                                  // container frame origin in ztronContent (cold, measured once per layout)
    func rebuild(count: Int, sections: [(items: Int, hasHeader: Bool, hasFooter: Bool)], ids: (Int) -> AnyHashable, estimate: CGFloat)
    func window(for unobscured: CGRect, config: ZTronLazyConfiguration) -> LazyWindow   // bucketLen = max(1, visibleLen·bucket); edges = floor/ceil((edge ∓ overscan)/bucketLen)
    func lines(in w: LazyWindow, config:) -> Range<Int>                                  // binary search on positions, clamped
    func report(line: Int, length: CGFloat)                                              // `!=`-guarded vs committed; appends to pending; schedules flush (§4)
    @discardableResult func flush(into state: ZTronScrollState?) -> Bool                 // §4; returns true when positions changed
    func frame(ofLine i: Int) -> CGRect; func line(at p: CGFloat) -> Int
    // LazyFrameProvider
    func frame(of id: AnyHashable) -> (rect: CGRect, isEstimate: Bool)?; func frames(in rect: CGRect) -> [(id: AnyHashable, rect: CGRect)]
    func nearest(to p: CGPoint) -> (id: AnyHashable, rect: CGRect)?; var isTargetLayout: Bool
}

// Lazy/VirtualLayout.swift (16+) and Lazy/LazyFallbackLayout.swift (15 / forced) — placement only, read `model.positions`
@available(iOS 16, *) struct VirtualLayout: Layout {   // sizeThatFits: cross = proposal (nil → max lane width), main = model.total
    let model: LazyLayoutModel; let first: Int           // placeSubviews: subview k → line first+k (lane via LayoutValueKey), at bounds.origin + positions[line]
}                                                        // measures `subviews[k].sizeThatFits(laneProposal)` → model.report (no per-row observer on 16+)
struct LazyFallbackLayout<Rows: View>: View {            // ZStack(alignment: .topLeading) { rows.offset(main: positions[line]) }.frame(main: model.total)
}                                                        // rows measured with GeometryReader background + LazyLinePreference → model.report (one frame later than 16+)

// Lazy/PinnedLayer.swift — leaf overlay in content space (inside the transform); reads hot visibleRect in ITS body only
struct PinnedLayer<Header: View, Footer: View>: View { /* §5 */ }

// State additions (State/ZTronScrollState.swift) and registry additions (Targets/TargetRegistry.swift, after M6 (a))
extension ZTronScrollState {
    func shiftTarget(by delta: CGPoint)      // unanimated: target, presentation, clock-motion origin and pan baseline (resizeGeneration bump) move together;
                                             // no didScroll (nothing moves on screen); no-op while resizeCommit.isOpen (M5 reflow owns the anchor then)
    var pendingLazyTarget: (id: AnyHashable, anchor: UnitPoint?, animation: ZTronScrollAnimation?, retargets: Int)?
    func lazyFrameDidChange(_ id: AnyHashable)   // from registry after a flush → retarget §6
}
protocol LazyFrameProvider: AnyObject { /* above */ }
extension TargetRegistry { func addProvider(_ p: LazyFrameProvider); func removeProvider(_ p: LazyFrameProvider)
    // frame(of:) = explicit frames[id] ?? providers.frame(of:) (origin added); nearestTarget/alignedOffsets merge explicit frames with
    // providers.frames(in: queried range) — so view-aligned targets exist for unmaterialized lines too (estimates). }
```

## 3. Data flow

```
visibleRect (hot) + adjustedContentInset + headerObscured (cold)  ──► LazyWindowProbe (ReaderProbe, M2 §8) ──► model.window(for: unobscuredRect)
     (unobscured = visibleRect inset by (I.start + h)/s at the top, I.end/s at the bottom; content units)      │ Equatable LazyWindow
container @State window ◄──────────────────────────────────────────────────────────────────────────────────────┘ (writes only on change)
container body (window, version, data, config)  →  rows = ForEach(data[lines(in: window)], id:) { row(el) }     ← ids stable, @State kept while in window
     16+: VirtualLayout(model, first)  { rows }    15: LazyFallbackLayout(model) { rows }                      ← placement from model.positions
     + PinnedLayer (leaf) + ztronContent-origin observer (cold) + registry.addProvider(model) on appear
measurements → model.report → flush (next run-loop turn, batched) → δ shift (§4) + version += 1 → body → layout → M2 content measurement → setContentSize
```
- **Subviews enumeration.** Data-driven inits enumerate `data` by index (RandomAccessCollection, O(1)); sections flatten to
  `lines` once per `rebuild` (on data identity/count change). The ViewBuilder init on 18+ uses `ForEach(sections: content)` /
  `Group(subviews:)`: lines come from `SectionConfiguration` (header/content/footer subviews), ids from `subview.id`, pinned flags from
  `containerValues`; the container places only `subviews[lines(in: window)]`, so only those bodies run. On 15–17 the ViewBuilder init
  renders SwiftUI's `LazyVStack` eagerly (DEBUG counter `lazy.eagerFallback = 1`, documented in the parity matrix).
- **Why rows don't re-run on a flush**: the container body re-runs and `ForEach` re-invokes `row(el)`, but SwiftUI skips a row's body when
  its view value is unchanged. Rows that capture closures in stored properties re-run on flushes (not per frame); documented, with
  `EquatableView` as the fix. Entering/leaving rows run once (enter). This is the M9 tier row: *materialized row body: window change only*.
- **Lane resolution** (grids): `GridItem` fixed/flexible/adaptive resolved exactly like `LazyVGrid` from `crossLength`; 16+ in
  `sizeThatFits` from the proposal, 15 from a background `GeometryReader` → `@State crossLength` (changes on rotation only). Line
  length = max over its lane items.

## 4. Formulas (per main axis; `p` = model.positions, `L` = line length, `sp` = spacing)

- `p_0 = 0`, `p_{i+1} = p_i + L_i + sp` (last without `sp`), `total = p_N`. Positions are always **top-anchored**; the model never
  stores a residual. Window: `bucketLen = visibleLen·bucket`, `first = ⌊(top − overscan·visibleLen)/bucketLen⌋`, `last = ⌈(bottom + overscan·visibleLen)/bucketLen⌉`,
  `lines = [line(at: first·bucketLen), line(at: last·bucketLen)]` ∩ `0..<N`. With `bucket = 0.5`, `overscan = 1` the body runs ≈ 2× per viewport scrolled.
- **Flush** (one update per run-loop turn, `Task { @MainActor }` when the clock is idle, else at the next tick before `probeTick`):
  commit `pending` into `L`; `estimate := mean(measured)` applied to all unmeasured lines; `a = anchorLine` (recomputed from `lastRect`
  *before* commit: first line with `p_i + L_i > unobscuredTop`, or 0 when `offset ≤ min + 0.5`);
  `δ = Σ_{i<a} (L_i^new − L_i^old)`; rebuild prefix sums; if `δ ≠ 0` → `state.shiftTarget(by: δ·axis)`; `version += 1`.
  The anchor line's position and the offset grow by the same `δ` in the same update, so its screen position is unchanged (no jump).
  Lines below the anchor just extend the content (M5 `.sizeChanges` default: offset unchanged, clamped) — identical to UIKit.
- **Same-frame guarantee.** Placement always uses *committed* `L`; a freshly measured row whose real size ≠ committed slot overlaps/gaps
  its neighbour for ≤ 1 frame (16+: 0 frames when `report` lands in the same pass and flush precedes layout; see R3). Entering rows sit at
  the window edge ≥ `overscan·visibleLen` from the unobscured rect, so the slot error is off-screen unless `Σ corrections > overscan·visibleLen`.
- **Data edits** (count/identity change): `rebuild` keeps `measured` by id, re-derives `L`, no `δ` (SwiftUI/UIKit parity: offset
  unchanged when rows are inserted above). `anchorLine` is re-derived from `lastRect` after rebuild.
- **Cross-size change** (rotation, Split View): measured lengths become stale-but-used; first flush after `closeResize()` re-measures
  materialized lines and applies `δ` normally. During `commit.isOpen` the model only *reports*; M5 §6 reflow (`nearestTarget` → a
  materialized line via the provider → `targetFrameDidChange`) owns the anchor, so the two mechanisms never double-correct.
- **Zoom**: everything is in unscaled content units; zooming out enlarges the unobscured rect → bigger window. Pinned views scale
  with content (no counter-scaling; documented).

## 5. Pinned headers/footers (SPEC 472–474)

All section headers/footers listed in `pinnedViews` are owned by `PinnedLayer`, never by the row layout: the model reserves their lines
(slot = measured header length), the layer draws each *materialized* header once (one instance → its `@State` is preserved; no duplicate)
at `y = clamp(natural, pinTop, nextHeaderNatural − L_header)`, `pinTop = visibleRect.minY + (I.top + h)/s`; footers mirrored at
`pinBottom = visibleRect.maxY − I.bottom/s − L_footer`, pushed by the previous footer. The layer's body reads `visibleRect` (hot) → tier
"every frame of motion", like indicators; the header **bodies** don't run (closure re-invocation → equal values; counter
`lazy.pinnedBodies`). The layer is the container's overlay (`alignment: .topLeading`, hit-testable above rows), inside the transform so it
needs no chrome slot; `h` comes from `metrics.headerObscured` (M8b). With `pinnedViews == []` headers/footers are ordinary lines and the
layer is absent (no per-frame reader at all).

## 6. `scrollTo`, `ztronScrollID`, target layout, behaviors

- The model registers as a `LazyFrameProvider` (no per-row geometry observers): `registry.frame(of: id)` resolves every id in the
  container, materialized or not, as `(rect, isEstimate)`; explicit `ztronScrollID` frames win. Rows get no automatic `.id` — `ForEach` ids
  already give identity; a developer `ztronScrollID` on a row still registers normally.
- `scrollTo(id, anchor, animation)` with `isEstimate == true` → state animates to the estimated rect (M5/M6 path) and stores
  `pendingLazyTarget`. Each flush that changes that id's frame calls `registry.lazyFrameDidChange(id)` → `state.lazyFrameDidChange`:
  `.uikit` → clock retargets the running curve to the new destination (same remaining duration); `.swiftUI(a)` → re-write the target in
  `withAnimation(a)`; `nil` → unanimated write. Done when `isEstimate == false` and one flush passes without change, or after
  `maxRetargets`. Target `anchor` uses the unobscured rect (`I.top + h`, SPEC 475). `ZTronScrollPosition(id:)` follows the same path.
- `ztronScrollTargetLayout` on the container sets `model.isTargetLayout`; `alignedOffsets` merges provider frames for the queried range, so
  `.viewAligned` lands on unmaterialized estimated lines; a correction after landing triggers one retarget via the same pending mechanism
  (the behavior's settled target is re-aimed, ≤ 1 pt visible if the estimate was off). `.paging` is viewport-based and unaffected.
- `shiftTarget` while dragging: `resizeGeneration` bump → `PanCoordinator` rebases (M5 §5); while decelerating: the clock shifts the motion
  origin so `presentation == target + curve(t)` stays continuous (one line in the clock; physics package untouched).

## 7. Edge cases

Empty data → `total = 0`, no probe writes. Window beyond `N` after deletions → clamped. `estimatedLength` set and > measured mean → the
first flush shrinks everything below the anchor (no jump). Variable-height rows above the viewport when scrolling *up* fast: corrections
batched per flush, `δ` can be several hundred pt — still invisible (same update). Two containers in one scroll view → two providers,
`nearestTarget` picks the closest across both. Container nested in a non-scrolling parent (e.g. inside `VStack`) → `origin ≠ 0`, handled by
the cold origin observer. `pinnedViews` with zero-height header → not pinned (matches SwiftUI). Row with `.id()` changed by the developer →
treated as leave + enter. Programmatic `offset` writes while a flush is pending → flush applies `δ` on top (order-independent).

## 8. Render-tier proof and budget

DEBUG counters (M2 harness): `lazy.containerBody`, `lazy.layoutPasses`, `lazy.rowBodies` (sum over rows), `lazy.rowsEntered`, `lazy.windowChanges`,
`lazy.flushes`, `lazy.shiftPt` (Σ|δ|), `lazy.pinnedLayerBody`, `lazy.pinnedBodies`, `lazy.jumpFrames` (frames where the anchor row's
viewport-space position changed by > 1 pt more than the presentation offset did), `lazy.materialized` (gauge).
Invariants: steady scroll frame → `containerBody 0`, `rowBodies 0`, `transform.effect 1`, `pinnedLayerBody ≤ 1`; per window change →
`containerBody 1`, `rowBodies == rowsEntered`; per flush → `rowBodies 0`, `jumpFrames 0`. Budget (iPhone 12-class, 44-pt rows, 10k items,
Release): steady frame main-thread ≤ 0.5 ms; window-change update ≤ 4 ms (≈ 10 rows entering); flush ≤ 1 ms incl. the O(N) prefix
rebuild (10k adds; switch to a Fenwick tree only if profiling demands it); memory ≤ 2 MB for 10k lines. Measured with `os_signpost` in DEBUG.

## 9. Tests

Unit (Swift Testing, `Tests/ZTronScrollViewTests/Lazy*Tests.swift`, state tests over `OSPath.allCases`):
1. Model: prefix sums, `line(at:)`, window bucketing (edges snap; same rect → equal window; scroll by < bucketLen → equal).
2. Flush δ: corrections above/below/at the anchor; at top (`offset == min`) → δ = 0; data insert above → no shift; estimate re-mean.
3. Sections/grids: lane resolution vs `LazyVGrid` rules (fixed/flexible/adaptive at 3 widths); line length = max of lanes; header/footer lines.
4. `shiftTarget`: target, presentation, clock origin and pan baseline move together; no didScroll; no-op while `isOpen`; drag rebase.
5. Provider ↔ registry: `frame(of:)` estimate vs explicit precedence; `alignedOffsets` merged; nearest across two providers.
6. `scrollTo` unmaterialized: estimated jump → materialize → retarget ≤ `maxRetargets` → final anchor within 0.5 pt (uikit, swiftUI, nil animation).
7. Render harness (both paths): 200 rows, scroll one viewport → counters per §8; flush → `rowBodies 0`; rows keep `@State` across window shifts.
Demo UI (`LazyScreen`, launch `-ZTronScreen lazy`, variants `list10k`, `grid`, `sections`; `LazyUITests`) on 27.0 and 17.5, preferred and
`-ZTronForceAllFallbacks`: a. 10k variable-height rows with pinned headers: fling 5 viewports → `jumpFrames 0`, `rowBodies == rowsEntered`,
`materialized ≤ 3 × visible`; b. scroll up from the bottom (corrections above) → `jumpFrames 0`; c. `scrollTo` row 9 000 → row label at
anchor ±1 pt; d. grid adaptive, rotate → same center cell (M5 assertion), counters 0 during rotation except `layoutPasses`; e. pinned
header pushes at section boundary with M8b header collapsed/expanded (pin line = inset + h); f. ViewBuilder form on 18+ (subviews path)
same assertions as a; on 17.5 `eagerFallback 1`.

## 10. Builder sessions and file ownership

- **(a) core — Opus builder (SPEC O4)**, after M6 (a) is committed (both touch `Targets/TargetRegistry.swift`, `State/ZTronScrollState.swift`):
  `Lazy/LazyLayoutModel.swift`, `Lazy/LazyWindowProbe.swift`, `Lazy/VirtualLayout.swift`, `Lazy/LazyFallbackLayout.swift`,
  `Lazy/ZTronLazyStacks.swift` (data-driven inits, V/H, grids), `Lazy/ZTronLazyConfiguration.swift`; `shiftTarget` + clock origin shift;
  registry providers; tests 1–5, 7. Exit: `scripts/test.sh -only-testing:ZTronScrollViewTests` green on 27.0 and 17.5.
- **(b) pinned + scrollTo + subviews** (after (a)): `Lazy/PinnedLayer.swift`, `Lazy/SubviewsSource.swift` (18+ ViewBuilder path, 15–17 eager),
  `pendingLazyTarget`/retarget in state + clock; test 6. **(c) demo + UI tests** (after (b)): `LazyScreen`, counters, `LazyUITests` a–f;
  parity-matrix rows. Nobody touches `Packages/ZTronScrollPhysics` or `ScrollArbitration`.
- Parity-matrix rows: `LazyVStack/HStack/VGrid/HGrid` (eager in our scroll view → `ZTronLazy…` virtualizes; ViewBuilder form eager on
  15–17); `pinnedViews` (single instance, pushed by next header, top inset + scaling header); `scrollTo` to unmaterialized id
  (estimate + refine; SwiftUI: exact only if laid out); `scrollTargetLayout` inside lazy (estimated targets); zoom (pinned views scale).

## 11. Device risks (check first, in this order)

- R1 18+ `Group(subviews:)`/`ForEach(sections:)` over 10k `ForEach` children: cost of resolving the collection per container body
  (should be view values only, no bodies). If > 2 ms, the ViewBuilder form documents a 2k-item ceiling and recommends the data-driven inits.
- R2 `VirtualLayout`: `subviews[k].sizeThatFits` per pass for ~30 rows must be cached by SwiftUI (verify `layoutPasses` × rows ≤ budget);
  else measure via `onGeometryChange` on rows like 15.
- R3 Flush ordering: a `report` in `sizeThatFits` and the subsequent `Task` flush must land before the next frame on 17.5/27 (else 1 frame of
  slot error in the overscan — invisible unless corrections exceed the overscan; verify `jumpFrames 0` in UI test b).
- R4 `shiftTarget` during deceleration on the 15–16 relay path: the shift must not wake the transform host out of phase (D10 `.target`
  channel) and `probe.pending` must equal the shifted presentation on the next tick.
- R5 `PinnedLayer` per-frame cost with 3+ materialized headers while zoomed; and hit-testing of pinned headers over rows (`.offset` + overlay).
- R6 Fallback `.offset` placement on 15: hit-testing and `ztronContent` frames of offset rows must match the Layout path (M3/M4 UI tests).
- R7 Memory/time of `rebuild` with 10k sections × 10 rows (100k lines): O(N) prefix rebuild per flush — measure; Fenwick fallback.

## Open questions
- Q1 ViewBuilder init on 15–17 = eager `LazyVStack` (no virtualization) — accept, or drop the ViewBuilder form below 18?
- Q2 Pinned layer in content space (per-frame leaf) vs an M8 chrome slot (updates only at section boundaries) — content space for M9, chrome later?
- Q3 Pinned views scale with zoom (no counter-scaling) — accept as documented parity gap?
- Q4 `shiftTarget` emits no `didScroll` (nothing moves on screen) but `contentOffset` changes — fire `didChangeContentSize`-style delegate instead?

## Orchestrator resolutions (2026-10-18)
- Q1 Ship both: the data-driven inits (`ZTronLazyVStack(data, id:) { … }` etc.) virtualize on every OS; the ViewBuilder
  form virtualizes on 18+ (subviews API) and falls back to eager below — documented in the parity matrix, with a DEBUG
  hint pointing 15–17 users to the data-driven init.
- Q2 Accepted for M9 (content-space `PinnedLayer`, indicator tier); revisit the chrome slot only if the counters show
  a cost.
- Q3 Accepted as a documented gap (native lazy stacks never zoom; zooming a lazy stack is our extension).
- Q4 Fire `didScroll` (S11: "for every offset change", coalesced at most once per frame) even though nothing moves.
- Sequencing: M9 (a) starts after M6 session 1 is committed.
