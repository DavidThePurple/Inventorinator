begin;

-- Notes may point at one local workshop record. The display label is retained
-- with the link so historical notes remain readable if that record is removed.
alter table public.inventorinator_device_notes
  add column if not exists subject_kind text,
  add column if not exists subject_id text,
  add column if not exists subject_label text;

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
      title, body, updated_at, is_shared, subject_kind, subject_id, subject_label
    ) values (
      target_workspace, auth.uid(), row->>'id', auth.uid(), current_device_name,
      left(coalesce(nullif(trim(row->>'title'),''),'Untitled note'),120),
      left(trim(row->>'body'),12000), now(), coalesce((row->>'isShared')::boolean, false),
      nullif(left(trim(coalesce(row->>'subjectKind','')),80),''),
      nullif(left(trim(coalesce(row->>'subjectId','')),160),''),
      nullif(left(trim(coalesce(row->>'subjectLabel','')),240),'')
    );
  end loop;
end;
$$;

-- PostgreSQL cannot change a function's OUT-column signature in place.
drop function if exists public.list_inventorinator_removed_device_notes(uuid);
create function public.list_inventorinator_removed_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,transferred_at timestamptz,subject_kind text,subject_id text,subject_label text)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner','admin') then raise exception 'Administrator access required'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.transferred_at,n.subject_kind,n.subject_id,n.subject_label
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.owner_user_id=auth.uid()
    and n.transferred_at is not null
  order by n.transferred_at desc,n.updated_at desc;
end;
$$;

drop function if exists public.list_inventorinator_shared_device_notes(uuid);
create function public.list_inventorinator_shared_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,is_shared boolean,subject_kind text,subject_id text,subject_label text)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.is_shared,n.subject_kind,n.subject_id,n.subject_label
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.is_shared and n.transferred_at is null
    and n.source_user_id <> auth.uid()
  order by n.updated_at desc;
end;
$$;

revoke all on function public.backup_inventorinator_device_notes(uuid,jsonb) from public;
revoke all on function public.list_inventorinator_removed_device_notes(uuid) from public;
revoke all on function public.list_inventorinator_shared_device_notes(uuid) from public;
grant execute on function public.backup_inventorinator_device_notes(uuid,jsonb) to authenticated;
grant execute on function public.list_inventorinator_removed_device_notes(uuid) to authenticated;
grant execute on function public.list_inventorinator_shared_device_notes(uuid) to authenticated;

insert into public.inventorinator_schema(singleton,version) values(true,28)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
