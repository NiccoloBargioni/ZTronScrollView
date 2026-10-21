# M6b-s2 handoff · 2026-10-21 · Opus 5.5 orchestrator (ultracode, 1 workflow / 3 agents)
Status: done — content-overlay API revision R6 (the user's request after M6b-s1; design `docs/design/M6b-content-overlay.md` R6, D41 revision),
built on branch `m6b-overlay-units` in a private worktree and fast-forwarded into main.
Changed:
- `Sources/ZTronScrollView/ContentOverlay/ZTronUnitTypes.swift` (new): `ZTronUnitLength` (float/integer literals), `ZTronUnitSize`,
  `ZTronUnitPoint` (nine statics, `init(_ UnitPoint)`); `let` components clamped to `[0, 1]` at init (NaN → 0, +∞ → 1), no other way in.
- `ContentOverlayTypes.swift`: anchor `.relative(ZTronUnitPoint)`; `ZTronContentOverlayLength` (`.ideal`, `.aspectRatio`, `.absolute`,
  `.relative(ZTronUnitLength)`); `ZTronContentOverlaySize` is a struct (internal `Kind`: `.fillMaxSize` or `.axes(width:height:)` with one
  canonical length per axis) with `fillMaxSize`, `ideal`, `fillMaxWidth(_:)` / `fillMaxWidth(height:)`, `fillMaxHeight(_:)` /
  `fillMaxHeight(width:)`, `relative(_:)`, `relative(width:height:)`, `absolute(_:)`; `==` means "draws the same frame".
- `ContentOverlayMath.swift`: one `axisLength` per axis for both hosts; an overflowing aspect result → 0 with the `badAspect` note.
- Tests: `ContentOverlayTests` 21 → 29 (unit types, normalization / equality, every length on both axes, hosted frames on both host paths,
  `.ideal` free axes measured, clamped corner anchor, compile-only spelling list). Demo: top strip `.fillMaxWidth(height: .relative(0.05))`
  and trailing bar `.fillMaxHeight(width: .absolute(12))` under `-ZTronResizeOverlay` (readout `sp`, `ba`); `ContentOverlayUITests`
  checks both and includes them in every zero-body assertion.
- Docs: SPEC S11 types, design §0/§1/§3 + R5 confirmation + R6, parity row, D41 revision, State / STATE rows, this handoff.
Decisions: struct + static constructors instead of an enum (Swift cannot overload enum cases by type, and `.fillMaxWidth(16/9)` must keep
compiling); canonical equality instead of per-spelling normalization (reviewer finding); anchors' `.relative` clamped too (the user
approved the proposal), `.absolute` and `overlayAnchor` stay unclamped. The user kept the twin environment-only.
Open:
- Source break, intended: `.relative(UnitPoint)` → `.relative(ZTronUnitPoint)`, `.relative(CGSize)` → `.relative(ZTronUnitSize(_:))`,
  `switch` over the old size enum. Only this repo's tests and demo used them.
- Anchors are not canonicalized: `.topTrailing != .relative(.topTrailing)` under the synthesized `==` (they render alike).
- Unchanged from M6b-s1: iOS 15 runtime unmeasured; layout-only re-placement when an overlay holds a control; multi-view content.
Next: 1. The user's 15/16 run. 2. Decide whether anchors should get canonical equality too (cheap). 3. Multi-view parity design
(`claude/unruffled-tesla-e0c4b5`, proposed D42) awaits the user.
Tests (private simulators, own derived data):
- `ContentOverlayTests` 29/29 on 27.0 and 17.5. Full `ZTronScrollViewTests` 645: 17.5 645/645; 27.0 644/645, the failure
  `LayoutHostTests.clockDrivesAnimatedOffsetThenPauses` ("ticks > 10" at load 400–700) passed when re-run alone.
- UI `ContentOverlayUITests` + `ResizeUITests`, 17 per lane: 27.0 preferred 17/17, 27.0 forced 17/17, 17.5 forced 17/17, 17.5 preferred
  16/17 with an XCUIDevice orientation timeout before any assertion, passed when re-run alone. Strip / bar max errors 0.37 pt / 0.67 pt.
Usage: not measured (workflow ≈ 0.6 M subagent tokens).
