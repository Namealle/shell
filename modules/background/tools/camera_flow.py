#!/usr/bin/env python3
"""Offscreen proof that the far field turns around with the camera.

Renders `shaders/starfield.frag` itself through bhrender.c (surfaceless EGL +
llvmpipe, no Quickshell and no GPU), two frames a known grid advance apart, and
cross-correlates them in the shader's OWN radial coordinate u = r^2/2. The peak
of that correlation is the field's displacement, in u, with a sign.

The renderer's rule is one line: the per-layer advance carries `sign = 1 - 2 *
cameraOutward`, so the inward stream (radialMode 1) advances forward and the
camera regime (radialMode 2) advances backward. This measures the consequence
on real pixels rather than trusting the arithmetic.

    python3 camera_flow.py [--width 1376] [--height 768] [--du 0.05]
"""
import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bh_probe import preprocess, _build  # noqa: E402

SHADERS = os.path.join(os.path.dirname(HERE), "shaders")
LAYER_CELL = (12.0, 30.0, 110.0)
LAYER_DEPTH = (0.10, 0.42, 1.0)


def grid(width, height, layer, density=1.0):
    """invU, invAngle and the optical padding, exactly as Starfield.publish()."""
    short = min(width, height)
    radius = short / 2.0
    display = max(1.0, (width * height / (1024.0 * 576.0)) ** 0.5)
    scale = display / density ** 0.5
    cell = LAYER_CELL[layer] * scale
    sectors = max(4, round(2 * np.pi * radius / cell))
    inv_angle = sectors / (2 * np.pi)
    inv_u = radius * radius / (cell * cell * inv_angle)
    depth = LAYER_DEPTH[layer]
    optical = (3.5, 6.0, 42.0 * display)[layer] + 2 + short * 0.012 * depth \
        + np.hypot(width, height) * 0.003 * depth
    if layer == 2:
        edge = 1 + optical / radius
        optical += radius * ((edge * edge + 2 * (6.0 / 1080.0) * 32) ** 0.5 - edge)
    return inv_u, inv_angle, optical


def uniforms(width, height, advance, radial_mode):
    u = {
        "qt_Opacity": [1.0],
        "resolution": [width, height],
        "density": [1.0], "brightness": [1.0], "twinkle": [0.0],
        "flareFraction": [0.003], "variableFraction": [0.006], "edgeLift": [0.0],
        "skyColor": [0.0, 0.0, 0.0, 1.0],
        "radialMode": [radial_mode],
        "cameraCentre": [0.5, 0.5], "centreOffset": [0.0, 0.0],
        "flowZoom": [1.0, 1.0, 1.0],
        "phaseTime": [0.0], "activeStamp": [0.0, 0.0], "flowPhaseLocal": [3000.0],
        "paddingAge": [-1.0], "captureHistory": [0.0], "legacyMaterialAlive": [0.0],
        "mood": [0.0, 0.0, 0.0, 0.0],
        "dustCluster": [16.0, 44.0, 0.0, 1.0], "dustParallax": [0.0, 0.0],
        "particlesEnabled": [0.0], "particleReady": [0.0], "particleMu": [0.0],
        "lensFlux": [1.0],
    }
    padding = []
    for layer in range(3):
        inv_u, inv_angle, optical = grid(width, height, layer)
        cells = advance * inv_u / grid(width, height, 0)[0] if layer else advance
        # One shared u offset for all three layers, so a single measured shift
        # describes the whole field: `cells` is that offset in each layer's own
        # cell units.
        cells = advance * inv_u
        u["flowGrid%d" % layer] = [inv_u, inv_angle, cells % 1.0, float(int(np.floor(cells)) % 256)]
        u["flowSeeds%d" % layer] = [13.7, 41.3, 13.7, 41.3]
        padding.append(optical)
    u["legacyPadding"] = padding
    u["birthPadding"] = padding
    return u


def source():
    """The production shader, retargeted to desktop GL 4.5 core.

    One rename: `packed` is a reserved word there, while the Vulkan GLSL 440
    that qsb compiles accepts it. It is a local, so this changes nothing about
    what the shader computes.
    """
    src = preprocess(os.path.join(SHADERS, "starfield.frag"))
    return src.replace("float packed =", "float packedByte =") \
              .replace("floor(packed /", "floor(packedByte /")


def render(width, height, advance, radial_mode, tmp):
    frag = os.path.join(tmp, "starfield.glsl")
    if not os.path.exists(frag):
        open(frag, "w").write(source())
    path = os.path.join(tmp, "u.txt")
    with open(path, "w") as f:
        for k, v in uniforms(width, height, advance, radial_mode).items():
            f.write("%s %s\n" % (k, " ".join(repr(float(x)) for x in v)))
    out = os.path.join(tmp, "out.f32")
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", EGL_PLATFORM="surfaceless",
               GALLIUM_DRIVER="llvmpipe", MESA_LOADER_DRIVER_OVERRIDE="")
    r = subprocess.run([_build(), frag, str(width), str(height), path, out],
                       env=env, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("bhrender failed: %s\n%s" % (r.stderr, r.stdout))
    a = np.fromfile(out, dtype="<f4").reshape(height, width, 4)[:, :, :3]
    return a.sum(axis=2)


def polar(image, bins_u=560, bins_t=900, u_max=1.2):
    h, w = image.shape
    y, x = np.mgrid[0:h, 0:w]
    radius = min(w, h) / 2.0
    dx = (x + 0.5 - w / 2.0) / radius
    dy = (y + 0.5 - h / 2.0) / radius
    u = 0.5 * (dx * dx + dy * dy)
    t = np.arctan2(dy, dx)
    iu = np.floor(u / u_max * bins_u).astype(int)
    it = np.floor((t + np.pi) / (2 * np.pi) * bins_t).astype(int)
    keep = (iu >= 0) & (iu < bins_u) & (it >= 0) & (it < bins_t)
    out = np.zeros((bins_u, bins_t))
    np.add.at(out, (iu[keep], it[keep]), image[keep])
    return out


def shift(a, b, bins_u, u_max, span=40):
    """Best integer u-shift taking a onto b, by cross-correlation."""
    a = a - a.mean(axis=0, keepdims=True)
    b = b - b.mean(axis=0, keepdims=True)
    best, peak = 0, -np.inf
    for k in range(-span, span + 1):
        if k >= 0:
            score = float((a[:bins_u - k] * b[k:]).sum())
        else:
            score = float((a[-k:] * b[:bins_u + k]).sum())
        if score > peak:
            peak, best = score, k
    return best * u_max / bins_u, peak


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--width", type=int, default=1376)
    p.add_argument("--height", type=int, default=768)
    p.add_argument("--du", type=float, default=0.05)
    p.add_argument("--keep", action="store_true")
    p.add_argument("--save", metavar="DIR", help="write the rendered frames as PNGs")
    args = p.parse_args()
    tmp = tempfile.mkdtemp(prefix="camflow-")
    bins_u, u_max = 560, 1.2
    base = 4.0 / grid(args.width, args.height, 0)[0]   # a whole number of cells
    frames = {}
    ok = True
    for name, mode, step in (("hole  (radialMode 1)", 1.0, +args.du),
                             ("camera (radialMode 2)", 2.0, -args.du)):
        a = render(args.width, args.height, base, mode, tmp)
        b = render(args.width, args.height, base + step, mode, tmp)
        frames[name] = (a, b)
        pa, pb = polar(a, bins_u), polar(b, bins_u)
        moved, _ = shift(pa, pb, bins_u, u_max)
        # A grid advance of +du moves every star's u by -du: the rows are being
        # consumed. The camera advances the other way, so its field goes out.
        want = -step
        direction = "outward" if moved > 0 else "inward"
        good = abs(moved - want) < 0.4 * args.du and np.sign(moved) == np.sign(want)
        ok = ok and good
        print("%-22s advance %+0.4f u -> field moved %+0.4f u (%s), expected %+0.4f  %s"
              % (name, step, moved, direction, want, "ok" if good else "FAIL"))
        print("   light %.4f -> %.4f, %d lit pixels"
              % (a.sum(), b.sum(), int((a > 0.004).sum())))
    if args.save:
        from PIL import Image
        os.makedirs(args.save, exist_ok=True)
        for name, (a, b) in frames.items():
            tag = "hole" if name.startswith("hole") else "camera"
            for suffix, frame in (("0", a), ("1", b)):
                px = np.clip(frame / 3.0, 0, 1) ** (1 / 2.2)
                Image.fromarray((px * 255).astype(np.uint8), "L").save(
                    os.path.join(args.save, "v8-camera-fardust-%s-%s.png" % (tag, suffix)))
        print("frames written to", args.save)
    if args.keep:
        for name, (a, b) in frames.items():
            np.save(os.path.join(tmp, name.split()[0] + ".npy"), np.stack([a, b]))
        print("frames in", tmp)
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
