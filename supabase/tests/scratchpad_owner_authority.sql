begin;
insert into auth.users(id) values
 ('32000000-0000-0000-0000-000000000001'),
 ('32000000-0000-0000-0000-000000000002'),
 ('32000000-0000-0000-0000-000000000003');
insert into public.inventorinator_workspaces(id,created_by) values
 ('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role,device_id,device_name) values
 ('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000001','owner','owner32','Owner'),
 ('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','builder','vm32','VM1'),
 ('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000003','admin','admin32','Admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000002',true);
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[{"id":"private","title":"Private","body":"Original","isShared":false}]');
-- Both builder and admin are denied inspection and modification.
do $$ declare caller text; begin
 foreach caller in array array['32000000-0000-0000-0000-000000000002','32000000-0000-0000-0000-000000000003'] loop
 perform set_config('request.jwt.claim.sub',caller,true);
 begin
 perform public.list_inventorinator_owner_notes('32000000-0000-0000-0000-000000000010');
 raise exception 'Permission test failed';
 exception when others then if sqlerrm <> 'Owner access required' then raise; end if; end;
 begin
 perform public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','private',now(),null);
 raise exception 'Permission test failed';
 exception when others then if sqlerrm <> 'Owner access required' then raise; end if; end;
 end loop;
end $$;
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000001',true);
select updated_at as note_time from public.list_inventorinator_owner_notes('32000000-0000-0000-0000-000000000010') where note_id='private' \gset
select public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','private',:'note_time','{"title":"Owner revision","body":"Corrected","isShared":true}');
-- A stale editor must not overwrite a newer change.
select set_config('test.old_timestamp',:'note_time',true);
do $$ begin
 begin
 perform public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','private',current_setting('test.old_timestamp')::timestamptz,'{"body":"Stale owner"}');
 raise exception 'Stale owner edit accepted';
 exception when others then if sqlerrm not like 'Note changed on another device.%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000002',true);
-- Old clients may upload a stale note or omit it entirely: neither undoes the Owner.
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[{"id":"private","body":"Original"}]');
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[]');
do $$ declare n record; begin
 select * into n from public.list_inventorinator_recovered_device_notes('32000000-0000-0000-0000-000000000010');
 if n.body is distinct from 'Corrected' or n.owner_revision<>1 or n.is_shared or n.owner_deleted then
 raise exception 'Stale backup reversed moderation or sharing changed'; end if;
end $$;
-- Once received, the author can edit normally using the new revision.
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[{"id":"private","body":"New author edit","ownerRevision":1}]','{"private":1}');
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000001',true);
select updated_at as note_time from public.list_inventorinator_owner_notes('32000000-0000-0000-0000-000000000010') where note_id='private' and body='New author edit' \gset
select public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','private',:'note_time',null);
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000002',true);
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[{"id":"private","body":"Resurrect","ownerRevision":2}]');
do $$ begin
 if not exists(select 1 from public.list_inventorinator_recovered_device_notes('32000000-0000-0000-0000-000000000010') where note_id='private' and owner_deleted) then
 raise exception 'Owner deletion resurrected'; end if;
end $$;
-- The Owner may also manage an archive held by a different administrator.
select public.backup_inventorinator_device_notes('32000000-0000-0000-0000-000000000010','[{"id":"archive","body":"Archive me"}]');
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000003',true);
select public.remove_inventorinator_device('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002',false);
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000001',true);
select updated_at as note_time from public.list_inventorinator_owner_notes('32000000-0000-0000-0000-000000000010') where note_id='archive' \gset
select public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','archive',:'note_time','{"body":"Reviewed archive"}');
select updated_at as note_time from public.list_inventorinator_owner_notes('32000000-0000-0000-0000-000000000010') where note_id='archive' and body='Reviewed archive' \gset
select public.manage_inventorinator_note('32000000-0000-0000-0000-000000000010','32000000-0000-0000-0000-000000000002','archive',:'note_time',null);
select set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000003',true);
do $$ begin
 if exists(select 1 from public.list_inventorinator_removed_device_notes('32000000-0000-0000-0000-000000000010')) then
 raise exception 'Deleted note visible in archive'; end if;
end $$;
rollback;
