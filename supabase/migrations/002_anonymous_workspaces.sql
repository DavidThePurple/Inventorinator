begin;

create table if not exists public.inventorinator_workspaces (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.inventorinator_workspace_members (
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

insert into public.inventorinator_workspaces (id, created_by)
select user_id, user_id from public.workshop_states
on conflict (id) do nothing;

insert into public.inventorinator_workspace_members (workspace_id, user_id, role)
select user_id, user_id, 'owner' from public.workshop_states
on conflict (workspace_id, user_id) do nothing;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'workshop_states'
      and column_name = 'user_id'
  ) then
    alter table public.workshop_states
      drop constraint if exists workshop_states_user_id_fkey;
    alter table public.workshop_states rename column user_id to workspace_id;
    alter table public.workshop_states
      add constraint workshop_states_workspace_id_fkey
      foreign key (workspace_id)
      references public.inventorinator_workspaces(id)
      on delete cascade;
  end if;
end;
$$;

create or replace function public.is_inventorinator_member(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.inventorinator_workspace_members
    where workspace_id = target_workspace
      and user_id = (select auth.uid())
  );
$$;

drop policy if exists "read own workshop" on public.workshop_states;
drop policy if exists "create own workshop" on public.workshop_states;
drop policy if exists "update own workshop" on public.workshop_states;
drop policy if exists "delete own workshop" on public.workshop_states;

create policy "members read workshop"
on public.workshop_states for select
to authenticated
using (public.is_inventorinator_member(workspace_id));

create policy "members create workshop"
on public.workshop_states for insert
to authenticated
with check (public.is_inventorinator_member(workspace_id));

create policy "members update workshop"
on public.workshop_states for update
to authenticated
using (public.is_inventorinator_member(workspace_id))
with check (public.is_inventorinator_member(workspace_id));

create policy "members delete workshop"
on public.workshop_states for delete
to authenticated
using (public.is_inventorinator_member(workspace_id));

alter table public.inventorinator_workspaces enable row level security;
alter table public.inventorinator_workspace_members enable row level security;
revoke all on public.inventorinator_workspaces from anon, authenticated;
revoke all on public.inventorinator_workspace_members from anon, authenticated;

create table if not exists public.inventorinator_pairing_codes (
  code_hash bytea primary key,
  workspace_id uuid not null references public.inventorinator_workspaces(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.inventorinator_pairing_codes enable row level security;
revoke all on public.inventorinator_pairing_codes from anon, authenticated;

create or replace function public.create_inventorinator_workspace()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  new_workspace_id uuid := gen_random_uuid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  insert into public.inventorinator_workspaces (id, created_by)
  values (new_workspace_id, current_user_id);
  insert into public.inventorinator_workspace_members (workspace_id, user_id, role)
  values (new_workspace_id, current_user_id, 'owner');
  return new_workspace_id;
end;
$$;

create or replace function public.create_inventorinator_pairing_code(
  target_workspace uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  new_code text := upper(
    substr(encode(extensions.gen_random_bytes(9), 'hex'), 1, 12)
  );
begin
  if not public.is_inventorinator_member(target_workspace) then
    raise exception 'Workspace access denied';
  end if;
  delete from public.inventorinator_pairing_codes
  where expires_at < now() or used_at is not null;
  insert into public.inventorinator_pairing_codes (
    code_hash, workspace_id, created_by, expires_at
  ) values (
    extensions.digest(new_code, 'sha256'), target_workspace, current_user_id,
    now() + interval '10 minutes'
  );
  return new_code;
end;
$$;

create or replace function public.redeem_inventorinator_pairing_code(
  pairing_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  matched public.inventorinator_pairing_codes%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  select * into matched
  from public.inventorinator_pairing_codes
  where code_hash = extensions.digest(upper(trim(pairing_code)), 'sha256')
    and used_at is null
    and expires_at > now()
  for update;
  if not found then
    raise exception 'Pairing code is invalid or expired';
  end if;
  insert into public.inventorinator_workspace_members (workspace_id, user_id)
  values (matched.workspace_id, current_user_id)
  on conflict (workspace_id, user_id) do nothing;
  update public.inventorinator_pairing_codes
  set used_at = now()
  where code_hash = matched.code_hash;
  return matched.workspace_id;
end;
$$;

revoke all on function public.create_inventorinator_workspace() from public;
revoke all on function public.create_inventorinator_pairing_code(uuid) from public;
revoke all on function public.redeem_inventorinator_pairing_code(text) from public;
grant execute on function public.create_inventorinator_workspace() to authenticated;
grant execute on function public.create_inventorinator_pairing_code(uuid) to authenticated;
grant execute on function public.redeem_inventorinator_pairing_code(text) to authenticated;

insert into public.inventorinator_schema (singleton, version)
values (true, 2)
on conflict (singleton) do update set
  version = excluded.version,
  updated_at = now();

commit;
