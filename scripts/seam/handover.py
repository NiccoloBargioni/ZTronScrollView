#!/usr/bin/env python3
"""The built-in refresh indicator against the `.stretch` band, frame by frame (M8b-s8 s1, open items 31 and 32).
usage: python3 -I scripts/seam/handover.py <scenario-dir> [--trigger T] [--length L] [--old] [--csv]
       (after analyze.py: reads rec.mov, meta.json, frames.csv)

Per app frame (portrait), as scripts/seam/spinner.py: the content's top (the first green row of two reference columns 70 pt
left and right of the centre), the band above it (the content's top minus its rest), the indicator's drawn rows in the
centre column (+-16 pt; rows where 2+ pixels differ from the reference by more than 20) and, new here, its INTENSITY: the
mean of the 20 largest channel differences inside those rows above the content (a glyph drawn at opacity o differs from
what is behind it by o times its full difference, so the intensity follows the placement's opacity; the arrow, the ring
and the spinner each have their own full value).

With a trigger (`--trigger T`, else `-ZTronSeamRefreshTrigger` from meta.json when the scenario pulls: default 60) it judges
item 31 on a pull: the trigger frame is the first one with band >= T; every frame's drawn centre (the middle of the drawn
rows, from the band's start) is compared with the one the handover predicts from the drawn band s (L the indicator's 60 pt,
p = max(0, s), dragPosition = min(1, p / T)): before the trigger min(s, L) - L/2 + max(0, L * dragPosition - p) / 2, from it
on min(s, L) / 2 (`--old`: HEAD's slide-in look, min(s, L) - L/2, before it), drawn as far as the band shows it: the
glyph's height h (the median drawn height of the frames that show all of it) clipped to [0, s].
Reports (JSON): `residual` = the largest |(change of the drawn centre) - (change of the predicted one)| between two
consecutive frames of the pull (band rising, both frames drawing 4+ pt), `atTrigger` the same at the trigger frame, `half`
= the largest |drawn centre - min(s, L)/2| from the trigger on while all of the glyph shows, the intensity series around the
trigger and `rampStep` = the largest one-frame intensity rise before (and at) the trigger as a fraction of the rise from
the first drawn frame to the trigger frame.
Always: `steps` = the largest one-frame intensity fall between two frames that both draw 4+ pt, as a fraction of the
first frame's intensity, with its frame (the `.default` band end of item 32's sibling; the re-grab of item 32), and
`--csv` prints frame, t, band, top, bottom, drawn, centre, intensity per frame instead."""
import sys, csv, json, subprocess
import numpy as np

args = sys.argv[1:]
d = args[0]
def opt(name, default=None):
    if name in args:
        i = args.index(name)
        return args[i + 1] if i + 1 < len(args) else default
    return default
meta = json.load(open(d + "/meta.json")); s = meta.get("scale", 3)
launch = meta.get("launchArgs", [])
def launch_arg(name):
    return launch[launch.index(name) + 1] if name in launch and launch.index(name) + 1 < len(launch) else None
L = float(opt("--length", 60))
T = opt("--trigger")
if T is None and meta.get("test") == "pull" and launch_arg("-ZTronSeamRefresh") is not None:
    T = launch_arg("-ZTronSeamRefreshTrigger") or "60"
T = float(T) if T is not None else None
old = "--old" in args

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
    top = int(h * 0.06); bot = int(h * 0.8)
    centre = img[top:bot, cx - half:cx + half]
    refL = img[top:bot, cx - off - 4:cx - off + 4].mean(axis=1)
    refR = img[top:bot, cx + off - 4:cx + off + 4].mean(axis=1)
    ref = np.where((np.abs(refL - refR).max(axis=1) < 30)[:, None], (refL + refR) / 2, refL)
    diff = np.abs(centre - ref[:, None, :]).max(axis=2)
    spin = (diff > 20).sum(axis=1) >= 2
    green = (ref[:, 1] > 200) & (ref[:, 0] < 80) & (ref[:, 2] < 80)
    gy = np.nonzero(green)[0]
    ctop = (top + gy[0]) / s if len(gy) else None
    sy = np.nonzero(spin)[0]
    r = {"frame": i - 1, "t": float(f["t"]), "ctop": ctop, "stop": None, "sbot": None, "n": 0.0, "I": 0.0}
    if len(sy):
        r["stop"], r["sbot"] = (top + sy[0]) / s, (top + sy[-1] + 1) / s
        r["n"] = r["sbot"] - r["stop"]
        lim = len(diff) if ctop is None else max(0, int(round(ctop * s)) - top)
        band = diff[sy[0]:min(sy[-1] + 1, lim)]
        if band.size:
            r["I"] = float(np.sort(band.ravel())[-20:].mean())
    rows.append(r)
p.stdout.close(); p.wait()
rows = [r for r in rows if r["ctop"] is not None]
if not rows:
    print(json.dumps({"dir": d, "frames": 0})); sys.exit(0)
base = float(np.median([r["ctop"] for r in rows[:5]]))
for r in rows:
    r["band"] = r["ctop"] - base
    r["c"] = ((r["stop"] + r["sbot"]) / 2 - base) if r["n"] > 0 else None

if "--csv" in args:
    for r in rows:
        print(f'{r["frame"]},{r["t"]:.3f},{r["band"]:.2f},{r["stop"] or ""},{r["sbot"] or ""},{r["n"]:.2f},'
              f'{"" if r["c"] is None else round(r["c"], 2)},{r["I"]:.1f}')
    sys.exit(0)

out = {"dir": d.rstrip("/").split("/")[-1], "frames": len(rows), "contentRest": round(base, 2),
       "maxBand": round(max(r["band"] for r in rows), 2)}

# Intensity falls between two drawn frames (the `.default` band end, a re-grab).
worst = None
for a, b in zip(rows, rows[1:]):
    if a["n"] >= 4 and b["n"] >= 4 and a["I"] > 0:
        fall = (a["I"] - b["I"]) / a["I"]
        if worst is None or fall > worst[0]:
            worst = (fall, a["frame"], b["frame"], round(a["I"], 1), round(b["I"], 1), round(a["band"], 2), round(b["band"], 2))
if worst:
    out["steps"] = {"fall": round(worst[0], 3), "frames": [worst[1], worst[2]], "I": [worst[3], worst[4]],
                    "band": [worst[5], worst[6]]}

if T is not None:
    # The pull: from the first frame with a band to the band's highest frame (the release comes later).
    k0 = next((k for k, r in enumerate(rows) if r["band"] > 1), None)
    kmax = max(range(len(rows)), key=lambda k: rows[k]["band"])
    kT = next((k for k in range(k0 or 0, kmax + 1) if rows[k]["band"] >= T), None) if k0 is not None else None
    out["trigger"] = T
    if k0 is not None and kT is not None:
        def centre(sv, refreshing):
            pp = max(0.0, sv)
            if refreshing: return min(sv, L) / 2
            if old: return min(sv, L) - L / 2
            dp = min(1.0, pp / T) if T > 0 else 1.0
            return min(sv, L) - L / 2 + max(0.0, L * dp - pp) / 2
        full_pull = [r["n"] for r in rows[k0:kT] if r["n"] > 0 and r["band"] >= L]
        full_ref = [r["n"] for r in rows[kT:kmax + 1] if r["n"] > 0 and r["band"] >= 2 * 20]
        hp = float(np.median(full_pull)) if full_pull else 17.0
        hr = float(np.median(full_ref)) if full_ref else 20.0
        def drawn(sv, refreshing):
            c = centre(sv, refreshing); hh = hr if refreshing else hp
            a, b = max(c - hh / 2, 0.0), min(c + hh / 2, sv)
            return (a + b) / 2 if b > a else None
        series, res, half_err = [], [], []
        prev = None
        for k in range(k0, kmax + 1):
            r = rows[k]
            pc = drawn(r["band"], k >= kT)
            item = {"frame": r["frame"], "band": round(r["band"], 2), "drawn": round(r["n"], 2),
                    "c": None if r["c"] is None else round(r["c"], 2), "pred": None if pc is None else round(pc, 2),
                    "I": round(r["I"], 1)}
            series.append(item)
            if prev is not None and r["n"] >= 4 and prev[0]["n"] >= 4 and pc is not None and prev[1] is not None:
                dd = (r["c"] - prev[0]["c"]) - (pc - prev[1])
                res.append((abs(dd), prev[0]["frame"], r["frame"], round(dd, 2)))
            if k >= kT and r["n"] > 0 and r["band"] >= hr + 1:
                half_err.append((abs(r["c"] - min(r["band"], L) / 2), r["frame"]))
            prev = (r, pc)
        out["glyph"] = {"pull": round(hp, 2), "refreshing": round(hr, 2)}
        out["triggerFrame"] = rows[kT]["frame"]
        if res:
            m = max(res)
            out["residual"] = {"max": round(m[0], 2), "frames": [m[1], m[2]], "signed": m[3]}
            at = [x for x in res if x[2] == rows[kT]["frame"]]
            if at: out["atTrigger"] = {"residual": at[0][3]}
        if half_err:
            m = max(half_err)
            out["half"] = {"max": round(m[0], 2), "frame": m[1]}
        # The intensity's rise up to the trigger.
        ramp = [r for r in rows[k0:kT + 1] if r["n"] > 0]
        if len(ramp) >= 2:
            total = ramp[-1]["I"] - ramp[0]["I"]
            rises = [(b["I"] - a["I"], b["frame"]) for a, b in zip(ramp, ramp[1:])]
            mr = max(rises)
            out["ramp"] = {"from": round(ramp[0]["I"], 1), "toTrigger": round(ramp[-1]["I"], 1),
                           "maxRise": round(mr[0], 1), "at": mr[1],
                           "rampStep": round(mr[0] / total, 3) if total > 0 else None}
        j0 = max(0, kT - k0 - 6)
        out["aroundTrigger"] = series[j0:j0 + 14]

# Item 32 (test `regrab`, or `--regrab`): after the first release (the band leaves its highest value) the spinner goes back
# with the content, is grabbed again (the band rises once more) and goes back again. The spinner's look and placement are
# kept all the way: the refreshing glyph (h = 20 pt) centred in the band, drawn min(band, h). Reports the re-grab (the first
# frame whose band rises again by more than 0.5 pt), `vanish` (frames with a band of 4+ pt and at most 1 pt drawn),
# `shortfall` (the largest min(band, h) - drawn over frames with a band of 2+ pt), `centre` (the largest
# |drawn centre - min(band, L)/2| over frames drawing 4+ pt) and `minDrawnFrom20` (the least drawn while the band is 20+).
if meta.get("test") == "regrab" or "--regrab" in args:
    kmax = max(range(len(rows)), key=lambda k: rows[k]["band"])
    top = rows[kmax]["band"]
    k1 = next((k for k in range(kmax, len(rows)) if rows[k]["band"] < top - 1), None)
    g = {"release": None}
    if k1 is not None:
        g["release"] = rows[k1]["frame"]
        kr = next((k for k in range(k1 + 1, len(rows)) if rows[k]["band"] > rows[k - 1]["band"] + 0.5), None)
        if kr is not None:
            g["regrab"] = {"frame": rows[kr]["frame"], "band": round(rows[kr - 1]["band"], 2),
                           "drawn": round(rows[kr - 1]["n"], 2)}
        hh = 20.0
        win = [r for r in rows[k1:] if r["band"] >= 2]
        van = [r["frame"] for r in win if r["band"] >= 4 and r["n"] <= 1]
        g["vanish"] = {"frames": len(van), "first": van[0] if van else None}
        sf = max(((min(r["band"], hh) - r["n"], r["frame"], round(r["band"], 2)) for r in win), default=None)
        if sf: g["shortfall"] = {"max": round(sf[0], 2), "frame": sf[1], "band": sf[2]}
        ce = max(((abs(r["c"] - min(r["band"], L) / 2), r["frame"]) for r in win if r["n"] >= 4), default=None)
        if ce: g["centre"] = {"max": round(ce[0], 2), "frame": ce[1]}
        m20 = [r["n"] for r in win if r["band"] >= 21]
        g["minDrawnFrom20"] = round(min(m20), 2) if m20 else None
        g["maxBandAfterRegrab"] = round(max((r["band"] for r in rows[kr:]), default=0), 2) if kr is not None else None
    out["regrab"] = g
print(json.dumps(out))
