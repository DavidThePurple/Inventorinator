begin;

-- Self-hosted Supabase commonly gives the authenticated role an 8 second
-- statement timeout. Incremental sync rewrites the compatibility snapshot in
-- the same transaction, so a legitimate inventory edit can exceed that limit
-- on larger workspaces. Keep the limit scoped to this RPC rather than
-- weakening the timeout for every authenticated request.
alter function public.apply_inventorinator_entity_changes(uuid, text, jsonb, jsonb)
  set statement_timeout = '45s';
alter function public.apply_inventorinator_entity_changes(uuid, text, jsonb, jsonb)
  set lock_timeout = '30s';

notify pgrst, 'reload schema';

insert into public.inventorinator_schema(singleton, version)
values(true, 20)
on conflict(singleton) do update set version = excluded.version, updated_at = now();

commit;
