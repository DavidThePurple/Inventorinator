# Optional secure token storage (issue #20)

Status: implemented as an experimental, off-by-default setting.

Remote Sync access and refresh tokens are stored in plaintext in
`sync_config.config_json`. Anyone who can read or copy the database file gets
long-lived workspace access.

## Decisions

- **Optional and off by default.** Nothing changes for anyone who never enables it.
- **Experimental.** Enabling shows a warning that must be confirmed before any token moves. It says the feature is experimental and that recovering the stored session becomes the operating system keyring's job, not Inventorinator's.
- **Per device.** Tokens belong to a device, so the toggle lives in Remote Settings on that device and any user of the device can enable it. (Open question: restrict to the workspace Owner? Default is no.)
- **Reversible.** Turning it off moves tokens back into SQLite, so nobody is signed out.
- **No silent fallback.** If no keyring is available (some Linux setups), the toggle refuses and stays off with a message.

## Recovery

If the keyring entry is lost or locked (reinstall, new OS profile, keyring reset),
Inventorinator cannot restore it. The account is unaffected: the device signs in
again through Remote Sync, and an Owner who loses their only device still uses the
existing recovery key.

A missing keyring entry must only show "signed out, reopen Remote Sync". It must
never trigger owner recovery automatically. That is the 2026-09-03 lockout bug,
where a routine token failure silently ran the destructive
`recover_inventorinator_workspace` RPC.

## Design

- Add `flutter_secure_storage`, with `flutter_secure_storage_linux_secret_service` as the Linux implementation. The default Linux implementation links `libsecret` at build and startup, which would stop the whole app from launching on systems without it, even for people who never turn this on. The secret-service package talks to GNOME Keyring or KDE Wallet over D-Bus in pure Dart, so there is no new system library.
- Tokens live in two places, not one: `sync_config.config_json` and the `known_supabase_workspaces` preference (the list used to switch between inventories). Both are covered.
- Keep the change inside `LocalDatabase`. About 15 places read the sync config
  synchronously through `loadSyncConfig()`, and secure storage is asynchronous.
  Load the secrets once at startup into an in-memory copy. `loadSyncConfig()` merges
  them into the returned JSON; `saveSyncConfig()` strips them and writes them to the
  keyring. Callers in `main.dart` and `cloud_sync_dialog.dart` stay unchanged.
- When the feature is off, `loadSyncConfig()` and `saveSyncConfig()` behave exactly
  as today.
- The setting itself is stored in SQLite (non-secret).
- Enabling: confirm the warning, write the tokens to the keyring, verify by reading
  them back, and only then strip them from the database row. If any step fails, leave
  the row untouched and stay off.
- Disabling: write the tokens back into the row, then delete the keyring entry.
- Signing out and deleting the local database clear the keyring entry too.
- Portable database exports already contain only `app_state`, never the sync config, so they carry no tokens either way.
- A keyring entry that could not be read is never deleted. A locked keyring at startup means "signed out", and routine saves must not wipe the stored sign-in.
- Enabling uses `secure_delete` and a WAL checkpoint so the old token text is overwritten in the database file. Copies of the file made before enabling, and any older backups, may still hold earlier tokens; those stop working once the tokens refresh.

## Platform notes

- Linux needs a running Secret Service (GNOME Keyring, KDE Wallet) at runtime and nothing extra to build.
- Windows builds need the C++ ATL libraries (part of Visual Studio Build Tools). Confirm the CI runner has them.
- Android needs minSdk 24, which is already Flutter's default. Auto-backup can restore the encrypted preferences without the Keystore key; the plugin resets its storage on that error, which shows up as "signed out". No backup rules were added.
- Recovery keys are still stored in the database and are not covered by this change. Moving them is a possible follow-up.

## Tests

- With the feature on, saved config JSON contains no `accessToken` or `refreshToken`.
- With the feature off, behavior is unchanged.
- Enable then disable round-trips the tokens; a failed keyring write leaves the row intact.
- Missing keyring entry with the feature on reports signed out and does not call recovery.

## Docs

`PRIVACY.md` and the release notes describe it as experimental and optional.
