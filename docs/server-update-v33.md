# Update an Inventorinator server to v33

For the upcoming v0.1.1-alpha.2 build (not yet released).

1. Back up PostgreSQL.
2. Replace the complete matching server bundle, including migrations through `033_inventory_modified_time.sql`, updater, and connector.
3. Run `./apply-migrations.sh` for self-hosted Docker, or `./install-or-update.sh --hosted` for hosted PostgreSQL.
4. Confirm `Inventorinator schema v33 is ready.` Then sync updated clients.

The Modified inventory sort defaults to newest first. Item edits, quantity changes, status/location changes, and usage changes record a full timestamp. Older items fall back to their added date until edited. Opening an item and loading images do not count as edits.

Schema 33 preserves the newer modification timestamp when older offline edits arrive. Local sorting works without the migration. This is device-recorded edit time, not a server audit timestamp; devices should have accurate clocks.

Publish this guide with a shipped build and preserve older migration guides.
