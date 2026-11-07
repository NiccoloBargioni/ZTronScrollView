#!/usr/bin/env python3
"""i28 R2 (M8b-s8 s7, D76): per-frame x of the seam lab's ruler marks (`-ZTronSeamRuler 1`, baseline.sh `ruler`) in a
screen recording: the header's six white bars (header y 20 + 40 i, 2 + 2 i pt tall, x 5-45 % of the header's LAID-OUT
width). Under `.keepTextSize` the header is laid out `W * s` wide, so the bars' x follow the grown layout: a layout that
lands in one frame (a measurement after the layout, a resize commit that re-sets the header) shows as a step in x.
usage: python3 -I rulerx.py rec.mov [--from t0] [--to t1] [--bar k] [--x -40]
Per decoded frame (ffmpeg rawvideo, pts from ffprobe): the red header's rows at column --x, then inside them the white
runs (R, G, B > 200) of each bar row: the bar's left and right edge (px). --bar picks the bar (0-5, default: the lowest
bar visible in every frame). Prints the series and a summary per edge: the total change, the largest single-frame change
as a fraction of it (a step >= 0.5 fails; a change < 6 px has no fraction) and whether the series is monotone (2 px of
h264 noise)."""
import argparse
import json
import subprocess
import numpy as np


def frames(path):
    info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                               "stream=width,height", "-of", "json", path]))["streams"][0]
    w, h = info["width"], info["height"]
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                   "frame=best_effort_timestamp_time", "-of", "csv=p=0", path]).decode()
    pts = [l.strip().strip(",") for l in out.splitlines() if l.strip().strip(",")]
    proc = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", path, "-map", "0:v:0", "-fps_mode", "passthrough",
                             "-enc_time_base", "demux", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
                            stdout=subprocess.PIPE)
    i = 0
    while True:
        buf = proc.stdout.read(w * h * 3)
        if len(buf) < w * h * 3:
            break
        yield (float(pts[i]) if i < len(pts) else float("nan")), np.frombuffer(buf, np.uint8).reshape(h, w, 3).astype(int)
        i += 1


def runs(mask):
    """[(start, end)] of the True runs of a 1-D mask."""
    ys = np.where(mask)[0]
    if len(ys) == 0:
        return []
    splits = np.where(np.diff(ys) != 1)[0]
    starts = np.concatenate(([ys[0]], ys[splits + 1]))
    ends = np.concatenate((ys[splits], [ys[-1]]))
    return list(zip(starts.tolist(), ends.tolist()))


def bars(f, x):
    """The header rows and the bars inside it: [(y0, y1, x0, x1)] top to bottom (white runs of rows, then columns)."""
    red = (f[:, :, 0] > 180) & (f[:, :, 1] < 90) & (f[:, :, 2] < 90)
    rr = runs(red[:, x])
    if not rr:
        return None, []
    top, bot = max(rr, key=lambda r: r[1] - r[0])
    white = (f[top:bot + 1, :, :].min(axis=2) > 200)
    rows = white.sum(axis=1) > 20
    out = []
    for y0, y1 in runs(rows):
        cols = white[y0:y1 + 1, :].any(axis=0)
        cr = runs(cols)
        if not cr:
            continue
        x0, x1 = max(cr, key=lambda c: c[1] - c[0])
        out.append((top + y0, top + y1, x0, x1))
    return (top, bot), out


def summary(name, v):
    total = v[-1] - v[0]
    steps = [abs(v[i + 1] - v[i]) for i in range(len(v) - 1)]
    sign = np.sign(total) if total else 0
    mono = all((v[i + 1] - v[i]) * sign >= -2 for i in range(len(v) - 1)) if sign else max(v) - min(v) <= 2
    frac = (max(steps) / abs(total)) if steps and abs(total) >= 6 else 0.0
    print("%s: %d -> %d (change %d), max step %d (%.2f of the change), range %d..%d, monotone %s" % (
        name, v[0], v[-1], total, max(steps) if steps else 0, frac, min(v), max(v), mono))
    return frac


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--x", type=int, default=-40,
                    help="the column the red header is found at (negative: from the right edge; the default -40 stays clear "
                         "of the bars, which overhang the left edge under .keepTextSize; portrait recordings only)")
    ap.add_argument("--from", dest="t_from", type=float, default=None)
    ap.add_argument("--to", dest="t_to", type=float, default=None)
    ap.add_argument("--bar", type=int, default=None, help="0-5 from the top (default: the lowest bar in every frame)")
    a = ap.parse_args()
    series = []
    for t, f in frames(a.video):
        if (a.t_from is not None and t < a.t_from) or (a.t_to is not None and t > a.t_to):
            continue
        hdr, b = bars(f, a.x if a.x >= 0 else f.shape[1] + a.x)
        if hdr is None or not b:
            continue
        series.append((t, hdr, b))
    if not series:
        print("no ruler bars found")
        return
    k = a.bar if a.bar is not None else min(len(s[2]) for s in series) - 1
    rows = [(t, hdr, b[k]) for t, hdr, b in series if len(b) > k]
    for t, (top, bot), (y0, y1, x0, x1) in rows:
        print("t %.3f header %d-%d bar %d y %d-%d x %d-%d" % (t, top, bot, k, y0, y1, x0, x1))
    print("summary: frames %d, bar %d" % (len(rows), k))
    worst = max(summary("left x", [r[2][2] for r in rows]), summary("right x", [r[2][3] for r in rows]),
                summary("bar top y", [r[2][0] for r in rows]))
    print("RESULT %s (largest step %.2f of its change)" % ("PASS" if worst < 0.5 else "FAIL", worst))


if __name__ == "__main__":
    main()
