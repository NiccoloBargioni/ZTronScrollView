# DBG-s3b handoff · 2026-10-20 · Sonnet 5.5 · Debugger (the M3b content gate evicts a focused UIKit text field; DBG-s2 Open 1 / Orchestration open item 25 (a))
Status: done — a focused `TextField` keeps the keyboard through a drag, a fling, an animated scroll and a resize on iOS 17.5 and 27.0 (the editing session never ends: `edit=1/0`), red before / green after (5 tests on 17.5, 3 on 27.0); the catching-touch and press-under-the-finger behaviors of M3b are unchanged. One documented gap (iOS 18+, a text input edited, a Button pressed before the drag) — see Open 1.
Started from main ecca598 + the DBG-s2 commits (cherry-picked: e8c5674 → b409f3f, cb275d7, ef69afa; the two append-only conflicts kept both sides).

## What was wrong (measured)
`TransformHost` applied `.allowsHitTesting(!blocked).disabled(blocked)` to the content while it was decelerating, animating (the resize watch's too) or dragged. Oracle used throughout: the number of editing sessions that began / ended (`UITextFieldTextDidBeginEditing` / `EndEditing`, shown in the demo's Info line as `edit=<begun>/<ended>`; `keyboards.count` read DURING a lock is unreliable). Levers applied by the APP to the content while a field is focused (`ZZLever` probe, 17.5 and 27.0 identical):

| lever | session ended? | afterwards |
|---|---|---|
| `.disabled(true)` | yes | never comes back (keyboards 0) |
| `.allowsHitTesting(false)` | **yes** | SwiftUI re-focuses when hit-testing returns (`edit=2/1`): the keyboard flickers away for the whole lock |
| GestureMask `.none` | no | — |
| overlay shield (clear, `contentShape`, `onTapGesture {}`) | no | — |

So the lead's guess (a hit-absorbing leaf instead of disabling) was right for the focus, and `allowsHitTesting(false)` is not innocent either. What each lever REACHES (static probe, the app applies it to `ControlsContent`, one tap each on Button / Toggle / TextField, idle):

| lever | 17.5 | 27.0 |
|---|---|---|
| `allowsHitTesting(false)` | all three blocked | all three blocked |
| `.disabled(true)` | all three blocked | all three blocked |
| GestureMask `.none` | Button blocked; Toggle and TextField work | **Button works**; Toggle and TextField work |
| shield overlay | Button blocked; Toggle and TextField work | all three blocked |
| high-priority zero-distance drag | all three blocked | Button blocked; Toggle works |

And for the press that began under the finger (`PanUITests.testPanStartingOnButtonScrollsWithoutFiring`, a pan that starts on a Button): hit-testing off, shield (held until the lift), a high-priority pan (`splitHigh`) and `.gesture(pan)` do NOT end it on either OS; `.disabled` does everywhere; the mask only on 17.5. (`testCatchDuringDecelerationDoesNotFireButton` flings from a Button, so it also contains that press: every "hit-only fails the catch" reading in the first matrices was this press, not the catch. `testCatchOfAFlingThatStartedOffAButtonDoesNotFireButton` starts in a gap and isolates the catch: hit-testing alone is enough, with or without a hold until the lift.)

## Changed
- `Render/ContentGate.swift` (new): `ContentLock`, pure `ContentGatePolicy.lock(phase:isTracking:isDragging:isEditingText:)`, `ContentGate` (`allowsHitTesting`, `.disabled`, a never-beginning `DragGesture` carrying the mask), `ContentShield`.
  Policy: new touches are taken away while the content moves without a finger (`.decelerating` / `.animating`, `!isTracking`) or a drag is recognized. Not editing: `allowsHitTesting(false)`, plus `.disabled` for a recognized drag ONLY (so a deceleration, an animated scroll and a resize disable nothing any more: the wrapper cases of DBG-s2 pass). Editing: the shield for the new touches and the mask for the press under the finger, neither of which touches UIKit.
- `Render/TextEditingMonitor.swift` (new): is a text input being edited? UIKit's public editing notifications (`UITextField` / `UITextView`, which SwiftUI's TextField / SecureField / TextEditor are) read by NAME as strings: no UIKit import or symbol (`scripts/check-uikit-scope.sh` clean, 95 files), weak sources, started in `ZTronScrollState.init`. DEBUG counters `editing.begin` / `editing.end`, `gate.shield` / `gate.disabled` / `gate.mask` (evaluations per means).
- `Render/ContentTransform.swift` (`TransformHost`): asks the policy, applies `ContentGate` and the shield overlay (above the viewport, outside the transform). `State/ZTronScrollState.swift`: one line starting the monitor.
- Demo: `ControlsScreen` gets Animate (`setContentOffset(y: 120, animated: true)`), Resize (4 s linear height change: a long, static lock), `-ZTronControlsWrap offset|scale|rotation|opacity|compositing|native` (the app-level wrapper cases and the native reference) and the editing-session readout (`edit=<begun>/<ended>`) in Info. `PanScreen` gets `-ZTronPanField` (a TextField beside the buttons, an Animate button, a shorter scroller and a short counter list so it fits above the keyboard of an iPhone 15). `NestedPagerUITests` comment only.
- Tests: `PanUITests` 8 → 18 (below), `ContentGatePolicyTests` (8) and `TextEditingMonitorTests` (4) in `ZTronScrollViewTests`.
- Docs: SPEC S12 (+ nested wording), `M3-pan.md` §6, `M8-chrome.md` §4, parity matrix row, Orchestration (D72, open item 25 (a), log), STATE.

## New PanUITests (red before / green after, on 17.5 and 27.0)
`testDragKeepsFocusedTextField`, `testFlingKeepsFocusedTextField`, `testAnimatedScrollKeepsFocusedTextField` (red on both OS before, `edit=` never `1/0`; typed text "ab"), `testFocusedTextFieldKeepsKeyboardInScaleEffectWrapper` / `…InRotationEffectWrapper` (red on 17.5 before; the 27.0 never failed), `testFocusedTextFieldKeepsKeyboardThroughAvoidance` (the DBG-s2 test, now with the oracle). Guards that are green before and after: `testNativeScrollViewKeepsFocusedTextFieldOnDrag` (the reference: native keeps the session), `testTapOnUIKitControlsIsBlockedWhileContentIsLocked` (a slow resize locks the content; a tap on the Toggle and the TextField does nothing; unlocked again after), `testCatchOfAFlingThatStartedOffAButtonDoesNotFireButton` (isolates the catch from the press under the finger), `testCatchWhileATextInputIsEditedDoesNotFireButton` (animated scroll caught by a tap while the field outside the scroll view is edited: the shield; `gate.shield > 0`, `gate.disabled == 0`) and `testPanStartingOnAButtonWhileATextInputIsEditedScrolls` (the mask: asserted on 17.5, an expected failure on 27.0 that pins Open 1).
Red-before evidence: the old gate + the oracle in a scratch worktree at b9215cf: 17.5 11/16 (animated scroll, drag, fling, scale, rotation red), 27.0 13/16 (animated scroll, drag, fling red). Logs in the notes folder.

## Decisions (D72 in Orchestration)
- The resize watch's `.animating` STAYS in the gate (H1 of DBG-s2 not taken): after this change a resize lock no longer disturbs a focused field (hit-testing for a field-less screen, shield while editing), the scale / rotation wrappers pass on 17.5, and a touch during a rotation transition is still kept from a moving Button.
- A (size, inset) pair that moves in lockstep is NOT reclassified as an inset change in `applyViewport`: with the gate fixed the spurious resize is harmless (unobscured size and centre unchanged, a few locked frames), the wrapper tests are green, and the M5 resize path has its own suites; the misclassification risk (a real resize whose size delta equals an inset delta) is not worth a speculative change. Reopen only if a measurement shows churn.
- `.disabled` stays for the press under a recognized drag while nothing is edited: it is the only thing that reaches a Button on 27.0.
- Accessibility: the old gate dimmed every control and refused VoiceOver activation during any motion, including the accessibility scroll action's animated scroll. Now `.disabled` exists only while a finger drags (VoiceOver's explore-by-touch does not pan); the shield is `accessibilityHidden`, the mask and hit-testing do not touch the accessibility tree. Not run with VoiceOver (the simulators cannot); the XCUI accessibility queries during a lock still find every element (`testTapOnUIKitControlsIsBlockedWhileContentIsLocked` reads the Toggle's value while locked). Side effect worth knowing: controls no longer flash disabled during a fling.

## Open
1. **Gap, iOS 18 and later** (measured on 18.6, 26.5 and 27.0): while a text input is edited, a pan that began on a SwiftUI Button can still fire it on lift (the mask does not reach a Button there; hit-testing, the shield and a high-priority pan do not either, `.disabled` would take the keyboard). On 17.5 the mask ends the press. `testPanStartingOnAButtonWhileATextInputIsEditedScrolls` pins it (`XCTExpectFailure` on 18+, an assertion on 17). If that matters: a UIKit-level touch cancel is the only thing that reaches it, which the library may not use.
2. In the same state on 17.5 the shield does not reach UIKit-backed controls (a catching tap can still toggle a Toggle or focus another field); on 27.0 it does.
3. 15 and 16 cannot run here: the mask's effect on a Button there is unverified (the non-editing path is the old gate's pair, so only the editing path is new).
4. `PanUITests.testControlsUsable` loses its first Toggle tap now and then under host load (1 of 5 at the base gate on 27.0 too; DBG-s2 Open 3).
5. A text field focused before the first `ZTronScrollState` exists is not seen by the monitor (the gate falls back to the old behavior for it).

## Next
1. Take Open 1 only if an app needs a Button-safe pan while editing on 18+.
2. Delete the `keyboards.count`-during-lock habit from future tests: the Info `edit=` readout is the oracle.
3. The 18.x slider step of `testControlsUsable` (DBG-s2 Open 2) still fails on 18.6 (slider stays 0.2); unrelated to the gate.

## Tests
Private clones of idle devices per lane, own derived data, `-collect-test-diagnostics never`; host load 130–850 from other sessions.
- Unit: `scripts/test.sh` (all of `ZTronScrollViewTests`) → 599 tests in 53 suites green on 17.5 and 27.0 at 86ae809 (+12: `ContentGatePolicyTests` 8, `TextEditingMonitorTests` 4; 587 before).
- Demo UI, the requested set (PanUITests, ProofUITests, ResizeUITests, ZoomUITests, ImageUITests, NestedPagerUITests, PagerUITests, TargetsUITests; 69 executed, none skipped), final tree 86ae809:
  27.0 preferred 69/69 · 27.0 `--forced` 69/69 · 17.5 preferred 68/69 · 17.5 `--forced` 68/69. The one failure on 17.5 is `PagerUITests.testPagerArbitration` (spike Q3), as before.
- PanUITests alone (18 tests): 17.5 18/18, 26.5 18/18, 27.0 18/18, 18.6 17/18 (`testControlsUsable`, the 18.x slider step: DBG-s2 Open 2).
- UIKit observer path (`--uikit`, D31): PanUITests + ZoomUITests 25/25 on 17.5 and 27.0.
- Red before: a scratch worktree at b9215cf with only the oracle (the monitor's counters) and the new tests: 17.5 11/16 (animated scroll, drag, fling, scale wrapper, rotation wrapper red), 27.0 13/16 (animated scroll, drag, fling red); the same tests are 16/16 at 1a9be45 on both OS.
- `scripts/check-uikit-scope.sh` clean (95 files). About 40 matrix runs of the lever variants (GestureMask, shield, eater, hit-only, hold, split pan modes) are in the notes folder as one patch plus the logs of the decisive runs.

Usage: not measured (about 150 simulator runs on 8 private clones, deleted at the end; the scratch worktree too). Notes folder: `side-session-notes/local_936c3932-…/gate-focus/` (FINDINGS.md, the experiment patch with every variant, the runner scripts, red / green logs).
