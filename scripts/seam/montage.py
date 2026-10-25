#!/usr/bin/env python3
"""Seam lab: a montage of recording frames (by decode index) for a visual check of the classification.

usage: python3 -I scripts/seam/montage.py <rec.mov> <out.png> <first> <last> [--step N] [--width 260]
Each tile is labelled with its frame index (same numbering as frames.csv).
"""
import argparse
import subprocess

import numpy as np
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("first", type=int)
    ap.add_argument("last", type=int)
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument("--width", type=int, default=260)
    a = ap.parse_args()
    import json
    info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                      "stream=width,height", "-of", "json", a.video],
                                     check=True, capture_output=True, text=True).stdout)["streams"][0]
    w, h = info["width"], info["height"]
    p = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", a.video, "-map", "0:v:0", "-fps_mode", "passthrough",
                          "-enc_time_base", "demux", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
                         stdout=subprocess.PIPE)
    tiles, i, n = [], 0, w * h * 3
    while i <= a.last:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        if i >= a.first and (i - a.first) % a.step == 0:
            im = Image.fromarray(np.frombuffer(buf, np.uint8).reshape(h, w, 3))
            im = im.resize((a.width, int(h * a.width / w)))
            ImageDraw.Draw(im).text((6, 6), str(i), fill=(255, 255, 255))
            tiles.append(im)
        i += 1
    p.kill()
    th = tiles[0].height
    cols = min(len(tiles), 8)
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (a.width + 6), rows * (th + 6)), (128, 128, 128))
    for k, t in enumerate(tiles):
        sheet.paste(t, ((k % cols) * (a.width + 6), (k // cols) * (th + 6)))
    sheet.save(a.out)


if __name__ == "__main__":
    main()
