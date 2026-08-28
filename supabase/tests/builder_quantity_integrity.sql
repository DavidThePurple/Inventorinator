insert into auth.users values ('00000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspaces(id, created_by)
values (
  '10000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001'
);
insert into public.inventorinator_workspace_members(workspace_id, user_id, role)
values (
  '10000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'builder'
);
insert into public.workshop_states(workspace_id, state_json)
values (
  '10000000-0000-0000-0000-000000000001',
  '{
    "inventory": [{
      "id": "INV-1", "name": "M3 screw", "quantity": 1,
      "catalogProductId": "P-1"
    }],
    "builds": [{
      "id": "B-1", "ownerUserId": "99999999-9999-9999-9999-999999999999",
      "shared": true,
      "lines": [{
        "id": "L-1", "productId": "P-1", "name": "M3 screw",
        "requiredQuantity": 1, "usedQuantity": 0,
        "consumedInventoryIds": []
      }]
    }]
  }'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  false
);

do $$
begin
  begin
    perform public.save_inventorinator_workshop_state(
      '10000000-0000-0000-0000-000000000001',
      '{
        "inventory": [{
          "id": "INV-1", "name": "M3 screw", "quantity": 9,
          "catalogProductId": "P-1"
        }],
        "builds": [{
          "id": "B-1", "ownerUserId": "99999999-9999-9999-9999-999999999999",
          "shared": true,
          "lines": [{
            "id": "L-1", "productId": "P-1", "name": "M3 screw",
            "requiredQuantity": 1, "usedQuantity": 0,
            "consumedInventoryIds": []
          }]
        }]
      }'::jsonb
    );
    raise exception 'tampered quantity was accepted';
  exception when others then
    if sqlerrm = 'tampered quantity was accepted' then raise; end if;
  end;
end;
$$;

select public.save_inventorinator_workshop_state(
  '10000000-0000-0000-0000-000000000001',
  '{
    "inventory": [{
      "id": "INV-1", "name": "M3 screw", "quantity": 0,
      "catalogProductId": "P-1"
    }],
    "builds": [{
      "id": "B-1", "ownerUserId": "99999999-9999-9999-9999-999999999999",
      "shared": true,
      "lines": [{
        "id": "L-1", "productId": "P-1", "name": "M3 screw",
        "requiredQuantity": 1, "usedQuantity": 1,
        "consumedInventoryIds": ["INV-1"]
      }]
    }]
  }'::jsonb
);

do $$
declare
  inventory_quantity numeric;
  used_quantity numeric;
begin
  select
    (state_json #>> '{inventory,0,quantity}')::numeric,
    (state_json #>> '{builds,0,lines,0,usedQuantity}')::numeric
  into inventory_quantity, used_quantity
  from public.workshop_states
  where workspace_id = '10000000-0000-0000-0000-000000000001';
  if inventory_quantity <> 0 or used_quantity <> 1 then
    raise exception 'legitimate Build use was not persisted';
  end if;
end;
$$;
