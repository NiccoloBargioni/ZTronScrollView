# UIKITPAN-s0 handoff · 2026-10-27 · Opus 5.5 · default effort (side session, Architect, ultracode lean: 4 readers + 3 reviewers; design only)
Status: done. The user approved a recognizing UIKit pan for N (a ZTron view inside a native vertical `ScrollView`, iOS 26+, D47) and S (a pager in a `.sheet`, D36), with 100 % coverage (D60). The user then accepted every §9 recommendation and asked for an opt-in modifier (folded in, same session). Nothing is built.
Changed:
- docs/design/UIKIT-pan.md (new, 336 lines): why a UIKit pan alone is not enough; the UIKit path (D31 observer + axis-aware pan; routes, delegate, axis rule, `.declined`, mapping, second finger); per-sequence activation; spike U1 Q1–Q9 with pass criteria; sessions U1–U5; coverage definition C1–C4 and gate mechanics; SPEC S2 amendment text; risks; open questions.
- Orchestration.md: open item 14, D60, session-log row.
Decisions (proposed, from the review):
- Representable route on 18+; window route only for S on 15–17, with `isDescendant(of: touch.view)`.
- Simultaneity `true` for `scrollArbitrationGestureName`; for other recognizers it is spike variable V.
- A participant of a one-axis container accepts drags more than 30° off the container's axis (fixes the 30–45° dead band). `participantDeclined` lets the container resolve past a declined participant.
- `PanEvent.declined` is emitted from `shouldBegin`, never from `.failed`.
- The path is latched per sequence. N is gated by the 26 SDK and runtime and is vertical-only. S is set by the app.
Follow-up (user answers):
- Opt-in modifier `ztronScrollUIKitPan(_ scenarios: ZTronUIKitPan)`, `.inNativeScrollView` (N) and `.inSheet` (S), environment-backed, default `[]`, no default argument. It replaces the `.offAxis` overload; `ztronScrollYieldsToSheet(Bool)` is unchanged.
- Latched per view at the first body in a `@State` reference box, so the gesture structure never flips (S4). Without the opt-in a view builds today's structure; the DEBUG counter `uikitpan.made` proves it in every suite.
- No `-ZTronForceUIKitPan`: the A/B lane toggles the opt-in in the demo.
- §6 opt-in gate rows, an older-SDK C4 item, §7 S2 and CLAUDE.md text, §9 answers, R9.
- Same-axis scrollable views stay on the SwiftUI path if no V passes Q3, per S2's "match native".
Open:
- D40 and SHEET-s3's D47 (§9 Q7): no recommendation; they block U3, not U1 or U2.
- `origin` re-pin. The app's `sync_with_base_branch` refused because `origin` changed since the app pinned it (now github.com/NiccoloBargioni/ZTronScrollView.git). This branch was fast-forwarded to local main 9e60063 instead.
Next: 1) U1 spike (Opus), §4; 2) U2 → U3 → U4 → U5, after D40 / SHEET-s3 are decided for U3.
Tests: none (design only). The review evidence is in this session's scratchpad (`understand/*.md`, `review.md`), not committed.
Usage: not measured
