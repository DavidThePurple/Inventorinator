# Update an Inventorinator server to v31

For the upcoming v0.1.1-alpha.2 build. No release has been published.

1. Back up PostgreSQL and export local inventory databases.
2. Replace the server bundle as a complete unit with the matching schema 31 bundle, including all migrations, updater, and connector.
3. For self-hosted Docker run `./apply-migrations.sh`. For hosted Supabase run `./install-or-update.sh --hosted`.
4. Confirm `Inventorinator schema v31 is ready.` Update the app and sync each device.

Re-pairing now restores Scratch Pad notes using the stable device ID. Recovered notes wait on the server until the device downloads and backs them up; an empty first backup cannot erase them. Different local edits are kept alongside recovered copies.

Older archived notes may lack a stable device ID. The administrator who removed the device can open an archived note in Scratch Pad, choose **Restore to device**, and select its current device (for example VM1). Device names alone never trigger automatic reassignment. Sync the receiving device to retrieve the note.

Verify removal and re-pairing, a changed login, private/shared notes, linked subjects, and a local edit made before recovery. Locked-out devices must remain blocked. Preserve the v28 and v30 Wiki guides when publishing this guide with the build.

## Owner note authority

The workspace Owner can inspect, edit, and delete any note backed up to that workspace, including unshared notes and archives held by another administrator. Administrators and other roles do not gain this authority. Notes that have never synced remain on their device.

Owner edits and deletion markers reach the author on the next sync. Stale backups cannot overwrite an Owner edit or resurrect a deleted note. Concurrent edits are rejected with a request to sync and reopen the note. Sharing remains off unless the author enables it.
