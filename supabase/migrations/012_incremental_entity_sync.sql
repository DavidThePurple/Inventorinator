begin;

create sequence if not exists public.inventorinator_entity_revision_seq;

create table if not exists public.inventorinator_entities (
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  payload jsonb not null default '{}'::jsonb,
  deleted boolean not null default false,
  revision bigint not null default nextval('public.inventorinator_entity_revision_seq'),
  source_device text not null default '',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, entity_type, entity_id)
);

create index if not exists inventorinator_entities_changes
  on public.inventorinator_entities(workspace_id, revision);

alter table public.inventorinator_entities enable row level security;
revoke all on public.inventorinator_entities from anon;
grant select on public.inventorinator_entities to authenticated;

drop policy if exists "members read inventorinator entities"
on public.inventorinator_entities;
create policy "members read inventorinator entities"
on public.inventorinator_entities for select to authenticated
using (exists (
  select 1 from public.inventorinator_workspace_members member
  where member.workspace_id = inventorinator_entities.workspace_id
    and member.user_id = auth.uid()
));

create or replace function public.apply_inventorinator_entity_changes(
  target_workspace uuid,
  source_device text,
  entity_changes jsonb,
  audit_events jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
  change jsonb;
  event jsonb;
  change_type text;
  change_id text;
  change_fields jsonb;
  change_deleted boolean;
  previous_payload jsonb;
  next_payload jsonb;
  initial_snapshot jsonb;
  next_revision bigint;
  latest_revision bigint := 0;
  snapshot jsonb;
  rows jsonb;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  if jsonb_typeof(coalesce(entity_changes, '[]'::jsonb)) <> 'array' then
    raise exception 'Entity changes must be an array';
  end if;

  select coalesce(state_json, '{}'::jsonb) into snapshot
  from public.workshop_states where workspace_id = target_workspace for update;
  snapshot := coalesce(snapshot, '{"schemaVersion":8}'::jsonb);
  initial_snapshot := snapshot;

  for change in select value from jsonb_array_elements(coalesce(entity_changes, '[]'::jsonb))
  loop
    change_type := change->>'entityType';
    change_id := change->>'entityId';
    change_fields := coalesce(change->'fields', '{}'::jsonb);
    change_deleted := coalesce((change->>'deleted')::boolean, false);
    if change_type is null or change_id is null or change_type not in (
      'inventory', 'customItemTypes', 'machineTypes', 'machines', 'kits',
      'builds', 'locations', 'shoppingList', 'auditLog', 'vendors', 'brands',
      'spoolTypes', 'materials', 'products', 'additionHistory',
      'workshopMetadata'
    ) then raise exception 'Unsupported Inventorinator entity type'; end if;

    select payload into previous_payload
    from public.inventorinator_entities
    where workspace_id = target_workspace
      and entity_type = change_type and entity_id = change_id;

    if caller_role = 'manager' and change_type = 'inventory' and change_deleted then
      raise exception 'Managers may archive or decommission items, not permanently delete them';
    elsif caller_role = 'editor' then
      if change_type = 'inventory' then
        if change_deleted or previous_payload is null then
          raise exception 'Editors may only edit existing inventory items';
        end if;
      elsif change_type <> 'builds' then
        raise exception 'Editors may only edit inventory and operate Builds';
      end if;
    elsif caller_role = 'builder' then
      if change_type = 'inventory' then
        if change_deleted or previous_payload is null or
           exists (select 1 from jsonb_object_keys(change_fields) key where key <> 'quantity') then
          raise exception 'Builders may only update inventory quantities';
        end if;
      elsif change_type <> 'builds' then
        raise exception 'Builders may only operate Builds';
      end if;
    end if;

    next_payload := case
      when change_deleted then coalesce(previous_payload, '{}'::jsonb)
      else jsonb_strip_nulls(coalesce(previous_payload, '{}'::jsonb) || change_fields) ||
           jsonb_build_object('id', change_id)
    end;

    if caller_role in ('editor', 'builder') and change_type = 'builds' then
      if change_deleted then
        if caller_role = 'editor' then raise exception 'Editors cannot remove Builds'; end if;
        raise exception 'Builders cannot create or remove Builds';
      end if;
      if previous_payload is null then
        if caller_role = 'builder' then raise exception 'Builders cannot create Builds'; end if;
        if next_payload->>'ownerUserId' is distinct from auth.uid()::text then
          raise exception 'A new Build must belong to its creator';
        end if;
      else
        if coalesce((previous_payload->>'shared')::boolean, false) is not true and
           previous_payload->>'ownerUserId' is distinct from auth.uid()::text then
          raise exception 'Only the owner can operate a private Build';
        end if;
        if (previous_payload - 'lines' - 'completedAt' - 'updatedAt' - 'shared') <>
           (next_payload - 'lines' - 'completedAt' - 'updatedAt' - 'shared') then
          raise exception 'Build identity and ownership cannot be changed';
        end if;
        if previous_payload->'lines' is distinct from next_payload->'lines' and
           (select jsonb_agg(value - 'usedQuantity' - 'consumedInventoryIds' order by value->>'id')
              from jsonb_array_elements(coalesce(previous_payload->'lines','[]'::jsonb)))
           is distinct from
           (select jsonb_agg(value - 'usedQuantity' - 'consumedInventoryIds' order by value->>'id')
              from jsonb_array_elements(coalesce(next_payload->'lines','[]'::jsonb))) then
          raise exception 'Build requirements cannot be changed while operating a Build';
        end if;
        if previous_payload->'shared' is distinct from next_payload->'shared' and
           (caller_role = 'builder' or previous_payload->>'ownerUserId' is distinct from auth.uid()::text) then
          raise exception 'Only a Build owner with role 1-3 can change sharing';
        end if;
      end if;
      if next_payload->>'completedAt' is not null and exists (
        select 1 from jsonb_array_elements(coalesce(next_payload->'lines','[]'::jsonb)) line
        where coalesce((line->>'usedQuantity')::numeric, 0) <
              coalesce((line->>'requiredQuantity')::numeric, 0)
      ) then raise exception 'Every component must be complete before the Build is completed';
      end if;
    end if;
    next_revision := nextval('public.inventorinator_entity_revision_seq');
    latest_revision := greatest(latest_revision, next_revision);

    insert into public.inventorinator_entities(
      workspace_id, entity_type, entity_id, payload, deleted, revision,
      source_device, updated_by, updated_at
    ) values (
      target_workspace, change_type, change_id, next_payload, change_deleted,
      next_revision, coalesce(source_device, ''), auth.uid(), now()
    ) on conflict(workspace_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      deleted = excluded.deleted,
      revision = excluded.revision,
      source_device = excluded.source_device,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

    -- Maintain the v1.1 snapshot as a compatibility mirror. New clients never
    -- transfer this document; older clients can still read changes made here.
    if change_type = 'workshopMetadata' then
      snapshot := jsonb_strip_nulls(snapshot || change_fields);
    else
      rows := coalesce(snapshot->change_type, '[]'::jsonb);
      select coalesce(jsonb_agg(value), '[]'::jsonb) into rows
      from jsonb_array_elements(rows) value where value->>'id' <> change_id;
      if not change_deleted then rows := rows || jsonb_build_array(next_payload); end if;
      snapshot := jsonb_set(snapshot, array[change_type], rows, true);
    end if;
  end loop;

  if caller_role = 'builder' then
    if exists (
      select 1
      from jsonb_array_elements(coalesce(snapshot->'builds', '[]'::jsonb)) build
      cross join jsonb_array_elements(coalesce(build->'lines', '[]'::jsonb)) line
      where coalesce((line->>'usedQuantity')::numeric, 0) < 0
         or coalesce((line->>'usedQuantity')::numeric, 0) >
            coalesce((line->>'requiredQuantity')::numeric, 0)
         or jsonb_array_length(coalesce(line->'consumedInventoryIds', '[]'::jsonb)) <>
            ceil(coalesce((line->>'usedQuantity')::numeric, 0))::integer
    ) then raise exception 'Build usage is invalid';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(coalesce(snapshot->'builds', '[]'::jsonb)) build
      cross join jsonb_array_elements(coalesce(build->'lines', '[]'::jsonb)) line
      cross join jsonb_array_elements_text(coalesce(line->'consumedInventoryIds', '[]'::jsonb)) consumed(inventory_id)
      where not exists (
        select 1 from jsonb_array_elements(coalesce(snapshot->'inventory', '[]'::jsonb)) item
        where item->>'id' = consumed.inventory_id
          and (
            nullif(item->>'catalogProductId', '') = line->>'productId'
            or regexp_replace(lower(coalesce(item->>'name', '')), '[^a-z0-9]+', '', 'g') =
               regexp_replace(lower(coalesce(line->>'name', '')), '[^a-z0-9]+', '', 'g')
          )
      )
    ) then raise exception 'Build usage references incompatible inventory';
    end if;

    if exists (
      with old_allocations as (
        select consumed.inventory_id,
               sum(greatest(least(coalesce((line->>'usedQuantity')::numeric, 0) -
                 (consumed.position - 1), 1::numeric), 0::numeric)) as amount
        from jsonb_array_elements(coalesce(initial_snapshot->'builds', '[]'::jsonb)) build
        cross join jsonb_array_elements(coalesce(build->'lines', '[]'::jsonb)) line
        cross join jsonb_array_elements_text(coalesce(line->'consumedInventoryIds', '[]'::jsonb))
          with ordinality consumed(inventory_id, position)
        group by consumed.inventory_id
      ), new_allocations as (
        select consumed.inventory_id,
               sum(greatest(least(coalesce((line->>'usedQuantity')::numeric, 0) -
                 (consumed.position - 1), 1::numeric), 0::numeric)) as amount
        from jsonb_array_elements(coalesce(snapshot->'builds', '[]'::jsonb)) build
        cross join jsonb_array_elements(coalesce(build->'lines', '[]'::jsonb)) line
        cross join jsonb_array_elements_text(coalesce(line->'consumedInventoryIds', '[]'::jsonb))
          with ordinality consumed(inventory_id, position)
        group by consumed.inventory_id
      ), old_inventory as (
        select item->>'id' as inventory_id, coalesce((item->>'quantity')::numeric, 1) as quantity
        from jsonb_array_elements(coalesce(initial_snapshot->'inventory', '[]'::jsonb)) item
      ), new_inventory as (
        select item->>'id' as inventory_id, coalesce((item->>'quantity')::numeric, 1) as quantity
        from jsonb_array_elements(coalesce(snapshot->'inventory', '[]'::jsonb)) item
      )
      select 1 from old_inventory old_item
      join new_inventory new_item using (inventory_id)
      left join old_allocations old_used using (inventory_id)
      left join new_allocations new_used using (inventory_id)
      where new_item.quantity < 0 or abs(
        (new_item.quantity - old_item.quantity) +
        (coalesce(new_used.amount, 0) - coalesce(old_used.amount, 0))
      ) > 0.0001
    ) then raise exception 'Inventory quantity changes must exactly match Build use or unuse actions';
    end if;
  end if;

  perform set_config('inventorinator.incremental_snapshot_write', 'on', true);
  insert into public.workshop_states(workspace_id, state_json)
  values(target_workspace, snapshot)
  on conflict(workspace_id) do update set state_json = excluded.state_json, updated_at = now();
  perform set_config('inventorinator.incremental_snapshot_write', 'off', true);

  for event in select value from jsonb_array_elements(coalesce(audit_events, '[]'::jsonb))
  loop
    insert into public.inventorinator_audit_log(
      workspace_id, actor_user_id, actor_role, action, entity_type, entity_id, changes
    ) values (
      target_workspace, auth.uid(), caller_role,
      coalesce(nullif(event->>'action',''), 'sync'),
      coalesce(nullif(event->>'entityType',''), 'workshop'),
      event->>'entityId', coalesce(event->'changes', '{}'::jsonb)
    );
  end loop;
  return latest_revision;
end;
$$;

revoke all on function public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb) from public;
grant execute on function public.apply_inventorinator_entity_changes(uuid,text,jsonb,jsonb) to authenticated;

-- Seed the entity store once from the existing snapshot. Subsequent clients
-- exchange only rows whose revision is newer than their local cursor.
do $$
declare
  source record;
  collection text;
  row_value jsonb;
  metadata jsonb;
begin
  for source in select workspace_id, state_json from public.workshop_states loop
    metadata := source.state_json;
    foreach collection in array array[
      'inventory', 'customItemTypes', 'machineTypes', 'machines', 'kits',
      'builds', 'locations', 'shoppingList', 'auditLog', 'vendors', 'brands',
      'spoolTypes', 'materials', 'products', 'additionHistory'
    ] loop
      for row_value in select value from jsonb_array_elements(coalesce(source.state_json->collection, '[]'::jsonb)) loop
        insert into public.inventorinator_entities(
          workspace_id, entity_type, entity_id, payload
        ) values(source.workspace_id, collection, row_value->>'id', row_value)
        on conflict(workspace_id, entity_type, entity_id) do nothing;
      end loop;
      metadata := metadata - collection;
    end loop;
    insert into public.inventorinator_entities(
      workspace_id, entity_type, entity_id, payload
    ) values(source.workspace_id, 'workshopMetadata', 'singleton', metadata)
    on conflict(workspace_id, entity_type, entity_id) do nothing;
  end loop;
end;
$$;

-- Keep already-released snapshot clients interoperable during upgrades. Their
-- existing role-aware RPC remains authoritative; this trigger translates only
-- the records that actually changed into the v12 entity stream.
create or replace function public.mirror_inventorinator_snapshot_changes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  collection text;
  row_value jsonb;
  old_value jsonb;
  old_state jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else old.state_json end;
  new_metadata jsonb := new.state_json;
  old_metadata jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else old.state_json end;
  next_revision bigint;
begin
  if current_setting('inventorinator.incremental_snapshot_write', true) = 'on' then
    return new;
  end if;
  foreach collection in array array[
    'inventory', 'customItemTypes', 'machineTypes', 'machines', 'kits',
    'builds', 'locations', 'shoppingList', 'auditLog', 'vendors', 'brands',
    'spoolTypes', 'materials', 'products', 'additionHistory'
  ] loop
    for row_value in select value from jsonb_array_elements(coalesce(new.state_json->collection, '[]'::jsonb)) loop
      select value into old_value
      from jsonb_array_elements(coalesce(old_state->collection, '[]'::jsonb)) value
      where value->>'id' = row_value->>'id';
      if old_value is distinct from row_value then
        next_revision := nextval('public.inventorinator_entity_revision_seq');
        insert into public.inventorinator_entities(
          workspace_id, entity_type, entity_id, payload, deleted, revision,
          source_device, updated_by, updated_at
        ) values (
          new.workspace_id, collection, row_value->>'id', row_value, false,
          next_revision, 'legacy-snapshot', auth.uid(), now()
        ) on conflict(workspace_id, entity_type, entity_id) do update set
          payload = excluded.payload, deleted = false,
          revision = excluded.revision, source_device = excluded.source_device,
          updated_by = excluded.updated_by, updated_at = excluded.updated_at;
      end if;
    end loop;

    for row_value in select value from jsonb_array_elements(coalesce(old_state->collection, '[]'::jsonb)) loop
      if not exists (
        select 1 from jsonb_array_elements(coalesce(new.state_json->collection, '[]'::jsonb)) value
        where value->>'id' = row_value->>'id'
      ) then
        next_revision := nextval('public.inventorinator_entity_revision_seq');
        insert into public.inventorinator_entities(
          workspace_id, entity_type, entity_id, payload, deleted, revision,
          source_device, updated_by, updated_at
        ) values (
          new.workspace_id, collection, row_value->>'id', row_value, true,
          next_revision, 'legacy-snapshot', auth.uid(), now()
        ) on conflict(workspace_id, entity_type, entity_id) do update set
          payload = excluded.payload, deleted = true,
          revision = excluded.revision, source_device = excluded.source_device,
          updated_by = excluded.updated_by, updated_at = excluded.updated_at;
      end if;
    end loop;
    new_metadata := new_metadata - collection;
    old_metadata := old_metadata - collection;
  end loop;

  if new_metadata is distinct from old_metadata then
    next_revision := nextval('public.inventorinator_entity_revision_seq');
    insert into public.inventorinator_entities(
      workspace_id, entity_type, entity_id, payload, deleted, revision,
      source_device, updated_by, updated_at
    ) values (
      new.workspace_id, 'workshopMetadata', 'singleton', new_metadata, false,
      next_revision, 'legacy-snapshot', auth.uid(), now()
    ) on conflict(workspace_id, entity_type, entity_id) do update set
      payload = excluded.payload, deleted = false,
      revision = excluded.revision, source_device = excluded.source_device,
      updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
  return new;
end;
$$;

drop trigger if exists mirror_inventorinator_snapshot_changes
on public.workshop_states;
create trigger mirror_inventorinator_snapshot_changes
after insert or update of state_json on public.workshop_states
for each row execute function public.mirror_inventorinator_snapshot_changes();

insert into public.inventorinator_schema(singleton, version) values(true, 12)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
