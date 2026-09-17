#!/usr/bin/env python3
"""Measurements and contact sheets for meteors, out of meteor-sheet.mjs.

    python3 modules/background/tools/meteor_curve.py MANIFEST.json OUTDIR [--json OUT.json]

Reports, in the order of the V12 acceptance tests:

  M1  the light curve: where along its own path each meteor is brightest (F),
      how sharp that peak is (pointedness P = the curve's width one magnitude
      down over its width two magnitudes down), and how many are double-peaked
  M2  the trail's width at u = 0.1, 0.4, 0.8 of the drawn streak, and the ratio
  M3  the colour along the path: (R-B)/(R+B) and the green excess per fifth,
      plus the bin one head-reach AHEAD of the head (the second spectrum)
  M4  the persistent train's deformation: total absolute turning of its
      measured centreline, sagitta over chord, and how many inflections it has
  M5  whether the train outlives its head at all, and how its width grows
  M7  the share of the light inside the head disc

The centreline is MEASURED, never read back from the uniforms: at each step
along the train's published axis the transverse intensity centroid is taken, so
a straight polyline drawn with a wobbly brush reports as straight and a warped
sample point reports as bent.
"""
import json
import sys
import os
import numpy as np
from PIL import Image, ImageDraw

FLOOR = 2.0 / 255.0


def load(path, w, h):
    return np.fromfile(path, dtype="<f4").reshape(h, w, 4)[:, :, :3]


def linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def bilinear(img, xs, ys):
    """Sample img (h, w, 3) at float coordinates; out of range reads zero."""
    h, w = img.shape[:2]
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    ok = (x0 >= 0) & (y0 >= 0) & (x0 < w - 1) & (y0 < h - 1)
    x0c = np.clip(x0, 0, w - 2)
    y0c = np.clip(y0, 0, h - 2)
    fx = (xs - x0c)[..., None]
    fy = (ys - y0c)[..., None]
    v = (img[y0c, x0c] * (1 - fx) * (1 - fy) + img[y0c, x0c + 1] * fx * (1 - fy)
         + img[y0c + 1, x0c] * (1 - fx) * fy + img[y0c + 1, x0c + 1] * fx * fy)
    return v * ok[..., None]


# ------------------------------------------------------------------ M1
def curve_stats(frames, key="headFlux"):
    """F on the PATH, pointedness, and the double-peak test."""
    u = np.array([f.get("pathU", f["u"]) for f in frames], dtype=float)
    y = np.array([f.get(key, 0.0) for f in frames], dtype=float)
    if y.max() <= 0:
        return None
    i = int(np.argmax(y))
    peak = y[i]

    def width_at(frac):
        """Width of the curve above `frac` of its peak, in path fraction."""
        above = y >= peak * frac
        if not above.any():
            return 0.0
        idx = np.nonzero(above)[0]
        return float(u[idx[-1]] - u[idx[0]])

    # One magnitude is a factor 2.512 in flux, two is 6.31.
    w1 = width_at(1 / 2.512)
    w2 = width_at(1 / 6.310)
    # A second peak: any local maximum at least 0.10 of the path away from the
    # main one and at least 0.55 of it, with a dip of 0.15 between.
    second = False
    for j in range(1, len(y) - 1):
        if y[j] <= y[j - 1] or y[j] < y[j + 1]:
            continue
        if abs(u[j] - u[i]) < 0.10 or y[j] < 0.55 * peak:
            continue
        lo, hi = (min(i, j), max(i, j))
        if y[lo:hi + 1].min() < 0.85 * min(y[i], y[j]):
            second = True
    return dict(F=float(u[i]), peak=float(peak), P=float(w1 / w2) if w2 > 0 else 0.0,
                w1mag=w1, w2mag=w2, doublePeak=second)


# ------------------------------------------------------------------ M4 / M5
def ridge(img, a, b, reach, steps=90):
    """Transverse intensity centroid along the axis a->b, extended 12 % each end.

    Returns (s, offset, weight, width) in pixels: s along the axis, offset
    across it. The axis is only a frame; every number below comes from where
    the light actually is.
    """
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    d = b - a
    L = float(np.hypot(*d))
    if L < 4:
        return None
    d /= L
    n = np.array([-d[1], d[0]])
    v = linear(np.clip(img, 0, 1)).sum(axis=2)
    ss = np.linspace(-0.12 * L, 1.12 * L, steps)
    ts = np.linspace(-reach, reach, max(41, int(reach * 2) | 1))
    S, T = np.meshgrid(ss, ts, indexing="ij")
    xs = a[0] + d[0] * S + n[0] * T
    ys = a[1] + d[1] * S + n[1] * T
    prof = bilinear(v[..., None], xs, ys)[..., 0]
    wsum = prof.sum(axis=1)
    off = np.where(wsum > 1e-9, (prof * ts[None, :]).sum(axis=1) / np.maximum(wsum, 1e-12), np.nan)
    # FWHM per step, for the width growth.
    width = np.full(len(ss), np.nan)
    for i in range(len(ss)):
        p = prof[i]
        if p.max() <= 1e-9:
            continue
        half = p.max() * 0.5
        idx = np.nonzero(p >= half)[0]
        width[i] = (ts[idx[-1]] - ts[idx[0]])
    return dict(s=ss, offset=off, weight=wsum, width=width, L=L, axis=(a, d, n))


def deformation(r, floor_frac=0.06):
    """Total absolute turning, sagitta/chord and inflection count of a ridge."""
    if r is None:
        return None
    w = r["weight"]
    good = np.isfinite(r["offset"]) & (w > max(w.max() * floor_frac, 1e-8))
    if good.sum() < 8:
        return None
    s = r["s"][good]
    o = r["offset"][good]
    # Light smoothing: three samples, which is well under the wavelengths any
    # of the shear spectrum carries, so it removes sampling noise and no bend.
    k = np.ones(3) / 3.0
    o = np.convolve(o, k, mode="same")
    o[0], o[-1] = r["offset"][good][0], r["offset"][good][-1]
    ds = np.diff(s)
    do = np.diff(o)
    ang = np.arctan2(do, ds)
    turn = float(np.abs(np.diff(ang)).sum() * 180 / np.pi)
    chord = float(np.hypot(s[-1] - s[0], o[-1] - o[0]))
    # Perpendicular distance from the straight chord.
    if chord > 1e-6:
        ux, uy = (s[-1] - s[0]) / chord, (o[-1] - o[0]) / chord
        sag = float(np.abs((s - s[0]) * uy - (o - o[0]) * ux).max())
    else:
        sag = 0.0
    second = np.diff(o, 2)
    # Count sign changes of the second difference above a noise floor, which is
    # the number of places the curve genuinely changes which way it bends.
    thr = max(np.abs(second).max() * 0.25, 1e-6)
    sig = np.sign(np.where(np.abs(second) < thr, 0, second))
    sig = sig[sig != 0]
    infl = int((np.diff(sig) != 0).sum()) if len(sig) > 1 else 0
    widths = r["width"][good]
    widths = widths[np.isfinite(widths)]
    return dict(turnDeg=turn, sagChord=sag / chord if chord > 1e-6 else 0.0,
                inflections=infl, chordPx=chord,
                widthMid=float(np.median(widths)) if len(widths) else 0.0)


# ------------------------------------------------------------------ sheets
def contact(frames, w, h, out, captions, columns=4, scale=4):
    keep = [f for f in frames if f.get("raw") and os.path.exists(f["raw"])]
    if not keep:
        return None
    tw, th = w // scale, h // scale
    cols = min(columns, len(keep))
    rows = (len(keep) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 22)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(keep):
        img = np.clip(load(f["raw"], w, h), 0, 1)
        block = img[:th * scale, :tw * scale].reshape(th, scale, tw, scale, 3).max(axis=(1, 3))
        sheet.paste(Image.fromarray((block * 255).astype(np.uint8)), ((i % cols) * tw, (i // cols) * (th + 22)))
        draw.text(((i % cols) * tw + 6, (i // cols) * (th + 22) + th + 5), captions(f), fill=(190, 190, 190))
    sheet.save(out)
    return out


def crop(frame, w, h, cx, cy, size, out, zoom=1):
    img = np.clip(load(frame["raw"], w, h), 0, 1)
    x0, y0 = max(0, int(cx - size // 2)), max(0, int(cy - size // 2))
    x1, y1 = min(w, x0 + size), min(h, y0 + size)
    tile = (img[y0:y1, x0:x1] * 255).astype(np.uint8)
    im = Image.fromarray(tile)
    if zoom > 1:
        im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
    im.save(out)
    return out


# ------------------------------------------------------------------ main
def main():
    manifest = json.load(open(sys.argv[1]))
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    jsonOut = None
    if "--json" in sys.argv:
        jsonOut = sys.argv[sys.argv.index("--json") + 1]
    w, h = manifest["width"], manifest["height"]
    label = manifest["label"]
    report = {"label": label, "width": w, "height": h}

    # ---- M1 -----------------------------------------------------------------
    print(f"== M1  light curve ({label}) ==")
    print("  k  family      dur s   F(drawn)  F(gain)  F(disc)   P     2nd   peak/255  satPx")
    Fs, Ps, doubles = [], [], 0
    for m in manifest["meteors"]:
        c = curve_stats(m["frames"], "headFlux")
        g = curve_stats(m["frames"], "gain")
        # The saturated disc is the one light-curve proxy the display clip
        # cannot flatten: a head already at 255/255 can still grow (V12 1.4).
        s = curve_stats(m["frames"], "satPx")
        if not c:
            continue
        Fs.append(c["F"])
        Ps.append(c["P"])
        doubles += 1 if c["doublePeak"] else 0
        pk = max(f["peak255"] for f in m["frames"])
        sat = max(f.get("satPx", 0) for f in m["frames"])
        print(f"  {m['index']:2d}  {m['family']:<10} {m['duration']:5.2f}   "
              f"{c['F']:7.3f}  {g['F'] if g else 0:7.3f}  {s['F'] if s else 0:7.3f}  {c['P']:5.3f}  "
              f"{'yes' if c['doublePeak'] else ' no':>4}  {pk:7.1f}  {sat:5d}")
        m["stats"] = c
        m["statsDisc"] = s
    if Fs:
        Fs = np.array(Fs)
        print(f"  population  F mean {Fs.mean():.3f}  sd {Fs.std(ddof=0):.3f}   "
              f"P mean {np.mean(Ps):.3f}   double-peaked {doubles}/{len(Fs)} = {100*doubles/len(Fs):.0f} %")
        report["M1"] = dict(Fmean=float(Fs.mean()), Fsd=float(Fs.std(ddof=0)),
                            Pmean=float(np.mean(Ps)), doubleShare=doubles / len(Fs), n=len(Fs))

    fb = []
    for m in manifest.get("fireballs", []):
        c = curve_stats(m["frames"], "headFlux")
        if c:
            fb.append(c["F"])
    if fb:
        print(f"  fireballs   F mean {np.mean(fb):.3f}  ({', '.join(f'{x:.3f}' for x in fb)})")
        report["M1fireball"] = dict(Fmean=float(np.mean(fb)), F=[float(x) for x in fb])

    # ---- M2 / M3 / M7 at each meteor's own peak -----------------------------
    print(f"\n== M2/M3/M7  at the light-curve peak ==")
    print("   k   w(0.1) w(0.4) w(0.8)  ratio | ridgeU mid/head | headShare | rb: head .. tail     lead  green")
    ratios, coreRatios, shares, greens, leads, rbspans, ridgeUs, ridgeRat = [], [], [], [], [], [], [], []
    for m in manifest["meteors"]:
        c = m.get("stats")
        if not c:
            continue
        frames = m["frames"]
        i = int(np.argmin([abs(f.get("pathU", f["u"]) - c["F"]) for f in frames]))
        f = frames[i]
        wds = f.get("width") or [0, 0, 0]
        cds = f.get("core") or [0, 0, 0]
        ratio = wds[2] / wds[0] if wds[0] > 1e-6 else 0
        cratio = cds[2] / cds[0] if cds[0] > 1e-6 else 0
        bins = f.get("bins") or []
        body = [b for b in bins if not b["lead"]]
        lead = next((b for b in bins if b["lead"]), None)
        rb = [b["rb"] for b in body]
        gr = [b["green"] for b in body]
        if not rb:
            continue
        ratios.append(ratio)
        coreRatios.append(cratio)
        shares.append(f.get("headShare", 0))
        greens.append(max(gr[2:]) - gr[0] if len(gr) > 2 else 0)
        leads.append((lead["rb"] - rb[0]) if lead else 0)
        rbspans.append(max(rb) - min(rb))
        ridgeUs.append(f.get("ridgeU", 0))
        ridgeRat.append(f.get("ridgeMidHead", 0))
        print(f"  {m['index']:2d}  {wds[0]:6.2f} {wds[1]:6.2f} {wds[2]:6.2f}  {ratio:5.2f} | "
              f"{f.get('ridgeU', 0):6.3f} {f.get('ridgeMidHead', 0):8.3f} | "
              f"{f.get('headShare', 0):7.3f} | " + " ".join(f"{x:+.3f}" for x in rb)
              + f"  {leads[-1]:+.3f}  {greens[-1]:+.3f}")
    # THE LENS, measured late. At the light-curve peak the head IS the
    # brightest point and should be; the fusiform only shows once the head has
    # flown past its maximum and the trail covers it, which is exactly when a
    # long exposure would record one. Measured at 0.85 of the path.
    lateU, lateRat = [], []
    for m in manifest["meteors"]:
        frames = m["frames"]
        i = int(np.argmin([abs(f.get("pathU", f["u"]) - 0.85) for f in frames]))
        f = frames[i]
        if f.get("ridgeU") is not None:
            lateU.append(f["ridgeU"])
            lateRat.append(f.get("ridgeMidHead", 0))
    if lateU:
        print(f"  late (path 0.85)  ridgeU {np.mean(lateU):.3f}   mid/head {np.mean(lateRat):.3f}")
        report["M2late"] = dict(ridgeU=float(np.mean(lateU)), ridgeMidHead=float(np.mean(lateRat)))
    if ratios:
        print(f"  population  width ratio {np.mean(ratios):.2f}   core ratio {np.mean(coreRatios):.2f}   "
              f"ridgeU {np.mean(ridgeUs):.3f}   mid/head {np.mean(ridgeRat):.3f}   "
              f"head share {np.mean(shares):.3f}   "
              f"rb span {np.mean(rbspans):.3f}   lead excess {np.mean(leads):+.3f}   green excess {np.mean(greens):+.3f}")
        report["M2"] = dict(ratio=float(np.mean(ratios)), coreRatio=float(np.mean(coreRatios)),
                            ridgeU=float(np.mean(ridgeUs)), ridgeMidHead=float(np.mean(ridgeRat)))
        report["M3"] = dict(rbSpan=float(np.mean(rbspans)), leadExcess=float(np.mean(leads)), greenExcess=float(np.mean(greens)))
        report["M7"] = dict(headShare=float(np.mean(shares)))

    # ---- M4 / M5  the persistent train --------------------------------------
    tr = manifest.get("train", {})
    frames = tr.get("frames", [])
    print(f"\n== M4/M5  the persistent train ==")
    if tr.get("child"):
        c = tr["child"]
        print(f"  fireball: flight {c['flight']:.2f} s, train {c['train']:.1f} s")
    print("    age  trainAge   litPx     flux   turn deg   sag/chord   infl   width px   chord px   len px")
    rows = []
    for f in frames:
        if not f.get("raw") or not os.path.exists(f["raw"]):
            continue
        img = load(f["raw"], w, h)
        reach = max(40.0, 14.0 * f.get("trainWidth", 4))
        r = ridge(img, f["p0"], f["p3"], reach)
        d = deformation(r)
        row = dict(age=f["age"], trainAge=f["trainAge"], litPx=f["litPx"], flux=f["flux"],
                   trainLen=f.get("trainLen", 0), gain=f.get("trainGain", 0))
        if d:
            row.update(d)
        rows.append(row)
        print(f"  {f['age']:6.2f}  {f['trainAge']:8.2f}  {f['litPx']:6d}  {f['flux']:8.1f}   "
              + (f"{d['turnDeg']:8.2f}   {d['sagChord']:9.4f}   {d['inflections']:4d}   "
                 f"{d['widthMid']:8.2f}   {d['chordPx']:8.0f}   {f.get('trainLen', 0):6.0f}" if d else "        --"))
    report["M4"] = rows
    alive = [r for r in rows if r["trainAge"] >= 9.5]
    report["M5"] = dict(litAt10s=alive[0]["litPx"] if alive else 0)

    # ---- sheets --------------------------------------------------------------
    sheets = {}
    for m in manifest["meteors"][:1]:
        p = contact(m["frames"], w, h, os.path.join(outdir, f"{label}-meteor-life.png"),
                    lambda f: f"u {f['u']:.2f}  peak {f['peak255']:.0f}  lit {f['litPx']}")
        if p:
            sheets["life"] = p
    p = contact(frames, w, h, os.path.join(outdir, f"{label}-train-life.png"),
                lambda f: f"+{f['trainAge']:.0f} s  lit {f['litPx']}", columns=5)
    if p:
        sheets["train"] = p
    p = contact(manifest["storm"].get("frames", []), w, h, os.path.join(outdir, f"{label}-storm-peak.png"),
                lambda f: f"{f['age']:.0f} s  {f['rate']:.1f}/s  lit {f['litPx']}", columns=3)
    if p:
        sheets["storm"] = p
    # Full-resolution crops: the head at its peak, and the train late in its life.
    for m in manifest["meteors"][:1]:
        c = m.get("stats")
        kept = [f for f in m["frames"] if f.get("raw") and os.path.exists(f["raw"])]
        if kept and c:
            f = min(kept, key=lambda f: abs(f.get("pathU", f["u"]) - c["F"]))
            sheets["headCrop"] = crop(f, w, h, f["head"][0], f["head"][1], 360,
                                      os.path.join(outdir, f"{label}-meteor-head-crop.png"), zoom=2)
    late = [f for f in frames if f.get("raw") and os.path.exists(f["raw"]) and f["trainAge"] > 5]
    if late:
        f = late[len(late) // 2]
        cx = (f["p0"][0] + f["p3"][0]) // 2
        cy = (f["p0"][1] + f["p3"][1]) // 2
        sheets["trainCrop"] = crop(f, w, h, cx, cy, 900, os.path.join(outdir, f"{label}-train-crop.png"))
    report["sheets"] = sheets
    for k, v in sheets.items():
        print(f"  sheet {k}: {v}")

    if jsonOut:
        json.dump(report, open(jsonOut, "w"), indent=2)
        print("json " + jsonOut)


if __name__ == "__main__":
    main()
