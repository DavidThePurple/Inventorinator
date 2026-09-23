# Optional secure token storage (issue #20)

Status: planned. Remote Sync access and refresh tokens are stored in plaintext in
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

- Add `flutter_secure_storage`.
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
- Exports and backups must not carry live tokens while the feature is on.

## Platform notes

- Linux needs `libsecret-1-dev` in CI and release builds, and a running secret
  service at runtime.
- Android backup rules must exclude the secure-storage preferences.
- Windows uses Credential Manager and needs no extra setup.

## Tests

- With the feature on, saved config JSON contains no `accessToken` or `refreshToken`.
- With the feature off, behavior is unchanged.
- Enable then disable round-trips the tokens; a failed keyring write leaves the row intact.
- Missing keyring entry with the feature on reports signed out and does not call recovery.

## Docs

`PRIVACY.md` and the release notes describe it as experimental and optional.
