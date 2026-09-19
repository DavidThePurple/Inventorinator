begin;
insert into auth.users(id) values
 ('33000000-0000-0000-0000-000000000001'),
 ('33000000-0000-0000-0000-000000000002');
insert into public.inventorinator_workspaces(id,created_by) values
 ('33000000-0000-0000-0000-000000000010','33000000-0000-0000-0000-000000000001');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role) values
 ('33000000-0000-0000-0000-000000000010','33000000-0000-0000-0000-000000000001','owner'),
 ('33000000-0000-0000-0000-000000000010','33000000-0000-0000-0000-000000000002','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000002',true);
do $$ begin
 if public.get_inventorinator_manual_drying('33000000-0000-0000-0000-000000000010') then raise exception 'Automatic must be default'; end if;
 begin
 perform public.set_inventorinator_manual_drying('33000000-0000-0000-0000-000000000010',true);
 raise exception 'Admin changed Owner policy';
 exception when others then if sqlerrm <> 'Only the workspace Owner can change drying policy' then raise; end if; end;
end $$;
select public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"spool","fields":{"type":"filament","filamentStatus":"drying","dryingStartedAt":"2026-09-19T00:00:00Z","dryingRemaining":360}}]');
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000001',true);
select public.set_inventorinator_manual_drying('33000000-0000-0000-0000-000000000010',true);
-- Existing cycles and unrelated item edits may continue.
select public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"spool","fields":{"name":"Renamed while drying"}}]');
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000002',true);
do $$ begin
 if not public.get_inventorinator_manual_drying('33000000-0000-0000-0000-000000000010') then raise exception 'Policy not shared'; end if;
 begin
 perform public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"spool","fields":{"dryingStartedAt":"2026-09-19T01:00:00Z"}}]');
 raise exception 'Restart bypassed manual policy';
 exception when others then if sqlerrm <> 'The workspace Owner requires a manual drying time before starting drying' then raise; end if; end;
 begin
 perform public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"new-spool","fields":{"type":"filament","filamentStatus":"drying","dryingMinutes":0}}]');
 raise exception 'Zero manual time accepted';
 exception when others then if sqlerrm <> 'The workspace Owner requires a manual drying time before starting drying' then raise; end if; end;
end $$;
select public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"spool","fields":{"dryingStartedAt":"2026-09-19T01:00:00Z","dryingMinutes":120}}]');
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000001',true);
select public.set_inventorinator_manual_drying('33000000-0000-0000-0000-000000000010',false);
select public.apply_inventorinator_entity_changes('33000000-0000-0000-0000-000000000010','test','[{"entityType":"inventory","entityId":"new-spool","fields":{"type":"filament","filamentStatus":"drying","dryingRemaining":360}}]');
rollback;
