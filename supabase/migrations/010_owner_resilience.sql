begin;

-- A block is workspace security state, not a property of the owner who
-- created it. Losing a later owner's auth identity must not unblock a stolen
-- device.
alter table public.inventorinator_blocked_devices
  alter column blocked_by drop not null;
alter table public.inventorinator_blocked_devices
  drop constraint if exists inventorinator_blocked_devices_blocked_by_fkey;
alter table public.inventorinator_blocked_devices
  add constraint inventorinator_blocked_devices_blocked_by_fkey
  foreign key (blocked_by) references auth.users(id) on delete set null;

-- Audit history must survive deletion of the anonymous auth identity that
-- performed the action.
alter table public.inventorinator_audit_log
  alter column actor_user_id drop not null;
alter table public.inventorinator_audit_log
  drop constraint if exists inventorinator_audit_log_actor_user_id_fkey;
alter table public.inventorinator_audit_log
  add constraint inventorinator_audit_log_actor_user_id_fkey
  foreign key (actor_user_id) references auth.users(id) on delete set null;

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

  -- A takeover invalidates every code issued by the previous owner. This
  -- closes the short window where a stolen device could reuse a code minted
  -- before recovery.
  delete from public.inventorinator_pairing_codes
  where workspace_id = target_workspace;

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

revoke all on function public.recover_inventorinator_workspace(uuid, text, text) from public;
grant execute on function public.recover_inventorinator_workspace(uuid, text, text) to authenticated;

-- The pre-recovery creator cannot safely return a recovery secret. Current
-- clients use create_inventorinator_workspace_with_recovery instead.
revoke execute on function public.create_inventorinator_workspace() from authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 10)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
