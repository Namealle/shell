#!/usr/bin/env python3
"""Two proofs that can only be made on live frames.

    sn_live.py DIR/TAG --site auto --rim 260 [--json out.json]

1. NO SKY FLASH, on the real desktop. For every captured frame, the mean
   luminance of the half of the buffer FURTHEST FROM THE SITE. The v9/v10
   detonation multiplied every pixel of the screen; if anything of that is left,
   this line steps when the star explodes. The pre-detonation frames give the
   noise floor for free -- the field is moving, so "identical" means "inside
   what the sky does anyway", and that number is measured rather than assumed.

2. THE REMNANT MOVES WITH THE REGIME. Block-matched optical flow between
   consecutive frames inside the remnant, split into its RADIAL component (the
   shell expanding about its own site) and its BULK component (the whole object
   travelling on the far layer's streamline). v10's remnant was a sprite nailed
   to a pixel: bulk flow exactly zero while the stars around it moved, which is
   "the cloud of the supernova is static and not moving with the rest" as a
   number. Both components are compared with the same frames' STAR flow, taken
   from an annulus outside the remnant, so the comparison is against what the
   sky did in the same seconds rather than against a theory.

Block matching, not Farneback: no cv2 on this box, and integer shifts at 32 px
blocks resolve 1 px/frame against a 30 fps capture sampled at 1 Hz, where the
motions of interest are tens of pixels.
"""
import argparse
import glob
import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image

BLOCK, STRIDE, SEARCH = 32, 16, 10


def load(path):
    a = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    return a


def integral(a):
    return np.pad(np.cumsum(np.cumsum(a, 0), 1), ((1, 0), (1, 0)))


def boxsum(ii, y, x, k):
    return ii[y + k, x + k] - ii[y, x + k] - ii[y + k, x] + ii[y, x]


def flow(a, b, ys, xs):
    """Best integer shift per block, by SSD, searched once per candidate shift
    over the whole frame rather than once per block."""
    best = np.full((len(ys), len(xs)), np.inf, dtype=np.float32)
    bdy = np.zeros((len(ys), len(xs)), dtype=np.int16)
    bdx = np.zeros((len(ys), len(xs)), dtype=np.int16)
    h, w = a.shape
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    for dy in range(-SEARCH, SEARCH + 1):
        for dx in range(-SEARCH, SEARCH + 1):
            shifted = np.roll(np.roll(b, -dy, axis=0), -dx, axis=1)
            ii = integral((a - shifted) ** 2)
            cost = boxsum(ii, yy, xx, BLOCK)
            better = cost < best
            best = np.where(better, cost, best)
            bdy = np.where(better, dy, bdy)
            bdx = np.where(better, dx, bdx)
    return bdx.astype(np.float64), bdy.astype(np.float64), best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefix", help="DIR/TAG; reads TAG-*.png")
    ap.add_argument("--site", default="auto", help="x,y or 'auto' (brightest pixel of the peak frame)")
    ap.add_argument("--rim", type=float, default=0.0, help="remnant radius in px; 0 = fit it")
    ap.add_argument("--detonation", type=int, default=-1, help="frame index of the peak; -1 = brightest")
    ap.add_argument("--flow-from", type=int, default=40)
    ap.add_argument("--flow-to", type=int, default=70)
    ap.add_argument("--exclude-left", type=int, default=0,
                    help="columns to drop from the far half: the shell's own bar is not sky")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    files = sorted(glob.glob(args.prefix + "-*.png"))
    if not files:
        raise SystemExit("no frames at " + args.prefix + "-*.png")
    frames = [load(f) for f in files]
    h, w = frames[0].shape

    means = np.array([f.mean() for f in frames])
    # The DETONATION, not the brightest frame: the mean peaks later, when the
    # shell is at its widest, and the question here is what the explosion does
    # to the far side of the screen in the second it goes off. The detonation is
    # the largest frame-to-frame RISE, which is what an explosion is.
    peak = int(np.argmax(np.diff(means)) + 1) if args.detonation < 0 else args.detonation
    if args.site == "auto":
        blur = frames[peak]
        ii = integral(blur)
        k = 24
        ys = np.arange(0, h - k, 8)
        xs = np.arange(0, w - k, 8)
        yy, xx = np.meshgrid(ys, xs, indexing="ij")
        s = boxsum(ii, yy, xx, k)
        i = np.unravel_index(np.argmax(s), s.shape)
        site = (float(xs[i[1]] + k / 2), float(ys[i[0]] + k / 2))
    else:
        site = tuple(float(v) for v in args.site.split(","))

    yy, xx = np.mgrid[0:h, 0:w]
    d2 = (xx - site[0]) ** 2 + (yy - site[1]) ** 2
    far = d2 >= np.median(d2)
    if args.exclude_left:
        # The caelestia bar lives on the left of every output and carries a
        # clock. It is in the far half by distance and it is not sky, so its
        # minute rolling over would be counted as the supernova lighting the
        # far side of the screen.
        far = far & (xx >= args.exclude_left)
    rim = args.rim if args.rim > 0 else 0.22 * min(h, w)

    # ---- 1. the far half, frame by frame
    farmean = np.array([float(f[far].mean() * 255) for f in frames])
    pre = farmean[:max(1, peak - 2)]
    during = farmean[peak:peak + 3]
    noise = float(np.abs(np.diff(pre)).mean()) if pre.size > 2 else 0.0
    step = float(during.max() - pre[-1]) if pre.size and during.size else 0.0
    print(f"site {site[0]:.0f},{site[1]:.0f}  peak frame {peak}  far half = "
          f"{int(far.sum())} px ({100 * far.mean():.0f} % of the buffer)")
    print(f"far-half mean/255: before {pre[-1]:.4f}, at the detonation {during.max():.4f}, "
          f"step {step:+.4f}, frame-to-frame noise before it {noise:.4f}")
    print("NO SKY FLASH" if abs(step) <= 3 * max(noise, 1e-4)
          else "the far half moved by more than three times its own noise")

    # ---- 2. flow inside the remnant against the stars outside it
    lo, hi = args.flow_from, min(args.flow_to, len(frames) - 1)
    ys = np.arange(0, h - BLOCK, STRIDE)
    xs = np.arange(0, w - BLOCK, STRIDE)
    cy = ys + BLOCK / 2
    cx = xs + BLOCK / 2
    gy, gx = np.meshgrid(cy, cx, indexing="ij")
    r = np.hypot(gx - site[0], gy - site[1])
    inside = r < rim * 0.95
    outside = (r > rim * 1.6) & (gx > BLOCK) & (gx < w - BLOCK)
    rows = []
    for i in range(lo, hi):
        dx, dy, cost = flow(frames[i], frames[i + 1], ys, xs)
        var = np.array([[frames[i][y:y + BLOCK, x:x + BLOCK].std() for x in xs] for y in ys])
        good = var > 0.012
        inn, out = inside & good, outside & good
        if inn.sum() < 8:
            continue
        ux = (gx - site[0]) / np.maximum(r, 1e-6)
        uy = (gy - site[1]) / np.maximum(r, 1e-6)
        radial = dx * ux + dy * uy
        rows.append({
            "pair": [i, i + 1],
            "blocksInside": int(inn.sum()), "blocksOutside": int(out.sum()),
            "remnantSpeedPx": float(np.hypot(dx[inn], dy[inn]).mean()),
            "remnantRadialPx": float(radial[inn].mean()),
            "remnantBulkX": float(dx[inn].mean()), "remnantBulkY": float(dy[inn].mean()),
            "starBulkX": float(dx[out].mean()) if out.sum() else 0.0,
            "starBulkY": float(dy[out].mean()) if out.sum() else 0.0,
        })
    if rows:
        print()
        print(f"{'frames':>9} {'blocks':>7} {'|flow| px':>10} {'radial px':>10} "
              f"{'remnant bulk':>14} {'star bulk':>14}")
        for r0 in rows:
            print(f"{r0['pair'][0]:>4}->{r0['pair'][1]:<4} {r0['blocksInside']:>7} "
                  f"{r0['remnantSpeedPx']:>10.2f} {r0['remnantRadialPx']:>10.2f} "
                  f"{r0['remnantBulkX']:>+7.2f},{r0['remnantBulkY']:<6.2f} "
                  f"{r0['starBulkX']:>+7.2f},{r0['starBulkY']:<6.2f}")
        speed = float(np.mean([r0["remnantSpeedPx"] for r0 in rows]))
        bulk = (float(np.mean([r0["remnantBulkX"] for r0 in rows])),
                float(np.mean([r0["remnantBulkY"] for r0 in rows])))
        star = (float(np.mean([r0["starBulkX"] for r0 in rows])),
                float(np.mean([r0["starBulkY"] for r0 in rows])))
        print()
        print(f"mean |flow| inside the remnant {speed:.2f} px/frame; "
              f"its bulk motion {bulk[0]:+.2f},{bulk[1]:+.2f} against the field's "
              f"{star[0]:+.2f},{star[1]:+.2f} px/frame")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps({
            "site": list(site), "peakFrame": peak, "rimPx": rim,
            "farHalfMean255": farmean.tolist(), "farHalfStep": step, "farHalfNoise": noise,
            "flow": rows}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
