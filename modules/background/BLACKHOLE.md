# Starfield v3 black hole

Single-pass Schwarzschild transfer model, rs=1, static observer D=20 rs.
Rh=size×shortSide; critical b=3√3/2; focal=7.83442197238 Rh; RL=4 Rh.
Offline float64 RK4 solves u''+u=1.5u². No per-pixel integration.
Disk intersections are the first two positive equatorial-plane crossings.
The camera model is Y-up; helpers convert Qt's physical Y-down pixels.

## JSON and state
Missing blackHole means enabled=false. Recommended preset enables it.
Defaults: size=.075, tilt=14 degrees, intensity=.65, warmth=.5, spin=1,
diskInnerRs=3, diskOuterRs=8, beamStrength=.15, haloUpper=.55, haloLower=.35,
photonWidth=.006, structure=.05, tiltWander=0, transitionSec=30.
spin is pattern speed, not Kerr spin; changes preserve the integrated phase.
Input time is the renderer's active seconds (unwrapped preferred; 4096 wrap works).
running=false freezes phase, envelope and ambient filtering; resume has no catchup.
An enable/disable change traverses a quintic envelope in 30 active seconds.
Ambient activity/warmth/brightness/structure use tau=120 s, maximum slew .002/s.
Phases use integer harmonics of a double-precision CPU base modulo 2π.

## LUT and build
Run `python3 modules/background/tools/blackhole_lut.py` from the repo root.
PNG: 1024×262 RGBA8, 1,073,152 raw bytes; four 256-column b partitions.
Partitions: [.025,.95bc], [.95bc,bc−epsilon], [bc+epsilon,1.25bc], [1.25bc,12].
Middle partitions use quadratic concentration at bc; epsilon=1e−7 bc.
Rows 0–255: u at phi=row×2π/255. Rows 256/257: terminal/turning phi divided by 32.
Row 258: capture flag. Row 259: b/12. Row 260: repeated uint16 sentinels.
Row 261: (signed sourceRadius/Rh+64)/128; B holds 8-bit hemisphere/order validity.
Each scalar uses R=high byte, G=low byte; alpha=255; other blue bytes are zero.
Decode `(floor(R*255+.5)*256+floor(G*255+.5))/65535`, then apply its row range.
Interpolate decoded scalars manually; NEVER round filtered packed bytes.
Sentinel words: 0,1,255,256,32767,32768,65280,65535. PNG has no colour tags.
BlackHole.bhTransfer is an Image: smooth=false, mipmap=false, colour space unset.
`supportsAtlasTextures:false` belongs to the consuming ShaderEffect, not Image.
Bake preview with qsb --glsl "100 es,120,150" --hlsl 50 --msl 12.

## Integration recipe (renderer owner)
Keep one ShaderEffect; bind bhCentre, bhGeometry, bhDisk, bhLook, bhHalo,
bhPhase, bhCaps and bhTransfer from the BlackHole state provider.
Add `#extension GL_GOOGLE_include_directive : require` after #version.
Inside existing `buf`, define BH_UNIFORMS, include blackhole.glsl, then undefine it.
Keep block instance `ubuf`; its `ubuf.bhDisk` coexists with function `bhDisk()`.
Include blackhole.glsl again after the block, before stars()/main().
The second include declares `layout(binding=1) uniform sampler2D bhTransfer;`.
Reserve binding 1; move any descriptor sampler to a free binding if necessary.
Existing physical `resolution` is required. bhGeometry=(Rh,RL,sinTilt,cosTilt).
bhDisk=(inner,outer,positionAngle,photonWidthPx); bhHalo.w is the enable envelope.
bhCaps=(disk .25, photon .30, footprint .03, structure .08).
FAR: evaluate equal-area row/sector and candidate distance at bhWarpBackground(pixel,w).
w is distortion weight (zero outside RL), NOT a visibility multiplier.
Recompute the angle from the mapped coordinate; preserve candidate ID/salt/history.
Mask FAR starlight with 1−bhShadowMask(pixel); reject off-domain sources, never repeat.
bhJacobian is the far mapping derivative: Sigma=sigma²I+J×transpose(J)/12.
Evaluate it only after candidate rejection. No determinant/flux multiplier.
Unrepresented hemispheres and unresolved higher orders fade out in the transfer.
MIDDLE/NEAR: use bhWarpMaterial(pixel,rimLife); its source radius is sqrt(r²−Rh²).
Replace central rejection/fade for new capture cohorts; do not multiply the old fade.
Candidate life uses smoothstep(Rh,1.08Rh,sqrt(sourceStarRadius²+Rh²)); rimLife guards pixels.
Use the analogous material mapping derivative for its footprint; bhJacobian is FAR-only.
Converge depth centres to the shared bhCentre with the envelope; recalculate birth padding.
Retire 480–600 flow-second expiration only for NEW capture cohorts; retain history <7560 s.
Keep already-born lifetime policies so migration never resurrects dead identities.
bhDisk returns premultiplied LINEAR emission/coverage, near crossing over farther crossing.
Composite disk.rgb+(1−disk.a)×background; shadow-mask background BEFORE the disk.
Convert display-encoded stars to linear for this composition, then encode output once;
apply existing gated dither afterward, preserving exact zero outside all supports.
Schedule each meteor/comet as foreground or capture at birth. CPU cubic Bézier capture
ends inside Rh; use four bounded tail segments and fade at the rim, without a flash.
Never recategorize an active event in response to an ambient rule change.

## Fidelity and caps
Recognizable shadow, upper/lower disk images, warm surface and thin photon ring.
No Kerr frame dragging, film-grade detail, lens treatment or DNGR beam filtering.
Rim capture is stylized; lens displacement has an artistic C² taper at 3.2–4 Rh.
The geometric disk extends to 8 rs; emission ends at inner+.66(outer−inner)=6.3 rs,
with a .9 rs compact thermal taper. This explicit art adjustment meets the area cap.
Disk luminance ≤.25 linear, photon region ≤.30; beam factors .8–1.2; structure ≤±.08.
At defaults, measured hole footprints: portrait 2.202%, tablet 2.452%, ultrawide 1.648%.
Size/tilt/radius overrides need a new footprint check. Measurements and all fixtures:
`/tmp/starfield-dev/bh3/report.md`; production integration/lifecycle remain the renderer's gate.
