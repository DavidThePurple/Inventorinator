#!/usr/bin/env bash
set -Eeuo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/inventorinator"
applications_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
bin_dir="$HOME/.local/bin"

test -x "$source_dir/inventorinator"
test -s "$source_dir/data/app_icon.png"

mkdir -p "$install_dir" "$applications_dir" "$icons_dir" "$bin_dir"
if [[ "$source_dir" != "$install_dir" ]]; then
  find "$install_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  cp -a "$source_dir/." "$install_dir/"
fi

install -m 644 \
  "$source_dir/share/icons/hicolor/512x512/apps/media.everlasting.inventorinator.png" \
  "$icons_dir/media.everlasting.inventorinator.png"

awk -v executable="$install_dir/inventorinator" '
  /^Exec=/ { print "Exec=" executable; next }
  { print }
' "$source_dir/share/applications/media.everlasting.inventorinator.desktop" \
  > "$applications_dir/media.everlasting.inventorinator.desktop"
chmod 644 "$applications_dir/media.everlasting.inventorinator.desktop"
ln -sfn "$install_dir/inventorinator" "$bin_dir/inventorinator"

command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
  gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" \
  >/dev/null 2>&1 || true

echo "Inventorinator installed. Open it from your application menu."
