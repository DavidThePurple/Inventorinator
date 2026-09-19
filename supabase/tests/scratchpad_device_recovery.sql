begin;
insert into auth.users(id) values
 ('31000000-0000-0000-0000-000000000001'),
 ('31000000-0000-0000-0000-000000000002'),
 ('31000000-0000-0000-0000-000000000003'),
 ('31000000-0000-0000-0000-000000000004');
insert into public.inventorinator_workspaces(id,created_by) values
 ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role,device_id,device_name) values
 ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000001','owner','owner31','Owner'),
 ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002','builder','vm31','VM1');
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000002',true);
select public.backup_inventorinator_device_notes('31000000-0000-0000-0000-000000000010',
 '[{"id":"note31","title":"Private","body":"Keep this","subjectKind":"Item","subjectId":"item31","subjectLabel":"Fixture"}]');
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
select public.remove_inventorinator_device('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002',false);
select public.create_inventorinator_pairing_code('31000000-0000-0000-0000-000000000010') as code \gset
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000003',true);
select public.redeem_inventorinator_pairing_code(:'code','vm31');
-- Old clients and empty first sync cannot erase undelivered recovery.
select public.backup_inventorinator_device_notes('31000000-0000-0000-0000-000000000010','[]');
do $$ declare n record; begin
 select * into n from public.list_inventorinator_recovered_device_notes('31000000-0000-0000-0000-000000000010');
 if n.title is distinct from 'Private' or n.body is distinct from 'Keep this' or n.is_shared
   or n.subject_id is distinct from 'item31' then raise exception 'Recovery lost note fields'; end if;
end $$;
select public.backup_inventorinator_device_notes('31000000-0000-0000-0000-000000000010',
 '[{"id":"note31","title":"Private","body":"Edited after recovery"}]');
do $$ begin
 if exists(select 1 from public.list_inventorinator_recovered_device_notes('31000000-0000-0000-0000-000000000010')) then
 raise exception 'Acknowledged notes are being replayed'; end if;
end $$;
-- Active membership replacement also recovers notes, without explicit removal.
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
select public.create_inventorinator_pairing_code('31000000-0000-0000-0000-000000000010') as code \gset
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000004',true);
select public.redeem_inventorinator_pairing_code(:'code','vm31');
do $$ begin
 if not exists(select 1 from public.list_inventorinator_recovered_device_notes('31000000-0000-0000-0000-000000000010') where body='Edited after recovery') then
 raise exception 'Active identity replacement lost notes'; end if;
end $$;
-- Legacy archives lack a stable ID and require explicit administrator selection.
reset role;
insert into public.inventorinator_device_notes(workspace_id,source_user_id,note_id,owner_user_id,source_device_name,title,body,transferred_at) values
 ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002','note31','31000000-0000-0000-0000-000000000001','VM1','[Former device: VM1] Legacy','Legacy content',now());
set local role authenticated;
do $$ begin
 begin
 perform public.restore_inventorinator_removed_device_note('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002','note31','31000000-0000-0000-0000-000000000004');
 raise exception 'Unauthorized recovery allowed';
 exception when others then if sqlerrm='Unauthorized recovery allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
select public.restore_inventorinator_removed_device_note('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002','note31','31000000-0000-0000-0000-000000000004');
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000004',true);
do $$ begin
 if (select count(*) from public.list_inventorinator_recovered_device_notes('31000000-0000-0000-0000-000000000010')) <> 2 then
 raise exception 'Note ID collision discarded content'; end if;
end $$;
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
select public.remove_inventorinator_device('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000004',true);
select public.create_inventorinator_pairing_code('31000000-0000-0000-0000-000000000010') as code \gset
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000003',true);
select set_config('test.pairing',:'code',true);
do $$ begin
 begin
 perform public.redeem_inventorinator_pairing_code(current_setting('test.pairing'),'vm31');
 raise exception 'Blocked device recovered';
 exception when others then if sqlerrm='Blocked device recovered' then raise; end if; end;
end $$;
rollback;
