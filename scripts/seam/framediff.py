#!/usr/bin/env python3
"""i28: bounding boxes of what changed between consecutive recorded frames. usage: framediff.py <dir with NNNNNN.png + ts.txt> t0 t1"""
import os, sys
import numpy as np
from PIL import Image
d, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
files = sorted((f for f in os.listdir(d) if f.endswith(".png")), key=lambda f: int(f[:-4]))
ts = sorted(float(x) for x in open(os.path.join(d, "ts.txt")) if x.strip())
prev = None
for f, t in zip(files, ts):
    if t < t0 - 0.2 or t > t1:
        continue
    a = np.asarray(Image.open(os.path.join(d, f)).convert("RGB")).astype(np.int16)
    if prev is not None and t >= t0:
        diff = np.abs(a - prev).max(axis=2)
        ys, xs = np.where(diff > 24)
        if len(ys):
            # split into the status bar (y < 150) and the rest
            sb = ys < 150
            def box(m):
                if not m.any(): return "-"
                return "x %d-%d y %d-%d n %d" % (xs[m].min(), xs[m].max(), ys[m].min(), ys[m].max(), m.sum())
            print("t %.3f  statusbar[%s]  rest[%s]" % (t, box(sb), box(~sb)))
        else:
            print("t %.3f  no change > 24 (max %d)" % (t, diff.max()))
    prev = a
