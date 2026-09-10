begin;

-- Credentials are separate from inventory entities and ordinary member reads.
create table if not exists public.inventorinator_digikey_credentials (
  workspace_id uuid primary key references public.inventorinator_workspaces(id) on delete cascade,
  client_id text not null check(length(client_id) between 1 and 256),
  client_secret text not null check(length(client_secret) between 1 and 4096),
  sandbox boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.inventorinator_digikey_credentials enable row level security;
revoke all on public.inventorinator_digikey_credentials from public, anon, authenticated;

create or replace function public.get_inventorinator_digikey_credentials(target_workspace uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if public.get_inventorinator_role(target_workspace) is distinct from 'owner' then
    raise exception 'Only the owner can access shared DigiKey credentials';
  end if;
  select jsonb_build_object('client_id', client_id, 'client_secret', client_secret, 'sandbox', sandbox)
    into result from public.inventorinator_digikey_credentials where workspace_id = target_workspace;
  return result;
end;
$$;

create or replace function public.set_inventorinator_digikey_credentials(
  target_workspace uuid, target_client_id text, target_client_secret text, target_sandbox boolean
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid() and role = 'owner' for update;
  if not found then raise exception 'Only the owner can manage shared DigiKey credentials'; end if;
  if target_client_id is null and target_client_secret is null then
    delete from public.inventorinator_digikey_credentials where workspace_id = target_workspace;
    return;
  end if;
  if target_client_id is null or target_client_secret is null
    or length(btrim(target_client_id)) not between 1 and 256
    or length(btrim(target_client_secret)) not between 1 and 4096
    or target_sandbox is null then
    raise exception 'Invalid DigiKey credentials';
  end if;
  insert into public.inventorinator_digikey_credentials(workspace_id, client_id, client_secret, sandbox)
    values(target_workspace, btrim(target_client_id), btrim(target_client_secret), target_sandbox)
  on conflict(workspace_id) do update set client_id = excluded.client_id,
    client_secret = excluded.client_secret, sandbox = excluded.sandbox, updated_at = now();
end;
$$;
revoke all on function public.get_inventorinator_digikey_credentials(uuid) from public;
revoke all on function public.set_inventorinator_digikey_credentials(uuid, text, text, boolean) from public;
grant execute on function public.get_inventorinator_digikey_credentials(uuid) to authenticated;
grant execute on function public.set_inventorinator_digikey_credentials(uuid, text, text, boolean) to authenticated;
insert into public.inventorinator_schema(singleton, version) values(true, 23)
on conflict(singleton) do update set version = excluded.version, updated_at = now();
notify pgrst, 'reload schema';
commit;
