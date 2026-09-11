begin;

insert into auth.users(id) values
  ('25000000-0000-0000-0000-000000000001'),
  ('25000000-0000-0000-0000-000000000002'),
  ('25000000-0000-0000-0000-000000000003');
insert into public.inventorinator_workspaces(id,created_by) values
  ('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,device_id,device_name,role)
values
  ('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000001','owner-device','Owner bench','owner'),
  ('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000002','removed-device','Removed bench','builder'),
  ('25000000-0000-0000-0000-000000000010','25000000-0000-0000-0000-000000000003','admin-device','Admin bench','admin');

set local role authenticated;
select set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000002',true);
select public.backup_inventorinator_device_notes(
  '25000000-0000-0000-0000-000000000010',
  '[{"id":"work-1","title":"Calibrate","body":"Adjust belt tension","updatedAt":"2026-09-11T00:00:00Z"}]'::jsonb
);

select set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000003',true);
select public.remove_inventorinator_device(
  '25000000-0000-0000-0000-000000000010',
  '25000000-0000-0000-0000-000000000002', false
);

do $$
declare archived record;
begin
  select * into archived from public.list_inventorinator_removed_device_notes(
    '25000000-0000-0000-0000-000000000010'
  );
  if archived.note_id is distinct from 'work-1' or
     archived.title not like '[Former device: Removed bench] %' or
     archived.body is distinct from 'Adjust belt tension' then
    raise exception 'Removed device note was not transferred to removing admin';
  end if;
end $$;

select set_config('request.jwt.claim.sub','25000000-0000-0000-0000-000000000001',true);
do $$
begin
  if exists (
    select 1 from public.list_inventorinator_removed_device_notes(
      '25000000-0000-0000-0000-000000000010'
    )
  ) then raise exception 'A different administrator can read another administrator archive'; end if;
end $$;

rollback;
