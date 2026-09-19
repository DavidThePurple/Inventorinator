begin;

-- Recursively match exact references, not substrings in unrelated descriptions.
create or replace function public.inventorinator_import_reference(value jsonb, item_id text, item_name text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare child jsonb; text_value text;
begin
  if jsonb_typeof(value) = 'string' then
    text_value := value #>> '{}';
    return text_value in (item_id, 'inventory:' || item_id) or
      (coalesce(item_name, '') <> '' and lower(btrim(text_value)) = lower(btrim(item_name)));
  elsif jsonb_typeof(value) = 'array' then
    for child in select jsonb_array_elements(value) loop
      if public.inventorinator_import_reference(child, item_id, item_name) then return true; end if;
    end loop;
  elsif jsonb_typeof(value) = 'object' then
    for child in select v from jsonb_each(value) as fields(k,v) loop
      if public.inventorinator_import_reference(child, item_id, item_name) then return true; end if;
    end loop;
  end if;
  return false;
end; $$;
revoke all on function public.inventorinator_import_reference(jsonb,text,text) from public;

do $migration$
declare definition text; updated text;
begin
  select pg_get_functiondef('public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure) into definition;
  -- Serialize writers within a workspace so both the compare/delete and the
  -- reference check stay valid through commit. Other workspaces are independent.
  updated := replace(definition,
    'caller_role := public.get_inventorinator_role(target_workspace);',
    'perform 1 from public.inventorinator_workspaces where id=target_workspace for update;
     caller_role := public.get_inventorinator_role(target_workspace);');
  updated := replace(updated,
    'if jsonb_typeof(change->''baseFields'') = ''object'' then',
    $guard$if change_deleted and change->'baseFields'->>'(importUndo)' = 'true' then
      if change_type <> 'inventory' or jsonb_typeof(change->'baseFields'->'(deleted)') is distinct from 'object' then
        raise exception 'Invalid import undo';
      end if;
      if previous_payload is not null and
          jsonb_strip_nulls(previous_payload) is distinct from jsonb_strip_nulls(change->'baseFields'->'(deleted)') then
        raise exception 'Sync conflict: imported item changed; keep the remote item';
      end if;
      if exists(select 1 from public.inventorinator_entities e
        where e.workspace_id=target_workspace and not e.deleted
          and e.entity_type not in ('inventory','auditLog','additionHistory','workshopMetadata')
          and public.inventorinator_import_reference(e.payload, change_id, change->'baseFields'->'(deleted)'->>'name')) then
        raise exception 'Sync conflict: imported item is referenced; keep the remote item';
      end if;
    end if;
    if jsonb_typeof(change->'baseFields') = 'object' then$guard$);
  if updated=definition or position('Invalid import undo' in updated)=0 or
      position('inventorinator_workspaces where id=target_workspace for update' in updated)=0 then
    raise exception 'Could not install guarded import undo';
  end if;
  execute updated;
end; $migration$;

insert into public.inventorinator_schema(singleton,version) values(true,30)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
