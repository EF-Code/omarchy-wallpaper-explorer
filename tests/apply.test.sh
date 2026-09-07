#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/wallpaper-explorer-apply.XXXXXX)

mkdir -p "$test_root/bin" "$test_root/state/omarchy/current" "$test_root/source"
printf '%s\n' 'last-horizon' > "$test_root/state/omarchy/current/theme.name"
printf '%s\n' 'fixture' > "$test_root/source/solitude.jpg"

# The second line is intentionally quoted so the generated fixture expands
# TEST_LOG when it runs, not while this test creates it.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" > "$TEST_LOG"' \
  > "$test_root/bin/omarchy"
chmod +x "$test_root/bin/omarchy"

output=$(HOME="$test_root" \
  XDG_CONFIG_HOME="$test_root/config" \
  XDG_STATE_HOME="$test_root/state" \
  TEST_LOG="$test_root/omarchy.log" \
  PATH="$test_root/bin:$PATH" \
  "$repo_root/apply.sh" "$test_root/source/solitude.jpg" solitude)

destination="$test_root/state/omarchy/wallpaper-explorer/backgrounds/last-horizon/wallpaper-explorer-solitude-solitude.jpg"
test -f "$destination"
test ! -e "$test_root/config/omarchy/backgrounds/last-horizon"
grep -q $'^applied\t' <<< "$output"
grep -q 'theme bg set' "$test_root/omarchy.log"
grep -q "$destination" "$test_root/omarchy.log"

printf '%s\n' 'Wallpaper Explorer apply test passed'
