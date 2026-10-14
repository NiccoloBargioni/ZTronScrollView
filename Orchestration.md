# ZTronScrollView · Orchestration (resume here)

Last updated: 2026-10-14 · by: Claude Code (Opus 5.5, ultracode session)
Status: **M0 done → MC + M1 next**

## Resume in a new session (cheapest path)
1. Open a session in `/Users/admin/Documents/ZTronScrollView` (CLAUDE.md loads automatically).
2. Read **only** this file, then `docs/progress/STATE.md` and the newest handoff in `docs/progress/`.
3. Do the first unchecked item in **Next steps** below. Read spec sections by line range
   (`grep -n '^## [SOF][0-9]' docs/SPEC.md`), never the whole spec.
4. Before stopping: tick what's done here, add a handoff (`docs/progress/TEMPLATE.md`), update STATE.md, commit.

## What this is
`docs/SPEC.md` is the user's spec ("ZoomScroll") verbatim. This repo implements it as **ZTronScrollView**;
the naming map is in `CLAUDE.md`. Part I (S1–S16) = what to build; Part II (O1–O10) = cost plan;
Part III (F1–F7) = repo files (all created in M0).

## Environment (verified 2026-10-14)
- Xcode 27.0 (27A266a), Swift 6.4, macOS 27. `jq` present; no xcodegen/tuist/gh/tmux.
- Simulator runtimes: iOS 17.5, 18.0–18.6, 26.0–26.5, 27.0. **iOS 15.x/16.0 runtimes are installed but
  unusable on this host** → legacy (15/16) smoke tests are a user task on Xcode 26.x / older macOS.
- Default test destination: `platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0` (`.claude/settings.json`).
- `scripts/test.sh` runs xcodebuild **without** `-quiet` (with `-quiet` Swift Testing results are hidden);
  the filter still trims output to results/errors.

## Decisions (keep; reasons in parentheses)
- D1 Naming: ZoomScroll → ZTronScroll, Zoom… → ZTron…, `zoomScroll…` → `ztronScroll…` (user named the
  component ZTronScrollView; lowercase `ztron` prefix matches ZTronPages' `ztronPage()`). Full map: CLAUDE.md.
- D2 Location `/Users/admin/Documents/ZTronScrollView`; package, module and main type are all `ZTronScrollView`
  (matches ZTronCarousel/ZTronMapKit convention).
- D3 `swift-tools-version: 6.0` + `swiftLanguageModes: [.v6]` everywhere (so Xcode 26.x can build the
  iOS 15/16 smoke tests).
- D4 ScrollArbitration stays in `Packages/ScrollArbitration` as a **path** dependency. Freezing = git tag
  `ScrollArbitration-1.0.0` in this repo. Moving it to its own GitHub repo + switching to
  `.upToNextMinor(from: "1.0.0")` is a **user action** (needs a remote; see "User actions").
- D5 Agents don't commit; the orchestrator commits after each verified workflow (avoids index-lock races).

## Milestones (detail in docs/progress/STATE.md)
- [x] M0 setup — Part III files, skeleton packages; `scripts/test-physics.sh`, `scripts/test-arbitration.sh`,
      `scripts/build.sh`, `scripts/test.sh` all green.
- [ ] MC contract lock (ScrollArbitration 1.0.0 + UIKit spike)
- [ ] M1 availability scaffolding + physics + tests (+ S14.1 design note)
- [ ] M2 … M10 (see STATE.md)

## Next steps
1. MC lane (S12 l.581–618, S16 l.754–873): design `docs/design/MC-contract.md` → ScrollArbitration package +
   contract tests → spike app `Packages/ScrollArbitration/Spike/ArbitrationSpike.xcodeproj` + UI tests on
   iOS 17.5/18/26/27 → record answers → tag `ScrollArbitration-1.0.0`.
2. M1 lane (S2–S6 l.46–236, S14.1): `docs/design/design-note.md` (≤1 page) + `docs/design/M1-physics.md` →
   `Packages/ZTronScrollPhysics` + Swift Testing suites → availability scaffolding in `Sources/ZTronScrollView`.

## User actions (can't be done from here)
- Push `Packages/ScrollArbitration` to its own repo (e.g. `git subtree split -P Packages/ScrollArbitration`),
  tag `1.0.0`, then switch both ZTronScrollView and ZTronPages to the URL dependency.
- iOS 15/16 smoke tests and spike runs with Xcode 26.x (`SPIKE_DEVELOPER_DIR=… SPIKE_DEST=… scripts/test-spike.sh`).
- Device checks (ProMotion 120 Hz, gesture feel, rotation) after each milestone.

## Session log
| Date | Session | Work | Result |
|---|---|---|---|
| 2026-10-14 | Opus 5.5 ultracode #1 | M0 | done, committed |
