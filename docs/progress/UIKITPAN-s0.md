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
Follow-up 2 (2026-10-28, after spike U1 = UIKITPAN-s1 on `claude/keen-lichterman-cfa1e6`):
- Folded U1's C1–C7 into the design, with the user's choices: per-OS cones for N (45° across; 85° on 26.x, 65° on 27.0+ along the page; ties outside) and a narrow S2 allowance (`controllerRoot` walk on the 15–17 window route; `UIControl` / `UISlider` / `UISwitch` checks in the V ctl delegate). §4 is now U1's results; §5 drops U1.
- Added F1: on the UIKit path the baseline credits the whole first sample (UIKit's translation already excludes its hysteresis).
- A 3-lens review plus a skeptic confirmed 17 defects, all fixed. The main ones:
  - the direction vector (finger displacement since the observer's touch-down), because UIKit's translation is bent per axis;
  - the pan is enabled from the static inputs before the touch, because UIKit binds a touch to the recognizers enabled at its start;
  - a pure `receives(hitView:location:anchor:)` with window unit tests;
  - the D31 observer attach in the anchor form;
  - `.uikitPan` is excluded from `forceAllFallbacks`;
  - corrected native facts: 50° at 600 pt/s goes to the carousel on every lane, the slow 50° cell splits on 26.5 / 27.0, and on 27.0 only the 30° list cell depends on speed;
  - new C3 rows: both scenarios, `.inNativeScrollView` without N, the zoomer at 35° / 40°, covered views, first drag after a flip.
- Open: the user answered C2 twice, 15 s apart: (b) here at 23:21:53Z, and (a), one 45° rule, to the spike session at 23:22:08Z (its commit 0038ea9). §9 item 8 records both and what (a) would change. The design follows (b) until the user confirms.
- Open: M-4 (D31 R1's rect-only observer on the UIKit path) is documented and printed, not fixed. Fixing it would widen the walk's allowance to the observer.
Next: 1) the user confirms C2; 2) U2 → U3 → U4 → U5, after D40 / SHEET-s3 are decided for U3.
Tests: none (design only). The review evidence is in this session's scratchpad (`understand/*.md`, `review.md`), not committed.
Usage: not measured
