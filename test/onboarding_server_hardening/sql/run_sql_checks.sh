#!/usr/bin/env bash
# Builds a throwaway database (stub Supabase bootstrap + canonical baseline +
# supabase/migrations in filename order) on a scratch Postgres 16 and runs
# every check script in this directory against its own fresh copy.
# Never point this at a shared or live database.
#
#   PGHOST=/path/to/socket PGPORT=5432 PGUSER=postgres \
#     test/onboarding_server_hardening/sql/run_sql_checks.sh
#
# EXCLUDE_MIGRATION=<filename> builds the database without that migration —
# used to prove a check fails before its fix and passes after it.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
status=0
for check in "$here"/*.sql; do
  name="$(basename "$check")"
  [ "$name" = "00_bootstrap_stub_supabase.sql" ] && continue
  db="ohcheck_$(echo "$name" | tr -c 'a-z0-9' '_' | cut -c1-40)"
  dropdb --if-exists "$db" >/dev/null 2>&1
  createdb "$db" || exit 2
  psql -q -v ON_ERROR_STOP=1 -d "$db" -f "$here/00_bootstrap_stub_supabase.sql" >/dev/null || exit 2
  psql -q -v ON_ERROR_STOP=1 -d "$db" -f "$repo/supabase/canonical_baseline/00_public_baseline_draft.sql" >/dev/null || exit 2
  for m in "$repo"/supabase/migrations/*.sql; do
    [ "$(basename "$m")" = "${EXCLUDE_MIGRATION:-}" ] && continue
    psql -q -v ON_ERROR_STOP=1 -d "$db" -f "$m" >/dev/null || exit 2
  done
  if out="$(psql -q -v ON_ERROR_STOP=1 -d "$db" -f "$check" 2>&1)"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "$out" | grep -E "ERROR|FAIL" | sed 's/^/      /' | head -5
    status=1
  fi
  dropdb "$db" >/dev/null 2>&1
done
exit $status
