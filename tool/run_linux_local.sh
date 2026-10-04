#!/usr/bin/env sh
# Build and open the exact Linux bundle in this checkout.  The optional
# --clean flag clears stale Flutter outputs first when Dart UI changes appear
# not to have reached a local release bundle.
set -eu

clean=false
if [ "${1:-}" = "--clean" ]; then
  clean=true
  shift
fi
test "$#" -eq 0 || {
  echo "Usage: $0 [--clean]" >&2
  exit 64
}

if command -v flutter >/dev/null 2>&1; then
  flutter_bin=flutter
elif [ -x "$HOME/Development/flutter/bin/flutter" ]; then
  flutter_bin=$HOME/Development/flutter/bin/flutter
else
  echo "Flutter was not found. Add it to PATH or install it in ~/Development/flutter." >&2
  exit 127
fi

if [ "$clean" = true ]; then
  "$flutter_bin" clean
  "$flutter_bin" pub get
fi

PATH="$(dirname "$flutter_bin"):$PATH"
export PATH
./tool/build_with_metadata.sh linux --release

bundle=build/linux/x64/release/bundle
app=$bundle/Inventorinator
sqlite=$bundle/lib/libsqlite3.so
test -x "$app"
test -f "$sqlite"

# The development bundle needs the SQLite native library preloaded on this
# host; installed packages load it through their normal launcher.
preload=/tmp/inventorinator-local-sqlite3.so
ln -sf "$(pwd)/$sqlite" "$preload"
exec env LD_PRELOAD="$preload" "$app"
