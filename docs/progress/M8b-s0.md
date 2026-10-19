# M8b-s0 handoff · 2026-10-19 · Fable 5.1 · xhigh (side session, Architect: design only, no code)
Status: done — the user's three M8b decisions are in the SPEC and in the M8b/M8 designs; nothing built, nothing to test.
Changed:
- docs/SPEC.md: S9 (header refresh route removed; `onZTronScrollReachEdge` is the only reach-edge API); S10 rewritten (`withScalingHeader(size:scalingBehavior:snap:fade:header:)`,
  `.fixed(min:max:)` / `.aspectRatio(_:min:)` / `.fit(min:)`, `.preserve` / `.stretch` geometry table, proxy + reader pattern with the rationale, horizontal case, natural height,
  degenerate cases, refresh with the header, snapping in one convention, performance tiers, migration table from ScalingHeaderScrollView); S11 (header block replaced by the member;
  state additions `headerGeometry` / `snapHeader(to:)` and `ZTronScrollGeometry.header`; "Delegate callbacks as modifiers": the 14 UIScrollViewDelegate methods → 13 `onZTronScroll…`
  modifiers with signatures, `viewForZooming` → `zoomRange`, coexistence rules with a delegate object); S5 (closures stored cold, never observed); S14 (demo bullets, test bullets,
  ports line). Every change is marked "Amendment 2026-10-19 (user)"; amendment text uses the repo names (CLAUDE.md map), the unamended text keeps `ZoomScroll`.
- docs/design/M8b-refresh-header.md: head + §1 kept (header routes removed); §2 rewritten (types, data flow, the render-time constraint vs the user's reference, formulas,
  pattern decision with alternatives A–G, iOS 15 fallback, edge cases); §3 builder split (M8b-3 files, no forwarding file, no container type), tests 1–15 with the
  render-counter proofs (test 7), parity rows, device risks R1–R10; open questions A1–A10 + Orchestrator resolutions (2026-10-19); 2026-10-18 Q5 voided.
- docs/design/M8-chrome.md: §7b delegate modifiers on M7's `ObserverHub` (`notifyX` wrappers at the 13 delegate call sites), task M8-8, `DelegateModifierTests`, resolution line.
- Orchestration.md: header, M6–M9 state row, step 2g, D26, session log. docs/progress/STATE.md M8b row, usage-log row.
Decisions (D26 in Orchestration.md):
- Header geometry reaches children through `ZTronHeaderProxy` + `ZTronHeaderGeometryReader(header, of:)` (the existing reader tier over `ZTronScrollGeometry.header`), not an
  ObservableObject / @Observable: object-wide invalidation on 15–16, no derived (Equatable) gating, and an object in the builder's hand invites hot reads in the builder's scope.
  The proxy exposes no geometry, so that read is impossible by construction. A `DynamicProperty` wrapper (E) is possible later as sugar over the same engine.
- The header is reserved as part of `adjustedContentInset.top` and drawn in the viewport overlay (top edge pinned): "precedes the content" holds on vertical and horizontal views,
  the content's layout never changes (S4.1). The frame leaf is the TransformHost pattern on the `.target` channel with an animatable `frame(height:)` → lockstep with the content
  transform under transactions, header body never re-evaluated; readers report the presentation geometry.
- `.preserve` = pinned header, gap opens below it; `.stretch` = grows by the already rubber-banded overscroll (no second band); collapse = shrink from the bottom in both;
  `.stretch` does not force bounce (a refresher does); `.fit` = measured ideal height, `.aspectRatio` = the computed equivalent (recommended for banners).
- `withScalingHeader` returns `Self` with an AnyView-erased builder (identity proof = test 11); `ZTronScalingHeaderScrollView` and the forwarding file are gone; redundant
  reference modifiers dropped (A4) and one snap convention (A5).
Open:
- A1–A10 at the end of the M8b design are the user's to veto before M8b-3 starts; most likely to draw a comment: A1 (gap below the header under `.preserve`), A2 (no slide-up
  collapse mode), A3 (`.stretch` does not force bounce), A4 (`scrollViewDidReachBottom`, `hideScrollIndicators`, `collapseProgress`, `scrollToTop(resetScroll:)` dropped).
- CLAUDE.md's naming map still lists `ZTronScalingHeaderScrollView` (the type no longer exists); fix at the next CLAUDE.md touch.
- `.fit` on iOS 15 does not re-measure on header *content* changes (matrix gap); `.fixed` / `.aspectRatio` have no gap.
- M9-virtualization keeps consuming `metrics.headerObscured` = live header height; contract unchanged, text not touched.
- Another session is editing `Sources/…` in this checkout (PanCoordinator, PanSession, ScrollEnvironment, a new NestedScrollArbiter): not mine, not committed here.
Next: 1. The user reads SPEC S10 + A1–A10 and vetoes in one line if needed. 2. M8b-1/-2 (Sonnet) after M5 (a) + M6 s1; M8b-3 (one Fable builder) from the amended docs;
M8-8 (delegate modifiers) right after M7 s1. 3. Orchestration step 3 (full demo UI re-run) unchanged.
Tests: none run (docs only). Unit 178/178 and physics 111 unchanged on main 87a2178.
Usage: weekly all-models 20% → 25% · Fable 39% → 49% (end readings; the parent orchestrator ran concurrently, so the delta is an upper bound) · cache hit n/a · context 29% of 1 M.
