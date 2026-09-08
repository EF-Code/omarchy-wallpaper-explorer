#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/wallpaper-explorer-discover.XXXXXX)
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

mkdir -p "$test_root/omarchy/themes/stock/backgrounds" \
  "$test_root/home/.config/omarchy/themes" \
  "$test_root/home/.config/omarchy/backgrounds/stock" \
  "$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds" \
  "$test_root/home/.local/state/omarchy/current" \
  "$test_root/external/linked/backgrounds" "$test_root/private"
printf '%s\n' stock > "$test_root/home/.local/state/omarchy/current/theme.name"
printf '%s\n' stock > "$test_root/omarchy/themes/stock/backgrounds/one.jpg"
printf '%s\n' override > "$test_root/home/.config/omarchy/backgrounds/stock/one.jpg"
printf '%s\n' 'space' > "$test_root/omarchy/themes/stock/backgrounds/two words.jpg"
printf '%s\n' linked > "$test_root/external/linked/backgrounds/linked.jpg"
printf '%s\n' xdg > "$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds/xdg.jpg"
ln -s "$test_root/external/linked" "$test_root/home/.config/omarchy/themes/linked"

printf '%s\n' secret > "$test_root/private/secret.jpg"
ln -s "$test_root/private/secret.jpg" "$test_root/omarchy/themes/stock/backgrounds/escape.jpg"
printf '%s\n' control > "$test_root/omarchy/themes/stock/backgrounds/"$'bad\nname.jpg'
truncate -s $((100 * 1024 * 1024 + 1)) "$test_root/omarchy/themes/stock/backgrounds/oversized.jpg"
mkdir -p "$test_root/omarchy/themes/nested-link"
ln -s "$test_root/private" "$test_root/omarchy/themes/nested-link/backgrounds"
mkdir -p "$test_root/home/.config/omarchy/backgrounds/orphan"
printf '%s\n' orphan > "$test_root/home/.config/omarchy/backgrounds/orphan/orphan.jpg"

output=$(HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/xdg-config" XDG_CACHE_HOME="$test_root/cache" \
  OMARCHY_PATH="$test_root/omarchy" "$repo_root/discover.sh")

grep -q $'^meta\tcurrent-theme\tstock$' <<< "$output"
grep -q $'^theme\tstock\tStock\t2\t' <<< "$output"
grep -Fq "$test_root/home/.config/omarchy/backgrounds/stock/one.jpg" <<< "$output"
grep -Fq "$test_root/omarchy/themes/stock/backgrounds/two words.jpg" <<< "$output"
grep -Fq "$test_root/external/linked/backgrounds/linked.jpg" <<< "$output"
grep -Fq "$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds/xdg.jpg" <<< "$output"
if grep -Fq "$test_root/private/secret.jpg" <<< "$output"; then
  echo "nested wallpaper symlink escaped its theme" >&2; exit 1
fi
if grep -Fq 'oversized.jpg' <<< "$output"; then
  echo "oversized wallpaper was discovered" >&2; exit 1
fi
if grep -Fq 'orphan.jpg' <<< "$output"; then
  echo "background-only directory was treated as an installed theme" >&2; exit 1
fi
if grep -q $'^background\tnested-link\t' <<< "$output"; then
  echo "symlinked backgrounds directory was followed" >&2; exit 1
fi

printf '%s\n' 'Wallpaper Explorer discovery tests passed'
