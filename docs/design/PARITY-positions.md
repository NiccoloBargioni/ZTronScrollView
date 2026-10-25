# PARITY-positions · SwiftUI's position APIs measured against ours (PARITY-s1, 2026-10-25)

User rule (2026-10-25, Orchestration Open item 9): every case is measured against the native SwiftUI `ScrollView` in the same
demo on the same OS; ours must match wherever native behaves correctly; where native is defective the defect and our chosen
behaviour are recorded (D54). Raw readouts: side-session notes `parity-s1/*.txt` (+ `an.py`, the n / b / z comparer).

## 1. Method

- Demo `-ZTronScreen positionParity -ZTronParity position|id|anchor` (`Demo/ZTronScrollViewDemo/PositionParityScreen.swift`).
  Three panes with the same content (100 rows × 44 pt, pane 150 pt): **n** = SwiftUI `ScrollView` + SwiftUI's modifier,
  **b** = SwiftUI `ScrollView` under our twin (the native bridge), **z** = `ZTronScrollView` + our member. Options: a 50 pt
  `safeAreaInset` on top (`-ZTronParityInset 50`), the modifier's anchor, a `defaultScrollAnchor` role, the row count,
  `LazyVStack` for the native panes. Every button applies to all three panes at once.
- Readouts (`Info` → `stateInfo`): SwiftUI's offset / inset from `onScrollGeometryChange` (18+), ours from the state; where
  each pane draws its content (`dy`, a reader in row 0: works on every OS, stale in a lazy stack once row 0 is dropped);
  the bound value and every change of it (`w` = count, `seq` = the values in order); `onScrollTargetVisibilityChange`
  (threshold 0.5) per pane.
- OS / devices: 27.0 iPhone 18 Pro, 26.5 iPhone 17 Pro, 18.6 iPhone 16 Pro, 17.5 iPhone 15 Pro (fresh private simulators).
- Assertions: `PositionParityUITests` (requests, user-scroll write-back, id binding, default anchor) and
  `TargetsUITests.testViewAlignedLimitsAgainstSwiftUI` (R5). The measurement passes stay in the same file
  (`testDump…`, run with `ZS_PARITY_DUMP=1`).
- Harness errors found on the way (each one had made native look different): a reader *around* the scroll target layout
  made SwiftUI's id bindings answer `nil` (now in row 0); `ScrollPosition()` has id type `Never`, so SwiftUI never wrote a
  view id (now `ScrollPosition(idType: Int.self)`); setting a binding to the value it already holds does nothing, so a
  Reset did not scroll SwiftUI back (Reset also jumps through the reader); R5 on 17.5: the same no-op Reset, see row 15.

## 2. Parity table

✓ = ours equals native on that OS (asserted), ✗ = differs (deliberate, see the decision), — = native has no API there
(ours held to the 18+ numbers). Offsets are UIKit-style (`-inset` at the top).

| # | API · case | Native (measured) | Ours before | Ours now | 17.5 | 18.6 | 26.5 | 27.0 | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `scrollTo(point:)`, no inset | offset = point, clamped (−100 → 0, 99999 → 4250) | same | same | — | ✓ | ✓ | ✓ | parity |
| 2 | `scrollTo(point:)` / `(y:)` / `(x:y:)` under a 50 pt top inset | content-space point: offset = point − inset (300 → 250, y 500 → 450, (0,400) → 350, −100 → −50) | offset = point (300, 500, 400) | point − inset | — | ✓ | ✓ | ✓ | **fixed** |
| 3 | modifier anchor on a point request | ignored (center anchor: 300 → 300) | same | same | — | ✓ | ✓ | ✓ | parity |
| 4 | `scrollTo(x:)` on a vertical view | y jumps to raw offset 0 (500 → 0; −50 → 0 under the inset) | y kept | y kept | — | ✗ | ✗ | ✗ | native defect (D54 b) |
| 5 | `scrollTo(edge:)` top / bottom | −inset / 4250 | same | same | — | ✓ | ✓ | ✓ | parity |
| 6 | `scrollTo(id:)`, no anchor | least scroll: from above the row's bottom meets the bottom (1214), from below its top meets the unobscured top (1320 / 1270) | same | same | — | ✓ | ✓ | ✓ | parity |
| 7 | `scrollTo(id: 30, anchor: .center/.bottom)` right after `scrollTo(id: 30)` | 18.6 / 26.5: ignored (stays 1320); 27.0: 1267 / 1214 | applies | applies | — | ✗ | ✗ | ✓ | native defect before 27 (D54 c) |
| 8 | `withAnimation { scrollTo(id:) }` end offset | 2534 (center anchor 2587) | same | same | — | ✓ | ✓ | ✓ | parity |
| 9 | read-back `point` / `x` / `y` | `scrollTo(x:y:)` reads as `point`, 26+ `x` / `y` nil; `scrollTo(y:)` reads 26+ `y` | no `x` / `y` | `x` / `y` for one-axis requests only | — | ✓ | ✓ | ✓ | **fixed** (API added) |
| 10 | user scroll → `ScrollPosition(idType: Int.self)` | the reported view is written every time it changes (a 10-row fling: 11 writes), never a point; `isPositionedByUser` stays **false**. Id type `Never`: one write per gesture, nothing named, `isPositionedByUser` true | ≤ 2 writes (release target + settle), view under the anchor point else `point`, any id type | one write per view passed, id type filter, no point, `isPositionedByUser` true | — | ✓ | ✓ | ✓ | **fixed**; user flag ✗ by choice (D54 a) |
| 11 | which view a user scroll reports | anchor point nearest the unobscured area's anchor point: top anchor = nearest row top (offset 34 → row 1, 69.7 → row 2), center = the row holding the center | the row under the top edge (34 → 0, 69.7 → 1) | nearest anchor point | ✓ | ✓ | ✓ | ✓ | **fixed** |
| 12 | `scrollPosition(id:)` set by the app (ids, insets, center anchor, lazy, `withAnimation`, `nil`) | as rows 6–8 | same | same | ✓ | ✓ | ✓ | ✓ | parity |
| 13 | `scrollPosition(id:)` after a user scroll | written per row passed, nearest rule; **17.5 + non-lazy stack: never written** (lazy: written) | ≤ 2 writes | per row passed | ✗ (non-lazy) / ✓ (lazy) | ✓ | ✓ | ✓ | **fixed**; 17.5 native defect (D54 d) |
| 14 | programmatic scroll (reader jump, animated offset) | writes nothing | nothing | nothing | ✓ | ✓ | ✓ | ✓ | parity |
| 15 | R5 view-aligned limits (fling over 120 pt cells) | never 480, byOne / byFew / automatic 240 | same | same | ✓ (offsets; ids on `LazyHStack`) | ✓ | ✓ | ✓ | parity; M6-s3's 17.5 "native = 0" = row 13's defect + the no-op Reset |
| 16 | `defaultScrollAnchor` initial offset (bottom, center, inset) | 4250, 2125, 4250 | same | same | ✓ | ✓ | ✓ | ✓ | parity |
| 17 | content that fits, anchor bottom / center | drawn at 62 / 31 (SwiftUI uses a 62 / 31 content inset, offset −62 / −31) | drawn at 62 / 31 (alignment padding, inset 0) | same | ✓ | ✓ | ✓ | ✓ | drawn parity; reported geometry differs (Open) |
| 18 | content grows while the view sits at its anchored position (`.sizeChanges`, or `.alignment` when it fitted) | stays anchored (4250 → 4382, 2125 → 2191, fitted → 70 / 35) | offset kept (4250, 2125, 0) | stays anchored | ✓ | ✓ | ✓ | ✓ | **fixed** |
| 19 | content grows / rows inserted above anywhere else | offset kept (the visible rows shift) | same | same | ✓ | ✓ | ✓ | ✓ | parity |
| 20 | `.initialOffset` only, content grows before the first scroll | 27.0: re-applied (4382); 18.6 / 26.5: kept (4250); any command, even to where it is, ends it | kept | re-applied on iOS 27+ only | — | ✓ | ✓ | ✓ | **fixed**, per OS like native (D55 a) |
| 21 | 17.5, center anchor, content change away from the anchored position | keeps the offset as a fraction of the range (2244 → 2311.7 → 2379.3; 4250 → 4382) | kept | kept (18+ rule) | ✗ | ✓ | ✓ | ✓ | OS difference, ours = 18+ (D55 b) |
| 22 | 17.5, fitted content shrinks back | not re-aligned (drawn at 0; 18+: 62) | re-aligned | re-aligned | ✗ | ✓ | ✓ | ✓ | native defect (D54 e) |
| 23 | the 18+ bridge (`ztronScrollPosition` on a native `ScrollView`) | — (b must equal n) | id requests never scrolled (an `AnyHashable` wrapper matched no view); an echo write per request; 26+ `x` / `y` lost | b = n for every request and user scroll | — | ✓ | ✓ | ✓ | **fixed** |
| 24 | `onScrollTargetVisibilityChange` under a 50 pt inset | the unobscured area (offset 250: rows 7, 8) | the whole viewport (6, 7, 8) | unobscured area | — | ✓ | ✓ | ✓ | **fixed** |
| 25 | `LazyVStack`, rows inserted above | keeps the visible rows in place (1214 → 1346), even with the binding `nil` | — (no lazy stack) | — | — | — | — | — | Open: M9 |

## 3. Decisions (Orchestration D53–D55)

- **D53 · write-back.** The position bindings follow SwiftUI's measured write-back (rows 10, 11, 13) instead of M6's
  "≤ 2 writes per gesture" (design Q2): while the user moves the view the binding follows the reported view, once per change;
  programmatic scrolls write nothing; `ZTronScrollPosition` gets SwiftUI's `init(idType:…)` shapes and reports only views of
  that id type, so `ZTronScrollPosition()` (id type `Never`) reports no view — source-compatible, behaviour-visible.
- **D54 · native defects and our behaviour.** (a) SwiftUI leaves `isPositionedByUser` false once it writes a view id
  (18.6–27.0) — ours true, as documented; (b) `scrollTo(x:)` on a vertical view moves y to raw 0 — ours keeps y;
  (c) 18.6 / 26.5 ignore asking for the same id with another anchor — ours re-applies, like 27.0; (d) 17.5 never writes
  `scrollPosition(id:)` for a non-lazy stack — ours writes; (e) 17.5 does not re-align fitted content after it shrank back —
  ours does, like 18+.
- **D55 · OS-dependent native behaviour.** (a) the initial anchor re-applied on content growth before the first scroll exists
  only on 27.0 → ours on iOS 27+ only (per-OS parity); (b) 17.5's center anchor keeps a fraction of the range on content
  changes → ours uses the 18+ rule everywhere (the user may ask for the 17 rule on 15–17).

## 4. Open

- Row 17: SwiftUI reports fitted content through `contentInsets` / `contentOffset` (62 / −62) in `onScrollGeometryChange`;
  ours reports 0 / 0 (drawn alike). An M7 geometry parity item, not measured further here.
- Row 25 and lazy content generally: M9.
- Not measured: `onScrollVisibilityChange` (per view) under insets; variable-height rows (the nearest-anchor rule and a
  "more than half visible" rule agree on uniform rows); SwiftUI's per-frame position writes during a slow drag under an
  inset (26.5 / 27.0: up to 84 writes of the same id with changing hidden fields; not mirrored); non-`Sendable` ids through
  the bridge still use the `AnyHashable` wrapper (no native view matches them).
