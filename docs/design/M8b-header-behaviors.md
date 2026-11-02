# M8b header behaviors: collapse `.slideBehind` (D68), pull `.stretch` as a scale effect (D69), split fade (D70)

Design for the builder. Base: SPEC S10 as of 2026-10-28 (D59–D66), code in `Sources/ZTronScrollView/ScalingHeader/`.
Decisions already taken with the user (not reopened here): parameters on `withScalingHeader`, `scalingBehavior:` → `pull:`
with a deprecated overload, `.slideBehind(parallax:)` default 0.5 with the header BEHIND the content, `.stretch` as a
render-time uniform scale anchored top-centre, the fade split "rest + per-direction, crossfaded". The quality bar is D62's:
no seam, no lateral drift, no one-frame step, on 27.0 / 17.5 / forced fallbacks.

## 1. Public API (`ScalingHeaderAPI.swift`, `HeaderTypes.swift`)

```swift
extension ZTronScrollView {
    /// Installs a scaling header above (or, with `.slideBehind`, behind) the content. Same contract as today; the
    /// reactions are split by scroll direction: `collapse:` for the content scrolling up over the header (o′ > 0),
    /// `pull:` for a pull past the top (o′ < 0; `.preserve` is refined by `scalingHeaderPullBehavior(_:)`, D65).
    public func withScalingHeader<Header: View>(
        size: ZTronHeaderSize,
        collapse: ZTronHeaderCollapseBehavior = .compress,        // D68
        pull: ZTronHeaderScalingBehavior = .preserve,             // the former `scalingBehavior:` (type kept)
        snap: ZTronHeaderSnap = .disabled,
        fade: ZTronHeaderFade? = nil,                             // D70: `.linear(…)` or `.init(rest:collapse:pull:)`
        background: ZTronHeaderBackground? = nil,
        overflow: ZTronHeaderOverflow = .uncapped,
        @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self

    /// Deprecated spelling. `scalingBehavior` has NO default, so `withScalingHeader(size:) { }` is never ambiguous.
    @available(*, deprecated, renamed: "withScalingHeader(size:collapse:pull:snap:fade:background:overflow:header:)")
    public func withScalingHeader<Header: View>(size: ZTronHeaderSize, scalingBehavior: ZTronHeaderScalingBehavior,
        snap: ZTronHeaderSnap = .disabled, fade: ZTronHeaderFade? = nil, background: ZTronHeaderBackground? = nil,
        overflow: ZTronHeaderOverflow = .uncapped, @ViewBuilder header: @escaping (ZTronHeaderProxy) -> Header) -> Self
    // forwards to `pull: scalingBehavior`
}

/// What the header does while the content scrolls up over it (o′ > 0). A struct (like `Animation`): `.slideBehind`
/// and `.slideBehind(parallax:)` both spell; an enum with a defaulted payload could not be written bare.
public struct ZTronHeaderCollapseBehavior: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case compress, slideBehind(parallax: CGFloat) }
    let kind: Kind
    /// Today's behavior: the header shrinks from its bottom edge (top pinned) to `min`; its subtree is laid out at the
    /// live height (sticky overlays follow the bottom edge).
    public static let compress: Self
    /// The header keeps its resting height R and is drawn BEHIND the content, which slides over it; it moves up by
    /// `parallax · covered` (0 = still, 1 = with the content). `min` is ignored (the content covers the whole header).
    public static let slideBehind: Self            // parallax 0.5
    public static func slideBehind(parallax: CGFloat) -> Self   // clamped to 0…1; NaN → 0.5 (DEBUG note)
    var parallax: CGFloat?                          // nil for .compress
}

/// D70. `.linear(to:from:)` keeps compiling and means that gradient in every state. The per-state form crossfades.
public struct ZTronHeaderFade: Equatable {
    public struct Gradient: Equatable {             // one state's gradient: clear at `start · band` → `color` at the band's end
        public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self
    }
    public var rest: Gradient?, collapse: Gradient?, pull: Gradient?      // nil = no fade in that state
    public init(rest: Gradient?, collapse: Gradient? = nil, pull: Gradient? = nil)
    public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self   // rest = collapse = pull = that gradient
}
```
`ZTronHeaderScalingBehavior` keeps its name and cases (`.preserve`, `.stretch`); `ZTronHeaderPullBehavior` and its member /
twin stay (they refine `.preserve`). `ZTronHeaderGeometry` is unchanged in shape: `progress` = collapse progress (`.slideBehind`:
the covered fraction), `height` = the DRAWN height (`.stretch`: R + g, scale included), `stretch` = g. Doc comment of
`withScalingHeader` gains: `.slideBehind` needs the content to paint its own background over the header's band (§3.4).
Internal: `HeaderSpec` / `HeaderSizing` / `HeaderMetrics` gain `collapse` (cold; a change goes through `headerSpecChanged()`);
`HeaderMetrics.band` becomes `collapse.parallax == nil ? max(0, resting − min) : resting`.

## 2. Math (`HeaderMath.swift`; extends the table in its header comment)

Conventions as today: `top0`, `R`, `min`, `o′`, `c = clamp(o′, 0, band)`, `g = max(0, −o′)`, `k` = parallax. `band` = `R − min`
(`.compress`) or `R` (`.slideBehind`: `min` ignored). New symbols: `h_L` the LAYOUT height (what the slot proposes the stack),
`h_v` the VISIBLE height (what the content leaves uncovered; the inset consumers' "live header height"), `s` the stretch scale.

| | `.compress` (today) | `.slideBehind(k)` |
|---|---|---|
| `h_L` (layout, `liveHeight`) | `(1 − p)·R(W,H) + p·min` — the stretch NO LONGER enters it (D69) | `R(W,H)` |
| `h_v` | `R − c` | `R − c` |
| collapse translation `t_c` | 0 | `−k·c` = `−k·p·h_L` (the layout's `h_L`, see §3.2) |
| pull translation `t_g` (`gapAbove`) | `g` with `.preserve .followContent`, else 0 | same |
| stretch scale `s` (`.stretch` pull only) | `h_L > 0 ? (h_L + g) / h_L : 1`; `c = 0` whenever `g > 0`, so `s = 1 + g/R` | same |
| drawn frame | `(0, top0 + t_g, W, h_L·s)`, clipped to that rect (wider content clipped at the sides) | `(0, top0 + t_g − k·c, W, R·s)` |
| header bottom edge (drawn) | `top0 + t_g + h_L·s` | `top0 + t_g − k·c + R·s` |
| content top (viewport y) | `aci.top − hold − o′ = top0 + ci.top + R − c + g` (unchanged, every mode) | same |
| `gapBelow` (`.preserve .openGap`) | `g` | `g` |
| `refreshTop` | unchanged: `.stretch` → `(top0 + R, overlay)`; `.followContent` → `(top0, false)`; `.openGap` → nil | same |
| `obscuredDelta` | `h_v + t_g − R = −c + t_g` | same (with `band = R`) |
| `progress` / `stretch` | `c / band` / `g` under `.stretch` | `c / R` / same |
| `ZTronHeaderGeometry.height` | `h_L·s` = `R − c + g` (as today's value) | `R + g` |
| z-order | header above the content (overlay) | header behind the content (background) |
| hit-testing / a11y visible | `h_v > 0.5` | `h_v > 0.5` |

Everything that reads the band (snap `snapOffset`/`nearestSnap`, `offset(for:)`, `keepProgress`, `resizeAnchor` /
`resizeOffsetY`, `solveTarget`, `HeaderResize.band`) works unchanged once `band` is mode-aware: `.slideBehind` snap
positions are covered fractions (`p·R`), `.height(h)` means the visible height (`o′ = R − clamp(h, 0, R)`), S7 keeps the covered
fraction across a rotation, `scrollTo` anchors see the uncovered top `aci.top + obscuredDelta`. Overflow (`.uncapped` /
`.capped` / `.refit`) resolves `R(W,H)` exactly as today (`layoutResting`) and the keyboard stays out of `H` (D64); `.slideBehind`'s
limited `min` is ignored. Banner (no vertical axis): `c ≡ 0`, `s ≡ 1`, `t_c ≡ 0` (only D15's zoomed pan moves it); `.stretch` stays inert
(DEBUG note as today). Degenerate `R = 0`: `s = 1`, `t_c = 0`. `min ≥ R` with `.compress`: band 0, `.stretch` still scales.
`keepProgress` across a `collapse:` change (band `R − min` → `R`) keeps the progress, as across a size change.
Stretch bit-stability (D62): during an open resize `g` is the anchor's `.top(x)` (as today), `s` is computed by the effect from
the DRAWN `h_L` (§3.1), so the unanimated commit changes nothing the header draws; `k·p` likewise.

Fade blend (D70), per frame, on the visible band `u ∈ [0, 1]` (`u = 0` the header's top, `u = 1` the band's end):
- band end in the header's local frame: `.compress` `y_end = h_L` (the whole frame; under `.stretch` the gradient is inside the
  scaled stack, so it stretches with the image); `.slideBehind` `y_end = R − (1 − k)·c` (the content's top edge in header-local
  coordinates: the fade reaches its color exactly where the content starts).
- weights: collapse `t = p` (covered fraction for `.slideBehind`); pull `t = min(1, g / (R / 2))` (full at half the header's
  height); at rest both 0; they are exclusive (`o′ > 0` vs `< 0`). A nil state = alpha 0 everywhere, color = the partner's.
- one gradient `α_X(u) = max(0, (u − start_X) / (1 − start_X))`; blended `α(u) = (1 − t)·α_A(u) + t·α_B(u)` with A = rest,
  B = collapse or pull. Same color (or one side nil, the common case `.linear(to: bg)` everywhere): ONE `LinearGradient(stops:)`
  with stops at the sorted union `{0, start_A, start_B, 1}` and `color.opacity(α(u))`: both α are piecewise linear with
  breakpoints in that set, so the gradient IS the interpolation (no dip). Different colors: two stacked gradients with the
  over-operator corrected, bottom A `a(u) = (1 − t)·α_A(u) / (1 − t·α_B(u))`, top B `b(u) = t·α_B(u)` — coverage
  `a + b − ab = α(u)` exactly at the stops, B's share exact; `a` is rational between stops, so add 6 interior stops per
  segment (error < 1 %). Gradient start/end points: `(0.5, 0)` → `(0.5, y_end / frameHeight)`, drawn as an overlay of the framed
  stack, above the content and the background, below the refresh indicator (as today). Clamp `start` to 0…1.

## 3. Host structure and data flow

### 3.1 `.stretch` as a scale effect (D69)
- `HeaderMath.liveHeight` drops `+ stretch`; `HeaderLiveInput.stateHeight` becomes `h_L` (`R − p·band`); `HeaderFallbackPlan` drops
  the stretch from `extra` / `outerPad` / `floor` and its `fitRest` condition (`c < 0.5` only). Add `HeaderLiveInput.visibleHeight`
  (`R − c`) for the `visible` gate.
- New `HeaderStretchEffect: GeometryEffect, Animatable` (nonisolated) with `live: HeaderLiveInput`, `animatableData = live.offset`
  (set: `live = live.at(offset:)`, as `HeaderTranslation`), `effectValue(size:)` = translate(W/2, 0) · scale(s) · translate(−W/2, 0)
  with `s = size.height > 0 ? (size.height + live.stretch) / size.height : 1` (identity when `stretch == 0`). The size is the stack's
  layout frame, so `s` uses the layout's `R(W,H)` on both paths (16+ `HeaderSlotLayout`, 15 `HeaderFallbackFrame`): bit-stable
  across the resize commit, interpolated by the drawn size in an app-animated resize (15–16: drawn per frame while no layout above
  it moves at the commit, the S9 "Indicator placement" rule; the stack's frame is the layout's, so none does).
- New `HeaderStretchClip: Shape, Animatable` (same `live` / `animatableData`): `path(in rect)` = `CGRect(0, 0, rect.width, rect.height · s)`.
  Replaces chrome's `.clipped()`: `framed.modifier(HeaderStretchEffect).clipShape(HeaderStretchClip)` — the clip is evaluated in the
  unscaled frame, so the scaled stack (wider than W, taller by g) is clipped to `W × h_L·s`: sides cut, bottom pinned to the
  content's top, no blank areas (a `background:` fills the scaled rect). Identity rect when `s = 1`, so collapse clips exactly as
  today. Then `HeaderLayerGroup` as today (the clip stays inside the header's group).
- Order inside the leaf (`HeaderFrameModifier.chrome`): `[fade overlay] → stretch effect → stretch clip → layer group → gates`.
  The fade is inside the scaled stack (it stretches with the image). All three read the SAME `live` the leaf computed for the
  slot in the same body (no frame lag); under a transaction-driven scroll each interpolates `o′` in that transaction, exactly
  as `HeaderTranslation` + `HeaderFallbackFrame` pair today.
- Refresh indicator: `refreshTop` unchanged (`top0 + R`, overlay forced): the hold `H` scales the header by `(R + H)/R` and the
  indicator floats over the scaled band. `RefreshResizeEffect.baseFollowsInset` unchanged.
- `ZTronHeaderGeometry.height` = `R − c + g` as today (the drawn height); readers inside the header are scaled with it (documented:
  a title sized from `height` under a pull is also scaled by `s`; use `restingHeight` for an unscaled size).

### 3.2 `.slideBehind` (D68): z-order, translation, hit-testing
- Host (`ZTronScrollView.swift:148–163`): after `.ignoresSafeArea(.all, edges: edges)` attach BOTH slots, always present
  (structure stable, R6/S4.2; the content is not inside either):
  `.background(alignment: .top) { HeaderOverlay(spec: header, state: state, behind: true) … }` then the existing
  `.overlay(alignment: .top) { HeaderOverlay(spec: header, state: state, behind: false) … }`, each with the same
  `ignoresSafeArea` pair (sides; `.keyboard` bottom). `HeaderOverlay` shows the host only when `spec.collapse.isSlideBehind == behind`.
  `.background(alignment:content:)` lays out like the overlay (same frame, same pass, top edge at the safe-area top), so D62's
  layout-driven geometry, the `.fit` measure, the keyboard-free slot (D64) and the rigid groups are untouched. Switching
  `collapse:` between the two modes moves the header to the other slot: its builder runs once more and its `@State` resets
  (documented; the content's identity is untouched; the latch `hasHeader` is the same).
- Translation from layout: `HeaderLiveInput.parallax: CGFloat` (k, or 0). 16+ `HeaderSlotLayout.placeSubviews`:
  `y = bounds.minY + live.translation − live.parallax · live.progress · h` with `h` the pass's own `height(at:slot:)`. 15 / forced:
  `HeaderTranslation` becomes a `GeometryEffect` (`ty = live.translation − live.parallax · live.progress · size.height`; `size` =
  the stack's frame = `h_L = R(W)` from the fallback frame). Both derive `t_c` from `(k, p)` and the LAYOUT's `R`, so an animated
  width change interpolates it with the content and the commit re-sets nothing (the 15 `.capped` / `.refit` known limit stays as is).
  Past full cover (`o′ ≥ R`) `p = 1`: the live input stops changing (no per-frame layout, like `.openGap` under a pull).
- Clip: the framed stack is clipped to its own frame as today; it is NOT clipped at `top0` when it moves up (it may draw under a
  translucent navigation bar, as UIKit parallax headers do; the scroll view clips at its own frame). A slot-level clip is possible
  but would be a second nested clip in rotations (the pre-intersection problem of D62's header clip): do not add one unless the
  lab shows a need.
- Hit-testing: the content layer is above the header, but the content's hit area is its own drawn frame (the transform is a
  `GeometryEffect`, applied to hit-testing; `ContentLayoutHost`'s box, the overlay host and the gates add no hit area), so touches
  in the uncovered band `[top0 − k·c, top0 + R − c]` fall through to the header in the background; a drag that starts there
  scrolls (the pan is on the container). Covered parts are unreachable, as they are hidden. `HeaderInteractionGate` and the
  `visible` gate (`h_v > 0.5`) apply unchanged. VERIFY on 27.0 / 17.5 / forced with the demo's `taps` counter (§5).
- Content background requirement + remedy: the content must paint its own background where it covers the header (a `List` row
  with a clear background shows the header through the text). Library remedy, cheap and structural: `.slideBehind(parallax:,
  backdrop: Color? = nil)`; when set, the content root gets `.background(backdrop)` INSIDE the transform (content space: it moves
  with the content as a render-time transform, covers exactly the content's rect, below the content-integral overlays; `nil` →
  `.background(Color.clear)` so the structure never changes). Recommended default in the docs: `backdrop: appBackground`.
  If the lead prefers the minimal API, keep `.slideBehind(parallax:)` only and document the requirement; the remedy is one line.
- Accessibility: the background host keeps `.accessibilityElement(children: .contain)` + `.accessibilitySortPriority(1)`: the
  header is announced before the content in both slots; hidden when `h_v ≤ 0.5`. VoiceOver reaches the header's controls
  through the hierarchy, not by occlusion: a covered button stays in the rotor until the gate hides it (same as a `.compress`
  header's child under a collapsing frame); acceptable, documented. Check with the a11y UI test that the order is header-first.
- 15–16 groups: the background slot carries the same `HeaderLayerGroup` (compositing group); the content group's latch is unchanged.
  Blend-mode isolation is as documented for 15–16 (a header blend mode does not reach the content above it).
- Refresh indicator: per `pull:` mode, unchanged; it is drawn in `RefreshOverlay`, above both slots.
- Fade (`.slideBehind`): gradient band end `y_end = R − (1 − k)·c` (§2); `start · y_end` from the top.

### 3.3 Fade driving (D70)
- Move the fade from the cold host (`HeaderHost.swift:36`, `.overlay(HeaderFade)`) into the hot leaf's chrome as
  `HeaderFadeOverlay: ViewModifier, Animatable` (`live` + `fade: ZTronHeaderFade?`, `animatableData = live.offset`), body =
  `content.overlay(gradient(for: live))` with `.allowsHitTesting(false).accessibilityHidden(true)`. It sits on the framed stack,
  so its `content` placeholder (the user's header) is never re-evaluated; only the gradient leaf is rebuilt. Stops from §2 in a
  pure `HeaderFadeMath.stops(fade:progress:pull:resting:collapse:) -> [Gradient.Stop]` (+ a `second` layer when the colors
  differ), unit-tested. Per-frame cost: one gradient layer update; `content.body` 0, `header.builder` 0.
- Both paths: the leaf's body passes the same `live` to the slot layout / fallback frame, the stretch effect, the clip and the
  fade in one update, so the fade never lags the geometry; in a transaction-driven scroll all of them interpolate `o′` in the same
  transaction (the `HeaderTranslation` + `HeaderFallbackFrame` precedent). During an open resize `p` and `g` are the anchor's
  (bit-stable), so the fade does not step at the commit.
- `ZTronHeaderFade.linear(to:from:)` yields `rest = collapse = pull` = the same gradient: `t` has no effect (both sides equal,
  one gradient), so the existing fade draws exactly as today in every state (`y_end` = the frame for `.compress`).

### 3.4 Horizontal pagers / banners
A view without the vertical axis: `.slideBehind` only changes the z-order (the banner is behind the content, which
`HeaderContentReserve` lays out below it, so nothing covers it: harmless, documented); `.stretch` inert; the fade shows `rest`
unless D15's zoomed pan drives `o′`. Inside a native horizontal pager (ZTronPages), nothing changes.

## 4. SPEC S10 text to add (summarised; the builder writes the amendment)
- API block: the new signature, the deprecated overload, `ZTronHeaderCollapseBehavior`, the `ZTronHeaderFade` set; migration row
  `.allowsHeaderGrowth()` → `pull: .stretch`; the reference's slide-up mode is now `.slideBehind(parallax: 1)`.
- Behavior: a "Collapse (D68)" paragraph (table of §2: `.slideBehind` keeps R, drawn behind the content, moves up by `k·c`, `min`
  ignored, snap = covered fraction, content must paint its background / `backdrop:`, not clipped at `top0`, switching modes
  re-installs the header). `.stretch` (D69): "grows by `g` as a render-time scale `(R + g)/R` anchored top-centre of the whole
  stack, clipped to `W × (R + g)`: an aspect-fit image grows with the pull; no relayout per frame; readers see the drawn height".
  Fade (D70): the blend rules of §2 and "no fade in a nil state". Placement of the refresh indicator: unchanged per `pull:`.
- Seamless edges: add that the stretch scale, the parallax translation and the fade are derived in the header's leaf from the
  same live input as the slot and from the layout's own `R`; `h = (1 − p)·R + p·min` (stretch removed from the layout height).

## 5. Tests
Unit (`scripts/test.sh -only-testing:ZTronScrollViewTests/HeaderMathTests` etc.):
1. `HeaderMathTests`: band per collapse mode; `geometry` height / progress for `.slideBehind` (`R + g`, `c/R`); `t_c = −k·c` clamped
   at `R`; `s = 1 + g/R`, `s = 1` for `R = 0`; `gapBelow` / `gapAbove` / `refreshTop` / `obscuredDelta` unchanged across collapse modes;
   `offset(for: .height)` under `.slideBehind`; `keepProgress` across a collapse-mode change; parallax clamping / NaN.
2. `HeaderFadeMathTests` (new): single-color stops are exact at 33 samples for t ∈ {0, .25, .5, 1}; two-color pair coverage within
   1 % of `α(u)`; nil states; `.linear` equals the per-state form with equal gradients; `y_end` for `.slideBehind`.
3. `HeaderLayoutFrameTests` (16+): `.stretch` places `(W, R)` not `(W, R + g)`; `.slideBehind` at `y = −k·p·h`; `HeaderFallbackPlan`
   without stretch (`extra = p·min`, `fitRest` at `c < 0.5` regardless of `g`).
4. `HeaderLiveInput.at(offset:)` re-derives stretch / parallax; `HeaderHeightResizeTests` pattern: a stretch hold and a half-covered
   `.slideBehind` across an unanimated commit change no drawn value (bit-stable).
5. `HeaderResizeTests` / S7: rotation keeps the covered fraction; centre rule with `band = R`. `HeaderSnapTests`: `.immediately`
   positions as covered fractions. `RefreshIndicatorMath` base per `pull:` with both collapse modes.
6. Render counters on both OS paths: `content.body` 0 and `header.builder` 1 through a collapse, a pull, a stretch hold and a
   fade crossfade; `header.frame` once per frame.
UI (`HeaderUITests`, 27.0 preferred / 17.5 / 27.0 forced): `-ZTronHeaderCollapse compress|slide|slide0|slide1`,
`-ZTronHeaderFade single|split|none`, `-ZTronHeaderBackdrop on|off`: a header button taps in the uncovered band under `.slideBehind`
(`taps` counter) and not once covered; VoiceOver order header-first; the deprecated overload compiles (a `#if` demo call);
a new demo screen `-ZTronScreen appbanner` reproducing the user's setup (NavigationView + GeometryReader, `.aspectRatio(16/9,
min: 0)`, `pull: .stretch`, `fade: .linear(to: appBackground)`, `overflow: .refit`, an aspect-fit `Image` with `maxWidth: .infinity`)
asserting that the image's drawn bottom edge moves down by the pull (a probe view pinned to the image's bottom; pixel probe on
the forced lane).
Seam lab (`scripts/seam`, 27.0 / 17.5 / forced; PASS |seam| ≤ 1, lateral ≤ 1, no one-frame step ≥ 0.5 of the change): new args
`-ZTronSeamCollapse compress|slideBehind[:k]`, `-ZTronSeamPullStretch scale`, `-ZTronSeamFade split`; scenarios: `ScrollBand`
with `slideBehind` (probe = the header's top marker: `t_c = −k·c` per frame, lateral), rotation and `withAnimation` width / height /
spring / retarget at half cover, `Pull` + `Hold` + end with the stretch scale (the header's drawn bottom edge vs the content's top;
the indicator over the band), rotation and `AnimateHeight` during a stretch hold, `kbreal` / `kbrotate` with the scale, the fade
crossfade under `withAnimation { scrollTo }` through the band (a pixel column's alpha vs the frame: no lag, no dip), `.capped` /
`.refit` with both modes (forced lane: the known F6 rows stay known).

## 6. Build plan (one green step each: edit → build → tests touched → commit)
1. Types and API: `ZTronHeaderCollapseBehavior`, `ZTronHeaderFade` set + `Gradient`, `collapse:` / `pull:` parameters, the
   deprecated overload, `HeaderSpec` / `HeaderSizing` / `HeaderMetrics.collapse`; everything still behaves as `.compress`.
   Fix call sites in the demo / tests (keep one deprecated call under `#if`). Unit suites green.
2. `HeaderMath`: mode-aware `band`, `visibleHeight`, `collapseTranslation`, `stretchScale`, fade math; `HeaderMathTests` +
   `HeaderFadeMathTests`.
3. D69: `HeaderStretchEffect` + `HeaderStretchClip` in the chrome; stretch out of `liveHeight` / `stateHeight` / `HeaderFallbackPlan`;
   `visible` from `visibleHeight`. Layout + resize unit tests; seam lab pull / hold / rotation-in-hold / keyboard on the three lanes;
   `RefreshUITests` + `HeaderUITests`.
4. D68: `HeaderLiveInput.parallax`, slot placement / `HeaderTranslation` effect, the background slot in the container, `backdrop:`,
   demo switch, hit-test and a11y UI tests, seam lab band / rotation / resize at half cover on the three lanes.
5. D70: `HeaderFadeOverlay` in the chrome (remove the host's cold `HeaderFade`), demo switch, pixel UI test (forced lane blend
   pattern), seam lab crossfade scenario.
6. `appbanner` demo + its UI test; SPEC S10 amendment, Orchestration D68–D70 + open items, handoff; full suite at the end.

## 7. Risks to check on device / in the lab
- Hit-testing through the content layer to a background header on the forced lane and 17.5 (a full-size element in the content
  chain would swallow the band); `ContentInteractionGate`'s `.disabled` must not reach the header.
  **Measured (step 4, 2026-11-02):** none on 27.0, 17.5 and 27.0 forced (`HeaderUITests`
  `testSlideBehindHeaderButtonTapsOnlyWhereUncovered`, 29/29 per lane): the header's button counts a tap half covered, not
  with 12 pt left uncovered (the content takes it), and again uncovered; the part moved above the scroll view takes no
  touches (the container's `contentShape`: the chrome's button under the 114 pt overflow works). The pan is attached after
  the container's `contentShape`, so a drag on the uncovered header scrolls; the gate is inside the content chain, the
  background slot outside it.
- The `.background` slot's top edge at the safe-area top on 15 / forced (the overlay needed an explicit `.top` frame).
  **Measured (step 4):** none: `HeaderSlideBehindTests` (both OS paths, 3 sizes x k 0 / 0.5 / 1 x rest / half / covered)
  find the header at `top0 − k·p·R`; the seam lab's ruler (white bars in the header, `-ZTronSeamRuler 1`) reads the drawn
  top at `top0 − k·c` within 0.44 pt on 17.5, 0.34 on 27.0, 0.33 forced (ScrollBand k 0 / 0.5 / 1, fling, snap, width /
  spring / retarget at half cover; worst one-frame step 0.12 of the move), `top0` = the safe-area top on every lane.
- A `clipShape` whose path animates inside a `compositingGroup()` during a system rotation of a stretch hold (CA interpolation of
  the mask), and the effect drawn per frame in an app-animated resize on 15–16.
  **Measured (step 3, 2026-11-01):** none on the forced lane (27.0, the 15–16 path): rotate holds |seam| ≤ 0.5 pt, lateral
  ≤ 0.25, jumps ≤ 0.24 (= preferred); the clip is a `Path(rect)`, no mask layer on either path; the app-animated width and
  AnimateHeight holds pass. Real 15–16 devices unmeasured (no runtime on macOS 27).
- Implicit animation of the gradient stops under a transaction-driven scroll (lag): the `Animatable` modifier precedent says no;
  measure with the crossfade scenario.
- `.slideBehind` under a translucent navigation bar: the header draws under the bar as it moves up (by design; confirm with the user).
  **Step 4:** per decision 3 it is clipped (drawing and touches) at the scroll view's own frame like the content, not at
  `top0`; so it draws under a bar only where the scroll view itself extends under it. The seam lab's scroll view is the
  safe-area rect, so its header is clipped at the safe-area top there; unit test `theHeaderIsClippedAtTheScrollViewsFrame`
  (a scroll view below a 200 pt spacer, k 1, half covered: no header pixel above it). Not yet seen under a real navigation
  bar (step 6's `appbanner` screen).
- 15–16 `.slideBehind`: the unclipped-at-`top0` header and the content group both inside the scroll view's clip; blend isolation.
  **Measured (step 4):** the clip holds on the forced lane (the unit clip test on both paths; 17 seam scenarios PASS,
  |seam| ≤ 0.5 pt, lateral ≤ 0.3, jumps ≤ 0.23 = preferred). Blend isolation not pixel-measured; from the code: the 15–16
  content group (`compositingGroup()`) keeps a content child's `.blendMode` from reaching the header behind it, while 17+
  (`geometryGroup()`) lets it (open item 29).
- Readers scaled under `.stretch` (text inside a scaled stack is rasterised by the scale on 15–16: slight blur while pulled).
  **Measured (step 3, 2026-11-01):** on EVERY lane (17.5, 27.0, 27.0 forced) the pulled header is its layer's bitmap
  scaled: a 24 pt text's edge width grows 1.25× (17.5) to 1.8× (27.0) at s = 1.25. Transient (pull / refresh hold only);
  a re-raster would re-run the header body (S4), so it is a documented limit (open item 28).
- Mode switch at runtime re-installs the header (`@State` lost) — acceptable? If not, both slots must share one host (harder).
  **Step 4:** accepted (decision 4) and documented on `.slideBehind(parallax:backdrop:)`; the switch keeps the covered
  fraction (the state's inset path now runs `keepProgress` when only the band changes) and runs no content body
  (`aModeSwitchAndABackdropRunNoContentBody`, both paths).

## 8. Lead decisions on the open questions (2026-11-01)
1. Type names: keep `ZTronHeaderScalingBehavior` as the `pull:` type (zero churn; the deprecated overload takes the same type).
   The D65 member `scalingHeaderPullBehavior(_:)` keeps its name; its doc comment says it refines `pull: .preserve`.
2. `backdrop:` is in the API: `.slideBehind(parallax: CGFloat = 0.5, backdrop: Color? = nil)` plus the bare `.slideBehind`.
   nil = the content draws as it is (documented requirement: paint an opaque background where it covers the header); the
   doc comment recommends the app's background colour. Drawn in content space as in §3.2 (structure never changes: nil →
   `Color.clear`). It must not re-evaluate content bodies when the backdrop or the mode changes (a cold spec change is fine).
3. A `.slideBehind` header is NOT clipped at `top0` (it may draw under a translucent bar, like the content does); verify in the
   lab that nothing draws outside the scroll view's own frame. If the lab shows the header drawn above the scroll view's frame
   (e.g. over a navigation bar region that the content itself never reaches), clip at the scroll view's frame, not at `top0`.
4. A runtime `collapse:` mode switch re-installing the header (its `@State` reset) is acceptable; document it in S10 and in the
   parameter's doc comment.
5. Risks §7 are the builder's checklist: each one is measured on 27.0, 17.5 and forced and recorded in the handoff.
