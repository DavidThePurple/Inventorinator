begin;

-- A device may retain an old outbox across a reconnect.  A hard delete must
-- never turn that stale local state into a blind Remote tombstone.  v29 made
-- every delete win so that a device could delete an edit it had queued before
-- the delete; that also allowed one stale device to erase a shared inventory.
-- The client records the last remote payload under `(deleted)`, which makes a
-- normal delete conditional on the record still being the one the user saw.
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
    $needle$if jsonb_typeof(change->'baseFields') = 'object' then
$needle$ || repeat(' ', 6) || $needle$
if exists(select 1 from jsonb_each(change->'baseFields') base where base.key <> '(deleted)' and change_fields ? base.key and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from base.value and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from change_fields->base.key) then raise exception 'Sync conflict: remote field changed'; end if;
    end if;$needle$,
    $replacement$-- Import undo has its own reference-aware protection. Every ordinary
    -- inventory delete must originate in the explicit UI delete flow and still
    -- match the Remote payload it was based on.  Keep this outside the
    -- baseFields branch so a stale or malformed client cannot bypass it.
    if change_deleted and change_type = 'inventory' and coalesce(change->'baseFields'->>'(importUndo)', 'false') <> 'true' then
      if coalesce(change->'baseFields'->>'(confirmedDelete)', 'false') <> 'true' then
        raise exception 'Hard deletes must be confirmed in Inventorinator.';
      end if;
      if jsonb_typeof(change->'baseFields') is distinct from 'object' or
         not (change->'baseFields' ? '(deleted)') or
         previous_payload is distinct from change->'baseFields'->'(deleted)' then
        raise exception 'Sync conflict: remote record changed before delete';
      end if;
    end if;
    if jsonb_typeof(change->'baseFields') = 'object' then
      if exists(select 1 from jsonb_each(change->'baseFields') base where base.key <> '(deleted)' and change_fields ? base.key and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from base.value and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from change_fields->base.key) then raise exception 'Sync conflict: remote field changed'; end if;
    end if;$replacement$
  );
  if updated = definition then
    raise exception 'Could not install stale-delete protection';
  end if;
  execute updated;
end;
$migration$;

insert into public.inventorinator_schema(singleton, version) values(true, 36)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

notify pgrst, 'reload schema';
commit;
