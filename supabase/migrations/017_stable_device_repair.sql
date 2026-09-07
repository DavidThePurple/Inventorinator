begin;

alter table public.inventorinator_workspace_members
  add column if not exists device_id text;

create unique index if not exists inventorinator_workspace_members_device_id
  on public.inventorinator_workspace_members(workspace_id, device_id)
  where device_id is not null;

create table if not exists public.inventorinator_device_history (
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  device_id text not null,
  last_role text not null check (last_role in ('owner', 'admin', 'manager', 'editor', 'builder')),
  blocked boolean not null default false,
  removed_at timestamptz not null default now(),
  primary key (workspace_id, device_id)
);
alter table public.inventorinator_device_history enable row level security;
revoke all on public.inventorinator_device_history from anon, authenticated;

create or replace function public.remove_inventorinator_device(
  target_workspace uuid, target_user uuid, lock_out boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
  victim_role text;
  victim_device_id text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  select role, device_id into victim_role, victim_device_id
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;
  if caller_role <> 'owner' then
    raise exception 'Only the shared inventory owner can remove devices';
  end if;
  if target_user = auth.uid() or victim_role = 'owner' then
    raise exception 'This device cannot be removed';
  end if;
  if lock_out then
    insert into public.inventorinator_blocked_devices(workspace_id, user_id, blocked_by)
    values(target_workspace, target_user, auth.uid()) on conflict do nothing;
  end if;
  if victim_device_id is not null then
    insert into public.inventorinator_device_history(
      workspace_id, device_id, last_role, blocked
    ) values (
      target_workspace, victim_device_id, victim_role, lock_out
    ) on conflict (workspace_id, device_id) do update set
      last_role = excluded.last_role,
      blocked = excluded.blocked,
      removed_at = now();
  end if;
  delete from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;
end;
$$;

drop function if exists public.redeem_inventorinator_pairing_code(text);
create or replace function public.redeem_inventorinator_pairing_code(
  pairing_code text,
  device_identifier text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  matched public.inventorinator_pairing_codes%rowtype;
  normalized_device_id text := nullif(trim(coalesce(device_identifier, '')), '');
  existing_user_id uuid;
  existing_role text;
  restored_role text;
  history_blocked boolean;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  select * into matched
  from public.inventorinator_pairing_codes
  where code_hash = extensions.digest(upper(trim(pairing_code)), 'sha256')
    and used_at is null and expires_at > now()
  for update;
  if not found then raise exception 'Pairing code is invalid or expired'; end if;

  if exists(
    select 1 from public.inventorinator_blocked_devices
    where workspace_id = matched.workspace_id and user_id = current_user_id
  ) then
    raise exception 'This device is locked out of the workspace';
  end if;
  if normalized_device_id is not null then
    select h.blocked into history_blocked
    from public.inventorinator_device_history as h
    where h.workspace_id = matched.workspace_id
      and h.device_id = normalized_device_id;
    if coalesce(history_blocked, false) then
      raise exception 'This device is locked out of the workspace';
    end if;

    select m.user_id, m.role into existing_user_id, existing_role
    from public.inventorinator_workspace_members as m
    where m.workspace_id = matched.workspace_id
      and m.device_id = normalized_device_id
    for update;
    if existing_user_id is not null and existing_user_id <> current_user_id then
      if existing_role = 'owner' then
        raise exception 'This device cannot be replaced';
      end if;
      restored_role := existing_role;
      delete from public.inventorinator_workspace_members
      where workspace_id = matched.workspace_id and user_id = existing_user_id;
    end if;
  end if;

  if restored_role is not null then
    null;
  elsif existing_user_id = current_user_id then
    restored_role := existing_role;
  else
    select h.last_role into restored_role
    from public.inventorinator_device_history as h
    where h.workspace_id = matched.workspace_id
      and h.device_id = normalized_device_id;
  end if;

  insert into public.inventorinator_workspace_members(
    workspace_id, user_id, role, device_id
  ) values (
    matched.workspace_id, current_user_id, coalesce(restored_role, 'builder'), normalized_device_id
  ) on conflict (workspace_id, user_id) do update set
    device_id = coalesce(excluded.device_id, inventorinator_workspace_members.device_id);

  if normalized_device_id is not null then
    delete from public.inventorinator_device_history
    where workspace_id = matched.workspace_id
      and public.inventorinator_device_history.device_id = normalized_device_id;
  end if;
  update public.inventorinator_pairing_codes
  set used_at = now()
  where code_hash = matched.code_hash;
  return matched.workspace_id;
end;
$$;

revoke all on function public.remove_inventorinator_device(uuid, uuid, boolean) from public;
revoke all on function public.redeem_inventorinator_pairing_code(text, text) from public;
grant execute on function public.remove_inventorinator_device(uuid, uuid, boolean) to authenticated;
grant execute on function public.redeem_inventorinator_pairing_code(text, text) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 17)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
