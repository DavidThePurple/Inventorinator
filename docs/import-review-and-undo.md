# Import review and undo

**Bulk Import → Import CSV, XLSX or JSON** opens a review before saving.
Select the rows to keep, use the pencil to inspect/correct a row, then import.
Duplicates are skipped by default, including duplicates within the file.
Unknown item types can be corrected or deselected. Invalid file structure or
invalid numeric values in the source still need correction before review.

**Bulk Import → Import history / undo** lists file imports made on this device.
Undo removes unchanged imported items and keeps anything edited or referenced
by other records. It requires delete permission and can be used after restart.
Catalog entries and the audit trail remain. Supplier forms, Rapidizer, kit
packages, and database restores are not part of this file-import history.

For shared inventory, undo is queued for Remote Sync. Server **schema 30** checks
again before deleting, so a newer remote edit or reference blocks the deletion.
Open **Reports and change log → Sync conflicts** and choose the remote value to
keep a protected item. Ordinary deletes retain their existing behavior.
Older servers keep undo requests queued until upgraded; other changes can sync.
History is local to the importing device and inventory scope.
