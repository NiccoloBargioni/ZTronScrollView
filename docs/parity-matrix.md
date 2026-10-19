# Parity matrix

Every SPEC S8 inventory item and every S9/S10 API → strategy, min OS, fallback, test, status
(full / approximate / impossible, with the reason). Strategies refer to SPEC S8 (1 = environment-backed,
2 = same-name member + `ztronScroll` twin, 3 = dual-mode content modifier, 4 = type mirror).

| API | Strategy | Min OS | Fallback | Test | Status |
|---|---|---|---|---|---|
| `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` → `ZTronScrollViewReader` / `ZTronScrollViewProxy` (+ `scrollTo(_:anchor:animation:)`, `ZTronScrollAnimation`) | 2 | 15 | ids our registries do not know go to the SwiftUI proxy of an internal `ScrollViewReader` (native `ScrollView`s inside the reader); `withAnimation` honored by the ambient overload | ProxyTests, ScrollToTests | full (ids off-screen in lazy content: pending until M9) |
| `.id(_:)` scroll targets → `ztronScrollID(_:)` | 3 | 15 | `id(_:)` + frame reporter into the registry (`onGeometryChange` 16+, `GeometryReader` + preference on 15); plain `id(_:)` outside a `ZTronScrollView` | TargetRegistryTests | full |
| `scrollTargetBehavior(_:)` → member `ZTronScrollView.scrollTargetBehavior(_:)` + `View.ztronScrollTargetBehavior(_:)` | 2a+2b | 15 (native 17) | the twin writes the environment overlay and applies SwiftUI's modifier on 17+ (`.paging` as SwiftUI's own, custom behaviors bridged); member wins over twin | TargetBehaviorTests, ScrollConfigTwinTests | full |
| `ScrollTarget`, `ScrollTargetBehavior` + `TargetContext` / `Properties` / `PropertiesContext` → `ZTronScrollTarget`, `ZTronScrollTargetBehavior` + `ZTronScrollTargetBehaviorContext` / `…Properties` / `…PropertiesContext` | 4 | 15 | conversions on 17+: native → ours for target and context; ours → native only by writing into the target SwiftUI hands out (`ScrollTarget` has no public initializer); native behaviors cannot run in a `ZTronScrollView` (`ScrollTargetBehaviorContext` is not constructible) | ScrollConfigTwinTests | approximate (documented gaps) |
| `PagingScrollTargetBehavior` → `ZTronPagingScrollTargetBehavior` (`.paging`) | 4 | 15 | ≡ `isPagingEnabled` (same `PagingSolver` call, same end positions) | TargetBehaviorTests | full |
| `AnyScrollTargetBehavior` → `AnyZTronScrollTargetBehavior` | 4 | 15 (native 18) | — | TargetBehaviorTests | full |
