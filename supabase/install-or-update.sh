#!/usr/bin/env sh
set -eu

release_tag=${INVENTORINATOR_RELEASE_TAG:-v1.1.0}
required_version=12
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
migrations_dir=$script_dir/migrations
temporary_dir=
mode=

usage() {
  cat <<'EOF'
Install or update the Inventorinator schema on Supabase.

Usage:
  ./install-or-update.sh                 Interactive mode
  ./install-or-update.sh --hosted        Hosted Supabase/PostgreSQL URL
  ./install-or-update.sh --self-hosted   Supabase Docker container

Optional environment variables:
  INVENTORINATOR_DB_URL       Hosted PostgreSQL connection string
  SUPABASE_DB_CONTAINER       Self-hosted database container (supabase-db)
  INVENTORINATOR_RELEASE_TAG  Migration release to download when needed
EOF
}

case ${1:-} in
  --hosted) mode=hosted ;;
  --self-hosted) mode=self-hosted ;;
  --help|-h) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit 2 ;;
esac

if [ -z "$mode" ]; then
  printf '%s\n' \
    'Where is Supabase running?' \
    '  1) Hosted Supabase or another PostgreSQL server' \
    '  2) Self-hosted Supabase Docker stack'
  printf 'Choose 1 or 2: '
  IFS= read -r choice
  case $choice in
    1) mode=hosted ;;
    2) mode=self-hosted ;;
    *) echo 'Choose 1 or 2.' >&2; exit 2 ;;
  esac
fi

cleanup() {
  if [ -n "$temporary_dir" ] && [ -d "$temporary_dir" ]; then
    rm -rf -- "$temporary_dir"
  fi
}
trap cleanup EXIT HUP INT TERM

download_migrations() {
  temporary_dir=$(mktemp -d)
  migrations_dir=$temporary_dir/migrations
  mkdir -p "$migrations_dir"
  base_url="https://raw.githubusercontent.com/DavidThePurple/Inventorinator/$release_tag/supabase/migrations"
  migration_names='001_workshop_state.sql 002_anonymous_workspaces.sql 003_device_roles.sql 004_owner_devices.sql 005_team_roles_audit.sql 006_shared_build_permissions.sql 007_builder_quantity_integrity.sql 008_owner_recovery.sql 009_owner_durability.sql 010_owner_resilience.sql 011_device_role_management.sql 012_incremental_entity_sync.sql'

  echo "Downloading Inventorinator migrations from $release_tag..."
  for migration_name in $migration_names; do
    destination=$migrations_dir/$migration_name
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$base_url/$migration_name" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
      wget -q "$base_url/$migration_name" -O "$destination"
    else
      echo 'Install curl or wget, then run this installer again.' >&2
      exit 1
    fi
  done
}

if [ ! -f "$migrations_dir/001_workshop_state.sql" ]; then
  download_migrations
fi

if [ "$mode" = hosted ]; then
  database_url=${INVENTORINATOR_DB_URL:-}
  if [ -z "$database_url" ]; then
    printf '%s\n' \
      'Paste the PostgreSQL connection string from Supabase Connect.' \
      'It is read silently and is not saved by this script.'
    printf 'PostgreSQL connection string: '
    stty -echo 2>/dev/null || true
    IFS= read -r database_url
    stty echo 2>/dev/null || true
    printf '\n'
  fi
  case $database_url in
    postgresql://*|postgres://*) ;;
    *) echo 'Expected a postgresql:// or postgres:// connection string.' >&2; exit 2 ;;
  esac

  if command -v psql >/dev/null 2>&1; then
    run_psql() {
      psql "$database_url" -X -v ON_ERROR_STOP=1 "$@"
    }
  elif command -v docker >/dev/null 2>&1; then
    echo 'psql was not found; using the official PostgreSQL Docker image.'
    run_psql() {
      docker run --rm -i postgres:17-alpine \
        psql "$database_url" -X -v ON_ERROR_STOP=1 "$@"
    }
  else
    echo 'Install PostgreSQL psql or Docker, then run this installer again.' >&2
    exit 1
  fi
else
  container=${SUPABASE_DB_CONTAINER:-supabase-db}
  if ! command -v docker >/dev/null 2>&1; then
    echo 'Docker is required for self-hosted installation.' >&2
    exit 1
  fi
  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "Supabase database container '$container' was not found." >&2
    echo 'Set SUPABASE_DB_CONTAINER if your container has another name.' >&2
    exit 1
  fi
  run_psql() {
    docker exec -i "$container" \
      psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 "$@"
  }
fi

echo 'Checking the database connection...'
run_psql -Atqc 'select 1' >/dev/null

schema_table=$(run_psql -Atqc "select to_regclass('public.inventorinator_schema')" | tr -d '[:space:]')
if [ -z "$schema_table" ]; then
  current_version=0
else
  current_version=$(run_psql -Atqc 'select coalesce(max(version), 0) from public.inventorinator_schema' | tr -d '[:space:]')
fi

case $current_version in
  ''|*[!0-9]*) echo "Invalid installed schema version: $current_version" >&2; exit 1 ;;
esac

echo "Installed schema: v$current_version"
for migration in "$migrations_dir"/*.sql; do
  migration_name=$(basename "$migration")
  padded_version=${migration_name%%_*}
  migration_version=$(printf '%s' "$padded_version" | sed 's/^0*//')
  migration_version=${migration_version:-0}
  if [ "$migration_version" -le "$current_version" ]; then
    echo "Already applied: $migration_name"
    continue
  fi
  echo "Applying $migration_name"
  run_psql < "$migration"
  current_version=$migration_version
done

installed_version=$(run_psql -Atqc 'select version from public.inventorinator_schema where singleton = true' | tr -d '[:space:]')
if [ "$installed_version" -lt "$required_version" ]; then
  echo "Schema v$installed_version installed; this release requires v$required_version." >&2
  exit 1
fi

echo "Inventorinator schema v$installed_version is ready."
