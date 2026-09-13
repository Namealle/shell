#!/usr/bin/env python3
"""Contact sheet + legibility metrics for the event families.

    python3 modules/background/tools/events_sheet.py MANIFEST.json OUT.png [--crop 640]

Reads the .f32 frames events-sheet.mjs rendered (row 0 = top, RGBA float32,
already sRGB-encoded on a #000000 sky) and reports, per family, what a person
actually sees: the brightest 8-bit value, how many pixels clear the 2/255
visibility floor, and the radius of that lit region. The near-layer star peak
from the manifest is the yardstick.
"""
import json
import sys
import numpy as np
from PIL import Image, ImageDraw


def load(path, w, h):
    a = np.fromfile(path, dtype="<f4").reshape(h, w, 4)[:, :, :3]
    return a


def metrics(img, head):
    v = img.max(axis=2)
    lit = v >= 2.0 / 255.0
    n = int(lit.sum())
    if n:
        ys, xs = np.nonzero(lit)
        r = float(np.hypot(xs - head[0], ys - head[1]).max())
        extent = (int(xs.max() - xs.min()) + 1, int(ys.max() - ys.min()) + 1)
    else:
        r, extent = 0.0, (0, 0)
    return {"peak255": round(float(v.max()) * 255, 1), "litPx": n, "litRadiusPx": round(r, 1),
            "extentPx": extent}


def main():
    manifest = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    crop = 640
    if "--crop" in sys.argv:
        crop = int(sys.argv[sys.argv.index("--crop") + 1])
    W, H = manifest["width"], manifest["height"]
    entries = manifest["entries"]
    cols = 4
    rows = (len(entries) + cols - 1) // cols
    cell = crop // 2
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    report = []
    for i, e in enumerate(entries):
        img = load(e["raw"], W, H)
        head = e["head"][:2]
        m = metrics(img, head)
        m["name"] = e["name"]
        m["gain"] = round(e["gain"], 4)
        m["headSigmaPx"] = round(e["head"][2], 2)
        report.append(m)
        b = e.get("bounds") or [head[0] - crop / 2, head[1] - crop / 2, head[0] + crop / 2, head[1] + crop / 2]
        # v9 put three SCREEN-SIZED things in this catalogue - the supernova's
        # sky lift, the storm and the nebula passage - and a fixed crop shows a
        # corner of each. Anything wider than the crop is fitted whole instead,
        # letterboxed into the same cell, and the header says which.
        fit = max(b[2] - b[0], b[3] - b[1]) > crop
        if fit:
            whole = np.clip(img * 255, 0, 255).astype(np.uint8)
            tile = Image.fromarray(whole)
            tile.thumbnail((cell, cell), Image.LANCZOS)
            pad = Image.new("RGB", (cell, cell), (0, 0, 0))
            pad.paste(tile, ((cell - tile.width) // 2, (cell - tile.height) // 2))
            tile = pad
        else:
            cx = min(max((b[0] + b[2]) / 2, crop / 2), W - crop / 2)
            cy = min(max((b[1] + b[3]) / 2, crop / 2), H - crop / 2)
            x0, y0 = int(cx - crop / 2), int(cy - crop / 2)
            tile = np.clip(img[y0:y0 + crop, x0:x0 + crop] * 255, 0, 255).astype(np.uint8)
            tile = Image.fromarray(tile).resize((cell, cell), Image.LANCZOS)
        m["wholeFrame"] = bool(fit)
        r, c = divmod(i, cols)
        sheet.paste(tile, (c * cell, r * (cell + 18)))
        draw.text((c * cell + 4, r * (cell + 18) + cell + 4),
                  "%s  peak %.0f/255  lit %d px  r %.0f%s"
                  % (e["name"], m["peak255"], m["litPx"], m["litRadiusPx"], "  [whole frame]" if fit else ""),
                  fill=(190, 190, 190))
    star = manifest["star"]
    draw.text((4, 4), "%s  1:1 px, %dx%d source, crop %d -> %d   star ref: sigma %.2f px peak %.0f/255"
              % (manifest["label"], W, H, crop, cell, star["sigma"], star["peak"] * 255), fill=(255, 200, 120))
    sheet.save(out)
    print(json.dumps({"star255": round(star["peak"] * 255, 1), "families": report}, indent=1))


if __name__ == "__main__":
    main()
