# Update an existing Inventorinator server from v21 to v25

Run these steps on the machine hosting Supabase, not on an Inventorinator client.
Use the migration bundle from this build; these changes may not be in a published release yet.

## 1. Back up the database

Confirm the database container name with `docker ps`. The commands below use the
installer's default `supabase-db`; substitute your actual name if different.

```sh
umask 077
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > inventorinator-before-v25.dump
```

Check that the command succeeded and retain the backup on protected storage.
It contains sensitive database data. Do not continue if backup fails.

## 2. Apply the bundled migrations

Extract `inventorinator-server-v25.tar.gz` and run from the extracted folder:

```sh
sh supabase/install-or-update.sh --self-hosted
```

For a different database container:

```sh
SUPABASE_DB_CONTAINER=your-db-container sh supabase/install-or-update.sh --self-hosted
```

The updater detects v21 and applies only:

- v22: owner-only role templates (drafts, not live permission changes).
- v23: owner-only DigiKey credential storage.
- v24: owner-only Mouser credential storage.
- v25: custom-role assignment/enforcement and conditional field writes for sync conflicts.

Each migration runs in a transaction. If one fails, stop and inspect the error;
rerunning after correcting it skips completed migrations. Do not reset the database.

## 3. Refresh the existing connector deployment

If you run the Inventorinator connector container, replace its existing build
context with this bundle's `supabase/connector` and `supabase/migrations` contents.
Keep your existing environment, passwords, networks, ports and Compose settings.
The example Compose file expects that context under `./inventorinator` beside the
Supabase Compose file. Use the same Compose files/project flags you normally use:

```sh
docker compose -f docker-compose.yml -f docker-compose.inventorinator.yml up -d --build --no-deps inventorinator-connector
docker compose -f docker-compose.yml -f docker-compose.inventorinator.yml logs --tail=50 inventorinator-connector
```

These example filenames must match your deployment. This rebuilds only the
connector; it does not recreate the database. The connector also applies any
remaining migrations at startup.

## 4. Verify

```sh
docker exec supabase-db psql -U postgres -d postgres -Atc 'select version from public.inventorinator_schema where singleton = true;'
```

Expect `25`. The connector log should report `Inventorinator schema v25 is ready`.
After the next successful app sync, the Supabase LED should turn green. Open Remote Settings to sync credentials and assign saved roles. Local role drafts must be saved to the remote role builder before assignment. Existing devices retain their built-in roles until the owner explicitly changes them.

Until updated, the new client supports inventory sync on v21–v24 and shows an
amber compatibility warning. Servers older than v21 still block inventory sync.
An actual network, authorization or inventory-sync failure still shows red.

For hosted Supabase, back up the database with your provider's tools, then run
`sh supabase/install-or-update.sh --hosted` and supply the database connection
string at its silent prompt. No connector restart is needed if none is deployed.
