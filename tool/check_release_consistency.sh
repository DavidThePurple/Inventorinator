#!/usr/bin/env sh
set -eu

app_version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
installer_tag=$(sed -n 's/^release_tag=.*:-\(v[^}]*\)}$/\1/p' supabase/install-or-update.sh)
installer_schema=$(sed -n 's/^required_version=\([0-9][0-9]*\)$/\1/p' supabase/install-or-update.sh)
connector_schema=$(sed -n 's/^SCHEMA_VERSION = \([0-9][0-9]*\)$/\1/p' supabase/connector/server.py)
client_schema=$(sed -n 's/^const requiredInventorinatorSchemaVersion = \([0-9][0-9]*\);$/\1/p' lib/supabase_sync.dart)
latest_migration=$(find supabase/migrations -maxdepth 1 -type f -name '[0-9][0-9][0-9]_*.sql' \
  -printf '%f\n' | sort | tail -n 1 | sed 's/^0*\([0-9][0-9]*\)_.*/\1/')
release_notes="docs/releases/v$app_version.md"

test -n "$app_version"
test "$installer_tag" = "v$app_version"
test "$installer_schema" = "$latest_migration"
test "$connector_schema" = "$latest_migration"
test "$client_schema" = "$latest_migration"
test -s "$release_notes"
grep -Fq "schema $latest_migration" "$release_notes"
grep -Fq "Supabase-schema$latest_migration.tar.gz" "$release_notes"

printf 'Release v%s and schema v%s are consistent.\n' \
  "$app_version" "$latest_migration"
