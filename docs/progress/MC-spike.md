# MC spike handoff
Status: spike project built and run on 27.0, 18.6, 17.5, 26.5; results in docs/design/MC-contract.md section 6 and notes A-E.
- 27.0 and 18.6: all 7 UI tests green (18.6 Q2 caveat, note D).
- 17.5: Q3 answered NO (paging pan blocked by SwiftUI gesture); fallback in note E. The runner hangs on teardown there.
- 26.5: page-0/button/fling green; testDragsPageOne `-startPage 1` did not land (harness).
- Touch hooks: scroll view touchesBegan override is never called (note A); a passive recognizer is used.
- Not done: iOS 15/16 (user), 1.0.0 tag (orchestrator), Orchestration.md update.
