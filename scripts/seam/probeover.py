#!/usr/bin/env python3
"""Is the lab's white 20 pt hold probe (`-ZTronSeamHold 1`) drawn OVER the content, under a header? (portrait app frames only;
the header behaviors' seamless review, S-RS-1; holdgap.py is the headerless twin)
usage: python3 -I scripts/seam/probeover.py <scenario-dir>   (after analyze.py: reads rec.mov, meta.json, frames.csv)
Per frame: the white square (20 +- 4 pt, upper 70 % of the screen, not the bottom buttons), the colours in a 3 pt ring
around it (content = yellow / magenta rows; header = red / green; band = blue / cyan), and its bottom relative to the
header's drawn bottom (frames.csv hdr_bot_c, pt from the display centre). A frame counts as OVER when the ring holds
content colours (> 5 % of the ring) on any side. Prints JSON: frames, probeFrames, overFrames, worst depth (probe bottom
minus header bottom, pt), the frame ranges."""
import sys, csv, json, subprocess
import numpy as np
d = sys.argv[1]
meta = json.load(open(d + "/meta.json")); s = meta.get("scale", 3)
fr = {int(x["frame"]): x for x in csv.DictReader(open(d + "/frames.csv"))}
pr = json.loads(subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","stream=width,height","-of","json",d+"/rec.mov"]))
w, h = pr["streams"][0]["width"], pr["streams"][0]["height"]
p = subprocess.Popen(["ffmpeg","-v","fatal","-i",d+"/rec.mov","-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","pipe:1"],stdout=subprocess.PIPE)
def components(mask, s):
    # pt-grid connected components (4-neighbour) of a boolean pixel mask; returns pixel slices
    H, W = mask.shape[0] // s, mask.shape[1] // s
    g = mask[:H*s, :W*s].reshape(H, s, W, s).mean(axis=(1, 3)) > 0.5
    seen = np.zeros_like(g); out = []
    for y, x in zip(*np.nonzero(g)):
        if seen[y, x]: continue
        st = [(y, x)]; seen[y, x] = True; ys = []; xs = []
        while st:
            a, c = st.pop(); ys.append(a); xs.append(c)
            for aa, cc in ((a+1, c), (a-1, c), (a, c+1), (a, c-1)):
                if 0 <= aa < H and 0 <= cc < W and g[aa, cc] and not seen[aa, cc]:
                    seen[aa, cc] = True; st.append((aa, cc))
        out.append((slice(min(ys)*s, (max(ys)+1)*s), slice(min(xs)*s, (max(xs)+1)*s)))
    return out
rows = []; i = -1
while True:
    buf = p.stdout.read(w*h*3)
    if len(buf) < w*h*3: break
    i += 1
    if h < w: continue
    if fr.get(i, {}).get("app") == "False": continue   # the home screen before launch / after the test
    im = np.frombuffer(buf, np.uint8).reshape(h, w, 3).astype(np.int16)
    r, g, b = im[...,0], im[...,1], im[...,2]
    white = (r > 235) & (g > 235) & (b > 235)
    white[int(h*0.7):] = False; white[:int(40*s)] = False
    if not white.any(): continue
    best = None
    for sl in components(white, s):
        hh = (sl[0].stop - sl[0].start) / s; ww = (sl[1].stop - sl[1].start) / s
        if 15 <= hh <= 25 and 15 <= ww <= 25:
            best = sl; break
    if best is None: continue
    y0, y1, x0, x1 = best[0].start, best[0].stop, best[1].start, best[1].stop
    m = int(3*s)
    ring = np.zeros((h, w), bool)
    ring[max(0,y0-m):min(h,y1+m), max(0,x0-m):min(w,x1+m)] = True
    ring[y0:y1, x0:x1] = False
    rr, gg, bb = r[ring], g[ring], b[ring]
    yellow = (rr > 200) & (gg > 200) & (bb < 80); magenta = (rr > 200) & (gg < 80) & (bb > 200)
    red = (rr > 200) & (gg < 80) & (bb < 80); green = (rr < 80) & (gg > 200) & (bb < 80)
    cont = float((yellow | magenta).mean())
    x = fr.get(i, {})
    hb = x.get("hdr_bot_c", "")
    depth = (y1 / s - h / s / 2 - float(hb)) if hb not in ("", None) else None
    rows.append((i, round(cont, 3), round(float(red.mean()), 3), round(float(green.mean()), 3), None if depth is None else round(depth, 2), round(y0/s, 2), round(y1/s, 2)))
over = [q for q in rows if q[1] > 0.05]
def ranges(fs):
    out = []; 
    for f in fs:
        if out and f == out[-1][1] + 1: out[-1][1] = f
        else: out.append([f, f])
    return out
print(json.dumps({"dir": d.rstrip('/').split('/')[-1], "probeFrames": len(rows), "overFrames": len(over),
                  "overRanges": ranges([q[0] for q in over]),
                  "worstDepth": max((q[4] for q in over if q[4] is not None), default=None),
                  "sample": [q for q in over[:: max(1, len(over)//8)]]}))
