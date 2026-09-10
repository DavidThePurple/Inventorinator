# Custom role groundwork

## Available now

The workspace owner can open **Remote Settings → Role builder** and create,
edit, duplicate or delete named role templates. Four presets give quick
starting points; every operation has a stable permission ID, a group, a
label and a description in `lib/workspace_role_template.dart`.

View inventory is required. Destructive permissions are explicitly marked
and disabled in every preset. Owner/admin/manager/editor/builder names are
reserved; template names are unique within a workspace, ignoring case.

Schema 22 stores templates separately from inventory entities and device
memberships. Authenticated clients have no direct table access. Each RPC
checks the requesting workspace owner on the server; write operations lock
the owner membership while authorizing. A template from one workspace cannot
be edited or deleted through another workspace. Templates belong to the
workspace, not a particular owner device, and survive ownership recovery.

## Offline local drafts

**Remote Settings → Role builder (local)** opens without a server request for a
local workspace or a device whose cached role is Owner. Drafts are stored in
local SQLite preferences, scoped to the server/workspace, and survive restart.
They do not upload automatically or participate in authorization. Shared
role templates still require a reachable schema-22 server and fresh owner
authorization. Local design access does not prove current server ownership.

## Assignment and enforcement (server v25)

Owners assign saved roles through **Remote Settings → Roles & device access**.
Custom permissions are loaded from the server at startup and during sync; offline
clients retain their last known permissions, and revoked writes are rejected on
reconnection. Assignment, ownership recovery, and device removal remain owner-only
for custom-role users. Device management grants listing and pairing, not assignment.

Assigned definitions cannot be edited or deleted. Duplicate a role, change the copy,
then explicitly reassign devices. To retire a role, move every assigned device to
another custom or built-in role before deleting it. Assignments are workspace-scoped,
locked during authorization, and recorded in the server audit log. Ownership recovery
clears a recovered device's custom assignment rather than blocking promotion.

Memberships retain Builder as their legacy fallback. The permission-aware entity RPC
checks each custom operation; old clients cannot gain wider access from an unfamiliar
role. Shared-build stock and progress upload together and retain quantity-integrity
checks. Inventory archive and deletion are independent permissions; catalog management
covers catalogs, locations, shopping and workshop metadata. History is append-only
for custom roles. Database deletion refers to the local device database, not workspace
ownership or deleting the hosted Supabase database.

Server v21–v24 still supports normal inventory sync and role drafts. Assignment needs
v25. Local role drafts are not automatically uploaded or assigned. Read access currently
covers the workspace inventory; no row-level confidentiality filter is promised.
