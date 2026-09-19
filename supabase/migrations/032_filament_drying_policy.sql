begin;
alter table public.inventorinator_workspaces
  add column require_manual_drying_times boolean not null default false;

create function public.get_inventorinator_manual_drying(target_workspace uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if public.get_inventorinator_role(target_workspace) is null then raise exception 'Workspace access denied'; end if;
  return (select require_manual_drying_times from public.inventorinator_workspaces where id=target_workspace);
end;
$$;
create function public.set_inventorinator_manual_drying(target_workspace uuid, target_required boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.inventorinator_workspace_members where workspace_id=target_workspace
    and user_id=auth.uid() and role='owner' for share;
  if not found then raise exception 'Only the workspace Owner can change drying policy'; end if;
  if target_required is null then raise exception 'Drying policy is required'; end if;
  update public.inventorinator_workspaces set require_manual_drying_times=target_required where id=target_workspace;
end;
$$;
revoke all on function public.get_inventorinator_manual_drying(uuid) from public;
revoke all on function public.set_inventorinator_manual_drying(uuid,boolean) from public;
grant execute on function public.get_inventorinator_manual_drying(uuid) to authenticated;
grant execute on function public.set_inventorinator_manual_drying(uuid,boolean) to authenticated;

-- Enforce the Owner's policy even for older/offline clients. Existing cycles
-- may finish normally when the policy is enabled midway through drying.
create function public.enforce_inventorinator_drying_policy()
returns trigger language plpgsql security definer set search_path='' as $$
declare manual_required boolean;
begin
  if new.deleted or new.entity_type <> 'inventory' or new.payload->>'type' <> 'filament'
    or new.payload->>'filamentStatus' is distinct from 'drying' then return new; end if;
  if TG_OP='UPDATE' and not old.deleted and old.payload->>'filamentStatus'='drying'
    and old.payload->>'dryingStartedAt' is not distinct from new.payload->>'dryingStartedAt' then return new; end if;
  select require_manual_drying_times into manual_required from public.inventorinator_workspaces
    where id=new.workspace_id for share;
  if manual_required and (coalesce(new.payload->>'dryingMinutes','') !~ '^[1-9][0-9]*$') then
    raise exception 'The workspace Owner requires a manual drying time before starting drying'; end if;
  return new;
end;
$$;
revoke all on function public.enforce_inventorinator_drying_policy() from public;
-- AFTER runs only on the actual INSERT/UPDATE branch of an upsert. Raising
-- here still rolls back the transaction, while preserving unrelated edits to existing cycles.
create trigger enforce_filament_drying_policy after insert or update on public.inventorinator_entities
  for each row execute function public.enforce_inventorinator_drying_policy();
insert into public.inventorinator_schema(singleton,version) values(true,32)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
