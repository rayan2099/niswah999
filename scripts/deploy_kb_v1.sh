#!/usr/bin/env bash
set -euo pipefail

# Deploy Niswah V1 KB to a Supabase/Postgres database.
# Required: SUPABASE_DB_URL (Postgres connection string with migration/write rights)
# Required tools: python3, supabase CLI, psql
#
# This script is deliberately fail-closed:
# 1) validates research/review packets,
# 2) materializes exactly 211 eligible candidates + 43 quarantined rows,
# 3) renders deterministic seed SQL,
# 4) applies migrations,
# 5) seeds only production candidates,
# 6) verifies the live denominator and source/publication gates.

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v supabase >/dev/null || { echo "supabase CLI is required" >&2; exit 1; }
command -v psql >/dev/null || { echo "psql is required" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 scripts/verify_kb_review_packets.py
python3 scripts/build_kb_production_candidates.py
python3 scripts/render_kb_seed_sql.py

SEED="production-readiness-results/knowledge-base/generated/PRODUCTION_KB_SEED.sql"
QUARANTINE="production-readiness-results/knowledge-base/generated/FIQH_QUARANTINE.csv"

[[ -s "$SEED" ]] || { echo "seed SQL was not generated" >&2; exit 1; }
[[ -s "$QUARANTINE" ]] || { echo "quarantine file was not generated" >&2; exit 1; }

# Apply all active migrations through the repository's canonical migration path.
supabase db push --db-url "$SUPABASE_DB_URL"

# Seed only evidence-eligible rows. Quarantine is intentionally never loaded
# into the authoritative retrieval tables.
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$SEED"

# Hard post-deploy gate. Any count/publication/source mismatch fails deployment.
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f scripts/verify_kb_live.sql

echo "KB V1 deploy complete: 211 active production items; 43 Fiqh rows remain quarantined outside authoritative retrieval."
