# DBG-s1 handoff · 2026-10-20 · Opus 5.5 · Debugger (SPEC O2)
Status: done. Orchestration open item 6 (M6-s1 Open 3, "second copy of the content on 27.0 forced") resolved: root cause found, patched, regression test.

Root cause (measured, then read):
- Repro `ParentReevaluationTests.siblingResizeKeepsContentIdentity` (hosted window, `OSPath.allCases`, the finder's tree
  `ZTronScrollView { StatefulContent; Color.blue.frame(height: model.tall ? 200 : 100) }`). On 27.0 forced, before the patch:
  the re-evaluation INSIDE the `withOSPath` scope kept one identity (ids 1, appears 1); the same re-evaluation OUTSIDE the
  scope (how the probe and most tests pump) gave ids 2, appears 2. Preferred: green both ways.
- So nothing in the layout host, `ContentSizeMeasure`/`ViewportObserver` or the named spaces (all choose their branch from
  `let` flags fixed on `ZTronScrollState` at creation, R6) is involved. The bodies that re-run on a parent re-evaluation
  read the process-wide switch instead: `PanGestureAdapter.body` computed `gated = !CatchObserver.usesSpatial` and
  `CatchArmingProbe(state: gated ? state : nil)` is an `if let … else` modifier around the whole content. Outside the
  scope 27.0 reports `.spatialEvents` available, the branch flips, SwiftUI rebuilds everything below it: new `@State`,
  `onAppear` again. On 17.5 `usesSpatial` is false on both paths (18+ only), so nothing flips; on 27.0 preferred it is
  always true.
- Same class, not yet biting: `PinchGestureAdapter` (`.magnifyGesture` read per body: the gesture inside `AnyGesture`
  flips), `CompletionObserver` (`.animationCompletion`, an `if/else` around the content, flips on 17+ when the transform
  host re-runs outside the scope), `PanCoordinator.init` (read at creation, could disagree with the state's flags).
- Scope of the defect: the demo app (`-ZTronForceAllFallbacks` installs the set once before any view) and real iOS 15/16
  (availability is constant) never flip, so users never saw it. It was a DEBUG/test-rig effect, BUT it meant forced-path
  unit tests that re-evaluated outside their scope silently ran the 18+ gesture path. Not SwiftUI behavior.

Changed:
- `State/ZTronScrollState.swift` — `usesSpatialEvents`, `usesMagnifyGesture`, `usesAnimationCompletion` fixed at init, next to the render flags.
- `Gesture/PanGestureAdapter.swift`, `Gesture/PinchGestureAdapter.swift`, `Gesture/PanCoordinator.swift` — read the state's flags; `CatchObserver.usesSpatial` removed (`Gesture/CatchObserver.swift`).
- `Render/ContentTransform.swift` — `CompletionObserver` reads `state.usesAnimationCompletion`.
- `Tests/ZTronScrollViewTests/ParentReevaluationTests.swift` — regression test (inside and outside the scope).
Decisions: every path choice that can sit in a body comes from a `let` on the state (R6 extended to gestures and the
completion observer); D10, D21, S4 untouched (no render-path change). The M6 registry's "one report per live reporter"
tolerance stays (cheap, still correct).
Open:
- `ProofUITests.testNoClockTicksAtRest` fails on the fresh `DBG-s1 iPhone 18 Pro` simulator, preferred AND forced
  (`clock.tick` 2 at rest, expected 0), identically at fd3d17a WITHOUT this patch, so it is not this change. Green in
  ORCH-s1 (5eca9a7, iPhone 18 Pro 897F9D8D). Unknown whether it is the fresh device or a regression from N-a
  (7f4d7d5..fd3d17a, not covered by NESTED-s1's UI re-run): re-run it on 897F9D8D at HEAD.
- `ZTronScrollState.unanimated` still reads `.keyPathTransaction` at call time (a function, not a branch; harmless).
Shared checkout note: other sessions began editing Sources/ (incl. `ZTronScrollState.swift`) during this session; this
work was verified in a detached scratch worktree (fd3d17a + patch, then 46725ad + patch) on a dedicated simulator
(`DBG-s1 iPhone 18 Pro`, 27.0, 7CAF736B-ACC3-488A-89CD-05E5500128C3; the default one was busy with another session's
run) and committed with only its own hunks.
Next: none for this item.
Tests: `ZTronScrollViewTests` 279/279 on 27.0 + 17.5 at fd3d17a + patch; 303/303 on 27.0 + 17.5 at 46725ad + patch
(the new test fails before the patch on 27.0 forced, outside-scope expectations only). Demo `ProofUITests` +
`ResizeUITests` on 27.0 (fd3d17a + patch): preferred 18/19, forced 18/19, the one failure = the pre-existing
`testNoClockTicksAtRest` above; `ResizeUITests` 13/13 both paths. One 27.0 unit run on the shared simulator died
mid-run (no assertion, host daemons crashed the same minute); re-run on the dedicated simulator green.
Usage: not measured (budget ~1–2 % weekly asked).
