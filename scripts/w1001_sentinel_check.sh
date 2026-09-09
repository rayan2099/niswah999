#!/usr/bin/env bash
# CI-safe production health check for the W1-001 AI rate-limiter database
# objects (ai_rate_limit_counters table, check_and_increment_ai_rate_limit()
# function). Built during the FOCUSED RESILIENCE WAVE — PRODUCTION W1-001
# SCHEMA SENTINEL, 2026-09-09, as the automated, scheduled counterpart to
# scripts/check_ai_rate_limit_objects.sh (which requires a full-privilege
# Supabase Management API personal access token — appropriate for a human
# running it locally, but not something this wave will store in GitHub
# Actions given its broad account-wide scope).
#
# This script instead uses ONLY the project's public "anon"/"publishable"
# API key — the same key already shipped inside the compiled app and
# designed by Supabase to be safe for client-side, public exposure (the
# real security boundary is RLS/grants, not this key's secrecy). No
# database password, no Management API token, no privileged credential of
# any kind is used or required.
#
# How it works: it distinguishes "object missing" from "object exists but
# access is correctly denied" using PostgREST's own distinct error codes,
# confirmed by live testing against production before this script was
# written:
#   - Table missing   -> HTTP 404, code PGRST205 ("could not find the
#                         table ... in the schema cache")
#   - Table exists     -> HTTP 401, code 42501 ("permission denied for
#                         table ...") — expected and correct: this table's
#                         grants are restricted to postgres/service_role
#                         only, so anon is denied, but the denial itself
#                         proves the table is there to be denied access to.
#   - Function missing -> HTTP 404, code PGRST202 ("could not find the
#                         function ... in the schema cache")
#   - Function exists   -> HTTP 403, code 28000 ("Not authenticated") —
#                         the function's own first check (auth.uid() IS
#                         NULL) rejects the anonymous caller before doing
#                         anything else, confirmed by live testing to
#                         happen before any table read/write, so this call
#                         is non-mutating.
#
# Any other response (network error, unexpected code, 5xx, etc.) is
# treated as INCONCLUSIVE, not silently treated as healthy — the script
# fails loudly rather than risk a false "all clear".
#
# Object names are overridable via environment variables purely so this
# same code path can be exercised end-to-end against deliberately-wrong
# names in a test run, without ever touching the real production objects.
#
# Exit 0 = both objects present. Exit 1 = at least one confirmed missing.
# Exit 2 = inconclusive (treat as a check failure, not as "healthy").

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:?SUPABASE_URL is required}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"
TABLE_NAME="${W1001_TABLE_NAME:-ai_rate_limit_counters}"
FUNCTION_NAME="${W1001_FUNCTION_NAME:-check_and_increment_ai_rate_limit}"

# Mask the key in GitHub Actions log output (defense in depth — this key
# is not sensitive, but there is no reason to ever print it either).
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::add-mask::${SUPABASE_ANON_KEY}"
fi

STATUS=0

check_table() {
  local resp http_code body code
  resp="$(curl -s -w '\n%{http_code}' -G "${SUPABASE_URL}/rest/v1/${TABLE_NAME}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    --data-urlencode "select=user_id" \
    --data-urlencode "limit=1")"
  http_code="$(echo "$resp" | tail -n1)"
  body="$(echo "$resp" | sed '$d')"
  code="$(echo "$body" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("code",""))
except Exception:
    print("")' 2>/dev/null || echo "")"

  if [[ "$http_code" == "404" && "$code" == "PGRST205" ]]; then
    echo "TABLE ${TABLE_NAME}: MISSING (HTTP 404, PGRST205 - not in schema cache)"
    return 1
  elif [[ "$http_code" == "401" && "$code" == "42501" ]]; then
    echo "TABLE ${TABLE_NAME}: PRESENT (HTTP 401, 42501 - exists, anon correctly denied)"
    return 0
  else
    echo "TABLE ${TABLE_NAME}: INCONCLUSIVE (HTTP ${http_code}, code=${code:-none}) - treating as failure"
    return 2
  fi
}

check_function() {
  local resp http_code body code
  resp="$(curl -s -w '\n%{http_code}' -X POST "${SUPABASE_URL}/rest/v1/rpc/${FUNCTION_NAME}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"p_function_name":"__w1001_sentinel_probe__","p_max_requests":1,"p_window_seconds":60}')"
  http_code="$(echo "$resp" | tail -n1)"
  body="$(echo "$resp" | sed '$d')"
  code="$(echo "$body" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("code",""))
except Exception:
    print("")' 2>/dev/null || echo "")"

  if [[ "$http_code" == "404" && "$code" == "PGRST202" ]]; then
    echo "FUNCTION ${FUNCTION_NAME}: MISSING (HTTP 404, PGRST202 - not in schema cache)"
    return 1
  elif [[ "$http_code" == "403" && "$code" == "28000" ]]; then
    echo "FUNCTION ${FUNCTION_NAME}: PRESENT (HTTP 403, 28000 - exists, anon correctly rejected pre-auth, non-mutating)"
    return 0
  else
    echo "FUNCTION ${FUNCTION_NAME}: INCONCLUSIVE (HTTP ${http_code}, code=${code:-none}) - treating as failure"
    return 2
  fi
}

table_result=0
check_table || table_result=$?

function_result=0
check_function || function_result=$?

if [[ "$table_result" -eq 0 && "$function_result" -eq 0 ]]; then
  echo "==> OK: both W1-001 objects present."
  exit 0
elif [[ "$table_result" -eq 1 || "$function_result" -eq 1 ]]; then
  echo "==> ALERT: at least one W1-001 object is confirmed MISSING. All 4 AI Edge Functions will be returning 503 to real users. Recovery runbook: production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md (W1-001) and 00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md §54." >&2
  exit 1
else
  echo "==> INCONCLUSIVE: could not definitively determine object presence. Treating as a failed check — investigate manually with scripts/check_ai_rate_limit_objects.sh." >&2
  exit 2
fi
