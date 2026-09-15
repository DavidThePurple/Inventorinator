# Update an existing Inventorinator server to v29

v29 fixes false sync conflicts when a device deletes a record after it has an
earlier queued local edit. A deletion is now applied after the latest remote
record and does not require conflict review.

## 1. Replace the complete Supabase bundle

Use the Supabase bundle from the same Inventorinator release as the app.
Replace the server bundle as a complete unit, including `migrations/`,
`install-or-update.sh`, and `apply-migrations.sh`. Do not move individual SQL
files or run them by hand.

## 2. Back up and apply

```bash
cd /opt/stacks/inventorinator-supabase
DB=$(docker compose ps -q db)
docker exec "$DB" pg_dump -U postgres -d postgres -Fc > "$HOME/inventorinator-before-v29.dump"
test -s "$HOME/inventorinator-before-v29.dump"

./apply-migrations.sh
```

The updater applies every missing migration in order and must finish with:

```text
Inventorinator schema v29 is ready.
```

If it says the updater is missing the v29 migration, the server has a mixed
bundle. Replace the complete bundle and run the same command again.

## 3. Confirm the fix

Delete a record that has a pending local change, then sync. The record should
be removed without a Sync conflicts entry.
