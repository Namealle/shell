#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 camera;
    vec2 cameraCentre;
    float phaseTime;
    float density;
    float twinkle;
    float flareFraction;
    float brightness;
    vec4 skyColor;
    float edgeLift;
    vec4 meteorHead;
    vec3 meteorShape;
    vec4 companionHead;
    vec3 companionShape;
    vec4 cometHead;
    vec3 cometShape;
    vec4 satelliteHead;
    float radialMode;
    vec2 centreOffset;
    vec3 flowZoom;
    vec3 birthPadding;
    vec4 flowGrid0;
    vec4 flowGrid1;
    vec4 flowGrid2;
    vec4 flowSeeds0;
    vec4 flowSeeds1;
    vec4 flowSeeds2;
    vec4 driftGrid0;
    vec4 driftGrid1;
    vec4 driftGrid2;
    mat4 driftSeeds0;
    mat4 driftSeeds1;
    mat4 driftSeeds2;
    float flowPhaseLocal;
    float variableFraction;
    vec4 mood;
    mat4 birthHistory0;
    mat4 birthHistory1;
    mat4 birthHistory2;
    mat4 birthHistory3;
    mat4 birthHistory4;
    mat4 birthHistory5;
    mat4 birthHistory6;
    mat4 birthHistory7;
    mat4 birthHistory8;
    mat4 birthHistory9;
    mat4 birthHistory10;
    mat4 birthHistory11;
    mat4 birthHistory12;
    mat4 birthHistory13;
    mat4 birthHistory14;
    mat4 birthHistory15;
    mat4 birthHistory16;
    mat4 birthHistory17;
    mat4 birthHistory18;
    mat4 birthHistory19;
    mat4 birthHistory20;
    mat4 birthHistory21;
    mat4 birthHistory22;
    mat4 birthHistory23;
    mat4 birthHistory24;
    mat4 birthHistory25;
    mat4 birthHistory26;
    mat4 birthHistory27;
    mat4 birthHistory28;
    mat4 birthHistory29;
    mat4 birthHistory30;
    mat4 birthHistory31;
    mat4 birthHistory32;
    mat4 birthHistory33;
    mat4 birthHistory34;
    mat4 birthHistory35;
    mat4 birthHistory36;
    mat4 birthHistory37;
    mat4 birthHistory38;
    mat4 birthHistory39;
    mat4 birthHistory40;
    mat4 birthHistory41;
    mat4 birthHistory42;
    mat4 birthHistory43;
    mat4 birthHistory44;
    mat4 birthHistory45;
    mat4 birthHistory46;
    mat4 birthHistory47;
    mat4 birthHistory48;
    mat4 birthHistory49;
    mat4 birthHistory50;
    mat4 birthHistory51;
    mat4 birthHistory52;
    mat4 birthHistory53;
    mat4 birthHistory54;
    mat4 birthHistory55;
    mat4 birthHistory56;
    mat4 birthHistory57;
    mat4 birthHistory58;
    mat4 birthHistory59;
    mat4 birthHistory60;
    mat4 birthHistory61;
    mat4 birthHistory62;
    mat4 birthHistory63;
} ubuf;

// No textures, sine hash or finite star catalogue. Each layer evaluates one cell.
vec4 hash4(vec2 p) {
    vec4 p4 = fract(vec4(p.xy, p.xy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

vec2 rotate(vec2 p, float c, float s) {
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}


// Literal column selection retains GLSL ES 100 / desktop 120 compatibility.
vec4 columnAt(mat4 m, float column) {
    if (column < 0.5) return m[0];
    if (column < 1.5) return m[1];
    if (column < 2.5) return m[2];
    return m[3];
}
// Six balanced decisions select one of 64 matrices. Only fragments inside
// a star's bounded support fetch history; the UBO remains below 5 KiB.
vec4 historyAt(float bucket) {
    float slot = mod(bucket, 256.0);
    float column = mod(slot, 4.0);
    if (slot < 128.0) {
        if (slot < 64.0) {
            if (slot < 32.0) {
                if (slot < 16.0) {
                    if (slot < 8.0) {
                        if (slot < 4.0) {
                            return columnAt(ubuf.birthHistory0, column);
                        } else {
                            return columnAt(ubuf.birthHistory1, column);
                        }
                    } else {
                        if (slot < 12.0) {
                            return columnAt(ubuf.birthHistory2, column);
                        } else {
                            return columnAt(ubuf.birthHistory3, column);
                        }
                    }
                } else {
                    if (slot < 24.0) {
                        if (slot < 20.0) {
                            return columnAt(ubuf.birthHistory4, column);
                        } else {
                            return columnAt(ubuf.birthHistory5, column);
                        }
                    } else {
                        if (slot < 28.0) {
                            return columnAt(ubuf.birthHistory6, column);
                        } else {
                            return columnAt(ubuf.birthHistory7, column);
                        }
                    }
                }
            } else {
                if (slot < 48.0) {
                    if (slot < 40.0) {
                        if (slot < 36.0) {
                            return columnAt(ubuf.birthHistory8, column);
                        } else {
                            return columnAt(ubuf.birthHistory9, column);
                        }
                    } else {
                        if (slot < 44.0) {
                            return columnAt(ubuf.birthHistory10, column);
                        } else {
                            return columnAt(ubuf.birthHistory11, column);
                        }
                    }
                } else {
                    if (slot < 56.0) {
                        if (slot < 52.0) {
                            return columnAt(ubuf.birthHistory12, column);
                        } else {
                            return columnAt(ubuf.birthHistory13, column);
                        }
                    } else {
                        if (slot < 60.0) {
                            return columnAt(ubuf.birthHistory14, column);
                        } else {
                            return columnAt(ubuf.birthHistory15, column);
                        }
                    }
                }
            }
        } else {
            if (slot < 96.0) {
                if (slot < 80.0) {
                    if (slot < 72.0) {
                        if (slot < 68.0) {
                            return columnAt(ubuf.birthHistory16, column);
                        } else {
                            return columnAt(ubuf.birthHistory17, column);
                        }
                    } else {
                        if (slot < 76.0) {
                            return columnAt(ubuf.birthHistory18, column);
                        } else {
                            return columnAt(ubuf.birthHistory19, column);
                        }
                    }
                } else {
                    if (slot < 88.0) {
                        if (slot < 84.0) {
                            return columnAt(ubuf.birthHistory20, column);
                        } else {
                            return columnAt(ubuf.birthHistory21, column);
                        }
                    } else {
                        if (slot < 92.0) {
                            return columnAt(ubuf.birthHistory22, column);
                        } else {
                            return columnAt(ubuf.birthHistory23, column);
                        }
                    }
                }
            } else {
                if (slot < 112.0) {
                    if (slot < 104.0) {
                        if (slot < 100.0) {
                            return columnAt(ubuf.birthHistory24, column);
                        } else {
                            return columnAt(ubuf.birthHistory25, column);
                        }
                    } else {
                        if (slot < 108.0) {
                            return columnAt(ubuf.birthHistory26, column);
                        } else {
                            return columnAt(ubuf.birthHistory27, column);
                        }
                    }
                } else {
                    if (slot < 120.0) {
                        if (slot < 116.0) {
                            return columnAt(ubuf.birthHistory28, column);
                        } else {
                            return columnAt(ubuf.birthHistory29, column);
                        }
                    } else {
                        if (slot < 124.0) {
                            return columnAt(ubuf.birthHistory30, column);
                        } else {
                            return columnAt(ubuf.birthHistory31, column);
                        }
                    }
                }
            }
        }
    } else {
        if (slot < 192.0) {
            if (slot < 160.0) {
                if (slot < 144.0) {
                    if (slot < 136.0) {
                        if (slot < 132.0) {
                            return columnAt(ubuf.birthHistory32, column);
                        } else {
                            return columnAt(ubuf.birthHistory33, column);
                        }
                    } else {
                        if (slot < 140.0) {
                            return columnAt(ubuf.birthHistory34, column);
                        } else {
                            return columnAt(ubuf.birthHistory35, column);
                        }
                    }
                } else {
                    if (slot < 152.0) {
                        if (slot < 148.0) {
                            return columnAt(ubuf.birthHistory36, column);
                        } else {
                            return columnAt(ubuf.birthHistory37, column);
                        }
                    } else {
                        if (slot < 156.0) {
                            return columnAt(ubuf.birthHistory38, column);
                        } else {
                            return columnAt(ubuf.birthHistory39, column);
                        }
                    }
                }
            } else {
                if (slot < 176.0) {
                    if (slot < 168.0) {
                        if (slot < 164.0) {
                            return columnAt(ubuf.birthHistory40, column);
                        } else {
                            return columnAt(ubuf.birthHistory41, column);
                        }
                    } else {
                        if (slot < 172.0) {
                            return columnAt(ubuf.birthHistory42, column);
                        } else {
                            return columnAt(ubuf.birthHistory43, column);
                        }
                    }
                } else {
                    if (slot < 184.0) {
                        if (slot < 180.0) {
                            return columnAt(ubuf.birthHistory44, column);
                        } else {
                            return columnAt(ubuf.birthHistory45, column);
                        }
                    } else {
                        if (slot < 188.0) {
                            return columnAt(ubuf.birthHistory46, column);
                        } else {
                            return columnAt(ubuf.birthHistory47, column);
                        }
                    }
                }
            }
        } else {
            if (slot < 224.0) {
                if (slot < 208.0) {
                    if (slot < 200.0) {
                        if (slot < 196.0) {
                            return columnAt(ubuf.birthHistory48, column);
                        } else {
                            return columnAt(ubuf.birthHistory49, column);
                        }
                    } else {
                        if (slot < 204.0) {
                            return columnAt(ubuf.birthHistory50, column);
                        } else {
                            return columnAt(ubuf.birthHistory51, column);
                        }
                    }
                } else {
                    if (slot < 216.0) {
                        if (slot < 212.0) {
                            return columnAt(ubuf.birthHistory52, column);
                        } else {
                            return columnAt(ubuf.birthHistory53, column);
                        }
                    } else {
                        if (slot < 220.0) {
                            return columnAt(ubuf.birthHistory54, column);
                        } else {
                            return columnAt(ubuf.birthHistory55, column);
                        }
                    }
                }
            } else {
                if (slot < 240.0) {
                    if (slot < 232.0) {
                        if (slot < 228.0) {
                            return columnAt(ubuf.birthHistory56, column);
                        } else {
                            return columnAt(ubuf.birthHistory57, column);
                        }
                    } else {
                        if (slot < 236.0) {
                            return columnAt(ubuf.birthHistory58, column);
                        } else {
                            return columnAt(ubuf.birthHistory59, column);
                        }
                    }
                } else {
                    if (slot < 248.0) {
                        if (slot < 244.0) {
                            return columnAt(ubuf.birthHistory60, column);
                        } else {
                            return columnAt(ubuf.birthHistory61, column);
                        }
                    } else {
                        if (slot < 252.0) {
                            return columnAt(ubuf.birthHistory62, column);
                        } else {
                            return columnAt(ubuf.birthHistory63, column);
                        }
                    }
                }
            }
        }
    }
}

vec3 stars(vec2 pixel, float baseAngle, float scale, float layer) {
    float nearLayer = step(1.5, layer);
    float middleLayer = step(0.5, layer);
    float displayScale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
    float optics = mix(1.0, displayScale, nearLayer);
    float cellSize = mix(mix(12.0, 30.0, middleLayer), 110.0, nearLayer) * scale;
    float depth = mix(mix(0.10, 0.42, middleLayer), 1.0, nearLayer);
    float requestedSupport = mix(mix(3.5, 6.0, middleLayer), 42.0 * optics, nearLayer);
    vec4 h;
    vec2 p;
    float support;
    float life = 1.0;
    float age = 0.0;
    if (ubuf.radialMode > 0.5) {
        vec4 grid = layer < 0.5 ? ubuf.flowGrid0 : layer < 1.5 ? ubuf.flowGrid1 : ubuf.flowGrid2;
        vec4 seeds = layer < 0.5 ? ubuf.flowSeeds0 : layer < 1.5 ? ubuf.flowSeeds1 : ubuf.flowSeeds2;
        float zoom = layer < 0.5 ? ubuf.flowZoom.x : layer < 1.5 ? ubuf.flowZoom.y : ubuf.flowZoom.z;
        float shortSide = min(ubuf.resolution.x, ubuf.resolution.y);
        float radius = shortSide * 0.5;
        vec2 centre = ubuf.resolution * 0.5 + ubuf.centreOffset * depth;
        vec2 q = (pixel - centre) / (radius * zoom);
        float u = dot(q, q) * 0.5;
        float padding = layer < 0.5 ? ubuf.birthPadding.x : layer < 1.5 ? ubuf.birthPadding.y : ubuf.birthPadding.z;
        float fadeInner = mix(mix(0.008, 0.025, middleLayer), 0.070, nearLayer);
        // The far layer reaches its central fade even from rectangular corners.
        // Keep the original middle/near lifetime and their population unchanged.
        float minimumEdgeR = 1.0 + padding / radius;
        float minimumStarR = max(2.0 * fadeInner, sqrt(max(0.0, minimumEdgeR * minimumEdgeR - mix(15120.0, 1200.0, middleLayer) * (6.0 / 1080.0) * depth)));
        float minimumPixelR = max(0.0, minimumStarR - requestedSupport / (radius * zoom));
        if (u < minimumPixelR * minimumPixelR * 0.5 || u < 1e-12) return vec3(0.0);
        // One shared atan per pixel, with a small centre-offset correction.
        // The central fades bound |t| < .3 at the allowed wander amplitude.
        // Alternating atan series through t^9 errs by < 0.001 physical px.
        vec2 base = pixel - ubuf.resolution * 0.5;
        vec2 relative = pixel - centre;
        float t = (base.x * relative.y - base.y * relative.x) / max(dot(base, relative), 0.0001);
        float t2 = t * t;
        float angle = baseAngle + t * (1.0 + t2 * (-1.0 / 3.0 + t2 * (1.0 / 5.0 + t2 * (-1.0 / 7.0 + t2 / 9.0))));
        if (abs(t) > 0.25 || dot(base, relative) <= 0.0)
            angle = atan(relative.y, relative.x);
        // Integer sector count makes both sides of atan's branch cut identical.
        float sectors = floor(grid.y * 6.28318530718 + 0.5);
        float angleOffset = 0.37 + layer * 1.23;
        float angularCell = mod((angle - angleOffset) * grid.y, sectors);
        float sector = floor(angularCell);
        float radialCell = u * grid.x + grid.z;
        float row = floor(radialCell);
        float rowId = row + grid.w;
        vec2 salt = rowId < 256.0 ? seeds.xy : seeds.zw;
        h = hash4(vec2(sector, mod(rowId, 256.0)) + salt + layer * vec2(173.17, 319.43));
        if (h.w > mix(0.90, 0.68, nearLayer)) return vec3(0.0);
        // Non-flare foreground halos are below one output code well before
        // 18*optics. Reject their empty surroundings before the expensive work;
        // the maximum birth flare multiplier (1.3) makes this test immutable.
        if (nearLayer > 0.5 && fract(h.x * 71.31 + h.z * 23.17) >= ubuf.flareFraction * 65.0 * 1.3)
            requestedSupport = min(requestedSupport, 18.0 * optics);
        vec2 jitter = 0.18 + 0.64 * h.xy;
        float starU = (row + jitter.y - grid.z) / grid.x;
        if (starU <= 0.0) return vec3(0.0);
        float r = sqrt(2.0 * starU);
        float pixelR = sqrt(2.0 * u);
        if (abs(pixelR - r) * radius * zoom > requestedSupport) return vec3(0.0);
        float deltaAngle = (angularCell - sector - jitter.x) / grid.y;
        float a2 = deltaAngle * deltaAngle;
        // sin lower bound gives a conservative, cheap angular rejection.
        if (abs(deltaAngle) * (1.0 - a2 / 6.0) * pixelR * radius * zoom > requestedSupport) return vec3(0.0);
        float sinA = deltaAngle * (1.0 + a2 * (-1.0 / 6.0 + a2 * (1.0 / 120.0 + a2 * (-1.0 / 5040.0 + a2 / 362880.0))));
        float cosA = 1.0 + a2 * (-1.0 / 2.0 + a2 * (1.0 / 24.0 + a2 * (-1.0 / 720.0 + a2 / 40320.0)));
        vec2 direction = rotate(q / pixelR, cosA, -sinA);
        vec2 starPosition = centre + radius * zoom * r * direction;
        p = pixel - starPosition; // physical pixels: round cores, screen-aligned crosses
        if (dot(p,p) >= requestedSupport * requestedSupport) return vec3(0.0);
        float innerR = sqrt(max(0.0, 2.0 * (row - grid.z) / grid.x));
        float outerR = sqrt(max(0.0, 2.0 * (row + 1.0 - grid.z) / grid.x));
        float angularMargin = r * sin(min(jitter.x, 1.0 - jitter.x) / grid.y);
        float radialMargin = min(r - innerR, outerR - r);
        // Dust needs only a subpixel guard. A full pixel erased cores in
        // the narrow inner sectors. Both guards remain strictly inside the
        // cell; the support taper reaches zero before its boundary.
        support = min(requestedSupport, mix(0.98, 0.9, middleLayer) * max(0.0, radius * zoom * min(angularMargin, radialMargin) - mix(0.125, 1.0, middleLayer)));
        if (support <= 0.0 || dot(p,p) >= support * support) return vec3(0.0);
        // Entry is measured against an immutable expanded rectangle, including
        // maximum camera excursion and optical support. Thus the palette was
        // sealed before even an off-screen star's halo could become visible.
        vec2 boundary = (ubuf.resolution * 0.5 + padding) / max(abs(direction), vec2(0.00001));
        float edgeR = min(boundary.x, boundary.y) / radius;
        age = (0.5 * edgeR * edgeR - starU) / ((6.0 / 1080.0) * depth);
        float fadeOuter = mix(mix(0.020, 0.060, middleLayer), 0.140, nearLayer);
        life = smoothstep(fadeInner, fadeOuter, r * 0.5);
        // The extended 7680 s ring covers the far layer's full journey on
        // portrait, ultrawide and tablet buffers. This last-resort lifetime
        // also prevents overwritten-history reads on extreme aspect ratios.
        // Two 30 s endpoints and a further 60 s margin remain at maximum age.
        float lifetime = mix(7440.0, 480.0, middleLayer) + 120.0 * fract(h.x * 13.71 + h.z * 19.13);
        life *= smoothstep(0.0, 4.0, age) * (1.0 - smoothstep(lifetime - 90.0, lifetime, age));
        if (life <= 0.0) return vec3(0.0);
    } else {
        float angle = 0.37 + layer * 1.23;
        float c = cos(angle), s = sin(angle);
        vec2 centre = ubuf.cameraCentre * ubuf.resolution;
        float zoom = exp(ubuf.camera.z * depth);
        float turn = ubuf.camera.w * depth;
        float cameraC = cos(turn), cameraS = sin(turn);
        vec2 samplePoint = rotate(pixel - centre, cameraC, -cameraS) / zoom + centre;
        vec4 grid = layer < 0.5 ? ubuf.driftGrid0 : layer < 1.5 ? ubuf.driftGrid1 : ubuf.driftGrid2;
        mat4 seeds = layer < 0.5 ? ubuf.driftSeeds0 : layer < 1.5 ? ubuf.driftSeeds1 : ubuf.driftSeeds2;
        vec2 world = rotate(samplePoint - ubuf.resolution * 0.5, c, s) / cellSize + grid.xy;
        vec2 cell = floor(world);
        vec2 id = cell + grid.zw;
        vec2 block = floor(id / 256.0);
        vec2 salt = columnAt(seeds, block.x + 2.0 * block.y).xy;
        h = hash4(mod(id, 256.0) + salt + layer * vec2(173.17, 319.43));
        if (h.w > mix(0.76, 0.68, nearLayer)) return vec3(0.0);
        support = min(requestedSupport, max(0.0, cellSize * 0.5 - 1.0));
        vec2 position = support + 1.0 + h.xy * max(vec2(0.0), vec2(cellSize - 2.0 * (support + 1.0)));
        vec2 delta = (fract(world) * cellSize - position) * zoom;
        support *= zoom;
        if (support <= 0.0 || dot(delta,delta) >= support * support) return vec3(0.0);
        p = rotate(rotate(delta, c, -s), cameraC, cameraS);
    }
    float r2 = dot(p, p);
    vec4 birth = vec4(0.0, 0.0, 0.0, 0.5);
    if (ubuf.radialMode > 0.5) {
        float birthBucket = (ubuf.flowPhaseLocal - age) / 30.0;
        float n = floor(birthBucket);
        birth = mix(historyAt(n - 1.0), historyAt(n), fract(birthBucket));
    }
    float calm = birth.w;
    float acceptance = middleLayer > 0.5 ? mix(0.76, 0.68, nearLayer) : mix(0.90, 0.62, calm);
    float moodTarget = acceptance;
    if (ubuf.mood.x < 0.5) moodTarget -= mix(0.08, 0.06, middleLayer) * (1.0 - nearLayer);
    else if (ubuf.mood.x < 1.5) moodTarget += mix(0.14, 0.02, middleLayer) * (1.0 - nearLayer);
    // Two stable masks: reserve stars fade over 60 seconds, never grid reseeding
    // or an animated threshold. Reactive acceptance itself is birth-frozen.
    float population = mix(1.0 - step(acceptance, h.w), 1.0 - step(moodTarget, h.w), ubuf.mood.y);
    if (population <= 0.0) return vec3(0.0);
    life *= population;
    float variation = fract(h.z * 37.19);
    float phase = h.z * 6.28318530718;
    float tauTime = ubuf.phaseTime * (6.28318530718 / 4096.0);
    float cycles = floor(mix(370.0, 990.0, variation));
    float flareDraw = fract(h.x * 71.31 + h.z * 23.17);
    float flare = nearLayer * (1.0 - step(ubuf.flareFraction * 65.0 * mix(1.3, 0.7, calm), flareDraw));
    float variableDraw = fract(h.y * 47.23 + h.z * 11.73);
    float variable = middleLayer * (1.0 - flare) * (1.0 - step(ubuf.variableFraction, variableDraw));
    float slowCycles = variable > 0.5 ? floor(mix(18.0, 46.0, variation)) : floor(mix(31.0, 83.0, h.z));
    float slow = sin(tauTime * slowCycles + phase * 2.3);
    float pulse = sin(tauTime * cycles + phase + 0.55 * slow);
    float shimmer = 1.0 + ubuf.twinkle * (0.60 * pulse + 0.28 * sin(tauTime * floor(mix(193.0, 431.0, h.w)) + phase * 1.7));
    // Unsynchronised 0.5–1.5 s glints, with variable strength, on a minority.
    if (variation > 0.78) {
        float glint = pow(max(0.0, sin(tauTime * floor(mix(63.0, 181.0, h.z)) + phase * 3.7)), 48.0);
        shimmer += ubuf.twinkle * glint * (0.8 + 0.6 * slow) * (1.0 + 0.35 * ubuf.mood.y * step(1.5, ubuf.mood.x) * (1.0 - step(2.5, ubuf.mood.x)));
    }
    shimmer *= 1.0 + variable * 0.15 * slow;
    float visibility = life;
    if (ubuf.mood.x > 0.5 && ubuf.mood.x < 1.5 && middleLayer == 0.0)
        visibility *= mix(1.0, 0.85, ubuf.mood.y);

    // Dust never scales with the screen: its faintest peaks remain perceptible.
    float sigma = mix(0.44, 0.56, h.z) + middleLayer * 0.12;
    sigma = mix(sigma, mix(1.0, 1.4, h.z) * optics, nearLayer);
    sigma *= mix(0.92, 1.08, calm);
    sigma = min(2.5, sigma);
    float energy = mix(0.32, 1.28, h.z * h.z);
    energy *= mix(1.0, 1.35, middleLayer);
    energy = mix(energy, mix(1.8, 2.8, h.z), nearLayer);
    // Pixel footprint convolved with the point spread: stable subpixel movement.
    float variance = sigma * sigma + 0.0833333;
    float core = exp2(-0.7213475 * r2 / variance) * sigma * sigma / variance;
    float halo = middleLayer * 0.024 * exp2(-r2 / (mix(3.5, 14.0, nearLayer) * optics * optics));
    float light = (core + halo) * energy * shimmer;

    if (nearLayer > 0.0 && flare == 0.0) {
        // A capped hot point plus redistributed light in a broad Gaussian halo.
        // The shoulder approaches white smoothly instead of clipping a wide core
        // into a flat disc. Sigma and convolution are in physical pixels.
        float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z) * mix(0.92, 1.08, calm));
        float hotVariance = hotSigma * hotSigma + 0.0833333;
        float hot = exp2(-0.7213475 * r2 / hotVariance) * hotSigma * hotSigma / hotVariance;
        float soft = exp2(-r2 / (26.0 * optics * optics));
        light = 1.0 - exp(-(3.2 * hot + 0.085 * soft) * shimmer);
    }
    if (flare > 0.0) {
        float breath = 1.0 + ubuf.twinkle * 0.45 * pulse;
        vec2 a = abs(p) / optics;
        float length = mix(28.0, 35.0, h.z) * breath;
        vec2 taper = max(vec2(0.0), 1.0 - a / length);
        taper *= taper;
        vec2 thin = exp2(-a * a / 0.38);
        vec2 skirt = exp2(-a * a / 2.0);
        float cross = dot(thin, taper.yx) * 0.48 + dot(skirt, taper.yx) * 0.10;
        float glowR2 = r2 / (optics * optics);
        float glow = 0.10 * exp2(-glowR2 / 12.0) + 0.030 * exp2(-glowR2 / 125.0);
        light += (cross + glow) * breath;
    }

    // Compact support reaches zero smoothly before a cell boundary can clip it.
    light *= 1.0 - smoothstep(support * support * 0.64, support * support, r2);
    vec3 tint = mix(vec3(0.73, 0.84, 1.0), vec3(1.0, 0.98, 0.94), h.z);
    vec3 probability = max(vec3(0.0), birth.xyz);
    probability *= min(1.0, 0.45 / max(0.00001, probability.x + probability.y + probability.z));
    float tintDraw = fract(h.x * 31.17 + h.y * 17.13 + h.z * 7.97);
    vec3 target = tint;
    if (tintDraw < probability.x) target = vec3(0.65, 1.0, 0.78);
    else if (tintDraw < probability.x + probability.y) target = vec3(0.86, 0.80, 1.0);
    else if (tintDraw < probability.x + probability.y + probability.z) target = vec3(1.0, 0.83, 0.67);
    tint = mix(tint, target, 0.45);
    // Foreground light stays near-white; whitening is an immutable layer trait,
    // independent of twinkle/intensity, so normalized colour cannot cycle live.
    tint = mix(tint, vec3(1.0), nearLayer * 0.65);
    return light * tint * visibility;
}

// CPU-computed deterministic event geometry; uniform branches skip idle events.
// Every distance and the anti-alias footprint are in physical pixels.
vec3 streak(vec2 pixel, vec4 head, vec3 shape, bool slowComet) {
    if (head.w <= 0.0)
        return vec3(0.0);
    vec2 p = pixel - head.xy;
    float along = -dot(p, shape.xy);
    float across = dot(p, vec2(-shape.y, shape.x));
    float extent = shape.z * (slowComet ? 14.0 : 6.0);
    if (along < -extent || along > head.z + extent || abs(across) > extent)
        return vec3(0.0);
    float u = clamp(along / max(head.z, 1.0), 0.0, 1.0);
    float width = shape.z * (slowComet ? 1.8 + 8.0 * u : 1.0 - 0.65 * u);
    float variance = width * width + 0.0833333;
    float tail = exp2(-0.7213475 * across * across / variance) * width / sqrt(variance);
    tail *= smoothstep(-shape.z, shape.z, along) * pow(1.0 - u, slowComet ? 1.6 : 2.0);
    float coreVariance = shape.z * shape.z + 0.0833333;
    float r2 = dot(p, p);
    float hot = exp2(-0.7213475 * r2 / coreVariance) * shape.z * shape.z / coreVariance;
    float glow = exp2(-r2 / (shape.z * shape.z * (slowComet ? 32.0 : 6.0)));
    vec3 nucleus = (1.35 * hot + (slowComet ? 0.22 : 0.12) * glow) * vec3(0.94, 0.97, 1.0);
    vec3 tailTint = slowComet ? vec3(0.68, 0.80, 1.0) : vec3(0.81, 0.89, 1.0);
    return head.w * (nucleus + tail * tailTint * (slowComet ? 0.23 : 0.62));
}

vec3 satellite(vec2 pixel) {
    if (ubuf.satelliteHead.w <= 0.0)
        return vec3(0.0);
    vec2 p = pixel - ubuf.satelliteHead.xy;
    float r2 = dot(p, p);
    if (r2 > 16.0)
        return vec3(0.0);
    float sigma2 = ubuf.satelliteHead.z * ubuf.satelliteHead.z;
    float light = exp2(-0.7213475 * r2 / (sigma2 + 0.0833333)) * sigma2 / (sigma2 + 0.0833333);
    return light * ubuf.satelliteHead.w * vec3(1.0, 0.95, 0.86);
}

void main() {
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    vec3 colour = ubuf.skyColor.rgb;
    vec2 edgePosition = qt_TexCoord0 * 2.0 - 1.0;
    float edge = pow(clamp(dot(edgePosition, edgePosition) * 0.6, 0.0, 1.0), 1.5);
    colour += ubuf.edgeLift * edge * vec3(0.10, 0.19, 0.30);
    if (ubuf.density > 0.0) {
        // Keep the composition's star count similar across aspect ratios, while
        // all distances are evaluated in physical pixels, independent of QML DPR.
        float scale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
        scale /= sqrt(max(0.0001, ubuf.density));
        vec2 relative = pixel - ubuf.resolution * 0.5;
        float baseAngle = ubuf.radialMode > 0.5 ? atan(relative.y, relative.x) : 0.0;
        vec3 field = stars(pixel, baseAngle, scale, 0.0);
        field += stars(pixel, baseAngle, scale, 1.0);
        field += stars(pixel, baseAngle, scale, 2.0);
        colour += field * ubuf.brightness;
    }
    colour += streak(pixel, ubuf.meteorHead, ubuf.meteorShape, false);
    colour += streak(pixel, ubuf.companionHead, ubuf.companionShape, false);
    colour += streak(pixel, ubuf.cometHead, ubuf.cometShape, true);
    colour += satellite(pixel);
    // Stationary sub-code-value dither; no animated noise in the black sky.
    float dither = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715)))) - 0.5;
    // Never lift empty black pixels with dither: the default sky is exactly zero.
    float lit = step(1.0 / 255.0, max(colour.r, max(colour.g, colour.b)));
    colour += lit * dither / 255.0;
    fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
