# M6 · Targets, position, reader/proxy (design)

Scope: SPEC S8 (253–296; creation, position, targets — not transitions), S11 (483–580). Builds on M3-pan §2/§5 (release pipeline,
`proposedTarget` M6 hook), M5-resize §2/§6 (`ScrollTargetRegistry`, `sizeChangesAnchor`, `targetFrameDidChange`, `pagingIndex`).
Names per CLAUDE.md. iOS 15 deployment; SwiftUI's own types only behind `#available`. No overload/shadowing tricks: every parameter
is one of *our* types, so `.paging` / `.viewAligned` resolve through `where Self ==` statics on *our* protocol and never collide with
SwiftUI's. Physics package untouched (`PagingSolver`, `TargetSnapping` already exist).

## 1. Parity strategy made concrete

| Kind | Shape | Where the value lives |
|---|---|---|
| Member (S8-2a) | `ZTronScrollView.scrollTargetBehavior(_:) -> Self` etc. | `ScrollViewConfig` stored on the view, applied in `ScrollContainer` (`!=`-guarded, cold) |
| Twin (S8-2b) | `View.ztronScrollTargetBehavior(_:)` etc. | `EnvironmentValues.ztronScrollConfig` (overlay struct) **and** SwiftUI's native modifier when `#available` |
| Content-level (S8-3) | `ztronScrollID(_:)`, `ztronScrollTargetLayout(isEnabled:)` | registry via environment inside a ZTronScrollView; native `.id` / `.scrollTargetLayout` always applied |
| Type mirror (S8-4) | `ZTronScroll…` 1:1 structs/protocols + `init(_ native:)` / `var native` where SwiftUI's type is publicly constructible | gated extensions in `Targets/NativeBridges.swift` |

Resolution order inside the container: member ?? environment twin ?? default. Unprefixed spellings bind only on the ZTronScrollView
itself (documented in the parity matrix). Conversions: `ZTronScrollTarget ⇄ ScrollTarget` (17+, both ways), `ZTronScrollTargetBehaviorContext(native)`
(17+, one way: SwiftUI's context is not constructible, so native behaviors cannot run in our pipeline — documented gap), ours → native
behavior via `ZTronBridgedScrollTargetBehavior` (17+), `ZTronScrollPosition ⇄ ScrollPosition` (18+; `isPositionedByUser` is get-only natively → one way),
`LimitBehavior` (17+, `.alwaysByOne/.alwaysByFew` need 18, else `.always`), `ZTronScrollAnchorRole ⇄ ScrollAnchorRole` (18+).

## 2. Types and signatures

```swift
// Targets/ScrollTargetBehavior.swift
public struct ZTronScrollTarget: Equatable, Sendable { public var rect: CGRect; public var anchor: UnitPoint?; public init(rect: CGRect, anchor: UnitPoint? = nil) }
@dynamicMemberLookup public struct ZTronScrollTargetBehaviorContext {            // mirrors ScrollTargetBehaviorContext
    public let originalTarget: ZTronScrollTarget; public let velocity: CGVector /* pt/ms, SwiftUI's unit (D32) */; public let contentSize: CGSize /* scaled, UIKit-style */
    public let containerSize: CGSize; public let axes: Axis.Set
    public subscript<T>(dynamicMember k: KeyPath<EnvironmentValues, T>) -> T          // backed by a captured EnvironmentValues
    let dragStart: CGPoint; let insets: EdgeInsets; let registry: TargetRegistry?; let zoomScale: CGFloat   // internal extras for built-ins
}
public struct ZTronScrollTargetBehaviorProperties: Equatable, Sendable { public var limitsVelocity: Bool; public static let `default` = Self(limitsVelocity: false) }
public struct ZTronScrollTargetBehaviorPropertiesContext { public let axes: Axis.Set; public let contentSize: CGSize; public let containerSize: CGSize }
public protocol ZTronScrollTargetBehavior {
    typealias TargetContext = ZTronScrollTargetBehaviorContext; typealias PropertiesContext = ZTronScrollTargetBehaviorPropertiesContext
    func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext)
    func properties(in context: PropertiesContext) -> ZTronScrollTargetBehaviorProperties      // default `.default`
}
public struct ZTronPagingScrollTargetBehavior: ZTronScrollTargetBehavior { public init() }        // limitsVelocity: true
public struct ZTronViewAlignedScrollTargetBehavior: ZTronScrollTargetBehavior {
    public struct LimitBehavior: Equatable, Sendable { public static let automatic, always, alwaysByOne, alwaysByFew, never: Self }
    public init(limitBehavior: LimitBehavior = .automatic)
}
public struct AnyZTronScrollTargetBehavior: ZTronScrollTargetBehavior { public init(_ b: some ZTronScrollTargetBehavior) }   // closure box; built-ins keep a `kind` tag
extension ZTronScrollTargetBehavior where Self == ZTronPagingScrollTargetBehavior { public static var paging: Self }
extension ZTronScrollTargetBehavior where Self == ZTronViewAlignedScrollTargetBehavior { public static var viewAligned: Self; public static func viewAligned(limitBehavior: LimitBehavior) -> Self }

// Targets/TargetRegistry.swift (internal) — fills M5's ScrollTargetRegistry protocol
@MainActor final class TargetRegistry: ObservableObject?, ScrollTargetRegistry {  // not observed by content; `version` is a cold channel
    private(set) var frames: [AnyHashable: CGRect]   // unscaled `ztronContent` space; var layoutEnabled = true; private(set) var version: UInt64
    func register(_ id: AnyHashable, frame: CGRect)  // `!=`-guarded; → state.targetFrameDidChange(id); bumps version
    func unregister(_ id: AnyHashable); func frame(of:) -> CGRect?; func nearestTarget(to: CGPoint) -> (id: AnyHashable, frame: CGRect)?
    func alignedOffsets(axis: Axis, anchor: UnitPoint, scale: CGFloat, pad: CGPoint, insets: EdgeInsets, container: CGFloat) -> [(id: AnyHashable, offset: CGFloat)]  // sorted
    #if DEBUG var writes: Int #endif
}
// Modifiers/ZTronScrollID.swift
extension View { public func ztronScrollID<ID: Hashable>(_ id: ID) -> some View        // .id(id) + frame reporter → registry (env); no registry → plain .id
                 public func ztronScrollTargetLayout(isEnabled: Bool = true) -> some View } // env flag → registry.layoutEnabled; 17+: also native .scrollTargetLayout

// Reader/ZTronScrollViewReader.swift
public struct ZTronScrollViewReader<Content: View>: View { public init(@ViewBuilder content: @escaping (ZTronScrollViewProxy) -> Content) }
public struct ZTronScrollViewProxy {                                                   // struct over a ProxyScope class (like ScrollViewProxy)
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil)             // ambient transaction (withAnimation honored)
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint?, animation: ZTronScrollAnimation?)   // nil = unanimated
}
public enum ZTronScrollAnimation: Equatable { case uikit /* setContentOffset(animated:) curve, clock path */; case swiftUI(Animation) /* transaction path */ }
@MainActor final class ProxyScope { var members: [(state: ZTronScrollState, registry: TargetRegistry)]  /* appear order */; weak var parent: ProxyScope?; var native: ScrollViewProxy? }

// Position/ZTronScrollPosition.swift — mirrors ScrollPosition (18+)
public struct ZTronScrollPosition: Equatable, Sendable {
    public init(); public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil); public init(point: CGPoint); public init(edge: Edge); public init(x: CGFloat); public init(y: CGFloat); public init(x: CGFloat, y: CGFloat)
    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil); public mutating func scrollTo(edge: Edge); public mutating func scrollTo(point: CGPoint)
    public mutating func scrollTo(x: CGFloat); public mutating func scrollTo(y: CGFloat); public mutating func scrollTo(x: CGFloat, y: CGFloat)
    public var viewID: (any Hashable)? { get }; public func viewID<T: Hashable>(type: T.Type) -> T?; public var point: CGPoint?; public var edge: Edge?; public private(set) var isPositionedByUser: Bool
    enum Request: Equatable { case id(AnyHashable, UnitPoint?), edge(Edge), point(CGPoint), x(CGFloat), y(CGFloat), xy(CGPoint) }
    var request: Request?; var serial: UInt64     // serial bumps on every scrollTo and takes part in ==, so repeating a request re-applies it
}
public enum ZTronScrollAnchorRole: Hashable, Sendable { case initialOffset, sizeChanges, alignment }

// ZTronScrollView.swift — members (S8-2a) and View twins (S8-2b, Modifiers/ScrollConfigTwins.swift)
extension ZTronScrollView {
    public func scrollTargetBehavior(_ behavior: some ZTronScrollTargetBehavior) -> Self
    public func scrollPosition(_ position: Binding<ZTronScrollPosition>, anchor: UnitPoint? = nil) -> Self
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> Self
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> Self; public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ZTronScrollAnchorRole) -> Self
}
extension View {   // same names with `ztronScroll` prefix; each applies the native modifier under #available(iOS 17/18) and writes the env overlay
    public func ztronScrollTargetBehavior(_ behavior: some ZTronScrollTargetBehavior) -> some View
    public func ztronScrollPosition(_ position: Binding<ZTronScrollPosition>, anchor: UnitPoint? = nil) -> some View
    public func ztronScrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View
    public func ztronDefaultScrollAnchor(_ anchor: UnitPoint?) -> some View; public func ztronDefaultScrollAnchor(_ anchor: UnitPoint?, for role: ZTronScrollAnchorRole) -> some View
}
struct ScrollViewConfig { var behavior: AnyZTronScrollTargetBehavior?; var position: PositionBinding?; var anchors: [ZTronScrollAnchorRole: UnitPoint?] }
// State additions (cold, never published): var targetBehavior: AnyZTronScrollTargetBehavior?; var alignmentAnchor: UnitPoint?; var initialOffsetAnchor: UnitPoint?
// var effectiveTargetBehavior: AnyZTronScrollTargetBehavior? { targetBehavior ?? (isPagingEnabled ? .init(.paging) : nil) }
// var onReleaseTargetDecided: ((CGPoint) -> Void)?   // PositionDriver hook, once per release
// func scrollTo(id: AnyHashable, anchor: UnitPoint?, animation: ZTronScrollAnimation?, ambient: Bool)   // via targetRegistry; proxy and position both use it
```

## 3. Data flow

```
.ztronScrollID(id)  ──frame in ztronContent space (16+: onGeometryChange; 15: GeometryReader+preference at the same node)──► TargetRegistry.register   (cold, 0 writes during scroll/zoom)
ZTronScrollViewReader → ProxyScope (env) ◄── each ZTronScrollView registers (state, registry) on appear, nearest scope only
proxy.scrollTo(id) → first member whose registry has id → state.scrollTo(id:…) ; none → nativeProxy.scrollTo(id, anchor)   (inner SwiftUI ScrollViewReader)
member/twin config → ScrollContainer resolves → state.targetBehavior / anchors / PositionDriver (cold)
release: PanCoordinator.endDrag → ReleasePipeline (§4: behavior → delegate) → ReleaseSolver → clock → settle → PositionDriver.writeBack (≤ 2 writes / gesture)
```

## 4. Formulas

Per axis: `x_v = s·x_c + pad − o`; unobscured width `W = V − I.total`; registered frame `f` (unscaled) → `r = s·f + pad` (offset space).
- **scrollTo(id, anchor a):** `a == nil` → minimal scroll: `o' = r.min − I.start` if `r.min < o + I.start`; `o' = r.max − (V − I.end)` if `r.max > o + V − I.end`;
  else unchanged; `r.len > W` → align start. `a ≠ nil` → `o' = r.min + a·r.len − I.start − a·W`. Clamp to bounds at current `s` (zoom unchanged, like
  `scrollRectToVisible`). `edge` → `o' = min` / `max`; `point` → `o' = clamp(p)`; `x`/`y` → one axis. Moving without a finger → `interrupt()` first (same rule as `scroll(to:)`).
- **Release pipeline (replaces M3 §5 step 3; `endDrag`):** `v` per axis (pt/s, accelerated) → `natural = clamp(projectedRest(origin, v, rate))` →
  `b = state.effectiveTargetBehavior`. If `b`: `p = b.properties(in:)`; `limitsVelocity` → `|v| ≤ W / projectedRest(0, 1, rate)` (decay is linear in `v`; one container
  length max), `natural` recomputed. `original = ZTronScrollTarget(rect: CGRect(origin: natural, size: V), anchor: nil)`; `var t = original; b.updateTarget(&t, context:)`;
  `proposed = clamp(t.rect.origin + a_t·(t.rect.size − V))` with `a_t = t.anchor ?? .zero`. No `b` → `proposed = natural`. Then **`willEndDragging(v/1000, &proposed)`**
  (delegate sees the behavior's result and may override). Per axis `target = proposed ≠ natural ? proposed : nil` → `ReleaseSolver` unchanged. The old
  `proposedTarget` paging branch is removed: `isPagingEnabled` ⇔ effective `.paging` (`isPagingEnabled` stays the stored knob; an explicit behavior wins).
- **Paging:** per enabled axis `PagingSolver.target(current: origin, dragStart:, velocity: v, pageLength: W, bounds:)` (one page max; same table as today's M3 tests).
- **ViewAligned:** candidates `c_i = r_i.min + a·r_i.len − I.start − a·W` (`a = t.anchor ?? .topLeading`) per axis from `registry.alignedOffsets`; `layoutEnabled == false` or no
  targets → `t` unchanged. `start = nearest(c, dragStartOffset)`. `.never`: `nearest(to: natural, candidates, direction: sign v)`. `.alwaysByOne` (= `.always`): `v == 0` →
  nearest to `origin`; else the candidate adjacent to `start` in direction `v`. `.alwaysByFew`: nearest to `natural` among `|c − start| ≤ W`. `.automatic`:
  `context[\.horizontalSizeClass] == .compact ? .alwaysByFew : .never` (calibrate vs native, R5). M5 hook: `pagingIndex` is replaced by the chosen id (M5 §6) so a resize keeps the aligned item.
- **Position write-back (S4.6):** exactly at (1) release target decided (`onReleaseTargetDecided`) and (2) settle (`phase → .idle` after user motion); never per frame, never
  after programmatic requests. Value: `viewID = registry.nearestTarget(to: probe)` where `probe` is the content point under viewport point `anchor ?? .topLeading`
  (within the chosen target's frame if it contains it), `point = contentOffset`, `edge = nil`, `isPositionedByUser = true`. `PositionDriver` keeps `lastWritten` and `lastApplied`:
  a change equal to `lastWritten` is not re-applied (no loop); a differing `serial` re-applies. Requests before the first layout (or an id not yet registered — lazy content) are
  held as one `pending` request, retried on `registry.version` / first `setContentSize`, dropped at `beginDragging`.
- **defaultScrollAnchor:** `.initialOffset a` → once, at the first layout with non-zero content and viewport: `o = clamp(a·(s·content + pad·2 − W) − I.start)` unanimated
  (default nil = `min`). `.sizeChanges a` → `state.sizeChangesAnchor = a` (M5 §6). `.alignment a` → `state.alignmentAnchor = a`; `contentAlignment = alignmentAnchor ?? (isZoomEnabled ? .center : .topLeading)`
  (feeds `pad`). `defaultScrollAnchor(_)` sets all three. Twin on 17: native `.defaultScrollAnchor(a)` only for `.initialOffset`/all; 18+: `(a, for: role)`.

## 5. Edge cases

Unknown id → no-op (+ DEBUG log; native is also silent). Same id in two members → first in appear order; duplicate ids in one view → last registered, DEBUG warning.
Nested readers: a ZTronScrollView joins the nearest scope only; the outer proxy still reaches it through `ProxyScope.parent` chain (first match, outer-to-inner). `ztronScrollID` outside
any ZTronScrollView → plain `.id`. Native `ScrollView` inside the reader with the same id as a member → ours wins (native proxy is called only on miss). Zoom ≠ 1: frames scaled by
`s`; `scrollTo` never changes `s`. Viewport zero → request pending. Behavior set on both member and twin → member. `isPagingEnabled = true` + `.viewAligned` → viewAligned.
`updateTarget` producing a non-finite origin → fall back to `natural` (DEBUG warning). `scrollTo` during `isDragging` → same as `scroll(to:)` today. Position binding released
mid-flight (view disappears) → driver dropped, no write. `withAnimation { proxy.scrollTo }` = transaction path (M2 token); `animation: .uikit` = `setContentOffset(animated: true)`;
`animation: nil` = unanimated. Content bodies run 0 times for all of the above (render-time transform only).

## 6. Exemplar plan (SPEC O5) and builder sessions

**Session 1 — exemplar, one API per kind, fully tested:** member+twin `scrollTargetBehavior` / `ztronScrollTargetBehavior`; type mirror `ZTronScrollTargetBehavior` family
(`Target`, `Context`, `Properties`, `PropertiesContext`, `AnyZTronScrollTargetBehavior`); behavior `.paging` (proves the pipeline hook and `isPagingEnabled` equivalence);
reader/proxy `ZTronScrollViewReader` + `scrollTo(_:anchor:)` (both overloads) + the registry/`ztronScrollID` they need. Files: `Targets/{ScrollTargetBehavior,TargetRegistry,PagingScrollTargetBehavior}.swift`,
`Modifiers/{ZTronScrollID,ScrollConfigTwins}.swift`, `Reader/ZTronScrollViewReader.swift`, `Gesture/ReleasePipeline.swift` (hook), `ZTronScrollView.swift` (config + members),
`State/ZTronScrollState.swift` (`targetBehavior`, `scrollTo(id:)`, `onReleaseTargetDecided`). Starts only after M5 (a) is committed (shared `ZTronScrollState.swift`, `ScrollTargetRegistry` protocol).
**Session 2 — copy the pattern:** `Targets/{ViewAlignedScrollTargetBehavior,NativeBridges}.swift` (limits, bridged native twin, conversions), `Modifiers/ZTronScrollTargetLayout.swift`,
M5 `pagingIndex` → aligned id. **Session 3:** `Position/{ZTronScrollPosition,PositionDriver}.swift`, `scrollPosition` ×2, `Modifiers/DefaultScrollAnchor.swift` + roles, Demo
`TargetsScreen` + `TargetsUITests`, parity-matrix rows. No session touches `Packages/`, `PanCoordinator.swift` (M5 b) or `ScrollArbitration`.

## 7. Tests (unit over `OSPath.allCases`; demo UI on 27.0 and 17.5, preferred and `-ZTronForceAllFallbacks`)

1. Pipeline: custom behavior gets `velocity` == accelerated pt/s, scaled `contentSize`, `containerSize`, `axes`; mutating `rect.origin` moves `endPosition`; `willEndDragging` runs after and
   can override; `limitsVelocity` caps a fling to ≤ one `W`. 2. `.paging` ≡ `isPagingEnabled` (same end positions over M3's table); explicit behavior beats the knob.
3. ViewAligned: `.never` nearest-to-projected; `.alwaysByOne` exactly one item in `sign(v)`, `v = 0` nearest; `.alwaysByFew` within `W` of drag start; `.automatic` via size class; anchor `.center`;
   zoom 2× scales candidates; empty registry / `layoutEnabled false` → unchanged. 4. Registry: frames in `ztronContent` space; `writes` == 0 during a scripted scroll+zoom; unregister on
   disappear; `targetFrameDidChange` on reflow. 5. Proxy search: id only in 2nd member → 2nd; in both → 1st; unknown → native proxy called (17+ check via native `scrollPosition(id:)`); nested scopes.
6. scrollTo math: nil-anchor minimal (above/below/visible/larger), anchors, insets, 2.5× zoom, clamped; `withAnimation` → transaction token set; `.uikit` → clock; nil → unanimated; `content.body` 0.
7. Position binding: ≤ 2 writes per fling, 0 during drag frames; `isPositionedByUser`; `viewID` under anchor; `scrollTo(edge: .bottom)` → `max`; `scrollTo(x:)` one axis; repeated request re-applies;
   write-back not re-applied (`applied` counter). 8. `scrollPosition(id:)` carousel: landed page written; setting id scrolls (animated under `withAnimation`); pending id before first layout applies once.
9. Anchors: `.bottom` initialOffset → `max`; `.sizeChanges` reaches `sizeChangesAnchor` (re-run M5 §10.7 bottom-pinned); `.alignment .center` centers small content. 10. Twins: value applied above the
   view reaches the state; member wins; compile tests with native `ScrollView` on 17/18. 11. Conversions (gated runtime): `ScrollTarget`, `ScrollPosition` id/point/edge round trip, `LimitBehavior`, `ScrollAnchorRole`.
Demo UI (`TargetsScreen`, `-ZTronScreen targets`): jump menu via reader (ids 0/50/99 × anchors), jump menu via position (edge/id), horizontal paging carousel with page dots bound by
`scrollPosition(id:)`, viewAligned list with limit picker, a native `ScrollView` under the same reader (forwarding). Assert cell label at anchor, `content.body` 0, `position.writes` ≤ 2.
Parity-matrix rows (API | Strategy | Min OS | Fallback | Test | Status): `ScrollViewReader`/`ScrollViewProxy.scrollTo` | 2 | 15 | — | ProxyTests; `.id` targets → `ztronScrollID` | 3 | 15 | registry;
`scrollTargetBehavior` | 2a+2b | 15 (native 17) | twin applies native; `scrollTargetLayout(isEnabled:)` | 3 | 15 | children need `ztronScrollID`; `ScrollTarget`/`ScrollTargetBehavior`+Context/Properties/PropertiesContext
| 4 | 15 | conversions 17+, native→ours context impossible; `PagingScrollTargetBehavior` | 4 | 15 | ≡ `isPagingEnabled`; `ViewAlignedScrollTargetBehavior` + LimitBehavior | 4 | 15 (native 17/18);
`AnyScrollTargetBehavior` | 4 | 15 (native 18); `scrollPosition(_:anchor:)` + `ScrollPosition` | 2+4 | 15 (native 18) | `isPositionedByUser` one way; `scrollPosition(id:anchor:)` | 2 | 15 (native 17);
`defaultScrollAnchor(_:)` | 2 | 15 (native 17); `defaultScrollAnchor(_:for:)` + `ScrollAnchorRole` | 2+4 | 15 (native 18) | 17 twin: initialOffset only.

## 8. Risks to check on device

- R1 (load-bearing): `ztronScrollID` frames measured in `ztronContent` space must not change while the `GeometryEffect` above the layout host animates (15/17.5/27): `registry.writes`
  stays 0 during scroll/zoom/rotation. If a path re-fires per frame, measure in the layout host's own space or compare-and-skip at the reporter.
- R2 Lazy content: only realized children are registered, so `scrollTo` an off-screen lazy id is pending/no-op where native works. `ZTronLazyVStack` (M9) must supply estimated frames.
- R3 `@Environment(\.self)` capture for the context subscript makes the capturing view depend on every environment change — keep it in a leaf; verify container re-render counters.
- R4 Native bridge on 17.5/27: `ScrollTargetBehaviorContext.velocity` units and native `ScrollPosition` write-back cadence; our twin must not fight the native binding.
- R5 `.automatic` / `.alwaysByFew` semantics vs native: compare the native and ZTron carousels side by side in the demo; adjust the table in §4.
- R6 Transaction path from a Button inside the reader on the 15 fallback (M2 proved it for `scroll(to:)`; re-verify with `proxy.scrollTo`).

## Open questions
- Q1 `ZTronScrollAnimation`: does an animation type already exist from M2? If so reuse its spelling; the enum here is a placeholder.
- Q2 Position write-back content: write both `viewID` and `point`, or only `viewID` when a target exists (native behaviour unverified)?
- Q3 `scrollTargetLayout`: accept the gap that children need `ztronScrollID` (no `Group(subviews:)` auto-registration, which can't read explicit ids anyway)?
- Q4 `.always` treated as `.alwaysByOne` (pre-18 semantics); `.automatic` → compact ? `.alwaysByFew` : `.never` — confirm after R5.

## Orchestrator resolutions (2026-10-18)
- Q1 Check `grep -rn ZTronScrollAnimation Sources` at session start; if absent (as of this note it is), the placeholder
  enum in §2 is the definition (S11's `scrollTo(_:anchor:animation:)` needs it).
- Q2 Match native `ScrollPosition`: write `viewID` when the view has a target layout and a target is centred/aligned,
  otherwise write `point` (and clear `viewID`); `isPositionedByUser` true after a user scroll. ≤ 2 writes per gesture.
- Q3 Accepted: `scrollTargetLayout` requires children to carry `ztronScrollID`; off-screen lazy ids are pending/no-op
  until M9 (document in the parity matrix).
- Q4 Accepted as the starting point; confirm against a native ScrollView in the demo (R5) and record it.
- Note accepted: native `ScrollTargetBehaviorContext` isn't publicly constructible → only ours → native bridging;
  parity-matrix row "native behaviors run in ZTronScrollView: impossible (no public context init)".

## Orchestrator resolutions (2026-10-20, session M8b-s0 acting as Architect; the M6-s1 handoff's Open items)
- Open 1 → **D27 (target space = SwiftUI's).** `ReleasePipeline.decideTarget` is the one conversion point: a behavior sees `rect.origin = contentOffset + I.start`
  (content coordinates: the inset includes the safe area, a scaling header's resting height and a refresh hold), `rect.size == containerSize == V − I.total` (the
  unobscured size), and the landing is converted back, `proposed = clamp(t.rect.origin + a_t·(t.rect.size − container) − I.start)`; the `limitsVelocity` cap uses the
  unobscured length. The public `.paging` pages by the unobscured length like native SwiftUI; the UIKit knob `isPagingEnabled` keeps paging by the viewport length
  (`effectiveTargetBehavior` maps it to an internal paging behavior with `pageLength: .viewport`; `PagingSolver` unchanged). With zero insets both coincide (the M3
  table stays); with insets they differ exactly as SwiftUI and UIKit do (S2: SwiftUI first, then UIKit; note the decision in the matrix). Session 2 writes the ViewAligned
  candidates in that same space inside `updateTarget` (`c_i = r_i.min + a·r_i.len − a·W`, `W` unobscured) and relies on the single conversion. Tests: §7-1/2 re-run under
  a 62 pt top inset with the native numbers measured in `NativeBridgeTests` (notes `M6-s1-findings.md` §1) as fixtures.
- Open 2 (R4, native `velocity` units): a delegate-injected release reports 0, so it needs a real pan: session 3's `TargetsScreen` UI test records a native
  `ScrollTargetBehaviorContext.velocity` next to ours on 17.5 and 27.0. Until then the bridge passes the value through unchanged and the matrix row says "units unverified".
- Open 3 (27.0 + forced fallbacks: a parent re-evaluation builds a second copy of the content for a moment): not M6, not N-a (present at 39f09c8). One Debugger session
  after Orchestration step 3 (Orchestration open item 6). Until it lands, M6/M8b/M9 builders keep the registry's "one report per live reporter" rule and expect a
  one-frame double registration on that path only.
- Open 4 (sibling `onAppear` in reverse tree order on 27.0): accepted for now — "first match" = the member that appeared first; parity-matrix note. Session 3's demo
  compares with a native `ScrollViewReader` over two scroll views; if native resolves the upper one, `ProxyScope` switches to frame order (containers report their
  frame in a reader-level space) in session 3.
- Open 5–7: the hosted-native-`ScrollView` conversion tests (public UIKit delegate API in the TEST target only; the library stays UIKit-free) are the accepted way to
  reach `ScrollTarget`/`Context`; lazy registration (R2) is M9's; the ~45 "Observation tracking feedback loop detected" warnings of the full 27.0 unit run are an open
  item to re-check after M7 session 1 (Orchestration open item 7).

