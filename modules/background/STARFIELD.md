# Starfield v2
`~/.config/caelestia/starfield.json` is watched, with a 150 ms reload debounce; XDG_CONFIG_HOME is respected.
Missing/invalid JSON, a non-object document or missing `screens` disables every output; removed keys restore defaults.
One validated snapshot owns configuration; the shell never writes it. Defaults (exact output names, no wildcard):
```json
{
  "screens": [], "density": 1, "driftSpeed": 3.5, "driftDirection": 165,
  "twinkle": 0.22, "flareFraction": 0.003, "brightness": 1,
  "backgroundColor": "#000000", "edgeLift": 0, "fps": 30,
  "motion": {"mode": "radial", "radialSpeed": 6, "centreWander": 0.012, "zoom": 0.003,
             "reversals": false, "wander": 0.8, "rotation": 0.5},
  "variety": {"enabled": true, "seed": 1}, "variables": {"fraction": 0.006},
  "meteors": {"enabled": true, "interval": [45, 120], "companionChance": 0.04, "fireballChance": 0.01},
  "comet": {"enabled": true, "interval": [900, 1800]},
  "satellites": {"enabled": true, "interval": [240, 480]},
  "reactive": {
    "enabled": true, "contextScope": "perScreen", "processPresenceWeight": 0.35, "paletteBudget": 0.45,
    "birthTauSec": 60, "liveTauSec": 90, "maxChangePerSec": 0.005,
    "matchers": [
      {"id": "htb", "class": "^zen$", "title": "\\bHTB\\b|Hack\\s*The\\s*Box|hackthebox\\.(com|eu)", "flags": "i"},
      {"id": "steam", "class": "^steam$", "flags": "i"},
      {"id": "game", "class": "^steam_app_[0-9]+$", "flags": "i"},
      {"id": "terminal", "class": "^(foot|footclient)$"},
      {"id": "agentWindow", "class": "^(foot|footclient)$", "title": "^[✳◑]"}
    ],
    "rules": [
      {"signal": "htb", "add": {"green": 0.32}},
      {"signal": "agent", "add": {"violet": 0.14, "twinkle": 0.04}},
      {"signal": "heat", "add": {"warm": 0.20}},
      {"signal": "load", "add": {"warm": 0.10, "flow": 0.25}},
      {"signal": "loadRising", "add": {"flow": 0.05}},
      {"signal": "rain", "add": {"calm": 0.22, "brightness": -0.25, "twinkle": -0.15}},
      {"signal": "wind", "add": {"flow": 0.04}},
      {"signal": "night", "add": {"calm": 0.20, "flow": -0.15, "twinkle": -0.15, "meteor": -0.25}},
      {"signal": "idle", "add": {"calm": 0.10, "flow": -0.10, "meteor": -0.10}},
      {"signal": "media", "add": {"twinkle": 0.05}},
      {"signal": "steam", "add": {"violet": 0.03}},
      {"signal": "game", "add": {"warm": 0.06}},
      {"signal": "terminal", "add": {"calm": 0.04}},
      {"signal": "memoryPressure", "add": {"calm": 0.05}},
      {"signal": "network", "enabled": false, "add": {"twinkle": 0.03}},
      {"signal": "notifications", "enabled": false, "add": {"meteor": 0.04}}
    ]
  }
}
```
Finite numbers clamp to ranges; wrong types use defaults. Arrays replace defaults; empty arrays disable all their entries.
Ranges: density/brightness 0–3, driftSpeed 0–30, driftDirection −360–360°, twinkle/edgeLift 0–1, flareFraction 0–0.025, fps 1–60 (rounded); color is opaque #RRGGBB.
Motion mode is radial or drift; radialSpeed 0–26 device px/s at radius shortSide/2 on a 2160-short-side output, scaled by shortSide/2160; centreWander 0–0.05 short sides.
Zoom is 0–0.15; radial default ±0.003 with 240–420 s periods, centre periods 1800–2700 s; reversals defaults off. Drift retains wander 0–2, rotation 0–3°, zoom default 0.025 and all old keys.
Variety enables slow moods; seed is a rounded 0–2147483647 integer. Variable fraction 0–0.05; meteor companion/fireball chances 0–1. All event intervals are ordered pairs in seconds, ≤3600; minima: meteor 3, comet 60, satellite 45.
Reactive scope is perScreen; process weight 0–1 and palette budget 0–0.45. Filter timing fields are fixed to the shown contract constants; other values normalize to those defaults.
Matchers/rules default enabled; at most 32 of each are considered. Matcher IDs are unique 1–48 character identifiers; built-in signal names are reserved except agentWindow.
Class is required, title optional; regexes compile on config changes, max 256 characters, flags only i/m (no duplicates); backreferences, lookarounds and repeated groups are rejected.
Invalid matchers and unknown-signal rules disable only those entries. Rules are data only: signal plus add coefficients −1–1 on green/violet/warm/calm/twinkle/brightness/flow/meteor, optional enabled.
Each target = clamp(neutral + sum(signal × add), 0, 1); neutral birth is (0,0,0,0.5), live is (0.5,0.5,0.5,0.5). Green/violet/warm scale proportionally if their sum exceeds the palette budget.
Signals include cpuLoad/cpuHeat/gpuLoad/gpuHeat/ram/vram/network/rain/wind/humidity/temperature/weatherNight/night/media/idle/agentProcess and matcher IDs; load/heat are CPU/GPU maxima.
loadRising is the maximum positive load slope; memoryPressure=max(smoothstep(.70,.95,ram),smoothstep(.75,.95,vram)); agent=max(agentWindow,processPresenceWeight×agentProcess). RAM temperature is unavailable; notifications have no source in this version.
Inputs have source-specific smoothing; stale sources lose rule weight over 120 s, weather after 3 h without receipt. Network is activity, not saturation; agent process presence includes waiting sessions.
Context counts mapped windows on that output's active or open special workspace, plus pinned windows; active weight 1, other visible 0.6, hidden/minimized 0 (occlusion is approximate).
Ambient sends targets; renderer filtering uses 60 s birth, 90 s live and 120 s meteor time constants with a 0.005/s step cap in active time.
New stars freeze their birth tint and traits, so opening/closing HTB changes future birth probabilities while existing stars finish their lives unchanged.
Privacy: match class before at most 512 title characters locally; never log, persist, transmit or hash titles, and retain only category strengths. Only selected-tab titles are exposed, not background tabs or verified URLs; no media metadata or notification content is read.
Pause: locked or a visible fullscreen>1 window freezes that output through running, retaining its Loader and history; other outputs continue. When no enabled output runs, Ambient stops polling and releases ServiceRefs; event subscriptions/config watching remain.
Suspend resets CPU baselines and derivatives without catch-up. Background.enabled still gates windows; density is static configuration and may rebuild the star composition, never a reactive control; empty pixels retain backgroundColor.
