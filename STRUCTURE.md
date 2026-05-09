# Caelestia Shell Structure

- `assets/`: UI assets, icons, images.
- `components/`: Reusable QML components.
- `modules/`: Core functional modules (launcher, bar, dashboard, etc.).
- `plugin/`: C++ source code for plugins (including configuration logic).
- `services/`: QML-based system services.
- `scripts/`: Helper scripts for shell functionality.

## Build and Recompile Procedure

To rebuild and install the Caelestia Shell after making modifications (specifically to C++ files in `plugin/`):

1. Navigate to the project root:
   ```bash
   cd ~/.config/quickshell/caelestia
   ```

2. Run the build and install command:
   ```bash
   cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/caelestia && cmake --build build && sudo cmake --install build
   ```
