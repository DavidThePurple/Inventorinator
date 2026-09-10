begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000101'),
 ('00000000-0000-0000-0000-000000000102'),
 ('00000000-0000-0000-0000-000000000103'),
 ('00000000-0000-0000-0000-000000000104'),
 ('00000000-0000-0000-0000-000000000105'),
 ('00000000-0000-0000-0000-000000000106');
insert into public.inventorinator_workspaces(id,created_by) values
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101'),
 ('22000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000101');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role,device_name) values
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101','owner','Owner'),
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000102','admin','Admin'),
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000103','manager','Manager'),
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000104','editor','Editor'),
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000105','builder','Builder'),
 ('22000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000101','owner','Owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000101',true);
do $$
declare saved uuid; ids text[]; name_input text; uid text; result_count integer;
begin
 saved := public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',null,' Stock assistant ','Handles filament',array['inventory.read','inventory.edit','inventory.read']);
 select permissions into ids from public.list_inventorinator_role_templates('22000000-0000-0000-0000-000000000001') where id=saved;
 if ids <> array['inventory.edit','inventory.read'] then raise exception 'Permission normalization failed'; end if;
 perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',saved,'Stock assistant','Updated',array['inventory.read']);
 begin
  perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',null,' STOCK ASSISTANT ','',array['inventory.read']);
  raise exception 'Duplicate accepted';
 exception when others then if sqlerrm not like '%already exists%' then raise; end if; end;
 foreach name_input in array array['owner',' ADMIN ','manager','editor','builder','',repeat('x',61)] loop
  begin
   perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',null,name_input,'',array['inventory.read']);
   raise exception 'Invalid name accepted';
  exception when others then if sqlerrm not like '%role name%' and sqlerrm not like '%built-in roles%' then raise; end if; end;
 end loop;
 foreach ids slice 1 in array array[array['inventory.read','owner.recover'],array['inventory.edit','inventory.delete'],array['inventory.read',null]] loop
  begin
   perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',null,'Invalid permissions','',ids);
   raise exception 'Invalid permissions accepted';
  exception when others then if sqlerrm not like '%Invalid role permissions%' then raise; end if; end;
 end loop;
 begin
  perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000002',saved,'Cross workspace','',array['inventory.read']);
  raise exception 'Cross-workspace update accepted';
 exception when others then if sqlerrm not like '%not found%' then raise; end if; end;
 begin
  perform public.delete_inventorinator_role_template('22000000-0000-0000-0000-000000000002',saved);
  raise exception 'Cross-workspace deletion accepted';
 exception when others then if sqlerrm not like '%not found%' then raise; end if; end;
 -- Templates cannot be used to bypass the existing role-assignment RPC.
 begin
  perform public.set_inventorinator_device_role('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000105',saved::text);
  raise exception 'Draft role assignment accepted';
 exception when others then if sqlerrm not like '%Invalid role%' then raise; end if; end;
 foreach uid in array array[
 '00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000103',
 '00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000105',
 '00000000-0000-0000-0000-000000000106',''] loop
  perform set_config('request.jwt.claim.sub',uid,true);
  begin
   perform public.list_inventorinator_role_templates('22000000-0000-0000-0000-000000000001');
   raise exception 'Non-owner read accepted';
  exception when others then if sqlerrm not like '%Only the owner%' and sqlerrm not like '%Workspace access denied%' then raise; end if; end;
  begin
   perform public.save_inventorinator_role_template('22000000-0000-0000-0000-000000000001',saved,'Hijacked','',array['inventory.read']);
   raise exception 'Non-owner write accepted';
  exception when others then if sqlerrm not like '%Only the owner%' then raise; end if; end;
  begin
   perform public.delete_inventorinator_role_template('22000000-0000-0000-0000-000000000001',saved);
   raise exception 'Non-owner deletion accepted';
  exception when others then if sqlerrm not like '%Only the owner%' then raise; end if; end;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000101',true);
 if has_table_privilege('authenticated','public.inventorinator_role_templates','SELECT')
 or has_table_privilege('authenticated','public.inventorinator_role_templates','INSERT')
 or has_table_privilege('authenticated','public.inventorinator_role_templates','UPDATE')
 or has_table_privilege('authenticated','public.inventorinator_role_templates','DELETE')
 or has_function_privilege('anon','public.save_inventorinator_role_template(uuid,uuid,text,text,text[])','EXECUTE')
 then raise exception 'Direct template access exposed'; end if;
 perform public.delete_inventorinator_role_template('22000000-0000-0000-0000-000000000001',saved);
 select count(*) into result_count from public.list_inventorinator_role_templates('22000000-0000-0000-0000-000000000001');
 if result_count <> 0 then raise exception 'Deletion failed'; end if;
end;
$$;
rollback;
