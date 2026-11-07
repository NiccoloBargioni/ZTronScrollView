# M8b-s8-s6 handoff · 2026-11-07 · Opus 5.5 · xhigh
Status: done. Builder s6-d76-api-16: D76's `stretchContent:` on the 16+ path (905177c, 90313c2). The default
`.keepTextMagnified` is D69 bit for bit: the hosted layer dumps match the d291afc reference on 27.0 and 17.5, on both paths,
and the seam-lab PNGs match the before build pixel for pixel. `.keepTextSize` grows the header by layout and keeps the text at
its point size (edge ratio 1.000 against rest). A switch between the cases morphs inside the header frame, with no seam or step.
On the 15 path (the non-Layout-protocol path) both cases draw as D69 until s7 (C14): the forced lane shows no difference
between the cases. The i28 seam lab is ported (a35cf4a, fdd6c49).

Changed:
- `ScalingHeader/HeaderTypes.swift`: `public enum ZTronHeaderStretchContent { case keepTextMagnified, keepTextSize }`.
- `ScalingHeader/ScalingHeaderAPI.swift`: `withScalingHeader(…, overflow:, stretchContent: = .keepTextMagnified, header:)`.
  The deprecated overload forwards `.keepTextMagnified`.
- `ScalingHeader/HeaderSpec.swift`: `stretchContent` is render-only and not in `HeaderSizing`, so a change costs
  header.builder +1 and no measuring pass.
- `ScalingHeader/HeaderMath.swift`: `grownSize`, `grownSidePad` and `stretchClip(…grownFrame:displayScale:)`. The path-aware
  clip snaps its side inset to the pixel grid: SwiftUI rounds the grown frame's width (452.25 → 452), which left a 0.11 pt
  gap per side on 27.0 (i28 R5). `HeaderLiveInput.layoutShare` `m` gives `layoutStretch` = m·g and `scaleStretch` = g − m·g.
- `ScalingHeader/HeaderFrameModifier.swift`: wake() sets `m` to 1 only for `.keepTextSize` on the Layout path with a header
  that is not a banner. The slot proposes `grownSize`. The effect scales by `scaleStretch`. The clip is `HeaderStretchClip`
  with `grown` and `displayScale`, and the fade rests at `layoutHeight − g_l`. Five modifiers animate
  `AnimatablePair(o′, m)`: HeaderSlotLayout, HeaderFallbackFrame, HeaderStretchEffect, HeaderStretchClip and
  HeaderFadeOverlay. HeaderTranslation keeps o′, and the D79 pin replaces o′ only.
- `ScalingHeader/HeaderHost.swift`: passes `spec.stretchContent` to the slot reader.
- Tests:
  - `HeaderStretchContentTests` (new):
    - `theDefaultIsD69BitForBit`: path × size, pull 60 and hold 60, compared with the presentation layer trees in
      `HeaderStretchD69Reference.swift`. The reference was generated at d291afc, two identical runs per lane, keyed by OS.
    - `anAnimatedSwitchMorphsInsideTheFrame`: animated and unanimated.
    - `aSwitchDuringAFingerPullKeepsTheSeam` (R8).
  - `HeaderStretchScaleTests`: the `.keepTextSize` arms, the text marker, the D69 reduction of the math at m = 0 (with the
    R5 snap case), and `aMixIsTheSameDrawnFrame`.
  - `ScalingHeaderAPITests`: the default, the forwarding and the carry.
- Lab:
  - `SeamLabScreen` gains these flags: `-ZTronSeamStretchContent`, `-ZTronSeamStretchSwitch d,dur`,
    `-ZTronSeamHoldHeight`, `-ZTronSeamHoldProbe`, `-ZTronSeamTextSize`, `-ZTronSeamTextLong`, `-ZTronSeamHeaderExtra`,
    `-ZTronSeamPullTo` and `-ZTronSeamCounters`.
  - `SeamLabUITests.testHold`.
  - `baseline.sh` keys: `text`, `hh<pt>`, `noprobe`, `long`, `extra<a+b>`, `ksize` and `switch<d>`.
  - New scripts: `edges.py --threshold`, `shot.sh`, `mixseq.sh`, `mixan.py`, `textbox.py` (with `--from`, `--to` and
    `--held`) and `framediff.py`.
- Docs: SPEC S10 now documents the parameter, the enum and the deprecated overload. `docs/design/M8b-s8-d76-magnified.md`
  holds the full evaluation.

Decisions:
- No new D-number. This step builds D76 as ruled. The pixel-snapped clip inset is part of that build: it is needed for the
  ≤ 1 pt seam and lateral gate at non-integer `W·s`.
- `m` animates as part of the five modifiers' `animatableData`, so a switch inside `withAnimation` morphs in one transaction.
  An unanimated switch lands in one frame. The text-box gate passes on 27.0 and 17.5 (table below).
- A banner header (D63 refit app banner) keeps `m = 0`. Its grow would move the banner's own layout. The banner shots are
  identical across the two cases on 27.0 and 17.5.

Measurements (seam lab; before = d291afc + the lab patch (`b27`, `b175`, PNGs `shots-b27`, `shots-b175`, `shots-b27f`),
after = a35cf4a (`a27`, `a175`, `a27f`). Forced = `-ZTronForceAllFallbacks`. Each cell is |seam| pt / lateral pt / largest
60 Hz header step as a fraction of the change. PASS = ≤ 1 / ≤ 1 / < 0.5. Load ≤ 300 at every row's start unless noted.):

| row | 27.0 magnified | 27.0 keepTextSize | 17.5 magnified | 17.5 keepTextSize | 27.0 forced magnified | 27.0 forced keepTextSize |
|---|---|---|---|---|---|---|
| `fixed-rest-stretch-pull-text` | 0.17 / - / 0.08 | 0.17 / - / 0.06 | 0.17 / - / 0.13 | 0.33 / - / 0.10 | 0.33 / - / 0.06 | 0.17 / - / 0.09 |
| `aspect-rest-stretch-rotate-uncapped-hold` | 0.50 / 0.12 / 0.24 | 0.17 / 0.08 / 0.84 → 0.24, 0.25 (re-runs) | 0.50 / 0.10 / 0.26 | 0.17 / 0.14 / 0.25 | 0.50 / 0.12 / 0.24 | 0.50 / 0.12 / 0.25 |
| `aspect-rest-stretch-width-hold` | 0.50 / 0.34 / 0.11 | 0.50 / 0.20 / 0.09 | 0.50 / 0.28 / 0.07 | 0.50 / 0.28 / 0.07 | 0.50 / 0.34 / 0.08 | 0.50 / 0.34 / 0.09 |
| `aspect-rest-stretch-pull-refit-appbanner` | 0.50 / - / 0.14 | 0.50 / - / 0.10 | 0.50 / - / 0.15 | 0.50 / - / 0.06 | 0.50 / - / 0.07 | 0.50 / - / 0.06 |
| `fixed-rest-stretch-rotate-hold-text` | 0.17 / 0.10 / 0.13 | 0.17 / 0.16 / 0.19 | 0.17 / 0.17 / 0.08 | 0.33 / 0.17 / 0.07 | 0.17 / 0.28 / 0.22 | 0.17 / 0.12 / 0.09 |
| `fit-rest-stretch-rotate-hold-text` | 0.50 / 0.12 / 0.23 | 0.33 / 0.11 / 0.24 | 0.50 / 0.09 / 0.71 → 0.26, 0.26 (re-runs) | 0.33 / 0.12 / 0.26 | 0.50 / 0.12 / 0.23 | 0.50 / 0.12 / 0.24 |
| `aspect-rest-stretch-pull-fade` | 0.50 / - / 0.11 | 0.17 / - / 0.15 | 0.50 / - / 0.19 | 0.17 / - / 0.09 | 0.50 / - / 0.04 | 0.50 / - / 0.05 |
| `aspect-rest-stretch-pull-longpull` | 0.50 / - / 0.03 | 0.17 / - / 0.12 | 0.50 / - / 0.14 | 0.17 / - / 0.07 | 0.50 / - / 0.08 | 0.67 / - / 0.02 |
| `fixed-rest-stretch-hold-text-switch4` (from magnified) | 0.17 / - / 0.18 | | 0.50 / - / 0.08 | | 0.17 / - / 0.00 | |
| `…-switch1` / `…-switch0` / `…-ksize-switch1` | 0.17 / 0.17 / 0.17 | | 0.17 / 0.17 / 0.33 | | 0.17 / 0.17 / 0.17 | |
| inset 40 `fixed-rest-stretch-pull-text` (seam = the inset) | 40.33 | 40.33 | 40.33 | 40.33 | 40.33 | 40.33 |
| before d291afc `fixed-rest-stretch-pull-text` | 0.17 / - / 0.03 | | 0.17 / - / 0.16 | | | |

- The two outliers (0.84 and 0.71) come from gaps in the recording, not from drawn jumps. The first is a 0.41 s gap at the
  drag start; the second is a 2.44 s gap with no frames before a rotation, followed by a 3 ms burst. Header and content move
  together in both. Each row re-ran twice and read 0.24 / 0.25 and 0.26 / 0.26.
- `.keepTextSize` vs magnified: the seam is never worse by more than one recording quantum (1/6 pt). Each 0.33 is one
  frame. The 17.5 seam's 1 px row is the boundary pixel blend: at rest it is the same in `b175`.
- Switch text box (`textbox.py --held`, ±2 px h264 noise, step < 0.5 and monotone; for switch1 a step ≤ 0.05).
  The header rows and the seam do not move during any switch.

  | row | 27.0 | 17.5 |
  |---|---|---|
  | switch4 | 669 → 538 px, step 0.03, monotone | 667 → 536, step 0.02, monotone |
  | switch1 | 670 → 536, 60 frames, step 0.03 | 668 → 536, 60 frames, step 0.03 |
  | ksize-switch1 | 536 → 670, step 0.03 | 536 → 668, step 0.03 |
  | switch0 | one frame | one frame |

  - Forced 27.0: the box stays at 670 px and the switch draws nothing (C14).
- PNG shots: after vs before, magnified (rows ≥ 150 px).
  - 27.0 and 17.5: identical for rest, hold60, hold120, anim120, banner60 and long60.
  - extra0 and extra60 differ only in the spinner's phase and the Dynamic Island. 17.5 has no island difference.
  - 27.0 forced: everything differs only in the home indicator's bar (y 2583–2597) and the spinner.
  - Forced: magnified and size are identical apart from the spinner.
  - `.keepTextSize` edges (`edges.py --threshold 1.10` against rest) PASS on 27.0 and 17.5: hold60, hold120 and anim120 have
    ratio 1.000 and box 541×59, the same as rest. Magnified is ×1.50–1.85 (the blur is item 28, built in M8b-s9).
  - long60 has edge ratio 1.04, and its box spans the clip (the long text is clipped by design).
  - No ⊘ placeholder in the extra shots: field, toggle and spinner draw natively.
- S4 counters (lab, during hold and pull): content.body 1, header.content 1 and header.builder 1 in both cases on every lane.
  header.frame (the frame modifier) counts.
- Re-runs of the earlier steps' key scenarios on this build:

  | step | scenario | result | earlier |
  |---|---|---|---|
  | s1 | `rtrig40`, 17.5 (residual / half / ramp / mixed) | 2.0 / 0.67 / 0.32 / 9, then two re-runs: 2.0 / 0.33 / 0.20 / 11 and 2.0 / 0.67 / 0.21 / 16 | 2.0 / 0.67 / 0.19–0.23 / 11–13 |
  | s3 | catch, 17.5, both cases (drop / spinner / seam, frames > 1) | magnified 0.67 / 20 / 0.5, 0; ksize 0.66 / 20 / 0.17, 0 | the same step pattern as s4's after |
  | s2 | `rows5-rowsto10-internal`, 27.0 | 28 / 28 frames, step 0.059, landing 447 / 450 ms | |
  | s4 | `noheader-hold-height04-instant`, forced (`holdgap.py --edge top`) | 57 / 57 in place, 0 missing / over / tint / ghost | |
  | s5 | `fit-half-preserve-width-grow-forced` | 0.50 / - / 0.04 | |

- Fade: no frame tracker for the fade exists. The fade row's seam and steps pass. The fade's resting height is covered by
  `HeaderFadeHostedTests` and by the `restingHeight` math test (`layoutHeight − g_l`).

Open:
- C14: on the 15 path both cases draw as D69 until s7 builds `.keepTextSize` there.
- Item 28 (`.keepTextMagnified` blur) is M8b-s9's raster engine. It is not a finding of this step. The closer records item 28.
- Real iOS 15 / 16 checks pending (the M1 Mac lane):
  - R8 (a switch during a finger pull) on real 16 with the Layout path;
  - the pixel-snapped clip at a 2× display scale;
  - `m = 0` on 15.
- Lab gotcha: 17.5 recordings show the home screen's red before launch and after exit, so `textbox.py --held` needs
  `--from` and `--to` around the app window.

Next:
1. s7: `.keepTextSize` on the 15 path (C14), using the same `m` and the same tests (`theDefaultIsD69BitForBit` already
   covers the 15 path's default).
2. The closer records item 28 and D76's "16+ built" in the batch summary.
3. M8b-s9: D76's crisp `.keepTextMagnified` (the raster engine).

Tests:
- Unit, 27.0 and 17.5: HeaderStretchScaleTests, HeaderStretchContentTests, HeaderFadeHostedTests, HeaderLayoutFrameTests,
  HeaderReviewD16Tests, HeaderMathTests, ScalingHeaderAPITests, DrawnCatchTests, HeaderFallbackSlotTests and
  HeaderSlideBehindTests → 100 / 100 green on each. R8 is green on 27.0 and 17.5.
- Demo UI HeaderUITests: 16 / 16 on 27.0, 17.5 and 27.0 forced.
- Seam lab: 3 lanes × 19 rows plus 3 inset rows, PNG shots on 4 lanes, 5 key scenarios and 6 re-runs.
- Notes: `scratchpad/s8/notes.md` § s6-d76-api-16.
Usage: not measured.
