# M8b-s8-s1 handoff · 2026-11-03 · Opus 5.5 · xhigh (workflow builder s1-refresh-31-32, resumed twice)
Status: done. Open items 31 and 32 are fixed. Open item 41 was found and fixed: the arrow → spinner cross-fade and a begin's
look switch were never drawn. Not merged. Branch `claude/cool-stonebraker-0015c9`, commits 61c7e21 … 285a535 plus the docs
commit, on 88828d7.

Changed:
- `Refresh/RefreshEngine.swift`: the carried spinner look (refresh design §3.2, item 32). A catch of a `.spinner` retraction
  keeps that look until the pull fires, the finger lifts, the pull is cancelled or the content is back at rest (8e0f364).
- `Refresh/RefreshIndicators.swift`:
  - 8e0f364: L2 (`reach` = `max(p/L, drag)` for the band's and the overlay's pull look), the C8 handover of the band's
    `.system` pull look, and L3 (`holdsPlacement` for every built-in style in the band).
  - fb4c52e: `RefreshLookSwitch` and `RefreshTransactionStash`, so a begin during a retraction switches in the cross-fade.
  - Item 41 (170c1d3, 542f59c, 8558f70, d114c6f, 782513b, 285a535): the glyphs in a `ZStack` in a 24 pt square;
    `RefreshLookFade` (the switch drawn frame by frame, with centre guides and an opacity factor); `RefreshGlyphBoundary`.
- Demo lab (`SeamLabScreen`, `SeamLabUITests`, `RefreshScreen`): `-ZTronSeamRefreshTrigger` (`rtrig<T>`), `hdef<H>`,
  `rdur<s>`, `rbegin<ms>` / `pd<pt>` and `testPullRegrab`. `scripts/seam/handover.py`, with the matching `baseline.sh` and
  `measure.sh` keys (61c7e21).
- Tests:
  - `RefreshEngineTests`, `RefreshRetractTests` and `RefreshIndicatorTests`: 9 new tests (the handover at T 30 / 40 / 50,
    `T ≥ L` bit-identical, the carried re-grab, the `.default` band end at H 20 / 30 / 45, the begin weight).
  - `RefreshUITests.testABeginWhileThePullGoesBackSwitchesTheLookOnce`.
- Docs:
  - SPEC S10: the amendment of 2026-11-03. Both "Known limit" sentences of items 31 and 32 are gone.
  - Orchestration: items 31 and 32 marked FIXED, item 41 added, a session log row.

Decisions:
- No D-number: plan C8 is the decision.
- The designer's centred `.system` pull look (L1) is not built. An established look stays, and plan §9 Q3 offers L1 as an
  option.
- The switch is drawn frame by frame with an Animatable weight, not with an animated opacity or geometry effect. SwiftUI
  resolves ancestors' animations at the leaves, and the spinner the cross-fade inserts is a new leaf.
- Open item 41, not 39. INTEG-s2's `integ-wave-2-b2` branch holds 39–40. The commit messages say 36 or 39.

Measurements (seam lab; code 285a535; before = the 61c7e21 lab on the 88828d7 library):

The 27.0 column lists two or three runs of the same scenario, comma-separated.

| row | 27.0 preferred | 17.5 | 27.0 forced |
|---|---|---|---|
| `rtrig40` largest \|Δcentre − Δpredicted\| (pt) | 9.67 → 0.83, 0.83 | 10.33 → 0.92, 0.67 | 9.67 → 1.0 |
| `rtrig40` \|centre − band/2\| from the trigger on (pt) | 10.0 → 0.33, 0.33 | 10.33 → 0.67, 1.0 | 10.0 → 0.67 |
| `rtrig40` largest one-frame opacity rise (fraction of the rise to the trigger) | 0.60 → 0.31, 0.21 | 0.62 → 0.29, 0.29 | 0.60 → 0.40 |
| `rtrig30` largest \|Δcentre − Δpredicted\| (pt) | 10.33 → 1.17, 1.0 | 10.0 → 1.0 | 10.0 → 1.0 |
| `rtrig30` \|centre − band/2\| (pt) / opacity rise | 0.33 / 0.82 → 0.33, 0.0 / 0.36, 0.34 | 0.33 / 0.84 → 0.67 / 0.30 | 0.33 / 0.82 → 0.0 / 0.27 |
| over / jumps / vanish (every after row) | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| `regrab-rdur0p2` frames with the spinner hidden | 26 → 0 | 26 → 0 | 30 → 0 |
| `fling-hold-hsys60-hend1p5` | 0 / 0 / 0, 20 pt at rest | 0 / 0 / 0, 20 pt | 0 / 0 / 0, 20 pt |
| `.default` end, `hdef30` / `hdef45` largest one-frame fall | 0.16 / 0.22 → 0.09 / 0.09 | 0.22 / 0.21 → 0.08 / 0.13 | 0.11 / 0.20 → 0.06 / 0.16 |
| `rbegin50-pd80` largest step (fraction of 11 pt), settle frames | 11.0 (1.0), 0 → 3.0 (0.27) 9, 2.33 (0.21) 8, 2.67 (0.24) 8 | 11.0 (0.94) → 2.33 (0.21) 10, 3.33 (0.29) 9 | 10.67 (0.97) → 3.0 (0.27) 9, 3.33 (0.29) 9 |
| cross-fade at a trigger | 1 frame → 5–6 frames mixed | the same | the same |
| `pull-refresh` (T ≥ L) per-band difference from before: pull / spinner / back (pt) | 0 / 0 / 0 | 0 / 0 / 0.17 | 0.33 / 0 / 0 |
| `hsys20`, `hsys30` at rest | 20 pt at band/2 | 20 pt at band/2 | 20 pt at band/2 |
| appbanner refresh \|seam\| / jump (s7: 0.10 / 0.05 / 0.09) | 0.5 / 0.13, 0.15 | 0.5 / 0.08 | 0.5 / 0.17, 0.11 |
| appbanner rotate-hold \|seam\| / hJ / bottom edge (s7: 1.08 normalisation) | 0.5 / 1.08 / 0.13 | 0.5 / 0.20 / 0.12 | 0.5 / 1.01 / 0.13 |

Notes on the table:
- The key 17.5 re-run at the end (`rtrig40`, the second 17.5 number) passes: 0.67, 1.0 and 0.29. Load was 112–150.
- The 1.17 on 27.0 `rtrig30` is one frame before the trigger, during a 6 pt band step. The glyph is 2 pixel rows behind
  there. The same measurement reads 0.67–1.0 on the before's unchanged `T ≥ L` pulls.
- The `pull-refresh` 0.17 on 17.5 and 0.33 on forced are one pixel row at the clipped edge of the turning arrow or spinner.
  Two runs of the same code differ in the same way (`n175`, `n27f`: 0.17 and 0.34).
- The 17.5 `.preserve` control's "over 1" is a false positive. In f259 the content is 157 pt away, and the frame shows
  240 pt of changed rows with no glyph intensity.
- The `fling-hold` analyze "over ~76" is the known content-under-pinned-header reading; the spinner is never over the content.

Open:
- Item 41 on real 15 / 16 (M1 Mac lane): its causes are SwiftUI semantics that the forced lane does not emulate. Check:
  - mixed arrow / spinner frames over 0.15 s at a trigger;
  - `rtrig300-rbegin50-pd80`: the glide, with no blank frame;
  - `rtrig40` / `rtrig30`: the arrow at band/2 right after the trigger, with no drift with the content;
  - a flexible custom indicator keeps its size through a begin during a retraction.
- Items 31 / 32 on real 15 / 16 are math (`RefreshIndicatorMath`) and engine code, the same on every OS. Check:
  - `rtrig40` / `rtrig30`: no centre step, opacity 1 at the trigger;
  - `regrab-rdur0p2`: no vanish;
  - `hdef30-hend1p5`: no opacity step.
- The cross-fade starts 1–3 frames after the trigger's stalled frame (item 35). Before, the swap landed in that frame. The stall
  is unchanged at 30–77 ms; the first scenario after a build reads 95–123 ms. Item 35 evidence: ProgressView creation takes
  ~40 ms of it, and a begin stalls 30–75 ms.
- Item 32's catch during a SwiftUI reset (`hreset4`) belongs to s3 (D79).

Next:
1. s2 (open item 34) and s3 (item 33 with the 17.5 header residual, and item 32 during a reset, D79), per
   `docs/design/M8b-s8-plan.md`.
2. The M1 Mac 15 / 16 checks above, once that lane exists.
3. The user merges the branch.

Tests:
- `scripts/test.sh` Refresh* (11 suites): 124 tests green on 27.0 and on 17.5, 8 known issues.
- `scripts/test-demo-ui.sh` `RefreshUITests`: 17/17 on 27.0 preferred, 17.5 and 27.0 forced.
- `scripts/build.sh`: green.
- Seam lab lanes: h27, h27b, h27c, h175, h175b, h27f, h27fb, k175, n175, n27f and n27, all 0 failures.

Usage: not measured by this subagent.
