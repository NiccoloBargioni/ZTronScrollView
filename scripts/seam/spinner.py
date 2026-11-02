#!/usr/bin/env python3
"""Where is the built-in refresh spinner drawn, against the content's top? (R1-RC1-1, header behaviors fixer round 2;
the lab's `hsys<H>` scenarios: `-ZTronSeamHold 1 -ZTronSeamHoldSystem <H>`, a `.system` indicator, L 60, holdOffset H)
usage: python3 -I scripts/seam/spinner.py <scenario-dir> [--csv]   (after analyze.py: reads rec.mov, meta.json, frames.csv)
Per app frame (frames.csv app == True): the spinner is what differs, row by row, between the centre column (+-16 pt) and
two reference columns 70 pt to each side (the lab's header, band, gap and content are horizontal stripes, so only the
centred indicator differs, by more than 20 in a channel; the spinner is the extent of those rows); the content's top is the first green row of the reference columns. Reports the drawn spinner
(top, bottom, height in pt), the band above the content (content top minus the content top of the first app frames, the
rest before the hold opens), frames drawn OVER the content (spinner rows more than 1 pt below its top), one-frame jumps
(the spinner's centre moves more than 4 pt plus 1.5 times the content's move, both frames drawing at least 4 pt of it)
and vanishings (from at least 15 pt drawn to at most 2 in one frame with a band of at least 20 pt). Prints JSON."""
import sys, csv, json, subprocess
import numpy as np
d = sys.argv[1]
meta = json.load(open(d + "/meta.json")); s = meta.get("scale", 3)
fr = {int(x["frame"]): x for x in csv.DictReader(open(d + "/frames.csv"))}
pr = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                         "stream=width,height", "-of", "json", d + "/rec.mov"]))
w, h = pr["streams"][0]["width"], pr["streams"][0]["height"]
p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", d + "/rec.mov", "-map", "0:v:0", "-fps_mode", "passthrough", "-f",
                      "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
cx = w // 2
half, off = 16 * s, 70 * s
rows = []
i = 0
while True:
    buf = p.stdout.read(w * h * 3)
    if len(buf) < w * h * 3: break
    f = fr.get(i, {})
    i += 1
    if f.get("app") != "True" or w > h: continue
    img = np.frombuffer(buf, np.uint8).reshape(h, w, 3).astype(np.int16)
    top = int(h * 0.06); bot = int(h * 0.8)          # below the status bar, above the lab's buttons
    centre = img[top:bot, cx - half:cx + half]
    refL = img[top:bot, cx - off - 4:cx - off + 4].mean(axis=1)
    refR = img[top:bot, cx + off - 4:cx + off + 4].mean(axis=1)
    ref = np.where((np.abs(refL - refR).max(axis=1) < 30)[:, None], (refL + refR) / 2, refL)
    diff = np.abs(centre - ref[:, None, :]).max(axis=2)          # rows x columns
    spin = (diff > 20).sum(axis=1) >= 2                           # a spinner row: 2+ differing pixels
    g = ref
    green = (g[:, 1] > 200) & (g[:, 0] < 80) & (g[:, 2] < 80)
    gy = np.nonzero(green)[0]
    ctop = (top + gy[0]) / s if len(gy) else None
    sy = np.nonzero(spin)[0]
    if len(sy):
        st, sb = (top + sy[0]) / s, (top + sy[-1] + 1) / s
        rows.append({"frame": i - 1, "t": float(f["t"]), "ctop": ctop, "stop": st, "sbot": sb, "n": sb - st})
    else:
        rows.append({"frame": i - 1, "t": float(f["t"]), "ctop": ctop, "stop": None, "sbot": None, "n": 0.0})
p.stdout.close(); p.wait()
rows = [r for r in rows if r["ctop"] is not None]
if not rows:
    print(json.dumps({"dir": d, "frames": 0})); sys.exit(0)
base = float(np.median([r["ctop"] for r in rows[:5]]))
over, jumps, vanish = [], [], []
for k, r in enumerate(rows):
    r["band"] = r["ctop"] - base
    r["drawn"] = r["n"]
    if r["n"] > 0 and r["sbot"] > r["ctop"] + 1: over.append(r["frame"])
    if k:
        q = rows[k - 1]
        if r["n"] >= 4 and q["n"] >= 4:
            dc = (r["stop"] + r["sbot"]) / 2 - (q["stop"] + q["sbot"]) / 2
            if abs(dc) > 4 + 1.5 * abs(r["ctop"] - q["ctop"]): jumps.append((q["frame"], r["frame"], round(dc, 2)))
        if q["n"] >= 15 and r["n"] <= 2 and r["band"] >= 20: vanish.append((q["frame"], r["frame"]))
if "--csv" in sys.argv:
    for r in rows:
        print(f'{r["frame"]},{r["t"]:.3f},{r["ctop"]:.2f},{r["band"]:.2f},{r["stop"] or ""},{r["sbot"] or ""},{r["n"]:.2f}')
    sys.exit(0)
held = [r for r in rows if r["band"] > 2]
rest = {}
if held:
    # the hold's rest: the most common band (rounded to 1 pt) among the frames with a band
    vals, cnt = np.unique(np.round([r["band"] for r in held]), return_counts=True)
    H = float(vals[np.argmax(cnt)])
    at = [r for r in held if abs(r["band"] - H) <= 1.0]
    rest = {"band": H, "frames": len(at), "drawnMedian": float(np.median([r["n"] for r in at])),
            "drawnMin": float(min(r["n"] for r in at)),
            "centreInBand": float(np.median([((r["stop"] + r["sbot"]) / 2 - base) if r["n"] else -1 for r in at]))}
print(json.dumps({"dir": d.rstrip("/").split("/")[-1], "frames": len(rows), "contentRest": round(base, 2), "rest": rest,
                  "overFrames": len(over), "over": over[:20], "jumps": jumps[:20], "vanish": vanish[:20],
                  "maxBand": round(max(r["band"] for r in rows), 2), "minBand": round(min(r["band"] for r in rows), 2)}))
