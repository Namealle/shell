# How this fork differs from upstream

This is a personal fork of [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell).
Everything here is additive — no upstream feature has been removed, and the upstream
README is unmodified apart from a link to this file.

**Default branch:** `local` — that is where the work lives, not `main`.

**Base:** `817a220e` (2026-08-09), which is current `upstream/main`. This fork is
38 commits ahead and 0 behind, touching 29 files (+4830 / −89).

---

## Launcher

The launcher is where most of the work went.

### Clipboard picker (`;` prefix)

A clipboard history browser backed by `cliphist`, with a reading pane rather than a
plain list.

- Type `;` in the launcher to browse history; entries are ranked with the fuzzy matcher
  described below.
- Each entry gets a content-derived Material icon (URL, path, JSON, hex colour, stack
  trace, SQL, and ~35 others) instead of one generic clipboard glyph.
- Selecting an entry opens it in a reader pane that morphs out of the list row it came
  from, so the entry stays visually anchored while it expands.
- The reader is a rail of live preloaded entries — scrolling between entries moves the
  rail rather than tearing down and rebuilding a single pane, which keeps the motion
  continuous when you scroll quickly or reverse mid-animation.
- Image entries render as thumbnails in the list and expand to the full image, with
  `imv`-style zoom and pan.
- Colour entries (hex/rgb/hsl) render a large swatch plus a selectable strip of the
  value in all three notations.
- Long text entries get word wrap, line numbers, and physics-based scrolling.

Files: `modules/launcher/services/Clipboard.qml`, `modules/launcher/ClipReader.qml`,
`modules/launcher/ClipBody.qml`, `modules/launcher/items/ClipItem.qml`.

### Emoji picker (`:` prefix)

Type `:` to search emoji by name and copy on select.

Files: `modules/launcher/services/Emoji.qml`, `modules/launcher/items/EmojiItem.qml`.

### Native fuzzy search

The launcher's ranking moved from QML into a C++ `Search` singleton — fuzzy matching
with a substring fast path, plus a standalone test binary.

Files: `plugin/src/Caelestia/search{.cpp,.hpp}`, `plugin/src/Caelestia/searchcore{.cpp,.hpp}`,
`plugin/tests/search_test.cpp`.

### Other launcher changes

- Keybinds that open the launcher with text already typed, so a single shortcut can
  drop you straight into the clipboard or emoji picker. Pressing the same bind again
  while that query is showing closes the launcher (`modules/UserShortcuts.qml`).
- Mouse wheel scrolling in the wallpaper list (`modules/launcher/WallpaperList.qml`).

### Configuration

Both prefixes are configurable, alongside the existing upstream ones:

| Option             | Default |
| ------------------ | ------- |
| `clipboardPrefix`  | `;`     |
| `emojiPrefix`      | `:`     |

Set in `~/.config/caelestia/shell.json` under `launcher`.

---

## Bar

Workspace indicators use Material shapes, morphing between them natively via
`MaterialShape` rather than hand-rolled animations. Window icons inside the indicators
are preserved (`modules/bar/components/workspaces/Workspace.qml`).

## Lock screen

Portrait layout support, so the lock screen lays out correctly on rotated / vertical
monitors instead of assuming landscape (`modules/lock/`).

## Nexus

Opens on the focused monitor and sizes itself against the short edge, which fixes
placement on mixed-orientation multi-monitor setups (`modules/nexus/`).

## Brightness

Rapid brightness steps accumulate into a single DDC write instead of queuing one write
per step, and each write is read back to confirm it landed — DDC silently drops writes
under load (`services/Brightness.qml`).

## Screenshots

`Super+Shift+S` splits by mouse button: left-click saves and copies silently,
right-click additionally opens the result in `swappy`
(`modules/areapicker/Picker.qml`).

---

## Other branches

- **`spring-anims`** — replaces the shell's bezier easing curves with a C++ spring
  animation across ~450 call sites. Working but not merged into `local`; it is a
  substantial feel change, kept separate deliberately.

---

## Building

Unchanged from upstream — see [`README.md`](README.md). The C++ additions build as part
of the existing `plugin/` CMake target, so no extra dependencies are introduced.
