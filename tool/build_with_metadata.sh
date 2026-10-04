#!/usr/bin/env sh
set -eu

for build_arg in "$@"; do
  case "$build_arg" in
    --dart-define=SUPABASE_URL=*|--dart-define=SUPABASE_PUBLISHABLE_KEY=*)
      echo 'Refusing build: do not bake Supabase connection defaults into Inventorinator.' >&2
      exit 1
      ;;
  esac
done

version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
test -n "$version"
build_hash=${INVENTORINATOR_BUILD_HASH:-}
if [ -z "$build_hash" ]; then
  build_hash=$(git rev-parse HEAD 2>/dev/null || printf '%s' local)
fi

local_changes=false
if [ -n "$(git status --porcelain -- . ':!dist' ':!build' 2>/dev/null)" ]; then
  local_changes=true
fi

exec flutter build "$@" \
  "--dart-define=INVENTORINATOR_VERSION=$version" \
  "--dart-define=INVENTORINATOR_BUILD_HASH=$build_hash" \
  "--dart-define=INVENTORINATOR_LOCAL_CHANGES=$local_changes"
