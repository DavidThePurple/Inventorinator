begin;

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000022'),
  ('00000000-0000-0000-0000-000000000023');

insert into public.inventorinator_workspaces(id, created_by) values (
  '30000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000021'
);
insert into public.inventorinator_workspace_members(
  workspace_id, user_id, role, device_name
) values
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000021', 'owner', 'Lost phone'),
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000023', 'manager', 'Manager');
insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash)
values (
  '30000000-0000-0000-0000-000000000001',
  extensions.digest('KNOWN-RECOVERY-KEY', 'sha256')
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);

do $$
declare replacement jsonb;
begin
  replacement := public.recover_inventorinator_workspace(
    '30000000-0000-0000-0000-000000000001',
    'KNOWN-RECOVERY-KEY',
    'Replacement laptop'
  );
  if replacement->>'recovery_key' = 'KNOWN-RECOVERY-KEY' then
    raise exception 'recovery key was not rotated';
  end if;
  if not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000001'
      and user_id = '00000000-0000-0000-0000-000000000022'
      and role = 'owner' and device_name = 'Replacement laptop'
  ) then raise exception 'new owner was not installed'; end if;
  if exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000001'
      and user_id = '00000000-0000-0000-0000-000000000021'
  ) then raise exception 'old owner retained membership'; end if;
  if not exists (
    select 1 from public.inventorinator_blocked_devices
    where workspace_id = '30000000-0000-0000-0000-000000000001'
      and user_id = '00000000-0000-0000-0000-000000000021'
  ) then raise exception 'old owner was not locked out'; end if;
  if not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000001'
      and user_id = '00000000-0000-0000-0000-000000000023'
      and role = 'manager'
  ) then raise exception 'team member was removed during recovery'; end if;
  begin
    perform public.recover_inventorinator_workspace(
      '30000000-0000-0000-0000-000000000001',
      'KNOWN-RECOVERY-KEY',
      'Attacker'
    );
    raise exception 'old recovery key was accepted';
  exception when others then
    if sqlerrm = 'old recovery key was accepted' then raise; end if;
  end;
end;
$$;

rollback;
