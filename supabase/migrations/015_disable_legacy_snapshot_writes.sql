begin;

-- Incremental entity sync is now authoritative. Older clients can continue to
-- read their last compatibility snapshot, but must not replace current state
-- with a stale whole-database document.
create or replace function public.save_inventorinator_workshop_state(
  target_workspace uuid,
  next_state jsonb,
  audit_events jsonb default '[]'::jsonb
) returns timestamptz language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'This Inventorinator client must be updated before syncing changes.';
end;
$$;

insert into public.inventorinator_schema(singleton, version) values(true, 15)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
