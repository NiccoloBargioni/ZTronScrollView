#!/usr/bin/env python3
"""Physics calibration report (docs/design/PHYSICS-calibration.md).

usage: scripts/compare-calibration.py <dir-with-json> [--md]

Reads the trajectories written by the demo's calibrate screen (`<variant>-<gesture>.json`, see CalibrateScreen.swift:
samples = [[t, y, phase], ...] on the device's uptime clock, fingers = [[t, fingerY, up], ...]) and prints per gesture,
for every variant found (native, ztron, native-short, ztron-short):

  tracking   ratio of content travel to finger travel while in bounds, and the lag (ms, frames @ 60 Hz)
  release    velocity at lift (pt/s) from the first 60 ms of the deceleration
  decay      distance (pt), duration (s) and the fitted deceleration rate r per ms of the in-bounds decay
  rubber     max displacement past the edge vs the finger overscroll, and the implied coefficient c
  bounce     bounce-back duration (s) and overshoot (pt) after the finger left the content out of bounds
  edge       overshoot (pt) and settle time (s) of a fling into an edge
  catch      stop latency (ms) from the catching touch-down to the last offset change

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
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        with open(path) as f:
            d = json.load(f)
        runs.setdefault(d["gesture"], {})[d["variant"]] = d
    return runs


def finger_segments(d):
    """(down_time, up_time) pairs from the finger log."""
    segs, down = [], None
    for t, _, up in d["fingers"]:
        if up:
            if down is not None:
                segs.append((down, t))
            down = None
        elif down is None:
            down = t
    if down is not None:
        segs.append((down, math.inf))
    return segs


def finger_at(d, t):
    fs = d["fingers"]
    prev = None
    for s in fs:
        if s[0] > t:
            break
        prev = s
    return prev[1] if prev else None


def y_at(samples, t):
    """Sample-and-hold offset at time t."""
    y = samples[0][1]
    for s in samples:
        if s[0] > t:
            break
        y = s[1]
    return y


def last_change(samples, after):
    """Time and value of the last offset change after `after`."""
    last = None
    for s in samples:
        if s[0] >= after:
            last = s
    return last


def fit_decay(points):
    """Least-squares fit of x(t) = x0 + v0 (e^{kt} - 1)/k to [(t, x)], t relative. Returns (v0, k, rms)."""
    if len(points) < 4:
        return None
    best = None
    for r in [0.990 + i * 0.0001 for i in range(0, 100)]:
        k = 1000 * math.log(r)
        # Linear LSQ in (x0, v0): x = x0 + v0 * g(t), g = (e^{kt}-1)/k
        gs = [(math.expm1(k * t)) / k for t, _ in points]
        xs = [x for _, x in points]
        n = len(points)
        gm, xm = sum(gs) / n, sum(xs) / n
        den = sum((g - gm) ** 2 for g in gs)
        if den < 1e-12:
            continue
        v0 = sum((g - gm) * (x - xm) for g, x in zip(gs, xs)) / den
        x0 = xm - v0 * gm
        rms = math.sqrt(sum((x0 + v0 * g - x) ** 2 for g, x in zip(gs, xs)) / n)
        if best is None or rms < best[2]:
            best = (v0, r, rms)
    return best


def analyze(d):
    s = d["samples"]
    out = {}
    if not s:
        return out
    segs = finger_segments(d)
    if not segs:
        return out
    down, up = segs[0]
    maxy = d["maxY"]
    in_bounds = lambda y: -0.5 <= y <= maxy + 0.5

    # --- tracking: content vs finger while the finger is down and the content is in bounds.
    f0 = finger_at(d, down)
    drag = [(t, y) for t, y, _ in s if down <= t <= up]
    if drag and f0 is not None:
        ys = [y for _, y in drag]
        y0 = y_at(s, down)
        # travel ratio over the in-bounds part (take the last in-bounds drag sample)
        inb = [(t, y) for t, y in drag if in_bounds(y)]
        if inb:
            t1, y1 = inb[-1]
            f1 = finger_at(d, t1)
            if f1 is not None and abs(f1 - f0) > 20:
                out["track_ratio"] = (y1 - y0) / -(f1 - f0)
        # lag: shift the finger curve by L and find the L with the least error against the content.
        fin = [(t, -(fy - f0) + y0) for t, fy, upf in d["fingers"] if down <= t <= up and not upf]
        if len(fin) > 5 and len(inb) > 5:
            best = None
            for lag_ms in range(0, 120, 2):
                lag = lag_ms / 1000
                err, n = 0.0, 0
                for t, y in inb:
                    # finger position at t - lag (sample-and-hold)
                    fy = None
                    for ft, fv in fin:
                        if ft > t - lag:
                            break
                        fy = fv
                    if fy is None:
                        continue
                    err += (fy - y) ** 2
                    n += 1
                if n:
                    e = math.sqrt(err / n)
                    if best is None or e < best[1]:
                        best = (lag_ms, e)
            if best:
                out["lag_ms"] = best[0]
                out["lag_frames"] = best[0] / 1000 / FRAME
                out["lag_rms"] = best[1]
        out["drag_max_over"] = min(0, min(ys)) if min(ys) < 0 else max(0, max(ys) - maxy)

    # --- after lift
    if up is not math.inf:
        lift_y = y_at(s, up)
        after = [(t - up, y) for t, y, _ in s if t > up]
        if after:
            end_t, end_y = after[-1]
            out["post_distance"] = end_y - lift_y
            out["post_duration"] = end_t
            # release velocity: slope over the first 60 ms after lift
            head = [(t, y) for t, y in after if t <= 0.06]
            if len(head) >= 2:
                (ta, ya), (tb, yb) = head[0], head[-1]
                if tb > ta:
                    out["release_v"] = (yb - ya) / (tb - ta)
            # decay fit on the in-bounds part
            inb = [(t, y) for t, y in after if in_bounds(y)]
            if len(inb) >= 6 and abs(inb[-1][1] - lift_y) > 5:
                fit = fit_decay(inb)
                if fit:
                    out["decay_v0"], out["decay_r"], out["decay_rms"] = fit
                    out["decay_distance"] = inb[-1][1] - lift_y
                    out["decay_duration"] = inb[-1][0]
            # rubber band / bounce back when released out of bounds
            if not in_bounds(lift_y):
                edge = 0 if lift_y < 0 else maxy
                over = lift_y - edge
                fin_over = None
                f_up = finger_at(d, up)
                # finger travel past the point where the content reached the edge
                for t, y, _ in s:
                    if t <= up and not in_bounds(y):
                        fy = finger_at(d, t)
                        if fy is not None and f_up is not None:
                            fin_over = -(f_up - fy)
                        break
                out["rb_displacement"] = over
                if fin_over and abs(fin_over) > 1:
                    out["rb_overscroll"] = fin_over
                    out["rb_ratio"] = over / fin_over
                    vp = d["viewport"]
                    f = abs(over)
                    x = abs(fin_over)
                    if f < vp:
                        out["rb_c"] = f * vp / (x * (vp - f))
                back = [(t, y) for t, y in after]
                # time to come back within 1 pt of the edge
                tb = None
                for t, y in back:
                    if abs(y - edge) <= 1:
                        tb = t
                        break
                out["bounce_duration"] = tb if tb is not None else end_t
                sign = -1 if over < 0 else 1
                out["bounce_overshoot"] = max(0, max(sign * (edge - y) for _, y in back))
            else:
                # edge hit during the decay?
                ov = [(t, y) for t, y in after if not in_bounds(y)]
                if ov:
                    edge = 0 if ov[0][1] < 0 else maxy
                    out["edge_overshoot"] = max(abs(y - edge) for _, y in ov)
                    out["edge_cross_t"] = ov[0][0]
                    out["edge_settle"] = end_t - ov[0][0]
        # catch: second finger segment
        if len(segs) >= 2:
            cdown, cup = segs[1]
            lc = last_change(s, cdown)
            before = [y for t, y, _ in s if t <= cdown]
            v_before = None
            pre = [(t, y) for t, y, _ in s if cdown - 0.05 <= t <= cdown]
            if len(pre) >= 2:
                v_before = (pre[-1][1] - pre[0][1]) / (pre[-1][0] - pre[0][0])
            moved_after = [(t, y) for t, y, _ in s if cdown < t <= cup + 0.05]
            if moved_after:
                out["catch_latency_ms"] = (moved_after[-1][0] - cdown) * 1000
                out["catch_slide"] = moved_after[-1][1] - (before[-1] if before else 0)
            else:
                out["catch_latency_ms"] = 0
                out["catch_slide"] = 0
            out["catch_v_before"] = v_before
    out["n"] = len(s)
    return out


KEYS = [
    ("track_ratio", "tracking ratio", "{:.3f}"),
    ("lag_ms", "tracking lag ms", "{:.0f}"),
    ("lag_frames", "lag frames", "{:.1f}"),
    ("release_v", "release v pt/s", "{:.0f}"),
    ("decay_v0", "fit v0 pt/s", "{:.0f}"),
    ("decay_r", "fit r /ms", "{:.4f}"),
    ("decay_rms", "fit rms pt", "{:.2f}"),
    ("decay_distance", "decay dist pt", "{:.1f}"),
    ("decay_duration", "decay dur s", "{:.2f}"),
    ("post_distance", "post-lift dist", "{:.1f}"),
    ("post_duration", "post-lift dur s", "{:.2f}"),
    ("rb_displacement", "rb displacement", "{:.1f}"),
    ("rb_overscroll", "rb overscroll", "{:.1f}"),
    ("rb_ratio", "rb ratio", "{:.3f}"),
    ("rb_c", "rb implied c", "{:.3f}"),
    ("bounce_duration", "bounce-back s", "{:.2f}"),
    ("bounce_overshoot", "bounce overshoot", "{:.1f}"),
    ("edge_overshoot", "edge overshoot", "{:.1f}"),
    ("edge_settle", "edge settle s", "{:.2f}"),
    ("catch_latency_ms", "catch stop ms", "{:.0f}"),
    ("catch_slide", "catch slide pt", "{:.1f}"),
    ("catch_v_before", "v before catch", "{:.0f}"),
    ("n", "samples", "{}"),
]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    md = "--md" in sys.argv
    runs = load(sys.argv[1])
    for gesture, variants in runs.items():
        names = sorted(variants)
        results = {n: analyze(variants[n]) for n in names}
        if md:
            print(f"\n### {gesture}\n")
            print("| metric | " + " | ".join(names) + " |")
            print("|---|" + "---|" * len(names))
        else:
            print(f"\n== {gesture}  ({', '.join(names)})")
        for key, label, fmt in KEYS:
            vals = []
            for n in names:
                v = results[n].get(key)
                vals.append(fmt.format(v) if v is not None else "-")
            if all(v == "-" for v in vals):
                continue
            if md:
                print(f"| {label} | " + " | ".join(vals) + " |")
            else:
                print(f"  {label:18s} " + "  ".join(f"{v:>12s}" for v in vals))


if __name__ == "__main__":
    main()
