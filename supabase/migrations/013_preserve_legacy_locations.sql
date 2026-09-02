begin;

-- Snapshot clients cannot distinguish "I deleted this record" from "my stale
-- snapshot never contained this record". Preserve locations omitted by those
-- clients. Current clients still delete locations through explicit entity
-- tombstones in apply_inventorinator_entity_changes().
create or replace function public.preserve_inventorinator_legacy_locations()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  preserved jsonb;
begin
  if current_setting('inventorinator.incremental_snapshot_write', true) = 'on' then
    return new;
  end if;

  select coalesce(jsonb_agg(entity.payload order by entity.entity_id), '[]'::jsonb)
  into preserved
  from public.inventorinator_entities entity
  where entity.workspace_id = new.workspace_id
    and entity.entity_type = 'locations'
    and not entity.deleted
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(new.state_json->'locations', '[]'::jsonb)) incoming
      where incoming->>'id' = entity.entity_id
    );

  if jsonb_array_length(preserved) > 0 then
    new.state_json := jsonb_set(
      new.state_json,
      '{locations}',
      coalesce(new.state_json->'locations', '[]'::jsonb) || preserved,
      true
    );
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_inventorinator_legacy_locations
on public.workshop_states;
create trigger preserve_inventorinator_legacy_locations
before insert or update of state_json on public.workshop_states
for each row execute function public.preserve_inventorinator_legacy_locations();

-- Schema 12 retained the last payload inside a tombstone, so locations that
-- were already removed by a stale legacy snapshot can be restored safely.
do $$
declare
  recovered record;
begin
  for recovered in
    select workspace_id, entity_id, payload
    from public.inventorinator_entities
    where entity_type = 'locations'
      and deleted
      and source_device = 'legacy-snapshot'
  loop
    update public.inventorinator_entities
    set deleted = false,
        revision = nextval('public.inventorinator_entity_revision_seq'),
        source_device = 'migration-13-recovery',
        updated_at = now()
    where workspace_id = recovered.workspace_id
      and entity_type = 'locations'
      and entity_id = recovered.entity_id;

    perform set_config('inventorinator.incremental_snapshot_write', 'on', true);
    update public.workshop_states
    set state_json = jsonb_set(
      state_json,
      '{locations}',
      coalesce(state_json->'locations', '[]'::jsonb) ||
        jsonb_build_array(recovered.payload),
      true
    ), updated_at = now()
    where workspace_id = recovered.workspace_id
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(state_json->'locations', '[]'::jsonb)) location
        where location->>'id' = recovered.entity_id
      );
    perform set_config('inventorinator.incremental_snapshot_write', 'off', true);
  end loop;

  if exists (
    select 1
    from public.inventorinator_entities entity
    join public.workshop_states state on state.workspace_id = entity.workspace_id
    where entity.entity_type = 'locations'
      and entity.source_device = 'migration-13-recovery'
      and not entity.deleted
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(state.state_json->'locations', '[]'::jsonb)) location
        where location->>'id' = entity.entity_id
      )
  ) then
    raise exception 'A legacy-deleted location could not be restored';
  end if;
end;
$$;

insert into public.inventorinator_schema(singleton, version) values(true, 13)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
