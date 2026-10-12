begin;

-- A missing row in one device's cache is not evidence that a person deleted
-- it. Require an explicit in-app delete intent for every ordinary tombstone,
-- in addition to the current-record baseline enforced by schema 37.
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
    $needle$-- Inventory deletes also require an explicit UI confirmation.$needle$,
    $replacement$-- A snapshot omission is never a deletion. Only an in-app delete
    -- action can stamp this intent; import undo remains separately guarded.
    if change_deleted and coalesce(change->'baseFields'->>'(importUndo)', 'false') <> 'true' then
      if coalesce(change->'baseFields'->>'(explicitDelete)', 'false') <> 'true' then
        raise exception 'Sync conflict: deletes must originate from an explicit Inventorinator action';
      end if;
    end if;

    -- Inventory deletes also require an explicit UI confirmation.$replacement$
  );
  if updated = definition then
    raise exception 'Could not install explicit-delete protection';
  end if;
  execute updated;
end;
$migration$;

insert into public.inventorinator_schema(singleton, version) values(true, 38)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

notify pgrst, 'reload schema';
commit;
