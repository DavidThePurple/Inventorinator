begin;

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000041'),
  ('00000000-0000-0000-0000-000000000042'),
  ('00000000-0000-0000-0000-000000000043'),
  ('00000000-0000-0000-0000-000000000044'),
  ('00000000-0000-0000-0000-000000000045');

insert into public.inventorinator_workspaces(id, created_by) values (
  '30000000-0000-0000-0000-000000000021',
  '00000000-0000-0000-0000-000000000041'
);
insert into public.inventorinator_workspace_members(
  workspace_id, user_id, role, device_name
) values
  ('30000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000041', 'owner', 'Stolen owner phone'),
  ('30000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000043', 'manager', 'Workshop manager'),
  ('30000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000045', 'editor', 'Audit actor');
insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash)
values (
  '30000000-0000-0000-0000-000000000021',
  extensions.digest('FIRST-RESILIENCE-KEY', 'sha256')
);
insert into public.workshop_states(workspace_id, state_json) values (
  '30000000-0000-0000-0000-000000000021',
  '{"inventory":[{"id":"INV-PRESERVED","quantity":17}],"builds":[{"id":"BUILD-PRESERVED"}]}'::jsonb
);
insert into public.inventorinator_pairing_codes(
  code_hash, workspace_id, created_by, expires_at
) values (
  extensions.digest('STALE-PAIRING-CODE', 'sha256'),
  '30000000-0000-0000-0000-000000000021',
  '00000000-0000-0000-0000-000000000041',
  now() + interval '10 minutes'
);
insert into public.inventorinator_audit_log(
  workspace_id, actor_user_id, actor_role, action, entity_type, entity_id
) values (
  '30000000-0000-0000-0000-000000000021',
  '00000000-0000-0000-0000-000000000045',
  'editor', 'edit', 'inventory', 'INV-PRESERVED'
);

-- Managers and other non-owners must not be able to mint or rotate recovery.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
do $$
begin
  begin
    perform public.ensure_inventorinator_recovery_key(
      '30000000-0000-0000-0000-000000000021'
    );
    raise exception 'manager provisioned owner recovery';
  exception when others then
    if sqlerrm = 'manager provisioned owner recovery' then raise; end if;
  end;
  begin
    perform public.rotate_inventorinator_recovery_key(
      '30000000-0000-0000-0000-000000000021'
    );
    raise exception 'manager rotated owner recovery';
  exception when others then
    if sqlerrm = 'manager rotated owner recovery' then raise; end if;
  end;
end;
$$;

-- Recover from a stolen but still-valid owner identity.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
do $$
declare replacement jsonb; next_key text;
begin
  replacement := public.recover_inventorinator_workspace(
    '30000000-0000-0000-0000-000000000021',
    'FIRST-RESILIENCE-KEY',
    'Replacement owner laptop'
  );
  next_key := replacement->>'recovery_key';
  if next_key is null or next_key = 'FIRST-RESILIENCE-KEY' then
    raise exception 'recovery did not rotate its credential';
  end if;
  if (select count(*) from public.inventorinator_workspace_members
      where workspace_id = '30000000-0000-0000-0000-000000000021'
        and role = 'owner') <> 1 then
    raise exception 'recovery did not leave exactly one owner';
  end if;
  if not exists (
    select 1 from public.inventorinator_blocked_devices
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and user_id = '00000000-0000-0000-0000-000000000041'
  ) then raise exception 'stolen owner was not blocked'; end if;
  if exists (
    select 1 from public.inventorinator_pairing_codes
    where workspace_id = '30000000-0000-0000-0000-000000000021'
  ) then raise exception 'recovery retained a stale pairing code'; end if;
  if not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and user_id = '00000000-0000-0000-0000-000000000043'
      and role = 'manager'
  ) then raise exception 'recovery removed a team member'; end if;
  if not exists (
    select 1 from public.workshop_states
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and state_json->'inventory'->0->>'id' = 'INV-PRESERVED'
      and state_json->'builds'->0->>'id' = 'BUILD-PRESERVED'
  ) then raise exception 'recovery changed inventory or builds'; end if;

  -- A rotated key is single-use. The previous key cannot take ownership back.
  begin
    perform public.recover_inventorinator_workspace(
      '30000000-0000-0000-0000-000000000021',
      'FIRST-RESILIENCE-KEY',
      'Stolen phone returns'
    );
    raise exception 'old recovery key was reused';
  exception when others then
    if sqlerrm = 'old recovery key was reused' then raise; end if;
  end;

  -- Deleting an audit actor must preserve the audit entry.
  delete from auth.users where id = '00000000-0000-0000-0000-000000000045';
  if not exists (
    select 1 from public.inventorinator_audit_log
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and entity_id = 'INV-PRESERVED' and actor_user_id is null
  ) then raise exception 'auth deletion erased audit history'; end if;

  -- Lose the replacement identity too. The workspace, recovery secret, and
  -- block on the first stolen phone must all survive.
  delete from auth.users where id = '00000000-0000-0000-0000-000000000042';
  if not exists (
    select 1 from public.inventorinator_workspaces
    where id = '30000000-0000-0000-0000-000000000021' and created_by is null
  ) then raise exception 'second owner loss removed or retained workspace ownership'; end if;
  if not exists (
    select 1 from public.inventorinator_blocked_devices
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and user_id = '00000000-0000-0000-0000-000000000041'
      and blocked_by is null
  ) then raise exception 'second owner loss unblocked the first stolen phone'; end if;

  -- A third owner can recover with the rotated package and all data remains.
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
  perform public.recover_inventorinator_workspace(
    '30000000-0000-0000-0000-000000000021', next_key, 'Third owner device'
  );
  if (select count(*) from public.inventorinator_workspace_members
      where workspace_id = '30000000-0000-0000-0000-000000000021'
        and role = 'owner') <> 1 or not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and user_id = '00000000-0000-0000-0000-000000000044'
      and role = 'owner'
  ) then raise exception 'successive recovery did not establish one owner'; end if;
  if not exists (
    select 1 from public.workshop_states
    where workspace_id = '30000000-0000-0000-0000-000000000021'
      and state_json->'inventory'->0->>'quantity' = '17'
  ) then raise exception 'successive recovery changed inventory state'; end if;
end;
$$;

do $$
begin
  if has_function_privilege(
    'authenticated', 'public.create_inventorinator_workspace()', 'EXECUTE'
  ) then raise exception 'legacy workspace creation can still omit recovery'; end if;
end;
$$;

rollback;
