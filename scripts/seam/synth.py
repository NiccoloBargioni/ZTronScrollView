#!/usr/bin/env python3
"""Seam lab analyzer check: a synthetic recording with known geometry, and the comparison of analyze.py's frames.csv
against it.

usage: python3 -I scripts/seam/synth.py make <out-dir> [tilt]  writes rec.mov (h264 yuv420p, 60 fps), truth.csv,
                                                                 meta.json
       python3 -I scripts/seam/synth.py check <out-dir>         compares <out-dir>/frames.csv (analyze.py) with truth

The scene is the seam lab's in window points (scale 3, a 402 x 874 pt display): a blue window with rounded corners
(black outside), the content (green 80 pt, then 40 rows yellow / magenta 60 pt) under a red header. The window is
rotated about the display centre by known angles (partial clipping by the display mid-rotation), the header and the
content are moved to known gaps / overlaps (0, 20, 90, 120 pt and ramps between them, 20 pt per frame at most) and
lateral offsets. Rendered with 3 x 3 supersampling, so edges are anti-aliased, then h264-encoded like the recorder.
The tilt scene turns the header alone by known small angles (0.4 .. 2.5 deg) against the content: frames past 1 deg
must be rejected (band = reject), the others measured (the seam at the header's centre).
"""
import csv
import json
import math
import os
import subprocess
import sys

import numpy as np

W_PT, H_PT, SCALE = 402.0, 874.0, 3
W, H = int(W_PT * SCALE), int(H_PT * SCALE)
RADIUS = 55.0
TOP0, HDR = 62.0, 226.0
COLORS = {"K": (0, 0, 0), "B": (0, 0, 255), "R": (255, 0, 0), "G": (0, 255, 0), "Y": (255, 255, 0),
          "M": (255, 0, 255)}


def script(scene="main"):
    """The frame list: dicts with the window rotation, window size, header and content geometry (points)."""
    out = []

    def add(n=1, **kw):
        base = {"angle": 0.0, "ww": W_PT, "wh": H_PT, "top0": TOP0, "hdr": HDR, "hx0": 0.0, "hx1": W_PT,
                "cx0": 0.0, "cx1": W_PT, "seam": 0.0, "tilt": 0.0}
        base.update(kw)
        for _ in range(n):
            out.append(dict(base))

    def ramp(key, a, b, step, **kw):
        k = max(1, int(math.ceil(abs(b - a) / step)))
        for j in range(1, k + 1):
            add(**{**kw, key: a + (b - a) * j / k})

    if scene == "tilt":
        mid = {"hx0": 40.0, "hx1": 362.0, "cx0": 20.0, "cx1": 382.0, "seam": 20.0}
        add(4, **mid)
        for tilt, ang in ((0.4, 0.0), (0.8, 0.0), (1.5, 0.0), (2.5, 0.0), (0.0, 0.0), (0.6, 30.0), (1.6, 30.0),
                          (-2.0, 30.0), (0.0, 30.0)):
            add(2, tilt=tilt, angle=ang, **mid)
        for f in out:
            f["ctop"] = f["top0"] + f["hdr"] + f["seam"]
        return out
    narrow = {"hx0": 40.0, "hx1": 362.0, "cx0": 20.0, "cx1": 382.0}   # header 20 pt inside: the green row shows beside it
    wide = {"hx0": 10.0, "hx1": 392.0, "cx0": 20.0, "cx1": 382.0}     # header 10 pt wider: it hides the whole green row
    add(6)                                                                     # rest, seam 0
    ramp("seam", 0, 20, 7)
    add(4, seam=20.0)                                                          # gap 20
    add(3, seam=20.0, **narrow)
    for a in (3, 8, 15, 24, 33, 45, 57, 68, 79, 86, 90):                       # rotate with the gap
        add(1, seam=20.0, angle=float(a), **narrow)
    add(2, seam=20.0, angle=90.0, **wide)
    ramp("seam", 20, -90, 20, angle=90.0, **wide)                              # cover the green row at 90 deg
    add(3, seam=-90.0, angle=90.0, **wide)
    for a in (82, 71, 60, 52, 41, 33, 22, 12, 5, 0):                           # rotate back covered by 90
        add(1, seam=-90.0, angle=float(a), **wide)
    ramp("seam", -90, -120, 10, **wide)
    add(3, seam=-120.0, **wide)                                                # overlap 120 (green + 40 pt)
    for a in (-6, -14, -27, -38, -27, -14, -6, 0):                             # rotate the other way at 120
        add(1, seam=-120.0, angle=float(a), **wide)
    ramp("seam", -120, 0, 20, **wide)
    add(3, seam=0.0, angle=0.0, **wide)
    for a in (7, 17, 29, 17, 7, 0):                                            # touching (0) mid-rotation
        add(1, seam=0.0, angle=float(a), **narrow)
    # A window larger than the display (the content's and the header's lateral edges off screen), rotated.
    for a in (0, 11, 23, 23, 11, 0):
        add(1, seam=-20.0, angle=float(a), ww=600.0, wh=1000.0, hx0=0.0, hx1=600.0, cx0=0.0, cx1=600.0)
    # The header misaligned laterally (drawn narrower and pinned left, as an app-driven resize can) over a gap.
    add(3, seam=40.0, hx0=20.0, hx1=241.0, cx0=20.0, cx1=382.0)
    add(3, seam=-50.0, angle=31.0, hx0=20.0, hx1=241.0, cx0=20.0, cx1=382.0)
    for f in out:
        f["ctop"] = f["top0"] + f["hdr"] + f["seam"]          # the content's top in window points
    return out


def render(f, ss=3, band=128):
    """One frame (H x W x 3 uint8), supersampled ss x ss (in bands of display rows)."""
    return np.concatenate([render_rows(f, y0, min(H, y0 + band), ss) for y0 in range(0, H, band)])


def render_rows(f, y0, y1, ss):
    th = math.radians(f["angle"])
    cth, sth = math.cos(th), math.sin(th)
    off = (np.arange(ss, dtype=np.float32) + 0.5) / ss
    xs = (np.arange(W, dtype=np.float32)[:, None] + off[None, :]).ravel() / SCALE - W_PT / 2   # points from the centre
    ys = (np.arange(y0, y1, dtype=np.float32)[:, None] + off[None, :]).ravel() / SCALE - H_PT / 2
    X, Y = np.meshgrid(xs, ys)
    # Display -> window: rotate by -angle, then the window's origin at its top-left corner.
    wx = cth * X + sth * Y + f["ww"] / 2
    wy = -sth * X + cth * Y + f["wh"] / 2
    ww, wh, r = f["ww"], f["wh"], RADIUS
    dx = np.maximum(np.abs(wx - ww / 2) - (ww / 2 - r), 0)
    dy = np.maximum(np.abs(wy - wh / 2) - (wh / 2 - r), 0)
    inside = (np.abs(wx - ww / 2) <= ww / 2) & (np.abs(wy - wh / 2) <= wh / 2) & (dx * dx + dy * dy <= r * r)
    img = np.zeros(X.shape + (3,), np.float32)
    img[inside] = COLORS["B"]
    ct = f["ctop"]
    cy = wy - ct
    incont = inside & (wx >= f["cx0"]) & (wx < f["cx1"]) & (cy >= 0) & (cy < 80 + 40 * 60)
    green = incont & (cy < 80)
    rowi = np.floor((cy - 80) / 60)
    yel = incont & ~green & (rowi % 2 == 0)
    mag = incont & ~green & (rowi % 2 == 1)
    img[green] = COLORS["G"]
    img[yel] = COLORS["Y"]
    img[mag] = COLORS["M"]
    # The header, turned by `tilt` about its centre (window points).
    hcx, hcy = (f["hx0"] + f["hx1"]) / 2, f["top0"] + f["hdr"] / 2
    ct_, st_ = math.cos(math.radians(f["tilt"])), math.sin(math.radians(f["tilt"]))
    hx = ct_ * (wx - hcx) + st_ * (wy - hcy)
    hy = -st_ * (wx - hcx) + ct_ * (wy - hcy)
    hw2, hh2 = (f["hx1"] - f["hx0"]) / 2, f["hdr"] / 2
    hdr = inside & (np.abs(hx) < hw2) & (np.abs(hy) < hh2)
    img[hdr] = COLORS["R"]
    img = img.reshape(y1 - y0, ss, W, ss, 3).mean(axis=(1, 3))
    return np.clip(np.round(img), 0, 255).astype(np.uint8)


def edge_visible(f, x, y0, y1, content, need=25.0):
    """Whether at least `need` pt of the window-vertical edge x, y in [y0, y1] shows on screen (4 pt inside the display; the
    analyzer skips shorter fragments at the display's corners): both sides (2 pt off)
    inside the window and the display, and (for the content's edge) not under the header."""
    th = math.radians(f["angle"])
    cth, sth = math.cos(th), math.sin(th)
    ww, wh, r = f["ww"], f["wh"], RADIUS
    seen = 0.0
    for y in np.arange(max(y0, 0.0) + 0.25, min(y1, wh), 0.5):
        ok = True
        for xx in (x - 2.0, x + 2.0):
            dx = max(abs(xx - ww / 2) - (ww / 2 - r), 0)
            dy = max(abs(y - wh / 2) - (wh / 2 - r), 0)
            if abs(xx - ww / 2) > ww / 2 or abs(y - wh / 2) > wh / 2 or dx * dx + dy * dy > r * r:
                ok = False
            # window -> display
            px, py = xx - ww / 2, y - wh / 2
            X = cth * px - sth * py + W_PT / 2
            Y = sth * px + cth * py + H_PT / 2
            if not (4 <= X <= W_PT - 4 and 4 <= Y <= H_PT - 4):
                ok = False
            if content and f["hx0"] <= xx < f["hx1"] and f["top0"] <= y < f["top0"] + f["hdr"]:
                ok = False
        seen += 0.5 if ok else 0.0
    return seen >= need


def write_truth(out, fr):
    """truth.csv: per frame the angle, the seam and, per side where both lateral edges show, header - content."""
    with open(os.path.join(out, "truth.csv"), "w", newline="") as fh:
        cols = ["frame", "angle", "seam", "hdr", "latL", "latR", "ctop", "ww", "wh", "tilt", "reject"]
        wr = csv.DictWriter(fh, fieldnames=cols)
        wr.writeheader()
        for i, f in enumerate(fr):
            hb = f["top0"] + f["hdr"]
            lat = {}
            for side, hx, cx in (("latL", f["hx0"], f["cx0"]), ("latR", f["hx1"], f["cx1"])):
                vis = edge_visible(f, hx, f["top0"], hb, False) and edge_visible(f, cx, f["ctop"], f["wh"], True)
                lat[side] = round(hx - cx, 4) if vis else ""
            if f["tilt"]:
                lat = {"latL": "", "latR": ""}
            wr.writerow({"frame": i, "angle": f["angle"] % 180.0, "seam": round(f["seam"], 4), "hdr": f["hdr"],
                         **lat, "ctop": f["ctop"], "ww": f["ww"], "wh": f["wh"], "tilt": f["tilt"],
                         "reject": int(abs(f["tilt"]) > 1.0)})


def make(out, scene="main"):
    os.makedirs(out, exist_ok=True)
    fr = script(scene)
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                          "-r", "60", "-i", "pipe:0", "-c:v", "libx264", "-preset", "medium", "-crf", "14",
                          "-pix_fmt", "yuv420p", os.path.join(out, "rec.mov")], stdin=subprocess.PIPE)
    for f in fr:
        p.stdin.write(render(f).tobytes())
    p.stdin.close()
    p.wait()
    write_truth(out, fr)
    json.dump({"name": "synthetic", "deviceType": "synthetic", "runtime": "synthetic", "scale": SCALE,
               "test": "synthetic", "launchArgs": [], "forced": False},
              open(os.path.join(out, "meta.json"), "w"), indent=1)
    print(f"{len(fr)} frames -> {out}")


def check(out, tol=0.5):
    truth = {int(r["frame"]): r for r in csv.DictReader(open(os.path.join(out, "truth.csv")))}
    got = {int(r["frame"]): r for r in csv.DictReader(open(os.path.join(out, "frames.csv")))}
    worst = {"seam": (0.0, None), "angle": (0.0, None), "lat": (0.0, None)}
    bad, missing = [], []
    rejects = [0, 0]
    for i, t in sorted(truth.items()):
        g = got.get(i, {})
        if t.get("reject") == "1":
            rejects[0] += 1
            if g.get("band") != "reject":
                bad.append((i, "reject", 1, g.get("band")))
            else:
                rejects[1] += 1
            continue
        if g.get("band") == "reject":
            bad.append((i, "reject", 0, "reject"))
            continue
        if g.get("seam", "") == "":
            missing.append(i)
            continue
        e = float(g["seam"]) - float(t["seam"])
        if abs(e) > abs(worst["seam"][0]):
            worst["seam"] = (e, i)
        if abs(e) > tol:
            bad.append((i, "seam", float(t["seam"]), float(g["seam"])))
        ea = (float(g["angle"]) - float(t["angle"]) + 90) % 180 - 90
        if abs(ea) > abs(worst["angle"][0]):
            worst["angle"] = (ea, i)
        if abs(ea) > 0.1:
            bad.append((i, "angle", float(t["angle"]), float(g["angle"])))
        for side in ("latL", "latR"):
            if t[side] != "":
                if g.get(side, "") == "":
                    bad.append((i, side, float(t[side]), None))
                    continue
                el = float(g[side]) - float(t[side])
                if abs(el) > abs(worst["lat"][0]):
                    worst["lat"] = (el, i)
                if abs(el) > tol:
                    bad.append((i, side, float(t[side]), float(g[side])))
    seams = sorted({float(t["seam"]) for t in truth.values()})
    print(f"frames {len(truth)}, seam values {seams[0]}..{seams[-1]}, unmeasured {len(missing)} {missing[:20]}")
    print("worst error: " + ", ".join(f"{k} {v[0]:+.3f} (frame {v[1]})" for k, v in worst.items()))
    if rejects[0]:
        print(f"tilted past 1 deg: {rejects[0]} frames, rejected {rejects[1]}")
    for b in bad:
        print("  OUT OF TOLERANCE", b)
    ok = not bad and not missing
    print("PASS" if ok else "FAIL")
    return ok


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("make", "check"):
        sys.exit(__doc__)
    if sys.argv[1] == "make":
        make(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "main")
    else:
        sys.exit(0 if check(sys.argv[2]) else 1)
