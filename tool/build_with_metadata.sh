#!/usr/bin/env sh
set -eu

version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
test -n "$version"
build_hash=${INVENTORINATOR_BUILD_HASH:-}
if [ -z "$build_hash" ]; then
  build_hash=$(git rev-parse --short=12 HEAD 2>/dev/null || printf '%s' local)
fi

exec flutter build "$@" \
  "--dart-define=INVENTORINATOR_VERSION=$version" \
  "--dart-define=INVENTORINATOR_BUILD_HASH=$build_hash"
