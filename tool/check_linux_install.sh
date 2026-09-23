#!/usr/bin/env bash
# Runs the Linux installer against a built bundle inside a throwaway home
# directory and checks the launcher it writes. Guards against a blank
# application icon after ./install.sh (issue #15).
# Usage: tool/check_linux_install.sh [bundle directory]
set -Eeuo pipefail

bundle=${1:-build/linux/x64/release/bundle}
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/package" "$work/home"
cp -a "$bundle/." "$work/package/"
install -m 755 "$repo/linux/packaging/install.sh" "$work/package/install.sh"

# Both variables point inside the throwaway directory, so the real home is
# never touched.
data="$work/home/.local/share"
HOME="$work/home" XDG_DATA_HOME="$data" "$work/package/install.sh" >/dev/null

desktop="$data/applications/media.everlasting.inventorinator.desktop"
test -s "$desktop"

icon=$(sed -n 's/^Icon=//p' "$desktop")
test "$icon" = "$data/inventorinator/data/app_icon.png" ||
  { echo "Launcher icon is '$icon', expected the installed icon file." >&2; exit 1; }
test -s "$icon"

grep -Fxq "Exec=$data/inventorinator/Inventorinator" "$desktop" ||
  { echo "Launcher Exec line does not point at the installed app." >&2; exit 1; }

# The themed copy stays installed for launchers that look icons up by name.
test -s "$data/icons/hicolor/512x512/apps/media.everlasting.inventorinator.png"
test -x "$data/inventorinator/Inventorinator"

echo "Linux installer wrote a working launcher and icon."
