begin;

create or replace function public.list_inventorinator_devices(target_workspace uuid)
returns table(user_id uuid, device_name text, role text, joined_at timestamptz, last_seen_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner', 'admin', 'manager') then
    raise exception 'Device management access required';
  end if;
  return query select m.user_id, m.device_name, m.role, m.joined_at, m.last_seen_at
  from public.inventorinator_workspace_members m
  where m.workspace_id = target_workspace order by m.joined_at;
end;
$$;

create or replace function public.set_inventorinator_device_role(
  target_workspace uuid, target_user uuid, target_role text
) returns void language plpgsql security definer set search_path = '' as $$
declare caller_role text; current_target_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  select role into current_target_role
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = target_user;

  if target_user = auth.uid() or current_target_role is null or current_target_role = 'owner' then
    raise exception 'This device role cannot be changed';
  end if;
  if target_role not in ('admin', 'manager', 'editor', 'builder') then
    raise exception 'Invalid role';
  end if;

  if caller_role in ('owner', 'admin') then
    null;
  elsif caller_role = 'manager'
      and current_target_role in ('editor', 'builder')
      and target_role in ('editor', 'builder') then
    null;
  else
    raise exception 'Your role cannot make that assignment';
  end if;

  update public.inventorinator_workspace_members set role = target_role
  where workspace_id = target_workspace and user_id = target_user;
end;
$$;

create or replace function public.create_inventorinator_pairing_code(target_workspace uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
  new_code text := upper(substr(encode(extensions.gen_random_bytes(9), 'hex'), 1, 12));
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner', 'admin', 'manager') then
    raise exception 'Device management access required';
  end if;
  delete from public.inventorinator_pairing_codes where expires_at < now() or used_at is not null;
  insert into public.inventorinator_pairing_codes(code_hash, workspace_id, created_by, expires_at)
  values(extensions.digest(new_code, 'sha256'), target_workspace, auth.uid(), now() + interval '10 minutes');
  return new_code;
end;
$$;

revoke all on function public.list_inventorinator_devices(uuid) from public;
revoke all on function public.set_inventorinator_device_role(uuid, uuid, text) from public;
revoke all on function public.create_inventorinator_pairing_code(uuid) from public;
grant execute on function public.list_inventorinator_devices(uuid) to authenticated;
grant execute on function public.set_inventorinator_device_role(uuid, uuid, text) to authenticated;
grant execute on function public.create_inventorinator_pairing_code(uuid) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 11)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
