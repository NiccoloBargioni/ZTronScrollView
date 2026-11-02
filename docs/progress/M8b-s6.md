# M8b-s6 handoff · 2026-10-28 · Opus 5.5 lead (ultracode, xhigh), branch `claude/cool-stonebraker-0015c9`

Status: done; not merged into main (the user merges). Main 9e60063 is merged in. HEAD is the commit that adds this file.
Remaining: the user's answer on D63 (open item 15 a). Pre-existing open item 19 (below) is not fixed.

Lead summary of the seamless scaling header after its review. The fixers wrote their detailed sections in
`docs/progress/M8b-s5.md`: "M8b-s6 (close)", "Core check fixes", "Overlay placement fix", "D65 review fixes" and "Final check fixes".
Each section gives root causes, seam tables and logs.

## Changed (since main 9e60063)
- **Merge:** main merged in (298f42f). The overflow policy is now cited as D59 (795bf1a).
- **Header slot and frame:** the slot is proposed between the safe areas (a7c459f). The keyboard is no longer part of that slot (D64, c089993).
  - Files: `ZTronScrollView.swift`, `HeaderFrameModifier.swift`, `HeaderMath.containerHeight`.
  - New `KeyboardProbeLayout` in `Render/ViewportSpaces.swift`, which writes `ScrollMetrics.keyboardExtension`.
- **M5 resize core** (`Render/ResizeMath.swift`, `ResizeCommit.swift`, `ZTronScrollState.applyViewport`). This applies to every view, header or not.
  - Resize progress is unclamped, so spring overshoots and additive retargets are followed.
  - Safe-area steps during an open resize shift the commit's track (`stepFallback`, `stepDrawn`).
  - Each retarget keeps the old track as `ResizeCommit.outer`, with bounded extrapolation (eebb2a4). The new tracks sit behind one immutable reference.
  - An app-animated safe-area change under an engaged limit is written in the turn's animation (`PositionDriver.animationInTurn`).
- **Refresh** (`Refresh/RefreshIndicators.swift`):
  - The indicator follows the presented geometry during an open resize (`RefreshResizeEffect`, e20473a).
  - The indicator box is a layer group laid out at its clip (5b32f97, open item 18 a). On 15/16 that group exists only under a scaling header (53b272c, `RefreshIndicatorGroup` + the shared `GroupLatch`).
- **Content** (`Render/ContentTransform.swift`): the hit-testing gate is now its own leaf, `ContentInteractionGate`. Before, its `.disabled` was re-created on every frame and re-laid out content controls. That bug was on main too (b7d40cc, open item 17).
- **D65 pull behaviour** (0bd98ad…2258d90):
  - `ZTronHeaderPullBehavior` (`.openGap` default, `.followContent`).
  - The member `scalingHeaderPullBehavior(_:)` and the environment twin `ztronScalingHeaderPullBehavior(_:)` (`Modifiers/ScrollConfigTwins.swift`).
  - Math in `HeaderMath` (`followsContent`, `gapBelow`, `refreshTop` per mode); `HeaderSizing.pull`.
- **Demo and lab:**
  - Seam lab arguments: `-ZTronSeamPull`, `-ZTronSeamKeyboard`, `-ZTronSeamFakeKeyboard`, `capped<digits>`, `kbreal` / `kbrotate` / `opengap` / `follow`.
  - Profile screen: `-ZTronHeaderPull`.
  - Refresh screen: `-ZTronRefreshSection blend|blendOverlay`.
  - `ProofScreen`: the settle label is its own leaf.
  - `scripts/seam/analyze.py --open-gap pull|hold` (6e317c2: per-segment reference, rest gap subtracted).
- **Docs:**
  - SPEC S5 (viewport observation without the keyboard) and S10: overflow container, pull behaviour, seamless edges, 15–16 layer groups, refresh base per mode.
  - Orchestration: D64, D65, D61 amended, open items 15–19.

## Decisions
- **D64 (lead, clarifies D59):** the overflow container excludes the keyboard, so the keyboard never changes R or min. The content inset still lifts above it.
  - Why: dismissing the system keyboard animated R from layout in an animation the container never sees, which left an 85–95 pt seam. Removing the dependency removes the animation that had to be matched.
- **D65 (user):** the `.preserve` pull behaviour is a view modifier, defaulting to `.openGap` (the pre-D61 still header). D61's moving header is `.followContent`.
- No other new decisions. D63 still needs the user's yes.

## Open (Orchestration open items)
- **15:**
  - (a) D63 needs the user's confirmation.
  - (b) The 15/16 F6 overflow limit: R lands at the commit, 70 pt on the forced lane's capped-height rows.
  - (c) A scroll command during an open resize (combo).
  - (d) compositingGroup cost on a real 15/16 device.
  - (e) The `stepDrawn` heuristic.
- **16 (D64):**
  - (a) iOS 15/16 runtimes are unverified on this host.
  - (b) Under an engaged limit, the header can be taller than the region above the keyboard. In landscape `.capped(0.5)` it is 191 pt over 178 pt; the content stays reachable because the header collapses.
  - (c) A band of background shows at the bottom while the keyboard animates. Pre-existing.
- **17:** fixed (overlay placements).
- **18 (D65):** (a) fixed; (b) iOS 15/16 runtimes are unverified.
- **19, pre-existing (fb1fe59; main not checked):** a view without a header, a non-overlay top refresh hold, and a rotation to landscape and back.
  - S7 scrolls the gap off-screen, so the indicator has no placement and is removed.
  - On the way back it appears at its final place over the content for about 14 frames (27.0 and 17.5).
  - Suggested fix: keep it laid out at the signed pull's place (off-screen when negative), so its layer exists and moves with the content.
- **Residuals:**
  - A non-collinear retarget near the drawn size keeps the chord model's 15–45 pt (main's level).
  - Removing that needs the two animations' progress separately.

## Next
1. The user merges `claude/cool-stonebraker-0015c9` into main and answers D63.
2. Open item 19, the headerless rotation during a refresh hold. Measure it with the seam lab: `-ZTronSeamNoHeader 1 -ZTronSeamHold 1`, testRotate, and the review's `rvover.py`.
3. A real-device or iOS 15/16 run (Xcode 26.x on an older macOS): open items 15 (b, d), 16 (a), 18 (b).

## Tests (final HEAD of the code, f4622af; this commit is docs only)
- **Unit `ZTronScrollViewTests`:** 785 tests in 76 suites, green on 27.0 and on 17.5. Each run has 1 known issue (`HeaderReviewD16Tests:137`, F6 on forcedFallback) and 0 feedback-loop warnings.
- **Final check, full demo UI suite at 001a111** (175 tests per lane):
  - 27.0 preferred: 1 failure, the `PanUITests.testControlsUsable` load flake (passed 2/2 alone).
  - 17.5 preferred: 2 pre-existing failures, `PagerUITests.testPagerArbitration` and `PanUITests.testControlsUsable` (both fail on main 9e60063).
  - 27.0 forced: 0 failures.
- **`ProofUITests.testWithAnimationScroll`** forced: 10/10 (it failed 1 run in 3 before the harness fix 4faa80c / 777e8ae).
- **After 53b272c:** `RefreshUITests` + `HeaderUITests` + `ProofUITests` 32/32 on 27.0 preferred, 17.5 and 27.0 forced, including the new blend pixel test.
- **Seam lab** on 27.0 / 17.5 / 27.0 forced. The PASS rule is |seam| ≤ 1 pt, lateral ≤ 1 pt, and no one-frame step ≥ 0.5 of the change.
  - Rotations, width / height / spring / retarget / bottom-pinned resizes, kbfake: all PASS.
  - Real keyboard in portrait and landscape (capped, refit, uncapped, show, hide, rotation with the keyboard up): gap 0.0, overlap ≤ 0.3.
  - Pulls, refresh holds, rotation during a hold, snap, band scroll, ambient and glass backgrounds, both pull modes: PASS. Under `.openGap`, gapExcess ≤ 0.33 and the header bottom drifts ≤ 0.5.
  - The forced capped-height rows stay at the known F6 70 pt (open item 15 b).
  - Tables: `M8b-s5.md` sections; scratchpad notes `fin/notes-keyboard.md`, `pull/notes-build.md`, `pull/fix/final-table.md`, `last/fc/seam-table.md`.

## Usage
```swift
ZTronScrollView { Rows() }
    .withScalingHeader(size: .aspectRatio(16/9, min: 64), background: .ambientBlur(radius: 30),
                       overflow: .capped(fraction: 0.5)) { _ in Header() }
    .scalingHeaderPullBehavior(.followContent)        // this view only; default .openGap

ProfileTabs().ztronScalingHeaderPullBehavior(.openGap) // every ZTronScrollView below; innermost twin wins, member beats twin
```
Usage: not measured.

## Review of item 21 follow-ups (2026-11-01, Opus 5.5 workflow subagent; a19ea0f -> 18620ed + this commit)
- **A, a19ea0f verified** (forced bottom overlay, height 0.4 and back): 8f902f4 drew 84/143 (59 missing, a 500 pt step);
  now 157/157, 0 missing, largest step 0.10 of the 467 pt travel. Those 42-48 pt steps are the forced 27.0 recording (frames
  repeated 2-3 times); 27.0 preferred and 17.5 step 11.3 pt.
- **B, D66's reveal no longer draws over the content** (18620ed, `RefreshIndicators.swift`). The 0.1 s Animatable reveal was a
  translucent fade from ~0.18 s into the rotation: SwiftUI animates what such a modifier's body derives with the transaction's
  animation. Now plain opacity, `RefreshResizeReveal.afterTransition` = 0.15 s linear after 0.3 s; D66's semantics kept
  (Orchestration D66, SPEC S10 amended). `scripts/seam/holdgap.py` counts a translucent probe as over (`tint`, tintOver), and
  its ring test takes only a probe-sized square (the battery icon and a lab button had been 'over').
- **C, the gate reads the latched group**: `RefreshGroupLatched` hands the boxes the `GroupLatch` kind; test
  `RefreshIndicatorLayerTests.theFifteenIndicatorGroupIsOnlyUnderAHeader` checks the gate note (the live gate failed it forced).
- **Seam lab**, 21 scenarios x 27.0 / 17.5 / forced (scen.sh ROT RES NEW HDR); 4 recordings with motion gaps were re-recorded:
  - 0 frames over (opaque or translucent) everywhere.
  - Forced headerless rotations (top / bottom / leading / trailing): over 0 / 0 / 4 / 0 -> 0, off 0 / 3 / 3 / 3 -> 0, missing
    7 / 15 / 10 / 9 -> 23 / 30 / 23 / 24. Hidden through the rotation back, opaque 0.17-0.18 s after it lands.
  - Everything else is as at a19ea0f within run-to-run noise. The resize scenarios' missing / off at the window base (height
    bottom 66 / 10, width leading 75-79 / 18) are pre-existing.
  - Notes: `scratchpad/fu/notes.md`.
- **Tests**: Refresh/Header/Indicator suites (27, 258 tests) green on 17.5, 9 known issues; full unit suite on 27.0: 795 tests in 77 suites green, 9 known issues (as at a19ea0f).
- **Open**: iPad rotations last 0.4 s, so the 0.3 s delay may start the fade before one lands. Not measured, no iPad lane.

## Fix round 2 of the item 21 follow-ups review (2026-11-01, Opus 5.5 workflow subagent; c5ffc4a -> 27bc80f + this commit)
- **MEDIUM fixed (27bc80f), pre-existing at 8f902f4.** A bottom hold while the app animates a bottom `.safeAreaInset` (seam lab
  `kbfake`, 150 pt, easeInOut 1.2 s): the probe vanished on the first frame instead of sliding out clipped by the frame.
  - Mechanism (hosted, presentation tree): not a resize. The viewport extends over the inset, so it keeps its size and only
    `aci.bottom` moves (128 -> 278). The report arrives after the layout pass that animates the container's frame and is
    written unanimated: the indicator's region clip (from the base) jumped 150 pt while the container's clip, its frame,
    followed the app's curve. An overlay jumped 150 pt to its new base (and back, at once, under the frame).
  - Fix: `ZTronScrollState.insetFollow` keeps the turn's animation (`positionDriver.animationInTurn`) and the inset it wrote;
    `RefreshBaseFollow` (leaf) draws the base move in it: an overlay always, the gap only where the content's edge stays
    (`base + pull` unchanged). The animation is set below `RefreshPlacementEffect`, whose `pull` lands at once.
  - Tried: animating the whole metrics write with the turn's animation (as the header follow does) moved the content 75 pt
    (the transform's animated insets take the non-plain path, which keeps the centre); the base made animatable with `pull`
    re-animated the values the modifier's body derives on every frame (moves lagged most of the change).
  - Test `RefreshIndicatorLayerTests.anAnimatedSafeAreaInsetSlidesTheHoldWithTheFrame` (gap / overlay x 2 paths, every
    0.05 s): c5ffc4a 4/4 fail (gap 6, overlay 44-46 of 56 samples bad), 27bc80f 4/4 pass on 27.0 and 17.5.
  - Seam lab, `scripts/seam/insetgap.py` (judged / bad > 1 pt, worst): gap 27.0 144 / 26 -> 146 / 0 (0.67 pt), forced
    143 / 26 -> 139 / 0 (0.33), 17.5 146 / 26 -> 146 / 0 (0.33); overlay (new scenario) 27.0 137 / 0 (0.5), forced 119 / 0
    (0.33), 17.5 137 / 0 (0.33). Controls as before: height04-hbottom 27.0 62/128 in place, 17.5 59/129, 0 over; forced
    rotate-hbottom 55/84, 0 over, 29 missing (was 54/84, 30); forced height04-hbottom-hoverlay 154/154, step 0.024. `kbreal`
    on 27.0: the keyboard covers the probe within 1-2 frames, nothing to judge.
- **LOW recorded as open item 27** (numbered 24 until 2026-11-02; renumbered because main's 24–26 belong to other sessions;
  not measured): D66's reveal also waits 0.3 s after an instant resize on the ungrouped
  15-16 path. Nothing pure-SwiftUI tells it from a system rotation; an orientation heuristic would bring item 20 back for
  single-axis system resizes (iPad, no lane). Orchestration item 27 has the options.
- **Tests:** unit 796 tests in 77 suites green on 27.0 and 17.5, 9 known issues, 0 feedback-loop warnings. Demo UI Refresh/Header/Proof/Resize
  (46 tests) on 27.0 preferred, 17.5 and 27.0 forced: 46/46 each, 0 failures (one lane at a time under the machine lock).
- Notes and recordings: `scratchpad/fu/fx2/` (seam/k27, k27f, k175; logs/).
