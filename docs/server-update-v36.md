# Server update: schema 36

This update prevents a stale device from turning an old local deletion into a
blind Remote tombstone.

1. Back up PostgreSQL.
2. Replace the complete Supabase bundle, including migrations through
   `036_reject_stale_delete_tombstones.sql`.
3. Run `./apply-migrations.sh`.
4. Confirm `Inventorinator schema v36 is ready.` before reconnecting devices.

If a record changed on Remote after a device last saw it, that device now keeps
its deletion in the conflict-review queue instead of deleting the Remote copy.
