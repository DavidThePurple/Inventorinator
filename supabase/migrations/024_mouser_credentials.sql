begin;
create table if not exists public.inventorinator_mouser_credentials (
 workspace_id uuid primary key references public.inventorinator_workspaces(id) on delete cascade,
 api_key text not null check(length(api_key) between 1 and 4096),
 updated_at timestamptz not null default now()
);
alter table public.inventorinator_mouser_credentials enable row level security;
revoke all on public.inventorinator_mouser_credentials from public, anon, authenticated;
create or replace function public.get_inventorinator_mouser_credentials(target_workspace uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 if public.get_inventorinator_role(target_workspace) is distinct from 'owner' then
  raise exception 'Only the owner can access shared Mouser credentials';
 end if;
 select jsonb_build_object('api_key',api_key) into result from public.inventorinator_mouser_credentials where workspace_id=target_workspace;
 return result;
end;
$$;
create or replace function public.set_inventorinator_mouser_credentials(target_workspace uuid,target_api_key text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 perform 1 from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=auth.uid() and role='owner' for update;
 if not found then raise exception 'Only the owner can manage shared Mouser credentials'; end if;
 if target_api_key is null then
  delete from public.inventorinator_mouser_credentials where workspace_id=target_workspace;
  return;
 end if;
 if length(btrim(target_api_key)) not between 1 and 4096 then raise exception 'Invalid Mouser credentials'; end if;
 insert into public.inventorinator_mouser_credentials(workspace_id,api_key) values(target_workspace,btrim(target_api_key))
 on conflict(workspace_id) do update set api_key=excluded.api_key,updated_at=now();
end;
$$;
revoke all on function public.get_inventorinator_mouser_credentials(uuid) from public;
revoke all on function public.set_inventorinator_mouser_credentials(uuid,text) from public;
grant execute on function public.get_inventorinator_mouser_credentials(uuid) to authenticated;
grant execute on function public.set_inventorinator_mouser_credentials(uuid,text) to authenticated;
insert into public.inventorinator_schema(singleton,version) values(true,24)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
