#!/usr/bin/env sh
set -eu

container=${SUPABASE_DB_CONTAINER:-inventorinator-owner-resilience-test}
workspace=30000000-0000-0000-0000-000000000031
old_owner=00000000-0000-0000-0000-000000000051
winner=00000000-0000-0000-0000-000000000052
loser=00000000-0000-0000-0000-000000000053
output_dir=$(mktemp -d)

run_psql() {
  docker exec "$container" psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 "$@"
}

cleanup() {
  run_psql -qAtc "delete from public.inventorinator_workspaces where id = '$workspace'; delete from auth.users where id in ('$old_owner', '$winner', '$loser');" >/dev/null 2>&1 || true
  rm -rf -- "$output_dir"
}
trap cleanup EXIT HUP INT TERM

run_psql -qAtc "
  insert into auth.users(id) values ('$old_owner'), ('$winner'), ('$loser');
  insert into public.inventorinator_workspaces(id, created_by) values ('$workspace', '$old_owner');
  insert into public.inventorinator_workspace_members(workspace_id, user_id, role) values ('$workspace', '$old_owner', 'owner');
  insert into public.inventorinator_workspace_recovery(workspace_id, recovery_hash) values ('$workspace', extensions.digest('CONCURRENT-RECOVERY-KEY', 'sha256'));
  insert into public.workshop_states(workspace_id, state_json) values ('$workspace', '{\"inventory\":[{\"id\":\"CONCURRENT-SAFE\"}]}'::jsonb);
" >/dev/null

(
  run_psql -qAtc "
    begin;
    select set_config('request.jwt.claim.sub', '$winner', false);
    select public.recover_inventorinator_workspace('$workspace', 'CONCURRENT-RECOVERY-KEY', 'Winning device');
    select pg_sleep(2);
    commit;
  " >"$output_dir/winner" 2>&1
) &
winner_pid=$!

sleep 0.2
set +e
run_psql -qAtc "
  select set_config('request.jwt.claim.sub', '$loser', false);
  select public.recover_inventorinator_workspace('$workspace', 'CONCURRENT-RECOVERY-KEY', 'Losing device');
" >"$output_dir/loser" 2>&1
loser_status=$?
set -e
wait "$winner_pid"

if [ "$loser_status" -eq 0 ]; then
  echo 'Concurrent recovery accepted the same key twice.' >&2
  exit 1
fi

result=$(run_psql -qAtc "
  select
    count(*) filter (where role = 'owner') || ':' ||
    count(*) filter (where role = 'owner' and user_id = '$winner') || ':' ||
    (select count(*) from public.workshop_states where workspace_id = '$workspace' and state_json->'inventory'->0->>'id' = 'CONCURRENT-SAFE')
  from public.inventorinator_workspace_members where workspace_id = '$workspace';
")
if [ "$result" != '1:1:1' ]; then
  echo "Concurrent recovery invariant failed: $result" >&2
  exit 1
fi

echo 'Concurrent recovery serialized correctly: one owner, one rejected key, state preserved.'
