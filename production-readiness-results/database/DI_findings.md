# Database & Data Integrity — Phase 2A: Static Verification & Findings

| Field | Value |
|---|---|
| System | Niswah |
| Database engine | PostgreSQL (Supabase) |
| Phase | 2A — Static Verification |
| Audit date | 2026-09-04 |
| Environment | Static repo review only — no live DB access |
| Restrictions | No live DB queries, no migration execution, no data mutation |

Evidence key: 🟧 Confirmed by code/migration text · 🟨 Likely (strong inference) · 🟦 Requires controlled/live test · ⬜ N/A

---

## DI-001 — `schema.sql` and `migrations/` have materially and repeatedly diverged; migrations cannot rebuild the schema from scratch

- **Severity:** DI1 (High) — pre-launch blocker for schema governance; historical instances of this exact drift already caused DI0-grade production breakage (see evidence).
- **Category:** SCHEMA-xx / MIG-xx / MODEL-xx
- **Entities:** `users`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `secret_vault_entries` (10 of 19 tables in `schema.sql`), plus `chat_threads`, `community_posts/comments/likes`.
- **Evidence (🟧 confirmed):**
  - `supabase/schema.sql` defines 19 tables. Only 9 of those table names ever appear in a `CREATE TABLE` statement anywhere in `supabase/migrations/` (`profiles`, `cycle_logs`, `private_conversations`, `private_messages`, `flagged_conversations`, `chat_threads`, `chat_messages`, `educational_resources`, `dream_entries`, `pregnancy_profile`, `wellbeing_logs`, `community_posts`, `community_comments`, `community_likes` — several of which are *not* in `schema.sql` at all, see DI-fallback list below). **10 tables `schema.sql` documents have no `CREATE TABLE` anywhere in the tracked migration history**: `users`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `secret_vault_entries`.
  - Migration `20260822014500_niswah_schema_sync_and_indexes.sql` performs `ALTER TABLE IF EXISTS public.prayer_log RENAME TO prayer_entries`, `ALTER TABLE IF EXISTS public.pregnancy_records RENAME TO pregnancy_milestones`, and `CREATE INDEX ... ON public.cycle_entries(...)` — all of which presuppose tables (`prayer_log`, `pregnancy_records`, `cycle_entries`) that **no prior migration in this repository ever created**. Replaying the tracked migrations in order against an empty database fails at this file.
  - Migration `20260824115900_dr_niswah_chat_threads.sql` contains an explicit inline comment stating: *"These tables are documented in supabase/schema.sql but were never turned into an applied migration, which is why 20260824120000's flagged_conversations.thread_id FK to chat_threads(id) failed with 'relation chat_threads does not exist' — chat_threads was missing on the remote database, not misnamed."* — direct, first-party confirmation of a real production incident caused by trusting `schema.sql` as if it were the live schema.
  - The same migration's comment also documents that `schema.sql`'s `thread_type` CHECK values (previously snake_case) did **not** match the app's Dart enum (`camelCase` `.name` values) and "would have made every 'drNiswah' or 'fiqhAdvisory' thread insert fail the CHECK constraint."
  - Migration `20260825210000_cycle_entries_updated_at_and_fiqh_default.sql`: *"No `updated_at` column existed ... every insert failed with 'Could not find the updated_at column' ... `fiqh_state` is NOT NULL with no default ... every insert failed with a not-null violation."*
  - Migration `20260826090000_cycle_entries_app_columns.sql`: *"every real cloud write to cycle_entries has been failing with 'column does not exist' since before this table was ever successfully written to from the app. This is why logging a haid entry or tapping 'End Haid' on the dashboard silently fails."* — confirms this drift caused **silent, extended production data loss on a core health-tracking feature**.
  - Migration `20260830140000_community_schema_reset.sql`: *"The live community tables had drifted completely from what the Flutter client and schema.sql expect ... Every comment insert and like toggle from the app was silently failing ... masking it by serving canned demo posts instead of surfacing an error."*
  - Direct type contradiction: `schema.sql` line 241 declares `cycle_entries.symptoms JSONB` (nullable, no default); migration `20260826090000` declares `ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS symptoms TEXT[] NOT NULL DEFAULT '{}'`. These cannot both be the live type. `schema.sql`'s own header comment for `cycle_entries` claims it was "Reconciled 2026-08-25 against the actual live table (via information_schema.columns)" and asserts "symptoms is jsonb, not text[]" — i.e., `schema.sql`'s author directly observed the live column and it contradicts what an applied migration declares. Since the migration used `ADD COLUMN IF NOT EXISTS`, it is a **silent no-op** if the column already existed under a different type — a concrete example of exactly the AI-migration hazard the audit template warns about in §41.6/§41.7 (idempotent-looking DDL that silently does nothing when assumptions are wrong).
- **Resolution of the assigned "unknown" (schema.sql vs. migrations relationship):** **CONFIRMED, not unresolvable.** `schema.sql` is a **hand-maintained, periodically and only-partially reconciled approximation of the live schema** — not a generated dump (a generated dump would exactly match some live state at export time and wouldn't itself contain an internal type contradiction with the migrations that supposedly produced it), and not a pure aspirational design doc either (it's been corrected in place against `information_schema` observations at least once, per its own comments, for `chat_threads.thread_type` and `cycle_entries` columns). It is unreliable as a source of truth and has repeatedly been the *cause* of shipped defects when trusted at face value. The `migrations/` directory is simultaneously **incomplete**: significant DDL (10 whole tables, and the original shapes of several renamed tables) exists only on the live database, created outside of version control, with no tracked migration file.
- **Integrity risk:** Any future schema change authored by reading `schema.sql` alone (rather than verifying against the live DB) risks repeating this exact failure mode — a CHECK/NOT NULL/type mismatch that silently breaks writes to a core feature, potentially for an extended period before detection (as happened at least twice already, for cycle tracking and community).
- **Confidence:** CONFIRMED (multiple independent first-party migration-comment admissions plus direct static diff).
- **Launch-blocker status:** YES — not because the *current* live schema is necessarily broken (the reactive fixes appear to have addressed the specific incidents described), but because the **process** that produced these incidents is still in place: there is no single verified source of truth, and the next schema change is exposed to the same risk. At minimum, a live `information_schema` dump must be taken and reconciled into a single authoritative file before further schema changes ship.
- **Remediation category:** Establish one schema source of truth (§10 of template) — see DI_remediation_plan.md R1.

---

## DI-002 — Systemic silent-failure pattern: DB write/read errors are caught and hidden behind local-only or demo-data fallbacks across multiple core features

- **Severity:** DI1 (High), bordering DI0 given confirmed real-world precedent on health-critical data.
- **Category:** TX-xx / ORPH-xx / MODEL-xx (data can silently diverge between client and server with no detection)
- **Entities:** `cycle_entries`, `pregnancy_milestones`, `community_posts`/`community_comments`
- **Evidence (🟧 confirmed by code):**
  - `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart`: `saveCycleLog()` always writes locally first, then attempts `upsertCycleLog()` and explicitly swallows `NetworkFailure`: *"Local save is authoritative for the UI; remote sync is eventually-consistent ... Swallow here so a transient network/schema issue never hides an already-successful local save."* `getCycleLogs()` likewise catches `PostgrestException` (and a bare `catch (_)`) and silently returns local-only data.
  - `lib/features/pregnancy_tracking/data/repositories/pregnancy_tracking_repository_impl.dart`: `saveMilestone()` and `deleteMilestone()` both wrap the remote Supabase call in a bare `catch (_) {}` with comments "Local-first persistence remains authoritative" / "Ignore remote deletion failures."
  - `lib/features/community/data/repositories/community_repository_impl.dart`: catches `PostgrestException` on post-fetch and comment-fetch paths and falls back to `_fallbackPage()` / `_fallbackComments()` (canned/demo content) rather than surfacing an error.
  - Migration `20260830140000`'s own comment names this exact pattern as the mechanism that **masked a live production bug**: *"CommunityRepositoryImpl.getPosts()'s `on PostgrestException` fallback was masking it by serving canned demo posts instead of surfacing an error."*
  - Migration `20260826090000`'s comment confirms the cycle-tracking equivalent already happened in production: cloud writes for cycle/haid logging were failing "since before this table was ever successfully written to from the app," and users would not have seen an error (per the swallow-pattern above) — they would only ever see their local copy.
- **Integrity risk:** `cycle_entries` carries `fiqh_state` — a value with direct religious/practical consequences (prayer and fasting obligations). If a user's device is lost, the app is reinstalled, or she switches devices, any entry that silently failed to sync is **permanently gone** with no record it ever existed, and no error was ever shown to her. There is no reconciliation job, conflict-resolution log, or telemetry surfaced in the reviewed code that would let anyone — user or operator — detect that cloud and local state have diverged. This is not hypothetical: it is the exact failure mode confirmed to have already occurred for `cycle_entries` and `community_posts`.
- **Confidence:** CONFIRMED (code + first-party migration-comment corroboration of a real incident).
- **Launch-blocker status:** YES.
- **Remediation category:** Surface remote-sync failures (at minimum via telemetry/error reporting, ideally a visible "not backed up" indicator + retry queue) and add a reconciliation/backfill path for entries that silently failed historically. See DI_remediation_plan.md R2.

---

## DI-003 — `private_conversations` uniqueness constraint enforces the wrong invariant (ordered pair, not unordered pair) — concurrency-exposed duplicate-conversation bug

- **Severity:** DI2 (Medium) — bounded blast radius (duplicate conversation row + split message history for one pair of users per race), but a genuine, concurrency-exposed invariant violation.
- **Category:** UNIQ-xx / CONC-xx
- **Entity:** `private_conversations`
- **Evidence (🟧 confirmed):**
  - Migration `20260822210000_private_messaging.sql`: `CONSTRAINT unique_pair UNIQUE (participant_one, participant_two)`, with the migration's own header comment stating the intent: *"Enforce one conversation per unordered pair of users."* A plain `UNIQUE(a, b)` constraint enforces uniqueness of the **ordered** tuple — `(A, B)` and `(B, A)` are distinct as far as Postgres is concerned. The stated intent is not what was implemented.
  - `lib/features/private_messaging/data/repositories/private_messaging_repository.dart`, `getOrCreateConversation()`: performs a **check-then-act** (SELECT with an `.or(and(...), and(...))` covering both orderings, then INSERT with `participant_one: currentUserId, participant_two: otherUserId` in caller-supplied, non-normalized order) — a classic TOCTOU race. If user A and user B both tap "message" on each other at close to the same time, `getOrCreateConversation(A, B)` and `getOrCreateConversation(B, A)` can each complete their SELECT before either INSERT commits, both see "no existing conversation," and both INSERT — producing rows `(A, B)` and `(B, A)`, which the `UNIQUE(participant_one, participant_two)` constraint does **not** reject because the tuples differ in order.
- **Integrity risk:** Two conversation threads exist for the same pair of users; subsequent messages and the `fetchConversations()` `.or(...)` query will show both, fragmenting message history between two threads with no merge path.
- **Confidence:** CONFIRMED by static logic analysis (both the DB constraint text and the exact race window in the app code are directly readable); the race itself is a 🟦 requires-controlled-test claim for whether it manifests in practice under real load, but the absence of any protection against it is 🟧 confirmed.
- **Launch-blocker status:** Recommended but not mandatory — low blast radius per occurrence, but trivial to fix (see remediation) and worth doing before launch given messaging is a user-trust-sensitive feature.
- **Remediation category:** Normalize participant order at write time (e.g., always store the lexicographically-smaller UUID as `participant_one`) and/or replace the UNIQUE constraint with a normalized generated column, or a unique index on `LEAST(participant_one,participant_two), GREATEST(...)`. See DI_remediation_plan.md R3.

---

## DI-004 — `users` table FK target is never populated by any tracked code path; write-path integrity across ~14 tables is UNKNOWN and requires urgent live verification

- **Severity:** UNKNOWN — could be DI0 if unresolved in production (would mean foreign-key violations on the majority of the app's cloud writes for every account), DI4/non-issue if some untracked mechanism populates it correctly. **Must be classified as a launch-blocking unknown per template §68 NO-GO criterion "Critical write behavior is unknown."**
- **Category:** REL-xx / ORPH-xx
- **Entities:** `chat_threads`, `chat_messages`, `flagged_conversations`, `community_posts/comments/likes`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `pregnancy_profile`, `wellbeing_logs`, `dream_entries` (per `schema.sql`) — all declared `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`.
- **Evidence (🟧 confirmed absence of a population path; 🟨 likely consequence, 🟦 requires live verification):**
  - Repo-wide search (`grep -rn "\.from('users')" lib --include="*.dart"`) returns **zero results** — no Flutter code anywhere reads or writes the `users` table.
  - Repo-wide search for `INSERT INTO.*users` and `public.users` across `supabase/` (migrations + edge functions) returns **zero results**.
  - The only auto-provisioning trigger found, `handle_new_user()` (migration `20260820174500`), inserts a row into `public.profiles` **only** — it does not touch `public.users`.
  - Every field the `users` table defines that's app-domain-specific (`premium_status`, `premium_expires_at`, `avg_cycle_length`, `avg_haid_duration`, `known_adah_days`, `adah_confidence`, `goal_flags`, `conditions`, `notification_prefs`, `prayer_calculation_method`, `location_lat/lng`) has **zero references** anywhere in `lib/` (`grep -rln "premium_status\|premium_expires_at\|isPremium\|premiumStatus" lib` → no matches) — the table appears entirely vestigial from the app's perspective.
  - However, `CREATE TABLE chat_threads (... REFERENCES users(id) ...)` (migration `20260824115900`) and equivalently-shaped `CREATE TABLE` statements for `pregnancy_profile`, `wellbeing_logs`, `community_posts/comments/likes` **were confirmed applied** (their own comments describe fixing real production incidents by *adding* these tables) — Postgres validates a `REFERENCES` target's existence at `CREATE TABLE` time, so `public.users` **must** exist live for those migrations to have succeeded at all.
  - Given `wellbeing_logs` and `pregnancy_profile` writes are *not* wrapped in the silent-swallow pattern (DI-002) — `WellbeingRepository.upsertToday()` explicitly rethrows `PostgrestException` as a surfaced `NetworkFailure` — and no code comment or migration anywhere documents an FK-violation incident on these tables (unlike the `chat_threads`/`cycle_entries`/community incidents, which *are* documented), it is **plausible but not verified** that `users` rows do get created for real accounts through some mechanism not captured in this repository (e.g., a live-only trigger, a Supabase dashboard-configured hook, or manual backfill).
- **Integrity risk:** If no such mechanism exists (or exists but is broken/inconsistent), every new user's writes to 14+ FK-dependent tables fail with a foreign-key violation (Postgres error 23503). For `cycle_entries`, `pregnancy_milestones`, and `community_*`, this failure mode is **actively hidden from the user** by DI-002's swallow pattern, meaning it could be silently, currently broken with no operator visibility.
- **Confidence:** Absence-of-population-path is CONFIRMED by static search. Live consequence is UNKNOWN — this specific item **requires querying the live database** (e.g. `SELECT count(*) FROM auth.users u LEFT JOIN public.users pu ON pu.id = u.id WHERE pu.id IS NULL;`) or attempting a real signup + cycle-entry write against a staging project, which this audit is not authorized to do.
- **Launch-blocker status:** YES — must be verified before launch. This is precisely the class of unknown the template's NO-GO rule targets ("Critical write behavior is unknown").
- **Remediation category:** Immediate live verification (read-only query), then either (a) confirm and document the existing population mechanism, or (b) add a `handle_new_user()`-style trigger to populate `public.users` alongside `public.profiles`, or (c) retarget all these FKs to `auth.users(id)` directly (matching how `private_conversations`, `private_messages`, `cycle_logs`, and `dream_entries`-per-migration already do it) and drop the unused `users` table entirely, consolidating on `profiles`. See DI_remediation_plan.md R4.

---

## DI-005 — Destructive `DROP TABLE ... CASCADE` migration has no enforced safety guard against replay on a populated environment

- **Severity:** DI1 (High) — pre-launch blocker for migration-safety process, even though current documented risk (0 rows at time of authoring) is low.
- **Category:** MIG-xx
- **Entity:** `community_posts`, `community_comments`, `community_likes` (and predecessor tables `community_post_comments`, `community_post_likes`)
- **Evidence (🟧 confirmed):**
  - `supabase/migrations/20260830140000_community_schema_reset.sql`: `DROP TABLE IF EXISTS community_post_likes CASCADE; DROP TABLE IF EXISTS community_post_comments CASCADE; DROP TABLE IF EXISTS community_posts CASCADE;` followed by fresh `CREATE TABLE` statements. Safety rationale is stated **only as a code comment** — *"All three tables were confirmed empty (0 rows) before this migration, so a drop-and-recreate is safe here"* — with **no SQL-level guard** (e.g., a `DO $$ ... IF EXISTS (SELECT 1 FROM community_posts LIMIT 1) THEN RAISE EXCEPTION ... END $$;` precondition check) enforcing that assertion at execution time.
  - Migrations are, by nature, replayable artifacts (fresh environments, CI, disaster-recovery rebuilds, or a future accidental `supabase db reset` against the wrong target all replay the full migration sequence). If this file is ever applied to an environment where these tables are *not* empty (e.g., a staging DB seeded with QA data, or a future environment provisioning mistake), it will **irreversibly delete all community posts, comments, and likes** with no backup or rollback step included.
- **Integrity risk:** Real, permanent data loss of user-generated community content if replayed against non-empty data; no compensating control exists in the file itself.
- **Confidence:** CONFIRMED (direct SQL text; the safety claim is explicitly comment-only, not enforced).
- **Launch-blocker status:** Recommended — the specific historical execution was likely safe (comment claims 0 rows), but the **file, as committed, remains a live landmine** for any future replay. Should be neutralized before other teams/environments start applying this migration sequence.
- **Remediation category:** Add an idempotency/precondition guard, or mark this migration as historical/already-applied and unsuitable for replay (e.g., via a documented one-time manual-execution convention), and adopt a policy requiring an explicit row-count guard on any future destructive migration. See DI_remediation_plan.md R5.

---

## DI-006 — Migration history has been altered outside normal append-only practice; referenced migrations are missing from the repository

- **Severity:** DI3 (Low) — process/auditability concern, not a current corruption risk.
- **Category:** MIG-xx / AUDIT-xx
- **Evidence (🟧 confirmed):**
  - `20260830140000_community_schema_reset.sql`'s comment: *"This supersedes the never-applied 20260829120000_community_likes.sql and 20260829130000_community_text_only_constraints.sql, folding both into a single consistent definition below."* **Neither file exists anywhere in `supabase/migrations/`** in this repository.
- **Integrity risk:** The tracked migration history cannot be fully reconstructed from version control alone; someone reviewing `git log` on the migrations directory cannot see the full decision trail (two migrations were apparently authored, never applied, and then deleted/never-committed rather than left in place with a no-op marker). This reduces confidence in the completeness of the rest of the history (reinforces DI-001) and removes an audit trail that could otherwise explain intermediate schema states.
- **Confidence:** CONFIRMED (explicit reference to non-existent files).
- **Launch-blocker status:** NO — advisory.
- **Remediation category:** Adopt an append-only migrations policy going forward (never delete a migration file once committed, even a superseded/never-applied one — mark it explicitly instead). See DI_remediation_plan.md R6.

---

## DI-007 — No DB-level `updated_at` maintenance; every table relies on application code to set it correctly on every write

- **Severity:** DI3 (Low)
- **Category:** NULL-xx / TX-xx
- **Entities:** `profiles`, `cycle_entries`, `chat_threads`, `chat_messages`, `community_posts`, `prayer_entries`, `pregnancy_milestones`, `pregnancy_profile`, `wellbeing_logs`
- **Evidence (🟧 confirmed):** Repo-wide search for `CREATE TRIGGER` across `supabase/schema.sql` and all migrations finds exactly **two** triggers: `on_auth_user_created` (provisions `profiles` on signup) and `trg_touch_private_conversation` (updates `private_conversations.updated_at` when a message is inserted). No other table has an `updated_at`-maintaining trigger. Migration comments for `pregnancy_profile` and `wellbeing_logs` explicitly acknowledge this by design: *"No triggers — updated_at is set explicitly by the app on every write."*
- **Integrity risk:** Any write path that omits `updated_at` (a future code change, an admin SQL edit, a partial `UPDATE` statement, a client bug) silently leaves a stale timestamp with no DB-level correction — low individual impact, but a broadly-applicable gap across nearly every table in the schema, and inconsistent with best practice for a schema this size.
- **Confidence:** CONFIRMED.
- **Launch-blocker status:** NO — backlog-acceptable.
- **Remediation category:** Add a generic `BEFORE UPDATE` trigger function (`updated_at = now()`) attached to every table that has the column. See DI_remediation_plan.md R7.

---

## DI-008 — Six tables plus one legacy repository class are entirely dead / unused, including a parallel duplicate of the core cycle-tracking table

- **Severity:** DI4 (Observation) with one DI3 sub-item (parallel schema risk).
- **Category:** MODEL-xx (§41.4 "parallel sources of truth" / §41.6 "incomplete refactors")
- **Entities:** `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log`, `secret_vault_entries`, `cycle_logs`
- **Evidence (🟧 confirmed):** Repo-wide search for each table name (`grep -rln "'<table>'" lib`) returns **zero matches** in `lib/` for all seven names. Additionally, `lib/core/services/cycle_log_repository.dart` implements a full CRUD repository against the `cycle_logs` table (created in the very first migration, with a different, simpler shape than the actively-used `cycle_entries` table — `start_date`/`end_date`/`bleeding_intensity` vs. `date`/`fiqh_state`/`flow_intensity`/etc.), but `grep -rln "CycleLogRepository\b" lib` (excluding its own definition file) returns **zero matches** — this class has no callers anywhere in the app.
- **Integrity risk:** None currently (nothing writes to these tables, so no corruption risk today). The risk is prospective: `cycle_logs` is a structurally incompatible parallel table for the same domain concept as `cycle_entries`; if a future change mistakenly re-wires cycle-tracking through the dead `CycleLogRepository` class (e.g., during a refactor, or because a new developer finds it via autocomplete and doesn't realize it's dead), cycle data would silently split across two incompatible tables. The five unused fiqh-ledger tables (`adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log`) represent designed-but-abandoned durable storage for religious-state tracking — see DI-009 for the resulting auditability gap.
- **Confidence:** CONFIRMED (static grep across full `lib/` tree).
- **Launch-blocker status:** NO.
- **Remediation category:** Either wire up or formally deprecate/drop the dead tables and the dead `CycleLogRepository` class; document the decision either way. See DI_remediation_plan.md R8.

---

## DI-009 — Religious/fiqh state (`fiqh_state`) is derived client-side only and never validated or reconciled against the DB, while purpose-built ledger tables for exactly this sit unused

- **Severity:** DI3 (Low-Medium) — no confirmed active corruption, but a real auditability/correctness gap given the app's domain.
- **Category:** INV-xx / AUDIT-xx
- **Entities:** `cycle_entries.fiqh_state`, `adah_ledger`, `istihadah_episodes`, `nifas_records`
- **Evidence (🟧 confirmed):** `schema.sql`'s `cycle_entries` header comment: *"fiqh_state is derived client-side from `flow` in dashboard_screen.dart's `_currentFiqhState()`, never read back from this column."* The tables purpose-built for durable, auditable fiqh-state tracking (`adah_ledger` = menstrual baseline ledger, `istihadah_episodes` = irregular bleeding, `nifas_records` = postpartum) are confirmed unused by the app (DI-008). There is no CHECK constraint or trigger anywhere preventing, e.g., two overlapping `HAID` periods for the same user, or logically inconsistent `fiqh_state` transitions over time.
- **Integrity risk:** For a health/religious app whose core value proposition is correctly determining prayer/fasting obligations from bleeding-pattern data, the authoritative logic lives entirely in client code with no durable, auditable, DB-verifiable trail of *why* a given fiqh determination was made — if a user disputes a determination, or the client-side logic has a bug, there is no server-side ledger to reconcile against.
- **Confidence:** CONFIRMED (explicit code/schema comment) for the "derived client-side, not persisted-and-validated" claim; the *consequence* (incorrect fiqh determinations occurring in practice) is UNKNOWN/not verified — would require either live data sampling or a client-logic audit (out of this audit's scope; cross-reference Functional QA / Code Quality audits for `_currentFiqhState()` correctness itself).
- **Launch-blocker status:** NO — but recommended for product/religious-review sign-off given domain sensitivity (cross-reference: this is arguably more of a Functional/Privacy-Compliance concern than a pure data-integrity one; noted here because it directly explains why several schema.sql tables sit unused).
- **Remediation category:** Product decision required — either formally retire the unused ledger tables (documenting that fiqh logic is client-authoritative by design) or invest in persisting/validating fiqh-state derivation server-side. See DI_remediation_plan.md R9.

---

## DI-010 — `pregnancy_milestones` has no cross-field consistency checks and no de-duplication constraint

- **Severity:** DI3 (Low)
- **Category:** CHECK-xx / UNIQ-xx
- **Entity:** `pregnancy_milestones`
- **Evidence (🟧 confirmed):** `schema.sql` lines 340–356: no `CHECK` constraint relates `due_date`/`lmp_date` (e.g., `due_date > lmp_date`), none relates `week`/`current_week`/`trimester` (e.g., trimester `'first'` implying `week` roughly 1–13), and no `UNIQUE` constraint bounds one row per `(user_id, date)` or `(user_id, week)` even though the table is described as a milestone/journal log. `PregnancyTrackingRepositoryImpl.saveMilestone()` (read in full) performs no client-side validation before `upsert()` — it spreads `milestone.toJson()` directly.
- **Integrity risk:** Nothing prevents a logically-impossible row (e.g., `due_date` before `lmp_date`, or `trimester = 'first'` with `week = 39`) at either the DB or app layer; low blast radius (display/report only, no downstream financial or safety-critical automated action was found consuming these fields), but a genuine unenforced-at-any-layer invariant.
- **Confidence:** CONFIRMED.
- **Launch-blocker status:** NO.
- **Remediation category:** Add CHECK constraints for basic date/week/trimester coherence. See DI_remediation_plan.md R10.

---

## DI-011 — `cycle_entries` has no uniqueness constraint on `(user_id, date)`, unlike the otherwise-similar `wellbeing_logs`

- **Severity:** DI2 (Medium)
- **Category:** UNIQ-xx / ORPH-xx
- **Entity:** `cycle_entries`
- **Evidence (🟧 confirmed):** `wellbeing_logs` (migration `20260825120000`) correctly has `UNIQUE (user_id, log_date)` to enforce "one check-in per day." `cycle_entries` has no equivalent constraint on `(user_id, date)` in `schema.sql` or any migration, despite being a per-day log conceptually. `CycleTrackingRepositoryImpl.getCycleLogs()` merges local and remote entries into a map **keyed by `entry.id`** (not by date), so two entries with different `id`s but the same `date` (e.g., produced by a retried/duplicated local save, or a bug in the local data source) would **not** be de-duplicated by the merge logic either.
- **Integrity risk:** Multiple, potentially contradictory `cycle_entries` rows (different `fiqh_state`/`flow_intensity`) for the same calendar day are possible, which directly affects the derived fiqh determination this table exists to support (see DI-009) and would produce a confusing cycle history in the UI.
- **Confidence:** CONFIRMED (schema + merge-logic read).
- **Launch-blocker status:** Recommended, not mandatory (bounded, recoverable via manual data cleanup; UX-level rather than corruption-level).
- **Remediation category:** Add `UNIQUE(user_id, date)` (after confirming no legitimate multi-entry-per-day use case exists — e.g. logging both a morning and evening symptom note — in which case a different constraint/dedup key is needed). See DI_remediation_plan.md R11.

---

## DI-012 — Account deletion cascades into shared private-message history the *other* participant did not delete

- **Severity:** DI3 (Low) — intentional-looking design trade-off, flagged for explicit product sign-off rather than as a bug.
- **Category:** DEL-xx
- **Entity:** `private_messages`, `private_conversations`
- **Evidence (🟧 confirmed):** `private_messages.sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE`. If user A deletes her account, every message she sent — including messages inside conversations that user B still has and can see — is hard-deleted, not soft-deleted/tombstoned. `private_conversations` itself also cascades fully on either participant's deletion.
- **Integrity risk:** Not a corruption risk, but a retention/UX behavior worth explicit confirmation: user B's conversation history silently loses A's half of the conversation (or the whole thread) the moment A deletes her account, with no tombstone ("this user deleted their account") shown.
- **Confidence:** CONFIRMED (schema read); whether this is the intended product behavior is UNKNOWN (cross-reference Privacy/Compliance audit).
- **Launch-blocker status:** NO — flagged for product/privacy sign-off.
- **Remediation category:** Confirm intended behavior; if unintended, consider a tombstone/soft-delete pattern for messages on account deletion. See DI_remediation_plan.md R12.

---

## Static Verification Matrix (summary)

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| SCHEMA-01 | Schema definition | schema.sql vs. migrations | Migrations should be able to reproduce schema.sql's schema from empty DB | DI-001 | **FAIL** |
| REL-01 | FK coverage | `users` FK target across 14+ tables | `users` should be populated for every account before dependent writes occur | DI-004 | **INCONCLUSIVE** (requires live verification) |
| UNIQ-01 | Uniqueness | `pregnancy_profile.user_id` | One profile per user | schema.sql line 363 `UNIQUE` | **PASS** |
| UNIQ-02 | Uniqueness | `wellbeing_logs(user_id, log_date)` | One check-in per user per day | migration 20260825120000 | **PASS** |
| UNIQ-03 | Uniqueness | `community_likes(post_id, user_id)` | One like per user per post | migration 20260830140000 | **PASS** |
| UNIQ-04 | Uniqueness/concurrency | `private_conversations(participant_one, participant_two)` | One conversation per unordered pair | DI-003 | **FAIL** |
| UNIQ-05 | Uniqueness | `cycle_entries(user_id, date)` | Expected one entry per day (by analogy to wellbeing_logs) | DI-011 | **FAIL** |
| TX-01 | Silent-failure / eventual consistency | `cycle_entries`, `pregnancy_milestones`, `community_*` remote writes | Write failures should be surfaced/detectable | DI-002 | **FAIL** |
| MIG-01 | Migration safety | `20260830140000_community_schema_reset.sql` | Destructive migrations should have enforced (not comment-only) safety guards | DI-005 | **FAIL** |
| MIG-02 | Migration completeness | `supabase/migrations/` | Referenced migrations should exist in repo | DI-006 | **FAIL** |
| AUDIT-01 | updated_at maintenance | 9+ tables | DB-enforced or consistently app-enforced | DI-007 | **FAIL (app-only)** |
| MODEL-01 | Dead schema | 6 tables + `cycle_logs`/`CycleLogRepository` | No orphaned parallel schema | DI-008 | **FAIL (observation)** |
| INV-01 | Fiqh-state integrity | `cycle_entries.fiqh_state` | DB-backed or validated invariant | DI-009 | **FAIL (observation)** |
| CHECK-01 | Domain validation | `pregnancy_milestones` | Basic date/week coherence checks | DI-010 | **FAIL (observation)** |
| DEL-01 | Delete/retention | `private_messages` on account deletion | Intentional, documented behavior | DI-012 | **INCONCLUSIVE (needs product sign-off)** |

**Static Verification Exit Gate:** Reviewed per template §43 — PK strategy, relationships, uniqueness, nullability/defaults, invariants, migration safety, model/schema drift, and AI-generated-schema risks were all reviewed statically (see DI_discovery.md §1–8 and findings above). Transaction-boundary and concurrency items that require actual execution (e.g., proving the DI-003 race manifests, or resolving DI-004) are explicitly marked INCONCLUSIVE/requires-controlled-test rather than assumed PASS or FAIL.
