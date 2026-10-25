# BTN-s2 handoff · 2026-10-25 · Opus 5.5 · default effort (Debugger: UIKit's release rule across an event-free pause)
Status: done (measured, rule inferred, recommendation written). No library change: the tracker change is a proposal for Fable (D16).

## How it was measured
- Demo `-ZTronScreen buttonDrag` (BTN-s1), native lane only: `BDNativeProbe` finds the `UIScrollView` behind SwiftUI's `ScrollView`
  (a view inside its content, superview chain), adds a target to its `panGestureRecognizer` (state, `velocity(in:)`, translation per
  callback; `isDecelerating` right after UIKit's own handler at `.ended`), a touch observer recognizer (every `UITouch`: phase,
  timestamp, location, coalesced count) and KVO on `contentOffset` (uptime-stamped). Readout `bd.native`; "Reset" puts the offset back,
  so one launch runs a whole sweep. `-ZTronBDWidth 6000`: flings never reach the trailing edge.
- `ButtonDragSweepUITests` (opt-in `TEST_RUNNER_ZS_BD_SWEEP=1`, no assertions): XCUI presets slow / default / fast × holds 0, 0.05,
  0.1, 0.25, 0.5, 1 s, −120 pt from the scroller's centre (finger on screen) or 66 pt in (end point 46 pt off screen); custom
  velocities 100–500 pt/s (threshold); 1500 / 4000 pt/s −300 pt drags (the calibration's medium / fast flings) × holds 0, 0.05, 0.25 s.
  Both lanes. 17.5 iPhone 15 Pro, 27.0 iPhone 18 Pro, 18.6 iPhone 16 Pro, all fresh private devices (`simctl create`, deleted).
- Release velocity of the native deceleration ("v0"): least-squares fit of the first 12 post-lift offsets to UIKit's decay
  (r = 0.998 / ms), cross-checked with the rest distance (`v0 ≈ (D + 5) / 0.4995`).
- Analysis scripts and the raw `BDS` lines: side-session notes folder `…/local_596f62b3-…/btn-s2/` (`analyze.py`, `model.py`,
  `score.py`; `score.py` replays the native lane's touch timelines through candidate tracker rules).

## UIKit's rule (identical on 17.5, 18.6 and 27.0)
1. **The lift never enters.** `panGestureRecognizer.velocity(in:)` at `.ended` equals its last `.changed` value in all 230 native
   drags, and the rest offset is the same for holds 0…1 s and for drags past the screen edge (no touch moves for 0.1–1.2 s): 17.5
   within 0.5 % of the fling, 27.0 within 3 %; it differs only where XCUI delivered a different move stream, and then the pan
   velocity differs with it (18.6 fast preset: 9 moves, `.ended` 682 → 491 pt; 10 moves, 564 → 445). Neither the ended touch's
   timestamp nor the gap matters. XCUI delivers no touch during a hold; preset drags lift in the same frame as the last move,
   custom-velocity drags one frame (16–17 ms) later.
2. **Gate at 250 pt/s.** `UIScrollView` decelerates iff `|velocity(in:)|` at `.ended` ≥ 250 pt/s: rest at 216, 224, 228, 248;
   fling at 250 (18.6), 252 (27.0), 256, 264, 276; 0 of 230 drags misclassified, the three OSes agree. Below it the content rests
   where the finger left it (`isDecelerating` false). BTN-s1's "no fling after a slow drag held 0.3 s" is this gate, not the hold:
   the same slow drag with hold 0 does not fling either (XCUI's slow preset ends at 144–187 pt/s).
3. **Start velocity ≈ the mean of the pan's last three `velocity(in:)` samples** (±3 % on 9 profiles, 270–4200 pt/s), above the
   `.ended` value on eased-out ends (fast preset: v0 691 vs `.ended` 552). The pan velocity itself ≈ the finger's displacement over its
   last 50 ms of moves (±2 % on every on-screen drag; drags clamped at the screen edge differ).

## Native vs ZTron (rest offset x, pt; native: the range over all holds, ZTron: per hold)
Presets, −120 pt (ZTron: hold 0 / 0.05 / ≥ 0.1 s; pan `.ended` velocity in brackets):
| drag | 17.5 native | 17.5 ZTron | 27.0 native | 27.0 ZTron | 18.6 native | 18.6 ZTron |
|---|---|---|---|---|---|---|
| centre slow (152 / 148) | 110 | 201 / 110 / 110 | 110 | 201 / 110 / 110 | 110 | 202 / 110 / 110 |
| centre default (296 / 308) | 299–300 | 317 / 257 / 110 | 302–305 | 296 / 257 / 110 | 302–322 | 316 / 257 / 110 |
| centre fast (552 / 554–596) | 448 | 445 / 384 / 110 | 445–452 | 444 / 382 / 110 | 445–491 | 463 / 329 / 110 |
| edge slow (276) | 198 | 64 (every hold) | 198–201 | 64 | 195–201 | 64 |
| edge default (500) | 337 | 64 | 337 | 64 | 337–341 | 64 |
| edge fast (796) | 480 | 64 | 459–485 | 64 | 462–481 | 64 |

Calibration flings, −300 pt from 350 pt in (ZTron: hold 0 / 0.05 / 0.25 s):
| drag | 17.5 native | 17.5 ZTron | 27.0 native | 27.0 ZTron | 18.6 native | 18.6 ZTron |
|---|---|---|---|---|---|---|
| 1500 pt/s (`.ended` 1228) | 979 | 954 / 290 / 290 | 979–980 | 987 / 290 / 290 | 967–979 | 946 / 290 / 290 |
| 4000 pt/s (3452) | 2367 | 2132 / 1953 / 290 | 2315–2367 | 2135 / 1953 / 290 | 2367–2459 | 1870 / 1953 / 290 |

Gate (custom XCUI velocity, centre, hold 0; 17.5 / 27.0 identical within 3 pt): native rests at 110 for 100–350 pt/s (`.ended`
56–216), ZTron drifts 137 / 155 / 180 / 225 / 238 for 100 / 150 / 200 / 300 / 350 pt/s (releases 64–265 pt/s); 400 pt/s: native 272,
ZTron 285; 500: 299 vs 317.

So ZTron differs in three ways: (G1) an event-free pause > 64 ms zeroes the release (SPEC S6 rest rule), and a shorter one shrinks the
lift-anchored 100 ms window (hold 0.05: −14 % at the fast preset, −18 % at 4000 pt/s; BTN-s1 open 2 is this); (G2) no gate: releases
between 20 pt/s (`negligibleReleaseVelocity`) and 250 pt/s drift up to 128 pt where UIKit stops; (G3) the 100 ms least-squares slope is
−11 … +10 % off UIKit's start velocity on these short XCUI drags on 17.5 / 27.0, −24 % on 18.6's 4000 pt/s drag (its DragGesture
stream: 3173 pt/s vs UIKit's ≈ 4200), within 1–2 % on the 27.0 calibration's longer flings.

## Recommendation (proposal for Fable, D16; not landed)
Revise D49: UIKit has no rest rule; its "rest" is the 250 pt/s gate. Two tracker changes, estimator unchanged:
- **P1 (pause):** `VelocityTracker.velocity(at:)` evaluates the fit at `min(lift, newest.time + 1/60 s)` and drops the `restTimeout`
  zeroing. A pause longer than one frame no longer changes the release; a lift within a frame of the last move keeps today's
  lift-anchored window, so every calibrated fling keeps its number (run1 / run3 / run4 replayed: fast, medium, edge Δ 0.00 %; their lift
  gaps 0.3–17.5 ms). A 20 ms clamp is worse (−9 % on paused fast drags: it drops 20 ms of samples). Cleaner alternative: evaluate at
  the newest sample (= `lastMotionVelocity`, which the spring-back already uses): one velocity for both paths, but the calibration's
  medium and edge flings rise from 1340 to 1410 pt/s (+5 %; native 1350), so it needs a re-calibration.
- **P2 (gate):** release velocity 0 unless the finger's velocity over the last 50 ms of samples before the newest (position
  interpolated at `newest − 50 ms`) reaches `minimumDecelerationVelocity = 250` pt/s per axis. It replaces the `restDistance` check
  (a < 1 pt / 64 ms rest is ≤ 16 pt/s). Natural releases only: target releases keep `negligibleReleaseVelocity`, the rubber-band
  spring-back keeps `lastMotionVelocity` (the calibration's bounce-back seeds are 103–958 pt/s after 0.3 s holds, not gated).
- **Not now (G3):** UIKit's start velocity (mean of three 50 ms velocities) scores better on these drags (mean |Δd| 16 pt vs 37) but
  moves every calibrated fling; only after a CalibrateUITests re-run on ZTron's own sample stream (DragGesture samples differ from
  UITouch: 1339 vs 1411 pt/s on the same 1500 pt/s drag, 17.5; 3173 vs 3698 at 4000 pt/s on 18.6).

Effect on the 27.0 calibration (`docs/design/PHYSICS-calibration.md`, the stored run4 finger samples replayed through P1 + P2): fast
3469, medium 1340, edge 1340 pt/s unchanged; slow (300 pt/s, hold 0.5 s) 50 ms velocity 173 < 250 → 0 = native (today 0 by the rest
rule); the rubber-band pulls (`top*`, `short-*`, held 0.3 s) release out of bounds → the bounce-back seed is unchanged, only
`willEndDragging` now reports 257–892 pt/s instead of 0 (UIKit's pan reports the same kind of value); catch unchanged. No calibrated
motion moves; re-run CalibrateUITests after landing. On this sweep (the native lane's 230 UITouch timelines replayed through the
rules, a fling = > 5 pt): wrong fling/rest decisions 144 → 14 (all 14: drags clamped at the screen edge within 30 pt/s of the gate,
whose pan velocity the 50 ms estimate under-reads), mean fling-distance error 119 → 37 pt where both fling.

Device: a resting finger either reports small moves (then the 50 ms velocity is under the gate on both) or none (then UIKit flings
after the lift, rule 1, and P1 + P2 do the same): parity either way. SPEC S6 "≈ 0 if the finger rested for ~50–80 ms" needs the
amendment when P1/P2 land; `ButtonDragUITests.testDragRunningOffTheScreenEdgeRestsWhereNativeFlings` then goes red by design (update it
and the parity row).

## Changed
- Demo: `ButtonDragScreen.swift`: `BDNativeProbe` + `BDTouchObserver` + `BDScrollViewFinder` (UIKit, native lane only), readout
  `bd.native`, "Reset", `-ZTronBDWidth`, ZTron's `willEndDragging` velocity as `vel=` in `bd.info`.
- UI tests: `ButtonDragSweepUITests` (6 opt-in sweeps; `TEST_RUNNER_ZS_BD_SPEEDS` / `_HOLDS` / `_STARTS` / `_REPEATS` narrow them).
- Docs: this handoff, parity-matrix row (rule + the two gaps), Orchestration D49 revision + open item 11 + log row, STATE row.
  Library, physics package and ScrollArbitration unchanged.

## Open
1. P1 + P2 for Fable (D16), then SPEC S6 amendment, `ButtonDragUITests` edge test, CalibrateUITests re-run on 27.0.
2. Gate on two axes: per axis or on the vector? Not measured (all drags horizontal).
3. G3: UIKit's start-velocity estimator on ZTron's own sample stream (DragGesture / SpatialEvent), with the calibration fixtures.
4. Device check (ProMotion: 120 Hz samples halve the 50 ms window's sample count; does a resting finger report moves?).
5. What `willEndDragging` / `ScrollTargetBehaviorContext.velocity` report for a gated release on native (not observable from the pan).

## Tests
- Sweeps (opt-in, numbers above; per OS and lane): 17.5 and 27.0 presets 36 + threshold 44 + calibration flings 6 drags per lane,
  fine threshold 8 (native); 18.6 presets + calibration flings. 230 native + 214 ZTron drags; every lane `** TEST SUCCEEDED **`, each
  `Test Case` passed, `BDS` line counts checked. Host load 7–320.
- `scripts/test-demo-ui.sh … -only-testing:ZTronScrollViewDemoUITests/ButtonDragUITests` on the private 17.5 device after the demo
  change: 3/3, BTN-s1's numbers unchanged (Button 384 = background 384, edge 64 vs native 474, native 448 = 448).
Usage: not measured.
