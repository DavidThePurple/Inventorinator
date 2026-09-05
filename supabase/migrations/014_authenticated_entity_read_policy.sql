begin;

-- Membership rows are intentionally private. The original entity read policy
-- queried that table as the authenticated caller, so PostgreSQL rejected
-- otherwise-valid incremental sync reads. Check membership through the
-- existing security-definer role function instead.
drop policy if exists "members read inventorinator entities"
on public.inventorinator_entities;
create policy "members read inventorinator entities"
on public.inventorinator_entities for select to authenticated
using (public.get_inventorinator_role(workspace_id) is not null);

insert into public.inventorinator_schema(singleton, version) values(true, 14)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
