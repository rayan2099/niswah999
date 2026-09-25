#!/usr/bin/env bash
# Explicit, reversible .env management for local acceptance runs.
#   scripts/local_env.sh use ios       -> .env points at http://127.0.0.1:54321
#   scripts/local_env.sh use android   -> .env points at http://10.0.2.2:54321
#                                          (the emulator's alias for the host)
#   scripts/local_env.sh restore       -> puts the real .env back
#   scripts/local_env.sh status        -> prints ONLY the safe backend host
#
# The real .env is copied to .env.real.backup exactly once, the first time
# a local .env is written, and never overwritten while a backup exists.
# Neither file is ever printed; both are gitignored (.env*).
set -euo pipefail
cd "$(dirname "$0")/.."
BACKUP=".env.real.backup"

case "${1:-status}" in
  use)
    PLATFORM="${2:?usage: $0 use ios|android}"
    case "$PLATFORM" in ios) HOST=127.0.0.1 ;; android) HOST=10.0.2.2 ;; *) echo "unknown platform" >&2; exit 2 ;; esac
    if [ -f .env ] && [ ! -f "$BACKUP" ]; then
      if python3 scripts/assert_test_backend.py --env-file .env >/dev/null 2>&1; then
        echo "note: current .env already targets an approved backend; no backup needed" >&2
      else
        cp .env "$BACKUP"; echo "backed up the real .env to $BACKUP" >&2
      fi
    fi
    ANON="$(supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | sed -E 's/^ANON_KEY="?([^"]*)"?$/\1/')"
    [ -n "$ANON" ] || { echo "local Supabase is not running (supabase status)" >&2; exit 1; }
    cat > .env <<ENV
APP_ENV=ci-acceptance
SUPABASE_URL=http://$HOST:54321
SUPABASE_ANON_KEY=$ANON
VITE_SUPABASE_URL=http://$HOST:54321
VITE_SUPABASE_ANON_KEY=$ANON
SENTRY_DSN=
ENV
    python3 scripts/assert_test_backend.py --env-file .env
    ;;
  restore)
    if [ -f "$BACKUP" ]; then mv "$BACKUP" .env; echo ".env restored from backup"; else echo "no backup present; .env left as is"; fi
    ;;
  status)
    python3 scripts/assert_test_backend.py --env-file .env || true
    ;;
  *) echo "usage: $0 use ios|android | restore | status" >&2; exit 2 ;;
esac
