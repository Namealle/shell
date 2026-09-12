#!/usr/bin/env python3
"""Deterministic Schwarzschild transfer texture. Only numpy and Pillow required.

1024 columns = four 256-column impact partitions (endpoints duplicated).
Rows 0..255: u(phi), phi = row*2*pi/255, scalar range [0,1].
Rows 256/257: terminal/turning phi in [0,32]. Row 258: capture flag.
Row 259: b/12. Row 260: repeated exact uint16 upload sentinels.
Row 261: (sourceRadius/Rh+64)/128; B=8-bit hemisphere/order transmission.
Every scalar: R=high byte, G=low byte, A=255. Other B=0. No PNG color tags.
Decode: (floor(R*255+.5)*256+floor(G*255+.5))/65535*range.
Nearest texture reads, then interpolate DECODED values, never packed bytes.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

D = 20.0
BC = 3 * np.sqrt(3) / 2
BMAX = 12.0
EPS = 1e-7
PHIMAX = 2 * np.pi
SENTINELS = [0, 1, 255, 256, 32767, 32768, 65280, 65535]
THETA = np.arcsin(BC * np.sqrt(1 - 1 / D) / D)
FOCAL = 1 / np.tan(THETA)


def impacts():
    t = np.linspace(0, 1, 256)
    return np.concatenate((
        .025 + (.95 * BC - .025) * t,
        BC * (1 - EPS - (.05 - EPS) * (1 - t) ** 2),
        BC * (1 + EPS + (.25 - EPS) * t ** 2),
        1.25 * BC + (BMAX - 1.25 * BC) * t,
    ))


def impact_index(b):
    b = np.asarray(b)
    return np.select([b < .95 * BC, b < BC, b < 1.25 * BC], [
        np.clip((b - .025) / (.95 * BC - .025), 0, 1) * 255,
        256 + (1 - np.sqrt(np.clip((1 - EPS - b / BC) / (.05 - EPS), 0, 1))) * 255,
        512 + np.sqrt(np.clip((b / BC - 1 - EPS) / (.25 - EPS), 0, 1)) * 255,
    ], 768 + np.clip((b - 1.25 * BC) / (BMAX - 1.25 * BC), 0, 1) * 255)


def rk4(u, v, h):
    a = 1.5 * u * u - u
    ub, vb = u + h * v / 2, v + h * a / 2
    ab = 1.5 * ub * ub - ub
    uc, vc = u + h * vb / 2, v + h * ab / 2
    ac = 1.5 * uc * uc - uc
    ud, vd = u + h * vc, v + h * ac
    ad = 1.5 * ud * ud - ud
    return u + h * (v + 2 * vb + 2 * vc + vd) / 6, v + h * (a + 2 * ab + 2 * ac + ad) / 6


def integrate(b, substeps=32):
    """Vector RK4; terminal states held fixed, crossings retained before capture."""
    u = np.full(len(b), 1 / D)
    v = np.sqrt(1 / b ** 2 - u * u + u ** 3)
    end, turn = np.zeros_like(u), np.zeros_like(u)
    captured = b < BC
    samples = np.zeros((256, len(b)))
    samples[0] = u
    h = PHIMAX / (255 * substeps)
    for step in range(1, int(np.ceil(32 / h)) + 1):
        active = end == 0
        un, vn = rk4(u, v, h)
        turning = active & (v > 0) & (vn <= 0)
        turn[turning] = (step - 1 + v[turning] / (v[turning] - vn[turning])) * h
        terminal = active & ((un <= 0) | (un >= 1))
        boundary = captured.astype(float)
        end[terminal] = (step - 1 + (boundary[terminal] - u[terminal]) / (un[terminal] - u[terminal])) * h
        u = np.where(active, np.clip(un, 0, 1), u)
        v = np.where(active & ~terminal, vn, 0)
        if step % substeps == 0 and step // substeps < 256:
            samples[step // substeps] = u
        if not np.any(end == 0) and step >= 255 * substeps:
            break
    if np.any(end == 0):
        raise RuntimeError("Ray did not terminate before phi=32")
    return samples, end, turn, captured


def generate(output):
    b = impacts()
    samples, end, turn, capture = integrate(b)
    cosine = -np.cos(end)
    projected = FOCAL * np.sin(end) / np.maximum(cosine, .05)
    def ease(x):
        x = np.clip(x, 0, 1)
        return x**3 * (10 + x * (-15 + 6*x))
    transmission = ease((cosine-.05)/.15) * (1-ease((end-5)/.8)) * ~capture
    values = np.vstack((samples, end / 32, turn / 32, capture, b / BMAX, np.zeros(1024), (projected+64)/128))
    words = np.floor(np.clip(values, 0, 1) * 65535 + .5).astype(np.uint16)
    words[260] = np.resize(SENTINELS, 1024)
    rgba = np.zeros((262, 1024, 4), dtype=np.uint8)
    rgba[:, :, 0] = words // 256
    rgba[:, :, 1] = words % 256
    rgba[:, :, 3] = 255
    rgba[261, :, 2] = np.floor(np.clip(transmission, 0, 1)*255+.5).astype(np.uint8)
    Image.fromarray(rgba).save(output, compress_level=9, optimize=False)
    print(json.dumps({"path": str(output), "size": [1024, 262], "raw_bytes": rgba.nbytes,
                      "png_bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                      "bc": BC, "focal_over_Rh": FOCAL, "sentinel_words": SENTINELS,
                      "sentinel_decode_normalized": [n / 65535 for n in SENTINELS]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "shaders/blackhole-lut.png")
    generate(parser.parse_args().output)
