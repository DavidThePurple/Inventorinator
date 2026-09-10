# Roadmap

## v0.2.0 (planned)

### State-safe delayed writes

Implementation status: mostly complete in build 9 for the current edit paths. Normal persistence now
uses a per-entity outbox with changed-field patches and tombstones. Explicit
local revisions protect newer edits from stale acknowledgements, incoming
records merge field-by-field against pending local fields, and conflicts are
recorded instead of silently replacing the local value. Build 7 added an
end-to-end delayed create/status race test; build 9 expands that coverage to
location, lifecycle, and item-detail edits.

- Treat eliminating local-state rollback after a save or Remote Sync response as
  a v0.2 release requirement. This is now enforced by local revision matching
  and pending-field merges; keep the requirement for future persistence paths.
- Keep the per-entity outbox and revision handling for all new edit paths.
- Preserve locally edited fields while an item creation or earlier update is
  still being committed; for example, changing a new filament from Ready to Wet
  must survive the initial database refresh.
- Keep revision-aware merging for local persistence and Remote Sync rather than
  treating debouncing alone as conflict resolution.
- Never respond to a successful record write by reloading the whole inventory.
  Acknowledge only the submitted record revision and retain any newer queued
  field changes on that item.
- Merge incoming changes field-by-field against the local outbox. Locally dirty
  fields remain authoritative until their exact revision is acknowledged;
  unrelated incoming fields and records may continue applying asynchronously.
- Keep lightweight pending/saved feedback where useful without blocking edits.
- The local commit is now deferred through a serialized, coalescing write queue;
  sync waits for that queue before reading or uploading. Keep extending the
  race suite as new edit fields are added. A dedicated isolate is optional and
  should only be introduced if profiling shows the queue still affects frames.
- Remaining v0.2 work is verification and coverage: exercise every edit path,
  prove incoming records never erase newer local fields, and finish the
  event-driven sync scheduler so idle screens do not poll or rebuild inventory.

### Detailed personalization, notifications, and sound

Implementation status: substantially complete in build 9. Per-device master
mute, sound style, volume, preview, recurrence, and independent Remote-addition,
drying-complete, and moisture-threshold chime controls are available together
in Personalization. Card, low-stock, moisture, and Remote Sync visual effects
can also be disabled independently per device without changing inventory data.

- Add intensity controls for individual effects where profiling and accessibility
  feedback show they are needed; duration and global recurrence are already
  available.
- Extend the existing per-alert notification controls to any new event types
  (low stock is independently switchable today; sound events are independently
  switchable for moisture, drying, and Remote Sync).
- Add per-alert sound profiles when multiple chime families are available;
  build 9 provides a shared profile, preview, volume, recurrence, and silence
  controls while retaining visual notifications.
- Keep notification, sound, and appearance preferences per device unless the
  user explicitly chooses a shared behavior.

### Spool usage controls

Implementation status: initial gram-based print usage and waste tracking is
available in build 9 through each filament item's details panel. Remaining
spool adjustments, transfers, and printer attribution still need completion.

- Treat grams as the canonical filament amount and record spool consumption
  through manual gram adjustments (with length or percentage as optional
  convenience inputs) without forcing a quantity change.
- Track starting amount, tare, remaining material, and usage history for each
  individual spool split from a stack.
- Support corrections, refills, spool transfers, and usage attribution to a
  printer, build, or project without destroying the audit trail.
- Track filament used by each print in grams, including whether the print was
  successful or failed, and distinguish planned usage from actual usage and
  waste (such as purge material or support discarded after a failed print).
- Keep print outcome, waste reason, and project/build attribution in the usage
  history so successful-use and failed-print totals can be reported without
  rewriting the spool's audit trail.
- Make low-material and moisture behavior work from the remaining spool amount.

### Multi-color filament support (deferred)

Implementation status: shelved for a later roadmap pass. Build 7/9 provide
gradient/coextruded data entry and initial color import, but the complete model
needs more design work before it should be a release target. Keep these
requirements parked rather than expanding this area during v0.2.

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
- Future investigation: HueForge-style light-dispersion/translucency metadata
  (working TLD terminology still to be confirmed) should be designed with the
  multi-color model, not bolted onto the single-color field.

### Filament purpose and property tags

Implementation status: base label support is present in build 9, but proper
filament-tag implementation is still outstanding. Tags can be edited, saved,
searched, and displayed on item cards and details; they are not yet a complete,
reviewable filter and provenance system.

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

In practical terms, users should be able to filter to “Use first” or “Support
only,” see why a tag was applied, and distinguish a manufacturer claim from a
user note. Imports may suggest tags, but engineering or performance claims must
stay reviewable and must never be presented as a certification. “Carbon-fiber
appearance” and verified carbon-fiber composite remain separate values.

### Filterable item metrics

Implementation status: partial. The current Metrics panel provides inventory
counts, low-stock counts, filament material/color/brand buckets, and tap-through
filters. The full historical metrics view is still outstanding; the remaining
items below are release work, not optional polish.

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

Implementation status: verified in build 10. The Z13-KJP front and rear
cameras work, and XREAL integration has been verified. Keep the diagnostics and
recovery requirements below as regression coverage for future camera changes.

- Retain the verified ROG Flow Z13 Kojima Edition (`z13-kjp`) front/rear and
  XREAL workflows as camera regression cases.
- Record camera enumeration, selected device ID, supported formats, negotiated
  resolution/frame rate, initialization state, and native backend errors in a
  user-readable diagnostic view.
- Test front/rear camera switching, reopening the scanner, app suspend/resume,
  permission changes, and recovery after a failed initialization.
- Add a bounded initialization timeout that releases the camera and offers a
  retry or alternate format instead of leaving it apparently busy.
- Retain regression coverage for the existing Windows camera selector and the
  verified `z13-kjp` workflows.

Hardware regression testing means rerunning the camera workflow on the actual
Z13-KJP and at least one known-good Windows camera after each camera/backend
change: enumerate devices, switch front/rear, open and close the scanner,
recover from permission or initialization failure, suspend/resume the app, and
confirm that preview and capture still work. This is separate from a successful
compile or simulated test; it catches device-specific drivers, formats, and
camera-claim regressions.

### Print-ready PDF lists

Implementation status: not started. This must land before external attachment
storage so users have printable, portable shopping and kit lists first.

- Generate a print-ready PDF shopping list with item names, quantities, units,
  optional locations, notes, and checkboxes.
- Generate a print-ready PDF kit list with kit metadata, buildable quantity,
  parts, quantities, and shortage state.
- Keep generation local and non-blocking, with predictable pagination and
  readable desktop/Android output.
- Offer preview, save, share, and print without requiring Remote Sync or a
  storage provider.

### Printed-part model attachments

- Attach STL files to Printed Part inventory records.
- Generate and cache a lightweight preview thumbnail without blocking the UI.
- Provide an interactive rotate and zoom STL preview on desktop and Android.
- Store attachment metadata and checksums separately from the local SQLite state.

### Optional Nextcloud and WebDAV storage

Status: things to try; optional integration exploration.

- Add a generic attachment-storage interface; local files remain the default.
- Offer Nextcloud as a WebDAV preset using a revocable app password.
- Upload and retrieve STL attachments and portable database backups.
- Keep SQLite as local storage and Supabase as Remote Sync; WebDAV does not
  replace inventory synchronization, roles, audit history, or conflict rules.
- Add offline transfer state, checksum verification, retry handling, and clear
  local-only/remote-available indicators before enabling shared attachments.

### Optional Spoolman integration

Status: things to try, following Nextcloud/WebDAV; not implemented.

- Add a per-spool **Manage with Spoolman** toggle and a reference to the user's
  Spoolman spool ID. Validate the ID against the configured instance.
- Put Spoolman connection configuration in the **Remote** view, below the
  **Supabase** pullout.
- Link remote spool data and remaining material to the existing inventory item;
  define which fields Spoolman manages and prevent double-counted consumption.
- Preserve the last known values offline, show connection/refresh state, and
  define unlinking and conflict behavior before allowing bidirectional edits.

### Optional ntfy notifications

Status: selected for the integration to-do list; not implemented.

- Allow users to configure an ntfy server, topic, and authentication, including
  self-hosted instances.
- Offer per-event notifications for low stock, drying completion, moisture
  alerts, and server/sync problems, with links back to relevant records.
- Respect notification preferences and deduplicate repeated alerts. Define the
  delivery component needed for notifications while Inventorinator is closed;
  desktop-only event detection must not promise background server monitoring.

### Optional Paperless-ngx document integration

Status: selected for the integration to-do list; not implemented.

- Configure a Paperless-ngx instance and link its document IDs to inventory
  items, machines, and kits.
- Find and open associated receipts, warranties, manuals, and datasheets from
  the relevant Inventorinator record.
- Evaluate document search, previews, and optional uploads through the API;
  preserve access permissions and distinguish unavailable documents from
  deleted links without deleting local inventory data.

### Optional Immich photo records and image hosting

Status: selected for the integration to-do list; not implemented.

- Link Immich photos and albums to inventory items, kits, machines, and project
  or maintenance logs for assembly references, condition records, and history.
- Explore Immich as an optional image host to move base64 image payloads out
  of Supabase records. Sync stable asset IDs, instance identity, and metadata
  while retaining local thumbnails/caching for offline use.
- Verify authenticated upload, retrieval, thumbnails, and permissions through
  the Immich API; private photos must not require public sharing links.
- Plan a resumable migration: confirm uploaded assets can be retrieved before
  removing existing payloads, retain a recovery path, and avoid duplicate uploads.
- Define missing-asset and deletion behavior without deleting unrelated Immich
  photos, and keep a local image-storage option for users without Immich.

### Optional Stirling PDF integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's local or self-hosted Stirling PDF instance through its API.
- Assemble downloadable, printable project packets from kit lists, shopping
  lists, instructions, and selected supporting PDFs; allow users to choose
  document order and preview the result.
- Keep the planned local PDF generation available independently of Stirling PDF.
- Verify supported endpoints, authentication, and file-size limits against the
  configured instance; preserve source documents if processing fails.
- Use no AI features or cloud processing.
- Reference: https://docs.stirlingpdf.com/API/

### Optional OpenSCAD integration

Status: selected for the integration to-do list; not implemented.

- Run local OpenSCAD templates to generate bins, dividers, and embossed labels
  from inventory names and storage dimensions.
- Let users review template parameters and previews before exporting model
  files; preserve the template and parameters used for reproducible regeneration.

### Optional FreeCAD integration

Status: selected for the integration to-do list; not implemented.

- Explore a local FreeCAD companion macro/add-on linking assembly components
  to Inventorinator records through stable part identifiers.
- Generate a reviewable kit/parts list with quantities and shortages; preserve
  source-document references and flag unmatched parts instead of guessing.

### Optional OctoPrint integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's local or self-hosted OctoPrint instance, associate print
  jobs with kits/projects, and show job progress and outcomes.
- Prompt users to confirm usable completed parts before receiving them into
  inventory; handle failed and cancelled jobs without adding finished stock.
- Coordinate material accounting with Spoolman so consumption is recorded once.
- Keep any future printer actions explicit and subject to connection permissions.

### Local printing through CUPS / IPP

Status: selected for the integration to-do list; not implemented.

- Print kit sheets, shopping lists, and labels through compatible local/network
  printers with saved printer, paper-size, orientation, and label preferences.
- Use CUPS where available on Linux and Unix-like systems; CUPS also exists on
  macOS. Design printing behind a platform-neutral interface, evaluating native
  Windows/Android printing and IPP access to shared printers separately.
- Verify printer capabilities, output sizing, queue/error feedback, and real
  printed results on each supported platform rather than assuming parity.

### Optional self-hosted Grafana dashboards

Status: selected for the integration to-do list; not implemented.

- Expose selected inventory metrics to a user's self-hosted Grafana OSS setup
  for workshop dashboards and wall displays, without cloud or AI dependencies.
- Explore stock levels, consumption, moisture history, and machine usage;
  distinguish current values from historical measurements that must be recorded.
- Define a read-only metrics interface/data source, permissions, and update
  cadence without exposing credentials or giving dashboards inventory write access.

### Optional Garage attachment storage

Status: selected for the integration to-do list; not implemented.

- Offer a user's self-hosted Garage instance as an optional attachment-storage
  provider through its S3-compatible API, without requiring a cloud service.
- Store models, photos, PDFs, and backup exports remotely while retaining stable
  file references and metadata in Inventorinator and local caching for offline use.
- Reuse the attachment-storage interface planned for Nextcloud/WebDAV; local
  files remain available without an external storage provider.
- Verify private authenticated access, supported API operations, checksums,
  retries, and recoverable transfers before removing any existing local payloads.
- Define ownership and deletion rules so removing a record cannot delete files
  still referenced elsewhere; keep credentials out of portable exports.

### Optional Dolibarr integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's self-hosted Dolibarr instance through its REST API.
- Explore linking customer orders to kits/projects, identifying missing supplies,
  tracking build progress, and associating builds with purchasing and invoices.
- Define stable remote IDs, field ownership, units, and conflict handling before
  enabling writes; avoid duplicate orders, invoices, or stock adjustments.
- Keep business-document actions explicit and reviewable, preserve local
  inventory use without Dolibarr, and verify the configured instance's API
  capabilities and permissions before implementation.

### Optional eLabFTW integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's self-hosted eLabFTW instance and link experiments and
  material-test records to inventory items, batches, kits, and prototype revisions.
- Explore filament tests, resin curing trials, paint mixtures, and other maker
  experiments; preserve exact material identity and links to source results.
- Verify API permissions and record mapping before enabling updates; distinguish
  user test results from manufacturer claims or certified properties.

### Optional scanservjs integration

Status: selected for the integration to-do list; not implemented.

- Connect to a local/self-hosted scanservjs server to acquire receipts,
  instructions, and sketches from supported SANE scanners.
- Preview scans before attaching them to inventory records, kits, or logs;
  explore handoff to the planned Paperless-ngx integration.
- Verify scanner selection, multipage capture, output formats, permissions,
  and cancellation/error handling with real hardware. Use no AI processing.

### Optional OpenEPaperLink integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's local OpenEPaperLink installation and map compatible
  e-paper tags to inventory items or storage locations.
- Display item names, quantities, locations, and QR codes using templates sized
  for the selected tag hardware.
- Verify supported hardware and update interfaces; show pending/failed updates
  and last successful refresh so stale label contents are not treated as current.

### Optional Documenso integration

Status: selected for the integration to-do list; not implemented.

- Explore a user's self-hosted Documenso instance for equipment handovers,
  kit acceptance, and customer build approvals.
- Associate signing documents and completion status with the relevant records;
  retain references to completed documents without changing stock implicitly.
- Verify self-hosted edition/API availability, authentication, and document
  access. Keep recipient selection and sending explicit and reviewable, with
  no cloud or AI dependency.

### Optional Grocy integration

Status: selected for the integration to-do list; not implemented.

- Connect to a user's self-hosted Grocy instance for shared household/workshop
  consumables and battery-charge records.
- Define explicit item mappings, units, and which application owns each field
  before enabling updates; prevent duplicate consumption or stock adjustments.
- Keep the inventories independently usable and define offline, unlinking,
  and conflict behavior before offering two-way synchronization.

### Optional DigiKey integration

Status: search/select/add groundwork implemented on alpha.2; live API verification pending.
See `docs/digikey-integration.md`.

- Use the official DigiKey API to look up components by part number and suggest
  product descriptions, specifications, and purchasing information.
- Provide an import preview before adding or updating inventory; preserve the
  supplier part number, source URL, units, and packaging quantities.
- Configure API access and verify current authentication, usage limits, and
  distribution requirements before implementation. Keep credentials out of exports.
- Reference: https://developer.digikey.com/products/product-information-v4/productsearch/productdetails?prod=true

### Optional McMaster-Carr integration

Status: selected for the integration to-do list; not implemented.

- Provide **Import from McMaster**: enter a part number, retrieve available
  product information, review the details, and add the inventory item.
- Evaluate specifications, current pricing, images, datasheets, CAD references,
  and discontinued/replacement information through the official Product
  Information API. Preserve supplier identity, units, and packaging quantities.
- Account for McMaster's customer approval, client certificate, authentication,
  product-subscription limits, and endpoint rate limits.
- Clarify access and distribution arrangements for a publicly available app
  with eprocurement@mcmaster.com before implementation; support each user's
  approved connection without bundling credentials or certificates.
- Reference: https://www.mcmaster.com/help/api/

### Stream Deck controls and expanded Desklets

Status: to do; extend the existing desktop companions.

- Add Stream Deck/StreamController actions for common Inventorinator workflows,
  such as opening inventory, finding an item, and recording stock changes.
- Expand the existing Inventorinator overview and moisture Desklets and consider
  shared server-status information with Service Pulse. Review their current
  capabilities before choosing the additional controls and summaries.
- Respect the active inventory and user permissions, and verify actual button
  actions and loaded Desklet behavior on the desktop.

### Integrated Kanban with a self-hostable task service

Status: to try; evaluate Vikunja first and comparable self-hostable apps if needed.

- Provide a Kanban board inside Inventorinator that syncs with the chosen service.
- Link tasks to kits, inventory items, shopping needs, or workshop projects.
- Evaluate API support for boards, columns, cards, ordering, and task updates;
  define stable remote IDs, offline behavior, conflict handling, and deletion
  semantics before enabling two-way synchronization.

### Top-level server status indicator

Status: to do.

- Show a compact server status indicator at the top of Inventorinator.
- Identify the configured server/service and distinguish connected, checking,
  unreachable, authentication failure, and local-only/unconfigured states.
- Let users inspect connection details and last successful sync; a reachable
  server must not imply that all pending inventory changes have synced.

### Expanded in-app guides

Status: to do; build on the existing onboarding and Help entry points.

- Add contextual, replayable guides for kits, shopping lists, Remote setup,
  integrations, importing/exporting, and printable lists.
- Keep guides concise, skippable, and useful on desktop and Android.

### Spreadsheet import/export and portable JSON

Status: to do; review existing data-transfer features before extending them.

- Support spreadsheet import/export, including CSV and XLSX, and portable JSON
  export for inventory and relevant kit/shopping-list data.
- Provide column mapping, a preview, validation, and explicit duplicate handling
  before applying imports; preserve quantities, units, IDs, and relationships.
- Use a versioned JSON format and verify export/re-import fidelity through the
  supported import path. Keep connection secrets out of portable exports.
- Make the active inventory and export scope clear and keep local export
  available without a connected server.
- Pair these exports with the print-ready PDF kit and shopping lists above,
  including an easily discoverable download/save action for paper printing.

### Kit deletion returns items to inventory

Status: correctness verification required; fix any failures found.

- Ensure deleting a kit returns its held/reserved items to the main inventory
  and makes them visible and available again without deleting their records.
- Preserve total stock: release allocations exactly once, without adding stock
  for reference-only kit entries or recreating material already consumed.
- Verify partial quantities, items shared across kits, repeated deletion,
  persistence after restart, and Remote Sync/offline replay with regression tests.

## v2.0 (planned)

### Multiple sync profiles and separate local inventories

- Keep multiple named Remote Sync profiles on one device.
- Allow a separate local inventory alongside each shared workspace instead of
  forcing local and shared data into one database.
- Make the active profile and local inventory explicit before any import,
  export, sync, or purge operation.
- Preserve per-profile device identity, role, revocation, offline-retention,
  and re-pairing behavior.
