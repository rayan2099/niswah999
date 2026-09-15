#!/usr/bin/env bash
# Proves the repository can deterministically rebuild the application
# schema from scratch: clean local DB -> canonical baseline -> active
# migrations (supabase/migrations/, in filename/timestamp order) ->
# schema-contract verification.
#
# BR-002 (Migration Chain Reproducibility) wave, 2026-09-06. Reconstruction
# order fixed by the BR-002 CI Migration-Reproducibility Repair wave,
# 2026-09-15 — see the note above the migration-preservation step below for
# the exact defect this replaced. Intended for local use and CI. Does not
# require or touch production access of any kind.
#
# Exit code 0 = every schema-contract check passed. Non-zero = at least
# one FAIL row (printed to stdout) or a hard failure applying the baseline
# or an active migration.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_CONTAINER="supabase_db_Niswah"
DUMMY_TOKEN="sbp_local_dummy_0000000000000000000000000000000000000000"
MIGRATIONS_DIR="supabase/migrations"
HOLD_DIR="$(mktemp -d)"

# `supabase start` applies every file in supabase/migrations/ automatically
# as part of its own first-time bootstrap — before this script ever gets a
# chance to apply the canonical baseline. That ordering is backwards: the
# baseline is the schema's historical starting point: active migrations
# are only meaningful applied *on top of* it. This went unnoticed while
# supabase/migrations/ held only one migration with no baseline overlap
# (W1-001); it became a real, CI-breaking defect the moment a migration
# (madhhab_authority_state) both ALTERed a baseline-defined table and
# replaced a baseline-defined function: the migration's own ALTER-TABLE
# logic silently no-ops (its own `IF EXISTS (... table_name = 'users')`
# guard is false — public.users doesn't exist yet at that point), and its
# `CREATE OR REPLACE FUNCTION create_user_profile` later collides with the
# baseline's bare `CREATE FUNCTION` of the same name, since the baseline
# applies *after* migrations in the old order — producing exactly the CI
# failure this fix addresses ("function ... already exists with same
# argument types"). Simply loosening the baseline's CREATE FUNCTION to
# CREATE OR REPLACE would hide the duplicate-function error while leaving
# the deeper bug: the ALTER-TABLE logic would still have no-op'd, so the
# rebuilt users table would silently lack madhhab_selection_state and keep
# the legacy hardcoded-Hanbali default — a materially wrong reconstructed
# schema, not just a cosmetic error.
#
# Fix: temporarily hold every migration file out of supabase/migrations/
# so `supabase start` bootstraps a genuinely empty database, apply the
# baseline, then apply each held migration back explicitly, in
# filename/timestamp order — the actual intended contract:
# baseline + migrations (in order) = current schema. Migration files are
# restored to their original location before this script exits, on success
# OR failure OR interruption (trap below) — nothing in the working tree is
# left modified.
restore_migrations() {
  if compgen -G "$HOLD_DIR"/'*.sql' > /dev/null 2>&1; then
    mv "$HOLD_DIR"/*.sql "$MIGRATIONS_DIR/"
  fi
  rmdir "$HOLD_DIR" 2>/dev/null || true
}
trap restore_migrations EXIT

echo "==> Preserving active migrations outside supabase/migrations/ (restored on exit — see trap)"
if compgen -G "$MIGRATIONS_DIR"/'*.sql' > /dev/null 2>&1; then
  mv "$MIGRATIONS_DIR"/*.sql "$HOLD_DIR/"
fi

echo "==> Removing any existing local Supabase volumes (clean-slate rebuild)"
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1 || true

echo "==> Starting local Supabase stack (supabase/migrations/ is empty right now — genuinely clean database)"
SUPABASE_ACCESS_TOKEN="$DUMMY_TOKEN" supabase start

echo "==> Applying canonical baseline (historical starting-point schema)"
docker cp supabase/canonical_baseline/00_public_baseline_draft.sql "$DB_CONTAINER:/tmp/baseline.sql"
docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/baseline.sql

echo "==> Applying active migrations explicitly, in filename/timestamp order"
while IFS= read -r migration; do
  name="$(basename "$migration")"
  echo "----> $name"
  docker cp "$migration" "$DB_CONTAINER:/tmp/$name"
  docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f "/tmp/$name"
done < <(printf '%s\n' "$HOLD_DIR"/*.sql | sort)

echo "==> Verifying schema contract"
docker cp scripts/verify_schema_contract.sql "$DB_CONTAINER:/tmp/verify_schema_contract.sql"
CONTRACT_OUTPUT="$(docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/verify_schema_contract.sql)"
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
