# M8b-s5 handoff · 2026-10-27 · Opus 5.5 fixer (review d16 of the seamless header)
Status: done for the nine review findings (7 fixed, 1 fixed + documented difference, 1 documented 15/16 limit) plus one
crash found while measuring. Branch `m8b3-seamless-final` from `df36258` (M8b-s4). Main is not merged in.
Changed:
- `ScalingHeader/HeaderMath.swift` `liveHeight`: a banner (no vertical axis) is laid out from layout too (`R(W)`, its
  committed overflow container); `HeaderFrameModifier.swift` `HeaderFallbackPlan`: banners take the aspect box on 15/16.
- `HeaderFrameModifier.swift` `HeaderSlotLayout`: reports a `.fit` measurement only from the main thread (crash, below).
- `.fit` re-measure in the change's transaction: `HeaderHost` records the animated transaction of an update that reaches
  the header content (`.transaction` reader) with its run-loop turn (`ZTronScrollState.headerContentTransaction`,
  `headerTurn`); `adoptHeaderNatural` adopts a measurement of that turn in it (16+: the deferred report; 15 at rest: the
  same update); unanimated as before inside a resize.
- `State/ZTronScrollState.swift` `contentAlignment`: with a scaling header the vertical alignment is the top.
- `ScalingHeader/HeaderSnap.swift`: an expanded target leaves a resting view at or above rest; from the band it goes to
  the top rest (`o′ = −hold`).
- `HeaderTypes.swift`: `material(radius:)` monotonic over the line (`+∞` ultraThick, `−∞` ultraThin, NaN regular);
  `blurRadius` (`+∞` = `maximumBlurRadius` 1000, negative / NaN = 0); docs.
- `State/ZTronScrollReader.swift`: cold readers (`ztronColdReaders` environment): the `.ambientBlur` copy's readers wake
  on the metrics only and show the geometry then (an untracked read), never per frame.
- `Render/ContentTransform.swift` `ContentLayerGroup`: 15–16 `compositingGroup()` only for a view with a header at its
  first render (`GroupLatch`, DEBUG note `content.group`); `TransformHost(hasHeader:)`; capability / group docs.
- Demo `ProofScreen`: counters zeroed after a quiet period (0.5 s without render-counter changes, at most 3 s), fixed
  frames for the texts Reset / Snapshot write, `settle` signal; `ProofUITests.reset` waits for it.
- Demo `SeamLabScreen`: `-ZTronSeamAxis horizontal` (review d16-4), `-ZTronSeamFitGrow 1`; `scripts/seam/baseline.sh`
  extras `horizontal`, `grow`.
- Tests `HeaderReviewD16Tests` (the reviewers' probes, adapted, plus ambient-reader, latch, snap-from-band, radius tests).
- Docs: SPEC S6 alignment line, S10 (content that fits, `.fit` transaction, background readers / radii, 15–16 layer
  groups, banners, 15-path overflow limit, snap), parity row "Header and content layer groups", M8b-s4 Open 3 corrected.
Decisions (unnumbered; the lead assigns D-numbers):
- Content that fits under a header is top-aligned vertically (horizontal alignment kept). Reason: user decision 1 ("no
  gap between the header and the content") and S10 Placement; centring left a 119 pt gap. Needs lead / user
  confirmation: the alternative (the header follows the centred content's top) makes a `.stretch` header grow by `pad`
  at rest.
- 15–16 content group only with a header, latched at the first render (a runtime toggle never changes the content's
  identity). Blend-mode isolation and group opacity are documented 15–16 differences of a header view.
- 15-path overflow limit during an app-driven resize: documented limit (no proportional size in iOS 13 layout modifiers,
  a per-frame GeometryReader is ruled out by S4.6); `withKnownIssue` on the forced lane.
- Ambient copy readers are cold (snapshot per metrics change) instead of documenting doubled per-frame work.
Found while measuring (fixed): `HeaderSlotLayout` called `MainActor.assumeIsolated` from `placeSubviews`, which SwiftUI
also runs on `com.apple.SwiftUI.AsyncRenderer`: the demo trapped (EXC_BREAKPOINT, `_dispatch_assert_queue_fail`) on a
`.fit` header's animated content change inside the band (seam lab `fit-half-preserve-width-grow`, 27.0).
Open:
1. The two M8b-s4 combination scenarios (scroll command overlapping an animated resize) are unchanged (design decision).
2. The 15-path `.fit` in the band on an app-driven resize and the new 15-path overflow-limit item (documented limits).
3. Logic-test host: an inset-only SwiftUI animation of the content transform draws one frame and freezes unless another
   animation runs (both paths); the forced `.fit` re-measure is therefore verified in the seam lab, not by frames in the
   unit test.
4. Real 15/16 device: `compositingGroup` cost (M8b-s4 Open 4).
Next:
1. Lead / user: confirm the top alignment of fitting content under a header.
2. Merge into `m8b3-seamless` / main (lead).
3. Real 15/16 device check.
Tests:
- Unit `scripts/test.sh -only-testing:ZTronScrollViewTests`: 739 tests in 65 suites green on 27.0 and on 17.5 (1 known
  issue: the 15-path overflow limit, `withKnownIssue` on the forced lane).
- `HeaderUITests` + `ResizeUITests` + `ProofUITests`: 29/29 on 27.0 preferred, 27.0 forced and 17.5 preferred.
  `testNoClockTicksAtRest` × 8 (`-test-iterations 8`, 27.0 preferred, load ~5): 8/8; every reset absorbed 5 effect
  evaluations in a 0.6-0.7 s settle (the fixed 0.3 s window counted the ones that spill past it under load).
- Seam lab (analyzer v2.2), 30 rows, all PASS (|seam| <= 0.5 pt, lateral <= 0.4 pt, no step >= 0.5): horizontal width
  (was 90 / 90 / 159 pt, hJ 1.00), horizontal rotation, `.fit` grow at rest / half / `.stretch` on three lanes, `.fit`
  and aspect width / rotation regressions, ambient rotation. Table: `scratchpad/seam/final-table.md`, section "Review d16".
Usage: not measured.
