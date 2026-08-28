begin;

drop function if exists public.register_inventorinator_device(uuid, text);
create function public.register_inventorinator_device(
  target_workspace uuid, target_name text
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.inventorinator_workspace_members
  set device_name = left(coalesce(nullif(trim(target_name), ''), 'Unnamed device'), 80),
      last_seen_at = now()
  where workspace_id = target_workspace and user_id = auth.uid();
  if not found then raise exception 'Workspace access denied'; end if;
  return true;
end;
$$;

create or replace function public.get_inventorinator_role(target_workspace uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare current_role text;
begin
  select role into current_role
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = auth.uid();
  if current_role is null then raise exception 'Workspace access denied'; end if;
  return current_role;
end;
$$;

create or replace function public.list_inventorinator_devices(target_workspace uuid)
returns table(user_id uuid, device_name text, role text, joined_at timestamptz, last_seen_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if public.get_inventorinator_role(target_workspace) <> 'owner' then
    raise exception 'Only the shared inventory owner can view devices';
  end if;
  return query select m.user_id, m.device_name, m.role, m.joined_at, m.last_seen_at
  from public.inventorinator_workspace_members m
  where m.workspace_id = target_workspace order by m.joined_at;
end;
$$;

create or replace function public.remove_inventorinator_device(
  target_workspace uuid, target_user uuid, lock_out boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
declare victim_role text;
begin
  if public.get_inventorinator_role(target_workspace) <> 'owner' then
    raise exception 'Only the shared inventory owner can remove devices';
  end if;
  select role into victim_role from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;
  if target_user = auth.uid() or victim_role = 'owner' then
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

revoke all on function public.register_inventorinator_device(uuid, text) from public;
revoke all on function public.get_inventorinator_role(uuid) from public;
revoke all on function public.list_inventorinator_devices(uuid) from public;
revoke all on function public.remove_inventorinator_device(uuid, uuid, boolean) from public;
grant execute on function public.register_inventorinator_device(uuid, text) to authenticated;
grant execute on function public.get_inventorinator_role(uuid) to authenticated;
grant execute on function public.list_inventorinator_devices(uuid) to authenticated;
grant execute on function public.remove_inventorinator_device(uuid, uuid, boolean) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 4)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
