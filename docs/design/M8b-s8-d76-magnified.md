# D76 evaluation: a crisp `.keepTextMagnified` (M8b-s8 side evaluation, input to M8b-s9)

> Committed by the M8b-s8 architect (2026-11-03). The two evaluators (`d76:swiftui`, `d76:uikit`, 2026-11-02) were not
> allowed to write report files; their full reports went to the lead as the workflow's structured output. This file
> keeps their own notes (shared `s8/notes.md`, sections `d76:swiftui` and `d76:uikit`) so the repository has the
> evidence; the lead may replace it with the full reports. Build plan and the user's ruling: [M8b-s8-plan.md](M8b-s8-plan.md)
> §7 and Orchestration D76.

## User ruling (2026-11-02, binding for M8b-s8)
`.stretch`'s header content is an enum parameter of `withScalingHeader`, default `.keepTextMagnified` (D69's look exactly),
the other case i28's grow (`.keepTextSize`). M8b-s8 builds the enum, the parameter, the grow case and `.keepTextMagnified`
exactly as today's D69, structured so the crisp path attaches later without an API change, with no UIKit, introspection or
reflection path. The crisp magnification is the follow-up batch M8b-s9.

## Pure SwiftUI (`d76:swiftui`)
- Verdict: no pure-SwiftUI path makes `.keepTextMagnified` crisp under every requirement.
- Only `Text` blurs under D69 (`CGDrawingLayer` / `RBDrawingLayer` bitmaps at `contentsScale` 3, scaled by `s`); SF
  Symbols, `Path`s, rectangle fills and strokes are vector layers and stay crisp.
- Best partial result: the layout grow plus a magnifying `TextRenderer` (`trmagsz`, iOS 18+, `sizeThatFits` × s): crisp
  (× 0.89-1.04), 0 px at rest, S4 clean; but text only (a real header is 10-49 pt off D69) and absent on iOS 15-17.
- An environment font × s: crisp only for `Text` without its own font; it re-runs `@Environment(\.font)` readers every frame
  and restyles controls without their own font at rest.
- Artifacts: `m8b-s8-resume/d76-swiftui-spike.patch` (against 72ca7fc, includes the i28 harness),
  `m8b-s8-resume/d76-swiftui-evidence/` (montages, tools, specs), in the shared notes folder.

## Scoped UIKit / Core Animation prototype (`d76:uikit`)
- Mechanism: a scoped Core Animation re-raster of D69's magnified header (`.stretch` + `.keepTextMagnified` while pulled).
  A zero-size `UIViewRepresentable` probe sits as a `.background` inside the magnified stack; the container is the probe's
  nearest clipping ancestor; a drawn layer is one with a delegate, non-`CGImage` contents (or no contents and
  `needsDisplay`) and a non-resize gravity; views from bundles other than `com.apple.SwiftUI*` are skipped (platform views
  stay native). Per drawn layer: `contentsScale = native · s`, nearest filter, a ¼-px `contentsRect` bias only within
  0.05 px of a ½-px tie; restored from per-layer records at rest.
- Hooks: an identity `GeometryEffect` tick (the stretch effect's animatable data), the probe's `layoutSubviews` (Core
  Animation's layout phase, after SwiftUI's render) and KVO on `contentsScale` (SwiftUI resets it to native at animation
  ends, text changes and app resizes, on 27.0 only; re-applied synchronously). No `CADisplayLink`.
- Results (lossless PNGs; 27.0, forced and 17.5 identical): stems exact / native over 12 sizes × 0.94-1.05 in 11 of 12
  (s 1.16: h × 1.29, native reference phase-aligned), means × 1.02 / × 1.00; D69 × 1.49-1.57. 0 px at rest, with the probe
  during holds, and after the restore (extras included); render counters equal to the unpatched build; 0 stale layers;
  platform views, a material backdrop, a blend, an image, a gradient and a shape: 0 px against D69.
- Seam lab (`scripts/seam`, exact vs off, loads < 10): 27.0 preferred, 27.0 forced and 17.5 all PASS; max seam 0.17 pt
  (`.fixed`) / 0.50 pt (`.aspectRatio`), lateral ≤ 0.42 pt, hJ / cJ ≤ 0.26 over pull-text, width-hold hh60, rotate-hold
  hh120, aspect rotate-uncapped-hold, aspect width-hold, appbanner; the off references equal within run noise.
- Hit testing and accessibility (27.0 UI test, exact vs off, preferred + forced): the header `Button` is found with the same
  magnified frame, hittable, and its taps count; a `TextField` exists and is hittable; identical in all four runs.
- Rejected: a child `UIHostingController` with a display-scale trait (no density change, × 1.73 = D69; rest not
  pixel-identical); a fixed density native · 2 (a visible switch at 1-2 pt pulls); the environment's `displayScale`,
  `contents = nil`, self-drawing, an effect-phase-only hook (SwiftUI resets the store in its render).
- Traps: SwiftUI 27.0 creates the header's clip container only while pulled; a layer inserted mid-hold has no contents at
  layout time (the needs-display rule); SwiftUI's image layer has `contentsScale` 1 (record the originals); `-Arg` parsing
  takes the FIRST occurrence.
- Artifacts: `m8b-s8-resume/d76-uikit-prototype.patch` (= `s8/d76-eval/uikit/prototype.patch`).

## For M8b-s9 (architect)
- The crisp path attaches where the magnified share is drawn: `HeaderStretchEffect` (`g_s`, i28 §4.5 / §4.12). It must cover
  the animated switch (`0 < m < 1`) and D75's `.headerFollows` + `.stretch` header, which is magnified at rest by `L`: gate on
  `g_s > 0` (`g + L > 0`), not on "pulled".
- The only route measured crisp is the scoped UIKit / Core Animation prototype above. It needs the user's ruling: UIKit, a
  `UIViewRepresentable` and KVO in the library are S16 exceptions (precedent: the parity-without-appeal ruling, D74).
