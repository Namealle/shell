#!/usr/bin/env python3
"""Offscreen frames + legibility metrics for the NEBULA PASSAGE.

    python3 modules/background/tools/nebula_sheet.py OUTDIR [--label v9]

Renders the shipped `nebulaField()` - lifted out of shaders/starfield.frag by
name, so this is the kernel the shell draws and not a re-implementation -
through surfaceless EGL + llvmpipe, with blackhole-noise.png on binding 2
exactly as the live ShaderEffect binds it. The uniforms come from the shipped
captureNebula()/nebulaState() in Starfield.qml by way of test-events.mjs, so
the geometry, the envelope and the palette are the scheduler's own.

Reports, per phase and per output: the extent of the cloud in px and as a
percentage of the short side, the linear-light q99/q999/max of its emission
(the sky must stay dark: q99 <= 0.35), how much of the far field its dust
lanes take away, and the overlap between the drawn cloud and everything the
hole draws, which must be zero. Writes one contact sheet and the raw frames.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SHADERS = os.path.join(REPO, "modules", "background", "shaders")
FRAG = os.path.join(SHADERS, "starfield.frag")
sys.path.insert(0, HERE)
import bh_probe  # noqa: E402  (the build/texture helpers, nothing else)


def frag_function(src, name):
    m = re.search(r"^(?:float|vec2|vec3|vec4)\s+%s\s*\(" % name, src, re.M)
    if not m:
        raise SystemExit("no %s() in starfield.frag" % name)
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[m.start():j + 1]
    raise SystemExit("unterminated %s()" % name)


def preview():
    src = open(FRAG).read()
    kernels = "\n\n".join(frag_function(src, n) for n in ("nebulaTap", "nebulaStar", "nebulaField"))
    return """#version 450 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    vec2 resolution;
    vec4 nebulaHead;
    vec4 nebulaShape;
    vec4 nebulaTone0;
    vec4 nebulaTone1;
    vec4 nebulaStars;
    vec4 nebulaStars2;
    vec4 nebulaBounds;
} ubuf;
layout(binding = 2) uniform sampler2D bhNoise;

%s

// rgb = the linear emission main() adds to the far field, a = the opacity it
// multiplies the far field by. Both are reported untouched.
void main() {
    fragColor = nebulaField(qt_TexCoord0 * ubuf.resolution);
}
""" % kernels


def uniforms(width, height, regime, phases):
    """-> [{phase, t, head, shape, tone0, tone1, stars, stars2, bounds}]"""
    script = """
import { makeHost } from "%s/test-events.mjs";
import vm from "vm"; import fs from "fs";
const ctx = vm.createContext({Math,JSON,isFinite,Number,Object,Array,console});
vm.runInContext(fs.readFileSync("%s/services/ambient/rules.js","utf8")+"\\nthis.validateDocument=validateDocument;", ctx);
const cfgPath = process.env.NEBULA_CONFIG;
const doc = ctx.validateDocument(cfgPath ? JSON.parse(fs.readFileSync(cfgPath,"utf8")) : null);
const palette = doc.palette.rgb;
const camera = %d;
const h = makeHost(doc, {width:%d, height:%d, dpr:1, paletteColors: palette,
    hole: camera ? false : true, holeSize: 0.11, cameraBlend: camera, cameraOutward: camera});
h._state.palette = new Array(palette.length).fill(1/palette.length);
const e = h.captureNebula(3, 0);
e.geo = 0; h._state.nebula = e;
const perSec = -h.nebulaDriftPerSec() / h.nebulaFlowRate();
const out = {duration: e.duration, fade: e.fade, semi: e.semi, stars: e.stars.length,
    tone0: e.tone0, tone1: e.tone1, enterU: e.enterU, frames: []};
for (const f of %s) {
    const t = e.duration * f;
    h._state.clock = t; h._state.geo[0] = perSec * t;
    const s = h.nebulaState(e);
    out.frames.push({phase: f, t: t, head: s.head, shape: s.shape, tone0: s.tone0,
        tone1: s.tone1, stars: s.stars, stars2: s.stars2, bounds: s.bounds});
}
console.log(JSON.stringify(out));
""" % (HERE, REPO, 1 if regime == "camera" else 0, width, height, json.dumps(phases))
    with tempfile.NamedTemporaryFile("w", suffix=".mjs", delete=False, dir=HERE) as f:
        f.write(script)
        path = f.name
    try:
        raw = subprocess.run(["node", path], capture_output=True, text=True, check=True).stdout
    finally:
        os.unlink(path)
    return json.loads(raw)


def render(frag_path, width, height, frame, tmp):
    u = os.path.join(tmp, "u.txt")
    with open(u, "w") as f:
        f.write("resolution %d %d\n" % (width, height))
        for key in ("head", "shape", "tone0", "tone1", "stars", "stars2", "bounds"):
            name = "nebula" + key[0].upper() + key[1:]
            f.write("%s %s\n" % (name, " ".join(repr(float(x)) for x in frame[key])))
    for name, png in (("t1.raw", "blackhole-lut.png"), ("t2.raw", "blackhole-noise.png")):
        p = os.path.join(tmp, name)
        if not os.path.exists(p):
            bh_probe._rawtex(os.path.join(SHADERS, png), p)
    out = os.path.join(tmp, "out.f32")
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", EGL_PLATFORM="surfaceless",
               GALLIUM_DRIVER="llvmpipe", MESA_LOADER_DRIVER_OVERRIDE="")
    r = subprocess.run([bh_probe._build(), frag_path, str(width), str(height), u, out,
                        os.path.join(tmp, "t1.raw"), os.path.join(tmp, "t2.raw")],
                       env=env, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("bhrender failed: %s\n%s" % (r.stderr, r.stdout))
    return np.fromfile(out, dtype="<f4").reshape(height, width, 4)


def encode(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def metrics(a, width, height):
    rgb, alpha = a[:, :, :3], a[:, :, 3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    drawn = (lum > 1e-4) | (alpha > 0.01)
    n = int(drawn.sum())
    short = min(width, height)
    if n:
        ys, xs = np.nonzero(drawn)
        extent = (int(xs.max() - xs.min()) + 1, int(ys.max() - ys.min()) + 1)
        body = lum[drawn]
    else:
        extent, body = (0, 0), np.zeros(1, dtype=np.float32)
    peak8 = float(encode(rgb.max(axis=2)).max()) * 255
    return {
        "drawnPx": n,
        "coverage": round(n / float(width * height), 4),
        "extentPx": extent,
        "extentShortPct": [round(100.0 * extent[0] / short, 1), round(100.0 * extent[1] / short, 1)],
        "q99": round(float(np.quantile(body, 0.99)), 4),
        "q999": round(float(np.quantile(body, 0.999)), 4),
        "maxLinear": round(float(lum.max()), 4),
        "peak255": round(peak8, 1),
        "maxOpacity": round(float(alpha.max()), 3),
        "meanOpacity": round(float(alpha[drawn].mean()) if n else 0.0, 3),
    }


def hole_overlap(a, width, height, reach):
    """Drawn cloud pixels inside the hole's drawn material. Informational: the
    disk composites in FRONT of the far field, so these are occluded, and the
    shadow is removed from `far` after the cloud has joined it."""
    y, x = np.mgrid[0:height, 0:width]
    inside = ((x - width / 2.0) ** 2 + (y - height / 2.0) ** 2) < reach * reach
    lum = a[:, :, :3].max(axis=2)
    return int(((lum > 1e-4) | (a[:, :, 3] > 0.01))[inside].sum())


def starfield(width, height, seed=7):
    """A stand-in far field, only so the contact sheet shows the extinction."""
    rng = np.random.default_rng(seed)
    img = np.zeros((height, width), dtype=np.float32)
    n = int(width * height / 2600)
    ys = rng.integers(0, height, n)
    xs = rng.integers(0, width, n)
    img[ys, xs] = rng.uniform(0.15, 1.0, n) ** 2
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--label", default="v9")
    ap.add_argument("--config", default=None)
    ap.add_argument("--phases", default="0.04,0.12,0.30,0.50,0.72,0.92")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    if args.config:
        os.environ["NEBULA_CONFIG"] = args.config
    phases = [float(x) for x in args.phases.split(",")]
    frag_path = os.path.join(args.outdir, "nebula-preview.frag")
    open(frag_path, "w").write(preview())
    outputs = [("tablet", 2880, 1800), ("DP-3", 2160, 3840), ("HDMI-A-1", 3440, 1440)]
    report = {"label": args.label, "outputs": []}
    tiles = []
    with tempfile.TemporaryDirectory(prefix="nebula-") as tmp:
        for name, w, h in outputs:
            for regime in ("hole", "camera"):
                spec = uniforms(w, h, regime, phases)
                rows = []
                for frame in spec["frames"]:
                    a = render(frag_path, w, h, frame, tmp)
                    m = metrics(a, w, h)
                    m["phase"] = frame["phase"]
                    m["t"] = round(frame["t"], 1)
                    m["semiPx"] = round(frame["head"][2], 1)
                    m["gain"] = round(frame["head"][3], 4)
                    if regime == "hole":
                        # 740 px on the tablet, 887 on DP-3: what the hole
                        # actually draws under his `target` preset.
                        reach = 740.0 if name == "tablet" else 887.0
                        m["insideHolePx"] = hole_overlap(a, w, h, reach)
                    rows.append(m)
                    tag = "%s-%s-%02d" % (name, regime, int(frame["phase"] * 100))
                    a.astype("<f4").tofile(os.path.join(args.outdir, "%s-nebula-%s.f32" % (args.label, tag)))
                    sky = starfield(w, h)[:, :, None] * np.float32([0.75, 0.82, 1.0])
                    composed = sky * (1 - a[:, :, 3:4]) + a[:, :, :3]
                    tile = Image.fromarray((encode(composed) * 255).astype(np.uint8))
                    tile.thumbnail((420, 420))
                    tiles.append(("%s %s %d%%" % (name, regime, int(frame["phase"] * 100)), tile))
                report["outputs"].append({
                    "output": name, "width": w, "height": h, "regime": regime,
                    "duration": round(spec["duration"], 1), "fade": round(spec["fade"], 1),
                    "semiPx": round(spec["semi"], 1), "stars": spec["stars"],
                    "tone0": [round(x, 3) for x in spec["tone0"]],
                    "tone1": [round(x, 3) for x in spec["tone1"]],
                    "frames": rows})
    cols = len(phases)
    cw = max(t.width for _, t in tiles)
    ch = max(t.height for _, t in tiles)
    rows_n = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw, rows_n * (ch + 16)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for i, (label, tile) in enumerate(tiles):
        x, y = (i % cols) * cw, (i // cols) * (ch + 16)
        sheet.paste(tile, (x, y + 16))
        draw.text((x + 3, y + 3), label, fill=(150, 190, 210))
    sheet_path = os.path.join(args.outdir, "%s-nebula-sheet.png" % args.label)
    sheet.save(sheet_path)
    json.dump(report, open(os.path.join(args.outdir, "%s-nebula-metrics.json" % args.label), "w"), indent=2)
    for block in report["outputs"]:
        print("\n%s %dx%d %s  duration %.0f s  fade %.0f s  semi %.0f px  stars %d" % (
            block["output"], block["width"], block["height"], block["regime"],
            block["duration"], block["fade"], block["semiPx"], block["stars"]))
        for r in block["frames"]:
            print("  t=%6.1f gain %.3f semi %6.1f  extent %5dx%-5d (%5.1f%% x %5.1f%% short)  "
                  "q99 %.4f q999 %.4f max %.4f peak %5.1f/255  opacity mean %.2f max %.2f%s" % (
                      r["t"], r["gain"], r["semiPx"], r["extentPx"][0], r["extentPx"][1],
                      r["extentShortPct"][0], r["extentShortPct"][1], r["q99"], r["q999"],
                      r["maxLinear"], r["peak255"], r["meanOpacity"], r["maxOpacity"],
                      "  insideHole %d" % r["insideHolePx"] if "insideHolePx" in r else ""))
    print("\nsheet: " + sheet_path)


if __name__ == "__main__":
    main()
