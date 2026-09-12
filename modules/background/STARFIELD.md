# Starfield

`~/.config/caelestia/starfield.json` is watched (`XDG_CONFIG_HOME` is respected).
Missing/invalid file or missing `screens` disables the effect; removed keys use
these defaults. The shell never writes this file. `background.enabled` still gates windows.
```json
{
  "screens": [], "density": 1,
  "driftSpeed": 3.5, "driftDirection": 165,
  "twinkle": 0.22, "flareFraction": 0.003, "brightness": 1,
  "backgroundColor": "#000000", "edgeLift": 0, "fps": 30,
  "motion": { "wander": 0.8, "zoom": 0.025, "rotation": 0.5 },
  "meteors": { "enabled": true, "interval": [10, 30] },
  "comet": { "enabled": true, "interval": [180, 300] },
  "satellites": { "enabled": true, "interval": [75, 140] }
}
```
Set `screens` to exact names, e.g. `["DP-3"]`; there is no wildcard.
`density`: 0–3 count multiplier; default roughly 3,500 device-pixel points at 4K.
`driftSpeed`: 0–30 base px/s at 1024×576, scaled by sqrt(screen area/reference area).
`driftDirection`: −360–360°, clockwise from right; 165 is down-left.
`motion.wander`: 0–2 velocity variation; smooth waves with 23–88 s periods.
`motion.zoom`: 0–0.15 fractional amplitude; default ±2.5%, 40/76 s breathing.
`motion.rotation`: 0–3° amplitude; default ±0.5°, 33/88 s gentle turns.
All camera components have depth factors 0.10/0.42/1.0; the zoom centre also wanders.
`twinkle`: 0–1; irregular 4–11 s scintillation, sparse short glints and slow fades.
`flareFraction`: 0–0.025 rarity control; default about 8 sky crosses.
`brightness`: 0–3 star intensity; `backgroundColor`: opaque `#RRGGBB`.
`edgeLift`: 0–1 optional blue-black edge light; default 0 keeps empty pixels #000000.
`fps`: 1–60 timer cap; Qt/vsync quantisation can reduce the actual rate.
Event `interval`: [minimum, maximum] seconds between starts, capped at 3600.
Meteor intervals clamp to ≥3 s; 0.55–1.15 s streaks decelerate, 18% have a companion.
Comet intervals clamp to ≥60 s; 20–35 s passages have a faint trailing fan.
Satellite intervals clamp to ≥45 s; 30–45 s passages are tiny steady points, no trail.
Each event has `enabled`; all positions, rates and companions are deterministic.
The QtQuick-only renderer uses device pixels: dust 1–2 px, capped soft bright cores.
`running: false` freezes the whole sky; writable `time` is seconds, independent of fps.
Live camera velocity/amplitude changes preserve position. Events follow active time.
Single shader pass; rebuild command is in `Starfield.qml`. Keep `.frag` and `.qsb`
together. No runtime compiler or C++ plugin installation is needed.
