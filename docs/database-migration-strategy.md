# Database Migration Strategy

Established by the BR-002 (Migration Chain Reproducibility) wave, 2026-09-06. Full supporting evidence: `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §37.

## The problem this document solves

Production's live schema was built through direct, out-of-band SQL execution, not through the tracked migration system — confirmed repeatedly across this engagement (`supabase migration list --linked` shows every historical migration with an empty `remote` field) and reproduced directly this wave (a full concatenated replay of the historical chain against an empty Postgres instance produces 96 `ERROR` lines and creates only 7 of the ~20 tables the chain collectively defines). Three live-only objects — a bare `public.users` table, `cycle_entries`, `prayer_log` — are referenced by migrations that assume they already exist, but no tracked migration ever creates any of them. This makes the historical migration chain unusable as a from-scratch reconstruction mechanism, which is `BR-002`'s native finding.

## The four-part state model

1. **Canonical baseline** (`supabase/canonical_baseline/00_public_baseline_draft.sql`) — captured directly from production's real, live schema (not reconstructed from migration files). This is the authoritative starting point for any fresh environment. Verified this wave to correctly include every known live-only object (`users`, `cycle_entries`, `prayer_log`, `pregnancy_records`, `secret_vault`, `chat_history`) and the auth-provisioning trigger pair (see below).
2. **Archived historical migrations** (`supabase/migrations_archive/`) — the original 12 migration files (2026-08-20 through 2026-08-30), moved here byte-for-byte (SHA-256-verified identical before and after the move) via `git mv` (full git history preserved, `git log --follow` still traces each file to its original commit). **Never executed by any Supabase tooling** — `supabase start`/`supabase db push` only read `supabase/migrations/`. Preserved as historical/audit evidence, not deleted, per this engagement's standing "do not erase historical truth" rule. See `supabase/migrations_archive/README.md` for the full per-file disposition.
3. **Active migration path** (`supabase/migrations/`) — contains only migrations written *after* the canonical baseline was captured (2026-09-04). Currently just `20260906090000_ai_rate_limit.sql` (`W1-001`) — self-contained, additive-only, verified idempotent, does not depend on anything in the archive. A fresh environment is always: baseline, then whatever is in this directory, in order.
4. **Production legacy state** — production's actual live schema, which the canonical baseline mirrors as of its last capture (2026-09-04). No production schema change of any kind has occurred since that capture (every subsequent wave in this engagement explicitly confirmed "no production DB changes"), so the baseline remains current — re-verified this wave via full schema-contract re-derivation, not assumed.

## Fresh-environment procedure (verified this wave)

```bash
# 1. Clean slate
docker volume ls --filter "name=supabase" --format "{{.Name}}" | xargs -r docker volume rm

# 2. Start — applies supabase/migrations/ only (currently just W1-001, self-contained)
SUPABASE_ACCESS_TOKEN="<any-non-empty-value>" supabase start

# 3. Apply the canonical baseline directly (never supabase db push against
#    the archive — it no longer exists in supabase/migrations/ at all)
docker cp supabase/canonical_baseline/00_public_baseline_draft.sql supabase_db_Niswah:/tmp/baseline.sql
docker exec supabase_db_Niswah psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/baseline.sql

# 4. Verify
docker cp scripts/verify_schema_contract.sql supabase_db_Niswah:/tmp/verify_schema_contract.sql
docker exec supabase_db_Niswah psql -U postgres -f /tmp/verify_schema_contract.sql
```

Or, in one command: `scripts/validate_migrations.sh` (does all of the above, plus teardown, and exits non-zero on any contract failure — this is what CI's `validate-migrations` job runs).

**Measured this wave**: `supabase start` (fresh, cached Docker images) — 47-50s. Baseline apply — under 1 second. Total to a fully verified, schema-contract-passing state: **well under one minute**, run twice (baseline-only, and baseline + `W1-001`) with identical results both times.

## Auth provisioning contract

Two triggers fire on every `auth.users` insert — verified this wave to be **complementary, not duplicative**:

- `auth_users_create_profile` → `create_user_profile()` → inserts into `public.users` (the bare FK target most feature tables reference — chat, community, wellbeing, pregnancy).
- `on_auth_user_created` → `handle_new_user()` → inserts into `public.profiles` (the 1:1 `auth.users` extension holding `full_name`/`selected_madhhab`, used by `AuthRepositoryImpl`).

Both are required — they populate two structurally distinct tables serving different parts of the application, not the same responsibility twice. **Tested this wave** in a fresh environment: a real signup via the local Auth API produces exactly one `public.users` row and exactly one `public.profiles` row, with no trigger collision and no duplicate rows, confirmed against both a baseline-only and a baseline+`W1-001` rebuild.

*Observation, not a defect this wave addresses*: the two tables' default values disagree (`users.madhhab` defaults to `'HANBALI'`, `profiles.selected_madhhab` defaults to `'shafii'`) — a pre-existing data-consistency quirk between two independently-evolved provisioning paths, out of `BR-002`'s scope (migration reproducibility, not data consistency) but worth a future application-layer look.

## `W1-001` status

Remains **`PENDING_PRODUCTION`** — nothing in this wave changes its authorization state. It lives in `supabase/migrations/` (the active path) specifically because fresh environments must be able to deterministically reach both `BASELINE` and `BASELINE + W1-001` states (both tested this wave), not because it has been applied to production. Its own production deployment remains gated on `BR-001` (a real, verified production backup — currently `OPEN`), per the Production Database Change Safety Gate wave's `NOT_SAFE_TO_AUTHORIZE_W1_001_DEPLOYMENT` decision, unchanged.

## Migration ledger policy

Production's migration ledger (`supabase migration list --linked`) shows every tracked migration — historical and `W1-001` alike — with an empty `remote` field. **This wave does not touch or attempt to reconcile that ledger.** Repository reproducibility (the actual native concern behind `BR-002`) is fully addressed by the four-part model above, without depending on production bookkeeping — the ledger's divergence is a separate, honestly-tracked fact, not hidden and not treated as something that must be fixed before repository reproducibility can be considered solved. If `W1-001` is ever applied to production via the isolated SQL-Editor mechanism already documented (`00_09` §34 Phase I), the ledger should be updated via `supabase migration repair --status applied 20260906090000` as a separate, later, non-schema-mutating bookkeeping step — not attempted this wave.

## Future migration procedure

1. Write the new migration file directly in `supabase/migrations/` (not the archive), dated after the last active migration.
2. Test it locally: `scripts/validate_migrations.sh` should still pass (proves it doesn't break the baseline+active-chain rebuild), plus any migration-specific behavioral tests (RLS, idempotency, load — following the pattern established for `W1-001` in `00_09` §34 Phases D/G).
3. Do not assume `supabase db push` is safe against production until `BR-002`'s ledger-divergence is separately, deliberately addressed — the isolated single-file-apply mechanism (`00_09` §34 Phase I) remains the default safe path for production application.
4. Once applied to production and its own `remote` ledger status is separately reconciled (an explicit, deliberate action, not automatic), the migration remains in `supabase/migrations/` — it does not move to the archive. Only migrations that predate the canonical baseline and cannot cleanly replay belong in `supabase/migrations_archive/`.

## Drift detection

**Distinguishes known production legacy drift from new, unexpected drift** — without repeating the credential-exposure risk from a prior wave (`db dump --data-only --dry-run` minted and printed a live production password; a standing, unresolved suspicion was also raised that even schema-only `-s <schema>` dumps might carry the same underlying wire-connection risk, simply not yet noticed). **No new production database connection was attempted this wave for drift-checking, out of that same caution.**

**Already-obtained, already-safe artifacts used instead**: `supabase/live_schema_capture/2026-09-04_{public,auth,storage}.sql` — captured in an earlier wave, before this suspicion was raised, and not re-fetched this wave. These remain the last confirmed point-in-time snapshot of production's real schema, and the canonical baseline is derived from them.

**Supported manual procedure for a future check** (not run this wave):
1. **Once the exposed `cli_login_postgres` credential is confirmed rotated** (standing owner action from the Production Database Change Safety Gate wave — a precondition for this step, not optional), re-run the schema-only captures: `supabase db dump -s public --linked -f supabase/live_schema_capture/<new-date>_public.sql` (and `-s auth`, `-s storage`).
2. Diff each against its most recent predecessor.
3. Classify every diff line: **KNOWN_LEGACY_DRIFT** if it matches an already-documented live-only object (`users`, `cycle_entries`, `prayer_log`, `pregnancy_records`, `secret_vault`, `chat_history` — the full list is in `scripts/verify_schema_contract.sql`) or an already-approved change (e.g. `W1-001` once actually deployed); **NEW_UNEXPECTED_DRIFT** for anything else — investigate before assuming it is safe, and update the canonical baseline + this document if it reflects a real, intentional production change.
4. A lightweight, already-proven-safe partial signal requiring no new production contact at all: re-run `supabase migration list --linked` and `supabase functions list --project-ref <ref>` (both Management-API-based, already used safely throughout this engagement) — if any historical migration's `remote` field ever changes from empty, or an Edge Function version changes unexpectedly, that alone is worth investigating even before a full schema diff.

## Files this strategy touches

- `supabase/canonical_baseline/00_public_baseline_draft.sql` — unchanged this wave, re-verified current.
- `supabase/migrations_archive/` (new) — 12 historical migration files + `README.md`.
- `supabase/migrations/` — now contains only `20260906090000_ai_rate_limit.sql`.
- `scripts/verify_schema_contract.sql` (new) — machine-checkable schema contract.
- `scripts/validate_migrations.sh` (new) — full clean-rebuild-and-verify automation, tested end-to-end this wave.
- `.github/workflows/ci.yml` — new `validate-migrations` job (not yet remotely verified — see `RD_release_rollback_runbook.md` §8 for the standing GitHub-authentication blocker).
