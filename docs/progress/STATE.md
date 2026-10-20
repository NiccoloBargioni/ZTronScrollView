# STATE
Status: RUNNING
Current: step 3 done 2026-10-20 (full demo UI suite: 42/42 on 27.0 both paths, 41/42 on 17.5 both paths = the known Q3 pager case); M6 (a) + N-a done; D27 decided → next = step 4 (M5 (b) remainder, M6 (b) session 2 in the SwiftUI target space, then M8b-1); Debugger item 6 (27.0 forced duplicate content copy); MC freeze blocked on the user's Q3 decision

| Milestone | Status | Budget % | Used % (my readings) | Notes |
|---|---|---|---|---|
| M0 | done | 0–1 | | repo, scripts, hook, agents, CLAUDE.md, skeleton packages; host + iOS 27 sim tests green |
| MC | partial | 3–5 | | package + spike done; tag blocked on Q3 (iOS 17.5) decision, see Orchestration.md Open items #1 |
| M1 | done | 6–9 | | physics 99 tests, availability 16 tests, design note; weekly limit hit in fix round (recovered 2026-10-18) |
| M2 | done | 7–10 | | render proof green on 27.0 + 17.5, both paths (docs/progress/M2-s3.md) |
| M3 | done | 8–10 | | pan/release/catch/delegate/arbitration; 123 unit tests; demo UI 14/14 on 27.0 both paths; PanUITests 7/7 on 17.5 both paths |
| M4 | done | 5–7 | | zoom state + pinch adapter + demo; criterion C staggered-lift fix (D20, docs/progress/M4-s3.md); ZoomUITests 7/7 on 27.0 (both paths) + 17.5 both paths (full demo UI re-run 2026-10-20, step 3) |
| M5 | partial | 5–7 | | (a) done; (b) rotation acceptance A+B green on 27.0 + 17.5 both paths (docs/progress/M5-s2.md s4); D21 render-path pixel tolerance, D22 programmatic zoom = native ease-in-out + duration law (ZoomTiming, docs/progress/USER-s3.md), D23 hand-off overscroll (docs/progress/USER-s2.md), D24 pinch overscroll rubber band + didZoom cadence kept per SPEC, D25 lift snap = trailing magnify sample ignored (USER-s4.md); device checks of C, D21, D22, D25 done by the user; left: PanCoordinator rebase, insets into pan/pinch env |
| M6 | partial | 8–11 | | (a) session 1 done (`docs/progress/M6-s1.md`, 7243121): target-behavior family + `.paging` ≡ `isPagingEnabled`, member/twin, reader/proxy `scrollTo`, `ztronScrollID` registry; unit 275/275 on 27.0 + 17.5, ZoomUITests 7/7; open: target space vs SwiftUI's (decide before session 2); left: session 2 (ViewAligned, NativeBridges, ScrollTargetLayout), session 3 (Position, DefaultScrollAnchor, TargetsScreen) |
| M7 | todo | 6–8 | | |
| M8 | todo | 6–9 | | |
| M8b | todo | 6–9 | | design amended 2026-10-19 per the user (SPEC S9/S10/S11/S14, M8b §2–3, M8-chrome §7b/M8-8; docs/progress/M8b-s0.md); A1–A10 approved by the user 2026-10-19; refresher shapes `.refresher { }` / `.refresher(refreshView:)` guaranteed, no introspection |
| M9 | todo | 9–13 | | |
| M10 | todo | 6–8 | | |

Open issues:
- iOS 15/16 simulator runtimes don't run on this Mac (macOS 27). Legacy smoke tests need Xcode 26.x on an older macOS (user).
Device feedback queue:
| N-a | done | 3–4 | | nested ZTronScrollView arbitration API (docs/design/NESTED-arbitration.md, D28); N-b demo + SPEC amendment pending (docs/progress/NESTED-s1.md) |
