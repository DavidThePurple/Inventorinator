begin;

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000031'),
  ('00000000-0000-0000-0000-000000000032'),
  ('00000000-0000-0000-0000-000000000033');

insert into public.inventorinator_workspaces(id, created_by) values
  ('30000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000031'),
  ('30000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000033');
insert into public.inventorinator_workspace_members(workspace_id, user_id, role)
values
  ('30000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000031', 'owner'),
  ('30000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000033', 'owner');
insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash)
values (
  '30000000-0000-0000-0000-000000000011',
  extensions.digest('DURABLE-RECOVERY-KEY', 'sha256')
);
insert into public.workshop_states(workspace_id, state_json) values (
  '30000000-0000-0000-0000-000000000011',
  '{"inventory":[{"id":"INV-SAFE"}],"builds":[]}'::jsonb
);

delete from auth.users where id = '00000000-0000-0000-0000-000000000031';

do $$
begin
  if not exists (
    select 1 from public.inventorinator_workspaces
    where id = '30000000-0000-0000-0000-000000000011' and created_by is null
  ) then raise exception 'deleting an auth owner deleted or retained ownership on the workspace'; end if;
  if not exists (
    select 1 from public.workshop_states
    where workspace_id = '30000000-0000-0000-0000-000000000011'
      and state_json->'inventory'->0->>'id' = 'INV-SAFE'
  ) then raise exception 'deleting an auth owner deleted the inventory state'; end if;
  if not exists (
    select 1 from public.inventorinator_workspace_recovery
    where workspace_id = '30000000-0000-0000-0000-000000000011'
  ) then raise exception 'deleting an auth owner deleted recovery access'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', false);
select public.recover_inventorinator_workspace(
  '30000000-0000-0000-0000-000000000011',
  'DURABLE-RECOVERY-KEY',
  'Replacement owner'
);

do $$
begin
  if not exists (
    select 1 from public.inventorinator_workspace_members
    where workspace_id = '30000000-0000-0000-0000-000000000011'
      and user_id = '00000000-0000-0000-0000-000000000032'
      and role = 'owner'
  ) then raise exception 'recovery did not restore an owner'; end if;
  if not exists (
    select 1 from public.workshop_states
    where workspace_id = '30000000-0000-0000-0000-000000000011'
      and state_json->'inventory'->0->>'id' = 'INV-SAFE'
  ) then raise exception 'recovery did not preserve inventory state'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000033', false);
do $$
declare first_key text; second_key text;
begin
  first_key := public.ensure_inventorinator_recovery_key(
    '30000000-0000-0000-0000-000000000012'
  );
  second_key := public.ensure_inventorinator_recovery_key(
    '30000000-0000-0000-0000-000000000012'
  );
  if first_key is null then raise exception 'missing recovery key was not provisioned'; end if;
  if second_key is not null then raise exception 'existing recovery key was exposed or rotated'; end if;
end;
$$;

rollback;
