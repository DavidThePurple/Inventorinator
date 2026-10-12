# Server update: schema 38

This update makes Remote deletion explicit-only. A record missing from one
device's cache or partial local state can never delete the shared record.

1. Back up PostgreSQL.
2. Replace the complete Supabase bundle, including migrations through
   `038_require_explicit_delete_intent.sql`.
3. Run `./apply-migrations.sh`.
4. Confirm `Inventorinator schema v38 is ready.` before reconnecting devices.

After this update, the Remote accepts ordinary deletes only when the app sends
both a deliberate delete intent and the exact current record baseline. Stale,
partial, or older clients are rejected instead of deleting shared data.
