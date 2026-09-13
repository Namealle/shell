# Integrated material particles (v4)

`Starfield.particles` is the JSON `particles` object. `particlesEnabled` defaults
true; false selects the byte-preserved v3 procedural middle/near shader path.
motionMode still controls far dust and blackHole.enabled the visible hole. Each
output owns one double-precision SoA simulation and two reusable Canvas ImageData
textures; far layer, events and disk stay procedural.

Service schema (closed object; reject unknown keys, booleans must be booleans):

| Key | Default | Bounds / validation |
|---|---|---|
| population.near | 120 | integer 0..3200 |
| population.middle | 480 | integer 0..3200; combined population <=3200 |
| stressPreset | false | boolean; missing populations become near600/middle1500 |
| vref | 120 | finite 10..600 px/s at r1080 on short side2160 |
| launch.plunge | .35 | finite 0..1 |
| launch.miss | .55 | finite 0..1 |
| launch.wide | .10 | finite 0..1; normalize the three, zero sum uses defaults |
| launch.betaBound | [.65,.90] | ordered finite pair, each 0.10..0.99 |
| launch.unboundShare | .20 | finite 0..1 of miss launches |
| launch.betaUnbound | [1.02,1.12] | ordered pair, each 1.001..2 |
| launch.handedness | .85 | finite 0..1 prograde with disk.rotationSign |
| capture.radius | [3.3,4] | ordered pair, each 1.05..8 Rh |
| capture.gamma | .25 | finite 0..2 /s; radial-only drag |
| capture.spiralSec | [20,60] | ordered pair, each 5..240 active seconds |
| epsilonRh | .05 | finite 0.01..0.20 |
| substeps | 4 | integer 4..32 per 1/30 s; adaptive refinement may add steps |
| streak.exposureSec | .035 | finite 0..0.10 seconds |
| streak.maxPx | 20 | finite 0..32 physical px |
| streak.bendExposureSec | .26 | finite 0..1 s, used inside bendRadiusRh |
| streak.bendMaxPx | 64 | finite 0..120 physical px |
| streak.bendMaxAlive | 200 | integer 0..3200 curved instances; the excess renders straight |
| streak.bendRadiusRh | 2.4 | finite 0..12 Rh; inside it trails curve along the orbit |
| sizes.nearPx | [2.4,4.8] | ordered pair, each .25..12 physical px FWHM |
| sizes.middlePx | [0.9,1.7] | ordered pair, each .25..12 physical px FWHM |
| sizes.capturedPx | [1.2,2.2] | ordered pair, each .25..12 physical px FWHM |
| safetyLifeSec | [180,240] | ordered pair, each 30..600 active seconds |
| flare.share | .085 | finite 0..0.5 of near births drawn as flared |
| flare.maxAlive | 10 | integer 0..64; render() caps the live flared instances |
| flare.capturedLight | .7 | finite 0..1; captured light = 1 - value*captured |
| publishHz | 30 | integer 10..30; effective rate is the largest 30/n not above it |
| mass | 1 | finite 0.5..3; also read from `blackHole.mass`, which this overrides |
| depth.frontShare | .12 | finite 0..0.5 of near births composited in FRONT of the disk |
| depth.binaryMaxAlive | 40 | integer 0..3200 extra binary instances; the excess renders single |
| clustering.share | .72 | finite 0..1 of births that join a stream instead of arriving uniformly |
| clustering.streams | 5 | integer 1..12 drifting birth streams |
| clustering.streamLifeSec | 150 | finite 20..600 active seconds before a stream is re-rolled |
| clustering.burstDepth | .55 | finite 0..1; arrival-rate modulation, long-run mean unchanged |
| dust.farFlow | 24 | finite 1..64; far-dust inflow multiplier, also scaled by sqrt(mass) |
| dust.parallaxPx | 250 | finite 0..800; bounded 4096-safe parallax sway of the far field |
| dust.clusterGain | 1 | finite 0..1; 0 restores the uniform far-dust occupancy |
| dust.clusterCells | 16 | integer 2..64 far-dust cells per cluster |
| dust.voidCells | 44 | integer 4..192 far-dust cells per void/stream cell |
| dust.cellScale | .77 | finite 0.4..2; far-dust cell size, <1 puts back the count clustering removes |

Only those keys exist. Preserve missing population keys until stress defaults
are resolved. Renderer validation clamps, sorts pairs, rounds integer fields and
proportionally reduces totals over3200; the service should reject malformed
values instead. Normalization: `particles/Physics.js` defaults()/validate().

`blackHole.mass` (0.5..3, default 1) scales mu for the particles and, as its
square root, the far-dust inflow, so one number moves every layer's speeds
together; `particles.mass` overrides it. The hole's own visibility envelope
(`bhHalo.w`) scales the swallow radius and the central render fade, so disabling
the hole leaves the particles streaming through a soft centre instead of
vanishing into an invisible point.

Far dust flows inward on the existing radial cell grid, which advances at a
constant rate in u = r^2/2 and therefore moves at dr/dt proportional to 1/r:
about 100 px/s at 1 Rh, 14 px/s at mid-screen and 7 px/s in the corner of a
2160x3840 output at farFlow 24. The bounded parallax sway adds a floor so no
region is frozen. Occupancy is a two-level Neyman-Scott process: cluster cells
inside much coarser void/stream cells, both advected with the flow.

Integration subdivides per particle: the outer step is the publish interval, and
each particle takes one to `substeps` inner kick-drift-kicks, chosen so
dt/j*sqrt(mu/r^3) stays under half the 0.03 stability limit and no particle
crosses 8% of its radius in a step — 1 beyond 2.68Rh, 2 beyond 1.69Rh, 3 beyond
1.29Rh, 4 inside; mean 1.71. Physics uses epsilon-softened Newtonian acceleration, mu proportional to Rh^3,
k=clamp(radialSpeed,0,26)/6*(.8+.4*filteredFlow), muTarget=muBase*k*k.
Mu approaches its target over60 active seconds; existing x/v never rescale on
speed edits. Zero speed freezes physics/births. Suspend gaps over.25s are dropped.
Launch q ranges are fixed: plunge 0.05..0.60Rh, miss 1.15..1.80Rh, wide 2.5..4.5Rh.
Radial damping conserves angular momentum, then a three-second torque ramp uses
nu=ln(rCircular/Rh)/(2*birthFrozenSpiralSec). Death sweeps the drift segment atRh.
Rate replenishment uses completed residence estimates, without cap-filling bursts.
Bound offscreen particles stay alive; positive-energy outward escapes are removed.

A near birth draws v3's four-point flare with flare.share and, when flared,
always takes a palette colour (whitened 0.30 rather than 0.35): those few stars
are the ones the eye reads as coloured. The flare cross is v3's at 0.55 core
radii, tapering to zero at 22 of them. Near cores are the gain of a saturating
kernel in the shader, not a normalized bump, so they reach white as v3's near
stars did; middle cores stay energy-normalized. Births copy resolved palette RGB, archetype, phase, size, luminosity and exposure,
so reordering palettes cannot retint an ID. Binaries orbit an integrated
barycentre; wanderer offsets affect rendering only. Decayer lifetime starts at
swept first viewport entry and never resets. DPR-only edits convert units once;
ordinary resize retains physical x/v. Pericentre hue styling is omitted.

Render instances are one flat Float64Array, stride 20: x y vx vy core support
streak r g b lum flags phase p0 age captured id generation halfMajor halfMinor;
flags is the archetype in the low three bits, bit 3 flare, bit 4 near layer,
bit 5 in front of the disk, bit 6 curved trail. The binner walks the streak's
capsule (half-extents at 18/19) rather than its bounding box; the packer turns
the same two numbers into the axis-aligned box the shader rejects against, which
a long thin trail fills about ten times more densely than the disc of its
half-length. Atlas: binding3, opaque nearest RGBA8, width256. Four metadata texels precede
32px-bin headers; each header packs list offset16 and count/flags8. Count uses
six low bits (0..16); bit6 extends offsets by65536; bit7 links another page.
Full pages carry16 indices followed by a continuation header. No occupant drops;
512 shader pages cover all6400 possible binary render instances. Eight data
texels hold position16+support(0.5px)/core, velocity16, RGB8, energy16, flags/phase,
period/streak and the reject box + capture blend. The last texel is a sentinel.
Position domain includes padding plus40px optical guard. All touched bins receive
an index. Empty bins fetch one header; appearance is fetched only after support
rejection. Compact anisotropic Gaussian kernels normalize integrated energy.

Canvas writes use all seven putImageData arguments; the dirty rectangle covers
only the texels in use. Both buffers are allocated once per configuration from its
hard ceiling (2 instances/particle, 16 bins each, plus flare.maxAlive wider ones):
one resize of the sampled texture cost 13ms->6700ms per frame of scene-graph
submission on llvmpipe and never recovered. Only an inactive texture is painted;
texture, offsets, domain, count and clock commit together after painted(), and a
missed paint retains the prior revision. Sentinels are checked on every commit.

Disk integration: particles bypass bhWarpMaterial. Geometric shadow transmission
clips streaks atRh; disk.rgb+(1-disk.a)*(far+material) composites in linear light.
particleDiskAbsorb() takes the larger of bhDisk().a and D's bhDiskAbsorb(pixel).
Binding1 is bhTransfer,2 is D's bhNoise,3 particles,4 birth descriptor history.
D's included GLSL reaches production only through a rebake of this shader.
Bake from repository root (qsb resolves sibling includes from its input path):
`/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/background/shaders/starfield.frag.qsb modules/background/shaders/starfield.frag`
