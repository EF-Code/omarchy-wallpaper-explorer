#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/wallpaper-explorer-apply.XXXXXX)
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT
fingerprint_for() { find "$1" -maxdepth 0 -type f -printf '%D:%i:%s:%T@:%C@'; }

mkdir -p "$test_root/bin" "$test_root/.local/state/omarchy/current" \
  "$test_root/.config/omarchy/themes/solitude/backgrounds"
printf '%s\n' 'last-horizon' > "$test_root/.local/state/omarchy/current/theme.name"
printf '%s\n' 'fixture' > "$test_root/.config/omarchy/themes/solitude/backgrounds/solitude.jpg"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$TEST_LOG"' \
  '[[ ${OMARCHY_FAIL:-0} != 1 ]]' > "$test_root/bin/omarchy"
chmod +x "$test_root/bin/omarchy"

source="$test_root/.config/omarchy/themes/solitude/backgrounds/solitude.jpg"
fingerprint=$(fingerprint_for "$source")
output=$(HOME="$test_root" XDG_STATE_HOME="$test_root/state" \
  TEST_LOG="$test_root/omarchy.log" PATH="$test_root/bin:$PATH" \
  "$repo_root/apply.sh" "$source" solitude "$fingerprint")
destination=${output#*$'applied\t'}

test -f "$destination"
grep -Fxq 'last-horizon' "$test_root/.local/state/omarchy/current/theme.name"
test ! -e "$test_root/.config/omarchy/backgrounds/last-horizon"
[[ $destination == "$test_root/state/omarchy/wallpaper-explorer/backgrounds/last-horizon/"* ]]
grep -Fq 'theme bg set' "$test_root/omarchy.log"
grep -Fq "$destination" "$test_root/omarchy.log"

mkdir -p "$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds"
printf '%s\n' xdg > "$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds/xdg.jpg"
xdg_source="$test_root/xdg-config/omarchy/themes/xdg-theme/backgrounds/xdg.jpg"
xdg_fingerprint=$(fingerprint_for "$xdg_source")
xdg_output=$(HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg-config" \
  XDG_STATE_HOME="$test_root/state" TEST_LOG="$test_root/omarchy.log" \
  PATH="$test_root/bin:$PATH" "$repo_root/apply.sh" "$xdg_source" xdg-theme "$xdg_fingerprint")
xdg_destination=${xdg_output#*$'applied\t'}
test -f "$xdg_destination"
test ! -e "$destination"
grep -Fxq 'last-horizon' "$test_root/.local/state/omarchy/current/theme.name"
destination=$xdg_destination

# A model retained across a plugin hot reload may not yet carry the optional
# fingerprint field. Containment and copy-consistency checks still apply.
compat_output=$(HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg-config" \
  XDG_STATE_HOME="$test_root/state" TEST_LOG="$test_root/omarchy.log" \
  PATH="$test_root/bin:$PATH" "$repo_root/apply.sh" "$xdg_source" xdg-theme)
[[ ${compat_output#*$'applied\t'} == "$destination" ]]

if command -v vips >/dev/null 2>&1; then
  vips black "$test_root/.config/omarchy/themes/solitude/backgrounds/converted.webp" 8 8 2>/dev/null
  webp_source="$test_root/.config/omarchy/themes/solitude/backgrounds/converted.webp"
  webp_fingerprint=$(fingerprint_for "$webp_source")
  webp_output=$(HOME="$test_root" XDG_STATE_HOME="$test_root/state" \
    TEST_LOG="$test_root/omarchy.log" PATH="$test_root/bin:$PATH" \
    "$repo_root/apply.sh" "$webp_source" solitude "$webp_fingerprint")
  webp_destination=${webp_output#*$'applied\t'}
  [[ $webp_destination == *.jpg ]]
  test -f "$webp_destination"
  file "$webp_destination" | grep -Fq 'JPEG image data'
  vipsheader "$webp_destination" >/dev/null 2>&1
  test ! -e "$destination"
  destination=$webp_destination
fi

if HOME="$test_root" XDG_STATE_HOME="$test_root/state" TEST_LOG="$test_root/omarchy.log" \
  PATH="$test_root/bin:$PATH" "$repo_root/apply.sh" "$source" solitude stale 2>/dev/null; then
  echo "stale fingerprint was accepted" >&2
  exit 1
fi

printf '%s\n' 'other' > "$test_root/outside.jpg"
outside_fingerprint=$(fingerprint_for "$test_root/outside.jpg")
if HOME="$test_root" XDG_STATE_HOME="$test_root/state" TEST_LOG="$test_root/omarchy.log" \
  PATH="$test_root/bin:$PATH" "$repo_root/apply.sh" "$test_root/outside.jpg" solitude "$outside_fingerprint" 2>/dev/null; then
  echo "out-of-theme wallpaper was accepted" >&2
  exit 1
fi

printf '%s\n' 'new fixture' > "$test_root/.config/omarchy/themes/solitude/backgrounds/new.jpg"
failed_source="$test_root/.config/omarchy/themes/solitude/backgrounds/new.jpg"
failed_fingerprint=$(fingerprint_for "$failed_source")
before_count=$(find "$(dirname -- "$destination")" -maxdepth 1 -type f | wc -l)
if HOME="$test_root" XDG_STATE_HOME="$test_root/state" TEST_LOG="$test_root/omarchy.log" \
  OMARCHY_FAIL=1 PATH="$test_root/bin:$PATH" \
  "$repo_root/apply.sh" "$failed_source" solitude "$failed_fingerprint" 2>/dev/null; then
  echo "failed Omarchy application returned success" >&2
  exit 1
fi
after_count=$(find "$(dirname -- "$destination")" -maxdepth 1 -type f | wc -l)
[[ $before_count -eq $after_count ]]
test -f "$destination"

printf '%s\n' 'Wallpaper Explorer apply tests passed'
