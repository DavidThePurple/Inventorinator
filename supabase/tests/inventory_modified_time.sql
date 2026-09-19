begin;
insert into auth.users(id) values ('34000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspaces(id,created_by) values ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role) values ('34000000-0000-0000-0000-000000000010','34000000-0000-0000-0000-000000000001','owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','34000000-0000-0000-0000-000000000001',true);
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"part","fields":{"name":"Part","quantity":1,"modifiedAt":"2026-09-19T12:00:00Z"}}]');
-- An older offline edit still applies its content but cannot regress the time.
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','offline','[{"entityType":"inventory","entityId":"part","fields":{"quantity":2,"modifiedAt":"2026-09-19T11:00:00Z"},"baseFields":{"quantity":1}}]');
do $$ begin
 if not exists(select 1 from public.inventorinator_entities where entity_id='part' and workspace_id='34000000-0000-0000-0000-000000000010' and payload->>'modifiedAt'='2026-09-19T12:00:00Z' and payload->>'quantity'='2') then raise exception 'Older edit regressed timestamp or lost content'; end if;
end $$;
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"part","fields":{"modifiedAt":"2026-09-19T13:00:00Z"}}]');
do $$ begin
 if not exists(select 1 from public.inventorinator_entities where entity_id='part' and workspace_id='34000000-0000-0000-0000-000000000010' and payload->>'modifiedAt'='2026-09-19T13:00:00Z') then raise exception 'Newer time not accepted'; end if;
end $$;
select public.apply_inventorinator_entity_changes('34000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"part","deleted":true}]');
do $$ begin
 if not exists(select 1 from public.inventorinator_entities where entity_id='part' and workspace_id='34000000-0000-0000-0000-000000000010' and deleted) then raise exception 'Deletion blocked'; end if;
end $$;
rollback;
