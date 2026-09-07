#!/usr/bin/env bash

set -euo pipefail

source_path=${1:-}
source_theme=${2:-external}

if [[ -z "$source_path" || ! -f "$source_path" ]]; then
  echo "Wallpaper file does not exist." >&2
  exit 1
fi

current_theme_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name"
current_theme=""
if [[ -f "$current_theme_file" ]]; then
  current_theme=$(<"$current_theme_file")
fi

if [[ ! "$current_theme" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "Could not determine the current Omarchy theme." >&2
  exit 1
fi

if [[ ! "$source_theme" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; then
  source_theme="external"
fi

source_real=$(readlink -f -- "$source_path")
# Keep plugin-owned copies out of ~/.config/omarchy/backgrounds. The standard
# Omarchy background picker scans that directory, while this plugin's applied
# wallpapers should remain available only through Wallpaper Explorer.
state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
destination_dir="$state_root/omarchy/wallpaper-explorer/backgrounds/$current_theme"
mkdir -p -- "$destination_dir"

source_name=$(basename -- "$source_real")
safe_name=$(printf '%s' "$source_name" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')
[[ -n "$safe_name" ]] || safe_name="wallpaper"
destination="$destination_dir/wallpaper-explorer-${source_theme}-${safe_name}"

temporary="$destination.tmp.$$"
cp -- "$source_real" "$temporary"
mv -f -- "$temporary" "$destination"

# This is the supported Omarchy wallpaper path. It updates the current
# background symlink and the running shell without switching theme colors.
omarchy theme bg set "$destination" >/dev/null

printf 'applied\t%s\n' "$destination"
