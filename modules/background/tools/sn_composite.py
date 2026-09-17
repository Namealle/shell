#!/usr/bin/env python3
"""Contact sheet and trails composite from a captured life cycle.

    sn_composite.py DIR/TAG --sheet OUT.png --trails OUT.png [--crop x,y,w,h]

The contact sheet is every Nth frame, labelled with its second, so a whole
episode fits on one page and the phases can be read off in order. The trails
composite is the per-pixel MAXIMUM over the sequence: every ember's whole path
at once, which is the one picture that shows the ejecta is a 3-D shell being
thrown outward rather than a texture being scaled up.
"""
import argparse
import glob
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefix")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--trails", default="")
    ap.add_argument("--every", type=int, default=10)
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--crop", default="", help="x,y,w,h in the captured frame")
    ap.add_argument("--gain", type=float, default=1.0)
    args = ap.parse_args()

    files = sorted(glob.glob(args.prefix + "-*.png"))
    if not files:
        raise SystemExit("no frames at " + args.prefix + "-*.png")
    box = [int(v) for v in args.crop.split(",")] if args.crop else None

    def frame(path):
        im = Image.open(path).convert("RGB")
        if box:
            im = im.crop((box[0], box[1], box[0] + box[2], box[1] + box[3]))
        return im

    if args.sheet:
        picks = list(range(0, len(files), args.every))
        rows = (len(picks) + args.cols - 1) // args.cols
        one = frame(files[0])
        tw = 560
        th = max(1, int(one.height * tw / one.width))
        sheet = Image.new("RGB", (args.cols * tw, rows * (th + 26)), "black")
        draw = ImageDraw.Draw(sheet)
        for i, k in enumerate(picks):
            tile = frame(files[k]).resize((tw, th), Image.LANCZOS)
            x, y = (i % args.cols) * tw, (i // args.cols) * (th + 26)
            sheet.paste(tile, (x, y + 26))
            draw.text((x + 6, y + 6), f"t+{k} s", fill="white")
        sheet.save(args.sheet)
        print(f"sheet: {args.sheet} ({len(picks)} of {len(files)} frames)")

    if args.trails:
        acc = None
        for f in files:
            a = np.asarray(frame(f), dtype=np.float32)
            acc = a if acc is None else np.maximum(acc, a)
        out = Image.fromarray(np.clip(acc * args.gain, 0, 255).astype("uint8"))
        out.save(args.trails)
        print(f"trails: {args.trails} (max over {len(files)} frames)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
