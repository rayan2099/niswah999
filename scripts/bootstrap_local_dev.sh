#!/usr/bin/env bash
# Bootstraps a persistent, working local dev environment: clean local DB ->
# canonical baseline -> active migrations (in filename/timestamp order).
#
# Local reproducibility gap (Production Readiness pass, 2026-09-30): a bare
# `supabase db reset` cannot do this alone. `supabase/config.toml`'s
# `[db.seed]` hook references `supabase/seed.sql`, which does not exist
# (confirmed: `supabase db reset` prints a WARN and silently skips
# seeding) -- and even a real seed.sql there would run in the wrong
# position, since Supabase CLI always applies `supabase/migrations/`
# *before* running the seed hook, while this repo's migrations assume the
# canonical baseline already exists (some both ALTER a baseline-defined
# table and replace a baseline-defined function). The result: a fresh
# `supabase db reset` leaves only migration-created tables (e.g. the KB
# tables) -- `cycle_entries`, `pregnancy_profile`, `users`, and everything
# else the baseline defines are silently absent.
#
# This script shares its core sequence with scripts/validate_migrations.sh
# (CI's own migration-reproducibility gate, BR-002) -- same canonical
# baseline file, same migrations, same order, proven reproducible there.
# It differs only in two ways, both intentional: (1) it does not tear down
# the stack at the end, since its purpose is to hand back a working
# environment to keep developing against, not to validate and discard one;
# (2) it does not run the CI schema-contract check, since that is a
# regression gate, not a dev-setup step. If the canonical bootstrap order
# ever changes, update both scripts together.
#
# Does not seed the Niswah KB itself -- run scripts/deploy_kb_v1.sh
# separately afterward (against SUPABASE_DB_URL=the local stack's own
# connection string) if KB-backed features are needed locally.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_CONTAINER="supabase_db_Niswah"
MIGRATIONS_DIR="supabase/migrations"
HOLD_DIR="$(mktemp -d)"

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

echo "==> Stopping any running local Supabase stack (containers must be stopped before their volumes can be removed)"
supabase stop --no-backup >/dev/null 2>&1 || true

echo "==> Removing any existing local Supabase volumes (clean-slate rebuild)"
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm

echo "==> Starting local Supabase stack (supabase/migrations/ is empty right now — genuinely clean database)"
supabase start

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

echo "==> Local environment ready and left running (not torn down)."
echo "==> To also seed the Niswah KB: SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres scripts/deploy_kb_v1.sh"
