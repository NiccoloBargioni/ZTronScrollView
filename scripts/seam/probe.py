#!/usr/bin/env python3
"""Seam lab white-probe tracker (M8b-s6): where a pure white probe sits relative to the header's bottom edge, per frame.

usage: python3 -I scripts/seam/probe.py <scenario-dir> [--edge bottom|top] [--window=LO,HI] [--min-px N]

Runs after scripts/seam/analyze.py on the same recording (reads <dir>/rec.mov, meta.json and frames.csv: the band normal
n, the header's bottom edge hdr_bot_c and its lateral edges, per frame). The lab's white probes (`-ZTronSeamHold 1`: a
20 pt square refresh indicator; `-ZTronSeamSticky 1`: a 120 x 16 pt bar in a bottom-aligned overlay of the header) are
the only white pixels in a window along n around the header's bottom edge (default [-80, +6] pt; the lab's white buttons
sit at the bottom of the screen, far from it). `--edge top` measures against the header's TOP edge instead (hdr_top_c: a
`.preserve` refresh indicator sits in the gap above the header, default window [-80, +6] pt then too). Per frame: the probe's extent along n relative to the header's bottom
(top_rel, bot_rel, pt), its centre along u relative to the header's lateral centre (lat_rel), its pixel count.

Summary (probe.json): the rest value before the first stimulus, the largest deviation from it over the recording
(maxDevN / maxDevU, pt), the largest single-frame step of bot_rel and lat_rel (maxStepN / maxStepU, pt) and how many
frames with a measured header lack the probe (missing). A probe glued to the header moves by < 1 pt relative to it.
"""
import argparse
import csv
import json
import os
import subprocess

import numpy as np


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


def num(r, k):
    try:
        v = float(r[k])
        return v if v == v else None
    except (KeyError, TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--window", default="-80,6")
    ap.add_argument("--min-px", type=int, default=20)
    ap.add_argument("--edge", choices=("bottom", "top"), default="bottom")
    a = ap.parse_args()
    lo, hi = (float(x) for x in a.window.split(","))
    meta = json.load(open(os.path.join(a.dir, "meta.json")))
    scale = float(meta.get("scale", 3))
    rows = {int(r["frame"]): r for r in csv.DictReader(open(os.path.join(a.dir, "frames.csv")))}
    video = os.path.join(a.dir, "rec.mov")
    info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                      "stream=width,height", "-of", "json", video],
                                     check=True, capture_output=True, text=True).stdout)["streams"][0]
    w, h = info["width"], info["height"]
    out = []
    for i, f in enumerate(frames(video, w, h)):
        r = rows.get(i)
        if r is None:
            continue
        nx, ny, bot = num(r, "nx"), num(r, "ny"), num(r, "hdr_bot_c" if a.edge == "bottom" else "hdr_top_c")
        if nx is None or ny is None or bot is None:
            continue
        hl, hr = num(r, "hdr_l_c"), num(r, "hdr_r_c")
        white = (f[..., 0] > 230) & (f[..., 1] > 230) & (f[..., 2] > 230)
        ys, xs = np.nonzero(white)
        rec = {"frame": i, "t": r.get("t"), "hdr_bot_c": bot, "px": 0, "top_rel": "", "bot_rel": "", "lat_rel": ""}
        if len(xs):
            px = (xs - w / 2.0) / scale
            py = (ys - h / 2.0) / scale
            s = px * nx + py * ny - bot                 # along n, relative to the header's bottom edge
            u = px * ny - py * nx                       # along u = (ny, -nx)
            keep = (s >= lo) & (s <= hi)
            if hl is not None and hr is not None:
                keep &= (u >= min(hl, hr) - 2) & (u <= max(hl, hr) + 2)
            if keep.sum() >= a.min_px:
                s, u = s[keep], u[keep]
                centre = (hl + hr) / 2 if hl is not None and hr is not None else 0.0
                rec.update(px=int(keep.sum()), top_rel=round(float(np.percentile(s, 1)), 3),
                           bot_rel=round(float(np.percentile(s, 99)), 3),
                           lat_rel=round(float((np.percentile(u, 1) + np.percentile(u, 99)) / 2 - centre), 3))
        out.append(rec)
    with open(os.path.join(a.dir, "probe.csv"), "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=list(out[0].keys()) if out else ["frame"])
        wr.writeheader()
        wr.writerows(out)
    seen = [x for x in out if x["px"]]
    summary = {"frames": len(out), "probeFrames": len(seen), "missing": len(out) - len(seen)}
    if seen:
        rest_n, rest_u = seen[0]["bot_rel"], seen[0]["lat_rel"]
        summary.update(restBotRel=rest_n, restLatRel=rest_u,
                       maxDevN=round(max(abs(x["bot_rel"] - rest_n) for x in seen), 3),
                       maxDevU=round(max(abs(x["lat_rel"] - rest_u) for x in seen), 3))
        stepn = stepu = 0.0
        at_n = at_u = None
        for p, q in zip(out, out[1:]):
            if p["px"] and q["px"]:
                if abs(q["bot_rel"] - p["bot_rel"]) > stepn:
                    stepn, at_n = abs(q["bot_rel"] - p["bot_rel"]), q["frame"]
                if abs(q["lat_rel"] - p["lat_rel"]) > stepu:
                    stepu, at_u = abs(q["lat_rel"] - p["lat_rel"]), q["frame"]
        summary.update(maxStepN=round(stepn, 3), maxStepNFrame=at_n, maxStepU=round(stepu, 3), maxStepUFrame=at_u)
        gaps = [x["frame"] for x in out if not x["px"]]
        summary["missingFrames"] = gaps[:40]
    json.dump(summary, open(os.path.join(a.dir, "probe.json"), "w"), indent=1)
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
