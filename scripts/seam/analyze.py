#!/usr/bin/env python3
"""Seam lab analyzer (M8b-3 R5): per-frame header/content seam from a simulator screen recording.

usage: python3 -I scripts/seam/analyze.py <rec.mov> [--meta meta.json] [--scale 3] [--out DIR] [--dump i,j,...]

The seam lab (`-ZTronScreen seamlab`) draws a pure red header, a pure green 80 pt first row, pure yellow / magenta rows
and a pure blue background. Every decoded frame (ffmpeg, passthrough timing, timestamps from ffprobe) is classified per
pixel; the green band's principal axes (PCA, refined to the direction of least thickness, so a band clipped by the
display mid-rotation keeps its true angle) give the band axis u and its normal n (pointing from the header to the
content). In a strip around the band's centre (40 % of its visible length) the red and green coverage profiles along n
give, per frame, in points:
  gap      header edge facing the band -> green facing edge (positive = blue between them)
  greenVis green visible thickness (80 pt nominal; red drawn over the green shortens it)
  greenShort 80 - greenVis when the green's far edge is on screen (anything drawn over the green shortens it)
  seam     header edge -> content top, signed: positive = blue gap, negative = red covers green. The content top is
           the green's far edge - 80 pt when the next row is intact (contentRows = 1: 60 pt of yellow, then magenta);
           otherwise the green's top when a blue gap shows or the whole green is visible; else unattributable (empty)
  overlap  max(0, -seam)
  hdr      header thickness along n (hdrAtBorder: its far edge is at the display edge; empty when that edge is cut by
           the display mid-rotation)
  *_c      edge positions along n relative to the display centre (stable through a rotation about the centre)
When the green row is not measurable (off screen, covered, a sliver at the display edge) but the header is (band =
header), the axes come from the header (least thickness near the previous frame's normal) and the row says what follows
the header's edge: after = content (touching or a blue run, gapMin), edge (only blue up to the window's or the display's
edge: the content is off screen and gapMin is a lower bound of the gap) or other; content_mark_c tracks the first row
boundary past the header (the content moving under a header that covers the green row).
A frame is a transition frame when the header or green geometry moved > 0.5 pt since the previous frame or the band's
angle is not a multiple of 90 deg (> 0.5 deg off). Segments (one per stimulus) are runs of frames that changed at all
(> 0.1 pt), bridged across holes < 0.4 s; rest spans lie between them (portrait / landscape / portrait). Per segment the
jump detector is the largest single-frame step of the header's thickness, its bottom edge and the green row's top as a
fraction of the change from the rest before to the rest after (1.0 = all in one frame). Frames are in decode (capture)
order; the 17.5 recorder can write scrambled pts, so t is indicative only (summary.timestampsMonotonic).
Outputs frames.csv, summary.json and worst-*.png (annotated: white = header edge facing the band, black = green facing
edge, cyan = header far edge, strip bounds in grey).
"""
import argparse
import csv
import json
import math
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw

GREEN_PT = 80.0
MOVE_PT = 0.5
ANGLE_DEG = 0.5
TOUCH_PT = 1.0
STIR_PT = 0.1
STIR_DEG = 0.05
BRIDGE_S = 0.4
ROW_PT = 60.0
MIN_BAND_PT = 100.0


def probe(path):
    info = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "json",
         path], check=True, capture_output=True, text=True).stdout)
    w, h = info["streams"][0]["width"], info["streams"][0]["height"]
    ts = []
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "frame=best_effort_timestamp_time", "-of", "csv=p=0", path],
                         check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip().strip(",")
        try:
            ts.append(float(line))
        except ValueError:
            ts.append(float("nan"))
    return w, h, ts


def frames(path, w, h):
    p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", path, "-map", "0:v:0", "-fps_mode", "passthrough",
                          "-enc_time_base", "demux", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
    n = w * h * 3
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, np.uint8).reshape(h, w, 3)
    p.wait()


def classify(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hi, lo = 150, 100
    rh, gh, bh = r > hi, g > hi, b > hi
    rl, gl, bl = r < lo, g < lo, b < lo
    return {"red": rh & gl & bl, "green": gh & rl & bl, "blue": bh & rl & gl,
            "yellow": rh & gh & bl, "magenta": rh & bh & gl}


def band_axes(xs, ys, prev_n, near=None):
    """PCA of the band's pixels, refined to the direction of least thickness (within +-8 deg of `near`, radians, when
    given: the header fallback, whose region is not elongated enough for PCA). Returns (u, n, mu, angle_deg)."""
    pts = np.stack([xs, ys], 1)
    mu = pts.mean(0)
    q = pts - mu
    if len(q) > 40000:
        q = q[:: len(q) // 40000 + 1]
    evals, evecs = np.linalg.eigh(np.cov(q.T))
    u0 = evecs[:, 1]
    base = math.atan2(u0[1], u0[0])

    def width(th):
        n = np.array([-math.sin(th), math.cos(th)])
        s = q @ n
        lo, hi = np.percentile(s, [0.2, 99.8])
        return hi - lo

    best = base if near is None else near
    axis = round(best / (math.pi / 2)) * (math.pi / 2)
    spans = ((4.0, 0.25), (0.3, 0.02)) if near is None else ((8.0, 0.5), (0.6, 0.05))
    if near is None and abs(base - axis) < math.radians(0.05):
        best = axis                          # axis-aligned: no refinement needed
    for span, step in (() if best == axis and near is None else spans):
        cands = [best + math.radians(d) for d in np.arange(-span, span + 1e-9, step)]
        best = min(cands, key=width)
    u = np.array([math.cos(best), math.sin(best)])
    n = np.array([-u[1], u[0]])
    if prev_n is not None and n @ prev_n < 0:
        n = -n
    ang = math.degrees(math.atan2(u[1], u[0])) % 180.0
    return u, n, mu, ang


def runs(mask):
    out, i, m = [], 0, len(mask)
    while i < m:
        if mask[i]:
            j = i
            while j + 1 < m and mask[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def crossing_start(f, i):
    if i == 0:
        return float(i)
    a, b = f[i - 1], f[i]
    return (i - 0.5) + ((0.5 - a) / (b - a) if b != a else 0.5)


def crossing_end(f, j):
    if j + 1 >= len(f):
        return float(j + 1)
    a, b = f[j], f[j + 1]
    return (j + 0.5) + ((a - 0.5) / (a - b) if a != b else 0.5)


class Analyzer:
    def __init__(self, w, h, scale):
        self.w, self.h, self.scale = w, h, scale
        self.X = (np.arange(w, dtype=np.float32) + 0.5)[None, :].repeat(h, 0)
        self.Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None].repeat(w, 1)
        self.centre = np.array([w / 2.0, h / 2.0])
        self.prev_n = None

    def header_only(self, c, row):
        """No measurable green row: the header alone. Axes from the header (least thickness within +-8 deg of the previous
        frame's normal: continuity through a rotation), then what follows its edge along n: `after` = content (a
        content color), edge (black outside the window, or the display's edge) or other; `gapMin` = the blue run from
        the header's edge to there. With after = edge the content is not on screen and gapMin is a lower bound of the
        gap (the content's top is past the visible region)."""
        # The seam lab always shows some blue (safe areas, the gap) when its green row is not measurable: a frame
        # without any is not the seam lab (the home screen after the test).
        if self.prev_n is None or not row.get("app") or row["blue"] < 0.02:
            return row, None
        ry, rx = np.nonzero(c["red"])
        if len(rx) < 2000:
            return row, None
        rxf, ryf = rx + 0.5, ry + 0.5
        prev_u = np.array([self.prev_n[1], -self.prev_n[0]])
        u, n, mu, ang = band_axes(rxf, ryf, self.prev_n, near=math.atan2(prev_u[1], prev_u[0]))
        u = np.array([n[1], -n[0]])
        sc = self.scale
        tr = (rxf - mu[0]) * u[0] + (ryf - mu[1]) * u[1]
        sr = (rxf - mu[0]) * n[0] + (ryf - mu[1]) * n[1]
        tlo, thi = np.percentile(tr, [0.5, 99.5])
        # Off-centre (10-30 % of the header's length): the run past the header reaches the window's bottom edge here,
        # where the home indicator sits at the centre.
        tc, hw = tlo + 0.2 * (thi - tlo), 0.1 * (thi - tlo)
        if (thi - tlo) / sc < MIN_BAND_PT:
            return row, None
        sel = np.abs(tr - tc) < hw
        s_lo = np.percentile(sr[sel], 0.1) - 6
        s_hi = np.percentile(sr[sel], 99.9) + 2 * max(self.w, self.h)
        corners = [mu + u * (tc + dt) + n * ds for dt in (-hw, hw) for ds in (s_lo, s_hi)]
        xs = [p[0] for p in corners]
        ys = [p[1] for p in corners]
        x0, x1 = max(0, int(min(xs)) - 1), min(self.w, int(max(xs)) + 2)
        y0, y1 = max(0, int(min(ys)) - 1), min(self.h, int(max(ys)) + 2)
        X, Y = self.X[y0:y1, x0:x1], self.Y[y0:y1, x0:x1]
        S = (X - mu[0]) * n[0] + (Y - mu[1]) * n[1]
        T = (X - mu[0]) * u[0] + (Y - mu[1]) * u[1]
        inside = (np.abs(T - tc) < hw) & (S >= s_lo) & (S < s_hi)
        base = math.floor(s_lo)
        nb = int(math.ceil(s_hi)) - base + 1
        idx = (S[inside] - base).astype(np.int64)
        tot = np.bincount(idx, minlength=nb).astype(np.float64)
        valid = tot > 0.5 * (2 * hw)

        def frac(mask):
            b = np.bincount(idx, weights=mask[y0:y1, x0:x1][inside], minlength=nb)
            return np.where(valid, b / np.maximum(tot, 1), 0.0)

        fr, fb = frac(c["red"]), frac(c["blue"])
        fc = frac(c["green"] | c["yellow"] | c["magenta"])
        fy, fm = frac(c["yellow"]), frac(c["magenta"])
        rr = [r for r in runs(fr >= 0.5) if r[1] - r[0] >= 2]
        if not rr:
            return row, None
        ri, rj = max(rr, key=lambda r: fr[r[0]:r[1] + 1].sum())
        r0, r1 = base + crossing_start(fr, ri), base + crossing_end(fr, rj)
        dev = min(ang % 90.0, 90.0 - ang % 90.0)
        at_border = ri == 0 or not valid[ri - 1]
        k = rj + 1
        # Up to two blended bins at the header's edge (h264 chroma: neither red nor blue).
        while k < rj + 3 and k < nb and valid[k] and fb[k] < 0.5 and fr[k] < 0.5 and fc[k] < 0.5 and \
                k + 1 < nb and valid[k + 1] and fb[k + 1] >= 0.5:
            k += 1
        while k < nb and valid[k] and fb[k] >= 0.5:
            k += 1
        if k < nb and valid[k] and fc[k] >= 0.5:
            after = "content"
        elif k >= nb or not valid[k] or (fb[k] < 0.5 and fr[k] < 0.5 and fc[k] < 0.5):
            after = "edge"
        else:
            after = "other"
        end = base + (crossing_end(fb, k - 1) if k - 1 > rj else rj + 1)
        # The content moving under a header that covers its green row: the first row boundary past the header's edge
        # (yellow or magenta run end) moves with it.
        mark = float("nan")
        if after == "content":
            for f in (fy, fm):
                cr = [r for r in runs(f >= 0.5) if k - 1 <= r[0] <= k + 3 and r[1] - r[0] >= 2]
                if cr and cr[0][1] + 1 < nb and valid[cr[0][1] + 1]:
                    mark = base + crossing_end(f, cr[0][1])
                    break
        ref = (mu - self.centre) @ n
        hdr = (r1 - r0) / sc if not (at_border and dev > ANGLE_DEG) else float("nan")
        row.update(band="header", angle=round(ang, 3), angleDev=round(dev, 3), nx=round(float(n[0]), 5),
                   ny=round(float(n[1]), 5), hdr_top_c=round((ref + r0) / sc, 3), hdr_bot_c=round((ref + r1) / sc, 3),
                   hdr=round(hdr, 3) if not math.isnan(hdr) else hdr, hdrVisible=round((r1 - r0) / sc, 3),
                   hdrAtBorder=int(at_border), after=after, gapMin=round(max(0.0, end - r1) / sc, 3),
                   content_mark_c=round((ref + mark) / sc, 3) if not math.isnan(mark) else mark,
                   hdrLen=round((thi - tlo) / sc, 3))
        self.prev_n = n
        return row, {"mu": mu, "u": u, "n": n, "tc": tc, "hw": hw, "r0": r0, "r1": r1, "g0": end, "g1": end}

    def frame(self, a):
        c = classify(a)
        npx = self.w * self.h
        pure = sum(int(m.sum()) for m in c.values()) / npx
        blue = int(c["blue"].sum()) / npx
        row = {"app": pure > 0.4, "pure": round(pure, 3), "blue": round(blue, 4)}
        if not row["app"]:
            return row, None
        gy, gx = np.nonzero(c["green"])
        if len(gx) < 2000:
            row["band"] = "none"
            return self.header_only(c, row)
        gxf, gyf = gx + 0.5, gy + 0.5
        ry, rx = np.nonzero(c["red"])
        u, n, mu, ang = band_axes(gxf, gyf, self.prev_n)
        if len(rx) > 200:
            mr = np.array([rx.mean() + 0.5, ry.mean() + 0.5])
            if (mr - mu) @ n > 0:
                n = -n
        elif self.prev_n is None:
            n = np.array([0.0, 1.0]) if abs(n[1]) > abs(n[0]) else n
        u = np.array([n[1], -n[0]])
        dev = min(ang % 90.0, 90.0 - ang % 90.0)
        row.update(angle=round(ang, 3), angleDev=round(dev, 3), nx=round(float(n[0]), 5), ny=round(float(n[1]), 5))

        # Strip around the band's centre along u.
        tg = (gxf - mu[0]) * u[0] + (gyf - mu[1]) * u[1]
        tlo, thi = np.percentile(tg, [0.5, 99.5])
        if (thi - tlo) / self.scale < MIN_BAND_PT:
            row["band"] = "short"      # a sliver of green at the display edge: its axes are not the band's
            return self.header_only(c, row)
        tc, hw = (tlo + thi) / 2, 0.2 * (thi - tlo)
        sg = (gxf - mu[0]) * n[0] + (gyf - mu[1]) * n[1]
        sel = np.abs(tg - tc) < hw
        if sel.sum() < 100:
            row["band"] = "nogreen"
            return self.header_only(c, row)
        sg_lo, sg_hi = np.percentile(sg[sel], [0.1, 99.9])
        if len(rx) > 0:
            rxf, ryf = rx + 0.5, ry + 0.5
            tr = (rxf - mu[0]) * u[0] + (ryf - mu[1]) * u[1]
            sr = (rxf - mu[0]) * n[0] + (ryf - mu[1]) * n[1]
            if len(tr) > 200:
                rlo, rhi = np.percentile(tr, [0.5, 99.5])
                row["hdrLen"] = round((rhi - rlo) / self.scale, 3)
            sr = sr[np.abs(tr - tc) < hw]
        else:
            sr = np.zeros(0)
        s_lo = min(sg_lo, sr.min() if len(sr) else sg_lo) - 6
        s_hi = sg_hi + (ROW_PT + 12) * self.scale      # the yellow row after the green and the next row's start
        # Bounding box of the strip between s_lo and s_hi, clipped to the image.
        corners = [mu + u * (tc + dt) + n * ds for dt in (-hw, hw) for ds in (s_lo, s_hi)]
        xs = [p[0] for p in corners]
        ys = [p[1] for p in corners]
        x0, x1 = max(0, int(min(xs)) - 1), min(self.w, int(max(xs)) + 2)
        y0, y1 = max(0, int(min(ys)) - 1), min(self.h, int(max(ys)) + 2)
        X, Y = self.X[y0:y1, x0:x1], self.Y[y0:y1, x0:x1]
        S = (X - mu[0]) * n[0] + (Y - mu[1]) * n[1]
        T = (X - mu[0]) * u[0] + (Y - mu[1]) * u[1]
        inside = (np.abs(T - tc) < hw) & (S >= s_lo) & (S < s_hi)
        base = math.floor(s_lo)
        nb = int(math.ceil(s_hi)) - base + 1
        idx = (S[inside] - base).astype(np.int64)
        tot = np.bincount(idx, minlength=nb).astype(np.float64)
        red_b = np.bincount(idx, weights=c["red"][y0:y1, x0:x1][inside], minlength=nb)
        grn_b = np.bincount(idx, weights=c["green"][y0:y1, x0:x1][inside], minlength=nb)
        ylw_b = np.bincount(idx, weights=c["yellow"][y0:y1, x0:x1][inside], minlength=nb)
        mag_b = np.bincount(idx, weights=c["magenta"][y0:y1, x0:x1][inside], minlength=nb)
        full = 2 * hw
        valid = tot > 0.5 * full
        fr = np.where(valid, red_b / np.maximum(tot, 1), 0.0)
        fg = np.where(valid, grn_b / np.maximum(tot, 1), 0.0)
        fy = np.where(valid, ylw_b / np.maximum(tot, 1), 0.0)
        fm = np.where(valid, mag_b / np.maximum(tot, 1), 0.0)

        gr = [r for r in runs(fg >= 0.5) if r[1] - r[0] >= 2]
        if not gr:
            row["band"] = "nogreen"
            return self.header_only(c, row)
        rr = [r for r in runs(fr >= 0.5) if r[1] - r[0] >= 2]
        hdr_run = max(rr, key=lambda r: fr[r[0]:r[1] + 1].sum()) if rr else None
        after = [r for r in gr if hdr_run is not None and r[0] >= hdr_run[1] - 2]
        # The band's facing edge is the first green run past the header (a row drawn over the green, as the content
        # does mid-rotation on 27.0, splits it); without a header, the largest run.
        gi, gj = after[0] if after else max(gr, key=lambda r: fg[r[0]:r[1] + 1].sum())
        g0, g1 = base + crossing_start(fg, gi), base + crossing_end(fg, gj)
        g1_border = gj + 1 >= nb or not valid[gj + 1]
        sc = self.scale
        if (g1 - g0) / sc > GREEN_PT + 2 or fg[gi:gj + 1].mean() < 0.9:
            row["band"] = "notband"    # thicker than the row or not solid: not the seam lab's green row
            return self.header_only(c, row)
        row["band"] = "ok"
        row["greenLen"] = round((thi - tlo) / sc, 3)
        self.prev_n = n
        ref = (mu - self.centre) @ n          # display centre -> band origin, along n
        row.update(green_top_c=round((ref + g0) / sc, 3), green_bot_c=round((ref + g1) / sc, 3),
                   greenVis=round((g1 - g0) / sc, 3), greenFarAtBorder=int(g1_border))
        geo = {"mu": mu, "u": u, "n": n, "tc": tc, "hw": hw, "g0": g0, "g1": g1}
        if hdr_run is None or hdr_run[1] > gi + 2:
            row.update(hdr=float("nan"), gap=float("nan"))
        else:
            ri, rj = hdr_run
            r0, r1 = base + crossing_start(fr, ri), base + crossing_end(fr, rj)
            at_border = ri == 0 or not valid[ri - 1]
            # At the display edge mid-rotation the header's far edge is cut by the display: its thickness is unknown.
            # Axis-aligned it is the window's edge (landscape top0 = 0): the thickness holds.
            hdr = (r1 - r0) / sc if not (at_border and dev > ANGLE_DEG) else float("nan")
            row.update(hdr_top_c=round((ref + r0) / sc, 3), hdr_bot_c=round((ref + r1) / sc, 3),
                       hdr=round(hdr, 3) if not math.isnan(hdr) else hdr, hdrVisible=round((r1 - r0) / sc, 3),
                       hdrAtBorder=int(at_border), gap=round((g0 - r1) / sc, 3))
            geo.update(r0=r0, r1=r1)
        short = max(0.0, GREEN_PT - row["greenVis"]) if not g1_border else float("nan")
        row["greenShort"] = round(short, 3) if not math.isnan(short) else short
        # The content's top from its own rows: when the yellow row after the green is intact (60 pt, then magenta), the
        # green's far edge is the content's own green/yellow boundary, so the content top is 80 pt before it, wherever
        # the green's top is covered (by the header) or not.
        natural = False
        yr = [r for r in runs(fy >= 0.5) if gj - 1 <= r[0] <= gj + 3]
        if yr and not g1_border:
            yi, yj = yr[0]
            ylen = (crossing_end(fy, yj) - crossing_start(fy, yi)) / sc
            natural = abs(ylen - ROW_PT) <= 1.5 and yj + 1 < nb and bool((fm[yj + 1: yj + 4] >= 0.5).any())
        row["contentRows"] = int(natural)
        seam = float("nan")
        if not math.isnan(row["gap"]):
            if natural:
                ctop = g1 - GREEN_PT * sc
                row["content_top_c"] = round((ref + ctop) / sc, 3)
                seam = (ctop - geo["r1"]) / sc            # header bottom -> content top, signed
            elif row["gap"] > TOUCH_PT or abs(short) <= TOUCH_PT:
                seam = row["gap"]                          # a blue gap, or the whole green visible: green top = content top
            # else: the header touches a shortened green and the rows after it are not intact: unattributable.
        row["seam"] = round(seam, 3) if not math.isnan(seam) else seam
        row["overlap"] = round(max(0.0, -seam), 3) if not math.isnan(seam) else seam
        if not math.isnan(seam):
            row["ctop_c"] = round(row["hdr_bot_c"] + seam, 3)      # the content's top (covered or not)
        return row, geo


def annotate(a, geo, path):
    img = Image.fromarray(np.ascontiguousarray(a))
    if geo is not None:
        d = ImageDraw.Draw(img)
        mu, u, n, tc, hw = geo["mu"], geo["u"], geo["n"], geo["tc"], geo["hw"]

        def line(s, color, width=2):
            p, q = mu + u * (tc - hw) + n * s, mu + u * (tc + hw) + n * s
            d.line([tuple(p), tuple(q)], fill=color, width=width)

        for k, color in (("r0", (0, 255, 255)), ("r1", (255, 255, 255)), ("g0", (0, 0, 0)), ("g1", (128, 128, 128))):
            if k in geo:
                line(geo[k], color)
        for dt in (-hw, hw):
            p = mu + u * (tc + dt) + n * (geo.get("r0", geo["g0"]) - 20)
            q = mu + u * (tc + dt) + n * (geo["g1"] + 20)
            d.line([tuple(p), tuple(q)], fill=(160, 160, 160), width=1)
    img.save(path)


def num(v):
    return v is not None and not (isinstance(v, float) and math.isnan(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--meta")
    ap.add_argument("--scale", type=float)
    ap.add_argument("--out")
    ap.add_argument("--dump", default="", help="comma-separated frame indices to save as PNG")
    args = ap.parse_args()
    meta = json.load(open(args.meta)) if args.meta else {}
    scale = args.scale or meta.get("scale", 3)
    out = args.out or os.path.dirname(os.path.abspath(args.video))
    os.makedirs(out, exist_ok=True)
    dump = {int(x) for x in args.dump.split(",") if x.strip()}

    w, h, ts = probe(args.video)
    an = Analyzer(w, h, scale)
    rows = []
    keep = {}           # name -> (score, index, array, geo)
    prev = None         # (index, array, geo, row) of the previous measured frame
    hdr_step_best = None
    for i, a in enumerate(frames(args.video, w, h)):
        row, geo = an.frame(a)
        row = {"frame": i, "t": round(ts[i], 4) if i < len(ts) else float("nan"), **row}
        rows.append(row)
        if i in dump:
            annotate(a, geo, os.path.join(out, f"frame-{i:05d}.png"))
        if geo is None:
            continue
        if num(row.get("seam")):
            if row["seam"] > 0 and (keep.get("gap") is None or row["seam"] > keep["gap"][0]):
                keep["gap"] = (row["seam"], i, a.copy(), geo)
            if row["seam"] < 0 and (keep.get("overlap") is None or -row["seam"] > keep["overlap"][0]):
                keep["overlap"] = (-row["seam"], i, a.copy(), geo)
        if row.get("band") == "header" and row.get("after") == "edge" and row["gapMin"] > 1.0 and \
                (keep.get("offscreen") is None or row["gapMin"] > keep["offscreen"][0]):
            keep["offscreen"] = (row["gapMin"], i, a.copy(), geo)
        if prev is not None and num(row.get("hdr")) and num(prev[3].get("hdr")):
            step = abs(row["hdr"] - prev[3]["hdr"])
            if hdr_step_best is None or step > hdr_step_best[0]:
                hdr_step_best = (step, prev[0], prev[1], prev[2], i, a.copy(), geo)
        prev = (i, a.copy(), geo, row)

    # Transition frames, over every frame with a measurement (the green row, or the header alone): a move > 0.5 pt
    # since the previous frame, or an angle off a multiple of 90 deg (> 0.5 deg).
    measured = [r for r in rows if r.get("band") in ("ok", "header")]
    keys = ("hdr", "hdr_bot_c", "green_top_c", "greenVis", "gapMin", "content_mark_c", "greenLen", "hdrLen")
    last = None
    for r in measured:
        moved = stirred = last is not None and r["band"] != last["band"]
        if last is not None:
            for k in keys:
                here, there = num(r.get(k)), num(last.get(k))
                if here and there:
                    d = abs(r[k] - last[k])
                    moved, stirred = moved or d > MOVE_PT, stirred or d > STIR_PT
                elif here != there:
                    moved = stirred = True
        r["transition"] = int(moved or r["angleDev"] > ANGLE_DEG)
        r["_stir"] = stirred or r["angleDev"] > STIR_DEG
        last = r
    mono = all(b["t"] >= a["t"] for a, b in zip(measured, measured[1:]))

    # Segments (one per stimulus): runs of frames that changed at all (> 0.1 pt; an ease-in moves less than 0.5 pt per
    # frame for its first frames), bridged across holes shorter than 0.4 s (6 frames when the timestamps are
    # scrambled). At rest the recorder writes few frames, so two stimuli 2.5 s apart stay apart.
    segs, cur = [], None
    for k, r in enumerate(measured):
        if not r["_stir"]:
            continue
        if cur is not None:
            close = (r["t"] - measured[cur[1]]["t"] < BRIDGE_S) if mono else (k - cur[1] <= 6)
            if close:
                cur[1] = k
                continue
            segs.append(cur)
        cur = [k, k]
    if cur is not None:
        segs.append(cur)
    in_seg = set()
    for a, b in segs:
        in_seg.update(range(a, b + 1))

    def jump(seg, key):
        """Largest single-frame step of `key` inside the segment, as a fraction of its total change (rest before ->
        rest after): 1.0 = the whole change happened in one frame."""
        a, b = seg
        before = measured[a - 1] if a > 0 else None
        after = measured[b + 1] if b + 1 < len(measured) else None
        series = measured[max(0, a - 1): b + 2]
        if before is None or after is None or not num(before.get(key)) or not num(after.get(key)):
            return None
        total = after[key] - before[key]
        # Steps between consecutive measured frames only; a span with the value unmeasured (the green row off screen,
        # a header cut by the display) is counted, not bridged.
        steps = [(abs(series[j][key] - series[j - 1][key]), series[j]["frame"]) for j in range(1, len(series))
                 if num(series[j].get(key)) and num(series[j - 1].get(key))]
        unmeasured = sum(1 for r in series if not num(r.get(key)))
        if not steps:
            return None
        big = max(steps)
        # The same per 60 Hz interval elapsed (a recorder or render hitch spans several; 1 when the timestamps are
        # scrambled, and for the first step: the recorder writes no frames at rest, so the time since the rest frame
        # before the segment says nothing): a real jump stays near 1.0, a hitch inside an interpolation drops.
        by = {r["frame"]: r for r in series}
        prev_t = {series[j]["frame"]: series[j - 1]["t"] for j in range(2, len(series))}

        def per_vsync(step, frame):
            if not mono or frame not in prev_t:
                return step
            return step / max(1, round((by[frame]["t"] - prev_t[frame]) * 60))

        rate = max(per_vsync(st, fr) for st, fr in steps)
        return {"from": before[key], "to": after[key], "totalChange": round(total, 3), "maxStep": round(big[0], 3),
                "atFrame": big[1], "unmeasured": unmeasured,
                "fraction": round(big[0] / abs(total), 3) if abs(total) >= 1.0 else None,
                "fractionPerVsync": round(rate / abs(total), 3) if abs(total) >= 1.0 else None}

    def stats(rs):
        seams = [r["seam"] for r in rs if num(r.get("seam"))]
        off = [r["gapMin"] for r in rs if r.get("band") == "header" and r.get("after") == "edge"]
        return {"maxGap": max([x for x in seams if x > 0], default=0.0),
                "maxOverlap": max([-x for x in seams if x < 0], default=0.0),
                "seamFrames": len(seams),
                "headerOnly": {k: sum(1 for r in rs if r.get("band") == "header" and r.get("after") == k)
                               for k in ("content", "edge", "other")},
                "maxGapMinContentOffscreen": max(off, default=None)}

    segments = []
    for seg in segs:
        rs = measured[seg[0]: seg[1] + 1]
        segments.append({"frames": [rs[0]["frame"], rs[-1]["frame"]], "t": [rs[0]["t"], rs[-1]["t"]], "count": len(rs),
                         **stats(rs), "hdrJump": jump(seg, "hdr"), "hdrBotJump": jump(seg, "hdr_bot_c"),
                         "greenTopJump": jump(seg, "green_top_c"), "contentTopJump": jump(seg, "ctop_c")})

    rest = [r for k, r in enumerate(measured) if k not in in_seg]
    rest_seams = [r["seam"] for r in rest if num(r.get("seam"))]
    tr = [r for r in measured if r["transition"]]
    # Rest spans: before the first segment, between segments, after the last (portrait / landscape / portrait again).
    bounds = [-1] + [x for a, b in segs for x in (a, b)] + [len(measured)]
    spans = []
    for j in range(0, len(bounds), 2):
        rs = measured[bounds[j] + 1: bounds[j + 1]]
        if rs:
            seams = [r["seam"] for r in rs if num(r.get("seam"))]
            hdrs = [r["hdr"] for r in rs if num(r.get("hdr"))]
            spans.append({"frames": [rs[0]["frame"], rs[-1]["frame"]], "count": len(rs),
                          "seamMedian": float(np.median(seams)) if seams else None,
                          "seamMin": min(seams, default=None), "seamMax": max(seams, default=None),
                          "hdrMedian": float(np.median(hdrs)) if hdrs else None, **stats(rs)})
    first_rest = [r["seam"] for r in measured[: segs[0][0] if segs else len(measured)] if num(r.get("seam"))]

    def frac(key, field="fraction"):
        vals = [s[key][field] for s in segments if s[key] and s[key][field] is not None]
        return max(vals) if vals else None

    def spread(vals):
        return {"median": float(np.median(vals)) if vals else None, "min": min(vals, default=None),
                "max": max(vals, default=None), "count": len(vals)}

    all_stats, tr_stats, rest_stats = stats(measured), stats(tr), stats(rest)
    summary = {
        "video": os.path.abspath(args.video), "meta": meta, "scale": scale, "size": [w, h],
        "frames": len(rows), "appFrames": sum(1 for r in rows if r.get("app")), "measuredFrames": len(measured),
        # Frames are in decode (capture) order; some recordings (17.5 under load) carry scrambled pts: t is then only
        # indicative and the frame index is the clock.
        "timestampsMonotonic": mono,
        "transitionFrames": len(tr),
        "seamFrames": all_stats["seamFrames"],
        "unattributedFrames": sum(1 for r in measured if num(r.get("gap")) and not num(r.get("seam"))),
        "greenShortFrames": sum(1 for r in measured if num(r.get("greenShort")) and r["greenShort"] > 1.0),
        # Header visible, green row not measurable: what follows the header's edge (content; edge = nothing but blue up
        # to the window's or the display's edge: the content is off screen, gapMin is a lower bound of the gap; other).
        "headerOnlyFrames": all_stats["headerOnly"],
        "maxGapMinContentOffscreen": all_stats["maxGapMinContentOffscreen"],
        "maxGap": all_stats["maxGap"], "maxOverlap": all_stats["maxOverlap"],
        "transition": tr_stats, "rest": rest_stats,
        "restSeam": spread(rest_seams), "firstRestSeam": spread(first_rest),
        "hdrJumpFraction": frac("hdrJump"), "hdrBotJumpFraction": frac("hdrBotJump"),
        "greenTopJumpFraction": frac("greenTopJump"), "contentTopJumpFraction": frac("contentTopJump"),
        "perVsync": {k: frac(k, "fractionPerVsync") for k in ("hdrJump", "hdrBotJump", "contentTopJump")},
        "segments": segments, "restSpans": spans,
        "worst": {},
    }
    for name in ("gap", "overlap", "offscreen"):
        if keep.get(name):
            score, i, a, geo = keep[name]
            p = os.path.join(out, f"worst-{name}-f{i:05d}.png")
            annotate(a, geo, p)
            summary["worst"][name] = {"value": score, "frame": i, "t": rows[i]["t"], "png": p}
    if hdr_step_best:
        step, pi, pa, pgeo, i, a, geo = hdr_step_best
        p0 = os.path.join(out, f"worst-hdrstep-f{pi:05d}-before.png")
        p1 = os.path.join(out, f"worst-hdrstep-f{i:05d}.png")
        annotate(pa, pgeo, p0)
        annotate(a, geo, p1)
        summary["worst"]["hdrStep"] = {"value": round(step, 3), "frame": i, "t": rows[i]["t"], "png": [p0, p1]}

    cols = ["frame", "t", "app", "pure", "band", "angle", "angleDev", "nx", "ny", "hdr_top_c", "hdr_bot_c", "green_top_c",
            "green_bot_c", "ctop_c", "hdr", "hdrVisible", "hdrLen", "greenLen", "hdrAtBorder", "greenVis", "greenShort",
            "greenFarAtBorder", "contentRows", "content_top_c", "gap", "overlap", "seam", "after", "gapMin",
            "content_mark_c", "transition"]
    with open(os.path.join(out, "frames.csv"), "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        wr.writeheader()
        for r in rows:
            wr.writerow({k: r.get(k, "") for k in cols})
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, default=float)
    brief = {k: summary[k] for k in ("frames", "measuredFrames", "transitionFrames", "seamFrames",
                                     "unattributedFrames", "greenShortFrames", "headerOnlyFrames",
                                     "maxGapMinContentOffscreen", "maxGap", "maxOverlap", "restSeam", "firstRestSeam",
                                     "hdrJumpFraction", "hdrBotJumpFraction", "contentTopJumpFraction")}
    print(json.dumps(brief))
    for sp in spans:
        print("rest", json.dumps({k: sp[k] for k in ("frames", "count", "seamMedian", "seamMin", "seamMax", "hdrMedian",
                                                     "headerOnly", "maxGapMinContentOffscreen")}))
    for seg in segments:
        print("segment", json.dumps({k: seg[k] for k in ("frames", "count", "maxGap", "maxOverlap", "headerOnly",
                                                         "maxGapMinContentOffscreen")}),
              "hdrJump", json.dumps(seg["hdrJump"]), "hdrBotJump", json.dumps(seg["hdrBotJump"]),
              "contentTopJump", json.dumps(seg["contentTopJump"]))


if __name__ == "__main__":
    main()
