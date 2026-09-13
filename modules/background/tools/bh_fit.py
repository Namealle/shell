#!/usr/bin/env python3
"""Coordinate descent of the black hole preset against the owner's reference.

The judgement is in OBJECTIVE below -- which measurements matter and how much.
The search itself is clerical, so it is scripted: hand-tuning eighteen coupled
knobs by eye is exactly the work that measured 20-50% right in the 2026-09-06
comparison, while the scripted half measured 97-100%.

  python3 bh_fit.py                      # fit from the current target preset
  python3 bh_fit.py --rounds 3 --only disk.falloff,disk.halo.gain
  python3 bh_fit.py --start '{"disk":{"falloff":1.2}}'
"""
import argparse
import copy
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bh_ringdiff as B

# key path -> (lo, hi, candidate step list). Only keys the owner has not fixed.
SPACE = {
    "disk.falloff":                (1.0, 3.0, [0.15, 0.4]),
    "disk.exposure":               (0.5, 2.0, [0.1, 0.25]),
    "disk.detail":                 (0.0, 0.85, [0.08, 0.2]),
    "disk.halo.gain":              (0.0, 1.0, [0.06, 0.15]),
    "disk.halo.reachRh":           (1.0, 2.0, [0.04, 0.1]),
    "disk.doppler.strength":       (0.0, 1.0, [0.04, 0.1]),
    "disk.hue.innerTemperature":   (4200, 10000, [300, 900]),
    "disk.hue.outerTemperature":   (1000, 2800, [120, 350]),
    "disk.hue.whiteness":          (0.0, 1.0, [0.05, 0.12]),
    "disk.hue.warmth":             (0.0, 1.0, [0.06, 0.15]),
    # Floors, not zero: the owner asked for a ragged frayed rim and a skirt
    # (v5 brief item 3), so the fit may calm them but never delete them.
    "disk.rim.skirt":              (0.3, 1.0, [0.08, 0.2]),
    "disk.rim.fray":               (0.3, 1.0, [0.08, 0.2]),
    "disk.rim.clump":              (0.3, 1.0, [0.08, 0.2]),
    "disk.depth.foreground":       (0.0, 1.0, [0.08, 0.2]),
    "disk.depth.lane":             (0.0, 1.0, [0.08, 0.2]),
    "disk.arcs.gain":              (0.0, 0.02, [0.002, 0.005]),
    "disk.streaks.smear":          (0.0, 1.0, [0.08, 0.2]),
    "disk.roll":                   (-30, 30, [1.0, 3.0]),
    "photon.gain":                 (0.0, 1.5, [0.1, 0.3]),
    "photon.widthPx":              (0.1, 0.75, [0.05, 0.12]),
    "tilt":                        (5, 35, [1.0, 3.0]),
    "diskOuterRs":                 (3.5, 11, [0.3, 0.8]),
    "intensity":                   (0.3, 1.0, [0.05, 0.12]),
    # Gains on the LENSED (order-1) arcs above and below. Since the inner
    # halo now carries the ring hugging the shadow, these are free to come
    # down and thin the disk vertically without emptying that ring.
    "haloUpper":                   (0.1, 1.0, [0.06, 0.15]),
    "haloLower":                   (0.1, 1.0, [0.06, 0.15]),
    "disk.streaks.octaves":        (1, 3, [1]),
    "disk.arcs.count":             (0, 4, [1]),
}
INTEGER = {"disk.streaks.octaves", "disk.arcs.count"}

# Judgement: what "close to the picture" means, in weights.
OBJECTIVE = [
    # (kind, key/index, weight)
    ("prof", 0, 3.0), ("prof", 1, 3.0), ("prof", 2, 2.0), ("prof", 3, 1.5),
    ("prof", 4, 1.0), ("prof", 5, 0.7), ("prof", 6, 0.4),
    ("pole", 0, 1.5), ("pole", 1, 1.5), ("pole", 2, 1.0),
    ("plane", 0, 1.5), ("plane", 1, 1.5), ("plane", 2, 1.2), ("plane", 3, 1.0),
    ("plane", 4, 0.8), ("plane", 5, 0.6),
    ("log", "q50", 1.5), ("log", "q90", 2.0), ("log", "q99", 1.5),
    ("log", "q999", 1.0), ("log", "peak", 1.0), ("log", "footprint", 1.0),
    ("log", "extentMajor", 2.0), ("log", "midHalfHeight", 2.5),
    ("log", "outHalfHeight", 2.5), ("log", "tipHalfHeight", 1.0),
    ("log", "topArcThickness", 1.5), ("log", "topArcOuter", 1.5),
    ("log", "botArcThickness", 2.0), ("log", "botArcOuter", 2.5),
    ("log", "botArcPeak", 1.5),
    # Texture and "drawn ring" terms carry real weight: the owner rejected
    # both hard edges and speckle, and the profile terms otherwise buy light
    # by turning the disk into filaments.
    ("log", "rimRagged", 3.5), ("log", "ringRagged", 2.5),
    ("log", "circleEnergy", 3.0), ("log", "nearFarRatio", 2.0),
    ("log", "cctInner", 1.2), ("log", "cctOuter", 1.2),
    ("log", "whiteFrac", 1.5), ("log", "nearStripPeak", 1.5),
    ("abs", "dopplerRatio", 1.5), ("deg", "posAngle", 1.0),
]


def get(cfg, path, default=None):
    node = cfg
    for k in path.split("."):
        if not isinstance(node, dict) or k not in node:
            return default
        node = node[k]
    return node


def put(cfg, path, v):
    node = cfg
    parts = path.split(".")
    for k in parts[:-1]:
        node = node.setdefault(k, {})
    node[parts[-1]] = v


def score(mr, mo):
    total = 0.0
    for kind, key, w in OBJECTIVE:
        if kind in ("prof", "pole", "plane"):
            a = mr["_" + {"prof": "profile"}.get(kind, kind)][key]
            b = mo["_" + {"prof": "profile"}.get(kind, kind)][key]
            # floor at 1e-4 so a dark band is a bounded, not infinite, penalty
            total += w * abs(math.log(max(b, 1e-4) / max(a, 1e-4)))
        elif kind == "log":
            total += w * abs(math.log(max(mo.get(key, 0.0), 1e-4)
                                      / max(mr.get(key, 0.0), 1e-4)))
        elif kind == "abs":
            total += w * abs(mo.get(key, 0.0) - mr.get(key, 0.0))
        elif kind == "deg":
            total += w * abs(mo.get(key, 0.0) - mr.get(key, 0.0)) / 10.0
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--only", default="")
    ap.add_argument("--skip", default="")
    ap.add_argument("--start", default="{}")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    keys = [k for k in SPACE
            if (not a.only or k in a.only.split(","))
            and k not in a.skip.split(",")]
    _, mr, _, _ = B.reference()
    cfg = json.loads(a.start)
    # seed every free key from the preset's own value so step 0 is the baseline
    for k in keys:
        if get(cfg, k) is None:
            put(cfg, k, float(get(bh_defaults(), k, SPACE[k][0])))
    _, mo = B.evaluate(copy.deepcopy(cfg))
    best = score(mr, mo)
    print("start score %.4f" % best)
    evals = 1
    for rnd in range(a.rounds):
        improved = False
        for k in keys:
            lo, hi, steps = SPACE[k]
            cur = float(get(cfg, k))
            for step in steps:
                for cand in (cur - step, cur + step):
                    cand = max(lo, min(hi, cand))
                    if k in INTEGER:
                        cand = float(round(cand))
                    if abs(cand - cur) < 1e-9:
                        continue
                    trial = copy.deepcopy(cfg)
                    put(trial, k, cand)
                    _, mo = B.evaluate(trial)
                    evals += 1
                    s = score(mr, mo)
                    if s < best - 1e-4:
                        best, cfg, cur, improved = s, trial, cand, True
                        print("  %-28s -> %-10.4g  score %.4f" % (k, cand, best))
        print("round %d: score %.4f after %d evals" % (rnd + 1, best, evals))
        if not improved:
            break
    print(json.dumps(cfg, indent=1, sort_keys=True))
    if a.out:
        json.dump({"score": best, "config": cfg}, open(a.out, "w"), indent=1)


def bh_defaults():
    """The target preset as BlackHole.qml states it, as a nested dict."""
    import bh_probe
    p = copy.deepcopy(bh_probe.PRESETS["target"])
    p.setdefault("disk", {}).setdefault("halo", {"gain": 0.0, "reachRh": 1.43})
    p["disk"].setdefault("roll", 0.0)
    p["disk"].setdefault("doppler", {}).setdefault("strength", 0.22)
    return p


if __name__ == "__main__":
    main()
