#!/usr/bin/env python3
"""Open item 19: the seam lab's held refresh indicator (`-ZTronSeamHold 1`: a white 20 x 20 pt square) against the content's
edge on the hold's side, per recorded frame, in a view without a header (`-ZTronSeamNoHeader 1`) on any edge
(`-ZTronSeamHoldEdge`). The content's edge and the window's edge are found on two lines from the display centre along the
edge's outward axis (lateral offsets +-90 pt: clear of the probe, the Dynamic Island and the rounded corners); the probe is
the white component within 40 pt of the centre line across that axis (the status bar text and the lab's buttons are
farther out).

usage: python3 -I holdgap.py <scenario-dir> --edge top|bottom|leading|trailing [--base <portrait,landscape>] [--tol <pt>]
  --base  the edge's base (the safe-area inset the gap starts at) in portrait and landscape; default per edge: top 62,0,
          bottom 34,21, leading / trailing 0,62 (the larger of iPhone 18 Pro / 15 Pro); mid-rotation the larger one. A
          frame is judged only when the indicator's resting place (measured against the content's edge in the first
          frames of the hold) lies entirely between the content's edge and the base, or entirely off the window.
Per frame (holdgap.csv): the content edge s_e and the window edge s_w (pt from the display centre along the outward axis),
the probe's extent along the axis relative to s_e, and a verdict:
  inPlace  the probe is drawn at its resting place against the content's edge (within --tol, default 1 pt);
  off      drawn elsewhere (dev = its centre's distance from the resting place);
  missing  its place is on the screen, it is not drawn;
  over     some of it lies on the content's side of the edge (> 1 pt), or a probe-sized white square anywhere has a
           surround of mostly content (rvover.py's ring test): drawn over the content (judged in every frame);
  ghost    its place is off the window, a probe is drawn anyway;
  partial / offscreen / unknown: not judged (the place straddles the base or the window's edge, or no edge found).
Prints and writes holdgap.json: counts, max deviation, worst over depth, the frames of each failure.
"""
import argparse
import csv
import json
import os
import subprocess
from collections import deque

import numpy as np

CONTENT = ("yellow", "magenta", "green", "cyan")


def frames(path, w, h):
    p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", path, "-map", "0:v:0", "-fps_mode", "passthrough",
                          "-enc_time_base", "demux", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
    n = w * h * 3
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, np.uint8).reshape(h, w, 3)
    p.wait()


def classify(px):
    """Per pixel (N x 3 int): 'yellow' ... as an index into NAMES."""
    R, G, B = px[:, 0], px[:, 1], px[:, 2]
    out = np.full(len(px), 6, dtype=np.int8)                              # other
    out[(R > 200) & (G > 200) & (B < 80)] = 0                             # yellow
    out[(R > 200) & (G < 80) & (B > 200)] = 1                             # magenta
    out[(R < 80) & (G > 200) & (B < 80)] = 2                              # green
    out[(R < 80) & (G > 200) & (B > 200)] = 3                             # cyan
    out[(R < 60) & (G < 60) & (B > 190)] = 4                              # blue
    out[(R < 30) & (G < 30) & (B < 30)] = 5                               # black
    out[(R > 230) & (G > 230) & (B > 230)] = 7                            # white
    return out


NAMES = ("yellow", "magenta", "green", "cyan", "blue", "black", "other", "white")


def run_edges(cls, step):
    """From the centre outward: (content edge, window edge) in samples; None when not found. The content edge is the end
    of the first content run followed by >= 3 pt of blue / white; the window edge the first black run of >= 3 pt after it."""
    n = len(cls)
    k3 = max(1, int(round(3 / step)))
    is_content = cls <= 3
    edge = None
    i = 0
    # Skip to the first content sample (the centre may sit on a probe or text).
    while i < n and not is_content[i]:
        i += 1
    while i < n:
        if not is_content[i]:
            run = cls[i:i + k3]
            if len(run) == k3 and np.all((run == 4) | (run == 7)):
                edge = i
                break
            if len(run) == k3 and np.all(run == 5):
                return None, i            # content runs into the window's edge: the gap is off the window
        i += 1
    if edge is None:
        return None, None
    j = edge
    while j < n:
        run = cls[j:j + k3]
        if len(run) == k3 and np.all(run == 5):
            return edge, j
        j += 1
    return edge, None


def components(mask):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        out.append(np.array(pts))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--edge", required=True, choices=["top", "bottom", "leading", "trailing"])
    ap.add_argument("--base", default=None, help="portrait,landscape base of the edge in pt")
    ap.add_argument("--tol", type=float, default=1.0)
    ap.add_argument("--rest-frames", type=int, default=8)
    ap.add_argument("--overlay", action="store_true",
                    help="overlay placement: the probe floats at the base, judged against the window's edge (present in every "
                         "frame with the window's edge measured, largest single-frame step); 'over' does not apply")
    a = ap.parse_args()
    # The edge's base (its safe-area inset) per orientation: iPhone 18 Pro (27.0) / 15 Pro (17.5), the larger of the two.
    bp, bl = {"top": (62, 0), "bottom": (34, 21), "leading": (0, 62), "trailing": (0, 62)}[a.edge]
    if a.base:
        bp, bl = (float(x) for x in a.base.split(","))
    meta = json.load(open(os.path.join(a.dir, "meta.json")))
    sc = float(meta.get("scale", 3))
    rows = {int(r["frame"]): r for r in csv.DictReader(open(os.path.join(a.dir, "frames.csv")))}
    video = os.path.join(a.dir, "rec.mov")
    info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                      "stream=width,height", "-of", "json", video],
                                     check=True, capture_output=True, text=True).stdout)["streams"][0]
    w, h = info["width"], info["height"]
    C = np.array([w / 2.0, h / 2.0])
    step = 0.5
    smax = int(max(w, h) / sc / step)
    cell = int(round(2 * sc))
    recs = []
    for i, f in enumerate(frames(video, w, h)):
        r = rows.get(i)
        rec = {"frame": i, "t": r.get("t") if r else "", "s_e": "", "s_w": "", "probe": 0, "p0": "", "p1": "", "pc": "",
               "pk": "", "ring": "", "verdict": "unknown"}
        recs.append(rec)
        try:
            nx, ny = float(r["nx"]), float(r["ny"])
        except (TypeError, KeyError, ValueError):
            continue
        n = np.array([nx, ny])
        u = np.array([ny, -nx])
        axis, cross = {"top": (-n, u), "bottom": (n, u), "leading": (-u, n), "trailing": (u, n)}[a.edge]
        # Content and window edges on two lines, +-90 pt across.
        s = np.arange(smax) * step
        found = []
        for k in (-90.0, 90.0):
            pts = C[None, :] + (s[:, None] * axis[None, :] + k * cross[None, :]) * sc
            xi, yi = np.round(pts[:, 0]).astype(int), np.round(pts[:, 1]).astype(int)
            ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
            cls = np.full(len(s), 5, dtype=np.int8)                  # off the recording = black
            cls[ok] = classify(f[yi[ok], xi[ok]].astype(np.int16))
            found.append(run_edges(cls, step))
        es = [e for e, _ in found if e is not None]
        ws = [x for _, x in found if x is not None]
        s_e = float(np.mean(es)) * step if len(es) == 2 and abs(es[0] - es[1]) * step <= 3 else None
        s_w = float(min(ws)) * step if ws else None
        content_off = all(e is None and x is not None for e, x in found)   # content reaches the window's edge
        rec["s_e"] = round(s_e, 2) if s_e is not None else ""
        rec["s_w"] = round(s_w, 2) if s_w is not None else ""
        # White components on a 2 pt grid (<= 34 pt per side: the lab's buttons form one 72 x 24 pt component). Per
        # component: its extent along the axis, its centre across it, its filled area and the colours of a ring 3..6 pt
        # outside its box (rvover's test: mostly content = drawn over the content, wherever it is).
        hh, ww = (h // cell) * cell, (w // cell) * cell
        g = f[:hh, :ww].reshape(hh // cell, cell, ww // cell, cell, 3).astype(np.int16)
        white = ((g[..., 0] > 230) & (g[..., 1] > 230) & (g[..., 2] > 230)).mean(axis=(1, 3)) > 0.25
        best, ringover = None, 0
        r0, r1 = int(3 * sc), int(6 * sc)
        for comp in components(white):
            y0, x0 = comp.min(axis=0)
            y1, x1 = comp.max(axis=0)
            if (x1 - x0 + 1) * 2 > 34 or (y1 - y0 + 1) * 2 > 34:
                continue
            sub = f[y0 * cell:(y1 + 1) * cell, x0 * cell:(x1 + 1) * cell].astype(np.int16)
            m = (sub[..., 0] > 230) & (sub[..., 1] > 230) & (sub[..., 2] > 230)
            py, pxx = np.nonzero(m)
            area = len(py) / (sc * sc)
            if area < 40 or area > 480:            # the lab's buttons are 24 x 24 pt (576), the probe 400
                continue
            P = np.stack([pxx + x0 * cell + 0.5, py + y0 * cell + 0.5], axis=1) - C[None, :]
            sa = P @ axis / sc
            ka = P @ cross / sc
            k0, k1 = float(np.percentile(ka, 1)), float(np.percentile(ka, 99))
            X0, X1, Y0, Y1 = x0 * cell, (x1 + 1) * cell, y0 * cell, (y1 + 1) * cell
            ring = []
            for (ya, yb, xa, xb) in ((Y0 - r1, Y0 - r0, X0 - r1, X1 + r1), (Y1 + r0, Y1 + r1, X0 - r1, X1 + r1),
                                     (Y0, Y1, X0 - r1, X0 - r0), (Y0, Y1, X1 + r0, X1 + r1)):
                ya, yb, xa, xb = max(0, ya), min(h, yb), max(0, xa), min(w, xb)
                if yb > ya and xb > xa:
                    ring.append(f[ya:yb, xa:xb].reshape(-1, 3))
            content = 0.0
            if ring:
                rc_ = classify(np.concatenate(ring).astype(np.int16))
                content = float((rc_ <= 3).mean())
            if area >= 100 and content > 0.5:
                ringover = max(ringover, 1)
            if abs((k0 + k1) / 2) > 40 or not (12 <= k1 - k0 <= 28):
                continue
            cand = (float(np.percentile(sa, 1)), float(np.percentile(sa, 99)), (k0 + k1) / 2)
            if best is None or abs(cand[2]) < abs(best[2]):
                best = cand
        if best is not None:
            rec.update(probe=1, p0=round(best[0], 2), p1=round(best[1], 2), pk=round(best[2], 2))
            if s_e is not None:
                rec["pc"] = round((best[0] + best[1]) / 2 - s_e, 2)
        rec["ring"] = ringover
        # Portrait (n down the recording), landscape (n across it) or in between (the larger base).
        ang = abs(np.degrees(np.arctan2(n[0], n[1]))) % 180
        base = bp if min(ang, 180 - ang) < 1 else bl if abs(ang - 90) < 1 else max(bp, bl)
        rec["_found"] = (s_e, s_w, content_off, best, ringover, base)
    if a.overlay:
        # The probe's centre along the outward axis from the display centre (rotation-invariant: the axis turns with the
        # content): present from its first frame on, and its largest single-frame step against its whole travel.
        rows_ = [x for x in recs if x.get("_found")]
        first = next((x["frame"] for x in rows_ if x["_found"][3] is not None), None)
        rows_ = [x for x in rows_ if first is not None and x["frame"] >= first]
        miss = [x["frame"] for x in rows_ if x["_found"][3] is None]
        cs = [(x["frame"], (x["_found"][3][0] + x["_found"][3][1]) / 2) for x in rows_ if x["_found"][3]]
        step, at = 0.0, None
        for (f0, v0), (f1, v1) in zip(cs, cs[1:]):
            if f1 == f0 + 1 and abs(v1 - v0) > step:
                step, at = abs(v1 - v0), f1
        travel = (max(v for _, v in cs) - min(v for _, v in cs)) if cs else 0.0
        for x in recs:
            x.pop("_found", None)
        summary = {"edge": a.edge, "overlay": True, "frames": len(recs), "judged": len(rows_), "drawn": len(cs),
                   "missing": len(miss), "missingFrames": miss[:40], "travel": round(travel, 2), "maxStep": round(step, 2),
                   "maxStepFrame": at, "stepFraction": round(step / travel, 3) if travel > 0 else None}
        json.dump(summary, open(os.path.join(a.dir, "holdgap.json"), "w"), indent=1)
        print(json.dumps(summary))
        return
    # Resting place: the first frames with the probe and the edge, full length (19-21 pt).
    rest = [x for x in recs if x.get("pc") != "" and x["probe"] and 18 <= x["p1"] - x["p0"] <= 22][:a.rest_frames]
    if not rest:
        print(json.dumps({"error": "no resting probe frames"}))
        return
    rc = float(np.median([x["pc"] for x in rest]))
    half = 10.0
    counts = {k: 0 for k in ("inPlace", "off", "missing", "over", "ghost", "partial", "offscreen", "unknown")}
    lists = {k: [] for k in ("off", "missing", "over", "ghost")}
    maxdev, maxover = 0.0, 0.0
    first_rest = rest[0]["frame"]
    for x in recs:
        found = x.pop("_found", None)
        if found is None or x["frame"] < first_rest:
            continue
        s_e, s_w, content_off, best, ringover, base = found
        # Over the content: any part of the probe on the content's side of its edge, or a probe-sized white square
        # anywhere whose surround is mostly content.
        if (best is not None and s_e is not None and best[0] < s_e - 1.0) or ringover:
            x["verdict"] = "over"
            counts["over"] += 1
            lists["over"].append(x["frame"])
            if best is not None and s_e is not None:
                maxover = max(maxover, s_e - best[0])
            continue
        if s_e is None:
            if content_off and best is not None:
                # The content covers the line up to the window's edge: no gap on the screen there.
                x["verdict"] = "ghost"
                counts["ghost"] += 1
                lists["ghost"].append(x["frame"])
            else:
                x["verdict"] = "offscreen" if content_off else "unknown"
                counts[x["verdict"]] += 1
            continue
        lo, hi = s_e + rc - half, s_e + rc + half
        if s_w is not None and hi <= s_w - base:
            if best is None:
                x["verdict"] = "missing"
                counts["missing"] += 1
                lists["missing"].append(x["frame"])
            else:
                dev = abs((best[0] + best[1]) / 2 - s_e - rc)
                maxdev = max(maxdev, dev)
                if dev <= a.tol and 18 <= best[1] - best[0] <= 22:
                    x["verdict"] = "inPlace"
                    counts["inPlace"] += 1
                else:
                    x["verdict"] = "off"
                    counts["off"] += 1
                    lists["off"].append((x["frame"], round(dev, 2)))
        elif s_w is not None and lo >= s_w:
            if best is not None:
                x["verdict"] = "ghost"
                counts["ghost"] += 1
                lists["ghost"].append(x["frame"])
            else:
                x["verdict"] = "offscreen"
                counts["offscreen"] += 1
        else:
            x["verdict"] = "partial"
            counts["partial"] += 1
    with open(os.path.join(a.dir, "holdgap.csv"), "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=[k for k in recs[0].keys() if not k.startswith("_")])
        wr.writeheader()
        for x in recs:
            x.pop("_found", None)
            wr.writerow(x)
    judged = counts["inPlace"] + counts["off"] + counts["missing"]
    summary = {"edge": a.edge, "frames": len(recs), "restCentre": round(rc, 2), "restFrom": first_rest,
               "onScreen": judged, **counts, "maxDev": round(maxdev, 2), "maxOverPt": round(maxover, 2),
               **{k + "Frames": v[:40] for k, v in lists.items()}}
    json.dump(summary, open(os.path.join(a.dir, "holdgap.json"), "w"), indent=1)
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
