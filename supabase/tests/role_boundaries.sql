begin;

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000012'),
  ('00000000-0000-0000-0000-000000000013'),
  ('00000000-0000-0000-0000-000000000014'),
  ('00000000-0000-0000-0000-000000000015');

insert into public.inventorinator_workspaces(id, created_by) values (
  '20000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000011'
);

insert into public.inventorinator_workspace_members(
  workspace_id, user_id, role, device_name
) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'owner', 'Owner'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000012', 'admin', 'Admin'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000013', 'manager', 'Manager'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000014', 'editor', 'Editor'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000015', 'builder', 'Builder');

insert into public.workshop_states(workspace_id, state_json) values (
  '20000000-0000-0000-0000-000000000001',
  '{
    "inventory": [
      {"id":"INV-A","name":"Bolt","quantity":2},
      {"id":"INV-B","name":"Nut","quantity":1}
    ],
    "builds": []
  }'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000012',
  false
);

do $$
declare device_count integer;
begin
  select count(*) into device_count from public.list_inventorinator_devices(
    '20000000-0000-0000-0000-000000000001'
  );
  if device_count <> 5 then raise exception 'admin device listing failed'; end if;
end;
$$;

select public.set_inventorinator_device_role(
  '20000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000015',
  'editor'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000013',
  false
);

do $$
declare device_count integer;
begin
  select count(*) into device_count from public.list_inventorinator_devices(
    '20000000-0000-0000-0000-000000000001'
  );
  if device_count <> 5 then raise exception 'manager device listing failed'; end if;

  perform public.set_inventorinator_device_role(
    '20000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000015',
    'builder'
  );

  begin
    perform public.set_inventorinator_device_role(
      '20000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000012',
      'editor'
    );
    raise exception 'manager changed an administrator';
  exception when others then
    if position('Your role cannot make that assignment' in sqlerrm) = 0 then
      raise;
    end if;
  end;

  begin
    perform public.apply_inventorinator_entity_changes(
      '20000000-0000-0000-0000-000000000001',
      'test-device',
      '[{"entityType":"inventory","entityId":"INV-B","deleted":true}]'::jsonb
    );
    raise exception 'manager hard deletion was accepted';
  exception when others then
    if position('Managers may archive or decommission' in sqlerrm) = 0 then
      raise;
    end if;
  end;
end;
$$;

select public.apply_inventorinator_entity_changes(
  '20000000-0000-0000-0000-000000000001',
  'test-device',
  '[{
    "entityType": "inventory", "entityId": "INV-B",
    "fields": {"archiveState": "archived"}
  }]'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000014',
  false
);

do $$
begin
  begin
    perform public.list_inventorinator_devices(
      '20000000-0000-0000-0000-000000000001'
    );
    raise exception 'editor device listing was accepted';
  exception when others then
    if position('Device management access required' in sqlerrm) = 0 then
      raise;
    end if;
  end;

  begin
    perform public.apply_inventorinator_entity_changes(
      '20000000-0000-0000-0000-000000000001',
      'test-device',
      '[{
        "entityType": "inventory", "entityId": "INV-C",
        "fields": {"name": "Washer", "quantity": 1}
      }]'::jsonb
    );
    raise exception 'editor inventory creation was accepted';
  exception when others then
    if position('Editors may only edit existing inventory items' in sqlerrm) = 0 then
      raise;
    end if;
  end;
end;
$$;

select public.apply_inventorinator_entity_changes(
  '20000000-0000-0000-0000-000000000001',
  'test-device',
  '[{
    "entityType": "inventory", "entityId": "INV-A",
    "fields": {"name": "Bolt revised"}
  }]'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000011',
  false
);

do $$
declare
  device_count integer;
begin
  select count(*) into device_count
  from public.list_inventorinator_devices(
    '20000000-0000-0000-0000-000000000001'
  );
  if device_count <> 5 then
    raise exception 'owner device listing returned % rows', device_count;
  end if;
end;
$$;

select public.set_inventorinator_device_role(
  '20000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000015',
  'editor'
);

do $$
begin
  if not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '20000000-0000-0000-0000-000000000001'
      and user_id = '00000000-0000-0000-0000-000000000015'
      and role = 'editor'
  ) then
    raise exception 'owner role assignment was not persisted';
  end if;
end;
$$;

set role authenticated;
do $$
begin
  begin
    update public.workshop_states
    set state_json = '{}'::jsonb
    where workspace_id = '20000000-0000-0000-0000-000000000001';
    raise exception 'direct workshop update was accepted';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;

rollback;
