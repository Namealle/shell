# Starfield v11
**The sky is its own Quickshell process** -- `starfield-shell start|restart|kill|fire`, not `caelestia shell`.
See **Process model** at the end of this file before running or debugging anything.
`~/.config/caelestia/starfield.json` is watched with 150 ms debounce (XDG_CONFIG_HOME respected).
Missing/invalid JSON, a non-object document or missing screens disables every output; deleted keys restore defaults.
One validated snapshot owns configuration; neither process ever writes it. Full schema and defaults:
```json
{
  "screens": [], "process": "separate", "density": 1, "driftSpeed": 3.5, "driftDirection": 165,
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
    "shower":{"enabled":true,"everyHours":[0.42,1],"durationSec":[70,130],"gain":1,"rampFraction":0.32,"peakRate":6,
      "radiantBias":0.28,"paletteMix":0.30,"streakShortSide":[0.10,0.30],"headPx":[3,6],
      "fireballs":[1,3],"trainSec":[12,26],"earthgrazerShare":0.08,"fragmentShare":0.06},
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
  "supernova":{"enabled":true,"everyHours":[0.5,1],"precursorSec":[10,20],"riseSec":[0.8,1.5],"holdSec":[0.6,1.6],"decaySec":[25,60],
    "flashShortSide":[0.15,0.25],"skyLift":0.35,"spikeGain":0.55,"gain":1.35,"shellSec":[30,90],"shellShortSide":[0.25,0.40],"shellGain":0.55,
    "filaments":0.55,"remnantSec":[120,300],"remnantGain":0.26,"pulsarGain":0.30,"pulsarPeriodSec":1.4,
    "hypernovaShare":0.15,"hypernovaGain":1.60,"hypernovaCooldownSec":10800,"paletteMix":0.35},
  "kilonova":{"enabled":true,"everyHours":[0.6,1.4],"flashSec":0.6,"gain":1.10,"ringShortSide":0.05,"ringGain":0.34,"ringSec":[8,15]},
  "pulsar":{"enabled":true,"everyHours":[0.5,1.1],"durationSec":[120,260],"periodSec":[0.9,2.2],"gain":0.70,"floorFraction":0.55,"edgeSec":0.14},
  "gammaBurst":{"enabled":true,"everyHours":[0.7,1.8],"riseSec":[0.4,0.7],"flashSec":[0.5,0.8],"gain":1.00,"beamShortSide":[0.10,0.18],"beamGain":0.42,"afterglowSec":[30,90]},
  "satelliteGlint":{"enabled":true,"gain":2.2,"widthSec":[1.5,3]},
  "nebula":{"enabled":true,"everyMinutes":[20,45],"durationSec":[180,480],"fadeSec":[30,60],"sizeShortSide":[0.40,0.80],"gain":0.30,"dustOpacity":0.55,"stars":[1,3],"starGain":0.45,"paletteMix":0.40,"driftScale":0.45}},
"phenomena": {"tde":{"enabled":true,"everyMinutes":[40,90],"streakPx":[60,140],"stretchSec":[6,12],"fragments":[4,8],"diskFlash":0.15},
  "microlensing":{"enabled":true,"gainCap":2.5}, "moods":{"clearing":0.15,"nebular":0.15}}
```
Measured on DP-3, three seeds, six hours each, v9 defaults with ALL THREE v9 features in: 37.4 meteors, 5.9 comets, 13.9 satellite passes, 5.0 star births,
6.3 novae, 2.4 red giants, 1.1 supernovae, 1.3 pulsars, 0.9 kilonovae, 0.8 gamma-ray bursts, 1.4 meteor storms, 0.8 slow wanderers and 1.8 nebula passages
**per hour** - a notable non-meteor event every **2.4 min** and something dramatic every **21.6 min**. Drawn seconds per hour, which is what he actually sees:
star birth 605, satellites 521, red giant 507, supernova **279** (v6 drew it for 0), nebula 260, pulsar 250, nova 219, slow wanderer 202, comet 172,
storm 147, gamma-ray burst 50, meteors 39, kilonova 10. `modules/background/tools/test-events.mjs --audit [config.json]` reprints that table for any config
on all three of his outputs; it runs the shipped scheduler, not a copy of it.
The table gained a `nebula` row in v9 (its `peak sigma` column is the cloud's semi-major axis, not a point's sigma); a family slower than the window prints when
it is next due rather than `off / never`. The passage takes its turn in the shared dramatic cooldown, so on a cold start it lands behind the first round of
supernova/kilonova/gamma-ray burst schedules — 92 min in on the default catalogue, ~32 min apart thereafter.
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
sides (the v9 supernova's own `shellShortSide` and `flashShortSide` go to 0.6, and are diameters), GRB beams ≤0.25, satelliteGlint gain is a 1–4 multiplier on an existing pass; durations 10–1800 s, sub-envelopes (rise/hold/decay/swell/collapse/echo/afterglow)
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
`pulsar` and `kilonova` share one kernel (style 3, radial: core + halo + ring + echo ring) and differ only in envelope, colour, size and schedule:
head=(x, y, coreSigmaPx, peak), shape=(haloSigmaPx, ringGain, ringWidthPx, ringRadiusPx), tail01=(echoRadiusPx, echoGain, haloGain, coreGain). Each component's gain is
absolute and is divided by the slot peak, so a nova's shell outlives the core that threw it, a light echo outlives the shell, and a kilonova's ring reddens through the
r-process colour after the flash that threw it has gone. `gammaBurst` is **style 4**: core + halo + two OPPOSED cones, no rings, so the ring channel is re-read as the
beam — tail01=(haloSigmaPx, haloGain, coreGain, beamGain), shape=(dirX, dirY, beamLengthPx, beamWidthPx).
**Placement.** An event composites after the disk and is not shadow-masked, so one sitting on the hole would shine straight through it; placement is therefore REJECTED,
never clamped, inside 1.25× what the hole actually DRAWS, or within 0.05 short sides of an edge — sixteen attempts, then the episode is skipped. **v9's supernova asks
for 0.12 short sides from an edge** (its shell reaches 0.20, and a rim half off the screen is half an event) **and for its whole shell's radius on top of the keep-out**,
falling back to the plain keep-out when sixteen attempts cannot find that much room: the keep-out guards where the event IS, and a centre that merely clears the drawn
material still puts a 0.20-short-side rim on the disk. Measured with his hole on, 1000 captures each: the padded placement succeeds 85.3 % on DP-3, 99.9 % on HDMI-A-1
and 28.3 % on the tablet, where the hole is 41 % of the short side and there is often nowhere that clears both. The fallback is exactly v8's placement, never worse. The drawn reach comes
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
own 112 B uniform block (`nebulaHead/Shape/Tone0/Tone1/Stars/Stars2/Bounds`; the merged v9 block is supernova 64 B + storm 64 B + nebula 112 B, UBO reflection 1600 → **1840 B** of 16384, measured with `BHRENDER_LAYOUT=1 bhrender`) and its own entry in `_state`. `nebulaHead.w <= 0` is the whole
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
`starfield-shell fire nebula <screen>` forces one through the same `pushEvent`; it waits for a running passage and is dropped two minutes later, exactly as a
pushed phenomenon waits for its family's entry.
The two directions of "never beside a supernova remnant" are covered differently and deliberately: a dramatic family scheduled AFTER a passage is placed reads
`familyLast.drama`, which a passage writes exactly as they do, so it takes its turn in the shared cooldown; a dramatic episode already on the books is RESERVED against
by the overlap test `schedule()` already uses for the transient heads. Reading `familyLast.drama` for that second direction is what a dramatic family does and it is
wrong for this one — those schedule in chronological order, so their `last` is the most recent start, while a passage is scheduled once against whatever the first round
of dramatic schedules happened to leave there. A gamma-ray burst booked ninety minutes out was pushing the FIRST passage of a session to 92 min and making
`everyMinutes` below ~15 min inert; reserving against the actual episodes is stricter (it is the real overlap) and costs nothing unless they would collide. Measured
first passage on three seeds: 22.2, 34.1, 37.7 min.
Bounds: `everyMinutes` 1–1440, `durationSec` 60–1800 (a crossing that reaches the rim sooner ends there), `fadeSec` 5–300 (capped at 0.45 of the duration), `sizeShortSide`
0.15–1.2, `gain` 0–0.35, `dustOpacity` 0–0.9, `stars` 0–3 (the renderer rounds), `starGain` 0–0.8, `paletteMix` 0–0.45, `driftScale` 0.05–2. Measured through the shipped
kernel offscreen (`tools/nebula_sheet.py`, llvmpipe, the real noise texture, his palette): q99 0.21–0.30 linear at the shipped gain, q999 0.34, peak 229/255 in the star
cores alone, extent 45–68 % of the short side on the tablet and 27–53 % on DP-3, mean dust opacity 0.15–0.27. `tools/nebula_harness.qml` drives the real QML headlessly
through a passage in both regimes. LIVE on his tablet (2880x1800, `caelestia shell starfield fire nebula tablet ''`, `grim -o tablet` every 5 s): a camera passage takes
the lit pixels (>= 8/255) from a 25 836 px sky to 553 246 px at peak — 10.7 % of the buffer against 0.5 %, a 21x rise — over 24 captured frames that rise and fall
without a step, and an infall passage adds up to 50 % on top of a sky that already has the hole in it. `qs` CPU and `nvidia-smi` over 30 s during a passage: GPU 4 %
in the camera regime and 6 % with the hole on, against v8's documented 2 % and 3 % — measured with two other agents running heavy offscreen renders on the same box,
so treat it as an upper bound rather than a number. Captures: `starfield-v2/evidence/v9-nebula-live-tablet-{camera,holeon}.png`, the `-sheet.png` contact sheets and
`v9-nebula-live-tablet-camera-trails.png`, a 51-frame maximum composite in which the embedded stars trace the cloud's own track across the sky.

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
**v9, THE THREE FEATURES TOGETHER.** The supernova, the meteor storm and the nebula passage were built in parallel from one base and merged; this is the contract
that keeps all three true at once.
- **Style ids.** `eventSlot` dispatches from the top down: **7** is the storm's fireball (`stormFireball`), **6** is the supernova (`supernovaField`, reached through
  `radialField`), 5 the comet, 3-4 radial, 0-2 the point kernels. Both v9 tests are bounded on BOTH sides (`> 5.5 && < 6.5` for the supernova, `> 6.5` for the
  fireball), so neither can shadow the other and a slot carrying one can never fall into the other's kernel.
- **One UBO block, in this order:** supernova `snRemnant/snTone/snShell/snExtra` (64 B), storm `stormHead/Shape/Colour/Span` (64 B), nebula
  `nebulaHead/Shape/Tone0/Tone1/Stars/Stars2/Bounds` (112 B). **1600 → 1840 B of 16384**, read off the driver's own reflection
  (`BHRENDER_LAYOUT=1 bhrender frag 4 4 /dev/null /dev/null` prints the block size and every member's offset), never added up by hand. The same order is written into
  `Starfield.qml`'s ShaderEffect properties and into every offline tool that re-declares the block.
- **Composite order in `main()`, which is the part that cannot be fudged:** far dust and far stars accumulate display-encoded at the LENSED `skySource` → decode →
  **the cloud extincts them and adds its emission** (`far*(1-nebula.a)+nebula.rgb`) → **the storm's streaks are added after that**, because a meteor is in the
  atmosphere and nothing in deep space can dim it → the hole's shadow → the disk and the particles composite over all of it → the phenomena and the events →
  the supernova's sky lift, which SCALES the composed sky. The storm still accumulates encoded with the stars, so its contribution is taken as the exact difference
  that accumulation would have made (`decodeDisplay(far + storm) - decodeDisplay(far)`): with no passage alive that is bit-for-bit the storm on its own, and with no
  storm alive it costs one compare. `legacyMain` keeps the same relative order - the cloud multiplies the far layer, the storm rides with the events.
- **Scheduling.** The warm start owns the FIRST episode of every slot family (first dramatic one ≤ 240 s); the passage is not a slot family and keeps its own
  `nebulaLast` clock, reserving against the actual dramatic episodes on the books rather than reading `familyLast.drama` - which is what stopped a burst booked 90
  minutes out from pushing the first passage to 92 minutes. It still WRITES `familyLast.drama`, so it takes its turn in the shared cooldown. `publishEvents()` runs
  before `publishNebula()`, so the warm start is placed first and the passage queues around it.

**v9-merged, LIVE on his tablet (2880x1800), all three fired into the same sky.** `starfield fire supernova tablet '{"precursor":3,"shellSpan":30,"remnant":45}'`
over a running passage and a running storm: the flash lit the whole screen, the storm's streaks crossed it, and the cloud took the sky lift with everything else --
which is the lift doing what it says, SCALING the sky already there rather than being pasted over it. `nvidia-smi` over 24 s with all three alive against the same
shell idle: **22 W / 4 % -> 23-25 W / 5-6 %**, and `qs` 37.3 % -> 34.2 % of one core (no measurable change). Captures:
`starfield-v2/evidence/v9-merged-live-tablet-{supernova,storm,nebula,all-three}.png`, and `v9-merged-sheet.png` is the whole catalogue -- all twenty families, the
storm and the passage included -- rendered offscreen through the merged kernels in main()'s own composite order.

## v10: EVENTS THAT HAPPEN TO THE FIELD

His report on v9, ledger 2285, four sentences: *"I saw a large comet or whatever that was with a large tail and it feels really poor for me: it was moving slow, same as
the other stars, and the tail was in the wrong direction."* / the supernova *"seems almost static with colour change, when in reality it should violently explode and
particles of it should spread everywhere."* / *"Right now everything feels like separate pieces, not part of one system."* / *"Isn't a supernova an exploded star? So it
should first be a star and then explode, not just fade in and then out."*

The third sentence is the diagnosis and the other three are its symptoms. Through v9 an event was a shader sprite SCHEDULED BESIDE the sky: it had a position the CPU
made up, a clock of its own and no relationship whatever to the 600 particles it was drawn among. v10 makes every event something that happens **to and through** the
particle field. The interface is four calls in `particles/Physics.js` and PARTICLES.md owns their contract; this section is what the events do with them.

**THE SUPERNOVA IS A STAR.** `supernovaParticles()` is the state machine; `supernovaState()` stays a pure function of (episode, age) so the offscreen sheets can still
sweep it, and the two talk through `e.site` and `e.hasStar`.
- **Arrival.** `Physics.pickStar` names a real, visible, near particle: alive at least 1.5 s (fully faded in), inside a 12 % margin, still on the screen and still clear
  of the hole when its precursor runs out, not already captured and not the tidal-disruption victim. The precursor length is then shortened against the **measured**
  field speed (`Physics.flowSpeed`), because how long a star can be held on the screen is a property of the regime and not a wish: measured on the tablet, **14 s with
  the camera on and 4.7 s with the hole on**, where the field itself crosses the screen in seconds. No candidate → the episode plays as v9's sprite did.
- **Precursor.** `Appearance.render` swells THAT particle by **x4.2** (measured 2.38 → 9.19 px core), brightens it **x5.5** (1.82 → 8.79), walks it red and then
  blue-white (r−b peaks at +0.54 at 60 % of the precursor, ends at −0.03) and pulses it from a 3.2 s period to a 1.0 s one on an INTEGRATED phase, so the period can
  shorten without the pulse ever jumping, with the amplitude eased to nothing over the last 1.2 s so the detonation cannot cut it mid-stroke. It keeps moving with the
  regime the whole time: **136 px over 13 s**. The sprite keeps only the halo the star casts — its core is gone, because the sprite's core was the thing that "faded in".
- **Detonation**, one frame: the star is REMOVED (`Physics.remove`, its own counter), **180–370 debris particles** are born at it with radial velocities, a shock front
  starts sweeping, `brightenNear` lifts the neighbourhood by 1.7 over 2.5–4 s, and the flash, the diffraction spikes and the sky lift fire on the same frame.
  - *Speeds.* The median ejecta speed is solved, not guessed: `r(t) = (v0*t0/0.4)*((t/t0)^0.4 − 1)` is the exact integral of the Sedov decay the kick channel applies,
    so `v0 = 0.4*shell/(t0*((span/t0)^0.4 − 1))` is the speed that puts the debris cloud on the shell's own radius at the end of the shell's own span. On the tablet
    with a 30 s span: **median 327 px/s at t0, fast fragments 916 px/s = 0.51 short sides per second**. The range is `[0.35, 1.65] x` the median, so the slow half stays
    inside the rim and the fast half runs ahead of it, which is what a shock into a real medium does and what stops the burst reading as a ring with a hole in it.
    Speeds are projected by `sqrt(uniform)` — a sphere seen flat — for the same reason.
  - *The shock.* `applyImpulse` with the `front` profile, called once a frame with the front's own advancing radius, kicks each star **exactly once as the shock
    reaches it** and then lets it relax back into the flow over `debris.relaxSec`. Strength `shockShortSide` (0.32 short sides/s by default) at the site, zero at
    `2.4 x` the drawn rim — the pressure wave runs ahead of the material that is lit up, and at 600 particles over a 2880x1800 buffer the drawn rim encloses about ten
    stars, which is not an explosion the field would feel. Measured displacement of the closest neighbours: **60-76 px in the first second**.
  - *One law, two consumers.* The rim is drawn on the same `r ~ t^0.4` from the same clock the debris decelerates on. Measured live across a whole episode:
    **worst disagreement 1.29x over 64 frames, 271 px of debris against a 249 px rim at the end.**
- **The shell's clock starts at the detonation**, not at the end of the flash. Two seconds of daylight between the rim and its own material is what made them two
  objects; it also made the shell appear mid-flight (a 0.27 step in one frame, which the anti-strobe test catches).
- **Both regimes.** With the hole on the debris is under gravity, crosses the disk band depth-ordered and can be swallowed (measured: 427 swallowed while one burst was
  out). With the camera on it is exempt from the depth advance and the whole cloud is translated along the far layer's streamline — see PARTICLES.md, "Transients".

**THE COMET IS A BODY.** `cometParticles()` spawns the nucleus as a real particle (`spawnBody`) on a **long chord, 1.1–1.6 short sides**, at a measured multiple of the
field's own speed. `cometRatio` is 3.2 (slow) to 7.5 (fast) and every family differs; six seconds is the floor on a pass, which is what binds with the hole on.
Measured live on the tablet: a **"slow" comet at 85 px/s against a field at 23 px/s — 3.7x — crossing 1523 px of screen in 18 s** with the camera on, and 411 px/s
against 184 px/s with the hole on. v9 drew it along a captured Bezier over a duration between 4 and 65 s that had no relation to how fast anything else was moving.
- **The tails come off the velocity.** A dust tail is material left behind, so it trails the motion and curves off the path — in both regimes. An ion tail is gas driven
  off by light, so it is anti-sunward with the hole on and **trails the motion with the hole off, because the camera regime has no light source in it**. The two
  crossfade on the hole's own envelope. And a hard clamp: no tail is ever within 80° of the heading, whatever the light is doing. Measured over 64 headings and over a
  live pass: **worst ion 0.0°, worst dust 14.9° from straight behind, nothing ever in front.** v9 pointed BOTH tails away from the screen centre, so a comet flying
  inward wore its tail on its face.
- The nucleus is a particle, so it lenses, occludes and is depth-ordered; it **sheds motes** along its path (11 alive at once, each on a few seconds of its own); and
  the chord curves — by gravity with the hole on (velocity turned **29.5°** on the way past, a real hyperbolic pass) and by rotating the peculiar channel at the
  family's own `cometTurn` rate with it off (**47 px of bow** over a 1523 px chord).
- With no pool behind it — the offscreen sheets, `particlesEnabled` false — `cometState` is byte-for-byte v9, which the suite pins.

**THE STORM AND THE PASSAGE, SMALL ON PURPOSE.** A fireball's terminal flash is the same mechanism one size down: `brightenNear` (0.26 short sides, gain 0.75, 1.4 s) plus
a 14-fragment spray, fired once per fireball on the frame its own flash peaks. Nothing else about the storm changed. The nebula passage is handed to the field as a
cloud (`Physics.setCloud`): material inside it is held back — with the camera on, its approach slows, so it moves slower AND stays smaller AND stays dimmer, all three
depth cues together — and takes `tint` of the cloud's own colour. Measured: **89.7 %** of a control run's speed inside a `drag` 0.9 cloud over twelve seconds, **99.8 %**
outside it, 77 particles in the cloud at once.

**NEW CONFIG.** `events.supernova.debrisCount` (pair, 0–480, default [180, 370]) and `events.supernova.shockShortSide` (0–2, default 0.32); `events.nebula.drag` (0–2,
default 0.55) and `events.nebula.tint` (0–1, default 0.30); `particles.debris.maxAlive` (integer 0–480, default 400) and `particles.debris.relaxSec` (0.05–12, default
1.6). Every one of them is carried by the defaults, so `starfield.json` needs no edit; 0 on either `debris` key turns the footprint off and gives the atlas rows back.

**COST.** The transient reserve is allocated whether or not an event fires, because a resize of the sampled texture cost 13 ms → 6700 ms per frame on llvmpipe and never
recovered: on his 2880x1800 tablet at the shipped 600 stars the atlas goes **112 → 176 rows, 112 → 176 KiB per canvas**, and the live layout never exceeds it through a
whole supernova. The hot loop pays one hoisted boolean while no kick is alive, two adds per particle per frame for the drawn velocity, and one distance test per
particle per live glow only while a flash is lit.

**v10, LIVE on his tablet (2880x1800, hole OFF, the regime he runs).** `caelestia shell starfield fire supernova tablet ''` and `fire comet tablet ''`, `grim -o tablet`
every 0.42 s:
- **The supernova is a star.** The precursor is a real near particle with its own four-point flare: warm orange, swelling and brightening over ten seconds while it
  travels with the field, going blue-white, then detonating into a cloud of individual fragments. Screen mean over the 80-frame sequence: **0.22 (the star) -> 41.6 (the
  flash, 5,181,017 of 5,184,000 pixels lit) -> 2.87 and falling** as the shell leaves, and the sky returns to #000000. Captures:
  `v10-supernova-precursor-tablet.png` (the swell, 3x gain), `v10-supernova-lifecycle-tablet.png` (star -> swell -> collapse -> debris + rim, nine frames),
  `v10-supernova-flash-tablet.png`, `v10-supernova-debris-trails-tablet.png` (max composite of 28 frames — hundreds of ejecta tracks radiating and decelerating,
  hot-white through yellow to orange, with the drawn rim running THROUGH them), and the raw sequences `v10-sn-*.png` / `v10-sn2-*.png`.
- **The comet's tails trail it.** Fired with the camera on, it crossed 977 px in 9.2 s (**106 px/s** against a field at ~23 px/s) moving DOWN-RIGHT with the narrow blue
  ion tail and the broad warm dust tail both pointing UP-LEFT, the dust lagging and curving off the path. Captures: `v10-comet-tail-tablet.png` (six crops along the
  pass), `v10-comet-pass-trails-tablet.png`, sequence `v10-cm-*.png`.
- **Both regimes.** `starfield-hole on`, then both fired again: the remnant's filament web sits in a field streaming into the hole and its debris is drawn out by
  gravity — `v10-holeon-supernova-comet-trails-tablet.png`, sequence `v10-hole-*.png`. Restored to off.
- **Cost.** `qs` process CPU, utime+stime over a 12 s window on three outputs: **33.9 % of one core idle, 33.8 % through a detonation and its shell** — no measurable
  change, against a ~35 % budget. GPU **3-6 % at 22.4-23.7 W** over the same runs (`nvidia-smi`), against an 8 % budget. Debris sizes were cut from
  `[0.9, 3.1] x optics` to `[0.8, 2.6] x sqrt(optics)` after the first live run: particle sizes are physical pixels and are not optics-scaled, so the full optical
  factor made the fragments 2.7-9.2 px against a 2.4-4.8 px near star and they read as bubbles.

**HARNESSES.** `tools/supernova_harness.qml` (27 checks) and `tools/comet_harness.qml` (18) load the real `Starfield.qml` with its real pool, fire through `pushEvent`
and measure the pool, in both regimes. Run them the way the others are run:
```
cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml tools/supernova_harness.qml
```

v9, THE WARM START: v8 based every schedule on `previous ? previous.start : s.clock`, so a family with no previous episode waited a FULL random interval from the moment
the shell started — after a restart the supernova was 21–48 minutes away, the kilonova 36–84 and the burst 42–108, and the first minutes of every session, the ones he
actually watches, could not contain a dramatic event at all (his report, ledger 2284). The FIRST episode of each family now lands uniformly in **[0.3, 1] × that
family's own interval MINIMUM**, and the first DRAMATIC one is additionally capped at `warmStartCapSec`, 240 s. Both bounds are divided by `events.rateScale` like every
other interval, so at rateScale 2 the first supernova is at 120 s and at 0.5 it is at 480 s; the shared `dramaCooldownSec` is applied AFTER the cap, so the supernova
takes the early slot (it is scheduled first) and the kilonova and the burst queue a cooldown behind it. A warm-started dramatic episode reserves on INSTANT slot
occupancy instead of on any overlap across its whole life: ownership is sticky and claimed in the first second, so a free slot at its start is all it needs, and the
three long quiet families would otherwise straddle the four-minute window and push it past the very cap the warm start exists to enforce; anything that collides later is
retired and rescheduled by publishPhenomena, which already exists for that. `_state.firstEpisode` keeps it a per-process first, so a retired phenomenon reschedules on
its ordinary interval and retirement can never loop. Pinned in `test-events.mjs`.
v9, THE SUPERNOVA: a force-fired v8 supernova on his 2880x1800 tablet was a ~40 px dot with a soft halo (`starfield-v2/evidence/v8-fire-supernova-tablet-tiny.png`).
It is a four-phase LIFE CYCLE now, on its own kernel — **style 6, `supernovaField`** — and its own four uniform vectors (64 B of the merged v9 block; UBO reflection 1600 → **1840 B** of 16384 with all three v9 features in), because
one supernova is alive at a time: `dramaCooldownSec` is 900 s against a ~290 s life, and the tests pin that.
**1 Precursor** (`precursorSec` 10–20 s): the star brightens, reddens and pulses faster. The pulse phase is the INTEGRAL of 1/period, so the period can shorten from
3.2 s to 1.0 s without the pulse ever jumping, and its amplitude eases to nothing over the last 1.5 s — a swing left mid-stroke when the collapse takes over would be a
step. The field's own stars cannot be addressed individually (they are a procedural hash grid), so this star is DRAWN at the site the shell will use; it is the same
object one phase earlier, and it is the one phase that carries his palette, because a star is where a palette belongs.
**2 Core collapse** (`riseSec` ≥0.8 s eased, then `holdSec`): a white-blue flash `flashShortSide` across (0.15–0.25 short sides at the 64/255 contour) with eight
diffraction spikes (`spikeGain`), and `skyLift` — a GLOBAL lift that reaches every pixel. It SCALES the sky already there by 1 + 2.5·lift and adds a flat
0.09·lift haze on top, so it lights the whole screen and still returns to exactly #000000: a multiply leaves a black pixel black, and both terms ease to zero with the
flash. Its falloff is 0.55 of the long side, so the corners sit at 56 % of the centre — global, but with a gradient, so it reads as light arriving. `main()` gains four
lines for it; nothing else in the shader knows about it.
**3 Shell** (`shellSec` 30–90 s): a rim-brightened filamentary shock. Sedov-Taylor, r ∝ t^0.4 (measured 0.400), reaching `shellShortSide` (0.25–0.40 short sides
across), broadening as it goes, cooling white → yellow → orange-red, with a hotter, narrower inner rim that dies first. `filaments` is how deeply the web breaks the
front's radius AND its brightness — a ring broken only in brightness still reads as a circle.
**4 Remnant** (`remnantSec` 2–5 min): a two-tone teal/red filament web, `remnantGain` faint, advected by its own noise and fading to nothing, with the neutron star the
collapse left behind blinking at the centre (`pulsarGain`, `pulsarPeriodSec` ≥0.8 s, trough ≥0.55 of peak — the pulsar family's own anti-strobe floors). It grows out of
the shell's last 40 % rather than replacing it, so there is no moment where one ends and the other begins.
**The filament field** is value noise on a POLAR grid: `snPolar`, N cells around the circle so the angular index wraps exactly and nothing tears at atan's branch cut,
two octaves (24 and 48 cells), ridged into filaments, two channels per call so the ridge and the two-tone pick share four hashes. Angular harmonics were tried first and
are the wrong tool — locked harmonics make a rosette, and warping them by radius to break it makes a kaleidoscope or a pinwheel, and this sky has no spiral in it. The
field is measured in the REMNANT's radius, not the shell's, and `snShell.z` is published from the first frame for that reason: the medium's inhomogeneity does not
expand, the shock LIGHTS IT UP as it passes.
**Where it is.** Every other phenomenon is nailed to the pixel it was placed on, which in the camera regime makes it the one thing on screen that is not moving. A
supernova travels on the FAR layer's own streamline instead: u = (r/R)²/2 advancing at the rate the far grid advances, with the grid's cell factor cancelling between
`advanceCells` and u, so it is that layer's motion rather than a copy of it — it reverses with `motion.camera.direction`, freezes with `speed` 0, slows as 1/r with
radius, and is FIXED with the hole on, since `_state.camFlow` carries the regime blend and the 30 s crossfade eases the drift in without a step. It does not SCALE with
the drift: that flow is area-preserving (tangential stretch r′/r, radial squash r/r′), so its isotropic magnification is exactly 1 and the remnant's apparent size is its
own expansion — which is the truth for a source that far away. The particles' z/z′ perspective was the other candidate and cannot carry a life cycle at all: at the
shipped `speed` 6 and `depth` 16 the camera crosses the whole depth in 60 active seconds, so a 3-D-anchored event would leave the screen before its shell finished.
Channels: head=(x, y, coreSigmaPx, peak), colour=(r, g, b, 6), tail01=(haloSigmaPx, haloGain, coreGain, shellGain), shape=(shellRadiusPx, shellWidthPx, filamentAmp,
toneWeight), plus `snRemnant`=(x, y, skyLiftGain, skyLiftRadiusPx), `snTone`=(secondR, secondG, secondB, advectionPhase), `snShell`=(innerRadiusPx, innerGain,
nebulaRadiusPx, nebulaGain), `snExtra`=(spikeGain, spikeLengthPx, pulsarGain, seedAngle). Every gain except the sky lift is a fraction of head.w, the same convention
style 3 uses. The advection phase is the episode's own age × 0.05 and is NEVER wrapped: it indexes a noise field, where a wrap is a jump.
v9 supernova key changes: `precursorSec`, `flashShortSide`, `skyLift`, `spikeGain`, `shellSec`, `filaments`, `remnantGain`, `pulsarGain`, `pulsarPeriodSec` are new;
`everyHours` becomes [0.5, 1] (one every 30–60 min at rateScale 1), `shellShortSide` [0.25, 0.40], `shellGain` 0.55 (cap 0.80), `decaySec` [25, 60] and `remnantSec`
[120, 300]; `shellShortSide` and `flashShortSide` are the drawn DIAMETER as a share of the short side, not a radius. `echoGain` and `echoDelaySec` are DROPPED — the
remnant replaces the light echo — and a file carrying either warns with its index and is otherwise unaffected.
`starfield-shell fire <family> <screen> '{"key":value}'` takes a third argument now: a JSON object written straight onto the captured episode, which is how
a phase is addressed. All three arguments are REQUIRED -- Quickshell checks the arity and QML will not take a default on an annotated parameter -- so `''` is how you
say "every screen" and "no overrides": `starfield fire shower tablet ''`. A supernova's duration is recomputed from its phases afterwards, so `fire supernova tablet '{"precursor":4,"shellSpan":20,"remnant":40}'` is the
same shapes in a quarter of the time rather than a life cycle truncated mid-phase. Invalid JSON is ignored; this is a test hook.
`modules/background/tools/supernova-sheet.mjs` + `supernova_sheet.py` render and measure the life cycle offscreen through the real kernels and the real CPU envelope,
one frame per named phase moment, reporting peak/255, lit pixels and both the 2/255 and 64/255 contours as a share of the short side. Measured that way on a
2880x1800 buffer, one episode (precursor 12.7 s, shell 88.4 s, remnant 129.6 s, 232.9 s in all), lit DIAMETER as a share of the short side at the 2/255 contour and the
64/255 disc contour: precursor 0.06 / 0.01, flash peak **1.89 / 0.24** (the 1.89 is the sky lift reaching the corners of the screen), shell at 5 s 0.32 / 0.15, at
25 % 0.20 / 0.18, at 50 % 0.27 / 0.24, remnant mid 0.48 / 0.01, remnant end 0.00 — it ends at exactly black.
LIVE on his tablet (2880x1800), `fire supernova tablet '{"precursor":6,"shellSpan":24,"remnant":45}'`, 85 `grim` frames 0.72 s apart, camera regime: the flash lit
**5,181,430 of 5,184,000 pixels** and took the whole screen's mean to **43.4/255** for about two seconds, then the sky returned to #000000. The site DRIFTED with the
far layer over the shell and the remnant, 882 → 938 px from the screen centre in 36 s against 935.6 px predicted by u = u0 + rate·t — the streamline law, measured, not
asserted. With the hole on and the same fire, the episode landed at r ≈ 1100 px, its shell never touched the disk, and the flash still took the whole screen to
36.7/255 and brightened the disk with it. Cost on the same shell, same three outputs, `nvidia-smi` and `qs` process CPU over 20 s with a supernova running on ALL
THREE outputs at once against 20 s with none: GPU **3.9 % → 4.0 %** at **22.7 W → 22.7 W**, `qs` **33.1 % → 32.7 %** of one core — no measurable change in either.
On the offscreen rig at 2160x3840 (llvmpipe, min of three runs of 200 fenced draws, `BHRENDER_REPEAT`): empty 0.624 ms, flash peak 0.713, shell half 0.673, remnant mid
0.689 — the whole life cycle is +0.05 to +0.09 ms per 4K frame on a SOFTWARE rasteriser. Captures: `starfield-v2/evidence/v9-supernova-live-tablet-{sheet,precursor,
flash,shell,remnant,trails}.png`, `v9-supernova-live-tablet-holeon-{sheet,flash,remnant}.png`, `v9-supernova-lifecycle-offscreen.png` and `v9-supernova-metrics.json`.
**THE METEOR STORM is `events.shower`, and it is ONE slot.** v8 drew a shower as six ordinary meteors on a 30-60 s timer, staggered 4-12 s apart and capped at 0.60 gain:
one meteor at a time, dimmer than a normal one, radiating from a point nobody could infer from six samples. He could not spot it (ledger 2284). A storm now has a **radiant**,
a **rate hump** and **fireballs**, and every ordinary streak in it is generated by the shader.
- **Radiant.** One point, `radiantBias` (0.28) short sides off the wandering centre, never inside 1.25x what the hole DRAWS (the keep-out the phenomena use, 887/592/740 px of
  material -> 1109/740/924 px), and always ON the buffer with a 0.04 short-side margin: pushing a radiant past the keep-out can send it off the short edge, and a shower whose
  convergence point is off-screen reads as meteors going one way rather than as a storm. 200 captures per output, 0 on the hole, 200 on the buffer (`test-storm.mjs`).
- **Perspective.** The projection is gnomonic about the radiant: a shower meteor travels a great circle away from it, which projects to a straight RADIAL line whose apparent
  length is `f*(tan(theta) - tan(theta - trail))` with `f` the short side. A meteor beside the radiant is a point and one fifty degrees away is a long streak, for free -
  `streakShortSide` [0.10,0.30] is that length at the 45 deg reference, and on DP-3 it measures 5.3-9.6 % of the short side at 6 deg from the radiant, 7.5-23.1 % at 34 deg and
  12.8-37.4 % at 52 deg. It is also why one angle compare can reject a candidate streak: every streak lies on a ray from one point.
- **Rate.** `durationSec` [70,130] is the WHOLE episode; `rampFraction` (0.32) splits it into a build-up, a plateau and a decay of 0.62 of what is left - 88 s = 28 + 23 + 37 by
  default. The rate eases from the ORDINARY meteor rate (2/(meteors.interval sum), 1/82 s) up to `peakRate` (6 a second) and back, both shoulders the same smoothstep, so a
  storm arrives out of the sky the viewer already has instead of switching one on. 331 streaks in a default storm; worst frame-to-frame step 0.6 % of the peak.
- **PHASE is the mechanism.** The CPU publishes the integral of that hump - the storm's cumulative expected meteor count - in closed form. Streak k launches where phase reaches
  k, so k advances at exactly `rate` per second whatever the hump is doing, and the kernel recovers a streak's age as `(phase - k)/rate`. That inversion is EXACT for a constant
  or a linear rate and stretches a long streak's apparent life by `age*r'/r` under the hump's curvature, which is smaller than the variety draw beside it and cannot move the
  rate, because the rate is phase's derivative. Nothing about an ordinary storm streak reaches the CPU.
- **Variety.** Brightness is a cubed uniform - many faint, few bright - floored where a head still clears 139/255 against a bright star's 243. Colour follows SPEED: green-teal
  fast, orange slow, with `paletteMix` (0.30) of the sky's own palette mixed into both. `earthgrazerShare` (0.08) draws a slow, long streak far from the radiant;
  `fragmentShare` (0.06) splits a head into three after its own midpoint. `headPx` [3,6] is the head sigma at a 2160 short side, spread across that pair per streak.
- **Fireballs.** `fireballs` [1,3] per storm, spread across the peak, each on an ordinary transient head as **style 7**: a nucleus, a terminal flash 5-10 % of the short side
  across (a 0.90 s Gaussian in time - 3.3 % of its own peak per frame at 30 Hz, inside the 5 % the anti-strobe floors are proven against) and a persistent train that drifts and
  SHEARS for `trainSec` [12,26] seconds after the head has gone. A fireball is AIMED: its ray and angular speed are solved so the flash lands on the buffer, and with the hole on
  the whole ray - not only its far end - must miss the keep-out, because a train is a slot and a slot drawn across the shadow shines through it. A fireball with no clear ray in
  forty tries is dropped rather than aimed through the disk (1-2 in 400).
- **Both regimes.** A storm streak is SKY: it is accumulated into the far-field, so one passing the hole is lensed by the same warp the background stars get, is eaten by the
  shadow and sinks behind the disk. No other event has that, because no other event is evaluated at a pixel. In the camera regime the radiant takes the shared centre wander and
  the camera's roll and creeps radially at the far plane's own rate - a translating camera does not carry a direction at infinity off the screen, and integrating the near
  field's magnification here would have done exactly that (4.8x over a 100 s storm).
- **Cost.** Four vec4 (64 B of the merged v9 block, UBO 1600 -> 1840 B of 16384) however many streaks are in the air, and a per-pixel loop over a time-sorted window of `ceil(rate*5.5)+3` candidates, 36 at
  the default peak, hard-bounded at 48 (which is why `peakRate` validates at 8: `ceil(8*5.5)+3 = 47`). A candidate costs one integer hash and one angle compare before it is
  rejected, which is what nearly every candidate costs for nearly every pixel. Live on his machine, three storms at once on all three outputs against the same shell idle:
  `qs` CPU 33.4 % of one core either way (no measurable change) and `nvidia-smi` 4 % -> 6 % of the GPU - +2 points for 18.5 Mpx of storm at 30 fps, about 0.3 ms a frame
  normalised to one 4K output.
Storm keys CLAMP like the rest of the v4 shower block rather than rejecting. Bounds: `everyHours` ordered 0.25-168, `durationSec` ordered 20-600, `gain` 0-1.5,
`rampFraction` 0.1-0.6, `peakRate` 0.2-8, `radiantBias` 0-0.45, `paletteMix` 0-0.45, `streakShortSide` ordered 0-0.45, `headPx` ordered 1-12, `fireballs` ordered 0-6 (rounded),
`trainSec` ordered 0-60, `earthgrazerShare` and `fragmentShare` 0-0.35. v8's three keys keep their names, their meaning and their clamping; only their bounds widened, which
cannot reject a file that used to validate.
`starfield-shell fire <family> <screen> <overrides>` now takes the TRANSIENT families too - `fire storm tablet ''`, `fire shower tablet ''`,
`fire meteors '' ''`, `fire comet '' ''`, `fire satellites '' ''`, `fire slowWanderer '' ''` - as well as the seven radial names and `nebula`. v8 only knew the radial
names, so `fire shower` did nothing.
Storm evidence, all measured rather than described: `modules/background/tools/test-storm.mjs` (55 checks, `--report` for the per-output table),
`tools/storm-sheet.mjs` + `tools/storm_sheet.py` (offscreen frames across the hump through the real kernels, then streak counts and lengths),
`starfield-v2/evidence/v9-storm-offscreen-sheet.png`, and live on the tablet: `v9-storm-live-tablet-peak.png`, `-trails.png` (a 36 s max composite - the radiant is the point
every streak comes out of), `-sheet.png`, and `v9-storm-live-tablet-holeon.png` / `-holeon-trails.png` for the lensed regime.
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

## v11: PROCESS MODEL — THE SKY IS ITS OWN QUICKSHELL INSTANCE

`shell.qml` and `starfield.qml` are two entry points into ONE repo, on branch `local`, rebased together. The sky runs in the second:
```
nice -n 15 qs -p ~/.config/quickshell/caelestia/starfield.qml -n -d     # = starfield-shell start
```
`-p` on a FILE makes that file's directory the config root, so `qs.services`, `qs.components`, `qs.utils` and `Caelestia.*` resolve exactly as they do for `shell.qml`.
`starfield.qml` mounts `StarfieldWindows.qml` (one `StyledWindow` per enabled screen, namespace `caelestia-starfield`, `WlrLayer.Background`, opaque black, exclusion
Ignore, empty input mask) and each window mounts `StarfieldLayer.qml` — the renderer's property wiring, which `Background.qml` mounts instead when the sky runs in-shell.
One copy of the wiring, two possible hosts.

**Why.** Measured 2026-09-13 18:51: `qs -c caelestia` main thread at 35 % of one core, 59 threads, only the main thread busy. `Starfield.qml` runs particle physics,
packing and two `Canvas.Immediate` paints per output at 30 fps on the QML engine's main thread — the same thread every launcher, bar, notification and drawer animation
runs on, so all of them queue behind the sky. His words: "every animation of it feels laggy and slower than it was." Two processes get two main threads and two render
threads, and the kernel spreads them over different cores. Measured 2026-09-13 19:15 after the split, two outputs, desktop in use: sky main thread **34 %**, shell main
thread and every shell thread **below 0.3 %** (i.e. below the sampler's floor). The sky's own cost did not fall — it moved.

**`"process"` (top-level, default `"separate"`).** `"separate"` = the second instance draws; the shell's `caelestia-background` window drops to `WlrLayer.Bottom` and
`color: "transparent"`, one layer ABOVE the sky's, so there is NO map-order dependency between the two clients and either can restart alone. `"shell"` restores the
v10 in-process path (Background.qml mounts the layer, its window goes back to Background+black) for A/B. **Changing this key needs both processes restarted** —
`starfield-shell restart` and `caelestia shell -r` — because it decides which process owns a window, not what a window draws.

**`~/namealle/scripts/starfield-shell`** is the whole interface: `start` (idempotent, and what `execs.lua` runs at login), `kill`, `restart` (needed after ANY edit to
the sky's QML — hot reload is off), `status` (pid, nice, both namespaces per output), `fire <family> [screen] [overrides]`. Binds: `CTRL+SUPER+SHIFT+R` kills both,
`CTRL+SUPER+ALT+R` toggles both (shell up → kill both, shell down → start both; `~/namealle/scripts/shell-toggle`), `CTRL+SUPER+ALT+K` restarts the sky alone.

**IPC moved with it.** `starfield fire` and `ambient dump` now answer on the SKY's socket: `qs -p …/starfield.qml ipc call starfield fire nebula tablet ''`, which is
what `starfield-shell fire` wraps. `caelestia shell starfield fire …` still reaches the shell's idle copy of the service and draws nothing while `process` is
`"separate"`; `caelestia shell ambient dump` answers **"Target not found"**, because naming `Ambient` only on the in-shell branch of `shell.qml`'s lock
binding is what keeps the whole reactive poller — a 250 ms timer, `/proc` reads, `nvidia-smi` — out of the shell. That "Target not found" is the positive proof the
shell is no longer doing the sky's work. Use that positional form: `caelestia shell ipc call …` answers "Target not found" for every target, `drawers` included
(checked 2026-09-14), so it proves nothing.

**starfield.json is unchanged and still hot-reloaded**, now by whichever process is drawing. Proved 2026-09-13 with no restart: `fps` 30 → 2 dropped the sky's main
thread 34.2 % → 0.2 %, and back to 34.2 % on restore. `starfield-hole` and `starfield-camera` edit that file and need nothing restarted.

**The session lock** is the one bit of shell state the sky cannot read for itself, and `rules.js runningFor` pauses the renderer while it is up. `shell.qml` publishes
it to `~/.local/state/caelestia/starfield-lock` (one byte, written only on lock/unlock) and `starfield.qml` binds `Ambient.locked` to a `FileView` on it. Nothing polls.

**What the shell keeps:** the desktop clock, the Visualiser, the bar, the drawers, the lock — everything except the sky, all of it drawn above the sky from the shell's
own Bottom-layer window. `Visualiser.qml` takes the sky as its blur source; out of process that source is a different client's pixels and unreachable, so it falls back
to the (inactive) wallpaper Loader — an empty Item. The bars still draw; what they lose is the blurred copy of the sky behind them, and only when
`background.visualiser.{enabled,blur}` are both on. His config has `visualiser.enabled: false`, so on this machine it loses nothing visible.

**nice.** The script asks for 15 (absolute, not `nice -n` relative — an agent shell measured at -4). It does not get it: `ananicy-cpp` pins every process named `qs`
to its `Service` type (nice 10, ionice 6) and re-applies within 5 s — measured. The rule is `/etc/ananicy.d/00-default/DEs-and-WMs/dank-material-shell.rules` and it
matches by process NAME, so it cannot tell the two instances apart. Both run at nice 10, which is what the shell always ran at. Changing that means system config.

## v11: WHAT A FRAME COSTS, AND THE PROBE THAT SAYS SO

**`starfield-shell perf on | dump | off`** turns on the renderer's own per-frame clock, per output. `dump` prints one JSON object per output and RESTARTS the window,
so two dumps are two intervals and a leak shows as a rising line instead of an average creeping up. Nothing is timed until `on`: every probe sits behind one null
test of `_perf` and makes no clock call while it is off. The clock is an `ElapsedTimer` (nanoseconds) injected from `services/Starfield.qml`, deliberately NOT
declared in `Starfield.qml`, because the headless harnesses load that file under plain `/usr/lib/qt6/bin/qml`, which has no Quickshell types.
`tools/perf_sample.sh <label> [window] [outfile]` puts it next to per-thread CPU for BOTH Quickshell processes, the GPU and Tctl, over the same window;
`tools/perf_leak_run.sh` restarts the sky and samples at 1, 5, 30 and 60 minutes.

**Where a frame goes** (2026-09-17, 3 outputs, 30 fps, ~600 particles each, hole off so the camera regime is live, `local` da77c651 → after the five fixes below).
Per output, ms on the main thread:

| phase | before | after | what it is |
|---|---|---|---|
| `ParticlePhysics.advance` | 0.90–0.98 | 0.63–0.75 | the integration |
| `ParticleAppearance.render` | 1.17–1.34 | 0.94–1.02 | per-particle optics into the flat instance array |
| `ParticleBinning.build` | 0.97–1.47 | 0.50–0.58 | the 32 px bin grid |
| `ParticlePacking.pack` (in `onPaint`) | 1.20–1.46 | 1.02–1.16 | the instance rows and bin headers into the atlas bytes |
| publish uniforms + events | ~0.30 | ~0.30 | ~60 shader property writes and the scheduler |
| **whole frame + paint** | **4.65–5.52** | **3.61–4.03** | |
| **share of one core** | **13.5–16.3 %** | **10.7–12.0 %** | |
| worst single frame | 21.6–23.8 ms | 4.3–4.5 ms | the descriptor atlas rebuild |

Sky main thread, three outputs uncovered and idle: **47.2 % → 33.1 %** of one core; Tctl 58.2 → 52.2 °C. With a supernova's ejecta, a storm and a nebula alive on
all three (266–326 transients per output, ~830 particles), the sum is 35.2 % — the debris reserve is already in the atlas allocation, so a live event costs about
what an idle field does.

**The engine is the floor.** QML's JS engine runs the same numeric kernel 14× slower than node: 211 ns per particle-iteration against 15 ns, measured this session
with an identical loop, and `QV4_FORCE_INTERPRETER=1` only takes it to 301 ns — so the JIT is on and this IS its speed. A call that wraps a `clamp` costs 125 ns
against 25 ns for the arithmetic inside it, which is why `smooth()`, `supportFor()`, `rgb()` and `cameraDepthOf()` are inlined at their hot call sites (each marked
KEEP IN STEP with the function it copies). Six hundred particles × three passes × 30 fps × 3 outputs is around 160 000 engine-ops a second per output and there is
no more fat on it: **the remaining 33 % is the cost of running this simulation in QML at all**, not waste. Below ~20 % needs the C++ `QQuickItem` in
`V12-FUTURE-GPU-CPP.md`.

**`Canvas.Threaded` is a loss — do not re-propose it.** V12 lists it as the one small unverified candidate. Measured 2026-09-17: Qt runs the `onPaint` JS on the GUI
thread either way and only the rasterisation crosses, so nothing moved off the main thread; it cost 15.4 → 15.8 % of a core per output, added a `QQuickContext2D`
thread and put 0.6 points more on `QSGRenderThread` for the command buffer. Reverted, with the reason written next to `renderStrategy`.

**The five fixes**, each measured on its own (`evidence/v11-perf-*.txt`), all of them work whose result was already known:
1. **Gravity that is off.** The camera regime sets `gravity = (1-blend)² = 0`, so `mu` is exactly 0 — and `step()` computed `-mu/(r²·√r²)` twice per substep per
   particle to add nothing. Guarded on `mu`, with `cameraDepthOf`'s fast path and two `smooth()`s inlined beside it. −0.35 ms/frame.
2. **A tide that is off.** `render()`'s continuous tidal deformation is multiplied by the hole's enable envelope, exactly 0 with the hole off; a cube, two
   smoothsteps and a dot product were computed per particle to reach zero. The relaxation of the remaining stretch is the same arithmetic with target 0. −0.35 ms.
3. **Bins that are empty.** Six hundred particles reach a sixth of a 14400-bin grid and both the binner's prefix sum and the packer's header pass walked all of it,
   every frame. `Binning.build` records a bin the first time something lands in it and all three passes run over that list. −0.5 ms on the portrait output.
   `tools/pack-equivalence.mjs` decodes every bin the way `starfield.frag` does, from both layouts, over 400 frames: 129600 bins, zero differences.
4. **An atlas that did not change.** The descriptor BMP is 64×1536: 256 rows of sealed descriptors and 1280 rows of entry ledger that only `publishEntries`
   (particles OFF) ever writes. Bottom-up rows put the ledger FIRST in the byte stream, and both halves are multiples of three, so the base64 of the whole is the
   concatenation of the two base64s — the ledger half is encoded once and cached. **Worst frame 29.0 → 6.3 ms**, which is the dropped frame that used to land every
   30 flow seconds per output. `tools/atlas-equivalence.qml` proves the data URL is byte-identical in both regimes, across thirteen seals.
5. **A normalisation done three times.** `vx/vy` was normalised in `render()`, again in `Binning.build` and again in `Packing.pack`. Stride 21 → 23 carries it once.
   An unstreaked particle's capsule is a DISC, and a disc's x-span is the same in every row, so the per-row interpolation is skipped for most of the field. −0.6 ms.

**The shell is not the sky's problem.** Measured 2026-09-17 with the sky killed AND all three outputs uncovered (no fullscreen window anywhere), `qs -c caelestia`
used **0.1 % of one core** over five minutes: 3.1 s of CPU in 56 minutes of uptime, three child processes, no growth. The 21–28 % seen on 2026-09-14 does not
reproduce in any state reachable from his current configuration.
