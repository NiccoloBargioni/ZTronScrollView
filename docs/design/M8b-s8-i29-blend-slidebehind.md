# i29: a content blend mode reaches a `.slideBehind` header on 15–16 (D77, proposed; blocked in pure SwiftUI)

> Committed by the M8b-s8 architect (2026-11-03) from the designer's scratch doc, unchanged below this note. Build order, numbering and the architect's amendments: [M8b-s8-plan.md](M8b-s8-plan.md) (they win where they differ). Scratch paths (`s8/i29-blend-slidebehind/…`, `scratchpad/s8/…`) are gone after a reboot; the text artifacts (patches, tools, tables) persist in the shared notes folder `m8b-s8-resume/s8-spikes/i29-blend-slidebehind/`.

Designer `i29-blend-slidebehind`, batch M8b-s8, 2026-11-02. Base 09226f4 on `claude/cool-stonebraker-0015c9`. Open item 29
(user ruling 2026-11-02: FIX, no limit). Spike code lived only in scratch worktrees `s8/i29-blend-slidebehind/wt` (G, the
layer and perf harnesses) and `wt2` (route P); both removed at the end, diffs kept in `spike/`. No library code was
committed. Evidence: `seam/`, `shots/`, `shotsP/`, `unit*.log`, tools in `tools/` (paths relative to the batch scratchpad
`s8/`).

## 0. Verdict

- **Symptom, measured.** Seam lab, a `.fixed` header half collapsed under `.slideBehind`, the content's first 80 pt a white
  `.difference` probe with nothing of the content behind it. 27.0 and 17.5 (`geometryGroup`) draw it cyan over the header and
  yellow over the blue behind the scroll view (blended); the 15–16 path (27.0 and 17.5 forced) draws it white (composited
  alone). In a rotation, 128 of 129 frames are white next to the header.
- **Root cause.** The 15–16 content group `compositingGroup()` (`ContentLayerGroup`) is a `CALayer` with `allowsGroupOpacity`
  1 and `allowsGroupBlending` 1. Blends composite inside the group's own surface, which holds only the content, and an
  ancestor's opacity fades the group as one image. 17+ `geometryGroup()` makes the same boundary with both flags 0. The
  `.slideBehind` header is a sibling outside the group.
- **Pure SwiftUI cannot match 17+, so this is blocked.**
  1. A rigid rotation needs a boundary that keeps every row's layer (no culling). Of 16 public modifiers, only flattening groups
     do that (compositing, drawing, shadow, gradient mask), and every one of them isolates blends. Every other modifier
     culls, and the rotation tears (control: lateral 397 pt).
  2. So the content's blends can reach the header only if the header joins the content's group. Design G does this with one
     `compositingGroup()` above the transform, around both the content and the `.slideBehind` slot. Design A puts the header
     inside today's group.
  3. Such a group fades the header and the content as ONE image. Under an ancestor `.opacity(0.5)`, the content over the header
     draws (0, 128, 127) with G. 17+ draws (64, 128, 63), and so does today's 15–16 build (17.5 and 27.0, §4).
  
  G fixes item 29: 0 failing frames in 4 motions, seams equal to today's. But it creates a new 15–16 look difference in every
  fade, so it is not a fix under the user's rule.
- **What does reach 17+ (measured; scoped; not pure SwiftUI): route P.** The whole difference is those two layer flags. In
  route P, a 0 × 0 probe `UIView` (a `UIViewRepresentable`) sits inside each 15–16 group, walks up to its group's layer once
  and turns both flags off, as `geometryGroup()` does. Today's structure stays and G is not used.
  - Pixels: on 17.5 and 27.0 forced, every probe pixel equals 17+. Blends over the header and over the blue behind are cyan /
    yellow. Fades with and without a content background are (32, 128, 95) / (64, 128, 63).
  - Persistence: the flags never come back through a scroll, a width animation or an animated collapse.
  - Cost: nothing changes per frame (today's 3–4 moved layers).
  - Price: an S16 exception. It puts UIKit and a `Representable` in the library, and `allowsGroupBlending` is a PRIVATE
    `CALayer` property, set by key. That is an App Review guideline 2.5.1 risk for every app that links the library.
- **Public-API variant (measured on 17.5): G + the probe turning off only the public `allowsGroupOpacity`.** Item 29 is fixed and fades
  equal 17+. G's per-leaf cost stays. Blends that 17+ lets reach BEHIND the scroll view stay isolated, as today: white over the
  blue. So do a header's own blend modes and an indicator's blend modes under a header. These are the pre-existing SPEC S10
  "15–16 layer groups" differences.
- **Recommendation: needs the user (decision, not taste).** D77 = route P, scoped to the 15–16 path (iOS < 17 and the forced
  lane), 100 % covered. It also closes the S10 documented 15–16 differences.
  - If the private property is refused: D77′ = G + public probe (UIKit only). It fixes item 29 and the fades; the S10 blends
    behind the scroll view stay blocked, because no public switch exists (§4).
  - G alone (pure SwiftUI) is not proposed, because it trades the fade.
  - Nothing is built before the decision.

## 1. Reproduction

Static, `simctl io screenshot`, one column at x = 50 % (`tools/runs.py`, `tools/segs.py`). Seam lab arguments:
`-ZTronHeaderSize fixed -ZTronSeamStart half -ZTronHeaderBehavior preserve -ZTronSeamCollapse slideBehind -ZTronSeamBlend
difference -ZTronSeamBlendHeight 80` (spike demo arguments, §8 step 2). On 27.0 the probe spans y 182–262: 60 pt over the part
of the header the content covers, and 20 pt over the blue behind the scroll view.

| lane | probe over the header (60 pt) | probe over the blue behind (20 pt) |
|---|---|---|
| 27.0 preferred (`geometryGroup`) | cyan (0, 255, 255): blended | yellow (255, 255, 0): blended |
| 17.5 preferred | cyan | yellow |
| 27.0 forced (`compositingGroup`, today) | white: alone | white: alone |
| 17.5 forced | white | white |
| 27.0 / 17.5 forced, G | **cyan** | white |
| 27.0 / 17.5 forced, route P (today's structure + probe) | **cyan** | **yellow** |

In motion, `tools/blendtrack.py` runs on the recordings. Per lab frame it counts cyan pixels, and white pixels within 6 px of
the header's red; a frame fails when that white count exceeds 2 px per frame row.

| recording | lab frames | failing | with cyan | max white next to red |
|---|---|---|---|---|
| 27.0 forced, rotation, today (`f27b/blend-rot-cur`) | 129 | 128 | 0 | 13 500 px |
| 27.0 forced, rotation, G (`f27b/blend-rot-outer`) | 129 | 0 | 129 | 33 px (anti-aliasing) |
| 27.0 forced, `.aspectRatio` rotation, G (`f27b/blend-rota-outer`) | 132 | 0 | 131 (all but the launch frame) | 36 px |
| 27.0 forced, width animation, G (`f27b/blend-width-outer`) | 164 | 0 | 163 (all but the launch frame) | 0 |
| 27.0 forced, band scroll 0.4 → 0.95, G (`f27a/blend-scroll-outer`) | 166 | 0 | 164 (the other 2: header covered) | 0 |
| 27.0 preferred, rotation / band scroll / width (`r27p/…-ref`) | 129 / 164 / 166 | 0 / 0 / 0 | 129 / 164 / 166 | – |
| 17.5 preferred, rotation / band scroll / width (`r175/…-ref`) | 112 / 172 / 170 | 0 / 0 / 0 | 112 / 172 / 170 | 17 / 0 / 0 |

Route P was measured statically and through scripted motions (§5.3), not yet with recordings (§9).

## 2. Root cause, with the layer evidence

Hosted unit spike `SpikeI29LayerTests` (27.0 sim): 30 marker rows of 60 pt and a `.fixed(min: 0, max: 100)` `.slideBehind`
red header. It dumps the markers' common ancestor and its chain, with `allowsGroupOpacity` / `allowsGroupBlending` read by
KVC, then scrolls 150 pt:

| path, content group | markers present (of 30) before → after | rows moved inside their parent | common ancestor of the rows | group flags |
|---|---|---|---|---|
| 27.0 preferred, `geometryGroup()` | 30 → 30 | 0 (the group moves) | the group layer (the viewport (0, 62, 402, 778), clips) | opacity 0, blending 0 |
| forced, `compositingGroup()` (today) | 30 → 30 | 0 (the group moves) | the group layer (same frame, clips) | **opacity 1, blending 1** |
| forced, no group (control) | 12 → 14 (7 kept) | 7 of 7 (pushed down) | the hosting view's layer (opacity 0, blending 0) | – |
| forced, G | 30 → 30 | 30 of 30 (pushed down) | the G layer, which also holds the header (31 sublayers) | opacity 1, blending 1 |

- SwiftUI's own layers on 27.0 carry both flags 0 (the hosting view's layer and every plain container). Only the compositing
  group sets them. On 17.5 forced, SwiftUI renders through UIViews: `_UIInheritedView` groups and `_UIGraphicsView` leaves,
  all 1 / 1 by UIKit's default. Only the group's flags matter there, because the leaves have no sublayers.
- A sublayer's compositing filter (`.blendMode`) blends with what its nearest group-blending ancestor has rendered so far.
  Inside today's content group that is the content alone, transparent where no row draws, so a white `.difference` stays
  white.
- The `.slideBehind` header is `HeaderOverlay(behind: true)` in the container's `.background(alignment: .top)`
  (`ZTronScrollView.swift:158-162`), a sibling under the content group's layer.
- An inherited opacity reaching a layer with `allowsGroupOpacity` 1 fades its subtree as one flattened image. With 0, it fades
  each sublayer on its own, which is SwiftUI's documented default. §4 measures what that does to a fade.

Why the 15–16 group exists (SPEC S10 "Rigid layer groups", spike C 3044abf): a system rotation is laid out once at the final
size, and Core Animation interpolates every layer change made inside UIKit's rotation block. Layers that SwiftUI adds or
removes in that pass (rows culled in or out against the container's clip) land at once while the others interpolate. The
measured control without a group tears: lateral 397.2 pt, split 17 (`f27a/slide-rot-none`).

## 3. Candidates measured

Each candidate replaced the 15–16 content group under the transform, on 27.0 forced (and on 17.5 forced where shot). Each was
checked with the pixel probe (static) and, in the second sweep, the hosted layer spike. The last three rows are the designs of
§5–§6.

| modifier (spike name) | blend reaches the header | rows present / transform | verdict |
|---|---|---|---|
| none | yes | culled (12 → 14), pushed down to every row | tears (lat 397 pt) |
| `.clipped()`, `.clipShape` of a rect 2 000 / 100 000 pt larger, `.mask` of the large rect | yes | culled, pushed down | no boundary: as none |
| `.blendMode(.normal)`, `.projectionEffect` (m34 −1e-9), `.hoverEffect(.automatic)`, `.opacity(0.99999)` | yes | culled, pushed down | as none |
| `.transformEffect(.identity)`, `.colorMultiply(white 0.99999)`, `.saturation(0.99999)` | yes (saturation: not shot) | culled (12 → 14), pushed down | as none |
| `.compositingGroup()` (today), `.compositingGroup().clipShape(…)` | **no** | all 30, on the group | isolates |
| `.drawingGroup()` | **no** | rasterized | isolates, offscreen |
| `.shadow(opacity 0.001, radius 0.01)` | **no** | all 30, pushed down | isolates, offscreen |
| `.mask(gradient)` | **no** | all 30, on the group | isolates, offscreen (mask) |
| **G**: no group under the transform; ONE `compositingGroup()` above it around the content and the `.slideBehind` slot | yes | all 30, pushed down | rigid (§6.2), but a new fade difference (§4) |
| **G + public probe** (G, its layer's `allowsGroupOpacity` off) | yes (not behind the scroll view) | as G | item 29 + fades fixed; S10 blends behind stay isolated |
| **P**: today's group, a probe turns `allowsGroupOpacity` and (private) `allowsGroupBlending` off | yes, also behind | as today | **every probe pixel = 17+ (§5.3)** |

Why G is still rigid: what a rigid rotation needs is not "the transform on one layer" but "no row culled or rebuilt during the
rotation". Inside any group SwiftUI stops culling against the ancestor clip, so all rows keep their layers. Each row's layer
then gets the pushed-down transform at both ends of the rotation, and Core Animation interpolates each one linearly with the
same timing.
- With a constant zoom `k`, the composite path of a row, `p(s) + k·r(s)`, is the same linear path a group would give it.
- With a zoom change during the rotation, neighbouring rows still share their edges. The scale interpolates linearly on every
  row, so the edge `= lerp(p0 + k0·a, p1 + k1·a) ± k(s)·h/2` meets its neighbour exactly.

## 4. Why no pure-SwiftUI design reaches 17+: the fade

Probe (spike demo): `-ZTronSpikeAncestorOpacity 0.5` puts `.opacity(0.5)` on the scroll view, inside the lab's blue, with no
blend probe. The content's first row (green, 80 pt) covers the lower 60 pt of the red header. The table gives the mean RGB in
that overlap. Every value is identical on 17.5 and 27.0 forced / preferred (`shotsP/o*`, `n*`, `q-*`, `r*-probe`), except the
G + public probe column, measured on 17.5 only (`pp-*`):

| content | 17+ | 15–16 today | G | G + public probe | P (probe, today's structure) |
|---|---|---|---|---|---|
| rows over the content's own background (the lab's blue; default) | (32, 128, 95) | (64, 128, 63) | (0, 128, 127) | (32, 128, 95) | (32, 128, 95) |
| rows only (`-ZTronSpikeNoContentBG 1`) | (64, 128, 63) | (64, 128, 63) | **(0, 128, 127)** | (64, 128, 63) | (64, 128, 63) |

These are exactly the compositing predictions:
- 17+ fades each leaf. Green 0.5 over the content's blue 0.5 over the header's red 0.5 over the blue gives (32, 128, 95);
  without the content's background, (64, 128, 63).
- Today flattens the content (green over its blue = green) and the header separately, then fades each image: (64, 128, 63) in
  both rows. The first row is the pre-existing S10 difference ("an ancestor's opacity fades it as one image").
- G flattens header and content TOGETHER, so the header vanishes under the content: (0, 128, 127) in both rows. The second
  row is new: there, today matches 17+ and G does not.

What this proves, with §3:
- A content blend reaches the header only inside a group that holds both of them.
- Every public 15–16 group that keeps the rows' layers is a flattening group (compositing, drawing, shadow, gradient mask:
  `allowsGroupOpacity` on, or a rasterized or offscreen image). Under an ancestor's opacity, such a group draws the header
  behind the content differently from 17+.
- A non-flattening boundary does not exist below iOS 17 (`geometryGroup()` is that boundary).
- Hence item 29 cannot be fixed in pure SwiftUI without a new 15–16 difference. That difference shows in every fade of a view
  with the content over a `.slideBehind` header: an `.opacity` transition, or any `.opacity(_:)` animation on an ancestor.

Duplicating the header as the content's backdrop also fails. The duplicate doubles under a fade (0.75 instead of 0.5 where the
content is transparent), and it duplicates `@State` and VoiceOver (§7).

## 5. Route P (proposed D77): turn the 15–16 group into what `geometryGroup()` is

### 5.1 Mechanism

`compositingGroup()` (15–16) and `geometryGroup()` (17+) both make a layer boundary that SwiftUI does not cull inside. They
differ in two `CALayer` flags (§2):
- `allowsGroupOpacity`: public, settable.
- `allowsGroupBlending`: private, settable by key-value coding.

A probe view inside the group reaches the boundary's layer and sets both flags to 0, as 17+ does. Rigidity is untouched: the
boundary and its culling stay, and the flags only change how blends and an inherited opacity composite. With the flags off,
Core Animation no longer needs an offscreen pass for a group that holds a blend-mode row (as on 17+).

### 5.2 Structure and files

- New `Sources/ZTronScrollView/Render/NeutralGroupProbe.swift` (the package is iOS only):
  - `struct NeutralGroupProbe: UIViewRepresentable`, which makes a `NeutralGroupProbeView`: 0 × 0,
    `isUserInteractionEnabled = false`, `isAccessibilityElement = false`, `accessibilityElementsHidden = true`.
  - `final class NeutralGroupProbeView: UIView` runs `neutralize()` from `didMoveToWindow`, `layoutSubviews` and
    `updateUIView`:
    - Once it has found its group (kept `weak`), it only turns the flags off again if SwiftUI set one; it never walks further.
    - Otherwise it walks `layer.superlayer` from the probe. It skips its own host (`superview?.layer`) and takes the FIRST
      layer with both flags 1.
    - The walk gives up at the hosting view (the first layer above the host with both flags 0 and a `UIView` delegate) or
      at a `UIWindow`. It never touches a layer above the hosting view: the UIKit chain above it is 1 / 1 and must stay so.
  - Neutralize = `allowsGroupOpacity = false` plus `setValue(false, forKey: Self.blendingKey)`. That is the one private key,
    a `static let`, not obfuscated. The set is guarded by `CALayer.instancesRespond(to:)` for its setter, checked once: a
    key-value set on a missing key raises an Objective-C exception, so without the property the probe sets only the public
    flag and notes `group.neutral.blending = unavailable` (a test failure, not a crash).
  - DEBUG: `ZTronRenderCounters` notes `group.neutral.<kind>` = `found@<depth>` / `none`, and a count
    `group.neutral.reset` (tests).
  - `extension View { func neutralCompositingGroup() -> some View }` (internal) =
    `background(NeutralGroupProbe().frame(width: 0, height: 0)).compositingGroup()`. The probe is INSIDE the group.
- The 15–16 branches only call `neutralCompositingGroup()` instead of `compositingGroup()`:
  - `Render/ContentTransform.swift:267` (`ContentLayerGroup`);
  - `ScalingHeader/HeaderFrameModifier.swift:412` (`HeaderLayerGroup`);
  - `Refresh/RefreshIndicators.swift:751` (`RefreshIndicatorGroup`, kind `.compositing`).
  
  The 17+ `geometryGroup()` branches are untouched (no probe in a 17+ tree). The latches are unchanged (`GroupLatch`
  "content.group" / "refresh.group"): the decision is still taken once at the first render, and the probe lives inside the
  latched branch.
- Doc comments: `ContentLayerGroup` (`ContentTransform.swift:232-256`), `HeaderLayerGroup` (`HeaderFrameModifier.swift:392-
  408`), `RefreshIndicatorGroup` (`RefreshIndicators.swift:~720-741`), `Availability/ZTronCapability.swift:60-62`.
- Spike evidence for the handle (`spike/spike-routeP.diff`, `SpikeGroupProbe` in `ContentTransform.swift`):
  - 27.0: probe → host (0 / 0, skipped) → group (1 / 1, the viewport frame, depth 2) → hosting view (0 / 0) → UIKit chain
    (1 / 1).
  - 17.5: probe → host (1 / 1, skipped by identity) → group (1 / 1, depth 2) → hosting view (0 / 0).
  
  The content's group and the header's were both found at depth 2 on both OS versions.

### 5.3 Measurements (17.5 and 27.0, forced = the 15–16 code path; `shotsP/`)

| probe | 17+ | 15–16 today | P, window-walk spike | P, probe view |
|---|---|---|---|---|
| blend: over the header / over the blue behind | cyan / yellow | white / white | cyan / yellow (`b1`, `b2`, `q-b-today-P1`) | cyan / yellow (`r17-b-probe`, `r27-b-probe`) |
| fade 0.5, content background | (32, 128, 95) | (64, 128, 63) | (32, 128, 95) (`o5`, `q-o-today-P2`) | (32, 128, 95) (`r17-o-probe`, `r27-o-probe`) |
| fade 0.5, rows only | (64, 128, 63) | (64, 128, 63) | (64, 128, 63) on G's structure (`n4`, `q-n-g-P2`) | (64, 128, 63) (`r17-n-probe`, `r27-n-probe`) |

- **Both flags are needed.** Turning off `allowsGroupBlending` alone fixes the blends and leaves the fade as today's
  (`o6`: (64, 128, 63) with the background). Turning off `allowsGroupOpacity` alone fixes the fades and leaves the blends
  isolated (`pp-o-today` / `pp-b-today`). Both are needed.
- **Persistence.** A scripted run (`-ZTronSpikeAutoMotion 1`) does a transaction scroll at 3.0 s, a width animation at 4.6 s
  and an animated header collapse at 6.4 s.
  - The window-walk spike checked the flags 12 times between 0.8 and 8.5 s: 0 set again on 17.5, with today's structure and
    with G.
  - The probe logged no re-neutralization on 17.5 and 27.0, and the probe still drew blended (cyan over the header) after the
    motions.
- **Cost.** Per frame nothing changes from today: the same group, the same 3–4 moved layers per scroll step, no culling, no
  per-leaf moves. Added: one 0 × 0 platform view per 15–16 group (2–4 per scroll view) and one short walk at attach. To be
  confirmed with the perf harness at step 3 (§9).

### 5.4 Scope, the S16 exception, App Review

- **Scope.** P is active only where the 15–16 groups exist: iOS < 17 and the forced lane. The 17+ path has no probe and no
  change. P is one file, and every branch it adds is covered (§9).
- **S16 / CLAUDE.md non-negotiables.** "No UIKit/AppKit, *Representable, … reflection or private API": P needs three
  exceptions, all confined to `NeutralGroupProbe.swift`:
  - UIKit,
  - a `UIViewRepresentable`,
  - one private key by KVC.
  
  The precedent is the user's ruling of 2026-11-02 (parity without appeal: a scoped UIKit / reflection route at 100 %
  coverage, D74). S16 and the non-negotiables change only if the user accepts this evaluated design.
- **App Review.** `allowsGroupBlending` is not in the public SDK (QuartzCore's `CALayer.h` declares `allowsGroupOpacity`,
  not it). Setting it by key is non-public API use under guideline 2.5.1.
  - It ships in every app that links the library, on every OS. App Review scans the binary, not the code path.
  - The key must not be hidden.
  - Whether the automated scan flags a KVC string is unknown. The user decides. An Organizer "Validate App" of an archived
    demo is the cheapest signal; it needs the user's account.
  - On the OS side the property cannot change: only iOS 15–16 run this path, and their `CALayer` is frozen.

### 5.5 What P also closes

The S10 "15–16 layer groups" differences, because the groups become 17+'s:
- a content blend against what is behind the scroll view (measured: yellow);
- a header's own blend over the content (`.compress`) or over the parent (`.slideBehind`);
- an indicator's blend under a header;
- an ancestor's opacity fading a group as one image (measured).

Not measured: the header's and the indicator's own blends. They work by the same mechanism, and the unit tests read the
flags of all three groups (§9).

Possible follow-up for the refresh owner, not part of D77 (D66 unchanged): with the groups neutral, the headerless
custom-indicator compromise (open item 20, D66: no group, so that its blend reaches behind) could group every box. The box
would then be rigid with its offscreen layer kept, and its blend would still reach behind.

### 5.6 If the private key is refused: D77′ = G + public probe

G (§6) plus the probe turning off `allowsGroupOpacity` only, on G's layer and on the header's group.
- Measured (17.5 forced): cyan over the header (`pp-b-g`), fades equal 17+ in both content kinds (`pp-o-g`, `pp-n-g`), as
  rigid as G (§6.2).
- Remaining 15–16 differences (pre-existing S10, not item 29): a content blend against what is behind the scroll view (white
  over the blue), a header's own blend, an indicator's under a header. These stay blocked: the only switch is the private
  key, no public `CALayer` or SwiftUI property does it, and every public boundary isolates (§3).
- Cost: G's per-leaf moves (§6.5). D77′ still needs the UIKit / `Representable` exception, but no private API.

## 6. G, measured (the pure-SwiftUI design; the structure of D77′)

### 6.1 Structure

```
container (clip)
├── [15–16 with a header] ViewportLayerGroup = compositingGroup()   ← above the content transform
│   ├── .slideBehind slot: HeaderOverlay(behind: true) (header group inside, unchanged)
│   └── content … TransformHost → ContentLayerGroup (17+ geometryGroup only; 15–16 nothing) → ContentTransform
├── .compress slot: HeaderOverlay (header group, unchanged)
├── RefreshOverlay (D65 / D66 boxes and groups, unchanged)
└── ScrollIndicatorsOverlay …
```

`ViewportLayerGroup(fallback: !state.usesGeometryGroup, hasHeader: header != nil)` sits after the behind slot
(`ZTronScrollView.swift:162`), latched by `GroupLatch` (note `content.group`, so
`HeaderReviewD16Tests.theFifteenContentGroupIsOnlyForAViewWithAHeader` keeps its expectations). It covers both collapse
modes (policy P1). The other policy, P2 (G only for a first-render `.slideBehind`), brings item 29 back on a runtime
`.compress` → `.slideBehind` switch.

### 6.2 Rigid rotations and the other motions (27.0 forced, `scripts/seam/table.py`; gap / overlap / lateral pt, hJ / cJ)

| scenario | today | G | note |
|---|---|---|---|
| aspect half `.slideBehind` rotate | 0.2 / 0.2 / 0.3, .10 / .10 | 0.2 / 0.2 / 0.3, .10 / .10 | control without a group: lat 397.2, split 17 |
| aspect half `.slideBehind` rotate from landscape | – | 0.2 / 0.2 / 0.4, .10 / .10 | |
| fixed half `.slideBehind(parallax: 1)` rotate | – | 0.3 / 0.0 / 0.2, – / .10 | |
| aspect rest `.stretch` hold `.slideBehind` rotate | 0.5 / 0.0 / 0.1, .24 / .18 | 0.5 / 0.0 / 0.1, .25 / .14* | hold probe over the content: 0 / 84 and 0 / 86 frames |
| aspect rest `.preserve` `.openGap` uncapped hold rotate (compress) | 60.0 (the gap) / 0.0 / 0.1, .17 / .16* | 60.0 / 0.0 / 0.1, .12 / .12* | the hold's designed gap (D65); `--open-gap hold`: header bottom deviation 0.0 / 0.0; probe over the content 0 / 83 and 0 / 66 |
| aspect rest `.compress` rotate | – | 0.0 / 0.1 / 0.1, .12 / .12* | |
| banner (horizontal) aspect rest `.slideBehind` rotate | – | 0.0 / 0.2 / 0.4, .10 / .10 | |
| aspect half `.slideBehind` width | – | 0.2 / 0.0 / 0.2, .03 / .03 | |
| aspect half `.slideBehind` height 0.4 (top-pinned) | 0.2 / 0.0 / – | 0.2 / 0.0 / – | |
| fixed rest `.slideBehind` band scroll 0.5 | – | 0.2 / 0.0 / –, .03 / .03 | |
| fixed rest `.slideBehind(parallax: 1)` snap | – | 0.2 / 0.3 / –, – / .07 | |
| aspect rest `.stretch` `.slideBehind` pull | – | 0.5 / 0.2 / –, .08 / .08 | |
| fixed rest `.slideBehind` fling | 17.8 / 0.0 / – | 17.2 / 0.0 / – (16.5 / 0.3 in a second run) | 27.0 preferred: 17.2 / 0.3; §6.3 |

`*` = the analyzer's ambiguous-frame mark. Loads (`uptime` 1-min) were below 300 during the G rows, with two exceptions:
`slide-rot-cur` (362; it matches its G twin) and lane f27a's blend rows (188–726). Those blend rows were re-run in f27b at
39–204 with the same results.

### 6.3 Fling

The fling rows read a 16.5–17.8 pt "gap" and about 138 ambiguous / 75 split frames on EVERY build and lane: today's forced
17.8, G 17.2 and 16.5, 27.0 preferred 17.2. The fling's bounce at the top opens the `.openGap` gap below the still
`.preserve` header by design (D65). It is not a G effect.

### 6.4 Static probes (27.0, `shots/n27*`, mean RGB over the probe, over the header / over the blue behind)

| probe | 27.0 preferred | forced today | forced G |
|---|---|---|---|
| white `.difference` | cyan / yellow | white / white | **cyan** / white |
| yellow `.multiply` | red / black | yellow / yellow | **red** / yellow |
| `.regularMaterial` row | (246, 187, 197) / (229, 189, 216) | identical | identical (0 px differ from today) |

A material's backdrop is not confined by the group on either 15–16 build: materials already match 17+.

### 6.5 Cost

Hosted harness `SpikeI29PerfTests`, run on the 27.0 sim:
- Setup: 402 × 874, a non-lazy `VStack` of `Text` rows with a background, and a `.fixed(min: 0, max: 100)` `.slideBehind`
  header.
- Rounds: 7–9 rounds × 120 programmatic scroll steps, each step with `layoutIfNeeded` + `CATransaction.flush`.
- Runs: unit5 (up to 1 500 rows) and unit7 (up to 1 000 rows, plus the 17+ path), at host load 95–270.
- The table gives the minimum ms per step:

| variant | moved per step | 100 rows | 300 rows | 1 000 rows | 1 500 rows |
|---|---|---|---|---|---|
| 17+ path (`geometryGroup`) | 3–4 | 1.09 | 2.57 | 5.64 | – |
| 15–16 today (= route P's structure) | 3–4 | 0.60–0.76 | 1.32–3.07 | 10.9 | 19.9 |
| **15–16 G** | 2 per row (all leaves) | 1.83–2.11 | 5.44 (13.4 at load 212) | 22.2 | 34.8 |
| 15–16 header without a group (tears) | 35 | 0.76 | 1.17–3.7 | 5.6 | 6.3 |
| 15–16 headerless (today's headerless path) | 35–36 | 0.84–0.91 | 1.82–2.9 | 5.0 | 6.6 |

- G moves every content leaf, which adds about 5.5–7 µs per leaf per step: +1.1–1.5 ms at 100 rows, +4 ms at 300, +11 ms at
  1 000, +15 ms at 1 500. That is about 2× the 17+ path at 100–300 rows and 4× at 1 000.
- Route P keeps today's row.

### 6.6 Suite under G

unit6 ran the full suite with G on by default: 840 tests, the 9 known issues of the base, and 1 failure:
`RefreshIndicatorLayerTests.anAnimatedSafeAreaInsetSlidesTheHoldWithTheFrame`, case preferred / gap (rest 2.67 instead of
30). Re-run alone under the unit lock (unit8), it failed a different case, forced / gap ("nothing drawn at rest"), and the
other 3 cases passed with bad = 0. Its view has no header, so neither G nor P is active in it, and the spike's code path
equals the base. This is a load-sensitive flake of the base test, reported to the lead.

## 7. Other alternatives rejected

- **A. The `.slideBehind` header inside today's content group, counter-transformed.** It has the same fade flattening as G
  (§4). It also lays the header out in content space under `ContentInteractionGate` (D11 would disable its controls), under
  the inverse of `ContentTransform`'s matrix, changes its VoiceOver order, and takes its slot out of the container's pass
  (D59, D62).
- **B′. Any other boundary under the transform** (§3): each one either isolates or culls.
- **No group (the control).** Tears: lateral 397.2 pt, split 17.
- **A group only during rotations.** The identity flip loses the content's `@State` (S4/R6), and a rotation is not known
  before UIKit's block starts.
- **A copy of the header as the content's backdrop.** It doubles under a fade, creates two instances (duplicate `@State`,
  builder runs, VoiceOver elements), and leaves a seam between them in rotations.
- **P2** (G only for `.slideBehind`): §6.1.
- **The content hosted in its own `UIHostingController`.** This public UIKit route was not built. It would mean a second
  SwiftUI graph (environment, preferences, transactions, S4 budget), and its platform view's layer is UIKit's (1 / 1), so the
  blends would isolate again without the private key.

## 8. Exact changes and build steps (route P, D77; each one green commit; only after the user accepts §5.4)

1. **Library: the neutral group.**
   - Add `Render/NeutralGroupProbe.swift` (§5.2).
   - Make the three 15–16 branches call `neutralCompositingGroup()`.
   - Update the doc comments (`ContentLayerGroup`, `HeaderLayerGroup`, `RefreshIndicatorGroup`, `GroupLatch`, and
     `ZTronCapability.swift:60-62`).
   - Gate: `scripts/build.sh`; `scripts/test.sh -only-testing:ZTronScrollViewTests/HeaderReviewD16Tests
     -only-testing:ZTronScrollViewTests/HeaderLayoutFrameTests -only-testing:ZTronScrollViewTests/HeaderSlideBehindTests
     -only-testing:ZTronScrollViewTests/RefreshIndicatorLayerTests` on 27.0.
   - Commit.
2. **Demo + seam tools.**
   - `SeamLabScreen.swift` arguments:
     - `-ZTronSeamBlend difference|multiply` (`SeamLabBlendProbe`: the first rows are a white `.difference` / yellow
       `.multiply` probe with nothing of the content behind it);
     - `-ZTronSeamBlendHeight <pt>`;
     - `-ZTronSeamAncestorOpacity <x>` (`.opacity(x)` on the scroll view inside the lab's blue);
     - `-ZTronSeamNoContentBackground 1`;
     - `-ZTronSeamScrollFrom <f>`.
   - `scripts/seam/baseline.sh` extras: `blend`, `blendm`, `fade<digits>`, `nobg`, `band<digits>` (matched before the plain
     `band`), `from<digits>`.
   - `scripts/seam/blendtrack.py` and `scripts/seam/segs.py` (from `tools/`).
   - Gate: `scripts/build.sh`.
   - Commit.
3. **Tests.**
   - Unit, new `Tests/ZTronScrollViewTests/NeutralGroupProbeTests.swift` (hosted window, `OSPath.allCases`):
     - (a) Forced: the content group's, the header group's and a refresh box group's layers read `allowsGroupOpacity` false
       and (KVC) `allowsGroupBlending` false after the first layout. Preferred: no `NeutralGroupProbeView` in the window.
     - (b) The flags stay off through 120 scroll frames, a 402 ↔ 874 resize, a header collapse, a refresh hold, a colour-scheme
       change and a remove / re-add of the hosting view (the probe re-finds its group).
     - (c) No layer above the hosting view changes (the window chain's flags read before and after), and a caller's own
       `.compositingGroup()` around the scroll view keeps 1 / 1.
     - (d) The probe is neither hit-testable nor an accessibility element, and the VoiceOver order of
       `HeaderSlideBehindTests` is unchanged.
     - (e) Render counters: content bodies 0 over those motions (S4); the probe's `updateUIView` runs at most once per
       container body.
     - (f) The perf harness row equals today's 15–16 within 10 % at 100 / 300 / 1 000 rows.
   - UI:
     - `HeaderUITests.testSlideBehindContentBlendReachesTheHeader`: seam lab `fixed half slideBehind blend`, colour runs down
       the probe's column (cyan and red names added to the helper). Cyan ≥ 55 of the 60 pt over the header and yellow ≥ 15
       of the 20 pt below it, on every lane.
     - `HeaderUITests.testAFadedSlideBehindViewDrawsAsThePreferredPath`: `fade50` with and without `nobg`; the overlap equals
       (32, 128, 95) / (64, 128, 63) ± 2 on every lane.
     - `RefreshUITests.testACustomIndicatorsBlendModeReachesWhatIsBehindIt`, plus a header variant that now passes on the
       forced lane.
   - Gate: the suites on 27.0 and 17.5, then the UI tests on 27.0, 17.5 and forced.
   - Commit.
4. **Docs.**
   - SPEC S10: the item 29 bullet (712-714); "Rigid layer groups" (894-903): the 15–16 group is neutralized; "15–16 layer
     groups" (904-…): the documented differences are removed. No known-limit text.
   - S16 and the CLAUDE.md non-negotiables: the user-approved exception, named file, the private key.
   - Orchestration: item 29 FIXED (D77) and D77 recorded.
   - Commit.

**D77′ (the private key refused).** Step 1 differs:
- New `Render/ViewportLayerGroup.swift` (G, `GroupLatch` "content.group"), inserted in `ZTronScrollView.swift` after the
  behind slot (162).
- `TransformHost` loses `hasHeader` (`ContentTransform.swift:179-180, 204`), and `ContentLayerGroup` keeps only its 17+
  branch.
- The probe sets only `allowsGroupOpacity` (no private key).

Steps 2–4 stay as above, except that the forced lane's expectation below the header stays white. That case is recorded as an
open item for the user: blocked, it needs the private key.

## 9. Acceptance

Thresholds (the user's PASS): |seam| ≤ 1 pt, lateral ≤ 1 pt, no 60 Hz step ≥ 0.5 of the change (hJ / cJ), a refresh
indicator drawn 0 frames over the content (`probeover.py`). Lanes: 27.0 preferred, 17.5, 27.0 forced. Recordings made at
load > ~300 are re-run.

- **Pixels**, every lane:
  - Static: cyan over the header and yellow over the blue behind; the fade overlap at the 17+ value ± 2.
  - `blendtrack.py` on `fixed-half-preserve-rotate-slide-blend`, `aspect-half-preserve-rotate-slide-blend`,
    `fixed-half-preserve-width-slide-blend` and `fixed-half-preserve-scroll-slide-blend-band95-from40`: 0 failing frames and
    cyan in every lab frame that shows the header. Plus the same with yellow tracked in the 20 pt below the header (P only).
- **Seams.** P keeps today's group and its culling, so the forced lane must equal today's on these §6.2 rows:
  `aspect-half-preserve-rotate-slide`, `aspect-half-preserve-rotatel-slide`, `fixed-half-preserve-rotate-slide1`,
  `aspect-rest-stretch-rotate-hold-slide`, `aspect-rest-preserve-rotate-uncapped-hold-opengap` (analyzed `--open-gap hold`),
  `aspect-rest-preserve-rotate`, `aspect-rest-preserve-rotate-horizontal-slide`, `aspect-half-preserve-width-slide`,
  `fixed-rest-preserve-scroll-band-slide`, `fixed-rest-preserve-snap-slide1`, `aspect-rest-stretch-pull-slide`. The 17+ lanes
  must equal the base.
- **Unit**, on 27.0 and 17.5: `NeutralGroupProbeTests` (a)–(f), `HeaderReviewD16Tests`, `HeaderLayoutFrameTests` (its
  `theRigidGroupKeepsIdentityAndAddsNoOffscreenPass` holds: no rasterization, filter or mask), `HeaderSlideBehindTests`,
  `HeaderStretchScaleTests`, `RefreshIndicatorLayerTests`. Then the full suite.
- **UI** (one demo UI lane machine-wide): the three pixel tests of step 3, plus `HeaderUITests`
  `testSlideBehindHeaderButtonTapsOnlyWhereUncovered`, `testSlideBehindMovesByTheParallaxAndIsAnnouncedFirst` and
  `testAppBannerSlideBehindStaysBelowTheBar` (hit-testing and VoiceOver unchanged).
- **Render counters**: content bodies 0 over scroll, zoom, collapse, refresh hold and resize.
- **D77′ adds**: G's seam rows of §6.2 within PASS on the forced lane, and the §6.5 cost accepted by the user.

## 10. iOS availability, S4, S7

- `compositingGroup()`, `UIViewRepresentable` and `allowsGroupOpacity` are public on iOS 15. `allowsGroupBlending` is private:
  present on 17.5 and 27.0 (the spike set it), and its presence on 15.0 / 16.0 is §12.1's first check (the probe guards the
  set, §5.2). No `#available` is needed, and nothing is new on 17+ (no probe in that branch).
- S4: no body runs per frame.
  - The probe's `make` / `updateUIView` run with the group modifier's body, which is cold (the container's).
  - Its `layoutSubviews` runs at attach and when its 0 × 0 frame changes, which never happens.
  - The latches keep the branch fixed from the first render.
- S7: layout and the rotation's target math are untouched. The groups (and D77′'s G) keep every row's layer, so the
  visible-centre tests do not depend on the change.

## 11. Risks

- **Private API (P).** App Review (§5.4). Mitigation: the user's decision; D77′ if refused.
- **The handle on real iOS 15.0 / 16.0.** The layer chain may hold more host wrappers. The probe then takes the first 1 / 1
  layer below the hosting view, which might be a wrapper instead of the group. That would leave the group isolating (a
  visible failure that the tests catch). It cannot touch UIKit above the hosting view. §12.1 checks the chain on 15.0 / 16.0.
- **SwiftUI rebuilding the group's layer** (identity change, trait change, a window move). The probe's `didMoveToWindow` /
  `layoutSubviews` re-run and find the new group; unit (b) covers this. Trait changes were not measured in the spike.
- **A platform view inside the content on 15–16.** On 17.5 / 27.0 forced it changed nothing measurable (pixels, motions).
  The seam rows of §9 verify it.
- **D77′ only**:
  - G's per-leaf cost on old devices (§6.5);
  - M9 rows materialized during a rotation would land at once inside G (they must stay alive within
    `max(width, height)` of the visible rect);
  - real 15.0 / 16.0 culling inside G, on which G's rigidity rests.

## 12. What a real iOS 15.0 / 16.0 run on the M1 should confirm

1. **The handle.** `CALayer` responds to the private setter on 15.0 and 16.0. In the DEBUG notes / probe log, the content's,
   the header's and a refresh box's group are found below the hosting view, and no layer above the hosting view changes. Run `NeutralGroupProbeTests` (a)–(c) on the 15.0 and 16.0
   sims.
2. **Pixels.** In the seam lab on 15.0 and 16.0, the blend is cyan over the header and yellow behind, and the fade overlap
   equals (32, 128, 95) / (64, 128, 63), the 17.5 preferred values.
3. **Persistence.** The flags stay off through a scroll, a width change, a collapse, a rotation, a colour-scheme change and
   background / foreground (unit (b) plus one XCUI run with the probe log).
4. **Rotations.** The §9 seam rows equal today's on 15.0 / 16.0, and all markers keep their layers inside the group.
5. **Cost.** Instruments (Animation Hitches) equals today's 15–16 build at 300 and 1 500 rows. For D77′, also G's per-leaf
   cost and no culling inside G.
6. **Not on the M1.** The App Review signal (Organizer "Validate App" of an archive) is the user's call.

## 13. Interactions with the other M8b-s8 designers

- **i28-stretch-blur** (proposed D76, `HeaderFrameModifier` / the header group): P edits `HeaderLayerGroup`'s 15–16 branch
  (`HeaderFrameModifier.swift:412`, one call) and its doc comment. That is conflict-prone with D76, so land it second and
  rebase. The probe sits inside the header group: re-run i28's `offscreenOffenders` unit and the `.slideBehind` pull rows
  after both land.
- **i15b-15path-resize** (proposed D78, `HeaderFallbackFrame` / `HeaderSlotLayout`): no shared lines. Re-run the forced width
  / height `.slideBehind` rows after both land.
- **d75-short-content** (D75, `ContentTransform` / layout host): P touches `ContentTransform.swift:267` and the
  `ContentLayerGroup` doc comment (D77′ touches `TransformHost` 179-204 too). Rebase the second to land.
- **refresh-27-31-32-33** (`RefreshIndicators`, `HeaderHost`): P changes one call in `RefreshIndicatorGroup`
  (`RefreshIndicators.swift:751`) and neither the latch nor D66. The §5.5 follow-up (grouping every box) is theirs to weigh.
- **D-numbers**: D75 d75, D76 i28, D77 this design (D77′ its variant), D78 i15b. Confirm against main and `git log --all`.

## 14. Spike artifacts

- **Scratch worktrees** (removed; base 09226f4):
  - `wt` held `SpikeGroup` / `SpikeOuterGroup` in `ContentTransform.swift` (variants by `-ZTronSpikeGroup`,
    `-ZTronSpikeHeaderGroup`, `-ZTronSpikeOuter`), the seam-lab probes, `SpikeI29LayerTests` and `SpikeI29PerfTests`.
  - `wt2` held the same plus route P: the window walk and `-ZTronSpikeNoGroupBlend / NoGroupOpacity / KeepGroupBlend` in
    `SeamLabScreen.swift`, `SpikeGroupProbe` (`-ZTronSpikeGroup probe -ZTronSpikeHeaderGroup probe`),
    `-ZTronSpikeAncestorOpacity`, `-ZTronSpikeNoContentBG` and `-ZTronSpikeAutoMotion`.
- **Saved diffs**: `spike/spike.diff` plus the two test files and `base.txt`; `spike/spike-routeP.diff`.
- **Recordings and analyses**: `seam/` (lanes f27a–f27d forced, r27p 27.0 preferred, r175 17.5; each lane's `.spec` and
  `.log`).
- **Shots**: `shots/` (G sweep, static probes) and `shotsP/` (fades, route P, D77′).
- **Unit logs**: `unit1.log`–`unit8.log` (unit5 / unit7 perf, unit6 the full suite under G, unit8 the lone re-run).
- **Tools** (`tools/`): `lane.sh`, `ui.sh`, `unit.sh`, `shot.sh`, `runs.py`, `segs.py`, `blendtrack.py`.
- **Not run**: the forced UI checks under G (`uiG`), cancelled before taking a lock once G stopped being the proposal.
