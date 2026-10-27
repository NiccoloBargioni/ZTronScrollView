#!/usr/bin/env python3
"""Seam lab analyzer v2 (M8b-3 R5): per-frame header/content seam from a simulator screen recording.

usage: python3 -I scripts/seam/analyze.py <rec.mov> [--meta meta.json] [--scale 3] [--out DIR] [--dump i,j,...]
                                          [--last N] [--quiet]

The seam lab (`-ZTronScreen seamlab`) draws a pure red header, a pure green 80 pt first row, then 40 rows alternating
pure yellow / magenta (60 pt), on a pure blue background. Every decoded frame (ffmpeg, passthrough timing, timestamps
from ffprobe) is labelled per pixel (red, green, blue, yellow, magenta, black = outside the window; the 1-2 px blend
of an anti-aliased edge between two colors, e.g. yellow between red and green, is left unlabelled).

v2 measures straight edges, not regions. Boundary points are the midpoints of differently labelled pixel pairs 3 px
apart (4 directions). The band normal n (from the header to the content) comes from the content's row boundaries
(green/yellow, yellow/magenta, magenta/yellow: a Hough-like search for the angle whose projections are sharpest; the
header's edges when no row boundary shows), refined by total least squares per line and jointly over every line of the
family (the content's edges, the header's bottom and top edges). A line of 30 pt or more whose own angle is more than
1 deg off the content's joint one rejects the frame (band = reject, angleSpread / angleWorst say by how much and which
line): the header and the content are not parallel there. Each line's position is refined to sub-pixel precision from
the coverage profile across it. n's sign: continuity; else green before yellow; else header before content.

  content top  from ANY visible content edge: green->yellow at content y = 80 (k = 0), blue->green (the green row's
               top facing the background) at 0, green->blue (its far edge facing the background) at 80,
               yellow->magenta / magenta->yellow at 80 + 60k (k odd / even). The rows fix the top modulo 120 pt; a green
               edge fixes it outright, otherwise the candidates are checked against the pixels (the green row of a
               candidate must be hidden: no visible yellow, magenta or blue where it would be) and the one nearest the
               prediction from the previous frames wins (no prediction: the smallest overlap). ctopSrc = green |
               greentop | greenfar | greenclip | rows; ctopAmb = 1 when that choice is not clear-cut: several
               candidates and no fresh prediction (none from the last two frames), a runner-up within 60 pt of it, or
               the winner > 30 pt off it (e.g. a collapsed header with the green row scrolled away), and (v2.1) for
               greenclip: the green row's far edge facing the background with no other content edge visible, which in
               this lab is the viewport's clip cutting the row (it is always followed by the yellow row), so the
               content top is not derivable from the pixels; ambiguous frames stay out of the
               maxima (summary maxOverlapAmbiguous reports them apart). v2.2: with `-ZTronSeamMarker 1` the lab draws
               row 4 (content y 320..380) pure cyan instead of yellow: its edges magenta->cyan (320) and cyan->magenta
               (380) fix the content top outright (ctopSrc = marker), e.g. under a collapsed header whose content is
               scrolled under it (the rows alone fix it modulo 120 pt only, and the green row may be clipped away
               above the header's top). Torn content (the 27.0 rotation draws the green
               row at its old place and the next rows at their new one, over it or apart from it): the green edge
               nearest the header's bottom edge sets the content top (what meets the header) and ctopSplit = 1 says the
               content's own edges disagree (> 2 pt, a blue->yellow edge off the rows included).
  seam         content top - header bottom along n (positive = gap, negative = the header covers the content);
               overlap = max(0, -seam). A stepped header bottom (the .fit header's aspect view and its frame animate
               apart mid-rotation) counts at its deepest step (hdrStep = the steps' spread): the largest cover.
  hdr          header thickness along n (empty when its top edge is cut by the display mid-rotation).
  lateral      along the tangent u: the header's and the content's left / right edges (red vs the rows' ends against
               the background); latMis = the largest |difference| over the sides where both edges are visible;
               latMisMin = a lower bound where one of them runs off the display (its visible extreme past the other's
               edge).
  after        header-only frames: content = some content color is visible on the content side of the header's bottom
               edge (its top not derivable), edge = none at all (the content is off screen; gapMin = the blue run past
               the header's bottom to the display's or the window's edge, a lower bound of the gap).
  *_c          positions along n (lateral: along u) relative to the display centre, in points.

A frame is a transition frame when the header or content geometry moved > 0.5 pt since the previous frame or the band's
angle is not a multiple of 90 deg (> 0.5 deg off). Segments (one per stimulus) are runs of frames that changed at all
(> 0.1 pt), bridged across holes < 0.4 s; rest spans lie between them. Per segment the jump detector is the largest
single-frame step of the header's thickness, its bottom edge and the content's top as a fraction of the change from the
rest before to the rest after (1.0 = all in one frame; partial = the rest before had no value, the change is counted
from the segment's first measured frame), also per 60 Hz interval. Frames are in decode (capture) order; the 17.5
recorder can write scrambled pts, so t is indicative only (summary.timestampsMonotonic).
Outputs frames.csv, summary.json and worst-*.png (annotated: white = header bottom, cyan = header top, black = content
top (extrapolated under the header), grey = row boundaries used, orange = lateral edges).
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
ROW_PT = 60.0
ROWS = 40
MOVE_PT = 0.5
ANGLE_DEG = 0.5
STIR_PT = 0.1
STIR_DEG = 0.05
BRIDGE_S = 0.4
AGREE_DEG = 1.0          # lines of one frame must agree this well
CHECK_LINE_PT = 30.0     # lines this long or longer take part in the angle agreement check
MIN_LINE_PT = 8.0        # shorter lines are not used
SPLIT_PT = 2.0
AMBIG_PT = 30.0

OTHER, RED, GREEN, BLUE, YELLOW, MAGENTA, BLACK, CYAN = range(8)
NAMES = "?RGBYMKC"
SHIFTS = ((0, 3), (3, 0), (2, 2), (2, -2))      # (dy, dx): pixel pairs 3 px apart
NORMALISH = 0.9                                  # |step . normal| for a pair to cross a line along that normal
CONTENT_SET = (GREEN, YELLOW, MAGENTA, CYAN)
BELOW_HDR = (GREEN, YELLOW, MAGENTA, BLUE, CYAN)
# v2.2: the optional marker row (`-ZTronSeamMarker 1`): row 4 cyan, content y 320..380.
MARKER_TOP_PT = GREEN_PT + ROW_PT * 4
MARKER_FAR_PT = MARKER_TOP_PT + ROW_PT
# Content edges along n: green->yellow (content y 80), yellow->magenta / magenta->yellow (80 + 60k), blue->green (the
# green row's top facing the background), green->blue (its far edge facing the background: a row drawn apart from the
# next one, as the 27.0 rotation does), blue->yellow (a yellow row's top facing the background: the same).
CONTENT_KINDS = ("GY", "YM", "MY", "BG", "GB", "BY", "MC", "CM")


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


def label(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hi, lo = 150, 100
    rh, gh, bh = r > hi, g > hi, b > hi
    rl, gl, bl = r < lo, g < lo, b < lo
    L = np.zeros(a.shape[:2], np.uint8)
    L[rh & gl & bl] = RED
    L[gh & rl & bl] = GREEN
    L[bh & rl & gl] = BLUE
    L[rh & gh & bl] = YELLOW
    L[rh & bh & gl] = MAGENTA
    L[(r < 40) & (g < 40) & (b < 40)] = BLACK
    # An anti-aliased red/green edge blends to yellow, a red/blue one to magenta and a yellow/magenta one to red (a 1-2
    # px line along the edge, mid-rotation): such a pixel within 2 px of both colors it lies between is a blend.
    yel, mag = dilate(L == YELLOW, 2), dilate(L == MAGENTA, 2)
    L[(L == RED) & yel & mag] = OTHER
    red = dilate(L == RED, 2)
    L[(L == YELLOW) & red & dilate(L == GREEN, 2)] = OTHER
    L[(L == MAGENTA) & red & dilate(L == BLUE, 2)] = OTHER
    # v2.2 marker: cyan; a cyan/magenta edge blends towards blue (a thin line along the marker's edges).
    cyan = gh & bh & rl
    if cyan.any():
        L[cyan] = CYAN
        L[(L == BLUE) & dilate(cyan, 2) & dilate(L == MAGENTA, 2)] = OTHER
    return L


def dilate(m, r):
    """Square dilation of a boolean mask by r px (separable shifts)."""
    out = m.copy()
    for k in range(1, r + 1):
        out[k:, :] |= m[:-k, :]
        out[:-k, :] |= m[k:, :]
    m2 = out.copy()
    for k in range(1, r + 1):
        out[:, k:] |= m2[:, :-k]
        out[:, :-k] |= m2[:, k:]
    return out


def edge_points(L):
    """Differently labelled pixel pairs 3 px apart: their midpoint (px), the unit step from the first to the second and
    both labels (unlabelled pixels, the h264 blend at an edge, take no part)."""
    h, w = L.shape
    P, D, A, B = [], [], [], []
    for dy, dx in SHIFTS:
        x0, x1 = max(0, -dx), w - max(0, dx)
        a = L[: h - dy, x0:x1]
        b = L[dy:, x0 + dx: x1 + dx]
        m = (a != b) & (a != 0) & (b != 0)
        yy, xx = np.nonzero(m)
        A.append(a[yy, xx])
        B.append(b[yy, xx])
        P.append(np.stack([xx + x0 + 0.5 + dx / 2.0, yy + 0.5 + dy / 2.0], 1))
        ln = math.hypot(dx, dy)
        D.append(np.broadcast_to(np.array([dx / ln, dy / ln]), (len(xx), 2)))
    return (np.concatenate(P), np.concatenate(D), np.concatenate(A), np.concatenate(B))


def tls(Q):
    mu = Q.mean(0)
    q = Q - mu
    ev, evec = np.linalg.eigh(q.T @ q)
    return evec[:, 0], mu, q.T @ q


def hough(P, prior=None, span=30.0):
    """Normal angle (radians) whose projections of the points are sharpest (sum of squared histogram counts, two bin
    phases): the common normal of a family of parallel lines. Coarse (0.5 deg, 3 px bins) within +-span of `prior`, or
    over 180 deg; then fine (0.05 deg, 1 px bins)."""
    if len(P) > 8000:
        P = P[:: len(P) // 8000 + 1]
    P = P - P.mean(0)

    def best(ths, binw):
        sc = []
        for th in ths:
            s = P[:, 0] * math.cos(th) + P[:, 1] * math.sin(th)
            s = (s - s.min()) / binw
            c1 = np.bincount(s.astype(np.int64)).astype(np.float64)
            c2 = np.bincount((s + 0.5).astype(np.int64)).astype(np.float64)
            sc.append((c1 * c1).sum() + (c2 * c2).sum())
        return ths[int(np.argmax(sc))]

    if prior is None:
        ths = np.radians(np.arange(0.0, 180.0, 0.5))
    else:
        ths = prior + np.radians(np.arange(-span, span + 1e-9, 0.5))
    th = best(ths, 3.0)
    return best(th + np.radians(np.arange(-0.6, 0.6 + 1e-9, 0.05)), 1.0)


class Line:
    """A straight edge: normal n (unit, oriented like the family's), centroid mu (px), own-fit angle, inlier scatter."""

    def __init__(self, kind, n, mu, scat, npts, t0, t1, rms):
        self.kind, self.n, self.mu, self.scat, self.npts = kind, n, mu, scat, npts
        self.t0, self.t1, self.rms = t0, t1, rms
        self.length = t1 - t0
        self.s = None          # refined position along the joint normal, px from the display centre
        self.tc = None         # centre along the joint tangent, px from the display centre


def find_lines(kind, Q, n, min_pts=12, max_lines=12):
    """Straight lines among the points Q whose normal is close to n: peaks of the histogram of their projections on n,
    then a total least squares fit per peak (twice: the peak's points, then every point within 2.5 px of the fit)."""
    if len(Q) < min_pts:
        return []
    u = np.array([n[1], -n[0]])
    s = Q @ n
    lo = math.floor(s.min())
    idx = (s - lo).astype(np.int64)
    c = np.bincount(idx).astype(np.float64)
    cs = np.convolve(c, [0.25, 0.5, 0.25], "same")
    out = []
    taken = np.zeros(len(Q), bool)
    for _ in range(max_lines):
        k = int(np.argmax(cs))
        if cs[k] < 4:
            break
        cs[max(0, k - 6): k + 7] = 0
        m = (np.abs(s - (lo + k + 0.5)) < 4) & ~taken
        if m.sum() < min_pts:
            continue
        nn, mu, _ = tls(Q[m])
        if angle_between(nn, n) > 10.0:
            nn = n                    # a short peak: widen along the family's normal
        for _pass in range(2):
            if nn @ n < 0:
                nn = -nn
            r = (Q - mu) @ nn
            m = (np.abs(r) < 2.5) & ~taken
            if m.sum() < min_pts:
                break
            nn, mu, scat = tls(Q[m])
        else:
            if nn @ n < 0:
                nn = -nn
            uu = np.array([nn[1], -nn[0]])
            if uu @ u < 0:
                uu = -uu
            # The densest run along the line (collinear crossings of other edges lie apart from it).
            ids = np.nonzero(m)[0]
            t = (Q[ids] - mu) @ uu
            o = np.argsort(t)
            ts = t[o]
            cuts = np.nonzero(np.diff(ts) > 12.0)[0]
            starts = np.concatenate([[0], cuts + 1])
            ends = np.concatenate([cuts + 1, [len(ts)]])
            j = int(np.argmax(ends - starts))
            if ends[j] - starts[j] < len(ts):
                m = np.zeros(len(Q), bool)
                m[ids[o[starts[j]:ends[j]]]] = True
                if m.sum() < min_pts:
                    continue
                nn, mu, scat = tls(Q[m])
                if nn @ n < 0:
                    nn = -nn
            q = Q[m] - mu
            t = q @ uu
            t0, t1 = np.percentile(t, [0.5, 99.5])
            rms = float(np.sqrt(((q @ nn) ** 2).mean()))
            # A real edge yields pairs all along it (> 1 per px); scattered crossings of other edges by near-parallel
            # pairs do not.
            if angle_between(nn, n) > 10.0 or m.sum() < 0.5 * (t1 - t0):
                continue
            taken |= m
            out.append(Line(kind, nn, mu, scat, int(m.sum()), float(t0), float(t1), rms))
    return out


def angle_between(n1, n2):
    """Unsigned angle between two line normals (deg, 0..90)."""
    c = abs(float(n1 @ n2))
    return math.degrees(math.acos(min(1.0, c)))


def joint_normal(lines, n0):
    S = sum(l.scat for l in lines)
    ev, evec = np.linalg.eigh(S)
    n = evec[:, 0]
    return n if n @ n0 >= 0 else -n


def wrap(x, period):
    return (x + period / 2) % period - period / 2


class Analyzer:
    def __init__(self, w, h, scale):
        self.w, self.h, self.scale = w, h, scale
        self.X = (np.arange(w, dtype=np.float32) + 0.5)[None, :].repeat(h, 0)
        self.Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None].repeat(w, 1)
        self.centre = np.array([w / 2.0, h / 2.0])
        # Every 3rd pixel, for the coarse pixel checks (content side, candidate green rows, lateral extremes).
        self.sx = self.X[1::3, 1::3] - self.centre[0]
        self.sy = self.Y[1::3, 1::3] - self.centre[1]
        self.prev_n = None
        self.prev_n_frame = -999
        self.hist = []          # (frame index, content top along n in pt) of the measured content tops
        self.i = -1

    # ---- sub-pixel edge position --------------------------------------------------------------------------------
    def refine(self, L, n, u, s, tc, half, a_set, b_set, reach=7.0):
        """Position (px along n from the display centre) of the edge from a_set (-n side) to b_set (+n side) near s:
        the coverage profiles of both sides across a strip (|t - tc| < half), each bin placed at the mean position of
        its pixels; the edge is the mean of the two 0.5 crossings (the h264 blend between them is neither). Returns
        (s, refined?)."""
        c = self.centre
        half = min(max(3.0, half), 240.0)
        pts = [c + n * (s + ds) + u * (tc + dt) for ds in (-reach, reach) for dt in (-half, half)]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1 = max(0, int(math.floor(min(xs)))), min(self.w, int(math.ceil(max(xs))) + 1)
        y0, y1 = max(0, int(math.floor(min(ys)))), min(self.h, int(math.ceil(max(ys))) + 1)
        if x1 - x0 < 1 or y1 - y0 < 1:
            return s, False
        X, Y = self.X[y0:y1, x0:x1], self.Y[y0:y1, x0:x1]
        S = (X - c[0]) * n[0] + (Y - c[1]) * n[1] - s
        T = (X - c[0]) * u[0] + (Y - c[1]) * u[1] - tc
        inside = (np.abs(S) < reach) & (np.abs(T) < half)
        Ss = S[inside]
        if len(Ss) < 20:
            return s, False
        Ls = L[y0:y1, x0:x1][inside]
        nb = int(2 * reach)
        idx = np.clip(np.floor(Ss + reach).astype(np.int64), 0, nb - 1)
        tot = np.bincount(idx, minlength=nb).astype(np.float64)
        pos = np.bincount(idx, weights=Ss, minlength=nb) / np.maximum(tot, 1)
        fa = np.bincount(idx, weights=np.isin(Ls, a_set), minlength=nb) / np.maximum(tot, 1)
        fb = np.bincount(idx, weights=np.isin(Ls, b_set), minlength=nb) / np.maximum(tot, 1)
        valid = tot >= 0.3 * tot.max()
        cands = []
        for f, falling in ((fa, True), (fb, False)):
            best = None
            for k in range(1, nb):
                if not (valid[k] and valid[k - 1]):
                    continue
                hit = (f[k - 1] >= 0.5 > f[k]) if falling else (f[k - 1] < 0.5 <= f[k])
                if hit:
                    x = pos[k - 1] + (f[k - 1] - 0.5) / (f[k - 1] - f[k]) * (pos[k] - pos[k - 1])
                    if best is None or abs(x) < abs(best):
                        best = x
            if best is not None:
                cands.append(best)
        if not cands:
            return s, False
        e = sum(cands) / len(cands)
        if abs(e) > 3.0:
            return s, False
        return s + e, True

    def place(self, L, line, n, u, a_set, b_set):
        """Position of a line along the joint normal n, refined from the pixels."""
        c = self.centre
        s0 = float((line.mu - c) @ n)
        tc = float((line.mu - c) @ u) + (line.t0 + line.t1) / 2
        half = (line.t1 - line.t0) / 2 - 3
        line.tc = tc
        line.s, line.refined = self.refine(L, n, u, s0, tc, half, a_set, b_set)
        return line.s

    # ---- one frame ----------------------------------------------------------------------------------------------
    def frame(self, a, index):
        self.i = index
        L = label(a)
        counts = np.bincount(L.ravel(), minlength=7)
        npx = L.size
        pure = counts[1:6].sum() / npx
        # The seam lab is all pure colors (a few unlabelled pixels: status bar, button, edge blends); the home screen's
        # wallpaper passes the pure-color share on 17.5 but leaves half its pixels unlabelled.
        other = counts[OTHER] / npx
        row = {"app": bool(pure > 0.4 and other < 0.1), "pure": round(float(pure), 3),
               "blue": round(float(counts[BLUE] / npx), 4)}
        if not row["app"]:
            return row, None
        sc = self.scale
        c = self.centre
        P, D, A, B = edge_points(L)
        isp = lambda X, vals: np.isin(X, vals)  # noqa: E731
        stripe = ((A == GREEN) & (B == YELLOW)) | ((A == YELLOW) & (B == GREEN)) | \
                 ((A == YELLOW) & (B == MAGENTA)) | ((A == MAGENTA) & (B == YELLOW))
        recent = self.prev_n is not None and index - self.prev_n_frame <= 30
        prior = math.atan2(self.prev_n[1], self.prev_n[0]) if recent else None
        if stripe.sum() >= 60:
            th = hough(P[stripe], None)
            fam = "rows"
        else:
            hdr_pts = ((A == RED) & isp(B, BELOW_HDR)) | ((B == RED) & isp(A, BELOW_HDR)) | \
                      ((A == BLUE) & (B == GREEN)) | ((A == GREEN) & (B == BLUE))
            if hdr_pts.sum() < 60:
                row["band"] = "none"
                return row, None
            # The header's edges come in two perpendicular families (bottom / top, and its sides). The recorder can
            # drop frames mid-rotation (45 deg between two decoded frames), so the previous frame's angle is no
            # guide: the band normal is the family along which the red region is thinner (the header is wider than
            # thick in every lab layout, clipped or not); the previous angle only breaks a near tie.
            th = hough(P[hdr_pts], None)
            fam = "header"
            lab3 = L[1::3, 1::3]
            red3 = lab3 == RED
            if red3.sum() > 200:
                ext = []
                for t_ in (th, th + math.pi / 2):
                    s_ = self.sx[red3] * math.cos(t_) + self.sy[red3] * math.sin(t_)
                    lo_, hi_ = np.percentile(s_, [1, 99])
                    ext.append(hi_ - lo_)
                if ext[1] < 0.8 * ext[0]:
                    th = th + math.pi / 2
                elif ext[1] < 1.25 * ext[0] and prior is not None:
                    alt = th + math.pi / 2
                    if abs(math.cos(alt - prior)) > abs(math.cos(th - prior)):
                        th = alt
                th = hough(P[hdr_pts], th, span=3.0)
        n = np.array([math.cos(th), math.sin(th)])

        # Orientation of n (header -> content): continuity with the last measured frame (unless n turned by more
        # than 60 deg since: dropped frames; torn content can show yellow before green, so the green vote comes
        # second); else the green row before the yellow one; else the header before the content; else downwards.
        dn = D @ n
        nish = np.abs(dn) >= NORMALISH
        gy = nish & (((A == GREEN) & (B == YELLOW)) | ((A == YELLOW) & (B == GREEN)))
        vote = float((np.sign(dn[gy]) * np.where(A[gy] == GREEN, 1.0, -1.0)).sum())
        how = None
        if recent and self.prev_n is not None and abs(n @ self.prev_n) >= 0.5:
            if n @ self.prev_n < 0:
                n = -n
            how = "continuity"
        elif gy.sum() >= 30 and abs(vote) >= 0.5 * gy.sum():
            if vote < 0:
                n = -n
            how = "green"
        else:
            lab = L[1::3, 1::3]
            red = lab == RED
            cnt = isp(lab, CONTENT_SET)
            if red.sum() > 200 and cnt.sum() > 200:
                d = np.array([self.sx[cnt].mean() - self.sx[red].mean(), self.sy[cnt].mean() - self.sy[red].mean()])
                if d @ n < 0:
                    n = -n
                how = "centroid"
            else:
                if n[1] < 0 or (n[1] == 0 and n[0] < 0):
                    n = -n
                how = "default"
        dn = D @ n
        nish = np.abs(dn) >= NORMALISH
        fwd = dn > 0
        F = np.where(fwd, A, B)       # first label along +n
        G = np.where(fwd, B, A)       # second label along +n

        # Lines parallel to the band.
        fam_lines = {}
        for kind, a_l, b_l in (("GY", GREEN, YELLOW), ("YM", YELLOW, MAGENTA), ("MY", MAGENTA, YELLOW),
                               ("BG", BLUE, GREEN), ("GB", GREEN, BLUE), ("BY", BLUE, YELLOW),
                               ("MC", MAGENTA, CYAN), ("CM", CYAN, MAGENTA)):
            sel = nish & (F == a_l) & (G == b_l)
            fam_lines[kind] = [l for l in find_lines(kind, P[sel], n) if l.length / sc >= MIN_LINE_PT]
        sel = nish & (F == RED) & isp(G, BELOW_HDR)
        hb = [l for l in find_lines("HB", P[sel], n) if l.length / sc >= MIN_LINE_PT]
        sel = nish & isp(F, BELOW_HDR) & (G == RED)
        ht = [l for l in find_lines("HT", P[sel], n) if l.length / sc >= MIN_LINE_PT]
        # The header's bottom edge. A stepped one (the .fit header's aspect view and its frame animate apart
        # mid-rotation: parallel red edges at different depths) counts at its deepest step of 20 pt or more, so the
        # seam is the largest cover / the smallest gap; hdrStep = deepest - shallowest.
        hdr_bot, hdr_step = None, 0.0
        if hb:
            main = max(hb, key=lambda l: l.npts)
            d0 = float(main.mu @ n)
            big = [l for l in hb if l is main or (l.length / sc >= 20.0 and abs(float(l.mu @ n) - d0) <= 40 * sc)]
            depth = {id(l): float(l.mu @ n) for l in big}
            hdr_bot = max(big, key=lambda l: depth[id(l)])
            hdr_step = (max(depth.values()) - min(depth.values())) / sc
            row["hdrStep"] = round(hdr_step, 3)
        # The header's top: the strongest X->red edge on the far side of its bottom edge.
        if hdr_bot is not None:
            ht = [l for l in ht if float((l.mu - hdr_bot.mu) @ n) < -3]
        hdr_top = max(ht, key=lambda l: l.npts) if ht else None
        content = [l for k in CONTENT_KINDS for l in fam_lines[k]]
        if not content and hdr_bot is None:
            row["band"] = "none"
            return row, None

        # Joint normal and the angle agreement check.
        n_cont = joint_normal(content, n) if content else None
        allv = content + ([hdr_bot] if hdr_bot is not None else []) + ([hdr_top] if hdr_top is not None else [])
        nj = joint_normal(allv, n)
        spread, worst = 0.0, None
        for l in content:
            if l.length / sc >= CHECK_LINE_PT:
                d = angle_between(l.n, n_cont)
                if d > spread:
                    spread, worst = d, l.kind
        for l in (hdr_bot, hdr_top):
            if l is not None and l.length / sc >= CHECK_LINE_PT:
                ref = n_cont if n_cont is not None and sum(x.npts for x in content) > 200 else nj
                d = angle_between(l.n, ref)
                if d > spread:
                    spread, worst = d, l.kind
        n = nj
        u = np.array([n[1], -n[0]])
        ang = round(math.degrees(math.atan2(u[1], u[0])), 3) % 180.0
        dev = min(ang % 90.0, 90.0 - ang % 90.0)
        row.update(angle=round(ang, 3), angleDev=round(dev, 3), nx=round(float(n[0]), 5), ny=round(float(n[1]), 5),
                   family=fam, orient=how, angleSpread=round(spread, 3), lines=len(allv))
        self.prev_n, self.prev_n_frame = n, index
        geo = {"c": c, "n": n, "u": u, "lines": [], "lat": []}
        if spread > AGREE_DEG:
            row["band"] = "reject"
            row["angleWorst"] = worst
            return row, geo

        # Positions.
        sets = {"GY": ((GREEN,), (YELLOW,)), "YM": ((YELLOW,), (MAGENTA,)), "MY": ((MAGENTA,), (YELLOW,)),
                "BG": ((BLUE,), (GREEN,)), "GB": ((GREEN,), (BLUE,)), "BY": ((BLUE,), (YELLOW,)),
                "MC": ((MAGENTA,), (CYAN,)), "CM": ((CYAN,), (MAGENTA,)),
                "HB": ((RED,), BELOW_HDR), "HT": (BELOW_HDR, (RED,))}
        for l in allv:
            self.place(L, l, n, u, *sets[l.kind])
            geo["lines"].append((l.kind, l.s, l.tc - l.length / 2, l.tc + l.length / 2))

        # The header.
        hb_c = ht_c = float("nan")
        lab3 = L[1::3, 1::3]
        S3 = self.sx * n[0] + self.sy * n[1]
        T3 = self.sx * u[0] + self.sy * u[1]
        red3 = lab3 == RED
        if red3.sum() > 50:
            rt = T3[red3]
            rlo, rhi = np.percentile(rt, [0.2, 99.8])
            row["hdrLen"] = round(float(rhi - rlo) / sc, 3)
        if hdr_bot is not None:
            hb_c = hdr_bot.s / sc
            row.update(hdr_bot_c=round(hb_c, 3))
            at_border = False
            if hdr_top is not None:
                ht_c = hdr_top.s / sc
            elif red3.sum() > 50:
                # No visible top edge: the header runs into the window's / the display's edge. Axis-aligned that edge
                # is the window's (landscape top0 = 0) and the thickness holds; mid-rotation it is unknown.
                sel = red3 & (np.abs(T3 - hdr_bot.tc) < max(30.0, hdr_bot.length / 2))
                if sel.sum() > 20 and dev <= ANGLE_DEG:
                    edge = self.border_along(-n, hdr_bot.tc, u)
                    if edge is not None and float(S3[sel].min()) <= -edge + 6:
                        ht_c = -edge / sc
                at_border = True
            if not math.isnan(ht_c):
                row.update(hdr_top_c=round(ht_c, 3), hdr=round(hb_c - ht_c, 3))
            else:
                row["hdr"] = float("nan")
            row["hdrAtBorder"] = int(at_border)
            if red3.sum() > 50:
                vis = S3[red3]
                row["hdrVisible"] = round(float(hb_c - np.percentile(vis, 0.2) / sc), 3)

        # The content's top.
        ct = self.content_top(L, fam_lines, hdr_bot, n, u, S3, T3, lab3, row)
        if not math.isnan(ct):
            hist_ok = row.get("ctopAmb", 0) == 0
            if hist_ok:
                self.hist.append((index, ct))
            row["ctop_c"] = row["content_top_c"] = round(ct, 3)
            tl = [l for k in CONTENT_KINDS for l in fam_lines[k]]
            t_lo = min(l.tc - l.length / 2 for l in tl)
            t_hi = max(l.tc + l.length / 2 for l in tl)
            geo["lines"].append(("CT", ct * sc, t_lo, t_hi))

        # Seam, or what follows a header whose content top is unknown.
        if hdr_bot is not None and not math.isnan(ct):
            seam = ct - hb_c
            row.update(band="ok", seam=round(seam, 3), overlap=round(max(0.0, -seam), 3),
                       gap=round(max(0.0, seam), 3))
        elif hdr_bot is not None:
            row["band"] = "header"
            cnt3 = isp(lab3, CONTENT_SET)
            side = cnt3 & (S3 > hdr_bot.s + 3)
            if side.sum() >= 30:
                row["after"] = "content"
            else:
                row["after"] = "edge"
                row["gapMin"] = round(self.blue_run(L, n, u, hdr_bot, T3, red3) / sc, 3)
        else:
            row["band"] = "content"

        # Lateral edges along u.
        self.lateral(L, P, D, A, B, n, u, row, geo, T3, lab3, red3, sc)
        return row, geo

    def border_along(self, v, tc, u):
        """Distance (px) from the display centre to the display's edge along v, on the line through the centre + u*tc."""
        p = self.centre + u * tc
        best = None
        for k, lim in ((0, self.w), (1, self.h)):
            if abs(v[k]) < 1e-9:
                continue
            for edge in (0.0, float(lim)):
                d = (edge - p[k]) / v[k]
                if d > 0:
                    q = p + v * d
                    if -1 <= q[0] <= self.w + 1 and -1 <= q[1] <= self.h + 1:
                        best = d if best is None else min(best, d)
        return best

    def blue_run(self, L, n, u, hdr_bot, T3, red3):
        """The blue run past the header's bottom edge along n (px), in a strip at 10-30 % of the header's visible length
        (off the home indicator at the centre), up to the first non-blue bin or the display's edge."""
        rt = T3[red3]
        if len(rt) < 20:
            return 0.0
        tlo, thi = np.percentile(rt, [0.5, 99.5])
        tc, hw = tlo + 0.2 * (thi - tlo), 0.1 * (thi - tlo)
        c = self.centre
        s0 = hdr_bot.s
        reach = 2.0 * max(self.w, self.h)
        pts = [c + n * (s0 + ds) + u * (tc + dt) for ds in (0, reach) for dt in (-hw, hw)]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1 = max(0, int(min(xs)) - 1), min(self.w, int(max(xs)) + 2)
        y0, y1 = max(0, int(min(ys)) - 1), min(self.h, int(max(ys)) + 2)
        X, Y = self.X[y0:y1, x0:x1], self.Y[y0:y1, x0:x1]
        S = (X - c[0]) * n[0] + (Y - c[1]) * n[1] - s0
        T = (X - c[0]) * u[0] + (Y - c[1]) * u[1] - tc
        inside = (np.abs(T) < hw) & (S >= 0) & (S < reach)
        idx = S[inside].astype(np.int64)
        nb = int(reach) + 1
        tot = np.bincount(idx, minlength=nb).astype(np.float64)
        fb = np.bincount(idx, weights=(L[y0:y1, x0:x1][inside] == BLUE), minlength=nb) / np.maximum(tot, 1)
        valid = tot > 0.5 * 2 * hw
        k = 0
        while k < 4 and k < nb and valid[k] and fb[k] < 0.5:      # the edge's blend
            k += 1
        while k < nb and valid[k] and fb[k] >= 0.5:
            k += 1
        return float(k)

    def content_top(self, L, fam, hdr_bot, n, u, S3, T3, lab3, row):
        """Content top along n (pt from the display centre) from any visible content boundary; nan when none."""
        sc = self.scale
        gy, bg = fam["GY"], fam["BG"]
        rows = [(l, 1) for l in fam["YM"]] + [(l, 2) for l in fam["MY"]]
        hb = hdr_bot.s / sc if hdr_bot is not None else None
        # Stripe phase (content top modulo 120 pt).
        phase, resid = None, 0.0
        if rows:
            bases = [(l.s / sc - GREEN_PT - ROW_PT * k0, l.length) for l, k0 in rows]
            ang = [2 * math.pi * b / (2 * ROW_PT) for b, _ in bases]
            sx = sum(w * math.sin(a) for (b, w), a in zip(bases, ang))
            cx = sum(w * math.cos(a) for (b, w), a in zip(bases, ang))
            phase = math.atan2(sx, cx) / (2 * math.pi) * 2 * ROW_PT
            resid = max(abs(wrap(b - phase, 2 * ROW_PT)) for b, _ in bases)
        split = resid > SPLIT_PT
        anchors = []            # (source, content top, the line's own position), pt
        if gy:
            l = max(gy, key=lambda x: x.length)
            anchors.append(("green", l.s / sc - GREEN_PT, l.s / sc))
        if bg:
            l = max(bg, key=lambda x: x.length)
            anchors.append(("greentop", l.s / sc, l.s / sc))
        if fam["GB"]:
            l = max(fam["GB"], key=lambda x: x.length)
            anchors.append(("greenfar", l.s / sc - GREEN_PT, l.s / sc))
        if fam["MC"]:
            l = max(fam["MC"], key=lambda x: x.length)
            anchors.append(("marker", l.s / sc - MARKER_TOP_PT, l.s / sc))
        if fam["CM"]:
            l = max(fam["CM"], key=lambda x: x.length)
            anchors.append(("marker", l.s / sc - MARKER_FAR_PT, l.s / sc))
        ct, src, k_used, amb = float("nan"), None, None, 0
        # v2.1: the green row's far edge facing the background with no other content edge anywhere (no green -> yellow,
        # no background -> green, no row boundary, no yellow top facing the background) is the VIEWPORT's clip, not the
        # row's far edge: in the lab the green row is always followed by the yellow one, so a far edge with nothing
        # beyond it means the content is cut there (e.g. the last frames of a rotation, the green row passing under the
        # container's clip). The content top is then not derivable (the strip may be the row's start, its end or both):
        # the frame is unresolved (ctopSrc greenclip, ctopAmb 1, out of the maxima; the greenfar reading is the
        # largest overlap it could hide).
        clip_only = (len(anchors) == 1 and anchors[0][0] == "greenfar" and not rows and not fam["BY"])
        if anchors:
            # Torn content (the 27.0 rotation draws the green row at its old place and the next rows at their new one):
            # the anchor nearest the header's bottom edge sets the content top, i.e. what meets the header; the others
            # raise ctopSplit. Rigid content: they all agree.
            if hb is not None:
                anchors.sort(key=lambda a_: abs(a_[2] - hb))
            src, ct, _ = anchors[0]
            for _, v, _ in anchors[1:]:
                split = split or abs(v - ct) > SPLIT_PT
            if phase is not None and abs(wrap(ct - phase, 2 * ROW_PT)) > SPLIT_PT:
                split = True
            k_used = 0
            if clip_only:
                src, amb = "greenclip", 1
        elif rows:
            # Candidates phase + 120 m: every visible boundary must be one of the rows (1 <= k <= 39).
            ub = min(l.s / sc - GREEN_PT - ROW_PT * k0 for l, k0 in rows)
            lb = max(l.s / sc - GREEN_PT - ROW_PT * (ROWS - 1) for l, _ in rows)
            m_hi = math.floor((ub - phase) / (2 * ROW_PT) + 0.05)
            m_lo = math.ceil((lb - phase) / (2 * ROW_PT) - 0.05)
            cands = [phase + 2 * ROW_PT * m for m in range(m_lo, m_hi + 1)]
            t_lo = min(l.tc - l.length / 2 for l, _ in rows)
            t_hi = max(l.tc + l.length / 2 for l, _ in rows)
            ok = [x for x in cands if self.green_hidden(x, S3, T3, lab3, t_lo, t_hi)]
            row["ctopCands"] = len(ok)
            if ok:
                pred = self.predict()
                if pred is not None:
                    pred, age = pred
                    ranked = sorted(ok, key=lambda x: abs(x - pred))
                    ct = ranked[0]
                    # Clear-cut only when the winner is near a fresh prediction (the previous frame or the one before)
                    # and the next candidate is far from it.
                    runner = abs(ranked[1] - pred) - abs(ct - pred) if len(ranked) > 1 else float("inf")
                    amb = int(abs(ct - pred) > AMBIG_PT or (len(ranked) > 1 and (age > 2 or runner < 2 * AMBIG_PT)))
                else:
                    ct = max(ok)          # no history: the smallest overlap (the green row just hidden)
                    amb = int(len(ok) > 1)
                src = "rows"
                l0 = min((l for l, _ in rows), key=lambda x: x.s)
                k_used = int(round((l0.s / sc - ct - GREEN_PT) / ROW_PT))
        if src is None:
            return float("nan")
        # A yellow row's top facing the background must still be one of the yellow rows (80 + 120 j).
        for l in fam["BY"]:
            split = split or abs(wrap(l.s / sc - ct - GREEN_PT, 2 * ROW_PT)) > SPLIT_PT
        row.update(ctopSrc=src, ctopK=k_used, ctopAmb=amb, ctopSplit=int(split), rowResid=round(resid, 3),
                   contentRows=sum(len(fam[k]) for k in CONTENT_KINDS))
        if gy or fam["GB"]:
            g1 = max(gy or fam["GB"], key=lambda x: x.length).s / sc
            top = max(ct, hb) if hb is not None else ct
            row.update(green_top_c=round(ct, 3), green_bot_c=round(g1, 3), greenVis=round(g1 - top, 3),
                       greenShort=round(max(0.0, GREEN_PT - (g1 - top)), 3))
        if hb is not None:
            past = [l.s / sc for l in fam["GY"] + fam["YM"] + fam["MY"] if l.s / sc > hb + 0.5]
            if past:
                row["content_mark_c"] = round(min(past), 3)
        return ct

    def green_hidden(self, ct, S3, T3, lab3, t_lo, t_hi):
        """A candidate content top is consistent when the green row it implies shows no visible yellow, magenta or blue
        (within the rows' visible lateral extent): the green row must be covered or off screen."""
        sc = self.scale
        band = (S3 > (ct + 3) * sc) & (S3 < (ct + GREEN_PT - 3) * sc) & (T3 > t_lo + 6) & (T3 < t_hi - 6)
        nb = int(band.sum())
        if nb == 0:
            return True
        bad = int(np.isin(lab3[band], (YELLOW, MAGENTA, BLUE, CYAN)).sum())
        return bad <= max(10, 0.03 * nb)

    def predict(self):
        """Content top predicted from the history (the last value, plus its velocity when the last two are adjacent),
        with its age in frames; None without a value in the last 40 frames."""
        if not self.hist:
            return None
        i1, c1 = self.hist[-1]
        if self.i - i1 > 40:
            return None
        if len(self.hist) >= 2:
            i0, c0 = self.hist[-2]
            if i1 - i0 == 1 and self.i - i1 <= 2:
                return c1 + (c1 - c0) * (self.i - i1), self.i - i1
        return c1, self.i - i1

    def lateral(self, L, P, D, A, B, n, u, row, geo, T3, lab3, red3, sc):
        """Header and content lateral edges along u, and their misalignment."""
        du = D @ u
        uish = np.abs(du) >= NORMALISH
        fwd = du > 0
        F = np.where(fwd, A, B)
        G = np.where(fwd, B, A)
        side_x = (BLUE, GREEN, YELLOW, MAGENTA)
        edges = {}
        specs = {"HL": (np.isin(F, side_x) & (G == RED), (side_x, (RED,))),
                 "HR": ((F == RED) & np.isin(G, side_x), ((RED,), side_x))}
        # The content's lateral edges from the rows' ends (the 27.0 rotation draws the green row at its old width under
        # the new rows); the green row's only when no row end is visible.
        rows_ym = np.isin(F, (YELLOW, MAGENTA)) | np.isin(G, (YELLOW, MAGENTA))
        if (uish & rows_ym & ((F == BLUE) | (G == BLUE))).sum() >= 20:
            cset = (YELLOW, MAGENTA)
        else:
            cset = (GREEN,)
        specs["CL"] = ((F == BLUE) & np.isin(G, cset), ((BLUE,), cset))
        specs["CR"] = (np.isin(F, cset) & (G == BLUE), (cset, (BLUE,)))
        nl = np.array([-n[0], -n[1]])           # for lines with normal u, the tangent (u_line) is -n
        for k, (sel, (aset, bset)) in specs.items():
            ls = [l for l in find_lines(k, P[uish & sel], u) if l.length / sc >= MIN_LINE_PT]
            if not ls:
                continue
            l = max(ls, key=lambda x: x.npts)
            if angle_between(l.n, u) > 3.0:
                continue
            c = self.centre
            t0 = float((l.mu - c) @ u)
            sc_ = float((l.mu - c) @ nl) + (l.t0 + l.t1) / 2
            half = (l.t1 - l.t0) / 2 - 3
            t, _ = self.refine(L, u, nl, t0, sc_, half, aset, bset)
            edges[k] = t / sc
            row[{"HL": "hdr_l_c", "HR": "hdr_r_c", "CL": "cnt_l_c", "CR": "cnt_r_c"}[k]] = round(t / sc, 3)
            geo["lat"].append((k, t, -sc_ - l.length / 2, -sc_ + l.length / 2))
        mis, mis_min = [], []
        cnt3 = np.isin(lab3, cset)
        ext = {}
        if red3.sum() > 50:
            ext["H"] = np.percentile(T3[red3], [0.1, 99.9]) / sc
        if cnt3.sum() > 50:
            ext["C"] = np.percentile(T3[cnt3], [0.1, 99.9]) / sc
        for side, j, sign in (("L", 0, -1), ("R", 1, 1)):
            h, cc = edges.get("H" + side), edges.get("C" + side)
            if h is not None and cc is not None:
                d = h - cc
                row["lat" + side] = round(d, 3)
                mis.append(abs(d))
            elif h is not None and "C" in ext:
                # The content runs at least to its visible extreme: past the header's edge = a lower bound.
                mis_min.append(max(0.0, sign * (ext["C"][j] - h)))
            elif cc is not None and "H" in ext:
                mis_min.append(max(0.0, sign * (ext["H"][j] - cc)))
        if mis:
            row["latMis"] = round(max(mis), 3)
        lb = max(mis + mis_min) if (mis or mis_min) else None
        if lb is not None:
            row["latMisMin"] = round(lb, 3)


def annotate(a, geo, path):
    img = Image.fromarray(np.ascontiguousarray(a))
    if geo is not None:
        d = ImageDraw.Draw(img)
        c, n, u = geo["c"], geo["n"], geo["u"]
        colors = {"HB": (255, 255, 255), "HT": (0, 255, 255), "CT": (0, 0, 0)}
        for kind, s, t0, t1 in geo["lines"]:
            p, q = c + n * s + u * t0, c + n * s + u * t1
            d.line([tuple(p), tuple(q)], fill=colors.get(kind, (128, 128, 128)), width=7 if kind == "CT" else 5)
        for kind, t, s0, s1 in geo["lat"]:
            p, q = c + u * t + n * s0, c + u * t + n * s1
            d.line([tuple(p), tuple(q)], fill=(255, 140, 0), width=5)
    img.save(path)


def num(v):
    return v is not None and not (isinstance(v, float) and math.isnan(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--meta")
    ap.add_argument("--scale", type=float)
    ap.add_argument("--out")
    ap.add_argument("--dump", default="", help="comma-separated frame indices to save as annotated PNG")
    ap.add_argument("--last", type=int, default=None, help="stop after this frame index (debugging)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    meta = json.load(open(args.meta)) if args.meta else {}
    if not meta:
        mp = os.path.join(os.path.dirname(os.path.abspath(args.video)), "meta.json")
        if os.path.exists(mp):
            meta = json.load(open(mp))
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
        if args.last is not None and i > args.last:
            break
        row, geo = an.frame(a, i)
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
        if row.get("band") == "header" and row.get("after") == "edge" and row.get("gapMin", 0) > 1.0 and \
                (keep.get("offscreen") is None or row["gapMin"] > keep["offscreen"][0]):
            keep["offscreen"] = (row["gapMin"], i, a.copy(), geo)
        if num(row.get("latMis")) and row["latMis"] > 1.0 and \
                (keep.get("lateral") is None or row["latMis"] > keep["lateral"][0]):
            keep["lateral"] = (row["latMis"], i, a.copy(), geo)
        if prev is not None and num(row.get("hdr")) and num(prev[3].get("hdr")):
            step = abs(row["hdr"] - prev[3]["hdr"])
            if hdr_step_best is None or step > hdr_step_best[0]:
                hdr_step_best = (step, prev[0], prev[1], prev[2], i, a.copy(), geo)
        prev = (i, a.copy(), geo, row)

    # Transition frames, over every frame with a measurement: a move > 0.5 pt since the previous frame, or an angle off
    # a multiple of 90 deg (> 0.5 deg).
    measured = [r for r in rows if r.get("band") in ("ok", "header", "content", "reject")]
    keys = ("hdr", "hdr_bot_c", "ctop_c", "gapMin", "hdrLen")
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
    for r in measured:          # the content-top jump counts clear-cut content tops only
        r["_ctop"] = r.get("ctop_c") if not r.get("ctopAmb") else None

    # Segments (one per stimulus): runs of frames that changed at all, bridged across holes shorter than 0.4 s (6
    # frames when the timestamps are scrambled).
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
        rest after; when the rest before has no value, from the segment's first measured frame: partial)."""
        a, b = seg
        series = measured[max(0, a - 1): b + 2]
        after = measured[b + 1] if b + 1 < len(measured) else None
        if after is None or not num(after.get(key)):
            return None
        before = measured[a - 1] if a > 0 else None
        partial = before is None or not num(before.get(key))
        if partial:
            first = next((r for r in series if num(r.get(key))), None)
            if first is None or first is after:
                return None
            before = first
        total = after[key] - before[key]
        steps = [(abs(series[j][key] - series[j - 1][key]), series[j]["frame"]) for j in range(1, len(series))
                 if num(series[j].get(key)) and num(series[j - 1].get(key))]
        unmeasured = sum(1 for r in series if not num(r.get(key)))
        if not steps:
            return None
        big = max(steps)
        by = {r["frame"]: r for r in series}
        prev_t = {series[j]["frame"]: series[j - 1]["t"] for j in range(2, len(series))}

        def per_vsync(step, frame):
            if not mono or frame not in prev_t:
                return step
            return step / max(1, round((by[frame]["t"] - prev_t[frame]) * 60))

        rate = max(per_vsync(st, fr) for st, fr in steps)
        return {"from": before[key], "to": after[key], "totalChange": round(total, 3), "maxStep": round(big[0], 3),
                "atFrame": big[1], "unmeasured": unmeasured, "partial": partial,
                "fraction": round(big[0] / abs(total), 3) if abs(total) >= 1.0 else None,
                "fractionPerVsync": round(rate / abs(total), 3) if abs(total) >= 1.0 else None}

    def argmax(rs, key, sign=1.0):
        best = None
        for r in rs:
            v = r.get(key)
            if num(v) and (best is None or sign * v > sign * best[0]):
                best = (v, r["frame"])
        return best

    def stats(rs):
        # Maxima over the frames whose content top is clear-cut; the ambiguous ones (rows only, no fresh continuity)
        # report apart.
        allseams = [r for r in rs if num(r.get("seam"))]
        seams = [r for r in allseams if not r.get("ctopAmb")]
        g = argmax([r for r in seams if r["seam"] > 0], "seam")
        o = argmax([r for r in seams if r["seam"] < 0], "seam", -1.0)
        oa = argmax([r for r in allseams if r.get("ctopAmb") and r["seam"] < 0], "seam", -1.0)
        lm = argmax(rs, "latMis")
        lmm = argmax(rs, "latMisMin")
        off = [r["gapMin"] for r in rs if r.get("band") == "header" and r.get("after") == "edge"]
        return {"maxGap": g[0] if g else 0.0, "maxGapFrame": g[1] if g else None,
                "maxOverlap": -o[0] if o else 0.0, "maxOverlapFrame": o[1] if o else None,
                "maxOverlapAmbiguous": -oa[0] if oa else None,
                "maxLatMis": lm[0] if lm else None, "maxLatMisFrame": lm[1] if lm else None,
                "maxLatMisMin": lmm[0] if lmm else None, "maxLatMisMinFrame": lmm[1] if lmm else None,
                "seamFrames": len(seams),
                "headerOnly": {k: sum(1 for r in rs if r.get("band") == "header" and r.get("after") == k)
                               for k in ("content", "edge")},
                "ambiguousFrames": sum(1 for r in rs if r.get("ctopAmb")),
                "splitFrames": sum(1 for r in rs if r.get("ctopSplit")),
                "rejectedFrames": sum(1 for r in rs if r.get("band") == "reject"),
                "maxGapMinContentOffscreen": max(off, default=None)}

    segments = []
    for seg in segs:
        rs = measured[seg[0]: seg[1] + 1]
        segments.append({"frames": [rs[0]["frame"], rs[-1]["frame"]], "t": [rs[0]["t"], rs[-1]["t"]], "count": len(rs),
                         **stats(rs), "hdrJump": jump(seg, "hdr"), "hdrBotJump": jump(seg, "hdr_bot_c"),
                         "greenTopJump": jump(seg, "green_top_c"), "contentTopJump": jump(seg, "_ctop")})

    rest = [r for k, r in enumerate(measured) if k not in in_seg]
    rest_seams = [r["seam"] for r in rest if num(r.get("seam"))]
    tr = [r for r in measured if r["transition"]]
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
        "analyzer": 2,
        "video": os.path.abspath(args.video), "meta": meta, "scale": scale, "size": [w, h],
        "frames": len(rows), "appFrames": sum(1 for r in rows if r.get("app")), "measuredFrames": len(measured),
        "timestampsMonotonic": mono,
        "transitionFrames": len(tr),
        "seamFrames": all_stats["seamFrames"],
        "unattributedFrames": sum(1 for r in measured if r.get("band") == "header" and r.get("after") == "content"),
        "greenShortFrames": sum(1 for r in measured if num(r.get("greenShort")) and r["greenShort"] > 1.0),
        "headerOnlyFrames": all_stats["headerOnly"],
        "ambiguousFrames": all_stats["ambiguousFrames"], "splitFrames": all_stats["splitFrames"],
        "rejectedFrames": all_stats["rejectedFrames"],
        "rejected": [{"frame": r["frame"], "angleSpread": r.get("angleSpread"), "worst": r.get("angleWorst")}
                     for r in measured if r.get("band") == "reject"],
        "maxGapMinContentOffscreen": all_stats["maxGapMinContentOffscreen"],
        "maxGap": all_stats["maxGap"], "maxGapFrame": all_stats["maxGapFrame"],
        "maxOverlap": all_stats["maxOverlap"], "maxOverlapFrame": all_stats["maxOverlapFrame"],
        "maxOverlapAmbiguous": all_stats["maxOverlapAmbiguous"],
        "maxLatMis": all_stats["maxLatMis"], "maxLatMisFrame": all_stats["maxLatMisFrame"],
        "maxLatMisMin": all_stats["maxLatMisMin"], "maxLatMisMinFrame": all_stats["maxLatMisMinFrame"],
        "transition": tr_stats, "rest": rest_stats,
        "restSeam": spread(rest_seams), "firstRestSeam": spread(first_rest),
        "hdrJumpFraction": frac("hdrJump"), "hdrBotJumpFraction": frac("hdrBotJump"),
        "greenTopJumpFraction": frac("greenTopJump"), "contentTopJumpFraction": frac("contentTopJump"),
        "perVsync": {k: frac(k, "fractionPerVsync") for k in ("hdrJump", "hdrBotJump", "contentTopJump")},
        "segments": segments, "restSpans": spans,
        "worst": {},
    }
    for name in ("gap", "overlap", "offscreen", "lateral"):
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
            "content_mark_c", "transition",
            # v2
            "family", "orient", "lines", "angleSpread", "angleWorst", "ctopSrc", "ctopK", "ctopAmb", "ctopSplit",
            "ctopCands", "rowResid", "hdr_l_c", "hdr_r_c", "cnt_l_c", "cnt_r_c", "latL", "latR", "latMis",
            "latMisMin", "hdrStep"]
    with open(os.path.join(out, "frames.csv"), "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        wr.writeheader()
        for r in rows:
            wr.writerow({k: r.get(k, "") for k in cols})
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, default=float)
    if args.quiet:
        return
    brief = {k: summary[k] for k in ("frames", "measuredFrames", "transitionFrames", "seamFrames",
                                     "unattributedFrames", "headerOnlyFrames", "ambiguousFrames", "splitFrames",
                                     "rejectedFrames", "maxGapMinContentOffscreen", "maxGap", "maxGapFrame",
                                     "maxOverlap", "maxOverlapFrame", "maxLatMis", "maxLatMisMin", "restSeam",
                                     "firstRestSeam", "hdrJumpFraction", "hdrBotJumpFraction",
                                     "contentTopJumpFraction")}
    print(json.dumps(brief))
    for sp in spans:
        print("rest", json.dumps({k: sp[k] for k in ("frames", "count", "seamMedian", "seamMin", "seamMax", "hdrMedian",
                                                     "headerOnly", "maxGapMinContentOffscreen")}))
    for seg in segments:
        print("segment", json.dumps({k: seg[k] for k in ("frames", "count", "maxGap", "maxOverlap", "maxOverlapFrame",
                                                         "maxLatMis", "maxLatMisMin", "headerOnly",
                                                         "ambiguousFrames", "rejectedFrames",
                                                         "maxGapMinContentOffscreen")}),
              "hdrJump", json.dumps(seg["hdrJump"]), "hdrBotJump", json.dumps(seg["hdrBotJump"]),
              "contentTopJump", json.dumps(seg["contentTopJump"]))


if __name__ == "__main__":
    main()
