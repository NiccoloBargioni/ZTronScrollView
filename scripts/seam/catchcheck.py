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
  (dc - dctop) next to the centred look's (the spinner centred in the band up to L, held at L/2 past it:
  (min(band, L) step)/2 - (band step), which is -(band step)/2 below L; L = the indicator's length, 60 for hsys60, or
  ZS_CATCH_L) (the acceptance: within 1 pt, the spinner 20 pt on every frame);
- header (with <dir>/frames.csv + summary.json from analyze.py): the header / content seam from the catch to the end of
  the analyzer's segment holding it (the next rest): max |seam|, the frames with |seam| > 1 pt, and the largest
  gapExcess (an --open-gap run; the acceptance: <= 1 pt)."""
import os, subprocess, sys, json
from collections import Counter

src = sys.argv[1] if len(sys.argv) > 1 else "-"
L = float(os.environ.get("ZS_CATCH_L", "60"))
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
        entry["centred"] = round((min(b["band"], L) - min(a["band"], L)) / 2 - (b["band"] - a["band"]), 2)
    spin.append(entry)
out = {"rest": rest, "catchFrame": rows[catch]["f"], "bandBefore": round(pre, 2), "dip": round(dip, 2),
       "resetStep": round(resetStep, 2), "dropBeyondReset": round(beyond, 2), "steps": steps, "spinner": spin}
if src != "-" and os.path.exists(os.path.join(src, "frames.csv")) and os.path.exists(os.path.join(src, "summary.json")):
    import csv
    cf = rows[catch]["f"]
    end = None
    for seg in json.load(open(os.path.join(src, "summary.json"))).get("segments", []):
        a, b = seg["frames"]
        if a <= cf <= b: end = b
    if end is None: end = cf + 180
    seam, over, gx = [], [], []
    for r in csv.DictReader(open(os.path.join(src, "frames.csv"))):
        try: f = int(r["frame"])
        except (KeyError, ValueError): continue
        if f < cf or f > end: continue
        if r.get("seam"):
            v = float(r["seam"]); seam.append((f, v))
            if abs(v) > 1: over.append(f)
        if r.get("gapExcess"): gx.append(float(r["gapExcess"]))
    m = max(seam, key=lambda x: abs(x[1])) if seam else None
    out["header"] = {"from": cf, "to": end, "measured": len(seam), "maxAbsSeam": round(abs(m[1]), 2) if m else None,
                     "maxAt": m[0] if m else None, "over1": len(over), "overSpan": [over[0], over[-1]] if over else [],
                     "maxGapExcess": round(max(gx), 2) if gx else None}
print(json.dumps(out))
