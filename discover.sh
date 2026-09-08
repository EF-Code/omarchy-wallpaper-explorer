#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

readonly max_themes=256 max_images_per_theme=256 max_images_total=2048
readonly max_image_bytes=$((100 * 1024 * 1024)) thumbnail_timeout_seconds=3
readonly max_thumbnail_files=512 max_thumbnail_bytes=$((512 * 1024 * 1024))
readonly scan_deadline=$((SECONDS + 8))

xdg_config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
user_theme_root="$HOME/.config/omarchy/themes"
xdg_theme_root="$xdg_config_root/omarchy/themes"
user_background_root="$HOME/.config/omarchy/backgrounds"
xdg_background_root="$xdg_config_root/omarchy/backgrounds"
stock_theme_root="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
current_state_root="$HOME/.local/state/omarchy/current"
xdg_current_state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current"
thumbnail_root="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-explorer"
for configured_root in "$user_theme_root" "$xdg_theme_root" "$user_background_root" \
  "$xdg_background_root" "$stock_theme_root" "$current_state_root" \
  "$xdg_current_state_root" "$thumbnail_root"; do
  has_bad_root=false
  [[ $configured_root == *$'\t'* || $configured_root == *$'\n'* || $configured_root == *$'\r'* ]] && has_bad_root=true
  [[ $has_bad_root == false ]] || { echo "Wallpaper Explorer paths contain unsupported control characters." >&2; exit 1; }
done
mkdir -p -- "$thumbnail_root"
chmod 700 -- "$thumbnail_root" 2>/dev/null || true

valid_slug() { [[ $1 =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; }
has_controls() { [[ $1 == *$'\t'* || $1 == *$'\n'* || $1 == *$'\r'* ]]; }
path_is_within() { [[ $1 == "$2"/* ]]; }

prune_thumbnail_cache() {
  local count=0 bytes=0 size path
  while IFS=$'\t' read -r size path; do
    [[ $size =~ ^[0-9]+$ ]] || continue
    if (( count < max_thumbnail_files && bytes + size <= max_thumbnail_bytes )); then
      ((count += 1)); ((bytes += size))
    else
      rm -f -- "$path" 2>/dev/null || true
    fi
  done < <(find "$thumbnail_root" -maxdepth 1 -type f -regextype posix-extended \
    -regex '.*/[0-9a-f]{64}\.jpg' -printf '%T@\t%s\t%p\n' 2>/dev/null \
    | sort -rn | cut -f2-)
}

thumbnail_for() {
  local image="$1" fingerprint="$2" hash thumbnail temporary
  case "${image##*.}" in
    webp|WEBP) ;;
    *) printf '%s' "$image"; return 0 ;;
  esac
  (( SECONDS < scan_deadline )) || return 1
  command -v vipsthumbnail >/dev/null 2>&1 || return 1
  hash=$(printf '%s\t%s' "$image" "$fingerprint" | sha256sum | cut -d ' ' -f1)
  thumbnail="$thumbnail_root/$hash.jpg"
  if [[ ! -f $thumbnail ]]; then
    temporary=$(mktemp --tmpdir="$thumbnail_root" '.wallpaper-explorer.XXXXXX.jpg')
    if timeout --signal=TERM --kill-after=2s "${thumbnail_timeout_seconds}s" \
      env VIPS_CONCURRENCY=1 vipsthumbnail "$image" --size 1280x720 \
      --smartcrop=centre --path "${temporary}[Q=82,strip]" >/dev/null 2>&1; then
      chmod 600 -- "$temporary"
      mv -f -- "$temporary" "$thumbnail"
    else
      rm -f -- "$temporary"
      return 1
    fi
  fi
  printf '%s' "$thumbnail"
}

title_for_slug() {
  local title=${1//-/ } word
  local -a words=()
  read -r -a words <<< "$title"
  title=""
  for word in "${words[@]}"; do
    [[ -z $title ]] || title+=" "
    title+="${word^}"
  done
  printf '%s\n' "$title"
}

current_theme="" current_background=""
[[ -f "$current_state_root/theme.name" ]] && current_theme=$(<"$current_state_root/theme.name")
[[ -e "$current_state_root/background" ]] && current_background=$(readlink -f -- "$current_state_root/background" 2>/dev/null || true)
if [[ -z $current_theme && $xdg_current_state_root != "$current_state_root" ]]; then
  [[ -f "$xdg_current_state_root/theme.name" ]] && current_theme=$(<"$xdg_current_state_root/theme.name")
  [[ -e "$xdg_current_state_root/background" ]] && current_background=$(readlink -f -- "$xdg_current_state_root/background" 2>/dev/null || true)
fi
has_controls "$current_theme" && current_theme=""
has_controls "$current_background" && current_background=""
printf 'meta\tcurrent-theme\t%s\n' "$current_theme"
printf 'meta\tcurrent-background\t%s\n' "$current_background"
prune_thumbnail_cache

declare -A seen_slugs=()
declare -a theme_slugs=()
declare -a theme_roots=("$stock_theme_root" "$user_theme_root")
declare -a background_roots=("$user_background_root")
if [[ $xdg_theme_root != "$user_theme_root" ]]; then theme_roots+=("$xdg_theme_root"); fi
if [[ $xdg_background_root != "$user_background_root" ]]; then background_roots+=("$xdg_background_root"); fi
for root in "${theme_roots[@]}"; do
  [[ -d $root ]] || continue
  while IFS= read -r -d '' entry; do
    slug=${entry##*/}
    valid_slug "$slug" || continue
    [[ -n ${seen_slugs[$slug]+set} ]] && continue
    seen_slugs["$slug"]=1; theme_slugs+=("$slug")
    (( ${#theme_slugs[@]} >= max_themes )) && break 2
  done < <(find "$root" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null | sort -z)
done
(( ${#theme_slugs[@]} == 0 )) || mapfile -t theme_slugs < <(printf '%s\n' "${theme_slugs[@]}" | sort -u)

total_images=0
for theme_slug in "${theme_slugs[@]}"; do
  declare -A images_by_name=()
  declare -A fingerprints_by_name=()

  collect_images() {
    local directory="$1" allowed_root="$2" image basename size fingerprint
    [[ -d $directory && ! -L $directory ]] || return 0
    directory=$(realpath -e -- "$directory" 2>/dev/null) || return 0
    path_is_within "$directory" "$allowed_root" || [[ $directory == "$allowed_root" ]] || return 0
    while IFS= read -r -d '' image \
      && IFS= read -r -d '' size \
      && IFS= read -r -d '' fingerprint; do
      has_controls "$image" && continue
      basename=${image##*/}; has_controls "$basename" && continue
      (( size <= max_image_bytes )) || continue
      images_by_name["$basename"]="$image"
      fingerprints_by_name["$basename"]="$fingerprint"
    done < <(find "$directory" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
      -o -iname '*.bmp' -o -iname '*.webp' \) \
      -printf '%p\0%s\0%D:%i:%s:%T@:%C@\0' 2>/dev/null)
  }

  collect_theme_entry() {
    local entry="$1" theme_real backgrounds
    [[ -d $entry ]] || return 0
    theme_real=$(realpath -e -- "$entry" 2>/dev/null) || return 0
    [[ -d $theme_real ]] || return 0
    backgrounds="$theme_real/backgrounds"
    collect_images "$backgrounds" "$theme_real"
  }

  for theme_root in "${theme_roots[@]}"; do
    [[ -d "$theme_root/$theme_slug" ]] && collect_theme_entry "$theme_root/$theme_slug"
  done
  for background_root in "${background_roots[@]}"; do
    if [[ -d "$background_root/$theme_slug" && ! -L "$background_root/$theme_slug" ]]; then
      backgrounds_real=$(realpath -e -- "$background_root/$theme_slug" 2>/dev/null || true)
      background_root_real=$(realpath -e -- "$background_root" 2>/dev/null || true)
      [[ -n $backgrounds_real && -n $background_root_real ]] && collect_images "$backgrounds_real" "$background_root_real"
    fi
  done

  declare -a sorted_names=()
  (( ${#images_by_name[@]} == 0 )) || mapfile -t sorted_names < <(printf '%s\n' "${!images_by_name[@]}" | sort -f)
  available=$((max_images_total - total_images)); image_count=${#sorted_names[@]}
  (( image_count <= max_images_per_theme )) || image_count=$max_images_per_theme
  (( image_count <= available )) || image_count=$available
  preview=""
  if (( image_count > 0 )); then
    preview_source=${images_by_name[${sorted_names[0]}]}
    preview_fingerprint=${fingerprints_by_name[${sorted_names[0]}]}
    [[ -z $preview_fingerprint ]] || preview=$(thumbnail_for "$preview_source" "$preview_fingerprint" || true)
  fi
  theme_name=$(title_for_slug "$theme_slug")
  printf 'theme\t%s\t%s\t%s\t%s\n' "$theme_slug" "$theme_name" "$image_count" "$preview"
  for ((index=0; index<image_count; index+=1)); do
    image=${images_by_name[${sorted_names[$index]}]}
    fingerprint=${fingerprints_by_name[${sorted_names[$index]}]}; [[ -n $fingerprint ]] || continue
    thumbnail=$(thumbnail_for "$image" "$fingerprint" || true)
    printf 'background\t%s\t%s\t%s\t%s\n' "$theme_slug" "$image" "$thumbnail" "$fingerprint"
    ((total_images += 1))
  done
  unset -f collect_images collect_theme_entry
  unset images_by_name fingerprints_by_name sorted_names
done
prune_thumbnail_cache
