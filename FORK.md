# Caelestia shell + a clipboard reader

This is a fork of [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell) that
adds one thing: a clipboard history **reader** inside the launcher, plus the emoji picker
and native fuzzy search that grew up next to it. Nothing upstream has been removed, and
the upstream README is unmodified apart from a link to this file.

**Branch:** `clipboard` = upstream + the launcher work below, and nothing else. It is
kept current by merging `upstream/main` into it, so it is never force-pushed and you can
`git pull` it.

It is a personal, experimental fork: it works on the author's machine (Hyprland,
CachyOS), it is not packaged, and it may lag upstream by a few days. Much of the code
and most of the commit messages were written with an AI coding assistant (Claude Code)
under the author's direction and testing.

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

### Configuration

Both prefixes are configurable, alongside the existing upstream ones:

| Option             | Default |
| ------------------ | ------- |
| `clipboardPrefix`  | `;`     |
| `emojiPrefix`      | `:`     |

Set in `~/.config/caelestia/shell.json` under `launcher`.

---

---

## Performance work

Found while making the reader hold up under key-mashing deep in a long history; the
second one is not specific to this fork.

- The reader no longer instantiates every entry between the top of the history and the
  one being read when it closes (it used to freeze for ~1 s, 400+ entries down), and it
  grows into its preload instead of building ~50 entries in the frame it opens.
- `Caelestia.Config`: font styles disconnect from the shared config nodes by stored
  handle instead of `disconnect(sender, nullptr, this, nullptr)`, and build their
  `QFont`s on first read. Under delegate churn that was 30% of the GUI thread. Proposed
  upstream as [#2056](https://github.com/caelestia-dots/shell/pull/2056).

---

## Trying it

Requirements beyond upstream's: [`cliphist`](https://github.com/sentriz/cliphist) storing
your clipboard (`wl-paste --watch cliphist store`), and `wl-clipboard`.

The fork changes the C++ plugin (the `Search` singleton and two launcher config
options), so the plugin has to be built and installed — copying the QML is not enough:

```sh
git clone -b clipboard https://github.com/Namealle/shell ~/.config/quickshell/caelestia
cd ~/.config/quickshell/caelestia
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DVERSION=0.0.0
cmake --build build
sudo cmake --install build   # installs to /usr/local
```

If a distro package of caelestia-shell is also installed, its plugin in
`/usr/lib/qt6/qml` wins unless the session exports
`QML_IMPORT_PATH=/usr/local/lib/qt6/qml`. The symptom of the wrong plugin being loaded
is silent: `;` and `:` simply do nothing. To try a build without installing it:

```sh
QML_IMPORT_PATH=$PWD/build/qml caelestia shell -r -d
```

Then open the launcher and type `;`. `→` opens the highlighted entry in the reader,
`↑`/`↓` browse entries from inside it, `←` goes back, `Del` removes an entry.

To bind a key straight to the clipboard, call the IPC this fork adds:

```sh
caelestia shell launcher open ';'
```
