#!/usr/bin/env bash
# Shared primitive: applies supabase/canonical_baseline/00_public_baseline_draft.sql
# followed by every *.sql file in a caller-supplied directory (in sorted
# filename/timestamp order) against a running DB container.
#
# This is the one place the "baseline is the schema's historical starting
# point; active migrations are only meaningful applied on top of it" order
# is encoded (see scripts/validate_migrations.sh's own header comment for
# the exact CI-breaking defect this order fixes). Both
# scripts/validate_migrations.sh (CI's migration-reproducibility gate,
# tears its stack down after) and scripts/bootstrap_local_dev.sh (a
# persistent local dev environment) call this instead of each keeping
# their own copy, so the sequence exists in exactly one place and cannot
# drift between the two callers.
#
# Usage: apply_baseline_and_migrations.sh <db_container_name> <migrations_source_dir>
# <migrations_source_dir> must contain only the *.sql files to apply, with
# supabase/migrations/ itself already empty (the caller is responsible for
# moving migrations out before `supabase start`, so its own native
# migration-auto-apply never runs them first -- see either caller's own
# "preserving active migrations" step).

set -euo pipefail

DB_CONTAINER="${1:?db container name required}"
MIGRATIONS_SRC_DIR="${2:?migrations source directory required}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> Applying canonical baseline (historical starting-point schema)"
docker cp "$REPO_ROOT/supabase/canonical_baseline/00_public_baseline_draft.sql" "$DB_CONTAINER:/tmp/baseline.sql"
docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/baseline.sql

echo "==> Applying active migrations explicitly, in filename/timestamp order"
while IFS= read -r migration; do
  name="$(basename "$migration")"
  echo "----> $name"
  docker cp "$migration" "$DB_CONTAINER:/tmp/$name"
  docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f "/tmp/$name"
done < <(printf '%s\n' "$MIGRATIONS_SRC_DIR"/*.sql | sort)
