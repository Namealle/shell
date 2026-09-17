#!/usr/bin/env python3
"""Crop one .f32 frame out of a sheet manifest and write it as a PNG.

    sn_crop.py MANIFEST.json PHASE OUT.png [--size 900] [--gain 1.0] [--zoom 1]

The contact sheet fits fourteen phases on one page, which is the right tool for
"does the life cycle hold together" and the wrong one for "is the rim made of
knots". This pulls one phase out at full resolution around the site so the
structure can actually be looked at.
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("phase")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=900)
    ap.add_argument("--gain", type=float, default=1.0)
    ap.add_argument("--zoom", type=float, default=1.0)
    args = ap.parse_args()

    m = json.load(open(args.manifest))
    w, h = m["width"], m["height"]
    entry = next((e for e in m["entries"] if e["name"] == args.phase), None)
    if entry is None:
        print("phases: " + ", ".join(e["name"] for e in m["entries"]), file=sys.stderr)
        return 1
    img = np.fromfile(entry["raw"], dtype="<f4").reshape(h, w, 4)[:, :, :3]
    cx, cy = int(entry["head"][0]), int(entry["head"][1])
    half = args.size // 2
    x0, y0 = max(0, cx - half), max(0, cy - half)
    crop = img[y0:y0 + args.size, x0:x0 + args.size]
    out = Image.fromarray(np.clip(crop * args.gain, 0, 1).__mul__(255).astype("uint8"))
    if args.zoom != 1.0:
        out = out.resize((int(out.width * args.zoom), int(out.height * args.zoom)), Image.LANCZOS)
    out.save(args.out)
    print(f"{args.phase} t+{entry['age']}s -> {args.out} ({out.width}x{out.height}, gain {args.gain})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
