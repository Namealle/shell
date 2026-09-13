# Starfield v4 black hole / shared disk field

Schwarzschild rs=1, observer D=20, bc=3sqrt(3)/2; Rh=size*shortSide,
focal=7.83442197238 Rh. Two positive plane crossings retain v3 geometry.
Camera is Y-up; public coordinates are physical Qt Y-down pixels.
Emission ends at re=ri+.66*(ro-ri), with the existing .9 rs outer taper.
P=(ri/r)^3*(1-sqrt(ri/r))/.0566527795; peak radius=49ri/36.

## JSON schema for the service delta
Flat defaults: enabled=false, size=.075, tilt=14, intensity=.85, warmth=.5,
spin=1, diskInnerRs=3, diskOuterRs=8, haloUpper=.55, haloLower=.35,
tiltWander=0, transitionSec=30, footprintCap=.03, preset="". Legacy
warmth/beamStrength/photonWidth/structure remain API-compatible; v4 appearance
uses the nested controls below instead.
Pass blackHole.disk/photon to BlackHole.disk/photon; all keys are optional.
tilt accepts 1–80 deg but only 1–35 is silhouette-verified against CPU geodesics.

| Key relative to blackHole | Default | Bounds / taste cap |
|---|---:|---|
| preset | "" | "" or "target"; supplies FALLBACKS only, any explicit key wins |
| footprintCap | .03 | .01–.12 declared luminous-footprint budget; validation checks it, GLSL does not clamp it |
| diskCap / photonCap | .25 / .30 | .10–1.0 linear; the limiters the shader ENFORCES. The film shoulder follows diskCap (knee .72*cap, span .24*cap), so a raised cap is actually reached. Discrete config: a change does not slew |
| disk.exposure | 1 | .5–2; multiplies intensity into bhLook.x, whose ceiling widens 1 -> 2 |
| disk.hue.whiteness | 0 | 0–1 highlight desaturation toward white, weighted by light/cap; luminance-preserving |
| disk.arcs.gain | 0 | 0–.02 linear; 0 (default) disables the outer bands entirely |
| disk.arcs.radiusRh / spacingRh / count | 1.7 / .6 / 2 | 1.2–2.6 Rh / .2–1 Rh / rounded integer 0–2 |
| disk.detail | .75 | 0–.85 |
| disk.seed / disk.rotationSign | 457 / 1 | integer 0–65535 / -1 or +1 (zero becomes +1) |
| disk.streaks.octaves / disk.streaks.radialScale | 2 / 1 | integer 1–3 / .5–2 |
| disk.streaks.innerCyclesPer4096 | 32 | rounded integer 16–128 |
| disk.streaks.warp / disk.streaks.grain | .25 / .06 | 0–.25 cells / 0–.08 |
| disk.knots.density / disk.knots.gain | .03 / .35 | 0–.06 / 0–.5; energy <=20% |
| disk.embers.count | 24 | even 0–min(32,2*(cycles-1)); odd rounds down |
| disk.embers.radiusRs / disk.embers.trailSec / disk.embers.gain | .012 / .35 / .06 | .004–.025 / 0–.6 / 0–.06 |
| disk.doppler.preset / disk.doppler.strength | film / .22 | film or physical; 0–1 (physical default 1) |
| disk.hue.innerTemperature / disk.hue.outerTemperature | 6500 / 1700 | 4200–10000 / 1000–2800 K |
| disk.hue.warmth | .5 | 0–1 |
| disk.glow.gain / disk.glow.radiusPx | .008 / 1.5 | 0–.008 / .25–2.5 physical px |
| photon.mode | shared-field | shared-field or off; unknown resolves shared-field |
| photon.widthPx / photon.gain / photon.textureStrength | .45 / 1.18 / .8 | .1–.75 / 0–1.5 / 0–1 |

## Target preset (owner's owner-target-wallpaper.png, 2026-09-12)
`"blackHole": { "preset": "target" }` is exactly equivalent to this literal JSON,
which the service may send instead if it prefers not to know preset names:

```json
{"blackHole": {"size": 0.11, "tilt": 28, "intensity": 1, "haloUpper": 1,
 "haloLower": 0.9, "footprintCap": 0.11, "diskCap": 0.6, "photonCap": 0.7,
 "disk": {"exposure": 2, "detail": 0.8,
   "streaks": {"octaves": 3, "radialScale": 1.4, "innerCyclesPer4096": 32, "warp": 0.25, "grain": 0.08},
   "hue": {"innerTemperature": 7000, "outerTemperature": 1700, "warmth": 0.35, "whiteness": 0.85},
   "glow": {"gain": 0.008, "radiusPx": 2.5},
   "arcs": {"gain": 0.013, "radiusRh": 1.7, "spacingRh": 0.6, "count": 2}},
 "photon": {"mode": "shared-field", "widthPx": 0.6, "gain": 1.35, "textureStrength": 0.8}}}
```

A preset only provides binding fallbacks: assigning size/tilt/disk/photon from
JSON replaces that binding and the preset stops affecting it. An explicit
`disk` object REPLACES the preset's object; the two are never merged.
Measured 2880x1800: peak .5302 linear (sRGB 193/255), disk mean .1037, q99 .4929,
footprint 9.82% (3440x1440: peak .5285, mean .1038, footprint 6.58%);
default preset renders bit-identically to the pre-Phase-2 shader.

Outer arcs are an ART-DIRECTED approximation. A true order>=2 image lands at
b_c*(1+3.4823*exp(-2pi)), i.e. .65% outside Rh, INSIDE the photon thread, so
these wider bands stand in for that unresolved light plus outer halo material.
They sample the shared field at mid-disk source radius and the order-0 crossing
azimuth, so they shear on the same clock; they add light without coverage, are
attenuated by the disk in front, and never reach the thread's radius.

## Field, colour and clocks
blackhole_noise.py: untagged 128x128 RGBA8, duplicated edges, RGB periods 32/64/127.
A=255 avoids Qt premultiplication corruption. Deviation: optional third period is
127; 128 unique cells plus duplicate need 129. Radial lattice period is 127.
Rows rotate at round(innerCycles*(ri/rRow)^1.5); quintic interpolation joins rows.
Two octaves .67/.33, <=.25-cell warp; optional third is <=.08 zero-mean grain.
Ridge=.12+2.6*smoothstep(.38,.76,N)^2; offline means .960401143495 (one),
.804861351448 (two). mix(1,ridge/mean,detail) has calibrated mean 1.
Source derivatives of r/cos(phi)/sin(phi), plus 1/30-s exposure motion, fade
unresolved detail toward its mean; lower secondary image uses the coarse octave.
16x48 cells give 26 knots at seed 457, compact .2-radial/.3-trailing cell supports.
24 embers use 12 integer orbits, two heads each; shared IDs/rotation in every image.
Dedicated phase integrates dt/4096 modulo 1, independent of spin/ambient.
running freezes integration; resume discards paused time. Strengths slew with tau=30 s.
Enable envelope is quintic over 30 active seconds; discrete changes retain the clock.
Linear sRGB anchors #FFF4E4/#FFD18B/#EC9B4B/#74382B interpolate against log T.
whiteness mixes that tint toward pure white by quintic(light/diskCap) AFTER the
shoulder; both ends carry luminance 1, so emitted energy and every cap are
untouched and whiteness=0 reproduces the four anchors exactly.
Ray g=sqrt((1-1.5/r)/.95)/(1-Omega*lambda), Omega=sign/sqrt(2r^3), lambda=-b*cosTilt*localX.
Film g^.22: brightness .65–1.5, temperature .90–1.12; physical removes those clamps.
Film highlight shoulder tends to .24 before opacity; output caps always apply.
Glow: compact polynomial at thermal edges, <=.008*P, default support 1.5 px; no blur.
Photon: analytic .45-px coverage outside Rh, shared field at 49ri/36 and order-0
azimuth, gain 1.18, attenuated by BOTH nearer crossings; no coverage normalization.
Accurate third-image option (deferred): extend LUT 2pi to 3pi (~128 rows), evaluate
third crossing with subpixel radial coverage. Current thread/filtering is approximate.

## Integration and frozen functions
Keep BH_UNIFORMS include inside buf, body include after `} ubuf;` before stars/main.
Bind original uniforms plus bhDetail, bhStreaks, bhKnots, bhEmbers, bhDoppler,
bhHue, bhGlow, bhPhoton, bhDetailPhase, bhArcs and bhNoise from BlackHole.
DEVIATION from CONTRACT-v4's uniform list: bhArcs (gain, radiusRh, spacingRh,
count) is a tenth vec4, appended LAST inside BH_UNIFORMS so no existing std140
offset moves. Unbound it reads as zero, which disables the bands.
Samplers: 1 bhTransfer nearest; 2 bhNoise linear; 3 physics atlas; no mipmaps/colour conversion.
Move current descriptorAtlas from binding 2 to a free slot (4); preview grid uses 4.
ShaderEffect: supportsAtlasTextures:false. Orchestrator re-bakes PRODUCTION after merge.
bhWarpBackground/bhJacobian/bhShadowMask retain v3 far lensing, C2 taper at 3.2–4 Rh.
bhWarpMaterial is legacy-only; particles use apparent-plane shadow/disk coverage.
bhDisk returns premultiplied LINEAR rgb/coverage: disk.rgb+(1-disk.a)*(far+material).
Shadow masks starlight BEFORE disk. bhDiskAbsorb is actual compact geometric disk
coverage weighted by P: 0 outside, 1 bright inner coverage; excludes shadow/thread.
Foreground/capture events remain birth-frozen; CPU cubic Bezier capture ends inside Rh.

## LUT, gates and limits
blackhole_lut.py is unchanged RK4: 1024x262 RGBA8. Rows 0–255 u(psi), 256/257
end/turn psi/32, 258 capture, 259 b/12, 260 sentinels, 261 signed sky projection+validity.
Decode (floor(R*255+.5)*256+floor(G*255+.5))/65535, then range; interpolate decoded words.
Bake: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o OUTPUT INPUT.
Disk <=diskCap linear (default .25), photon composite <=photonCap on thread support
(default .30); the target preset raises them to .60/.70 on the owner's decision.
Footprint <=3% (4% hard) at defaults; blackHole.footprintCap declares a larger budget
for a preset (target .11, measured .0982 at 2880x1800, .1066 worst at tilt 35).
Overrides require a footprint check. No Kerr/DNGR beam tracing, spectral physics,
film-grain fidelity or extended bloom. Phase 1 evidence: /tmp/starfield-dev/d4/report.md;
Phase 2 (preset/footprintCap/whiteness/arcs, tilt to 35) evidence: d4/p2-*.json + p2-*.png
and the delegate's final report. Default preset renders byte-identically to Phase 1.
