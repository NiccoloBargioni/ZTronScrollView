#!/usr/bin/env python3
"""Seam lab: re-measure every recording under a root with analyze.py (v2), in parallel, into an output tree.

usage: python3 -I scripts/seam/reanalyze.py <root> [--out-root DIR | --sub v2] [--jobs 3] [--only substring]
                                                [--skip-done]
Every directory holding a rec.mov is one recording (its meta.json gives the scale); analyze.py writes frames.csv,
summary.json and worst-*.png into <out-root>/<path below root>/ (default: <dir>/<sub>/; the outputs next to rec.mov
stay). Prints the directories measured.
"""
import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor


def recordings(root):
    out = []
    for d, _dirs, files in os.walk(root):
        if "rec.mov" in files:
            out.append(d)
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--sub", default="v2")
    ap.add_argument("--out-root")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--only", default="")
    ap.add_argument("--skip-done", action="store_true")
    a = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    skip = os.path.abspath(a.out_root) if a.out_root else None
    dirs = [d for d in recordings(a.root) if a.only in d and os.sep + a.sub + os.sep not in d + os.sep
            and not (skip and os.path.abspath(d).startswith(skip + os.sep))]

    def run(d):
        out = os.path.join(a.out_root, os.path.relpath(d, a.root)) if a.out_root else os.path.join(d, a.sub)
        if a.skip_done and os.path.exists(os.path.join(out, "summary.json")):
            return d, 0, "skipped"
        cmd = [sys.executable, "-I", os.path.join(here, "analyze.py"), os.path.join(d, "rec.mov"), "--out", out,
               "--quiet"]
        meta = os.path.join(d, "meta.json")
        if os.path.exists(meta):
            cmd += ["--meta", meta]
        p = subprocess.run(cmd, capture_output=True, text=True)
        return d, p.returncode, (p.stderr or "").strip()[-400:]

    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for d, rc, err in ex.map(run, dirs):
            print(("ok  " if rc == 0 else f"rc={rc} ") + d + (f"  {err}" if rc else ""), flush=True)


if __name__ == "__main__":
    main()
