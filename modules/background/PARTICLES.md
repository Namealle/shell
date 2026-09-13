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
| capture.radius | [1.0,1.3] | ordered pair, each 0.8..6 **Rd** (disk material-rim radii, see below) |
| capture.gamma | .25 | finite 0..2 /s; radial-only drag |
| capture.spiralSec | [20,60] | ordered pair, each 5..240 active seconds |
| epsilonRh | .05 | finite 0.01..0.20 |
| substeps | 4 | integer 4..32 per 1/30 s; adaptive refinement may add steps |
| streak.exposureSec | .035 | finite 0..0.10 seconds |
| streak.maxPx | 20 | finite 0..32 physical px |
| streak.bendExposureSec | .26 | finite 0..1 s, the exposure at full deformation |
| streak.bendMaxPx | 64 | finite 0..120 physical px, the streak ceiling at full deformation |
| streak.bendMaxAlive | 200 | integer 0..3200; a SMOOTH budget on the summed deformation, not a per-instance switch |
| streak.bendRadiusRd | 0.70 | finite 0..4 **Rd**; the nominal onset radius of the tidal deformation (was `bendRadiusRh` 2.4 Rh, then v7's `bendRadiusRv` 1.45) |
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

## Three radii, three jobs (v7b)

`Rh` is the DYNAMICAL scale — mu goes as `rh^3` — and it is also the screen
radius where the impact parameter reaches `b_c = 3*sqrt(3)/2 Rs`, i.e. the
**shadow** and the photon ring. It is not the size of the drawn object, which
runs out to the disk's material rim and, on a preset that draws them, fainter
still to the outer arcs. `Physics.visibleRadius(rh, geom)` returns all three and
each boundary picks the one that gives it its meaning:

| | what it is | who uses it |
|---|---|---|
| `shadow` | the black core, `Rh` | the swallow radius, the spiral target, the render fade, plunge/miss pericentres |
| `disk` (**Rd**) | the disk's emissive rim (`bhOuter`) | the capture band, the drag window, wide pericentres, the tidal reach |
| `arcs` | the art-directed outer bands (`bhArcReach`) | nothing — reported so a boundary never lands on them again |

It MIRRORS `bhOuter()`, `bhImpact()` and `bhArcReach()` in
`shaders/blackhole.glsl` and must be changed with them; `test-particles.mjs`
pins the constants. `geom` is the hole's own published uniforms — `bhDisk.x/.y`
and `bhArcs.x/.y/.z/.w` — read in `Starfield.qml`, so a disk the owner resizes
moves the particle boundaries with it and `starfield.json` needs no edit.
Omitted, it falls back to the v4 default disk (Rd = 2.783 Rh). The live `target`
preset since b0aa32dc is Rd = **3.735 Rh** with the arcs off.

### Two bugs, opposite directions

v6 anchored everything to Rh. Against the target preset's picture that put the
capture band INSIDE the disk, and stars were drawn on top of the material: 65.8 %
of the rendered ink and 99.5 % of the 267-instance captured ring sat inside the
drawn hole (ledger 2281, "it makes it seem like stars are inside"). v7 anchored
everything to the outermost drawn radius and killed stars there, which he
rejected the same day (ledger 2282): *"now the stars disappear too far from the
hole, they are disappearing somewhere close to the rings, don't think that is
right."*

Both were the same mistake: treating "the star is over the disk" as a question
about WHERE IT DIES. It is not. A star crosses the disk band alive and
**depth-ordered**; it dies in the black core and nowhere else.

### What is anchored where

- **Swallow radius = the shadow** (times the `bhHalo.w` envelope), as in v6.
- **Capture band = `capture.radius` x Rd**, default `[1.0, 1.3]`: the ring
  circularises at the disk's own rim, where the material it is joining ends.
- **Drag is a WINDOW, not everything inside the outer edge.** Filling it inward
  meant a star dragged past the band kept being damped all the way down and
  circularised wherever it ran out of speed — measured at 0.54 Rd, a captured
  ring sitting inside the material, which is half of what 2281 reported. The
  floor is half a band-width under the rim (0.85 Rd by default); below it a star
  is on a free orbit and simply falls in.
- **Spiral target = the shadow**: a captured star leaves the ring and spirals
  down THROUGH the disk band, occluded by the material, into the core.
- **Launch pericentres** are anchored per class by what the class means: plunge
  `[0.05,0.60]` and miss `[1.15,1.80]` in shadow radii (they are about hitting
  or missing the hole), wide `[0.70,1.30]` in Rd (it is about grazing the disk).
  Against the target preset these reproduce the v6 ladder; on any other disk the
  three classes keep their meaning. `s.qCap` caps a pericentre at the shortest
  birth radius so `launch()` never burns sixteen retries on an impossible orbit.
- **Tidal reach = `streak.bendRadiusRd` x Rd**, default 0.70: the tide bites as
  a star enters the material and tears it apart on the way to the core.
- **Still on Rh**, because they are dynamics and not geometry: mu, `vref`,
  `epsilonRh`, the substep thresholds, `padding`.

Mass moves the band's STANDOFF above the rim, not the rim, which is drawn and
does not move: `captureInner = Rd*(1 + (radius[0]-1)*cbrt(mass))`.

### The occlusion half

Keeping a star off the TOP of the disk is a compositing job, and `starfield.frag`
was only half doing it. `particleHit` attenuates by the disk through
`1-captured*absorb*(1-front)` — gated on `captured`, so an ordinary star got no
disk attenuation at all — and `main()` composited the whole particle field
through the disk's shading alpha `(1-disk.a)`. The non-front field now goes
through `(1-diskOcclusion)` where `diskOcclusion = particleDiskAbsorb(pixel,
disk.a) = max(disk.a, bhDiskAbsorb(pixel))`: the disk's geometric coverage
weighted by its own emissivity, which is what actually stands between a star and
the camera, and which also picks up the inner halo's alpha. `far` keeps the
shading alpha; `ahead` (the `depth.frontShare` of NEAR births) is still
composited over the disk, masked by the geometric shadow only. One extra `max`
per pixel, on a value already computed.

`Appearance.render` dissolves a star over the last `0.10 Rh` before the shadow
rather than a couple of core radii, so the swallow reads as a star sinking into
the core instead of switching off.

`blackHole.mass` (0.5..3, default 1) scales mu for the particles and, as its
square root, the far-dust inflow, so one number moves every layer's speeds
together; `particles.mass` overrides it. The hole's own visibility envelope
(`bhHalo.w`) scales the swallow radius and the central render fade, so disabling
the hole leaves the particles streaming through a soft centre instead of
vanishing into an invisible point.

## Tidal deformation (v6)

Every particle carries one continuous scalar, `stretch` in 0..1, and nothing
about its rendered shape switches between states. Through v5 a star crossed
`streak.bendRadiusRh` (now `bendRadiusRd`) and had its exposure replaced (.035 s -> .26 s) and its
kernel swapped from straight to curved in a SINGLE frame, while a
first-come-first-served `bendMaxAlive` cap flipped stars in and out of that
state from one frame to the next; measured on a 2160x3840 output, 344 stars sat
inside a 200-instance cap and rendered streaks jumped by up to 54 px between
consecutive frames. The scalar replaces both.

The drive is the local tidal field. mu is proportional to `rh^3 * mass`, so
normalising `mu/r^3` at `reach = bendRadiusRd * Rd * cbrt(mass) * onset` leaves
`(reach/r)^3`, which depends on `mass/r^3` and nothing else: one number moves
both the reach and the strength, and the hole's enable envelope (`absorb`,
i.e. `bhHalo.w`) multiplies the whole target, so a disabled hole fades the
deformation out over the same thirty seconds and leaves none at all. The
response saturates as `smoothstep(clamp((drive-1)*0.4))`, is weighted by
`0.55 + 0.45 * |r^ . v^|` — the tide stretches material along the RADIUS, and
the kernel is oriented by the velocity, so a radial plunge is what elongates it —
and takes `0.35 * captured` on top, the existing four-second capture ramp
standing in for time since capture.

Three traits are frozen at birth, so two stars at the same radius never render
the same shape: `tideOnset` .62-1.42 scales where the star first feels the hole,
`tideGain` .55-1 how far it goes, `tideRate` .45-1.9 s the relaxation constant.
The rendered value is a first-order relaxation `stretch += (target-stretch) *
step/(tau+step)` on ACTIVE time, so a paused output resumes rather than jumping,
and no star can move more than 6.9 % of its remaining gap in one frame.

The scalar drives three things continuously: the exposure and its pixel ceiling
lerp from `streak.exposureSec`/`maxPx` to `bendExposureSec`/`bendMaxPx`
(tangential stretch), the shader multiplies `minorVariance` by `1 - .40*stretch`
(radial squash at constant integrated energy), and it weights the curved
kernel's transverse offset. That last term needs no direction factor of its own:
kappa is the perpendicular acceleration, which a radial plunge has none of.

`bendMaxAlive` is now a smooth global budget. Each frame the summed unscaled
target is compared with it and one global scale slews toward `cap/demand` with a
two-second constant, so a crowded frame dims everyone's deformation slightly
instead of snapping one star's trail from 64 px to 14 px. Because the scale is
global, slow and applied to the target rather than the state, no single star's
shape can step. `bounds()` therefore sizes the atlas for `maxBends = maxItems`:
any instance may be fully stretched, and a transient may briefly carry the sum
above the budget while the relaxations catch up.

Flags bit 6 is only a hint that the deformation is nonzero; the shader and the
packer both weight on the scalar. Node tests: `modules/background/tools/test-particles.mjs`.

## Tidal disruption (v6, `phenomena.tde`)

Particles only: no event slot, no uniform, no shader change. The renderer owns
the schedule (`Starfield.qml` `scheduleTde()`), `Physics.js` owns the victim and
the split, `Appearance.js` owns the trail.

`Physics.doom(s, {streakPx, stretchSec, fragments})` picks a victim: alive, not
already captured, pericentre inside 6 Rh, currently between the capture radius
and 12 Rh, inbound, and nearest to its own pericentre so the stretch and the
closest approach coincide. It returns false when no particle qualifies; the
renderer retries in five seconds rather than losing the episode.

`Appearance.render()` then ramps that particle's packed streak to `streakPx`
over `stretchSec` on a smoothstep, dimming its core by up to 55 % and reddening
it (green -10 %, blue -26 %) as the same light spreads over a far longer trail.
`streakPx` is clamped to **120 px, not the service's 160**: 120/255 per code is
what the packed streak byte carries, and `Physics.doom` clamps to the same
number so the atlas and the renderer agree.

`tdeStep()` runs once per outer step, outside `step()`, so the hot loop pays
nothing. At `stretchSec` it injects `fragments` siblings spread ALONG the orbit
(a spread in specific energy, not a spray of directions) through `inject()`,
which places them on the victim's own state rather than launching them from an
edge. The descriptor is then held for a six-second fade so the head's own trail
eases back to its natural length: clearing it at the split snapped the rendered
streak from 120 px to 8 px on one frame, the same defect as the old bend cap.

`diskFlash` rides the hole's brightness channel (`ambientHole.z`, which
`bhLook.x` reads) for twenty seconds, eased in over the first quarter and out
over the last half on top of the hole's own 30 s slew. The brainstorm called it
`activity`, but activity is the pattern-speed channel and would not brighten
anything.

ATLAS: `bounds()` returns `maxTde`/`tdeSupport` for one instance at the 120 px
ceiling and `capacity()` adds it as a bounded addition, like the flare set —
about 72 extra references in total. This is unconditional and does not consult
the live `phenomena` config, because the atlas is allocated once per
configuration and a resize of the sampled texture cost 13 ms -> 6700 ms per
frame on llvmpipe and never recovered.

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
Launch q ranges are fixed: plunge 0.05..0.60 and miss 1.15..1.80 in SHADOW radii,
wide 0.70..1.30 in disk-rim radii, each capped at the shortest birth radius.
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

Render instances are one flat Float64Array, stride 21: x y vx vy core support
streak r g b lum flags phase p0 age captured id generation halfMajor halfMinor
stretch; flags is the archetype in the low three bits, bit 3 flare, bit 4 near
layer, bit 5 in front of the disk, bit 6 a nonzero tidal deformation. The binner walks the streak's
capsule (half-extents at 18/19) rather than its bounding box; the packer turns
the same two numbers into the axis-aligned box the shader rejects against, which
a long thin trail fills about ten times more densely than the disc of its
half-length. Atlas: binding3, opaque nearest RGBA8, width256. Four metadata texels precede
32px-bin headers; each header packs list offset16 and count/flags8. Count uses
six low bits (0..16); bit6 extends offsets by65536; bit7 links another page.
Full pages carry16 indices followed by a continuation header. No occupant drops;
512 shader pages cover all6400 possible binary render instances. Eight data
texels hold position16+stretch/core, velocity16, RGB8, energy16, flags/phase,
period/streak and the reject box + capture blend. The last texel is a sentinel.
Texel +1 green carried the bin support through v5, which the reject box replaced
and no shader has read since; it now carries the 0..255 tidal stretch, and costs
no extra fetch because that texel is already sampled for the position's high
bits. The version byte is 5 (was 4), checked on the CPU by `Packing.verify`.
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
clips streaks atRh, the same radius the CPU fades and swallows them at;
disk.rgb+(1-disk.a)*far+(1-diskOcclusion)*material composites in linear light.
particleDiskAbsorb() takes the larger of bhDisk().a and D's bhDiskAbsorb(pixel).
Binding1 is bhTransfer,2 is D's bhNoise,3 particles,4 birth descriptor history.
D's included GLSL reaches production only through a rebake of this shader.
Bake from repository root (qsb resolves sibling includes from its input path):
`/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/background/shaders/starfield.frag.qsb modules/background/shaders/starfield.frag`
