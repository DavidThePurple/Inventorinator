# Roadmap

Updated September 20, 2026. Current release: [v0.1.1 checklist](release-checklist.md).

## v0.1.1 — finish before release

- [x] **Import review:** inspect incoming items, resolve issues, and select what to accept before finalizing an import.
- [x] **Undo import:** undo an import batch without removing unrelated inventory or silently overwriting later edits; keep restart and Remote Sync behavior safe.

Details: [import review and undo](import-review-and-undo.md). Shared undo requires server schema 30.

## v0.1.2 — planned

- [ ] **Touchscreen controls:** make the bottom row easier to use on Linux/Windows.
- [ ] **Project tools:** Kanban and Visual Relationship Architect (design to follow).
- [ ] **Scratch Pad editor:** alignment, bold, italic, font selection, and a formatting toolbar.
- [ ] **Catalog:** better contextual visuals, smarter ordering, and drag and drop.
- [ ] **Sub-Types:** organize items into sub-types within their main inventory type.
- [ ] **Stockroom:** improve workflows and add individual items directly to shopping lists.
- [ ] **Checkout system:** check items out to a person or project, track quantities and expected returns, and record full or partial returns without changing total owned stock. Show who has each item and what remains available.
- [ ] **Browser add-on:** selectively capture web content and import it on Linux/Windows.
- [ ] **Import feed:** optional live feed of incoming items.
- [ ] **App lock:** optional device biometrics or device PIN protection.
- [ ] **Note privacy:** explore locked shared notes and sharing to selected devices; inter-device messaging is an alternative, not a settled design.
- [ ] **Custom interface:** reorder controls and add custom buttons for workflow and accessibility needs.
- [ ] **Notifications:** push notifications and/or ntfy integration.
- [ ] **Machine timers:** set timers and completion notifications for dryers, printers, and other machines.
- [ ] **Status indicator experiment:** try a larger, more animated indicator that makes status easier to notice.
- [ ] **3D timer carousel:** showcase drying timers and life-remaining timers in a 3D carousel at the top of the interface.
- [ ] **New-item carousel:** a separate carousel showcasing newly added items.
- [ ] **Nextcloud:** view 3D files inside Inventorinator, including a printed-parts queue.
- [ ] **Restart camera:** release and reopen the selected camera using its saved device address when it stalls or fails at startup.

## Maybe

- **Build review / QC:** build photos with pen/shape annotations, circles/arrows, and supervisor approval. Optional, with role-based enforcement; design still open.

## Stretch goals

- Optional text-to-speech (TTS), text scaling, and deeper appearance controls: corner radius, borders, accents, and custom themes.

## Carried forward into v0.1.2

- [ ] **Background sync:** reduce periodic network polling; preserve drying timers, countdowns, and alerts. Verify newer edits survive delayed saves.
- [ ] **Spools:** corrections, refills, transfers, individual-spool tracking, and printer/build attribution.
- [ ] **Filament:** tag filters and property sources; complete multi-color support.
- [ ] **Metrics:** historical values, consumption, moisture, movement, and fuller filters.
- [ ] **Import/export:** JSON import for kits/shopping lists, images, and preserved location links.
- [ ] **Models and printing:** STL attachments/previews, PDF locations/notes, saved printer/label settings, and CUPS/IPP.
- [ ] **Status and help:** clearer login/local-only/sync status, contextual guides, effect intensity, and per-alert sounds.
- [ ] **Suppliers:** check only untested suppliers and expand pagination where available. DigiKey works; most suppliers are already working. This is not a v0.1.1 blocker.
- [ ] **Inventories:** multiple sync profiles and separate local inventories.
- [ ] **Other integrations:** WebDAV/Garage, Spoolman, OctoPrint, Immich, Paperless-ngx, scanservjs, Stirling PDF, Grafana, OpenEPaperLink, OpenSCAD, FreeCAD, Dolibarr, eLabFTW, Documenso, Grocy, McMaster-Carr, Stream Deck, and expanded Desklets.

Carried-forward work is a backlog, not a promise that every integration ships in v0.1.2.
Camera switching and DigiKey import are confirmed working by the user.

## Every release with a new migration

Publish version-specific migration instructions to the Wiki with the build, link them from the release notes, and ship the matching complete server bundle. Preserve instructions for older releases.

[Implementation reference](roadmap-details.md) · [Supplier coverage](supplier-integrations.md)
