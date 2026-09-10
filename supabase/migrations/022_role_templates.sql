begin;

-- Draft definitions only. Memberships and live authorization remain unchanged.
create table if not exists public.inventorinator_role_templates (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 60),
  description text not null default '' check (length(description) <= 240),
  permissions text[] not null,
  updated_at timestamptz not null default now(),
  check (lower(btrim(name)) not in ('owner', 'admin', 'manager', 'editor', 'builder')),
  check (permissions @> array['inventory.read']::text[]),
  check (array_position(permissions, null) is null),
  check (permissions <@ array[
    'inventory.read', 'inventory.create', 'inventory.edit', 'inventory.archive',
    'inventory.delete', 'catalog.manage', 'builds.create', 'builds.share',
    'builds.operate', 'devices.manage', 'database.delete'
  ]::text[])
);
create unique index if not exists inventorinator_role_template_names
  on public.inventorinator_role_templates(workspace_id, lower(btrim(name)));
alter table public.inventorinator_role_templates enable row level security;
revoke all on public.inventorinator_role_templates from public, anon, authenticated;

create or replace function public.list_inventorinator_role_templates(target_workspace uuid)
returns setof public.inventorinator_role_templates
language plpgsql security definer set search_path = '' as $$
begin
  if public.get_inventorinator_role(target_workspace) is distinct from 'owner' then
    raise exception 'Only the owner can manage role templates';
  end if;
  return query select * from public.inventorinator_role_templates
    where workspace_id = target_workspace order by lower(name), id;
end;
$$;

create or replace function public.save_inventorinator_role_template(
  target_workspace uuid, target_id uuid, target_name text,
  target_description text, target_permissions text[]
) returns uuid language plpgsql security definer set search_path = '' as $$
declare saved_id uuid; normalized_permissions text[];
begin
  -- Lock membership while authorizing so ownership cannot change mid-write.
  perform 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid() and role = 'owner'
    for update;
  if not found then raise exception 'Only the owner can manage role templates'; end if;
  if target_name is null or length(btrim(target_name)) not between 1 and 60 then
    raise exception 'Use a role name between 1 and 60 characters';
  end if;
  if lower(btrim(target_name)) in ('owner', 'admin', 'manager', 'editor', 'builder') then
    raise exception 'Choose a name different from the built-in roles';
  end if;
  if length(coalesce(target_description, '')) > 240 then
    raise exception 'Keep the description within 240 characters';
  end if;
  if target_permissions is null or array_position(target_permissions, null) is not null
    or not (target_permissions @> array['inventory.read']::text[])
    or not (target_permissions <@ array[
      'inventory.read', 'inventory.create', 'inventory.edit', 'inventory.archive',
      'inventory.delete', 'catalog.manage', 'builds.create', 'builds.share',
      'builds.operate', 'devices.manage', 'database.delete'
    ]::text[]) then
    raise exception 'Invalid role permissions';
  end if;
  select array_agg(distinct p order by p) into normalized_permissions
    from unnest(target_permissions) p;
  if target_id is null then
    insert into public.inventorinator_role_templates(workspace_id, name, description, permissions)
      values(target_workspace, btrim(target_name), btrim(coalesce(target_description, '')), normalized_permissions)
      returning id into saved_id;
  else
    update public.inventorinator_role_templates
      set name = btrim(target_name), description = btrim(coalesce(target_description, '')),
          permissions = normalized_permissions, updated_at = now()
      where workspace_id = target_workspace and id = target_id returning id into saved_id;
    if not found then raise exception 'Role template not found'; end if;
  end if;
  return saved_id;
exception when unique_violation then
  raise exception 'A role template with that name already exists';
end;
$$;

create or replace function public.delete_inventorinator_role_template(
  target_workspace uuid, target_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.inventorinator_workspace_members
    where workspace_id = target_workspace and user_id = auth.uid() and role = 'owner'
    for update;
  if not found then raise exception 'Only the owner can manage role templates'; end if;
  delete from public.inventorinator_role_templates
    where workspace_id = target_workspace and id = target_id;
  if not found then raise exception 'Role template not found'; end if;
end;
$$;

revoke all on function public.list_inventorinator_role_templates(uuid) from public;
revoke all on function public.save_inventorinator_role_template(uuid, uuid, text, text, text[]) from public;
revoke all on function public.delete_inventorinator_role_template(uuid, uuid) from public;
grant execute on function public.list_inventorinator_role_templates(uuid) to authenticated;
grant execute on function public.save_inventorinator_role_template(uuid, uuid, text, text, text[]) to authenticated;
grant execute on function public.delete_inventorinator_role_template(uuid, uuid) to authenticated;

insert into public.inventorinator_schema(singleton, version) values(true, 22)
on conflict(singleton) do update set version = excluded.version, updated_at = now();
notify pgrst, 'reload schema';
commit;
