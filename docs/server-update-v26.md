# Update an existing Inventorinator server to v26

Run this on the machine hosting Supabase. This update keeps Scratch Pad notes
local to each device and adds an optional per-device remote backup.

## 1. Back up the database

Confirm the database container name with `docker ps`; the example uses the
installer default of `supabase-db`.

```sh
umask 077
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > inventorinator-before-v26.dump
```

Do not continue if the backup fails.

## 2. Apply the supplied migrations

From the extracted Inventorinator server bundle:

```sh
sh supabase/install-or-update.sh --self-hosted
```

If your database container has a different name:

```sh
SUPABASE_DB_CONTAINER=your-db-container sh supabase/install-or-update.sh --self-hosted
```

The v26 migration creates a protected backup store. A device can replace only
its own active backup. When an Owner or Admin removes a device, its backed-up
notes are prefixed with the former device name and transferred to that remover
for read-only review. No notes are copied into the shared inventory stream.

## 3. Verify

```sh
docker exec supabase-db psql -U postgres -d postgres -Atc 'select version from public.inventorinator_schema where singleton = true;'
```

Expect `26`. Existing v21–v25 servers still support inventory sync, but show
an amber update-needed status until v26 is applied.
