begin;

-- A workspace is shared state. A device that has been offline must never be
-- able to tombstone a record it no longer recognizes, regardless of entity
-- type. Schema 36 protected inventory only; locations, kits, catalog records,
-- machines, and other shared entities still accepted stale deletes.
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
    $needle$    if jsonb_typeof(change->'baseFields') = 'object' then$needle$,
    $replacement$-- Inventory deletes also require an explicit UI confirmation.
    if change_deleted and change_type = 'inventory' and coalesce(change->'baseFields'->>'(importUndo)', 'false') <> 'true' then
      if coalesce(change->'baseFields'->>'(confirmedDelete)', 'false') <> 'true' then
        raise exception 'Hard deletes must be confirmed in Inventorinator.';
      end if;
    end if;

    -- Every ordinary tombstone is conditional on the exact Remote record the
    -- deleting device saw. A mismatched or absent baseline is stale, so keep
    -- the Remote record and make the client resolve the conflict instead.
    if change_deleted and coalesce(change->'baseFields'->>'(importUndo)', 'false') <> 'true' then
      if jsonb_typeof(change->'baseFields') is distinct from 'object' or
         not (change->'baseFields' ? '(deleted)') or
         previous_payload is distinct from change->'baseFields'->'(deleted)' then
        raise exception 'Sync conflict: remote record changed before delete';
      end if;
    end if;
    if jsonb_typeof(change->'baseFields') = 'object' then$replacement$
  );
  if updated = definition then
    raise exception 'Could not install universal stale-delete protection';
  end if;
  execute updated;
end;
$migration$;

insert into public.inventorinator_schema(singleton, version) values(true, 37)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

notify pgrst, 'reload schema';
commit;
