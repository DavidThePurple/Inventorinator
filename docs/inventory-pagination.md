# Inventory pagination

The app opens workshop settings and catalog metadata without loading inventory payloads. `DiskInventoryList` retains inventory IDs and pending edits, not a complete collection of item objects. Operations outside the page can read individual image-free records as needed.

SQLite filters and orders the selected inventory scope, calculates the matching count independently, and fetches only the requested `LIMIT` / `OFFSET` page including its thumbnails. Mixed “Everything” pages account for preceding catalog records when calculating the inventory offset. The page cache, UI notifiers, persistence references, and decoded image cache release previous-page objects after the old widgets unmount.

A local `inventory_metadata` table excludes binary fields and is maintained transactionally by triggers on `entity_state`. Counts, metrics, and kit availability queries use this projection. Date and quantity indexes support common paging orders. Search normalization and specialized sorts preserve existing matching/comparison behavior through SQLite callbacks using image-free metadata. The database and sync payload formats remain compatible; no server upgrade is needed.

Ordinary paging does not create full inventory snapshots. Explicit exports and full replacement/import operations can still materialize their transfer data. Full-size photos remain lazy in `inventory_images`.

Validation covers bounded pages with 1,000 stored records, filters outside the initial page, cache retention across page changes, independent counts, restart persistence, queued edits, and sync races. The developer diagnostic `retainedInventoryItemCount` measures item IDs retained by the home screen's item caches.
