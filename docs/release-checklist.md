# Release checklist

## Required on every release

- Update `version` in `pubspec.yaml` and `CHANGELOG.md`.
- Run `flutter analyze` and the complete `flutter test` suite.
- Build and start the Linux release bundle.
- Build, install, and start an Android APK on the oldest supported API and the
  current target API. Verify camera permission, barcode/OCR, import/export, and
  responsive Add/Edit forms.
- Build and start the Windows release on a clean Windows machine. Verify local
  database creation, import/export, camera availability, and sync.
- Apply every Supabase migration to a disposable database, then upgrade a copy
  of a real previous-version database.
- Verify owner/admin/manager/editor/builder behavior with separate accounts.
- Verify offline edits, two-way merge, conflict refusal, pairing, revocation,
  and shared-build use/unuse against the release server schema.
- Inspect package permissions, bundled licenses, artifact sizes, and checksums.
- Confirm no credentials, database exports, captured labels, or signing files
  are tracked by Git.

## Signing and publication

- Sign Android with the private release keystore and Windows with the release
  code-signing certificate. Never place either credential in Git.
- Publish SHA-256 checksums with Linux, Android, and Windows artifacts.
- Back up the production database before rebuilding the server connector.
- Confirm the connector reports the schema required by
  `requiredInventorinatorSchemaVersion` before distributing clients.
