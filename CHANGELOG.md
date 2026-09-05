# Changelog

All notable changes to Inventorinator will be recorded here.

## [0.1.1-alpha] - Unreleased

### Added

- A collapsible, default-collapsed Metrics panel above the search bar,
  showing filament spool count (summed by quantity, not row count, so
  multi-spool stacks count correctly), total units, item records, and
  low-stock count.
- A "Tracked types" chip row on the Metrics panel so any built-in or custom
  item type can be excluded from its stats and charts, persisted per device.
- An overlaid inventory-growth chart on the Metrics panel: per-type
  cumulative trends in hue-rotated shades of the active theme accent, with a
  "Unified" toggle to switch to one aggregate curve for the whole tracked
  inventory.
- A filament Style attribute: Flat, Matte, Silk, Galaxy, Glitter, Glow,
  Carbon Fiber (Chopped/Ground), Glass Fiber, Gradient, and Coextruded, with
  up to two styles per item. Gradient gets a live-blended gradient editor and
  a single name shown inline next to the item's color, same as a regular
  color name. Coextruded gets a named color slot per strand and renders as a
  pie-chart chicklet on item cards, with strand names surfaced on hover
  rather than crowding the card.

### Fixed

- A device's session simply failing to refresh (a routine, recoverable
  event) no longer triggers an automatic, silent workspace-ownership
  transfer. That transfer evicts every other device claiming ownership and
  rotates the shared recovery key; it now only happens from the explicit,
  user-initiated "Recover ownership" action.
- Same-field edits made by two devices around the same time are no longer
  silently resolved by picking one side - the collision is now recorded to
  the Audit Log while still keeping the local edit, so it's visible instead
  of invisible.
- Local "Saved" feedback, previously shown only for quantity changes, now
  covers status, location, lifecycle, and other item-detail edits.
- Removed an unused, superseded three-way merge module that had no
  production callers and risked being mistaken for the sync path actually in
  use.

## [0.1.0-alpha] - 2026-09-02

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
