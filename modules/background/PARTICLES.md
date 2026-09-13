# Integrated material particles (v4)

`Starfield.particles` is the JSON `particles` object. `particlesEnabled` defaults
true; false selects the byte-preserved v3 procedural middle/near shader path.
With particles enabled, motionMode still controls far dust; blackHole.enabled
controls the visible hole. Physics runs in either mode until particles are disabled.
Each output owns one double-precision SoA simulation and two reusable Canvas
ImageData textures. The far layer, events and black-hole disk remain procedural.

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
| streak.exposureSec | .02 | finite 0..0.10 seconds |
| streak.maxPx | 12 | finite 0..32 physical px |
| sizes.nearPx | [2,4] | ordered pair, each .25..12 physical px FWHM |
| sizes.middlePx | [1,2] | ordered pair, each .25..12 physical px FWHM |
| sizes.capturedPx | [.8,1.4] | ordered pair, each .25..12 physical px FWHM |
| safetyLifeSec | [180,240] | ordered pair, each 30..600 active seconds |

Only those keys exist. Preserve missing population keys until stress defaults
are resolved; explicit values override the preset. Renderer validation clamps,
sorts pairs, rounds integer fields and proportionally reduces totals over3200.
The service should reject malformed values instead of silently repairing them.
Defaults/renderer normalization: `particles/Physics.js` defaults()/validate().

Physics uses epsilon-softened Newtonian acceleration, mu proportional to Rh^3,
k=clamp(radialSpeed,0,26)/6*(.8+.4*filteredFlow), muTarget=muBase*k*k.
Mu approaches its target over60 active seconds; existing x/v never rescale on
speed edits. Zero speed freezes physics/births. Suspend gaps over.25s are dropped.
Launch q ranges are fixed: plunge 0.05..0.60Rh, miss 1.15..1.80Rh, wide 2.5..4.5Rh.
Radial damping conserves angular momentum, then a three-second torque ramp uses
nu=ln(rCircular/Rh)/(2*birthFrozenSpiralSec). Death sweeps the drift segment atRh.
Rate replenishment uses completed residence estimates, without cap-filling bursts.
Bound offscreen particles stay alive; positive-energy outward escapes are removed.

Births copy resolved palette RGB, archetype, phase, size, luminosity and exposure;
reordering palettes cannot retint an ID. Binaries orbit an integrated barycentre;
wanderer offsets affect rendering only. Decayer lifetime starts at swept first
viewport nucleus entry, recorded at a physics substep and never reset on reentry.
DPR-only edits convert physical units once; ordinary resize retains physical x/v.
Optional pericentre hue/brightness styling is omitted: no force-dependent hue edit.

Atlas: binding3, opaque nearest RGBA8, width256. Four metadata texels precede
32px-bin headers; each header packs list offset16 and count/flags8. Count uses
six low bits (0..16); bit6 extends offsets by65536; bit7 links another page.
Full pages carry16 indices followed by a continuation header. No occupant drops;
512 shader pages cover all6400 possible binary render instances. Eight data
texels hold position16+support/core, velocity16, RGB8, energy16, archetype/phase,
period, age, streak and capture blend. The last texel is an upload sentinel.
Position domain includes padding plus40px optical guard. All touched bins receive
an index. Empty bins fetch one header; appearance is fetched only after support
rejection. Compact anisotropic Gaussian kernels normalize integrated energy.

Canvas writes use all seven putImageData arguments; the dirty rectangle covers
only the texels in use. Both buffers are allocated once per configuration from
its hard ceiling (2 instances/particle, 16 bins/instance), because one resize of
the sampled texture cost 13ms->6700ms per frame of scene-graph submission on
llvmpipe and never recovered. Only an inactive texture is painted; its texture,
header/data offsets, domain, count and clock commit together after painted(),
and a missed paint retains the prior revision. CPU sentinels are checked per
commit; GPU byte preservation is verified by the offscreen readback fixture
under /tmp/starfield-dev/p4/qt-validation/.

Disk integration: particles bypass bhWarpMaterial. Geometric shadow transmission
clips streaks atRh; disk.rgb+(1-disk.a)*(far+material) composites in linear light.
TEMP particleDiskAbsorb() currently uses bhDisk().a. Once D lands, replace its
body with bhDiskAbsorb(pixel), then rebake; D-owned GLSL is never modified here.
Binding1 is bhTransfer,2 is D's bhNoise,3 particles,4 birth descriptor history.
QML includes D's future uniform bindings; optional disk/photon inputs are passed
only when the provider exposes them. Its included GLSL must be rebaked on merge.
Bake from repository root (qsb resolves sibling includes from its input path):
`/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/background/shaders/starfield.frag.qsb modules/background/shaders/starfield.frag`
