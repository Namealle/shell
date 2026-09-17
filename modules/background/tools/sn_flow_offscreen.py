#!/usr/bin/env python3
"""Is the remnant's INTERNAL structure alive, or is it a frozen texture?

    SN_MOMENTS=150,151,152,153,154 node .../supernova-sheet.mjs /tmp/bhrender OUT tag W H
    python3 .../sn_flow_offscreen.py OUT/tag-manifest.json [--rim 0]

"The cloud of the supernova is static and not moving with the rest" (ledger
2286) has two halves and the live capture only answers one of them. That the
whole object TRAVELS is easy to show and v10 did it too -- the site has ridden
the far layer's streamline since v9. What v10 did not do is have anything happen
INSIDE the object: one radial-noise disc, advected by a phase term so slowly
that a second of it moves less than a pixel.

This measures exactly that, and it measures it offscreen: the sheet pins the
site at the centre of the frame and there is no camera flow in the host, so the
bulk motion is zero BY CONSTRUCTION and everything left is the structure moving
through itself. No output is taken over, nothing on his screen changes, and the
two trees are rendered through the same rig at the same ages.

Block-matched optical flow on the .f32 frames, same matcher as sn_live.py.
"""
import argparse
import json
import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sn_live import flow, BLOCK, STRIDE  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--rim", type=float, default=0.0, help="px; 0 = the manifest's remnant radius")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    m = json.load(open(args.manifest))
    w, h = m["width"], m["height"]
    entries = m["entries"]
    if len(entries) < 2:
        raise SystemExit("need at least two moments; set SN_MOMENTS when rendering")

    def gray(e):
        a = np.fromfile(e["raw"], dtype="<f4").reshape(h, w, 4)[:, :, :3]
        return (a[:, :, 0] * 0.2126 + a[:, :, 1] * 0.7152 + a[:, :, 2] * 0.0722).astype(np.float32)

    frames = [gray(e) for e in entries]
    site = (entries[0]["head"][0], entries[0]["head"][1])
    rim = args.rim or entries[0].get("remnantRadiusPx") or m["spans"]["shellRadiusPx"]

    ys = np.arange(0, h - BLOCK, STRIDE)
    xs = np.arange(0, w - BLOCK, STRIDE)
    gy, gx = np.meshgrid(ys + BLOCK / 2, xs + BLOCK / 2, indexing="ij")
    r = np.hypot(gx - site[0], gy - site[1])
    inside = r < rim * 1.05

    rows = []
    for i in range(len(frames) - 1):
        dt = entries[i + 1]["age"] - entries[i]["age"]
        dx, dy, _ = flow(frames[i], frames[i + 1], ys, xs)
        var = np.array([[frames[i][y:y + BLOCK, x:x + BLOCK].std() for x in xs] for y in ys])
        good = inside & (var > frames[i].max() * 0.012)
        if good.sum() < 8:
            continue
        ux = (gx - site[0]) / np.maximum(r, 1e-6)
        uy = (gy - site[1]) / np.maximum(r, 1e-6)
        speed = np.hypot(dx[good], dy[good])
        rad = (dx * ux + dy * uy)[good]
        rows.append({"from": entries[i]["age"], "to": entries[i + 1]["age"], "dtSec": dt,
                     "blocks": int(good.sum()),
                     "internalPxPerSec": float(speed.mean() / max(dt, 1e-6)),
                     "radialPxPerSec": float(rad.mean() / max(dt, 1e-6)),
                     "movingBlocks": float((speed > 0.5).mean())})
    print(f"{pathlib.Path(args.manifest).stem}: site {site[0]:.0f},{site[1]:.0f} rim {rim:.0f} px")
    print(f"{'t0':>8} {'t1':>8} {'blocks':>7} {'internal px/s':>14} {'radial px/s':>12} {'moving':>8}")
    for r0 in rows:
        print(f"{r0['from']:>8.1f} {r0['to']:>8.1f} {r0['blocks']:>7} "
              f"{r0['internalPxPerSec']:>14.2f} {r0['radialPxPerSec']:>12.2f} {r0['movingBlocks']:>7.0%}")
    if rows:
        print(f"mean internal motion {np.mean([r0['internalPxPerSec'] for r0 in rows]):.2f} px/s, "
              f"radial {np.mean([r0['radialPxPerSec'] for r0 in rows]):.2f} px/s, "
              f"{np.mean([r0['movingBlocks'] for r0 in rows]):.0%} of blocks moving")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(rows, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
