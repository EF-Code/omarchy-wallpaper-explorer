# Wallpaper Explorer

Wallpaper Explorer is a native Omarchy shell plugin for browsing and applying
wallpapers from every installed Omarchy theme without changing the active theme
colors.

It does not download or install themes or wallpapers. The gallery is built only
from themes already installed for the current user.

## Features

- Fullscreen, keyboard-friendly Quickshell gallery
- Theme cards with wallpaper previews and searchable names
- Stock themes, user theme overlays, and user-added backgrounds for installed themes
- Wallpaper-only application through `omarchy theme bg set`
- Active theme colors remain unchanged
- Plugin-owned applied copies stay out of Omarchy's regular background picker
- Bounded scanning, preview conversion, cache storage, and applied state

## Install

```bash
omarchy plugin add https://github.com/EF-Code/omarchy-wallpaper-explorer.git --enable
```

Open Wallpaper Explorer from its bar widget. Select an installed theme, choose
one of its wallpapers, then press **Apply**.

WebP previews require `vipsthumbnail`, which Omarchy normally provides. When
Omarchy's desktop renderer cannot decode a selected WebP, GIF, or BMP directly,
Wallpaper Explorer converts its plugin-owned copy to a full-resolution JPEG
before applying it. Installed theme files remain untouched.

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

The plugin copies a selected wallpaper into
`$XDG_STATE_HOME/omarchy/wallpaper-explorer` (or `~/.local/state` when
`XDG_STATE_HOME` is unset) before applying it. Generated WebP previews live in
`$XDG_CACHE_HOME/wallpaper-explorer` (or `~/.cache`). It never writes to
`/usr/share/omarchy`.

## Security

Only regular image files contained by an installed theme's wallpaper directory
are accepted. Nested symlink escapes, stale selections, oversized files, and
malformed discovery records are rejected. See [SECURITY.md](SECURITY.md) for
private reporting instructions.

## License

MIT
