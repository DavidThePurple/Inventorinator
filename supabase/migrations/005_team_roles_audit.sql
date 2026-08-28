begin;

alter table public.inventorinator_workspace_members
  drop constraint if exists inventorinator_workspace_members_role_check;
update public.inventorinator_workspace_members set role = 'builder' where role = 'member';
alter table public.inventorinator_workspace_members alter column role set default 'builder';
alter table public.inventorinator_workspace_members
  add constraint inventorinator_workspace_members_role_check
  check (role in ('owner', 'admin', 'manager', 'editor', 'builder'));

create table if not exists public.inventorinator_audit_log (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  actor_role text not null,
  action text not null,
  entity_type text not null,
  entity_id text,
  changes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists inventorinator_audit_workspace_created
  on public.inventorinator_audit_log(workspace_id, created_at desc);
alter table public.inventorinator_audit_log enable row level security;
revoke all on public.inventorinator_audit_log from anon, authenticated;

create or replace function public.inventorinator_role(target_workspace uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case role when 'owner' then 'admin' else role end
  from public.inventorinator_workspace_members
  where workspace_id = target_workspace and user_id = auth.uid();
$$;

create or replace function public.set_inventorinator_device_role(
  target_workspace uuid, target_user uuid, target_role text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.get_inventorinator_role(target_workspace) <> 'owner' then
    raise exception 'Only the shared inventory owner can assign roles';
  end if;
  if target_role not in ('admin', 'manager', 'editor', 'builder') then
    raise exception 'Invalid role';
  end if;
  update public.inventorinator_workspace_members set role = target_role
  where workspace_id = target_workspace and user_id = target_user and role <> 'owner';
end;
$$;

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
    if (previous_state - 'inventory' - 'auditLog') <> (next_state - 'inventory' - 'auditLog') then
      raise exception 'Editors may only edit existing inventory items';
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
      raise exception 'Builders may only operate Builds';
    end if;
    if (select jsonb_agg(value - 'quantity' order by value->>'id') from jsonb_array_elements(coalesce(previous_state->'inventory','[]'::jsonb)))
       is distinct from
       (select jsonb_agg(value - 'quantity' order by value->>'id') from jsonb_array_elements(coalesce(next_state->'inventory','[]'::jsonb))) then
      raise exception 'Builders cannot directly edit inventory';
    end if;
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

create or replace function public.list_inventorinator_audit_log(
  target_workspace uuid, result_limit integer default 100
) returns setof public.inventorinator_audit_log
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.inventorinator_role(target_workspace) is null then
    raise exception 'Workspace access denied';
  end if;
  return query select * from public.inventorinator_audit_log
  where workspace_id = target_workspace
  order by created_at desc limit least(greatest(result_limit, 1), 2000);
end;
$$;

drop policy if exists "members create workshop" on public.workshop_states;
drop policy if exists "members update workshop" on public.workshop_states;
drop policy if exists "members delete workshop" on public.workshop_states;
revoke insert, update, delete on public.workshop_states from authenticated;

revoke all on function public.inventorinator_role(uuid) from public;
revoke all on function public.save_inventorinator_workshop_state(uuid,jsonb,jsonb) from public;
revoke all on function public.list_inventorinator_audit_log(uuid,integer) from public;
grant execute on function public.inventorinator_role(uuid) to authenticated;
grant execute on function public.save_inventorinator_workshop_state(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.list_inventorinator_audit_log(uuid,integer) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 5)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
