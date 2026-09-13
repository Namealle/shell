#!/usr/bin/env python3
"""Contact sheet + measurements for a meteor storm.

    python3 modules/background/tools/storm_sheet.py MANIFEST.json OUT.png

Reads the .f32 frames storm-sheet.mjs rendered (row 0 = top, RGBA float32,
already sRGB-encoded on a #000000 sky) and reports, per frame across the rate
hump, what a person actually sees: how many separate streaks are lit, how long
the longest one is in pixels and in per cent of the short side, the brightest
8-bit value and how many pixels clear the 2/255 visibility floor.

Streaks are counted by flood fill over the lit mask, so the number is what the
eye would count, not what the scheduler intended.
"""
import json
import sys
import numpy as np
from PIL import Image, ImageDraw

FLOOR = 2.0 / 255.0


def load(path, w, h):
    return np.fromfile(path, dtype="<f4").reshape(h, w, 4)[:, :, :3]


def components(mask, minimum=12):
    """Flood fill over a boolean mask; returns (count, list of bbox extents)."""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        minx = maxx = x0
        miny = maxy = y0
        size = 0
        while stack:
            y, x = stack.pop()
            size += 1
            if x < minx: minx = x
            if x > maxx: maxx = x
            if y < miny: miny = y
            if y > maxy: maxy = y
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if size >= minimum:
            out.append((size, float(np.hypot(maxx - minx, maxy - miny))))
    return out


def main():
    manifest = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    w, h = manifest["width"], manifest["height"]
    short = min(w, h)
    frames = manifest["frames"]
    storm = manifest["storm"]
    print(f"storm  {storm['duration']:.0f} s = ramp {storm['ramp']:.0f} + peak {storm['peak']:.0f} "
          f"+ decay {storm['decay']:.0f},  {storm['total']:.0f} streaks,  "
          f"{storm['rateFloor']:.3f} -> {storm['rateMax']:.2f} -> {storm['rateFloor']:.3f} per second, "
          f"{storm['children']} fireballs,  buffer {w}x{h}")
    print("\nage s   rate/s   window   streaks   longest px   % short   peak/255   lit px   fireballs")
    rows = []
    for f in frames:
        img = load(f["raw"], w, h)
        v = img.max(axis=2)
        mask = v >= FLOOR
        comps = components(mask)
        longest = max((c[1] for c in comps), default=0.0)
        lit = int(mask.sum())
        peak = float(v.max()) * 255
        rows.append(dict(f, streaks=len(comps), longest=longest, lit=lit, peak=peak))
        print(f"{f['age']:6.1f}   {f['rate']:6.2f}   {f['window']:6.0f}   {len(comps):7d}   "
              f"{longest:10.0f}   {100 * longest / short:7.1f}   {peak:8.1f}   {lit:6d}   {f['fireballs']:9d}")

    # Contact sheet: every frame at a quarter scale, in a row-major grid.
    scale = 4
    tw, th = w // scale, h // scale
    columns = min(5, len(frames))
    rowsn = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tw, rowsn * (th + 22)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(rows):
        img = load(f["raw"], w, h)
        # MAX pooling, not an average: a one-pixel-wide streak survives the
        # downscale, which is the whole point of looking at the sheet.
        block = np.clip(img, 0, 1)[:th * scale, :tw * scale].reshape(th, scale, tw, scale, 3).max(axis=(1, 3))
        tile = Image.fromarray((block * 255).astype(np.uint8))
        x, y = (i % columns) * tw, (i // columns) * (th + 22)
        sheet.paste(tile, (x, y))
        draw.text((x + 6, y + th + 5),
                  f"{f['age']:.0f} s   {f['rate']:.2f}/s   {f['streaks']} streaks   longest {100 * f['longest'] / short:.0f} %",
                  fill=(190, 190, 190))
    sheet.save(out)
    print("\nsheet " + out)


if __name__ == "__main__":
    main()
