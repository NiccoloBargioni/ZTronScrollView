# i28: sharp `.stretch` text: D76's `.keepTextSize` case (grow by layout) and the seamless switch with `.keepTextMagnified`

> Committed by the M8b-s8 architect (2026-11-03) from the designer's scratch doc, unchanged below this note. Build order, numbering and the architect's amendments: [M8b-s8-plan.md](M8b-s8-plan.md) (they win where they differ). Scratch paths (`s8/i28-stretch-blur/…`, `scratchpad/s8/…`) are gone after a reboot; the text artifacts (patches, tools, tables) persist in the shared notes folder `m8b-s8-resume/s8-spikes/i28-stretch-blur/`.

Designer `i28-stretch-blur`, batch M8b-s8, 2026-11-02. Base 09226f4 on `claude/cool-stonebraker-0015c9`. This covers open item 28.

**Binding: user ruling D76** (Orchestration 72ca7fc; RULES2; status PENDING).

- The `.stretch` fix is an OPTION: an enum parameter of `withScalingHeader`, placed beside D75's.
- The default is `.keepTextMagnified`: D69's look, which must still become crisp. That is the job of `d76-magnified-eval` and
  M8b-s9.
- The other case is this design.
- In this batch: build the enum, the parameter, the grow case, and `.keepTextMagnified` exactly as today's D69 rendering.
  Structure it so that the crisp path can be added later without an API change. No UIKit.

This revision replaces the first draft's "Decision", which made grow THE look, added no API, and claimed D76 as its number. The
first draft is kept at `s8/i28-stretch-blur/design-draft1.md`.

The spike code ran in two scratch worktrees, `wt` (the variants) and `wt2` (the mix). Both were removed at the end of the
session. Their diffs against 09226f4 are kept as `s8/i28-stretch-blur/spike-variants.patch` and `spike-mix.patch`; the
second includes the first. No library code was committed.

## 0. Summary

**Root cause.**

- D69 draws the pull with `HeaderStretchEffect`, a `GeometryEffect`. SwiftUI's Core Animation renderer turns its scale into a
  `CALayer.transform` on each leaf layer of the header.
- Text is drawn into a bitmap layer (`CGDrawingLayer`, `contentsScale` 3). It is rasterized at its UNSCALED bounds, then
  magnified by `s` with bilinear filtering.
- `d76:swiftui` found that SF Symbols, paths and fills are vector layers and stay crisp. Images are magnified like text,
  as expected for an image.
- At `s` 1.25 the text's edges (the 10–90 % width of straight stems) are 1.49–1.52x wider than at rest. At `s` 1.5 they are
  1.73x wider. This is the same on 27.0, 17.5 and forced.
- No pure-SwiftUI input re-rasterizes a CA-drawn leaf at a higher density: `\.displayScale` only moves layout rounding.

**Why 17.5 seemed to blur less.**

- The two lanes render the same, pixel for pixel. The old "1.25x on 17.5 against 1.8x on 27.0" came from the measurement.
- On iPhone 15 Pro, `recordVideo` (h264, even width) writes the 1179 px screen 1178 px wide, which resamples it.
- That blurred 17.5's rest reference: stems are 2.06 px in the video against 1.32 px in a lossless PNG.

**What this batch builds (D76).**

- **API.** `ZTronHeaderStretchContent { keepTextMagnified, keepTextSize }`, passed as `stretchContent:` right after D75's
  `fittingContent:`. The default is `.keepTextMagnified`.
- **One mechanism for both cases.** The pull `g` is split into two shares, with `m` = 0 for `.keepTextMagnified` and 1 for
  `.keepTextSize`:
  - a laid-out share `g_l = m·g`;
  - a magnified share `g_s = g − g_l`.
- **How it is drawn.**
  - The stack is proposed `(W·s_l, h + g_l)` with `s_l = (h + g_l)/h`.
  - D69's own `HeaderStretchEffect` magnifies the rest, `s_eff = (h + g)/(h + g_l)`.
  - The clip is the slot's `W × (h + g)`. The fade's pull weight takes `R = layoutHeight − g_l`.
  - The drawn outer frame is `W·s × (h + g)` for every `m`.
- **`.keepTextMagnified`, m = 0.** Pixel-identical to D69 on 3 lanes (max diff 0, §2.4); every expression reduces exactly.
  - Its blur is the remaining half of item 28, scheduled for M8b-s9. `d76-magnified-eval` found pure SwiftUI not viable and is
    evaluating scoped UIKit.
  - The crisp path plugs into the `g_s` share (§4.12).
- **`.keepTextSize`, m = 1.**
  - Text stays at 1.00x on every lane: at rest, held at 60 and 120 pt, and in an animated 120 pt pull.
  - The user's aspect-fit image grows pixel-identically to D69 on all 3 lanes.
  - Platform views stay native, the render counters are unchanged, and the fade is bit-identical with the fix.
  - Seam lab: every scenario is within the thresholds on 3 lanes (§2.2).
- **Runtime switch** (§2.4, 3 lanes).
  - `m` is animatable data, paired with `o′`, in every consumer. Under `withAnimation` the header morphs inside an outer
    frame that does not move: the text box is monotone, 669 → 535 px.
  - Recorded at 60 Hz, a 1 s switch moves the text box by at most 0.03 of the change per frame. The header's rows stay
    constant and the seam stays at 0 px.
  - Unanimated, the switch lands in one frame, like D65's member.
- **The 15 path.** It lands on i15b's slot reader (`W`) and `.fit` box (D78). While pulled, the box is laid out at `W·s_l`
  and still measures at `W`: a flexible frame's ideal width answers the ideal query (§2.5).

**Rejected (measured, §2).** Every pure-SwiftUI lever for a crisp *magnified* look:

- `drawingGroup` variants: platform views turn into placeholders, materials are drawn by RenderBox, and a 60 pt hole opens.
- `displayScale`: no effect.
- Layer-group changes: no effect.

This agrees with `d76-magnified-eval`'s verdict.

## 1. Evidence

### 1.1 Method (lossless, reproducible)

- **Screenshots.**
  - The scratch demo shows the seam lab with `-ZTronSeamHeaderText 1`: black 24 pt text, centred in a pure-red fixed 240 pt
    header.
  - A steady programmatic refresh hold uses `-ZTronSeamHold 1 -ZTronSeamHoldHeight 60|120 -ZTronSeamHoldProbe 0`, which gives
    `s` 1.25 and 1.5.
  - Screenshots are taken with `xcrun simctl io <udid> screenshot --type=png`: lossless, no UI lock, no XCUI.
- **Meter.** `s8/i28-stretch-blur/edges.py` measures the 10–90 % red-channel distance of every red-to-black transition inside
  the text's box.
  - "all" counts every transition.
  - "stem" keeps only straight edges: the crossing moves less than 0.35 px between neighbouring scanlines.
  - `h` is horizontal edges, `v` vertical edges. Ratios are against the same lane's rest screenshot.
- **Layer dump.** `-ZTronSpikeDump <s>` (scratch `Spike28Lab`, demo only) prints the key window's layer tree: class,
  delegate, frame, bounds, transform, `contentsScale`.
- **Counters.** `-ZTronSpikeCounters t1,t2,…` prints `ZTronRenderCounters`: `content.body`, `header.builder`,
  `header.content` and `header.frame` (leaf runs).
- **Devices.**
  - iPhone 18 Pro (27.0, 402 × 874 pt).
  - iPhone 15 Pro (17.5, 393 × 852 pt).
  - Forced = 27.0 with `-ZTronForceAllFallbacks` (the 15–16 code path).

### 1.2 Base (D69) numbers: identical on every lane

| lane | rest stem h / v (px) | held 60 pt (s 1.25) stem h / v | held 120 pt (s 1.5) stem h / v | "all" h at 1.25 / 1.5 |
|---|---|---|---|---|
| 27.0 | 1.323 / 1.319 | 1.969 / 1.998 (×1.49 / ×1.52) | 2.289 / 2.282 (×1.73 / ×1.73) | ×1.54 / ×1.83 |
| 17.5 | 1.323 / 1.314 | 1.965 / 1.993 (×1.49 / ×1.52) | 2.229 / 2.279 (×1.69 / ×1.73) | ×1.54 / ×1.76 |
| forced | 1.323 / 1.319 | 1.969 / 1.998 (×1.49 / ×1.52) | 2.289 / 2.282 (×1.73 / ×1.73) | ×1.54 / ×1.83 |

- The text box grows from 541 × 59 px to 675 × 72 (×1.248) and 809 × 85 (×1.495).
- An animated 120 pt pull (`withAnimation(.easeInOut(duration: 1))`) blurs the same as a hold: ×1.73 on 27.0, ×1.69 on 17.5,
  ×1.72 on forced.

### 1.3 Root cause (layer dump, 27.0, s 1.25; 17.5 and forced the same)

```
CALayer        d=_SwiftUILayerDelegate fr=(-50.25,62.00,502.50,300.00) b=(402.00,240.00) T=(a 1.25 d 1.25) cs=3.00 bg=red
CGDrawingLayer d=_SwiftUILayerDelegate fr=(88.08,194.08,226.25,35.83) b=(181.00,28.67)  T=(a 1.25 d 1.25) cs=3.00
```

- The effect's scale is pushed down onto every leaf layer. On 17.5 the delegate is `CGDrawingView`.
- The text is drawn into a 181 × 28.67 pt bitmap at 3x, and Core Animation scales that bitmap by 1.25.
- Image layers are magnified the same way. That is expected for an image and does not show as an edge problem.

### 1.4 What is not the cause (measured)

- **The layer group.** The stems are bit-identical to base (×1.49 / ×1.73):
  - with no group (`nogroup`);
  - with `compositingGroup()` on 17+ instead of `geometryGroup()` (`cg`).
- **Density.** `.environment(\.displayScale, 3·k)` was tried three ways:
  - static ×2 (`ss`);
  - on a `drawingGroup` inside the scale (`ssdg`);
  - per frame at 3·s (`dyn`, Animatable on `o′`).

  The stems stayed at ×1.49–1.50 and ×1.71–1.73, and the dump shows `contentsScale` staying at 3.00. The environment only
  moves layout rounding, a side effect: text width 181.00 → 180.83 pt, header 402.13 pt.

## 2. Spikes (three lanes, lossless PNG; seam lab in §2.2; mix in §2.4)

### 2.1 Approaches

Each lane cell gives the stem ratios held at 60 pt / held at 120 pt, against the same lane's rest.

| approach | mechanism | 27.0 | 17.5 | forced | platform views | verdict |
|---|---|---|---|---|---|---|
| A1 `nogroup` / A2 `cg` | layer group removed / changed | ×1.49 / ×1.73 | — | — | native | no effect |
| B1 `ss`, B2 `ssdg`, B3 `dyn` | `\.displayScale` ×2 / on a DG / 3·s per frame | ×1.49–1.50 / ×1.71–1.73 | — | — | native | no effect + rounding side effects |
| C1 `dgout` | `drawingGroup()` inside the scale (its texture scaled) | ×1.50 / blur | — | — | placeholders | blurred |
| C2 `dgin` | `drawingGroup()` around the scaled stack | ×0.97 / ×1.04 | ×0.97 / ×1.04 | ×0.97 / ×1.04 | placeholders | crisp, but the texture ends at the layout frame, so the stretched band is not drawn: a 60 pt hole (red 59–299 pt, content at 359) |
| C3 `dg2` | C2 with the drawing group's frame extended by `g + 2` pt below (Animatable on `o′`) | ×0.97 / ×1.04 | ×0.97 / ×1.04 | ×0.97 / ×1.04 | **placeholders**: TextField, Toggle, ProgressView show a yellow ⊘ on 17.5 and 27.0. A header material is drawn by RenderBox (mean R 218.7 against 223.4, ≤ 10/255). Blend modes are isolated on 17+ too. | crisp and magnified; red reaches the content top exactly (27.0 62–362 / 62–422, 17.5 59–359 / 59–419) |
| **D `relayout` ("grow") = `.keepTextSize`** | stack laid out at `(W·s, h_L·s)`, top-centred; no transform | **×1.00 / ×1.00** | **×1.00 / ×1.00** | **×1.00 / ×1.00** | **native** (they keep their size) | crisp; text keeps its size; width-following multi-line text re-wraps |
| E per-OS mix | different approaches per OS | — | — | — | — | not needed: the rendering is identical on every lane |

The animated 120 pt pull, sampled mid-pull at `s` ≈ 1.5:

| lane | base | C3 | D |
|---|---|---|---|
| 27.0 | ×1.73 | ×1.04 | ×1.00 |
| 17.5 | ×1.69 | ×1.04 | ×1.00 |
| forced | ×1.72 | ×1.04 | ×1.00 |

**The user's setup.**

- The demo `appbanner` is `NavigationView` + `GeometryReader`, `.aspectRatio(16/9, min: 0)`, `.refit`, and a red `Image`
  with `.aspectRatio(16/9, contentMode: .fit)` and `maxWidth: .infinity`.
- Held at 60 pt, the red rows are the same for base, C3 and D on each lane: 116–402 pt on 27.0 and forced, 59–340 pt on 17.5
  (`R + 60`: 226 + 60, 221 + 60).
- The image grows from its top centre, with its bottom on the content's top, exactly as with D69.

**Render counters.** Each of the 3 lanes was run with base, C3 and D, through a held 120 pt refresh and an animated 120 pt
pull and return:

- `content.body`, `header.builder` and `header.content` stay at 1 (the install).
- `header.frame` goes 4 → 43–45 over the hold and 4 → 5 → 6 over the animated pull.
- `transform.effect` goes 6 → 84–87 over the hold and 6 → 129 → 251–253 over the animated pull.

The numbers are the same across approaches. Grow adds no body run (S4).

**Multi-line text** (`-ZTronSeamTextLong 1`, a centred 2-line text with 16 pt padding, 17.5):

- D re-wraps it at `s` 1.25 and at 1.5, to longer lines cut at the sides.
- C3 keeps the line breaks, magnified, also cut at the sides.
- Both cut at the sides, as D69 did.
- Montage: `s8/i28-stretch-blur/shots/e9/long-montage.png`.

**Platform views** (`-ZTronSeamHeaderExtra field,toggle,spinner`, held 60 pt; 27.0 Layout path and forced). The count is
the yellow placeholder pixels in the header region:

| variant | yellow px | rendering |
|---|---|---|
| base | 0 | native controls, magnified and blurred |
| D, Layout path | 0 | native controls at their own size |
| D, forced | 0 | native controls at their own size |
| C3 | 39,947 | three ⊘ placeholders |

17.5 showed the same: C2 and C3 gave placeholders, D gave native controls. Montage: `s8/i28-stretch-blur/shots/e14/x-montage.png`.

**Fade under grow.** Tested on 17.5, Layout path and forced path, with `-ZTronSeamFade split`:

- The setup: the rest fade from 0.5 and no pull fade, so the pull crossfades the fade out by `min(1, g/(R/2))`.
- Measurement: `fadecmp.py`, where the green channel is the white's opacity, column 40 px.
- **Without the fix,** D was off by up to 26/255 at 60 pt and 85/255 at 120 pt. The weight was taken against `R + g`.
- **With the fix** (`R = layoutHeight − g`, flag `-ZTronSpike28FadeFix 1`), the pixels were bit-identical to D69 (max |dG|
  0) at 60 and 120 pt.
- **Forced** with the fix was bit-identical to D69 and to the Layout path.

**`.fit` under grow** (17.5, `-ZTronHeaderSize fit`, text, held 60 and 120 pt).

- The pre-i15b 15-path plan was modified: `fitRest` is off while `g > 0`, so the frame is `R + g`, plus the side pad.
- Crisp: ×1.00, text box 541 × 59 px, against base ×1.50 at 60 pt and ×1.77 at 120 pt.
- The Layout and forced paths were pixel-identical at 60 pt. At 120 pt the only difference was the status-bar clock.
- The header's last red row and the content's first row were adjacent (seam 0) on both paths.

**`.slideBehind` under grow** (17.5 Layout and forced paths; an `.aspectRatio` header with R 221 pt, text, held at 60 pt).

- D measured ×1.00. Base measured ×1.50, at `s` = 1.27.
- The red rows were identical on both paths, 177–1019 px, for both base and D.
- The content's first row is the next row on both paths, so the seam is 0.

### 2.2 Seam lab (`scripts/seam/baseline.sh` + `analyze.py`; thresholds |seam| ≤ 1 pt, lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change)

Spike `wt` (variant flag `-ZTronSpike28 <v>`), scenarios from `scripts/seam/baseline.sh` with the lab's `text` header.
Variants: `base` = D69 as built, `relayout` = grow (`.keepTextSize`, `m` = 1), `dg2` = C3. Cell = max |seam| (pt) / max
lateral (pt; `-` = no width change) / max header step (content step), as fractions of the segment's change. `r` = the
cell comes from the quiet re-run lane (§2.3). The D69 column is M8b-s7 wave 1 (code 9a3ebf5), same scenario, same lanes.
`seamall.py` regenerates it from `s8/i28-stretch-blur/seam/<lane>/<run>/summary.json`.

| scenario | variant | 27.0 | 17.5 | forced | D69 wave 1 (27.0 · 17.5 · forced) |
|---|---|---|---|---|---|
| `aspect-rest-stretch-pull-refit-appbanner` | relayout | 0.50/-/0.10 (0.10) | 0.50/-/0.09 (0.09) r | 0.17/-/0.06 (0.06) | 0.50/-/0.03 · 0.50/-/0.10 · 0.50/-/0.08 |
| `aspect-rest-stretch-rotate-uncapped-hold` | relayout | 0.17/0.11/0.23 (0.17) | 0.17/0.09/0.24 (0.15) | 0.17/0.08/0.24 (0.23) | 0.50/0.11/0.24 · 0.50/0.13/0.25 · 0.50/0.12/0.24 |
| `aspect-rest-stretch-width-hold` | base | 0.50/0.35/0.07 (0.07) r | — | — | 0.50/0.34/0.07 · 0.50/0.28/0.09 · 0.50/0.34/0.10 |
| `aspect-rest-stretch-width-hold` | relayout | 0.33/0.34/0.07 (0.07) r | 0.50/0.28/0.07 (0.07) r | 0.50/0.28/0.12 (0.12) | 0.50/0.34/0.07 · 0.50/0.28/0.09 · 0.50/0.34/0.10 |
| `fit-rest-stretch-rotate-hold-text` | base | 0.50/0.13/0.24 (0.15) r | — | 0.50/0.12/0.25 (0.17) | 0.50/0.13/0.24 · 0.50/0.11/0.26 · 0.50/0.14/0.23 |
| `fit-rest-stretch-rotate-hold-text` | relayout | 0.34/0.15/0.25 (0.14) r | 0.17/0.10/0.26 (0.14) r | 0.17/0.12/0.25 (0.14) | 0.50/0.13/0.24 · 0.50/0.11/0.26 · 0.50/0.14/0.23 |
| `fixed-rest-stretch-pull-text` | base | 0.17/-/0.12 (0.12); quiet 0.17/-/0.03 | 0.17/-/0.03 (0.03) r | 0.17/-/0.05 (0.05) | 0.33/-/0.12 · 0.17/-/0.12 · 0.17/-/0.06 |
| `fixed-rest-stretch-pull-text` | relayout | 0.17/-/0.23 (0.23); quiet 0.17/-/0.10 | 0.17/-/0.06 (0.06) r | 0.17/-/0.13 (0.13) | 0.33/-/0.12 · 0.17/-/0.12 · 0.17/-/0.06 |
| `fixed-rest-stretch-pull-text` | dg2 | **0.17/-/0.58 (0.58)** | 0.17/-/0.00 (0.00) | 0.17/-/0.00 (0.00) | 0.33/-/0.12 · 0.17/-/0.12 · 0.17/-/0.06 |
| `fixed-rest-stretch-rotate-hold-text` | relayout | 0.17/0.22/0.16 (0.17) | 0.27/0.17/0.07 (0.10) r | 0.17/0.20/0.07 (0.10) | (no wave-1 run) |

**Verdict.** Every `relayout` cell passes on every lane: |seam| ≤ 0.50 pt, lateral ≤ 0.34 pt, steps ≤ 0.26 of the change.
- **Seams** are at or under D69's own: 0.17–0.34 pt where D69 had 0.50.
- **Lateral** is within 0.02 pt of D69's, or better.
- **Steps** are within D69's range, with three cells to read:
  - The 27.0 pull and fit cells are explained in §2.3.
  - The 27.0 `appbanner` step is 0.10, against wave 1's 0.03, with no base run in this batch. A pull's step varies
    0.03–0.12 between runs of the same build (base: 0.12 in `s27`, 0.03 quiet). 17.5 and forced are at or under D69's.
- **Refresh indicator.** These scenarios use no band indicator; the band scenarios are the builder's (step 5).
- **`dg2`** fails the step criterion on 27.0.

### 2.3 Seam-lab notes

- **Lanes, times and loads** (`sysctl vm.loadavg`, 1-minute value; per-run lines in `seam/<lane>/loads.txt`). Every lane
  ran on its own simulator clone and its own derived data, under the seam lock and then the UI lock.
  - `s27`: 27.0 preferred, 16:39–16:46, load 20–143.
  - `s175`: 17.5, 17:24–17:37. Four runs ran at load 314–939. The cause was my fresh simulator boots and the mix build
    beside other sessions' lanes. Those four runs (width, appbanner, fixed-rotate, fit) and the pull pair were re-run
    as `s175r`, 18:01–18:04, at load 4–5. The `r` cells are from `s175r`.
  - `s27f`: 27.0 forced (`-ZTronForceAllFallbacks`), 17:44–17:50, load 6–9. The fit base run was at 165.
  - `s27r`: 27.0, the width and fit pairs re-run, 17:51–17:53, load 17–94.
  - `s27p`: 27.0, the pull pair re-run at load 3 (18:10). These are the "quiet" cells.
- **The 27.0 fit `relayout` step.** In `s27` the step was 0.46. It came right after a 1030 ms recorder gap: one step
  spanning unrecorded frames. The `s27r` re-run gives 0.25, the same as base's 0.24.
- **The 27.0 pull `relayout` step** (0.23 in `s27`, 0.10 quiet, against base 0.12 / 0.03). It is an attribution
  artefact, not motion.
  - The return's first motion frame lands right after a ~1.5 s idle gap, and `analyze.py` counts it in the pull
    segment's end. Base got a static frame first.
  - The motion itself is the same: first steps −9.3 pt (grow) against −7.3 pt (base), and a 12.8 pt peak on both.
  - All values are below 0.5 in any case.
- **The 17.5 pull `relayout` seam.** The first `s175` run gave 0.33 pt. It did not repeat: `s175r` gives 0.17, the same
  as base. R10 covers the ⅓ pt class.
- **The held refresh's indicator** (the lab's white 20 pt probe, `scripts/seam/probe.py`, all 17 hold runs). Wherever the
  probe itself is the detection (≤ 3.5 k px, |lateral| ≤ 0.42 pt), its bottom stays within 1 pt of rest, 20–21 pt above the
  header's bottom. That is 0 frames over the content, in both variants, on 3 lanes.
  - The aspect and fit rotations also have 33–52 landscape frames that deviate. These detect the lab's white buttons
    instead: 5–18 k px at 160–331 pt lateral.
  - They are the same in base and grow (27.0 fit: 34 frames for both).
  - Cause: in landscape the short screen brings the buttons into the tracker's [−80, +6] pt window. It is a tracker limit,
    not the indicator.
- **`dg2` (C3) on 27.0: a real 0.58 step.** A recorded consecutive frame precedes it (5 ms gap), so it is not a recorder
  artefact. That is one more reason, beside the platform-view placeholders, why C3 is rejected.
- **Not run here** (they need code that is not in this spike):
  - `fit-rest-stretch-width-hold-grow` and `fixed-rest-stretch-width-hold-text`: these need i15b's box and slot reader;
  - `aspect-rest-stretch-pull-fade`: the fade under grow is measured statically, bit-identical (§2.1);
  - `aspect-rest-stretch-pull-longpull`, and the inset view;
  - the band-indicator scenarios.
  The builder runs them at step 5 (§6).
- **Forced `.fit` under grow** uses the pre-i15b plan change (`fitRest` off while `g > 0`). The D78 box variant (§4.8) is
  step 4's gate.

### 2.4 The mix (`wt2`): the runtime switch between the two cases

**Setup.**

- Scratch `wt2`, variant `mix`. `m` comes from an environment value (`-ZTronSpike28Mix` gives its default).
- The animatable data of the five consumers is (`o′`, `m`). The effect takes `g_s`, the slot and the 15 frame take `g_l`,
  the clip is path-aware (§4.6), and the fade weight uses `R = layoutHeight − g_l`.
- The demo switches `m` 0 → 1, 5 s after launch, during a 60 pt hold, either in `.linear(duration: 4)` or unanimated
  (`-ZTronSpike28MixTo 1 -ZTronSpike28MixDelay 5 -ZTronSpike28MixDur 4|0`).
- Fixed 240 pt header, text, 3 lanes, lossless PNG.
  - `mixseq.sh` takes back-to-back shots, 0.5–0.8 s apart.
  - `mixan.py` reads the red rows at x = 40 px, the first green row (the content) and the black text box.
  - `edges.py` gives the stems.
- Shots: `s8/i28-stretch-blur/shots/m2` (static), `m3` (animated), `m4` (unanimated).

**Static `m`, held 60 pt (`s` = 1.25).**

| m | 27.0 rows / seam | forced rows / seam | 17.5 rows / seam | text box (mixan; edges.py) | stems vs rest (3 lanes) |
|---|---|---|---|---|---|
| D69 base | 186–1085 / 0 | 186–1085 / 0 | 177–1076 / 0 | 669 × 65; 675 × 72 | ×1.49–1.52 |
| 0 | **pixel-identical to base** (rows ≥ 150 px: 0 px differ) | identical | identical | same | same |
| 0.5 | 186–1085 / 0 | 186–1085 / 0 | 177–1076 / 0 | 595 × 58; 601 × 65 (×1.111 = `s_eff`) | ×1.33–1.40 (the magnified share) |
| 1 | 186–1085 / 0 | 186–1085 / 0 | 177–1076 / 0 | 535 × 52; **541 × 59 = rest** | **×1.00** |

**Animated switch** (4 s linear, held 60 pt, 18 shots per lane).

- The header's top row and the content's first row stay put on every lane: 186 / 1086 on 27.0 and forced, 177 / 1077 on
  17.5.
- The text box shrinks monotonically and stays centred (x-centre 601.5–602.5 px):
  - 27.0: 669 → 632 → 609 → 583 → 563 → 539 → 535;
  - forced: 669 → 667 → 641 → 619 → 597 → 581 → 561 → 547 → 535;
  - 17.5: 669 → 651 → 629 → 609 → 593 → 577 → 559 → 545 → 535.
- **The bottom row mid-switch.** In 2–3 of the 6–8 mid-switch shots per lane, the header's last pixel row is partly
  uncovered:
  - usually `(191, 0, 64)`, 75 % red over the backdrop;
  - once on 27.0 a whole row, `(0, 0, 255)`;
  - that is a gap of ¼–1 px (≤ ⅓ pt).
- **Why.** The layout height `h + m·g` is fractional during the switch, and the frame is pixel-rounded before the effect
  scales it. At `m` = 0 and 1 the edge is exact.
- **Assessment.** It is the class of D69's own in-motion bias at a non-integer `R` (+0.125 pt, M8b-s7 wave 1), and it is
  within |seam| ≤ 1 pt. R10 (§7) gives the candidate fix.

**Recorded switch at 60 Hz** (1 s linear, held 60 pt; `mixrec.sh` = `simctl io recordVideo` under the seam lock;
`textbox.py --held` = the frames at the held bottom row, from the last frame before the switch to the first at the end
value).

| lane | frames | text box (px) | max step | monotone | header top / bottom rows | seam |
|---|---|---|---|---|---|---|
| 27.0 | 60 | 670 → 536 | 4 px (0.03 of the change) | yes | 186 / 1085, constant | 0 px |
| forced | 61 | 670 → 534 | 4 px (0.03) | yes | 186 / 1085, constant | 0 px |
| 17.5 | 60 | 668 → 536 | 4 px (0.03) | yes | 178 / 1076, constant | 1 px, constant before and through the switch |

- On 17.5 the video is 1178 px wide for a 1179 px screen, and the resample moves the rows by 1 px. The lossless PNGs have
  177 / 1076 and seam 0 (§2.4 static table).
- The h264 box runs 1–2 px wider than the PNG box (669 / 535) because of the codec's edge blur.
- Tool: `textbox.py --from 2 --held`. `--from` skips the launch frames, whose red is another screen.
- **The 27.0 recording's last two frames are stamped at the stop** (7.915 and 7.933 s, 3.6 s after the switch's 59th
  frame). Nothing else on screen changes there (`framediff.py`: changed pixels only in the text box). The recorder writes
  frames on change and flushed the last two at the stop.
- The live framebuffer has no such delay. In the 4 s run, shot `w27-08` (9.90 s) is 539 px, 4 px short of the end, and
  `w27-09` (10.47 s) is 535 px, the end. The end state is on screen within one shot interval of the switch's end.

**Unanimated switch.** A one-frame swap from 669 × 65 to 535 × 52, with no intermediate frame. Rows and seam are unchanged
on all 3 lanes.

**Side edges (R5).**

- At `m` = 1 on 17.5 (393 pt wide, `W·s_l` = 491.25 pt) the outermost pixel columns are 70 % red, `(179, 0, 76)`. The
  derived clip is 0.6 px narrower, 0.1 pt per side: the grown frame's width is pixel-rounded (1473.75 → 1473 px), and the
  ratio derives `W` from it.
- 27.0 (402 pt) is exact, and so is the 15 path, whose frame is the slot's `W`.
- In the first mix build the clip was not path-aware: on the 15 path it cut the sides at `W/s_l`, and no red was left at
  x = 40 px. Hence §4.6.

### 2.5 The 15-path box under grow: a flexible frame's ideal width (probe)

- **Question.** i15b's `.fit` box measures `N(W)` through the ideal query of `.aspectRatio(nil, .fit)`. Under grow the content
  must be laid out at `W·s_l`. Can one chain measure at `W` while laying out at `W·s_l`?
- **Probe.** `s8/i28-stretch-blur/flex/flex.swift`: SwiftUI on macOS 27, the same layout engine (`NSHostingView`), a
  91-character `Text`. Results:

| view | result |
|---|---|
| text, ideal | 596 × 16 (one line) |
| text `.frame(width: 100)` / `150` | 100 × 128 / 150 × 80 |
| text `.frame(minWidth: 0, idealWidth: 100, maxWidth: .infinity)`, ideal query | **100 × 128**: the child is proposed the ideal width |
| the same frame in a 150 pt proposal | frame 150 × 80, text laid out 135 × 80: the child gets the concrete proposal |
| the same under `fixedSize()` (both axes) | 100 × 128 |

- **Conclusion.** A flexible frame with an ideal width answers an ideal query at that width, and passes concrete proposals
  through. i15b's box already relies on this (its outer `idealWidth: W/(1 − q)`). At `q = 0`, which every pull has, that
  ideal width is `W`. So the box can be laid out at `W·s_l` and measure at `W` (§4.8).
- **Not yet measured.** The probe is macOS. The forced lanes (17.5, 27.0) are the build gate (step 4, after i15b lands),
  and real iOS 15.0 is the M1 check (§9).

## 3. Decision (D76 as ruled; no new D-number)

### 3.1 What D76 is in this batch

- `withScalingHeader(…, stretchContent: ZTronHeaderStretchContent = .keepTextMagnified, …)`:
  - `.keepTextMagnified` (the default, the user's name) keeps D69's rendering, pixel for pixel (§2.4);
  - `.keepTextSize` (proposed name) grows the header by layout.
- One mechanism serves both cases: the laid-out share `m` (0 or 1). It is animatable, so an animated option change is a
  seamless morph.
- The crisp `.keepTextMagnified` is M8b-s9. This batch only leaves its seam: the effect acts on `g_s` alone (§4.12).
- **Numbering.** Everything here is D76's implementation. If the architect wants the mix recorded on its own, take the next
  free number after D77 (i29) and D78 (i15b), and re-check main and `git log --all`.

### 3.2 What `.keepTextSize` keeps from D69

| D69 property | `.keepTextSize` |
|---|---|
| The user's aspect-fit image (maxWidth .infinity) grows from its top centre, bottom on the content's start | Same pixels on 3 lanes (§2.1). It grows because it is proposed `W·s` wide. The pre-D69 relayout proposed `W`, so the image stayed `W × W/r`. |
| No content body or header builder per frame (S4) | Counters unchanged (§2.1). Per frame the header stack is laid out, as in `.compress` today. Header bodies never run. |
| Bit-stable live input across the unanimated commit | The same `HeaderLiveInput`. 16+: `s` from the pass's own `h_L`, as the effect took it from its size. 15: the aspect pad `g·r/2` does not depend on `W`. |
| Seamless rotation / resize during a hold | The grown size is affine in `W` for `.aspectRatio` (`W + g·r`, `W/r + g`) and `.fixed` (`W·s`, `h + g`), so SwiftUI's interpolation of the two layouts is exact. Seam lab: §2.2. |
| `background:` fills the drawn rect; the fade stretches with the header | The background and the fade are laid out in the grown frame: same rect, same gradient positions (`start·h·s … h·s`). |
| Refresh hold `H` "scales" the header by `(R + H)/R`; indicator over the band | The header is laid out `H` taller. The band `[top0 + R, top0 + R + g]` and every indicator rule are unchanged. |

### 3.3 What `.keepTextSize` changes (visible; the doc comments say it)

- **Fixed-size content keeps its size while pulled.** This covers text, SF Symbols, controls, padding and fixed frames.
  - Grow is the convention of UIKit stretchy headers and of Exyte, the SPEC's reference: the image grows, the labels do not.
  - A title that should grow is one reader away, and it stays crisp:
    `ZTronHeaderGeometryReader(header, of: \.height) { h in Text(…).font(.system(size: 17 + 0.1 * h)) }`.
- **Width-following text re-wraps.** A text whose width follows the header's width, such as a multi-line paragraph, is
  proposed `W·s` while pulled and can re-wrap.
  - To keep the line breaks, give it the resting width from the same reader:
    `ZTronHeaderGeometryReader(header, of: \.width) { w in Text(…).frame(width: w − 32) }`.
- **Hit testing and accessibility.** Header buttons keep their size and move with the layout. Their frames are natural; D69
  scales them.

### 3.4 The runtime switch

- **What moves and what does not.** Changing `stretchContent:` while pulled (a refresh hold, or `.headerFollows`'s rest
  stretch) changes `m` between 0 and 1:
  - The drawn outer frame stays `W·s × (h + g)`, so the header's edge and the content's top do not move.
  - The image keeps its drawn size.
  - Fixed-size content changes from magnified (`s`) to its point size (1) through `s_eff = (h + g)/(h + m·g)`. This is
    monotone in `m`.
  - Measured on 3 lanes (§2.4).
- **Animated** (`withAnimation { option = … }`, or `.animation(_:value:)`): SwiftUI interpolates `m` in the same transaction
  in all five consumers (layout, 15 frame, effect, clip, fade).
- **Unanimated:** the new look lands in one frame. This follows SwiftUI's convention: a state change animates only in an
  animated transaction. It is D65's precedent for `scalingHeaderPullBehavior(_:)`.
- **At rest** (`g = 0`) both cases draw the same pixels, so a switch is invisible.

### 3.5 Rejected for a crisp magnified look (the default's crisp path, now M8b-s9's)

- **C3 (`drawingGroup` around the scale, bounds extended).** Crisp and magnified, but:
  - RenderBox cannot draw platform-backed views: `TextField`, `Toggle`, `ProgressView`, `Map` and any `UIViewRepresentable`
    render as ⊘ placeholders, at rest too.
  - The drawing group would have to be permanent: a conditional one changes the content's identity and resets its `@State`.
  - RenderBox draws materials without their backdrop, and isolates the header's blend modes on 17+, which conflicts with i29.
  - D74 refuses trading native behaviour for a look.
- **A1 / A2 (group changes) and B1–B3 (`displayScale`).** No effect: the contents scale stays 3.
- **C1 (`drawingGroup` inside the scale).** Its texture is scaled, so it blurs.
- **C2 (`drawingGroup` at the layout frame).** The band below is not drawn: a 60 pt hole, a seam.
- **The pre-D69 relayout `(W, R + g)`.** The user's fit image does not grow, which is what D69 was for.
- **UIKit / introspection** (raising `contentsScale` on the header's drawn layers). It is evaluated by `d76-magnified-eval`
  for the default case and, under PENDING, not built in this batch.

## 4. Design

### 4.1 Public API (`HeaderTypes.swift`, `ScalingHeaderAPI.swift`, `HeaderSpec.swift`)

```swift
/// What a `pull: .stretch` header's content does while a pull past the top grows the header (D76). In both cases the
/// header's frame grows by the pull with its bottom edge on the content's top, its sides are cut at its own width, and an
/// aspect-fit image grows from its top centre; they differ in the content's fixed-size parts (text, symbols, controls,
/// padding, fixed frames). `pull: .preserve` and a banner (no vertical axis) ignore it.
public enum ZTronHeaderStretchContent: Hashable, Sendable {
    /// The default: the whole header is magnified with the pull, `(R + g) / R` times from its top centre (`R` its resting
    /// height, `g` the pull), its text, symbols and controls included, as if the resting header were zoomed in.
    case keepTextMagnified
    /// The header is laid out larger with the pull, `(R + g) / R` times its resting width and height, from its top
    /// centre: text, symbols, controls and fixed frames keep their point size, while an aspect-fit image (and anything else
    /// that follows the size it is offered) grows as with `.keepTextMagnified`. Text whose width follows the header's width
    /// can re-wrap while pulled; give it the resting width with `ZTronHeaderGeometryReader(…, of: \.width)`.
    case keepTextSize
}
```

- **Signature.**
  `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:stretchContent:header:)`.
  `stretchContent:` comes right after D75's `fittingContent:`.
- **Parameter doc.**

  > "`stretchContent`: with `pull: .stretch`, what the content does while a pull grows the header:
  > `.keepTextMagnified` (the default) magnifies the whole header; `.keepTextSize` lays it out larger, so text and controls
  > keep their size and an aspect-fit image still grows. A change while the header is pulled morphs between the two inside
  > the same frame when animated (`withAnimation`), and lands in one frame otherwise."
- **Deprecated overload.** The `scalingBehavior:` overload is unchanged. It forwards the default.
- **No member and no environment twin.** The ruling says a parameter.
- **`HeaderSpec.stretchContent`.**
  - It is render-only: not in `HeaderSizing`, so a change runs no `headerSpecChanged()` and leaves the metrics alone.
  - `HeaderHost` passes it to `HeaderFrameModifier(state:size:overflow:fade:stretchContent:)`.
  - A change runs the host body once (`header.builder` +1), as a `fade:` change does today. That is a cold app change,
    allowed by S4.

### 4.2 Live input and animation (`HeaderMath.swift`, `HeaderFrameModifier.swift`)

- **`HeaderLiveInput.layoutShare: CGFloat`** (`m`) is set in `HeaderFrameModifier.wake()`: 0 for `.keepTextMagnified`, 1 for
  `.keepTextSize`. `geometry` and `at(offset:)` copy it (they copy `self`).
- **Derived values**, exact at the ends:
  - `layoutStretch` = `m == 0 ? 0 : (m == 1 ? g : m·g)`;
  - `scaleStretch` = `stretch − layoutStretch`, which is exactly `g` at `m = 0`.
- **Animatable data.** These five types change their animatable data to `AnimatablePair<CGFloat, CGFloat>` = (`o′`, `m`):
  - `HeaderSlotLayout`, `HeaderFallbackFrame`, `HeaderStretchEffect`, `HeaderStretchClip` and `HeaderFadeOverlay`;
  - `set` is `live = live.at(offset: first); live.layoutShare = second`;
  - `HeaderTranslation` keeps `o′`.
  - Spiked in `wt2` exactly like this (§2.4).
- **D62.** `m` is exactly 0 or 1 except inside an app-animated switch. The unanimated resize commit never changes it.
- **Where `m` is set.** The leaf sets `m` from a stored property: in a `@ViewBuilder` body it must be a `let` from a helper
  (`let live = mixed(wake())`), not a statement. The spike's first build failed on that.

### 4.3 Math (`HeaderMath`, pure, tested)

- `stretchScale(layoutHeight:stretch:)`: unchanged.
- **New:** `grownSize(width:layoutHeight:stretch:) -> CGSize` returns `(W·s_l, h·s_l)`. It returns exactly `(W, h)` when
  `s_l == 1`.
- **New:** `stretchClip(in rect:, layoutStretch g_l:, scaleStretch g_s:, grownFrame: Bool) -> CGRect`.
  - **x / width, `grownFrame` (16+).** When `g_l > 0` and `rect.height > g_l`, the clip is the centred
    `W = rect.width · (rect.height − g_l) / rect.height`.
  - **x / width, otherwise.** `rect.minX` / `rect.width`. The 15 frame is already the slot's `W` (§4.6).
  - **Height.** `rect.height · stretchScale(rect.height, g_s)`.
  - **At `g_l = 0`** this is D69's `HeaderStretchClip.rect` exactly. At `g_s = 0` it is the grown clip.
  - **Exact under interpolation.** For `.aspectRatio` and `.fixed`, any linear interpolation of the frame keeps the clip
    exact: `(W(t) + g·r)·(W(t)/r)/(W(t)/r + g) = W(t)`.
- **New:** `grownSidePad(width:layoutHeight:stretch:)` = `(s_l − 1)·W/2`. For an unlimited `.aspectRatio(r)` it is
  `g_l·r/2`, which does not depend on `W`.

### 4.4 16+ path: `HeaderSlotLayout.placeSubviews`

- **Placement.** `let h = height(at:…)` as today, then `place(at: (midX, y), anchor: .top, proposal:
  grownSize(width: bounds.width, layoutHeight: h, stretch: live.layoutStretch))`.
- **Measurement.** `sizeThatFits` and the `.fit` measurement (`first.sizeThatFits(width: w, height: nil)`) are unchanged:
  `R` is always measured at the slot width.
- **Filling the proposal.** `HeaderHost`'s `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` makes the
  stack fill the grown proposal, so the effect and the clip see `(W·s_l, h + g_l)`.

### 4.5 Effect: `HeaderStretchEffect` kept (D69, `.keepTextMagnified`)

- `effectValue(size:)` = `transform(size: size, stretch: live.scaleStretch)`.
- `size` is the layout frame, so `s_eff = (h + g_l + g_s)/(h + g_l) = (h + g)/(h + g_l)`.
- It is the identity for `.keepTextSize` (`g_s = 0`) and D69 for `.keepTextMagnified`.
- On the 15 path the frame is `W × (h + g_l)`, with the content overflowing it by the side padding. Scaling about that
  frame's top centre gives the same drawn `W·s` (measured: forced = 27.0, §2.4).

### 4.6 Clip: `HeaderStretchClip` (path-aware)

- `path(in:)` = `Path(HeaderMath.stretchClip(in: rect, layoutStretch: live.layoutStretch, scaleStretch: live.scaleStretch,
  grownFrame: grown))`.
- `grown` is a stored `Bool` set by `chrome(…)`:
  - `true` on 16+, where the chrome sees the grown frame `W·s_l`;
  - `false` on 15 / forced, where `HeaderFallbackFrame`'s negative side padding keeps the chrome's frame at the slot's `W`.
- Measured: without it, the 15 path was cut at `W/s_l` (§2.4).
- It is still a `Shape` (`Path(rect)`): no mask layer, no offscreen pass (`offscreenOffenders`).
- It still comes before `HeaderLayerGroup`.

### 4.7 Fade: `HeaderFadeOverlay` / `HeaderFadeGradient`

- **The fix.** The GeometryReader hands the gradient leaf `layoutHeight: max(0, g.size.height − live.layoutStretch)`, the
  resting `R`. Today it hands `g.size.height`.
- **Why it is stable.** During a pull at a fixed width that value is constant: `(h + g_l) − g_l`. Its Animatable data
  therefore does not chase a per-frame height (R3).
- **What does not change.** The gradient's unit points span the grown frame, which equals D69's scaled gradient. At `m = 0`
  the value is today's.

### 4.8 15 path (and forced): on i15b's slot reader and `.fit` box (D78)

i15b lands first, and step 4 rebases on it. `HeaderFallbackPlan(live, slot:)` reads `g_l = live.layoutStretch` and
`W = slot.width`. With no slot, `W` is the committed metrics width.

**Non-`.fit` sizes** (`.fixed`, `.aspectRatio`, a limited `R`). Today's minimum-height floor stays.

- `minHeight = maxHeight = h + g_l`, where `h` is i15b's `liveHeight(width: W, …)`.
- `sidePad = grownSidePad(width: W, layoutHeight: h, stretch: g_l)`, applied as `.padding(.horizontal, −sidePad)` outside
  the chain, before the final `fixedSize(vertical:)`.
- For an unlimited `.aspectRatio` this is `g_l·r/2`, which does not depend on `W`. It is exact through a rotation and an
  app-animated width change.

**`.fit` while pulled** (`g_l > 0`, which implies `q = 0`). i15b's box, with these parameters:

| parameter | at rest / in the band (i15b) | pulled, grow share `g_l` |
|---|---|---|
| side padding (outside the chain) | 0 | `−(s_l − 1)·W/2`: the box is proposed `W·s_l` |
| inner `frame(width:)` | `W` | `nil` (the outer flexible frame's ideal width is `W/(1 − q) = W`) |
| `innerPad` / `outerPad` | `−m′` / `m′` | 0 / 0 |
| box floor / limit | `ε` / `L − m′` | `m′` / `s_l·L` (∞ when unlimited) |
| report | `box.height/(1 − q) + m′` | `box.height / s_l` |

- **The ideal query** gives the ratio `W : clamp(N(W), m′, s_l·L)`, measured at `W` (§2.5).
- **The layout** fits that ratio to `W·s_l`, and the floor and the limit clamp it to `[m′, s_l·L]`. The box is
  `W·s_l × s_l·clamp(N, m′, L) = W·s_l × s_l·R` in all four regimes:
  - `N < m′`;
  - `m′ ≤ N ≤ L`;
  - `L < N ≤ s_l·L`;
  - `N > s_l·L`.
- **The report** is `clamp(N, m′, L) = R` in all four regimes. A header content change during a pull or a refresh hold is
  measured in layout, as in the band. Its adoption follows i15b's in-band path.
- **Continuity.** At `g_l → 0` the pulled parameters give i15b's rest layout: `clamp(N − m′, ε, L − m′) + m′` equals
  `clamp(N, m′, L)` up to `ε` = 10⁻⁹.
- **Mixed `m`.** For `0 < m < 1` (an animated switch) the same holds with `g_l = m·g`, and D69's effect magnifies `g_s`.
- **`.keepTextMagnified`** (`g_l = 0`) uses i15b's plan exactly: D69 + D78.
- **`HeaderMeasuringPass`.** After i15b, the pass runs at launch (`g = 0`) and on a Dynamic Type change. For a Dynamic Type
  change during a pull with `g_l > 0`, it applies `.frame(width: W)` while the pass runs, so it measures at `W`. It is
  `nil` otherwise. If i15b's box takes over Dynamic Type, drop this.

### 4.9 Background, readers, hit testing

- **`HeaderBackgroundView`.** It is inside the framed stack, so it is laid out at `(W·s_l, h + g_l)` and magnified by
  `s_eff`. The drawn rect is identical in both cases.
- **`.ambientBlur`.** Its blur radius is in layout points. Under `.keepTextSize` it is not magnified, so the glow is
  slightly sharper than `.keepTextMagnified`'s.
- **`ZTronHeaderGeometry`.** Unchanged: `height` is `R − c + g`, `stretch` is `g`. A reader inside the header is magnified
  with `.keepTextMagnified` and not with `.keepTextSize`.
- **Hit testing and accessibility frames.** Natural under `.keepTextSize`; D69 scales them under `.keepTextMagnified`.

### 4.10 Unchanged

- `ContentTransform` and `GroupLatch`: S7 is untouched.
- `RefreshIndicators`: the band geometry is the same.
- `HeaderLayerGroup`, which i29 owns.
- `HeaderTranslation`: a pull has `p = 0`.
- The content's proposal, inset and top.
- The `ZTronHeaderGeometry` values.

### 4.11 iOS availability

- 16+ uses the existing `usesLayoutProtocol` / `#available(iOS 16, *)` branch.
- 15 uses `padding`, `frame` and `aspectRatio`, which exist since iOS 13.
- `AnimatablePair` is iOS 13.
- No new `if #available`. The forced lane has the same API and pixels (§2.1, §2.4).

### 4.12 S4 / S7 and the seam left for M8b-s9

- **S4.** No content or header body runs per frame (counters, §2.1). Layout is not a body run, and `.compress` already lays
  the header out per frame. An option change is a cold app change: one host body run.
- **S7.** Content transform, inset and `top0` are unchanged. The rotation-in-hold scenarios are in §2.2 and §6.
- **M8b-s9.** The crisp `.keepTextMagnified` replaces or augments the effect for `g_s` alone, at `HeaderStretchEffect` or
  beside it. The API, the mix and the clip stay as they are.
  - The crisp path must also cover `0 < m < 1`, the switch's frames. At `m` = 0.5 the magnified share blurs ×1.33–1.40
    (§2.4).

## 5. Build steps (each one a green commit; library code by the builder, not this designer)

1. **Math.**
   - Add `HeaderMath.grownSize` / `stretchClip` / `grownSidePad` and pure unit tests in `HeaderStretchScaleTests`:
     - `stretchClip(layoutStretch: 0)` bit-equal to D69's `HeaderStretchClip.rect`;
     - the grown clip on both frames, and under the affine interpolation;
     - the aspect W-free pad;
     - non-finite guards.
   - Run `scripts/test.sh -only-testing:ZTronScrollViewTests/HeaderStretchScaleTests` on 27.0 and 17.5. Commit.
2. **API and plumbing, `.keepTextMagnified` only.**
   - The enum and its docs, `stretchContent:` after `fittingContent:` (after D75's step 1; before it, after `overflow:`),
     `HeaderSpec.stretchContent`, `HeaderHost` → `HeaderFrameModifier`, `HeaderLiveInput.layoutShare`, and the five
     `AnimatablePair`s.
   - The effect, the path-aware clip and the fade read the shares.
   - `.keepTextSize` maps to `m = 1`, but the slot / 15 frame still ignore `g_l` in this step: the parameter is internal until
     step 3 (`@_spi` or not yet public) so that no public state is half-built.
   - All D69 tests are unchanged and green, with bit equality at `m = 0`.
   - New `theDefaultIsD69BitForBit`: hosted, the layer frames and the drawn rect under a 60 pt hold, against a reference
     captured before the change.
   - Suites: `HeaderStretchScaleTests`, `HeaderFadeHostedTests`, `HeaderLayoutFrameTests`, `HeaderReviewD16Tests` on 27.0 +
     17.5. Commit.
3. **16+ `.keepTextSize`.** The `HeaderSlotLayout` proposal. The parameter becomes public.
   - The `.keepTextSize` arms of:
     - `aPullIsARenderTimeScaleOfTheRestingLayout`: the reader box `(402·s, R + g)`, the text marker keeps its size;
     - `aStretchHoldKeepsTheScaleAcrossAnAnimatedWidthChange`;
     - `aStretchHoldIsBitStableAcrossTheUnanimatedCommit`;
     - `theUsersAspectFitImageGrowsWithThePull`.
   - New `aMixIsTheSameDrawnFrame`: static `m` ∈ {0, 0.5, 1}, the drawn rect and the clip are equal to ½ pt.
   - New `anAnimatedSwitchMorphsInsideTheFrame`: a `withAnimation` switch during a hold; sampled frames; outer rect constant;
     the marker's height monotone.
   - Same suites as step 2. Commit.
4. **15 `.keepTextSize`.** This needs i15b's D78 on the branch.
   - The `HeaderFallbackPlan` pulled parameters (§4.8): non-`.fit` pad and height; the `.fit` box's pulled parameters and
     report.
   - The `HeaderMeasuringPass` width guard.
   - The fallback arms of the step-3 tests, plus:
     - `aFitHeaderPulledMeasuresAtTheSlotWidth`: `.fallback`; the reported `R` equals the natural height at `W` while held.
       All four regimes, via `.capped` and `min`.
     - `aFitContentChangeDuringAHoldIsMeasuredInLayout`.
   - Same suites, plus `HeaderSlideBehindTests` and i15b's slot tests. Commit.
5. **Demo + seam lab.**
   - Port the scratch lab flags:
     - `-ZTronSeamHoldHeight`, `-ZTronSeamHoldProbe 0`, `-ZTronSeamTextLong`, `-ZTronSeamHeaderExtra field,toggle,spinner`;
     - `-ZTronSeamStretchContent magnified|size`;
     - `-ZTronSeamStretchSwitch <delay>,<duration>`, from the spike's `-ZTronSpike28MixTo/Delay/Dur`: an animated switch
       during the hold; duration 0 = unanimated.
   - Ports to `scripts/seam/`:
     - `edges.py`, with a threshold mode;
     - the `baseline.sh` extras `text`, `hh<pt>`, `long`, `extra<list>`, `ksize`, `switch<d>`;
     - `shot.sh` and `mixseq.sh`, lossless capture and sequences;
     - `mixan.py`, the rows, the seam and the text box per PNG;
     - `textbox.py` (`--from`, `--held`), the per-frame text box, for the switch;
     - `framediff.py`, what changed between recorded frames (a late frame = the recorder's stop flush);
     - new, not written in this spike: `rulerx.py`, the per-frame x of the `ruler` marks (R2's gate).
   - Demo: a `stretchContent` picker on the header demo screen.
   - `HeaderUITests`:
     - `testAppBannerPullGrowsTheImage`: both cases;
     - new `testKeepTextSizeKeepsHeaderTextCrisp`: a lossless `XCUIScreen` PNG held at 60 pt, edge ratio ≤ 1.10, or the
       seam-lab check if XCUI capture is lossy on a lane;
     - new `testStretchContentSwitchKeepsTheFrame`;
     - new `testStretchContentSwitchDuringADrag` (R8).
   - Run the Header demo UI suite on 3 lanes under the UI lock. Commit.
6. **Docs.**
   - SPEC S10:
     - the D69 paragraph becomes D76: the two cases, the mix, the switch;
     - item 28 is fixed for `.keepTextSize`, and the crisp `.keepTextMagnified` is in M8b-s9;
     - the API lines ~479, 527, 561 and the "Header behaviors from the same live input" bullet.
   - Orchestration: D76 as built. Item 28: the grow case is fixed; the `.keepTextMagnified` crisp path is in M8b-s9.
   - Handoff. Commit.

## 6. Acceptance

- **Crispness** (lossless PNG on every lane: 27.0, 17.5, forced).
  - `text` held at 60 pt and 120 pt, plus an animated 120 pt pull.
  - `.keepTextSize`: the `edges.py` stem and "all" ratios against rest are ≤ 1.10 in both directions (measured 1.00). The
    text box is the rest size (541 × 59 px).
  - `.keepTextMagnified`: pixel-identical to the D69 reference (rows ≥ 150 px). The blur is unchanged; removing it is the
    M8b-s9 gate, not this batch's.
- **The user's setup** (`appbanner`, `refit`, held at 60 pt and a finger pull).
  - Both cases: the image's red rows equal D69's, ±⅓ pt. That is 116–402 pt on 27.0 / forced and 59–340 pt on 17.5.
  - `HeaderUITests.testAppBannerPullGrowsTheImage` stays green on 3 lanes for both cases: bottom `R + g`, width `s·W` within
    0.5 pt.
- **Seam lab, per lane and per case.** Criteria: |seam| ≤ 1 pt, lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change,
  and the refresh indicator 0 frames over the content.
  - Scenarios:
    - `fixed-rest-stretch-pull-text`
    - `aspect-rest-stretch-rotate-uncapped-hold`
    - `aspect-rest-stretch-width-hold`
    - `aspect-rest-stretch-pull-refit-appbanner`
    - `fixed-rest-stretch-rotate-hold-text`
    - `fit-rest-stretch-rotate-hold-text`
    - `fit-rest-stretch-width-hold-grow`: the content changes during the hold; forced is the gate
    - `fixed-rest-stretch-width-hold-text`: needs i15b
    - `aspect-rest-stretch-pull-fade`: the fade under grow, read with the fade tracker
    - `aspect-rest-stretch-pull-longpull`
    - an inset view, `-ZTronSeamInset 40`: R5
  - **Switch scenarios.**
    - `fixed-rest-stretch-hold-text-switch4`: animated, 4 s. The spike passed on 3 lanes (§2.4). Seam and lateral within
      the thresholds, `hJ` / `cJ` = 0 (the frame does not move), and `textbox.py` monotone with no step ≥ 0.5 of the
      change.
    - `…-switch1`: animated 1 s, recorded at 60 Hz. `textbox.py --held`: monotone, max step ≤ 0.05 of the change
      (measured 0.03 on 27.0 and forced, §2.4), the header's rows constant, seam 0. A late frame after a long gap is the
      recorder's stop flush (§2.4): confirm such a frame with a lossless shot, not with the video.
    - `…-switch0`: unanimated. A one-frame change of the text only; the frame is still constant.
  - The D69 baselines of these scenarios (b2 wave 1) are the reference: no scenario may get worse by > 0.1 pt.
- **Unit tests** (`scripts/test.sh -only-testing:ZTronScrollViewTests/<Suite>`, 27.0 + 17.5):
  - `HeaderStretchScaleTests`: both cases, both `OSPath`s, all three sizes, the mix.
  - `HeaderFadeHostedTests`: the pull weight with `R = layoutHeight − g_l`.
  - `HeaderLayoutFrameTests`, `HeaderReviewD16Tests`, `HeaderSlideBehindTests`, i15b's slot tests.
  - The full unit suite at the end of the milestone.
- **UI tests.** The demo `HeaderUITests` + `RefreshUITests` + the Proof suite on 3 lanes: the targeted suites, then the full
  suite at milestone end.
- **Render counters.**
  - Through a hold, an animated pull and a finger pull, `content.body`, `header.builder` and `header.content` stay at their
    install value. `header.frame` increments per step.
  - An option switch adds exactly 1 to `header.builder`.
- **Platform views** (`-ZTronSeamHeaderExtra field,toggle,spinner`, held at 60 pt, 3 lanes): no yellow ⊘ pixels in either
  case. Under `.keepTextSize` the controls keep their size.

## 7. Risks

- **R1. Re-wrap (visible, `.keepTextSize` only).** A width-following multi-line text re-wraps while pulled: a word moves
  between lines in one frame. This is inherent in growing a fit image without magnifying everything.
  - Mitigation: the doc comment and the reader recipe (§3.3), plus a demo case.
  - The user can keep `.keepTextMagnified` for such a header.
- **R2. A measurement while grown (15 path).** i15b's box measures in layout, so the old premise ("iOS 15 cannot measure
  without laying out") applies only to the launch and Dynamic Type pass (§4.8).
  - Gate: forced `fit-rest-stretch-rotate-hold-text` and `fit-rest-stretch-rotate-hold-ruler` (ruler x per frame,
    `rulerx.py`, a new tracker the builder writes at step 5).
- **R3. Fade weight in a transaction-driven pull.** `R = layoutHeight − g_l` is constant during a pull at a fixed width, so
  the gradient's Animatable data has nothing to chase.
  - Gate: `aspect-rest-stretch-pull-fade` with the fade tracker. The crossfade must be monotone with no step.
- **R4. Layout cost.** The header is laid out per frame during a pull, the cost class of `.compress`. There is no new
  per-frame body.
  - Check on the M1 15.0 lane: no dropped frames in a hold with a complex header (the demo profile header).
- **R5. Side edges on 16+.** The clip derives `W` from the grown rect, and SwiftUI pixel-rounds that rect's width.
  - Measured: 0.1 pt per side on 17.5's 393 pt at `s_l` 1.25. The outermost columns are 70 % covered.
  - None on 27.0's 402 pt or on the 15 path (§2.4).
  - Within lateral ≤ 1 pt. Check an inset view (`-ZTronSeamInset 40`).
  - If the user's "no misalignment" bar wants it exact: snap the side inset to the pixel grid, with the leaf's
    `displayScale` handed to the clip. The trade is ⅓ pt steps of the side edges during an animated resize. Builder's
    call, measured on the inset scenario.
- **R6. A `GeometryReader` inside the user's header sees the grown size per frame** (`.keepTextSize`). Its closure re-runs
  per frame, as during collapse. That is the user's own reader, allowed by S4 ("reader content runs").
- **R7. The 15 `.fit` box under grow** (§4.8) rests on the flexible frame's ideal-width semantics. That is measured on macOS
  (§2.5), and i15b's box already relies on it.
  - Gates: forced `fit-rest-stretch-width-hold-grow`, `fit-…-capped` in all four regimes (unit), and the real 15.0 lane.
  - If a gate fails, do not fall back to "adopt at release": that would be a 15 vs 16+ difference. Stop and consult.
- **R8. A switch inside a finger drag.** The app calls `withAnimation { option = … }` in the same update as a pan step. The
  pair (`o′`, `m`) is one animatable value, so the pan step's `o′` change could be animated with the switch, and the header
  would lag the content for the duration.
  - On 15–16, a later unanimated `o′` change may cut the `m` animation short. iOS 17+ animations are additive.
  - Gate: `testStretchContentSwitchDuringADrag` (UI, all lanes): seam ≤ 1 pt and no `m` jump.
  - Mitigation if it fails: drive `m` from a library-owned `@State` set in `onChange(of: option)`, in its own transaction.
- **R9. `.headerFollows` (D75) + `.stretch` + the default.** The rest stretch `L` makes `.keepTextMagnified` magnify the
  header at REST by `(h + L)/h`, so it is blurred at rest until M8b-s9. The same mechanism draws it (`g + L` split by `m`).
  - Decided by the user's D76 timing. Tell the architect. `.keepTextSize` is crisp there.
- **R10. Fractional layout heights.** Grow lays the header out at `h + g_l`, which is fractional per frame in an animated
  pull and in a switch. SwiftUI pixel-rounds the frame. D69 instead draws the bottom edge with a CA transform.
  - Measured: ≤ ⅓ pt at the bottom edge mid-switch (§2.4). In the seam lab every grow seam is ≤ 0.50 pt, at or under
    D69's. The one 0.33 pt pull seam on 17.5 did not repeat: `s175r` gives 0.17, the same as base (§2.3).
  - All within |seam| ≤ 1 pt. It is the class of D69's +0.125 pt in-motion bias at a non-integer `R`.
  - Not a fix: magnifying the sub-pixel remainder with the effect, as D69 does. A scale of ×1.001 resamples the text bitmap
    and brings the blur back.
  - Candidate fix, if a scenario exceeds its baseline: round the laid-out height `h + g_l` the way `ContentTransform` snaps
    the content's top (D62's comment: "the content's snapped top"), in the slot (16+) and the plan (15). The two edges then
    land on the same pixel row.
  - Measure it against the D69 baselines before adopting it, and keep the unrounded value in the live input for D62's bit
    stability.

## 8. Interactions with the other M8b-s8 designers (shared files)

- **i15b-15path-resize (D78: `HeaderSlotReader`, the `.fit` box, `HeaderFallbackPlan(live, slot:)`).**
  - Land i15b first. Step 4 here rebases on it: `W = slot.width`, the box's pulled parameters (§4.8), and grow outside the
    box via the side padding, which is i15b's own recommendation.
  - The box removes the old R2 / R7 "measure at release" corners.
  - Both edit the `HeaderFallbackPlan` init: mechanical conflicts.
- **d75-short-content (D75, `fittingContent:`).**
  - `stretchContent:` goes right after `fittingContent:`. Land D75's step 1 first, or place `stretchContent:` after
    `overflow:` and let D75 insert before it.
  - D75's `.stretch` + `.headerFollows` takes `g + L` in the shared `grownSize` / effect split: `g_l = m·(g + L)`,
    `g_s = (1 − m)·(g + L)`.
  - With the default this is a magnified header at rest (R9).
- **i29-blend-slidebehind (D77, `HeaderLayerGroup` / `ContentLayerGroup`).**
  - Nothing here touches the groups.
  - The grown frame is wider than `W` inside the header's group. If i29 changes the 15–16 group, check that the clip still
    cuts the sides (unit `offscreenOffenders` + seam).
- **refresh-27-31-32-33 (`RefreshIndicators`, `HeaderHost`).**
  - No change to the band, the indicators or the `.system` spinner. Both cases keep `[top0 + R, top0 + R + g]`.
  - Rerun `RefreshUITests` + the `hsys` scenarios at step 5.
- **d76-magnified-eval / M8b-s9.**
  - The crisp path attaches to `g_s` (§4.12) and must cover `0 < m < 1`.
  - Its evidence and this design's C1–C3 / B1–B3 agree that no pure-SwiftUI lever works.
- **`ContentTransform` / `GroupLatch`:** not touched.

## 9. Real iOS 15.0 / 16.0 checks (the user's M1 Mac)

- **15.0** (the 15 path natively, not forced):
  - **Crispness.** Lossless `simctl io screenshot` of `text` held at 60 / 120 pt with `.keepTextSize`: stem ratio ≤ 1.10,
    and the text box equals rest.
  - **The flexible-frame probe.** The `flex.swift` cases as a unit test: the ideal query at the ideal width, the layout at
    the proposal. This is the premise of §4.8.
  - **The box.** `fit-rest-stretch-width-hold-grow` and a `.capped` `.fit` hold. The header follows its content change
    during the hold, and the report equals `N(W)`.
  - **The switch.** The `mixseq` set of §2.4: the frame is constant, the text box is monotone, the unanimated switch is
    one frame. Also a switch during a finger drag (R8; 15 has no additive animations).
  - **The user's setup.** `appbanner` refit held at 60 pt: the image rows equal forced 27.0, scaled to the device.
  - **Rotation.** `fixed-rest-stretch-rotate-hold-text` and `fit-rest-stretch-rotate-hold-text`: seam ≤ 1 pt, no step. On
    real 15 the rotation is UIKit's.
  - **Platform views.** `-ZTronSeamHeaderExtra field,toggle,spinner` while held: native controls keeping their size.
  - **`.keepTextMagnified` on 15.** Pixel-equal to D69 against a pre-change capture.
- **16.0** (`Layout` path + the `compositingGroup()` header group):
  - The grown subview, wider than `W`, is clipped inside the compositing group: no side bleed in an inset scroll view.
  - The R5 side columns.
  - Seam ≤ 1 pt in `aspect-rest-stretch-rotate-uncapped-hold`, both cases.
  - Text ×1.00, counters through a hold, and the switch scenario.
- **Both:** `HeaderStretchScaleTests` + `HeaderUITests` on the M1 lane, the read-only verification lane.

## 10. User questions (naming only; defaults chosen)

- **Q1. The grow case's name.** Default `.keepTextSize`: it pairs with the user's `.keepTextMagnified`, and says that text
  keeps its point size. Alternatives: `.keepTextPointSize`, `.growLayout`, `.relayout`.
- **Q2. The type and the parameter.** Default `ZTronHeaderStretchContent` / `stretchContent:`. Alternatives:
  `ZTronHeaderStretchRendering` / `stretchRendering:`, `ZTronHeaderStretchMode` / `stretchMode:`.
- **Q3. Placement.** Default: right after D75's `fittingContent:`, as ruled. Alternative: right after `pull:`, which it
  refines.
