# Starfield v8
`~/.config/caelestia/starfield.json` is watched with 150 ms debounce (XDG_CONFIG_HOME respected).
Missing/invalid JSON, a non-object document or missing screens disables every output; deleted keys restore defaults.
One validated snapshot owns configuration; the shell never writes it. Full schema and defaults:
```json
{
  "screens": [], "density": 1, "driftSpeed": 3.5, "driftDirection": 165,
  "twinkle": 0.22, "flareFraction": 0.003, "brightness": 1, "backgroundColor": "#000000", "edgeLift": 0, "fps": 30,
  "motion": {"mode": "radial", "radialSpeed": 6, "centreWander": 0.012, "zoom": 0.003, "reversals": false, "wander": 0.8, "rotation": 0.5,
    "camera": {"enabled": "auto", "direction": "out", "speed": 6, "depth": 16, "dustFlow": 3, "roll": 0.15, "wander": 0.35, "sizeGain": 0.55}},
  "variety": {"enabled": true, "seed": 1}, "variables": {"fraction": 0.006},
  "palette": {"colors": ["#A8E6BD","#FFF0AD","#F2B1B1","#ADCFFF","#F4B9DA","#FFD0A8","#CFB8F4","#A8E4DE"],
    "ids": ["green","yellow","red","blue","pink","orange","purple","teal"], "weights": [1,1,1,1,1,1,1,1],
    "lightness": 0.45, "saturationCap": 0.28, "mix": 0.32, "variationWhite": [0,0.10], "foregroundWhite": 0.35},
  "archetypes": {"weights": {"steady":0.82,"pulsator":0.10,"decayer":0.04,"glint":0.02,"wanderer":0.015,"binary":0.005},
    "farWeights": {"steady":0.97,"pulsator":0.03}, "pulsator": {"periodSec":[6,40],"amplitude":[0.08,0.22]},
    "decayer": {"lifeSec":[20,90],"fadeInSec":[3,8]}, "glint": {"everySec":[18,65],"widthSec":[0.8,2],"gain":0.18},
    "wanderer": {"periodSec":[30,100],"offsetPx":8}, "binary": {"periodSec":[12,45],"separationPx":[1.5,5]},
    "colorShifter": {"enabled":false,"share":0.005,"periodSec":[120,360]}},
  "comet": {"enabled":true,"interval":[300,900],"paletteMix":0.35,"families":{
    "fast":{"weight":0.18,"durationSec":[4,9],"gain":0.95,"tailShortSide":[0.06,0.11],"bendShortSide":[0,0]},
    "slow":{"weight":0.34,"durationSec":[30,65],"gain":0.70,"tailShortSide":[0.20,0.32],"bendShortSide":[0,0]},
    "bent":{"weight":0.28,"durationSec":[12,28],"gain":0.80,"tailShortSide":[0.12,0.20],"bendShortSide":[0.02,0.06]},
    "pulsating":{"weight":0.08,"durationSec":[20,40],"gain":0.75,"tailShortSide":[0.14,0.24],"bendShortSide":[0.02,0.06]},
    "fragmenting":{"weight":0.02,"durationSec":[8,16],"gain":0.80,"tailShortSide":[0.08,0.16],"bendShortSide":[0.02,0.06],"cooldownSec":7200},
    "spiral":{"weight":0.10,"durationSec":[18,35],"gain":0.65,"tailShortSide":[0.08,0.18],"bendShortSide":[0,0.06],"cooldownSec":14400}}},
  "meteors": {"enabled":true,"interval":[45,120],"companionChance":0.04,"fireballChance":0.01,"paletteMix":0.25,"families":{
    "straight":{"weight":0.72,"durationSec":[0.7,1.3],"gain":0.85,"tailShortSide":[0.08,0.14],"bendShortSide":[0,0]},
    "curved":{"weight":0.20,"durationSec":[0.9,1.7],"gain":0.80,"tailShortSide":[0.04,0.10],"bendShortSide":[0.005,0.02]},
    "skipping":{"weight":0.08,"durationSec":[1.2,2.2],"gain":0.70,"tailShortSide":[0.08,0.14],"bendShortSide":[0,0]}}},
  "satellites": {"enabled":true,"interval":[150,330]},
  "events": {"headCap":3,"phenomenonCap":3,"phenomenonGainCap":1.6,"dramaCooldownSec":900,"rateScale":1,
    "shower":{"enabled":true,"everyHours":[0.75,2],"durationSec":[30,60],"gain":0.60},
    "slowWanderer":{"enabled":true,"everyHours":[0.75,2],"durationSec":[180,360],"gain":0.75}},
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
The nine event families are omitted above only for length: each defaults exactly to the block below, so an absent family *is* that block. `phenomena` is
FORWARDED like `blackHole`/`particles` (an absent key keeps the renderer's default); `events` families are defaulted here. Defaults, written out to paste:
```json
"events": {"headCap":3,"phenomenonCap":3,"phenomenonGainCap":1.6,"dramaCooldownSec":900,"rateScale":1,
  "starBirth":{"enabled":true,"everyMinutes":[8,16],"durationSec":[80,170],"gain":0.60,"condenseSec":[25,55],"haloPx":[40,9],"paletteMix":0.30},
  "nova":{"enabled":true,"everyMinutes":[6,13],"riseSec":[1.2,2.4],"holdSec":[0.6,1.6],"decaySec":[20,45],"gain":0.90,"shellShortSide":[0.035,0.06],"shellGain":0.26,"paletteMix":0.30},
  "redGiant":{"enabled":true,"everyMinutes":[18,34],"durationSec":[140,280],"gain":0.60,"swellSec":[45,80],"collapseSec":[30,55],"nebulaShortSide":0.030,"nebulaGain":0.16},
  "supernova":{"enabled":true,"everyHours":[0.35,0.8],"riseSec":[0.8,1.5],"holdSec":[0.6,1.6],"decaySec":[50,130],"gain":1.35,"remnantSec":[90,200],"shellShortSide":[0.09,0.15],"shellGain":0.24,"echoGain":0.10,"echoDelaySec":[40,90],"hypernovaShare":0.15,"hypernovaGain":1.60,"hypernovaCooldownSec":10800,"paletteMix":0.35},
  "kilonova":{"enabled":true,"everyHours":[0.6,1.4],"flashSec":0.6,"gain":1.10,"ringShortSide":0.05,"ringGain":0.34,"ringSec":[8,15]},
  "pulsar":{"enabled":true,"everyHours":[0.5,1.1],"durationSec":[120,260],"periodSec":[0.9,2.2],"gain":0.70,"floorFraction":0.55,"edgeSec":0.14},
  "gammaBurst":{"enabled":true,"everyHours":[0.7,1.8],"riseSec":[0.4,0.7],"flashSec":[0.5,0.8],"gain":1.00,"beamShortSide":[0.10,0.18],"beamGain":0.42,"afterglowSec":[30,90]},
  "satelliteGlint":{"enabled":true,"gain":2.2,"widthSec":[1.5,3]},
  "nebula":{"enabled":true,"everyMinutes":[20,45],"durationSec":[180,480],"fadeSec":[30,60],"sizeShortSide":[0.40,0.80],"gain":0.30,"dustOpacity":0.55,"stars":[1,3],"starGain":0.45,"paletteMix":0.40,"driftScale":0.45}},
"phenomena": {"tde":{"enabled":true,"everyMinutes":[40,90],"streakPx":[60,140],"stretchSec":[6,12],"fragments":[4,8],"diskFlash":0.15},
  "microlensing":{"enabled":true,"gainCap":2.5}, "moods":{"clearing":0.15,"nebular":0.15}}
```
Measured on DP-3 (1440x2560), three seeds, six hours each: 39 meteors, 5.7 comets, 14 satellite passes, 4.9 star births, 6.2 novae, 2.3 red giants,
0.8 supernovae, 1.2 pulsars, 0.8 kilonovae, 0.7 gamma-ray bursts, 0.7 showers and 0.6 slow wanderers **per hour** - a notable non-meteor event every
~2.7 min and something dramatic every ~26 min. `modules/background/tools/test-events.mjs --audit [config.json]` reprints that table for any config
on all three of his outputs; it runs the shipped scheduler, not a copy of it.
**`events.rateScale` (0-4, default 1) is the one dial for all of it.** It divides every interval in the catalogue - meteors, comets, satellites,
showers, wanderers and the seven phenomena. 2 is twice as many events, 0.5 half as many, **0 turns every scheduled event off** (nothing is captured,
so it costs nothing). Everything else stays as documented; per-family keys still override on top of it. Calm, for a quieter sky:
```json
"events": {"rateScale": 0.45, "phenomenonGainCap": 1.0, "pulsar":{"enabled":false}, "gammaBurst":{"enabled":false}}
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
Fragmenting share ≤2%, cooldown ≥7200 s; spiral cooldown ≥14400 s (both ≤604800). Event headCap 1–3; hourly spacing 0.25–168 h; episode duration/gain bounded as shown.
Event intervals allow up to 86400 s; minima: meteor 3, comet 60, satellite 45. Companions/fireballs 0–1; three is the hard head cap, normally two (renderer).
phenomenonCap 1–3 (long faint slots, separate from headCap and never spilling into it), phenomenonGainCap 0.3–3, dramaCooldownSec 300–86400 across all dramatic
families (supernova, kilonova, gamma-ray burst and the nebula passage), rateScale 0–4 dividing every interval.
Schedules: `everyMinutes` ordered pair 1–1440, `everyHours` ordered 0.25–168. Every `gain` is 0–the value listed in the defaults block; shells/rings/nebulae ≤0.25 short
sides, GRB beams ≤0.25, satelliteGlint gain is a 1–4 multiplier on an existing pass; durations 10–1800 s, sub-envelopes (rise/hold/decay/swell/collapse/echo/afterglow)
0–600 s, remnant ≤1800 s, cooldowns 600–604800 s, hypernovaShare 0–1, `haloPx` is a from–to span 0.5–96 px and may descend.
Anti-strobe floors are VALIDATOR-ENFORCED, not advice: `riseSec` ≥0.8 s (nova and supernova), ≥0.35 s (gamma-ray burst, which is sub-second by nature — ten frames at
30 fps, eased); kilonova `flashSec` ≥0.35 s; pulsar `periodSec` ≥0.8 s, `floorFraction` ≥0.5 (the trough never drops below half the peak, so a pulsar modulates instead
of blinking), `edgeSec` ≥0.10 s; glint `widthSec` ≥0.5 s. A value under a floor is rejected, not raised. The floors are PROVEN by sampling every published frame at
30 Hz over three simulated hours, per family, against its own eased-rise bound of 0.05·peak/floor per frame (`test-events.mjs`), not asserted.
Every event-family key REJECTS instead of repairing — a bad type, an out-of-range number, an inverted pair or an unknown key inside a family drops with an index-only warning and that key's documented default applies — while the v4 keys beside them (headCap, shower, slowWanderer) keep their v4 clamping, unchanged.
v8 key changes: kilonova drops `minSpacingSec`/`maxPerHour` (it is interval-scheduled now and `dramaCooldownSec` spaces it) and gains `everyHours`/`ringGain`;
gammaBurst drops `cooldownSec` (same reason) and gains `riseSec`/`beamGain`. A file carrying a dropped key warns with its index and is otherwise unaffected.
`phenomena` is a closed sparse object like `particles`: tde{enabled, everyMinutes 1–1440, streakPx [0,160] — the maximum feeds the one-time particle atlas ceiling, see PARTICLES.md — stretchSec [1,120], fragments [1,16] (renderer rounds), diskFlash 0–0.5}, microlensing{enabled, gainCap 1–3}, moods{clearing, nebular 0–1}.
RENDERER: `microlensing` multiplies far-layer stars by clamp(1/|det J|, 1, gainCap) wherever the shader already filters them through the lens Jacobian — inside `bhGeometry.y` only, no scheduler, no slot, ~4 ALU. A background star drifting past the
hole brightens and returns over the tens of seconds the drift takes. It applies whatever `particlesEnabled` is (the far field is shared); `"microlensing": {"enabled": false}` restores the v5 far field exactly. `moods.clearing`/`moods.nebular` add mood kinds 4 and 5
to the existing 900 s slots, taking their share off the top so the four v5 kinds keep their proportions and a zero share reproduces v5's distribution: clearing thins far dust by 0.07 acceptance and warms the middle layer, nebular doubles the tinted middle-layer
share. Both interpolate the two outcomes by the eased weight rather than moving a threshold, so no star switches on a frame. `events.satelliteGlint` modulates the existing satellite slot's gain by a birth-frozen Gaussian in time (gain 1–4, width 0.5–10 s, placed in
the middle half of the pass), and now also drives the head flash so the glint blooms. A satellite and a slow wanderer used a FIXED 0.65 px sigma whatever the buffer —
14 lit pixels against a bright star's 1.55 px sigma and 243/255, smaller AND dimmer than an ordinary star; both scale with the near-layer optics now (0.62 and 0.56 of
it) and their gain cap is 0.55 and 0.75 rather than 0.33 and 0.40. All seven phenomena are DRAWN, as kinds 5–11 on **three** phenomenon slots (event3/4/5, 80 B each; UBO reflection 1520 → 1600 B of 16384). `starBirth`, `nova`, `redGiant`,
`supernova`, `pulsar` and `kilonova` share one kernel (style 3, radial: core + halo + ring + echo ring) and differ only in envelope, colour, size and schedule:
head=(x, y, coreSigmaPx, peak), shape=(haloSigmaPx, ringGain, ringWidthPx, ringRadiusPx), tail01=(echoRadiusPx, echoGain, haloGain, coreGain). Each component's gain is
absolute and is divided by the slot peak, so a nova's shell outlives the core that threw it, a light echo outlives the shell, and a kilonova's ring reddens through the
r-process colour after the flash that threw it has gone. `gammaBurst` is **style 4**: core + halo + two OPPOSED cones, no rings, so the ring channel is re-read as the
beam — tail01=(haloSigmaPx, haloGain, coreGain, beamGain), shape=(dirX, dirY, beamLengthPx, beamWidthPx).
**Placement.** An event composites after the disk and is not shadow-masked, so one sitting on the hole would shine straight through it; placement is therefore REJECTED,
never clamped, inside 1.25× what the hole actually DRAWS, or within 0.05 short sides of an edge — sixteen attempts, then the episode is skipped. The drawn reach comes
from `Physics.visibleRadius()` on the hole's own published uniforms, the same call the particles use, so one number moves both. **v6 excluded 1.6× `bhGeometry.y`, which
is the LENSING reach — 8 Rh under his `target` preset, so 12.8 Rh. On DP-3 (2160x3840 device) that is 3041 px against a 1080 px half-width; on HDMI-A-1 2028 px and on
the tablet 2534 px. It covered the whole buffer on all three: measured acceptance 0.000, 0/400 captures found a spot, so no phenomenon had EVER been placed on any of
his screens.** The drawn material is 887/592/740 px on those outputs, the new keep-out 1109/740/924, and acceptance 400/400 (`test-events.mjs`).
Slot ownership is STICKY: an episode claims a slot in its first second and keeps it until it ends, so nothing can appear mid-life at whatever gain it had reached.
**v6 held the KIND in the slot, and publishEvents replaces `s.events[kind]` with the next episode the instant the current one ends: the release test always read a future
end time, so slots 3–4 stayed owned by the first star birth and the first nova for the life of the process. Measured over six hours on three seeds, red giant was
scheduled 0.83/h and drawn 0 s, supernova 0.33/h and drawn 0 s — neither had ever reached the screen.** The slot holds the EPISODE now, and a phenomenon that finds every
slot busy at its moment is retired and rescheduled rather than silently dropped. The two classes never spill into each other — transient heads reserve only against
transients, phenomena only against phenomena. Combined phenomenon gain is capped at `phenomenonGainCap` (1.6) outside a supernova or burst flash, the exemption easing
away over two to three seconds rather than switching.
**`pendingEvents`** is the queue for an episode that arrives from outside the interval scheduler: `pushEvent(family, delaySec, overrides)` captures it from the same hash
stream and `drainPending()` lands it on that family's entry once the entry is free, in order, bounded to four and dropped if it is still waiting two minutes after its
moment. It never evicts a running episode and obeys exactly the same slot and cap rules. This is the hook a particle merge (kilonova) or any other detection calls.
`phenomena.tde` is DRAWN, by the particles alone — no slot, no uniform, no shader change; PARTICLES.md owns it. One doomed particle's packed streak is ramped to `streakPx` over `stretchSec` while its core dims and reddens, it splits into `fragments` siblings
along its own orbit, and its head's trail then eases back over six seconds. `streakPx` is clamped to 120 px by the renderer whatever the service validates up to 160: 120 is what the packed streak byte carries. `diskFlash` rides the hole's brightness channel for 20 s.

**v9, THE NEBULA PASSAGE (`events.nebula`).** The only large-scale thing on the sky was `moods.nebular`, which changes which stars take a colour and which nobody has
ever noticed; a force-fired supernova measured ~40 px on the 2880 px tablet (`starfield-v2/evidence/v8-fire-supernova-tablet-tiny.png`). This is the other end of that
scale, and the first event that takes light AWAY instead of adding it: a ragged cloud **40–80 % of the short side** across (`sizeShortSide` is its DIAMETER as a fraction
of the short side), 3–8 minutes long, one every **20–45 min** at rateScale 1. It is NOT a slot and not in `s.events` — a cloud is not a point source — so it carries its
own 112 B uniform block (`nebulaHead/Shape/Tone0/Tone1/Stars/Stars2/Bounds`, UBO 1600 → 1712 B of 16384) and its own entry in `_state`. `nebulaHead.w <= 0` is the whole
switch; `density: 0` also turns it off, because it shares the far field's pass.
**Shape.** One bounding ellipse, then three texture fetches. `blackhole-noise.png` is already bound (binding 2, linear) whatever the hole is doing, and one hardware-bilinear
tap of it IS a C1 value-noise lattice when the fractional part is pre-eased — the trick `bhNoiseRow` already uses on the same texture. Its R and G channels have x periods
of 32 and 64 texels and a y period of 127 with the last row duplicated, so folding the integer part by (64, 127) keeps BOTH continuous across the fold and yields two
decorrelated fields per fetch: a warp octave, a medium octave and a fine octave give a soft fbm for the body, a ridged layer for the filaments, a low band for the dust
lanes — which are dark AND opaque — and a two-octave bite that makes the rim ragged at two scales while the hard ellipse stays the cost bound. Colour is two palette tones
(`paletteMix` 0–0.45 of the way from a cold neutral to a listed hue, so no unlisted hue is generated and the saturation cap still holds) mixed to their ENDS rather than
linearly: a palette capped at 0.28 saturation has little chroma, and averaging two of those over most of the cloud threw away what there was (measured mean chroma 0.017
linear against 0.024 after the change). `stars` 0–3 embedded young stars have a hot core and a halo that only lights the material around them, so the scattering reads as
the cloud glowing. The body's 0.36 internal factor is a CALIBRATION: it makes the cloud's 99th linear percentile equal `gain`, so the 0.35 ceiling on that key is the q99
the sky actually gets. The star cores are deliberately outside it — an embedded young star is meant to be a star.
**Motion.** Its position is not captured and replayed: it follows the far layer's own flow law (u = r²/2, du/d`geo` from `stars()` layer 0 at depth 0.10 and the dust
boost), at `driftScale` 0.45 of the dust's own rate. At 1.0 the far layer crosses from the screen edge to the hole in 60–200 s, which is a fly-past rather than a passage;
0.45 is the same direction, the same reversal and the same regime crossfade at a speed that reads as something large and far away. Because the signed accumulator
`_state.geo[0]` already carries the camera's rate and sign, the cloud drifts inward under infall, outward under the camera, and turns around mid-passage when the camera
reverses — for one subtraction a frame, with no second model of the flow. Under infall it arrives from off the edge along a direction that is REJECTED, not clamped, when
there is no room in it (the hole's material reaches 740 px against the tablet's 900 px half-height, so a cloud on the short axis would dissolve before its centre crossed
the edge), the tide stretches it radially and squeezes it tangentially as it approaches, and it dissolves across the last stretch into the rim it is feeding. Under the
camera it is a body at a DEPTH: it fades in small, grows with its own screen radius (the configured size is what it is at mid-passage) and passes partly off-screen.
Internal turbulence is three octaves advected at three different velocities by the EPISODE's age, so the structure shears through itself over minutes; the age keeps that
phase bounded and starts every passage at the same place in its own evolution.
**Order.** It composites into the far field — `far = far*(1-a) + rgb`, evaluated at the same lensed source coordinate the far stars use — so it is lensed with the
background it belongs to, its lanes extinct the dust behind it, the particles and the disk are in front of it, and `bhShadowMask` is subtracted from it: it can never be
drawn over the hole. Like every event it ignores `brightness`. It takes its turn in the SHARED dramatic cooldown (`dramaCooldownSec`, `familyLast.drama`), so a passage and
a supernova remnant never occupy the same screen — 900 s against a ≤480 s passage and a ≤333 s supernova separates them in both directions with no second mechanism.
`caelestia shell starfield fire nebula [screen]` forces one through the same `pushEvent`; it waits for a running passage and is dropped two minutes later, exactly as a
pushed phenomenon waits for its family's entry.
Bounds: `everyMinutes` 1–1440, `durationSec` 60–1800 (a crossing that reaches the rim sooner ends there), `fadeSec` 5–300 (capped at 0.45 of the duration), `sizeShortSide`
0.15–1.2, `gain` 0–0.35, `dustOpacity` 0–0.9, `stars` 0–3 (the renderer rounds), `starGain` 0–0.8, `paletteMix` 0–0.45, `driftScale` 0.05–2. Measured through the shipped
kernel offscreen (`tools/nebula_sheet.py`, llvmpipe, the real noise texture, his palette): q99 0.21–0.30 linear at the shipped gain, q999 0.34, peak 229/255 in the star
cores alone, extent 45–68 % of the short side on the tablet and 27–53 % on DP-3, mean dust opacity 0.15–0.27. `tools/nebula_harness.qml` drives the real QML headlessly
through a passage in both regimes.

**A comet is style 5 (`cometField`), not a wider meteor.** v6 drew it as one Gaussian polyline behind the nucleus: measured on DP-3, a slow comet peaked at 116/255 with
2566 lit pixels — the same shape as a meteor, only slower (his report, ledger 2283). It is now a nucleus inside a two-stage coma, a straight narrow bluish **ion tail**
pointing directly away from the only light source on the sky (the hole; the radial centre when the hole is off) with rays across it, and a broader warmer **dust tail**
lagging the ion tail by a fixed birth-frozen angle, parabolically curved and striated. Both tails brighten toward the nucleus. The parabola is applied to the SAMPLE
point, so a curved tail costs six ops instead of a curve solve. The lag is an ANGLE, never a blend of anti-sunward with anti-velocity: a comet receding straight from the
light has those antiparallel and the blend collapses the dust tail onto the ion tail. Everything travels in the slot's existing seven vectors — head=(x, y,
nucleusSigmaPx, gain), tail01=(ionDirX, ionDirY, ionLengthPx, ionWidthPx), tail23=(dustDirX, dustDirY, dustLengthPx, dustWidth0Px), tail4=(dustCurve, comaSigmaPx),
shape=(ionGain, dustGain, comaGain, striationAmp) — so no uniform was added. `cometLook()` in Starfield.qml is the whole of the per-family difference: **fast** is a
bright blue spike with a stub of dust, **slow** a broad curved fan, **bent** nearly all dust, **pulsating** breathes its coma, **fragmenting** gives each branch its own
coma and half-tail, **spiral** sweeps its tail around the hole. The direction is recomputed every publish because it is a property of where the comet *is*.
**Meteors** keep their streak and gain an entry flash (`shape.w` widens the halo and the taper together, so it blooms rather than brightening) and an ionisation train
(a wide, dim tail component with a shallower `(1-u)` falloff): 420 → 2517 lit pixels at the same 255/255 head.
Measured v7 → v8 at 1:1 on 1440x2560, peak/255 · lit px · lit radius px, against a near-layer star at 243/255 and 1.55 px sigma
(`starfield-v2/evidence/v8-events-sheet.png`, `v8-events-before-after.png`, rendered offscreen through the real kernels by `tools/events-sheet.mjs`):
comet-slow 116·2566·86 → 255·29238·383; comet-bent 170·3441·102 → 255·36623·365; satellite 130·**14**·2 → 255·462·15; starBirth 46·216·9 → 131·1936·26;
nova 125·840·17 → 255·5488·42; redGiant 74·7472·49 → 163·39760·113; supernova 222·1468·22 → 255·15308·70; kilonova and gammaBurst not drawn at all → 255·6676·47 and
255·12282·178. Worst-case cost, six busy slots (three wide comets and three phenomena) at 3440x1440 on llvmpipe: below this harness's ~0.5 ms measurement floor — the
CPU bounds reject nearly every pixel with one compare. Live on his machine, same shell, same three outputs, `qs` process CPU and `nvidia-smi`: v7 18.2–19.3 % of a core
at 3 % GPU, v8 19.4–20.0 % at 3–4 % — **+1.2 points of one core, no measurable GPU change**, with the third phenomenon slot, the comet kernel and two new families in.
Live captures on the tablet: `v8-live-tablet-comet.png` (coma, straight ion tail, curved striated dust tail, two meteors with trains, a satellite),
`v8-live-tablet-redgiant.png`, `v8-live-tablet-nova.png`, `v8-live-tablet-full.png`.
v8, THE CAMERA REGIME: `blackHole.enabled:false` used to fade the hole's PICTURE and nothing else. mu was untouched, so stars went on falling into an invisible mass and
circularising into a ring nobody could see (289 captures in 180 s), and because the swallow radius follows the same envelope they stopped dying at the centre and piled up
there — 76 instances inside 1 Rh against 0 with the hole on — held until their 180–240 s safety life expired, and the population sagged with them (540 against 598). The
toggle now switches the whole regime: gravity and the capture drag scale to zero, the substep ladder relaxes to one kick-drift-kick, the tide and the swallow were already
on the envelope, and a camera takes their place. A star at 3-D depth z and screen radius r projects at r = f·ρ/z, so a camera step scales every screen position about the
centre by z/z′ and nothing else — one multiply, exact, exactly invertible (which is what makes reverse a true reverse), and perspective for free: dr/dt = r·w/z grows with
radius, and two stars at the same radius separate by depth, which IS the parallax. Size and light follow 1/z, so a star grows and brightens as the camera closes on it;
both factors are ≤1, so the atlas ceiling `bounds()` allocated from the configured sizes is still the ceiling. Births are the time-reverse of deaths, which is what keeps
the field uniform in both directions (measured bin density spread 1.16× out, 1.21× in): forward a star is born at the far plane anywhere on the padded rectangle — a
uniform 3-D field crossing a plane is uniform on the screen — and leaves at an edge; reverse takes the same far-plane draw as the point where the star will DISSOLVE and
runs it back out along its own ray to the edge it came in through, at the depth it crossed. Arc-length and flux weightings of the perimeter were both tried and both
measured a thinner field than forward. The crossfade is the hole's own 30 s enable envelope read backwards — ease(1−x) = 1−ease(x) for this smoothstep, so the two regimes
always sum to one — and the stored velocity is the blend of both, so nothing is a cut: measured worst one-frame move 21 px across the change. THE FAR FIELD reverses with
the same toggle: `radialMode` carries the blend in its FRACTION (1 = the inward stream, 2 = fully reversed), so the shader needs no new uniform and no UBO change, and a
separate signed per-layer accumulator (`_state.geo`) carries the geometry so the descriptor history is never run backwards — it is the same accumulation as `flow`, bit for
bit, while the camera is off. The far layer keeps its equal-area grid, so its density stays uniform and its speed law stays 1/r rather than the particles' r/z; `dustFlow`
3 is what keeps that difference under the threshold of notice. With `particlesEnabled:false` the middle and near layers fall back to the same reversed procedural grid.
LIVE, on his tablet (2880x1800), ten `grim` frames 0.3 s apart per direction, fitted for the radial magnification between the first and the last (a fly-through IS a
magnification about the centre, so the correlation peak is the answer): hole on **1.000** (corr 0.99, the field is not scaling at all), camera out **1.075**, camera in
**0.925** -- within 0.5 % of each other's inverse, which is reverse playback being a real reverse rather than a differently-shaped flow. Cost on the same shell, same
three outputs, `qs` process CPU over 30 s and `nvidia-smi`: hole on 20.5 % of one core at 3 % GPU, camera 18.4 % at 2 %. The camera regime is CHEAPER live as well as in
the harness -- no innermost orbit to subdivide for. Captures: `starfield-v2/evidence/v8-live-tablet-camera-{holeon,out,in}.png` and the `-trails.png` composites of all
ten frames, which is what shows the streaming.
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
v7b gives the hole three radii and lets each boundary pick the one that gives it its meaning. Rh is the dynamical scale AND the shadow, the black core; the
disk's material rim (bhOuter, 3.735 Rh under the live `target` preset) is where the drawn material ends; the outer arcs are a third radius, off in `target`.
`Physics.visibleRadius` returns all three, derived from `blackHole.diskInnerRs`/`diskOuterRs` and `disk.arcs`, mirroring bhOuter()/bhImpact()/bhArcReach() in
`shaders/blackhole.glsl`: change them together. A star is swallowed at the SHADOW and nowhere else; the captured ring circularises at the disk's material rim
and spirals down through the band into the core. Crossing the band is an OCCLUSION, not a swallow: `starfield.frag` composites the non-front particle field
through the disk's geometric coverage (`max(disk.a, bhDiskAbsorb)`, which also picks up the inner halo) instead of the alpha its shading left, so a star sinks
into the material rather than riding over it. v6 anchored everything to Rh and drew stars on top of the disk (ledger 2281); v7 anchored everything to the
outermost drawn radius and killed them out by the rings, which he rejected (ledger 2282). Two keys change unit: `capture.radius` (Rh -> Rd, default [1.0,1.3])
and `streak.bendRadiusRh` -> `streak.bendRadiusRd` (default 0.70). The shader change needs a `.qsb` rebake; the command is in PARTICLES.md.
Closed schema, every key optional: population{near, middle} integers 0–3200 with near+middle ≤3200 (defaults 120/480, or 600/1500 when
stressPreset is true), stressPreset boolean, vref 10–600 px/s, launch{plunge, miss, wide 0–1 (the renderer normalizes the three),
betaBound [0.10,0.99], unboundShare 0–1, betaUnbound [1.001,2], handedness 0–1}, capture{radius [0.8,6] Rd, gamma 0–2 /s,
spiralSec [5,240] s}, epsilonRh 0.01–0.20, substeps integer 4–32, streak{exposureSec 0–0.10, maxPx 0–32, bendRadiusRd 0–4},
sizes{nearPx, middlePx, capturedPx [0.25,12] px}, safetyLifeSec [30,600] s; pairs are ordered two-number arrays.
Malformed particle values are REJECTED, not repaired: a bad type, an out-of-range number, an inverted pair, a fractional integer or an
over-budget population is dropped with an index-only warning and the renderer's documented default applies instead.
V2 bounds: density/brightness 0–3, driftSpeed 0–30, direction ±360°, twinkle/edgeLift 0–1, flare ≤0.025, fps 1–60 rounded; opaque #RRGGBB background, default pure black.
Motion: radial/drift, radialSpeed 0–26 (device px/s at shortSide/2 on 2160 short side), centreWander ≤0.05 short sides; zoom ≤0.15 (drift default 0.025), wander 0–2, rotation 0–3°.
`motion.camera` is the OTHER regime, v8: `enabled` "auto" (default) ties it to the black hole — a hole that is off has no mass to fall into, so the field stops being an
infall and becomes a camera moving forward through a nearly static sky — while `true`/`false` force it on or off whatever the hole is doing. `direction` "out" (default)
flies the camera toward the centre, so stars stream out past the edges; "in" is the same playback reversed and they come in from the sides. `speed` 0–30 (6 crosses the
whole depth in 60 active seconds, 0 freezes with the rest of the motion), `depth` 2–64 (the far plane over the near one: how far apart the parallax layers are, and the
largest magnification a star can undergo), `dustFlow` 0–64 (the far layer's flow multiplier in this regime, replacing `particles.dust.farFlow`; the default 3 against 24
is what makes the dust the slow distant layer), `roll` 0–2 °/s peak (a bounded sinusoid in RATE, so the ±4° sway can never wind up), `wander` 0–1 (how much of
`centreWander`'s amplitude moves to a livelier pair of periods — it is a SPLIT, never an addition, so the excursion stays inside the 0.012 short sides the birth padding
is sized for), `sizeGain` 0–1 (how strongly size and light follow depth). Every camera value clamps or falls back; nothing about them throws. Toggle either regime with
`~/namealle/scripts/starfield-hole on|off|toggle` and `~/namealle/scripts/starfield-camera on|off|auto|out|in|flip|speed N|depth N|status`.
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
meteors, shower, slowWanderer, the eight event families, `phenomena`, `phenomenonCap`, `phenomenonGainCap`, `dramaCooldownSec` and `rateScale`. Only headCap travels
separately, as `eventHeadCap`.
Privacy: match class first, read at most 512 title chars locally; retain only category strengths, never titles/URLs/history/media metadata/notification content. No title hashing or transmission.
Context: mapped active/open-special/pinned windows on that output; focused weight 1, other visible 0.6, hidden/minimized 0. Visibility is approximate, not pixel occlusion.
`ambient dump` includes rounded birth/live, paletteWeights[16], archetypeWeights[6], mix/calm/hole[4], eventBias{family:multiplier}, numeric signals and availability; no titles.
Pause: lock or visible fullscreen>1 freezes that output's targets and renderer active time/history, retaining Loader; other outputs continue. All paused stops polling and releases ServiceRefs.
Config watching/event subscriptions remain; paused profiles preserve all fields through edits. Suspend resets baselines/derivatives with no catch-up; workspace activity freezes while paused.
`background.enabled` still gates windows. Density is static, never reactive. Keep backgroundColor #000000 for exact-black empty pixels.
