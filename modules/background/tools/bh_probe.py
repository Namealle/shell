#!/usr/bin/env python3
"""Offscreen probe for the black hole: renders blackhole-preview.frag through
bhrender.c (surfaceless EGL + llvmpipe) with the uniforms BlackHole.qml would
produce, and returns a linear-light float32 RGB array.

The preset tables here MIRROR BlackHole.qml. `python3 bh_probe.py --check`
re-derives them straight out of the .qml text and fails if they have drifted,
so the probe can never silently measure a different hole from the live one.

Usage as a library:
    from bh_probe import render
    img = render(width=1376, height=768, preset="target", overrides={...})
"""
import json
import os
import re
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
SHADERS = os.path.join(MOD, "shaders")
BIN = os.path.join(tempfile.gettempdir(), "bhrender-%d" % os.getuid())

# ---------------------------------------------------------------- QML mirror
# Flat defaults, used when the preset does not supply the key.
FLAT_DEFAULTS = dict(size=0.075, tilt=14, intensity=0.85, diskOuterRs=8,
                     diskInnerRs=3, haloUpper=0.55, haloLower=0.35,
                     footprintCap=0.04, diskCap=0.25, photonCap=0.3,
                     lensReach=8, lensStretch=1.5)
INNER_MIN = 3     # matches BlackHole.qml's diskInnerRs clamp

PRESETS = {
    "target": json.loads(r"""
{"size": 0.11, "tilt": 15, "intensity": 1, "haloUpper": 1, "haloLower": 0.9,
 "diskOuterRs": 10.5, "lensReach": 8, "lensStretch": 1.6, "footprintCap": 0.2,
 "diskCap": 1, "photonCap": 1,
 "disk": {"exposure": 1.7, "detail": 0.8, "falloff": 2.4,
   "streaks": {"octaves": 3, "radialScale": 1.4, "innerPeriodSec": 12,
               "warp": 0.25, "grain": 0.08, "smear": 0.85},
   "hue": {"innerTemperature": 7000, "outerTemperature": 1700, "warmth": 0.35,
           "whiteness": 0.85},
   "glow": {"gain": 0.008, "radiusPx": 2.5},
   "rim": {"skirt": 0.8, "fray": 0.7, "clump": 0.65},
   "depth": {"foreground": 0.45, "lane": 0.35},
   "arcs": {"gain": 0.013, "radiusRh": 1.6, "spacingRh": 0.55, "count": 4}},
 "photon": {"mode": "shared-field", "widthPx": 0.5, "gain": 1.35,
            "textureStrength": 0.8}}
"""),
}


def clamp(x, lo, hi):
    return lo if not isinstance(x, (int, float)) else max(lo, min(hi, x))


def value(group, key, fallback, lo, hi):
    if group and isinstance(group.get(key), (int, float)):
        return clamp(group[key], lo, hi)
    return fallback


def layered(base, over):
    if not base:
        return dict(over or {})
    out = dict(base)
    for k, o in (over or {}).items():
        b = out.get(k)
        out[k] = {**b, **o} if isinstance(b, dict) and isinstance(o, dict) else o
    return out


def uniforms(width, height, preset="target", overrides=None, detail_phase=0.0,
             mode=1.0, linear=1.0, order=0.0, enabled=1.0):
    """Reproduce BlackHole.qml's readonly vector4d bindings at steady state
    (_strengths == strengthTargets(), _ambient == .5, _enablePosition == 1)."""
    pre = PRESETS.get(preset, {})
    cfg = layered(pre, overrides or {})          # flat keys: explicit wins
    d = layered(pre.get("disk"), (overrides or {}).get("disk"))
    ph = layered(pre.get("photon"), (overrides or {}).get("photon"))
    g = lambda k: d.get(k) if isinstance(d.get(k), dict) else {}

    def flat(k):
        v = cfg.get(k)
        return v if isinstance(v, (int, float)) else FLAT_DEFAULTS[k]

    warmth, spin, beamStrength, structure = 0.5, 1.0, 0.15, 0.05
    photonWidth, tiltWander = 0.006, 0.0
    rh = max(1.0, clamp(flat("size"), 0.01, 0.2) * min(width, height))
    tilt = clamp(clamp(flat("tilt"), 1, 80), 1, 80) * np.pi / 180.0
    physical = bool(d.get("doppler")) and g("doppler").get("preset") == "physical"

    s = [  # strengthTargets(), in order
        value(d, "detail", 0.75, 0, 0.85),
        value(g("streaks"), "warp", 0.25, 0, 0.25),
        value(g("streaks"), "grain", 0.06, 0, 0.08),
        value(g("knots"), "gain", 0.35, 0, 0.5),
        value(g("embers"), "gain", 0.06, 0, 0.06),
        value(g("doppler"), "strength", 1 if physical else 0.22, 0, 1),
        value(g("hue"), "warmth", 0.5, 0, 1),
        value(g("glow"), "gain", 0.008, 0, 0.008),
        value(ph, "widthPx", 0.45, 0.1, 0.75),
        value(ph, "gain", 1.18, 0, 1.5),
        value(ph, "textureStrength", 0.8, 0, 1),
        value(d, "exposure", 1, 0.5, 2),
        value(g("arcs"), "gain", 0, 0, 0.02),
        value(g("hue"), "whiteness", 0, 0, 1),
        value(g("rim"), "skirt", 0.7, 0, 1),
        value(g("rim"), "fray", 0.6, 0, 1),
        value(g("rim"), "clump", 0.6, 0, 1),
        value(g("streaks"), "smear", 0.6, 0, 1),
        value(g("depth"), "foreground", 0.35, 0, 1),
        value(g("depth"), "lane", 0.3, 0, 1),
    ]
    st = g("streaks")
    if isinstance(st.get("innerCyclesPer4096"), (int, float)):
        cycles = round(clamp(st["innerCyclesPer4096"], 16, 1024))
    else:
        cycles = round(4096.0 / value(st, "innerPeriodSec", 12, 4, 256))
    inner = clamp(flat("diskInnerRs"), INNER_MIN, 7)
    roll = value(d, "roll", 0, -90, 90) * np.pi / 180.0
    ease = lambda x: (lambda y: y * y * y * (10 + y * (-15 + 6 * y)))(clamp(x, 0, 1))

    u = {
        "qt_Matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        "qt_Opacity": [1.0],
        "resolution": [float(width), float(height)],
        "phaseTime": [0.0],
        "fixtureMode": [float(mode)],
        "fixtureLinear": [float(linear)],
        "fixtureOrder": [float(order)],
        "testSource": [0.0, 0.0],
        "bhCentre": [width / 2.0, height / 2.0],
        "bhGeometry": [rh, clamp(flat("lensReach"), 4, 12) * rh,
                       np.sin(tilt), np.cos(tilt)],
        "bhDisk": [inner, max(inner + 0.5, clamp(flat("diskOuterRs"), 3.5, 11)), roll,
                   max(1.0, clamp(photonWidth, 0.001, 0.02) * rh)],
        "bhLook": [clamp(flat("intensity") * s[11], 0, 2), clamp(warmth, 0, 1),
                   clamp(beamStrength, 0, 0.2), clamp(structure, 0, 0.08)],
        "bhHalo": [clamp(flat("haloUpper"), 0, 1), clamp(flat("haloLower"), 0, 1),
                   0.6, ease(enabled)],
        "bhPhase": [0.0, 0.0, 0.0, 0.5],
        "bhCaps": [clamp(flat("diskCap"), 0.1, 1), clamp(flat("photonCap"), 0.1, 1),
                   clamp(flat("footprintCap"), 0.01, 0.5), 0.08],
        "bhDetail": [s[0], round(value(d, "seed", 457, 0, 65535)),
                     -1.0 if value(d, "rotationSign", 1, -1, 1) < 0 else 1.0,
                     round(value(st, "octaves", 2, 1, 3))],
        "bhStreaks": [value(st, "radialScale", 1, 0.5, 2), float(cycles), s[1], s[2]],
        "bhKnots": [value(g("knots"), "density", 0.03, 0, 0.06), s[3], 16.0, 48.0],
        "bhEmbers": [2 * (value(g("embers"), "count", 24, 0, 32) // 2),
                     value(g("embers"), "radiusRs", 0.012, 0.004, 0.025),
                     value(g("embers"), "trailSec", 0.35, 0, 0.6), s[4]],
        "bhDoppler": [1.0 if physical else 0.0, s[5], 0.0, 0.0],
        "bhHue": [np.log(value(g("hue"), "innerTemperature", 6500, 4200, 10000)),
                  np.log(value(g("hue"), "outerTemperature", 1700, 1000, 2800)),
                  s[6], s[13]],
        "bhGlow": [s[7], value(g("glow"), "radiusPx", 1.5, 0.25, 2.5), 0.0, 0.0],
        "bhPhoton": [s[8], s[9], s[10], 0.0 if ph.get("mode") == "off" else 1.0],
        "bhDetailPhase": [float(detail_phase), 1.0 / 30.0, 0.0, 0.0],
        "bhArcs": [s[12], value(g("arcs"), "radiusRh", 1.75, 1.2, 2.6),
                   value(g("arcs"), "spacingRh", 0.6, 0.2, 1),
                   round(value(g("arcs"), "count", 2, 0, 4))],
        "bhRim": [s[14], s[15], s[16], s[17]],
        "bhDepth": [s[18], s[19], value(d, "falloff", 1, 1, 3),
                    clamp(flat("lensStretch"), 1, 3)],
    }
    u["_rh"] = rh
    return u


# ------------------------------------------------------------------ plumbing
def preprocess(path):
    """Resolve the GL_GOOGLE include and retarget to desktop GL 4.5 core."""
    src = open(path).read()
    src = src.replace("#version 440", "#version 450 core")
    src = src.replace("#extension GL_GOOGLE_include_directive : require\n", "")
    def sub(m):
        return open(os.path.join(os.path.dirname(path), m.group(1))).read()
    while '#include "' in src:
        src = re.sub(r'#include "([^"]+)"\n', sub, src, count=1)
    return src


def _rawtex(png, out):
    a = np.asarray(Image.open(png).convert("RGBA"), dtype=np.uint8)
    with open(out, "wb") as f:
        f.write(b"%d %d\n" % (a.shape[1], a.shape[0]))
        f.write(a.tobytes())


def _build():
    src = os.path.join(HERE, "bhrender.c")
    if not os.path.exists(BIN) or os.path.getmtime(BIN) < os.path.getmtime(src):
        subprocess.run(["cc", "-O2", "-o", BIN, src, "-lEGL", "-lGL", "-lm"], check=True)
    return BIN


def render(width=1376, height=768, preset="target", overrides=None,
           frag=None, tmp=None, **kw):
    """-> float32 (H, W, 3) linear-light RGB."""
    frag = frag or os.path.join(SHADERS, "blackhole-preview.frag")
    tmp = tmp or tempfile.mkdtemp(prefix="bhprobe-")
    os.makedirs(tmp, exist_ok=True)
    fp = os.path.join(tmp, "frag.glsl")
    open(fp, "w").write(preprocess(frag))
    u = uniforms(width, height, preset, overrides, **kw)
    rh = u.pop("_rh")
    with open(os.path.join(tmp, "u.txt"), "w") as f:
        for k, v in u.items():
            f.write("%s %s\n" % (k, " ".join(repr(float(x)) for x in v)))
    for name, png in (("t1.raw", "blackhole-lut.png"), ("t2.raw", "blackhole-noise.png")):
        p = os.path.join(tmp, name)
        if not os.path.exists(p):
            _rawtex(os.path.join(SHADERS, png), p)
    out = os.path.join(tmp, "out.f32")
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", EGL_PLATFORM="surfaceless",
               GALLIUM_DRIVER="llvmpipe", MESA_LOADER_DRIVER_OVERRIDE="")
    r = subprocess.run([_build(), fp, str(width), str(height),
                        os.path.join(tmp, "u.txt"), out,
                        os.path.join(tmp, "t1.raw"), os.path.join(tmp, "t2.raw")],
                       env=env, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("bhrender failed: %s\n%s" % (r.stderr, r.stdout))
    a = np.fromfile(out, dtype="<f4").reshape(height, width, 4)[:, :, :3]
    render.last_rh = rh
    return a


# ---------------------------------------------------------------- drift gate
def check_mirror():
    """Fail loudly if BlackHole.qml's target preset or strengthTargets() order
    no longer matches the tables above. Clerical checking, not eyeballing."""
    qml = open(os.path.join(MOD, "BlackHole.qml")).read()
    bad = []
    body = qml[qml.index("target: {"):qml.index("readonly property var _preset")]
    body = re.sub(r"//[^\n]*", "", body)
    for k, v in PRESETS["target"].items():
        if isinstance(v, dict):
            for k2, v2 in v.items():
                if isinstance(v2, dict):
                    for k3, v3 in v2.items():
                        if not re.search(r"\b%s:\s*%s\b" % (k3, re.escape(str(v3))), body):
                            bad.append("disk/photon %s.%s = %s" % (k2, k3, v3))
                elif not re.search(r"\b%s:\s*[\"]?%s\b" % (k2, re.escape(str(v2))), body):
                    bad.append("%s.%s = %s" % (k, k2, v2))
        elif not re.search(r"\b%s:\s*%s\b" % (k, re.escape(str(v))), body):
            bad.append("%s = %s" % (k, v))
    order = re.findall(r'value\(_?\w+(?:\.\w+)?,\s*"(\w+)"', qml[qml.index("function strengthTargets"):])
    mine = ["detail", "warp", "grain", "gain", "gain", "strength", "warmth", "gain",
            "widthPx", "gain", "textureStrength", "exposure", "gain", "whiteness",
            "skirt", "fray", "clump", "smear", "foreground", "lane"]
    if order[:20] != mine:
        bad.append("strengthTargets order drifted: %s" % order[:20])
    if bad:
        print("MIRROR DRIFT:\n  " + "\n  ".join(bad))
        return 1
    print("bh_probe mirrors BlackHole.qml: target preset + strengthTargets order OK")
    return 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(check_mirror())
    img = render()
    print("render ok", img.shape, "max", float(img.max()), "Rh", render.last_rh)
