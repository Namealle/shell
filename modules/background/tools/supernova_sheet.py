#!/usr/bin/env python3
"""Contact sheet + measured sizes for the v9 supernova life cycle.

    python3 modules/background/tools/supernova_sheet.py MANIFEST.json OUT.png

Reads the .f32 frames supernova-sheet.mjs rendered (row 0 = top, RGBA float32,
already sRGB-encoded on a #000000 sky) and reports, per phase moment, what a
person actually sees: the brightest 8-bit value, how many pixels clear the
2/255 visibility floor, the radius of that lit region, and the same radius as a
share of the screen's short side -- which is the number the brief is written in.
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw


def load(path, w, h):
    return np.fromfile(path, dtype="<f4").reshape(h, w, 4)[:, :, :3]


def radius_at(v, head, floor):
    hit = v >= floor
    if not hit.any():
        return 0.0
    ys, xs = np.nonzero(hit)
    return float(np.hypot(xs - head[0], ys - head[1]).max())


def metrics(img, head, short_side):
    v = img.max(axis=2)
    lit = v >= 2.0 / 255.0
    n = int(lit.sum())
    # Two contours: 2/255 is the visibility floor (can this be seen at all) and
    # 64/255 is the bright DISC the brief's "peak size" is written about.
    r = radius_at(v, head, 2.0 / 255.0)
    disc = radius_at(v, head, 64.0 / 255.0)
    return {
        "peak255": round(float(v.max()) * 255, 1),
        "litPx": n,
        "litRadiusPx": round(r, 1),
        "litDiameterShortSides": round(2 * r / short_side, 3),
        "discRadiusPx": round(disc, 1),
        "discDiameterShortSides": round(2 * disc / short_side, 3),
        "meanLit255": round(float(v[lit].mean()) * 255, 1) if n else 0.0,
    }


def main():
    manifest = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    w, h = manifest["width"], manifest["height"]
    short_side = manifest["spans"]["shortSidePx"]
    cols = 4
    tile_w, tile_h = 480, int(round(480 * h / w))
    rows = (len(manifest["entries"]) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile_w, rows * (tile_h + 34)), "black")
    draw = ImageDraw.Draw(sheet)
    print(f"{'phase':<16} {'age s':>7} {'peak/255':>8} {'lit px':>9} {'lit r px':>9} "
          f"{'lit d/short':>11} {'disc d/short':>12} {'shell r px':>10} {'neb r px':>9} {'body':>6}")
    for i, entry in enumerate(manifest["entries"]):
        img = load(entry["raw"], w, h)
        m = metrics(img, entry["head"], short_side)
        entry["measured"] = m
        tile = Image.fromarray((np.clip(img, 0, 1) * 255).astype("uint8")).resize((tile_w, tile_h))
        x, y = (i % cols) * tile_w, (i // cols) * (tile_h + 34)
        sheet.paste(tile, (x, y + 34))
        draw.text((x + 6, y + 4),
                  f"{entry['name']}  t={entry['age']:.1f}s  peak {m['peak255']:.0f}/255  "
                  f"lit d {m['litDiameterShortSides']:.2f} short sides", fill="white")
        print(f"{entry['name']:<16} {entry['age']:>7.1f} {m['peak255']:>8.1f} {m['litPx']:>9} "
              f"{m['litRadiusPx']:>9.1f} {m['litDiameterShortSides']:>11.3f} "
              f"{m['discDiameterShortSides']:>12.3f} "
              f"{entry['shellRadiusPx']:>10.1f} {entry['nebulaRadiusPx']:>9.1f} {entry['remnantGain']:>6.3f}")
    sheet.save(out)
    json.dump(manifest, open(sys.argv[1], "w"), indent=2)
    print("\nsheet: " + out)
    print("spans: " + json.dumps(manifest["spans"]))


if __name__ == "__main__":
    main()
