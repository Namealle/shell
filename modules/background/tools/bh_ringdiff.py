#!/usr/bin/env python3
"""Measured diff between the owner's reference black hole and ours.

Both images are reduced to the SAME frame -- shadow centred, shadow radius
normalised to RN px -- then measured, so every number below is comparable:

  extentMajor        disk half-length along the projected major axis, in Rh
  tipHalfHeight      vertical half-thickness at .8*extent, in Rh   (thin ellipse?)
  midHalfHeight      same at .45*extent
  aspect             tipHalfHeight/extent -- the ellipse's squash
  topArcThickness    radial thickness of the bright band over the shadow, in Rh
  photonRadius       radius of the sharp inner light edge above the shadow, in Rh
  nearStripY         signed height of the front crossing below centre, in Rh
  nearStripPeak      its peak linear luminance
  dopplerRatio       mean light left-of-centre / right-of-centre
  q50/q90/q99/q999   linear-luminance percentiles over lit pixels
  footprint          fraction of the frame above 1% of the cap
  rimRagged          high-frequency energy along an azimuthal ring (smooth<->filamentary)
  cctInner/cctOuter  R/B ratio at .25 and .85 of the extent (warm = high)
  whiteFrac          fraction of disk light within 12% of neutral (the white band)

Usage:
  python3 bh_ringdiff.py --ref ~/Downloads/LocalSend/wallpaper.png \
      --out ~/namealle/claude/caelestia/starfield-v2/evidence/v7-ring --tag v7
  python3 bh_ringdiff.py ... --override '{"disk":{"falloff":3}}'
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bh_probe

RN = 160.0          # normalised shadow radius, px
HALF_W, HALF_H = 7.0, 4.0   # normalised frame, in Rh
LUM = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def to_linear(a):
    a = a.astype(np.float32) / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, 12.92 * a, 1.055 * a ** (1 / 2.4) - 0.055)


def lum(rgb):
    return rgb @ LUM


def box_min(a, k):
    """Separable running minimum, radius k. Kills stars without scipy."""
    for axis in (0, 1):
        a = np.moveaxis(a, axis, 0)
        p = np.pad(a, ((k, k),) + ((0, 0),) * (a.ndim - 1), mode="edge")
        a = np.min(np.stack([p[i:i + a.shape[0]] for i in range(2 * k + 1)]), 0)
        a = np.moveaxis(a, 0, axis)
    return a


def box_max(a, k):
    for axis in (0, 1):
        a = np.moveaxis(a, axis, 0)
        p = np.pad(a, ((k, k),) + ((0, 0),) * (a.ndim - 1), mode="edge")
        a = np.max(np.stack([p[i:i + a.shape[0]] for i in range(2 * k + 1)]), 0)
        a = np.moveaxis(a, 0, axis)
    return a


def destar(rgb, k=5):
    """Grey opening: stars (a few px, isolated) vanish, the disk survives."""
    l = lum(rgb)
    keep = box_max(box_min(l, k), k)
    scale = np.where(l > 1e-6, np.minimum(1.0, keep / np.maximum(l, 1e-6)), 1.0)
    return rgb * scale[..., None]


_ANG = np.linspace(0, 2 * np.pi, 72, endpoint=False)
_COS, _SIN = np.cos(_ANG), np.sin(_ANG)


def _sample(l, x, y):
    h, w = l.shape
    x = np.clip(x, 0, w - 2)
    y = np.clip(y, 0, h - 2)
    x0, y0 = x.astype(np.int32), y.astype(np.int32)
    fx, fy = x - x0, y - y0
    return ((l[y0, x0] * (1 - fx) + l[y0, x0 + 1] * fx) * (1 - fy)
            + (l[y0 + 1, x0] * (1 - fx) + l[y0 + 1, x0 + 1] * fx) * fy)


def _hole_score(l, cx, cy, radii):
    """Score every candidate radius at one centre by sampling two concentric
    rings of 72 azimuths. The outer ring uses its 25th PERCENTILE, not its mean,
    so a circle that only catches the bright top arc cannot win: the light has
    to surround the shadow the way it does in both images."""
    r = np.asarray(radii, np.float32)[:, None]
    inner = np.stack([_sample(l, cx + f * r * _COS, cy - f * r * _SIN)
                      for f in (0.45, 0.70, 0.88)]).mean(0)
    outer = np.stack([_sample(l, cx + f * r * _COS, cy - f * r * _SIN)
                      for f in (1.10, 1.22, 1.36)]).mean(0)
    return np.percentile(outer, 25, axis=1) - 3.0 * inner.mean(1)


def find_hole(l, scale_hint=None):
    """(cx, cy, R) of the shadow: the circle whose interior is darkest and whose
    surrounding annulus is brightest. Searched on a <=400 px proxy, then the
    result is scaled back, so a 2752 px reference costs a couple of seconds."""
    h, w = l.shape
    k = min(1.0, 400.0 / w)
    if k < 1.0:
        small = np.asarray(Image.fromarray(l).resize(
            (int(w * k), int(h * k)), Image.BILINEAR), dtype=np.float32)
    else:
        small = l
    sh, sw = small.shape
    ys, xs = np.mgrid[0:sh, 0:sw].astype(np.float32)
    bright = small > np.quantile(small, 0.999)
    cx, cy = float(xs[bright].mean()), float(ys[bright].mean())
    r0 = sw * 0.05
    radii = r0 * np.linspace(0.35, 2.4, 100)
    for span, step in ((10, sw / 40.0), (8, sw / 200.0), (8, sw / 900.0)):
        best, arg = -1e9, (cx, cy, r0)
        for dx in np.linspace(-span * step, span * step, 2 * span + 1):
            for dy in np.linspace(-span * step, span * step, 2 * span + 1):
                sc = _hole_score(small, cx + dx, cy + dy, radii)
                i = int(np.argmax(sc))
                if sc[i] > best:
                    best, arg = sc[i], (cx + dx, cy + dy, float(radii[i]))
        cx, cy, r0 = arg
        radii = r0 * np.linspace(0.90, 1.11, 50)
    fit = edge_fit(small, cx, cy, r0)
    if fit and 0.75 < fit[2] / r0 < 1.35:
        cx, cy, r0 = fit
    return (cx / k, cy / k, r0 / k)


def edge_fit(l, cx, cy, r0):
    """Refine to the shadow boundary itself: the steepest radial brightness rise,
    at 72 azimuths, outliers dropped, a circle least-squares-fitted to what is
    left. The ring score above is only azimuthally averaged and reads ~6% small;
    this lands on the boundary a drawn circle would trace."""
    ang = np.radians(np.arange(0, 360, 5.0))
    ca, sa = np.cos(ang), np.sin(ang)
    out = None
    for _ in range(40):
        t = np.arange(0.40 * r0, 2.0 * r0, max(0.2, r0 / 400.0))
        v = _sample(l, cx + t[:, None] * ca, cy - t[:, None] * sa)
        e = t[np.argmax(np.gradient(v, axis=0), axis=0)]
        med = np.median(e)
        keep = np.abs(e - med) < max(2.5 * np.median(np.abs(e - med)), 0.05 * med)
        if keep.sum() < 12:
            return None
        ex, ey = (cx + e * ca)[keep], (cy - e * sa)[keep]
        s = np.linalg.lstsq(np.c_[ex, ey, np.ones(keep.sum())],
                            ex ** 2 + ey ** 2, rcond=None)[0]
        ncx, ncy = s[0] / 2, s[1] / 2
        R = float(np.sqrt(max(s[2] + ncx ** 2 + ncy ** 2, 1e-6)))
        done = out and abs(R - out[2]) < 0.02 and abs(ncx - cx) < 0.02 and abs(ncy - cy) < 0.02
        cx, cy, r0, out = float(ncx), float(ncy), R, (float(ncx), float(ncy), R)
        if done:
            break
    return out


def normalise(rgb, hole, rot=0.0):
    """Resample so the shadow is radius RN at the frame centre and the disk's
    projected major axis is horizontal. `rot` is that axis's angle in degrees,
    CCW positive in screen coordinates (y down)."""
    cx, cy, r = hole
    k = RN / r
    W, H = int(2 * HALF_W * RN), int(2 * HALF_H * RN)
    u = (np.arange(W) - W / 2 + 0.5)[None, :] / k
    v = (np.arange(H) - H / 2 + 0.5)[:, None] / k
    c, s = np.cos(np.radians(rot)), np.sin(np.radians(rot))
    gx = cx + u * c + v * s
    gy = cy - u * s + v * c
    x0 = np.clip(np.floor(gx).astype(int), 0, rgb.shape[1] - 2)
    y0 = np.clip(np.floor(gy).astype(int), 0, rgb.shape[0] - 2)
    fx, fy = (gx - x0)[..., None], (gy - y0)[..., None]
    a = rgb[y0, x0]
    b = rgb[y0, x0 + 1]
    d = rgb[y0 + 1, x0]
    e = rgb[y0 + 1, x0 + 1]
    return ((a * (1 - fx) + b * fx) * (1 - fy) + (d * (1 - fx) + e * fx) * fy).astype(np.float32)


def find_angle(rgb, hole):
    """Position angle of the projected major axis: the direction whose outer
    light integral (1.6-6 Rh, both arms) is largest. Tenth-degree resolution."""
    cx, cy, r = hole
    l = lum(rgb)
    t = np.linspace(1.6, 6.0, 260) * r
    best, arg = -1e9, 0.0
    for step, span in ((1.0, 45), (0.1, 12)):
        for a in arg + step * np.arange(-span, span + 1):
            rad = np.radians(a)
            tot = 0.0
            for sgn in (1, -1):
                x = cx + sgn * t * np.cos(rad)
                y = cy - sgn * t * np.sin(rad)
                ok = (x >= 0) & (x < l.shape[1] - 1) & (y >= 0) & (y < l.shape[0] - 1)
                tot += float((_sample(l, x, y) * ok).sum())
            if tot > best:
                best, arg = tot, float(a)
    return arg


def ray(l, ang, rmax=HALF_W, n=900):
    """Luminance sampled outward from the centre along `ang` (deg, 0 = +x, CCW)."""
    H, W = l.shape
    t = np.linspace(0.0, rmax, n)
    x = W / 2 + t * RN * np.cos(np.radians(ang))
    y = H / 2 - t * RN * np.sin(np.radians(ang))
    ok = (x >= 0) & (x < W - 1) & (y >= 0) & (y < H - 1)
    out = np.zeros(n, np.float32)
    xi, yi = np.clip(x, 0, W - 2), np.clip(y, 0, H - 2)
    x0, y0 = xi.astype(int), yi.astype(int)
    fx, fy = xi - x0, yi - y0
    out = ((l[y0, x0] * (1 - fx) + l[y0, x0 + 1] * fx) * (1 - fy)
           + (l[y0 + 1, x0] * (1 - fx) + l[y0 + 1, x0 + 1] * fx) * fy)
    return t, np.where(ok, out, 0.0)


def column(l, xRh, n=800):
    """Luminance down a vertical line at x = xRh (Rh), y from -HALF_H..HALF_H."""
    H, W = l.shape
    t = np.linspace(-HALF_H, HALF_H, n)
    x = np.clip(W / 2 + xRh * RN, 0, W - 2)
    y = np.clip(H / 2 + t * RN, 0, H - 2)
    x0, y0 = int(x), y.astype(int)
    fx, fy = x - x0, y - y0
    return t, ((l[y0, x0] * (1 - fx) + l[y0, x0 + 1] * fx) * (1 - fy)
               + (l[y0 + 1, x0] * (1 - fx) + l[y0 + 1, x0 + 1] * fx) * fy)


def measure(rgb):
    l = lum(rgb).astype(np.float32)
    H, W = l.shape
    m = {}
    peak = float(np.quantile(l, 0.99995))
    m["peak"] = peak

    # --- major-axis extent: outward along +x and -x, last radius above 4% peak
    ext = []
    for ang in (0.0, 180.0):
        t, v = ray(l, ang)
        hot = np.where(v > 0.04 * peak)[0]
        ext.append(float(t[hot[-1]]) if len(hot) else 0.0)
    m["extentR"], m["extentL"] = ext[0], ext[1]
    m["extentMajor"] = float(np.mean(ext))

    # --- vertical half-thickness of the arm at FIXED radii, so both images are
    # measured at the same physical place rather than at a fraction of their own
    # extent (which would hide a length difference inside a thickness number).
    for name, rr in (("mid", 1.8), ("out", 2.5), ("tip", 3.2)):
        hh = []
        for sgn in (1, -1):
            t, v = column(l, sgn * rr)
            hot = np.where(v > 0.06 * peak)[0]
            hh.append(float(t[hot[-1]] - t[hot[0]]) / 2 if len(hot) else 0.0)
        m[name + "HalfHeight"] = float(np.mean(hh))
    m["aspect"] = m["tipHalfHeight"] / max(m["extentMajor"], 1e-6)

    # --- the bright bands over and under the shadow, along +90 / -90 deg.
    # Both, because the UNDER side is where the near strip, the lensed lower
    # arc and the inner halo all pile up and can bloom into a lobe.
    for name, a0 in (("top", 90.0), ("bot", 270.0)):
        t, v = ray(l, a0)
        hot = np.where(v > 0.20 * peak)[0]
        m[name + "ArcInner"] = float(t[hot[0]]) if len(hot) else 0.0
        m[name + "ArcOuter"] = float(t[hot[-1]]) if len(hot) else 0.0
        m[name + "ArcThickness"] = m[name + "ArcOuter"] - m[name + "ArcInner"]
        m[name + "ArcPeak"] = float(v.max())
    t, v = ray(l, 90.0)
    # sharp inner light edge = steepest rise between .9 and 2 Rh
    w = (t > 0.9) & (t < 2.0)
    g = np.gradient(v)
    m["photonRadius"] = float(t[w][np.argmax(g[w])]) if w.any() else 0.0

    # --- near strip: the FRONT crossing, wherever it falls. In the reference it
    # runs across the shadow itself, so the search must not start outside it.
    t, v = column(l, 0.0)
    below = (t > 0.15) & (t < 2.6)
    if below.any() and v[below].max() > 0.02 * peak:
        i = int(np.argmax(v[below]))
        m["nearStripY"] = float(t[below][i])
        m["nearStripPeak"] = float(v[below][i])
        hot = np.where(v[below] > 0.30 * v[below][i])[0]
        m["nearStripHeight"] = float(t[below][hot[-1]] - t[below][hot[0]]) if len(hot) else 0.0
    else:
        m["nearStripY"] = m["nearStripPeak"] = m["nearStripHeight"] = 0.0
    # How much of the black disk the foreground actually covers.
    ys0, xs0 = np.mgrid[0:H, 0:W]
    inside = np.hypot(xs0 - W / 2, ys0 - H / 2) < 0.92 * RN
    m["shadowLit"] = float((l[inside] > 0.15 * peak).mean())

    # --- Doppler asymmetry over the two halves of the disk
    ys, xs = np.mgrid[0:H, 0:W]
    d = np.hypot(xs - W / 2, ys - H / 2) / RN
    disk = (d > 1.05) & (l > 0.02 * peak)
    left, right = disk & (xs < W / 2), disk & (xs > W / 2)
    m["dopplerRatio"] = float(l[left].mean() / max(l[right].mean(), 1e-9)) if right.any() else 0.0

    # --- levels
    lit = l[l > 0.01 * peak]
    for q, k in ((0.5, "q50"), (0.9, "q90"), (0.99, "q99"), (0.999, "q999")):
        m[k] = float(np.quantile(lit, q)) if lit.size else 0.0
    m["footprint"] = float((l > 0.01).mean())

    # --- raggedness: high-frequency energy along azimuthal rings. 2.4 Rh reads
    # the outer disk arm, 1.15 Rh the bright band hugging the shadow.
    ang = np.linspace(0, 2 * np.pi, 2048, endpoint=False)
    for name, rr in (("rimRagged", 2.4), ("ringRagged", 1.15)):
        x = np.clip(W / 2 + rr * RN * np.cos(ang), 0, W - 1).astype(int)
        y = np.clip(H / 2 - rr * RN * np.sin(ang), 0, H - 1).astype(int)
        s = l[y, x]
        s = s / max(s.mean(), 1e-9)
        sm = np.convolve(np.r_[s[-16:], s, s[:16]], np.ones(33) / 33, "same")[16:-16]
        m[name] = float(np.std(s - sm))

    # --- "drawn circle" energy: high-frequency RADIAL structure in the polar
    # sector out at 1.8-3.6 Rh, where a concentric band shows as a ripple on an
    # otherwise smooth falloff. The owner rejected drawn rings in v5 ("they look
    # like drawn"), and no other metric here can see them.
    ce = []
    for a0 in (70, 90, 110, 250, 270, 290):
        t, v = ray(l, a0, rmax=3.6)
        w2 = t > 1.8
        seg = v[w2] / max(v[w2].mean(), 1e-9)
        sm = np.convolve(np.r_[seg[:12][::-1], seg, seg[-12:][::-1]],
                         np.ones(25) / 25, "same")[12:-12]
        ce.append(float(np.std(seg - sm)))
    m["circleEnergy"] = float(np.mean(ce))
    m["nearFarRatio"] = m["nearStripPeak"] / max(m["topArcPeak"], 1e-9)

    # --- colour: light-weighted R/B ratio in a full column of the disk arm at a
    # fixed radius, both sides averaged. Only lit pixels, so it never reads sky.
    for name, rr in (("cctInner", 1.5), ("cctOuter", 3.0)):
        acc = []
        for sgn in (1, -1):
            xx = int(np.clip(W / 2 + sgn * rr * RN, 0, W - 1))
            band = rgb[:, max(0, xx - 10):xx + 10].reshape(-1, 3)
            band = band[lum(band) > 0.05 * peak]
            if band.size:
                acc.append(float(band[:, 0].sum() / max(band[:, 2].sum(), 1e-9)))
        m[name] = float(np.mean(acc)) if acc else 0.0

    # --- radial light profile: mean luminance in annuli, and the same split
    # into the disk plane (+-25 deg of the major axis) and the polar cap.
    d = np.hypot(xs - W / 2, ys - H / 2) / RN
    ang = np.abs(np.degrees(np.arctan2(-(ys - H / 2), xs - W / 2)))
    ang = np.minimum(ang, 180 - ang)
    edges = [1.0, 1.2, 1.45, 1.75, 2.1, 2.6, 3.2, 4.0, 5.0, 6.5]
    prof, plane, pole = [], [], []
    for a0, a1 in zip(edges[:-1], edges[1:]):
        sel = (d >= a0) & (d < a1)
        prof.append(float(l[sel].mean()) if sel.any() else 0.0)
        s2 = sel & (ang < 25)
        plane.append(float(l[s2].mean()) if s2.any() else 0.0)
        s3 = sel & (ang > 65)
        pole.append(float(l[s3].mean()) if s3.any() else 0.0)
    m["_profile"] = prof
    m["_plane"] = plane
    m["_pole"] = pole
    m["_edges"] = edges

    # --- white fraction: light carried by near-neutral pixels
    bright = l > 0.25 * peak
    if bright.sum():
        c = rgb[bright]
        mx, mn = c.max(1), c.min(1)
        neutral = (mx - mn) / np.maximum(mx, 1e-9) < 0.12
        m["whiteFrac"] = float(l[bright][neutral].sum() / max(l[bright].sum(), 1e-9))
    else:
        m["whiteFrac"] = 0.0
    return m


KEYS = ["posAngle", "extentMajor", "extentL", "extentR", "midHalfHeight",
        "outHalfHeight", "tipHalfHeight", "aspect", "topArcInner", "topArcOuter",
        "topArcThickness", "topArcPeak", "botArcInner", "botArcOuter",
        "botArcThickness", "botArcPeak", "photonRadius", "nearStripY",
        "nearStripHeight", "nearStripPeak", "shadowLit", "dopplerRatio", "peak",
        "q50", "q90", "q99", "q999", "footprint", "rimRagged", "ringRagged", "circleEnergy",
        "nearFarRatio", "cctInner",
        "cctOuter", "whiteFrac"]


def table(ref, ours, tag):
    out = ["| metric | reference | %s | delta |" % tag, "|---|---:|---:|---:|"]
    for k in KEYS:
        a, b = ref.get(k, 0.0), ours.get(k, 0.0)
        d = b - a
        rel = "" if abs(a) < 1e-9 else "  (%+.0f%%)" % (100 * d / abs(a))
        out.append("| %s | %.4f | %.4f | %+.4f%s |" % (k, a, b, d, rel))
    e = ref["_edges"]
    bands = ["%.2f-%.2f" % (a, b) for a, b in zip(e[:-1], e[1:])]
    out += ["", "| annulus Rh | ref all | %s all | ref plane | %s plane | ref pole | %s pole |"
            % (tag, tag, tag), "|---|---:|---:|---:|---:|---:|---:|"]
    for i, b in enumerate(bands):
        out.append("| %s | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |" %
                   (b, ref["_profile"][i], ours["_profile"][i], ref["_plane"][i],
                    ours["_plane"][i], ref["_pole"][i], ours["_pole"][i]))
    return "\n".join(out)


def compose(refN, oursN, path):
    """Side-by-side over an overlay (reference red / ours cyan)."""
    H, W, _ = refN.shape
    a, b = to_srgb(refN), to_srgb(oursN)
    over = np.zeros_like(a)
    over[..., 0] = np.clip(lum(refN), 0, None) ** 0.45
    over[..., 1] = over[..., 2] = np.clip(lum(oursN), 0, None) ** 0.45
    stack = np.concatenate([a, b, np.clip(over, 0, 1)], 0)
    img = Image.fromarray((np.clip(stack, 0, 1) * 255 + 0.5).astype(np.uint8))
    img.thumbnail((1600, 4000))
    img.save(path)


_REF = {}


def reference(path=None):
    """Normalised reference frame + its measurements, computed once."""
    path = path or os.path.expanduser("~/Downloads/LocalSend/wallpaper.png")
    if path not in _REF:
        ref = to_linear(np.asarray(Image.open(path).convert("RGB")))
        ref = destar(ref, k=max(3, ref.shape[1] // 400))
        hole = find_hole(lum(ref))
        ang = find_angle(ref, hole)
        n = normalise(ref, hole, ang)
        m = measure(n)
        m["posAngle"] = ang
        _REF[path] = (n, m, hole, ang)
    return _REF[path]


def evaluate(override=None, preset="target", width=1376, height=768, phase=0.0):
    """Render one variant and measure it in the reference's frame."""
    img = bh_probe.render(width, height, preset, override or {}, detail_phase=phase)
    rh = bh_probe.render.last_rh
    hole = (width / 2.0, height / 2.0, rh)
    ang = find_angle(img, hole)
    n = normalise(img, hole, ang)
    m = measure(n)
    m["posAngle"] = ang
    return n, m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=os.path.expanduser("~/Downloads/LocalSend/wallpaper.png"))
    ap.add_argument("--out", default=os.path.expanduser(
        "~/namealle/claude/caelestia/starfield-v2/evidence/v7-ring"))
    ap.add_argument("--tag", default="ours")
    ap.add_argument("--preset", default="target")
    ap.add_argument("--override", default="{}")
    ap.add_argument("--width", type=int, default=1376)
    ap.add_argument("--height", type=int, default=768)
    ap.add_argument("--phase", type=float, default=0.0)
    ap.add_argument("--no-image", action="store_true")
    a = ap.parse_args()

    refN, mr, hole, refAng = reference(a.ref)
    oursN, mo = evaluate(json.loads(a.override), a.preset, a.width, a.height, a.phase)
    rh = bh_probe.render.last_rh
    print("reference hole: centre (%.1f, %.1f) radius %.1f px, major axis %+.1f deg"
          % (hole + (refAng,)))
    print("ours: Rh %.2f px at %dx%d, major axis %+.1f deg"
          % (rh, a.width, a.height, mo["posAngle"]))
    print(table(mr, mo, a.tag))
    if not a.no_image:
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        compose(refN, oursN, a.out + "-%s.png" % a.tag)
        print("\nwrote %s-%s.png" % (a.out, a.tag))
    json.dump({"ref": mr, a.tag: mo, "hole": hole, "rh": rh},
              open(a.out + "-%s.json" % a.tag, "w"), indent=1)


if __name__ == "__main__":
    main()
