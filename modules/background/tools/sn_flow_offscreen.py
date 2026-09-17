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
        tan = (dx * -uy + dy * ux)[good]
        # ---- v12: IS THE FLOW VARIED, OR IS IT ONE RIGID MOTION? -----------
        # The mean radial term alone cannot tell "gas in wind" from "a picture
        # being scaled up": v11 measured 0.45 px/s radial out of 0.53 px/s
        # total, i.e. 85 % of every block doing the same thing, which is a rigid
        # body. These are the numbers that say whether each part moves
        # differently.
        #
        #   dirStdDeg  circular standard deviation of each block's flow
        #              direction MEASURED AGAINST ITS OWN RADIAL DIRECTION, so
        #              pure homologous expansion scores 0 however big it is.
        #   magCV      coefficient of variation of |flow| -- one number for
        #              "some parts are moving much faster than others".
        #   coherence  radial mean over speed mean: 1 is rigid expansion, 0 is
        #              pure churn. This is v11's 85 % in its own terms.
        #   radialSpreadAtR  the std-dev of radial speed WITHIN a radius bin,
        #              averaged over bins, as a share of the mean radial speed.
        #              Homologous expansion of a single sheet makes this ~0;
        #              depth slices at different perspective magnifications make
        #              it the size of the magnification spread. It is the layer
        #              parallax, measured on pixels rather than asserted.
        ang = np.arctan2(tan, rad)
        dir_std = float(math.degrees(math.sqrt(
            max(-2.0 * math.log(max(math.hypot(np.cos(ang).mean(), np.sin(ang).mean()), 1e-9)), 0.0))))
        rbin = np.clip((r[good] / rim * 6).astype(int), 0, 5)
        spreads = []
        for b in range(6):
            sel = rbin == b
            if sel.sum() >= 6:
                spreads.append(rad[sel].std())
        mean_rad = abs(rad.mean()) if abs(rad.mean()) > 1e-9 else 1e-9
        rows.append({"from": entries[i]["age"], "to": entries[i + 1]["age"], "dtSec": dt,
                     "blocks": int(good.sum()),
                     "internalPxPerSec": float(speed.mean() / max(dt, 1e-6)),
                     "radialPxPerSec": float(rad.mean() / max(dt, 1e-6)),
                     "tangentialAbsPxPerSec": float(np.abs(tan).mean() / max(dt, 1e-6)),
                     "movingBlocks": float((speed > 0.5).mean()),
                     "dirStdDeg": dir_std,
                     "magCV": float(speed.std() / max(speed.mean(), 1e-9)),
                     "coherence": float(rad.mean() / max(speed.mean(), 1e-9)),
                     "radialSpreadAtR": float(np.mean(spreads) / mean_rad) if spreads else 0.0})
    print(f"{pathlib.Path(args.manifest).stem}: site {site[0]:.0f},{site[1]:.0f} rim {rim:.0f} px")
    print(f"{'t0':>8} {'t1':>8} {'blocks':>7} {'internal px/s':>14} {'radial px/s':>12} {'tang px/s':>10} "
          f"{'moving':>7} {'dir sd':>8} {'mag CV':>7} {'coher':>6} {'layer':>6}")
    for r0 in rows:
        print(f"{r0['from']:>8.1f} {r0['to']:>8.1f} {r0['blocks']:>7} "
              f"{r0['internalPxPerSec']:>14.2f} {r0['radialPxPerSec']:>12.2f} "
              f"{r0['tangentialAbsPxPerSec']:>10.2f} {r0['movingBlocks']:>6.0%} "
              f"{r0['dirStdDeg']:>7.1f}d {r0['magCV']:>7.2f} {r0['coherence']:>6.2f} "
              f"{r0['radialSpreadAtR']:>6.2f}")
    if rows:
        mean = lambda k: float(np.mean([r0[k] for r0 in rows]))  # noqa: E731
        print(f"mean internal motion {mean('internalPxPerSec'):.2f} px/s, "
              f"radial {mean('radialPxPerSec'):.2f} px/s, "
              f"tangential {mean('tangentialAbsPxPerSec'):.2f} px/s, "
              f"{mean('movingBlocks'):.0%} of blocks moving")
        print(f"VARIATION: flow direction sd {mean('dirStdDeg'):.1f} deg about the local radial, "
              f"magnitude CV {mean('magCV'):.2f}, coherence {mean('coherence'):.2f} "
              f"(1 = rigid expansion), layer parallax {mean('radialSpreadAtR'):.2f} "
              f"of the mean radial speed")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(rows, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
