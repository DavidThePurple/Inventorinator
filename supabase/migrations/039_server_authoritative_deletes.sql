begin;

-- Ordinary delta uploads are creates and updates only. A client is never
-- allowed to manufacture a tombstone in that transport: every deletion must
-- enter through delete_inventorinator_entity(), which checks the record the
-- user saw while holding the workspace writer lock.
do $migration$
declare
  definition text;
  updated text;
begin
  select pg_get_functiondef(
    'public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The incremental entity-sync RPC is missing';
  end if;

  updated := replace(
    definition,
    $needle$-- A snapshot omission is never a deletion. Only an in-app delete
    -- action can stamp this intent; import undo remains separately guarded.
    if change_deleted and coalesce(change->'baseFields'->>'(importUndo)', 'false') <> 'true' then
      if coalesce(change->'baseFields'->>'(explicitDelete)', 'false') <> 'true' then
        raise exception 'Sync conflict: deletes must originate from an explicit Inventorinator action';
      end if;
    end if;

    -- Inventory deletes also require an explicit UI confirmation.$needle$,
    $replacement$-- Only the dedicated server-side delete operation may submit a
    -- tombstone. Snapshot differences and arbitrary client payloads are never
    -- evidence of a user deleting a record.
    if change_deleted and current_setting('inventorinator.server_delete', true) is distinct from 'on' then
      raise exception 'Sync conflict: use the server-authoritative delete operation';
    end if;

    -- Inventory deletes also require an explicit UI confirmation.$replacement$
  );
  if updated = definition then
    raise exception 'Could not restrict generic entity deletes';
  end if;
  execute updated;
end;
$migration$;

create or replace function public.delete_inventorinator_entity(
  target_workspace uuid,
  source_device text,
  entity_type text,
  entity_id text,
  expected_revision bigint default null,
  expected_payload jsonb default null,
  import_undo boolean default false,
  audit_events jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  current_revision bigint;
  current_payload jsonb;
  current_deleted boolean;
  delete_change jsonb;
  resulting_revision bigint;
begin
  -- Serialize this comparison with all writers in the workspace. The generic
  -- mutation below reuses the established role, build, import-undo, audit and
  -- compatibility-mirror rules rather than reimplementing them here.
  perform 1 from public.inventorinator_workspaces
    where id = target_workspace for update;
  if not found or public.get_inventorinator_role(target_workspace) is null then
    raise exception 'Workspace access denied';
  end if;
  if entity_type is null or entity_id is null or entity_type not in (
    'inventory', 'customItemTypes', 'machineTypes', 'machines', 'kits',
    'builds', 'locations', 'shoppingList', 'auditLog', 'vendors', 'brands',
    'spoolTypes', 'materials', 'products', 'additionHistory', 'spoolUsage',
    'checkouts', 'workshopMetadata'
  ) then
    raise exception 'Unsupported Inventorinator entity type';
  end if;

  select revision, payload, deleted
    into current_revision, current_payload, current_deleted
    from public.inventorinator_entities entity
    where entity.workspace_id = target_workspace
      and entity.entity_type = delete_inventorinator_entity.entity_type
      and entity.entity_id = delete_inventorinator_entity.entity_id
    for update;

  -- An already-confirmed delete, or an unsynced local create that never made
  -- it to the Remote, is safe to acknowledge without creating a new event.
  if not found then return 0; end if;
  if current_deleted then return current_revision; end if;

  if expected_revision is not null then
    if current_revision <> expected_revision then
      raise exception 'Sync conflict: remote record changed before delete';
    end if;
  elsif expected_payload is not null then
    -- Pre-v39 local databases have no stored Remote revision. They may delete
    -- only while the exact remote payload they saw still exists; their next
    -- pull upgrades future deletes to revision checks.
    if jsonb_strip_nulls(current_payload) is distinct from
       jsonb_strip_nulls(expected_payload) then
      raise exception 'Sync conflict: remote record changed before delete';
    end if;
  else
    raise exception 'Sync conflict: sync this record before deleting it';
  end if;

  delete_change := jsonb_build_object(
    'entityType', entity_type,
    'entityId', entity_id,
    'fields', '{}'::jsonb,
    'deleted', true,
    'baseFields', jsonb_build_object(
      '(deleted)', current_payload,
      '(importUndo)', coalesce(import_undo, false),
      -- Required by the older inventory-specific guard, but stamped only
      -- inside this server operation rather than accepted from a client.
      '(confirmedDelete)', true
    )
  );
  perform set_config('inventorinator.server_delete', 'on', true);
  resulting_revision := public.apply_inventorinator_entity_changes(
    target_workspace,
    source_device,
    jsonb_build_array(delete_change),
    coalesce(audit_events, '[]'::jsonb)
  );
  -- Do not leave the internal capability set for another function invoked in
  -- the same SQL transaction.
  perform set_config('inventorinator.server_delete', 'off', true);
  return resulting_revision;
end;
$$;

revoke all on function public.delete_inventorinator_entity(uuid,text,text,text,bigint,jsonb,boolean,jsonb) from public;
grant execute on function public.delete_inventorinator_entity(uuid,text,text,text,bigint,jsonb,boolean,jsonb) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 39)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

notify pgrst, 'reload schema';
commit;
