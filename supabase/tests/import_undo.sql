begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000091');
insert into public.inventorinator_workspaces(id,created_by) values ('90000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000091');
insert into public.inventorinator_workspace_members(workspace_id,user_id,role,device_name) values ('90000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000091','owner','Undo test');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
do $$
declare w uuid := '90000000-0000-0000-0000-000000000001'; original jsonb; rejected boolean;
begin
  original := '{"id":"IMPORT-A","name":"Bolt","quantity":2,"image":null}';
  perform public.apply_inventorinator_entity_changes(w,'device',jsonb_build_array(jsonb_build_object('entityType','inventory','entityId','IMPORT-A','fields',original)));
  -- Later remote edits cannot be removed by a stale undo, including a race
  -- occurring after the client's preflight download.
  perform public.apply_inventorinator_entity_changes(w,'other-device','[{"entityType":"inventory","entityId":"IMPORT-A","fields":{"quantity":9}}]');
  rejected := false;
  begin
    perform public.delete_inventorinator_entity(
      w, 'device', 'inventory', 'IMPORT-A', null, original, true
    );
  exception when others then
    if sqlerrm not like 'Sync conflict:%' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Stale import undo erased a newer edit'; end if;
  if (select deleted or payload->>'quantity' <> '9' from public.inventorinator_entities where workspace_id=w and entity_id='IMPORT-A') then raise exception 'Failed undo modified item'; end if;
  -- An unchanged item used by another record is protected too.
  perform public.apply_inventorinator_entity_changes(w,'other-device','[{"entityType":"inventory","entityId":"IMPORT-A","fields":{"quantity":2}},{"entityType":"kits","entityId":"KIT-A","fields":{"name":"Kit","bom":[{"productId":"inventory:IMPORT-A","quantity":1}]}}]');
  rejected := false;
  begin
    perform public.delete_inventorinator_entity(
      w, 'device', 'inventory', 'IMPORT-A', null, original, true
    );
  exception when others then
    if sqlerrm not like 'Sync conflict:%' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Undo erased a referenced item'; end if;
  perform public.delete_inventorinator_entity(
    w, 'device', 'kits', 'KIT-A',
    (select revision from public.inventorinator_entities
      where workspace_id = w and entity_type = 'kits'
        and entity_id = 'KIT-A' and not deleted)
  );
  perform public.delete_inventorinator_entity(
    w, 'device', 'inventory', 'IMPORT-A', null, original, true
  );
  if not (select deleted from public.inventorinator_entities where workspace_id=w and entity_id='IMPORT-A') then raise exception 'Eligible undo did not delete'; end if;
  -- Replaying an acknowledged undo is harmless.
  perform public.delete_inventorinator_entity(
    w, 'device', 'inventory', 'IMPORT-A', null, original, true
  );
  -- Ordinary deletes use the dedicated server-owned operation, while imports
  -- keep their separately guarded undo path.
  perform public.apply_inventorinator_entity_changes(
    w, 'device',
    '[{"entityType":"inventory","entityId":"IMPORT-B","fields":{"quantity":5}}]'
  );
  perform public.delete_inventorinator_entity(
    w, 'device', 'inventory', 'IMPORT-B',
    (select revision from public.inventorinator_entities
      where workspace_id = w and entity_type = 'inventory'
        and entity_id = 'IMPORT-B' and not deleted)
  );
  if not (select deleted from public.inventorinator_entities where workspace_id=w and entity_id='IMPORT-B') then raise exception 'Ordinary deletion regressed'; end if;
end; $$;
rollback;
