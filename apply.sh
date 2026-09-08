#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

readonly max_image_bytes=$((100 * 1024 * 1024))
source_path=${1:-}
source_theme=${2:-}
expected_fingerprint=${3:-}
temporary=""
created_destination=false
applied_successfully=false
destination=""

cleanup() {
  [[ -z $temporary ]] || rm -f -- "$temporary" 2>/dev/null || true
  if [[ $created_destination == true && $applied_successfully == false && -n $destination ]]; then
    rm -f -- "$destination" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

fail() { printf '%s\n' "$1" >&2; exit 1; }
valid_slug() { [[ $1 =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; }
has_controls() { [[ $1 == *$'\t'* || $1 == *$'\n'* || $1 == *$'\r'* ]]; }
path_is_within() { [[ $1 == "$2"/* ]]; }
fingerprint_for() { find "$1" -maxdepth 0 -type f -printf '%D:%i:%s:%T@:%C@' 2>/dev/null; }

[[ -n $source_path && -f $source_path && ! -L $source_path ]] || fail "Wallpaper file is unavailable. Refresh Wallpaper Explorer and try again."
has_controls "$source_path" && fail "Wallpaper path contains unsupported control characters."
valid_slug "$source_theme" || fail "Wallpaper theme is invalid."
case "${source_path##*.}" in
  jpg|JPG|jpeg|JPEG|png|PNG|gif|GIF|bmp|BMP|webp|WEBP) ;;
  *) fail "Unsupported wallpaper format." ;;
esac
command -v omarchy >/dev/null 2>&1 || fail "Omarchy is unavailable."
command -v flock >/dev/null 2>&1 || fail "Required file-locking support is unavailable."

source_real=$(realpath -e -- "$source_path" 2>/dev/null) || fail "Wallpaper file is unavailable."
[[ -f $source_real ]] || fail "Wallpaper file is unavailable."
source_size=$(stat -Lc '%s' -- "$source_real" 2>/dev/null) || fail "Could not inspect wallpaper file."
(( source_size <= max_image_bytes )) || fail "Wallpaper exceeds the 100 MiB safety limit."

xdg_config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
declare -a theme_roots=("${OMARCHY_PATH:-/usr/share/omarchy}/themes" "$HOME/.config/omarchy/themes")
declare -a background_roots=("$HOME/.config/omarchy/backgrounds")
if [[ $xdg_config_root != "$HOME/.config" ]]; then
  theme_roots+=("$xdg_config_root/omarchy/themes")
  background_roots+=("$xdg_config_root/omarchy/backgrounds")
fi

source_allowed=false
for theme_root in "${theme_roots[@]}"; do
  theme_entry="$theme_root/$source_theme"
  [[ -d $theme_entry ]] || continue
  theme_real=$(realpath -e -- "$theme_entry" 2>/dev/null) || continue
  backgrounds="$theme_real/backgrounds"
  [[ -d $backgrounds && ! -L $backgrounds ]] || continue
  backgrounds_real=$(realpath -e -- "$backgrounds" 2>/dev/null) || continue
  [[ $backgrounds_real == "$backgrounds" ]] || continue
  if path_is_within "$source_real" "$backgrounds_real"; then
    source_allowed=true
    break
  fi
done

if [[ $source_allowed == false ]]; then
  for background_root in "${background_roots[@]}"; do
    user_backgrounds="$background_root/$source_theme"
    if [[ -d $user_backgrounds && ! -L $user_backgrounds ]]; then
      user_backgrounds_real=$(realpath -e -- "$user_backgrounds" 2>/dev/null || true)
      user_background_root_real=$(realpath -e -- "$background_root" 2>/dev/null || true)
      if [[ -n $user_backgrounds_real && -n $user_background_root_real ]] \
        && path_is_within "$user_backgrounds_real" "$user_background_root_real" \
        && path_is_within "$source_real" "$user_backgrounds_real"; then
        source_allowed=true
        break
      fi
    fi
  done
fi

[[ $source_allowed == true ]] || fail "Wallpaper is outside the selected installed theme."

actual_fingerprint=$(fingerprint_for "$source_real") || fail "Could not inspect wallpaper file."
if [[ -n $expected_fingerprint && $actual_fingerprint != "$expected_fingerprint" ]]; then
  fail "Wallpaper changed after it was previewed. Refresh Wallpaper Explorer and try again."
fi
expected_fingerprint=$actual_fingerprint

current_theme_file="$HOME/.local/state/omarchy/current/theme.name"
if [[ ! -f $current_theme_file && -n ${XDG_STATE_HOME:-} ]]; then
  current_theme_file="$XDG_STATE_HOME/omarchy/current/theme.name"
fi
[[ -f $current_theme_file ]] || fail "Could not determine the current Omarchy theme."
current_theme=$(<"$current_theme_file")
valid_slug "$current_theme" || fail "Could not determine the current Omarchy theme."

state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
plugin_state_root="$state_root/omarchy/wallpaper-explorer"
mkdir -p -- "$plugin_state_root"
chmod 700 -- "$plugin_state_root" 2>/dev/null || true
exec {apply_lock_fd}> "$plugin_state_root/.apply.lock"
flock -w 15 "$apply_lock_fd" || fail "Another wallpaper apply is still running."
chmod 600 -- "$plugin_state_root/.apply.lock" 2>/dev/null || true

destination_dir="$plugin_state_root/backgrounds/$current_theme"
mkdir -p -- "$destination_dir"
chmod 700 -- "$plugin_state_root/backgrounds" "$destination_dir" 2>/dev/null || true

source_name=$(basename -- "$source_real")
source_extension=${source_name##*.}
source_extension=${source_extension,,}
convert_for_shell=false
case "$source_extension" in
  jpg|jpeg|png) ;;
  webp|gif|bmp) convert_for_shell=true ;;
esac

if [[ $convert_for_shell == true ]]; then
  command -v vips >/dev/null 2>&1 || fail "Image conversion support is unavailable."
  temporary=$(mktemp --tmpdir="$destination_dir" '.wallpaper-explorer.XXXXXX.jpg')
  chmod 600 -- "$temporary"
  if ! timeout --signal=TERM --kill-after=2s 15s env VIPS_CONCURRENCY=1 \
    vips copy "$source_real" "${temporary}[Q=92,strip]" >/dev/null 2>&1; then
    fail "Wallpaper could not be converted for the desktop."
  fi
  source_name="${source_name%.*}.jpg"
else
  temporary=$(mktemp --tmpdir="$destination_dir" '.wallpaper-explorer.XXXXXX')
  chmod 600 -- "$temporary"
  cp -- "$source_real" "$temporary"
  cmp -s -- "$source_real" "$temporary" || fail "Wallpaper changed while it was being copied. Try again."
fi
[[ $(fingerprint_for "$source_real") == "$expected_fingerprint" ]] || fail "Wallpaper changed while it was being copied. Try again."

digest=$(sha256sum -- "$temporary" | cut -d ' ' -f1)
safe_name=$(printf '%s' "$source_name" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')
[[ -n $safe_name ]] || safe_name="wallpaper"
destination="$destination_dir/wallpaper-explorer-${source_theme}-${digest:0:16}-${safe_name}"

if [[ -e $destination ]]; then
  cmp -s -- "$temporary" "$destination" || fail "A conflicting wallpaper copy already exists."
  rm -f -- "$temporary"
  temporary=""
else
  mv -- "$temporary" "$destination"
  temporary=""
  created_destination=true
fi

if ! omarchy theme bg set "$destination" >/dev/null; then
  fail "Omarchy could not apply the wallpaper."
fi
applied_successfully=true

while IFS= read -r -d '' old_copy; do
  [[ $old_copy == "$destination" ]] || rm -f -- "$old_copy" 2>/dev/null || true
done < <(find "$destination_dir" -maxdepth 1 -type f -name 'wallpaper-explorer-*' -print0 2>/dev/null)

printf 'applied\t%s\n' "$destination"
