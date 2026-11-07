# D76: a crisp `.keepTextMagnified` (the default of `withScalingHeader(…, stretchContent:)`)

> Committed by builder s6-d76-api-16 of M8b-s8 (2026-11-07) from the designer's scratch doc (`s8/design/d76-magnified.md`), unchanged below this note. It replaces the architect's notes-assembled version of febf007 (in git history; plan C15). Scratch paths (`s8/…`) are gone after the 2026-11-02 reboot; the evidence persists in the shared notes folder `m8b-s8-resume/` (`d76-design-evidence/`, `d76-swiftui-evidence/`, `d76-verify/`). The user's acceptance of the crisp path (2026-11-03) and its build in M8b-s9: Orchestration D76; this batch builds only the API, `.keepTextMagnified` as D69 and the grow case.

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
