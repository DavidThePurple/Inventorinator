#!/bin/sh
set -eu

export PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
database_host="${POSTGRES_HOST:-db}"
database_port="${POSTGRES_PORT:-5432}"
database_name="${POSTGRES_DB:-postgres}"
database_user="${POSTGRES_USER:-postgres}"

until pg_isready -h "$database_host" -p "$database_port" -U "$database_user" -d "$database_name" >/dev/null 2>&1; do
  sleep 2
done

psql_command="psql -h $database_host -p $database_port -U $database_user -d $database_name -v ON_ERROR_STOP=1"
if $psql_command -Atqc "select to_regclass('public.inventorinator_schema') is not null" | grep -qx t; then
  current_version=$($psql_command -Atqc "select coalesce(max(version), 0) from public.inventorinator_schema")
else
  current_version=0
fi

for migration in /connector/migrations/*.sql; do
  migration_name=$(basename "$migration")
  migration_version=$(expr "${migration_name%%_*}" + 0)
  if [ "$migration_version" -le "$current_version" ]; then
    echo "Already applied: $migration_name"
    continue
  fi
  echo "Applying $migration_name"
  $psql_command -f "$migration"
  current_version=$migration_version
done

$psql_command -c "notify pgrst, 'reload schema'" >/dev/null
echo "Inventorinator schema v$current_version is ready."

exec python /connector/server.py
