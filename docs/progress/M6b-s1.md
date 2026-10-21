# M6b-s1 handoff · 2026-10-21 · Opus 5.5 orchestrator (ultracode, 2 workflows / 7 agents) · design by Fable 5.1
Status: done — content-integral overlay (SPEC S11 amendment 2026-10-21, design `docs/design/M6b-content-overlay.md`, decision D41), library + unit
tests + demo + UI tests, built in a private worktree on branch `m6b-content-overlay` and fast-forwarded into main.
Changed:
- `Sources/ZTronScrollView/ContentOverlay/{ContentOverlayTypes,ContentOverlayMath,ContentOverlayHost}.swift`: public enums, the one placement rule
  (origin = anchor point − overlayAnchor × frame; `.fillMaxSize` = the content rect), host on 16+ = `ContentOverlayLayout`, on 15 / forced =
  `GeometryReader` + alignment guides; `ContentOverlayLeaf` (counter `contentOverlay.body`), `ContentOverlayViewCache` (an `Equatable` overlay
  equal to the shown one keeps its `AnyView`: `EquatableView` inside `AnyView` did not gate the body on 17.5 / 27.0).
- `Sources/ZTronScrollView/Modifiers/ContentOverlayTwins.swift`: member `scrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)`
  + twin `ztronScrollContentIntegralOverlay` (key "member.<i>" / `@State` token; twins below members; overlay subtree drops the twin list so a
  scroll view inside an overlay cannot recurse).
- `Sources/ZTronScrollView/Helpers/CounterScaled.swift`: public `ztronScrollCounterScaled(anchor:)` (SPEC S6 helper, M8-chrome §6) = the
  `.counterScaled` implementation; leaf reads `targetZoom` alone; `ChannelStorage.targetZoomChannel` (State/StateStorage.swift, additive)
  so on 15–16 it wakes on target-zoom writes only.
- `ZTronScrollView.swift`: one `.overlay(alignment: .topLeading) { ContentOverlayHost(…) }` as the first content modifier;
  `ScrollConfigTwins.swift`: `ScrollViewConfig.contentOverlays`.
- Tests: `ContentOverlayTests` (21 tests, 16 over both OS paths). Demo: `ResizeScreen` flags `-ZTronResizeOverlay`,
  `-ZTronResizeOverlayCounterScaled`, `-ZTronResizeOverlayNoButton`, readout fields, lockstep probe; `ContentOverlayUITests` (4).
- Docs: SPEC S4 tier row (measured wording), design §2 corrected (reflow = one layout pass + frame interpolation, not a pass per frame)
  + L1 / L2 notes, two parity rows, this handoff, Orchestration State row + D41 + log, STATE row.
Decisions: D41 (Orchestration). Measure first: a `GeometryReader` under `ContentTransform` does not re-run its closure on scroll, zoom or the
`.disabled` flips (17.5 / 27.0, both paths), so the iOS 15 host is the reader. Frame semantics everywhere: the overlay's frame is the computed size
(a smaller view centred), the view's own size on an unspecified axis.
Open:
- iOS 15 runtime unmeasured (no 15 simulator on macOS 27): run `ContentOverlayTests` + `ContentOverlayUITests --forced` there (Xcode 26.x).
- On 16+ an overlay holding a control re-places (layout only) ~2× per gesture (content gate `.disabled` flips); documented in S4, not fixed.
- Multi-view content (`ZTronScrollView { A; B }`): container modifiers apply per element (pre-existing; the views also overlap at the origin),
  so overlays would be drawn per element. Recommend a single root; SwiftUI parity (implicit stack) is a separate task.
- A `ztronScrollID` inside a `.counterScaled` overlay registers its drawn (counter-scaled) frame and re-registers on zoom.
- Per-frame lockstep of `.counterScaled` vs the drawn zoom needs a library DEBUG probe; checked at rest only.
- Library-wide finding: `AnyView(EquatableView(v))` does not gate `v`'s body (17.5, 27.0); the M8b-2 custom refresh indicators erase the same way.
- Device checks (design R5): hit area of a counter-scaled overlay, VoiceOver order of overlays vs content.
Next: 1. The user's 15/16 run (with D31 (c)). 2. M8-4 builds sticky / parallax / LOD next to `Helpers/CounterScaled.swift` (no second
counter-scale). 3. Decide multi-view content parity (implicit stack) as its own design item.
Tests:
- Unit, full `ZTronScrollViewTests` at 4614c8a (Sources unchanged since): 17.5 637/637; 27.0 636/637, the one failure
  `ProxyTests.theAnimationOverloadReachesTheOwner` (animated scroll read mid-way at host load ~600) passed 9/9 when the suite was re-run alone.
- UI at 3c60248 (private clones, `-collect-test-diagnostics never`): forced 27.0 17/17, forced 17.5 17/17 (ContentOverlay 4 + Resize 13);
  preferred 27.0 17/17 and 17.5 17/17 (final re-run at 3c60248, no restarts).
Usage: not measured in this session (2 workflows: L1 ≈ 0.97 M subagent tokens, L2 ≈ 0.65 M).
