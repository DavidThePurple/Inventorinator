# Roadmap

Updated October 14, 2026 against the current `0.1.1-alpha2` development
branch. Current release: [v0.1.1 checklist](release-checklist.md).

## v0.1.1 — finish before release

- [x] **Import review:** inspect incoming items, resolve issues, and select what to accept before finalizing an import.
- [x] **Undo import:** undo an import batch without removing unrelated inventory or silently overwriting later edits; keep restart and Remote Sync behavior safe.

Details: [import review and undo](import-review-and-undo.md). Shared undo requires server schema 30.

## v0.1.2 — remaining work

### Not started

- [ ] **Project tools:** Kanban and Visual Relationship Architect (design to follow).
- [ ] **Scratch Pad editor:** alignment, bold, italic, font selection, and a formatting toolbar.
- [ ] **Browser add-on:** selectively capture web content and import it on Linux/Windows.
- [ ] **Import feed:** optional live feed of incoming items.
- [ ] **Note privacy:** locked shared notes and sharing to selected devices; inter-device messaging remains an alternative, not a settled design.
- [ ] **Custom interface:** reorder controls and add custom buttons for workflow and accessibility needs.
- [ ] **Notifications:** push notifications and/or ntfy integration.
- [ ] **3D timer carousel:** showcase drying timers and life-remaining timers in a 3D carousel at the top of the interface.
- [ ] **New-item carousel:** a separate carousel showcasing newly added items.
- [ ] **Nextcloud:** view 3D files inside Inventorinator, including a printed-parts queue.

### Partial — finish the listed gaps

- [ ] **App lock:** device PIN is implemented; biometric unlock remains optional follow-up work.

### Complete this cycle

- [x] **Touchscreen controls:** bottom-row touch use on Linux/Windows.
- [x] **Catalog:** contextual visuals, ordering, and drag and drop.
- [x] **Sub-types:** organize items within their main inventory type.
- [x] **Stockroom:** improved workflows and add individual items directly to shopping lists.
- [x] **Checkout system:** person/project loans, quantities, expected returns, partial/full returns, and availability.
- [x] **Machine timers:** active/finished timers visible directly on cards.
- [x] **Status indicator experiment:** a larger animated status indicator.
- [x] **Restart camera:** reopen the selected camera using its saved device address.

## Maybe

- **Build review / QC:** build photos with pen/shape annotations, circles/arrows, and supervisor approval. Optional, with role-based enforcement; design still open.

## Stretch goals

- Optional text-to-speech (TTS), text scaling, and deeper appearance controls: corner radius, borders, accents, and custom themes.

## Carried forward into v0.1.2 — remaining work

### Partial — finish the listed gaps

- [ ] **Background sync:** reduce periodic network polling; preserve drying timers, countdowns, and alerts. Verify newer edits survive delayed saves.
- [ ] **Spools:** corrections, refills, transfers, individual-spool tracking, and printer/build attribution. Refill/reload is implemented; corrections, transfers, and printer/build attribution remain.
- [ ] **Filament:** tag filters and property sources; complete multi-color support. Ordered multi-color styles and basic tags are implemented; provenance and complete filtering/model work remain.
- [ ] **Metrics:** historical values, consumption, moisture, movement, and fuller filters.
- [ ] **Import/export:** JSON import for kits/shopping lists, images, and preserved location links. Portable kit and shopping-list JSON exists; image and location-link coverage remains.
- [ ] **Status and help:** clearer login/local-only/sync status, contextual guides, effect intensity, and per-alert sounds. Connection status, replayable onboarding, effect controls, and alert sounds exist; broader contextual guides remain.
- [ ] **Suppliers:** check only untested suppliers and expand pagination where available. DigiKey works; most suppliers are already working. This is not a v0.1.1 blocker.

### Not started or deferred

- [ ] **Models and printing:** STL attachments/previews, PDF locations/notes, saved printer/label settings, and CUPS/IPP.
- [ ] **Inventories:** multiple sync profiles and separate local inventories.
- [ ] **Other integrations:** WebDAV/Garage, Spoolman, OctoPrint, Immich, Paperless-ngx, scanservjs, Stirling PDF, Grafana, OpenEPaperLink, OpenSCAD, FreeCAD, Dolibarr, eLabFTW, Documenso, Grocy, McMaster-Carr, Stream Deck, and expanded Desklets.

Carried-forward work is a backlog, not a promise that every integration ships in v0.1.2.
Camera switching and DigiKey import are confirmed working by the user.

## Every release with a new migration

Publish version-specific migration instructions to the Wiki with the build, link them from the release notes, and ship the matching complete server bundle. Preserve instructions for older releases.

[Implementation reference](roadmap-details.md) · [Supplier coverage](supplier-integrations.md)
