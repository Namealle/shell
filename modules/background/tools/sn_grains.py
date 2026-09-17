#!/usr/bin/env python3
"""Is the colour change POPULATION TURNOVER, or is it a crossfade wearing a hat?

    SN_MOMENTS=$(seq -s, 60 6 200) node .../supernova-sheet.mjs /tmp/bhrender OUT v12 2880 1800
    python3 .../sn_grains.py OUT/v12-manifest.json [--json out.json]

His complaint (ledger 2403) was that the phase change "feels unatural and as
just pure color fade transition", and what he asked for instead was that "new
particles of new tone" appear while the old ones die. Those two produce very
similar AVERAGE colours over time, so an average cannot tell them apart. Two
measurements can.

1. TRACKED-GRAIN HUE CONSTANCY. Find the local maxima -- the grains -- in one
   frame, match each to the nearest maximum in the next frame, and measure how
   far its HUE moved. Under a crossfade every grain's hue moves together by the
   crossfade's own step. Under turnover a grain's hue does not move at all: it
   was fixed when the grain was born. The control is the same statistic
   computed between RANDOMLY PAIRED grains, which is what "no relationship
   between these two colours" looks like; a tracked drift far below the shuffled
   one is the whole claim, and it is a claim about pixels rather than about the
   code.

2. THE HUE HISTOGRAM IS BIMODAL MID-CHANGE. A crossfade has one peak that
   slides across the hue circle. A turnover has two peaks at FIXED hues whose
   heights trade places. Sweeping the episode and reporting the second peak's
   height as a share of the first shows which one is happening, and when.

Both run on the .f32 frames the real shader wrote, offscreen, with the site
pinned, so nothing on his screen is touched and nothing here is a model of the
kernel rather than the kernel.
"""
import argparse
import json
import math
import pathlib
import sys

import numpy as np

HUE_BINS = 12


def load(entry, w, h):
    return np.fromfile(entry["raw"], dtype="<f4").reshape(h, w, 4)[:, :, :3].astype(np.float64)


def luminance(img):
    return img[..., 0] * 0.2126 + img[..., 1] * 0.7152 + img[..., 2] * 0.0722


def hue_sat(rgb):
    """Hue in TURNS and saturation, on linear rgb -- the light the shader mixes
    in. A hue difference is taken around the circle, so 0.98 and 0.02 are 0.04
    apart and not 0.96."""
    mx, mn = rgb.max(-1), rgb.min(-1)
    c = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    safe = c > 1e-9
    cc = np.maximum(c, 1e-9)
    h = np.where(mx == r, ((g - b) / cc) % 6, np.where(mx == g, (b - r) / cc + 2, (r - g) / cc + 4)) / 6.0
    return np.where(safe, h % 1.0, 0.0), np.where(mx > 1e-9, c / np.maximum(mx, 1e-9), 0.0)


def hue_gap(a, b):
    d = np.abs(a - b) % 1.0
    return np.minimum(d, 1.0 - d)


def maxima(lum, floor):
    """Eight-neighbour local maxima above `floor` -- one point per grain."""
    m = np.ones_like(lum, bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            m &= lum >= np.roll(np.roll(lum, dy, axis=0), dx, axis=1)
    m &= lum > floor
    m[:2, :] = m[-2:, :] = m[:, :2] = m[:, -2:] = False
    return np.argwhere(m)


def patch_tone(img, ys, xs, k=1):
    """Mean linear rgb of a (2k+1) box about each point: a grain's colour, not
    one texel of it."""
    h, w, _ = img.shape
    out = np.zeros((len(ys), 3))
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            out += img[np.clip(ys + dy, 0, h - 1), np.clip(xs + dx, 0, w - 1)]
    return out / ((2 * k + 1) ** 2)


def track(a, b, site, rim, radius, rng, pct=97.0):
    """Match maxima between two frames and return (tracked drift, shuffled
    drift, counts)."""
    la, lb = luminance(a), luminance(b)
    floor = np.percentile(la[la > 0], pct) if (la > 0).any() else 1e9
    pa, pb = maxima(la, floor), maxima(lb, floor)
    if len(pa) < 40 or len(pb) < 40:
        return None
    ra = np.hypot(pa[:, 1] - site[0], pa[:, 0] - site[1])
    pa = pa[ra < rim * 1.02]
    rb = np.hypot(pb[:, 1] - site[0], pb[:, 0] - site[1])
    pb = pb[rb < rim * 1.02]
    if len(pa) < 40 or len(pb) < 40:
        return None
    # Nearest-neighbour match inside `radius`. A grain moves well under a pixel
    # a frame at these ages, so a small window is not a convenience, it is what
    # makes the match a match: widen it and the statistic degrades toward the
    # shuffled control on its own, which is the honest failure mode.
    d2 = ((pa[:, None, 0] - pb[None, :, 0]) ** 2 + (pa[:, None, 1] - pb[None, :, 1]) ** 2)
    j = d2.argmin(1)
    ok = d2[np.arange(len(pa)), j] <= radius * radius
    pa, j = pa[ok], j[ok]
    if len(pa) < 30:
        return None
    ta = patch_tone(a, pa[:, 0], pa[:, 1])
    tb = patch_tone(b, pb[j][:, 0], pb[j][:, 1])
    ha, sa = hue_sat(ta)
    hb, sb = hue_sat(tb)
    # Only grains with enough chroma to HAVE a hue. A near-white grain's hue is
    # numerical noise -- the blast-wave population is 0.25 saturated by
    # construction -- and including it would add scatter to both columns and
    # flatter the ratio rather than test it.
    keep = (sa > 0.25) & (sb > 0.25)
    ha, hb = ha[keep], hb[keep]
    if len(ha) < 20:
        return None
    tracked = hue_gap(ha, hb)
    perm = rng.permutation(len(hb))
    shuffled = hue_gap(ha, hb[perm])
    return {"matched": int(len(ha)),
            "trackedMedian": float(np.median(tracked)),
            "trackedP90": float(np.percentile(tracked, 90)),
            "trackedMean": float(tracked.mean()),
            "shuffledMedian": float(np.median(shuffled)),
            "shuffledMean": float(shuffled.mean()),
            "ratio": float(tracked.mean() / max(shuffled.mean(), 1e-9)),
            "cloudMeanHueStep": float(hue_gap(np.array([circmean(ha)]), np.array([circmean(hb)]))[0])}


def circmean(h):
    a = 2 * math.pi * h
    return (math.atan2(np.sin(a).mean(), np.cos(a).mean()) / (2 * math.pi)) % 1.0


def histogram(img, site, rim):
    lum = luminance(img)
    h, w = lum.shape
    yy, xx = np.mgrid[0:h, 0:w]
    inside = np.hypot(xx - site[0], yy - site[1]) < rim * 1.02
    lit = inside & (lum > 0.02 * max(lum.max(), 1e-9))
    if not lit.any():
        return [0.0] * HUE_BINS, 0.0
    hue, sat = hue_sat(img)
    sel = lit & (sat > 0.2)
    if not sel.any():
        return [0.0] * HUE_BINS, 0.0
    hist, _ = np.histogram(hue[sel], bins=HUE_BINS, range=(0, 1), weights=lum[sel])
    hist = hist / max(hist.sum(), 1e-9)
    peaks = [i for i in range(HUE_BINS)
             if hist[i] >= hist[(i - 1) % HUE_BINS] and hist[i] >= hist[(i + 1) % HUE_BINS]]
    peaks.sort(key=lambda i: -hist[i])
    second = 0.0
    for i in peaks[1:]:
        gap = min(abs(i - peaks[0]), HUE_BINS - abs(i - peaks[0]))
        if gap >= 2:
            second = hist[i]
            break
    return [float(v) for v in hist], float(second / max(hist[peaks[0]], 1e-9)) if peaks else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--radius", type=float, default=3.0, help="px; the match window")
    ap.add_argument("--floor", type=float, default=97.0,
                    help="percentile of the lit luminance a local maximum must beat "
                         "to be counted as a grain")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    m = json.load(open(args.manifest))
    w, h = m["width"], m["height"]
    entries = m["entries"]
    rng = np.random.default_rng(20260917)

    print(f"{pathlib.Path(args.manifest).stem}: {len(entries)} moments, {w}x{h}")
    print()
    print("1. TRACKED-GRAIN HUE CONSTANCY  (hue in turns; 0.5 is the far side of the circle)")
    print(f"{'t0':>8} {'t1':>8} {'grains':>7} {'tracked med':>12} {'tracked p90':>12} "
          f"{'shuffled med':>13} {'tracked/shuffled':>17}")
    tracks = []
    for i in range(len(entries) - 1):
        a, b = load(entries[i], w, h), load(entries[i + 1], w, h)
        site = (entries[i]["head"][0], entries[i]["head"][1])
        rim = entries[i].get("remnantRadiusPx") or m["spans"]["shellRadiusPx"]
        t = track(a, b, site, rim, args.radius, rng, args.floor)
        if not t:
            continue
        t["from"], t["to"] = entries[i]["age"], entries[i + 1]["age"]
        tracks.append(t)
        print(f"{t['from']:>8.1f} {t['to']:>8.1f} {t['matched']:>7} {t['trackedMedian']:>12.4f} "
              f"{t['trackedP90']:>12.4f} {t['shuffledMedian']:>13.4f} {t['ratio']:>17.3f}")
    if tracks:
        tm = float(np.mean([t["trackedMean"] for t in tracks]))
        sm = float(np.mean([t["shuffledMean"] for t in tracks]))
        print(f"\nmean tracked hue drift {tm:.4f} turns against {sm:.4f} for randomly paired "
              f"grains -- ratio {tm / max(sm, 1e-9):.3f}")
        print("a grain keeps the hue it was born with; the ratio is how far from "
              "'these two colours are unrelated' that is.")

    print()
    print("2. THE HUE HISTOGRAM THROUGH THE EPISODE  (bimodality = 2nd peak / 1st peak)")
    print(f"{'age':>8} {'bimodal':>9}   histogram (12 bins, R->Y->G->C->B->M)")
    hists = []
    for e in entries:
        img = load(e, w, h)
        site = (e["head"][0], e["head"][1])
        rim = e.get("remnantRadiusPx") or m["spans"]["shellRadiusPx"]
        hist, bi = histogram(img, site, rim)
        hists.append({"age": e["age"], "bimodality": bi, "hist": hist})
        bars = "".join(" .:-=+*#%@$"[min(10, int(v * 30))] for v in hist)
        print(f"{e['age']:>8.1f} {bi:>9.3f}   |{bars}|")
    if hists:
        bis = [x["bimodality"] for x in hists]
        print(f"\nbimodality: median {np.median(bis):.3f}, max {max(bis):.3f}, "
              f"{sum(1 for b in bis if b > 0.35)}/{len(bis)} moments with two "
              f"populations visibly coexisting")

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(
            {"tracks": tracks, "histograms": hists}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
