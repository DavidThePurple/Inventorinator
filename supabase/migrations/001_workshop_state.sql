begin;

create table if not exists public.inventorinator_schema (
  singleton boolean primary key default true check (singleton),
  version integer not null,
  updated_at timestamptz not null default now()
);

alter table public.inventorinator_schema enable row level security;
revoke all on public.inventorinator_schema from anon;
grant select on public.inventorinator_schema to authenticated;

drop policy if exists "authenticated users can read schema version"
on public.inventorinator_schema;
create policy "authenticated users can read schema version"
on public.inventorinator_schema for select
to authenticated
using (true);

create table if not exists public.workshop_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state_json jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.workshop_states enable row level security;

revoke all on public.workshop_states from anon;
grant select, insert, update, delete on public.workshop_states to authenticated;

drop policy if exists "read own workshop" on public.workshop_states;
create policy "read own workshop"
on public.workshop_states for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "create own workshop" on public.workshop_states;
create policy "create own workshop"
on public.workshop_states for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "update own workshop" on public.workshop_states;
create policy "update own workshop"
on public.workshop_states for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "delete own workshop" on public.workshop_states;
create policy "delete own workshop"
on public.workshop_states for delete
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.set_workshop_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_workshop_updated_at on public.workshop_states;
create trigger set_workshop_updated_at
before update on public.workshop_states
for each row execute function public.set_workshop_updated_at();

insert into public.inventorinator_schema (singleton, version)
values (true, 1)
on conflict (singleton) do update set
  version = excluded.version,
  updated_at = now();

commit;
