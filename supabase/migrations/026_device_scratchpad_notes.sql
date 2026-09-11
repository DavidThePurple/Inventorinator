begin;

-- Scratch Pad is local-first. This table is only the per-device backup and
-- the review archive created when an owner or admin removes a device.
create table if not exists public.inventorinator_device_notes (
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  source_user_id uuid not null references auth.users(id) on delete restrict,
  note_id text not null check (note_id ~ '^[A-Za-z0-9_-]{1,120}$'),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  source_device_name text not null,
  title text not null check (char_length(title) <= 120),
  body text not null check (char_length(body) <= 12000),
  updated_at timestamptz not null default now(),
  transferred_at timestamptz,
  removed_by_user_id uuid references auth.users(id) on delete set null,
  primary key (workspace_id, source_user_id, note_id)
);
create index if not exists inventorinator_device_notes_owner
  on public.inventorinator_device_notes(workspace_id, owner_user_id, transferred_at);
alter table public.inventorinator_device_notes enable row level security;
revoke all on public.inventorinator_device_notes from anon, authenticated;

create or replace function public.backup_inventorinator_device_notes(
  target_workspace uuid, target_notes jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare caller_role text; current_device_name text; row jsonb;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  if jsonb_typeof(coalesce(target_notes, '[]'::jsonb)) <> 'array' or jsonb_array_length(target_notes) > 250 then
    raise exception 'Invalid device notes backup';
  end if;
  select device_name into current_device_name from public.inventorinator_workspace_members
  where workspace_id=target_workspace and user_id=auth.uid() for share;
  if current_device_name is null then raise exception 'Workspace access denied'; end if;

  -- A complete local snapshot replaces only the caller's active device notes.
  delete from public.inventorinator_device_notes
  where workspace_id=target_workspace and source_user_id=auth.uid()
    and owner_user_id=auth.uid() and transferred_at is null;
  for row in select value from jsonb_array_elements(target_notes) loop
    if nullif(trim(row->>'id'),'') is null or nullif(trim(row->>'body'),'') is null then
      raise exception 'Each device note needs an id and body';
    end if;
    insert into public.inventorinator_device_notes(
      workspace_id, source_user_id, note_id, owner_user_id, source_device_name,
      title, body, updated_at
    ) values (
      target_workspace, auth.uid(), row->>'id', auth.uid(), current_device_name,
      left(coalesce(nullif(trim(row->>'title'),''),'Untitled note'),120),
      left(trim(row->>'body'),12000), now()
    );
  end loop;
end;
$$;

create or replace function public.list_inventorinator_removed_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,transferred_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner','admin') then raise exception 'Administrator access required'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.transferred_at
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.owner_user_id=auth.uid()
    and n.transferred_at is not null
  order by n.transferred_at desc,n.updated_at desc;
end;
$$;

-- Preserve the durable device-history behavior from v17 while assigning every
-- backed-up note to the administrator who removed the device for review.
create or replace function public.remove_inventorinator_device(
  target_workspace uuid, target_user uuid, lock_out boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
declare caller_role text; victim_role text; victim_device_id text; victim_device_name text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  select role,device_id,device_name into victim_role,victim_device_id,victim_device_name
  from public.inventorinator_workspace_members
  where workspace_id=target_workspace and user_id=target_user for update;
  if caller_role not in ('owner','admin') then raise exception 'Administrator access required'; end if;
  if target_user=auth.uid() or victim_role is null or victim_role='owner' or
     (caller_role='admin' and victim_role='admin') then
    raise exception 'This device cannot be removed';
  end if;
  if lock_out then
    insert into public.inventorinator_blocked_devices(workspace_id,user_id,blocked_by)
    values(target_workspace,target_user,auth.uid()) on conflict do nothing;
  end if;
  if victim_device_id is not null then
    insert into public.inventorinator_device_history(workspace_id,device_id,last_role,blocked)
    values(target_workspace,victim_device_id,victim_role,lock_out)
    on conflict(workspace_id,device_id) do update set
      last_role=excluded.last_role,blocked=excluded.blocked,removed_at=now();
  end if;
  update public.inventorinator_device_notes set
    title='[Former device: ' || left(coalesce(nullif(victim_device_name,''),'Unnamed device'),80) || '] ' || title,
    owner_user_id=auth.uid(), transferred_at=now(), removed_by_user_id=auth.uid()
  where workspace_id=target_workspace and source_user_id=target_user
    and owner_user_id=target_user and transferred_at is null;
  delete from public.inventorinator_workspace_members
  where workspace_id=target_workspace and user_id=target_user;
end;
$$;

revoke all on function public.backup_inventorinator_device_notes(uuid,jsonb) from public;
revoke all on function public.list_inventorinator_removed_device_notes(uuid) from public;
revoke all on function public.remove_inventorinator_device(uuid,uuid,boolean) from public;
grant execute on function public.backup_inventorinator_device_notes(uuid,jsonb) to authenticated;
grant execute on function public.list_inventorinator_removed_device_notes(uuid) to authenticated;
grant execute on function public.remove_inventorinator_device(uuid,uuid,boolean) to authenticated;

insert into public.inventorinator_schema(singleton,version) values(true,26)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
