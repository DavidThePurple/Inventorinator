begin;

create or replace function public.save_inventorinator_workshop_state(
  target_workspace uuid,
  next_state jsonb,
  audit_events jsonb default '[]'::jsonb
) returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  member_role text;
  previous_state jsonb;
  saved_at timestamptz;
  event jsonb;
  old_build jsonb;
  new_build jsonb;
  owns_build boolean;
begin
  member_role := public.inventorinator_role(target_workspace);
  if member_role is null then raise exception 'Workspace access denied'; end if;

  select state_json into previous_state from public.workshop_states
  where workspace_id = target_workspace for update;
  previous_state := coalesce(previous_state, '{}'::jsonb);

  if member_role = 'manager' and exists (
    select 1 from jsonb_array_elements(coalesce(previous_state->'inventory', '[]'::jsonb)) old_item
    where not exists (
      select 1 from jsonb_array_elements(coalesce(next_state->'inventory', '[]'::jsonb)) new_item
      where new_item->>'id' = old_item->>'id'
    )
  ) then raise exception 'Managers may archive or decommission items, not permanently delete them';
  end if;

  if member_role = 'editor' then
    if (previous_state - 'inventory' - 'builds' - 'auditLog') <>
       (next_state - 'inventory' - 'builds' - 'auditLog') then
      raise exception 'Editors may only edit inventory and operate Builds';
    end if;
    if (select array_agg(value->>'id' order by value->>'id') from jsonb_array_elements(coalesce(previous_state->'inventory','[]'::jsonb)))
       is distinct from
       (select array_agg(value->>'id' order by value->>'id') from jsonb_array_elements(coalesce(next_state->'inventory','[]'::jsonb))) then
      raise exception 'Editors cannot add or remove inventory items';
    end if;
  end if;

  if member_role = 'builder' then
    if (previous_state - 'inventory' - 'builds' - 'auditLog') <>
       (next_state - 'inventory' - 'builds' - 'auditLog') then
      raise exception 'Builders may only operate shared Builds';
    end if;
    if (select jsonb_agg(value - 'quantity' order by value->>'id') from jsonb_array_elements(coalesce(previous_state->'inventory','[]'::jsonb)))
       is distinct from
       (select jsonb_agg(value - 'quantity' order by value->>'id') from jsonb_array_elements(coalesce(next_state->'inventory','[]'::jsonb))) then
      raise exception 'Builders cannot directly edit inventory';
    end if;
    if (select array_agg(value->>'id' order by value->>'id') from jsonb_array_elements(coalesce(previous_state->'builds','[]'::jsonb)))
       is distinct from
       (select array_agg(value->>'id' order by value->>'id') from jsonb_array_elements(coalesce(next_state->'builds','[]'::jsonb))) then
      raise exception 'Builders cannot create or remove Builds';
    end if;
  end if;

  if member_role in ('editor', 'builder') then
    if member_role = 'editor' and exists (
      select 1 from jsonb_array_elements(coalesce(previous_state->'builds','[]'::jsonb)) old_row
      where not exists (
        select 1 from jsonb_array_elements(coalesce(next_state->'builds','[]'::jsonb)) new_row
        where new_row->>'id' = old_row->>'id'
      )
    ) then raise exception 'Editors cannot remove Builds';
    end if;

    for new_build in select value from jsonb_array_elements(coalesce(next_state->'builds','[]'::jsonb))
    loop
      select value into old_build
      from jsonb_array_elements(coalesce(previous_state->'builds','[]'::jsonb))
      where value->>'id' = new_build->>'id';

      if old_build is null then
        if member_role = 'builder' then raise exception 'Builders cannot create Builds'; end if;
        if new_build->>'ownerUserId' is distinct from auth.uid()::text then
          raise exception 'A new Build must belong to its creator';
        end if;
        continue;
      end if;
      if old_build = new_build then continue; end if;

      owns_build := old_build->>'ownerUserId' = auth.uid()::text;
      if coalesce((old_build->>'shared')::boolean, false) is not true and not owns_build then
        raise exception 'Only the owner can operate a private Build';
      end if;

      if (old_build - 'lines' - 'completedAt' - 'updatedAt' - 'shared') <>
         (new_build - 'lines' - 'completedAt' - 'updatedAt' - 'shared') then
        raise exception 'Build identity and ownership cannot be changed';
      end if;
      if old_build->'lines' is distinct from new_build->'lines' then
        if (select jsonb_agg(value - 'usedQuantity' - 'consumedInventoryIds' order by value->>'id')
            from jsonb_array_elements(coalesce(old_build->'lines','[]'::jsonb)))
           is distinct from
           (select jsonb_agg(value - 'usedQuantity' - 'consumedInventoryIds' order by value->>'id')
            from jsonb_array_elements(coalesce(new_build->'lines','[]'::jsonb))) then
          raise exception 'Build requirements cannot be changed while operating a Build';
        end if;
      end if;
      if old_build->'shared' is distinct from new_build->'shared' and
         (member_role = 'builder' or not owns_build) then
        raise exception 'Only a Build owner with role 1-3 can change sharing';
      end if;
      if new_build->>'completedAt' is not null and exists (
        select 1 from jsonb_array_elements(coalesce(new_build->'lines','[]'::jsonb)) line
        where coalesce((line->>'usedQuantity')::numeric, 0) <
              coalesce((line->>'requiredQuantity')::numeric, 0)
      ) then raise exception 'Every component must be complete before the Build is completed';
      end if;
    end loop;
  end if;

  insert into public.workshop_states(workspace_id, state_json)
  values(target_workspace, next_state)
  on conflict(workspace_id) do update set state_json = excluded.state_json, updated_at = now()
  returning updated_at into saved_at;

  if jsonb_array_length(coalesce(audit_events, '[]'::jsonb)) = 0 then
    audit_events := '[{"action":"sync","entityType":"workshop","changes":{}}]'::jsonb;
  end if;
  for event in select value from jsonb_array_elements(audit_events)
  loop
    insert into public.inventorinator_audit_log(
      workspace_id, actor_user_id, actor_role, action, entity_type, entity_id, changes
    ) values (
      target_workspace, auth.uid(), member_role,
      coalesce(nullif(event->>'action',''), 'sync'),
      coalesce(nullif(event->>'entityType',''), 'workshop'),
      event->>'entityId', coalesce(event->'changes', '{}'::jsonb)
    );
  end loop;
  return saved_at;
end;
$$;

revoke all on function public.save_inventorinator_workshop_state(uuid,jsonb,jsonb) from public;
grant execute on function public.save_inventorinator_workshop_state(uuid,jsonb,jsonb) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 6)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
