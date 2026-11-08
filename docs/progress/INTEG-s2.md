# INTEG-s2 handoff · 2026-11-03 · Opus 5.5 (integration session, wave 2 subset: plan rows 9, 10, 13)
Status: done — variant (b2) of D86: rows 10 and 13 merged and verified on `claude/integ-wave-2-b2` without row 9; main fast-forwarded to it
(never pushed, no branch deleted). Row 9 (sharp-banach stage B, D40) is accepted (D84) but not landed as the 26+ default (D86).
Changed (from main a82f144; the attach, `PanGestureAdapter.swift`, is byte-identical to a82f144):
- Row 10, cherry-picks (a merge of confident-babbage would bring sharp-banach with it): 6980bc7 = b84302c's demo part only
  (`MixedTopologyScreen`, `MixedTopologyUITests`, case `mixed`), 15dd33b = 0d00c02 (strict per-OS `MixedTopologyUITests`, ZTron-page cases,
  `MixedProbe…` harness), 1bc7ba0 = a0ba8de (D47 before D49, open item 13 after 11, SPEC S12 "Inside SwiftUI's own `ScrollView`" bullet without
  D40's wheel bullet, M3-pan unchanged, parity row after the sheet hand-off row, STATE row DBG-s8 only). DBG-s5's item 12 stays on sharp-banach.
- Row 13: 34d1868 merge keen-lichterman (U1 spike + U2 core, D60; DemoApp keeps `buttonDrag` + the three `uikitPan…` cases, item 14 after 13,
  D60 after D59, log rows in date order), 82a420a merge upbeat-mendeleev (`UIKIT-pan.md` == 9e6d448; item 14 C2 = option (b) and Next = U3;
  UIKITPAN-s1.md Open / Next read option (b) and D86). The U2 core is not wired.
- ecbc1ce fix-ups: DBG-s8's demo `ProbeAnchor` → `MixedProbeAnchor` (U1 declares its own: the demo did not compile); D73 + D60 unit test
  `aLazyDeclineIsSupersededByTheOutersTouchDown`; `UIKitControlsUITests` wheel expectation is a required fix naming open item 39 (26+) / 37
  (below 26), still not strict, so every lane reads as on a82f144.
- 88548e7 D86 (variant b2), item 39, item 40 reserved, the D84 append, SPEC S12 wheel sentence (required fix, items 37–39), plan rows 9 / 10 / 13,
  Orchestration State rows.
Decisions:
- D86 (orchestrator, applying D74): no attach keeps Button, slider and wheel together on 27.0 (`.simultaneous`: wheel scrolls 50; `.gesture`:
  Button drags freeze ~110 pt then jump, the edge drag fires the Button at content 0, native 474; `.highPriorityGesture`: slider and wheel
  broken), so the non-shared pan stays `.simultaneous` on 26+. (b2) taken because rows 10 and 13 do not need row 9's code (0d00c02's
  assertions are per OS and give the same numbers with either attach; keen-lichterman / upbeat-mendeleev never touch the attach).
- References kept: `claude/sharp-banach-dadf23` (stage B, D40) and `claude/integ-wave-1-60dda2` at bde9dd7 (rows 9/10/13 with D40 + D85:
  `.adaptive` shares while armed with a text input edited, because ContentShield's `.onTapGesture` starves a `.gesture` observer).
- Numbers: D85 (bde9dd7 only), D86; open items 39 (D86) and 40 (reserved for M9-s1, whose 36 collides with M8b-s8 s1's 170c1d3).
  Next free: D87, open item 41.
Open:
- Items 37 / 38 / 39 (the picker fix after U3). No UI test covers item 38 (a wheel in a nested inner / pager page / container) yet.
- Item 25's strict 18+ expected failure stays as on main (D40 closed it on 26+; with D86 it is open again there).
- Absorbed branches (confident-babbage, keen-lichterman, upbeat-mendeleev) still to delete on the user's yes; nothing was deleted.
Next:
1. U3 (UIKITPAN): wire the U2 core (`UIKitPanCore`, `.declined` / `.settle`, revive, F1) for scenarios N and S (D60).
2. The picker fix (items 37, 38, 39): pure SwiftUI first, then a scoped UIKit route at 100 % coverage (D74, D84, D86).
3. Wave 2 rows 11–12 (cool-stonebraker, refresh branches); m9-a1 takes open item 40 when it merges.
Tests (private clones, own derived data, one demo UI lane machine-wide under `ztron-ui-lane.lock`):
- Build green. Unit `ZTronScrollViewTests` 798 (bde9dd7's 805 minus the 6 D40 `PanAttachTests` and the D85 test), 0 feedback-loop
  warnings: 27.0 798/798, 17.5 798/798, 18.5 798/798, 26.5 797/798 (`ChromeLeafTests.aScriptedScrollAndZoom…` under load 28, 3/3 alone,
  the flake also seen on bde9dd7). Physics 119, arbitration 39 (packages untouched since a82f144).
- Demo UI on code tip 88548e7 (passed / failed / skipped): 27.0 preferred 208/0/32 · `--forced` 187/1/52 · `--uikit` 188/0/52; 17.5
  preferred 207/1/32 · `--forced` 187/0/53; 18.5 targeted (Sheet, ScrollDisabled, MixedTopology, UIKitControls, NestedPager, Pan, Refresh,
  ButtonDrag) 138/5/0; 26.5 the same + ContentOverlay 147/0/0. Item 25's strict expected failure and the wheel's required-fix expectation
  held on every lane.
- The single reds passed 3/3 alone under the lock (full-suite load flakes): 27.0 `--forced`
  `NestedPagerUITests.testAutomaticVerticalListScrollsAndHorizontalPages`, 17.5 preferred
  `HeaderUITests.testAHeaderButtonWorksAtPartialHeightAndHidesAtZero`.
- 18.5 `SheetUITests` Y1–Y5: red with identical numbers on base a82f144 (Y1 169 ≠ 0, Y2 63 ≠ 72, Y3 0 ≠ 1, Y4 169 ≠ 0, Y5 0 ≠ 1),
  run alone under the lock: open item 10 (D46), not a regression.
Usage: not measured.
