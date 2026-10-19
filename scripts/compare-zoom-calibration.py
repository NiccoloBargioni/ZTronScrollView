#!/usr/bin/env python3
"""Native zoom-animation calibration report (docs/design/PHYSICS-calibration.md, "Programmatic zoom").

usage: scripts/compare-zoom-calibration.py <dir-with-json> [--fixture]

Reads `native-zoom-<case>.json` written by the spike's `-zoomCal` screen (ZoomCalibrationViewController.swift):
samples = [[t, modelScale, presentationScale, ox, oy, pox, poy], ...] (t = CACurrentMediaTime), events = [[t, name, scale]].
For every case it prints the animation window seen by the presentation layer, whether the model scale jumps to the end
at once, the delegate events, and the least-squares fit of the normalized progress f(t) against candidate curves:
critically damped spring (fit omega), UIKit timing curves (ease-in-out / ease-out / ease-in / linear) with a fitted
duration, and a cubic ease-in-out with fitted duration. `--fixture` prints the progress samples as a Swift literal.
No third-party modules (plain python3).
"""
import glob
import json
import math
import os
import sys

FRAME = 1 / 60


def load(directory):
    runs = {}
    for path in sorted(glob.glob(os.path.join(directory, "native-zoom-*.json"))):
        with open(path) as f:
            d = json.load(f)
        runs[d["gesture"]] = d
    return runs


def window(samples, col, eps=1e-4):
    """(i_start, i_end): first index whose value differs from the initial one, last index whose value still changes."""
    v0 = samples[0][col]
    start = None
    for i, s in enumerate(samples):
        if abs(s[col] - v0) > eps:
            start = i
            break
    if start is None:
        return None
    end = start
    for i in range(start + 1, len(samples)):
        if abs(samples[i][col] - samples[i - 1][col]) > eps:
            end = i
    return start, end


def bezier_y_at_x(x, p1x, p1y, p2x, p2y):
    """Cubic bezier (0,0) (p1) (p2) (1,1): y for a given x (Newton on the parameter)."""
    u = x
    for _ in range(12):
        bx = 3 * (1 - u) ** 2 * u * p1x + 3 * (1 - u) * u ** 2 * p2x + u ** 3
        dx = 3 * (1 - u) ** 2 * p1x + 6 * (1 - u) * u * (p2x - p1x) + 3 * u ** 2 * (1 - p2x)
        if abs(dx) < 1e-9:
            break
        u -= (bx - x) / dx
        u = min(1, max(0, u))
    return 3 * (1 - u) ** 2 * u * p1y + 3 * (1 - u) * u ** 2 * p2y + u ** 3


CURVES = {
    "easeInOut(0.42,0,0.58,1)": (0.42, 0, 0.58, 1),
    "easeOut(0,0,0.58,1)": (0, 0, 0.58, 1),
    "easeIn(0.42,0,1,1)": (0.42, 0, 1, 1),
    "linear": None,
}


def rms(pairs, fn):
    return math.sqrt(sum((fn(t) - f) ** 2 for t, f in pairs) / len(pairs))


def fit_spring(pairs):
    best = None
    w = 4.0
    while w <= 60:
        fn = lambda t, w=w: 1 - (1 + w * t) * math.exp(-w * t)
        e = rms(pairs, fn)
        if best is None or e < best[1]:
            best = (w, e)
        w += 0.1
    return best


def fit_timed(pairs, bez):
    best = None
    d = 0.08
    while d <= 2.0:
        if bez is None:
            fn = lambda t, d=d: min(1, t / d)
        else:
            fn = lambda t, d=d, b=bez: bezier_y_at_x(min(1, t / d), *b)
        e = rms(pairs, fn)
        if best is None or e < best[1]:
            best = (d, e)
        d += 0.005
    return best


def report(name, d, fixture):
    s = d["samples"]
    t0 = s[0][0]
    w = window(s, 2)
    print(f"\n== {name}  (os {d.get('os')}, samples {len(s)}, events {len(d.get('events', []))})")
    if w is None:
        print("   presentation scale never changed")
        return
    i0, i1 = w
    z0, z1 = s[0][2], s[i1][2]
    t_start, t_end = s[i0][0] - t0, s[i1][0] - t0
    # The frame before the first change is the animation start (the change is visible one frame later).
    t_anim0 = s[i0 - 1][0] - t0 if i0 > 0 else t_start
    print(f"   scale {z0:.4f} -> {z1:.4f}; first change at +{t_start*1000:.0f} ms, last change at +{t_end*1000:.0f} ms"
          f" => visible duration {(t_end - t_anim0):.3f} s over {i1 - i0 + 1} frames")
    mw = window(s, 1)
    if mw is None:
        print("   model zoomScale never changed")
    else:
        print(f"   model zoomScale: first change +{(s[mw[0]][0]-t0)*1000:.0f} ms, last change +{(s[mw[1]][0]-t0)*1000:.0f} ms,"
              f" value after first change {s[mw[0]][1]:.4f} (jump to the end at once: {abs(s[mw[0]][1]-z1) < 1e-3})")
    ev = d.get("events", [])
    kinds = {}
    for e in ev:
        kinds[e[1]] = kinds.get(e[1], 0) + 1
    if ev:
        print(f"   events: {kinds}; first {ev[0][1]} at +{(ev[0][0]-t0)*1000:.0f} ms, last {ev[-1][1]} at +{(ev[-1][0]-t0)*1000:.0f} ms")
    ox0, oy0, ox1, oy1 = s[0][5], s[0][6], s[i1][5], s[i1][6]
    print(f"   presentation offset ({ox0:.1f}, {oy0:.1f}) -> ({ox1:.1f}, {oy1:.1f})")
    pairs = [((s[i][0] - t0) - t_anim0, (s[i][2] - z0) / (z1 - z0)) for i in range(i0, i1 + 1)]
    print("   progress per frame (t s, f):", " ".join(f"({t:.3f},{f:.3f})" for t, f in pairs[: 12]), "..." if len(pairs) > 12 else "")
    print("   fits (rms of f):")
    wbest = fit_spring(pairs)
    print(f"     critical spring       omega={wbest[0]:.1f}  (stiffness {wbest[0]**2:.0f})   rms={wbest[1]:.4f}")
    for cname, bez in CURVES.items():
        dbest = fit_timed(pairs, bez)
        print(f"     {cname:24s} duration={dbest[0]:.3f} s   rms={dbest[1]:.4f}")
    if fixture:
        lit = ", ".join(f"({t:.4f}, {f:.4f})" for t, f in pairs)
        print(f"   fixture: static let zoom_{name.replace('-', '_')}: [(TimeInterval, CGFloat)] = [{lit}]")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    runs = load(sys.argv[1])
    fixture = "--fixture" in sys.argv
    if not runs:
        print("no native-zoom-*.json in", sys.argv[1])
        sys.exit(1)
    for name in sorted(runs):
        report(name, runs[name], fixture)


if __name__ == "__main__":
    main()
