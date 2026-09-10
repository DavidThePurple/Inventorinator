# Changelog

All notable changes to Inventorinator will be recorded here.

## [0.1.1-alpha.2] - Unreleased

### Fixed

- Inventory paging now filters, sorts, counts, and selects pages in SQLite. Item and thumbnail caches are limited to the active page; offline inventory and images remain on disk.

- Supplier imports use descriptive item names and existing category matches, ask for unmatched types, and preserve supplier details when changing type. Supplier search actions are grouped above the form with a responsive header.

### Added

- BIQU/BIGTREETECH, E3D, Polymaker, Printed Solid, and Slice Engineering search/import through the shared storefront client, with official logos, variant selection, supplier-specific metadata, and cached photos.

- Adafruit keyword/part-number search using a persistent SQLite catalog, one-request refresh, offline searching, and 12-result database-backed pages.

- LDO storefront search/variant import and Adafruit product-ID/link lookup, with cached results and a persistent local cooldown indicator respecting Adafruit request limits.

- Supplier product previews and offline image import for DigiKey, Mouser, and West3D, with bounded, deduplicated CDN downloads and existing-photo preservation.

- Compact Search suppliers dropdown with supplier logos; researched product API candidates are tracked in `docs/supplier-integrations.md`.

- West3D product search and variant import without API credentials, using on-demand storefront requests.

- Persistent local item drafts with a draft picker, deletion, and a Personalization option to resume the latest unfinished item.

- Mouser Search API integration with product import, persistent local and owner-only remote credentials, and connection indicators (schema 24).

- Configured services show connection LEDs beside the logo; connection details stay inside their Remote Settings pullouts.

- DigiKey credentials now persist locally with owner-only remote storage and offline pending updates (schema 23).

- Remote Settings replaces the Remote Sync page title and includes a DigiKey
  settings pullout below Supabase Settings, shared by later search windows.
- DigiKey keyword search, packaging selection and reviewed inventory creation;
  requires a user-supplied subscribed DigiKey developer application.
- Local role drafts are accessible without Supabase and persist on this device.

- Owner-only role builder with named templates, operation descriptions,
  quick presets, duplication, editing and deletion.
- Schema 22 stores role templates with owner-only server authorization.
  Templates are unassigned drafts: existing device roles remain authoritative.

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
