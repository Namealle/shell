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
| debris.maxAlive | 400 | integer 0..480; transient (event) particles alive at once. **Atlas-allocated whether or not an event ever fires** |
| debris.relaxSec | 1.6 | finite 0.05..12 s; how long a star shoved by a shock takes to relax back into the flow |
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

Only those keys exist (`debris` is v10). Preserve missing population keys until stress defaults
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

## Camera fly-through (v8)

The other regime, and the only one with no hole in it. It is NOT a particle
config key: `Starfield.qml` writes it onto the pool every frame the way it
already writes `absorb`, because it is runtime state, not configuration —
`cameraBlend` 0..1, `cameraDir` +1 out / −1 in, `cameraDepth` (the far plane,
2..64, near plane fixed at 1), `cameraRate` (depth units per active second),
`cameraRoll` (rad/s, a bounded sinusoid), `cameraSizeGain`. The JSON that feeds
them is `motion.camera` and STARFIELD.md owns its bounds.

`blend > 0` scales `mu` and `capture.gamma` by `1 - blend` in `step()` and
scales the substep ladder by the same number in `advance()`, so at blend 1 there
is no gravity, no drag, no torque, no circularisation (the `e < 0` test cannot
pass with mu 0), no swallow (already on `absorb`) and no tide (already on
`absorb`), and every particle integrates the whole publish interval in ONE
kick-drift-kick. `phenomena.tde` is scheduled only while the hole is enabled, so
it stops on its own.

What replaces it is one line in the drift. A star at 3-D depth `z` and screen
radius `r` projects at `r = f*rho/z`, so advancing the camera by `rate*h` scales
every screen position about the centre by `z/z'`:

```js
zn = z - dir*rate*h;  mag = z/zn;
nx = mix(x + h*vx, mag*x, blend);   // + a small roll in the same 2x2
vx += blend*((nx - x)/h - vx);      // the stored velocity IS the blend
```

Exact, exactly invertible — which is what makes reverse playback a true reverse,
pinned in the tests to 1e-11 px over 200 steps out and 200 back — and
perspective for free: `dr/dt = r*w/z` grows with radius, and two stars at the
same radius separate by depth, which is the parallax. `depthZ` is one more
Float64Array; a particle alive when the camera engages is given one from a hash
of its slot and generation rather than from the simulation's RNG, so the orbital
stream stays byte-identical to v7 (pinned: 600 live stars compared bit for bit
after 90 s with the camera present at blend 0).

**Births are the time-reverse of deaths**, which is the whole reason the field
stays uniform in both directions (measured bin density spread 1.16x out, 1.21x
in, against a 3.4x hole in the middle for the first attempt):

- forward, a star is born at the FAR plane, uniform over the padded rectangle
  around the camera axis — a uniform 3-D field crossing a plane is uniform on
  the screen — and dies where its magnified radius leaves that rectangle (the
  ordinary escape test, which mu 0 makes unconditional) or, for the ~1 % born
  inside `corner/depth`, at the near plane;
- reverse takes the SAME far-plane draw as the point where the star will
  dissolve, runs it back out along its own ray to the edge it came in through,
  and starts it there at the depth it crossed at. Arc-length weighting of the
  perimeter and flux weighting were both tried; both measured a thinner field
  than forward, because neither reproduces the joint distribution of position
  and depth. This construction is the forward one read backwards, so it cannot.

`Appearance.render` scales core and light by `1/z` through `sizeGain` and fades
both over the last 10 % of the depth range at the far plane and the last 6 % at
the near one, so an arrival and a departure are never a switch. Both factors are
at most 1: depth can only dim and shrink a star, so the atlas ceiling `bounds()`
allocated from `sizes.*Px` is still the ceiling and no camera value can overflow
it. Pinned in the tests.

The crossfade is the hole's own 30 s enable envelope read backwards, and the
regimes always sum to one. Measured worst one-frame move across the change:
21 px, which is what the orbital regime's own fastest star does anyway. Two
things about it are not linear in the envelope, both measured:

- **gravity leaves as the SQUARE of it.** The swallow radius follows `absorb`
  linearly, so a linear mass fade leaves a late crossfade holding 6 % of the
  pull behind a 14 px event horizon, and a star diving into that gap whips
  round it — worst one-frame streak change 8.0 px against a 2.8 px baseline
  with no change of regime. Squaring takes the peak speed at a given radius
  down by four. It is the right way round anyway: the mass should be gone
  before its horizon is.
- **a birth mid-crossfade arrives with the velocity the crossfade is about to
  give it.** A share `1 - blend` of births still comes off an orbit, and a pure
  orbital velocity at blend 0.88 was a 264 -> 38 px/s change on the star's first
  step: an 8 px jump in the rendered streak, on a star the 0.35 s entrance fade
  still had at 3 % light. Blending the launch velocity by the same number takes
  the change of regime to the SAME contract the orbital regime has held since
  v6 — 1.73 M instance-frames across it, none over 5 px, and the same p99.9
  (0.94 px) as the orbital regime alone.

Three things keep the population steady, all of them off at blend 0:

- **`clustering.burstDepth` fades out with the regime.** Arrival gusts are an
  INFALL idea, and a gust lands inside one camera generation (21 s mean life
  against the orbital 97) instead of averaging out: twenty minutes measured a
  467-600 swing against the orbital 577-600. With it off the camera holds
  545-600, and `clustering.share` never reached `cameraLaunch` at all.
- **the lifetime estimator is cleared at the crossing and bounded after it.**
  It is a feed-forward guess with unbounded memory, which is right for a regime
  that never changes and wrong for one that does: the change itself records
  lives that began under gravity and ended under the camera. Cleared, it goes
  back to its own 30 s prior; halved every 800 samples, it then follows the
  regime it is in instead of the one it came from.
- **a proportional term closes the rest.** Nothing ever corrected the guess,
  because nothing had to. A change of regime breaks it twice over — the old
  population is not a camera population and a chunk of it leaves at once — and
  the field measured 600 -> 314 stars recovering over minutes. A term that is
  zero at the target and adds `(target - alive)/10` births a second otherwise
  holds the bottom of the change at ~410 and has it back at 550 within twenty
  seconds. It stays live for 90 s after a crossing, because the change BACK to
  the hole ends at blend 0 where a term scaled by the blend would already be
  gone (measured 465 stars without that window, 595 with it).

Verification is three-legged, because no one tool covers it: `node
tools/test-particles.mjs` for the particle modules (80 checks), `python3
tools/camera_flow.py` for the far field (it renders `starfield.frag` itself
through bhrender.c on surfaceless EGL and cross-correlates two frames in the
shader's own u = r^2/2), and `tools/camera_harness.qml` for the part only QML
runs — the bindings, the envelope and the uniforms `publish()` writes:

    cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
      /usr/lib/qt6/bin/qml tools/camera_harness.qml

Without `QT_ASSUME_STDERR_HAS_CONSOLE` every line it prints is dropped and the
run looks like it printed nothing.

Cost, measured on 2160x3840 with 600 stars (simulation + render + binning, one
core, per frame): 0.164 ms camera against 0.187 ms orbital. The camera regime is
CHEAPER, because there is no innermost orbit to subdivide for.

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

## The event -> particle interface (v10)

His report, ledger 2285: *"right now everything feels like separate pieces, not
part of one system."* Through v9 an event was a shader sprite scheduled BESIDE
the sky — a supernova faded in where no star had ever been, a comet drifted at
the field's own speed with its tail pointing the wrong way. These calls are the
system. Every v10 event reaches the field through them, so a sprite and the
material it is made of share one position, one velocity and one clock by
construction instead of by two pieces of code being kept in step.

| call | what it does |
|---|---|
| `applyImpulse(s, x, y, strength, radiusPx, profile)` | a radial shove on the particles already there |
| `spawnBurst(s, x, y, count, speedRange, traits)` | debris born at a point, integrated like everything else |
| `spawnBody(s, x, y, vx, vy, traits)` | one body under its own proper motion (a comet's nucleus) |
| `brightenNear(s, x, y, radius, gain, decaySec)` | a transient luminosity lift on the stars around a flash |
| `pickStar(s, opts)` / `markNova(s, i, opts)` | the existing particle an event happens TO, and its precursor |
| `flowSpeed(s)` | the field's own mean screen speed, to measure a body against |
| `setCloud(s, cloud)` / `cloudWeight(s, i)` | a cloud the field passes through (the nebula) |
| `driftGroup(s, group, dx, dy)` | translate one event's material as a body |
| `remove(s, i, cause)` | a public death, for an event that consumes a particle |

**`applyImpulse` is bounded by construction.** No particle receives more than
`strength` px/s, so the total momentum delivered is at most `strength x (particles
in reach)`, and the return value is `{count, momentum, peak}` so the caller and
the test can check it. `strength` is clamped to `BOUNDS.impulsePx[1]` = 6000 px/s
and `radiusPx` to eight screen diagonals. Four profiles:

- `blast` (default) — `(1-u)^2 (1+u)`, strongest at the centre, zero at `radiusPx`.
- `shell` — a Gaussian band of `widthPx` at `radiusPx`.
- `front` — the ANNULUS `[fromPx, radiusPx]` only, weighted `(1-r/maxPx)^2(1+r/maxPx)`.
  Called once a frame with the front's own advancing radius, this kicks each
  particle **exactly once**, as the shock reaches it. That is the difference
  between a shell that passes through the field and one drawn over the top of it.
- `flat` — uniform inside `radiusPx`.

### The peculiar-velocity channel

`kickX`/`kickY`/`kickAge`/`kickDrag` are new simulation fields, and they are the
mechanism the whole interface rests on. At `cameraBlend` 1 `step()` rewrites the
stored velocity from the magnification **every substep** (`vx += blend*((nx-x)*invH
- vx)`), so a velocity impulse is discarded on the frame it lands and an event
could not touch the field at all in the one regime he runs. The kick channel
moves the POSITION, after the magnification, and decays as

```
v = v0 * (t0/t)^p          t0 = 0.02 s
```

- `p = 0.6` integrates to `r ~ t^0.4` — **the Sedov law `supernovaState` draws
  the rim with**, which is why the shell and the debris it is made of cannot
  drift apart. Measured live: worst disagreement 1.29x over a whole episode.
- `p = 0` never slows: a body under its own proper motion, i.e. a comet.
- `p` from `debris.relaxSec` (1.05 at the default) is a star shoved by a shock
  and easing back into the flow.

`applyImpulse` splits a kick by `cameraOn(s)`: the orbital share goes into
`vx/vy`, where it is a genuine change of orbit and gravity answers it, and the
camera share goes into the channel. A kick is truncated at 2 px/s (0.07 px in a
30 Hz frame) so the power law's tail cannot run for half a minute at speeds
nothing can see. `s.kickAlive` counts the particles carrying one; while it is
zero the hot loop pays one hoisted boolean. `Appearance.render` adds the channel
to the drawn velocity, so streaks point the right way.

### Transients

A particle spawned by `spawnBurst`/`spawnBody` sets `s.transient[i]`, and that
flag changes four things:

1. **It is not population.** `replenish()` compares `aliveCount - transientCount`
   with the target, so a burst does not stop ordinary births for its own life.
2. **It does not feed the lifetime estimator.** 400 forty-second lives against a
   97 s orbital mean would have quadrupled the birth rate for minutes.
3. **It is exempt from the camera regime** — no magnification, no depth fade, no
   death at the near plane. The camera crosses the whole depth range in sixty
   active seconds, so anything anchored in 3-D leaves the screen before its own
   shell finishes (the v9 note on `supernovaSite` already said so for the site);
   and debris that each drew its own depth magnified by a different factor and
   pulled away from the rim — measured 650 px of debris against a 279 px rim.
   Debris expands by its own velocity and the cloud is translated as one body
   (`driftGroup`) along the far layer's streamline, which is where a supernova is.
4. **It is never a `doom()` victim and never a `pickStar` candidate.**

`p2` carries the event's group id (1 supernova, 2 comet, 3 storm fireball) so
`driftGroup` can move one event's material and leave another's alone.

`Appearance.transient(s, i, traits)` is the optical half, wired up once by the
renderer (`pool.transientBirth`) exactly the way `birthCallback` is: Physics
must not reach into Appearance's arrays. Event material takes its colour from
the physics of the event, never from his palette, which is why this is a
separate entry point and not a flag inside `birth()`.

**Archetype 7, the EMBER.** Supernova debris: hot white on the frame it is born
(a two-frame entrance — an explosion does not fade in over a third of a second),
cooling through yellow (1, 0.90, 0.55) and orange (1, 0.55, 0.22) to a dim red
over its own life while its core shrinks to 55 % and its light falls as
`(1-u)^1.7`. The shader knows nothing about it: it reads flare, near and front
out of the flags and the low three bits are the CPU's alone.

### The atlas

`BOUNDS.capacity` is **3680**, not 3200: the population ceiling is still 3200
and the transient reserve sits on top of it, so an event's debris can never take
a slot a star was going to be born into. `bounds()` adds `debris.maxAlive` to
`maxItems` and returns `maxWide`/`wideSupport` for three instances at the packed
core maximum (12 px) and the deformation streak ceiling — a supernova's
precursor swells to x4.2 and a comet's nucleus is a body, both wider than any
configured star. `Packing.capacity` takes the two new arguments and adds them as
a bounded addition, exactly like the flare and tidal-disruption sets.

All of it is UNCONDITIONAL, for the same reason the tidal-disruption ceiling is:
the atlas is allocated once per configuration and a resize of the sampled
texture cost 13 ms -> 6700 ms per frame on llvmpipe and never recovered.
Measured on his 2880x1800 tablet at the shipped 600 stars: **112 -> 176 rows,
112 -> 176 KiB per canvas**, and the live layout never exceeds it through a
whole supernova (harness check). `debris.maxAlive` 0 gives the rows back.

### The cloud

`setCloud` hands the nebula passage to the field: an ellipse (`x, y, radius,
aspect, angle`), a `drag` and a colour `tint`/`weight`. `cloudStep` runs once per
OUTER step over the live list — it is a per-second effect, not a force, so it
never enters the substep loop — and expresses the drag in each regime's own
terms, because a multiply on the stored velocity only works in one of them:

- hole on: `vx, vy *= exp(-drag*w*dt)`.
- camera on: the cloud **holds the material back in depth**. The approach slows
  by `drag*w` while the particle is inside, which slows it on the screen, keeps
  it smaller and keeps it dimmer — all three depth cues together — and leaves it
  honestly further away once the cloud has gone past. Measured: 89.7 % of a
  control run's speed over twelve seconds inside a `drag` 0.9 cloud, 99.8 %
  outside it.

`Appearance.render` reads the same ellipse for the tint. Both are small on
purpose: it is a passage, not a wall.

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

Simulation fields gained `depthZ` in v8 (the camera's per-star depth, 1 at the
near plane and `motion.camera.depth` at the far one); it is dimensionless, so
`rescale()` leaves it alone, and `counters` gained `passed` for a star that
reaches the end of the camera's depth range.
Simulation fields gained `kickX`/`kickY`/`kickAge`/`kickDrag` in v10 (the
peculiar-velocity channel) and `transient`/`glows`/`cloud`/`nova` alongside them;
`counters` gained `debris`, `impulses`, `kicked` and `consumed`/`supernova`.
`rescale()` scales the kick channel, the glow sources and the cloud with the
other lengths.
Render instances are one flat Float64Array, stride 23: x y vx vy core support
streak r g b lum flags phase p0 age captured id generation halfMajor halfMinor
stretch unitVx unitVy; 21/22 are the unit velocity, resolved once by `render()`
because the binner and the packer both used to recompute it from vx/vy (three
square roots and six divisions per particle per frame for one number); flags is the archetype in the low three bits (v10 adds **kind 7, the
ember**), bit 3 flare, bit 4 near
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
