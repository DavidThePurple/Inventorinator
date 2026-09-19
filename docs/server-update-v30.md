# Update an Inventorinator server to v30

**For the upcoming v0.1.1-alpha.2 build (not yet released).** CI artifacts are test builds, not published releases.

Schema 30 adds safe import undo. It refuses to remove an imported item that
another device has edited or linked to a kit, build, or other record.

1. Back up the server's PostgreSQL database.
2. Replace the extracted Supabase bundle as a complete unit with the bundle
   from the same app release. Keep the updater, connector, and all migrations
   through `030_guarded_import_undo.sql` together.
3. For self-hosted Docker, run from that extracted bundle:

   ```bash
   ./apply-migrations.sh
   ```

   For hosted Supabase, run `./install-or-update.sh --hosted` instead.

4. Confirm `Inventorinator schema v30 is ready.` Then reconnect/sync the app.

Ordinary sync works on supported older schemas, but import undo waits for v30.
No live server is upgraded by editing this repository.

Published guide: [Server Update v30](https://github.com/DavidThePurple/Inventorinator/wiki/Server-Update-v30). Older version guides remain available.
