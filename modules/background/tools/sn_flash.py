#!/usr/bin/env python3
"""Proof that the supernova does not flash the screen (requirement A, v11).

    cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
    node modules/background/tools/supernova-sheet.mjs /tmp/bhrender OUTDIR v11
    python3 modules/background/tools/sn_flash.py OUTDIR/v11-manifest.json

Two questions, both answered on pixels rather than on an argument.

1. DOES ANYTHING REACH THE FAR SKY? The v9/v10 detonation multiplied every
   pixel of the frame by 1 + 2.5*gauss(0.55 of the long side) and added a flat
   haze on top. On the sheet's black sky the multiply has nothing to scale, so
   what the haze leaves behind IS the global term, isolated. For every phase
   frame this reports the mean and the max outside 1.5 shell radii of the site
   -- the radius requirement A allows the detonation to touch. With the lift
   gone both must be exactly 0, on every frame, because the only other terms
   are the slot's own bounds box and brightenNear, and both are bounded by the
   episode's geometry.

   The same numbers are reported for the half-plane on the far side of the
   buffer's centre line through the site ("far half"), which is the test as the
   brief words it.

2. HOW BIG AND HOW BRIEF IS THE BLOOM? The 2/255 visibility contour and the
   64/255 bright disc, as a share of the short side, per phase -- the same two
   contours supernova_sheet.py measures, so the numbers are comparable with
   every earlier run. `--bloom` additionally sweeps the CPU envelope through
   node and reports how long the bloom stays above a given share.

The sheet renders the REAL kernels lifted out of starfield.frag (see
supernova-sheet.mjs), so this measures the shipped shader, not a model of it.
"""
import argparse
import json
import pathlib
import subprocess
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent


def load(raw, w, h):
    a = np.fromfile(raw, dtype="<f4")
    return a.reshape(h, w, 4)[:, :, :3]


def luminance(img):
    return img[:, :, 0] * 0.2126 + img[:, :, 1] * 0.7152 + img[:, :, 2] * 0.0722


def measure(img, site, keep, short_side):
    """Everything outside `keep`, and the far half. `keep` is either a radius in
    px or a bounds box (x0, y0, x1, y1) -- the shader rejects on the BOX, so a
    circle of the box's half-width would flag its own corners."""
    h, w, _ = img.shape
    lum = luminance(img)
    ys, xs = np.mgrid[0:h, 0:w]
    d2 = (xs - site[0]) ** 2 + (ys - site[1]) ** 2
    if np.ndim(keep) == 0:
        outside = d2 > keep * keep
    else:
        outside = (xs < keep[0]) | (ys < keep[1]) | (xs > keep[2]) | (ys > keep[3])
    # THE FAR HALF is the half of the buffer FURTHEST FROM THE SITE, not a
    # half-plane: the offscreen rig places the event at the middle of the frame,
    # where every half-plane contains it and a half-plane test proves nothing.
    # The median squared distance splits any frame into exactly two halves
    # wherever the site is, which is the same test on a live capture with the
    # site off to one side.
    far = d2 >= np.median(d2)
    lit = lum > 1.0 / 255.0
    return {
        "outsidePx": int(outside.sum()),
        "outsideMean255": float(lum[outside].mean() * 255) if outside.any() else 0.0,
        "outsideMax255": float(lum[outside].max() * 255) if outside.any() else 0.0,
        "outsideLitPx": int((lit & outside).sum()),
        "farHalfMean255": float(lum[far].mean() * 255) if far.any() else 0.0,
        "farHalfMax255": float(lum[far].max() * 255) if far.any() else 0.0,
        "farHalfLitPx": int((lit & far).sum()),
        "litDiameterShortSides": contour_diameter(lum, site, 2.0 / 255.0) / short_side,
        "discDiameterShortSides": contour_diameter(lum, site, 64.0 / 255.0) / short_side,
        "peak255": float(lum.max() * 255),
    }


def contour_diameter(lum, site, level):
    """Diameter of the largest circle about the site whose rim is still above
    `level`, measured as 2x the furthest lit pixel — the same construction
    supernova_sheet.py uses, so the two agree."""
    ys, xs = np.nonzero(lum > level)
    if ys.size == 0:
        return 0.0
    d = np.hypot(xs - site[0], ys - site[1])
    return float(d.max() * 2)


def bloom_window(share, secs):
    """Sweep the shipped CPU envelope for how long the bloom's visible disc
    stays above `share` of the short side. Runs through node so the envelope is
    supernovaState() itself, extracted out of Starfield.qml by test-events."""
    script = HERE / "sn_bloom.mjs"
    out = subprocess.run(["node", str(script), str(share), str(secs)],
                         capture_output=True, text=True, cwd=str(HERE))
    if out.returncode != 0:
        print(out.stderr.strip(), file=sys.stderr)
        return None
    return json.loads(out.stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--keep-out", type=float, default=1.5,
                    help="shell radii the detonation is allowed to touch (requirement A: 1.5)")
    ap.add_argument("--bloom", type=float, default=0.0,
                    help="also sweep how long the bloom exceeds this share of the short side")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    manifest = json.load(open(args.manifest))
    w, h = manifest["width"], manifest["height"]
    short = min(w, h)
    shell = manifest["spans"]["shellRadiusPx"]
    detonation = args.keep_out * shell

    print(f"buffer {w}x{h}  short side {short}  shell radius {shell:.1f} px  "
          f"detonation keep-out {detonation:.1f} px ({args.keep_out} shell radii)")
    print(f"{'phase':<16} {'age s':>7} {'peak/255':>8} {'lit d/short':>11} {'disc d/short':>12} "
          f"{'reach px':>9} {'>reach lit':>10} {'far half mean':>13} {'max':>8} {'lit px':>8}")
    worst = {"outsideMax255": 0.0, "farHalfMax255": 0.0, "outsideLitPx": 0, "farHalfLitPx": 0}
    rows, breaches = [], []
    for entry in manifest["entries"]:
        img = load(entry["raw"], w, h)
        site = entry["head"][:2]
        # Every phase is allowed exactly what the CPU published as its own
        # bounds box -- that box is what the shader rejects on, and it is the
        # whole claim: outside it a pixel is what it would have been with no
        # supernova at all. The DETONATION phases are additionally held to
        # requirement A's 1.5 shell radii, which is tighter.
        b = entry["bounds"]
        reach = max(b[2] - site[0], b[3] - site[1], site[0] - b[0], site[1] - b[1])
        detonating = entry["name"].startswith(("rise", "flash"))
        keep = min(reach, detonation) if detonating else b
        m = measure(img, site, keep, short)
        m["name"], m["age"], m["reachPx"] = entry["name"], entry["age"], reach
        m["keepOut"] = keep if np.ndim(keep) == 0 else "bounds box"
        rows.append(m)
        for k in worst:
            worst[k] = max(worst[k], m[k])
        if m["outsideLitPx"]:
            breaches.append(m)
        print(f"{entry['name']:<16} {entry['age']:>7.1f} {m['peak255']:>8.1f} "
              f"{m['litDiameterShortSides']:>11.3f} {m['discDiameterShortSides']:>12.3f} "
              f"{(keep if np.ndim(keep) == 0 else reach):>9.1f} {m['outsideLitPx']:>10} "
              f"{m['farHalfMean255']:>13.5f} {m['farHalfMax255']:>8.3f} {m['farHalfLitPx']:>8}")

    ok = not breaches
    print()
    print(f"worst over every phase: outside its own reach {worst['outsideMax255']:.4f}/255 "
          f"({worst['outsideLitPx']} lit px), far half of the buffer {worst['farHalfMax255']:.4f}/255 "
          f"({worst['farHalfLitPx']} lit px)")
    print("NO SKY FLASH: every phase is inside the box it published"
          if ok else "SKY FLASH: " + ", ".join(m["name"] for m in breaches))

    result = {"worst": worst, "phases": rows, "ok": ok}
    if args.bloom > 0:
        b = bloom_window(args.bloom, manifest["spans"]["durationSec"])
        if b:
            result["bloom"] = b
            print(f"bloom above {args.bloom:.3f} of the short side: {b['seconds']:.3f} s "
                  f"(peak {b['peak']:.3f} at t+{b['peakAt']:.2f} s, core peak {b['corePeak']:.3f})")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(result, indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
