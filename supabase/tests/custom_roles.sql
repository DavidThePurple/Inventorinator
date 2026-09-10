begin;
insert into auth.users(id) values('25000000-0000-0000-0000-000000000001'),('25000000-0000-0000-0000-000000000002');
insert into public.inventorinator_workspaces(id,created_by) values('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role) values
('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000001','owner'),
('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002','builder');
set local role authenticated;
select set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
do $$ declare reader uuid; editor uuid; ops uuid; result jsonb; op jsonb; begin
 reader := public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',null,'Reader','',array['inventory.read']);
 editor := public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',null,'Stock editor','',array['inventory.read','inventory.edit']);
 ops := public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',null,'Operator','',array['inventory.read','builds.operate']);
 perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"item","fields":{"name":"Part","quantity":10,"archived":false}}]');
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',reader);
 begin
  perform public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',reader,'Reader','',array['inventory.read','inventory.edit']);
  raise exception 'Assigned role was mutable';
 exception when others then if sqlerrm not like '%assigned%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 result := public.get_inventorinator_effective_role('25000000-0000-0000-0000-000000000010');
 if result->>'templateId' is distinct from reader::text then raise exception 'Wrong effective role'; end if;
 for op in select value from jsonb_array_elements('[
 {"entityType":"inventory","entityId":"item","fields":{"quantity":9}},
 {"entityType":"inventory","entityId":"new","fields":{"name":"New"}},
 {"entityType":"inventory","entityId":"item","fields":{},"deleted":true},
 {"entityType":"inventory","entityId":"item","fields":{"archived":true}},
 {"entityType":"kits","entityId":"kit","fields":{"name":"Kit"}},
 {"entityType":"spoolUsage","entityId":"usage","fields":{"gramsUsed":5}},
 {"entityType":"workshopMetadata","entityId":"singleton","fields":{"historyLimit":1}}
 ]') loop
  begin
   perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test',jsonb_build_array(op));
   raise exception 'DENIAL FAILED: %',op;
  exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 end loop;
 begin
  perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000001',editor);
  raise exception 'DENIAL FAILED: assignment';
 exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 begin
  perform public.create_inventorinator_pairing_code('25000000-0000-0000-0000-000000000010');
  raise exception 'DENIAL FAILED: pairing';
 exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 begin
  perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','stale reader','[{"entityType":"inventory","entityId":"item","fields":{"name":"Lost update"},"baseFields":{"name":"Outdated name"}}]');
  raise exception 'DENIAL FAILED: stale conditional write';
 exception when others then if sqlerrm not like '%Sync conflict%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',editor);
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"item","fields":{"name":"Edited","quantity":9}}]');
 begin
  perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"item","fields":{"archived":true}}]');
  raise exception 'DENIAL FAILED: editor archive';
 exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',ops);
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 begin
  perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"item","fields":{"quantity":8}}]');
  raise exception 'DENIAL FAILED: operator unallocated consumption';
 exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',reader);
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 begin
  perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','old queued edit','[{"entityType":"inventory","entityId":"item","fields":{"name":"Stale edit"}}]');
  raise exception 'DENIAL FAILED: revoked permission';
 exception when others then if sqlerrm like 'DENIAL FAILED%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 editor := public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',null,'Create only','',array['inventory.read','inventory.create']);
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',editor);
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"created","fields":{"name":"Created","quantity":3}}]');
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
 editor := public.save_inventorinator_role_template('25000000-0000-0000-0000-000000000010',null,'Catalog only','',array['inventory.read','catalog.manage']);
 perform public.assign_inventorinator_custom_role('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002',editor);
 perform set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
 perform public.apply_inventorinator_entity_changes('25000000-0000-0000-0000-000000000010','test','[{"entityType":"kits","entityId":"kit","fields":{"name":"Kit","bom":[]}}]');
end $$;
rollback;
