begin;
insert into auth.users(id) values
 ('34000000-0000-0000-0000-000000000001'),
 ('34000000-0000-0000-0000-000000000002'),
 ('34000000-0000-0000-0000-000000000003'),
 ('34000000-0000-0000-0000-000000000004'),
 ('34000000-0000-0000-0000-000000000005');
insert into public.inventorinator_workspaces(id,created_by) values
 ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role) values
 ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000001','owner'),
 ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000002','admin'),
 ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000003','editor'),
 ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000004','builder');
set local role authenticated;

-- Off by default, readable by every member, hidden from outsiders.
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000003',true);
do $$ begin
 if public.get_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010') then
   raise exception 'Checkout sync must be off by default'; end if;
 begin
  perform public.set_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010',true);
  raise exception 'Editor changed checkout sync';
 exception when others then
  if sqlerrm <> 'Only the workspace Owner or an Admin can change checkout sync' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000005',true);
do $$ begin
 begin
  perform public.get_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010');
  raise exception 'Outsider read checkout sync';
 exception when others then
  if sqlerrm <> 'Workspace access denied' then raise; end if; end;
end $$;

-- While off, the server refuses checkout records from any role.
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000003',true);
do $$ begin
 begin
  perform public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"checkouts","entityId":"co-1","fields":{"itemId":"spool","borrower":"Sam","quantity":1}}]');
  raise exception 'Checkout accepted while sync was off';
 exception when others then
  if sqlerrm <> 'Checkout sync is turned off for this workspace' then raise; end if; end;
end $$;

-- An Admin turns it on, and every device sees the setting.
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000002',true);
select public.set_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010',true);
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000003',true);
do $$ begin
 if not public.get_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010') then
   raise exception 'Checkout sync setting is not shared'; end if;
end $$;

-- Editors and Builders, who work at the bench, may record and update checkouts.
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','editor-device','[{"entityType":"checkouts","entityId":"co-1","fields":{"itemId":"spool","borrower":"Sam","quantity":2}}]');
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000004',true);
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','builder-device','[{"entityType":"checkouts","entityId":"co-1","fields":{"returnedQuantity":1}}]');
do $$ begin
 if (select (payload->>'returnedQuantity')::int from public.inventorinator_entities
     where workspace_id='34000000-0000-0000-0000-000000000010' and entity_type='checkouts' and entity_id='co-1') <> 1
 then raise exception 'Builder return was not stored'; end if;
 if (select payload->>'borrower' from public.inventorinator_entities
     where workspace_id='34000000-0000-0000-0000-000000000010' and entity_type='checkouts' and entity_id='co-1') <> 'Sam'
 then raise exception 'Checkout fields were not merged'; end if;
end $$;

-- The new type did not widen anything else: Editors and Builders still cannot
-- write catalog records.
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000003',true);
do $$ begin
 begin
  perform public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"vendors","entityId":"v-1","fields":{"name":"Acme"}}]');
  raise exception 'Editor changed the catalog';
 exception when others then
  if sqlerrm <> 'Editors may only edit inventory and operate Builds' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000004',true);
do $$ begin
 begin
  perform public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"vendors","entityId":"v-1","fields":{"name":"Acme"}}]');
  raise exception 'Builder changed the catalog';
 exception when others then
  if sqlerrm <> 'Builders may only operate Builds' then raise; end if; end;
end $$;

-- The Owner may turn it back off; the server then refuses new checkout writes.
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000001',true);
select public.set_inventorinator_checkout_sync('34000000-0000-0000-0000-000000000010',false);
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000003',true);
do $$ begin
 begin
  perform public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"checkouts","entityId":"co-2","fields":{"itemId":"spool","borrower":"Alex","quantity":1}}]');
  raise exception 'Checkout accepted after sync was turned off';
 exception when others then
  if sqlerrm <> 'Checkout sync is turned off for this workspace' then raise; end if; end;
end $$;
rollback;

-- Custom roles record checkouts through the same permission the inventory uses.
do $$ begin
 if position('checkouts' in pg_get_functiondef(
   'public.validate_inventorinator_custom_change(uuid,text,text,jsonb,boolean,jsonb)'::regprocedure)) = 0
 then raise exception 'Custom-role validation does not know checkouts'; end if;
end $$;
