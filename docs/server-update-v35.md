# Update an Inventorinator server to v35

For the upcoming v0.1.1-alpha.2 build (not yet released).

1. Back up PostgreSQL.
2. Replace the complete matching server bundle, including migrations through `035_owner_device_recovery_guard.sql`, updater, and connector.
3. Run `./apply-migrations.sh` for self-hosted Docker, or `./install-or-update.sh --hosted` for hosted PostgreSQL.
4. Confirm `Inventorinator schema v35 is ready.` Then sync updated clients.

Schema 35 closes an Owner recovery gap. Recovering ownership now blocks both the replaced Owner's anonymous account and its stable device identity, and the client registers that identity for every Owner device. A stolen or wiped former Owner device cannot return with a fresh anonymous account and a later pairing code.

Recovery still preserves the shared inventory and team members. It rotates the recovery key and invalidates unused pairing codes. Keep the newly displayed recovery package somewhere safe.

Publish this guide with a shipped build and preserve older migration guides.
