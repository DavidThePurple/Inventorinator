# Inventorinator 1.1.0 practical release test checklist

This is a hands-on test runbook. Check an item only after performing the steps
on the packaged release candidate and observing the stated result.

## Candidate record

- [ ] Commit: `________________________________________`
- [ ] Version/build number: `________________________________________`
- [ ] Linux artifact: `________________________________________`
- [ ] Android artifact: `________________________________________`
- [ ] Windows artifact: `________________________________________`
- [ ] Remote Sync test server/schema: `________________________________________`
- [ ] Tester/date: `________________________________________`

For failures, record the test ID, platform, screenshot/log, and exact build.

## Test equipment

- [ ] Linux X11 machine
- [ ] Linux Wayland machine or laptop
- [ ] Android phone
- [ ] Android emulator at 360–412 logical pixels wide
- [ ] Windows machine or VM without Flutter installed
- [ ] Disposable Remote Sync workspace and Supabase project
- [ ] Six disposable devices/sessions: Owner 1, Owner 2, Admin, Manager,
  Editor, and Builder
- [ ] A v1.0 database containing real inventory, archived items, custom Types,
  images, machines, Kits, and Builds

## 1. Clean install and persistence

- [ ] **BASE-01 — Clean launch**
  - Install the candidate on a machine with no Inventorinator data and launch it.
  - Pass: onboarding opens, the UI is usable, and no error/overflow banner appears.

- [ ] **BASE-02 — Create a working test inventory**
  - Create vendor `Test Supply`, brand `Test Brand`, location
    `Workshop / Shelf A`, and these items:
    - `Purple PLA Test` — Filament, quantity 0, cost 22.85, purple.
    - `M4 Bolt Test` — Fasteners, quantity 12, cost 0.25.
    - `Brand Search Probe` — Other, quantity 1, brand `Test Brand`.
  - Restart Inventorinator twice.
  - Pass: every value, link, color, quantity, and location remains unchanged.

- [ ] **BASE-03 — Archive persistence**
  - Archive `M4 Bolt Test`, restart, restore it, and restart again.
  - Pass: it appears only in Archived while archived and returns normally when restored.

- [ ] **BASE-04 — Local export/import round trip**
  - Export the local database. Import it into a second clean installation.
  - Pass: inventory, catalog, locations, images, Kits, Builds, and settings match.

- [ ] **BASE-05 — Bad import safety**
  - Attempt to import an unrelated file and a deliberately truncated database/JSON.
  - Pass: Inventorinator explains the failure and the open database is unchanged.

## 2. Inventory basics

- [ ] **INV-01 — Zero quantity for every Type**
  - Create quantity-0 items using Filament, Fasteners, Other, and one custom Type.
  - Pass: all save at 0; none are silently changed to 1.

- [ ] **INV-02 — Quantity buttons and debounce**
  - Rapidly press `+` five times, wait two seconds, then press `−` three times.
  - Pass: the card immediately shows +5 then −3, input does not lag, and restart
    preserves the final quantity.

- [ ] **INV-03 — Hide zero and quantity sorting**
  - Enable Hide zero, then sort By Quantity ascending and descending.
  - Pass: zero items disappear and remaining cards are numerically ordered both ways.

- [ ] **INV-04 — Item edit coverage**
  - Edit name, description, Type, material, color, cost, quantity, brand, vendor,
    image, compatibility, and location on one item.
  - Pass: the sidebar and main card update correctly and survive restart.

- [ ] **INV-05 — Mark depleted availability**
  - Enable `Allow “Mark depleted”` on one custom Type and disable it on another.
  - Open one item of each Type.
  - Pass: Mark depleted is shown only for the enabled Type; using it sets quantity 0.

- [ ] **INV-06 — Status visibility by Type and quantity**
  - Inspect a stocked Filament, a quantity-0 Filament, and a stocked Fastener.
    Enable Show item status for Fasteners in Catalog and inspect again.
  - Pass: stocked Filament shows status; zero quantity never shows status;
    Fasteners default off and show it only after their Type opts in.

- [ ] **INV-07 — Main card anatomy**
  - Inspect standard and photo-card modes at minimum, middle, and maximum card size.
  - Pass: cards remain square; quantity, status, Type, price, image/color, and
    material are readable; no Added age appears on the main card.

- [ ] **INV-08 — Sidebar anatomy**
  - Open an item with a location and an old Added date.
  - Pass: Added-to-inventory age appears above archive/lifecycle actions and the
    Storage Location card opens that exact Stockroom location.

- [ ] **INV-09 — Rapidizer parsing**
  - Enter `Blue PLA Filament 22.85`, review the preview, and save it.
  - Pass: Blue is color, PLA is material, Filament is Type, and 22.85 is cost.

- [ ] **INV-10 — Split one item from a stack**
  - Open the details for a quantity-10 item and press `Split one`.
  - Pass: the original stack becomes 9, a separate quantity-1 item is created
    with the same product details and location, and its details open immediately.
    Split one is disabled on the new quantity-1 item. Use the top Edit button and
    confirm it opens that item's Edit form.

- [ ] **INV-11 — Alert read state**
  - Trigger two low-stock alerts. Open Alerts and click one alert, then return.
  - Pass: the clicked alert is cleared while the other remains. Press `Mark all
    as read`, restart Inventorinator, and confirm the alert badge stays cleared.
    Raise an item above its threshold and lower it again; its alert becomes unread.

## 3. Search, filters, sorting, and selection

- [ ] **FIND-01 — Search fields**
  - Search separately for `Purple`, `Filament`, `PLA`, `Test Brand`,
    `Test Supply`, and a compatibility value.
  - Pass: the expected item appears for every field, even when the term is not
    present in the item name.

- [ ] **FIND-02 — Search responsiveness**
  - Type a 20-character query quickly, hold Backspace, and repeat while scrolling.
  - Pass: keystrokes remain responsive and the grid does not disappear or hitch badly.

- [ ] **FIND-03 — Ctrl+F**
  - On Linux and Windows, focus another control and press Ctrl+F.
  - Pass: the inventory search receives focus and its text is selected.

- [ ] **FIND-04 — Type and Color filters**
  - Select a Type, then a Color, then clear each filter in reverse order.
  - Pass: filters combine correctly and clearing one does not reset the other.

- [ ] **FIND-05 — Sort options**
  - Exercise every sort option, including By Quantity, in both directions.
  - Pass: order is correct and the selection remains readable in dark and light mode.

- [ ] **FIND-06 — Bulk selection**
  - Shift-click two inventory cards, then repeat with Printers, Machines, Kits,
    Builds, and Tools.
  - Pass: both records select without the first click opening the detail view.

## 4. Catalog and Types

- [ ] **CAT-01 — Catalog order and collapsed state**
  - Open Product Catalog on a fresh launch.
  - Pass: order is Types, Items, Materials, Machines, Kits, Spool Sizes,
    Vendors, Brands, Product Templates; Vendors starts collapsed.

- [ ] **CAT-02 — Add-form placement**
  - Open every Catalog section containing a list.
  - Pass: its Add control is above the list and remains reachable without
    scrolling to the bottom.

- [ ] **CAT-03 — Type lifecycle and relinking**
  - Create `Test Consumable`, assign an item to it, delete the Type, recreate it,
    and use the reconnect/reassign path.
  - Pass: the item never disappears and returns to the recreated Type/filter.

- [ ] **CAT-04 — Type visuals**
  - Give a custom Type a built-in icon, then an uploaded image/animation.
  - Scroll quickly and switch its animation setting between Always and On interaction.
  - Pass: the visual does not vanish and the setting behaves as labeled.

- [ ] **CAT-05 — Vendor and Brand clarity**
  - Create separate vendor and brand records, then create a vendor that is also a brand.
  - Add/replace logos and connect both to a product template.
  - Pass: seller/maker identities remain distinct and survive restart.

## 5. General JSON import

- [ ] **JSON-01 — Valid preview**
  - Import the documented general-item JSON sample containing Type, material,
    brand, vendor, color, quantity, cost, source, and one product image URL.
  - Pass: preview shows every mapped field before anything is written.

- [ ] **JSON-02 — Cancel is safe**
  - Cancel the preview and search for the sample item.
  - Pass: no sample records, brands, vendors, or Types were created.

- [ ] **JSON-03 — Confirmed import**
  - Repeat and confirm the import.
  - Pass: fields and brand/vendor relationships are correct; the listed image
    imports and an item without an image remains image-less.

- [ ] **JSON-04 — Invalid and duplicate rows**
  - Import one invalid row mixed with valid rows, then reimport the valid file.
  - Pass: validation identifies the bad row before writing, and duplicate
    handling matches the preview instead of silently multiplying records.

- [ ] **JSON-05 — Offline image failure**
  - Disable networking and import a valid item with an image URL.
  - Pass: item data imports, the image failure is explained, and the import does not hang.

## 6. Kits, BOMs, Builds, and machines

- [ ] **KIT-01 — Manual Kit**
  - Create `Two Bolt Test Kit`, add a Main component BOM line requiring two
    `M4 Bolt Test` items, then open its card.
  - Pass: the Kit detail opens—not Catalog—and reports the correct required/available count.

- [ ] **KIT-02 — Missing-line matching**
  - Add a BOM line named `M4 x 10 bolt` with no inventory match. From the Kit
    detail view, match it to `M4 Bolt Test`.
  - Pass: the match persists after closing/reopening and availability updates immediately.

- [ ] **KIT-03 — Build quantity use/unuse**
  - Create a Build from `Two Bolt Test Kit`, consume its components, then undo use.
  - Pass: exactly two bolts are subtracted and restored; insufficient stock is refused.

- [ ] **KIT-04 — Kit deletion warning**
  - Attempt to delete a Kit with an unfinished Build, cancel once, then confirm.
  - Pass: the warning gives the correct Build count, Cancel changes nothing,
    and confirmation performs only the described deletion.

- [ ] **KIT-05 — Package import preview**
  - Import the documented `.inventorinator-kit.json` sample.
  - Pass: preview lists sections, sources, machines, BOM quantities, proposed
    matches, and new inventory records before import.

- [ ] **KIT-06 — Package import ownership truth**
  - Confirm the package import and inspect several newly created BOM parts.
  - Pass: each exists in inventory at quantity 0 and is not marked owned.

- [ ] **KIT-07 — Stable reimport**
  - Import the same package again.
  - Pass: preview explains reuse/update behavior and does not duplicate the whole BOM.

- [ ] **KIT-08 — Detail navigation**
  - Open a Kit, Build, Machine, Printer, and Tool from the main grid.
  - Pass: every card opens its own detail view, never Product Catalog.

## 7. Stockroom and shopping

- [ ] **STOCK-01 — Location hierarchy**
  - Create `Workshop`, child `Shelf A`, and grandchild `Bin 1`; move an item to Bin 1.
  - Pass: all paths display as `Workshop / Shelf A / Bin 1`.

- [ ] **STOCK-02 — Location cards on Android**
  - Open Stockroom at 360–412 px portrait width.
  - Pass: names/counts do not wrap character-by-character; Move, Rename, and
    Delete sit on their own row beneath the text.

- [ ] **STOCK-03 — Location details on Android**
  - Open a populated location on Android.
  - Pass: QR is centered above the count, description, and buttons; item rows
    use the full width and no overflow stripes appear.

- [ ] **STOCK-04 — Location QR round trip**
  - Download the QR PNG, open/print it elsewhere, then scan it with Inventorinator.
  - Pass: it opens the exact location and shows direct plus child inventory totals.

- [ ] **STOCK-05 — Rename propagation**
  - Rename `Shelf A` to `Shelf B`.
  - Pass: child paths, item location cards, and downloaded QR label text update.

- [ ] **STOCK-06 — Safe location deletion**
  - Delete Shelf B while it contains Bin 1 and a directly stored item.
  - Pass: direct items move to Workshop, Bin 1 moves up to Workshop, and no
    inventory item is deleted.

- [ ] **STOCK-07 — Move search by brand**
  - In Move items here, search `Test Brand`.
  - Pass: `Brand Search Probe` appears even though its name lacks the brand text.

- [ ] **STOCK-08 — Shopping receive/remove**
  - Add a two-unit BOM shortage to Shopping, receive one, then remove the entry.
  - Pass: remaining count becomes one, inventory gains one, and the red remove
    action is visually distinct from the red dialog Close button.

## 8. Themes, layout, and interaction

- [ ] **UI-01 — Theme matrix**
  - Test violet, red, blue, green, grey/black, orange/brown, and one custom hue
    in both dark and light mode.
  - Pass: hue and light/dark are independent, persist after restart, and the
    background never shifts green unexpectedly.

- [ ] **UI-02 — Contrast sweep**
  - In light mode inspect cost, quantity, sort/type/color dropdowns, disabled
    controls, menus, dialogs, slider thumbs, and window buttons.
  - Pass: text/icons remain readable and no control has white text on white.

- [ ] **UI-03 — Responsive sweep**
  - Resize desktop slowly from minimum width to ultrawide. Rotate Android
    portrait → landscape → portrait.
  - Pass: controls reflow without clipping, overlap, upside-down dialogs, or
    inaccessible actions.

- [ ] **UI-04 — Bottom action bar**
  - Shrink through full labels, wide icon buttons, and compact icon buttons.
  - Pass: buttons collapse before clipping, left/right groups stay against
    their respective sides, icons remain centered, and outer padding is even.

- [ ] **UI-05 — Sliders**
  - Drag Page size and Card size continuously from end to end, then release.
  - Pass: thumbs/teardrops update under the pointer, cards change smoothly,
    and persistence work occurs after release/debounce rather than every frame.

- [ ] **UI-06 — Hover treatment**
  - Hover cards and every major button on desktop.
  - Pass: buttons use the magenta-then-purple glass effect; cards use the dimmer
    highlight and do not flash as brightly as buttons.

## 9. Performance

- [ ] **PERF-01 — Long grid scroll**
  - Load 400+ mixed items with images and animated Type icons. Scroll rapidly
    for 30 seconds using mouse wheel, touchpad, and Android touch.
  - Pass: grid content never disappears, status badges do not restart on every
    frame, and input recovers immediately when scrolling stops.

- [ ] **PERF-02 — Search under load**
  - With the same inventory, type and erase searches repeatedly.
  - Pass: characters appear without noticeable delay and CPU settles when idle.

- [ ] **PERF-03 — Quantity burst**
  - Click `+`/`−` rapidly on several cards while scrolling.
  - Pass: visual counts keep up, persistence is batched, and scrolling remains usable.

- [ ] **PERF-04 — Desktop corner resize**
  - Drag a window corner quickly in circles for 20 seconds, then resize only X
    and only Y.
  - Pass: preview tracks the pointer, no long input lag occurs, and top/right
    edges do not leave black or missing blocks.

- [ ] **PERF-05 — Idle CPU**
  - Leave Inventorinator untouched for two minutes on each platform while
    watching its process in a task manager.
  - Pass: CPU returns near idle; no Python/Rider/helper process is spawned or
    consumes a core.

## 10. Remote Sync and roles

Use only the disposable test workspace for this section.

- [ ] **SYNC-01 — Fresh server setup**
  - Run `supabase/install-or-update.sh` on a fresh disposable Supabase project,
    connect Owner 1, create one item, and sync.
  - Pass: schema reports 11 and a second clean Owner device receives the item.

- [ ] **SYNC-02 — Upgrade server setup**
  - Restore a schema-8/v1.0 test backup, record table counts, run the updater,
    and compare counts.
  - Pass: schema reaches 11 without losing inventory, role, device, or audit rows.

- [ ] **SYNC-03 — Multiple owner devices**
  - Pair Owner 2, restart both owner devices, edit on each, and Sync now.
  - Pass: both retain Owner controls, see all devices, and receive both edits.

- [ ] **SYNC-04 — Admin permissions**
  - As Admin, open Roles & devices. Change another Admin to Editor, then back.
    Attempt to change an Owner or the current Admin's own role.
  - Pass: non-owner/non-self changes work; Owner/self changes are blocked in UI
    and by a direct server request.

- [ ] **SYNC-05 — Manager permissions**
  - As Manager, change Editor ↔ Builder. Attempt to change Admin or Owner.
  - Pass: only Editor/Builder changes work; higher roles are blocked in UI and server.

- [ ] **SYNC-06 — Editor and Builder visibility**
  - Sign in as Editor and Builder and open Remote Sync.
  - Pass: neither sees Roles & devices or pairing management, and direct calls fail.

- [ ] **SYNC-07 — Pairing token lifecycle**
  - Use a pairing token once, attempt to reuse it, then try an expired token.
  - Pass: first use succeeds; reuse/expiry gives a useful pairing message without
    exposing raw `Invalid Refresh Token: already used` jargon.

- [ ] **SYNC-08 — Revocation**
  - Owner revokes Editor while Editor is open, then Editor tries to sync and
    access role/device operations.
  - Pass: access is denied cleanly, local inventory remains intact, and no raw
    token detail is shown to the revoked low-role device.

- [ ] **SYNC-09 — Owner recovery**
  - In Supabase Authentication, delete Owner 1's auth user. Open Owner 2, sync,
    and inspect Roles & devices.
  - Pass: Owner 2 retains/reclaims owner control, inventory and history remain,
    and the obsolete Owner 1 session cannot manage the workspace.

- [ ] **SYNC-10 — Concurrent owner recovery**
  - Repeat SYNC-09 with two eligible owner devices initiating recovery as
    closely together as possible.
  - Pass: one recovery wins cleanly; the workspace has a valid owner and remains usable.

- [ ] **SYNC-11 — Non-conflicting offline merge**
  - Disconnect two devices. Add Item A on one and Item B on the other. Reconnect
    and sync both.
  - Pass: both devices end with A and B.

- [ ] **SYNC-12 — Conflicting edit**
  - Disconnect two devices, change the same item's name differently, reconnect,
    and sync.
  - Pass: conflict is shown and not silently overwritten.

- [ ] **SYNC-13 — Full-data propagation**
  - Sync a custom Type/icon/depletion setting, image item, Kit/BOM, location,
    shopping entry, brand/vendor, and role change.
  - Pass: a clean permitted device receives every supported record and relation.

- [ ] **SYNC-14 — Disconnect/reconnect wording**
  - Disconnect Remote Sync, continue local edits, reconnect, and sync.
  - Pass: local data survives, edits propagate, and all visible wording says
    Remote Sync/Remote—not Cloud Sync or Cloud session.

## 11. Linux checks

- [ ] **LINUX-01 — X11 packaged build**
  - Launch the packaged Linux build on X11 from the file manager and terminal.
  - Pass: one native Inventorinator process runs; it is not Wine.

- [ ] **LINUX-02 — Wayland packaged build**
  - Repeat LINUX-01 on Wayland.
  - Pass: launch, dialogs, scrolling, resize, clipboard, files, and window
    controls work without an X11-only dependency failure.

- [ ] **LINUX-03 — App identity**
  - Inspect Mission Center and another task manager while Inventorinator runs.
  - Pass: capitalized `Inventorinator` and its proper icon appear consistently.

- [ ] **LINUX-04 — Window controls and resize**
  - Minimize, maximize, restore, close, edge-resize, and corner-resize in dark
    and light mode.
  - Pass: controls are aligned/themed and the custom resize preview remains visible.

## 12. Android checks

- [ ] **ANDROID-01 — Clean install**
  - Install on a clean emulator/phone, launch, create an item, force-stop, and relaunch.
  - Pass: onboarding works and the item persists.

- [ ] **ANDROID-02 — In-place upgrade**
  - Install v1.0, create/record data, then run `adb install -r <1.1-apk>`.
  - Pass: install succeeds without uninstalling and every recorded value remains.

- [ ] **ANDROID-03 — Camera and files**
  - Test camera permission, barcode, OCR label capture, QR scan, image picker,
    JSON import, and database import/export.
  - Pass: each returns to Inventorinator with the expected result and no crash.

- [ ] **ANDROID-04 — Core responsive controls**
  - At phone portrait and landscape widths, open Types, Colors, sort, views,
    sliders, Personalization, Local Database, Remote Sync, Stockroom, and Catalog.
  - Pass: no overflow stripes, clipped controls, character-by-character wrapping,
    upside-down view, or blocked action.

- [ ] **ANDROID-05 — Real phone sync roles**
  - On the physical phone as Admin, repeat SYNC-04 and compare with desktop.
  - Pass: device list and role controls match the server-granted Admin permissions.

## 13. Windows checks

- [ ] **WIN-01 — Clean packaged launch**
  - Unzip/install on Windows without Flutter/dev tooling and launch normally.
  - Pass: no missing-runtime error; local database is created and persists.

- [ ] **WIN-02 — App identity**
  - Inspect Task Manager, taskbar, Start menu/shortcut, and window title.
  - Pass: all show Inventorinator with the proper icon.

- [ ] **WIN-03 — Desktop integration**
  - Test minimize/maximize/close, resize, scrolling, Ctrl+F, clipboard, file
    dialogs, import/export, and Remote Sync.
  - Pass: behavior matches Linux except documented platform limitations.

- [ ] **WIN-04 — Upgrade/uninstall**
  - Upgrade a populated v1.0 install, verify data, then uninstall.
  - Pass: upgrade preserves data and uninstall behavior matches the documentation.

## 14. Automated checks and final artifacts

Run these from the exact commit used for the artifacts:

- [ ] `./tool/check_release_consistency.sh`
- [ ] `flutter analyze`
- [ ] `flutter test --coverage`
- [ ] `./tool/check_coverage.sh 60`
- [ ] Disposable Supabase bootstrap and SQL regression suite
- [ ] No unexpected test skips, analyzer warnings, overflow warnings, or exceptions

Then verify the actual downloadable files:

- [ ] **REL-01 — Version agreement**
  - Compare `pubspec.yaml`, in-app version, filenames, changelog, installer
    default tag, Git tag, and required connector schema.
  - Pass: all identify `1.1.0+2` and schema 11 as intended.

- [ ] **REL-02 — Artifact contents**
  - Inspect Linux and Windows archives.
  - Pass: executable, runtime files, icon/desktop metadata, README, LICENSE, and
    CHANGELOG are present.

- [ ] **REL-03 — Signing**
  - Verify Android signature and Windows signing status using the platform tools.
  - Pass: Android uses the release key; Windows status matches the published warning/docs.

- [ ] **REL-04 — Size accounting**
  - Record compressed/uncompressed sizes and compare with v1.0.
  - Pass: every material increase is explained by a named dependency or asset.

- [ ] **REL-05 — Secrets scan**
  - Search tracked files and unpacked artifacts for tokens, credentials,
    recovery packages, signing files, exported databases, and captured labels.
  - Pass: none are present.

- [ ] **REL-06 — Download test**
  - Upload as a GitHub pre-release, download each artifact as a user would,
    verify its SHA-256, install it, and repeat the platform smoke test.
  - Pass: downloaded files match checksums, install, launch, and retain data.

## Result

- Passed: `______`
- Failed: `______`
- Not run: `______`
- Accepted known limitations and follow-up version:
  `________________________________________________________________________`
- Go / No-go: `________________`
- Signed/date: `____________________________________________________________`
