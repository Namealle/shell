# Starfield v6
`~/.config/caelestia/starfield.json` is watched with 150 ms debounce (XDG_CONFIG_HOME respected).
Missing/invalid JSON, a non-object document or missing screens disables every output; deleted keys restore defaults.
One validated snapshot owns configuration; the shell never writes it. Full schema and defaults:
```json
{
  "screens": [], "density": 1, "driftSpeed": 3.5, "driftDirection": 165,
  "twinkle": 0.22, "flareFraction": 0.003, "brightness": 1, "backgroundColor": "#000000", "edgeLift": 0, "fps": 30,
  "motion": {"mode": "radial", "radialSpeed": 6, "centreWander": 0.012, "zoom": 0.003, "reversals": false, "wander": 0.8, "rotation": 0.5},
  "variety": {"enabled": true, "seed": 1}, "variables": {"fraction": 0.006},
  "palette": {"colors": ["#A8E6BD","#FFF0AD","#F2B1B1","#ADCFFF","#F4B9DA","#FFD0A8","#CFB8F4","#A8E4DE"],
    "ids": ["green","yellow","red","blue","pink","orange","purple","teal"], "weights": [1,1,1,1,1,1,1,1],
    "lightness": 0.45, "saturationCap": 0.28, "mix": 0.32, "variationWhite": [0,0.10], "foregroundWhite": 0.35},
  "archetypes": {"weights": {"steady":0.82,"pulsator":0.10,"decayer":0.04,"glint":0.02,"wanderer":0.015,"binary":0.005},
    "farWeights": {"steady":0.97,"pulsator":0.03}, "pulsator": {"periodSec":[6,40],"amplitude":[0.08,0.22]},
    "decayer": {"lifeSec":[20,90],"fadeInSec":[3,8]}, "glint": {"everySec":[18,65],"widthSec":[0.8,2],"gain":0.18},
    "wanderer": {"periodSec":[30,100],"offsetPx":8}, "binary": {"periodSec":[12,45],"separationPx":[1.5,5]},
    "colorShifter": {"enabled":false,"share":0.005,"periodSec":[120,360]}},
  "comet": {"enabled":true,"interval":[900,1800],"paletteMix":0.35,"families":{
    "fast":{"weight":0.15,"durationSec":[4,9],"gain":0.55,"tailShortSide":[0.04,0.08],"bendShortSide":[0,0]},
    "slow":{"weight":0.50,"durationSec":[30,65],"gain":0.26,"tailShortSide":[0.20,0.32],"bendShortSide":[0,0]},
    "bent":{"weight":0.30,"durationSec":[12,28],"gain":0.38,"tailShortSide":[0.08,0.18],"bendShortSide":[0.02,0.06]},
    "pulsating":{"weight":0.05,"durationSec":[20,40],"gain":0.32,"tailShortSide":[0.12,0.22],"bendShortSide":[0.02,0.06]},
    "fragmenting":{"weight":0,"durationSec":[8,16],"gain":0.38,"tailShortSide":[0.08,0.16],"bendShortSide":[0.02,0.06],"cooldownSec":7200},
    "spiral":{"weight":0,"durationSec":[18,35],"gain":0.25,"tailShortSide":[0.08,0.16],"bendShortSide":[0,0.06],"cooldownSec":14400}}},
  "meteors": {"enabled":true,"interval":[45,120],"companionChance":0.04,"fireballChance":0.01,"paletteMix":0.25,"families":{
    "straight":{"weight":0.75,"durationSec":[0.7,1.3],"gain":0.85,"tailShortSide":[0.08,0.14],"bendShortSide":[0,0]},
    "curved":{"weight":0.20,"durationSec":[0.9,1.7],"gain":0.80,"tailShortSide":[0.04,0.10],"bendShortSide":[0.005,0.02]},
    "skipping":{"weight":0.05,"durationSec":[1.2,2.2],"gain":0.70,"tailShortSide":[0.08,0.14],"bendShortSide":[0,0]}}},
  "satellites": {"enabled":true,"interval":[240,480]},
  "events": {"headCap":3,"phenomenonCap":2,"dramaCooldownSec":4500,
    "shower":{"enabled":true,"everyHours":[2,5],"durationSec":[30,60],"gain":0.60},
    "slowWanderer":{"enabled":true,"everyHours":[2,6],"durationSec":[180,360],"gain":0.40}},
  "phenomena": {}, "blackHole": {}, "particles": {}, "particlesEnabled": true,
  "reactive": {"enabled":true,"contextScope":"perScreen","processPresenceWeight":0.35,"paletteBudget":0.45,
    "birthTauSec":60,"liveTauSec":90,"maxChangePerSec":0.005,
    "matchers":[
      {"id":"htb","class":"^zen$","title":"\\bHTB\\b|Hack\\s*The\\s*Box|hackthebox\\.(com|eu)","flags":"i"},
      {"id":"steam","class":"^steam$","flags":"i"}, {"id":"game","class":"^steam_app_[0-9]+$","flags":"i"},
      {"id":"terminal","class":"^(foot|footclient)$"}, {"id":"agentWindow","class":"^(foot|footclient)$","title":"^[✳◑]"}],
    "rules":[
      {"signal":"htb","add":{"palette":{"green":0.35,"teal":0.08}}},
      {"signal":"rain","add":{"archetypes":{"decayer":0.025,"pulsator":-0.02},"calm":0.12,"twinkle":-0.08}},
      {"signal":"night","add":{"palette":{"blue":0.16,"purple":0.10},"calm":0.12,"flow":-0.08,"meteor":-0.12}},
      {"signal":"agent","add":{"archetypes":{"wanderer":0.007},"palette":{"purple":0.16,"teal":0.06}}},
      {"signal":"load","add":{"archetypes":{"pulsator":0.04}}}, {"signal":"heat","add":{"palette":{"orange":0.18,"red":0.08}}},
      {"signal":"media","add":{"archetypes":{"pulsator":0.01}}}, {"signal":"idle","add":{"calm":0.08,"meteor":-0.08}},
      {"signal":"workspaceActivity","enabled":false,"add":{"archetypes":{"wanderer":0.003}}},
      {"signal":"network","enabled":false,"add":{"archetypes":{"glint":0.002}}},
      {"signal":"notifications","enabled":false,"add":{"archetypes":{"pulsator":0.003}}},
      {"signal":"gpuLoad","add":{"hole":{"activity":0.25}}}, {"signal":"heat","add":{"hole":{"warmth":0.15,"brightness":0.20}}},
      {"signal":"agent","add":{"hole":{"structure":0.10}}}, {"signal":"night","add":{"hole":{"brightness":-0.15}}},
      {"signal":"agentFalling","enabled":false,"add":{"events":{"nova":0.6}}}, {"signal":"heat","enabled":false,"add":{"events":{"redGiant":0.4}}},
      {"signal":"gpuLoad","enabled":false,"add":{"events":{"tde":0.3}}}, {"signal":"night","enabled":false,"add":{"events":{"starBirth":0.3,"supernova":-0.3}}}]}
}
```
The eight v6 event families are omitted above only for length: each defaults exactly to the calm block below, so an absent family *is* that block. `phenomena` is
FORWARDED like `blackHole`/`particles` (an absent key keeps the renderer's default); `events` families are defaulted here. Calm defaults, written out to paste:
```json
"events": {"headCap":3,"phenomenonCap":2,"dramaCooldownSec":4500,
  "starBirth":{"enabled":true,"everyMinutes":[20,45],"durationSec":[180,360],"gain":0.22,"condenseSec":[40,90],"haloPx":[18,4],"paletteMix":0.30},
  "nova":{"enabled":true,"everyMinutes":[25,50],"riseSec":[1.5,3],"holdSec":[0.5,1.5],"decaySec":[25,60],"gain":0.45,"shellShortSide":[0.02,0.04],"shellGain":0.12,"paletteMix":0.30},
  "redGiant":{"enabled":true,"everyMinutes":[45,90],"durationSec":[240,480],"gain":0.28,"swellSec":[90,150],"collapseSec":[45,75],"nebulaShortSide":0.015,"nebulaGain":0.06},
  "supernova":{"enabled":true,"everyHours":[1.5,3],"riseSec":[0.8,1.5],"holdSec":[0.5,1.5],"decaySec":[90,240],"gain":0.70,"remnantSec":[180,360],"shellShortSide":[0.06,0.11],"shellGain":0.10,"echoGain":0.04,"echoDelaySec":[60,120],"hypernovaShare":0.15,"hypernovaGain":0.78,"hypernovaCooldownSec":21600,"paletteMix":0.35},
  "kilonova":{"enabled":false,"minSpacingSec":3600,"maxPerHour":1,"flashSec":0.4,"gain":0.55,"ringShortSide":0.03,"ringSec":[8,15]},
  "pulsar":{"enabled":false,"everyHours":[2,4],"durationSec":[240,600],"periodSec":[0.8,2],"gain":0.30,"floorFraction":0.60,"edgeSec":0.12},
  "gammaBurst":{"enabled":false,"everyHours":[4,12],"flashSec":[0.5,0.8],"gain":0.45,"beamShortSide":[0.10,0.18],"afterglowSec":[30,90],"cooldownSec":14400},
  "satelliteGlint":{"enabled":true,"gain":2.2,"widthSec":[1.5,3]}},
"phenomena": {"tde":{"enabled":true,"everyMinutes":[40,90],"streakPx":[60,140],"stretchSec":[6,12],"fragments":[4,8],"diskFlash":0.15},
  "microlensing":{"enabled":true,"gainCap":2.5}, "moods":{"clearing":0.15,"nebular":0.15}}
```
Lively (notable every ~3 min, dramatic every ~35 min). Same blocks with these keys replaced; everything else keeps the calm value:
```json
"events": {"dramaCooldownSec":2100, "starBirth":{"everyMinutes":[10,20]}, "nova":{"everyMinutes":[8,18]},
  "redGiant":{"everyMinutes":[20,35]}, "supernova":{"everyHours":[0.67,1.33]},
  "pulsar":{"enabled":true,"everyHours":[0.75,1.5]}, "gammaBurst":{"enabled":true,"everyHours":[6,6]}},
"phenomena": {"tde":{"everyMinutes":[15,30]}}
```
`blackHole` and `particles` are FORWARDED, not defaulted: only keys the file carries reach the renderer, so an absent
key keeps the renderer's own default and a `preset` keeps supplying its fallbacks. Recommended for this machine:
```json
"blackHole": {"enabled": true, "preset": "target"}, "particles": {}
```
Paste your colours here (replace this object's `colors`; IDs are optional, weights default to 1):
```json
"palette": {"colors":["#FFFF00","#00FF00"],"ids":["sun","leaf"],"weights":[1,1]}
```
Palette formula on load, RGB channels 0–1 (black becomes white; grey/white remain achromatic):
```text
c = c / max(c.r,c.g,c.b)
c = c * (1-lightness) + white * lightness
c = mix(white,c,min(1,saturationCap/max(max(c)-min(c),1e-9)))
```
Thus yellow becomes [1,1,0.72], green [0.72,1,0.72]; even already-pastel inputs soften again. No unlisted hue is generated.
Accept up to 16 valid #RRGGBB entries; empty/wrong-type colors disables tint. Invalid entries warn with only their original zero-based index.
Survivors keep their IDs/weights; numeric rule keys address original colors indices, so a dropped entry never retargets a rule. Missing custom IDs stay unnamed.
IDs: unique letters followed by letters/digits/underscore, ≤48 characters; constructor/prototype excluded. Bad/duplicate IDs become unnamed.
Palette weights 0–1000000 normalize; all-zero base becomes uniform. lightness/whitening 0–1, saturationCap 0–0.28, mix/event paletteMix 0–0.45.
`paletteWeights[i]=max(0,normalizedBase[i]+sum(signal*add[i]))`, then normalize; all-zero conditional weights fall back to the normalized base.
Rule add accepts `palette:{idOrIndex:add}`, `archetypes:{steady|pulsator|decayer|glint|wanderer|binary:add}`, `hole:{activity|warmth|brightness|structure:add}`.
`events:{family:add}` biases a SCHEDULE and never triggers an event: families meteors/comet/satellites/shower/slowWanderer/starBirth/nova/redGiant/supernova/kilonova/pulsar/gammaBurst/tde, add −1–1, multiplier 2^−sum on the NEXT interval only, clamped 0.5×–2× (positive = sooner). The four shipped examples are off.
Scalar adds: green/violet/warm (legacy), calm/twinkle/brightness/flow/meteor, mix; all coefficients −1–1. Arrays replace defaults, including empty rules/matchers.
Semantic IDs resolve exactly first, then green/yellow/red/blue/pink/orange/purple/teal choose nearest listed hue at 120/60/0/240/330/30/270/180° within 30°.
Legacy green/violet/warm always choose nearest hue at 120/270/30° within 30°; absent hues contribute nothing. Custom explicit IDs survive reordering.
Archetype base weights 0–1 normalize (all-zero restores defaults); adds change probability points, steady takes the remainder; explicit steady adds renormalize.
Total nonsteady probability caps at 25%, scaled proportionally. Far ineligible weights return to steady; renderer caps far pulsator amplitude at 0.08.
Targets neutral: calm/live/hole 0.5; mix comes from palette, capped by legacy paletteBudget ≤0.45. Hole targets clamp 0–1; geometry never reacts to load.
Archetype bounds: pulsator period 6–360 s/amplitude 0–0.22; decayer life 20–600 s/entrance 3–20 s; glint every 18–3600 s/width 0.8–2 s/gain ≤0.18.
Wanderer period 30–600 s/offset ≤8 px; binary period 12–360 s/separation 0–5 px; shifter period 120–3600 s/share ≤0.005, disabled initially.
Family weights 0–1 divide scheduled starts; duration stays within the listed range, gain/tail/bend within 0–listed maximum; ranges are ordered two-number arrays.
Fragmenting share ≤2%, cooldown ≥7200 s; spiral cooldown ≥14400 s (both ≤604800). Event headCap 1–3; hourly spacing 2–168 h; episode duration/gain bounded as shown.
Event intervals allow up to 86400 s; minima: meteor 3, comet 60, satellite 45. Companions/fireballs 0–1; three is the hard head cap, normally two (renderer).
v6 adds phenomenonCap 1–2 (long faint slots, separate from headCap and never spilling into it) and dramaCooldownSec 600–86400 across all dramatic families.
Schedules: `everyMinutes` ordered pair 1–1440, `everyHours` ordered 0.25–168. Every `gain` is 0–the value listed in the calm block; shells/rings/nebulae ≤0.15 short
sides, GRB beams ≤0.25, satelliteGlint gain is a 1–4 multiplier on an existing pass; durations 10–1800 s, sub-envelopes (rise/hold/decay/swell/collapse/echo/afterglow)
0–600 s, remnant ≤1800 s, cooldowns 600–604800 s, hypernovaShare 0–1, kilonova maxPerHour 0–4, `haloPx` is a from–to span 0.5–64 px and may descend.
Anti-strobe floors are VALIDATOR-ENFORCED, not advice: `riseSec` ≥0.8 s (nova and supernova), pulsar `periodSec` ≥0.8 s, `floorFraction` ≥0.5 (the trough never drops below half the peak, so a pulsar modulates instead of blinking), `edgeSec` ≥0.10 s, glint `widthSec` ≥0.5 s. A value under a floor is rejected, not raised.
Every v6 key REJECTS instead of repairing — a bad type, an out-of-range number, an inverted pair or an unknown key inside a family drops with an index-only warning and that key's documented default applies — while the v4 keys beside them (headCap, shower, slowWanderer) keep their v4 clamping, unchanged.
`phenomena` is a closed sparse object like `particles`: tde{enabled, everyMinutes 1–1440, streakPx [0,160] — the maximum feeds the one-time particle atlas ceiling, see PARTICLES.md — stretchSec [1,120], fragments [1,16] (renderer rounds), diskFlash 0–0.5}, microlensing{enabled, gainCap 1–3}, moods{clearing, nebular 0–1}.
RENDERER, v6 so far: `microlensing` multiplies far-layer stars by clamp(1/|det J|, 1, gainCap) wherever the shader already filters them through the lens Jacobian — inside `bhGeometry.y` only, no scheduler, no slot, ~4 ALU. A background star drifting past the
hole brightens and returns over the tens of seconds the drift takes. It applies whatever `particlesEnabled` is (the far field is shared); `"microlensing": {"enabled": false}` restores the v5 far field exactly. `moods.clearing`/`moods.nebular` add mood kinds 4 and 5
to the existing 900 s slots, taking their share off the top so the four v5 kinds keep their proportions and a zero share reproduces v5's distribution: clearing thins far dust by 0.07 acceptance and warms the middle layer, nebular doubles the tinted middle-layer
share. Both interpolate the two outcomes by the eased weight rather than moving a threshold, so no star switches on a frame. `events.satelliteGlint` modulates the existing satellite slot's gain by a birth-frozen Gaussian in time (gain 1–4, width 0.5–10 s, placed in
the middle half of the pass) — no new slot, no new uniform, no shader change. `starBirth`, `nova`, `redGiant`, `supernova` and `pulsar` are DRAWN, as kinds 5–9 on two phenomenon slots. They share one shader kernel (style 3, radial: core + halo + ring + echo ring), so they differ only in envelope, colour, size and schedule:
head=(x, y, coreSigmaPx, peak), shape=(haloSigmaPx, ringGain, ringWidthPx, ringRadiusPx), tail01=(echoRadiusPx, echoGain, haloGain, coreGain). Each component's gain is absolute and is divided by the slot peak, so a nova's shell outlives the core that threw it and a
light echo outlives the shell. Placement is REJECTED, never clamped, inside 1.6×the lensing reach (events composite after the disk and are not shadow-masked) or within 0.05 short sides of an edge; eight attempts, then the episode is skipped. Slots 3–4 carry five
vectors rather than a transient slot's seven (160 B, UBO reflection 1360 → 1520 B of 16384); two idle slots measured no cost at all (19.8 % of a core against 20.6 % for v5 on the same output, GPU 17.8 % against 18.4 %), so the brainstorm's optional `phenomenaActive`
gate is not needed. Slot ownership is STICKY: an episode claims a slot only in its first 0.25 s and keeps it until it ends, so nothing can appear mid-life at whatever gain it had reached; scheduling already keeps at most `phenomenonCap` overlapping. The two classes
never spill into each other — transient heads reserve only against transients, phenomena only against phenomena. Combined phenomenon gain is capped at 0.55 outside a supernova flash, the exemption easing away over three seconds rather than switching.
`phenomena.tde` is DRAWN, by the particles alone — no slot, no uniform, no shader change; PARTICLES.md owns it. One doomed particle's packed streak is ramped to `streakPx` over `stretchSec` while its core dims and reddens, it splits into `fragments` siblings
along its own orbit, and its head's trail then eases back over six seconds. `streakPx` is clamped to 120 px by the renderer whatever the service validates up to 160: 120 is what the packed streak byte carries. `diskFlash` rides the hole's brightness channel for 20 s.
`kilonova` and `gammaBurst` are validated and forwarded but NOT yet drawn (they need the pending-event queue and a beam style).
Black hole: `modules/background/BLACKHOLE.md` owns every default, the taste caps and the shader's own limiters; missing blackHole is disabled.
Flat bounds: size 0.01–0.2 short sides, tilt 1–35° (the renderer accepts 80, only 35 is silhouette-verified), intensity/warmth/halos 0–1,
spin 0–2 (pattern speed), inner 3–6 rs, outer max(inner+0.5, 3.5)–12 rs, beam 0–0.2, photonWidth 0.001–0.02 shadow radii,
legacy structure 0–0.08 — that cap is the legacy field's alone and never applies to `disk.detail` — tiltWander 0–1°, transition 30–300 s.
v4 adds preset `""`/`"target"` (fallbacks only: any explicit key wins, and an explicit `disk`/`photon` object REPLACES the preset's, never merges),
footprintCap 0.01–0.12 (declared budget), diskCap/photonCap 0.10–1 (the limiters the shader enforces).
`disk`: detail 0–0.85, seed integer 0–65535, rotationSign −1/+1 (0 reads as +1), exposure 0.5–2,
streaks{octaves 1–3, radialScale 0.5–2, innerCyclesPer4096 16–128, warp 0–0.25, grain 0–0.08}, knots{density 0–0.06, gain 0–0.5},
embers{count 0–32, radiusRs 0.004–0.025, trailSec 0–0.6, gain 0–0.06}, doppler{preset film/physical, strength 0–1},
hue{innerTemperature 4200–10000 K, outerTemperature 1000–2800 K, warmth 0–1, whiteness 0–1}, glow{gain 0–0.008, radiusPx 0.25–2.5},
arcs{gain 0–0.02, radiusRh 1.2–2.6, spacingRh 0.2–1, count 0–2}. `photon`: mode shared-field/off, widthPx 0.1–0.75, gain 0–1.5, textureStrength 0–1.
Hole numbers clamp into range; wrong types and unknown nested keys drop with an index-only warning. Visual integration is renderer-owned.
Particles replace the procedural middle/near layers; `modules/background/PARTICLES.md` owns the physics, the atlas and the renderer's own clamping.
`"particlesEnabled": false` restores the v3 shader path exactly; far dust, events and the disk stay procedural either way.
v6 deforms particle stars continuously: one 0–1 scalar per star from the local tidal field (mass/r^3), its direction relative to the hole and its time
since capture, relaxed over 0.45–1.9 s per star, driving the streak exposure, a radial squash and the curved trail together. Birth-frozen onset, gain and
rate keep two stars at the same radius different; `blackHole.mass` scales reach and strength; a disabled hole fades it to nothing. No key changes.
v7 anchors every boundary a star can reach to the VISIBLE hole (Rv), not to Rh. Rh is the dynamical scale and the shadow/photon-ring radius; the
drawn object is the disk and its arcs, which reach 3.900 Rh under the `target` preset, so the swallow radius, the capture band, the spiral target
and the tidal reach all sat inside the picture and 66 % of the particle ink was rendered on top of the hole. Rv is derived in `Physics.visibleRadius`
from `blackHole.diskInnerRs`/`diskOuterRs` and `disk.arcs`, mirroring bhOuter()/bhImpact()/bhArcReach() in `shaders/blackhole.glsl`: change them
together. Two keys change unit with it — `capture.radius` (Rh -> Rv, default [1.06,1.45]) and `streak.bendRadiusRh` -> `streak.bendRadiusRv`
(default 1.45). No shader, uniform or atlas change, so no `.qsb` rebake.
Closed schema, every key optional: population{near, middle} integers 0–3200 with near+middle ≤3200 (defaults 120/480, or 600/1500 when
stressPreset is true), stressPreset boolean, vref 10–600 px/s, launch{plunge, miss, wide 0–1 (the renderer normalizes the three),
betaBound [0.10,0.99], unboundShare 0–1, betaUnbound [1.001,2], handedness 0–1}, capture{radius [1.02,6] Rv, gamma 0–2 /s,
spiralSec [5,240] s}, epsilonRh 0.01–0.20, substeps integer 4–32, streak{exposureSec 0–0.10, maxPx 0–32, bendRadiusRv 0–6},
sizes{nearPx, middlePx, capturedPx [0.25,12] px}, safetyLifeSec [30,600] s; pairs are ordered two-number arrays.
Malformed particle values are REJECTED, not repaired: a bad type, an out-of-range number, an inverted pair, a fractional integer or an
over-budget population is dropped with an index-only warning and the renderer's documented default applies instead.
V2 bounds: density/brightness 0–3, driftSpeed 0–30, direction ±360°, twinkle/edgeLift 0–1, flare ≤0.025, fps 1–60 rounded; opaque #RRGGBB background, default pure black.
Motion: radial/drift, radialSpeed 0–26 (device px/s at shortSide/2 on 2160 short side), centreWander ≤0.05 short sides; zoom ≤0.15 (drift default 0.025), wander 0–2, rotation 0–3°.
Variety seed is integer 0–2147483647, variable fraction 0–0.05; numeric wrong types use defaults, finite values clamp. Screen names exact, nonempty ≤128 characters, deduplicated.
Matchers/rules: first 32 entries, matcher IDs unique and built-in signals reserved except agentWindow. Required class/optional title regex ≤256 chars; flags i/m, no duplicates.
Backreferences/lookarounds/repeated groups are rejected; invalid matchers or unknown-signal rules disable only that entry. Compile only on config reload.
Signals: cpuLoad/cpuHeat/gpuLoad/gpuHeat/vram/ram/network/rain/wind/humidity/temperature/weatherNight/night/media/idle/agentProcess/agentWindow/notifications and matcher IDs.
Derived load/heat = CPU/GPU maxima; cpuLoadRising/gpuLoadRising/loadRising are positive slopes; memoryPressure uses RAM/VRAM; agent=max(agentWindow,processPresenceWeight*agentProcess), weight 0–1.
agentFalling is the mirrored negative slope of whichever term owns that maximum, 0 while agent is steady or rising — "a long build finished", not "an agent started".
Workspace activity counts only workspacev2, adds 0.15 up to 1, decays with τ=120 active s; rule off initially. Notifications have no source; no raw input or new network inspection.
Gradualness: source smoothing/freshness remains; stale inputs fade over 120 s, weather stale at 3 h. Targets filter in renderer: birth 60 s, live 90 s, events 120 s, max change 0.005/s.
The frozen renderer contract keeps filter metadata at these constants; hole filtering is 120 s, max change 0.002/s. Enabling/disabling the hole takes ≥30 active seconds.
New births freeze palette, archetype and parameters (including colour-shifter trajectory); event edits affect future schedules. Renderer owns descriptor history and phase continuity.
Glue passes archetypes/farWeights plus `archetypeParams.palette.{variationWhite,foregroundWhite}`. `eventFamilies` is the single object Background.qml forwards: comet,
meteors, shower, slowWanderer, the eight v6 families, `phenomena`, `phenomenonCap` and `dramaCooldownSec`. Only headCap travels separately, as `eventHeadCap`.
Privacy: match class first, read at most 512 title chars locally; retain only category strengths, never titles/URLs/history/media metadata/notification content. No title hashing or transmission.
Context: mapped active/open-special/pinned windows on that output; focused weight 1, other visible 0.6, hidden/minimized 0. Visibility is approximate, not pixel occlusion.
`ambient dump` includes rounded birth/live, paletteWeights[16], archetypeWeights[6], mix/calm/hole[4], eventBias{family:multiplier}, numeric signals and availability; no titles.
Pause: lock or visible fullscreen>1 freezes that output's targets and renderer active time/history, retaining Loader; other outputs continue. All paused stops polling and releases ServiceRefs.
Config watching/event subscriptions remain; paused profiles preserve all fields through edits. Suspend resets baselines/derivatives with no catch-up; workspace activity freezes while paused.
`background.enabled` still gates windows. Density is static, never reactive. Keep backgroundColor #000000 for exact-black empty pixels.
