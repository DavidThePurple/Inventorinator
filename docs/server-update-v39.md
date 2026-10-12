# Server update v39

Run the supplied `./apply-migrations.sh` from the complete Inventorinator server
bundle. It upgrades the Remote schema to v39.

v39 makes the Remote—not a device snapshot—the authority for deletes. Generic
sync uploads can create or update records only. A deliberate in-app deletion
uses a dedicated Remote operation, which locks the record and verifies the
server revision the user saw before it writes the replicated tombstone.

This prevents a disconnected, partial, old, or malformed client from deleting
inventory, locations, kits, machines, builds, or any other shared entity merely
because it lacks that record locally.
