# STATE
Status: RUNNING
Current: M5 (b): rotation criteria A+B met on both user trees (D18/D19) and criterion C fixed in code (D20, 2026-10-19; user device check pending) → full demo UI re-run (Orchestration step 3), PanCoordinator rebase; MC freeze blocked on a user decision

| Milestone | Status | Budget % | Used % (my readings) | Notes |
|---|---|---|---|---|
| M0 | done | 0–1 | | repo, scripts, hook, agents, CLAUDE.md, skeleton packages; host + iOS 27 sim tests green |
| MC | partial | 3–5 | | package + spike done; tag blocked on Q3 (iOS 17.5) decision, see Orchestration.md Open items #1 |
| M1 | done | 6–9 | | physics 99 tests, availability 16 tests, design note; weekly limit hit in fix round (recovered 2026-10-18) |
| M2 | done | 7–10 | | render proof green on 27.0 + 17.5, both paths (docs/progress/M2-s3.md) |
| M3 | done | 8–10 | | pan/release/catch/delegate/arbitration; 123 unit tests; demo UI 14/14 on 27.0 both paths; PanUITests 7/7 on 17.5 both paths |
| M4 | done | 5–7 | | zoom state + pinch adapter + demo; criterion C staggered-lift fix (D20, docs/progress/M4-s3.md); ZoomUITests 7/7 on 27.0 (both paths) + 17.5 preferred; 17.5 forced pending |
| M5 | partial | 5–7 | | (a) done; (b) rotation acceptance A+B green on 27.0 + 17.5 both paths (docs/progress/M5-s2.md s4); left: user device check of (C), PanCoordinator rebase, insets into pan/pinch env |
| M6 | todo | 8–11 | | |
| M7 | todo | 6–8 | | |
| M8 | todo | 6–9 | | |
| M8b | todo | 6–9 | | |
| M9 | todo | 9–13 | | |
| M10 | todo | 6–8 | | |

Open issues:
- iOS 15/16 simulator runtimes don't run on this Mac (macOS 27). Legacy smoke tests need Xcode 26.x on an older macOS (user).
Device feedback queue:
