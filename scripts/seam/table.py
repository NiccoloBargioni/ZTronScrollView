#!/usr/bin/env python3
"""Seam lab: one table row per measured recording (reads <dir>/summary.json; analyze.py v1 or v2).

usage: python3 -I scripts/seam/table.py [--root R] <dir>...
A <dir> is an analyze.py output directory (summary.json; scripts/seam/reanalyze.py --out-root writes one per recording)
or a recording directory whose v2/ holds one. The row is named after the path below --root (default: the last two path
components).
Columns (points): rest = seam at the first rest (the control reads its inset); gap / ovl = largest gap / largest cover of
the content by the header over the whole run, with the frame (decode index); lat = largest lateral misalignment of the
header's and the content's edges where both are visible [a larger lower bound where one runs off the display]; off =
largest blue run past the header with the content off screen (a lower bound of the gap; n = frames); hJ / cJ = largest
single-frame step of the header's thickness / the content's top as a fraction of the change (1.0 = all in one frame;
- = no change or unmeasured; the maximum over the run's segments; [x] = the same per 60 Hz interval when a recorder or
render hitch inflates it; * = partial: the rest before had no value); frames = transition / measured / decoded; flags =
amb (content top from the rows without a clear-cut choice: kept out of the gap / ovl maxima, its largest overlap shown
apart), split (content anchors disagree), rej (lines not parallel within 1 deg: frame rejected).
"""
import json
import os
import sys


def f(v, d=1):
    return "-" if v is None else (f"{v:.{d}f}" if isinstance(v, (int, float)) else str(v))


def jf(s, key, vkey):
    """The jump fraction per recorded frame, with the per-60-Hz value in brackets when a hitch makes them differ."""
    raw, per = s.get(key), s.get("perVsync", {}).get(vkey)
    partial = any(seg.get(vkey) and seg[vkey].get("partial") and seg[vkey].get("fraction") == raw
                  for seg in s.get("segments", []))
    star = "*" if partial and raw is not None else ""
    if raw is not None and per is not None and abs(raw - per) > 0.05:
        return f"{raw:.2f}{star} [{per:.2f}]"
    return f(raw, 2) + star


def at(v, frame, d=1):
    if v is None:
        return "-"
    return f"{f(v, d)} (f{frame})" if frame is not None and v else f(v, d)


STANDARD = ("-ZTronHeaderSize", "-ZTronSeamStart", "-ZTronHeaderBehavior")


def notes(s):
    """The test and any launch argument beyond the scenario's standard ones (a variant lab screen)."""
    meta = s.get("meta") or {}
    args, extra, k = meta.get("launchArgs") or [], [], 0
    while k < len(args):
        if args[k] in STANDARD and k + 1 < len(args):
            k += 2
            continue
        extra.append(args[k])
        k += 1
    out = [meta.get("test", "")] + (["forced"] if meta.get("forced") else []) + extra
    return " ".join(x for x in out if x) or "-"


def main():
    args = sys.argv[1:]
    root = None
    if args[:1] == ["--root"]:
        root, args = os.path.abspath(args[1]), args[2:]
    print("| recording | rest | max gap | max ovl | max lat | off (n) | hJ | cJ | frames tr/meas/all | flags | notes |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for d in args:
        p = os.path.join(d, "v2", "summary.json")
        if not os.path.exists(p):
            p = os.path.join(d, "summary.json")
        rec = os.path.dirname(p) if os.path.basename(os.path.dirname(p)) != "v2" else os.path.dirname(os.path.dirname(p))
        rec = os.path.abspath(rec)
        name = os.path.relpath(rec, root) if root else os.path.join(*os.path.normpath(rec).split(os.sep)[-2:])
        if not os.path.exists(p):
            print(f"| {name} | (no summary) ||||||||||")
            continue
        s = json.load(open(p))
        off_n = s["headerOnlyFrames"].get("edge", 0)
        off = f"{f(s['maxGapMinContentOffscreen'])} ({off_n})" if off_n else "-"
        lat = at(s.get("maxLatMis"), s.get("maxLatMisFrame"))
        lb = s.get("maxLatMisMin")
        if lb is not None and (s.get("maxLatMis") is None or lb > s["maxLatMis"] + 0.5):
            lat += f" [>={f(lb)} f{s.get('maxLatMisMinFrame')}]"
        flags = []
        for k, label in (("ambiguousFrames", "amb"), ("splitFrames", "split"), ("rejectedFrames", "rej")):
            if s.get(k):
                flags.append(f"{label} {s[k]}")
                if label == "amb" and s.get("maxOverlapAmbiguous"):
                    flags[-1] += f" (unresolved ovl up to {f(s['maxOverlapAmbiguous'])})"
        print(f"| {name} | {f(s['firstRestSeam']['median'], 2)} | {at(s['maxGap'], s.get('maxGapFrame'))} | "
              f"{at(s['maxOverlap'], s.get('maxOverlapFrame'))} | {lat} | {off} | "
              f"{jf(s, 'hdrJumpFraction', 'hdrJump')} | {jf(s, 'contentTopJumpFraction', 'contentTopJump')} | "
              f"{s['transitionFrames']}/{s['measuredFrames']}/{s['frames']} | {', '.join(flags) or '-'} | "
              f"{notes(s)} |")


if __name__ == "__main__":
    main()
