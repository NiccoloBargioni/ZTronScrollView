# i15b: the 15–16 path resolves the header from its own slot (open item 15 (b), F6, S-RS-2)

> Committed by the M8b-s8 architect (2026-11-03) from the designer's scratch doc, unchanged below this note. Build order, numbering and the architect's amendments: [M8b-s8-plan.md](M8b-s8-plan.md) (they win where they differ). Scratch paths (`s8/i15b-15path-resize/…`, `scratchpad/s8/…`) are gone after a reboot; the text artifacts (patches, tools, tables) persist in the shared notes folder `m8b-s8-resume/s8-spikes/i15b-15path-resize/`.

Designer `i15b-15path-resize`, batch M8b-s8, base `09226f4`. The spike ran in the scratch worktree `s8/i15b-15path-resize/wt`,
since removed. The final spike (A + C3) is saved as `s8/i15b-15path-resize/spikeC3.patch` (library) and
`s8/i15b-15path-resize/I15bSpikeTests.swift` (the hosted tests). Earlier states:

- `spikeAB.patch` / `spikeA/` / `spikeB/`;
- `spikeAC.patch`, `spikeC2.patch` (C2 = the width fit everywhere).
Lanes: 27.0 forced and 27.0 preferred on my iPhone 18 Pro clone; 17.5 (unit + seam) on my iPhone 15 Pro clone.

## 0. Verdict

- **Fixable in pure SwiftUI on iOS 15, with no API change** (proposed **D78**; D75 is d75's, D76 i28's, D77 i29's; the lead
  confirms the number).
- **Overflow-limited `R` and `.fixed` rows (spike A, "slot reader").** These cover S-RS-2, F6, the 70 / 35 / 31 / 84 / 115 pt rows
  and `.slideBehind(1)`. A cold `GeometryReader` around the 15-path header leaf gives the plan the slot's `W × H` in the app's
  animated pass. The plan then resolves `R(W, H)` with the same `HeaderMath.liveHeight` that 16+'s `HeaderSlotLayout` uses.
  - Forced lane: every row PASSes. Seam ≤ 0.333 pt, lateral ≤ 0.284 pt, step fraction ≤ 0.034 (HEAD: 1.00, the landing).
- **`.fit` inside the band (spike C, "ideal-ratio box").** `aspectRatio(nil)` reads the header content's ideal size. The box
  scales it by `1 − q` through `frame(idealWidth: W / (1 − q))` and clamps it to `[m′, L]`.
  - In a resize's animated pass the box is fitted to the slot width. The content is proposed 16+'s height `(1 − q)·R + q·m′`
    from its fresh ideal height, in the same layout pass.
  - At the committed viewport (C3) it is fitted to the committed live height, as 16+'s `layoutResting` does, and its width
    carries the measurement.
  - `R` is reported to the state the way 16+ reports it.
  - Forced (final C3 build, `c3f27`): all nine `.fit` rows PASS. These are width, rest, `.capped(0.25)`, `.slideBehind(1)`,
    retarget, sticky rotation, a scroll through the band, and the two content-change (grow) rows. Seam ≤ 0.5, lateral ≤ 0.372,
    step fraction ≤ 0.099 (the 0.099 is the rotation's own frame rate).
  - HEAD: 45.2 / 159.3 / 1.00. Spike B (a measuring flip driven in the app's transaction): 1.33 / 75.9.
- **Not this mechanism.**
  - 15 (c) (`combo`): the M5 intervention snaps the content, on every lane (§1.4). It stays item 15 (c), with its own fix.
  - The `.fit` grow re-measure on 15 is a header content change, not a resize. It was a documented gap before (SPEC S10
    "Natural height"). The box now measures it in the band. C2 adopted it with an 11-pt seam on 15 only; C3 applies 16+'s
    committed-`R` rule (§2.4).

## 1. Root cause

### 1.1 The 15 path reads `R` from the committed metrics; 16+ reads it from the layout proposal

An app-animated resize is one flush with two updates:

- **U0, the app's transaction (animated).** The viewport frame changes. Every layout that depends on the proposal is
  re-solved, and SwiftUI animates the change in the app's animation.
- **U1, the viewport commit (unanimated).** `applyViewport` writes `storage.metrics` inside `unanimated { … }`
  (`ZTronScrollState.swift` 823). That publishes the new `R`, band and container to the header leaf. D51 / D62 require that U1
  changes nothing in the header's layout ("bit-stability"). Whatever does change in U1 is re-set without animation, which is the
  landing.

The two paths compare as follows:

- **16+ (`HeaderSlotLayout`, `HeaderFrameModifier.swift` 229–284).** It receives the new `W × H` as its proposal in U0 and computes
  `HeaderMath.liveHeight(width: W, containerHeight: H, …)` there. The header's U0 target is therefore final, U1 changes nothing,
  and the header animates with the content.
- **15 / forced (`HeaderFallbackFrame` + `HeaderFallbackPlan.init(_ live:)`, 285–400).**
  - The plan is computed from `live.metrics`, the committed metrics. The only layout-driven exception is an unlimited
    `.aspectRatio`, whose `R` follows the width alone through `aspectRatio(r)`.
  - When `R` depends on the container height or is limited, the U0 layout keeps the old `R`. These are `.capped` / `.refit`
    engaged or released, `min ≥ R`, and `.fixed` under a limit.
  - U1 then writes the new `R`, and the plan's `minHeight = maxHeight` changes in an unanimated transaction. The header lands in
    the first frame while the content animates.

Evidence (27.0 forced, HEAD `09226f4`, lane `base27f`). In every row the header's whole step happens in the first animation frame
(`hdrJump` fraction 1.00) and the content's top moves smoothly (fraction ≤ 0.038):

| row (seam-lab scenario) | narrow / shrink | back |
|---|---|---|
| S-RS-2 `.compress` (`aspect-half-preserve-width-capped25-forced`) | gap 29.3, lateral 159.3, hJ 1.00 | overlap 29.3, hJ 1.00 |
| S-RS-2 `.slideBehind(1)` (`…-capped25-slide1-forced`) | gap 29.3, lateral 159.3, hJ 1.00 | 0.167 / 0.34 |
| `.capped(0.5)` height 0.4 at rest (`aspect-rest-preserve-width-capped-height04-forced`) | gap 70.0, hJ 1.00 | overlap 70.0, hJ 1.00 |
| same, half collapsed (`aspect-half-…-capped-height04-forced`) | gap 35.2, hJ 1.00 | overlap 35.2, hJ 1.00 |
| `.refit` height 0.25 (`aspect-rest-preserve-width-refit-height025-forced`) | gap 31.3, hJ 1.00 | overlap 26.0 |
| `.fixed(64…240)` capped (`fixed-rest-preserve-width-capped-height04-forced`) | gap 84.0, hJ 1.00 | overlap 84.2, hJ 1.00 |
| landscape (`aspect-rest-preserve-width-capped-height04-vland-forced`) | gap 114.8, hJ 1.00 | overlap 78.8, hJ 0.67 |
| `.fit` half, width (`fit-half-preserve-width-forced`) | gap 45.2, lateral 159.3, hJ 1.00 | overlap 45.2, hJ 1.00 |

Notes:

- The baseline lane ran at load 600–800. The landing is deterministic: it is code, not a timing effect, and spike A removes it at
  load 9–220.
- Unit proof on 17.5: `HeaderReviewD16Tests.anOverflowLimitThatTurnsOnDuringAnAnimatedResizeIsInTheAnimatedPass` is a
  `withKnownIssue … when: path == .forcedFallback` (115–136). With spike A, that known issue is no longer recorded ("Known issue was
  not recorded", u175C).

### 1.2 `.fit` in the band: the measurement needs a second layout, and 27.0 compounds every retarget

- On 15, `N(W)` (the content's ideal height at the new width) is measured by `HeaderMeasuringPass` (`HeaderMeasure.swift` 84–140).
  It is a `fixedSize(vertical:)` flip with a preference report, armed in U1 by the stale committed width.
- The report becomes `setHeaderNatural`, then a new metrics commit. In total, three updates retarget the header's rect in one flush:
  U0 (W), the flip (N), and the commit (R).
- **27.0 retarget chaining (measured).** Each animated retarget within a flush starts from the live value of the previous animation,
  so after `n` retargets the drawn rect is `(1 − e)^n` of the way. An unanimated change lands the rect.
- Spike B put the flip and the adoption in the app's animated transaction (`HeaderHost` `.transaction` override +
  `state.headerResizeAnimation`). It measured lateral 75.9 and gap 1.33 (`spkAB27f`), against HEAD's landing of 159.3 / 45.2.
  Nothing that needs a second layout can be seamless on this runtime.
- iOS 15's own retarget semantics are unknown on this host (§9). The fix must therefore not depend on them: the U0 layout has to
  be final.

### 1.3 Why only `.fit` needed more than the slot

- For `.aspectRatio`, `.fixed` and the overflow rules, `R(W, H)` is a pure function of the slot (`HeaderMath`). Giving the 15 plan
  the slot's `W × H` in U0 is enough (spike A).
- `.fit` needs `N(W)`, which only the content knows. 16+ asks for it inside `placeSubviews` (`sizeThatFits(width: W, height: nil)`).
  iOS 15 has no `Layout`, so the ask must be expressed with iOS 13 modifiers. That is the ideal-ratio box (spike C, §2.2).

### 1.4 Item 15 (c), `combo`: a different mechanism, not fixed here

- In the combo, the scroll command calls `beginIntervention()` (`ZTronScrollState.swift` 365). That calls `closeResize()` (1136),
  which writes the final metrics and offset `unanimated`.
- The content snaps to the committed geometry while the header keeps animating. Lateral, back segment:
  - forced, `base27f`: 50.0;
  - forced with spike A, `spkAB27f`: 52.1;
  - **27.0 preferred**, `ctlC27`: 53.3, with gap 29.8 and a content step of 31.2 pt (fraction 0.25).

  The 16+ path does the same, so the header path is not the cause.
- This is content-side and independent of the header path. It stays item 15 (c) and needs its own design. The direction: an
  intervention inside the app's animated transaction closes the resize in that transaction, or retargets inside it, instead of
  `unanimated`. Under the user's rule it must be queued as a fix.

## 2. Approach (D78, proposed)

### 2.1 A: the cold slot reader (`HeaderSlotReader`)

`HeaderHost` (`HeaderHost.swift` 38) applies `HeaderSlotReader(state:size:overflow:fade:)` instead of `HeaderFrameModifier`:

- **16+:** `content.modifier(HeaderFrameModifier(...))`. Same structure and behaviour as today.
- **15 / forced:** `GeometryReader { proxy in content.modifier(HeaderFrameModifier(..., slot: proxy.size)) }`. The proxy's size is
  the header slot's `W × H`, the same proposal `HeaderSlotLayout` sees on 16+. The slot is the overlay / background of the viewport
  after `.ignoresSafeArea`, so `H` is the container height `HeaderMath.metrics` expects. Evidence:
  - the capped / refit rows resolve the state's own `L` in U0 and nothing changes at U1;
  - C3's grow rows pass, which needs `|H − committedContainer| ≤ 0.5` at rest (otherwise the plan would stay in the width fit,
    §2.2).
- `HeaderFrameModifier.slot: CGSize?` is passed to `HeaderFallbackFrame(slot:reporter:)` and then to
  `HeaderFallbackPlan(live, slot:)`.
  - **Non-`.fit` sizes:** `minHeight = maxHeight = max(HeaderMath.liveHeight(width: slot.width, containerHeight: H, natural:,
    live), minimumHeight)`. This is 16+'s formula.
  - **`.fit`:** the box (§2.2).
  - **No slot** (no reader above it): the old plan, unchanged, so the existing plan tests keep their meaning.
- **Cold.** A `GeometryReader`'s closure runs when its size changes or its parent's body runs. The leaf inside wakes on its own
  channels (`ChannelRelay`) without re-running the closure, so:
  - a resize runs it once, in U0;
  - a host body run (a parent rebuild, R7) runs it once;
  - scrolling, collapse, pull and refresh never run it.

  Measured on 17.5: `header.slot` = 0 over 90 scroll steps on both paths (`theSlotReaderRunsOnResizesOnlyNeverPerFrame`), and ≥ 1
  per window resize on forced, 0 on preferred.

### 2.2 C: the `.fit` ideal-ratio box (two fits, one structure)

The chain in `HeaderFallbackFrame.body`, inner to outer. Every modifier is iOS 13. For the other plans the new modifiers are
neutral: nil width, nil ideal, nil limits, `fixedSize(false, false)`, `ratio` = `neutralRatio`. Only values change, never the
structure, so the header keeps its identity.

```
content
  .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)  // plan.minHeight/maxHeight
  .frame(width: W)                                   // plan.boxWidth: the content is laid out, and asked, at the slot width
  .padding(.bottom, -m′)                             // plan.innerPad
  .frame(minWidth: 0, idealWidth: W / (1 - q), maxWidth: .infinity,
         minHeight: ε, maxHeight: L - m′, alignment: .topLeading)   // plan.boxIdealWidth / boxFloor / boxLimit
  .aspectRatio(nil, contentMode: .fit)               // plan.ratio = nil: the child's IDEAL ratio (W/(1-q)) : (R - m′)
  .background(GeometryReader { g in noteBox(g.size) })
  .fixedSize(horizontal: fitsHeight, vertical: false)                          // plan.boxFitsHeight
  .frame(width: fitsHeight ? W : nil, height: fitsHeight ? h_L - m′ : nil, alignment: .topLeading)  // plan.boxHeight
  .padding(.bottom, m′)                              // plan.outerPad
  .frame(minHeight: 0, alignment: .top)
  .fixedSize(horizontal: false, vertical: true)
```

- **Ideal size of the box's child.** Width `W / (1 − q)`. Height `clamp(N(W) − m′, ε, L − m′) = R − m′`, where `N(W)` is the
  content's ideal height at the slot width (the inner `frame(width: W)` fixes the query's width).
- **Which fit.** 16+'s own rule (`HeaderMath.layoutResting`, which `HeaderSlotLayout` applies):
  - **Resize pass** (U0): the slot's `W` or `H` differs from the committed width or container. The box is fitted to the slot
    WIDTH, so it is `W × (1 − q)(R − m′)` and the stack `(1 − q)·R + q·m′`. That is 16+'s live height from the content's fresh
    ideal height, in the same layout pass as the width.
  - **Committed viewport** (U1, every frame after it, scrolling, collapse, pull, and a header content change). The box is fitted to
    the live HEIGHT `h_L = (1 − p)·R_c + p·m′` of the COMMITTED `R` (`HeaderMath.liveHeight`). `fixedSize(horizontal:)` drops
    the width proposal and `frame(height: h_L − m′)` gives the height.
    - The content is laid out at exactly 16+'s rect.
    - A content change does not move the header until the state commits the new `R`, in the content's own transaction together
      with the inset (§2.4).
    - The box's WIDTH carries the measurement.
- **Report (both fits).** The fitted box keeps the child's ideal ratio, so `R = (W / (1 − q)) · box.height / box.width + m′`.
  - Width fit: `box.width = W`, which reduces to `box.height / (1 − q) + m′`.
  - Height fit: `1 − q` cancels, since `box.width = W·(R_c − m′)/(R − m′)`.
  - The value goes to the leaf's `HeaderNaturalReporter.measured(_:width: W)`, the reporter `HeaderSlotLayout` uses on 16+. It
    records `headerNaturalLive` synchronously, so U1 adopts it in the same update, and it delivers content changes at the next
    run-loop turn in the content's captured transaction (`adoptHeaderNatural`).
- **U0 → U1 is bit-stable.** The width fit at U0 and the height fit at U1 lay the content out at the same height when the committed
  `R` is the measured one. The reporter and the commit dedupe at 0.5 pt, as on 16+, so a sub-0.5 change keeps the old `R` on both
  paths alike.
- **Overflow and `min`.** `L` is container·fraction (`.capped`), the container (`.refit`) or ∞. `m′ = min(min, L)`, or 0 for
  `.slideBehind`. `q` is the collapse progress, clamped to `1 − 10⁻⁶` (0 for `.slideBehind`). This is `HeaderMath.metrics`'
  rule. Step 1 of §6 extracts it as `HeaderMath.overflowLimit(_:containerHeight:)` so there is one copy.
  - The box reports the clamped `R` (`clamp(N, m′, L)`), where 16+ reports the raw `N`. The state's `R` is the same: every
    resize re-measures at the new `W × H` in U0.
  - The one visible difference is DEBUG only: the "no natural height" warning for a `min > 0` header made of flexible views.
    Keep it on the launch measurement, which is still the raw `N`.
- **Precision.**
  - Layout sizes are not pixel-rounded here: 35.875 pt is 107.625 px. Reported `R` is exact:
    - width fit `241.333 × 35.875 → 135.750` (`W·9/16`), `402 × 81.0625 → 226.125`, capped `402 × 65.625 → 195.25 = L`;
    - full collapse (`q = 0.999999`) `241.333 × 0.000072 → 135.750`;
    - height fit, full collapse `0.003364 × 10⁻⁹ → 135.750`, `0.002480 × 10⁻⁹ → 226.125`.
  - The floor `ε` is 10⁻⁹. The spike first used 10⁻⁴, which mis-measures `R − m′ < 100` at full collapse.
- **The measuring pass after this.** `HeaderMeasuringPass` keeps the first measurement and Dynamic Type. Its stale-width arming is
  gated on `metrics.header == nil`, so it covers only width changes before the first commit (launch). After that the box measures
  in layout.
  - Without the gate the old flip re-runs at every width change and steps the header (§1.2).
  - Without the launch exception the `.fit` header was missing for 1–5 frames at launch (spike C's first lane). Verified fixed in
    §8.1.

### 2.3 What this changes for 15 users

- An app-animated width or height change, a rotation, a split-view resize or the keyboard's container change now animates the
  header with the content on 15. That holds for `.fit`, limited `R` and `.fixed`.
- A header content change inside the band (`.fit`) is now re-measured on 15 as on 16+. SPEC S10's "15 cannot see header content
  changes inside the band (documented gap)" is removed (§6 step 5).

### 2.4 Header content change in the band (`.fit` grow) on 15

- The seam lab's `grow` extra (`-ZTronSeamFitGrow 1`) toggles the header's content between 16:9 and 4:3 in
  `.easeInOut(duration: 1.2)`.
- **HEAD.** The 15 path did not re-measure in the band. The header did not grow until it came to rest: the documented gap.
- **Spike C2 (the width fit everywhere).** The header's frame followed the content's change in its own update. The inset followed
  a run-loop turn later, while the committed band changed under the animated offset.
  - The header ended ~0.3 s before the content and overshot by 0.7 pt.
  - Overlap 11.3 / gap 11.2 on forced, at 27.0 and at 17.5.
  - Preferred is seamless (0.167–0.5) at both, because 16+'s `layoutResting` keeps the committed `R` at the committed viewport.
- **C3 (§2.2's height fit at the committed viewport)** applies the same rule on 15. The header moves only when the state commits
  the new `R`, in the content's captured transaction, together with the inset.
  - Forced 27.0 (`c3f27`): `fit-half-preserve-width-grow` 0.167 / 0.5 there and 0.5 / 0.333 back; `fit-rest-preserve-width-grow`
    0.167 / 0.5. PASS.
  - The documented gap closes with 16+'s behaviour.

## 3. Alternatives

| alternative | outcome |
|---|---|
| B: drive the measuring flip + adoption in the app's transaction (`HeaderHost` `.transaction` override, `state.headerResizeAnimation`) | **Measured, rejected.** Lateral 75.9, gap 1.33 (`spkAB27f`). 27.0 compounds every animated retarget in a flush; any design that needs a second layout to learn `N` fails the same way. |
| Commit U1 in the app's transaction (drop D51's unanimated commit) | Rejected. It changes every path (16+ too) and double-animates the content (ContentTransform already interpolates offset + insets). D62's bit-stability is what makes 16+ seamless. |
| A hidden measuring copy of the header | Rejected. A second instance of the user's view: `onAppear` twice, divergent `@State`, two `AsyncImage` loads. SPEC S10 forbids it ("never a hidden second copy"). |
| Always lay the content out at `N` and crop to the live frame | Rejected. It changes the look of flexible content (an image with `.fill`, the seam lab's red), which is laid out at `h` on 16+: a 15–16 look difference. |
| Predict `N(W)` from the last measurement (`N ∝ W`) | Rejected. Wrong for wrapping text and for any content that is not an aspect box. |
| Per-frame `GeometryReader` re-measurement | Rejected. It costs a closure per frame (S4) and still lags one update. |
| Introspect / reflection / UIKit | Not needed: pure SwiftUI fixes it (S16 untouched). |

## 4. Files and types (implementation)

- `Sources/ZTronScrollView/ScalingHeader/HeaderFrameModifier.swift`
  - New `struct HeaderSlotReader: ViewModifier { state, size, overflow, fade }` (§2.1), DEBUG `header.slot` counter and a
    `slot WxH` event.
  - `HeaderFrameModifier`: `var slot: CGSize? = nil`. The 15 branch passes `slot` and `reporter`.
  - `HeaderFallbackFrame`: `var slot: CGSize?`, `var reporter: HeaderNaturalReporter?`. The chain changes as in §2.2.
    `static func noteBox(_:plan:reporter:) -> Bool` (main thread only, DEBUG `box` event).
  - `HeaderFallbackPlan`: `init(_ live: HeaderLiveInput, slot: CGSize? = nil)`; `ratio: CGFloat?`; new
    `fitBox, boxWidth, boxIdealWidth, boxFloor, boxLimit, boxProgress, boxMin, boxFitsHeight, boxHeight`;
    `boxEpsilon = 1e-6`, `boxFloorHeight = 1e-9`.
    - The fit choice uses `HeaderMath.layoutResting`'s committed-viewport test (`|W − m.width| ≤ 0.5`,
      `|H − committedContainer| ≤ 0.5`). Extract it as `HeaderMath.isCommittedViewport(width:container:_:)` so both paths share
      it.
    - Drop the spike's unreachable second `.fit` branch inside the slot block.
- `Sources/ZTronScrollView/ScalingHeader/HeaderHost.swift`: one line (38), `HeaderSlotReader` replaces `HeaderFrameModifier`.
- `Sources/ZTronScrollView/ScalingHeader/HeaderMeasure.swift`:
  - `HeaderMeasuringPass.body`: `stale` gated on `state.storage.metrics.header == nil`.
  - Doc comments: the `HeaderMeasure` header (15 measures in layout, content changes included) and the `stale` comment.
- `Sources/ZTronScrollView/ScalingHeader/HeaderMath.swift`: `static func overflowLimit(_ o: ZTronHeaderOverflow, containerHeight:
  CGFloat) -> CGFloat`, extracted from `metrics` (157) and used by the plan.
- Tests (`Tests/ZTronScrollViewTests/`):
  - New `HeaderFallbackSlotTests` (port of the spike's `I15bSpikeTests`, both `OSPath`s):
    - capped height change (`.aspectRatio` / `.fixed`): no layout at a stale height;
    - S-RS-2 width there and back;
    - `.fit` width in the band (uncapped / `.capped(0.25)` × q 0.5 / 1);
    - `.fit` content change in the band (the header content 16:9 → 4:3 in an app animation). The header keeps the committed
      height until the state commits the new `R`, then `R = W·3/4`, on both paths;
    - S4 motion counters (`header.slot` 0, `header.builder` 0, content bodies 0 over 90 steps);
    - root-hosted window resize (`header.slot` ≥ 1 forced / 0 preferred, builder 0, content bodies 0).
  - `HeaderReviewD16Tests`: remove the forced `withKnownIssue` (115–136).
  - `HeaderLayoutFrameTests`: pure plan tests for the slot branch. They cover:
    - box values (`boxIdealWidth = W/(1−q)`, `boxLimit`, `innerPad = −m′`, `outerPad = m′`);
    - the fit choice: committed viewport gives the height fit with `boxHeight = h_L − m′`, a different `W` or `H` gives the width
      fit;
    - `liveHeight` for limited sizes.
- Docs:
  - SPEC S10: line 618 `(16+) header content changes` becomes `header content changes`.
  - SPEC S10 "Natural height" (771–783): the 15 sentence becomes the box, and the documented gap goes.
  - SPEC S10 "Seamless edges" 991–996: the measuring-pass paragraph is limited to launch and Dynamic Type.
  - Orchestration: item 15 (b) FIXED (D78); 15 (c) stays open with §1.4's evidence.
- Demo / seam lab: no change. All scenarios exist.

## 5. iOS 15 availability, S4, S7

- **Availability.** `GeometryReader`, `frame(minWidth:idealWidth:maxWidth:minHeight:maxHeight:alignment:)`,
  `aspectRatio(_: CGFloat?, contentMode:)`, negative `padding`, `fixedSize(horizontal:vertical:)` and `background(_:)` are all iOS 13.
  `MainActor.assumeIsolated` is already used on this path. No new `if #available`. The 16+ branch of `HeaderSlotReader` is behind
  the existing `state.usesLayoutProtocol, #available(iOS 16, *)`.
- **S4.**
  - Content bodies are never re-evaluated. The slot closure runs only on resizes and host runs (measured counters above).
  - The box's `GeometryReader` builds a `Color.clear` and calls `noteBox`. Its closure runs when the box's size changes, i.e. per
    frame while the header collapses on 15. That is the leaf's own per-frame layout, the cost class of 16+'s `HeaderSlotLayout`,
    which calls `sizeThatFits` and `reporter.measured` in every pass, and of today's `fitRest` reader.
  - The report dedupes at 0.5 pt and writes cold storage only (`headerNaturalLive`), so it never publishes during layout.
  - `header.builder` = 0 for scrolls and window resizes. `content.body` = 0 for both. A parent rebuild runs the builder once (R7),
    as before.
- **S7.** The header no longer lands, and the content's S7 resolution (`ResizeMath`) is untouched. Rotations on forced:
  - `fit-half-preserve-rotate-sticky-forced`: lateral 0.122 / 0.357, gap ≤ 0.167, step 0.099 (C3; the rotation's 19-frame
    animation itself);
  - the vland rows' rotation segments: lateral 0.08 / 0.218;
  - `aspect-rest-preserve-rotate-capped-forced`: §8.1.

## 6. Build steps (each a green commit)

1. **`HeaderMath.overflowLimit` extraction.** A pure refactor of `metrics`. Gate: `HeaderMathTests` + `HeaderFitTests` on 27.0.
2. **Slot reader for non-`.fit` sizes.**
   - Code: `HeaderSlotReader`, `HeaderFrameModifier.slot`, `HeaderFallbackFrame.slot`, the plan's slot branch for non-fit sizes, and
     the `HeaderHost` hook. Until step 3, `.fit` keeps the old plan when it has a slot.
   - Tests: `HeaderFallbackSlotTests` (non-fit cases, S4 counters, window resize). D16 forced known issue removed. Plan tests.
   - Gate: unit tests on 17.5 + 27.0. Seam lab 27.0 forced: the eight §1.1 non-fit rows PASS. 27.0 preferred: the same rows without
     `-forced`, unchanged.
3. **`.fit` ideal-ratio box (both fits).**
   - Code: the plan's box fields, the chain, `noteBox`, the leaf's reporter on 15, the measuring-pass gate, and
     `HeaderMath.isCommittedViewport`.
   - Tests:
     - `.fit` cases (width, q 0.5 / 1, capped, content change);
     - the plan's fit choice;
     - launch: the header is present in the first frame (a launch test reading `header.frame` + `headerGeometry` at the first
       layout).
   - Gate:
     - seam lab forced `.fit` rows (§7) PASS, including `fit-half-preserve-width-grow` and `fit-rest-preserve-width-grow`;
     - `HeaderFitTests`, `HeaderReviewD16Tests`, `HeaderSlideBehindTests`, `HeaderStretchScaleTests` and
       `ScalingHeaderHostedTests` green on 17.5 + 27.0.
4. **Docs.** SPEC S10 (618, 771–783, 991–996), Orchestration item 15 (b) FIXED with the §7 table, decision D78, handoff.

## 7. Acceptance

PASS on a row: |seam| ≤ 1 pt (`maxGap`, `maxOverlap`), lateral ≤ 1 pt (`maxLatMis`), and no 60 Hz step ≥ 0.5 of the change
(`hdrJump` / `contentTopJump` fraction). No refresh indicator is involved in these rows. Run under the UI lock at load < ~300, and
re-run a failure alone.

- **27.0 forced.**
  - Overflow and width rows: `aspect-half-preserve-width-capped25`, `…-capped25-slide1`, `aspect-rest-preserve-width-capped-height04`,
    `aspect-half-preserve-width-capped-height04`, `aspect-rest-preserve-width-refit-height025`,
    `fixed-rest-preserve-width-capped-height04`, `aspect-rest-preserve-width-capped-height04-vland`.
  - `.fit` rows: `fit-half-preserve-width`, `fit-rest-preserve-width`, `fit-half-preserve-width-capped25`,
    `fit-half-preserve-width-slide1`, `fit-half-preserve-width-vretarget`, `fit-half-preserve-rotate-sticky`,
    `fit-half-preserve-width-grow`, `fit-rest-preserve-width-grow`, `fit-half-preserve-scroll-band`.
  - Controls: `aspect-rest-preserve-width`, `aspect-rest-preserve-rotate-capped`, `aspect-half-preserve-scroll-band-capped25`,
    `aspect-rest-preserve-pull-capped25-opengap`.
  - All with `-forced`.
- **27.0 preferred.** The same list without `-forced`: no regression against HEAD (16+ code is unchanged apart from the
  pass-through wrapper).
- **17.5.** Preferred and forced: `fit-half-preserve-width`, `aspect-half-preserve-width-capped25`,
  `aspect-rest-preserve-width-capped-height04`, `fixed-rest-preserve-width-capped-height04`, `fit-half-preserve-width-capped25`,
  `fit-half-preserve-width-grow`.
- **Unit (17.5 + 27.0).** `HeaderFallbackSlotTests` (new), `HeaderReviewD16Tests` (no known issue left on forced),
  `HeaderLayoutFrameTests`, `HeaderFitTests`, `HeaderSlideBehindTests`, `HeaderStretchScaleTests`, `HeaderResizeTests`,
  `HeaderHeightResizeTests`, `HeaderSafeAreaInsetTests`, `HeaderKeyboardTests`, `HeaderPullBehaviorTests`,
  `ScalingHeaderHostedTests`. Full suite at milestone end.
- **Render counters.**
  - Scroll / collapse / pull: `header.slot` = 0 and `header.builder` = 0.
  - Resize: `header.slot` ≥ 1 on 15 / forced, 0 on 16+, and `header.builder` = 0 without a parent rebuild.
  - `content.body` = 0 throughout.
- **UI.** The header UI suites unchanged. Full demo UI suite at milestone end (one lane machine-wide).

## 8. Spike results

### 8.1 Seam lab (27.0)

Spike A on forced (`spkAB27f`, load 220 → 9). Every non-fit row PASSes:

| row | narrow / shrink | back |
|---|---|---|
| S-RS-2 `.compress` | 0.167 / ov 0.5 / lat 0.263, step 0.034 | 0.167 / 0.5 / 0.169, 0.034 |
| S-RS-2 `.slideBehind(1)` | 0.167 / 0.005 / 0.284, 0.023 | 0.167 / 0.005 / 0.168, 0.023 |
| capped height 0.4, rest | 0.333 / 0.333, 0.026 | 0.333 / 0.333, 0.026 |
| capped height 0.4, half | 0.167 / 0.5, 0.028 | 0.167 / 0.5, 0.028 |
| refit height 0.25 | 0.167 / 0.333, 0.032 | 0.167 / 0.333, 0.032 |
| `.fixed` capped | 0.167 / 0.333, 0.024 | 0.167 / 0.333, 0.024 |
| landscape (vland) | 0 / 0.333 / 0.001, 0.026 | 0 / 0.333 / 0.001, 0.026; rotations 0.08 / 0.218, 0.097 |

Spike A + C on forced (`spkC27f`, load 9–45):

| row | narrow / there | back |
|---|---|---|
| `fit-half-preserve-width` | 0.167 / 0.5 / lat 0.271, step 0.030 | 0.167 / 0.5 / 0.322, 0.030 |
| `fit-rest-preserve-width` | 0.194 / 0.333 / 0.334, 0.028 | 0.194 / 0.333 / 0.335, 0.028 |
| `fit-half-preserve-width-capped25` | 0.167 / 0.5 / 0.263, 0.034 | 0.167 / 0.5 / 0.169, 0.034 |
| `fit-half-preserve-width-slide1` | 0.167 / 0 / 0.341, 0.030 | 0.167 / 0 / 0.338, 0.030 |
| `fit-half-preserve-width-vretarget` | 0.167 / 0.335 / 0.167 | 0.167 / 0.5 / 0.167 |
| `fit-half-preserve-rotate-sticky` | 0 / 0.167 / 0.393, 0.097 | 0.167 / 0.117 / 0.494, 0.098 |
| `aspect-half-…-capped25-slide1` | 0.167 / 0.005 / 0.271, 0.023 | 0.167 / 0.005 / 0.283, 0.023 |
| `fit-half-preserve-width-grow` (content change) | overlap 11.3 | gap 12.5: §2.4 |

The first segment of each launch reads `cJ ≈ 1.0`. That is the analyzer's degenerate launch segment (content from −375 to its
first position), not a step.

Controls on the spike C2 build (`ctlC27`, 27.0, load 33–160):

| row | result |
|---|---|
| `fit-rest-preserve-width-forced` (launch re-check) | 0.195 / 0.333 / 0.334, step 0.026. No degenerate launch segment: the header is drawn in the first recorded frame. |
| `aspect-rest-preserve-width-forced` | 0.333 / lat 0.195. Back segment: one shared step of 9.2 pt (fraction 0.10, header and content together: a dropped frame at load 160). |
| `aspect-rest-preserve-rotate-capped-forced` | gap 0 / lat 0.073 / 0.113, step 0.099 (the rotation's own frames) |
| `aspect-half-preserve-scroll-band-capped25-forced` | 0.5, step 0.112, header and content together |
| `aspect-rest-preserve-pull-capped25-opengap-forced` | `.openGap` by design (gap 99–102 = the pull). Header still (hJ 0), content step ≤ 0.133. |
| `fit-half-preserve-width` (preferred) | 0.167–0.177 / lat 0.209 / 0.168 |
| `fit-half-preserve-width-grow` (preferred) | 0.167 / 0.5: **seamless on 16+** |
| `fit-half-preserve-width-grow-forced` | overlap 11.3 / gap 11.2: **15-path only** (§2.4) |
| `aspect-half-preserve-width-combo` (preferred) | back segment gap 29.8, lateral 53.3, content step 31.2 (fraction 0.25): item 15 (c) is on 16+ too (§1.4) |

17.5 (`s175C`, iPhone 15 Pro, spike C2, load 10–265):

| row | narrow / there | back |
|---|---|---|
| `fit-half-preserve-width-forced` | 0.167 / ov 0.5 / lat 0.257, step 0.03 | 0.167 / 0.5 / 0.167 |
| `aspect-half-preserve-width-capped25-forced` (S-RS-2) | 0.167 / 0.5 / 0.182, 0.029 | 0.167 / 0.5 / 0.327 |
| `aspect-rest-preserve-width-capped-height04-forced` | 0.5 / 0.333, 0.029 | 0.333 / 0.333 |
| `fixed-rest-preserve-width-capped-height04-forced` | 0.333 / 0.167, 0.026 | 0.5 / 0.167 |
| `fit-half-preserve-width-capped25-forced` | 0.167 / 0.5 / 0.182 | 0.167 / 0.5 / 0.167 |
| `fit-half-preserve-width` / `aspect-half-preserve-width-capped25` (preferred) | PASS (≤ 0.5 / lat ≤ 0.325) | PASS |
| `fit-half-preserve-width-grow` (preferred) | 0.5 / 0.5: PASS | |
| `fit-half-preserve-width-grow-forced` (C2) | overlap 10.8 | gap 11.2: the same 15-path grow lag as 27.0 |

**C3 on 27.0 forced** (`c3f27`, the final spike build, load 5–48): every `.fit` row PASSes, including both grow rows.

| row | there | back |
|---|---|---|
| `fit-half-preserve-width-grow` (content change) | 0.167 / ov 0.5, step 0.036 | 0.5 / 0.333, 0.031 (C2: 11.3 / 11.2) |
| `fit-rest-preserve-width-grow` | 0.167 / 0.5, 0.026 | 0.167 / 0.5, 0.026 |
| `fit-half-preserve-width` | 0.167 / 0.5 / lat 0.271, 0.030 | 0.167 / 0.5 / 0.275, 0.030 |
| `fit-rest-preserve-width` | 0.167 / 0.333 / 0.372, 0.026 | 0.195 / 0.333 / 0.371, 0.026 |
| `fit-half-preserve-width-capped25` | 0.167 / 0.5 / 0.168, 0.034 | 0.167 / 0.5 / 0.167, 0.034 |
| `fit-half-preserve-rotate-sticky` | 0 / 0.167 / 0.122, 0.096 | 0.167 / 0.122 / 0.357, 0.099 |
| `fit-half-preserve-width-slide1` | 0.167 / 0 / 0.336, 0.030 | 0.167 / 0 / 0.335, 0.030 |
| `fit-half-preserve-width-vretarget` | 0.167 / 0.333 / 0.167 | 0.167 / 0.5 / 0.167 |
| `fit-half-preserve-scroll-band` (the height fit per frame) | 0.167 / 0.5, step 0.025 | |

Two single-frame 0.166-pt settles (half a pixel) close the grow and the retarget rows. They are below every threshold.

### 8.2 Unit (17.5: `u175C`, `u175D`, `u175E`)

- `u175C` (spike A + C, 12 header suites, 69 tests): every header suite passed on both paths, including the new `.fit` band test.
  Two issues were expected:
  - `HeaderReviewD16Tests`' forced known issue no longer recorded: the fix;
  - the spike's first S4 test: a `GeometryReader` host re-created the container on resize, a harness artefact replaced by the
    root-hosted test.
- `u175D` (ε = 10⁻⁹, q = 1 cases, root-hosted resize; `I15bSpikeTests` + `HeaderFitTests` + `HeaderReviewD16Tests`, 19 tests):
  all green. The one issue is the expected D16 "Known issue was not recorded" on forced.
  - **Full collapse.** At `q = 0.999999` the box is `241.333 × 0.000072`, `402 × 0.000131` (capped) and `402 × 0.000162`. Reported
    `R` = 135.750, 195.250 and 226.125 (error 2·10⁻⁹ pt). The same `R` as 16+ to within its own 0.5-pt dedupe: 16+ kept 135.675,
    a measurement from mid-animation.
  - **Root-hosted window resize to 402 × 520.**
    - `header.slot` 1 forced / 0 preferred; `header.builder` 0.
    - Scroll content body 0; header content body 0 (a counting header view).
    - `R` 213.5 on both paths.
    - Leaf bodies: 3 forced / 2 preferred.
  - **Motion (90 scroll steps).** Leaf bodies 90 / 90 (the per-frame leaf, as designed), `header.slot` 0.
- `u175E` (C3; `I15bSpikeTests`, `HeaderFitTests`, `HeaderReviewD16Tests`, `HeaderLayoutFrameTests`, `HeaderSlideBehindTests`,
  `HeaderStretchScaleTests`, `HeaderPullBehaviorTests`, `ScalingHeaderHostedTests`, 52 tests): all green apart from the same
  expected D16 issue.
  - Box events show both fits. Width fit `241.333 × 35.875 → R 135.75`.
  - Height fit at the committed viewport, full collapse: `0.003364 × 10⁻⁹ → 135.75`, `0.003063 × 10⁻⁹ → 195.25` (capped),
    `0.002480 × 10⁻⁹ → 226.125`. All exact.

## 9. Risks

1. **iOS 15/16 semantics of the ideal query.**
   - The risk: how `aspectRatio(nil)` reads the child's ideal size on 15, how `frame(idealWidth:)` answers an unspecified proposal,
     and whether the negative padding composes.
   - Measured only on the 17.5 and 27.0 runtimes. These are iOS 13 APIs with documented semantics; the M1 lane confirms (§10).
2. **`GeometryReader` closure timing on 15.** The slot's size must reach the plan in the same layout pass as the frame (U0).
   - The spike shows it on 17.5 and 27.0 (no stale layout in `log.sizes`).
   - If 15 delivered it one pass later, the landing would come back. The DEBUG `slot` event ordering against the first animated
     frame detects that.
3. **Precision near `q → 1`.** `(1 − q) ≥ 10⁻⁶` and ε = 10⁻⁹ in double precision. The q = 1 unit case guards it.
4. **Layout off the main thread.** `noteBox` reports only on the main thread, as `HeaderSlotLayout` does. A skipped report leaves
   the previous `R` until the next main-thread pass. That is the same exposure 16+ has today.
5. **Two reporters at launch.** The first measuring pass and the box both report. The reporter dedupes, and the gate keeps the flip
   to the first commit.
6. **Content with no ideal height.** A bare `Color` or a `GeometryReader` gets the same `N` on both paths: the box queries
   `(W, nil)`, as `sizeThatFits(width: W, height: nil)` does on 16+. Parity, including D16's DEBUG warning.
7. **Interaction with i28's grow on the 15 path** (§11). Both edit `HeaderFallbackPlan`. Sequence the landings.
8. **The fit switch.** The plan switches from the width fit to the height fit when the committed width and container match the
   slot, the same test 16+'s `layoutResting` makes.
   - If 15's slot height differed from `committedContainer` by more than 0.5 pt at rest, the plan would stay in the width fit and
     content changes would move the header ahead of the inset again: C2's 11-pt seam.
   - The plan tests pin the switch. A DEBUG event (`box fit w|h`) makes it visible on the M1 lane.

## 10. What a real 15.0 / 16.0 run on the M1 should confirm

- **15.0 (the 15 path natively).**
  - The seam-lab rows of §7 (forced is the native path there) PASS at the same thresholds. In particular S-RS-2, the height rows and
    `fit-half-preserve-width`, with no first-frame landing.
  - DEBUG `box WxH q R` events give `R = W·9/16` for the seam lab's 16:9 header and `L` when capped, in both fits:
    - the width fit (`W × …`) during a resize;
    - the height fit (`w_b × h`) at rest and in the band.

    This confirms the `aspectRatio(nil)` ideal-ratio semantics and `fixedSize(horizontal:)` under a fixed height.
  - `fit-half-preserve-width-grow` (forced = native) is seamless: header and inset move together.
  - The `slot` event precedes the first animated frame of the resize (closure timing).
  - `header.slot` stays at 0 while scrolling or pulling.
  - No dropped frames during a collapse with the demo's profile header against HEAD (the per-frame box reader's cost).
  - Launch: the `.fit` header is present in the first frame.
- **16.0 (the `Layout` path).** The same rows show no regression; the wrapper is a pass-through there.
- **Both.** Item 15 (c)'s combo, to record how the native runtime treats the M5 snap (expected: same as 27.0).

## 11. Interactions with the other M8b-s8 designers

- **i28-stretch-blur (D76, `HeaderFallbackPlan` / `HeaderFallbackFrame`).**
  - i28 §4.6 / §8 take the 15-path `W` for its `sidePad` from i15b. That `W` is `slot.width`, in `HeaderFallbackPlan(live, slot:)`.
    Land i15b first; i28's step 3 rebases on it.
  - **The box changes i28's R2 / R7 premise** ("iOS 15 cannot measure without laying out"). The box answers the ideal query at
    its inner `frame(width:)` in the same pass as the layout. No measuring pass is needed after launch.
  - While pulled, the box is in the height fit (the committed viewport). i28's grow sets `boxHeight = h_L + g − m′` and the inner
    width `W·s`.
  - The ideal query then runs at `W·s`, so `noteBox` must skip frames with `g > 0`. The measurement is taken at release, which is
    R7's plan without the flip.
  - A rotation or app-animated width change during a hold stays in the width fit for its U0 (fresh `N(W)`), then returns to the
    height fit. Re-run i28's `fit-rest-stretch-rotate-hold-*` rows on top of D78.
  - Both edit the same `HeaderFallbackPlan` init. Merge conflicts are expected but mechanical.
- **i29-blend-slidebehind (D77).** G (the 15–16 viewport group) wraps the `.slideBehind` slot. Both readers here are layout-only
  (`Color.clear`) and draw nothing, so compositing is unaffected. No shared lines. After both land, re-run the forced width / height
  rows with `.slideBehind`: S-RS-2 slide1 and `fit-…-slide1`.
- **d75-short-content (D75, content alignment / layout host).**
  - No shared lines. The slot's `H` must stay the container height `HeaderMath` uses for the overflow limit.
  - If D75 changes how the container height is derived (`HeaderMath.containerHeight`), `overflowLimit`'s `containerHeight` and the
    slot's `H` must follow the same definition.
  - A divergence would show as a capped row landing at U1, or as the grow rows falling back to the width fit.
  - Add a hosted test asserting `|slot.H − committedContainer| ≤ 0.5` at rest, on both orientations.
- **refresh-27-31-32-33 (`RefreshIndicators`, `HeaderHost`).**
  - `HeaderHost`: my change is one line (the modifier swap). Trivial merge.
  - `RefreshIndicators` is unaffected. The indicators read the committed header geometry, which this design keeps identical at rest
    and makes final earlier during a resize.
- **`GroupLatch`, `ContentTransform`:** not touched.

## 12. Numbering and user questions

- Decision: **D78** (proposed; D75 d75, D76 i28 / user ruling, D77 i29). No new open item: 15 (b) closes, and 15 (c) stays with §1.4.
- Naming question, default picked: the DEBUG counter is `header.slot`, in the family of `header.frame` / `header.builder`.
