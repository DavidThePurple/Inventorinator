# Changelog

All notable changes to Inventorinator will be recorded here.

## [1.0.0] - 2026-08-28

### Added

- Linux, Android, and Windows inventory application.
- Local SQLite storage with portable database import and export.
- Optional hosted or self-hosted Supabase synchronization.
- Inventory, catalog, machine, kit/BOM, shared build, role, audit, QR,
  barcode, OCR, filament lifecycle, alert, and animation workflows.

### Security

- Server-enforced owner, admin, manager, editor, and builder boundaries.
- Builder quantity changes must exactly match shared Build use/unuse actions.
- Android release builds require a private maintainer keystore.

### Known limitations

- Cloud sync requires Inventorinator connector schema 7. Existing schema 6
  servers must be migrated before connecting this release.
