# Changelog

All notable changes to Inventorinator will be recorded here.

## [0.1.0-alpha] - Unreleased

### Added

- Optional FilamentColors.xyz swatch search with brand/material prefiltering,
  local caching, offline fallback, attribution, automatic filament detail
  entry, request throttling, and server cooldown handling.
- Searchable Lucide and Material Type icons, plus custom Type icon image upload
  and Base64/data-URL paste support.
- Desktop `.inventorinator-kit.json` validation, preview, and confirmed import,
  with optional AI-assisted BOM research and no built-in AI account or API key.
- Imported kit parts begin at quantity zero, with stable deduplication, source
  records, sections, catalog products, materials, brands, and machines.

### Security

- Shared-inventory ownership now survives auth-user deletion, preserves stolen
  device blocks and audit history, and revokes stale pairing codes on recovery.

### Fixed

- Empty storage locations are no longer deleted when a stale snapshot-based
  device synchronizes. Schema 13 also restores location tombstones previously
  created by that compatibility path.

## [0.0.9-alpha] - 2026-08-28

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
- Shared inventories provide a rotatable owner recovery package for lost or
  stolen devices; recovery revokes the previous owner session.

### Known limitations

- Cloud sync requires Inventorinator connector schema 8. Existing schema 7
  servers must be migrated before connecting this release.
