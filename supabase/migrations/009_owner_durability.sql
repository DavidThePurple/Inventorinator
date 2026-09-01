begin;

-- An auth identity is a login credential, not the inventory itself. Removing
-- an expired or administratively deleted anonymous user must never cascade
-- into deleting the workspace, its state, or its recovery record.
alter table public.inventorinator_workspaces
  alter column created_by drop not null;
alter table public.inventorinator_workspaces
  drop constraint if exists inventorinator_workspaces_created_by_fkey;
alter table public.inventorinator_workspaces
  add constraint inventorinator_workspaces_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

-- Older workspaces may predate recovery credentials. A currently authorized
-- owner can provision the missing credential once; an existing key is never
-- rotated or exposed by this function.
create or replace function public.ensure_inventorinator_recovery_key(
  target_workspace uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare new_recovery_key text;
begin
  if public.get_inventorinator_role(target_workspace) <> 'owner' then
    raise exception 'Only the shared inventory owner can provision recovery';
  end if;
  if exists (
    select 1 from public.inventorinator_workspace_recovery
    where workspace_id = target_workspace
  ) then
    return null;
  end if;
  new_recovery_key := upper(encode(extensions.gen_random_bytes(24), 'hex'));
  insert into public.inventorinator_workspace_recovery(
    workspace_id, recovery_hash, rotated_at
  ) values (
    target_workspace, extensions.digest(new_recovery_key, 'sha256'), now()
  );
  return new_recovery_key;
end;
$$;

revoke all on function public.ensure_inventorinator_recovery_key(uuid) from public;
grant execute on function public.ensure_inventorinator_recovery_key(uuid) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 9)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
