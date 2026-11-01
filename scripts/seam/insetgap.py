#!/usr/bin/env python3
"""Fix round 2 of M8b-s6: a bottom refresh hold (`-ZTronSeamHold 1 -ZTronSeamHoldEdge bottom`, no header) while the seam lab
toggles a 150 pt bottom `.safeAreaInset` in `withAnimation` (`kbfake`), against the scroll view's DRAWN bottom: the lab's
buttons' bottom + 4 pt (they sit 4 pt above the frame's bottom, in the frame SwiftUI animates). The probe is the white
20 pt square on the vertical line x = 201 pt.

usage: python3 -I insetgap.py <scenario-dir> gap|overlay
  gap      the hold in the gap stays on the content's edge (which does not move) and is drawn exactly as far as the
           frame's drawn bottom reaches over its rest place: |drawn - clamp(bottom - restTop, 0, 20)| and the drawn top's
           offset from rest, per frame;
  overlay  it floats its rest distance before the frame's drawn bottom: |(bottom - centre) - rest|.
Judged from 3 frames before the first moving frame to 12 after the last (both directions). Prints JSON: judged, moving,
bad (error > 1 pt), worst (pt), the bad frames, maxMovingDt (the largest frame interval while the frame moves: a gap there
hides motion, re-record). c5ffc4a: gap 26 bad on 27.0 / forced / 17.5 (the probe vanished on the first frame); 27bc80f: 0.
"""
import csv, json, os, subprocess, sys
import numpy as np
d, kind = sys.argv[1], sys.argv[2]
lo, hi = 0, 10**9
INSET = 150.0   # -ZTronSeamFakeKeyboard 150 (baseline.sh `kbfake`)
v = os.path.join(d, "rec.mov")
rows = {int(r["frame"]): r for r in csv.DictReader(open(os.path.join(d, "frames.csv")))}
info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                                  "-of", "json", v], capture_output=True, text=True).stdout)["streams"][0]
W, H = info["width"], info["height"]; sc = 3
p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", v, "-map", "0:v:0", "-fps_mode", "passthrough", "-f", "rawvideo",
                      "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
n = W * H * 3; i = 0; out = []
while True:
    b = p.stdout.read(n)
    if len(b) < n or i > hi: break
    if i >= lo:
        f = np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(int)
        white = f.min(axis=2) > 235
        by = np.nonzero(white[:, int(330 * sc)])[0]
        geo = (by.max() + 1) / sc + 4 if len(by) else None
        py = np.nonzero(white[:, int(201 * sc)])[0]; py = py[py > 60 * sc]
        pr = (py.min() / sc, (py.max() + 1) / sc) if len(py) else None
        out.append((i, float(rows.get(i, {}).get("t", "nan") or "nan"), geo, pr))
    i += 1
p.kill()
# the lab's resting frame bottom (the most common geo while the hold rests), the change's frames (off both rests)
from collections import Counter
gs = [round(g * 3) / 3 for _, _, g, pr in out if g is not None and pr and pr[0] > 400 and g > 600]
g0 = Counter(gs).most_common(1)[0][0]
start = next(k for k, (_, _, g, pr) in enumerate(out) if g is not None and abs(g - g0) < 0.5 and pr and pr[0] > 400)
mov = [k for k, (_, _, g, _) in enumerate(out) if k > start and g is not None and g > 600 - INSET
       and abs(g - g0) > 0.5 and abs(g - (g0 - INSET)) > 0.5]
if not mov: print(json.dumps({"error": "no change"})); sys.exit()
first, last = mov[0], mov[-1]
rest = [pr for _, _, g, pr in out[max(0, first - 20):first] if g is not None and abs(g - g0) < 0.5 and pr][-3:]
if not rest: print(json.dumps({"error": "no rest probe"})); sys.exit()
rmin, rmax = np.median([r[0] for r in rest]), np.median([r[1] for r in rest])
restDist = g0 - (rmin + rmax) / 2
out = out[max(0, first - 3):last + 13]
bad, judged, moving, worst = [], 0, 0, 0.0
for i, t, g, pr in out:
    if g is None or g < g0 - INSET - 1 or g > g0 + 1: continue
    if abs(g - g0) > 0.5 and abs(g - (g0 - INSET)) > 0.5: moving += 1
    if kind == "gap":
        exp = max(0.0, min(20.0, g - rmin))
        shown = 0.0 if pr is None else max(0.0, pr[1] - pr[0])
        err = abs(shown - exp)
        if pr is not None and shown > 0.5: err = max(err, abs(pr[0] - rmin))
    else:
        if pr is None: err = 99.0
        else: err = abs((g - (pr[0] + pr[1]) / 2) - restDist)
    judged += 1
    worst = max(worst, err)
    if err > 1: bad.append((i, round(g, 2), pr and (round(pr[0], 2), round(pr[1], 2)), round(err, 2)))
# the largest frame interval while the frame is moving (a still period between the two changes records no frames)
mv = [(out[k + 1][1] - out[k][1], out[k][0]) for k in range(len(out) - 1)
      if out[k][2] is not None and out[k + 1][2] is not None and abs(out[k + 1][2] - out[k][2]) > 0.3
      and abs(out[k][2] - g0) > 0.5 and abs(out[k][2] - (g0 - INSET)) > 0.5]
maxGap = max(mv) if mv else None
print(json.dumps({"maxMovingDt": maxGap, "frames": [first, last], "dir": os.path.basename(d), "kind": kind, "g0": g0, "rest": [rmin, rmax], "restDist": restDist,
                  "judged": judged, "moving": moving, "bad": len(bad), "worst": round(worst, 2), "badFrames": bad[:80]}))
