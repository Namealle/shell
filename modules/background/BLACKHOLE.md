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
| lensReach / lensStretch | 8 / 1.5 | 4-12 Rh lensing envelope (C2 taper over .8RL..RL; RL=4 is the v4 envelope exactly) / 1-3 art-directed exaggeration of the Jacobian and of the retained radial streak structure |
| footprintCap | .03 | .01–.12 declared luminous-footprint budget; validation checks it, GLSL does not clamp it |
| diskCap / photonCap | .25 / .30 | .10–1.0 linear; the limiters the shader ENFORCES. The film shoulder follows diskCap (knee .72*cap, span .24*cap), so a raised cap is actually reached. Discrete config: a change does not slew |
| disk.exposure | 1 | .5–2; multiplies intensity into bhLook.x, whose ceiling widens 1 -> 2 |
| disk.hue.whiteness | 0 | 0–1 highlight desaturation toward white, weighted by light/cap; luminance-preserving |
| disk.arcs.gain | 0 | 0–.02 linear; 0 (default) disables the outer bands entirely |
| disk.arcs.radiusRh / spacingRh / count | 1.7 / .6 / 2 | 1.2–2.6 Rh / .2–1 Rh / rounded integer 0–2 |
| disk.detail | .75 | 0–.85 |
| disk.seed / disk.rotationSign | 457 / 1 | integer 0–65535 / -1 or +1 (zero becomes +1) |
| disk.streaks.octaves / disk.streaks.radialScale | 2 / 1 | integer 1–3 / .5–2 |
| disk.streaks.innerPeriodSec | 12 | 4-256 s; converted to round(4096/period) whole turns so every row still repeats exactly in 4096 s |
| disk.streaks.innerCyclesPer4096 | (derived) | 16-1024; when present it OVERRIDES innerPeriodSec |
| disk.streaks.smear | .6 | 0-1 azimuthal motion blur, 3 taps only where a row moves >.3 cell per 1/30 s exposure |
| disk.falloff | 1 | 1-3 exponent on the normalised radial profile; 1 is the frozen zero-torque profile |
| disk.rim.skirt / fray / clump | .7 / .6 / .6 | 0-1: sparse clumpy dust from re to diskOuterRs / wobble of the inner boundary radius / azimuthal break-up of skirt, arcs and photon thread |
| disk.depth.foreground / lane | .35 / .3 | 0-1: near-strip gain and coverage boost (occludes the thread and the far arcs) / equatorial dust lane about the projected major axis |
| disk.arcs.count | 2 | 0-4 rings (was 0-2); each is razor-thin and broken independently in azimuth |
| disk.streaks.warp / disk.streaks.grain | .25 / .06 | 0–.25 cells / 0–.08 |
| disk.knots.density / disk.knots.gain | .03 / .35 | 0–.06 / 0–.5; energy <=20% |
| disk.embers.count | 24 | even 0–min(32,2*(cycles-1)); odd rounds down |
| disk.embers.radiusRs / disk.embers.trailSec / disk.embers.gain | .012 / .35 / .06 | .004–.025 / 0–.6 / 0–.06 |
| disk.doppler.preset / disk.doppler.strength | film / .22 | film or physical; 0–1 (physical default 1) |
| disk.hue.innerTemperature / disk.hue.outerTemperature | 6500 / 1700 | 4200–10000 / 1000–2800 K |
| disk.hue.warmth | .5 | 0–1 |
| disk.glow.gain / disk.glow.radiusPx | .008 / 1.5 | 0–.008 / .25–2.5 physical px |
| disk.halo.gain / disk.halo.reachRh | 0 / 1.43 | 0–1 fraction of photonCap at the shadow edge (0 = off, so every pre-v7 preset renders unchanged) / 1–2 Rh. The inner-halo band; bhGlow.z/.w |
| disk.roll | 0 | -90–90 deg: roll of the disk PLANE in the image plane. bhDisk.z has always carried it through bhCrossing / bhDopplerFactors / the dust-lane axis; before v7 nothing wrote it |
| photon.mode | shared-field | shared-field or off; unknown resolves shared-field |
| photon.widthPx / photon.gain / photon.textureStrength | .45 / 1.18 / .8 | .1–.75 / 0–1.5 / 0–1 |

## Target preset (v7, fitted to ~/Downloads/LocalSend/wallpaper.png 2026-09-13)
`"blackHole": { "preset": "target" }` is exactly equivalent to this literal JSON,
which the service may send instead if it prefers not to know preset names:

```json
{"blackHole": {
  "size": 0.11,
  "tilt": 13,
  "intensity": 1,
  "haloUpper": 0.82,
  "haloLower": 0.51,
  "diskOuterRs": 11,
  "lensReach": 8,
  "lensStretch": 1.6,
  "footprintCap": 0.2,
  "diskCap": 1,
  "photonCap": 1,
  "disk": {
   "exposure": 1.7,
   "detail": 0.29,
   "falloff": 1.25,
   "roll": 11,
   "halo": {
    "gain": 0.76,
    "reachRh": 1.61
   },
   "streaks": {
    "octaves": 2,
    "radialScale": 1.4,
    "innerPeriodSec": 12,
    "warp": 0.25,
    "grain": 0.08,
    "smear": 0.85
   },
   "hue": {
    "innerTemperature": 10000,
    "outerTemperature": 2800,
    "warmth": 0,
    "whiteness": 0.49
   },
   "doppler": {
    "strength": 0
   },
   "glow": {
    "gain": 0.008,
    "radiusPx": 2.5
   },
   "rim": {
    "skirt": 1,
    "fray": 0.92,
    "clump": 0.3
   },
   "depth": {
    "foreground": 0.09,
    "lane": 0.35
   },
   "arcs": {
    "gain": 0,
    "radiusRh": 1.6,
    "spacingRh": 0.55,
    "count": 4
   }
  },
  "photon": {
   "mode": "shared-field",
   "widthPx": 0.75,
   "gain": 0.9,
   "textureStrength": 0.8
  }
 }}
```

`disk`/`photon` are LAYERED: the preset sits beneath whatever object is
assigned, and explicit keys win key by key, one nested level deep. Assigning
`disk = {}` therefore cannot erase the preset (a consumer doing exactly that
every frame is what produced the 2026-09-12 live regression).
The FLAT properties (size, tilt, intensity, haloUpper, haloLower, diskOuterRs,
diskCap, photonCap, footprintCap) are preset-aware BINDINGS instead: a consumer
that assigns them unconditionally replaces the binding and the preset can no
longer reach them. Bind them as
`x: cfg.x !== undefined ? cfg.x : pick("x", <default>)`, never as
`x: cfg.x !== undefined ? cfg.x : <default>`.

### How it was fitted, and how to refit it
Nothing here was chosen by eye. `tools/bh_probe.py` renders the preview shader
offscreen with exactly the uniforms BlackHole.qml would produce, and its
`--check` fails if it has drifted from the .qml. `tools/bh_ringdiff.py`
normalises the reference and the render into ONE frame -- shadow centred, its
radius matched, the disk's major axis rotated level -- then measures ~35
quantities plus a 9-band radial profile split into disk plane and polar cap.
`tools/bh_fit.py` coordinate-descends the preset against a weighted objective;
the judgement is in its OBJECTIVE table, the search is clerical.
The reference's shadow is fitted twice (a ring score for the centre, then a
circle least-squares-fitted to the steepest radial brightness rise) and lands at
centre (1372.4, 757.3) radius 174.6 px, exactly on the photon ring the picture
draws. Full before/after: ~/namealle/claude/caelestia/starfield-v2/evidence/
v7-ring-table.md, v7-ring-compare.png, v7-ring-overlay.png, v7-ring-metrics.json.

Headlines, reference -> v6 -> v7 (linear luminance, normalised frame):

| | reference | v6 | v7 |
|---|---:|---:|---:|
| 1.00-1.20 Rh annulus | .5799 | .0572 | .5199 |
| 1.20-1.45 Rh annulus | .4614 | .0578 | .3930 |
| major-axis angle | +14.0 deg | +2.6 deg | +13.4 deg |
| q50 / q90 / q99.9 | .119 / .639 / .958 | .052 / .254 / .866 | .112 / .500 / .963 |
| azimuthal HF energy at 2.4 Rh | .655 | 2.053 | .640 |
| "drawn ring" radial ripple | .189 | 1.340 | .196 |
| R/B at 3 Rh | 3.44 | 11.17 | 3.48 |
| white light fraction | .138 | .056 | .141 |

What v7 changed and why, in order of how much it mattered:
1. THE MOAT. v6 put .057 of light in the 1.0-1.45 Rh annuli where the reference
   carries its brightest band (.580/.461), nearly isotropically (plane .603,
   pole .616). That region is the photon-ring COMPLEX, the order>=2 image
   pile-up, which this renderer cannot trace because the transfer LUT stops at
   2pi. `disk.halo` is the same kind of ART-DIRECTED stand-in the outer arcs
   already are, put where the reference actually carries its light. The shader
   comment in bhDisk() states its shape, texture bound and occlusion rules.
2. ROLL. The reference's disk plane is rolled +14.0 deg in the image plane.
   bhDisk.z already carried a roll everywhere it mattered; nothing wrote it.
3. TEXTURE. detail .8 measured 2.05 of azimuthal high-frequency energy against
   the reference's .655: v6's arms were separated filaments, the reference's are
   one sheet with striations. detail .29 lands on .640.
4. OUTER ARCS OFF. Measured, the razor bands are the largest source of radial
   ripple in the polar sector (1.34 with them, .30 without, reference .19), and
   they are what the owner called "drawn" in v5. Dimming does NOT help, since
   the ripple is relative to the local mean; only `arcs.gain: 0` does. Keys stay.
5. COLOUR. innerTemperature 7000 -> 10000 and outerTemperature 1700 -> 2800 take
   the outer arm's R/B from 11.17 to 3.48 against the reference's 3.44, and the
   white-light fraction from .056 to .141 against .138.
6. DOPPLER. The reference carries no beaming asymmetry (mean light left of
   centre over right, .967); v6 measured 1.439. `disk.doppler.strength: 0`.
   Put it back to .22 for the physical look; nothing else depends on it.
7. LENSED ARC GAINS. haloUpper/haloLower 1/.9 -> .82/.51. The inner halo now
   carries the ring hugging the shadow, so these can come down and thin the disk
   vertically instead of padding it.

Footprint against the declared .2 cap: .0711 at 3440x1440, .1061 at 2880x1800,
.0955 at 1440x2560 (DP-3 rotated). Peak reaches the cap by design; q99.9 rises
from .6635 (v6) to .80-.84 against the reference's .958.

STILL DIFFERENT, and why. The disk's vertical half-thickness at 1.8 and 2.5 Rh
is +123% and +99% against the reference. Lowering `tilt` fixes the middle and
collapses the tip (at tilt 8 the tip half-height drops to .018 against .140),
and extending the emitting radius lengthens the arms and fattens them in the
same proportion -- both measured, both rejected by the fit. The reference's arms
are long AND thin, which a lensed Schwarzschild disk at one inclination does not
produce: closing that needs a radius-dependent vertical squash, i.e. new
geometry, not a preset value. The lower crescent is also 29% brighter than the
reference's and its inner edge starts at .374 Rh rather than .101, because the
reference's near strip crosses further across the face of the shadow.

## Field, colour and clocks
blackhole_noise.py: untagged 128x128 RGBA8, duplicated edges, RGB periods 32/64/127.
A=255 avoids Qt premultiplication corruption. Deviation: optional third period is
127; 128 unique cells plus duplicate need 129. Radial lattice period is 127.
Rows rotate at round(innerCycles*(ri/rRow)^1.5); quintic interpolation joins rows.
innerPeriodSec 12 gives innerCycles 341 (12.012 s inner, ~77 s at the outer skirt).
LOD is ANISOTROPIC: radial and angular footprints filter separately, so a strongly
demagnified lensed image keeps its azimuthal filaments while its row structure
washes out - the arc reads as stretched material. lensStretch retains extra
radial structure and exaggerates bhJacobian away from identity.
diskOuterRs <= 11: the transfer LUT's impact-parameter table ends at b=12, i.e.
r ~ 11.47 rs, and the skirt must stay inside it.
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
bhHue, bhGlow, bhPhoton, bhDetailPhase, bhArcs, bhRim, bhDepth and bhNoise.
bhRim = (skirt, fray, clump, smear); bhDepth = (foreground, lane, falloff, lensStretch).
DEVIATION from CONTRACT-v4's uniform list: bhArcs, bhRim and bhDepth are the
tenth to twelfth vec4s, appended LAST inside BH_UNIFORMS so no existing std140
offset moves. Unbound, bhArcs and bhRim read zero (bands and skirt off) but
bhDepth MUST be bound: a zero falloff/lensStretch flattens the profile and the
lens Jacobian. Bind all three.
Samplers: 1 bhTransfer nearest; 2 bhNoise linear; 3 physics atlas; no mipmaps/colour conversion.
Move current descriptorAtlas from binding 2 to a free slot (4); preview grid uses 4.
ShaderEffect: supportsAtlasTextures:false. Orchestrator re-bakes PRODUCTION after merge.
bhWarpBackground/bhJacobian/bhShadowMask retain v3 far lensing, C2 taper at 3.2–4 Rh.
bhWarpMaterial is legacy-only; particles use apparent-plane shadow/disk coverage.
bhDisk returns premultiplied LINEAR rgb/coverage: disk.rgb+(1-disk.a)*(far+material).
Shadow masks starlight BEFORE disk. bhDiskAbsorb is actual compact geometric disk
coverage weighted by P: 0 outside, 1 bright inner coverage; excludes shadow/thread.
Foreground/capture events remain birth-frozen; CPU cubic Bezier capture ends inside Rh.
`blackHole.mass` (.5-3, default 1, overridden by `particles.mass`) also sets the
reach and strength of the particles' tidal deformation: the onset radius goes as
`cbrt(mass)`, so the drive is exactly proportional to mass/r^3. The enable
envelope gates it, so a disabled hole leaves no deformation. PARTICLES.md owns it.

## LUT, gates and limits
blackhole_lut.py is unchanged RK4: 1024x262 RGBA8. Rows 0–255 u(psi), 256/257
end/turn psi/32, 258 capture, 259 b/12, 260 sentinels, 261 signed sky projection+validity.
Decode (floor(R*255+.5)*256+floor(G*255+.5))/65535, then range; interpolate decoded words.
Bake: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o OUTPUT INPUT.
Offscreen rendering for measurement: tools/bhrender.c (surfaceless EGL,
LIBGL_ALWAYS_SOFTWARE=1), driven by tools/bh_probe.py. QT_QPA_PLATFORM=offscreen
renders ShaderEffect BLACK and QT_QUICK_BACKEND=software does not render it at all.
Disk <=diskCap linear (default .25), photon composite <=photonCap on thread support
(default .30); the target preset raises both to 1 (v5 had .60/.70).
Footprint <=3% (4% hard) at defaults; blackHole.footprintCap declares a larger budget
for a preset (target .2, measured .1061 at 2880x1800, .0711 at 3440x1440).
Overrides require a footprint check. No Kerr/DNGR beam tracing, spectral physics,
film-grain fidelity or extended bloom. Phase 1 evidence: /tmp/starfield-dev/d4/report.md;
Phase 2 (preset/footprintCap/whiteness/arcs, tilt to 35) evidence: d4/p2-*.json + p2-*.png
and the delegate's final report. Default preset renders byte-identically to Phase 1.
