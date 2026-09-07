# Archived migrations — NOT executed by any Supabase tooling

Moved here from `supabase/migrations/` by the BR-002 (Migration Chain Reproducibility) wave, 2026-09-06. See `docs/database-migration-strategy.md` for the full rationale and `production-readiness-results/master/00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §37 for the complete evidence.

## Why these files are here, not in `supabase/migrations/`

These 12 files are the project's original, chronological migration history (2026-08-20 through 2026-08-30). **They do not replay cleanly against an empty database and were never actually applied to production through the tracked migration system** — production's live schema was built through direct, out-of-band SQL execution, evidenced by `supabase migration list --linked` showing every one of these files with an empty `remote` field, and directly reproduced this wave: a full concatenated replay against a truly empty Postgres instance produces 96 `ERROR` lines and successfully creates only 7 of the ~20 tables these files collectively define.

**Root causes, precisely identified this wave** (not merely observed as "broken"):
1. `prayer_log` and `pregnancy_records` are referenced (via `ALTER TABLE ... RENAME`/`DROP POLICY ... ON`) by `20260822014500_niswah_schema_sync_and_indexes.sql` as if already existing — but no tracked migration ever creates either table. Both are live-only objects.
2. A bare `public.users` table (distinct from `auth.users`) is referenced via foreign key by six later migrations (`chat_threads`/`flagged_conversations`/`pregnancy_profile`/`wellbeing_logs`/`community_posts`, and `chat_messages` transitively) — no tracked migration ever creates it either. This single missing object cascades into the majority of this chain's failures, and is the same root cause `PJ-001` identified independently from the application-code side.
3. `cycle_entries` (distinct from `cycle_logs`, which migration #1 *does* create) is `ALTER`ed by two later migrations as if already existing — a third live-only object with no creating migration anywhere in this chain.

None of this is a defect in these files' original authorship — they accurately describe *intended* schema changes at the time they were written, and remain valuable, truthful historical evidence of the project's actual development sequence. They are archived, not deleted, precisely so that evidence is never lost.

## What replaced them for fresh-environment reconstruction

`supabase/canonical_baseline/00_public_baseline_draft.sql` — captured directly from production's real, live schema (not reconstructed from these files), and independently verified this wave to already contain every one of the live-only objects these migrations assumed pre-existed (`users`, `cycle_entries`, `prayer_log`, `pregnancy_records`), plus every other table/function/trigger/RLS policy the application currently depends on. See `docs/database-migration-strategy.md` for the full fresh-environment procedure.

## What remains active

`supabase/migrations/` now contains only migrations written *after* the canonical baseline was captured (2026-09-04) — currently just `20260906090000_ai_rate_limit.sql` (`W1-001`), which is self-contained, additive-only, and does not depend on anything in this archive. Supabase's own tooling (`supabase start`, `supabase db push`) only ever reads `supabase/migrations/`, so these archived files are never executed by accident.

## If you need to inspect original history

Every file here retains its exact original content (verified via SHA-256 checksum before and after this move — identical) and its full git history (moved via `git mv`, not copy-and-delete, so `git log --follow` still traces each file back to its original commit).
