begin;

alter table public.inventorinator_workspaces
  add column if not exists remote_purge_after_days integer not null default 3;

alter table public.inventorinator_workspaces
  drop constraint if exists inventorinator_workspaces_remote_purge_days_check;
alter table public.inventorinator_workspaces
  add constraint inventorinator_workspaces_remote_purge_days_check
  check (remote_purge_after_days between 1 and 365);

create or replace function public.get_inventorinator_remote_purge_days(
  target_workspace uuid
) returns integer language plpgsql stable security definer set search_path = '' as $$
declare
  caller_role text;
  purge_days integer;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  select remote_purge_after_days into purge_days
  from public.inventorinator_workspaces
  where id = target_workspace;
  if purge_days is null then raise exception 'Workspace access denied'; end if;
  return purge_days;
end;
$$;

create or replace function public.set_inventorinator_remote_purge_days(
  target_workspace uuid,
  target_days integer
) returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner', 'admin') then
    raise exception 'Owner or administrator access required';
  end if;
  if target_days < 1 or target_days > 365 then
    raise exception 'Offline purge must be between 1 and 365 days';
  end if;
  update public.inventorinator_workspaces
  set remote_purge_after_days = target_days
  where id = target_workspace;
end;
$$;

revoke all on function public.get_inventorinator_remote_purge_days(uuid) from public;
revoke all on function public.set_inventorinator_remote_purge_days(uuid, integer) from public;
grant execute on function public.get_inventorinator_remote_purge_days(uuid) to authenticated;
grant execute on function public.set_inventorinator_remote_purge_days(uuid, integer) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 16)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
