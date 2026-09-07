# Wallpaper Explorer

Wallpaper Explorer is a native Omarchy shell plugin for browsing and applying
wallpapers from every installed Omarchy theme without changing the active theme
colors.

## Current status

The project currently contains the first working slice:

- a `bar-widget` entry point for opening the explorer;
- a fullscreen Quickshell gallery overlay;
- discovery of stock themes and user theme overlays;
- theme-level previews and wallpaper grids;
- persistence-safe application through `omarchy theme bg set`;
- model, shell, and manifest checks.

## Development install

From this repository:

```bash
omarchy plugin validate .
./scripts/check
```

To test the working copy in the current Omarchy session, install it into the
user plugin directory with a symlink, then rescan and enable it:

```bash
ln -sfn "$PWD" "$HOME/.config/omarchy/plugins/io.github.ef-code.wallpaper-explorer"
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ef-code.wallpaper-explorer
```

The plugin copies a selected wallpaper into its XDG state directory before
applying it. This keeps the choice available across shell restarts without
adding plugin-applied wallpapers to Omarchy's regular theme background picker.
