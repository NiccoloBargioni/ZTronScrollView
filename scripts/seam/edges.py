#!/usr/bin/env python3
"""i28 edge meter: black text on the seam lab's pure red header, from lossless PNG screenshots.

For every PNG: the text's bounding box (pixels darker than R 128 on the red/black axis inside the red header), and the
10-90 % edge distance of every red->black transition along rows (horizontal edges of vertical strokes) and columns, by
linear interpolation of the red channel between the last pure-red (>= 230) and the first black (<= 25) pixel. "straight"
keeps only transitions whose crossing moves < 0.35 px between neighbouring scanlines (stems, not curves).
usage: edges.py a.png [b.png ...] [--ref a.png] [--threshold 1.10] [--box-tolerance 2]
  (ratios against --ref, default the first). Threshold mode (M8b-s8 s6, D76 `.keepTextSize` gate): every h / v "all"
  and "stem" ratio of every PNG must lie in [1/t, t] and its text box within --box-tolerance px of the reference's;
  prints PASS / FAIL per PNG and exits 1 on any FAIL.
"""
import sys, json
import numpy as np
from PIL import Image

HI, LO = 230.0, 25.0


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float64)


def text_box(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    axis = (g < 70) & (b < 70)              # on the red <-> black axis
    red = axis & (r > 200)
    rows = np.where(red.mean(axis=1) > 0.25)[0]
    if len(rows) == 0:
        return None
    # the largest run of red rows = the header
    runs, start = [], rows[0]
    for x, y in zip(rows, rows[1:]):
        if y != x + 1:
            runs.append((start, x)); start = y
    runs.append((start, rows[-1]))
    top, bot = max(runs, key=lambda t: t[1] - t[0])
    dark = axis & (r < 128)
    dark[:top] = False; dark[bot + 1:] = False
    ys, xs = np.where(dark)
    if len(ys) == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())), (int(top), int(bot))


def crossings(v):
    """[(pos10, pos90, width)] for each monotone pure-red <-> black transition in the 1-D red channel v."""
    out = []
    n = len(v)
    i = 0
    last_ext, last_kind = None, None
    while i < n:
        kind = "h" if v[i] >= HI else ("l" if v[i] <= LO else None)
        if kind:
            if last_kind and kind != last_kind and i - last_ext <= 10:
                seg = v[last_ext:i + 1]
                mono = np.all(np.diff(seg) <= 0) if last_kind == "h" else np.all(np.diff(seg) >= 0)
                if mono:
                    def cross(level):
                        for k in range(len(seg) - 1):
                            a, b = seg[k], seg[k + 1]
                            if (a - level) * (b - level) <= 0 and a != b:
                                return last_ext + k + (a - level) / (a - b)
                        return None
                    c1, c2 = cross(HI), cross(LO)
                    if c1 is not None and c2 is not None:
                        out.append(((c1 + c2) / 2, abs(c2 - c1), last_kind + kind))
            last_ext, last_kind = i, kind
        i += 1
    return out


def measure(p):
    a = load(p)
    tb = text_box(a)
    if tb is None:
        return {"file": p, "error": "no text"}
    (x0, y0, x1, y1), (top, bot) = tb
    x0, y0, x1, y1 = max(0, x0 - 3), max(top, y0 - 3), min(a.shape[1] - 1, x1 + 3), min(bot, y1 + 3)
    r = a[y0:y1 + 1, x0:x1 + 1, 0]
    g = a[y0:y1 + 1, x0:x1 + 1, 1]
    if (g > 70).mean() > 0.02:
        return {"file": p, "error": "non-axis pixels in the text box (%.3f)" % (g > 70).mean()}
    res = {}
    for name, img in (("h", r), ("v", r.T)):
        per_line = [crossings(img[k]) for k in range(img.shape[0])]
        allw = [c[1] for line in per_line for c in line]
        straight = []
        for k in range(1, img.shape[0] - 1):
            for pos, w, kind in per_line[k]:
                ok = any(abs(pos - q) < 0.35 and kk == kind for q, _, kk in per_line[k - 1]) and \
                     any(abs(pos - q) < 0.35 and kk == kind for q, _, kk in per_line[k + 1])
                if ok:
                    straight.append(w)
        res[name] = {"n": len(allw), "mean": float(np.mean(allw)) if allw else None,
                     "ns": len(straight), "smean": float(np.mean(straight)) if straight else None}
    # gradient-energy blur measure: sum |dr| / max |dr| per transition, robust to slope
    return {"file": p, "box": [x0, y0, x1 - x0 + 1, y1 - y0 + 1], "header": [top, bot], **res}


def main():
    args = sys.argv[1:]
    ref = None
    if "--ref" in args:
        i = args.index("--ref"); ref = args[i + 1]; del args[i:i + 2]
    thr = None
    if "--threshold" in args:
        i = args.index("--threshold"); thr = float(args[i + 1]); del args[i:i + 2]
    tol = 2
    if "--box-tolerance" in args:
        i = args.index("--box-tolerance"); tol = int(args[i + 1]); del args[i:i + 2]
    if "--json" in args:
        args.remove("--json")
    rows = [measure(p) for p in args]
    base = measure(ref) if ref else (rows[0] if rows else None)
    for m in rows:
        if "error" in m:
            print("%-60s %s" % (m["file"].split("/")[-1], m["error"])); continue
        bw = m["box"][2] / base["box"][2] if base and "box" in base else float("nan")
        def rat(k, f):
            return m[k][f] / base[k][f] if base and base.get(k, {}).get(f) and m[k][f] else float("nan")
        print("%-46s box %4dx%-4d scale %.3f | h all %.3f (n %4d, x%.2f) stem %.3f (n %4d, x%.2f) | v all %.3f (x%.2f) stem %.3f (n %4d, x%.2f)" % (
            m["file"].split("/")[-1][:46], m["box"][2], m["box"][3], bw,
            m["h"]["mean"] or 0, m["h"]["n"], rat("h", "mean"), m["h"]["smean"] or 0, m["h"]["ns"], rat("h", "smean"),
            m["v"]["mean"] or 0, rat("v", "mean"), m["v"]["smean"] or 0, m["v"]["ns"], rat("v", "smean")))
    if "--json" in sys.argv:
        print(json.dumps(rows))
    if thr is not None:
        bad = 0
        for m in rows:
            name = m["file"].split("/")[-1]
            if "error" in m or not base or "box" not in base:
                print("FAIL %s %s" % (name, m.get("error", "no reference"))); bad += 1; continue
            ratios = []
            for k in ("h", "v"):
                for f in ("mean", "smean"):
                    if base[k][f] and m[k][f]:
                        ratios.append(m[k][f] / base[k][f])
            worst = max([max(r, 1 / r) for r in ratios] or [float("inf")])
            dbox = max(abs(m["box"][2] - base["box"][2]), abs(m["box"][3] - base["box"][3]))
            ok = worst <= thr and dbox <= tol
            bad += 0 if ok else 1
            print("%s %s worst ratio %.3f (<= %.2f) box %dx%d vs %dx%d (d %d <= %d)" % (
                "PASS" if ok else "FAIL", name, worst, thr, m["box"][2], m["box"][3], base["box"][2], base["box"][3], dbox, tol))
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
