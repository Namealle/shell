#!/usr/bin/env python3
"""M6: does a fragmenting storm streak actually SEPARATE, and does a faint one not?

    python3 modules/background/tools/storm_fragments.py MANIFEST.json [--json OUT.json]

Reads the .f32 frames storm-sheet.mjs rendered and, for every lit component,
finds the HEADS inside it -- local maxima of the linear image, separated by at
least a head width -- then measures where they sit in that component's own
frame: along its principal axis (the drag lag, which should grow as t^2) and
across it (the ballistic splay, which should grow linearly).

The shipped kernel put two siblings at a FIXED lateral offset that never
decelerated, so a fragmenting streak was a wider streak: every component had
its extra maxima at the same separation on every frame, and none of them ever
fell behind. What is reported here is the distribution over a whole storm, not
one lucky streak, because the hash draws the fragment count per streak and a
single frame proves nothing.
"""
import json
import os
import sys
import numpy as np


FLOOR = 2.0 / 255.0


def load(path, w, h):
    return np.fromfile(path, dtype="<f4").reshape(h, w, 4)[:, :, :3]


def linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def components(mask, minimum=40):
    """Flood fill; yields boolean masks of each component above `minimum` px."""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if len(pts) >= minimum:
            yield np.array(pts)


def heads(v, pts, sep):
    """Compact HEADS inside a component: local maxima that stand above their own
    annulus, which a smooth trail ridge does not.

    A streak is a long bright ridge, so "brightest pixel at least sep away from
    the last" finds a maximum every sep pixels down its length and reports a
    single meteor as a comb of seven. A head is a BLOB: its value at the centre
    is well above the mean of the ring at sep..2*sep around it, because the
    trail on either side of a head is dimmer than the head. That ratio is the
    test, and it is what separates a fragment from a bright patch of wake.
    """
    h, w = v.shape
    vals = v[pts[:, 0], pts[:, 1]]
    order = np.argsort(-vals)
    top = vals[order[0]]
    picked = []
    r1, r2 = sep, 2.0 * sep
    for i in order:
        y, x = int(pts[i][0]), int(pts[i][1])
        if vals[i] < top * 0.06:
            break
        if any((y - py) ** 2 + (x - px) ** 2 < sep * sep for py, px, _ in picked):
            continue
        y0, y1 = max(0, int(y - r2)), min(h, int(y + r2) + 1)
        x0, x1 = max(0, int(x - r2)), min(w, int(x + r2) + 1)
        sub = v[y0:y1, x0:x1]
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d2 = (yy - y) ** 2 + (xx - x) ** 2
        ring = (d2 >= r1 * r1) & (d2 <= r2 * r2)
        core = d2 <= (0.5 * r1) ** 2
        if not ring.any() or not core.any():
            continue
        if sub[core].max() > vals[i] + 1e-12:
            continue                                # not a local maximum
        if vals[i] < 1.8 * float(sub[ring].mean()):
            continue                                # a ridge, not a blob
        picked.append((y, x, float(vals[i])))
        if len(picked) >= 8:
            break
    return picked


def sigma_of(v, y, x, reach):
    """Second moment of the light around one head, as a drawn sigma in px."""
    h, w = v.shape
    y0, y1 = max(0, int(y - reach)), min(h, int(y + reach) + 1)
    x0, x1 = max(0, int(x - reach)), min(w, int(x + reach) + 1)
    sub = v[y0:y1, x0:x1]
    yy, xx = np.mgrid[y0:y1, x0:x1]
    r2 = (yy - y) ** 2 + (xx - x) ** 2
    keep = r2 <= reach * reach
    tot = sub[keep].sum()
    if tot <= 1e-9:
        return 0.0
    return float(np.sqrt((sub[keep] * r2[keep]).sum() / tot / 2.0))


def main():
    manifest = json.load(open(sys.argv[1]))
    out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    w, h = manifest["width"], manifest["height"]
    short = min(w, h)
    sep = max(6.0, float(np.mean([f.get("headSigma", 3.0) for f in manifest["frames"]])) * 4.0)
    rows = []
    print(f"buffer {w}x{h}   head separation floor {sep:.1f} px")
    print("\n age s   comps   multi   heads/comp   along px   across px   sigma ratio")
    for f in manifest["frames"]:
        raw = f.get("raw")
        if not raw or not os.path.exists(raw):
            continue
        img = load(raw, w, h)
        v = linear(np.clip(img, 0, 1)).sum(axis=2)
        mask = img.max(axis=2) >= FLOOR
        comps = 0
        multi = 0
        counts, alongs, acrosses, ratios = [], [], [], []
        for pts in components(mask):
            comps += 1
            hs = heads(v, pts, sep)
            counts.append(len(hs))
            if len(hs) < 2:
                continue
            multi += 1
            # The component's own frame: principal axis of its lit pixels.
            c = pts.mean(axis=0)
            d = pts - c
            cov = (d.T @ d) / max(1, len(d))
            evals, evecs = np.linalg.eigh(cov)
            axis = evecs[:, int(np.argmax(evals))]
            nrm = np.array([-axis[1], axis[0]])
            lead = np.array(hs[0][:2], dtype=float)
            al, ac, sg = [], [], []
            # A fragment comb stays NEAR its leader: 100 m/s for a second at
            # 100 km is 0.057 degrees. Anything further than a tenth of the
            # short side away is another streak that happened to cross this one
            # and get flood-filled into the same component, not a sibling.
            reachCap = 0.10 * short
            hs = [p for p in hs if (p[0] - lead[0]) ** 2 + (p[1] - lead[1]) ** 2 <= reachCap * reachCap]
            if len(hs) < 2:
                multi -= 1
                continue
            for (y, x, val) in hs:
                q = np.array([y, x], dtype=float) - lead
                al.append(abs(float(q @ axis)))
                ac.append(abs(float(q @ nrm)))
                sg.append(sigma_of(v, y, x, sep))
            alongs.append(max(al))
            acrosses.append(max(ac))
            sg = [s for s in sg if s > 0]
            ratios.append(max(sg) / min(sg) if len(sg) > 1 and min(sg) > 0 else 1.0)
        row = dict(age=f["age"], comps=comps, multi=multi,
                   headsPerComp=float(np.mean(counts)) if counts else 0.0,
                   alongPx=float(np.mean(alongs)) if alongs else 0.0,
                   acrossPx=float(np.mean(acrosses)) if acrosses else 0.0,
                   sigmaRatio=float(np.mean(ratios)) if ratios else 0.0,
                   rate=f.get("rate", 0))
        rows.append(row)
        print(f"{f['age']:6.1f}   {comps:5d}   {multi:5d}   {row['headsPerComp']:10.2f}   "
              f"{row['alongPx']:8.1f}   {row['acrossPx']:9.1f}   {row['sigmaRatio']:11.2f}")

    live = [r for r in rows if r["multi"]]
    if live:
        print(f"\n  components with more than one head: {sum(r['multi'] for r in rows)} of {sum(r['comps'] for r in rows)}")
        print(f"  heads per multi-head component   : {np.mean([r['headsPerComp'] for r in live]):.2f}")
        print(f"  worst lag behind the leader      : {max(r['alongPx'] for r in live):.0f} px "
              f"({100 * max(r['alongPx'] for r in live) / short:.1f} % of the short side)")
        print(f"  widest splay across the path     : {max(r['acrossPx'] for r in live):.0f} px")
        print(f"  drawn sigma ratio, largest       : {max(r['sigmaRatio'] for r in live):.2f}")
    if out:
        json.dump(dict(width=w, height=h, sep=sep, frames=rows), open(out, "w"), indent=2)
        print("json " + out)


if __name__ == "__main__":
    main()
