#!/usr/bin/env python3
"""Catch check (M8b-s8 s3, open item 33 / D79; open item 32 during a reset): a finger that catches the content while a
SwiftUI-animated refresh reset (`-ZTronSeamHoldReset <s>`, extra `hreset<s>`) draws it back to rest.
usage: python3 -I scripts/seam/catchcheck.py <scenario-dir>        (runs spinner.py --csv on it; after analyze.py)
       python3 -I scripts/seam/spinner.py <scenario-dir> --csv | python3 -I scripts/seam/catchcheck.py -
Rows (frame,t,ctop,band,stop,sbot,n): the band = the content's top minus its rest. The catch = the first frame after the
hold's retraction began (the band falling from its rest plateau) where the band rises by > 3 pt (the finger pulls the
content down). Reports:
- dip: the band 6 frames before that rise minus the lowest band of the 4 frames before it (a catch that drops SwiftUI's
  residual draws the content back up toward rest: a dip; the reset's own motion over those frames counts too);
- resetStep: the reset's own one-frame fall (median over the 10 frames before that window) and dropBeyondReset: the
  largest one-frame fall in [catch - 4, catch + 3] beyond it (the acceptance: <= 1 pt);
- steps: the one-frame band steps around the catch;
- spinner: per frame around the catch, the drawn spinner height (n) and its centre step against the content's
  (dc - dctop) next to the centred look's -(band step)/2 (the acceptance: within 1 pt, the spinner 20 pt on every frame)."""
import os, subprocess, sys, json
from collections import Counter

src = sys.argv[1] if len(sys.argv) > 1 else "-"
if src == "-":
    lines = sys.stdin.read().splitlines()
else:
    here = os.path.dirname(os.path.abspath(__file__))
    lines = subprocess.check_output([sys.executable, "-I", os.path.join(here, "spinner.py"), src, "--csv"],
                                    text=True).splitlines()
rows = []
for line in lines:
    p = line.strip().split(",")
    if len(p) < 7: continue
    f, t, ctop, band, st, sb, n = p
    try:
        rows.append(dict(f=int(f), t=float(t), ctop=float(ctop), band=float(band),
                         st=float(st) if st else None, sb=float(sb) if sb else None, n=float(n)))
    except ValueError:
        continue
held = [round(r["band"]) for r in rows if r["band"] > 20]
rest = Counter(held).most_common(1)[0][0] if held else None
catch, fell, atRest = None, False, 0
for k in range(1, len(rows)):
    b = rows[k]["band"]
    if rest is not None and abs(b - rest) <= 1: atRest += 1
    if rest is not None and atRest >= 10 and b < rest - 3: fell = True
    if fell and rows[k]["band"] - rows[k - 1]["band"] > 3:
        catch = k; break
if catch is None:
    print(json.dumps({"rest": rest, "catch": None})); sys.exit(0)
pre = rows[max(0, catch - 6)]["band"]
win = rows[max(0, catch - 4):catch + 1]
dip = pre - min(r["band"] for r in win)
falls = [rows[k - 1]["band"] - rows[k]["band"] for k in range(max(1, catch - 14), max(1, catch - 4))]
falls.sort()
resetStep = falls[len(falls) // 2] if falls else 0.0
beyond = max([rows[k - 1]["band"] - rows[k]["band"] - resetStep
              for k in range(max(1, catch - 4), min(len(rows), catch + 4))] or [0.0])
steps = [(rows[k]["f"], round(rows[k]["band"] - rows[k - 1]["band"], 2))
         for k in range(max(1, catch - 4), min(len(rows), catch + 4))]
spin = []
for k in range(max(1, catch - 4), min(len(rows), catch + 6)):
    a, b = rows[k - 1], rows[k]
    entry = {"f": b["f"], "n": round(b["n"], 1)}
    if a["n"] >= 4 and b["n"] >= 4:
        dc = (b["st"] + b["sb"]) / 2 - (a["st"] + a["sb"]) / 2
        entry["vsContent"] = round(dc - (b["ctop"] - a["ctop"]), 2)
        entry["centred"] = round(-(b["band"] - a["band"]) / 2, 2)
    spin.append(entry)
print(json.dumps({"rest": rest, "catchFrame": rows[catch]["f"], "bandBefore": round(pre, 2), "dip": round(dip, 2),
                  "resetStep": round(resetStep, 2), "dropBeyondReset": round(beyond, 2), "steps": steps,
                  "spinner": spin}))
