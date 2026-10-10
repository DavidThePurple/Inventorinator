begin;

-- Owner recovery previously blocked the old anonymous auth account, but not
-- its stable device identity. A wiped or reinstalled stolen Owner device could
-- therefore come back as a fresh anonymous user if it later obtained a pairing
-- code. Preserve and block that device identity before removing its membership.
create or replace function public.recover_inventorinator_workspace(
  target_workspace uuid,
  recovery_key text,
  target_device_name text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  stored_hash bytea;
  new_recovery_key text := upper(encode(extensions.gen_random_bytes(24), 'hex'));
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  select recovery_hash into stored_hash
  from public.inventorinator_workspace_recovery
  where workspace_id = target_workspace for update;
  if stored_hash is null or stored_hash <> extensions.digest(upper(trim(recovery_key)), 'sha256') then
    raise exception 'Recovery key or inventory ID is invalid';
  end if;

  delete from public.inventorinator_pairing_codes
  where workspace_id = target_workspace;

  insert into public.inventorinator_blocked_devices(workspace_id, user_id, blocked_by)
  select target_workspace, user_id, current_user_id
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and role = 'owner' and user_id <> current_user_id
  on conflict(workspace_id, user_id) do update set
    blocked_by = excluded.blocked_by,
    blocked_at = now();

  insert into public.inventorinator_device_history(
    workspace_id, device_id, last_role, blocked, removed_at
  )
  select target_workspace, device_id, 'owner', true, now()
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace
    and role = 'owner'
    and user_id <> current_user_id
    and device_id is not null
  on conflict(workspace_id, device_id) do update set
    last_role = 'owner',
    blocked = true,
    removed_at = now();

  delete from public.inventorinator_workspace_members
  where workspace_id = target_workspace and role = 'owner' and user_id <> current_user_id;
  delete from public.inventorinator_blocked_devices
  where workspace_id = target_workspace and user_id = current_user_id;
  insert into public.inventorinator_workspace_members(
    workspace_id, user_id, role, device_name, last_seen_at
  ) values (
    target_workspace, current_user_id, 'owner',
    left(coalesce(nullif(trim(target_device_name), ''), 'Recovered device'), 80), now()
  ) on conflict(workspace_id, user_id) do update set
    role = 'owner', device_name = excluded.device_name, last_seen_at = now();
  update public.inventorinator_workspaces
  set created_by = current_user_id where id = target_workspace;
  update public.inventorinator_workspace_recovery set
    recovery_hash = extensions.digest(new_recovery_key, 'sha256'),
    rotated_at = now(), recovered_at = now()
  where workspace_id = target_workspace;
  return jsonb_build_object(
    'workspace_id', target_workspace,
    'recovery_key', new_recovery_key
  );
end;
$$;

-- Associate every Owner device with its stable local identity. Existing apps
-- may keep calling the two-argument RPC because the third argument has a
-- default, while current clients send it on each registration/refresh.
drop function if exists public.register_inventorinator_device(uuid, text);
create function public.register_inventorinator_device(
  target_workspace uuid,
  target_name text,
  device_identifier text default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  normalized_device_id text := nullif(trim(coalesce(device_identifier, '')), '');
begin
  update public.inventorinator_workspace_members
  set device_name = left(coalesce(nullif(trim(target_name), ''), 'Unnamed device'), 80),
      device_id = coalesce(normalized_device_id, device_id),
      last_seen_at = now()
  where workspace_id = target_workspace and user_id = auth.uid();
  if not found then raise exception 'Workspace access denied'; end if;
  return true;
end;
$$;

revoke all on function public.recover_inventorinator_workspace(uuid, text, text) from public;
revoke all on function public.register_inventorinator_device(uuid, text, text) from public;
grant execute on function public.recover_inventorinator_workspace(uuid, text, text) to authenticated;
grant execute on function public.register_inventorinator_device(uuid, text, text) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 35)
on conflict(singleton) do update set version = excluded.version, updated_at = now();
notify pgrst, 'reload schema';
commit;
