# Update an Inventorinator server to v32

For the upcoming v0.1.1-alpha.2 build (not released).

1. Back up PostgreSQL.
2. Replace the matching server bundle as a complete unit, including all migrations through `032_filament_drying_policy.sql`, updater, and connector.
3. Run `./apply-migrations.sh` for self-hosted Docker, or `./install-or-update.sh --hosted` for hosted PostgreSQL.
4. Confirm `Inventorinator schema v32 is ready.` Then sync updated clients.

Schema 32 adds the Owner-only **Require manual drying times** setting, off by default. Automatic material/weight estimates work locally without this migration. The migration makes the workspace setting shared and enforced on new drying cycles. Existing running timers continue.

Verify Owner-only setting changes, member reads, default automatic starts, required manual starts, and reconnecting after an offline policy change. Publish this version-specific guide to the Wiki with a shipped build; retain the v31 and older guides.
