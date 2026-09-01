# Inventorinator on Supabase

Inventorinator remains usable offline in local SQLite. Supabase adds shared
inventory, device roles, audit history, and synchronized Builds.

## Why migrations run on the server

The Flutter app only receives Supabase's client-safe publishable key. Giving a
phone or desktop app the database password or service-role key would let anyone
extract full administrator access. Therefore:

- the app checks the server schema version whenever it connects or starts sync;
- the `inventorinator-connector` applies pending SQL migrations when its
  container starts;
- an outdated server is rejected with its installed and required versions;
- the connector never exposes the PostgreSQL password to an app client.

Current required schema: **v11**.

Schema v8-v10 add owner recovery and durability. Save the recovery package
when creating a shared inventory. It can transfer ownership to a replacement
device, lock out the previous owner device, and preserve the workspace if an
anonymous auth identity is lost.

## One-command installer and updater

Run the interactive installer shipped with Inventorinator:

```sh
./supabase/install-or-update.sh
```

Choose hosted Supabase or a self-hosted Docker stack. For hosted Supabase, paste
the PostgreSQL connection string from the project's **Connect** dialog when
prompted; it is read silently and is not saved. For self-hosting, the script
uses the `supabase-db` container by default. It detects the installed schema,
applies only missing migrations, and verifies the result.

If `psql` is unavailable for a hosted project, the installer can use Docker's
official PostgreSQL image instead.

## Add the connector to a self-hosted Supabase stack

Place this `supabase` directory inside the Supabase Compose directory as
`inventorinator/`. The resulting paths should include:

```text
inventorinator/connector/Dockerfile
inventorinator/connector/entrypoint.sh
inventorinator/migrations/001_workshop_state.sql
inventorinator/docker-compose.inventorinator.yml
```

Start the stack with the connector override:

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.private.yml \
  -f inventorinator/docker-compose.inventorinator.yml \
  up -d --build inventorinator-connector
```

For Dockge, copy the `inventorinator-connector` service from
`docker-compose.inventorinator.yml` into the stack's private override. Dockge
will then rebuild and start it with the rest of Supabase.

The connector waits for PostgreSQL, reads `inventorinator_schema`, applies only
newer numbered migrations in order, reloads PostgREST's schema cache, and then
reports healthy. Starting it repeatedly is safe.

## Updating

1. Back up the Supabase PostgreSQL database.
2. Replace the server's `inventorinator/connector` and
   `inventorinator/migrations` folders with those from the new release.
3. In Dockge, choose **Update** or **Rebuild** for the Supabase stack. From a
   terminal, run the Compose command above.
4. Confirm the connector log ends with `Inventorinator schema vN is ready.`
5. Start Inventorinator. Its startup sync verifies that the server meets the
   application's required schema before reading or writing shared data.

No SQL pasting or AI assistance is required during a normal update.

## Manual recovery

If the connector service cannot be installed yet, run the same installer in
self-hosted mode:

```sh
./install-or-update.sh --self-hosted
```

By default this targets the `supabase-db` container. Override it with
`SUPABASE_DB_CONTAINER` when the database container has another name.

## Optional build defaults

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://inventory.example.com \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_example
```

Never place the dashboard password, database password, JWT secret, or
Supabase service-role key in the Flutter app.
