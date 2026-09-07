#!/usr/bin/env bash
# Proves the repository can deterministically rebuild the application
# schema from scratch: clean local DB -> canonical baseline -> active
# migrations (supabase/migrations/) -> schema-contract verification.
#
# BR-002 (Migration Chain Reproducibility) wave, 2026-09-06. Intended for
# local use and for a future CI job (once GitHub authentication is
# restored — see production-readiness-results/release-deployment/
# RD_release_rollback_runbook.md §8). Does not require or touch production
# access of any kind.
#
# Exit code 0 = every schema-contract check passed. Non-zero = at least
# one FAIL row (printed to stdout) or a hard failure applying the baseline
# or an active migration.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_CONTAINER="supabase_db_Niswah"
DUMMY_TOKEN="sbp_local_dummy_0000000000000000000000000000000000000000"

echo "==> Removing any existing local Supabase volumes (clean-slate rebuild)"
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1 || true

echo "==> Starting local Supabase stack (applies supabase/migrations/ only — currently just W1-001)"
SUPABASE_ACCESS_TOKEN="$DUMMY_TOKEN" supabase start

echo "==> Applying canonical baseline"
docker cp supabase/canonical_baseline/00_public_baseline_draft.sql "$DB_CONTAINER:/tmp/baseline.sql"
docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/baseline.sql

echo "==> Verifying schema contract"
docker cp scripts/verify_schema_contract.sql "$DB_CONTAINER:/tmp/verify_schema_contract.sql"
CONTRACT_OUTPUT="$(docker exec "$DB_CONTAINER" psql -U postgres -f /tmp/verify_schema_contract.sql)"
echo "$CONTRACT_OUTPUT"

if echo "$CONTRACT_OUTPUT" | grep -q "FAIL"; then
  echo "==> SCHEMA CONTRACT FAILED — see FAIL rows above"
  EXIT_CODE=1
else
  echo "==> Schema contract: all checks passed"
  EXIT_CODE=0
fi

echo "==> Tearing down (no state persisted between validation runs, by design)"
supabase stop --no-backup >/dev/null 2>&1 || true
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1 || true

exit $EXIT_CODE
