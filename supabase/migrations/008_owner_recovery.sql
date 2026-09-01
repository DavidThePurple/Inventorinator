begin;

create table if not exists public.inventorinator_workspace_recovery (
  workspace_id uuid primary key references public.inventorinator_workspaces(id) on delete cascade,
  recovery_hash bytea not null,
  rotated_at timestamptz not null default now(),
  recovered_at timestamptz
);
alter table public.inventorinator_workspace_recovery enable row level security;
revoke all on public.inventorinator_workspace_recovery from anon, authenticated;

create or replace function public.create_inventorinator_workspace_with_recovery()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  new_workspace_id uuid := gen_random_uuid();
  new_recovery_key text := upper(encode(extensions.gen_random_bytes(24), 'hex'));
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  insert into public.inventorinator_workspaces(id, created_by)
  values(new_workspace_id, current_user_id);
  insert into public.inventorinator_workspace_members(workspace_id, user_id, role)
  values(new_workspace_id, current_user_id, 'owner');
  insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash)
  values(new_workspace_id, extensions.digest(new_recovery_key, 'sha256'));
  return jsonb_build_object(
    'workspace_id', new_workspace_id,
    'recovery_key', new_recovery_key
  );
end;
$$;

create or replace function public.rotate_inventorinator_recovery_key(
  target_workspace uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare new_recovery_key text := upper(encode(extensions.gen_random_bytes(24), 'hex'));
begin
  if public.get_inventorinator_role(target_workspace) <> 'owner' then
    raise exception 'Only the shared inventory owner can rotate its recovery key';
  end if;
  insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash, rotated_at)
  values(target_workspace, extensions.digest(new_recovery_key, 'sha256'), now())
  on conflict(workspace_id) do update set
    recovery_hash = excluded.recovery_hash,
    rotated_at = excluded.rotated_at,
    recovered_at = null;
  return new_recovery_key;
end;
$$;

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

  -- A recovery is an ownership transfer. Lock out every previous owner token so
  -- a lost or stolen owner device cannot silently reclaim access.
  insert into public.inventorinator_blocked_devices(workspace_id, user_id, blocked_by)
  select target_workspace, user_id, current_user_id
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and role = 'owner' and user_id <> current_user_id
  on conflict(workspace_id, user_id) do update set
    blocked_by = excluded.blocked_by,
    blocked_at = now();
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

revoke all on function public.create_inventorinator_workspace_with_recovery() from public;
revoke all on function public.rotate_inventorinator_recovery_key(uuid) from public;
revoke all on function public.recover_inventorinator_workspace(uuid, text, text) from public;
grant execute on function public.create_inventorinator_workspace_with_recovery() to authenticated;
grant execute on function public.rotate_inventorinator_recovery_key(uuid) to authenticated;
grant execute on function public.recover_inventorinator_workspace(uuid, text, text) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 8)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
