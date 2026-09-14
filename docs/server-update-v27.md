# Update an existing Inventorinator server to v27

v27 adds opt-in Scratch Pad sharing. Notes remain backed up privately to their source device; only notes explicitly marked **Share with workspace** appear to other active devices.

## 1. Back up the database

```bash
cd /opt/stacks/inventorinator-supabase
DB=$(docker compose ps -q db)
docker exec "$DB" pg_dump -U postgres -d postgres -Fc > "$HOME/inventorinator-before-v27.dump"
test -s "$HOME/inventorinator-before-v27.dump"
```

## 2. Apply migration 027

Copy `027_shared_scratchpad_notes.sql` from this build into the server's `migrations` folder, then run:

```bash
cd /opt/stacks/inventorinator-supabase
./apply-migrations.sh
```

The updater applies only missing migrations. Verify it reports schema v27 before opening a client that uses note sharing.
