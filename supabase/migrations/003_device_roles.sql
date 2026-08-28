begin;

alter table public.inventorinator_workspace_members
  drop constraint if exists inventorinator_workspace_members_role_check;
alter table public.inventorinator_workspace_members
  add constraint inventorinator_workspace_members_role_check
  check (role in ('owner', 'admin', 'member'));
alter table public.inventorinator_workspace_members
  add column if not exists device_name text not null default 'Unnamed device',
  add column if not exists last_seen_at timestamptz not null default now();

create table if not exists public.inventorinator_blocked_devices (
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  blocked_by uuid not null references auth.users(id) on delete cascade,
  blocked_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
alter table public.inventorinator_blocked_devices enable row level security;
revoke all on public.inventorinator_blocked_devices from anon, authenticated;

create or replace function public.is_inventorinator_admin(target_workspace uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid()
      and role in ('owner', 'admin')
  );
$$;

create or replace function public.register_inventorinator_device(
  target_workspace uuid, target_name text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.inventorinator_workspace_members
  set device_name = left(coalesce(nullif(trim(target_name), ''), 'Unnamed device'), 80),
      last_seen_at = now()
  where workspace_id = target_workspace and user_id = auth.uid();
  if not found then raise exception 'Workspace access denied'; end if;
end;
$$;

create or replace function public.list_inventorinator_devices(target_workspace uuid)
returns table(user_id uuid, device_name text, role text, joined_at timestamptz, last_seen_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_inventorinator_member(target_workspace) then
    raise exception 'Workspace access denied';
  end if;
  return query select m.user_id, m.device_name, m.role, m.joined_at, m.last_seen_at
  from public.inventorinator_workspace_members m
  where m.workspace_id = target_workspace order by m.joined_at;
end;
$$;

create or replace function public.set_inventorinator_device_role(
  target_workspace uuid, target_user uuid, target_role text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid() and role = 'owner') then
    raise exception 'Only the owner can change administrator roles';
  end if;
  if target_role not in ('admin', 'member') then raise exception 'Invalid role'; end if;
  update public.inventorinator_workspace_members set role = target_role
  where workspace_id = target_workspace and user_id = target_user and role <> 'owner';
  if not found then raise exception 'Device cannot be changed'; end if;
end;
$$;

create or replace function public.remove_inventorinator_device(
  target_workspace uuid, target_user uuid, lock_out boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
declare caller_role text; victim_role text;
begin
  select role into caller_role from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = auth.uid();
  select role into victim_role from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;
  if caller_role not in ('owner', 'admin') then raise exception 'Administrator access required'; end if;
  if target_user = auth.uid() or victim_role = 'owner' or
     (caller_role = 'admin' and victim_role <> 'member') then
    raise exception 'This device cannot be removed';
  end if;
  if lock_out then
    insert into public.inventorinator_blocked_devices(workspace_id, user_id, blocked_by)
    values(target_workspace, target_user, auth.uid()) on conflict do nothing;
  end if;
  delete from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;
end;
$$;

create or replace function public.create_inventorinator_pairing_code(target_workspace uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare new_code text := upper(substr(encode(extensions.gen_random_bytes(9), 'hex'), 1, 12));
begin
  if not public.is_inventorinator_admin(target_workspace) then raise exception 'Administrator access required'; end if;
  delete from public.inventorinator_pairing_codes where expires_at < now() or used_at is not null;
  insert into public.inventorinator_pairing_codes(code_hash, workspace_id, created_by, expires_at)
  values(extensions.digest(new_code, 'sha256'), target_workspace, auth.uid(), now() + interval '10 minutes');
  return new_code;
end;
$$;

create or replace function public.redeem_inventorinator_pairing_code(pairing_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare matched public.inventorinator_pairing_codes%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into matched from public.inventorinator_pairing_codes
  where code_hash = extensions.digest(upper(trim(pairing_code)), 'sha256')
    and used_at is null and expires_at > now() for update;
  if not found then raise exception 'Pairing code is invalid or expired'; end if;
  if exists(select 1 from public.inventorinator_blocked_devices
    where workspace_id = matched.workspace_id and user_id = auth.uid()) then
    raise exception 'This device is locked out of the workspace';
  end if;
  insert into public.inventorinator_workspace_members(workspace_id, user_id)
  values(matched.workspace_id, auth.uid()) on conflict do nothing;
  update public.inventorinator_pairing_codes set used_at = now() where code_hash = matched.code_hash;
  return matched.workspace_id;
end;
$$;

revoke all on function public.register_inventorinator_device(uuid, text) from public;
revoke all on function public.list_inventorinator_devices(uuid) from public;
revoke all on function public.set_inventorinator_device_role(uuid, uuid, text) from public;
revoke all on function public.remove_inventorinator_device(uuid, uuid, boolean) from public;
grant execute on function public.register_inventorinator_device(uuid, text) to authenticated;
grant execute on function public.list_inventorinator_devices(uuid) to authenticated;
grant execute on function public.set_inventorinator_device_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_inventorinator_device(uuid, uuid, boolean) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 3)
on conflict(singleton) do update set version = excluded.version, updated_at = now();
commit;
