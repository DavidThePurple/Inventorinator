#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
container=${SUPABASE_DB_CONTAINER:-supabase-db}

for migration in "$script_dir"/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  docker exec -i "$container" psql \
    -U postgres -d postgres -v ON_ERROR_STOP=1 < "$migration"
done

echo "Inventorinator connector is up to date."
