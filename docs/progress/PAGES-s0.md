# PAGES-s0 handoff · 2026-10-25 · Opus 5.5 · default effort (side session, Architect: design only, no code)
Status: done. `docs/design/ZTRONPAGES-integration.md` (239 lines) is written and waits for the user's answers (8 open questions). Nothing was built or tested.
Changed:
- docs/design/ZTRONPAGES-integration.md (new): topologies T1–T8 with a per-OS matrix; options A–D compared; recommendation B; MC spike notes A–E under B and under the UIKit recipe; acceptance tests A1–A12 (+ U1–U3); impossibilities; builder split P-a…P-d; risks R1–R7; open questions.
- Orchestration.md: Open item 2 pointer and a session-log row. No D-number assigned: this is a proposal; the clerk takes the next free number when the user decides.
Decisions (proposed):
- B: ZTronPages = a paging `ZTronScrollView` on every OS. D28's nested arbiter already arbitrates pager and zoomer in pure SwiftUI, so note E and D47 cannot occur. This is D50's SwiftUI pan on 15–17, and the same code runs on 18+.
- The UIKit pager is a recipe only: an owned `UIScrollView` subclass, names on 18+, Q3-s1 `cancel` on ≤ 17. `UIPageViewController` and `TabView(.page)` are unsupported.
- Under B there is one arbiter, in the outer's content space, so R6 is met automatically. The UIKit recipe uses one arbiter per page.
Open:
- The user's 8 questions. Q1 (ZTronPages depends on ZTronScrollView, which amends S16's premise) gates everything.
- Unmerged inputs: Q3-s1 (`claude/spike-q3-descendant-simultaneous`), D47 DBG-s8, SHEET-s3, D34/D37/D40.
- `NavigationStack` back swipes are unmeasured (R1).
Next: 1) the user answers Q1–Q3; 2) P-b demo stand-in (`PagesScreen` + `PagesUITests`) and P-c three levels, in parallel; 3) P-a, the ZTronPages core, in the home chosen in Q2.
Tests: none (design only).
Usage: not measured
