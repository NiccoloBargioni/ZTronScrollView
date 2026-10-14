# ZTronScrollView — pure-SwiftUI UIScrollView replacement (iOS 15+)

Resume here: `Orchestration.md` (state, decisions, next step). Spec and plan: docs/SPEC.md. Read only the
sections your task names; `grep -n '^## [SOF][0-9]' docs/SPEC.md` lists them with line numbers.
Designs: docs/design/. Handoffs and state: docs/progress/.

## Naming (the spec says "ZoomScroll"; this repo is ZTronScrollView)
- `ZoomScrollView` → `ZTronScrollView`; any `ZoomScroll…` type → `ZTronScroll…` (State, ViewReader, ViewProxy, Reader, Geometry, Phase, Position, TargetBehavior, Animation, ViewDelegate).
- Other `Zoom…` types → `ZTron…` (`ZTronRefreshState`, `ZTronHeaderGeometry`, `ZTronLazyVStack`, `ZTronScalingHeaderScrollView`); `ZoomScale` → `ZTronZoomScale`.
- `zoomScroll…` modifiers → `ztronScroll…` (`ztronScrollID`, `ztronScrollCounterScaled`); `onZoomScroll…` → `onZTronScroll…`.
- Packages: `Packages/ZTronScrollPhysics` (spec: ZoomScrollPhysics). `ScrollArbitration` keeps its name (shared with ZTronPages).

## Non-negotiables
- Library imports only SwiftUI, Combine, Observation (gated), Foundation and ScrollArbitration (SPEC S16). No UIKit/AppKit, *Representable, CADisplayLink, reflection or private API; UIKit appears only in the MC spike app.
- ScrollArbitration's public API is frozen at 1.0.0 after MC (SPEC S16). Never change it from this repo.
- iOS 15 minimum. Every newer API is behind `if #available`, with a fallback that keeps the same API and behavior.
- Scrolling, zooming, refreshing and header collapse never re-evaluate content bodies; offset/zoom are render-time transforms only (SPEC S4).
- Rotation preserves the visible center (SPEC S7).

## Commands (never run raw xcodebuild)
- Physics tests (host, fast): `scripts/test-physics.sh`
- Contract tests (host, fast): `scripts/test-arbitration.sh`
- Build: `scripts/build.sh`
- Tests: `scripts/test.sh -only-testing:<Target/Suite>`. Run only the suites you touched; run the full suite at milestone end.
- Simulators: iOS 17.5, 18.x, 26.x, 27.0 on this Mac. iOS 15/16 runtimes don't run on macOS 27: those smoke tests need Xcode 26.x on an older macOS.
- Prefer the `test-runner` subagent for builds and tests. Use `scout` to locate code and `clerk` for docs/ bookkeeping.

## Working rules (token budget matters)
- One step at a time: edit → build → test → commit. Commit at every green state.
- Locate before reading: grep or `scout` first, then read line ranges. Don't re-read files you just wrote.
- Don't paste code or logs into replies; reference file:line. Keep final replies to 8 lines or fewer unless asked.
- After 2 failed attempts at the same problem, consult the advisor once. If still stuck, stop and write the handoff.
- Start no workflows unless the prompt contains `ultracode` or asks for a workflow.
- No screenshots unless asked; verify with render counters, logs and tests.
- End every session with a handoff in docs/progress/ (template: docs/progress/TEMPLATE.md) and update `Orchestration.md`.

# Compact instructions
Keep: decisions and their reasons, open issues, failing tests, file paths, next steps. Drop: logs, file contents, exploration.
