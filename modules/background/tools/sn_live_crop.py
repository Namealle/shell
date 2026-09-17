#!/usr/bin/env python3
"""Full-resolution crops of the remnant out of a LIVE capture.

    sn_live_crop.py DIR/TAG 45,75,105 OUTDIR/PREFIX [--size 1100]

`sn_crop.py` pulls a phase out of an offscreen manifest, which knows where the
site is. A live capture does not, so the site is found the way the eye does:
the centroid of the brightest connected mass, taken on a heavily boxed-down
copy so a single bright star cannot win. One crop per age, at native pixels,
because three of the four v11 noise artefacts were invisible at tile size.
"""
import argparse
import pathlib
import sys

import numpy as np
from PIL import Image


def site_of(lum, bs=32):
    h, w = lum.shape
    box = lum[:h // bs * bs, :w // bs * bs].reshape(h // bs, bs, w // bs, bs).mean(axis=(1, 3))
    # The remnant is an extended mass; a star is one cell. Weighting by the
    # square of the box mean picks the mass and not the brightest point.
    wgt = np.maximum(box - np.percentile(box, 70), 0) ** 2
    if wgt.sum() <= 0:
        return w // 2, h // 2
    ys, xs = np.mgrid[0:box.shape[0], 0:box.shape[1]]
    return (float((xs * wgt).sum() / wgt.sum()) * bs + bs / 2,
            float((ys * wgt).sum() / wgt.sum()) * bs + bs / 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefix")
    ap.add_argument("ages", help="comma list of frame indices")
    ap.add_argument("out", help="output path prefix")
    ap.add_argument("--size", type=int, default=1100)
    ap.add_argument("--gain", type=float, default=1.0)
    args = ap.parse_args()

    for age in (int(a) for a in args.ages.split(",")):
        src = pathlib.Path(f"{args.prefix}-{age:03d}.png")
        if not src.exists():
            print(f"missing {src}", file=sys.stderr)
            continue
        im = Image.open(src).convert("RGB")
        a = np.asarray(im, dtype=np.float64) / 255.0
        lum = a[:, :, 0] * 0.2126 + a[:, :, 1] * 0.7152 + a[:, :, 2] * 0.0722
        cx, cy = site_of(lum)
        half = args.size // 2
        x0 = int(np.clip(cx - half, 0, max(0, im.width - args.size)))
        y0 = int(np.clip(cy - half, 0, max(0, im.height - args.size)))
        crop = im.crop((x0, y0, x0 + args.size, y0 + args.size))
        if args.gain != 1.0:
            crop = Image.fromarray(np.clip(np.asarray(crop, dtype=np.float64) * args.gain,
                                           0, 255).astype("uint8"))
        dest = f"{args.out}-{age:03d}.png"
        crop.save(dest)
        print(f"t+{age}s site ({cx:.0f},{cy:.0f}) -> {dest} ({crop.width}x{crop.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
