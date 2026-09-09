begin;

-- The v12 incremental RPC predates print-log spool usage records. Reuse its
-- current definition and add the newer entity type without replacing the
-- role and quantity-integrity checks added by that function.
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
  updated := regexp_replace(
    definition,
    $pattern$'workshopMetadata'(\s*\n\s*\))$pattern$,
    $replacement$'workshopMetadata', 'spoolUsage'\1$replacement$,
    1
  );
  if updated = definition then
    raise exception 'Could not update the incremental entity-sync allowlist';
  end if;
  execute updated;
end;
$migration$;

-- Keep legacy snapshot writes and the initial entity backfill aware of usage
-- records too. Current clients use the incremental RPC above, but this keeps
-- the compatibility mirror complete during staged upgrades.
do $migration$
declare
  definition text;
  updated text;
begin
  select pg_get_functiondef(
    'public.mirror_inventorinator_snapshot_changes()'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The legacy snapshot mirror is missing';
  end if;
  updated := regexp_replace(
    definition,
    $pattern$'additionHistory'(\s*\n\s*\]\s*loop)$pattern$,
    $replacement$'additionHistory', 'spoolUsage'\1$replacement$,
    1
  );
  if updated = definition then
    raise exception 'Could not update the legacy snapshot mirror allowlist';
  end if;
  execute updated;
end;
$migration$;

do $seed$
declare
  source record;
  row_value jsonb;
begin
  for source in select workspace_id, state_json
    from public.workshop_states
  loop
    for row_value in select value
      from jsonb_array_elements(
        coalesce(source.state_json->'spoolUsage', '[]'::jsonb)
      )
    loop
      if row_value->>'id' is not null then
        insert into public.inventorinator_entities(
          workspace_id, entity_type, entity_id, payload
        ) values (
          source.workspace_id, 'spoolUsage', row_value->>'id', row_value
        ) on conflict(workspace_id, entity_type, entity_id) do nothing;
      end if;
    end loop;
  end loop;
end;
$seed$;

notify pgrst, 'reload schema';

insert into public.inventorinator_schema(singleton, version) values(true, 19)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
