begin;

-- Every note stays in its device-private backup. This flag controls the
-- separate, opt-in workspace view.
alter table public.inventorinator_device_notes
  add column if not exists is_shared boolean not null default false;
create index if not exists inventorinator_device_notes_shared
  on public.inventorinator_device_notes(workspace_id, is_shared, source_user_id)
  where transferred_at is null and is_shared;

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

  delete from public.inventorinator_device_notes
  where workspace_id=target_workspace and source_user_id=auth.uid()
    and owner_user_id=auth.uid() and transferred_at is null;
  for row in select value from jsonb_array_elements(target_notes) loop
    if nullif(trim(row->>'id'),'') is null or nullif(trim(row->>'body'),'') is null then
      raise exception 'Each device note needs an id and body';
    end if;
    insert into public.inventorinator_device_notes(
      workspace_id, source_user_id, note_id, owner_user_id, source_device_name,
      title, body, updated_at, is_shared
    ) values (
      target_workspace, auth.uid(), row->>'id', auth.uid(), current_device_name,
      left(coalesce(nullif(trim(row->>'title'),''),'Untitled note'),120),
      left(trim(row->>'body'),12000), now(), coalesce((row->>'isShared')::boolean, false)
    );
  end loop;
end;
$$;

create or replace function public.list_inventorinator_shared_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,is_shared boolean)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.is_shared
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.is_shared and n.transferred_at is null
    and n.source_user_id <> auth.uid()
  order by n.updated_at desc;
end;
$$;

revoke all on function public.list_inventorinator_shared_device_notes(uuid) from public;
grant execute on function public.list_inventorinator_shared_device_notes(uuid) to authenticated;

insert into public.inventorinator_schema(singleton,version) values(true,27)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
