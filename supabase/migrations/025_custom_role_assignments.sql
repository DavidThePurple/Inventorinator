begin;
alter table public.inventorinator_workspace_members add column if not exists role_template_id uuid references public.inventorinator_role_templates(id) on delete restrict;
alter table public.inventorinator_workspace_members add constraint custom_role_is_not_owner check(role_template_id is null or role = 'builder');

create function public.clear_inventorinator_custom_role_on_promotion() returns trigger
language plpgsql set search_path='' as $$ begin
 if new.role <> 'builder' then new.role_template_id := null; end if;
 return new;
end; $$;
create trigger clear_custom_role_on_promotion before update of role on public.inventorinator_workspace_members
for each row execute function public.clear_inventorinator_custom_role_on_promotion();

-- Keep the stored built-in role at Builder, so old clients and every legacy
-- authorization path fail closed. Only the permission-aware RPC expands access.
create function public.inventorinator_custom_permissions(target_workspace uuid)
returns text[] language sql stable security definer set search_path = '' as $$
 select t.permissions from public.inventorinator_workspace_members m
 join public.inventorinator_role_templates t on t.id=m.role_template_id and t.workspace_id=m.workspace_id
 where m.workspace_id=target_workspace and m.user_id=auth.uid();
$$;
revoke all on function public.inventorinator_custom_permissions(uuid) from public;

create function public.get_inventorinator_effective_role(target_workspace uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 select jsonb_build_object('role',m.role,'templateId',t.id,'name',coalesce(t.name,m.role),'permissions',t.permissions)
 into result from public.inventorinator_workspace_members m
 left join public.inventorinator_role_templates t on t.id=m.role_template_id and t.workspace_id=m.workspace_id
 where m.workspace_id=target_workspace and m.user_id=auth.uid();
 if result is null then raise exception 'Workspace access denied'; end if;
 return result;
end; $$;
revoke all on function public.get_inventorinator_effective_role(uuid) from public;
grant execute on function public.get_inventorinator_effective_role(uuid) to authenticated;

create function public.assign_inventorinator_custom_role(target_workspace uuid,target_user uuid,target_template uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare target_record public.inventorinator_workspace_members; definition public.inventorinator_role_templates;
begin
 perform 1 from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=auth.uid() and role='owner' for update;
 if not found then raise exception 'Only the owner can assign custom roles'; end if;
 select * into target_record from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=target_user for update;
 if target_record.user_id is null or target_record.role='owner' or target_user=auth.uid() then raise exception 'This device role cannot be changed'; end if;
 select * into definition from public.inventorinator_role_templates where workspace_id=target_workspace and id=target_template for share;
 if definition.id is null then raise exception 'Role template not found in this workspace'; end if;
 update public.inventorinator_workspace_members set role='builder',role_template_id=target_template where workspace_id=target_workspace and user_id=target_user;
 insert into public.inventorinator_audit_log(workspace_id,actor_user_id,actor_role,action,entity_type,entity_id,changes)
 values(target_workspace,auth.uid(),'owner','assign_custom_role','device',target_user::text,jsonb_build_object('templateId',target_template,'name',definition.name));
end; $$;
revoke all on function public.assign_inventorinator_custom_role(uuid,uuid,uuid) from public;
grant execute on function public.assign_inventorinator_custom_role(uuid,uuid,uuid) to authenticated;

-- Assigned definitions are immutable: duplicate, revise and explicitly reassign.
-- This prevents a stale editor from silently widening access on live devices.
create function public.protect_inventorinator_assigned_template() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.inventorinator_workspace_members where role_template_id=old.id) then
   raise exception 'This role is assigned. Duplicate it, edit the copy, then reassign devices before deleting the old role';
 end if;
 if TG_OP='DELETE' then return old; end if;
 return new;
end; $$;
create trigger protect_assigned_template before update or delete on public.inventorinator_role_templates
for each row execute function public.protect_inventorinator_assigned_template();

-- Returning to a built-in role clears its custom definition; only the owner
-- can replace a custom assignment. Lock membership for the authorization/write.
do $migration$
declare d text;
begin
 select pg_get_functiondef('public.set_inventorinator_device_role(uuid,uuid,text)'::regprocedure) into d;
 d := replace(d, 'caller_role := public.get_inventorinator_role(target_workspace);',
 $code$perform 1 from public.inventorinator_workspace_members where workspace_id=target_workspace order by user_id for update;
 caller_role := public.get_inventorinator_role(target_workspace);
 if exists(select 1 from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=target_user and role_template_id is not null) and caller_role is distinct from 'owner' then
 raise exception 'Only the owner can replace custom role assignments'; end if;$code$);
 d := replace(d,'set role = target_role','set role = target_role, role_template_id = null');
 execute d;
end; $migration$;

-- Validate each custom operation before the existing incremental transaction.
create function public.validate_inventorinator_custom_change(target_workspace uuid, change_type text, change_id text, fields jsonb, is_deleted boolean, previous jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare p text[]; required_permission text; next_build jsonb;
begin
 p := public.inventorinator_custom_permissions(target_workspace);
 if p is null then return; end if;
 if change_type='inventory' then
   if is_deleted then required_permission := 'inventory.delete';
   elsif previous is null then required_permission := 'inventory.create';
   else
     if (fields ? 'archived' or fields ? 'archiveDisposition') and not ('inventory.archive'=any(p)) then raise exception 'Archive permission required'; end if;
     if exists(select 1 from jsonb_object_keys(fields) k where k not in ('archived','archiveDisposition')) then
       if not ('inventory.edit'=any(p)) and not ('builds.operate'=any(p) and fields - 'quantity' = '{}'::jsonb) then raise exception 'Inventory edit permission required'; end if;
     end if;
     return;
   end if;
 elsif change_type='builds' then
   if is_deleted then raise exception 'Custom roles cannot delete builds'; end if;
   next_build := coalesce(previous,'{}'::jsonb) || fields;
   if previous is null then
     required_permission := 'builds.create';
     if exists(select 1 from jsonb_array_elements(coalesce(next_build->'lines','[]')) line where coalesce((line->>'usedQuantity')::numeric,0) <> 0 or jsonb_array_length(coalesce(line->'consumedInventoryIds','[]')) <> 0) then raise exception 'New builds must start without consumed stock'; end if;
     if next_build->>'ownerUserId' is distinct from auth.uid()::text then raise exception 'A build must belong to its creator'; end if;
   else
     if previous->>'ownerUserId' is distinct from auth.uid()::text and not coalesce((previous->>'shared')::boolean,false) then raise exception 'Private build access denied'; end if;
     if (fields ? 'ownerUserId' and fields->>'ownerUserId' is distinct from previous->>'ownerUserId') or (fields ? 'id' and fields->>'id' is distinct from change_id) then raise exception 'Build ownership cannot be changed'; end if;
     if (previous - 'lines' - 'completedAt' - 'updatedAt' - 'shared') is distinct from (next_build - 'lines' - 'completedAt' - 'updatedAt' - 'shared') then raise exception 'Build identity cannot be changed'; end if;
     if (select jsonb_agg(v - 'usedQuantity' - 'consumedInventoryIds' order by v->>'id') from jsonb_array_elements(coalesce(previous->'lines','[]')) v)
        is distinct from (select jsonb_agg(v - 'usedQuantity' - 'consumedInventoryIds' order by v->>'id') from jsonb_array_elements(coalesce(next_build->'lines','[]')) v) then raise exception 'Build requirements cannot change during operation'; end if;
     required_permission := case when fields - 'shared' - 'updatedAt' = '{}'::jsonb then 'builds.share' else 'builds.operate' end;
   end if;
   if coalesce((next_build->>'shared')::boolean,false) is distinct from coalesce((previous->>'shared')::boolean,false) and
      (not ('builds.share'=any(p)) or next_build->>'ownerUserId' is distinct from auth.uid()::text) then raise exception 'Build sharing permission required'; end if;
   if next_build->>'completedAt' is not null and exists(select 1 from jsonb_array_elements(coalesce(next_build->'lines','[]')) line where coalesce((line->>'usedQuantity')::numeric,0)<coalesce((line->>'requiredQuantity')::numeric,0)) then raise exception 'Build is incomplete'; end if;
 elsif change_type='spoolUsage' then required_permission := 'inventory.edit';
 elsif change_type in ('auditLog','additionHistory') then
   if is_deleted or previous is not null then raise exception 'History is append-only for custom roles'; end if;
   if not (p && array['inventory.create','inventory.edit','inventory.archive','inventory.delete','catalog.manage','builds.create','builds.operate']) then raise exception 'Write permission required'; end if;
   return;
 elsif change_type in ('customItemTypes','machineTypes','machines','kits','locations','shoppingList','vendors','brands','spoolTypes','materials','products','workshopMetadata') then required_permission := 'catalog.manage';
 else raise exception 'Unsupported custom role operation';
 end if;
 if not (required_permission=any(p)) then raise exception 'Permission required: %',required_permission; end if;
end; $$;
revoke all on function public.validate_inventorinator_custom_change(uuid,text,text,jsonb,boolean,jsonb) from public;

-- Extend the current optimized RPC, preserving all built-in role behavior and
-- builder allocation integrity checks for custom roles without inventory.edit.
do $migration$
declare d text; original text;
begin
 select pg_get_functiondef('public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb)'::regprocedure) into d;
 original := d;
 d := replace(d,'caller_role text;', 'caller_role text; custom_permissions text[];');
 d := replace(d,'caller_role := public.get_inventorinator_role(target_workspace);',
 $code$perform 1 from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=auth.uid() for share;
 caller_role := public.get_inventorinator_role(target_workspace);
 custom_permissions := public.inventorinator_custom_permissions(target_workspace);
 if custom_permissions is not null then caller_role := 'custom'; end if;$code$);
 d := replace(d, E'\n  if caller_role = ''builder'' then', E'\n  if caller_role = ''builder'' or (caller_role = ''custom'' and not (''inventory.edit''=any(custom_permissions))) then');
 d := replace(d, 'if caller_role = ''manager'' and change_type',
 $code$if jsonb_typeof(change->'baseFields') = 'object' then
      if change_deleted and change->'baseFields' ? '(deleted)' and previous_payload is distinct from change->'baseFields'->'(deleted)' then raise exception 'Sync conflict: remote record changed'; end if;
      if exists(select 1 from jsonb_each(change->'baseFields') base where base.key <> '(deleted)' and change_fields ? base.key and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from base.value and coalesce(previous_payload->base.key,'null'::jsonb) is distinct from change_fields->base.key) then raise exception 'Sync conflict: remote field changed'; end if;
    end if;
    if caller_role = 'manager' and change_type$code$);
 d := replace(d, 'if caller_role = ''manager'' and change_type',
 $code$perform public.validate_inventorinator_custom_change(target_workspace,change_type,change_id,change_fields,change_deleted,previous_payload);
    if caller_role = 'manager' and change_type$code$);
 -- A tombstoned row is a creation for authorization purposes.
 d := replace(d, 'and entity_type = change_type and entity_id = change_id;', 'and entity_type = change_type and entity_id = change_id and not deleted;');
 if d=original or position('validate_inventorinator_custom_change' in d)=0 then raise exception 'Entity permission hook missing'; end if;
 execute d;
end; $migration$;

-- Device listing/pairing are optional custom permissions, not role assignment.
do $migration$
declare f text; d text;
begin
 foreach f in array array['public.list_inventorinator_devices(uuid)','public.create_inventorinator_pairing_code(uuid)'] loop
  select pg_get_functiondef(f::regprocedure) into d;
  d := replace(d, 'if caller_role not in (''owner'', ''admin'', ''manager'') then',
    'if caller_role is null or (caller_role not in (''owner'', ''admin'', ''manager'') and not coalesce(''devices.manage''=any(public.inventorinator_custom_permissions(target_workspace)),false)) then');
  if f='public.list_inventorinator_devices(uuid)' then
    d := replace(d,'m.role, m.joined_at', 'case when m.role_template_id is null then m.role else ''template:'' || m.role_template_id::text end, m.joined_at');
  end if;
  execute d;
 end loop;
end; $migration$;

insert into public.inventorinator_schema(singleton,version) values(true,25)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
