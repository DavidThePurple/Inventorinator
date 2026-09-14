# Update an existing Inventorinator server to v28

v28 preserves the optional subject link on a Scratch Pad note. v27 remains the
feature that makes an explicitly shared note visible to other active devices.
Private notes stay backed up to their source device.

## 1. Replace the complete Supabase bundle

Use the Supabase bundle from the same Inventorinator release as the app. Replace
the server's bundle as a complete unit, including `migrations/`,
`install-or-update.sh`, and `apply-migrations.sh`. Do not move individual SQL
files or run them by hand.

## 2. Back up and apply

```bash
cd /opt/stacks/inventorinator-supabase
DB=$(docker compose ps -q db)
docker exec "$DB" pg_dump -U postgres -d postgres -Fc > "$HOME/inventorinator-before-v28.dump"
test -s "$HOME/inventorinator-before-v28.dump"

./apply-migrations.sh
```

The updater applies every missing migration in order and must finish with:

```text
Inventorinator schema v28 is ready.
```

If it says the updater is missing the v28 migration, the server has a mixed
bundle. Replace the complete bundle and run the same command again.

## 3. Confirm note sharing

Open Scratch Pad on both devices. A note appears on another device only when
**Share with workspace** is enabled. Private notes remain device-local while
their backup stays available for recovery and removed-device review.
