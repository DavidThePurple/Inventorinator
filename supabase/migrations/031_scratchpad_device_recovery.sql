begin;

alter table public.inventorinator_device_notes
  add column source_device_id text,
  add column restore_pending boolean not null default false,
  add column owner_revision bigint not null default 0,
  add column owner_deleted boolean not null default false;
update public.inventorinator_device_notes n set source_device_id=m.device_id
from public.inventorinator_workspace_members m
where n.workspace_id=m.workspace_id and n.source_user_id=m.user_id;

-- Internal helper. Only trusted membership changes and the authorized recovery
-- RPC may move a note; display names are never identity credentials.
create function public.move_inventorinator_device_note(
  target_workspace uuid, old_user uuid, old_note text, new_user uuid
) returns void language plpgsql security definer set search_path='' as $$
declare n public.inventorinator_device_notes%rowtype;
  m public.inventorinator_workspace_members%rowtype; next_id text;
begin
  select * into m from public.inventorinator_workspace_members
    where workspace_id=target_workspace and user_id=new_user for share;
  if not found then raise exception 'Target device is not a workspace member'; end if;
  select * into n from public.inventorinator_device_notes
    where workspace_id=target_workspace and source_user_id=old_user and note_id=old_note for update;
  if not found then return; end if;
  next_id := n.note_id;
  if old_user <> new_user and exists(select 1 from public.inventorinator_device_notes
    where workspace_id=target_workspace and source_user_id=new_user and note_id=next_id) then
    next_id := 'recovered_' || extensions.gen_random_uuid()::text;
  end if;
  update public.inventorinator_device_notes set source_user_id=new_user,
    note_id=next_id, owner_user_id=new_user, source_device_id=m.device_id,
    source_device_name=m.device_name, transferred_at=null, removed_by_user_id=null,
    restore_pending=true,
    title=case when n.transferred_at is not null then
      regexp_replace(n.title, '^\[Former device: [^]]*\] ', '') else n.title end
  where workspace_id=target_workspace and source_user_id=old_user and note_id=old_note;
end;
$$;
revoke all on function public.move_inventorinator_device_note(uuid,uuid,text,uuid) from public;

create function public.reconcile_inventorinator_device_notes()
returns trigger language plpgsql security definer set search_path='' as $$
declare n record;
begin
  if TG_OP='DELETE' then
    update public.inventorinator_device_notes set source_device_id=old.device_id
      where workspace_id=old.workspace_id and source_user_id=old.user_id
      and old.device_id is not null;
    return old;
  end if;
  for n in select source_user_id,note_id from public.inventorinator_device_notes
    where workspace_id=new.workspace_id
      and ((new.device_id is not null and source_device_id=new.device_id)
        or source_user_id=new.user_id)
      and (source_user_id<>new.user_id or transferred_at is not null)
  loop
    perform public.move_inventorinator_device_note(new.workspace_id,n.source_user_id,n.note_id,new.user_id);
  end loop;
  return new;
end;
$$;
revoke all on function public.reconcile_inventorinator_device_notes() from public;
create trigger remember_scratch_pad_device before delete on public.inventorinator_workspace_members
  for each row execute function public.reconcile_inventorinator_device_notes();
create trigger restore_scratch_pad_device after insert or update of device_id on public.inventorinator_workspace_members
  for each row execute function public.reconcile_inventorinator_device_notes();

create function public.list_inventorinator_recovered_device_notes(target_workspace uuid)
returns setof public.inventorinator_device_notes
language plpgsql security definer set search_path='' as $$
begin
  if public.get_inventorinator_role(target_workspace) is null then raise exception 'Workspace access denied'; end if;
  return query select n.* from public.inventorinator_device_notes n
    where n.workspace_id=target_workspace and n.source_user_id=auth.uid()
      and n.owner_user_id=auth.uid() and n.transferred_at is null and (n.restore_pending or n.owner_revision > 0);
end;
$$;
revoke all on function public.list_inventorinator_recovered_device_notes(uuid) from public;
grant execute on function public.list_inventorinator_recovered_device_notes(uuid) to authenticated;

create function public.restore_inventorinator_removed_device_note(
  target_workspace uuid, source_user uuid, target_note text, target_user uuid
) returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(public.get_inventorinator_role(target_workspace),'') not in ('owner','admin') then
    raise exception 'Administrator access required'; end if;
  perform 1 from public.inventorinator_device_notes where workspace_id=target_workspace
    and source_user_id=source_user and note_id=target_note
    and owner_user_id=auth.uid() and transferred_at is not null for update;
  if not found then raise exception 'Archived note is not available to this administrator'; end if;
  perform public.move_inventorinator_device_note(target_workspace,source_user,target_note,target_user);
end;
$$;
revoke all on function public.restore_inventorinator_removed_device_note(uuid,uuid,text,uuid) from public;
grant execute on function public.restore_inventorinator_removed_device_note(uuid,uuid,text,uuid) to authenticated;

drop function public.backup_inventorinator_device_notes(uuid,jsonb);
create function public.backup_inventorinator_device_notes(
  target_workspace uuid, target_notes jsonb, target_owner_revisions jsonb default '{}'::jsonb
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
    and owner_user_id=auth.uid() and transferred_at is null and not restore_pending and owner_revision=0;
  -- A device may delete an Owner-edited note only after seeing that revision.
  update public.inventorinator_device_notes n set owner_deleted=true,
    owner_revision=n.owner_revision+1, updated_at=clock_timestamp()
  where n.workspace_id=target_workspace and n.source_user_id=auth.uid()
    and n.owner_user_id=auth.uid() and n.transferred_at is null
    and n.owner_revision>0 and not n.owner_deleted
    and coalesce((target_owner_revisions->>n.note_id)::bigint,0)=n.owner_revision
    and not exists(select 1 from jsonb_array_elements(target_notes) v where v->>'id'=n.note_id);
  for row in select value from jsonb_array_elements(target_notes) loop
    if nullif(trim(row->>'id'),'') is null or nullif(trim(row->>'body'),'') is null then
      raise exception 'Each device note needs an id and body';
    end if;
    insert into public.inventorinator_device_notes(
      workspace_id, source_user_id, note_id, owner_user_id, source_device_name,
      title, body, updated_at, is_shared, subject_kind, subject_id, subject_label, source_device_id
    ) values (
      target_workspace, auth.uid(), row->>'id', auth.uid(), current_device_name,
      left(coalesce(nullif(trim(row->>'title'),''),'Untitled note'),120),
      left(trim(row->>'body'),12000), now(), coalesce((row->>'isShared')::boolean, false),
      nullif(left(trim(coalesce(row->>'subjectKind','')),80),''),
      nullif(left(trim(coalesce(row->>'subjectId','')),160),''),
      nullif(left(trim(coalesce(row->>'subjectLabel','')),240),''),
      (select device_id from public.inventorinator_workspace_members where workspace_id=target_workspace and user_id=auth.uid())
    ) on conflict(workspace_id,source_user_id,note_id) do update set
      title=excluded.title, body=excluded.body, updated_at=excluded.updated_at,
      is_shared=excluded.is_shared, subject_kind=excluded.subject_kind,
      subject_id=excluded.subject_id, subject_label=excluded.subject_label,
      restore_pending=false, source_device_name=excluded.source_device_name,
      source_device_id=excluded.source_device_id
    where inventorinator_device_notes.owner_user_id=auth.uid()
      and inventorinator_device_notes.transferred_at is null
      and not inventorinator_device_notes.owner_deleted
      and inventorinator_device_notes.owner_revision=coalesce((row->>'ownerRevision')::bigint,0);
  end loop;
end;
$$;

drop function if exists public.list_inventorinator_removed_device_notes(uuid);
create function public.list_inventorinator_removed_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,transferred_at timestamptz,subject_kind text,subject_id text,subject_label text,source_user_id uuid)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role not in ('owner','admin') then raise exception 'Administrator access required'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.transferred_at,n.subject_kind,n.subject_id,n.subject_label,n.source_user_id
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.owner_user_id=auth.uid()
    and n.transferred_at is not null and not n.owner_deleted
  order by n.transferred_at desc,n.updated_at desc;
end;
$$;


revoke all on function public.list_inventorinator_removed_device_notes(uuid) from public;
grant execute on function public.list_inventorinator_removed_device_notes(uuid) to authenticated;
-- Recover archives for memberships already re-added under the same login.
update public.inventorinator_workspace_members set device_id=device_id;

create or replace function public.list_inventorinator_shared_device_notes(target_workspace uuid)
returns table(note_id text,title text,body text,updated_at timestamptz,source_device_name text,is_shared boolean,subject_kind text,subject_id text,subject_label text)
language plpgsql security definer set search_path = '' as $$
declare caller_role text;
begin
  caller_role := public.get_inventorinator_role(target_workspace);
  if caller_role is null then raise exception 'Workspace access denied'; end if;
  return query select n.note_id,n.title,n.body,n.updated_at,n.source_device_name,n.is_shared,n.subject_kind,n.subject_id,n.subject_label
  from public.inventorinator_device_notes n
  where n.workspace_id=target_workspace and n.is_shared and not n.owner_deleted and n.transferred_at is null
    and n.source_user_id <> auth.uid()
  order by n.updated_at desc;
end;
$$;


revoke all on function public.backup_inventorinator_device_notes(uuid,jsonb,jsonb) from public;
grant execute on function public.backup_inventorinator_device_notes(uuid,jsonb,jsonb) to authenticated;

create function public.list_inventorinator_owner_notes(target_workspace uuid)
returns setof public.inventorinator_device_notes
language plpgsql security definer set search_path='' as $$
begin
  if public.get_inventorinator_role(target_workspace) is distinct from 'owner' then
    raise exception 'Owner access required'; end if;
  return query select n.* from public.inventorinator_device_notes n
    where n.workspace_id=target_workspace and not n.owner_deleted order by n.updated_at desc;
end;
$$;

create function public.manage_inventorinator_note(
  target_workspace uuid, source_user uuid, target_note text,
  expected_updated_at timestamptz, replacement jsonb default null
) returns void language plpgsql security definer set search_path='' as $$
declare n public.inventorinator_device_notes%rowtype;
begin
  -- Share-lock the Owner membership so a concurrent role change cannot race authorization.
  perform 1 from public.inventorinator_workspace_members
    where workspace_id=target_workspace and user_id=auth.uid() and role='owner' for share;
  if not found then raise exception 'Owner access required'; end if;
  select * into n from public.inventorinator_device_notes
    where workspace_id=target_workspace and source_user_id=source_user and note_id=target_note for update;
  if not found or n.owner_deleted then raise exception 'Note is no longer available'; end if;
  if n.updated_at is distinct from expected_updated_at then
    raise exception 'Note changed on another device. Sync and reopen it before editing.'; end if;
  if replacement is not null and (jsonb_typeof(replacement)<>'object' or
    nullif(trim(replacement->>'body'),'') is null) then raise exception 'A note needs a body'; end if;
  update public.inventorinator_device_notes set
    title=case when replacement is null then title else left(coalesce(nullif(trim(replacement->>'title'),''),'Untitled note'),120) end,
    body=case when replacement is null then body else left(trim(replacement->>'body'),12000) end,
    subject_kind=case when replacement is null then subject_kind else nullif(left(replacement->>'subjectKind',80),'') end,
    subject_id=case when replacement is null then subject_id else nullif(left(replacement->>'subjectId',160),'') end,
    subject_label=case when replacement is null then subject_label else nullif(left(replacement->>'subjectLabel',240),'') end,
    -- Owner editing does not silently change the author's sharing choice.
    owner_deleted=(replacement is null), owner_revision=owner_revision+1,
    updated_at=clock_timestamp()
  where workspace_id=target_workspace and source_user_id=source_user and note_id=target_note;
end;
$$;
revoke all on function public.list_inventorinator_owner_notes(uuid) from public;
revoke all on function public.manage_inventorinator_note(uuid,uuid,text,timestamptz,jsonb) from public;
grant execute on function public.list_inventorinator_owner_notes(uuid) to authenticated;
grant execute on function public.manage_inventorinator_note(uuid,uuid,text,timestamptz,jsonb) to authenticated;

insert into public.inventorinator_schema(singleton,version) values(true,31)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
