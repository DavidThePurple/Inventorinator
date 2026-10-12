# Server update: schema 37

This update prevents an offline device from deleting a Remote record it no
longer recognizes, across inventory, locations, kits, machines, and catalog
records.

1. Back up PostgreSQL.
2. Replace the complete Supabase bundle, including migrations through
   `037_reject_all_stale_delete_tombstones.sql`.
3. Run `./apply-migrations.sh`.
4. Confirm `Inventorinator schema v37 is ready.` before reconnecting devices.

The app will now pause Remote sync with a clear migration prompt until schema
37 is installed.
