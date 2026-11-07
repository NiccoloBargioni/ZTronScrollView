#!/usr/bin/env python3
"""i28 mix: per PNG, the red header's rows at x = 40 px and its columns at its middle row, the first content (green) row
below it (seam = green top - red bottom - 1, px), and the black text box (px). usage: mixan.py a.png ..."""
import sys
import numpy as np
from PIL import Image


def runs(mask):
    ys = np.where(mask)[0]
    if len(ys) == 0:
        return None
    best, s, prev = None, ys[0], ys[0]
    for v in list(ys[1:]) + [None]:
        if v is None or v != prev + 1:
            if best is None or prev - s > best[1] - best[0]:
                best = (s, prev)
            s = v
        prev = v if v is not None else prev
    return best


for p in sys.argv[1:]:
    a = np.asarray(Image.open(p).convert("RGB")).astype(int)
    red = (a[:, :, 0] > 200) & (a[:, :, 1] < 70) & (a[:, :, 2] < 70)
    green = (a[:, :, 1] > 200) & (a[:, :, 0] < 70) & (a[:, :, 2] < 70)
    r = runs(red[:, 40])
    if r is None:
        print("%-28s no red" % p.split("/")[-1]); continue
    top, bot = r
    g = np.where(green[bot + 1:, 40])[0]
    gtop = bot + 1 + g[0] if len(g) else -1
    mid = (top + bot) // 2
    cx = runs(red[mid, :])
    blk = (a[top:bot + 1, :, 0] < 90) & (a[top:bot + 1, :, 1] < 90) & (a[top:bot + 1, :, 2] < 90)
    yy, xx = np.where(blk)
    box = "%dx%d @(%d,%d)" % (xx.max() - xx.min() + 1, yy.max() - yy.min() + 1, xx.min(), yy.min() + top) if len(xx) else "-"
    print("%-28s red rows %4d-%4d cols %4d-%4d green %4d seam %+d  text %s" % (
        p.split("/")[-1], top, bot, cx[0], cx[1], gtop, gtop - bot - 1 if gtop >= 0 else 0, box))
