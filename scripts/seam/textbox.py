#!/usr/bin/env python3
"""i28: per-frame text box of the seam lab's header text in a screen recording (the D76 switch gate).
usage: python3 -I textbox.py rec.mov [--x 40] [--from t0] [--to t1] [--held]
Per decoded frame (ffmpeg rawvideo, pts from ffprobe): the red header's rows at column x, the black text box inside it
(width x height px) and the first green row below the header (seam px). Prints the series and a summary: the total
change of the box width, the largest single-frame change as a fraction of it (a step >= 0.5 fails), whether the series is
monotone (within 2 px of h264 noise), and the header rows' / seam's range (they must not move)."""
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


def run(mask):
    ys = np.where(mask)[0]
    if len(ys) == 0:
        return None
    splits = np.where(np.diff(ys) != 1)[0]
    starts = np.concatenate(([ys[0]], ys[splits + 1]))
    ends = np.concatenate((ys[splits], [ys[-1]]))
    k = int(np.argmax(ends - starts))
    return int(starts[k]), int(ends[k])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--x", type=int, default=40)
    ap.add_argument("--from", dest="t_from", type=float, default=None, help="ignore frames before this time (s)")
    ap.add_argument("--to", dest="t_to", type=float, default=None,
                    help="ignore frames after this time (s): 17.5 recordings show the home screen's red before launch and after exit")
    ap.add_argument("--held", action="store_true",
                    help="only frames whose header bottom is within 1 px of the recording's lowest (a hold's steady frame)")
    a = ap.parse_args()
    rows = []
    for t, f in frames(a.video):
        red = (f[:, :, 0] > 180) & (f[:, :, 1] < 90) & (f[:, :, 2] < 90)
        r = run(red[:, a.x])
        if r is None:
            continue
        top, bot = r
        green = (f[bot + 1:, a.x, 1] > 180) & (f[bot + 1:, a.x, 0] < 90) & (f[bot + 1:, a.x, 2] < 90)
        g = np.where(green)[0]
        blk = (f[top:bot + 1, :, :].max(axis=2) < 90)
        yy, xx = np.where(blk)
        if len(xx) < 50:
            continue
        rows.append((t, top, bot, int(g[0]) if len(g) else -1, int(xx.max() - xx.min() + 1), int(yy.max() - yy.min() + 1)))
    if a.t_from is not None:
        rows = [r for r in rows if r[0] >= a.t_from]
    if a.t_to is not None:
        rows = [r for r in rows if r[0] <= a.t_to]
    if a.held and rows:
        lowest = max(r[2] for r in rows)
        rows = [r for r in rows if r[2] >= lowest - 1]
        # from the last frame at the first plateau value to the first frame at the final one: the change itself
        w0, w1 = rows[0][4], rows[-1][4]
        i0 = max(i for i, r in enumerate(rows) if abs(r[4] - w0) <= 2 and all(abs(q[4] - w0) <= 2 for q in rows[:i + 1]))
        i1 = min(i for i, r in enumerate(rows) if all(abs(q[4] - w1) <= 2 for q in rows[i:]))
        rows = rows[i0:i1 + 1]
    for r in rows:
        print("t %.3f rows %d-%d seam %d box %dx%d" % r)
    w = [r[4] for r in rows]
    total = w[-1] - w[0]
    steps = [abs(w[i + 1] - w[i]) for i in range(len(w) - 1)]
    sign = np.sign(total) if total else 0
    mono = all((w[i + 1] - w[i]) * sign >= -2 for i in range(len(w) - 1))
    print("summary: frames %d, box width %d -> %d (change %d), max step %d (%.2f of the change), monotone %s, "
          "header top %d-%d, bottom %d-%d, seam %d..%d px" % (
              len(rows), w[0], w[-1], total, max(steps) if steps else 0,
              (max(steps) / abs(total)) if total else 0, mono, min(r[1] for r in rows), max(r[1] for r in rows),
              min(r[2] for r in rows), max(r[2] for r in rows), min(r[3] for r in rows), max(r[3] for r in rows)))


if __name__ == "__main__":
    main()
