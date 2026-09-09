#!/usr/bin/env bash
# Non-mutating production health check for the W1-001 AI rate-limiter
# database objects (ai_rate_limit_counters table,
# check_and_increment_ai_rate_limit() function).
#
# Built during the URGENT PRODUCTION RECOVERY — W1-001 wave, 2026-09-09,
# after these objects were found completely absent from production
# (all 4 AI Edge Functions returning 503) despite having been verified
# present when originally deployed on 2026-09-08. Root-cause investigation
# (see production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md,
# W1-001 incident history) found direct Postgres log evidence of a compute
# restart on 2026-09-08T07:41Z followed by WAL-archive-based recovery that
# stopped at an LSN earlier than the objects' creation — i.e. an
# infrastructure-level event that can silently revert recent schema
# changes without ever executing a logged DROP statement. That mechanism
# is outside this repository's control, so the appropriate mitigation is
# detection, not automatic repair (a self-healing schema process that
# silently mutates production is explicitly out of scope — see the W1-001
# incident record).
#
# What this script does: a single read-only SQL query against production
# via the Supabase Management API, checking whether both objects still
# exist. It changes nothing. Run it manually, or wire it into your own
# monitoring/cron/CI with your own credentials — this script deliberately
# does not provision or read any repository/CI secret; it only uses the
# local Supabase CLI access token already required for other scripts in
# this repo (~/.supabase/access-token, or $SUPABASE_ACCESS_TOKEN).
#
# Exit code 0 = both objects present. Exit code 1 = at least one missing
# (treat as a P1: it means every AI feature will be returning 503, same
# as the 2026-09-09 incident). Exit code 2 = could not reach the API.

set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-jkmjobvxfrmuwafczvtw}"

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  TOKEN="$SUPABASE_ACCESS_TOKEN"
elif [[ -f "$HOME/.supabase/access-token" ]]; then
  TOKEN="$(cat "$HOME/.supabase/access-token")"
else
  echo "ERROR: no Supabase access token found (set \$SUPABASE_ACCESS_TOKEN or create ~/.supabase/access-token)" >&2
  exit 2
fi

QUERY="select to_regclass('public.ai_rate_limit_counters') is not null as table_present, to_regprocedure('public.check_and_increment_ai_rate_limit(text,integer,integer)') is not null as function_present;"

RESPONSE="$(curl -s -w '\n%{http_code}' -X POST \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$QUERY")")"

HTTP_CODE="$(echo "$RESPONSE" | tail -n1)"
BODY="$(echo "$RESPONSE" | sed '$d')"

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "ERROR: Management API request failed (HTTP $HTTP_CODE): $BODY" >&2
  exit 2
fi

TABLE_PRESENT="$(echo "$BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["table_present"])' 2>/dev/null || echo "unknown")"
FUNCTION_PRESENT="$(echo "$BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["function_present"])' 2>/dev/null || echo "unknown")"

echo "ai_rate_limit_counters table present:            $TABLE_PRESENT"
echo "check_and_increment_ai_rate_limit function present: $FUNCTION_PRESENT"

if [[ "$TABLE_PRESENT" == "True" && "$FUNCTION_PRESENT" == "True" ]]; then
  echo "==> OK: both W1-001 objects present."
  exit 0
else
  echo "==> ALERT: at least one W1-001 object is missing. All 4 AI Edge Functions will be returning 503 to real users. See W1-001 in production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md for the recovery procedure (re-apply supabase/migrations/20260906090000_ai_rate_limit.sql)." >&2
  exit 1
fi
