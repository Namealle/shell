#!/usr/bin/env python3
"""Measure a rendered supernova remnant against the Cassiopeia A references.

    python3 modules/background/tools/sn_reference.py \
        --render OUT/v11-manifest.json:remnant-mid \
        --render OUT/v10-manifest.json:remnant-mid \
        --reference .../sa0225Mosk01.jpg --reference .../casa-JWST-supernova.webp \
        [--json out.json] [--csv out.csv]

"It looks nothing like a real supernova. I want it hyper-detailed" (ledger 2286)
is not a number, so this turns it into six of them. Every image -- render or
photograph -- is resampled into the SAME polar grid normalised to its own rim
radius, so a 2880x1800 render and a 2940x2370 Chandra composite are compared as
the same object at the same scale and nothing depends on either one's framing.

  edgeDensity      high-frequency energy along the rim over the same in the
                   interior. A smooth disc scores ~1; a filigree rim scores high.
                   This is the single number that says "detailed" rather than
                   "big and bright".
  knotsPerRimRad   isolated local maxima in the rim annulus, counted per radian
                   of rim, and their characteristic diameter in rim radii. Both
                   references are made of knots; v10's remnant has none at all.
  tangentialFrac   share of the rim annulus whose local filament direction
                   (structure tensor, minor eigenvector) lies within 30 degrees
                   of the tangent. A shell's sheets are seen edge-on and lie
                   ALONG the rim; radial spokes score near zero.
  radialFracJet    the same, measured RADIALLY, in the two sectors with the most
                   material beyond 1.05 rim radii -- the jets, which are the one
                   place both references are radial.
  cavityFrac       share of the disc darker than 35 % of its own annulus median:
                   the dark bubbles and holes.
  colourByRadius   mean (R-B)/(R+B) per radial bin, which walks blue-white ->
                   orange -> red outwards in both references.
  throughFrac      point sources visible inside the rim as a share of those in
                   the same area of sky outside it: how translucent the thing
                   is. Only meaningful on a frame with stars behind it.

Nothing here is scipy: box filters are integral images and the local maxima are
an eight-neighbour compare, so it runs anywhere the rest of the tooling runs.
"""
import argparse
import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image

NR, NTH = 220, 720          # the common polar grid: radius x angle
RIM_LO, RIM_HI = 0.68, 1.02  # the rim annulus, in rim radii
IN_LO, IN_HI = 0.12, 0.58    # the interior, same units


# ---------------------------------------------------------------- loading
def load_render(spec):
    """MANIFEST.json:phase -> (rgb float array, centre, rim radius px)."""
    path, _, phase = spec.partition(":")
    m = json.load(open(path))
    w, h = m["width"], m["height"]
    entry = next((e for e in m["entries"] if e["name"] == (phase or "remnant-mid")), None)
    if entry is None:
        raise SystemExit(f"{path}: no phase {phase!r}; have "
                         + ", ".join(e["name"] for e in m["entries"]))
    img = np.fromfile(entry["raw"], dtype="<f4").reshape(h, w, 4)[:, :, :3].astype(np.float64)
    centre = (entry["head"][0], entry["head"][1])
    rim = entry.get("remnantRadiusPx") or m["spans"]["shellRadiusPx"]
    return img, centre, float(rim), f"{pathlib.Path(path).stem}:{entry['name']}"


def load_image(path):
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0
    # A photograph is display-encoded; the render is linear. Decode so the two
    # are measured in the same light -- edge density and cavity fraction are
    # both ratios of intensities and a gamma of 2.2 moves them a long way.
    img = np.where(img <= 0.04045, img / 12.92, ((img + 0.055) / 1.055) ** 2.4)
    return img


def fit_disc(img, floor=0.72):
    """Centre and rim radius of the bright object in a reference photograph.

    The centroid of the lit mask is the centre; the rim is the radius holding
    `floor` of the total light, which is stable against the wispy outskirts in a
    way that a brightness contour is not.
    """
    lum = luminance(img)
    h, w = lum.shape
    thresh = np.percentile(lum, 82)
    mask = lum > thresh
    ys, xs = np.nonzero(mask)
    cx, cy = xs.mean(), ys.mean()
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - cx, yy - cy).ravel()
    v = np.maximum(lum.ravel() - thresh * 0.25, 0)
    order = np.argsort(d)
    cum = np.cumsum(v[order])
    rim = float(d[order][np.searchsorted(cum, floor * cum[-1])])
    return (float(cx), float(cy)), rim


def luminance(img):
    return img[..., 0] * 0.2126 + img[..., 1] * 0.7152 + img[..., 2] * 0.0722


# ---------------------------------------------------------------- resampling
def polar(img, centre, rim, rmax=1.34):
    """Bilinear resample into (NR, NTH, 3), radius 0..rmax in rim radii."""
    h, w, _ = img.shape
    r = np.linspace(0, rmax, NR)[:, None]
    th = np.linspace(0, 2 * math.pi, NTH, endpoint=False)[None, :]
    x = centre[0] + r * rim * np.cos(th)
    y = centre[1] + r * rim * np.sin(th)
    x0 = np.clip(np.floor(x).astype(int), 0, w - 2)
    y0 = np.clip(np.floor(y).astype(int), 0, h - 2)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    inside = (x >= 0) & (x < w) & (y >= 0) & (y < h)
    out = (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
           + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)
    return out * inside[..., None]


def boxmean(a, k):
    """Mean over a (2k+1) window, wrapping in angle and clamping in radius."""
    pad = np.pad(a, ((k, k), (0, 0)), mode="edge")
    pad = np.pad(pad, ((0, 0), (k, k)), mode="wrap")
    c = np.cumsum(np.cumsum(pad, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    n = 2 * k + 1
    return (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)


# ---------------------------------------------------------------- metrics
def band(p, lo, hi):
    r = np.linspace(0, 1.34, NR)[:, None]
    return (r >= lo) & (r < hi) & np.ones((NR, NTH), bool)


def edge_density(lum):
    """High-frequency energy, normalised by the local mean so a bright region is
    not automatically a detailed one."""
    gr = np.gradient(lum, axis=0)
    gt = np.gradient(lum, axis=1)
    mag = np.hypot(gr, gt)
    base = boxmean(lum, 6) + 1e-6
    rel = mag / base
    rim = band(None, RIM_LO, RIM_HI)
    inner = band(None, IN_LO, IN_HI)
    lit = lum > np.percentile(lum[lum > 0], 25) if (lum > 0).any() else np.ones_like(lum, bool)
    a = rel[rim & lit]
    b = rel[inner & lit]
    return {"edgeRim": float(a.mean()) if a.size else 0.0,
            "edgeInterior": float(b.mean()) if b.size else 0.0,
            "edgeDensity": float(a.mean() / max(b.mean(), 1e-6)) if a.size and b.size else 0.0}


def knots(lum):
    """Isolated local maxima in the rim annulus, per radian of rim, and their
    characteristic diameter in rim radii."""
    rim = band(None, RIM_LO, RIM_HI)
    vals = lum[rim]
    if vals.size == 0 or vals.max() <= 0:
        return {"knotsPerRad": 0.0, "knotDiameterRimRadii": 0.0, "knotCount": 0}
    hi = np.percentile(vals[vals > 0], 96) if (vals > 0).any() else 0
    a = lum
    peak = np.ones_like(a, bool)
    for dr in (-1, 0, 1):
        for dt in (-1, 0, 1):
            if dr == 0 and dt == 0:
                continue
            peak &= a >= np.roll(np.roll(a, dr, axis=0), dt, axis=1)
    peak &= (a > hi) & rim
    count = int(peak.sum())
    # Characteristic size: the area above the same threshold divided by the
    # number of maxima in it, as a diameter, then scaled out of polar cells into
    # rim radii through the annulus' own mean circumference.
    area_cells = int(((a > hi) & rim).sum())
    cell_r = 1.34 / NR
    cell_t = 2 * math.pi * 0.85 / NTH      # arc length at the annulus' midpoint
    diam = 2 * math.sqrt(max(area_cells, 1) * cell_r * cell_t / max(count, 1) / math.pi)
    return {"knotsPerRad": count / (2 * math.pi), "knotDiameterRimRadii": diam,
            "knotCount": count}


def orientation(lum):
    """Structure tensor in the polar frame. In (r, theta) the RADIAL direction
    is the r axis and the TANGENT is the theta axis, so the comparison with the
    local radial direction is free -- no per-pixel angle arithmetic at all."""
    r = np.linspace(0, 1.34, NR)[:, None] + 1e-3
    gr = np.gradient(lum, axis=0)
    # The theta gradient is per CELL; dividing by r turns it into a gradient per
    # unit arc length, which is what makes the tensor isotropic in the plane.
    gt = np.gradient(lum, axis=1) * (NTH / (2 * math.pi)) / (r * NR / 1.34)
    jrr, jtt, jrt = boxmean(gr * gr, 3), boxmean(gt * gt, 3), boxmean(gr * gt, 3)
    # The filament runs along the MINOR eigenvector: perpendicular to the
    # gradient. Angle of the major axis from the r axis:
    ang = 0.5 * np.arctan2(2 * jrt, jrr - jtt)
    # Filament direction = gradient direction + 90 degrees. |cos| against the
    # tangent (theta axis) is |sin(ang)|; against the radius, |cos(ang)|.
    tangential = np.abs(np.sin(ang))
    coherence = np.hypot(jrr - jtt, 2 * jrt) / (jrr + jtt + 1e-9)
    strong = (jrr + jtt) > np.percentile((jrr + jtt)[(jrr + jtt) > 0], 55) if ((jrr + jtt) > 0).any() else np.ones_like(lum, bool)
    rim = band(None, RIM_LO, RIM_HI) & strong & (coherence > 0.25)
    frac = float((tangential[rim] > math.cos(math.radians(60))).mean()) if rim.any() else 0.0
    # The jets: the two opposite sectors with the most light past 1.05 rim
    # radii. Both references are radial exactly there and tangential everywhere
    # else, so one number cannot describe both and this is the second one.
    outer = band(None, 1.02, 1.34)
    per_sector = (lum * outer).reshape(NR, 36, NTH // 36).sum(axis=(0, 2))
    j0 = int(np.argmax(per_sector + np.roll(per_sector, 18)))
    sector = np.zeros(NTH, bool)
    for s in (j0, (j0 + 18) % 36):
        sector[s * (NTH // 36):(s + 1) * (NTH // 36)] = True
    jet = band(None, 0.90, 1.34) & sector[None, :] & strong & (coherence > 0.25)
    radial = np.abs(np.cos(ang))
    jfrac = float((radial[jet] > math.cos(math.radians(60))).mean()) if jet.any() else 0.0
    return {"tangentialFrac": frac, "radialFracJet": jfrac}


def cavities(lum):
    """Share of the disc darker than 35 % of its own annulus median: the holes."""
    r = np.linspace(0, 1.34, NR)
    disc = (r < 1.0)[:, None] & np.ones((NR, NTH), bool)
    med = np.median(lum, axis=1, keepdims=True)
    dark = (lum < 0.35 * med) & disc
    return {"cavityFrac": float(dark.sum() / max(disc.sum(), 1))}


def colour_by_radius(rgb, bins=6):
    r = np.linspace(0, 1.34, NR)
    out = []
    for i in range(bins):
        lo, hi = 1.15 * i / bins, 1.15 * (i + 1) / bins
        sel = (r >= lo) & (r < hi)
        block = rgb[sel]
        w = luminance(block)
        if w.sum() <= 0:
            out.append(0.0)
            continue
        rr = (block[..., 0] * w).sum() / w.sum()
        bb = (block[..., 2] * w).sum() / w.sum()
        out.append(float((rr - bb) / max(rr + bb, 1e-9)))
    return {"colourByRadius": out}


def translucency(lum):
    """Point sources inside the rim as a share of the density outside it. A
    remnant that is drawn OVER the sky hides them; one that is drawn INTO it,
    with a dust column, dims them and lets them through."""
    a = lum
    peak = np.ones_like(a, bool)
    for dr in (-1, 0, 1):
        for dt in (-1, 0, 1):
            if dr == 0 and dt == 0:
                continue
            peak &= a > np.roll(np.roll(a, dr, axis=0), dt, axis=1)
    base = boxmean(a, 5)
    star = peak & (a > base * 2.2) & (a > 0.004)
    inside = band(None, 0.05, 0.95)
    outside = band(None, 1.10, 1.34)
    r = np.linspace(0, 1.34, NR)[:, None] * np.ones((1, NTH))
    area_in = float((r * inside).sum())
    area_out = float((r * outside).sum())
    din = float((star & inside).sum()) / max(area_in, 1e-9)
    dout = float((star & outside).sum()) / max(area_out, 1e-9)
    return {"pointsInside": int((star & inside).sum()), "pointsOutside": int((star & outside).sum()),
            "throughFrac": float(din / dout) if dout > 0 else 0.0}


HUE_BINS = 12


def hue_of(rgb):
    """Hue in turns (0..1) and saturation (1 - min/max) of a linear rgb block.

    Hue is computed on LINEAR rgb rather than on the display encoding, because
    that is what the shader mixes in and what the populations are defined in --
    gamma moves a hue angle a long way when one channel is near zero.
    """
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    c = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    safe = c > 1e-9
    with np.errstate(invalid="ignore", divide="ignore"):
        hr = np.where(safe, ((g - b) / np.maximum(c, 1e-9)) % 6, 0)
        hg = np.where(safe, (b - r) / np.maximum(c, 1e-9) + 2, 0)
        hb = np.where(safe, (r - g) / np.maximum(c, 1e-9) + 4, 0)
    h = np.where(mx == r, hr, np.where(mx == g, hg, hb)) / 6.0
    sat = np.where(mx > 1e-9, c / np.maximum(mx, 1e-9), 0.0)
    return np.where(safe, h % 1.0, 0.0), sat


def tone_stats(p, lit_floor=0.02):
    """Absolute brightness, saturation and the HUE HISTOGRAM.

    These are the v12 numbers and they are deliberately taken BEFORE the
    per-image luminance normalisation the structural metrics use: "brighter and
    far more chromatic" is a claim about absolute values, and normalising is
    exactly what would hide it.

    `bimodality` is the turnover proof. A cloud whose colour is being CROSSFADED
    has one hue peak that slides; a cloud whose POPULATION is turning over has
    two peaks at fixed hues whose heights trade. The statistic is the second
    peak's height as a share of the first, counting only peaks separated by at
    least two bins -- 0 is one tone or a pure gradient, and anything above ~0.35
    is two populations visibly coexisting.
    """
    lum = luminance(p)
    r = np.linspace(0, 1.34, NR)[:, None] * np.ones((1, NTH))
    disc = r < 1.02
    lit = disc & (lum > lit_floor * max(lum.max(), 1e-9))
    if not lit.any():
        return {"p50": 0.0, "p99": 0.0, "satP50": 0.0, "satMean": 0.0,
                "hueHist": [0.0] * HUE_BINS, "bimodality": 0.0, "litFrac": 0.0}
    hue, sat = hue_of(p)
    w = lum[lit]
    hist, _ = np.histogram(hue[lit], bins=HUE_BINS, range=(0, 1), weights=w)
    hist = hist / max(hist.sum(), 1e-9)
    # Circular peak finding, so a population sitting on the wrap does not vanish.
    peaks = [i for i in range(HUE_BINS)
             if hist[i] >= hist[(i - 1) % HUE_BINS] and hist[i] >= hist[(i + 1) % HUE_BINS]]
    peaks.sort(key=lambda i: -hist[i])
    second = 0.0
    for i in peaks[1:]:
        gap = min(abs(i - peaks[0]), HUE_BINS - abs(i - peaks[0]))
        if gap >= 2:
            second = hist[i]
            break
    return {"p50": float(np.percentile(lum[lit], 50)),
            "p99": float(np.percentile(lum[lit], 99)),
            "satP50": float(np.percentile(sat[lit], 50)),
            "satMean": float(sat[lit].mean()),
            "hueHist": [float(v) for v in hist],
            "bimodality": float(second / max(hist[peaks[0]], 1e-9)) if peaks else 0.0,
            "litFrac": float(lit.sum() / max(disc.sum(), 1))}


def hue_by_radius(p, bins=4):
    """The hue histogram per radial bin -- the per-radius version the brief
    asks for, and the one that shows the turnover as a WAVE rather than as a
    whole-object average."""
    r = np.linspace(0, 1.34, NR)[:, None] * np.ones((1, NTH))
    lum = luminance(p)
    hue, _ = hue_of(p)
    out = []
    for i in range(bins):
        lo, hi = 1.02 * i / bins, 1.02 * (i + 1) / bins
        sel = (r >= lo) & (r < hi) & (lum > 0.02 * max(lum.max(), 1e-9))
        if not sel.any():
            out.append([0.0] * HUE_BINS)
            continue
        h, _ = np.histogram(hue[sel], bins=HUE_BINS, range=(0, 1), weights=lum[sel])
        out.append([float(v) for v in h / max(h.sum(), 1e-9)])
    return {"hueByRadius": out}


def measure(rgb, centre, rim, label):
    p = polar(rgb, centre, rim)
    out = {"label": label, "rimRadiusPx": rim, "centre": list(centre)}
    # v12: absolute tone and brightness FIRST, on the un-normalised block.
    out.update(tone_stats(p))
    out.update(hue_by_radius(p))
    lum = luminance(p)
    if lum.max() > 0:
        lum = lum / lum.max()
    out.update(edge_density(lum))
    out.update(knots(lum))
    out.update(orientation(lum))
    out.update(cavities(lum))
    out.update(colour_by_radius(p))
    out.update(translucency(lum))
    return out


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="append", default=[],
                    help="MANIFEST.json[:phase], repeatable")
    ap.add_argument("--frame", action="append", default=[],
                    help="PNG:centreX,centreY,rimPx, repeatable (a live capture)")
    ap.add_argument("--reference", action="append", default=[])
    ap.add_argument("--json", default="")
    ap.add_argument("--csv", default="")
    args = ap.parse_args()

    rows = []
    for spec in args.render:
        img, centre, rim, label = load_render(spec)
        rows.append(measure(img, centre, rim, label))
    for spec in args.frame:
        path, _, geom = spec.partition(":")
        cx, cy, rim = (float(v) for v in geom.split(","))
        rows.append(measure(load_image(path), (cx, cy), rim, pathlib.Path(path).stem))
    for path in args.reference:
        img = load_image(path)
        centre, rim = fit_disc(img)
        rows.append(measure(img, centre, rim, pathlib.Path(path).stem))

    cols = [("edgeDensity", "edge density", "{:.2f}"),
            ("knotsPerRad", "knots/rad", "{:.1f}"),
            ("knotDiameterRimRadii", "knot diam", "{:.4f}"),
            ("tangentialFrac", "tangential", "{:.2f}"),
            ("radialFracJet", "radial jets", "{:.2f}"),
            ("cavityFrac", "cavities", "{:.2f}"),
            ("throughFrac", "through", "{:.2f}")]
    width = max(len(r["label"]) for r in rows) + 1
    print(f"{'':<{width}}" + "".join(f"{h:>13}" for _, h, _ in cols) + "   colour by radius (R-B)/(R+B)")
    for r in rows:
        line = f"{r['label']:<{width}}"
        for key, _, fmt in cols:
            line += f"{fmt.format(r[key]):>13}"
        line += "   " + " ".join(f"{v:+.2f}" for v in r["colourByRadius"])
        print(line)

    # v12's own table: absolute brightness, saturation, and how many hue peaks
    # the cloud has. A render is linear and so is a decoded photograph, so p50
    # and p99 are directly comparable between the two.
    print()
    print(f"{'':<{width}}{'lum p50':>10}{'lum p99':>10}{'sat p50':>10}{'sat mean':>10}"
          f"{'lit frac':>10}{'hue peaks':>11}   hue histogram (12 bins, R->Y->G->C->B->M)")
    for r in rows:
        bars = "".join(" .:-=+*#%@$"[min(10, int(v * 30))] for v in r["hueHist"])
        print(f"{r['label']:<{width}}{r['p50']:>10.4f}{r['p99']:>10.4f}"
              f"{r['satP50']:>10.3f}{r['satMean']:>10.3f}{r['litFrac']:>10.3f}"
              f"{r['bimodality']:>11.3f}   |{bars}|")

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(rows, indent=1))
    if args.csv:
        keys = ["label"] + [c[0] for c in cols]
        lines = [",".join(keys)]
        for r in rows:
            lines.append(",".join(str(r[k]) for k in keys))
        pathlib.Path(args.csv).write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
