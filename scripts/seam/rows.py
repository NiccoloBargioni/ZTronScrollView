#!/usr/bin/env python3
"""Seam lab row-change tracker (M8b-s8 s2, open item 34): the user's own animated change of the content, per frame.

usage: python3 -I scripts/seam/rows.py <scenario-dir> [--x FRACTION] [--min-change A]

Reads <dir>/rec.mov and meta.json of a `rows` scenario (SeamLabUITests.testRows, `-ZTronSeamRows <n> -ZTronSeamRowsTo
<m>`: seam.width changes the content's row count n -> m, then back). The lab's rows are pure yellow / magenta over the
content's pure blue background; a row inserted or removed in an animation fades (SwiftUI's default `.opacity`
transition), so its pixels are blue blended with the row colour and the red channel IS the row's drawn opacity (yellow
(1,1,0) and magenta (1,0,1) both give r = a over blue (0,0,1)). Per frame, along the column at --x of the width (default
0.3, clear of the lab's buttons): the content's top (the first pure green pixel: the 80 pt green first row) and the
opacity of the first changed row (row min(n, m), at content y 80 + 60 min(n, m) + 30 pt).

With `-ZTronSeamRowsGrow 1` (extra `rgrow`) the content keeps n rows and their height changes (12 pt per count step: 60
-> 120 pt for 5 -> 10, no insertion); the tracked value is then the first row's drawn height in pt (from the end of the
green row to the first magenta pixel below it: row 0 is yellow, row 1 magenta) and --min-change defaults to 0.2 pt.

A change segment is a run of frames whose tracked value moves by more than --min-change (opacity: default 0.003, under
one 8-bit level) from the previous frame in one direction, bridged across holes < 0.4 s. Per segment: `frames` (drawn frames that move the
tracked value: an animation that runs draws one
per display frame, 30 in 0.5 s at 60 Hz; a stalled one draws the whole change in 1), `framesIn500ms` (those within 0.5 s
of the segment's first), `maxStep` (the largest single-frame step as a fraction of the segment's total change: a jump is
>= 0.5), `maxGapMs` (the longest interval between two moving frames) and `maxGapCoreMs` (the same between 5 % and 95 % of the
change: a recorder gap above ~35 ms there makes the recording suspect), `contentTopMove` (pt: how far the content's top moved during the segment; 0 for top-aligned
content), and for each stimulus (a segment moving more than 5 % of the full change) `rest` (the value drawn before the
next stimulus), `landMs` (when that rest was first drawn, from the segment's first moving frame: ~450-500 ms for a 0.5 s
animation; a final frame drawn late shows up here) and `lateStep` (the segment's last value's distance from the rest).
Summary in rows.json; per-frame values in rows.csv.
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


def times(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "frame=best_effort_timestamp_time", "-of", "csv=p=0", path], capture_output=True, text=True)
    ts = []
    for line in out.stdout.split():
        try:
            ts.append(float(line.strip(",")))
        except ValueError:
            ts.append(None)
    return ts


def arg(meta, name, default=None):
    a = meta.get("launchArgs", [])
    if name in a:
        i = a.index(name)
        if i + 1 < len(a):
            return a[i + 1]
    return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--x", type=float, default=0.3)
    ap.add_argument("--min-change", type=float, default=None)
    a = ap.parse_args()
    meta = json.load(open(os.path.join(a.dir, "meta.json")))
    scale = float(meta.get("scale", 3))
    n = int(arg(meta, "-ZTronSeamRows", 40))
    m = int(arg(meta, "-ZTronSeamRowsTo", n))
    k = min(n, m)
    grow = arg(meta, "-ZTronSeamRowsGrow", "0") == "1"
    if a.min_change is None:
        a.min_change = 0.2 if grow else 0.003
    video = os.path.join(a.dir, "rec.mov")
    info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                      "stream=width,height", "-of", "json", video],
                                     capture_output=True, text=True).stdout)["streams"][0]
    w, h = int(info["width"]), int(info["height"])
    ts = times(video)
    x = int(w * a.x)
    row_off = (80 + 60 * k + 30) * scale
    out = []
    for i, f in enumerate(frames(video, w, h)):
        col = f[:, x, :].astype(int)
        green = np.where((col[:, 1] > 230) & (col[:, 0] < 25) & (col[:, 2] < 25))[0]
        top = float(green[0]) if len(green) else None
        alpha = None
        if top is not None and grow:
            # Row 0's drawn height: from the green row's end to the first magenta pixel below it.
            start = int(round(top + 80 * scale))
            seg = col[start:]
            mag = np.where((seg[:, 0] > 230) & (seg[:, 1] < 25) & (seg[:, 2] > 230))[0]
            alpha = float(mag[0]) / scale if len(mag) else None
        elif top is not None:
            y = int(round(top + row_off))
            if 0 <= y < h:
                px = f[max(0, y - 2):y + 3, max(0, x - 2):x + 3, :].astype(float).reshape(-1, 3).mean(axis=0)
                # Blue under the row: only a blend of blue and yellow / magenta is a row pixel (b + r ~ 1 for yellow).
                alpha = float(px[0] / 255.0)
        t = ts[i] if i < len(ts) else None
        out.append({"frame": i, "t": t, "top_pt": None if top is None else top / scale, "alpha": alpha})
    with open(os.path.join(a.dir, "rows.csv"), "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=["frame", "t", "top_pt", "alpha"])
        wr.writeheader()
        wr.writerows(out)
    # Segments of moving opacity.
    moving = []
    prev = None
    for r in out:
        if r["alpha"] is None:
            continue
        if prev is not None and abs(r["alpha"] - prev["alpha"]) > a.min_change:
            moving.append((prev, r))
        prev = r
    segs = []
    def sign(pair):
        return 1 if pair[1]["alpha"] > pair[0]["alpha"] else -1

    for p, r in moving:
        # One segment per direction of motion, bridged across recorder holes < 0.4 s.
        if (segs and r["t"] is not None and segs[-1]["pairs"][-1][1]["t"] is not None
                and r["t"] - segs[-1]["pairs"][-1][1]["t"] < 0.4 and sign((p, r)) == sign(segs[-1]["pairs"][0])):
            segs[-1]["pairs"].append((p, r))
        else:
            segs.append({"pairs": [(p, r)]})
    summary = []
    for s in segs:
        pairs = s["pairs"]
        a0 = pairs[0][0]["alpha"]
        a1 = pairs[-1][1]["alpha"]
        total = abs(a1 - a0)
        steps = [abs(r["alpha"] - p["alpha"]) for p, r in pairs]
        t0 = pairs[0][1]["t"]
        tl = [r["t"] for _, r in pairs if r["t"] is not None]
        gaps = [(q - p) * 1000 for p, q in zip(tl, tl[1:])]
        # The core of the change (5 % .. 95 % of it): the recorder's frame gaps there (the slow ease-in / ease-out tails
        # move by single 8-bit levels at irregular intervals).
        core = [r["t"] for _, r in pairs if r["t"] is not None and total > 0.05
                and 0.05 <= abs(r["alpha"] - a0) / total <= 0.95]
        core_gaps = [(q - p) * 1000 for p, q in zip(core, core[1:])]
        tops = [r["top_pt"] for p, r in pairs if r["top_pt"] is not None]
        if pairs[0][0]["top_pt"] is not None:
            tops.append(pairs[0][0]["top_pt"])
        summary.append({
            "frames": len(pairs),
            "framesIn500ms": sum(1 for _, r in pairs if r["t"] is not None and t0 is not None and r["t"] - t0 <= 0.5),
            "from": round(a0, 3), "to": round(a1, 3),
            "durationMs": round((tl[-1] - tl[0]) * 1000, 1) if len(tl) > 1 else 0,
            "maxStep": round(max(steps) / total, 3) if total > 0.05 else None,
            "maxGapMs": round(max(gaps), 1) if gaps else None,
            "maxGapCoreMs": round(max(core_gaps), 1) if core_gaps else None,
            "contentTopMove": round(max(tops) - min(tops), 2) if tops else None,
            "firstFrame": pairs[0][1]["frame"],
            "t0": t0,
        })
    # Landing of each stimulus (a segment that changes the value by more than 5 % of the full change): the value the
    # content rests at before the next stimulus, when it was first drawn (`landMs` from the segment's first moving frame:
    # ~450-500 for a 0.5 s animation; a final frame drawn late shows up here even when a recorder hole split it into a
    # segment of its own), and `lateStep`, how far the segment's last frame was from that rest.
    full = 60.0 if grow else 1.0
    stim = [i for i, g in enumerate(summary) if g["maxStep"] is not None and abs(g["to"] - g["from"]) > 0.05 * full]
    vals = [r for r in out if r["alpha"] is not None and r["t"] is not None]
    for k, i in enumerate(stim):
        g = summary[i]
        t_next = summary[stim[k + 1]]["t0"] if k + 1 < len(stim) else float("inf")
        before = [r for r in vals if g["t0"] <= r["t"] < t_next]
        if not before:
            continue
        rest = before[-1]["alpha"]
        land = next((r for j, r in enumerate(before) if all(abs(q["alpha"] - rest) <= a.min_change for q in before[j:])),
                    before[-1])
        g["landMs"] = round((land["t"] - g["t0"]) * 1000, 1)
        g["rest"] = round(rest, 3)
        g["lateStep"] = round(abs(rest - g["to"]), 3)
    for g in summary:
        g.pop("t0", None)
    res = {"rows": n, "rowsTo": m, "value": "row0HeightPt" if grow else "opacity", "segments": summary, "frames": len(out)}
    json.dump(res, open(os.path.join(a.dir, "rows.json"), "w"), indent=1)
    print(json.dumps(res))


if __name__ == "__main__":
    main()
