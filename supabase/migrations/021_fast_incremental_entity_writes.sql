begin;

-- Current clients read inventorinator_entities. Rebuilding the complete
-- workshop_states compatibility document inside every incremental write made
-- a one-record edit scale with the entire inventory (and its image payloads).
-- Remove that synchronous mirror write. The entity table is authoritative for
-- schema 12+ clients; workshop_states remains the last compatibility snapshot
-- for older read-only clients. Builders still get a current validation view,
-- assembled only for builder operations where quantity integrity is enforced.
create or replace function public.build_inventorinator_entity_snapshot(
  target_workspace uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  snapshot jsonb := '{"schemaVersion":8}'::jsonb;
  collection text;
  rows jsonb;
  metadata jsonb;
begin
  select coalesce(payload, '{}'::jsonb) into metadata
  from public.inventorinator_entities
  where workspace_id = target_workspace
    and entity_type = 'workshopMetadata'
    and entity_id = 'singleton'
    and not deleted;
  snapshot := snapshot || coalesce(metadata, '{}'::jsonb);
  foreach collection in array array[
    'inventory', 'customItemTypes', 'machineTypes', 'machines', 'kits',
    'builds', 'locations', 'shoppingList', 'auditLog', 'vendors', 'brands',
    'spoolTypes', 'materials', 'products', 'additionHistory', 'spoolUsage'
  ] loop
    select coalesce(jsonb_agg(payload order by entity_id), '[]'::jsonb)
      into rows
    from public.inventorinator_entities
    where workspace_id = target_workspace
      and entity_type = collection
      and not deleted;
    snapshot := jsonb_set(snapshot, array[collection], rows, true);
  end loop;
  return snapshot;
end;
$$;

revoke all on function public.build_inventorinator_entity_snapshot(uuid) from public;
do $migration$
declare
  definition text;
  updated text;
  with_builder_snapshot text;
begin
  select pg_get_functiondef(
    'public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The incremental entity-sync RPC is missing';
  end if;
  -- Stop touching workshop_states for incremental writes. Normal roles only
  -- write the changed entity row; builders get a validation snapshot before
  -- and after their small, privileged operation.
  updated := regexp_replace(
    definition,
    $pattern$(?is)select\s+coalesce\(state_json,\s*'\{\}'::jsonb\)\s+into\s+snapshot\s+from\s+public\.workshop_states\s+where\s+workspace_id\s*=\s*target_workspace\s+for\s+update;\s*snapshot\s*:=\s*coalesce\(snapshot,\s*'\{"schemaVersion":8\}'::jsonb\);\s*initial_snapshot\s*:=\s*snapshot;$pattern$,
    E'if caller_role = ''builder'' then\n' ||
      E'    snapshot := public.build_inventorinator_entity_snapshot(target_workspace);\n' ||
      E'    initial_snapshot := snapshot;\n' ||
      E'  end if;',
    1
  );
  updated := regexp_replace(
    updated,
    $pattern$(?is)\n\s*--\s*Maintain the v1\.1 snapshot as a compatibility mirror\..*?\n\s*end if;\s*\n\s*end loop;$pattern$,
    E'\n  end loop;',
    1
  );
  updated := replace(
    updated,
    E'  end loop;\n\n  if caller_role = ''builder'' then',
    E'  end loop;\n\n  if caller_role = ''builder'' then\n    snapshot := public.build_inventorinator_entity_snapshot(target_workspace);'
  );
  if updated = definition or
     updated ~ $assert$inventorinator\.incremental_snapshot_write$assert$ or
     updated ~* $assert$public\.workshop_states$assert$ or
     updated ~ $assert$Maintain the v1\.1 snapshot$assert$ then
    raise exception 'Could not remove the synchronous compatibility snapshot write';
  end if;
  execute updated;
end;
$migration$;

-- Restore the normal role-level limits now that incremental writes are small.
alter function public.apply_inventorinator_entity_changes(uuid, text, jsonb, jsonb)
  reset statement_timeout;
alter function public.apply_inventorinator_entity_changes(uuid, text, jsonb, jsonb)
  reset lock_timeout;

notify pgrst, 'reload schema';

insert into public.inventorinator_schema(singleton, version)
values(true, 21)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
