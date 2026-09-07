#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

user_config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
user_theme_root="$user_config_root/omarchy/themes"
user_background_root="$user_config_root/omarchy/backgrounds"
stock_theme_root="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current"
thumbnail_root="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-explorer"

mkdir -p -- "$thumbnail_root"

current_theme=""
current_background=""
if [[ -f "$state_root/theme.name" ]]; then
  current_theme=$(<"$state_root/theme.name")
fi
if [[ -e "$state_root/background" ]]; then
  current_background=$(readlink -f -- "$state_root/background" 2>/dev/null || true)
fi

printf 'meta\tcurrent-theme\t%s\n' "$current_theme"
printf 'meta\tcurrent-background\t%s\n' "$current_background"

title_for_slug() {
  printf '%s\n' "$1" | sed -E 's/(^|-)([a-z])|_([a-z])/'"\1"'\U\2\U\3/g; s/-|_/ /g'
}

thumbnail_for() {
  local image="$1"
  local signature hash thumbnail temporary

  # Qt handles the common formats directly. Omarchy installations can also
  # contain WebP wallpapers, while the Qt image plugin on some systems cannot
  # decode them. Convert only that format so discovery stays fast and the
  # shell log stays quiet for unsupported previews.
  case "${image##*.}" in
    webp|WEBP) ;;
    *)
      printf '%s' "$image"
      return 0
      ;;
  esac

  if ! command -v vipsthumbnail >/dev/null 2>&1; then
    return 1
  fi

  signature=$(stat -Lc '%s:%Y' -- "$image" 2>/dev/null) || return 1
  hash=$(printf '%s\t%s' "$image" "$signature" | sha256sum | cut -d ' ' -f1)
  thumbnail="$thumbnail_root/$hash.jpg"

  if [[ ! -f "$thumbnail" ]]; then
    temporary="$thumbnail.tmp.$$.jpg"
    if VIPS_CONCURRENCY=1 vipsthumbnail "$image" \
      --size 1280x720 --smartcrop=centre \
      --path "${temporary}[Q=82,strip]" >/dev/null 2>&1; then
      mv -f -- "$temporary" "$thumbnail"
    else
      rm -f -- "$temporary" "$thumbnail"
      return 1
    fi
  fi

  printf '%s' "$thumbnail"
}

theme_slugs=$(
  {
    find -L "$user_theme_root" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -printf '%f\n' 2>/dev/null || true
    find -L "$stock_theme_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true
  } | sort -u
)

for theme_slug in $theme_slugs; do
  declare -A images_by_name=()

  collect_images() {
    local directory="$1"
    local image basename
    [[ -d "$directory" ]] || return 0

    while IFS= read -r -d '' image; do
      basename=${image##*/}
      images_by_name["$basename"]="$image"
    done < <(
      find -L "$directory" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
        -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
        -print0 2>/dev/null | sort -z
    )
  }

  # Match Omarchy's theme staging order: stock content first, then the user's
  # overlay. User backgrounds are included last so wallpapers added through
  # `omarchy theme bg install` are visible and win same-name collisions.
  collect_images "$stock_theme_root/$theme_slug/backgrounds"
  collect_images "$user_theme_root/$theme_slug/backgrounds"
  collect_images "$user_background_root/$theme_slug"

  sorted_images=""
  if (( ${#images_by_name[@]} > 0 )); then
    sorted_images=$(
      for basename in "${!images_by_name[@]}"; do
        printf '%s\t%s\n' "$basename" "${images_by_name[$basename]}"
      done | sort -f -k1,1
    )
  fi

  image_count=0
  preview=""
  if [[ -n "$sorted_images" ]]; then
    image_count=$(printf '%s\n' "$sorted_images" | awk 'NF { count += 1 } END { print count + 0 }')
    preview_source=$(printf '%s\n' "$sorted_images" | sed -n '1p' | cut -f2-)
    preview=$(thumbnail_for "$preview_source" || true)
  fi

  theme_name=$(title_for_slug "$theme_slug")
  printf 'theme\t%s\t%s\t%s\t%s\n' "$theme_slug" "$theme_name" "$image_count" "$preview"

  if [[ -n "$sorted_images" ]]; then
    while IFS=$'\t' read -r _basename image; do
      [[ -n "$image" ]] || continue
      thumbnail=$(thumbnail_for "$image" || true)
      printf 'background\t%s\t%s\t%s\n' "$theme_slug" "$image" "$thumbnail"
    done <<< "$sorted_images"
  fi

  unset -f collect_images
  unset images_by_name
done
