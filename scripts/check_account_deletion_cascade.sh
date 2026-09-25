#!/usr/bin/env bash
# Behavioral regression test for account deletion, against the LOCAL
# disposable Postgres only (never production). Creates a throwaway user
# with data in the canonical menstrual tables, the legacy cycle_entries
# table AND the FK-less ai_rate_limit_counters table, deletes the user
# through the app's REAL deletion path (delete_my_account(), as that
# user), and fails unless NOTHING attributable to the deleted uuid remains
# in ANY public table. Everything runs in one transaction that is rolled
# back. Usage: scripts/check_account_deletion_cascade.sh [db-container]
set -euo pipefail
DB="${1:-supabase_db_Niswah}"
U="cccccccc-0000-0000-0000-00000000de1e"
OUT="$(docker exec -i "$DB" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At <<SQL
begin;
insert into auth.users (id,email,encrypted_password,email_confirmed_at,created_at,updated_at,aud,role)
values ('$U','deletion-probe@example.test','',now(),now(),now(),'authenticated','authenticated');
select set_config('request.jwt.claim.sub','$U',true) \\gset
select set_config('request.jwt.claims','{"sub":"$U","role":"authenticated"}',true) \\gset
set local role authenticated;
select record_onboarding_menstrual_history('dddddddd-0000-0000-0000-000000000001'::uuid,180,current_date-32,'date_only',null,'ended',null,current_date-27,'date_only',null,5,32) \\gset
reset role;
insert into public.cycle_entries (user_id, date, flow) values ('$U', current_date, 'medium');
insert into public.ai_rate_limit_counters (user_id, function_name, window_start, request_count)
  values ('$U','ai-assistant-chat',date_trunc('hour',now()),3);
create or replace function pg_temp.owned_rows(u uuid) returns bigint language plpgsql as \$f\$
declare r record; cnt bigint; total bigint := 0; begin
  for r in select c.table_name t, c.column_name cn from information_schema.columns c
           join information_schema.tables tt using (table_schema, table_name)
           where c.table_schema='public' and tt.table_type='BASE TABLE' and c.data_type='uuid'
             and c.column_name in ('user_id','owner_id','author_id','sender_id','participant_one','participant_two') loop
    execute format('select count(*) from public.%I where %I = \$1', r.t, r.cn) into cnt using u;
    total := total + cnt;
  end loop; return total; end \$f\$;
select 'before=' || pg_temp.owned_rows('$U');
set local role authenticated;
select public.delete_my_account();
reset role;
select 'after=' || pg_temp.owned_rows('$U');
select 'auth_users_left=' || count(*) from auth.users where id='$U';
rollback;
SQL
)"
echo "$OUT" | grep -E "^(before|after|auth_users_left)="
BEFORE="$(echo "$OUT" | sed -n 's/^before=//p')"; AFTER="$(echo "$OUT" | sed -n 's/^after=//p')"
if [ "${BEFORE:-0}" -lt 5 ]; then echo "FAIL: fixture did not create data (before=$BEFORE)" >&2; exit 1; fi
if [ "${AFTER:-1}" != "0" ]; then echo "FAIL: $AFTER row(s) still attributable to the deleted user" >&2; exit 1; fi
echo "OK: account deletion leaves zero rows attributable to the deleted user"
