begin;
-- Concurrent edits can touch different fields. A timestamp is merge metadata,
-- not a conflicting user field, and an older offline edit must not move it back.
create function public.preserve_inventorinator_modified_time()
returns trigger language plpgsql security definer set search_path='' as $$
declare old_time timestamptz; new_time timestamptz;
begin
  if new.entity_type <> 'inventory' or new.deleted then return new; end if;
  begin old_time := (old.payload->>'modifiedAt')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow then old_time := null; end;
  begin new_time := (new.payload->>'modifiedAt')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow then new_time := null; end;
  if old_time is not null and (new_time is null or old_time > new_time) then
    new.payload := jsonb_set(new.payload,'{modifiedAt}',old.payload->'modifiedAt');
  end if;
  return new;
end;
$$;
revoke all on function public.preserve_inventorinator_modified_time() from public;
create trigger preserve_inventory_modified_time before update on public.inventorinator_entities
for each row execute function public.preserve_inventorinator_modified_time();
insert into public.inventorinator_schema(singleton,version) values(true,33)
on conflict(singleton) do update set version=excluded.version,updated_at=now();
notify pgrst, 'reload schema';
commit;
