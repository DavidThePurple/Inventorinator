begin;

-- Checkouts record who has borrowed how much of an inventory item. Each device
-- keeps its own checkouts; the workspace Owner or an Admin decides whether they
-- are shared. The switch lives on the workspace so every device agrees.
alter table public.inventorinator_workspaces
  add column sync_checkouts boolean not null default false;

create function public.get_inventorinator_checkout_sync(target_workspace uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if public.get_inventorinator_role(target_workspace) is null then
    raise exception 'Workspace access denied';
  end if;
  return (select sync_checkouts from public.inventorinator_workspaces
    where id = target_workspace);
end;
$$;

create function public.set_inventorinator_checkout_sync(
  target_workspace uuid, target_enabled boolean
) returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid()
      and role in ('owner', 'admin') for share;
  if not found then
    raise exception 'Only the workspace Owner or an Admin can change checkout sync';
  end if;
  if target_enabled is null then
    raise exception 'Checkout sync setting is required';
  end if;
  update public.inventorinator_workspaces
    set sync_checkouts = target_enabled where id = target_workspace;
end;
$$;

revoke all on function public.get_inventorinator_checkout_sync(uuid) from public;
revoke all on function public.set_inventorinator_checkout_sync(uuid, boolean) from public;
grant execute on function public.get_inventorinator_checkout_sync(uuid) to authenticated;
grant execute on function public.set_inventorinator_checkout_sync(uuid, boolean) to authenticated;

-- Reuse the current incremental-write function and add the new record type,
-- keeping every role and quantity-integrity check it already has. Editors and
-- Builders work at the bench, so they may record checkouts too.
do $migration$
declare
  definition text;
  updated text;
begin
  select pg_get_functiondef(
    'public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The incremental entity-sync RPC is missing';
  end if;
  updated := replace(
    definition,
    '''workshopMetadata'', ''spoolUsage''',
    '''workshopMetadata'', ''spoolUsage'', ''checkouts'''
  );
  if updated = definition then
    raise exception 'Could not update the incremental entity-sync allowlist';
  end if;
  definition := updated;
  updated := regexp_replace(
    definition,
    $pattern$elsif change_type <> 'builds' then(\s+raise exception 'Editors may)$pattern$,
    $replacement$elsif change_type not in ('builds', 'checkouts') then\1$replacement$,
    1
  );
  if updated = definition then
    raise exception 'Could not let Editors record checkouts';
  end if;
  definition := updated;
  updated := regexp_replace(
    definition,
    $pattern$elsif change_type <> 'builds' then(\s+raise exception 'Builders may)$pattern$,
    $replacement$elsif change_type not in ('builds', 'checkouts') then\1$replacement$,
    1
  );
  if updated = definition then
    raise exception 'Could not let Builders record checkouts';
  end if;
  execute updated;
end;
$migration$;

-- Custom roles may record checkouts with inventory edit or build operation.
do $migration$
declare
  definition text;
  updated text;
begin
  select pg_get_functiondef(
    'public.validate_inventorinator_custom_change(uuid,text,text,jsonb,boolean,jsonb)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'The custom-role validation function is missing';
  end if;
  updated := replace(
    definition,
    'elsif change_type=''spoolUsage'' then required_permission := ''inventory.edit'';',
    'elsif change_type=''spoolUsage'' then required_permission := ''inventory.edit'';' || E'\n ' ||
    'elsif change_type=''checkouts'' then' || E'\n   ' ||
    'required_permission := case when ''inventory.edit''=any(p) then ''inventory.edit'' else ''builds.operate'' end;'
  );
  if updated = definition then
    raise exception 'Could not update custom-role validation for checkouts';
  end if;
  execute updated;
end;
$migration$;

-- Enforce the switch for every client, including older or offline ones: while
-- checkout sync is off the server holds no checkout records.
create function public.enforce_inventorinator_checkout_sync()
returns trigger language plpgsql security definer set search_path='' as $$
declare sync_enabled boolean;
begin
  if new.entity_type <> 'checkouts' then return new; end if;
  select sync_checkouts into sync_enabled from public.inventorinator_workspaces
    where id = new.workspace_id for share;
  if not coalesce(sync_enabled, false) then
    raise exception 'Checkout sync is turned off for this workspace';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_inventorinator_checkout_sync() from public;
create trigger enforce_checkout_sync after insert or update on public.inventorinator_entities
  for each row execute function public.enforce_inventorinator_checkout_sync();

insert into public.inventorinator_schema(singleton, version) values(true, 34)
on conflict(singleton) do update set version = excluded.version, updated_at = now();
notify pgrst, 'reload schema';
commit;
