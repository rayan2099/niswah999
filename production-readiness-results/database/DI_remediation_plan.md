# Database & Data Integrity — Phase 3: Remediation Plan

> ⚠️ **This remediation plan is PROPOSED and NOT YET IMPLEMENTED.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until schema/code changes are completed and controlled validation (Phase 2B, not performed in this static audit) is rerun. No SQL below has been executed against any database as part of this audit.

---

## Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| DI-001 | schema.sql and migrations disagree; migrations can't rebuild schema from scratch | No enforced process requiring every live DDL change to be captured as a tracked migration; schema.sql maintained by hand instead of generated | CONFIRMED | DI-002 (consequence), DI-004 (consequence) | R1 |
| DI-002 | Silent, undetectable divergence between local and cloud data | Repository-layer error handling deliberately prioritizes "never break the UI" over "never lose data invisibly," with no telemetry/retry-queue backstop | CONFIRMED | DI-001 (root trigger of the historical incidents), DI-011 | R2 |
| DI-003 | Duplicate private conversations possible under concurrent creation | UNIQUE constraint implemented on ordered tuple instead of normalized/unordered pair | CONFIRMED | — | R3 |
| DI-004 | `users` table FK population path unverified | No tracked trigger/code populates `public.users`; possible untracked live-only mechanism (same root cause pattern as DI-001) | CONFIRMED (absence) / UNKNOWN (consequence) | DI-001 | R4 |
| DI-005 | Destructive migration lacks enforced safety guard | Migration safety relied on author's manual pre-check, not codified as a re-runnable guard | CONFIRMED | DI-001, DI-006 | R5 |
| DI-006 | Referenced migration files missing from repo | Migration files deleted/never committed instead of left as historical markers | CONFIRMED | DI-001 | R6 |
| DI-007 | No DB-enforced `updated_at` maintenance | Convention chosen (app sets it explicitly) without a DB-side backstop | CONFIRMED | — | R7 |
| DI-008 | Dead tables + dead repository class | Abandoned/superseded designs never cleaned up (ledger tables, `cycle_logs`) | CONFIRMED | DI-009 | R8 |
| DI-009 | Fiqh-state correctness has no server-side backing | Product architecture chose client-side derivation; ledger tables designed but never wired up | CONFIRMED | DI-008 | R9 |
| DI-010 | `pregnancy_milestones` accepts logically inconsistent data | No CHECK constraints authored for cross-field coherence | CONFIRMED | — | R10 |
| DI-011 | Duplicate/contradictory cycle entries for one day possible | No UNIQUE(user_id, date), inconsistent with the wellbeing_logs pattern already used elsewhere in the same codebase | CONFIRMED | DI-002, DI-009 | R11 |
| DI-012 | Account deletion removes other users' visible message history | Hard-CASCADE delete chosen for `private_messages.sender_id`, no tombstone | CONFIRMED | — | R12 |

---

## Remediation Principles Applied

- Database protects critical invariants — do not rely solely on client-side checks (applies to R3, R4, R7, R10, R11).
- One schema source of truth — eliminate drift (R1, R6).
- Expand-before-contract / backfill-before-constrain — any new UNIQUE/CHECK constraint (R3, R7, R10, R11) must first be validated against live data for existing violations before being added as a hard constraint.
- Prevention fix before cleanup — R1/R4 must be resolved (or at least understood) before any further schema change is authored, since the next change is exposed to the same drift risk.
- Retest after repair — every item below requires Phase 2B controlled validation (not performed here) before being marked Verified Closed.

---

## R1 — Establish one verified schema source of truth (closes DI-001)

1. **Detection / live verification (read-only):** Connect to the live Supabase project (with proper authorization) and export the actual live schema via `pg_dump --schema-only` or Supabase's schema-diff tooling, or query `information_schema.columns`/`information_schema.table_constraints` for every table named in `schema.sql`.
2. **Reconciliation:** Diff the live export against both `schema.sql` and the cumulative effect of `supabase/migrations/*.sql`. For every discrepancy found (expect at least the 10 tables identified in DI-001, plus the `symptoms` type contradiction), record which one (schema.sql, migrations, or neither) matches reality.
3. **Backfill missing migrations:** For every table/column/constraint that exists live but has no corresponding tracked migration, author a new, idempotent (`IF NOT EXISTS`) "catch-up" migration that documents and captures the current live state, so a fresh environment can be rebuilt from `supabase/migrations/` alone going forward. Do **not** attempt to retroactively rewrite history for migrations already applied.
4. **Regenerate `schema.sql`** as a true generated artifact (e.g., `supabase db dump --schema-only` or equivalent) rather than a hand-maintained file, and add a CI check that fails if `schema.sql` drifts from what the tracked migrations produce.
5. **Process change:** Require that any manual/dashboard DDL change against the live database be captured as a tracked migration within the same change window, going forward — no more untracked live-only schema changes.
- **Schema changes:** Additive catch-up migration(s) only; no destructive changes.
- **Code changes:** Add CI drift-check (tooling/script, not application code).
- **Data repair:** None required by this item alone.
- **Risk:** Low (read-only investigation + additive catch-up migrations).
- **Rollback:** N/A (additive).
- **Retest:** Apply the full migration sequence against a fresh empty database in CI and confirm it succeeds and matches the live schema export.

## R2 — Surface remote-sync failures instead of silently swallowing them (closes DI-002)

1. Add structured error telemetry (e.g., to whatever crash/analytics pipeline the app already uses — out of this audit's scope to specify) at every current silent `catch (_)` / swallowed-`PostgrestException` site identified in DI-002 (`CycleTrackingRepositoryImpl`, `PregnancyTrackingRepositoryImpl`, `CommunityRepositoryImpl`), so failures are at least operator-visible even while remaining non-blocking for the UI.
2. Add a lightweight local "pending sync" / "sync failed" indicator using the existing `sync_status` column pattern already present on `cycle_entries`, extended consistently to `pregnancy_milestones` and community writes, with a visible (even if unobtrusive) UI affordance so a user isn't unknowingly relying on local-only storage indefinitely.
3. Add a periodic background reconciliation/retry job for rows still marked pending/failed after local save, distinct from the current best-effort inline retry.
4. **Data repair (separate, historical):** Because DI-002's failure mode is confirmed to have already occurred in production for `cycle_entries` and `community_posts` before the fixes in migrations `20260825210000`/`20260826090000`/`20260830140000`, assess (via live DB query, not performed here) whether any users have local-only data from that window that never made it to the cloud, and if the local data source retains it, provide a one-time forced-resync path.
- **Schema changes:** None required (reuse existing `sync_status` pattern; may need to add `sync_status` to `pregnancy_milestones` if adopting the same pattern there).
- **Code changes:** Yes — error telemetry, UI indicator, background retry.
- **Data repair:** Possible one-time resync pass, pending live investigation.
- **Risk:** Low-medium (telemetry/UI additions; retry job needs idempotent upsert to avoid duplicate rows).
- **Rollback:** Feature-flaggable.
- **Retest:** Simulate a remote failure (e.g., point at an invalid endpoint in a controlled test build) and confirm the failure is now visible/telemetered rather than silent.

## R3 — Fix the private-conversation uniqueness invariant (closes DI-003)

1. **Detection query (before changing the constraint):** `SELECT participant_one, participant_two, count(*) FROM private_conversations GROUP BY LEAST(participant_one, participant_two), GREATEST(participant_one, participant_two) HAVING count(*) > 1;` — run against live data to check for existing duplicate pairs before adding a stricter constraint.
2. **Schema fix:** Replace `UNIQUE(participant_one, participant_two)` with a unique index on the normalized pair: `CREATE UNIQUE INDEX private_conversations_unordered_pair_key ON private_conversations (LEAST(participant_one, participant_two), GREATEST(participant_one, participant_two));` (drop the old constraint in the same migration).
3. **App fix:** In `getOrCreateConversation()`, normalize `participant_one`/`participant_two` order (e.g., always store the lexicographically smaller UUID first) before both the existence check and the insert, and handle the unique-violation error from a losing concurrent insert by re-selecting the winning row (retry-on-conflict pattern) rather than assuming the insert always succeeds.
- **Schema changes:** Yes — replace one constraint with a normalized unique index (requires a prior de-duplication step if the detection query in step 1 finds existing violations).
- **Code changes:** Yes — `private_messaging_repository.dart`.
- **Data repair:** Merge any existing duplicate-pair rows found in step 1 (data repair script + dry run + backup, per template §62) before applying the new constraint.
- **Risk:** Low if no existing duplicates found; medium (requires a data-merge script) if duplicates exist.
- **Rollback:** Revert to old constraint (though this reintroduces the bug).
- **Retest:** Concurrency test (Phase 2B) — fire two concurrent `getOrCreateConversation(A,B)` / `getOrCreateConversation(B,A)` calls against a test project and confirm exactly one row results.

## R4 — Verify and fix the `users` FK-population gap (closes DI-004)

1. **Immediate live verification (read-only, highest priority item in this plan):** Run `SELECT count(*) FROM auth.users u LEFT JOIN public.users pu ON pu.id = u.id WHERE pu.id IS NULL;` against the live/staging project. A non-zero count directly confirms the DI0-level risk (accounts unable to write to 14+ tables).
2. **If gap confirmed:** Either (a) add a `handle_new_user()`-equivalent trigger that also inserts into `public.users` on `auth.users` insert, with a backfill for existing accounts (`INSERT INTO public.users (id) SELECT id FROM auth.users ON CONFLICT DO NOTHING;`), or (b) retarget the affected FKs to `auth.users(id)` directly (consistent with how `private_conversations`/`private_messages`/`dream_entries`-per-migration already do it) and formally deprecate the `users` table (folding any still-needed fields like `notification_prefs`/`prayer_calculation_method` into `profiles`, after confirming nothing currently depends on them — DI-008 already shows no app code does).
3. **Recommended direction:** Option (b) — consolidate on `profiles` as the single user-data table, since `users` is already confirmed unused by all application code (DI-004, DI-008) and the app has clearly been converging on `profiles` as the real source of truth (per the schema.sql comment on the `profiles` table itself: "single source of truth for AuthRepositoryImpl & UserProfileRepository"). This also directly resolves DI-001's `users`-table drift.
- **Schema changes:** Yes — either a new trigger + backfill, or 14+ `ALTER TABLE ... DROP CONSTRAINT ... ADD CONSTRAINT ... REFERENCES profiles(id)` (expand-and-contract: add new FK alongside old, backfill/verify, then drop old).
- **Code changes:** None expected if retargeting FKs only (app never referenced `users` directly).
- **Data repair:** Backfill required either way.
- **Risk:** Medium-high — touches the FK target of most of the schema; must be staged (expand/contract, not a single destructive step) and validated against live data first.
- **Rollback:** Keep old FK constraints until new ones are verified; use a maintenance window.
- **Retest:** After backfill, rerun the detection query from step 1 (expect 0) and perform an end-to-end signup + first cycle-entry write in staging.

## R5 — Add an enforced safety guard to destructive migrations, going forward (closes DI-005)

1. For the already-applied `20260830140000` file: no retroactive change needed to the file itself (rewriting an applied migration is unsafe), but add a code comment/README note in `supabase/migrations/` marking it as historical and **not safe for blind replay** without re-verifying row counts first.
2. Adopt a standing convention for any future destructive (`DROP TABLE`, `TRUNCATE`, destructive `ALTER`) migration: require an enforced precondition, e.g. `DO $$ BEGIN IF EXISTS (SELECT 1 FROM <table> LIMIT 1) THEN RAISE EXCEPTION 'Refusing destructive migration: <table> is not empty'; END IF; END $$;` immediately before the `DROP`/destructive statement, so the safety property is enforced by Postgres itself, not just documented in a comment.
- **Schema changes:** None to existing migrations; adds a process requirement for future ones.
- **Code changes:** None.
- **Data repair:** None.
- **Risk:** Low.
- **Rollback:** N/A.
- **Retest:** N/A (process control); verify via code review checklist going forward.

## R6 — Adopt an append-only migrations policy (closes DI-006)

Document (e.g., in a `supabase/migrations/README.md`) that migration files, once committed, are never deleted — a superseded or never-applied migration should be left in place with a clear "SUPERSEDED — do not apply" header rather than removed from the repository, preserving the audit trail referenced in DI-006.
- **Schema changes:** None. **Code changes:** None (documentation/process). **Risk:** None.

## R7 — Add DB-enforced `updated_at` maintenance (closes DI-007)

1. Create one generic trigger function: `CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;`
2. Attach `BEFORE UPDATE FOR EACH ROW EXECUTE FUNCTION set_updated_at()` to every table with an `updated_at` column (`profiles`, `cycle_entries`, `chat_threads`, `chat_messages`, `community_posts`, `prayer_entries`, `pregnancy_milestones`, `pregnancy_profile`, `wellbeing_logs`).
- **Schema changes:** Yes — one function + 9 triggers, purely additive, no behavior change for callers who already set `updated_at` correctly (DB will simply overwrite with the same "now" semantics on every UPDATE).
- **Code changes:** None required (app can keep setting it too, harmlessly).
- **Data repair:** None.
- **Risk:** Low.
- **Rollback:** Drop triggers.
- **Retest:** UPDATE a row without setting `updated_at` client-side and confirm it still advances.

## R8 — Resolve dead schema surface (closes DI-008)

1. Product/engineering decision: either wire up `adah_ledger`/`istihadah_episodes`/`nifas_records`/`ramadan_records`/`symptoms_log`/`secret_vault_entries`, or formally deprecate them.
2. If deprecating: do **not** drop them silently in the same pass as other work (avoid another DI-005-style incident) — drop only after confirming (live query) they truly hold 0 rows in production, in a dedicated, reviewed migration.
3. Delete the dead `lib/core/services/cycle_log_repository.dart` class (or clearly mark it deprecated/unused) and, once confirmed unreferenced live, drop the `cycle_logs` table in the same dedicated migration as step 2.
- **Schema changes:** Deferred, destructive-but-justified drops in a dedicated future migration, gated on live row-count verification.
- **Code changes:** Remove dead class.
- **Data repair:** None (tables confirmed unused by app; live row count still needs verification before drop).
- **Risk:** Low (code removal) / Low-medium (table drops, once verified empty).
- **Retest:** Confirm build/tests pass after dead-code removal; confirm row counts are 0 immediately before any drop.

## R9 — Decide the architecture for fiqh-state integrity (closes DI-009)

Product/religious-review decision required, not a pure engineering fix: either (a) formally document that fiqh-state derivation is intentionally client-side-authoritative and the unused ledger tables should be retired (fold into R8), or (b) invest in persisting the derivation inputs/outputs server-side with validation. Out of scope for this audit to prescribe which; flagged for explicit sign-off.
- **Schema/code changes:** Depends on decision. **Risk:** N/A until decided.

## R10 — Add cross-field CHECK constraints to `pregnancy_milestones` (closes DI-010)

1. **Detection query:** Check live data for any existing rows violating `due_date > lmp_date` or obviously inconsistent `week`/`trimester` pairs before adding constraints.
2. Add, e.g., `CHECK (due_date IS NULL OR lmp_date IS NULL OR due_date > lmp_date)` and a `week`/`trimester` coherence check (exact bounds to be confirmed with product — e.g., first ≈ weeks 1–13, second ≈ 14–27, third ≈ 28–42).
- **Schema changes:** Additive CHECK constraints (after data-repair if step 1 finds violations). **Risk:** Low-medium, contingent on live data.

## R11 — Add `UNIQUE(user_id, date)` to `cycle_entries`, after confirming the one-entry-per-day assumption (closes DI-011)

1. **Product confirmation first:** Confirm with product/domain owners whether multiple `cycle_entries` rows per user per day are ever legitimate (e.g., a morning and an evening log). If yes, this constraint must instead target a different key (e.g., add a `period_segment` distinguishing field) rather than blindly following the `wellbeing_logs` pattern.
2. **Detection query:** `SELECT user_id, date, count(*) FROM cycle_entries GROUP BY user_id, date HAVING count(*) > 1;` against live data.
3. If confirmed one-per-day and no existing violations (or after merging any found), add `UNIQUE(user_id, date)` (or an `upsert`-friendly equivalent matching the `wellbeing_logs(user_id, log_date)` pattern already proven in this codebase) and switch `CycleTrackingRepositoryImpl`'s local/remote merge key from `entry.id` to `(user_id, date)` accordingly, and use `upsert(..., onConflict: 'user_id,date')`.
- **Schema changes:** Additive UNIQUE constraint, contingent on product confirmation and data-repair.
- **Code changes:** Update merge/upsert key in `cycle_tracking_repository_impl.dart`.
- **Risk:** Medium (behavior-affecting; must confirm domain assumption first).

## R12 — Confirm intended retention behavior for private messages on account deletion (closes DI-012)

Product/privacy sign-off required: confirm whether `private_messages.sender_id ON DELETE CASCADE` (removing a deleted user's messages from the *other* participant's still-active conversation) is intended. If not intended, redesign as a soft-delete/tombstone (e.g., `sender_id` nullable + `SET NULL` + a "deleted user" placeholder in the UI) rather than hard delete.
- **Schema changes:** Contingent on decision (would require `ON DELETE SET NULL` + nullable `sender_id` + app-level "deleted account" rendering).
- **Risk:** Low to assess; medium to implement if changed (touches RLS policies referencing `sender_id`, e.g., "Recipients can mark messages as read" excludes `auth.uid() = sender_id` — would need re-verification against a nullable `sender_id`).

---

## Migration Rollout Requirements (for the highest-risk items — R1, R4, R11)

| Item | Deployment order | Compatibility window | Backfill | Locking risk | Rollback | Monitoring | Success criteria |
|---|---|---|---|---|---|---|---|
| R1 (catch-up migrations) | Additive migrations only, deploy anytime | N/A (additive) | N/A | Low | N/A | CI drift-check | Fresh-DB migration replay succeeds and matches live schema export |
| R4 (users→profiles FK retarget) | Expand (add new FK) → verify → contract (drop old FK) across 14+ tables, staged over multiple releases | Old and new FK both valid during migration window | Yes — backfill `public.users` or repoint FKs | Medium (ALTER TABLE ... ADD/DROP CONSTRAINT can briefly lock large tables) | Keep old constraint until new one verified in production | Live FK-violation error rate on writes to affected tables | Zero FK violations on affected tables post-cutover for 1+ week |
| R11 (cycle_entries UNIQUE) | Backfill/dedupe → add constraint → switch merge key in same release | N/A | Yes, if duplicates found | Low (small-medium table expected) | Drop constraint if issues found | Client-reported upsert conflicts | No user-visible "duplicate entry" errors post-launch |

---

## Remediation Exit Gate

- [ ] Root cause identified for every finding — **done** (see Root-Cause Map above).
- [ ] Constraint/transaction strategy defined — **done** for R3, R7, R10, R11; **pending live data** for exact bounds in R10.
- [ ] Existing bad-data impact assessed — **NOT DONE**, requires live DB access (R1 step 1, R3 step 1, R4 step 1, R10 step 1, R11 step 2 detection queries all still need to be run).
- [ ] Backfill/repair plan exists where necessary — **done** (see R1, R3, R4, R11).
- [ ] Migration order defined for risky changes — **done** (see Migration Rollout Requirements above).
- [ ] Rollback defined where needed — **done**.
- [ ] Cross-version compatibility understood — **done** (expand-and-contract specified for R4).
- [ ] Retest cases defined — **done** (per-item "Retest" line above).
- [ ] Functional/API impacts cross-referenced — R4 and R11 both touch write paths reviewed by this audit; recommend the API/Backend and Functional QA audits re-verify after implementation.

**This plan is proposed only.** None of R1–R12 have been implemented, and no controlled validation (Phase 2B) has been performed as part of this audit.
