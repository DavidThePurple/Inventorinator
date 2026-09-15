begin;

-- A tombstone is a later operation, not a competing field edit.  In
-- particular, it must supersede an earlier local edit that remains in a
-- device outbox.  The former whole-payload comparison reported that normal
-- sequence as a sync conflict and stranded the delete indefinitely.
do $migration$
declare definition text; updated text;
begin
  select pg_get_functiondef(
    'public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The incremental entity-sync RPC is missing';
  end if;
  updated := replace(
    definition,
    'if change_deleted and change->''baseFields'' ? ''(deleted)'' and previous_payload is distinct from change->''baseFields''->''(deleted)'' then raise exception ''Sync conflict: remote record changed''; end if;',
    ''
  );
  if updated = definition then
    raise exception 'Could not update the delete conflict policy';
  end if;
  execute updated;
end;
$migration$;

insert into public.inventorinator_schema(singleton,version) values(true,29)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
