begin;

insert into auth.users(id) values ('00000000-0000-0000-0000-000000000061');
insert into public.inventorinator_workspaces(id, created_by)
values (
  '60000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000061'
);
insert into public.inventorinator_workspace_members(
  workspace_id, user_id, role, device_name
) values (
  '60000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000061',
  'owner',
  'Test owner'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061',
  false
);

select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001',
  'test-device',
  '[{
    "entityType":"inventory",
    "entityId":"INV-A",
    "fields":{"id":"INV-A","name":"M3 screw","quantity":2},
    "deleted":false
  }]'::jsonb
);

select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001',
  'test-device',
  '[{
    "entityType":"inventory",
    "entityId":"INV-A",
    "fields":{"quantity":3},
    "deleted":false
  }]'::jsonb
);

do $$
declare
  entity jsonb;
  mirrored jsonb;
begin
  select payload into entity
  from public.inventorinator_entities
  where workspace_id = '60000000-0000-0000-0000-000000000001'
    and entity_type = 'inventory' and entity_id = 'INV-A';
  if entity->>'name' <> 'M3 screw' or (entity->>'quantity')::numeric <> 3 then
    raise exception 'field patch replaced unchanged entity fields';
  end if;

  select state_json #> '{inventory,0}' into mirrored
  from public.workshop_states
  where workspace_id = '60000000-0000-0000-0000-000000000001';
  if mirrored->>'name' <> 'M3 screw' or
     (mirrored->>'quantity')::numeric <> 3 then
    raise exception 'compatibility snapshot did not mirror entity patch';
  end if;
end;
$$;

select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001',
  'test-device',
  '[{
    "entityType":"inventory",
    "entityId":"INV-A",
    "fields":{},
    "deleted":true
  }]'::jsonb
);

do $$
begin
  if not exists (
    select 1 from public.inventorinator_entities
    where workspace_id = '60000000-0000-0000-0000-000000000001'
      and entity_type = 'inventory' and entity_id = 'INV-A' and deleted
  ) then
    raise exception 'entity tombstone was not retained';
  end if;
  if jsonb_array_length((select state_json->'inventory'
      from public.workshop_states
      where workspace_id = '60000000-0000-0000-0000-000000000001')) <> 0 then
    raise exception 'deleted entity remained in compatibility snapshot';
  end if;
end;
$$;

-- A v11 client may still be connected during rollout. Its snapshot RPC must
-- feed only its changed records into the v12 stream until every device updates.
select public.save_inventorinator_workshop_state(
  '60000000-0000-0000-0000-000000000001',
  '{"schemaVersion":8,"inventory":[{"id":"LEGACY-A","name":"Nut","quantity":4}]}'::jsonb
);

do $$
declare legacy_entity jsonb;
begin
  select payload into legacy_entity
  from public.inventorinator_entities
  where workspace_id = '60000000-0000-0000-0000-000000000001'
    and entity_type = 'inventory' and entity_id = 'LEGACY-A' and not deleted;
  if legacy_entity->>'name' <> 'Nut' or
     (legacy_entity->>'quantity')::numeric <> 4 then
    raise exception 'legacy snapshot change did not enter entity stream';
  end if;
end;
$$;

-- A stale snapshot must not interpret an empty location that it never loaded
-- as a deletion. Explicit entity tombstones remain authoritative.
select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001',
  'current-device',
  '[{
    "entityType":"locations",
    "entityId":"LOC-EMPTY",
    "fields":{"id":"LOC-EMPTY","name":"Empty shelf"},
    "deleted":false
  }]'::jsonb
);

select public.save_inventorinator_workshop_state(
  '60000000-0000-0000-0000-000000000001',
  '{"schemaVersion":8,"inventory":[{"id":"LEGACY-A","name":"Nut","quantity":5}]}'::jsonb
);

do $$
begin
  if not exists (
    select 1 from public.inventorinator_entities
    where workspace_id = '60000000-0000-0000-0000-000000000001'
      and entity_type = 'locations' and entity_id = 'LOC-EMPTY' and not deleted
  ) then
    raise exception 'stale snapshot deleted an empty location entity';
  end if;
  if not exists (
    select 1
    from public.workshop_states state,
         jsonb_array_elements(coalesce(state.state_json->'locations', '[]'::jsonb)) location
    where state.workspace_id = '60000000-0000-0000-0000-000000000001'
      and location->>'id' = 'LOC-EMPTY'
  ) then
    raise exception 'stale snapshot removed an empty location from compatibility state';
  end if;
end;
$$;

select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001',
  'current-device',
  '[{
    "entityType":"locations",
    "entityId":"LOC-EMPTY",
    "fields":{},
    "deleted":true
  }]'::jsonb
);

do $$
begin
  if not exists (
    select 1 from public.inventorinator_entities
    where workspace_id = '60000000-0000-0000-0000-000000000001'
      and entity_type = 'locations' and entity_id = 'LOC-EMPTY' and deleted
  ) then
    raise exception 'explicit location deletion was blocked';
  end if;
end;
$$;

-- Incremental writes must preserve the v1.1 role boundaries rather than
-- bypassing them simply because a client sends one entity at a time.
insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000062'),
  ('00000000-0000-0000-0000-000000000063');
insert into public.inventorinator_workspace_members(
  workspace_id, user_id, role, device_name
) values
  ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000062', 'editor', 'Editor'),
  ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000063', 'builder', 'Builder');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000061', false);
select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001', 'owner-device',
  '[
    {"entityType":"inventory","entityId":"INV-B","fields":{"id":"INV-B","name":"M3 screw","catalogProductId":"P-1","quantity":2}},
    {"entityType":"builds","entityId":"BUILD-SHARED","fields":{"id":"BUILD-SHARED","name":"Shared","ownerUserId":"00000000-0000-0000-0000-000000000061","shared":true,"lines":[{"id":"LINE-1","productId":"P-1","name":"M3 screw","requiredQuantity":2,"usedQuantity":0,"consumedInventoryIds":[]}] }},
    {"entityType":"builds","entityId":"BUILD-PRIVATE","fields":{"id":"BUILD-PRIVATE","name":"Private","ownerUserId":"00000000-0000-0000-0000-000000000061","shared":false,"lines":[]}}
  ]'::jsonb
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', false);
select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001', 'editor-device',
  '[{"entityType":"inventory","entityId":"INV-B","fields":{"status":"ready"}}]'::jsonb
);
select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001', 'editor-device',
  '[{"entityType":"builds","entityId":"EDITOR-BUILD","fields":{"id":"EDITOR-BUILD","name":"Mine","ownerUserId":"00000000-0000-0000-0000-000000000062","shared":false,"lines":[]}}]'::jsonb
);
do $$ begin
  perform public.apply_inventorinator_entity_changes(
    '60000000-0000-0000-0000-000000000001', 'editor-device',
    '[{"entityType":"inventory","entityId":"EDITOR-NEW","fields":{"name":"Forbidden"}}]'::jsonb
  );
  raise exception 'editor created inventory through incremental sync';
exception when others then
  if sqlerrm = 'editor created inventory through incremental sync' then raise; end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000063', false);
do $$ begin
  perform public.apply_inventorinator_entity_changes(
    '60000000-0000-0000-0000-000000000001', 'builder-device',
    '[{"entityType":"inventory","entityId":"INV-B","fields":{"name":"Forbidden"}}]'::jsonb
  );
  raise exception 'builder edited inventory metadata through incremental sync';
exception when others then
  if sqlerrm = 'builder edited inventory metadata through incremental sync' then raise; end if;
end $$;
do $$ begin
  perform public.apply_inventorinator_entity_changes(
    '60000000-0000-0000-0000-000000000001', 'builder-device',
    '[{"entityType":"builds","entityId":"BUILD-PRIVATE","fields":{"updatedAt":"2026-09-02T00:00:00Z"}}]'::jsonb
  );
  raise exception 'builder operated a private build through incremental sync';
exception when others then
  if sqlerrm = 'builder operated a private build through incremental sync' then raise; end if;
end $$;

select public.apply_inventorinator_entity_changes(
  '60000000-0000-0000-0000-000000000001', 'builder-device',
  '[
    {"entityType":"inventory","entityId":"INV-B","fields":{"quantity":1}},
    {"entityType":"builds","entityId":"BUILD-SHARED","fields":{"lines":[{"id":"LINE-1","productId":"P-1","name":"M3 screw","requiredQuantity":2,"usedQuantity":1,"consumedInventoryIds":["INV-B"]}]}}
  ]'::jsonb
);
do $$ begin
  perform public.apply_inventorinator_entity_changes(
    '60000000-0000-0000-0000-000000000001', 'builder-device',
    '[{"entityType":"inventory","entityId":"INV-B","fields":{"quantity":0}}]'::jsonb
  );
  raise exception 'builder quantity drift passed incremental integrity checks';
exception when others then
  if sqlerrm = 'builder quantity drift passed incremental integrity checks' then raise; end if;
end $$;

rollback;
