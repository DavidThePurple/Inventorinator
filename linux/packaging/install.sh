#!/usr/bin/env bash
set -Eeuo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/inventorinator"
applications_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons_root="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
icons_dir="$icons_root/512x512/apps"
bin_dir="$HOME/.local/bin"

test -x "$source_dir/Inventorinator"
test -s "$source_dir/data/app_icon.png"

if [[ -L "$install_dir" ]]; then
  echo "Refusing to replace symbolic-link install directory: $install_dir" >&2
  exit 1
fi

mkdir -p "$install_dir" "$applications_dir" "$icons_dir" "$bin_dir"
if [[ "$source_dir" != "$install_dir" ]]; then
  find "$install_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  cp -a "$source_dir/." "$install_dir/"
fi

install -m 644 \
  "$source_dir/share/icons/hicolor/512x512/apps/media.everlasting.inventorinator.png" \
  "$icons_dir/media.everlasting.inventorinator.png"

# A per-user hicolor tree needs its theme index before sandboxed process
# viewers such as Mission Center can resolve icon names from desktop entries.
if [[ ! -s "$icons_root/index.theme" && -s /usr/share/icons/hicolor/index.theme ]]; then
  install -m 644 /usr/share/icons/hicolor/index.theme "$icons_root/index.theme"
fi

awk \
  -v executable="$install_dir/Inventorinator" '
  /^Exec=/ { print "Exec=" executable; next }
  { print }
' "$source_dir/share/applications/media.everlasting.inventorinator.desktop" \
  > "$applications_dir/media.everlasting.inventorinator.desktop"
chmod 644 "$applications_dir/media.everlasting.inventorinator.desktop"
ln -sfn "$install_dir/Inventorinator" "$bin_dir/inventorinator"

command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
  gtk-update-icon-cache -f -t "$icons_root" \
  >/dev/null 2>&1 || true

echo "Inventorinator installed. Open it from your application menu."
