#!/usr/bin/env python3
"""The built-in refresh indicator against the `.stretch` band, frame by frame (M8b-s8 s1, open items 31 and 32).
usage: python3 -I scripts/seam/handover.py <scenario-dir> [--trigger T] [--length L] [--old] [--glyph <T>=L-pull-dir] [--csv]
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
glyph's height h (the median drawn height of the frames that show all of it) clipped to [0, s]; with `--glyph <dir>` (a
pull with T >= L on the same lane, e.g. `…-pull-refresh-rtrig100`) the turning arrow's rows per angle instead of h.
From the trigger on the arrow (turned 180 degrees) and the spinner cross-fade in 0.15 s at the refreshing look's place
(open item 41), starting where the arrow's intensity first falls below 0.9 of its value at the trigger: the frames before
that start draw the arrow alone (`look` "arrow", its full-turn rows at the place), the frames after the 0.15 s the spinner
alone ("spinner"), the fade's frames both at partial opacity ("mixed": which of the spinner's rows show depends on its
spokes, so their drawn centre is no placement; `xfade.edge` = the largest distance of a drawn edge outside the two glyphs'
predicted edges instead).
Reports (JSON): `residual` = the largest |(change of the drawn centre) - (change of the predicted one)| between two
consecutive frames of the pull and of the refreshing look (band rising, both frames drawing 4+ pt, neither "mixed"),
`atTrigger` the same at the trigger frame, `half` = the largest |drawn centre - the glyph's own offset - min(s, L)/2| from
the trigger on while all of the glyph shows (not "mixed"), `xfade` (start, frames after the trigger, mixed frames, edge),
the intensity series around the trigger and `rampStep` = the largest one-frame intensity rise before (and at) the trigger
as a fraction of the rise from the first drawn frame to the trigger frame.
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

def extract(dd):
    """The app frames of a scenario: [{frame, t, band, stop, sbot, n, c, I}] (band and c from the content's rest)."""
    sc = json.load(open(dd + "/meta.json")).get("scale", 3)
    fr = {int(x["frame"]): x for x in csv.DictReader(open(dd + "/frames.csv"))}
    pr = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                             "stream=width,height", "-of", "json", dd + "/rec.mov"]))
    w, h = pr["streams"][0]["width"], pr["streams"][0]["height"]
    p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", dd + "/rec.mov", "-map", "0:v:0", "-fps_mode", "passthrough", "-f",
                          "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
    cx = w // 2
    half, off = 16 * sc, 70 * sc
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
        ctop = (top + gy[0]) / sc if len(gy) else None
        sy = np.nonzero(spin)[0]
        r = {"frame": i - 1, "t": float(f["t"]), "ctop": ctop, "stop": None, "sbot": None, "n": 0.0, "I": 0.0}
        if len(sy):
            r["stop"], r["sbot"] = (top + sy[0]) / sc, (top + sy[-1] + 1) / sc
            r["n"] = r["sbot"] - r["stop"]
            lim = len(diff) if ctop is None else max(0, int(round(ctop * sc)) - top)
            band = diff[sy[0]:min(sy[-1] + 1, lim)]
            if band.size:
                r["I"] = float(np.sort(band.ravel())[-20:].mean())
        rows.append(r)
    p.stdout.close(); p.wait()
    rows = [r for r in rows if r["ctop"] is not None]
    if not rows: return rows, None
    base = float(np.median([r["ctop"] for r in rows[:5]]))
    for r in rows:
        r["band"] = r["ctop"] - base
        r["c"] = ((r["stop"] + r["sbot"]) / 2 - base) if r["n"] > 0 else None
    return rows, base

rows, base = extract(d)
if not rows:
    print(json.dumps({"dir": d, "frames": 0})); sys.exit(0)

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
        # `--glyph <dir>`: the pull's arrow turns with the pull (dragPosition * 180 degrees), so its drawn rows are not a
        # fixed h around its place (16 pt upright, 12-13 pt across). A pull with T >= L on the same lane (its place is
        # HEAD's min(s, L) - L/2 there) gives the rows' offsets from the place per angle, from its frames that draw all
        # of the arrow (2 px inside the band's ends); the prediction then uses the offsets at the frame's angle.
        cal = None
        if opt("--glyph"):
            cd = opt("--glyph")
            cla = json.load(open(cd + "/meta.json")).get("launchArgs", [])
            Tc = float(cla[cla.index("-ZTronSeamRefreshTrigger") + 1]) if "-ZTronSeamRefreshTrigger" in cla else 60.0
            crows, _ = extract(cd)
            cal, best = [], None
            for r in crows:
                if best is not None and r["band"] <= best: continue
                best = r["band"]
                if r["band"] >= Tc: break
                if r["n"] <= 0: continue
                lo, hi = r["c"] - r["n"] / 2, r["c"] + r["n"] / 2
                if lo < 0.67 or hi > r["band"] - 0.67: continue
                place = min(r["band"], L) - L / 2
                cal.append((180 * min(1.0, r["band"] / Tc), lo - place, hi - place))
            out["glyphCalibration"] = {"dir": cd.rstrip("/").split("/")[-1], "trigger": Tc, "frames": len(cal),
                                       "angles": [round(min(x[0] for x in cal)), round(max(x[0] for x in cal))] if cal else None}
        def offsets(theta):
            near = [x for x in cal or [] if abs(x[0] - theta) <= 4]
            if not near and cal:
                m = min(abs(x[0] - theta) for x in cal)
                near = [x for x in cal if abs(x[0] - theta) == m] if m <= 10 else []
            if near: return float(np.median([x[1] for x in near])), float(np.median([x[2] for x in near]))
            return -hp / 2, hp / 2
        def drawn(sv, refreshing):
            c = centre(sv, refreshing)
            lo, hi = (-hr / 2, hr / 2) if refreshing else offsets(180 * min(1.0, max(0.0, sv) / T) if T > 0 else 180)
            a, b = max(c + lo, 0.0), min(c + hi, sv)
            return (a + b) / 2 if b > a else None
        # The cross-fade (open item 41): from the trigger the arrow (turned 180 degrees) fades out and the spinner fades in,
        # both at the refreshing look's place min(s, L)/2, in 0.15 s from the first frame the arrow's intensity falls below
        # 0.9 of its value at the trigger (SwiftUI starts it a few frames after the update). Before that frame the arrow is
        # drawn alone (`arrow`: its full-turn rows at the place), after the 0.15 s the spinner alone (`spinner`); the fade's
        # frames (`mixed`) draw both at partial opacity, and which of the spinner's rows are detected depends on its spokes'
        # phase, so their drawn centre is no placement: each drawn edge is judged against the two glyphs' predicted edges
        # instead (`xfade.edge`: the largest distance outside them), and the residual skips the pairs with a mixed frame.
        alo, ahi = offsets(180)
        i_full = max((rows[k]["I"] for k in range(max(k0, kT - 1), min(kmax, kT + 1) + 1)), default=0.0)
        kF = next((k for k in range(kT, kmax + 1) if rows[k]["I"] < 0.9 * i_full), None)
        tF = None if kF is None else rows[kF - 1]["t"] + 0.15 + 1 / 60
        def phase(k):
            if k < kT: return "pull"
            if kF is None or k < kF: return "arrow"
            return "mixed" if rows[k]["t"] <= tF else "spinner"
        def rows_of(sv, lo, hi):
            c = min(sv, L) / 2
            a, b = max(c + lo, 0.0), min(c + hi, sv)
            return (a, b) if b > a else None
        def predict(k):
            sv, ph = rows[k]["band"], phase(k)
            if ph == "pull": return drawn(sv, False)
            if ph == "spinner": return drawn(sv, True)
            if ph == "arrow":
                ab = rows_of(sv, alo, ahi)
                return None if ab is None else (ab[0] + ab[1]) / 2
            return None
        series, res, half_err, edge = [], [], [], []
        prev = None
        for k in range(k0, kmax + 1):
            r = rows[k]
            pc, ph = predict(k), phase(k)
            item = {"frame": r["frame"], "band": round(r["band"], 2), "drawn": round(r["n"], 2),
                    "c": None if r["c"] is None else round(r["c"], 2), "pred": None if pc is None else round(pc, 2),
                    "I": round(r["I"], 1), "look": ph}
            series.append(item)
            if prev is not None and r["n"] >= 4 and prev[0]["n"] >= 4 and pc is not None and prev[1] is not None:
                dd = (r["c"] - prev[0]["c"]) - (pc - prev[1])
                res.append((abs(dd), prev[0]["frame"], r["frame"], round(dd, 2)))
            if ph in ("arrow", "spinner") and r["n"] > 0 and r["band"] >= hr + 1:
                off = (alo + ahi) / 2 if ph == "arrow" else 0.0
                half_err.append((abs(r["c"] - off - min(r["band"], L) / 2), r["frame"]))
            if ph == "mixed" and r["n"] > 0:
                A, S = rows_of(r["band"], alo, ahi), rows_of(r["band"], -hr / 2, hr / 2)
                if A and S:
                    dt, db = r["stop"] - base, r["sbot"] - base
                    def outside(x, p, q):
                        lo_, hi_ = min(p, q), max(p, q)
                        return max(0.0, lo_ - x, x - hi_)
                    edge.append((max(outside(dt, A[0], S[0]), outside(db, A[1], S[1])), r["frame"]))
            prev = (r, pc)
        if kF is not None:
            mixed = [x["frame"] for x in series if x["look"] == "mixed"]
            out["xfade"] = {"start": rows[kF]["frame"], "framesAfterTrigger": kF - kT, "mixed": len(mixed),
                            "edge": round(max(edge)[0], 2) if edge else None,
                            "edgeFrame": max(edge)[1] if edge else None,
                            "arrowRows": [round(alo, 2), round(ahi, 2)]}
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

# The begin switch (`-ZTronSeamBeginAfterRelease`, or `--begin`): a programmatic begin while the pull's look retracts
# switches to the refreshing look (the 20 pt glyph centred in the band, opaque). After the release the band falls; the
# begin's opening raises it again (the first frame whose band rises by more than 0.5 pt, `begin`). Per frame
# e = drawn centre - the refreshing look's drawn centre (min(band, L)/2, the glyph clipped to [0, band]); reports e on the
# frame before the begin (`from`), the largest one-frame |change of e| from there on as a fraction of |from| (`step`), the
# frames from the begin until |e| <= 1 for good (`settle`), and the intensity's largest one-frame rise as a fraction of its
# rise from the frame before the begin to the median of the 10 frames after the settle (`ramp`).
if launch_arg("-ZTronSeamBeginAfterRelease") is not None or "--begin" in args:
    runmax, k1 = None, None
    for k, r in enumerate(rows):
        if runmax is None or r["band"] > runmax: runmax = r["band"]
        elif runmax > 4 and r["band"] < runmax - 1: k1 = k; break
    g = {"release": None if k1 is None else rows[k1]["frame"]}
    kb = None if k1 is None else next((k for k in range(k1 + 1, len(rows))
                                       if rows[k]["band"] > rows[k - 1]["band"] + 0.5), None)
    if kb is not None:
        def ref_drawn(sv):
            c = min(sv, L) / 2
            a, b = max(c - 10.0, 0.0), min(c + 10.0, sv)
            return (a + b) / 2 if b > a else None
        e = []
        for r in rows[kb - 1:]:
            pc = ref_drawn(r["band"])
            e.append(None if r["c"] is None or pc is None or r["n"] < 4 else r["c"] - pc)
        g["begin"] = {"frame": rows[kb]["frame"], "band": round(rows[kb - 1]["band"], 2)}
        if e and e[0] is not None:
            g["from"] = round(e[0], 2)
            steps = [(abs(b - a), rows[kb - 1 + j + 1]["frame"]) for j, (a, b) in enumerate(zip(e, e[1:]))
                     if a is not None and b is not None]
            if steps and abs(e[0]) > 0:
                m = max(steps)
                g["step"] = {"max": round(m[0], 2), "fraction": round(m[0] / abs(e[0]), 3), "at": m[1]}
            last_off = max((j for j, x in enumerate(e) if x is None or abs(x) > 1), default=0)
            g["settle"] = last_off
            g["e"] = [None if x is None else round(x, 2) for x in e[:16]]
            I = [r["I"] for r in rows[kb - 1:]]
            after = I[last_off + 1:last_off + 11]
            if after:
                rise = float(np.median(after)) - I[0]
                rises = [(b - a, rows[kb - 1 + j + 1]["frame"]) for j, (a, b) in enumerate(zip(I[:last_off + 2], I[1:last_off + 2]))]
                mr = max(rises) if rises else (0.0, None)
                g["ramp"] = {"from": round(I[0], 1), "to": round(rise + I[0], 1), "maxRise": round(mr[0], 1), "at": mr[1],
                             "fraction": round(mr[0] / rise, 3) if rise > 0 else None}
                g["I"] = [round(x, 1) for x in I[:16]]
    out["begin"] = g
print(json.dumps(out))
