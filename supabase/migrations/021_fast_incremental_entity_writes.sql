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
  updated := regexp_replace(
    definition,
    $pattern$(?is)perform\s+set_config\('inventorinator\.incremental_snapshot_write'\s*,\s*'on'\s*,\s*true\s*\);$pattern$,
    '',
    1
  );
  updated := regexp_replace(
    updated,
    $pattern$(?is)insert\s+into\s+public\.workshop_states\s*\([^;]*?;\s*$pattern$,
    '',
    1
  );
  updated := regexp_replace(
    updated,
    $pattern$(?is)perform\s+set_config\('inventorinator\.incremental_snapshot_write'\s*,\s*'off'\s*,\s*true\s*\);$pattern$,
    '',
    1
  );
  if updated = definition or
     updated ~ $assert$inventorinator\.incremental_snapshot_write$assert$ or
     updated ~* $assert$insert\s+into\s+public\.workshop_states$assert$ then
    raise exception 'Could not remove the synchronous compatibility snapshot write';
  end if;
  with_builder_snapshot := replace(
    updated,
    'snapshot := coalesce(snapshot, ''{"schemaVersion":8}''::jsonb);',
    'snapshot := coalesce(snapshot, ''{"schemaVersion":8}''::jsonb);' ||
      E'\n  if caller_role = ''builder'' then\n' ||
      '    snapshot := public.build_inventorinator_entity_snapshot(target_workspace);' ||
      E'\n  end if;'
  );
  if with_builder_snapshot = updated then
    raise exception 'Could not add the builder validation snapshot';
  end if;
  updated := with_builder_snapshot;
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
