# STATE
Status: RUNNING
Current: integrated HEAD f985f95 verified 2026-10-20 (unit 349/349 on 27.0 + 17.5; demo UI 55 executed per run, green on 27.0 both paths, 17.5 both paths = the known Q3 pager case only); M6 (a)+(b), N-a/N-b, M8b-1, DBG-s1 (open item 6) done; D27 confirmed, D29/D30 in; M8 (1) chrome exemplar done (`docs/progress/M8-s1.md`, 5b9a6f7: unit 477/477 on 27.0 + 17.5) → next = step 4 (M5 (b) remainder / M6 s3 / M8b-2 / M8-2) from a Sonnet orchestrator; MC freeze blocked on the user's Q3 decision

| Milestone | Status | Budget % | Used % (my readings) | Notes |
|---|---|---|---|---|
| M0 | done | 0–1 | | repo, scripts, hook, agents, CLAUDE.md, skeleton packages; host + iOS 27 sim tests green |
| MC | partial | 3–5 | | package + spike done; tag blocked on Q3 (iOS 17.5) decision, see Orchestration.md Open items #1 |
| M1 | done | 6–9 | | physics 99 tests, availability 16 tests, design note; weekly limit hit in fix round (recovered 2026-10-18) |
| M2 | done | 7–10 | | render proof green on 27.0 + 17.5, both paths (docs/progress/M2-s3.md) |
| M3 | done | 8–10 | | pan/release/catch/delegate/arbitration; 123 unit tests; demo UI 14/14 on 27.0 both paths; PanUITests 7/7 on 17.5 both paths |
| M4 | done | 5–7 | | zoom state + pinch adapter + demo; criterion C staggered-lift fix (D20, docs/progress/M4-s3.md); ZoomUITests 7/7 on 27.0 (both paths) + 17.5 both paths (full demo UI re-run 2026-10-20, step 3) |
| M5 | partial | 5–7 | | (a) done; (b) rotation acceptance A+B green on 27.0 + 17.5 both paths (docs/progress/M5-s2.md s4); D21 render-path pixel tolerance, D22 programmatic zoom = native ease-in-out + duration law (ZoomTiming, docs/progress/USER-s3.md), D23 hand-off overscroll (docs/progress/USER-s2.md), D24 pinch overscroll rubber band + didZoom cadence kept per SPEC, D25 lift snap = trailing magnify sample ignored (USER-s4.md); device checks of C, D21, D22, D25 done by the user; left: PanCoordinator rebase, insets into pan/pinch env |
| M6 | done | 8–11 | | (a) session 1 done (`docs/progress/M6-s1.md`, 7243121): target-behavior family + `.paging` ≡ `isPagingEnabled`, member/twin, reader/proxy `scrollTo`, `ztronScrollID` registry; unit 275/275 on 27.0 + 17.5, ZoomUITests 7/7; open: target space vs SwiftUI's (decide before session 2); session 2 done (`M6-s2.md`, 612b068): ViewAligned + LimitBehavior, NativeBridges, `ztronScrollTargetLayout`, resize keeps the aligned item, ViewAlignedTests 16; session 3 done (`M6-s3.md`, 07d8f54): `ZTronScrollPosition` + `PositionDriver` (write-back at the release target and at settle, ≤ 2 per gesture), `scrollPosition` ×2 member + twins, `defaultScrollAnchor` + roles, `ScrollPosition` / `ScrollAnchorRole` bridges, `TargetsScreen` + `TargetsUITests` 7/7 on 27.0 both paths + 17.5, R4 (context velocity is pt/ms, D32) / R5 / Open 4 closed, full unit suite 480 on 27.0 + 17.5; open: D32 decision, R5 on 17.5, lazy content (M9) |
| M7 | partial | 6–8 | | (a) session 1 done (`docs/progress/M7-s1.md`, b0ab38a): `ObserverHub` + state hook, geometry member/twin + 18+ bridge, content visibility modifier, 48/48 in the touched suites on 27.0 + 17.5; left: session 2 (phase ×2, target visibility, `EventLogScreen`), session 3 (transitions, R1) |
| M8 | partial | 6–9 | | (1) chrome exemplar done (`docs/progress/M8-s1.md`): `ChromeConfig` + `ChromeLeaf` + scroll indicators (member + twin + mirror + hot leaf + fade + `scrollIndicatorInsets` / `flashScrollIndicators()`), 79 new tests, unit 477/477 on 27.0 + 17.5 at 5b9a6f7, parity rows; left: M8-2 … M8-8 (margins, clip, keyboard, input, a11y, helpers, edge effects, containers, system hooks, delegate modifiers, demo `ChromeScreen`); device risk 3 (indicator constants) open |
| M8b | partial | 6–9 | | (1) refresh engine done (`docs/progress/M8b-s1.md`): engine + coordinator + hold in `adjustedContentInset` + `beginRefreshing/endRefreshing` + reach-edge watchers, 43 tests, unit 345/345 on 27.0 + 17.5, not wired into the container; left: M8b-2 (refresher API, indicators, accessibility, demo `RefreshScreen`), M8b-3 (scaling header); device risks R1–R3 open; design amended 2026-10-19 per the user (SPEC S9/S10/S11/S14, M8b §2–3, M8-chrome §7b/M8-8; docs/progress/M8b-s0.md); A1–A10 approved by the user 2026-10-19; refresher shapes `.refresher { }` / `.refresher(refreshView:)` guaranteed, no introspection |
| M9 | todo | 9–13 | | |
| M10 | todo | 6–8 | | |

Open issues:
- iOS 15/16 simulator runtimes don't run on this Mac (macOS 27). Legacy smoke tests need Xcode 26.x on an older macOS (user).
Device feedback queue:
| N-a | done | 3–4 | | nested ZTronScrollView arbitration API (docs/design/NESTED-arbitration.md, D28); SPEC amendment written with N-b (docs/progress/NESTED-s1.md) |
| N-b | done | 1.5–2 | | nested demo `NestedPagerScreen` + `NestedPagerUITests` 13/13 on 27.0 + 17.5 both paths; D30 measurement isolation fix; SPEC S11/S12 + parity row (docs/progress/NESTED-s2.md) |
| UIKIT-a | done | 1 | | D31 session (a): pure `TouchObserverCore` (100 % lines), `uikitTouchObserver` capability + DEBUG force switch, state flag; unit 520/520 on 27.0 + 17.5 (docs/progress/UIKIT-s1.md, 5aba0db); next (b) shell + wiring + UI tests + gate scripts |
