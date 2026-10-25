# PARITY-s1 handoff · 2026-10-25 · Opus 5.5 (side session, Orchestration Open item 9: positions compared against native)
Status: done on branch `claude/elastic-kirch-23bf73` (not merged) — three user confirmations pending (D53, D54 a, D55 b).
Report: `docs/design/PARITY-positions.md` (method, the 25-row parity table per API × OS, decisions, open). Raw readouts and
the n / b / z comparer: side-session notes `parity-s1/`.
Changed:
- Demo `PositionParityScreen.swift` (new, `-ZTronScreen positionParity -ZTronParity position|id|anchor`): SwiftUI's
  `ScrollView` (n), SwiftUI's under our twin (b) and ours (z) side by side, one command to all, readouts of offsets, drawn
  position, bound values and their changes, target visibility. `TargetsScreen` aligned section: SwiftUI's offset probe,
  `-ZTronTargetsLazy`, Reset through a reader; position section uses `idType: Int`.
- `PositionParityUITests` (new): requests, user-scroll write-back, id binding, default anchor — native vs ours vs bridge
  per step; `testDump…` measurement passes behind `ZS_PARITY_DUMP=1`. `TargetsUITests` R5 compares offsets and ids with
  SwiftUI's (lazy stack on 17), 180 pt drag (mid-cell).
- `PositionDriver`: content-space points (offset = point − leading inset); write-back = one write per change of the
  reported view while the user moves the view (`didScroll` in the user phases + settle), nearest anchor point among the
  binding's id type, no point; release hook no longer writes; held initial anchor; 17's id-binding default anchor.
- `ZTronScrollPosition`: `init(idType:…)` shapes (SwiftUI's), `idType`, `x` / `y`, Sendable-typed ids for the bridge,
  custom `==`. `NativeBridges` / `ScrollPositionModifiers`: typed ids, id type kept, echo writes skipped, 26 `x` / `y`.
- `ZTronScrollState`: `offsetAfterContentSizeChange` (SwiftUI's content-size rule, initial anchor re-applied on 27+),
  `didScroll` → driver, a command to where the view is still ends a held initial anchor. `ZTronScrollGeometry.unobscuredRect`
  + target visibility against it.
- Docs: parity-matrix rows (view-aligned, `ScrollPosition`, `scrollPosition(id:)`, `defaultScrollAnchor`, target
  visibility), SPEC S7 / S8 amendments, Orchestration item 9 + D53–D55, STATE row.
Decisions: D53 write-back = SwiftUI's (replaces M6 Q2); D54 native defects not mirrored (a user flag, b `scrollTo(x:)`
resets y, c same id + new anchor ignored on 18/26, d 17.5 id binding of eager stacks, e 17.5 fitted re-alignment);
D55 OS-dependent native behaviour (a initial anchor on growth: 27+ only, b 17.5 center fraction rule not mirrored,
c 17's id-binding top alignment mirrored on < 18).
Open:
- User: confirm D53 (behaviour-visible: `ZTronScrollPosition()` reports no view, like `ScrollPosition()`), D54 a, D55 b.
- Fitted content: SwiftUI reports its alignment as content inset / offset in `onScrollGeometryChange`, ours as padding
  (drawn alike) — M7 geometry parity follow-up.
- Native `LazyVStack` keeps visible rows in place on insertion above (M9). Not measured: per-view `onScrollVisibilityChange`
  under insets, variable-height rows for the reported-view rule.
- Not this change (seen in the full suite): `PanUITests.testControlsUsable` red on 17.5 = the `PositionTicket` wrapper
  regression whose fix (DBG-s2, e8c5674 on `claude/determined-lederberg-7907ea`) was never merged into main;
  `ProofUITests.testNoClockTicksAtRest` red on this fresh 27.0 device at the base commit 80e2e08 too (2 ticks, the known
  fresh-device artifact); `PagerUITests.testPagerArbitration` on 17.5 = Q3 (D50).
Next: 1. User answers D53 / D54 a / D55 b. 2. Merge the branch (docs rows touch shared files: parity-matrix, Orchestration,
STATE, SPEC). 3. M7 follow-up: `ScrollGeometry` for fitted content.
Tests (private fresh simulators, own derived data):
- Unit `scripts/test.sh -only-testing:ZTronScrollViewTests` → 681/681 (57 suites) on 27.0 and 17.5 at 4f78481 + the 17
  id-anchor change (touched suites re-run green on both after it).
- `PositionParityUITests` (4 tests) + `TargetsUITests` (7): 27.0, 17.5 green in the full suite at bf64fa9; 18.6 11/11 and
  26.5 11/11 (one launch-flake re-run) at 4f78481 + R5 re-run with the mid-cell drag (18.6 / 26.5 at da9d482); the 17
  id-anchor change only touches < 18.
- Full demo UI suite (173 tests, preferred path) at bf64fa9: 27.0 161 passed + 10 skipped by design + 2 failed
  (`ProofUITests.testNoClockTicksAtRest`: same failure at the base commit on this device; `ScrollDisabledUITests.
  testNativeScrollDisabledOnAParentStopsTheView`: green alone); 17.5 158 passed + 10 skipped + 5 failed (Q3 pager, the
  unmerged DBG-s2 text-field fix, 3 infra "Failed to terminate" / "the sheet appeared": green alone). No runner restarts.
Usage: not read; one session, ~25 UI lanes on four private simulators at host load 100–950.
