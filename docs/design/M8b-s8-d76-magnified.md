# D76: a crisp `.keepTextMagnified` (the default of `withScalingHeader(…, stretchContent:)`)

Designer `d76:design`, workflow `d76-magnified-eval`, 2026-11-03. Inputs: the user's D76 ruling (Orchestration D76), the i28
design (`s8/design/i28-stretch-blur.md`, the grow case and the switch), D75 (`s8/design/d75-short-content.md`), the two
spikes of this workflow (`d76:swiftui`, `d76:uikit`, `s8/notes.md`) and this designer's own checks (§3.3). No library code
is built from this document until the user accepts the amendments in §5. No new D-number: this is D76's evaluated design;
the orchestrator records the amendment under the next free number (from main and `git log --all`) when the user accepts it.

**Verdict.** Pure SwiftUI cannot make a magnified header crisp (§3.1). The scoped UIKit raster engine can, and it meets the
requirements on 27.0, 27.0 forced and 17.5 (§3.2, §3.3). Chosen: the hardened engine of §4, behind the amendments of §5.
`blocked` = false; `needsUserAcceptance` = true.

## 1. Summary for the user

1. A `pull: .stretch` header gets a choice, `stretchContent:`, for what its content does while a pull grows it.
2. `.keepTextMagnified` (the default, your name): the whole header zooms in as today, text, symbols, controls and image alike.
3. What changes: its text is redrawn sharp at the zoomed size (edges ×0.89–1.04 of native text; today ×1.49–1.73 blurred),
   held or animating, on iOS 15 to 27; at rest every pixel is exactly as today (0 px difference).
4. `.keepTextSize`: the header is laid out larger instead; text and controls keep their point size, the image still grows.
5. Pure SwiftUI cannot redraw zoomed text sharply (six routes measured). A small UIKit helper redraws only the header's own
   text and controls at the zoomed pixel density while it is zoomed, and puts everything back at rest.
6. UIKit-backed controls in the header (a `TextField`) are redrawn sharp too (×1.03–1.05); only GPU content (a Metal view,
   a map, video) still zooms like an image, as photos do.
7. Cost: about 0.5 ms per frame (1 ms worst) and ~0.2 MB while pulled; nothing at rest, while scrolling or collapsing.
8. Accepting it adds a second narrow UIKit exception to the library rules (SPEC S2 / S16, CLAUDE.md, §5): this header
   only, five named drawing properties only, with the touch observer's 100 % coverage and scope gates.
9. Still to prove when it is built: one of twelve tested sizes is not yet sharp enough (×1.29); the build must fix it.

## 2. API

### 2.1 Type (`ScalingHeader/HeaderTypes.swift`)

```swift
/// What a `pull: .stretch` header's content does while a pull past the top grows the header (D76). In both cases the
/// header grows by the pull with its bottom edge on the content's top, is cut at the scroll view's width, and an aspect-fit
/// image grows from its top centre; the cases differ in the fixed-size parts (text, symbols, controls, padding, fixed
/// frames). `pull: .preserve` and a banner (a scroll view without the vertical axis) ignore it.
public enum ZTronHeaderStretchContent: Hashable, Sendable {
    /// The default: the whole header is magnified with the pull, `(R + g) / R` times about its top centre (`R` its resting
    /// height, `g` the pull), its text, symbols and controls included, as if the resting header were zoomed in. Text and
    /// controls are redrawn at the magnified size, so they stay sharp; images and GPU-drawn views (Metal, maps, video) are
    /// magnified like a photo. At rest the header is exactly the resting one.
    case keepTextMagnified
    /// The header is laid out larger with the pull, `(R + g) / R` times its resting width and height, from its top
    /// centre: text, symbols, controls and fixed frames keep their point size, while an aspect-fit image (and anything else
    /// that follows the size it is offered) grows as with `.keepTextMagnified`. Text whose width follows the header's width
    /// can re-wrap while pulled; give it the resting width with `ZTronHeaderGeometryReader(…, of: \.width)`.
    case keepTextSize
}
```

- **Names.** `.keepTextMagnified` is the user's. `.keepTextSize` is i28's proposal and is kept: it states the one thing
  that differs (text size), mirrors the default's form, and `.grow` / `.relayout` would describe the mechanism, not the
  look. Alternatives for the user, if wanted: `.keepTextAtPointSize`, `.layOutLarger`.

### 2.2 Parameter

- **Signature.** `withScalingHeader(size:collapse:pull:snap:fade:background:overflow:fittingContent:stretchContent:header:)`
  with `stretchContent: ZTronHeaderStretchContent = .keepTextMagnified`, right after D75's
  `fittingContent: ZTronHeaderFittingContent = .topAligned`, before the trailing `header:` closure.
- **Parameter doc.** "`stretchContent`: with `pull: .stretch`, what the content does while a pull grows the header:
  `.keepTextMagnified` (the default) magnifies the whole header and keeps its text sharp; `.keepTextSize` lays it out
  larger, so text and controls keep their size and an aspect-fit image still grows. A change while the header is pulled
  morphs between the two inside the same frame when animated (`withAnimation`), and lands in one frame otherwise."
- **`.stretch`'s own doc** (`ZTronHeaderScalingBehavior.stretch`) loses "while pulled, text and vector art in it are drawn
  as the scaled bitmap" and gains "what its content does is `stretchContent:`" (symbols and paths were never bitmaps: they
  are vector layers, d76:swiftui).

### 2.3 Source compatibility

- Defaulted parameter after the existing ones: every call compiles unchanged and gets today's look made crisp. No
  deprecation. The deprecated `scalingBehavior:` overload keeps its parameters and forwards `.keepTextMagnified`; its
  `renamed:` / DocC link moves to the full new signature. No member, no environment twin (the ruling says a parameter).
- `HeaderSpec.stretchContent` is render-only (not in `HeaderSizing`): a change runs no `headerSpecChanged()`, one host
  body run (a cold app change, S4), as `fade:` today.

### 2.4 Pull values other than `.stretch`

- `pull: .preserve`: the parameter is stored and ignored; no probe, no tick, no engine is installed (zero UIKit work).
- A banner (no vertical axis): `.stretch` is inert there, so is the parameter.
- `.stretch` + `.keepTextSize` (`m` = 1 outside a switch): the engine is installed but idle (`s_eff` = 1, §4.5).
- `.stretch` + D75 `fittingContent: .headerFollows`: the header is magnified AT REST by `(h + g + L)/h`; the engine keys
  on the drawn magnification `s_eff > 1`, never on "pulled", so the resting magnified header is crisp too (D75 step 5 lands
  after this design's M3).

### 2.5 Changing the option at runtime

- i28 §3.4 is unchanged: animated, `m` interpolates in the same transaction (morph inside a fixed frame); unanimated, the
  new look lands in one frame (D65's precedent); at rest (`g` = 0, `L` = 0) both cases draw the same pixels.
- **The engine follows `m` seamlessly**: its density per frame is the effect's own `s_eff = (h + g)/(h + m·g)` read in
  the same update (§4.5), so every morph frame is drawn at its own magnification. At `m` = 1 `s_eff` = 1 and the
  restore lands in that same commit. This is the same transition as a release to rest (density follows `s` down to 1),
  measured by d76:uikit's release bursts: 0 STALE frames, restore 0 px, on 27.0 / forced / 17.5. Unanimated: the swap
  commit restores in the same commit (one-frame swap, never a blurred frame). Acceptance re-measures the morph itself
  (§7, A6), because the morph also re-lays out text (a SwiftUI redraw that resets `contentsScale`; §4.5 handles it).

### 2.6 Interplay

- **Fade (D70).** `HeaderFadeOverlay` sits inside the magnified stack. Its colour / gradient layers are not delegate-drawn
  bitmaps, so the engine never touches them (d76:uikit: gradient 0 px vs D69). The fade is active only while collapsing,
  when `s_eff` = 1 and the engine is idle; D75's resting magnification ends before compression starts (`L` first).
- **Collapse (D68).** Compress and slide-behind have `g` = 0: the engine does nothing (no visit, no write) while
  collapsing, snapping or scrolling. The only overlap is `.headerFollows`' `L` shrinking (a release-like descent of `s`).
- **Refresh under `.stretch`.** The hold keeps `g` = hold height: the header stays magnified and crisp for the whole
  refresh (seconds). SwiftUI's resets during it (animation ends, a text change, an app resize) are re-applied in the same
  transaction (KVO, §4.5). The refresh indicator is outside the header subtree (it floats over the band), so it is never
  raised.
- **Background (`background:`).** Materials and blurs are backdrop layers, not drawn bitmaps: skipped (0 px vs D69).
- **i28's switch frames (`0 < m < 1`).** Covered by `s_eff` (above); i28 measured ×1.33–1.40 blur at `m` = 0.5 without
  the engine.

## 3. Evaluation

Method for every number below: lossless `simctl io screenshot` PNGs of the scratch demo's seam lab (black text on the pure
red header, i28's meter `edges.py`: 10–90 % edge widths, all edges and straight stems, horizontal and vertical), holds at
60 / 120 pt (`s` 1.25 / 1.5 on the 240 pt header), animated pulls, bursts. "Native" = the same text laid out at the
magnified point size, phase-aligned. Lanes: 27.0 preferred, 27.0 `-ZTronForceAllFallbacks`, 17.5.

### 3.1 Pure SwiftUI: no route meets the requirements (d76:swiftui, i28 §3.5)

Root cause (layer dumps, every lane): SwiftUI draws Text into bitmap layers at `contentsScale` = 3 and pushes the stretch
effect's transform `s` down to them; CA magnifies the bitmap bilinearly (D69: ×1.49 at `s` 1.25, ×1.73 at 1.5). Symbols,
paths, fills and strokes are vector layers and stay crisp. SwiftUI has no public lever on a leaf's raster density:

| # | Route | Result |
|---|---|---|
| P1 | `\.displayScale` in the environment (any value) | moves layout rounding only; `contentsScale` stays 3: ×1.49 / ×1.73 |
| P2 | `compositingGroup` / `geometryGroup` / transform placement variants | identical pixels to D69 |
| P3 | `drawingGroup` (inside, around, extended bounds) | crisp only around the scale, but platform views draw as placeholders, materials lose their backdrop, blends isolate: refused by D74 |
| P4 | RenderBox via `.drawingGroup(opaque:colorMode:)` variants | as P3 |
| P5 | `TextRenderer` magnifying the glyphs (18+ only) | crisp ×0.89–1.04 but text-only and absent on 15–17 (a 15–16 vs 17+ difference) |
| P6 | environment font × `s` per frame | re-runs `@Environment(\.font)` readers every frame (S4) and restyles font-less controls at rest |

### 3.2 The scoped UIKit engine (d76:uikit prototype, measured)

Mechanism in §4. Results, identical on 27.0 / forced / 17.5:

- **Crisp.** Stems engine/native ×0.89 / ×0.99 (`s` 1.25, h / v), ×1.04 / ×1.01 (`s` 1.5). Twelve-size table: 11 of 12
  within 1.05, means ×1.02 / ×1.00; the outlier is `s` 1.16, horizontal ×1.29 (§9 R2). Mid-animation bursts within 1.05
  except one 17.5 vertical frame at ×1.06 (§9 R2). D69 for comparison: ×1.49–1.57 (`s` 1.25) and ×1.73 (`s` 1.5).
- **Rest identity.** 0 px at rest with the probe installed, 0 px with the probe at holds outside the drawn layers, 0 px
  after release and restore (extras included).
- **No staleness.** 0 STALE frames (a committed layer at the wrong density) through holds, animated pulls and releases,
  a text changing every second, a text appearing / disappearing mid-hold (layout-changing and overlay), width changes,
  rotation and a dark-mode switch mid-hold (the needs-display rule and the KVO re-apply, §4.5).
- **Seam lab** (`|seam|` ≤ 1 pt, lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change): PASS on all three lanes, max seam
  0.17 / 0.50 pt, lateral ≤ 0.42 pt, header / content jumps ≤ 0.26.
- **Counters.** `content.body`, `header.builder`, `header.content` equal to the unpatched build (S4).
- **Untouched kinds.** Material backdrop, blend modes, gradients, images, shapes: 0 px vs D69. The prototype also left
  platform views as D69 (this design raises them, §3.3). Hit testing and accessibility identical (27.0 preferred and
  forced).
- **Cost.** Visit + writes 0.49 ms median, 1.03 ms max per pulled frame (27.0 sim, seam-lab header); the raised text
  stores grow with `s²` (190 → 420 KB at `s` 1.5); zero work at rest and while scrolling or collapsing.
- **Rejected variants (measured).** Linear filter at density `native·s` (×1.33 / ×1.49: sub-pixel resampling); full
  phase snap (v ×1.35); supersampling ×2 (×0.83 / ×0.79, over-sharp, double memory); a fixed density `native·2` (a
  visible switch at 1–2 pt pulls); writing in the effect's update phase only (SwiftUI overwrites in its render); a child
  `UIHostingController` with a `displayScale` trait (×1.73, rest not pixel-identical, and forbidden); dropping the
  platform boundary (applies the layer rule to UIKit-owned layers, which does nothing for their text, §3.3).

### 3.3 This designer's checks (`d76-design-spike.patch`)

- **Container identification.** The prototype takes the nearest clipping ancestor of the probe as the header's subtree.
  If SwiftUI ever omitted the header's own clip layer, that walk would reach the viewport's `.clipped()` layer, a common
  ancestor of header AND content, and raise content text. Guard measured: a second zero-size probe OUTSIDE the header
  chrome (after `HeaderLayerGroup`); a clipping layer that is also an ancestor of that boundary probe is refused.
  27.0 preferred and forced, 17.5: every lookup found the header clip two layers up (17.5: 120 of 120) and none held the
  boundary; only header text was raised (y ≤ 225 pt); prototype vs guarded 0 px at a 60 pt hold; differences vs D69
  only in the header-text rows (hold and animated pull); release and rest 0 px. 17.5 keeps the clip layer at rest,
  27.0 creates it only while pulled.
- **Platform views** (a SwiftUI `TextField` in the header, 60 pt hold, its text on its white background, same meter
  on the white→black axis; rest = ×1.00):

| Variant | 17.5 | 27.0 | rest after release |
|---|---|---|---|
| D69 | ×1.40–1.56 | ×1.40–1.53 | — |
| engine, platform boundary (prototype) | as D69 | as D69 | 0 px |
| engine, no boundary (`isDrawn` rule also on UIKit layers) | as D69 | as D69 | 0 px |
| … + `contentScaleFactor` on UIKit views whose layer passes `isDrawn` | as D69 | as D69 | 0 px |
| `contentScaleFactor = native·s` on EVERY view of the platform subtree | ×1.15–1.44 | ×1.13–1.18 | 0 px / 0 px |
| **… + nearest filter and tie bias on their drawn layers (chosen, §4.3)** | **×1.03–1.05** | **×1.03–1.05** | **0 px / 0 px** |

  UIKit draws a text field's text in views whose layers the public "drawn layer" rule does not select; raising every
  platform view's `contentScaleFactor` (public UIKit API, no class identification) redraws them denser, and the engine's
  filter and tie bias make them 1:1. Ratios here are against the resting field (the same meter on white→black edges);
  SwiftUI's `Text` ratios in §3.2 are against native text at the magnified size. Platform views were identified by
  `Bundle(for:)`: SwiftUI's renderer views report `com.apple.SwiftUI`, the text field's views `com.apple.UIKitCore`
  (17.5 and 27.0).

## 4. Mechanism (the hardened engine)

### 4.1 Files and types

| File | Contents |
|---|---|
| `ScalingHeader/UIKit/HeaderRasterCore.swift` (pure: Foundation + CoreGraphics, no UIKit import) | `HeaderRasterMath`: `density(original:scale:)`, `isMagnified(_:)` (`s > 1 + 1e-5`), `isOneToOne(storeScale:onScreenScale:)` (within 1 %), `tieBias(phasePx:)` (¼ px when the sub-pixel phase is within 0.05 px of ½ px, else 0), `contentsRect(phase:sizePx:)`, `storeBytes`; `HeaderRasterLedger` (records by opaque id: original scale, filters, rect, view scale; raise / restore-all / exclude transitions, counts); `HeaderRasterPolicy.action(for: LayerTraits)` → `.skip`, `.raiseLayer`, `.platformSubtree`, `.stopDescent` (the table of §4.3) |
| `ScalingHeader/UIKit/HeaderRasterEngine.swift` (`#if canImport(UIKit) && os(iOS)`) | `HeaderRasterProbeView` + `HeaderRasterProbe: UIViewRepresentable` (inner); `HeaderRasterBoundaryView` + `HeaderRasterBoundaryProbe` (outer); `@MainActor final class HeaderRasterEngine` (visit, writes, KVO, restore, failure checks, DEBUG counters); `HeaderRasterTick: GeometryEffect` |
| `ScalingHeader/UIKit/HeaderRasterAttachment.swift` (`#if canImport(UIKit) && os(iOS)` with an identity `#else`) | SwiftUI-typed entry points used by `HeaderFrameModifier`: `.headerRasterContent(_:)`, `.headerRasterBoundary(_:)`, `.headerRasterTick(live:engine:)`; so no file outside the directory names a UIKit type |
| `ScalingHeader/HeaderFrameModifier.swift` | `@StateObject` engine per header instance (no `@Published`: never invalidates); the chrome installs the three attachments only for `pull: .stretch` with the capability available; `HeaderStretchEffect.drawnScale(size:stretch:)` (pure, shared by the effect and the tick, so both use the same `s_eff` in the same update) |
| `Availability/ZTronCapability.swift`, `ZTronAvailability.swift` | `.headerRasterDensity` and its DEBUG switch (§4.8) |

### 4.2 Where the probes sit

```
framed                                                // the header at its layout frame (i28: h + g_l)
  .headerRasterContent(engine)                        // zero-size .background, top-leading: its host layer sits among
                                                      // the header's own layers, below the stretch transform
  .modifier(HeaderFadeOverlay(…))
  .modifier(HeaderStretchEffect(live:))               // s_eff = drawnScale(size, scaleStretch)
  .headerRasterTick(live:, engine:)                   // identity effect, same animatable data and size
  .clipShape(HeaderStretchClip(live:))                // the header's own clip layer = the subtree root
  .modifier(HeaderLayerGroup(…))
  .headerRasterBoundary(engine)                       // zero-size .background OUTSIDE the header's clip
  .allowsHitTesting(visible).accessibilityHidden(!visible)
```

Both probes are `UIViewRepresentable`s of zero size, `isUserInteractionEnabled = false`, accessibility-hidden, made once
(`makeUIView`), with an empty `updateUIView`; `dismantleUIView` restores.

### 4.3 Which layers

The container is the nearest ancestor layer of the inner probe that clips (`masksToBounds` or `mask`), accepted only if
it is not also an ancestor of the outer probe's layer (§3.3). The visit walks that subtree, skipping the probes' layers:

| Layer | Action |
|---|---|
| delegate set; contents a backing store (not a `CGImage`) or none with `needsDisplay()`; gravity not `.resize`; not `drawsAsynchronously` (SwiftUI's text: `CGDrawingLayer` / `RBDrawingLayer` on 27.0, `CGDrawingView` on 17.5) | **raise**: record, `contentsScale = original·s`, then filters and tie bias if the store maps 1:1 on screen |
| delegate is a `UIView` whose class's bundle (`Bundle(for:)`) is not `com.apple.SwiftUI*` (UIKit-backed controls, the app's representables) | **platform subtree**: every view in it gets `contentScaleFactor = original·s` (recorded); its drawn layers (contents not a `CGImage`, gravity not `.resize`) get the nearest filter and the tie bias (recorded); descend through it |
| `CAMetalLayer` (Metal views, maps), `drawsAsynchronously` layers | **stop**: the subtree keeps D69's rendering (GPU content scales like an image) |
| anything else (images, shapes, gradients, colours, materials, blends, the fade overlay) | **skip** (unchanged, 0 px vs D69) |

The platform-subtree row is this design's addition (§3.3: the TextField's text from ×1.40–1.53 to ×1.03–1.05 on 27.0,
restore 0 px). SwiftUI's own views never get `contentScaleFactor` (a hosting view could turn it into an environment
change and re-run bodies): that is what the bundle boundary is for.

### 4.4 Density, filter and tie bias

- `s` = `HeaderStretchEffect.drawnScale` of this update: `(h + g_l + g_s)/(h + g_l)` (i28's `s_eff`), which already
  contains D75's `L` in `g_s`. The engine never reads `m`, `g` or `L` itself.
- Density per layer = its recorded original `contentsScale` × `s` (for SwiftUI's text, `3·s`; the measured rule).
- Filter and tie bias only where the store maps 1:1 on screen (`isOneToOne`: original·s vs the layer's on-screen scale,
  `layer.convert(_:to:)` against the window's layer, within 1 %): nearest magnification and minification filters, and
  `contentsRect` shifted by ¼ px only when the layer's sub-pixel phase is within 0.05 px of a ½-px sampling tie. A layer
  under an extra user transform (`scaleEffect`, a rotation) keeps its filters: it is then the resting rendering scaled,
  never aliased.
- The native scale is `traitCollection.displayScale` of the probe (not `UIScreen.main`, deprecated).

### 4.5 Per-frame timing (no `CADisplayLink`)

- **Tick.** `HeaderRasterTick` is evaluated in every update that evaluates the stretch effect (finger, physics clock,
  transaction animations, the i28 morph). It stores `s` and calls `setNeedsLayout()` on the inner probe when `s` changed
  or layers are raised.
- **Write.** The inner probe's `layoutSubviews` runs in the CA commit's layout phase, after SwiftUI rendered that update:
  the engine visits and writes there, so the density lands in the same commit as the frame it belongs to. The prototype
  also wrote in the tick ("both"); M3 starts with layout-only writes and keeps the tick write only if a STALE frame
  shows (the prototype's measured mode).
- **Resets.** SwiftUI (27.0) resets `contentsScale` to native in its render at animation ends, text changes and app
  resizes. Key-value observation of `contentsScale` on every raised layer re-applies synchronously, inside that same
  transaction, and requests a layout pass. The engine's own writes are flagged and ignored by the observer.
- **New layers.** A layer SwiftUI inserted in this transaction has no contents yet; if it needs display it is raised now
  and draws at the density in this commit's display phase (the needs-display rule; 0 STALE for appearing text, §3.2).

### 4.6 Restore at rest

- When `s ≤ 1 + 1e-5` (release, end of refresh, morph to `.keepTextSize`, D75's `L` gone): every recorded layer gets its
  original `contentsScale`, filters and `contentsRect`, every recorded view its `contentScaleFactor`, with
  `setNeedsDisplay`, in that commit; records and observers are cleared. Records are weakly keyed by the layer object
  (`NSMapTable` weak keys), so a layer SwiftUI discarded is neither leaked nor touched again.
- Also on: dismantle of either probe, the probe leaving its window, the DEBUG switch turning the capability off, deinit.
- At rest with nothing raised the engine returns before any visit: zero UIKit work at rest, while scrolling, collapsing.

### 4.7 Failure detection (every failure degrades to D69's rendering for that frame or layer, never a wrong geometry)

- **F1 container.** No clipping ancestor, or one that also holds the outer probe: no write this frame; DEBUG counter
  `containerMisses` (acceptance: 0).
- **F2 no redraw.** At the next layout pass a raised layer whose contents object is unchanged and whose store is not at
  the density (its owner sets its contents) is restored and excluded for the engine's life; DEBUG `excluded`.
- **F3 fight.** A layer reset by someone else more than 3 times within one second is restored and excluded (an owner
  that insists on its own scale); DEBUG `excluded`.
- **F4 visibility for tests.** DEBUG-only `raisedCount`, `excludedCount`, `containerMisses`, `lastDensity` on the engine,
  read by hosted tests and by the demo's readout (app-side counters, no screenshots).

### 4.8 Scope and gating

- **Capability** `ZTronCapability.headerRasterDensity`: `minimumOS` 15.0, no `preferredOSCeiling` (it runs on every OS,
  the blur exists on every OS), `hasFallback` true (the fallback is D69's rendering), not gated: `forceFallback` and
  `forceAllFallbacks` leave it on, because the forced lane emulates iOS 15–16, where the engine runs.
- **Force switch** (DEBUG, like D31's own switch): `ZTronAvailability.forceHeaderRasterDensityOff(_ on: Bool)`, demo
  launch argument `-ZTronForceRasterDensityOff 1`; `isAvailable(.headerRasterDensity)` is `osSupports && !forcedOff`;
  inert in release. Used for the A/B acceptance and the coverage union.
- **Directory** `Sources/ZTronScrollView/ScalingHeader/UIKit/`, every UIKit-importing file starting with
  `#if canImport(UIKit) && os(iOS)`.
- **`scripts/check-uikit-scope.sh`**: `ALLOWED` becomes both directories; for `ScalingHeader/UIKit/` it also forbids
  assignments to any layer or view property other than `contentsScale`, `magnificationFilter`, `minificationFilter`,
  `contentsRect`, `contentScaleFactor`, `isUserInteractionEnabled = false`, `isAccessibilityElement = false`,
  `accessibilityElementsHidden = true` (a regex over `\.(\w+)\s*=` with that allow-list), and the tokens `UIScreen`,
  `CADisplayLink`, `UIGestureRecognizer`, `hitTest`, `point(inside`, `setValue(`, `perform(`, `NSStringFromClass`,
  `String(describing: type(of`, `isKind(of`, `isMember(of`; the global forbidden list is unchanged.
- **`scripts/coverage-uikit.sh`**: 100 % line coverage of each directory, union of the unit run and the demo UI runs
  preferred, `-ZTronForceAllFallbacks`, `-ZTronForceUIKitObserver` (D31) and `-ZTronForceRasterDensityOff 1`.

### 4.9 Availability, S4, S7

- **iOS 15.** Every API exists on 15.0 (`contentsScale` / filters / `contentsRect` iOS 2–4, `contentScaleFactor` 4,
  `displayScale` 8, `NSKeyValueObservation` 11, `UIViewRepresentable` / `GeometryEffect` 13, `Bundle(for:)` 2): no
  `#available` branch. The 15–16 render paths (forced) measured identical to preferred.
- **S4.** No body runs: probes are made once, the tick is an effect, the engine never publishes; counters equal to the
  unpatched build (§3.2).
- **S7.** No geometry write (raster properties only): content transform, insets and the visible centre are unchanged;
  rotation mid-hold 0 STALE.

### 4.10 Cost

- Measured: visit + writes 0.49 ms median, 1.03 ms max per pulled frame; raised stores ×`s²` (190 → 420 KB at 1.5); the
  redraw of raised layers is the same text drawing SwiftUI does on any text change. Nothing at rest.
- Budget (acceptance): p95 ≤ 2 ms, max ≤ 4 ms per pulled frame with the seam-lab header and extras; no extra dropped
  frames in fast (0.3 s) and normal (1 s) animated pulls, engine vs `-ZTronForceRasterDensityOff 1`.

## 5. Amendments the user must accept before anything is built (verbatim; `2026-11-__` = the acceptance date)

Scoped like D31's: one directory, one purpose, named APIs, the same two gates. The clerk applies them in one docs
commit after the user's acceptance; the orchestrator records the decision under the next free D-number.

> **Orchestrator, 2026-11-03, after §11.** 5.2 below already carries §11.5 items 1–3:
> - no `contentScaleFactor` write on a view whose layer holds a `CGImage`;
> - the `sublayers` observation that only asks for a layout pass;
> - probes that add nothing to the accessibility tree. The flags and modifiers tried in §11.4 do not achieve this, and
>   A6's XCUI diff is the test. Untried leads: `isHidden` on the probe's host view, and SwiftUI's `.hidden()`.
>
> The user's D77 ruling (2026-11-03) adds a third scoped exception, the iOS 15–16 neutral group probe
> (`Render/NeutralGroupProbe.swift`, i29 §5.6, D77′). It is a probe of the same kind and has the same accessibility
> requirement. M8b-s9 writes D77′ and D76 as one amendment, so 5.1, 5.3, 5.5 and 5.6 name all three exceptions (D31,
> D77′, D76) where they say "two".

**5.1 SPEC S2, `Allowed imports` bullet.** Append this sentence to the bullet:

> UIKit only inside the two scoped exceptions below (the iOS 15–16 touch observer and the crisp magnified header), each
> in its own directory.

**5.2 SPEC S2, new sub-bullet under `Not allowed`, after the 2026-10-20 touch-observer amendment:**

> - **Amendment 2026-11-__ (user) — the crisp magnified header (D76).** A second library exception: UIKit may be used
>   **only to keep the drawing of a `pull: .stretch` header with `stretchContent: .keepTextMagnified` at its on-screen
>   pixel density while that header is drawn magnified** (pulled, held by a refresh, or magnified at rest by
>   `fittingContent: .headerFollows`), on every iOS version — never for scrolling, gestures, layout, geometry,
>   hit-testing, accessibility, or any view outside that header. Rules (design `docs/design/d76-magnified.md`):
>   - UIKit code lives **only** in `Sources/ZTronScrollView/ScalingHeader/UIKit/`, wrapped in
>     `#if canImport(UIKit) && os(iOS)`. It does nothing while the header is not magnified; the DEBUG launch argument
>     `-ZTronForceRasterDensityOff` turns it off (the pure-SwiftUI rendering, for A/B tests).
>   - Allowed there: two zero-size, non-interactive `UIViewRepresentable` probes that add nothing to the accessibility
>     tree (one inside the header's magnified stack, one outside the header's clip); a walk of the header's own layer
>     subtree only (below the header's clip layer, found from the inner probe and refused when it also contains the
>     outer probe); writes of `contentsScale`, `magnificationFilter`, `minificationFilter` and `contentsRect` on the
>     layers drawn in that subtree, of `contentScaleFactor` on the views of platform views in it (UIKit-backed controls,
>     representables) except a view whose layer holds a `CGImage`, and `setNeedsDisplay`; key-value observation of
>     `contentsScale` on the layers it changed and of `sublayers` on the platform layers it raised (that handler only
>     asks for the probe's next layout pass); telling platform views from
>     SwiftUI's own views only by their class's framework bundle (`Bundle(for:)`). Every changed value is recorded
>     first and restored when the header stops being magnified, so the resting header is pixel-identical to the
>     pure-SwiftUI rendering.
>   - Still forbidden everywhere: `UIScrollView`, `UIHostingController`, `CADisplayLink`, private API (private
>     selectors, ivars or KVC keys), behaviour keyed on class names, and writes to any other layer or view property.
>   - That directory has the same **100 % line-coverage gate** and **scope gate** as `Gesture/UIKit/` (S14 §5).

**5.3 SPEC S14 §5.** Replace the `UIKit touch observer gates` bullet and its two sub-bullets with:

> - **UIKit gates** (Amendment 2026-10-20 (user), extended 2026-11-__ (user, D76)), both run by the test-runner at every
>   milestone end and before any commit that touches `Sources/ZTronScrollView/Gesture/UIKit/` or
>   `Sources/ZTronScrollView/ScalingHeader/UIKit/`; a failure blocks the commit:
>   - **Coverage gate** — `scripts/coverage-uikit.sh`: **100 % line coverage** of every file under those two
>     directories, measured on the `ZS_DEST` simulator (Debug, `-enableCodeCoverage YES`, `-resultBundlePath`) as the
>     union of the package unit tests and the demo UI tests launched without arguments, with `-ZTronForceUIKitObserver`
>     (with and without `-ZTronForceAllFallbacks`) and with `-ZTronForceRasterDensityOff 1`; `xcrun xccov view --report
>     --json` / `--archive --file` filtered to those directories; exits 1 below 100 % and prints every uncovered line.
>     Lines executed only by a direct call of an override with an empty touch set count for coverage but not for
>     behavior (the touch-observer design says which lines those are and how their behavior is proven instead).
>   - **Scope gate** — `scripts/check-uikit-scope.sh`: `import UIKit` (and `UIKit.`-qualified names,
>     `UIViewRepresentable`) appear only under those two directories; every file there that imports UIKit starts with
>     `#if canImport(UIKit) && os(iOS)`; `UIScrollView`, `UIHostingController`, `NSClassFromString`, `value(forKey`,
>     `Mirror(` appear nowhere in `Sources/` or `Packages/`; under `ScalingHeader/UIKit/` no assignment to a layer or
>     view property other than `contentsScale`, `magnificationFilter`, `minificationFilter`, `contentsRect`,
>     `contentScaleFactor` and the probes' `isUserInteractionEnabled = false`, `isAccessibilityElement = false`,
>     `accessibilityElementsHidden = true`, and none of `UIScreen`, `CADisplayLink`, `UIGestureRecognizer`, `hitTest`,
>     `point(inside`, `setValue(`, `perform(`, `NSStringFromClass`, `String(describing: type(of`, `isKind(of`,
>     `isMember(of`; exits 1 otherwise.

**5.4 SPEC S14 §3, new bullet after `UIKit touch observer core`:**

> - **Header raster core** (Amendment 2026-11-__ (user), D76; `ScalingHeader/UIKit/HeaderRasterCore.swift`, pure):
>   density = original × `s`, exactly the original at `s` = 1; the 1:1 test; the tie bias (¼ px only within 0.05 px of
>   a ½-px tie, both signs, both axes); the ledger (raise, re-raise, restore-all to the exact originals, exclude); the
>   layer policy table (drawn, needs-display, image, `.resize`, asynchronous, platform subtree, `CAMetalLayer`); every
>   branch, including the defensive ones (non-finite or zero scales, empty ledgers).

**5.5 SPEC S16, `Spike: proving the contract against UIKit`, `Where:` bullet.** Replace "It is the only place in this
repo where UIKit is allowed." with:

> It is the only place in this repo where UIKit drives scrolling; the library's two scoped UIKit exceptions (S2: the
> iOS 15–16 touch observer and the crisp magnified header) observe touches or keep a header's raster density, and
> neither is part of ScrollArbitration.

**5.6 CLAUDE.md `Non-negotiables`, first bullet (and its copy in SPEC F6).** Replace

> - Library imports only SwiftUI, Combine, Observation (gated), Foundation and ScrollArbitration (SPEC S16). No
>   UIKit/AppKit, *Representable, CADisplayLink, reflection or private API; UIKit appears only in the MC spike app.

with

> - Library imports only SwiftUI, Combine, Observation (gated), Foundation and ScrollArbitration (SPEC S16). No
>   UIKit/AppKit, *Representable, CADisplayLink, reflection or private API, except SPEC S2's two scoped UIKit
>   exceptions, each behind 100 % coverage and the scope gate: `Gesture/UIKit/` (iOS 15–16 touch observer, D31) and
>   `ScalingHeader/UIKit/` (crisp magnified header, D76). Elsewhere UIKit appears only in the MC spike app.

(The current bullet predates D31; the replacement also states D31's accepted exception.)

## 6. Build steps (M8b-s9 or a follow-up; each one a green commit; after i28 steps 1–2, the enum and `drawnScale`)

The grow case, the mix and the switch are i28's steps and are not repeated. `scripts/test.sh -only-testing:` the
touched suites on 27.0 and 17.5 at each step; both gates from step 1 on.

0. **Acceptance.** The user accepts §5. Clerk: SPEC S2 / S14 §3 / S14 §5 / S16 / F6 and CLAUDE.md in one docs commit;
   Orchestration records the decision. Nothing below starts before this.
1. **Gates and capability.** `check-uikit-scope.sh` (two directories, the per-directory rules of §4.8) with a self-test
   (a temporary file per rule must make it exit 1); `coverage-uikit.sh` over both directories with the new union;
   `ZTronCapability.headerRasterDensity`, `forceHeaderRasterDensityOff`, the demo's `-ZTronForceRasterDensityOff`;
   `ZTronCapabilityTests`: minimum 15.0, not gated, `forceAllFallbacks` leaves it available, the switch turns it off,
   release inert. Commit.
2. **Pure core.** `HeaderRasterCore.swift` + `HeaderRasterCoreTests` (S14 §3 bullet of §5.4), 100 % lines of the file;
   `HeaderStretchEffect.drawnScale(size:stretch:)` shared by the effect (D69 tests bit-equal). Commit.
3. **Engine for SwiftUI's layers.** `HeaderRasterEngine.swift` (probes, tick, layout-phase writes, KVO, needs-display
   rule, restore, F1–F4), `HeaderRasterAttachment.swift`, the chrome of §4.2 for `.stretch` only.
   `HeaderRasterHostedTests` (window-hosted, as `HeaderStretchScaleTests`). Layout-only writes first; if A6 shows a
   STALE frame, add the tick-phase write (the prototype's mode). Commit.
4. **Platform subtree.** The `contentScaleFactor` / filter / tie path and the `CAMetalLayer` stop of §4.3; hosted tests
   with a `TextField`, a `UIViewRepresentable` label and an `MTKView`. Commit.
5. **Demo and UI tests.** Seam-lab switches `-ZTronSeamHeaderText`, `-ZTronSeamContentText`, `-ZTronSeamHeaderExtra`
   (from the spikes), the engine's DEBUG counters in the readout, `SeamLabUITests` reading app-side counters (raised,
   excluded, misses; no screenshots), the coverage-union launch arguments. Commit.
6. **Acceptance lanes** (§7) on 27.0 preferred, 27.0 forced and 17.5, smoke on 18.x and 26.x; both gates at 100 % /
   clean. Then D75 step 5 (resting magnification) may land. Commit the report numbers in the handoff.
7. **Docs.** SPEC S10 (`.stretch` paragraph and `stretchContent:`), S11 signature, S3 availability row (the engine on
   every OS, D69 as its DEBUG-off rendering), the parity matrix, this design under `docs/design/`, handoff, Orchestration.

## 7. Acceptance (per lane: 27.0 preferred, 27.0 `-ZTronForceAllFallbacks`, 17.5; lossless PNGs, load < ~300)

| # | Check | Pass |
|---|---|---|
| A1 | Crispness of SwiftUI text vs native text at the magnified size: holds at `s` 1.25 and 1.5; the twelve-size table; bursts of fast (0.3 s) and normal (1 s) animated pulls and of the release | every stem and all-edge ratio ≤ 1.05, h and v, 12 of 12 sizes, every burst frame |
| A2 | Rest identity vs `-ZTronForceRasterDensityOff 1` | 0 px at rest with the probes, after release, after a refresh, after a morph to `.keepTextSize` and back, after a rotation at a hold, with extras |
| A3 | Seam lab with header and content text rows | PASS: \|seam\| ≤ 1 pt, lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change |
| A4 | Counters `content.body`, `header.builder`, `header.content` | equal to the engine-off run through holds, pulls, refresh, morph |
| A5 | Content and untouched kinds | content text 0 px vs off at every hold; images, shapes, gradients, materials (backdrop), blend modes, the fade overlay 0 px vs off; an `MTKView` 0 px vs off |
| A6 | Platform views | `TextField` text ≤ 1.05 at `s` 1.25 and 1.5 (vs the resting field) and its restore 0 px; `Toggle` / `Button` hittable and working while pulled; accessibility tree identical |
| A7 | Switches and changes, app-side commit check | 0 STALE frames: animated and unanimated morph while held, a text changing every second, text appearing / disappearing, dark mode, width change, rotation, a text change at rest in `.headerFollows` |
| A8 | Container | 0 misses and 0 boundary refusals in every scenario |
| A9 | Cost | visit + writes p95 ≤ 2 ms, max ≤ 4 ms per pulled frame; no extra dropped frames vs off in fast and normal pulls; stores ≤ `s²` × rest + 5 % |
| A10 | Gates | 100 % line coverage of both UIKit directories; scope gate clean |

## 8. Tests

- **Unit (host-free, pure):** `HeaderRasterCoreTests` (§5.4), `ZTronCapabilityTests` additions, the effect's
  `drawnScale` (bit-equal with D69's transform at `m` = 0, i28's `s_eff` at `m` = 1 and between).
- **Hosted (window, CALayer assertions, as `HeaderStretchScaleTests`):** at a 60 pt hold every SwiftUI text layer of the
  header has `contentsScale` = 3·`s` and nearest filters, no content layer changed, image / shape / gradient / material
  layers unchanged; release restores the exact recorded values; `.preserve` installs no probe; `.keepTextSize` raises
  nothing; capability off installs nothing; dismantle and window removal restore; a simulated reset (a write to a raised
  layer's `contentsScale`) is re-raised in the same run-loop turn; F1 with synthetic `CALayer` trees (a clip holding the
  boundary is refused); F2 (a layer with owner-set contents is excluded); F3 (four resets in a second exclude a layer);
  platform subtree (`TextField`, representable, `MTKView` stop).
- **UI (demo, app-side counters):** seam lab holds, pulls, refresh, morph, rotation, dark mode with the counters of F4;
  hit tests on header controls while pulled; the coverage-union lanes.
- **Coverage:** 100 % lines of both UIKit directories (union of unit + UI runs, §5.3); defensive lines reached by the
  hosted tests above, not by direct calls.

## 9. Risks

- **R1 SwiftUI's layer structure changes** (a future OS draws text without a delegate-drawn store, or drops the clip
  layer): the engine raises nothing and the header is D69's blur, silently. Mitigation: hosted test "≥ 1 header text
  layer raised at a hold" on every lane (fails loudly on a new OS), DEBUG `containerMisses`, A1 / A8 per new OS.
- **R2 Two measured outliers:** the twelve-size table's `s` 1.16 horizontal ×1.29, and one 17.5 vertical burst frame at
  ×1.06. Hypothesis: the effect's `s` and the layer's on-screen scale differ by layout rounding, so the store is not
  exactly 1:1 and the nearest filter drops or doubles a column. Planned fix: the 1:1 test and the per-layer on-screen
  scale (§4.4). A1 requires 12 of 12; if it still fails, the builder stops and reports with the numbers.
- **R3 The bundle boundary** relies on SwiftUI's renderer views coming from `com.apple.SwiftUI*` bundles (17.5, 27.0:
  `com.apple.SwiftUI`; UIKit's controls: `com.apple.UIKitCore`). A hosted test asserts both on every lane. If SwiftUI's
  own views ever fell outside the prefix they would take the platform path (also crisp, measured), but SwiftUI's hosting
  views could then turn `contentScaleFactor` into an environment change: A4's counters would catch it.
- **R4 Platform views are UIKit-owned.** UIKit may reset `contentScaleFactor` (trait or window changes): the KVO on their
  layers re-applies; an owner that fights is excluded (F3, D69 look for that view only). Heavy GPU views are stopped by
  the `CAMetalLayer` rule; a representable drawing with another GPU API would be raised and cost memory (A9 on the
  demo's extras only).
- **R5 Large magnifications.** A small header pulled far has a large `s` (e.g. 100 pt pulled 150 pt: `s` 2.5, stores
  ×6.25); memory and redraw cost grow with `s²`; no cap, since a cap would bring the blur back. A9 includes a 2.5 case.
- **R6 KVO on `CALayer`** is not documented property by property; measured to fire for `contentsScale` on 27.0 and
  17.5 (SwiftUI's resets: 27.0 only). A hosted test asserts the observer fires.
- **R7 Old devices** (iOS 15 on A9–A11 hardware): text redraws at `s²` density per pulled frame may cost frames; only the
  real 15.0 / 16.0 runs (§10) can tell.
- **R8 i29's route P (D77, a private KVC key)** is a separate decision with its own directory; nothing here depends on it.
- **R9 D75's resting magnification** keeps raised stores while `.headerFollows` has `L` > 0, and relies on KVO and the
  needs-display rule for content changes at rest (no tick); A7 includes that case.

## 10. Real iOS 15.0 / 16.0 checklist (the user's M1 Mac lane, Xcode 26.x)

1. Seam lab, `-ZTronHeaderBehavior stretch -ZTronSeamHeaderText 1`, holds 60 and 120: A1 meter (edges.py), and engine
   off vs on at rest 0 px.
2. Extras `field,toggle,button,material,symbol,image,gradient`: A5 / A6 (TextField ≤ 1.05, controls work).
3. Animated pull and release bursts: A1 per frame; A7's commit check in the log.
4. Refresh hold under `.stretch` for 5 s with a text changing every second: 0 STALE, rest 0 px after.
5. Readout: container misses 0, boundary refusals 0, `Bundle(for:)` ids of the header's SwiftUI views and of the
   TextField's views (expect `com.apple.SwiftUI` / `com.apple.UIKitCore`).
6. Cost per pulled frame (DEBUG log) and Memory gauge at `s` 1.5.
7. Rotation at a hold, dark mode at a hold: 0 STALE, visible centre unchanged (S7).

## 11. Verification (d76:verify, independent skeptic, 2026-11-03)

**Verdict: partly.** For SwiftUI's own header text the engine does what §3.2 says, on 27.0 preferred, 27.0 forced and 17.5
alike:
- crisp at holds and in every committed frame;
- 0 px at rest against the unpatched build, with one 1/255 exception on 17.5;
- counters equal;
- the `.stretch` seam rows PASS (27.0 p / f; 17.5's seam rows were not run, see §11.1).

As written, the design fails in seven places:
- (a) The platform row of §4.3 (its "gravity not `.resize`" condition) regresses `TextField` and `draw(_:)` text.
- (b) UIKit content that inserts views during a hold stays at D69's blur for the whole hold. A synchronous KVO repair does
  not work. A three-part repair (§11.4) is crisp in every frame on all three lanes.
- (c) The probes add two zero-size containers to the accessibility tree. Four measured ways to hide them fail (§11.4).
- (d) R2's planned fix cannot remove the `s` 1.16 outlier, and A1's 1.05 bound lies inside native text's own spread.
  One mid-animation frame is ×1.05–1.06 against native at the neighbouring sizes.
- (e) §1 / §4.10's cost leaves out the redraw the engine causes.
- (f) On 17.5, rotated and `scaleEffect` text is 2 px at 1/255 off the unpatched build after a release.
- (g) A `UIImageView` with a non-scaling `contentMode` (`.center`) stops magnifying while held: the platform row's
  `contentScaleFactor` write sets its image's on-screen size. A one-line exclusion fixes it (§11.4).

Nothing here touches SPEC S2 / S16 or CLAUDE.md. All of this is scratch evidence for the user's decision.

### 11.1 Method

- **Builds.** Own worktrees at 72ca7fc (removed after the run):
  - the designer's `d76-design-spike.patch`, rebuilt;
  - `-ZTronVerifyDesignRules 1`, which applies the §4.3 / §4.4 rules as written: the `CGImage` exclusion, the gravity
    condition, `isOneToOne`, and the `CAMetalLayer` / `drawsAsynchronously` stop;
  - scratch flags for the repairs in §11.4;
  - for the A/B, the **unpatched** 72ca7fc library with a byte-identical demo.

  r1 compared against 72ca7fc's own demo and found 2385 px of harness noise. r2 fixes that by copying the demo.
- **Configs.**

  | Config | What it is |
  |---|---|
  | D69 | engine off |
  | DES | the design as written |
  | DESL | DES writing in the layout phase only (§4.5's M3 start) |
  | proto | the designer's spike |
  | desng | DES without the platform row's gravity condition |
  | desw / desw2 / desng2 / des3 | DES plus parts of a candidate repair (§11.4) |
  | **fix** (desng3) | the repair that works: desng + the `sublayers` trigger + the needs-display filter rule (§11.4) |
  | **fix2** | the fix + no `contentScaleFactor` write on a view whose layer holds a `CGImage` (§11.4) |
- **Simulators.** Own simulators: iPhone 18 Pro on 27.0 (preferred, and with `-ZTronForceAllFallbacks`) and iPhone 15 Pro
  on 17.5.
  - Shots are lossless `simctl io` PNGs, measured with i28's meter (`edges.py`, 10–90 % edge widths).
  - Every shot was taken at a 1-min load below 175.
  - Shots whose load spiked during the wait were re-run alone. Only one was broken (17.5 `pv-uilabel-rest-base`, load 526).
- **Per-frame checker** (`VerifyLab.swift`, `-ZTronVerifyFrames`).
  - It is independent of the engine: a demo `CADisplayLink` walks the **presentation** tree every frame.
  - For every visible drawn layer it computes q = `contentsScale` / (native × on-screen scale). q = 1 means drawn 1:1;
    q = 1/s is D69's magnified bitmap.
  - r3 adds UIKit-owned layers, whose gravity is `.resize` (the first version excluded them).
  - It sees the committed scale, not the store's pixels. Bursts of screenshots cover the pixels.
- **Counters.** `-ZTronSpikeCounters`. Rest launches were repeated 8 times per config per lane at load 3–6.
- **Locks.** Seam-lab and XCUI runs took the s8 seam lock and the machine-wide UI lock. Both stayed with other lanes from
  14:26 to 16:30, so every lock-free lane ran first. The 17.5 seam rows and flicks and the D69 fling-hold run were not
  made; the accessibility runs (no seam scenario) took the UI lock alone.
- **Patch and tools.** `m8b-s8-resume/d76-verify/r3/` holds:
  - `d76-verify-r3.patch`: the spike, the harness and every candidate flag;
  - `tools.tgz`: the lanes and meters.

### 11.2 Claims

- 27.0 p = preferred; 27.0 f = `-ZTronForceAllFallbacks`.
- "Native" = the same text laid out at the magnified size.
- Ratios are stems h / v unless "all-edge" is stated.

| # | Claim (where) | Status | Evidence |
|---|---|---|---|
| C1 | Crisp SwiftUI text at holds, ×0.89–1.04 (§1.3, §3.2) | confirmed | Engine vs native, stems: `s` 1.25 ×0.889 / ×0.990 (17.5 ×0.889 / ×0.989); `s` 1.5 ×1.039 / ×1.014. All-edge ×0.941 / ×1.012 and ×1.036 / ×1.004. D69: ×1.37–1.52 and ×1.65–1.79. DES, DESL and proto are pixel-identical. 27.0 f equals 27.0 p (0 px). `s` 2.5 (360 pt hold): ×1.08 / ×1.04 vs native 60 pt; D69 ×2.85 / ×2.79. |
| C2 | Twelve sizes: 11 of 12 ≤ 1.05, `s` 1.16 the outlier; cause = store not 1:1, fixed by the 1:1 test (§3.2, §9 R2) | numbers confirmed; **R2's cause refuted** | 27.0 and 17.5 agree to ±0.001. Means ×1.028 / ×0.998. `s` 1.16 h ×1.293 (all-edge ×1.107); `s` 1.28 ×0.945 (sharper). At `s` 1.16 the store is exactly 1:1: store / on-screen = 1.000000 in the layout phase (0.998 in the tick phase). Yet the stem is 1.458 px against native 1.128 px and the text at rest 1.323 px. This is not resampling, so the planned 1:1 test cannot change it. Native at ±0.12 pt is off by more than 5 % at 4 of 12 sizes (×0.932–×1.064), so A1's 1.05 lies inside native text's own phase spread. |
| C3 | Mid-animation within 1.05 (§3.2) | **refuted, marginally** | Worst burst frame of a 3 s pull against native at the neighbouring sizes. 27.0 p, `s` 1.461: stem 1.436 px vs native 1.355 (`s` 1.44) and 1.362 (`s` 1.48) = ×1.05–1.06. It is ×1.04 against the widest native of ±0.12 pt there (1.384); native 30 pt is 1.443. 17.5, `s` 1.235: 1.415 vs native 1.387 (`s` 1.24) = ×1.02. 27.0 f ≤ ×1.04 vs rest. DESL ×1.06 / ×1.04 vs rest; D69 ×1.73 vs rest. It is the same phase effect as C2, not resampling. |
| C4 | Rest identity, 0 px (§1.3, A2) | **confirmed on 27.0 p / f; refuted on 17.5 by 1/255** | 0 px vs the unpatched build at rest, after release, at the end of a refresh hold, with content text, in five extras groups, with platform views, after every attack, and after fast pulls with platform views (also with the fix). On 17.5 one exception: group E (a 12° `rotationEffect` `Text` and a `scaleEffect(0.75)` `Text`). After release 2 px differ by 1/255 at pt x 165–171, y 81–82, in 3 of 3 runs, still there 12 s later. D69 vs unpatched is 0 px, and the unpatched build's rest and after-release are identical. `isOneToOne` refuses those layers' filters, but their density is still raised and restored; presumably the redraw after the restore lands 1/255 off (not isolated). 17.5 excludes the home-indicator rows (839–844 pt), which differ base vs base too. After a morph: **unverified** (`.keepTextSize` is not in 72ca7fc). |
| C5 | No staleness: every committed frame at the right density (§3.2, A7) | **SwiftUI text confirmed; UIKit content refuted as designed, repaired by the fix** | See the two rows below. |
| C5a | … for SwiftUI text | confirmed | 0 frames off 1:1 among all magnified frames: fast (0.3 s) and normal (1 s) pulls and releases (96–185 per run, 2 runs each, all three lanes); finger flicks at 3000 pt/s (262–266 per run, 27.0 p / f); a 1 s timer `Text`; text appearing / disappearing (layout-changing and overlay); rotation; app-animated width; dark mode; Dynamic Type; background / foreground (same pid); two headers; the app banner (NavigationView + aspect refit). D69: 100 % at q 0.667 (0.8 at `s` 1.25). The only counted frames are a pre-existing glitch with D69 too (§11.3, width). |
| C5b | … for UIKit-owned text | **refuted** (fix measured) | Static `TextField`, `UILabel` and `draw(_:)` views stay 1:1 per frame through holds, bg / fg, dark mode, Dynamic Type, rotation, width change and fast pulls. A `UILabel` whose text changes in place stays crisp (×1.04 / ×1.00). But UIKit content that **inserts views** during a hold is never raised. (1) A representable that replaces its `UILabel` every second sits at q 0.667 in 258 of 262 frames for the whole hold: ×1.61–1.80 (27.0 p / f) and ×1.55–1.60 / ×1.78–1.81 (17.5), the same as D69, in proto and desng alike. (2) A SwiftUI `TextField` whose text changes every second (UIKit inserts new text-fragment views) gives ×1.13–1.15 / ×1.20–1.25, even without the gravity condition; the static field is ×0.96 / ×1.03. (3) 17.5, DES, app-animated width: one frame with a platform layer at q 0.8 (0.60 s) in 3 of 3 runs (27.0: 0 in 3); the fix removes it (0 in 2 runs). The engine only runs on a SwiftUI update (tick), on a layout pass it requested, or on a `contentsScale` KVO of a layer it already raised, and none of those fire. The fix (§11.4) makes (1) and (2) crisp in every frame on all three lanes. |
| C6 | Seam lab PASS (§3.2, A3) | confirmed for the `.stretch` rows on 27.0 p / f; 17.5 unverified | 27.0 p / f: pull with and without content text, D69, rotate-hold, width-hold and the app banner all PASS. Max \|seam\| 0.5 pt, lateral ≤ 0.41 pt, jumps ≤ 0.23 (p) / ≤ 0.12 (f). `aspect-rest-stretch-fling-hold` prints FAIL with an overlap of 71.3 pt (p and f): from frame 214 the header holds its collapsed 64 pt while the content scrolls under it. `analyze.py` documents that case as geometry, not a seam, to be judged by its jumps: 0.13 / 0.13 / 0.07, so it passes by the lab's own rule. Flicks: 0 of 262–266 magnified frames off. Not run: 17.5's seam rows and flicks, and the D69 run of fling-hold, because the s8 seam lock and the UI lock stayed with other lanes for 1.5 h+. |
| C7 | Counters equal (§3.2, A4, S4) | confirmed | `content.body` / `header.builder` / `header.content` = 1 / 1 / 1 in all of these: holds, pulls, after release, end-of-hold, extras and attacks, and while UIKit inserts views mid-hold (DES and the fix alike, at 1.2 s and 6 s). Rest launches: 32 of 32 per lane (base, DES, D69, probes only, 8 each) at load 3–6, on 27.0 and on 17.5. The earlier 17.5 launches with `header.builder` 2 (base, DES and D69 alike) all ran at load 7–158: a launch-timing effect, not the engine. |
| C8 | Untouched kinds 0 px vs D69 (§3.2, A5) | **refuted for one platform kind**; one exception by construction | 0 px at holds for: toggle (its `UISwitch` subtree is raised to csf 4.5 with identical pixels), SF symbol, blend, gradient, image (resizable and not), shape, `.scaleToFill` `UIImageView` (static, and inserted mid-hold) and `MTKView`. The `UIImageView` passes thanks to the `CGImage` exclusion (proto pixelates it: 7629 px); the `MTKView` thanks to the `CAMetalLayer` stop. **A `UIImageView` with `contentMode = .center` does not magnify while held** (DES and the fix, 27.0 p and 17.5). At `s` 1.5 its dark-pixel box is 113 × 59 px against D69's 170 × 89 px (15 860 px differ in the image area); after release 0 px. Cause: §4.3 writes `contentScaleFactor` = density on every platform view, and under a non-scaling gravity a `CGImage` layer's `contentsScale` sets its on-screen size. Repair: §11.4 (fix2). Exception by construction: a material **over** header text changes (up to 229 / 255) because its backdrop is now the crisp text. |
| C9 | Platform views ×1.03–1.05 (§1.6, §3.3, A6) | **refuted as written** | §4.3's platform row puts nearest and tie bias only on layers whose gravity is not `.resize`. UIKit's text layers are `.resize`, so they stay bilinear. `TextField`: ×1.21 / ×1.17 at `s` 1.25 and ×1.41 / ×1.28 at 1.5 on 27.0; ×1.51 / ×1.18 and ×1.28 / ×1.28 on 17.5. `draw(_:)` view: ×1.18–1.38 h. Without the condition (desng = proto = fix): `TextField` ×1.12 / ×1.05 (vs rest ×1.09 / ×1.02) and ×0.96 / ×1.03; `UILabel` ×1.07 / ×1.01 and ×1.02 / ×0.99; draw view ×1.05 / ×1.00 and ×1.02 / ×1.00. Identical on 27.0 and 17.5. `s` 1.25 h still misses 1.05 (the C2 phase effect again). Toggle and Button are hittable and work while pulled (27.0 p / f, 17.5). |
| C10 | Hit testing and accessibility identical (§3.2, A6) | hit testing confirmed; **accessibility refuted** | XCUI tree at a 60 pt hold, engine on vs off: two extra zero-size "Other" elements per header, the probes (27.0 p / f at {−50.2, 62} and {0, 62}; 17.5 at {−49.1, 59} and {0, 59}). All other elements and frames are identical. `isAccessibilityElement = false` and `accessibilityElementsHidden = true` on the UIView do not hide SwiftUI's platform-view host, and neither do three more attempts on 17.5 (§11.4): SwiftUI's `.accessibilityHidden(true)` on both representables (tree identical to DES's), the library's `.accessibilityRepresentation` idiom (the two elements stay, at {0, 0, 0, 0}), and the hosting superview's own flags (unchanged). Both elements are unlabelled containers; VoiceOver focus was not measured. |
| C11 | Container: 0 misses, 0 refusals, clip two layers up (§3.3, A8) | confirmed | Every lookup: hops 2, 0 boundary refusals, 0 misses (27.0 p / f, 17.5, all attacks, twin headers, app banner). The clip exists at rest on 17.5, and on 27.0 with platform views in the header; 27.0 creates it while pulled otherwise. 27.0 f's rest tree equals 27.0 p's (43 layers; only group-opacity flags differ). The probes add 4 `_UIInheritedView` + 4 `PlatformViewHost` on 17.5 and 2 + 2 on 27.0 (C10). |
| C12 | Bundle boundary (§3.3, R3) | confirmed | SwiftUI's renderer and host views come from `com.apple.SwiftUI`, UIKit's controls from `com.apple.UIKitCore` (8 classes), representables from the app bundle. |
| C13 | KVO re-applies SwiftUI's resets (§4.5, R6) | confirmed | 27.0 p / f: 1–3 resets per run (animation ends, text change, resize), re-applied in the same transaction (0 frames off). 17.5: none with header text alone; with a field, toggle, material, symbol and button in the header, 1 per run at the pull animation's end (4.5 → 3.0), re-applied 0.1 ms later. On a UIKit-owned view the prototype installs no `contentsScale` KVO (R4). No measured case needed one: UIKit never reset an already-raised view under traits, rotation or bg / fg. The one platform frame at q 0.8 on 17.5 (C5b (3)) comes from an insertion: the `sublayers` trigger removes it (desw and the fix). |
| C14 | S7 / no geometry write (§4.9) | confirmed | Rotation mid-hold: 0 frames off, rest after 0 px, seam rotate-hold PASS (lateral ≤ 0.41 pt). |
| C15 | Cost: ~0.5 ms, 1 ms worst, ~0.2 MB (§1.7, §4.10, A9) | **refuted as stated** | Visit + writes per pulled frame: median 0.10–0.23 ms, p95 0.31–1.51, max 2.04 ms. That meets A9 but not "1 ms worst". **The redraw the engine causes is extra** (D69 never redraws while pulled): text header 0.46 ms median, 0.94 max; 12-sentence paragraph 1.54 / 2.30 at `s` 1.5 and 2.00 / 5.38 at `s` 2.5. Total per frame at `s` 2.5: p95 3.83 ms, max 5.73 ms. Memory (phys_footprint, paragraph): +1.28 MB at `s` 1.5 and +4.07 MB at `s` 2.5 (D69 −0.1 / −0.2); after release 0.7 MB above rest (one sample). §1's "~0.2 MB" holds only for a one-line header. Pacing (27.0 simulator): fast pulls 0 hitches in 3 (DES), 1 hitch of 33–36 ms in 2 of 3 (DESL), 0 (D69); collapses 1 hitch (35.9 ms) in 3 with the probes vs 0 in 3 unpatched. That is simulator-noise level (a D69 paragraph run had 2), but it is not evidence of "no extra dropped frames". |
| C16 | iOS 15 / 16 (§1.3, §4.9) | unverified | No 15 / 16 runtime on this Mac. The forced lane switches the library's fallbacks, not SwiftUI's renderer. |
| C17 | F2 / F3, scope gate, coverage (§4.7, §4.8, A10) | unverified | Not in the prototype. |
| C18 | Morph, `.headerFollows` with L > 0 (A2, A7, R9) | unverified | Not in 72ca7fc. |

### 11.3 Attacks

DES unless stated; 27.0 p / f and 17.5 agree unless stated.

| Attack | Result |
|---|---|
| Timer-driven `Text` (1 s) at a 120 pt hold | 0 frames off; ×1.01–1.04 / ×0.99–1.01 vs native 36 pt (D69 ×1.71–1.79) |
| Rotation during a hold (and back) | 0 frames off (SwiftUI and UIKit layers, DES and fix); landscape ×1.04 / ×0.98 vs rest; rest after 0 px; seam PASS |
| App-animated resize (`withAnimation` width) during a hold | 0 frames off on 27.0 (DES 3 runs, fix 2); ×0.97 / ×0.98; seam PASS. 17.5: DES one platform frame at q 0.8 (C5b). The fix: 0 (2 runs per lane). All configs and lanes, D69 included: 2 frames per run (at each width animation's end) show the extras row unmagnified while the header is at 1.25 (pre-existing, §11.5 item 10) |
| Dark mode mid-hold | 0 frames off (DES and fix); ×1.04 / ×1.01 vs dark native; rest after 0 px |
| Dynamic Type (accessibility-medium) mid-hold | 0 frames off (DES and fix); ×1.06 / ×1.01 vs its own rest at the new size |
| Background / foreground mid-pull | same pid; 0 frames off (DES and fix); ×1.04 / ×1.01 before and after |
| Two scaling headers (pulled 60 / 120) | 0 frames off; L ×1.05 / ×1.00, R ×1.06 / ×0.95 (D69 ×1.56–1.80); after 0 px |
| `UIViewRepresentable` in the header | `UILabel` / `draw(_:)` / in-place text: crisp, 1:1. Subview replacement: D69's blur (C5b), crisp with the fix. `MTKView`: untouched (0 px). `UIImageView`: `.scaleToFill` untouched, also inserted mid-hold; `.center` stops magnifying (C8), fixed by fix2 |
| SwiftUI `TextField` changing text mid-hold | ×1.13–1.25 in every DES variant (C5b); fix ×0.90–0.92 / ×0.88–0.94 (all-edge ×0.98–1.00) |
| Fast flicks (3 × 3000 pt/s, then a slow pull held 1 s) | 0 of 262–266 magnified frames off 1:1 (D69 226–229), also with a field + `UILabel` in the header (27.0 p / f; 17.5 not run, §11.1) |
| Memory | C15 |
| The user's setup (app banner + aspect refit) | 0 frames off; ×1.05 / ×0.93 (17.5 ×1.02 / ×1.00); seam PASS; after release 0 px |

### 11.4 Repairs tried for C5b / C8 / C10 (scratch flags; not part of the design yet)

- **`-ZTronVerifyPlatWatch 1`** (desw): a synchronous re-apply from a `sublayers` KVO on every raised platform-subtree layer.
  It **fails**. The KVO fires (12 times in 6 s), but the new label's `contentScaleFactor` is 3.0 again right after
  `addSubview` returns, so UIKit resets it during the insertion. Still ×1.61–1.80 (27.0 p / f).
- **`-ZTronVerifyPlatWatch 2`** (desw2 / desng2): the KVO only calls `probe.setNeedsLayout()`, so the write lands in the
  commit's layout phase, after UIKit's insertion.
  - It fixes the density: csf 4.5 0.1 s after each insertion, 0 frames off.
  - The stems stay soft: ×1.30–1.39 / ×1.00–1.03. At write time the new layer has no contents yet, so the filter rule
    skips it and it is drawn bilinear.
- **`+ -ZTronVerifyPlatNeedsDisplay 1`** (**the fix**, desng3): nearest and tie bias also go on a platform layer that has
  no contents but `needsDisplay()`. Results, identical on 27.0 p / f and 17.5:

  | Case | Result |
  |---|---|
  | Replaced `UILabel` | ×0.97–0.98 / ×0.99–1.02 (all-edge ×0.99–1.01 / ×0.97–0.98) |
  | `TextField` changing text | ×0.90–0.92 / ×0.88–0.94 (all-edge ×0.98–1.00) |
  | Static field | ×0.96 / ×1.03 |
  | Frames off 1:1, platform or SwiftUI | 0, in every run: holds, pulls, bg / fg, dark, Dynamic Type, rotation, width (holds and pulls on all three lanes; the attacks on 27.0 p and 17.5) |
  | After release | 0 px |
  | Counters | 1 / 1 / 1 |

  The gravity condition must go as well. des3 (the fix with the condition kept) leaves the field at ×1.41 / ×1.28 static
  and ×1.13–1.15 / ×1.20–1.25 changing.
- **`+ -ZTronVerifyPlatSkipImageCSF 1`** (**fix2** = the fix + no `contentScaleFactor` write on a view whose layer
  holds a `CGImage`), for C8's centred `UIImageView`:
  - the image area matches D69 at the hold (0 px; only the header text differs), on 27.0 p and 17.5 (17.5 also differs
    in its home-indicator rows, as base vs base does);
  - after release 0 px (2 of 2 re-takes; a first take differed only in the home-indicator rows, 861–866 pt);
  - static and inserted `.scaleToFill` image views 0 px in their area;
  - the replaced `UILabel` stays ×0.97–0.98 / ×0.99–1.02 (both lanes); uitick, fieldtick and the platform hold 0
    frames off.
- **`-ZTronVerifyProbeA11yHidden 1`** (SwiftUI `.accessibilityHidden(true)` on both representables): **fails**. On 17.5
  the XCUI tree is identical to DES's, with the same two extra elements.
- **`-ZTronVerifyProbeA11yHidden 2`** (the library's own ambient-copy idiom on both representables:
  `.accessibilityRepresentation { Color.clear.accessibilityHidden(true) }` + `.accessibilityHidden(true)`): **fails**. The
  two elements stay, now at {0, 0, 0, 0}.
- **`-ZTronVerifyProbeA11yHidden 3`** (each probe sets `accessibilityElementsHidden = true` and
  `isAccessibilityElement = false` on its hosting superview, public API, no class test): **fails**. The tree is unchanged.

### 11.5 Amendments this verification asks for (before §5 is accepted)

1. **§4.3 platform row.**
   - Drop "gravity not `.resize`". Without it: `TextField` ×0.96–1.12, draw view ×1.02–1.06.
   - Keep the `CGImage` exclusion and `isOneToOne`; they protect `UIImageView` and rotated content (measured).
   - Extend the `CGImage` exclusion to the `contentScaleFactor` write: no write on a view whose layer holds a
     `CGImage` (C8; fix2 measured).
2. **§4.5, a trigger for UIKit-side changes during a hold** (C5b). Adopt the measured fix:
   - (i) a `sublayers` KVO on every raised platform layer. Its handler only calls `probe.setNeedsLayout()`: a write from
     inside the KVO is undone by UIKit;
   - (ii) the platform filter / tie-bias rule also covers a layer with no contents that `needsDisplay()`.

   A7 gains three rows, each with 0 frames off and crisp bursts: a representable replacing a subview mid-hold; a SwiftUI
   `TextField` whose text changes mid-hold; an app-animated width change with platform views. §8 gains the per-frame
   checker with UIKit layers.
3. **§4.2.** The probes must not reach the accessibility tree (C10). UIKit's flags and SwiftUI's `.accessibilityHidden`
   do not keep them out, nor do `.accessibilityRepresentation` or the host superview's flags (§11.4). Find a probe
   that adds no container, or state the two empty containers in A6. Either way A6's "accessibility tree identical"
   needs the XCUI diff as its test.
4. **A1.** "12 of 12 ≤ 1.05" cannot be met, R2's fix does not address `s` 1.16 (C2), and one mid-animation frame is
   ×1.05–1.06 (C3). Pick one:
   - an acceptance relative to native's own ±0.12 pt envelope, or a phase-averaged ratio;
   - an investigation of why a 1:1 store at `s` 1.16 renders a 1.46 px stem (glyph origin phase inside the store). The
     user's rule says a measured blur is fixed or proven impossible, never closed as a limit.
5. **A5.** Materials **over header text** change by construction (C8). State it, or exclude that case from "0 px".
6. **§1 item 7 / §4.10 / A9.** Count the redraw: about 0.6 ms per pulled frame for a text header, 1.8–2.4 ms median for a
   paragraph, max 5.7 ms at `s` 2.5. Memory grows with `s²` in MB for text-heavy headers. A9's budget should cover the
   total (visit + writes + display).
7. **§4.5 write phase.** M3's planned "layout-only" start showed 1 hitch in 2 of 3 fast pulls and a worst burst of ×1.06;
   "both" showed neither. Keep "both" unless a device run says otherwise.
8. **§4.4 / A2, rotated and scaled text on 17.5** (C4). Find where the 1/255 comes from: either leave the density of
   layers that `isOneToOne` refuses alone (measure how they look held), or prove the redraw identical. Repeat on 15 / 16.
9. **§4.3, needs-display rule.** It decides before the layer has contents. Measured for a `UIImageView` inserted every
   second mid-hold: its contents are set at insertion and it never needs display, so it stays linear (0 px vs D69). A
   view that draws first and receives a `CGImage` later is not covered: add both cases to A7.
10. **Follow-ups outside D76 (pre-existing, D69 too).** (a) and (b) are look differences under the user's rule, so they
    are queued fixes, not limits:
    - (a) During an app-animated width change with platform views in the header, the extras row is drawn unmagnified
      for one frame at each animation's end. Seen on all three lanes, in every config.
    - (b) 27.0 f: extras group B at rest differs by 5909 px (max 2 / 255, pt x 133–173, y 75–95) between the forced and
      preferred paths, in base and DES alike.
    - (c) The seam lab's summary prints FAIL for a recording whose content legitimately runs under a collapsed header
      (fling-hold, C6), although `analyze.py` says to judge it by its jumps. Make the summary apply that rule.

### 11.6 Real iOS 15.0 / 16.0: what the M1 lane must add to §10

1. The per-frame checker (`-ZTronVerifyFrames`, r3 with UIKit layers) on fast and normal pulls and releases, and on every
   §11.3 attack. Pass: 0 frames off 1:1, plus bursts.
2. Layer structure on 15 / 16's renderer:
   - the clip container at rest and while pulled; hops; 0 misses / refusals;
   - the drawing classes (`CGDrawingView` / `CGDrawingLayer`?) and whether `isDrawn` selects them;
   - `Bundle(for:)` of every header class: is 15 / 16's SwiftUI renderer entirely `com.apple.SwiftUI*`?
3. Does 15 / 16's SwiftUI reset `contentsScale` at animation ends or text changes (KVO counts), and are the re-applies
   in-transaction (0 frames off)?
4. The twelve-size table with native ±0.12 pt; `s` 1.16 in particular.
5. Platform views at `s` 1.25 / 1.5 with the fix:
   - `UITextField` on 15 / 16 draws through `UITextFieldLabel` / `_UITextLayoutCanvasView`: which layers are `.resize`,
     which hold a `CGImage`, and whether the `sublayers` KVO fires when 15 / 16 inserts its text views;
   - the C5b cases (subview replacement, `TextField` text change mid-hold, app-animated width).
   - `UIImageView` with `.scaleToFill` and `.center`, static and inserted mid-hold, with fix2 (C8).
6. The accessibility tree with the probes (C10) and with the repair.
7. Rest identity of rotated / `scaleEffect` text after a release (C4: 17.5 is 1/255 off).
8. Rest launches 8× per config at low load: `header.builder` 1 (C7).
9. Cost and memory on A9–A11 hardware with iOS 15, not the simulator. Measure visit + writes + redraw per pulled frame
   for the text header and the paragraph at `s` 1.5 and 2.5, and frame pacing on fast pulls, engine vs off. The redraw
   (C15) is the risk there.


## 12. Gap closure (d76-gaps, 2026-11-04)

An independent skeptic (gap-V) re-measured the three gap reports in `d76-gaps/` (`gap-A.md`, `gap-B.md`, `gap-C.md`, their
patches and `result-gap-*.json`) and ran A + B + C together. 27.0 and most of 17.5 ran 2026-11-04 (stopped at 12:42 by the user's pause, not on a finding);
the 17.5 lock lanes, two 17.5 re-checks, 27.0 A7 and the 18.6 check ran 2026-11-07 on the same build and simulators.
Notes, tables and tools: `d76-gaps/gap-V.md`, `gap-V.patch`, `gap-V-tables/`.

**Method.**
- Scratch worktree at 72ca7fc + `gap-C.patch` (r3 + gap-B + gap-C) + gap-A's lookup-counter hunk; the A-only files are
  byte-identical to `gap-A.patch`'s tree. One build carries every recipe behind its scratch flag, plus gap-V's diagnostics
  (warm-up scope, native counterparts) behind their own flags.
- Configs: **off** = engine absent (D69); **des** = the verified r3 design (FIX2); **all** = des + gap-A `repE` + gap-C
  `RestoreNil` + gap-C warm-up (`-ZTronGapCWarm 2`) = A + B + C.
- Lanes: 27.0 preferred (**p**), 27.0 `-ZTronForceAllFallbacks` (**f**), 17.5; one private simulator per lane, one booted at
  a time. PNGs lossless at 1-min load < 175 (home-indicator rows masked, see 12.11 C1). Timing interleaved, ≥ 3 reps, every
  run's load kept; cost runs only at load < 60. XCUI under the UI lock, the seam lab under the seam + UI locks.
- Harness slip, corrected: an in-process accessibility walk left the app's AX runtime on in the 27.0 p simulator for 30 min;
  the 27.0 p cost comparison was re-run with it off (4 reps) and both are reported.

### 12.1 Verdicts

| Gap | The report says | gap-V finds | Verdict |
|---|---|---|---|
| A — probes in the accessibility tree | fixed by `.accessibilityRepresentation { EmptyView() }` on each probe | XCUI tree and app walk identical to off, probes alive, on every lane | **confirmed** |
| B — A1's phase outliers | A1's reference was wrong (optical size); the engine equals native text of the resting design | ×1.000 and 13/13 identical glyphs vs R(s) at 12/12 sizes and both holds; bursts ≤ ×1.05 phase-normalized; checker 0 | **confirmed** |
| C part 2 — 17.5 rest identity | fixed by `contents = nil` before `setNeedsDisplay` on refused layers | 17.5 all and fix 15/15 0 px, des group E 1–2 px in 3/3; 27.0 p and f 45/45 | **confirmed** |
| C part 1 — cost | A9 impossible for the paragraph as written; native busy ≥ the engine's; warm-up in the header's subtree | visit + writes and warm-up confirmed; "native ≥ engine" refuted run for run; A9 (c) not shown | **partly refuted** |
| A + B + C together (A1–A10) | — | A1, A2, A4, A6, A8 pass on every lane; A3 passes on every lane (17.5 now run); A7 passes on 27.0 p / f and fails on 17.5 in flicks with platform views; A5 fails on 17.5 (launch-dependent look of Canvas and `drawingGroup` text); A9 (c) open on 27.0 p; A10 not built | **partly** |

**Overall: partly closed.** A, B and C part 2 are closed on every lane. C part 1 stays open (A9 (c) on 27.0 p; the
restated (b) holds). The combined run found two 17.5 defects of r3's design that A + B + C neither causes nor fixes (12.7):
platform layers one frame over-dense at flick starts, and a launch-dependent held look of Canvas and `drawingGroup` text.
Both must be fixed before M8b-s9 builds D76 (the user's rule: no measured defect is closed as a known limit).

### 12.2 Gap A — the probes and the accessibility tree

- **Recipe (gap-A's, unchanged).** `.accessibilityRepresentation { EmptyView() }` on each zero-size probe representable
  (an iOS 15.0 API). Never `.accessibilityHidden`, `.accessibilityElement(children: .ignore)` or `.hidden()` on the probe
  or on a probe-only wrapper.
- **27.0 p and f.** XCUI, 32 configs (UI lock 09:06–09:13, load 14 → 6, 0 failures). `repE` and all are identical to off,
  0 lines, at rest, at 60 / 120 pt holds and with a hidden header. des (r3's UIKit flags only) has 2 extra zero-size `Other`
  per tree, which reproduces §11 C10. The app-side walk is identical too. Hit tests equal off in 16/16 pairs. Clip lookups
  are hops 2 only (103–127 per run), with 0 misses and 0 refusals.
- **17.5.** XCUI, 32 configs, preferred and forced (UI lock 11:50–11:58, load 6 → 11, 0 failures): `repE` and all identical
  to off at rest, 60 / 120 pt and with a hidden header (16/16); des +2 zero-size `Other`. App walks identical (16/16).
  Hit tests equal off in 24/24 pairs.
- **The probes stay alive** in the same builds: checker 0 frames off 1:1 (12.3), counters 1/1/1 (12.6 A4).
- **Verdicts.** "Fixed": confirmed on every lane. "No rule text change": confirmed (§5.2 already requires probes that add
  nothing; the orchestrator note's untried leads are moot). The same modifier also removes the D31 anchor's element
  (12.11 PA1, confirmed on 27.0 p).

### 12.3 Gap B — A1's reference

- **Recipe (gap-B's).** No engine change. A1's reference R(s) is the same `Text` laid out natively at resting pt × s with
  `kCTFontOpticalSizeAttribute` = resting pt (demo `-ZTronGapBOpsz`).
- **Twelve sizes 1.04–1.48 and holds at s 1.25 / 1.5**, all vs R(s):
  - 27.0 p (load 5–127) and 27.0 f (6–138): ×1.000 on stems and all edges, h and v; 13/13 glyph components
    pixel-identical at 12/12 sizes and at both holds. Every 27.0 f PNG is 0 px from 27.0 p's.
  - Against native with automatic optical size: ×0.945–×1.293 (the s 1.16 outlier); phase-normalized ×0.982–×1.021.
    D69 vs R(s): ×1.28–×1.80.
  - 17.5 (load 6–10): the same table — ×1.000 and 13/13 at 12/12 and both holds; automatic ×0.945–×1.293;
    phase-normalized ×0.984–×1.023; D69 ×1.28–×1.83.
- **Bursts** (fast 0.3 s, normal 1 s, a 3 s pull; every sampled pulled frame, phase-normalized vs the lane's native curve):
  27.0 p 36 frames, worst ×1.022 (des ×1.010); 27.0 f 32 frames, ×1.015 (des ×1.006); 17.5 39 frames, ×1.026 (des ×1.008). D69 ×1.42–×1.96 (the
  lane calibration holds). Per-frame checker: 0 of 71–159 magnified frames per run off 1:1 (D69: 72–73 of 74–75); 17.5: 0 of 75–159 (D69: 72 of 74).
- **Verdict.** Confirmed on every lane. gap-B's side note on A6 is confirmed too (12.6 A6).

### 12.4 Gap C part 2 — rest identity after the density excursion

- **Recipe (gap-C's).** At every restore path, a layer the 1:1 test refused at its first raise gets `contents = nil`
  immediately before `setNeedsDisplay`, in the same transaction; 1:1 layers keep their contents object.
- **After a 120 pt pull and release**, extras groups A–E × 3 runs × off / des / fix / all (fix = des + `RestoreNil`):
  - 27.0 p: 45/45 engine shots 0 px vs off (load 4–151).
  - 27.0 f: 45/45 (one group-A run launched at load 136–152 caught the release and its engine-off shot differed from the
    other off runs by 14 476 px at the toggle row; re-run × 3 at load ≤ 24: 9/9 0 px, off vs off 0 px).
  - 17.5: all 15/15 and fix 15/15 0 px; des 12/15: group E differs by 1–2 px at 1/255 (pt x 165–171, y 81–82) in 3/3
    runs, which reproduces gap-C's cause; load 6–119 at launch (one shot ended at 214, result 0 px).
- **At rest with the probes installed** (A2), groups A–E, all vs off: 0 px on 27.0 p (load 16–99) and 27.0 f (7–15);
  17.5 (6–9).
- **End of a 120 pt hold and after a fast pull** (2 + 2 runs): all vs off 0 px, off vs off 0 px, counters 1/1/1, on 27.0 p
  and f, and on 17.5 (4/4).
- **Not re-measured:** the release video (gap-C's every-frame check).
- **Verdict.** Confirmed on every lane: the fix is needed on 17.5 (des group E 3/3) and changes nothing elsewhere.

### 12.5 Gap C part 1 — cost, the native reference and the warm-up

Native reference = the same 12-sentence paragraph grown by SwiftUI from 15 to 15·s pt in the same header slot (gap-C's
`-ZTronGapCNativePara`), interleaved with the engine (all) and off runs; busy per changing frame in the 1 s pull and 1 s
release windows.

1. **"Visit + writes meet A9; the first raise is 0.16–1.25 ms with the warm-up."** Confirmed. `-ZTronGapCCost`, normal pulls,
   T / P15 / P25 × 3: 27.0 p median 0.25–0.41 ms, p95 0.37–0.64, max 0.79–1.49, first pulled frame 0.21–0.38 (load ≤ 6);
   27.0 f p95 0.38–0.56, max 0.56–0.81, first 0.17–0.35 (≤ 7); 17.5 median 0.32–0.44, p95 0.46–0.75, max 0.60–1.61, first 0.50–1.24 (≤ 14).
2. **"Native SwiftUI costs as much main-thread time; the native reference's busy is equal to or above the engine's."**
   Refuted run for run (engine total ≤ native, per run and statistic):
   - 27.0 p, AX runtime off, 4 reps, load 4–6: P15 median 2/4, p95 4/4, max 1/4; P25 median 1/4, p95 2/4, max 0/4.
     Without each window's first 2 frames: P15 max 4/4; P25 max 0/4 (mid-pull 6.7–7.6 ms vs native 6.0–7.0).
   - 27.0 p, AX runtime on, 3 reps, load 9–55: P15 2/3, 3/3, 0/3; P25 3/3, 1/3, 0/3.
   - 27.0 f, 3 reps, load 5–9: P15 2/3, 3/3, 1/3; P25 2/3, 2/3, 1/3.
   - 17.5, 3 reps, load 6–13: P15 median 0/3, p95 1/3, max 1/3; P25 median 0/3 (+16–20 %), p95 0/3, max 1/3. gap-C's
     own 17.5 numbers (native 3.6–4.0 vs engine 3.9–4.2) already showed this.
   - On 27.0 the medians are within +1–9 %, on 17.5 +3–20 %. The max is the pull-start frame (11–31 ms; engine-off has it too, 12.11 C2) and, at
     s 2.5, mid-pull frames.
   - What does hold run for run: the engine's **added** busy (all − off) is below native's busy for the same text.
     27.0 p 8/8 (AX off) and 6/6 (AX on), 27.0 f 6/6: medians 1.5–3.3 ms vs native 3.2–4.4; p95 increments 2.3–4.1 vs native
     p95 5.3–5.9. 17.5 6/6: medians 1.87–3.26 vs 3.31–3.59, p95 2.07–3.87 vs 4.28–4.90. That is gap-C's restated A9 (b), and it holds.
3. **"A9 as written (redraw included) is impossible for the paragraph."** Confirmed: native itself runs at p95 4.7–9.6 ms
   for the same text (27.0 p, f).
4. **"Warm-up: found 2 levels up within 8–9 layers; the walk stays in the header's own subtree and never reaches an
   ancestor that contains the outer probe."** Confirmed with one correction:
   - 27.0 p and f, 12/12 launches: found at up = 2 (n 8 for a text header, 29 with extras); visit 0.31–1.42 ms, KVO
     0.54–5.33 ms. The walk's root holds 5 / 26 layers, none below the header and none drawn there; the root's parent holds
     the outer probe. 17.5, 6/6: the same topology (up = 2, root 5 / 24 layers, 0 below the header, parent holds the outer probe); visit
     0.74–7.76 ms, KVO 0.42–1.14.
   - Correction: that root is the parent of §4.2's clip container. At rest the clip container holds 2 layers (it exists only
     while pulled, §11 C11), so the text the warm-up must reach is outside it. §5.2's "a walk of the header's own layer
     subtree only (below the header's clip layer …)" does not cover the warm-up: rule-text delta in 12.9.
5. **"No extra dropped frames vs off"** (gap-C's restated A9 (c); gap-C left it OPEN). Not shown; stays OPEN.
   - 27.0 p, P15 normal × 10 (load 9–179, one run skipped at load > 60): all 1 drop in 9 runs vs off 0 in 10. With gap-C's
     4/25 vs 0/23, pooled 5/34 vs 0/33 (Fisher two-sided p ≈ 0.05); every drop is in the first 4 frames of the pull.
   - 27.0 p fast pulls: runs with a hitch all 6/9 vs off 5/9, all at the pull start. Pooled over every 27.0 p scenario:
     runs with a drop all 11/34 vs off 7/35.
   - 27.0 f: fast all 1 vs off 1 (of 9), normal 0 vs 0. 17.5 (load 5–38): 0 drops in every run and config, P15 normal
     0/13 vs 0/13, fast 0/3 vs 0/3, P25 and T 0/3 vs 0/3 at each speed.
   - No config reaches gap-C's ≥ 20 pulls per scenario and speed except 27.0 p P15 normal (with gap-C's runs).
6. **Memory (A9 (e)).** Footprint after the release, 27.0 p: engine +0.69–0.76 MB vs native +2.40–2.53 (2 reps, load
   10–19); 17.5 engine +6.4–7.6 MB vs native +8.6–9.2 (2 reps, load 15–36; engine-off +0.9–1.0). Footprint ≤ native in
   4/4; the engine's residue over engine-off on 17.5 is 5.5–6.2 MB. Heap by type was not run.

### 12.6 A + B + C in one build: A1–A10 per lane

Config all against engine-off (D69) of the same build, same lane. A1, A2, A6 and A9 are judged on the wording of 12.10;
the result on today's wording is given where it differs. Loads are 1-min averages at the runs.

| # | 27.0 p | 27.0 f | 17.5 |
|---|---|---|---|
| A1 | **pass**: ×1.000, 13/13 glyphs at 12/12 sizes and both holds; 36 burst frames, phase-normalized ≤ ×1.022; checker 0 off 1:1 | **pass**: the same; 32 frames ≤ ×1.015 | **pass**: the same; 39 frames ≤ ×1.026 |
| A2 | **pass** on the rows run: at rest with the probes 5/5 groups, after release 15/15, end of a refresh hold 2/2, after a fast pull 2/2, all 0 px | **pass**: the same rows (release group A re-run at load ≤ 24) | **pass**: the same rows, plus after a rotation at a 120 pt hold 2/2 0 px (off vs off 0 px, counters equal) |
| A3 | **pass**: pull with header text and with content text rows, \|seam\| 0.167 pt, lateral 0, steps ≤ 0.13; fling-hold = D69 (steps 0.19 vs 0.13, overlap as D69) | **pass**: 0.167 / 0 / ≤ 0.07; fling-hold steps 0.30 = D69 0.30 | **pass** (12.7): 6 rows PASS, \|seam\| ≤ 0.5, lateral ≤ 0.31, steps ≤ 0.14; fling-hold = D69 (overlap 71.2 both, steps 0.13 both) |
| A4 | **pass**: 1 / 1 / 1 in 24/24 engine and 24/24 off logs | **pass**: the same | **pass**: `content.body` and `header.content` 1 in 32/32; pulls, holds, releases and a rotation add 0; `header.builder` 2 at launch in 4/32, engine on and off alike (12.11 C6) |
| A5 | **pass**: changes only inside the header (extras row, header text, group D's material over the text), 0 px below it 10/10; all = des 10/10 (per-item: §11 C8) | **pass**: the same, 10/10 | **fails** on the amended A5 (12.10; as written it names neither kind): 0 px below the header 10/10, but the Canvas and `drawingGroup` text take one of two looks per launch with the engine (D69's or another raster, 1.6k–2.8k px, ≤ 247/255), des 2–4 of 4 and all 1–3 of 4 launches per hold; engine-off 12/12 identical (12.7) |
| A6 | **pass**: field ×1.00 / ×1.00 vs the pinned field at `s` 1.25 / 1.5 (today's wording: ×1.09 at 1.25, fails on its reference); rest and restore 0 px; switch / button / field hits equal 16/16; XCUI and app walk identical | **pass**: the same | **pass**: the same; hits 24/24 |
| A7 | **pass** on the rows run: 0 of 404–432 magnified frames off 1:1 (even at \|q − 1\| > 0.005), platform layers 0, 15/15 runs (text every second, text appearing, width change, rotation, dark mode, at a 120 pt hold with a field and a label; load 13–56); engine-off 119–432 of 119–434 at q 0.667. Flicks with field + label: not re-run on the combined build (UI lock contention) | **pass**: the same rows, 0 of 428–432 in 15/15 (load 7–15); engine-off 422–430. Flicks with field + label: §11: 0 of 262–266 (r3) | **fails in flicks**: 8, 7, 11, 13 frames per run (of 267–290) with a platform layer over-dense (q 1.07–1.21) at each flick start (r3's des 6, 9, 9), 12.7; **pass** on the rows run: 0 stale of 428–430 magnified frames per run, platform layers too, 10/10 runs (text every second, text appearing / disappearing, width change, rotation, dark mode, at a 120 pt hold with a field and a label); engine-off 424–428 of 426–431 (q 0.667, calibration) |
| A8 | **pass**: hops 2 only (103–127 per run), 0 misses, 0 refusals | **pass**: the same | **pass**: hops 2 only (120–136), 0 / 0 in 32 logs |
| A9 | (a) **pass**; (b) increment **pass** 8/8 (AX off) + 6/6, total **fails**; (c) **open**: P15 normal 5/34 vs 0/33 pooled with gap-C, every drop in the first 4 frames; (d) not re-measured; (e) footprint **pass** 2/2, heap by type not run | (a) **pass**; (b) increment **pass** 6/6, total **fails**; (c) 9 + 9 runs: fast 1 vs 1, normal 0 vs 0; (d), (e) not run | (a) **pass**; (b) increment **pass** 6/6, total **fails**; (c) 0 drops in every run: P15 normal 0/13 vs 0/13, fast 0/3 vs 0/3, P25 and T 0/3 vs 0/3 at each speed; (e) footprint **pass** 2/2 |
| A10 | **not met by the prototype**: the scope gate admits only `Gesture/UIKit` (5 hits, every one a D76 file); §5.3's extension and the coverage run are not built (§11 C17) | the same | the same |

A7's 17.5 rows run: 2 of 3 rounds (the third was cut on 2026-11-04 to keep the cost lane's interleave).
Not run on any lane: A2 after a morph and A7's morph rows (no morph in 72ca7fc, §11 C18), the release video (A2 gap-C row),
A9 (d) and heap by type.

### 12.7 What §11 could not run: the 17.5 seam rows, the 17.5 flicks and the D69 fling-hold (A + B + C)

Run 2026-11-07 on gV-175 (17.5, iPhone 15 Pro), seam + UI locks, the combined build (all = A + B + C). 1-min load at the
runs: 10–153 for the seam rows, 4–285 for the flick repeats (loads per run in `gap-V.md`). Judged by `seamcheck.py`
(PASS = |seam| ≤ 1 pt, lateral ≤ 1 pt, every 60 Hz jump fraction < 0.5) and the per-frame checker (`-ZTronVerifyFrames`,
a magnified layer is off 1:1 when q < 0.98 or q > 1.02).

| Row (17.5) | all (A + B + C) | D69 (engine off) | Verdict |
|---|---|---|---|
| pull, header text | PASS: \|seam\| 0.167, lateral 0, jumps 0.14 | PASS: 0.167 (overlap 0.167), 0, 0.03 | pass |
| pull, header + content text rows | PASS: 0.167, 0, 0.03 | — | pass |
| rotation at a 120 pt hold | PASS: 0.167 (overlap 0.087), lateral 0.307, jumps ≤ 0.13 | — | pass |
| app-animated width at a 60 pt hold | PASS: 0.167, lateral 0.269, jumps 0.07 | — | pass |
| app banner, refit pull | PASS: 0.5, 0, 0.11 | — | pass |
| fling-hold (the D69 run §11 lacked) | overlap 71.167 pt, gap 0.5, lateral 0, jumps 0.13 / 0.13 / 0.09 | overlap 71.167, 0.5, 0, 0.13 / 0.13 / 0.07 | = D69 (the lab's FAIL is the collapsed header over scrolling content, judged by its jumps, as on 27.0: all 0.19 / 0.30 vs D69 0.13 / 0.30 on 27.0 p / f) |
| flicks, header text | 0 of 267 magnified frames off 1:1 | 230 of 267 (q 0.64–0.77, the calibration) | pass |
| flicks, header text + `TextField` + `UILabel` | **8, 7, 11, 13 off 1:1 per run** (4 runs, 267–290 magnified frames each) | 230 of 267 | **fails** |

**The new 17.5 defect (flicks with platform views).** Every counted frame is a platform layer (the field's or the label's),
**over**-dense, q 1.07–1.21, in the three steepest frames of each flick's start (drawn `s` 1.08 → 1.20 → 1.31, while the
layer's density already equals the next frame's `s`: q·s = 1.20, 1.31, 1.40), 2–3 frames per flick, 3–4 flicks per run.
Another 18–38 frames per run sit at q 1.01–1.02 (platform layers, inside the checker's tolerance). r3's design (des = fix2)
does the same: 6, 9, 9 of 289–290, so A + B + C neither causes nor fixes it. Without platform views 0; on 27.0 p and f
§11 measured the same flicks with a field and a label at 0 of 262–266 (r3's design); they were not re-run on the combined
build (the UI lock stayed with other sessions from 13:25 to 15:06), but the combined build's 27.0 A7 rows show platform
layers 0 off in 30/30 runs. Not load: the first repeat ran at load 4–9 (all 7, des 6). Visual effect not measured in
pixels (a one-frame minification by 0.83–0.93 of the platform text; with the nearest filter it can alias). Under the user's
rules this is a one-frame look difference to fix, not a known limit. Next experiment: log, per platform view, the commit in
which its `contentScaleFactor` write lands against the commit of the drawn transform (`HeaderRasterTick`'s `s` vs the
presentation scale) on 17.5; candidate fixes: write platform views at the layout pass of the frame whose transform is
committed (the 27.0 order), or hold the platform density at min(s_prev, s) on a rising ramp.

**The new 17.5 nondeterminism (A5, held look).** At 60 / 120 pt holds, groups B and C, interleaved off / des / all × 3
(load 87–176, re-taken above 175) plus the 2026-11-04 shots: engine off is identical launch to launch (12/12, 0 px).
With the engine, the Canvas text (group C, pt x 239–309) and the `drawingGroup` text (group B, x 292–352) take one of two
looks per launch: D69's (0 px vs off) or another raster (1 636–2 752 px, up to 247/255, same ink and edge counts, so not
crisper). Changed launches: des 2/4, 2/4, 2/4, 4/4 and all 1/4, 3/4, 1/4, 3/4 (C 60, C 120, B 60, B 120). So "all = des"
cannot be stated on 17.5, and A5's 0 px vs D69 fails for these two kinds there; on 27.0 p all = des 10/10 and both are
deterministic. Not caused by A + B + C (des does it). The shots' logs carry no per-layer decisions, so the cause is not
attributed. Next experiment: per launch, log the visit's decision for those two layers (class, `drawsAsynchronously`,
contents type, `isOneToOne`, filter, tie bias) and find the one that flips.

### 12.8 Design deltas (§4, §7, §8, §10)

Adopt the three reports' design deltas (`result-gap-A.json`, `-B.json`, `-C.json` → `designDelta`) with these changes:

- **§4.5 warm-up (gap-C).** Replace "walk up from the inner probe within the header's own subtree, never to an ancestor
  that also contains the outer probe" with: start at the inner probe's host layer and climb one ancestor at a time; **stop
  before the first ancestor that contains the outer probe's layer** (this is the bound, not a fixed number of ancestors);
  visit that subtree, skipping the probes; observe `contentsScale` on the first non-foreign layer that passes the visit's
  drawn-layer test and invalidate the observation at once; if none is found, do nothing (no retry, no further climb).
  Measured topology: on 27.0 p / f the bound is the clip container's parent (root of 5–26 layers, all inside the header);
  the scratch recipe's cap of 4 ancestors crosses it when the header has no SwiftUI text (17.5: root = the window's
  content, 45 content layers, 3.1–3.5 ms).
- **§4.6 (gap-C).** Keep `contents = nil` on refused layers as gap-C wrote it (reproduced: 17.5 group E, 3/3 without,
  0/3 with).
- **§4.10 (gap-C).** Keep gap-C's split, but replace "Native reference busy is equal to or above the engine's" with: "The
  engine's added busy (engine − engine-off, same scenario) is below native SwiftUI's busy for the same text, run for run
  (27.0 p 8/8 and 6/6, 27.0 f 6/6, 17.5 6/6). The total is not: medians within +1–9 % of native on 27.0 and +3–20 % on 17.5, the max above native in
  most runs (the pull-start frame, pre-existing, and mid-pull frames at s 2.5)."
- **§4.3 / §4.5 (new, 17.5).** Two defects to fix before the build, each with its measured next experiment in 12.7:
  (1) a platform view's `contentScaleFactor` must not run ahead of its drawn transform: on 17.5 the platform layers carry
  the next frame's density for 2–3 frames at each flick's start (q 1.07–1.21); (2) the visit's decision for Canvas and
  `drawingGroup` layers must not depend on the launch: on 17.5 their held look is bimodal (des and all alike).
  §4.3's table must say where Canvas and `drawingGroup` content fall (raise, platform, stop or skip), with the 17.5 layer
  classes measured.
- **§7.** As 12.10.
- **§8.** Add the 17.5 flick run with a `TextField` and a `UILabel` in the header to the per-frame checker lane (0 frames
  off 1:1, platform layers included), and a launch-to-launch identity test of the held look (4 launches per config, groups
  B and C at 60 / 120 pt). Add to gap-C's hosted warm-up test: a header with no SwiftUI text (the walk stops below the outer probe's
  ancestors, observes nothing, writes nothing). Add the native counterparts used here as demo scenes: the opsz-pinned
  `TextField` reference (A6), the native paragraph and the native `.scaleEffect` reference (A9, pre-existing C2).
- **§10 (the M1 Mac's 15.0 / 16.0 lane).** Add: flicks with a field and a label in the header through the per-frame
  checker (17.5 fails there, 12.7; 15 / 16 run the same fallback path); the held look of groups B and C over 4 launches
  per config (bimodal on 17.5); `-ZTronSeamStart collapsed` with the app banner (18.6 hides it, 17.5 / 27.0 leave 52–91 pt,
  12.11 PA5); the probes' masked XCUI diff (gap-A); the twelve-size table against R(s) (gap-B); 17.5 group E after release
  without and with `contents = nil` (gap-C); the warm-up scope on 15 / 16 for a text header and a header without text (root, layer count, outer probe);
  the A6 field against the opsz-pinned field; A9 (b) as an increment, run for run.

### 12.9 (a) §5 rule-text deltas (exact)

1. **§5.2, `Allowed there` bullet** — replace
   > a walk of the header's own layer subtree only (below the header's clip layer, found from the inner probe and refused
   > when it also contains the outer probe);

   with
   > a walk of the header's own layer subtree only (below the header's clip layer, found from the inner probe and refused
   > when it also contains the outer probe), and once per process, at rest and outside any animation, a read-only walk of
   > the subtree of the highest ancestor of the inner probe that does not contain the outer probe;
2. **§5.2, same bullet** — replace
   > and `setNeedsDisplay`;

   with
   > and `setNeedsDisplay`; `contents = nil` immediately before that `setNeedsDisplay`, in the same transaction, when a
   > layer whose store did not map 1:1 is restored;
3. **§5.2, same bullet** — replace
   > key-value observation of `contentsScale` on the layers it changed

   with
   > key-value observation of `contentsScale` on the layers it changed and, once per process from the read-only walk, on
   > one SwiftUI-drawn layer, invalidated at once
4. **§5.3, scope gate** — replace
   > no assignment to a layer or view property other than `contentsScale`, `magnificationFilter`, `minificationFilter`,
   > `contentsRect`,

   with
   > no assignment to a layer or view property other than `contentsScale`, `magnificationFilter`, `minificationFilter`,
   > `contentsRect`, `contents` (only as `contents = nil`),
5. **§5 orchestrator note, third bullet** (not rule text): "Untried leads: `isHidden` on the probe's host view, and SwiftUI's
   `.hidden()`" → "Resolved by gap-A: `.accessibilityRepresentation { EmptyView() }` on the probe; `isHidden` leaves both
   nodes and is not an allowed write; `.hidden()` stops the engine."

No other rule text changes: gap-A's recipe and gap-B's reference are inside the current text.

### 12.10 (b) Acceptance criteria to change (§7)

- **A1** — replace with gap-B's text (reference R(s) = native text at resting pt × s with its optical size pinned to the
  resting pt; (a) every glyph component pixel-identical to R(s) after whole-pixel alignment, n of n, at the 12 sizes and both
  holds; (b) every pulled frame of fast, normal and 3 s pulls and their releases phase-normalized ≤ 1.05 on stems and all
  edges, h and v, with the lane calibration (native ×0.96–×1.04, D69 ≥ ×1.25) and 0 checker frames off 1:1; (c) the raw
  ratio against automatic optical size reported, not judged). Measured passing on 27.0 p, 27.0 f and 17.5.
- **A2** — add gap-C's rows: "17.5 group E (rotated 12° and 0.75-scaled text) after release: 0 px" and "the release video
  shows the header's text in every frame of the restore". The video row was not re-measured here.
- **A6** — replace "`TextField` text ≤ 1.05 at `s` 1.25 and 1.5 (vs the resting field)" with "`TextField` text vs a native
  field at 17·s pt with its optical size pinned to 17 (the R(s) of platform text): every stem and all-edge ratio ≤ 1.05,
  h and v, at `s` 1.25 and 1.5". Measured ×1.00 / ×1.00 on 27.0 p, 27.0 f and 17.5; against the resting field the same pixels
  are ×1.09 at `s` 1.25, so A6 as written fails on the reference, not on the engine. Replace "accessibility tree identical"
  with gap-A's masked XCUI diff (0 lines vs `-ZTronForceRasterDensityOff 1` at rest, 60 / 120 pt holds, a banner hold and a
  hidden header; preferred, forced and observer-forced) plus the in-process walk, with the probes alive in the same runs.
- **A9** — replace with:
  > (a) engine visit + writes ≤ 2 ms p95 and ≤ 4 ms max per pulled frame, the first pulled frame included (warm-up on);
  > (b) the engine's added main-thread busy per pulled frame (engine − engine-off, same scenario, interleaved, ≥ 3 reps,
  > load < 30) ≤ native SwiftUI's busy for the same text grown to pt·s, at the median and p95, run for run (the max is
  > bounded by (a) and (c): the pull-start frame varies 10–30 ms between engine-off runs, so differences of maxima are noise);
  > (c) no extra dropped frames vs engine-off, ≥ 20 pulls per config, fast and normal, load < 30, each drop attributed to
  > its interval; (d) stores ≤ s² × rest + 5 %; (e) after the release, no engine-owned live allocation (heap by type) and a
  > footprint ≤ the native reference's after its animation.

  This is gap-C's (a)–(e) with (b) stated as the increment it measures. Do not state (b) as "total ≤ native": the total
  fails run for run (12.5 item 2) because of the engine-off pull path (12.11 C2). (c) is not met yet (12.5 item 5).

- **A5** — add: "Canvas and `drawingGroup` content: one look per config, identical over 4 launches at each hold (groups B and
  C at 60 / 120 pt), and 0 px vs off where §4.3 classes the layer *skip* or *stop*". As written, A5 names neither kind, so
  17.5's launch-dependent look (12.7) slips through it; on the amended A5 it fails on 17.5 and passes on 27.0 p.
- **A7** — add the row "finger flicks (3 × 3000 pt/s, then a slow pull held 1 s) with a `TextField` and a `UILabel` in the
  header: 0 magnified frames off 1:1 (q outside 0.98–1.02), platform layers included". §11 ran it as an attack only; it
  fails on 17.5 (12.7).

No change to A3, A4, A8, A10.

### 12.11 Pre-existing findings, classified (engine absent, on the lane where each was seen, against a native counterpart)

Classes: **ztron defect** (native differs), **native behaviour** (native does the same), **harness artefact**, **unclassed**.
Native counterparts are demo scenes without ZTronScrollView (`-ZTronScreen gvnative`, `-ZTronGVNativeScale`, gap-C's native
paragraph).

| # | Claim (source) | Class | Lanes | Numbers |
|---|---|---|---|---|
| PA1 | The D31 anchor adds a zero-size element (gap-A 1) | ztron defect | 27.0 p, f, 17.5 | +1 `Other {0,62,0,0}` (27.0), `{0,59,0,0}` (17.5) with `-ZTronForceUIKitObserver`; a native header lists none. The empty representation on the anchor removes it: 0 lines (27.0 p, 17.5) |
| PA2 | The header background's accessibility idiom leaves an unlabelled element (gap-A 2) | ztron defect | 27.0 p, f, 17.5 | `Other {0,0,0,0}` without a background, `{0,-11,402,313}` / `{0,-9.3,393,308.3}` with the ambient one; a native header with a plain background lists none; the same idiom in plain SwiftUI adds `{0,62,402,240}` / `{0,59,393,240}`; an empty representation removes it |
| PA3 | The header's `.contain` container spans the viewport at rest (gap-A 3) | ztron defect | 27.0 p, 17.5 | `{0,62,402,778}` / `{0,59,393,759}` vs a native `.contain` header `{0,62,402,240}` / `{0,59,393,240}`; VoiceOver impact unmeasured |
| PA4 | A hidden header's controls stay in the XCUI tree, hittable, and taps do nothing (gap-A 4) | ztron defect | 27.0 p, f, 17.5 | switch 1→1, button Tap 0→0, hittable = true at unclipped frames y 124–128 (27.0) / 67–72 (17.5); a native header scrolled past: hittable = false at its real frame (y −450 / −455); a native zero-height clipped header: absent |
| PA5 | `snapHeader(to:)` collapsed before the first layout leaves the banner partly shown (gap-A, PROGRESS 08:47) | ztron defect (OS-dependent) | 27.0 p, 17.5, 18.6 | the banner stays 52 pt (27.0; pixels 2026-11-07: red image pt y 116–168, 2/2 launches, load 11–15) / 90.7 pt (17.5, walk) tall and its controls act; on 18.6 it is hidden fully (0 red rows, 2/2 launches, load 111–153), which reproduces gap-A; a native scroll view started past the header shows 0 pt; the API doc says it is applied at the first layout. gap-A's "does not take" is an under-collapse, not a no-op |
| B1 | D69's bitmap at s 1.08 differs between launches (gap-B 1) | unclassed | 27.0 p, f | not reproduced: 0 px in 5 + 4 launches (load 5–20); native `.scaleEffect(1.08)` 0 px in 4/4 |
| C1 | Home-indicator rows differ between runs (gap-C 1) | harness artefact | 27.0 f, 27.0 p, 17.5 | 6 452 px, max 124/255, pt y 861–866 (27.0 f; 27.0 p in 1 of 10 hold pairs); 17.5 rows 839–844; a system overlay's adaptive luminance, never app rows; masked |
| C2 | The engine-off pull-start frame is expensive (gap-C 2) | ztron defect | 27.0 p, f, 17.5 | first pulled frame busy, engine off: 27.0 p 9.8–29.0 ms (16 runs), 27.0 f 4.5–20.3; a native `.scaleEffect` magnification in the same slot, same interleaved runs: 0.2–4.5 (median 2.6–3.0), 0 drops; native font growth 1.0–12.0. 17.5: off 3.0–8.0 ms vs native `.scaleEffect` 0.9–1.9 and font growth 0.5–0.9 |
| C3 | A native paragraph animation leaves footprint (gap-C 3) | native behaviour | 27.0 p, 17.5 | native +2.40–2.53 MB after it ends (2 + 2 runs); engine-off −0.1 to −0.2; engine +0.69–0.76. 17.5: native +8.6–9.2 MB, engine-off +0.9–1.0, engine +6.4–7.6 |
| C4 | Host stalls of 100–700 ms during load spikes (gap-C 4) | harness artefact | all | 1-min load reached 211 (10:30) and 214 (11:37) from other sessions; cost runs gated at < 60 and one 27.0 p run skipped; screenshots re-taken above 175 |
| C6 | (new) 17.5: `header.builder` runs twice at launch in 4 of 32 launches, engine on and off alike (gap-V, A4) | unclassed | 17.5 | 0 of 48 launches on 27.0; already 2 at the first sample (t 0.8–2.0 s, before any pull), unchanged by pulls, holds and releases. No native counterpart exists for the builder closure; the next check is a native `ScrollView` with the same header view counting its body runs at launch over 32 launches |
| C5 | (new) 27.0 f, extras group A, one engine-off run differs from the other two by 14 476 px at the toggle row (gap-V) | harness artefact | 27.0 f | the launch ran at load 136–152 and the shot caught the toggle row mid-animation; re-run × 3 at load ≤ 24: off vs off 0 px |

Queue PA1–PA5 and C2 as fixes outside D76 (the user's rule: a measured difference is fixed or proven impossible).

### 12.12 New risks

1. **The warm-up's bound is not in the scratch recipe.** It climbs a fixed 4 ancestors; with a header without SwiftUI
   text it crosses the outer probe and walks 45 content layers (17.5, 3.1–3.5 ms). The design must stop at the outer probe
   (12.8, 12.9), and §8's hosted test must include a text-less header.
2. **Warm-up cost on 17.5** was 0.7–7.8 ms visit + 0.4–1.1 ms KVO in one launch each (ext-2: 8.9 ms): it must stay out of
   appearance animations (gap-C's risk, now measured on the slow end).
3. **A9 (c) is open:** pull-start drops 27.0 p P15 5/34 vs 0/33 pooled with gap-C; 27.0 f and 17.5 show no extra drops
   (fast 1 vs 1 of 9; 17.5 0 in every run), but no lane reaches 20 pulls per config and speed except 27.0 p P15 normal.
4. **The total busy is above native at the pull start** because of C2; D76 inherits it until C2 is fixed.
5. **UIKit platform text other than `TextField`** (`UILabel` ×1.07–1.08, a `draw(_:)` view ×1.06 at s 1.25 against native
   with automatic optical size) has no pinned reference yet; A6 covers only the field.
6. **Harness:** an in-process accessibility walk leaves the app's AX runtime on in that simulator and shifts cost numbers;
   cost lanes must reset `ApplicationAccessibilityEnabled` first. `vcost.sh`'s pace mode reused another mode's labels.
7. **17.5 platform views at flick starts** (12.7): 2–3 frames per flick over-dense by 7–21 %, r3's design included; the
   pixel effect is unmeasured and 15 / 16 run the same path.
8. **17.5 held look of Canvas and `drawingGroup` text depends on the launch** (12.7); the cause is not attributed.
9. **Harness:** zsh does not split an unquoted argument string, so a launch with `$A` passes one argument; use `${=A}` or
   an array (one discarded 27.0 run).

### 12.13 User ruling (2026-11-07)
- **Accepted:** the §5 rule-text deltas of 12.9 (items 1–4; item 5 is the orchestrator note) and the §7 criteria changes of 12.10.
- **Not acceptable:** a total main-thread cost above native. The engine's total on 17.5 (+16–20 % at P25's median) must be cut.
  A9 therefore also gets **(b′)**: the engine's TOTAL busy per pulled frame (engine on, same scenario, interleaved, ≥ 3 reps, load < 30)
  ≤ native SwiftUI's busy for the same text grown to pt·s, at the median and p95, run for run, on every lane; and the pull-start frame
  (12.11 C2, pre-existing) ≤ native's. (b), the increment, stays as well.
- The cost work runs as the d76-cost spike (notes in d76-cost/) before the M8b-s9 build.

## 13. Cost cut (d76-cost, 2026-11-07)

The cost spike (cost-K: `d76-cost/cost-K.md`, `cost-K.patch`) tried to bring the engine's total main-thread busy to
native's (12.13, A9 (b′)). An independent skeptic (cost-V: `d76-cost/cost-V.md`, `cost-V.patch` = cost-K.patch, tools
and tables in `cost-V-tools.tgz` / `cost-V-tables.tgz`) re-measured it on its own simulators (v-27 iPhone 18 Pro 27.0,
v-175 iPhone 15 Pro 17.5, one booted at a time, appearance light, `ApplicationAccessibilityEnabled` 0), interleaving
N / NT / off / all / K per rep, ≥ 3 reps per lane and speed, every run at a 1-min load < 30 (5–29; one retake).

- **Configs.** all = the gap-V engine (A + B + C, 12.6). K = all + the cut (`-ZTronCostFast 1 -ZTronCostLazyDebug 1
  -ZTronCostNoFade 1`). off = engine absent. N = the paragraph grown natively 15 → 15·s pt inside the seam lab (gap-C's
  reference; its 24 pt title is **not** grown). NT = a standalone native header whose title and paragraph both grow (the
  same visual as the engine's header). NSV = NT inside a native `ScrollView` whose header height grows to 240·s.
- **Meter.** Busy per display-link frame in the 1 s (normal) / 0.3 s (fast) pull and release windows; start = the max
  of the first 3 pull frames; drop = an interval > 25 ms in the windows. Pull 1 s after appear unless "late" (4 s).

### 13.1 Verdict

**Partly.** The spike's outcome ("A9 (b′) not met, open") is confirmed on every lane, in Debug and in Release. The cut
is regression-free on every row re-measured (13.4) but buys ≤ 0.2 ms per frame in shipping code: it is hygiene, not the
cut 12.13 asks for. (b′) fails on every lane at the pull-start frame (27.0: C2, pre-existing; 17.5: the engine's first
raise) and on 17.5 also at the median and p95 against N. Against NT (the same visual) the medians pass in most runs.

### 13.2 Claims

| Claim (cost-K) | Status | cost-V evidence |
|---|---|---|
| (b′) not met; outcome open | confirmed | 13.3: start frame fails on every lane; 17.5 median vs N P15 0/4, P25 1/4 |
| 27.0 p / f: level with native within ±10 %, not ≤ run for run | partly | medians −28 … +23 % vs N; p95 of fast P25 pulls above N in 6/6 runs (+5 … +62 %) |
| 17.5 P25 +10–20 % over N, ≤ NT in most runs | confirmed | +10 +29 −13 +6 % (normal), +5 +2 +9 % (Release), −1 +5 +1 % (late); ≤ NT 4/4, 3/3, 3/3 |
| C2: 27.0 engine-off start frame 12–25 ms at a 1 s pull vs native 2–6 | confirmed, and present in Release | Debug off start 4.4–21.0 (p / f), Release 8.4–28.2; K 10–19; N 1.6–5.2 |
| With the pull at 4 s, K's start ≤ N in 5/6 | **refuted (number)** | 27.0 p late: 3/6 (P15 2/3, P25 1/3) |
| 20 P25 normal pulls at 1 s: K 5 drops vs N 0 | **not reproduced** | normal: K 0, off 1, N 0, all 0; fast: K 2 (both at the start frame), off 5 (4 runs), N 0, all 1 |
| The cuts save 0.1–0.2 ms per frame (profile) | confirmed | 17.5 profile, 2 reps, load 6–9: engine + debug + KVO −0.19 (P15) / −0.16 (P25) ms; SwiftUI graph (K5) −0.09 / +0.14 (noise) |
| The cuts are not separable in busy on 17.5 normal | **refuted** | Debug: K ≤ all in 15 of 17 runs (−1 … −24 %); Release: not separable (0 −12 −1 / +20 −3 +4 %): the visible part is K4 (DEBUG only) |
| No regressions | confirmed | 13.4, three lanes |
| K6 re-applies 91 resets on 27.0 p / f, none on 17.5 | partly | 91 / 91 confirmed; 17.5 had 2 (extras group A at the pull end), re-applied, A2 0 px |
| A3 on 27.0 p with `kcut` PASS | confirmed | 5/5 PASS, fling-hold = D69 (13.5) |

### 13.3 A9 per lane (cut build K; per-rep ratios K / native − 1)

| Lane | (a) visit + writes | (b) K − off ≤ N | (b′) med ≤ N | (b′) p95 ≤ N | (b′) start ≤ N | med ≤ NT | (c) drops | (d) | (e) after release |
|---|---|---|---|---|---|---|---|---|---|
| 27.0 p normal | P15 med 0.28 p95 0.39 max 1.02 first 0.21; P25 0.19 / 0.37 / 1.25 / 0.24 ms | 8/8 | P15 2/4 (+7 −13 +2 −6), P25 4/4 (−2 −4 −28 −0) | 4/4, 2/4 | **0/4, 0/4** (K 10.0–15.6 vs N 1.6–4.5) | 2/4, 3/4 | 20 P25: K 0, off 1, N 0, all 0 | ≤ s²·rest + 0.08 % | K +0.70 / +0.74 MB vs N +2.62 / +3.90 |
| 27.0 p fast | — | 5/6 | 1/3 (+0 −11 +23), 1/3 (+91 +6 −2) | 1/3, **0/3** (+31 +30 +10) | **0/3, 0/3** | 2/3, 2/3 | 20 P25: K 2 (start), off 5, N 0, all 1 | — | — |
| 27.0 p late (4 s) | — | 6/6 | 2/3 (−5 −2 +15), 2/3 (−11 +1 −4) | 3/3, 2/3 | 2/3, 1/3 | 3/3, 2/3 | 0 | — | — |
| 27.0 p Release | — | — | n: 2/3, 3/3; f: 1/3, 0/3 (+51 +30 +4) | n: 3/3, 2/3; f: 3/3, 0/3 | **n 1/3, 0/3; f 0/3, 0/3** | n 2/3, 3/3 | n: K 1, off 2, all 4, N 0 (6 runs each) | — | — |
| 27.0 f normal | P15 0.24 / 0.38 / 0.57 / 0.23; P25 0.21 / 0.35 / 0.50 / 0.21 | 6/6 | 3/3, 2/3 (−8 −11 +5) | 3/3, 1/3 | **0/3, 0/3** | 3/3, 3/3 | 0 in 6 | ≤ + 0.08 % | K +0.57 MB vs N +3.99 |
| 27.0 f fast | — | 6/6 | 2/3, 2/3 | 1/3, **0/3** (+62 +34 +5) | 1/3, 1/3 | 2/3, 3/3 | K 1 in 6 (start) | — | — |
| 17.5 normal | P15 0.33 / 0.47 / 0.82 / 0.82; P25 0.29 / 0.45 / 0.81 / 0.59 | 7/8 | **P15 0/4 (+0 +10 +22 +91), P25 1/4 (+10 +29 −13 +6)** | 1/4, 0/4 | **0/4, 0/4** (K 4.6–11.4 vs N 2.0–3.8) | 3/4, 4/4 | 0 | ≤ + 0.08 % | K +4.86 / +7.35 MB vs N +7.92 / +8.53 |
| 17.5 fast | — | 5/6 | 2/3, 1/3 (−17 +65 +19) | 2/3, 0/3 | 1/3, 0/3 | 3/3, 2/3 | 0 | — | — |
| 17.5 late (4 s) | — | 6/6 | 0/3 (+7 +3 +32), 1/3 (−1 +5 +1) | 3/3, 0/3 (+9 +8 +10) | 0/3, 1/3 (K 3.6–5.5 vs N 3.0–4.2) | 3/3, 3/3 | 0 | — | — |
| 17.5 Release | — | — | n: 2/3, 0/3 (+5 +2 +9); f: 3/3, 1/3 | n: 2/3, 2/3; f: 3/3, 1/3 | **0/3, 0/3** both speeds | n 3/3, 3/3 | 0 | — | — |

(a) passes everywhere (p95 ≤ 0.47, max ≤ 1.25 ms, first pulled frame ≤ 0.82 ms). (b) passes except against two low N
outliers (N15 2.03, N25 2.09). (c) as written (vs engine-off) passes on 27.0 p: K 2 / 40 pulls vs off 6 / 40 (5 runs);
against native K 2 vs N 0. (d) is the engine's own byte formula (as gap-C), not a measured store. (e) footprint ≤ native
5/5; heap by type not run.

### 13.4 Cost table (busy ms per pulled frame; ranges over reps; med / p95 / start; loads 5–29)

| Lane, scenario | N | NT | off | all (before) | K (after) |
|---|---|---|---|---|---|
| 27.0 p normal P15 | 3.65–3.96 / 4.91–5.54 / 1.6–4.0 | 3.23–4.28 / 5.60–5.93 | 0.93–1.22 / 1.38–1.66 / 4.4–13.6 | 3.45–3.98 / 4.38–4.97 / 3.3–16.7 | 3.44–3.94 / 4.37–4.97 / 10.0–14.8 |
| 27.0 p normal P25 | 3.97–4.12 / 5.26–5.52 / 3.7–4.5 | 4.01–4.41 / 5.83–6.37 (NSV 4.03–4.35, start 4.7–5.2) | 1.08–1.45 / 1.44–2.11 / 4.9–11.8 | 3.63–4.14 / 5.20–5.73 / 5.4–23.2, 2 drops | 2.85–4.10 / 4.91–5.82 / 10.3–15.6 |
| 27.0 p fast P25 | 2.09–3.97 / 4.44–5.29 / 2.5–4.6 | 3.86–4.16 | 1.19–1.23 / start 10.5–11.1 | 3.84–4.21 / 6.21–7.51 / 12.0–21.1 | 3.83–4.21 / 5.81–6.33 / 10.3–18.7 |
| 27.0 p late P25 | 4.00–4.13 / 5.16–5.54 / 2.9–4.0 | 3.94–4.15 | 1.08–1.81 / start 1.0–5.2 | 3.74–4.12 / 4.83–5.00 / 1.9–3.6 | 3.67–4.06 / 4.96–5.64 / 1.8–7.2 |
| 27.0 f normal P25 | 3.51–4.64 / 5.00–5.87 / 3.4–5.6 | 3.94–4.73 | 1.18–1.20 / start 1.3–11.6 | 3.48–4.24 / 5.11–5.66 / 5.6–14.1 | 3.68–4.12 / 5.54–6.00 / 14.1–15.8 |
| 27.0 f fast P25 | 3.80–3.97 / 4.62–5.71 | 4.00–4.50 | 1.10–1.55 / start 11.1–16.9 | 3.16–3.53 / 5.28–6.52 / 12.2–21.6 | 3.34–3.84 / 5.65–9.23 / 1.8–18.7 |
| 17.5 normal P15 | 2.03–3.44 / 2.90–4.69 / 2.0–3.6 | 3.05–4.10 | 0.77–1.19 / start 3.7–4.7 | 3.81–4.06 / 4.92–5.15 / 1.7–5.4 | 3.41–3.87 / 4.39–5.08 / 4.7–7.6 |
| 17.5 normal P25 | 3.03–3.64 / 4.25–4.97 / 2.6–3.8 | 3.93–4.45 / 5.36–5.83 | 1.11–1.18 / start 3.8–4.7 | 3.86–4.18 / 5.21–5.71 / 5.3–6.9 | 3.18–3.90 / 4.84–5.31 / 4.6–11.4 |
| 17.5 late P25 | 3.74–4.05 / 4.88–5.02 / 3.0–3.8 | 4.02–4.53 | 1.21–1.59 / start 2.4–3.4 | 4.01–4.07 / 5.51–5.87 | 3.93–4.00 / 5.35–5.49 / 3.6–4.2 |
| 17.5 Release normal P25 | 3.83–3.87 / 4.93–5.37 / 2.6–3.1 | 4.19–4.58 | 1.09–1.43 / start 4.2–5.3 | 3.36–4.08 / 4.83–5.39 / 2.1–4.6 | 3.89–4.22 / 5.04–5.42 / 3.9–6.8 |
| 27.0 p Release normal P25 | 4.07–4.45 / 5.50–6.35 / 3.8–5.2 | 3.92–4.43 | 1.26–1.44 / start 13.5–28.2 | 3.85–3.97 / 5.11–5.81 / 16.0–27.0, 3 drops | 2.67–4.13 / 5.32–5.65 / 16.5–20.3 |

Every config and scenario (P15 / P25, normal / fast, max and drops): `cost-V-tables.tgz:compact.txt`.

**Where the excess sits (17.5 profile, ms per window frame):** K = display of both raised texts 1.8–2.5 + SwiftUI
graph 0.6–0.7 + engine 0.3 + KVO 0.1 + commit / UIKit 0.4; N = display of the paragraph 1.3–1.8 + text layout in the
graph 1.3–1.5. The off path (1.0–1.5 ms) is unchanged in Release (17.5 P25 off 1.09–1.43 vs Debug 1.11–1.18), so it is
SwiftUI / AttributeGraph work, not unoptimized ZTron Swift. N does not redraw the title; the engine does (0.3–0.6 ms):
against N the engine carries a structural excess that no cut keeping both texts crisp can remove, against NT it does not.

### 13.5 Regressions on the cut (all + KF vs all, same build)

| Row | 27.0 p | 27.0 f | 17.5 |
|---|---|---|---|
| A1 twelve held sizes 1.04–1.48 | 12/12 0 px | 12/12 0 px | 12/12 0 px |
| A1 checker, fast + normal P15 + normal P25 × 2 | 0 of 768 magnified frames off 1:1 | 0 of 775 | 0 of 785 |
| A2 groups A–E after a 120 pt pull + release, and at rest | 0 px ×5, 0 px ×5 | 0 px ×5, 0 px ×5 | 0 px ×5, 0 px ×5 |
| A3 seam rows (`kcut`) | **PASS** 5/5: \|seam\| ≤ 0.5, lateral ≤ 0.42, jumps ≤ 0.12; fling-hold = D69 (overlap 76.7 vs 78.0 pt, jumps 0.19 / 0.19 / 0.07 both) | not run (locks) | **PASS** 5/5: \|seam\| ≤ 0.5, lateral ≤ 0.27, jumps ≤ 0.13; fling-hold = D69 (overlap 74.5 vs 77.3 pt, jumps 0.13 / 0.13 / 0.07 both) |
| A4 rest / h60 / pull / fast / end-of-hold, off and K | 1/1/1 | 1/1/1 | 1/1/1 |
| A6 field / UILabel / draw view, 60 / 120 pt | 0 px ×6 | 0 px ×6 | 0 px ×6 |
| A7 rows at a 120 pt hold with field + label (text tick, appear, width, rotation, dark) | K 0 off in 10/10 (417–432 magnified each), all 0 in 5/5 | not run | K 0 in 10/10, all 0 in 5/5 |
| A7 flicks with field + label (q outside 0.98–1.02) | K 0, 0 of 247–264; all 0, 0; off 227 | not run | K **9, 11** of 265, all 10, 10 of 266 (q 1.02–1.11, over-dense at flick starts), off 229: **the 12.7 defect is unchanged by the cut** |
| A8 | hops 2, no miss / refusal | same | same |
| K6 re-applies | 91 resets | 91 | 2 |

Not re-measured: A1 pixel bursts (the checker and the twelve sizes stand in), A5.

### 13.6 Recipe to fold into §4 (only as hygiene; it does not meet (b′))

1. **§4.4 / §4.5 (engine), K2:** one 1:1 test per layer per pass, reused for the filter decision only when nothing
   changes the density between the two (no rounding, bias or quantisation step); store-byte accounting only in
   diagnostics; the container lookup walks the boundary's superlayers instead of building an ancestor set (same clip,
   hops and refusal); launch flags read once.
2. **§4.5, K6:** `observe(\.contentsScale, options: [])`, the handler reads the layer's value; still synchronous,
   still ignoring the engine's own flagged writes.
3. **HeaderFrameModifier (K5):** a fade that draws nothing gets a constant `HeaderLiveInput`. Only with the risk of
   13.11 item 1 closed first.
4. **ContentTransform (K4):** DEBUG only; it changes Debug measurements, not shipping cost.
5. Not to fold: K1 (layout-phase-only writes; changes §4.5's timing, gain not separable).

### 13.7 §5 rule-text deltas

None. K2, K4, K5 and K6 add no UIKit write, observation or API outside 12.9's accepted text (`contentsScale` KVO
options are not part of the rule text).

### 13.8 §7 criteria changes (for the user; none adopted here)

1. **Name (b′)'s native reference.** 12.13 says "the same text grown to pt·s"; the engine magnifies the title and the
   paragraph, N grows only the paragraph, NT grows both. Either NT is the reference (the same text; over every run of 13.3, K ≤ NT at the median in 62 of 76,
   the p95 in 57 of 76, the start frame in 22 of 76; K ≤ N in 38, 39 and 8 of 76), or N stays and (b′) is unreachable
   by construction for a header with more than one text.
2. **State (b′) statistically.** At the meter's measured spread (±10–15 % run to run at load < 10, plus whole low-busy
   reps in native and engine runs alike, 13.3), two identical distributions pass a strict run-for-run ≤ over n reps
   with probability 2⁻ⁿ (1/8 at 3 reps); over all 76 paired runs here K ≤ N at the median in exactly 38. Proposal: paired runs, ≥ 8 reps, a one-sided sign test at 5 % (K above native
   in ≥ 7 of 8 pairs fails), plus pooled medians and p95 ≤ native.
3. **Pull-start frame.** Keep 12.13's "≤ native's", measured at both a 1 s pull (C2 row) and a ≥ 3 s pull; a fast-pull
   p95 row (it fails on both 27.0 lanes where normal pulls pass).
4. **A2 reference.** Compare against engine-off without the cut's flags (reg.sh compared off + KF vs all + KF).

### 13.9 Real iOS 15.0 / 16.0 (the M1 lane)

1. Interleaved busy runs N / NT / off / all / K, P15 / P25, normal and fast, ≥ 3 reps (8 for a sign test), load < 30,
   in Debug and Release: (b) and (b′) per run, with the reference of 13.8 item 1 stated.
2. The pull-start frame at a 1 s and a 4 s pull, engine off vs native (C2 on 15 / 16), and K vs off (the engine's first
   raise; 17.5 has it even at 4 s).
3. 20 P25 pulls per config, normal and fast, K / off / N: drops with their frame.
4. K6: count `RASTER kvo reset` lines; every reset re-applied (checker 0 off 1:1).
5. The cut's regression rows: twelve sizes all vs all + KF, checker, A2 A–E, A4, A6, A7 rows, and the flicks with a
   field and a label (17.5 fails there, 13.5; 15 / 16 run the same path).
6. K5: a fade switched on during an animated pull (13.11 item 1).

### 13.10 Pre-existing findings, classified

| # | Finding | Class | Lanes | Numbers |
|---|---|---|---|---|
| V1 | C2: the first pull ≤ 2 s after appear costs a 4–28 ms start frame with the engine off | ztron defect | 27.0 p, f; Debug and Release | off start Debug 4.4–21.0, Release 8.4–28.2 vs N 1.6–5.2, NSV 4.3–5.2; at 4 s off 1.0–5.2 |
| V2 | 17.5 start frame with the engine is above native even at a 4 s pull | ztron (D76 engine's first raise), not pre-existing | 17.5 | K 3.6–5.5 vs off 2.3–4.2 vs N 3.0–4.2 (late); 4.6–11.4 vs N 2.0–3.8 at 1 s |
| V3 | 17.5 platform layers over-dense at flick starts (12.7) | ztron (r3 design) | 17.5 | K 9, 11; all 10, 10 frames (q 1.02–1.11) |
| V4 | SwiftUI resets `contentsScale` at the pull's end with platform views in the header | native behaviour | 17.5 (2), 27.0 (91) | re-applied by K6, 0 px |
| V5 | Whole reps with low busy (1.3–2.1 ms medians) in native and engine runs | harness | 27.0 p, 17.5 | N 2.03 / 2.09 / 2.12, K 1.35 / 1.87, all 1.36 |
| V6 | Host stalls under load < 30 hit native too | harness | all | NT25 47.2 ms, NSV25 274 ms, NT15 41.5 ms |
| V7 | The off path costs 1.0–1.5 ms per pulled frame, unchanged in Release | ztron (SwiftUI graph of the header chrome) | 17.5, 27.0 | 17.5 P25 off Debug 1.11–1.18, Release 1.09–1.43; 27.0 p 1.08–1.45 / 1.26–1.44 |

### 13.11 New risks

1. **K5** replaces the fade overlay's animatable input by a constant while the fade draws nothing. A fade switched on
   inside an animated transaction during a pull would interpolate from that constant, not from the live geometry: a
   possible wrong fade for the transaction's length. No demo switch exists; unmeasured.
2. **K2's reuse** of the 1:1 test is only valid while nothing moves the density between the test and the filter
   decision (gap-B rounding, bias, quantisation off in the scratch flags); the folded code must keep that condition.
3. **(b′) is not decidable run for run** at the meter's spread (13.8 item 2): a cut that only reaches parity will
   still "fail" most strict comparisons.
4. **No cut that keeps every frame crisp removes the title redraw** (13.4); meeting (b′) against N needs either NT as
   the reference or a cheaper path for the whole display, and on every lane the C2 fix (V1) and a 17.5 first-raise fix
   (V2) for the start frame.
5. A3, the flicks and the A7 rows on 27.0 f stay unrun on the cut (locks); 27.0 p and 17.5 ran them.

### 13.12 User ruling (2026-11-08)
Accepted all four changes of 13.8. A9 (b′) now reads: the engine's TOTAL main-thread busy per pulled frame against **NT** (the native
header with the same texts grown to pt·s), in paired interleaved runs, ≥ 8 reps per config and lane, load < 30, passes when (i) a
one-sided sign test at 5 % does not show the engine above NT (the engine above NT in ≥ 7 of 8 pairs fails) and (ii) the pooled median
and pooled p95 are ≤ NT's; for the median, the p95 of normal pulls, the p95 of fast pulls, and the pull-start frame, the last measured
both with the pull 1 s after appear (the C2 row) and ≥ 3 s after. A2 compares against plain engine-off (no cut flags).
The fixes still owed: C2 (pre-existing, Release too), V7 (engine-off path 1.0–1.5 ms per frame), V2 (17.5 first raise),
the 27.0 fast-pull p95, and the two 17.5 defects of 12.7 (flick over-density, Canvas / drawingGroup bimodal look).

## 14. Cost round 2 (d76-cost2, 2026-11-08)

Three spikes on top of cost-K (`d76-cost2/cost2-S.md`, `cost2-F.md`, `cost2-P.md`, each with `-delta.patch` on cost-K.patch)
and an independent skeptic (cost2-V: `d76-cost2/cost2-V.md`, raw verdicts in `cost2-V-raw/`, `cost2-V.patch` = full diff vs
72ca7fc, `cost2-V-delta.patch` = S + F + P on cost-K.patch with the one conflict resolved). cost2-V built the combined
tree **C** and the base tree **K** (cost-K, installed side by side under a second bundle id), Debug and Release, on its own
simulators (s2v-27 iPhone 18 Pro 27.0, s2v-175 iPhone 15 Pro 17.5, one booted at a time, light, AX 0), and measured A9
(b′) per 13.12: NT / N / off / K / C interleaved and rotated per rep, 8 pairs, every run at a 1-min load < 30.
C = ALL + KF + `-ZTronP2Gate 2 -ZTronP2RB raise`; CnoP = ALL + KF on the combined app (S + F without P).

### 14.1 Verdict

**Partly.** The combined build is pixel-clean on every A row measured (0 px / 0 off) and closes two of 13.12's owed items:
P's 17.5 out-of-cycle over-density (steps harness 18 / 33 off -> 0) and the Canvas / drawingGroup bimodal look (A5 one look
over 4 launches; canvastick RB 58 off -> 0); F removes the 27.0 `contentsScale` resets (K6 re-applies 4 per run -> 0).
A9 (b′) is **not met**: on 27.0 the start frame fails at 1 s and at >= 3 s for C, K and plain off (C2, SwiftUI first use),
and the fast-pull p95 fails on both 27.0 lanes; on 17.5 Release the fast p95 and the start frame sit 0.1-0.6 ms above NT.
P's gate gives back part of F's p95 gain on 27.0 (C above CnoP in 13 of 16 pairs, p .011). A3 and the XCUI flicks are
unmeasured (the seam and UI locks were held by other sessions).

### 14.2 Claims

| Spike | Claim | Verdict |
|---|---|---|
| S | C2 is SwiftUI first-use work; no kept change fixes it | confirmed (start FAIL for C, K, off at 1 s and 4 s on 27.0 p / f, Debug and Release) |
| S | lean chrome renders 0 px | confirmed (A1 12/12, A2, A6, all lanes) |
| S | round 1's start metric missed the pull's first frame | refuted (0-2 of 24 runs); S's own window drops a post-pull frame at 60 Hz |
| S | nudge visible | unmeasured |
| F | 27.0 resets come from `.allowsHitTesting` flipping inside the layer group; HeaderHitGate removes them | confirmed (K 4 per run in 48/48, C 0 in 48/48) |
| F | 27.0 p fast p95 passes | refuted (6/8, 6.02 vs 5.49; again 5.67 vs 5.33); S + F passes only without start frames |
| F | K median -0.9 ms, 8/8 | refuted (CnoP vs K 3/8 and 6/8 above) |
| F | 27.0 f fast p95 still fails | confirmed |
| F | Release fast p95 fails by ~1 % | partly (+7 % pooled with start frames; p95x passes) |
| F | 17.5 passes, fix neutral | confirmed in Debug |
| F | V7 0.79-0.90 ms | partly (0.90-1.30 on 27.0, 1.19-1.25 on 17.5) |
| F | new UI test passes | unmeasured |
| P | commit gate fixes 17.5 over-density (steps) | confirmed (C 0 off; CnoP 18 / 33; 141 / 156 deferrals, 18 fixes) |
| P | RB raise fixes canvastick | confirmed (58 -> 0, 27.0 and 17.5) |
| P | A5 one look across launches | confirmed (27.0 p, 17.5) |
| P | 27.0 never defers | confirmed (0 deferrals) |
| P | no measurable cost raise | refuted, small: fast p95 +0.04-0.13 ms on 27.0, 13/16 pairs |
| P | XCUI flicks 0 / 0 / 0 | unmeasured |

### 14.3 A9 on the combined build (C vs NT: pairs above / pooled C vs NT)

| Lane | median | p95 normal | p95 fast | start, pull at 1 s | start, pull at 4 s | (a) | (c) | (d) | (e) |
|---|---|---|---|---|---|---|---|---|---|
| 27.0 p Debug | PASS n / f / L (0/8 3.56 vs 4.18; 3/8 3.72 vs 3.91) | PASS 1/8 5.40 vs 5.78 | **FAIL 6/8 6.02 vs 5.49** | **FAIL 8/8 (p .004) 15.5 vs 4.0** | **FAIL 7/8 12.4 vs 3.8** | visit p95 0.13-0.44, one first raise 5.8 ms | drops C 8 vs off 5 (n 1/2, f 1/0, L 6/3; K 6; NT 0): **not met** on f and L | <= 1.0008 s²·rest | C +0.7 MB vs N25 +2.6 MB over rest |
| 27.0 f Debug | PASS | PASS 0/8 4.97 vs 5.75 | **FAIL 6/8 7.17 vs 5.66** | **FAIL 7-8/8 11.6-14.0 vs 3.8-3.9** | **FAIL 8/8 13.0 vs 3.7** | not run | drops C 5 vs off 8 (n 3/0, f 2/1, L 0/7): met in sum, not on n / f | not run | not run |
| 27.0 p Release | PASS n / f / L | PASS | **FAIL pooled 6.42 vs 6.00 (5/8)**; p95x PASS | **FAIL 8/8** | **FAIL 8/8** | | drops C 2 vs off 0 (n 1, f 1) | | |
| 17.5 Debug | PASS n / f / L | PASS 3/8 5.25 vs 5.45 | PASS 4/8 5.93 vs 6.09 | n: pooled p95 FAIL 8.55 vs 7.72 (2/8, one rep); f PASS 0/8 | PASS 2/8 4.86 vs 7.33 | first raise 0.79-1.36 ms | drops C 2 vs off 0 (f), K 0 | 0.9975-1.0008 | C 23.8-26.0 MB, N25 25.7-26.7, off 18.7-18.8 |
| 17.5 Release | PASS | PASS 3/8 5.36 vs 5.73 | **FAIL 6/8 6.42 vs 5.87; 6.00 vs 5.87** (K 5.83-5.87, CnoP 5.94) | n PASS 4.37 vs 4.52; f **FAIL pooled 4.75-4.89 vs 4.35-4.57** | not run | | drops C 3 vs off 0 (f), K 0; p175ri C 0 | | |

(c) = dropped frames (interval > 25 ms in the windows) summed over the 8 pulls per speed, C vs off. F's K6 re-applies: C 0 per run in 48 runs, K 4 per run (27.0), 0 on 17.5. (d) = applied store bytes over
s² times the rest store. (e) = phys footprint at t = 6 s and 13 s, nothing grows between them. The forced lane (27.0 f) is the
15-16 code path. Appear frame (27.0 p): C 105-118 ms vs off 86-98 (engine + chrome +10-20 ms; NT is another screen, 27-33).

### 14.4 Regressions on the combined build (C vs K or off)

| Row | 27.0 p | 27.0 f | 17.5 |
|---|---|---|---|
| A1 twelve sizes, K vs C; checker x6 | 12/12 0 px; 0 off | 12/12 0 px; 0 off | 12/12 0 px; 0 off |
| A2 after / rest, off vs C | 0 px x5 / x5 | same | same |
| A3 seam rows | unmeasured | unmeasured | unmeasured |
| A4 rest / h60 / pull / fast / endhold | 1/1/1 | 1/1/1 | 1/1/1 |
| A5 amended, 4 launches | one look, C = K 0 px | not run | one look (K two looks; C vs K 1582-2619 px = the RB raise) |
| A6 field / uilabel / uidraw 60 / 120 | 0 px x6, 0 off | same | same |
| A7 rows incl. canvastick | 0 off 6/6 (CnoP RB off 58) | 0 off (CnoP 57) | 0 off (CnoP 58) |
| A8 lookups | hops 2 | hops 2 | hops 2 |
| steps harness field + label, 60 / 120 Hz | 0 off | 0 off, 0 deferrals | C 0 off; CnoP 18 / 33 |
| 17.5 XCUI flicks field + label | | | unmeasured |
| 17.5 fast-pull drops | | | C 5 drops in 24 fast pulls, off 0, K 0 / 24, CnoP 0 / 8, NT 0 (A9 (c) not met on 17.5) |

### 14.5 Recipe to fold into §4 and the library (head 9ebe1bd)

1. **F now, independent of the engine.** `HeaderInteractionGate` (HeaderFrameModifier.swift:804-816 on head) keeps only
   `.disabled(blocked)`. A new `HeaderHitGate` leaf with its own relay on `.phase` applies `.allowsHitTesting(!blocked)`.
   It goes right after `.modifier(HeaderSlotReader(...))` (HeaderHost.swift:38) and before
   `.accessibilityElement(children: .contain)`. Run the whole UI suite and F's
   `testHeaderButtonCatchDuringBounceDoesNotFire` on 27.0 p, 27.0 f and 17.5. Also update the SPEC / D11 wording (cost2-F §6).
2. **S is already the head's structure.** The chrome is one static chain at HeaderFrameModifier.swift:157. When the engine
   lands, the probe and tick go in as slots in that chain, with no variant switch. S's demo hooks are measurement tools.
   `-ZTronS2Counters` must go under `#if DEBUG`, because as shipped it does not build in Release.
3. **P goes in with the D76 engine** (M8b-s9, `ScalingHeader/UIKit/HeaderRasterDensity.swift`).
   - The surface-backed row (RB raise) and commit gate 2 become defaults.
   - The `-ZTronP2Log` diagnostics stay out of the library: the CFRunLoopObserver and `String(describing: type(of:))`.
   - First, skip gate 2's ancestor walks on passes that cannot be out of cycle. 27.0 never defers but pays the p95.
   - Re-measure C vs CnoP after that change. Also attribute the C-only 17.5 drops.
4. cost-K's ALL + KF stay as 13.6 says.
5. Measure C2 again on head after folding. Head adds HeaderLift / LiftTrack types, and they run on first use too.

### 14.6 §5 rule-text deltas (for the user; exact)

S: none. F: none (pure SwiftUI). P: one clarifying delta. **§5.4 (SPEC S14 §3, header raster core)**: replace
> the layer policy table (drawn, needs-display, image, `.resize`, asynchronous, platform subtree, `CAMetalLayer`);

with
> the layer policy table (drawn, needs-display, surface-backed (a contents-less layer whose delegate-less sublayer
> holds non-`CGImage` contents), image, `.resize`, asynchronous, platform subtree, `CAMetalLayer`); the commit gate
> (the tick writes unless an update outside the display cycle was seen in the last 0.5 s; any other pass writes only
> when the model tree's drawn scale equals `max(s, 1)` and otherwise puts back that scale's density);

### 14.7 §7 criteria changes (for the user; none adopted here)

1. For the late pull, start the meter at least 0.3 s before the pull. Round 1 and every round-2 spike used T0 3.9 for a 4 s
   pull, which put the meter start 18-43 ms after the pull, so the first frames were never measured.
2. Define the start frame as the last row stamped within 20 ms before the pull plus the 3 rows after it. De-duplicate meter
   rows by stamp.
3. State that the median and p95 include the start frames. p95x (start frames excluded) is reported but never decides a
   verdict.
4. Split the start row into two rows:
   - a C2 row: off vs NT;
   - an engine start row: C vs off, paired.

   Until C2 has a fix, A9 (b′) cannot pass on 27.0. The user decides whether C2 counts as a tracked pre-existing excess.
5. For A9 (a), measure the first raise over at least 5 runs.
6. For the start row, use at least 16 reps or the sign test alone. With 8 values, the pooled p95 is a single rep.
7. Add three rows: the steps harness (field and label, 60 and 120 Hz, 0 off), the A7 canvastick RB check, and A5 over at
   least 4 launches.

### 14.8 Real iOS 15.0 / 16.0 (the M1 lane)

1. A9 (b′): C vs NT for n, f and L, 8 pairs, meter started before the pull, with the corrected start frame. Add off vs NT as
   the C2 row.
2. Count K6 resets at phase edges, with and without HeaderHitGate, inside the 15-16 compositingGroup layer group.
3. Count `-ZTronP2Log 1` deferrals: do 15.0 and 16.0 run out-of-cycle updates the way 17.5 does? Then run the steps harness
   and the XCUI flicks, C vs CnoP.
4. A5 over 4 launches, the A7 canvastick RB check, A1 K vs C, F's UI test, and the appear frame C vs off.

### 14.9 Pre-existing findings, classified

**Harness**
- The late pull was metered starting after the pull itself, in round 1 and in every round-2 spike.
- cost2-S's start window drops a post-pull frame.
- The meter logs duplicate rows.
- cost2-S's `-ZTronS2Counters` does not build in Release.
- Host stalls get past the load gate (one 274 ms run).

**ZTron**
- C2 on 27.0: off 11-19 ms vs NT 3.7-4.5.
- V7: 0.9-1.3 ms per frame.
- The appear frame is 10-20 ms over off.
- One first raise took 5.8 ms (27.0 p).

**Native**
- On 17.5 Debug, NT's own first change takes 6.8-7.7 ms, more than ours.

### 14.10 New risks

1. P's gate costs fast p95 on 27.0, where it never defers.
2. A9 (c): 17.5 fast pulls drop frames only on C (5 drops in 24 pulls; off, K 0), and 27.0 p Debug C 8 vs off 5; the cause is not attributed.
3. F moves hit-testing above the layer group. The UI suite has not been run against it.
4. C2 makes A9 (b′)'s start row unmeetable on 27.0 with every change measured so far. That needs the user's decision.
5. The recipe was measured on 72ca7fc, and head has more first-use types.
6. A3 and the flicks are unmeasured.

### 14.11 User ruling (2026-11-08)

"Split it, fix both" on 14.7 (4). The start-frame row of A9 (b′) becomes two rows, and both must pass:
- **C2 row:** ZTron with the engine off against NT. This is a pre-existing ZTron defect to fix, never a tracked excess.
- **Engine start row:** C against engine-off, paired, with the 13.12 sign test and pooled median and p95.

Both rows are measured at a 1 s and a ≥ 3 s pull, normal and fast, Debug and Release.

Not yet ruled:
- 14.6, the §5.4 surface-backed row and the commit gate;
- 14.7 items 1–3 and 5–7.

Until they are, round 3 measures so that both the 13.12 text and the proposed items hold. It uses the corrected meter start and start window, ≥ 16 reps on start rows, both p95 and p95x reported (p95 decides), and the 14.7 (7) rows as extra checks.

### 14.12 User ruling (2026-11-08): "Accept all"

These are now ACCEPTED:
- the §5.4 rule-text delta of 14.6: the surface-backed row and the commit gate;
- items 1–3 and 5–7 of 14.7.

The A9 (b′) measurement is therefore:
- **Meter start:** the meter starts ≥ 0.3 s before the pull.
- **Start frame:** the last row stamped within 20 ms before the pull, plus the 3 rows after it. Rows are de-duplicated by stamp.
- **p95:** the median and p95 include the start frames. p95x is reported but never decides.
- **Start row:** split per 14.11.
- **A9 (a) first raise:** measured over ≥ 5 runs.
- **Start rows:** ≥ 16 reps, or the sign test alone.
- **New rows:**
  - the steps harness (field and label, 60 and 120 Hz, 0 off);
  - the A7 canvastick RB check (0 RB off);
  - A5 over ≥ 4 launches (one look).

The P2 diagnostics (CFRunLoopObserver, `String(describing: type(of:))`) do not ship.

## 15. Cost round 3 (d76-cost3, 2026-11-08)

Three spikes: cost3-O (the engine-off path: C2, appear, V7; `d76-cost3/cost3-O.md`, `cost3-O.patch`, `cost3-O-library.patch`),
cost3-E (the engine's own increment: `cost3-E.md`, `cost3-E.patch` = cost2-V + E vs 72ca7fc) and cost3-U (the UI rows
round 2 could not run, HeaderHitGate on head: `cost3-U.md`, `cost3-U-F-head.patch`). Independent skeptic: cost3-V
(`d76-cost3/cost3-V.md`; `cost3-V.patch` = three full diffs, one per build below).

cost3-V built and measured, on its own simulators (s3v-27 iPhone 18 Pro 27.0, s3v-175 iPhone 15 Pro 17.5, one booted at a
time, light, AX 0), Debug and Release, under the cost lock:
- **H** = 7f57020 + cost3-O.patch + cost3-U F-head (its UI test, docs and comment; its HeaderHitGate hunks are O's, same
  placement) + a `cpu=` column (CLOCK_THREAD_CPUTIME_ID) in O's meter. **h0** = 7f57020's library with H's demo (before).
- **C3full** = 72ca7fc + cost3-E.patch + cost3-O's warm ported onto the engine build (below). Configs on it: **off** (no
  flags), **offK** (off + KF, the non-engine cost flags), **C3** = ALL + KF + P2 + `-ZTronE3 gate,objckvo` (= cost3-E's E).
  **E** = cost3-E's own app (no warm), same flags.
- **HT** = branch tip 80f5ad9 + H's library mapped by hand (O-library does not apply there); **t0** = the tip as is.
- **NT** = the native reference (costnative, texts grown), in the H app; NTc in the C3full app (equal: 4.03 vs 4.07).

Method (13.12 + 14.11 / 14.12): paired, interleaved, configs and speeds rotated per rep, every run at a 1-min load < 30
(retaken otherwise), meter started >= 0.4 s before the pull, rows de-duplicated by stamp, start frame stL = the last row
within 20 ms before the pull + the 3 rows after, p95 includes the start rows (p95x reported only), one-sided 5 % sign test
plus pooled median and pooled p95 <= the reference's; a run is void for a host stall (a row with busy - cpu > 100 ms, or
dt > 100 ms with cpu < dt / 2), a meter that ends before the release window or an empty start window. Speeds: n = 1 s pull
at 1 s, f = 0.3 s pull at 1 s, L = 1 s pull at 4 s, M = 0.3 s pull at 4 s. Reps: 27.0 p Debug 16 x n f L M; 27.0 p Release
16 x n L; 27.0 f Debug 8 x n f L M (16 pairs per pull time on the start rows); 17.5 Debug 16 x n f L M; 17.5 Release 8 x n L.
The cpu column (stLc) is reported beside stL and agrees with it on every verdict below.

### 15.1 Verdict

**Partly.** Every pixel and regression row measured on the two measured builds holds (0 px / 0 off; A4 1/1/1; A5 one look;
steps 0 off; A8 hops 2; HeaderUITests 20/20; C3full's hosted suites 137/137), but cost3-V's hand mapping of O's warm onto
the branch tip fails one hosted test (`aPinchOnAZoomableFollowingViewKeepsTheSeam`, 15.4). The two cuts are real: O's FirstUseWarm takes the 27.0 first pulled frame from 11-12 ms (h0, t0)
to 4.3-5.8 ms, and E's objckvo + gate plus the ported warm keep the engine build's pulled frames under NT's at the median
and the normal p95 on every lane measured. A9 (b′) is **still not met**:
- **C2 row (engine off vs NT) fails on every lane and both pull times**, Debug and Release. The first pulled frame is one
  4.5-7.8 ms row (ZTron) against native's costliest start row 3.9-5.1 ms (native spreads its first change over rows 0
  and 2). The cpu column makes it significant on 27.0 p Debug (21/31 and 22/32), 27.0 p Release n (12/16, p .038) and
  27.0 f (13/16, p .011). O's passing rows (27.0 p Debug f and L, Release n and L) are not reproduced at 16 pairs.
- **Engine start row (C3 vs off) fails** on pooled tails or medians by 0.1-1.0 ms on every lane; no sign test is
  significant. Against offK (the same non-engine flags as C3) it fails on the median too.
- **Fast-pull p95 (C3 vs NT)** still fails on 27.0 p Debug f (5.88 vs 5.64) and 27.0 f (f 5.79 = 5.79, M 5.93 vs 5.77);
  it passes on 27.0 p Debug M.
- **Appear**: every ZTron config is ~3x NTs (pre-existing); C3 is 4 ms over off at the median (5/12 above, n.s.).

### 15.2 Claims

| Spike | Claim | Verdict | Evidence (cost3-V) |
|---|---|---|---|
| O | C2 is first-use conformance work; FirstUseWarm removes most of it | confirmed | h0 stL 11.4-12.3 vs H 4.6-5.2 (27.0 p Debug, 31-32/32 pairs h0 above NT); t0 9.8-12.5 vs HT 4.0-4.6; E (no warm) 11.99 vs C3 (ported) 4.64, 1/14 |
| O | start frame at native's level; 27.0 p Debug f and L pass 13.12 (16 pairs) | refuted | f 4.75 vs 4.73 (9/16, median above); L 5.12 vs 4.54 (12/16, p .038); pooled 1 s / 4 s FAIL; stLc 21/31 p .035, 22/32 p .025 |
| O | 27.0 p Release n and L pass | refuted | n 5.83 vs 4.77 (12/16, p .038); L 5.44 vs 5.07, p95 8.09 vs 6.37 (8/16) |
| O | 27.0 f Debug fails | confirmed | pooled 1 s 6.76 vs 4.80 (13/16, p .011); 4 s 6.11 vs 5.16 |
| O | pulled frames pass by ~3x | confirmed | H vs NT med 1.09-1.47 vs 3.98-4.29, p95 1.75-2.81 vs 5.59-5.86, every lane |
| O | pixels and S4 unchanged; header.frame +1 at appear | confirmed | A2 H vs h0 0 px at rest / hold / after x2 (27.0 p, 27.0 f); counters equal except hf +1 |
| O | the warm costs nothing measurable at appear | confirmed (noise-limited) | AP27pD: H 89.3 vs h0 92.1, 3/12 above |
| O | Release f fails on the pooled p95 only | unmeasured | f not run in Release (timebox) |
| O | O-library applies on the branch tip | refuted | does not apply on 80f5ad9 (HeaderFrameModifier conflicts with D75's lift, a24ac2c..f0e6d31); hand mapping in cost3-V.patch PART 3 |
| E | objckvo + gate: E vs NT medians and normal p95 pass on every lane | confirmed on the lanes run | C3 (= E + warm) vs NT med and normal p95 PASS on 27.0 p Debug / Release, 27.0 f (17.5 below) |
| E | fast p95 fails by 0.05-0.53 ms | confirmed | 27.0 p Debug f 5.88 vs 5.64; 27.0 f f 5.79 = 5.79, M 5.93 vs 5.77 |
| E | the start row on 27.0 is C2's, the engine adds ~0 there | partly | with C2 cut (port) the engine start row is visible: 27.0 p Release n C3 5.45 vs off 4.47 (10/16), rows 1-3 +0.6 ms; Debug +0.1-0.4 vs offK |
| E | drops E <= off | partly | 27.0 p Debug A: C3 n 5 vs 0 (busy 13-30 ms, cpu 2-6 ms: host), A2 re-run 0/16; 27.0 f L 2 vs 0 (one host gap, one unattributed) |
| E | (a) first raise / visit within budget | confirmed | 27.0 p, 10 runs: visit+writes p95 0.33-0.58, max 0.97 ms, first frame 0.21-0.97 |
| E | no rule-text delta (objckvo is KVO through Foundation's public API) | confirmed | §5.4 says "key-value observation of `contentsScale` on the layers it changed", no API named |
| E | appear E 88.6 vs off 81.5 is noise | partly | C3 96.2 vs off 92.2 (5/12 above, p .81) but the pooled median fails |
| U | HeaderHitGate keeps HeaderUITests green incl. the new catch test | confirmed (27.0 p) | H 20/20 incl. testHeaderButtonCatchDuringBounceDoesNotFire |
| U | F applies clean on the tip | confirmed | `git apply` clean on 80f5ad9 (HeaderHost.swift:40, HeaderFrameModifier.swift:866-900) |
| U | the hosted unit failure is pre-existing (HeaderFallbackSlotTests) | confirmed | fails the same 4 cases on the clean tip ee0eaed (17.5) and on the mapped tip |
| U | A3 seam rows, A5 27.0 f, 17.5 flicks pass on round 2's C | not re-measured as such | A5 on C3full 27.0 p 4 launches one look; flicks on C3full: 15.4 |

### 15.3 A9 per lane (stL = start frame, ms, median / p95; "a/b" = pairs above the reference / pairs)

The start row is split per 14.11. **C2 row** = engine off vs NT, on the off-path build H (7f57020 + O + U) and, in
brackets, on the engine build with the engine off (C3full off). **Engine start row** = C3 vs off of the same app (offK =
off + KF in brackets, where measured). Median / normal p95 / fast p95 = C3 vs NT over every pulled frame including the start rows.

| Lane | C2 row, pull at 1 s | C2 row, pull at >= 3 s | engine start, 1 s | engine start, >= 3 s | median | normal p95 | fast p95 | (a) | (c) | appear |
|---|---|---|---|---|---|---|---|---|---|---|
| 27.0 p Debug (16 reps) | **FAIL** 19/31, 4.92 / 7.22 vs 4.52 / 6.37 (cpu 21/31 p .035) [off 17/31 4.49 / 7.27 FAIL] | **FAIL** 20/32, 4.98 / 9.26 vs 4.58 / 6.83 (cpu 22/32 p .025) [off FAIL] | **FAIL** 17/32, 4.35 / 7.53 vs 4.57 / 7.27 [offK 19/32, 4.35 vs 4.22 FAIL] | **FAIL** 15/27, 4.59 / 7.50 vs 4.67 / 7.42 [offK 17/29, 4.33 vs 4.15 FAIL] | PASS n f L M (3.61-3.97 vs 4.00-4.29) | PASS n 5.33 vs 5.76, L 5.25 vs 5.85 | **FAIL** f 5.88 vs 5.64 (6/16); M PASS 5.84 = 5.84 | PASS: visit+writes p95 0.33-0.58, max 0.97, first 0.21-0.97 (10 runs) | C3 n 5 drops vs off 0 in one batch (busy 13-30 ms at cpu 2-6 ms: host); re-run 0/16 | C3 96.2 vs off 92.2 (5/12, pooled med FAIL); H 89.3 vs h0 92.1; NTs 31.2 |
| 27.0 p Release (16 reps, n L) | **FAIL** n 12/16 p .038, 5.83 / 7.33 vs 4.77 / 5.69 [off 6/16 4.47 / 6.17 FAIL p95] | **FAIL** L 8/16, 5.44 / 8.09 vs 5.07 / 6.37 [off 3.94 / 7.00 FAIL p95] | **FAIL** n 10/16, 5.45 / 6.98 vs 4.47 / 6.17 | **FAIL** L 8/16, 4.26 / 7.93 vs 3.94 / 7.00 | PASS n 3.84 vs 4.21, L 3.87 vs 4.12 | PASS n 5.26 vs 5.75, L 5.31 vs 5.75 | unmeasured (f / M not run) | | drops 0 / 0 / NT 1 | |
| 27.0 f Debug (8 reps; 16 pairs pooled) | **FAIL** 13/16 p .011, 6.76 / 8.49 vs 4.80 / 6.46 [off 12/16 p .038 FAIL] | **FAIL** 9/16, 6.11 / 8.72 vs 5.16 / 7.50 [off 12/16 p .038 FAIL] | **FAIL** 7/16, 5.99 / 8.79 vs 5.34 / 8.57 | **FAIL** 7/16, 5.33 / 12.72 vs 6.67 / 8.65 (p95) | PASS n f L M (2.90-3.92 vs 3.98-4.19) | PASS n 5.14 vs 5.68, L 5.43 vs 5.59 | **FAIL** f 5.79 = 5.79 (4/8), M 5.93 vs 5.77 | | C3 L 2 (one host gap) vs off 0 | |
| 17.5 Debug (7 reps, cut) | PASS 0/15, 4.87 / 7.61 vs 8.21 / 10.32 [off PASS] | PASS 2/14, 4.84 / 6.45 vs 7.64 / 12.45 [off PASS] | **FAIL** 8/14, 5.69 / 8.42 vs 4.77 / 8.33 (n 6/7 p .062) | **FAIL** 8/14, 5.07 vs 4.84 (M 6/7 p .062) | PASS n f L M (3.86-4.19 vs 4.16-4.20) | PASS n 5.70 vs 5.79, L 5.36 vs 5.83 | f PASS 6.07 vs 6.16; **M FAIL** 6.02 vs 5.81 | not re-run (E: tick 0.26-0.62, layout raise 0.58-1.15) | 0 drops in every config | not run |
| 17.5 Release | unmeasured (timebox) | | | | | | | | | |

(d) stores / (s² x rest): 27.0 p 0.9984-1.0008 PASS (10 runs). (e) footprint 6 s after the release, 27.0 p: C3 19.66 / 19.56 MB,
off 18.53 / 18.60, N25 22.66 / 22.67: C3 +1.0 MB, N25 +4.1 PASS (heap by type not run).
Tip (80f5ad9, 27.0 p Debug, 8 reps): t0 (tip as is) **FAIL** 7-8/8, 9.8-12.5 vs 4.2-4.6 at every speed (C2 is on the branch tip);
HT (tip + H mapped) n 4.28 vs 4.54 PASS, f 4.03 vs 4.46 PASS, L 4.47 vs 4.21 FAIL (5/8), M 4.62 vs 4.63 PASS; HT vs t0 0/8 above.

Where the start frame goes (median busy of rows r0..r3, r0 = the pull's first frame): native spreads its first change,
27.0 p NT 2.9 / 0.3 / 4.4 / 3.2, 17.5 NT 7.9 / 0.2 / 4.5 / 4.5; ZTron pays it in one frame, 27.0 p Debug H 5.0 / 0.7 / 1.5 / 0.9,
offK 4.0-4.5, Release H 5.8, off 3.9-4.5; forced H 7.8. The C2 residual is therefore the first pulled frame alone, 0.4-1.2 ms
over native's costliest start row on 27.0 (2.6-3.9 ms on forced), and H (7f57020, with D75's HeaderLift / LiftTrack types) is
0.5-1.4 ms above the 72ca7fc engine build's off at r0 (14.5 (5), measured). The engine adds +0.6 ms (27.0 p Release) and
+2.3-2.5 ms (17.5, rows r0 and r2: its first raise and the first redraws at density) to the start window.

### 15.4 Regressions

Off path: H vs h0 (`hreg`: lossless PNGs at rest, at a 360 pt hold and after the release, 2 launches; S4 counters through
appear, a normal and a fast pull and the release). Engine: C3full with C3's flags; K = cost3-E's own app with the same flags
(27.0 p); off = C3full without flags.

| Row | 27.0 p | 27.0 f | 17.5 |
|---|---|---|---|
| Off path A2 (H vs h0; H1 vs H2) | 0 px x6; 0 px | 0 px x6; 0 px | 0 px x6; 0 px |
| Off path S4 (content.body, header.builder, header.content) | equal; header.frame +1 (the warm) | equal; +1 | equal; +1 |
| HeaderUITests on H (20 tests) | **20/20** incl. testHeaderButtonCatchDuringBounceDoesNotFire | not re-run (U: 20/20) | not re-run (U: 20/20) |
| A1 twelve sizes K vs C; checker x6 | 0 px x12; 0 off | not run | sizes **unmeasured** (cost3-V harness: K's app was not installed on s3v-175, the K shots are the home screen); checker x4 0 off |
| A2 after A-E / rest, off vs C3 | 0 px x5 / x5 | not run | 0 px x5 / x5 |
| A4 rest / h60 / pull / fast / endhold | 1/1/1 | not run | not run |
| A5 amended, 4 launches | one look; C vs K 0 px | not run (U: pass on round 2's C) | not run |
| A6 field / uilabel / uidraw at 60 / 120 | 0 px x6, 0 off | not run | not run |
| A7 appear / tick / dark / rotate / width / canvastick | 0 off; canvastick rb frames 230, rb-off 0 | not run | 0 off; canvastick rb frames 238, rb-off 0 |
| A8 lookups | hops 2, holds 0 (3 logs) | not run | not run |
| steps harness field + label 60 / 120 Hz | 0 off, 0 deferrals | not run | 0 off; deferrals / fixes 137 / 18 and 156 / 18 (round 2: 141 / 156, 18) |
| Hosted unit suites, C3full (19 suites) | | | **137/137 pass** (9 known issues, `withKnownIssue`) |
| Hosted unit suites, tip mapping (HT + ee0eaed's tests, 24 suites, 190 tests) | | | **FAIL: `HeaderFittingContentTests.aPinchOnAZoomableFollowingViewKeepsTheSeam` (preferred and forced, seam `sm2` > 1 pt)**, again when re-run alone; it passes on the clean tip ee0eaed (same lane). Pre-existing on the clean tip too: `HeaderFallbackSlotTests.aRuntimeOverflowChangeFollowsTheSameSequence` (4 cases). Load flakes (fail at load 270-800, pass re-run alone or on the clean tip): `optionChangesIntoAndOutOfFollowsAnimate` (forced), `aStretchingHeaderFollowsRowChangesAcrossTheKink`, `aKeyboardMovesFittingContentInTheKeyboardsCurve` (clean tip) |
| A3 seam rows, XCUI flicks on C3full | not run | not run | not run (timebox; U ran both on round 2's C: pass) |

The engine port changes no pixel against cost3-E's app (A1 12/12, A6, A5 C vs K 0 px on 27.0 p); a first reg-27p run was
invalid (the shot helper ran the H app for the C shots) and was re-run.

### 15.5 Recipe to fold

**Onto head now (branch tip ee0eaed = 80f5ad9 + a test commit; `7f57020..ee0eaed -- Sources/` = a24ac2c, 8cbec47, f0e6d31,
all D75 lift work).** Both pieces are pure SwiftUI, outside the D76 engine. They are improvements that do **not** close the
C2 row (15.3): fold them as such and keep C2 open.
1. **HeaderHitGate (U = O, identical hunks).** `cost3-U-F-head.patch` applies clean on 80f5ad9 and ee0eaed:
   `HeaderInteractionGate` keeps `.disabled(HeaderHitGate.blocked(...))` only (HeaderFrameModifier.swift:866-879 on the
   mapped tree); new `HeaderHitGate` leaf (:887-900); `.modifier(HeaderHitGate(state: state))` at HeaderHost.swift:40 (after
   `HeaderSlotReader`, before `.accessibilityElement`); the ContentTransform comment, the docs line and
   `HeaderUITests.testHeaderButtonCatchDuringBounceDoesNotFire`.
2. **FirstUseWarm (O), hand-mapped.** `cost3-O-library.patch` does **not** apply on the tip (HeaderFrameModifier.swift
   conflicts with D75's lift). The mapping is `cost3-V.patch` PART 3 (base 80f5ad9; applies clean on ee0eaed):
   - `Render/FirstUseWarm.swift` (new, as O);
   - `Render/ContentTransform.swift`: `TransformVector.w` spare scalar (:15, :52-59), `TransformHost` `@State warm = 1`
     (:204), passed as `warm:` (:231), `.onAppear { FirstUseWarm.run { warm = 0 } }` (:236) (as O);
   - `Render/FrameClockDriver.swift`: the warm tick (:8-22) (as O);
   - `ScalingHeader/HeaderFrameModifier.swift`: `@State warm = 1` next to `liftMemo` (:90-91); the `.onAppear` goes on the
     returned `content.modifier(HeaderStretchLiftBase(...).pinned(...))` (:133); `wake()` writes the share outside
     [0, 1] while warm (:156; its only reader clamps, HeaderMath.swift:82); `HeaderTranslation.animatableData` becomes
     `live.effectData` (o′, m, L) (:357-362) instead of O's `(offset, layoutShare)`, so it keeps D75's L;
   - not mapped (open): the tip's lift leaves (`HeaderStretchLiftBase`, `HeaderStretchLiftShift`, `HeaderLiftBase`,
     `HeaderLiftShift`, HeaderLift.swift:102-303) are new first-use types the warm does not touch; their `base` could carry
     `TransformVector.w = warm`. Unbuilt, unmeasured.
   - Measured on the mapped tip (HT): start frame 4.0-4.6 vs t0 9.8-12.5 (0/8 above t0), still above NT at L.
   - **Blocker before folding:** the mapped tip fails `HeaderFittingContentTests.aPinchOnAZoomableFollowingViewKeepsTheSeam`
     on both paths (17.5, deterministic; the clean tip passes). Not attributed (candidates: `HeaderTranslation` now animating
     the share m with (o′, L), or `TransformVector.w` in the lift leaves' catch-pin comparison). Find and fix it first.
3. Re-run C2 on head after folding with the lift leaves warmed; then attribute the remaining r0 (4.5-5.8 ms in one frame
   vs native's 2.9 + 4.4 over two) before any further cut. A cut must not move work out of the start window (games the metric).

**With the D76 engine in M8b-s9** (`ScalingHeader/UIKit/HeaderRasterDensity.swift` and the probe slots): cost2-V's recipe
(14.5: P2 gate + RB raise defaults, ALL + KF), plus:
4. **E's objckvo + gate** (cost3-E.patch hunks in HeaderRasterDensity.swift): the engine-owned NSObject observer
   (`addObserver(_:forKeyPath:"contentsScale",options:[],context:<layer>)`, registrations in a weak hash table, removed in
   deinit) as the only KVO path; the gate skip unconditional for gate 2; drop lean, t2l, ndfirst, kvowarm, kvowarmd and the
   e3 diagnostics (E's own list).
5. **The warm's engine piece** (cost3-V.patch PART 2, ported onto 72ca7fc + cost2-V + E): `HeaderRasterTick`'s animatable
   data carries the warm (there `AnimatablePair(live.offset, live.warm)` with `HeaderLiveInput.warm`, HeaderMath.swift +2,
   because 72ca7fc has no share). On the tip use `live.effectData` for HeaderRasterTick instead (its share is warmed by
   item 2), so `HeaderLiveInput` needs no new field; the other five 72ca7fc leaves are already `effectData` on the tip.
   The port removes C2 from the engine build (C3 4.64 vs E 11.99, 1/14).
6. The engine's own start-row increment (+0.6 ms 27.0 p Release, +2.3-2.5 ms 17.5) and the fast-pull p95 (+0.16-0.24 ms)
   remain: no cut found by E or here that keeps every frame crisp and on time.

### 15.6 §5 rule-text deltas (exact; listed separately)

None required. O, U and the port are pure SwiftUI outside the engine; the port's engine piece is a spare animatable scalar
in the engine's own SwiftUI leaf. E's objckvo is "key-value observation of `contentsScale` on the layers it changed"
(§5.4), which names no API. Optional clarification only, if the user wants the API named — in §5.4, after
> key-value observation of `contentsScale` on the layers it changed

insert
> (an engine-owned `NSObject` observer registered with `addObserver(_:forKeyPath:options:context:)` and removed with
> `removeObserver(_:forKeyPath:context:)`, every registration removed when the engine goes away)

### 15.7 §7 criteria changes (for the user; none adopted here; listed separately)

1. **Engine start row reference.** Compare engine on against engine off **with every non-engine flag equal** (off + KF
   while KF are flags). KF lowers the 27.0 p Debug start frame by 0.35-0.37 ms (offK vs off 11/32, 12/28), so C vs plain
   off flatters the engine.
2. **Void rules.** Add to 14.12: a run is void when its start window holds no row (the pull mark was logged but no meter
   row follows within 3 rows) and when its meter stops before the release window ends; report every void with its reason.
   Report the cpu column (stLc) beside stL; it decides nothing.
3. **Per-lane rep floor under host load.** When a lane cannot reach 16 reps (load > 30 for most of the window), report it
   as unmeasured beyond the reps taken instead of pooling a partial batch with a full one (17.5 here: 7 reps).

### 15.8 Real iOS 15.0 / 16.0 (the M1 lane)

1. C2 row: H (and the mapped tip) vs NT at n f L M, >= 16 reps, cpu column; profile rows r0..r3. The 15 / 16 path is the
   forced path (27.0 f fails by 1-2 ms), so expect C2 there; does FirstUseWarm reach the 15-16 `HeaderFallbackFrame` /
   `HeaderTranslation` leaves (the warm's `.onAppear` sits after `HeaderTranslation` on that branch)?
2. HeaderHitGate on 15 / 16: HeaderUITests incl. testHeaderButtonCatchDuringBounceDoesNotFire; header text redraws per pull
   with and without it inside the 15-16 `compositingGroup()` (cost3-U 15.0 / 16.0 list, items 1-3).
3. objckvo on 15.0: `observeValue` on the main thread for main-thread writes (`MainActor.assumeIsolated` traps otherwise),
   the A7 tick row, push / pop 20x and rotate during a pull (deinit removal), steps harness 60 / 120 Hz (cost3-E list).
4. Engine start row and fast p95 C3 vs off / NT; A9 (a) first raise >= 5 runs; appear C3 vs off.

### 15.9 Pre-existing findings, classified

**ZTron**
- C2 on the branch tip: t0 9.8-12.5 ms vs NT 4.2-4.6 (27.0 p Debug, 7-8/8). After O's cut the first pulled frame is still
  one 4.5-7.8 ms frame against native's 3.9-5.1 ms costliest start row (27.0 p / f); not on 17.5 (native's own first change
  is 7.9-8.6 ms there).
- H (7f57020) pays 0.5-1.4 ms more than 72ca7fc at the first pulled frame (D75's lift types; 14.5 (5)).
- Appear frame ~3x native on every ZTron config (H 89, off 92, C3 96 vs NTs 31 ms, 27.0 p Debug).
- `HeaderFallbackSlotTests.aRuntimeOverflowChangeFollowsTheSameSequence` (O and U: fails on head without their changes): 15.4.

**Native**
- 17.5 Debug: NT's first change costs 7.9-8.6 ms (r0), above every ZTron config.

**Harness**
- O's verdict did not flag runs whose meter stopped before the release window (here 2-4 of 16 L runs per config at 4.0 s
  windows; widened to 4.3 s + 9.3 s wait in round 3's later batches).
- cost3-E's verdict2 de-duplicates rows by tuple, not by stamp, and pools the start row across speeds at one pull time
  (both still give the same verdicts here).
- reg3.sh's shot helper takes the bundle from `$B` unless `BID` is set: on a two-app tree the "C" shots silently ran the
  other app (cost3-V's first reg-27p, discarded and re-run).
- Host load from other sessions (100-977 for hours) stalls interleaved batches; the load gate keeps them valid but not complete.

### 15.10 New risks

1. **C2 stays open with no measured fix.** O's warm is necessary, not sufficient: the residual is one frame, 0.4-1.2 ms over
   native on 27.0 p and 1.0-2.6 ms on the forced (15-16) path. Further cuts must not defer work out of the window.
2. **The tip mapping regresses a hosted test** (`aPinchOnAZoomableFollowingViewKeepsTheSeam`, 15.4): the warm cannot be
   folded as mapped. **The tip's new first-use types** (HeaderLift leaves) are not warmed by the mapping; the tip's L row already fails (5/8).
3. **The warm changes animatable types** (six header leaves + HeaderRasterTick on the engine build, HeaderTranslation on the
   tip): any test or catch-pin code that compares `animatableData` by type or shape must follow (HeaderStretchScaleTests did).
4. **Engine start row on 17.5** (+0.9 ms pooled median, n and M 6/7 p .062) is close to significant: the engine's first raise
   and first redraws at density on 17.5 are the largest remaining engine cost.
5. **Fast-pull p95** still fails on 27.0 (p Debug f, forced f and M) and 17.5 M by 0.16-0.24 ms.
6. 17.5 Release, 27.0 p Release fast pulls and the 17.5 flicks on C3full are unmeasured in this round.

### 15.11 User ruling (2026-11-09): "Accept all three"

The three criteria changes of 15.7 are ACCEPTED:

1. **Engine start row reference.** The engine is compared with engine-off, with every non-engine flag equal (off + KF while KF exist as flags). Plain off is still reported, but it does not decide.
2. **Void rules.** A run is void when:
   - its start window holds no meter row, or
   - its meter stops before the release window ends, or
   - it has a host stall (busy minus cpu > 100 ms).

   Every void is reported with its reason. The cpu column (stLc) is reported beside stL; it never decides.
3. **Short lanes.** A lane short of 16 reps is reported as measured to the reps it took. It is never pooled as a full lane.

The optional §5.4 objc-KVO wording (15.6) was not ruled; §5.4 already covers it.

## 16. Cost round 4 (d76-cost4, 2026-11-09)

Spikes cost4-T (C2 row on the tip), cost4-A (appear frame), cost4-E (engine increment); verify cost4-V (this section).
Notes, patches and data: `d76-cost4/` (cost4-V.md, cost4-V.patch, cost4-V-data.tgz, PROGRESS.md). Builds:
- **HT4** = branch tip fa4278b + cost4-T.patch + cost4-A.patch. One conflict (Demo DemoApp.swift screen switch: both scratch
  cases kept); library hunks clean. T-only and clean-tip apps built beside it for attribution.
- **E** = 72ca7fc + cost4-E.patch + cost4-T's ContentHitGate ported. T's other cut (D11 `.disabled` narrowing) is a semantic
  change and was not ported (measured separately as a variant).

Lanes: 27.0 p Debug and Release (16 reps), 17.5 Debug (16 reps), 17.5 Release (measured to 8 reps), 27.0 f Debug (see 16.3).
Every run had a 1-min load < 30 (retaken otherwise). Voids: 1 (E 27.0 p R n-4: no meter row in the start window).

### 16.1 Verdict

**Partly.** Round 4 closes no A9 (b') row that was open.
- **C2 (engine-off start frame vs NT)** still fails on 27.0 p (Debug and Release, all four speeds) and on 17.5 Release. It
  passes on 17.5 Debug, where native's own first change costs 7-8 ms.
- **Engine start row vs off + KF** fails on every lane. The only passes are isolated speeds: 27.0 p D L and M, 27.0 p R f,
  17.5 R f.
- **Fast-pull p95 vs NT** fails on 27.0 p f and M (Debug and Release), on 17.5 D M and on 17.5 R f and M.
- **Median and normal p95** pass on every lane.
- **Appear**: cold and sheet fail vs native on every lane measured. The engine's appear increment over off fails too.

What holds:
- T's 17.5 seam fix (ContentHitGate);
- A's ~7-8 ms cold-appear cut, on 27.0 p only;
- E's regression rows (27.0 p D);
- A9 (a), (c) and (e).

What is refuted: T's 27.0 M C2 pass, T's parity claim for the D11 cut, A's "no behaviour change", E's 27.0 p fast-f
pass, E's 17.5 fast-M pass, and E's claim that privwarm is the only rule delta.

### 16.2 Claims

| claim | status | evidence |
|---|---|---|
| T: ContentHitGate fixes `aPinchOnAZoomableFollowingViewKeepsTheSeam` (17.5) | confirmed | HT4 17.5: HeaderFittingContentTests 26/26 |
| T: C2 M passes on 27.0 p D | refuted | C27pD M 10/16, stL p95 7.91 vs 5.88; T27pR M p95 8.38 vs 6.46 |
| T: C2 fails 27.0 p n f L; passes 17.5 D | confirmed | 27.0 p D/R FAIL; 17.5 D PASS x4 (stL 4.6-6.0 vs 7.1-7.9) |
| T: `.disabled` on isDragging only gives r0 ~3.6-3.8 < NT | refuted | 8 reps: r0 4.2-4.9 ms, stL FAIL x4 vs NT (p95 6.5-7.3 vs 5.9-6.3) |
| T: the two `.disabled` flips are part of the residual | confirmed | the same variant is lower than HT4 at n, f, L (6 of 8 runs) |
| A: cuts take ~9 ms off the cold appear (27.0 p D) | confirmed on 27.0 p D only | zt 66.8 vs 73.6, zth 76.6 vs 84.6 (8 reps); 17.5 D: -1.2 / -0.5 ms, not significant |
| A: cold appear still fails vs native | confirmed | 27.0 p D/R, 17.5 D: 1.6-2.0x native |
| A: no behaviour change | refuted | `reachEdgeTwinsRegisterWatchersAndUpdateInPlace` fails alone on HT4, both paths (27.0); passes on the clean tip and on T-only. Cause: cut3 (see 16.4) |
| A: 0 px at rest, S4 | confirmed | 13 screens 0 px; content.body = 1 on 6 launches |
| A: hook order kept on 27.0 / 17.5 | unmeasured | not run here |
| E: regression rows unchanged | confirmed on 27.0 p D | A1, A2, A4, A5, A6, A7 incl. canvastick, A8, steps: all pass. 17.5 and 27.0 f not re-run |
| E: fast p95 passes on 27.0 p f | refuted | D 6.04 vs 5.67; R 6.20 vs 5.82 |
| E: 17.5 fast p95 passes at every speed | refuted (M) | 17.5 D M 6.81 vs 6.45 (12/16, p .038). f passes on D, fails on R (8 reps) |
| E: start row vs off / offK not met | confirmed | fails on every lane |
| E: appear increment fails | confirmed | 27.0 p R 90.5 vs 88.3, p95 128 vs 96.5; 17.5 D 60.5 vs 60.3, p95 66.8 vs 62.1 |
| E: A9 (a), (e) pass | confirmed | (a) med 0.11-0.18 ms per pulled frame; (e) 19.3-19.5 vs N25 21.1 MB |
| E: (d) | unmeasured | fast and tickcache records carry bytes = 0 |
| E: privwarm is the only §5 delta | refuted | privwarm also assigns `bounds` on its private layer (16.6) |

### 16.3 A9 per lane

stL is the start frame in ms, given as median / p95. "a/b" is the number of pairs above the reference, out of the pairs
measured. The rows are in speed order n, f, L, M. The deciding rows are:
- **C2**: F (tip line) vs NT;
- **engine start row**: E vs off + KF.

**C2: F (HT4) vs NT**
| lane | n | f | L | M | verdict |
|---|---|---|---|---|---|
| 27.0 p D | 4.62/4.56, p95 6.80/5.79 (10/16) | 5.66/4.65 (12/16, p .038) | 5.01/4.26 (13/16, p .011) | 5.05/4.58, p95 7.91/5.88 | FAIL x4 |
| 27.0 p R | 4.68/4.44, p95 6.72/5.71 | p95 7.82/5.12 | 5.47/4.54 | p95 8.38/6.46 | FAIL x4 |
| 17.5 D | 5.97/7.14 (4/16) | 4.56/7.94 | 5.38/7.72 | 5.73/7.34 | PASS x4 |
| 17.5 R (8) | 5.14/4.80 (6/8) | p95 7.13/5.53 | p95 5.89/5.87 | p95 6.07/5.89 | FAIL x4 |

The engine line's off vs NT gives the same picture: 27.0 p D FAIL x4, 27.0 p R FAIL x4, 17.5 D PASS x4, 17.5 R FAIL n, f, L.

**Pulled frames vs NT** (median / normal p95 / fast p95)
- F and off: PASS on every lane and speed (median 1.2-1.6 vs 3.7-4.5 ms).
- E:

| lane | median | normal p95 (n, L) | fast p95 f | fast p95 M |
|---|---|---|---|---|
| 27.0 p D | PASS x4 | PASS (5.46/5.79, 5.39/5.71) | FAIL 6.04/5.67 | FAIL 5.90/5.83 |
| 27.0 p R | PASS x4 | PASS (5.40/5.71, 5.40/5.85) | FAIL 6.20/5.82 | FAIL 5.93/5.92 |
| 17.5 D | PASS x4 | PASS (5.63/5.88, 5.59/5.85) | PASS 6.23/6.28 | FAIL 6.81/6.45 (p .038) |
| 17.5 R (8) | PASS x4 | PASS (5.45/5.75, 5.45/5.79) | FAIL 6.18/5.78 | FAIL 6.11/6.07 |

**Engine start row: E vs off + KF (deciding); plain off reported**
| lane | vs offK n | f | L | M | vs off |
|---|---|---|---|---|---|
| 27.0 p D | FAIL 4.77/4.49 | FAIL p95 7.14/6.58 | PASS | PASS on stL, FAIL on stLc (1) | f PASS; n, L, M FAIL |
| 27.0 p R | FAIL (15 reps) | PASS | FAIL 6.07/5.70 | FAIL 5.92/5.41 | n PASS; f, L, M FAIL |
| 17.5 D | FAIL 5.44/4.99 | FAIL p95 7.66/7.29 | FAIL p95 8.15/7.69 | FAIL 6.15/4.61 | f, L PASS; n, M FAIL |
| 17.5 R (8) | FAIL | PASS | FAIL | FAIL | f PASS; n, L, M FAIL |

(1) offK's p95 of 41.5 ms comes from an unvoided host hitch: busy 41.5 ms at cpu 4.4 ms, below the 100 ms void bar.

**27.0 f Debug** (`-ZTronForceAllFallbacks`): host load 160-220 from other sessions from 12:02. The lane stopped at 1 rep:
unmeasured (see 16.8).

**Other A9 rows**
- **(a)** (27.0 p D): visit plus writes per pulled frame, median 0.11-0.18 ms, p95 0.28-0.39 ms. PASS.
- **(c)** dropped frames over 64 pulls per lane, E vs off: 27.0 p D 1 vs 0 (a host hitch, cpu 4.1 ms); 27.0 p R 0 vs 0;
  17.5 D 0 vs 0. PASS.
- **(d)** unmeasurable on E (bytes = 0).
- **(e)** footprint 6 s after the release: E 19.27 / 19.50 MB vs off 18.53 / 18.56 vs N25 21.11 / 21.17. PASS.

**Appear: cold max in [mark - 20 ms, + 500 ms], 8 reps**
| lane | zt vs nat | zth vs nath | HT4 vs clean tip | sheet zt vs nat | seam lab E vs off / offK |
|---|---|---|---|---|---|
| 27.0 p D | 66.8/39.7 FAIL | 76.6/38.5 FAIL | lower: 66.8/73.6, 76.6/84.6 | 46.4/44.8 FAIL (p95) | not run |
| 27.0 p R | 63.6/39.3 FAIL | 76.0/38.7 FAIL | not run | 54.3/49.2 FAIL | 90.5/88.3 FAIL; 90.5/90.4 FAIL (p95 128) |
| 17.5 D | 49.9/30.0 FAIL | 57.6/36.4 FAIL | no gain (49.9/51.1, 57.6/58.1) | 48.2/27.4 FAIL | 60.5/60.3 FAIL; 60.5/59.2 FAIL |

### 16.4 Regressions

- **HT4 (cost4-A cut3)**: `RefreshIndicatorTests.reachEdgeTwinsRegisterWatchersAndUpdateInPlace` fails alone on 27.0 on
  both paths; reachEdgeWatchers is empty.
  - Mechanism: `RefreshOverlay.front()` attaches its `.onAppear` (it sets `pan.refresh`, `announce`, `holder.apply()` and
    `holder.syncReach(state:)`) to `RefreshHostSlot`. That slot's body is empty when no refresher is resolved, so the
    onAppear never runs and the reach-edge watchers never register.
  - The same hooks also stop setting `pan.refresh` on a container that has no refresher. That container is reach-only, or
    gains a refresher later.
- Full 27.0 hosted run on HT4: 926 tests, 89 suites, load about 5, 19 issues of which 11 are known. Besides reachEdge, the
  failures are:
  - `anAnimatedWidthChangeAtHalfCoverKeepsTheParallax`: passes alone, as on the tip's handoff;
  - `aRuntimeOverflowChangeFollowsTheSameSequence`: pre-existing;
  - `aResetThatSwiftUIAnimatesCarriesTheIndicatorWithTheContent`: pre-existing.
- None in A2 or S4 on 27.0 p D, and none in E's rows on 27.0 p D.

### 16.5 Recipe to fold

The branch tip is still fa4278b. `git log 2da5dc7..HEAD -- Sources/` lists only 65df4f4 (Render/ContentShape.swift).
Neither patch touches that file.

**Onto the tip now** (pure SwiftUI, outside the engine). None of these closes C2 or the appear row; fold them as
improvements only.
1. **cost4-T.patch** (`git diff fa4278b 07229fd -- Sources`, cost4-V.patch Part 1). Files:
   - `Render/ContentTransform.swift`: ContentHitGate leaf above the transform host's geometry modifiers;
     ContentInteractionGate keeps `.disabled` only; TransformVector.w; the TransformHost warm;
   - `Render/FirstUseWarm.swift` (new);
   - `Render/FrameClockDriver.swift` (warm tick);
   - `ScalingHeader/HeaderFrameModifier.swift`: HeaderHitGate leaf, warm on HeaderStretchLiftBase, and
     `HeaderTranslation.animatableData = live.effectData`;
   - `ScalingHeader/HeaderHost.swift` (`.modifier(HeaderHitGate(state:))`).

   This is cost3-V's PART 3 mapping, now with the seam blocker fixed.
2. **cost4-A cuts 1, 2 and 4**:
   - cut1, a stored `objectWillChange` (13 classes, `git diff 07229fd 8677faf -- Sources`, cost4-V.patch Part 1, minus
     T's hunks): `Chrome/ScrollIndicators.swift` (IndicatorController `isShown` with `willSet`),
     `ContentOverlay/ContentOverlayTypes.swift`, `Gesture/PanCoordinator.swift`, `Gesture/PanGestureAdapter.swift`,
     `Observation/ScrollObservers.swift`, `Reader/ZTronScrollViewReader.swift`, `Refresh/RefreshCoordinator.swift`,
     `Refresh/RefreshIndicators.swift` (the classes only, not RefreshHostSlot), `Render/ContentTransform.swift`
     (GroupLatch), `ScalingHeader/HeaderMeasure.swift` and `ZTronScrollView.swift` (StateHolder);
   - cut2, ContainerHooks in `ZTronScrollView.swift`;
   - cut4, `headerSlotsAttached` in `State/ZTronScrollState.swift` plus the slot latch in `ZTronScrollView.swift`.

   Before folding: run HeaderUITests 20/20 and the hook-order probe on 15 / 16. Neither has run.
3. **cost4-A cut3** (`Refresh/RefreshIndicators.swift`, RefreshHostSlot): **do not fold as is.**
   - Move the `.onAppear` / `.onDisappear` / `.onChangeCompat` hooks of `front()` onto a leaf that always exists, for
     example a zero-size `Color.clear` background of the slot, then re-run RefreshIndicatorTests.
   - That fix is unbuilt, and its miss count is unmeasured.
4. **Not to fold**: cost4-T's D11 `.disabled` narrowing (cost4-V.patch Part 3). It is a semantic change: an API option or
   a user decision. It also does not reach parity.

**With the D76 engine in M8b-s9** (`ScalingHeader/UIKit/HeaderRasterDensity.swift`):
5. **cost4-E** tokens `fast`, `restskip`, `tickcache` and `bridgewarm` become the engine's shipped tick / layout / warm2
   behaviour, as E's section 6 describes. Drop the token switches, `trace`, LateProbe (including its `@State` branch in
   HeaderFrameModifier.swift), E4Dump and the GCRec `fmiss` / `walked` / `dispc` / `px` diagnostics.
   - `privwarm` folds only with the 16.6 delta accepted. Otherwise drop its `bounds` write and re-measure, or drop
     privwarm.
   - The E patch does **not** apply onto HT4: HeaderFrameModifier.swift and HeaderHost.swift conflict with T's mapped warm
     and gates. Rebase E's two hunks there by hand. The ContentHitGate port is already in E + port (cost4-V.patch Part 2).
6. **Record bytes on the fast / tickcache paths** so that (d) can be measured. This is a diagnostic only.

### 16.6 §5 rule-text deltas (exact; listed separately)

E's proposed §5.2 text, in cost4-E.md section 5 item 1, is needed for privwarm but is not enough. privwarm (in
HeaderRasterDensity.swift, warm2) also assigns `l.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)` on its private
layer, and the §5.3 scope gate's assignment allow-list rejects that line. The deltas, if privwarm is kept:

1. **§5.2, `Allowed there` bullet.** Use E's replacement text with "creates and never attaches to a tree" replaced by:
   > creates, sizes once (its `bounds`) and never attaches to a tree
2. **§5.3, scope gate.** Replace
   > `contentsRect`, `contents` (only as `contents = nil`),

   with
   > `contentsRect`, `contents` (only as `contents = nil`), `bounds` (only on the engine's own private warm layer),

No other deltas. The other pieces fall within the current text:
- `fast`, `restskip` and `tickcache` change when the existing writes happen;
- `tickFromCache` calls `setNeedsDisplay()` on platform views, which is already allowed;
- `bridgewarm` is a Foundation cast;
- the `CATransaction` begin / `setDisableActions` / commit around privwarm assigns no layer property.

Alternative with no delta: drop the `bounds` write. That variant is unmeasured, and a zero-size layer may skip the
display path that privwarm is there to warm.

### 16.7 §7 criteria changes (for the user; none adopted here; listed separately)

1. **(d) must be measurable on the shipped path.** The store-bytes record (GAPC `bytes`) must be filled on the fast and
   tickcache paths. An unmeasurable row is never counted as a pass.
2. **Sub-100 ms host hitches.** A run is void when a row in its start window has busy − cpu > 20 ms and busy > 3x cpu.
   Example: offK 27.0 p D M-7, busy 41.5 ms at cpu 4.4 ms, which set the reference p95 to 41.5 ms and turned a FAIL into a
   PASS. The same applies to the release window (27.0 p R: F L p95 54.9, offK L p95 83.1).
3. **Batch-to-batch drift.** F's r0 median moved 1-2 ms between two 27.0 p D batches of the same app on the same day.
   - Decide a start row on two independent 16-rep batches, each interleaved with its reference.
   - It passes only when both pass.
   - Alternatively, require every start-row verdict to be reproduced on both Debug and Release.

### 16.8 Real iOS 15.0 / 16.0 (the M1 lane) and what this round left unmeasured

M1 lane (15.0 / 16.0):
1. HT4 hosted suites, plus HeaderUITests 20/20, on 15.0 and 16.0, against the clean tip. In particular:
   - RefreshIndicatorTests, which reachEdge fails on 27.0;
   - HeaderFittingContentTests, the seam test with ContentHitGate on the 15-16 compositingGroup path.
2. cost4-A's order probe: `-ZTronScreen applab -APKind order -APSecond 0`. ContainerHooks takes the `onChange(of:perform:)`
   fallback there, and each change must fire once, in this order: position, limits, sizing, anchor.
3. C2 (F vs NT) at n, f, L and M, ≥ 16 reps. The forced lane emulates 15-16 and did not run here.
4. E: engine start row vs offK, fast p95 vs NT, A7 rows and the steps harness. privwarm on a 15.0 private layer.
   restskip's same-commit layout pass at the first pull: the checker must read 0 off, first pulled frame included.

Unmeasured here (locks, host load, timebox):
- HeaderUITests, A3 seam rows and the 17.5 XCUI flicks with a field and a label. The UI lock was held by UIKITPAN-s4 all
  session, and the seam lock by recheck1.
- 27.0 f lane: C2, engine and appear.
- The clean-tip appear rows on Release.
- E's rows on 17.5 and on 27.0 f.
- Hosted 17.5 and 27.0 f full suites on HT4.

### 16.9 Pre-existing findings, classified

**ZTron**
- C2 on the tip line: F's first pulled frame is one 4.6-5.7 ms row (r0) on 27.0 p, where NT spreads 2.9-3.4 (r0) and
  4.2-4.5 (r2) ms. On 17.5 Release this fails as well (8 reps).
- The cold appear frame is 1.6-2.0x native on every lane, even after A's cuts. A estimates it scales with about 100
  distinct container types.
- `aRuntimeOverflowChangeFollowsTheSameSequence` and `aResetThatSwiftUIAnimatesCarriesTheIndicatorWithTheContent` fail on
  the tip's full 27.0 run.

**Native**
- 17.5 Debug NT's first change costs 7.1-7.9 ms (r0), above every ZTron config (as in round 3).

**Harness**
- vv4.py labels a lane run at 8 reps as `[FULL]` when MIN = 8. Report it as "measured to 8".
- A zsh loop `set -- $r` does not word-split, so its verdict files went to wrong names. Run the loops under bash.
- The A2 pull rows show a home-indicator band in alternate launches (6449 px, y 2583-2598). It appears equally in A-vs-A
  and B-vs-B. Mask the band or compare like launches.
- One E 27.0 p R run (n-4) had no meter row in its start window and was voided.

### 16.10 New risks

1. **C2 has no measured fix left inside the rules.** The `.disabled` narrowing is the only lever found that is not a
   spread, and it does not reach parity on 27.0 p. A further cut needs a design change: either fewer flips at the pull's
   first frame, or an API option.
2. **A's cut3 is a behaviour regression** (reach-edge watchers, `pan.refresh`) that A's own regression rows could not see.
   The hosted suites must run before any cut lands.
3. **Engine fast-pull p95** fails by 0.01-0.40 ms on 27.0 p (f and M) and on 17.5 (M; f on Release). E's tokens did not
   move it on 27.0.
4. **The appear increment** of the engine over off is +0.2 to +2.2 ms at the median, and its p95 tail is wider (+4.7 to
   +31.5 ms). It comes from hosting the probes and has no cut.
5. **E does not apply onto HT4.** The M8b-s9 fold needs a hand rebase of HeaderFrameModifier and HeaderHost against T's
   mapped warm.

### 16.11 User ruling (2026-11-09): "Accept 1,3,4 reject 2"

1. **Accepted, as a fix (not an option): D11 `.disabled` narrows to `isDragging`.** ContentInteractionGate and
   HeaderInteractionGate apply `.disabled` only while a drag is recognized. Hit-testing (ContentHitGate, HeaderHitGate) keeps
   `(decelerating || animating) && !isTracking || isDragging`. Controls no longer take the disabled state during a deceleration
   or an app animation, and a press that began before an app-animated scroll is no longer cancelled; both match native. A catch
   still never reaches a Button, and a recognized drag still cancels the press under the finger.
2. **Rejected: the §16.6 rule-text delta** (`bounds` on the engine's private warm layer). §5.2 and §5.3 stay as written.
   privwarm ships only without its `bounds` write, re-measured, or it is dropped.
3. **Accepted: the three §16.7 criteria changes.**
   - (d) must be measurable on the shipped path; an unmeasurable row is never a pass.
   - A run is void when a row in its start or release window has busy − cpu > 20 ms and busy > 3x cpu.
   - A start row is decided on two independent 16-rep batches, each interleaved with its reference; it passes only when both
     pass.
4. **Accepted: round 5.** Change the design so the first pulled frame does less work, and go after the fast-pull peaks and the
   appear frame.
