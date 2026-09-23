# Update an Inventorinator server to v34

For the upcoming v0.1.1-alpha.2 build (not yet released).

1. Back up PostgreSQL.
2. Replace the complete matching server bundle, including migrations through `034_checkout_sync.sql`, updater, and connector.
3. Run `./apply-migrations.sh` for self-hosted Docker, or `./install-or-update.sh --hosted` for hosted PostgreSQL.
4. Confirm `Inventorinator schema v34 is ready.` Then sync updated clients.

Checkouts record who has borrowed how much of an inventory item, without changing the total owned. Each device keeps its own checkouts. The workspace Owner or an Admin decides whether they are shared: Remote Settings has a **Sync checkouts** switch, off by default. While it is off, checkouts stay on the device that made them and the server holds none.

Schema 34 stores that switch on the workspace and lets Owners, Admins, Managers, Editors and Builders record checkouts. Custom roles need Inventory edit or Build operation. It changes nothing else about roles: Editors and Builders still cannot edit the catalog.

Publish this guide with a shipped build and preserve older migration guides.
