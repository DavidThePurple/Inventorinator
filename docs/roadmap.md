# Roadmap

## v0.2.0 (planned)

### State-safe delayed writes

- Treat eliminating local-state rollback after a save or Remote Sync response as
  a v0.2 release requirement. A database acknowledgement must never reset newer
  local edits to the older state that was originally submitted.
- Replace independent delayed saves and reloads with per-record write queues so
  an older database response cannot overwrite a newer user action.
- Preserve locally edited fields while an item creation or earlier update is
  still being committed; for example, changing a new filament from Ready to Wet
  must survive the initial database refresh.
- Add revision-aware merging for local persistence and Remote Sync rather than
  treating debouncing alone as conflict resolution.
- Never respond to a successful record write by reloading the whole inventory.
  Acknowledge only the submitted record revision and retain any newer queued
  field changes on that item.
- Merge incoming changes field-by-field against the local outbox. Locally dirty
  fields remain authoritative until their exact revision is acknowledged;
  unrelated incoming fields and records may continue applying asynchronously.
- Show a lightweight pending/saved state where feedback is useful without
  blocking continued edits.
  Implementation status: complete for debounced quantity changes; broaden this
  feedback as the remaining queued-write paths move to the record outbox.
- Add race-condition tests for rapid quantity, status, location, lifecycle, and
  item-detail changes.
- Add a required end-to-end test that creates an item, immediately changes its
  status or another field while the initial image/database write is delayed,
  receives both local and remote acknowledgements out of order, and proves the
  newest visible value never rolls back on either device.

### Detailed personalization, notifications, and sound

Implementation status: in progress. Per-device master mute and independent
Remote-addition, drying-complete, and moisture-threshold chime controls are
available together in Personalization. Low-stock visual notifications can also
be disabled independently per device without changing item thresholds.

- Provide per-effect controls for card, status, alert, moisture, and Remote Sync
  animations, including intensity and duration where appropriate.
- Provide per-alert notification controls for low stock, moisture, drying,
  Remote Sync changes, and other supported events.
- Allow each alert type to select its sound, preview it, set volume, choose
  recurrence, or remain silent while retaining its visual notification.
- Keep notification, sound, and appearance preferences per device unless the
  user explicitly chooses a shared behavior.

### Spool usage controls

- Record spool consumption through manual weight, length, or percentage
  adjustments without forcing a quantity change.
- Track starting amount, tare, remaining material, and usage history for each
  individual spool split from a stack.
- Support corrections, refills, spool transfers, and usage attribution to a
  printer, build, or project without destroying the audit trail.
- Make low-material and moisture behavior work from the remaining spool amount.

### Multi-color filament support

Implementation status: in progress. URL import now recognizes explicit color
names and hexadecimal swatches from structured product data and product pages.

- Allow one filament item or spool to contain multiple named colors rather than
  forcing it into a single color field.
- Preserve the color order for gradients, coextrusions, transitions, and other
  intentionally multi-color filaments.
- Display multi-color swatches consistently on item cards, details, filters,
  JSON import/export, and Remote Sync.
- Let color filtering match any color assigned to the filament while keeping
  the complete multi-color identity visible.
- Extend product URL import to detect filament color names, HTML color swatches,
  hexadecimal values, RGB/HSL values, and other vendor-provided color codes.
- Normalize convertible values to sRGB hex for display and matching while also
  retaining the original vendor color name and code.
- Add import review when a page exposes conflicting product-level and
  variant-level colors instead of silently choosing the wrong value.

### Filament purpose and property tags

Implementation status: in progress. Filament purpose tags can now be edited,
saved, searched, and displayed on item cards and details.

- Add visible, filterable filament tags for construction, intended use, print
  role, handling priority, and verified material properties.
- Include useful starter tags such as **Coextruded**, **Four color**,
  **Support only**, **Prototype**, **Use first**, **Engineering**, and
  **Beauty prints only**, while allowing users to create their own tags.
- Show tags on filament cards and details without forcing important distinctions
  into the item name or material field.
- Distinguish decorative fillers and marketing finishes from functional
  reinforcement; for example, **Carbon-fiber appearance** must not imply the
  strength, stiffness, heat resistance, or abrasion behavior of a verified
  carbon-fiber composite.
- Track whether a property claim comes from a manufacturer datasheet, user
  testing, or an unverified product description, and keep the original source.
- Let URL and JSON imports suggest tags, but require review before applying
  performance or engineering-property tags.
- Support tag-based search, filters, metrics, purchasing, and spool-selection
  guidance without treating tags as safety certifications.

### Filterable item metrics

- Add an item metrics view covering quantity, value, consumption, low stock,
  moisture, age, and inventory movement.
- Filter metrics by date range, item type, material, brand, vendor, location,
  machine, kit, and archived state.
- Let users move from a metric directly to the filtered inventory records that
  produced it.

### Inventory sorting controls

Implementation status: complete in the current v0.2 development branch.

- Add **Added Date** to the main inventory sort options using each item's
  original creation timestamp rather than its latest edit or sync time.
- Add an invert-sort control that switches the active sort between ascending
  and descending without requiring a second option for every sort type.
- Persist the selected sort and direction per device and make the current
  direction visually unambiguous on desktop and Android.
- Define deterministic tie-breaking so repeated sorting and Remote Sync do not
  make equal-valued items jump around.

### New Items review clarity

Implementation status: complete in the current v0.2 development branch.

- Give every entry in the **New Items** window a consistent second information
  line showing its color or colors and storage location.
- Keep missing values explicit but visually quiet so entries remain aligned and
  users can quickly spot items that still need a color or location.
- Make the second line responsive and readable on both desktop and Android
  without truncating the primary item name.

### Per-device inventory visibility

Implementation status: complete in the current v0.2 development branch.

- Persist the **Hide quantity 0 items** toggle in SQLite as a per-device
  preference.
- Restore it at launch without Remote Sync changing another device's choice.
- Define the same per-device persistence behavior for other view-only controls
  as they are added.

### Rudimentary in-app onboarding

Implementation status: complete in the current v0.2 development branch.

- Add a short first-run path covering local inventory, Remote Sync, adding the
  first item, searching, Stockroom locations, and backup/export.
- Let users choose an empty inventory or demo data and clearly explain the
  consequences before creating either.
- Keep onboarding skippable, resumable, and available again from Help.

### Windows camera compatibility and recovery

- Investigate the front-facing camera on the ROG Flow Z13 Kojima Edition
  (`z13-kjp`), where Inventorinator can claim or activate the camera without
  displaying a preview even though other applications can open it normally.
- Record camera enumeration, selected device ID, supported formats, negotiated
  resolution/frame rate, initialization state, and native backend errors in a
  user-readable diagnostic view.
- Test front/rear camera switching, reopening the scanner, app suspend/resume,
  permission changes, and recovery after a failed initialization.
- Add a bounded initialization timeout that releases the camera and offers a
  retry or alternate format instead of leaving it apparently busy.
- Verify the fix on `z13-kjp` hardware and retain regression coverage for the
  existing Windows camera selector.

### Printed-part model attachments

- Attach STL files to Printed Part inventory records.
- Generate and cache a lightweight preview thumbnail without blocking the UI.
- Provide an interactive rotate and zoom STL preview on desktop and Android.
- Store attachment metadata and checksums separately from the local SQLite state.

### Optional Nextcloud and WebDAV storage

- Add a generic attachment-storage interface; local files remain the default.
- Offer Nextcloud as a WebDAV preset using a revocable app password.
- Upload and retrieve STL attachments and portable database backups.
- Keep SQLite as local storage and Supabase as Remote Sync; WebDAV does not
  replace inventory synchronization, roles, audit history, or conflict rules.
- Add offline transfer state, checksum verification, retry handling, and clear
  local-only/remote-available indicators before enabling shared attachments.
