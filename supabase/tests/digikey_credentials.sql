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
declare uid text; value jsonb;
begin
 perform public.set_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001','fixture-id','fixture-secret',false);
 value := public.get_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001');
 if value->>'client_secret' <> 'fixture-secret' then raise exception 'Round trip failed'; end if;
 if public.get_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000002') is not null then raise exception 'Workspace isolation failed'; end if;
 begin
  perform * from public.inventorinator_digikey_credentials;
  raise exception 'Direct read accepted';
 exception when insufficient_privilege then null; end;
 foreach uid in array array[
 '00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000103',
 '00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000105',
 '00000000-0000-0000-0000-000000000106',''] loop
  perform set_config('request.jwt.claim.sub',uid,true);
  begin
   perform public.get_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001');
   raise exception 'Non-owner read accepted';
  exception when others then if sqlerrm not like '%Only the owner%' then raise; end if; end;
  begin
   perform public.set_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001',null,null,false);
   raise exception 'Non-owner write accepted';
  exception when others then if sqlerrm not like '%Only the owner%' then raise; end if; end;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000101',true);
 begin
  perform public.set_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001','',null,false);
  raise exception 'Invalid credentials accepted';
 exception when others then if sqlerrm not like '%Invalid DigiKey%' then raise; end if; end;
 perform public.set_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001',null,null,false);
 if public.get_inventorinator_digikey_credentials('22000000-0000-0000-0000-000000000001') is not null then raise exception 'Clear failed'; end if;
end;
$$;
rollback;
