#!/usr/bin/env python3
"""Seam lab: one table row per measured scenario (reads <dir>/summary.json).

usage: python3 -I scripts/seam/table.py <scenario-dir>...
Columns (points): rest = seam at the first rest (the control reads its inset); gap / ovl = largest blue gap / largest red
cover of the content over the whole run; off = largest blue run past the header with the content off screen (a lower
bound of the gap; n = frames); tr = transition frames; hJ / bJ / cJ = largest single-frame step of the header's thickness /
its bottom edge / the content's top as a fraction of the change (1.0 = all in one frame; - = no change or unmeasured;
the maximum over the run's segments; [x] = the same per 60 Hz interval when a recorder or render hitch inflates it).
"""
import json
import os
import sys


def f(v, d=1):
    return "-" if v is None else (f"{v:.{d}f}" if isinstance(v, (int, float)) else str(v))


def jf(s, key, vkey):
    """The jump fraction per recorded frame, with the per-60-Hz value in brackets when a hitch makes them differ."""
    raw, per = s[key], s.get("perVsync", {}).get(vkey)
    if raw is not None and per is not None and abs(raw - per) > 0.05:
        return f"{raw:.2f} [{per:.2f}]"
    return f(raw, 2)


def main():
    print("| scenario | rest | gap | ovl | off (n) | tr | hJ | bJ | cJ |")
    print("|---|---|---|---|---|---|---|---|---|")
    for d in sys.argv[1:]:
        p = os.path.join(d, "summary.json")
        name = os.path.join(*os.path.normpath(d).split(os.sep)[-2:])
        if not os.path.exists(p):
            print(f"| {name} | (no summary) |||||||||")
            continue
        s = json.load(open(p))
        off_n = s["headerOnlyFrames"]["edge"]
        off = f"{f(s['maxGapMinContentOffscreen'])} ({off_n})" if off_n else "-"
        print(f"| {name} | {f(s['firstRestSeam']['median'], 2)} | {f(s['maxGap'])} | "
              f"{f(s['maxOverlap'])} | {off} | {s['transitionFrames']} | "
              f"{jf(s, 'hdrJumpFraction', 'hdrJump')} | {jf(s, 'hdrBotJumpFraction', 'hdrBotJump')} | "
              f"{jf(s, 'contentTopJumpFraction', 'contentTopJump')} |")


if __name__ == "__main__":
    main()
