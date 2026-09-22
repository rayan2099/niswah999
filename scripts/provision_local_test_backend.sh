#!/usr/bin/env bash
# Brings up a disposable LOCAL Supabase backend (baseline + active migrations,
# same reconstruction order as validate_migrations.sh) and leaves it running
# for UI acceptance testing. Never touches production. Prints the local API
# URL and anon key at the end. Tear down with: supabase stop --no-backup
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_CONTAINER="supabase_db_Niswah"
DUMMY_TOKEN="sbp_local_dummy_0000000000000000000000000000000000000000"
MIGRATIONS_DIR="supabase/migrations"
HOLD_DIR="$(mktemp -d)"

restore_migrations() {
  if compgen -G "$HOLD_DIR"/'*.sql' > /dev/null 2>&1; then
    mv "$HOLD_DIR"/*.sql "$MIGRATIONS_DIR/"
  fi
  rmdir "$HOLD_DIR" 2>/dev/null || true
}
trap restore_migrations EXIT

if compgen -G "$MIGRATIONS_DIR"/'*.sql' > /dev/null 2>&1; then
  mv "$MIGRATIONS_DIR"/*.sql "$HOLD_DIR/"
fi

docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1 || true

# Only the services the Flutter client actually needs (db, auth, rest, kong);
# analytics/vector/studio/etc. are log/UI sidecars that time out in
# constrained environments and are irrelevant to app behavior.
SUPABASE_ACCESS_TOKEN="$DUMMY_TOKEN" supabase start \
  -x analytics,vector,studio,imgproxy,edge-runtime,functions,realtime,storage,inbucket,meta

docker cp supabase/canonical_baseline/00_public_baseline_draft.sql "$DB_CONTAINER:/tmp/baseline.sql"
docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/baseline.sql >/dev/null

while IFS= read -r migration; do
  name="$(basename "$migration")"
  docker cp "$migration" "$DB_CONTAINER:/tmp/$name"
  docker exec "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -f "/tmp/$name" >/dev/null
done < <(printf '%s\n' "$HOLD_DIR"/*.sql | sort)

echo "==> Local test backend ready"
supabase status -o env 2>/dev/null | grep -E "^(API_URL|ANON_KEY)=" || true
