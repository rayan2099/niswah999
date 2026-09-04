# Database & Data Integrity — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | HEAD at audit time (13a9387) |
| Database engine | PostgreSQL (Supabase-managed) |
| Database version | UNKNOWN — not verified (no live DB access) |
| ORM / Data layer | `supabase_flutter` SDK (PostgREST over HTTP), raw SQL migrations, no ORM |
| Phase | Phase 1 — Discovery |
| Audit date | 2026-09-04 |
| Environment | Local static repo only |
| Environment status | 🧪 Controlled (read-only, no DB connection) |
| Restrictions | No live DB connection; no migrations executed; no schema introspection via `information_schema`; no row counts; no runtime tests |
| Report created | DI_discovery.md |

---

## 1. Persistence Architecture Inventory

| Component | Technology | Purpose | Source of truth? | Writes data? | Criticality | Evidence |
|---|---|---|---|---|---|---|
| Supabase Postgres | PostgreSQL | Primary application datastore | Yes (live DB — not directly inspectable) | Yes | Critical | `supabase/schema.sql`, `supabase/migrations/*.sql` |
| `supabase/schema.sql` | Hand-maintained SQL file | Claims to document current schema | Partial/unreliable — see Finding DI-001 | No (documentation only) | High | 507 lines, 19 `CREATE TABLE` statements |
| `supabase/migrations/` | Timestamped SQL migration files | Deploy history / intended schema evolution | Partial — incomplete (see DI-001) | Yes, when applied | Critical | 15 files, `20260820174500`–`20260830140000` |
| Device-local storage (`LocalCycleTrackingDataSource`, `LocalPregnancyTrackingDataSource`, SharedPreferences-style) | Local device storage | Offline-first cache/authoritative-for-UI copy of cycle logs, pregnancy milestones | Effectively yes, for UI purposes — see DI-002 | Yes | Critical | `lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart`, `lib/features/pregnancy_tracking/data/datasources/local_pregnancy_tracking_data_source.dart` |
| Supabase Edge Function `dr-niswah-chat` | Deno/TypeScript | AI chat backend; writes `flagged_conversations` via service role (bypasses RLS) | Yes, for flagged_conversations | Yes | High (clinical-review data) | `supabase/functions/dr-niswah-chat/index.ts` |
| Supabase Realtime | Postgres logical replication | Live message delivery for `private_messages` | No | No (read-only stream) | Medium | `private_messaging_repository.dart` `subscribeToMessages` |
| Supabase Auth (`auth.users`) | Managed by Supabase | Identity/session | Yes, for identity | Yes (via SDK) | Critical | referenced throughout migrations |

No caches, search engines, queues, analytics warehouses, or external persistence providers were found referenced in `supabase/` or `lib/core/network/`. No read replicas or backup/restore tooling found in-repo (see Out-of-Scope in the readiness report).

---

## 2. Entity Inventory

| Entity ID | Table | Purpose | Primary key | Ownership (FK) | Criticality | Personal/health data? |
|---|---|---|---|---|---|---|
| ENT-001 | `users` | Legacy/parallel user profile row (madhhab, premium status, cycle averages) | `id` (= `auth.users.id`) | self | Low — appears unused by app code (see DI-008) | Yes |
| ENT-002 | `profiles` | Actual single source of truth for auth/profile data used by the app | `id` (= `auth.users.id`) | self | Critical | Yes |
| ENT-003 | `chat_threads` | AI assistant / Dr. Niswah / dream-interpreter / fiqh-advisory chat threads | `id` | `user_id → users.id` | High | Yes (health/religious) |
| ENT-004 | `chat_messages` | Messages within a chat thread | `id` | `thread_id → chat_threads.id`, `user_id → users.id` | High | Yes |
| ENT-005 | `flagged_conversations` | Clinical-review log of red-flagged AI chat content, service-role-only writes | `id` | `user_id → users.id`, `thread_id → chat_threads.id` | High (clinical/safety) | Yes |
| ENT-006 | `community_posts` | Public community forum posts | `id` | `user_id → users.id` | High | Potentially (health/anonymous posts) |
| ENT-007 | `community_comments` | Comments on posts | `id` | `post_id → community_posts.id`, `user_id → users.id` | Medium | Potentially |
| ENT-008 | `community_likes` | Post likes | `id` | `post_id`, `user_id` | Low | No |
| ENT-009 | `private_conversations` | 1:1 DM threads between two users | `id` | `participant_one/two → auth.users.id` | High | Yes |
| ENT-010 | `private_messages` | DM message content | `id` | `conversation_id`, `sender_id → auth.users.id` | High | Yes |
| ENT-011 | `cycle_entries` | Core menstrual-cycle / fiqh tracking log (haid, flow, fiqh_state) | `id` | `user_id → users.id` | Critical (religious + health) | Yes |
| ENT-012 | `cycle_logs` | Legacy/duplicate cycle table (start/end date, bleeding_intensity) | `id` | `user_id → auth.users.id` | Dead — unused (see DI-008) | Yes |
| ENT-013 | `symptoms_log` | Per-day symptom records | `id` | `user_id`, `cycle_entry_id` | Unused by app (see DI-008) | Yes |
| ENT-014 | `prayer_entries` | Prayer completion / fiqh status log | `id` | `user_id → users.id` | Critical (religious) | Yes |
| ENT-015 | `adah_ledger` | Menstrual-baseline (ʿādah) fiqh ledger | `id` | `user_id` | Unused by app (see DI-008) | Yes |
| ENT-016 | `istihadah_episodes` | Irregular-bleeding fiqh tracking | `id` | `user_id` | Unused by app (see DI-008) | Yes |
| ENT-017 | `nifas_records` | Postpartum bleeding fiqh tracking | `id` | `user_id` | Unused by app (see DI-008) | Yes |
| ENT-018 | `ramadan_records` | Fasting/qadha tracking | `id` | `user_id` | Unused by app (see DI-008) | Yes |
| ENT-019 | `pregnancy_milestones` | Multi-row pregnancy log/journal | `id` | `user_id → users.id` | High | Yes |
| ENT-020 | `pregnancy_profile` | Single-row-per-user pregnancy personalization context for AI chat | `id`, `UNIQUE(user_id)` | `user_id → users.id` | High | Yes |
| ENT-021 | `secret_vault_entries` | Client-side-encrypted private notes | `id` | `user_id` | Unused by app (see DI-008) | Yes (encrypted) |
| ENT-022 | `educational_resources` | Public read-only content library | `id` | none (no user FK) | Low | No |
| ENT-023 | `dream_entries` | Dream journal + AI interpretation | `id` | `user_id → users.id` (schema.sql) / `auth.users.id` (migration) | Medium | Yes |
| ENT-024 | `wellbeing_logs` | Daily mood/energy/sleep check-in, one row per user per day | `id`, `UNIQUE(user_id, log_date)` | `user_id → users.id` | High | Yes |

Notifications: no dedicated Supabase table exists for `lib/features/notifications/`; this feature appears to be locally-scheduled (device notifications) plus reads of `notification_prefs` — not independently verified in depth (out of primary DB-integrity scope, no persistence risk identified).

---

## 3. Relationship Inventory (selected — full detail in schema/migration text)

| Parent | Child | Relationship | FK | Required? | Delete behavior | Evidence |
|---|---|---|---|---|---|---|
| `auth.users` | `profiles` | 1:1 | `profiles.id` | Yes | CASCADE | migration 20260820174500 |
| `users` | `cycle_entries`, `chat_threads`, `community_posts`, `prayer_entries`, `pregnancy_milestones`, `pregnancy_profile`, `wellbeing_logs`, `dream_entries` (schema.sql), `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log`, `secret_vault_entries` | 1:N | `user_id` | Yes (NOT NULL) | CASCADE | schema.sql + matching CREATE TABLE migrations |
| `chat_threads` | `chat_messages` | 1:N | `thread_id` | Yes | CASCADE | migration 20260824115900 |
| `chat_threads` | `flagged_conversations` | 1:N | `thread_id` | No (nullable) | CASCADE | migration 20260824120000 |
| `community_posts` | `community_comments`, `community_likes` | 1:N | `post_id` | Yes | CASCADE | migration 20260830140000 |
| `private_conversations` | `private_messages` | 1:N | `conversation_id` | Yes | CASCADE | migration 20260822210000 |
| `auth.users` | `private_conversations` (×2 FKs) | 1:N | `participant_one`, `participant_two` | Yes | CASCADE | migration 20260822210000 |
| `nifas_records` | `pregnancy_milestones` | 1:N (optional link) | `nifas_id` | No | SET NULL | schema.sql line 347 |
| `cycle_entries` | `symptoms_log` | 1:N (optional link) | `cycle_entry_id` | No | SET NULL | schema.sql line 262 |

**Flagged relationship concerns** (detailed in DI_findings.md):
- `users` table is the FK target for ~14 tables, but no code path or tracked migration ever inserts a row into `users` — see **DI-004**.
- `private_conversations` UNIQUE constraint is on the *ordered* pair `(participant_one, participant_two)`, but the invariant it is meant to enforce ("one conversation per unordered pair") requires an *unordered* uniqueness check — see **DI-003**.
- All user-owned content cascades fully on `auth.users` deletion, including a user's sent messages inside *other* users' shared private conversations — see **DI-020** (retention note) in findings.

---

## 4. Schema Source-of-Truth Inventory

| Concept | Sources | Canonical source | Drift risk | Notes |
|---|---|---|---|---|
| Full schema | `supabase/schema.sql`, `supabase/migrations/*.sql`, live Supabase project (not accessible) | **Unclear / contested** — see DI-001 | **HIGH — confirmed, not inferred** | `schema.sql` is explicitly described in its own inline comments as reconciled by hand against `information_schema.columns` on specific dates; migrations contain comments describing real production breakage caused by trusting `schema.sql` |
| `cycle_entries` columns | `schema.sql` (reconciled 2026-08-25 comment), 3 separate migrations (20260822014500, 20260825210000, 20260826090000) | Live DB (unverifiable) | HIGH | `symptoms` typed `JSONB` in schema.sql vs `TEXT[] NOT NULL DEFAULT '{}'` in the 20260826090000 migration — direct type contradiction, see DI-001 |
| `chat_threads.thread_type` allowed values | `schema.sql`, migration 20260824115900 | Migration (confirmed matches app enum) | Resolved but historically HIGH | Migration's own comment documents `schema.sql` previously had wrong (snake_case) values that would have failed every insert |
| Community tables (posts/comments/likes) | `schema.sql`, migration 20260830140000 (reset) | Migration (post-reset) | Resolved but historically HIGH | Reset migration comment documents the live tables were named/shaped completely differently (`community_post_comments`, `community_post_likes`, `author_id` instead of `user_id`) before the reset |
| Application entity models | `lib/features/*/domain/entities/*.dart` | App-side, hand-written, not generated from DB schema | HIGH | No code generation / schema-to-Dart pipeline found; every mismatch has historically been caught only by production runtime failures, per migration comments |

**Resolution of the assigned unknown (`schema.sql` vs `migrations/`)** — see full discussion in DI_findings.md Finding **DI-001**. Summary: this was **resolvable statically, and the answer is CONFIRMED, not UNKNOWN**: `schema.sql` is a hand-maintained, periodically-reconciled *approximation* of the live schema — not a generated dump, and not authoritative design doc either. It has repeatedly drifted from what migrations actually created/altered live, and this drift has caused real, documented production incidents (see DI-001). The `migrations/` directory is also incomplete: at least 10 of the 19 tables `schema.sql` documents (`users`, `cycle_entries`, `symptoms_log`, `prayer_entries`, `adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `pregnancy_milestones`, `secret_vault_entries`) have **no `CREATE TABLE` statement anywhere in `supabase/migrations/`** — meaning replaying every migration in this repository against an empty database would fail (e.g. migration `20260822014500` tries to `RENAME` `prayer_log`, `ALTER TABLE cycle_entries`, and `CREATE INDEX ... ON cycle_entries` — none of which exist yet at that point in the migration sequence). This means these tables were created directly against the live database outside of version control at some point. **What remains genuinely UNKNOWN (requires live DB access):** the exact current live column-level definition of every table, whether the live DB matches `schema.sql`, `migrations/`, both, or neither, and whether a `public.users` row is actually populated for real accounts (see DI-004).

---

## 5. Migration Inventory

| Migration | Order | Purpose | Additive/Destructive | Reversible? | Data migration? | Depends on | Status |
|---|---|---|---|---|---|---|---|
| `20260820174500_niswah_production_schema_security.sql` | 1 | Create `profiles`, `cycle_logs`; RLS; auto-provision trigger | Additive | No (no down migration) | No | none (assumes `auth.users` exists) | Applied (inferred) |
| `20260822014500_niswah_schema_sync_and_indexes.sql` | 2 | Rename `prayer_log`→`prayer_entries`, `pregnancy_records`→`pregnancy_milestones`; create `educational_resources`, `dream_entries`; add `profiles` columns; add indexes | Mixed (rename + additive) | No | Yes (backfill `display_name`) | Assumes `prayer_log`, `pregnancy_records`, `cycle_entries`, `users` already exist **outside this migration history** (see DI-001) | Applied (inferred) |
| `20260822210000_private_messaging.sql` | 3 | Create `private_conversations`, `private_messages`, RLS, triggers | Additive | No | No | `auth.users` | Applied (inferred) |
| `20260824115900_dr_niswah_chat_threads.sql` | 4 | Create `chat_threads`, `chat_messages` (retroactive fix for missing table) | Additive | No | No | `users` (pre-existing, untracked) | Applied — comment documents this fixed a live "relation does not exist" production error |
| `20260824120000_dr_niswah_flagged_conversations.sql` | 5 | Create `flagged_conversations` | Additive | No | No | `chat_threads`, `users` | Applied (inferred) |
| `20260824130000_pregnancy_profile.sql` | 6 | Create `pregnancy_profile` (unique per user) | Additive | No | No | `users` | Applied (inferred) |
| `20260825120000_wellbeing_logs.sql` | 7 | Create `wellbeing_logs` | Additive | No | No | `users` | Applied (inferred) |
| `20260825130000_flagged_conversations_self_read.sql` | 8 | Add self-read RLS policy to `flagged_conversations` | Additive (policy only) | No | No | migration 5 | Applied (inferred) |
| `20260825210000_cycle_entries_updated_at_and_fiqh_default.sql` | 9 | Add `cycle_entries.updated_at`; default `fiqh_state` | Additive (fix) | No | No | `cycle_entries` (pre-existing, untracked) | Applied — comment documents this fixed live insert failures |
| `20260826090000_cycle_entries_app_columns.sql` | 10 | Add `flow`, `cycle_day`, `symptoms`, `sync_status` to `cycle_entries` | Additive (fix) | No | No | `cycle_entries` | Applied — comment documents this fixed silent write failures for "logging a haid entry" / "End Haid" |
| `20260827120000_wellbeing_logs_notes.sql` | 11 | Add `wellbeing_logs.notes` | Additive | No | No | migration 7 | Applied (inferred) |
| `20260830140000_community_schema_reset.sql` | 12 | **DROP and recreate** `community_posts`/`community_comments`/`community_likes` (previously `community_post_comments`/`community_post_likes`, wrong columns) | **Destructive** (DROP TABLE CASCADE) | No | No — relies on comment-asserted "0 rows" pre-condition, not enforced by the migration itself | References two absent files (`20260829120000_community_likes.sql`, `20260829130000_community_text_only_constraints.sql`) that do not exist in this repo | Applied — see **DI-005**, **DI-006** |

**Flags per template §11:**
- Out-of-order/incomplete history: **Yes** — see DI-001, DI-006 (referenced-but-missing migration files).
- Destructive change without enforced data-migration guard: **Yes** — migration 12, see DI-005.
- Schema changes made manually outside migration history: **Yes (confirmed)** — `users`, `cycle_entries` (initial shape), `prayer_log`/`pregnancy_records` (pre-rename shape), and the pre-reset community tables all existed live without ever being created by a tracked migration.
- No down/rollback migrations exist for any file.

---

## 6. Critical Data Invariants Identified

| Invariant ID | Rule | Entities | Enforcement layer | DB-enforced? | Risk if violated |
|---|---|---|---|---|---|
| INV-001 | One `pregnancy_profile` row per user | `pregnancy_profile` | DB | **Yes** (`UNIQUE(user_id)`) | N/A — enforced |
| INV-002 | One `wellbeing_logs` row per user per day | `wellbeing_logs` | DB | **Yes** (`UNIQUE(user_id, log_date)`) | N/A — enforced |
| INV-003 | One `private_conversations` row per unordered pair of participants | `private_conversations` | DB (attempted) + App | **Partial/Broken** — DB constraint is ordered-pair only | Duplicate conversation threads under concurrent creation — see DI-003 |
| INV-004 | Every domain row's `user_id` must reference an existing `users` row | 14+ tables | DB (FK) | Nominally yes, but population path for `users` is unverified | Possible foreknown FK violation on every write — see DI-004 (UNKNOWN) |
| INV-005 | `community_likes` — a user can like a post at most once | `community_likes` | DB | **Yes** (`UNIQUE(post_id, user_id)`) | N/A — enforced |
| INV-006 | `cycle_entries` — at most one entry per user per calendar date | `cycle_entries` | **Not enforced anywhere** | No | Contradictory/duplicate cycle-day records possible — see DI-011 |
| INV-007 | `fiqh_state` transitions are chronologically/logically consistent (no overlapping HAID periods, NIFAS after birth_date, etc.) | `cycle_entries`, `adah_ledger`, `nifas_records` | Client-side only (and ledger tables unused) | No | Incorrect derived religious/fiqh status not caught by DB — see DI-009 |
| INV-008 | Cloud-synced cycle/pregnancy/community writes eventually reach the server (no silent, permanent local-only divergence) | `cycle_entries`, `pregnancy_milestones`, `community_posts/comments/likes` | App (best-effort, errors swallowed) | No | Confirmed historical silent data loss — see DI-002 |

---

## 7. Identifier Strategy

All primary keys are `UUID`, generated via `uuid_generate_v4()` (schema.sql, older migrations) or `gen_random_uuid()` (`cycle_entries` in schema.sql, `cycle_logs`/`cycle_entries`-index migration, community tables in the reset migration). Both are cryptographically-random UUIDv4 generators from Postgres extensions (`uuid-ossp` and `pgcrypto`/built-in respectively) — functionally equivalent, no collision or predictability concern, but the **inconsistent choice of generator function across tables** (some `uuid_generate_v4()`, some `gen_random_uuid()`) is a minor inconsistency (DI4) that suggests different authors/sessions wrote different tables without a shared convention — consistent with the broader drift pattern in DI-001. `auth.users(id)` is the ultimate root identity; `profiles.id` and `users.id` both mirror it 1:1. No natural keys, composite keys, or external-provider IDs were found in the schema.

---

## 8. Data Type Notes

- No money/currency fields exist anywhere in the reviewed schema (no payments/subscriptions tables found; `premium_status`/`premium_expires_at` exist as boolean/timestamp flags on the unused `users` table but no billing ledger).
- All timestamps use `TIMESTAMPTZ` (timezone-aware) — correct choice; some default via `now()`, some via `timezone('utc'::text, now())` — functionally equivalent (both UTC) but inconsistent style across migrations (DI4).
- Dates (`DATE` type, no time/timezone) are used for `cycle_entries.date`, `pregnancy_profile.reference_date`, `nifas_records.expected_end/actual_end`, etc. — appropriate for calendar-day semantics, but see DI-011 for lack of per-day uniqueness enforcement.
- `symptoms` on `cycle_entries` has a **confirmed type contradiction** between `schema.sql` (`JSONB`) and migration `20260826090000` (`TEXT[] NOT NULL DEFAULT '{}'`) — see DI-001.
- Status/enum-like fields (`fiqh_state`, `flow_intensity`, `thread_type`, `role`, `status`, `category`, `mood`, `trimester`, `tracking_basis`, `fasting_status`) are consistently implemented as `TEXT` + `CHECK (... IN (...))` rather than native Postgres `ENUM` types (except `madhhab_type` in the first migration, later abandoned in favor of a plain `TEXT CHECK` in `schema.sql`'s `users.madhhab`/`profiles.selected_madhhab`) — acceptable pattern, but the **inconsistent switch away from the enum type** (`public.madhhab_type` created in migration 1, then bypassed by `schema.sql`'s plain-TEXT `CHECK` columns) is further evidence of the drift documented in DI-001.

---

## 9. Discovery Execution Log

### Fully reviewed
- `supabase/schema.sql` (all 507 lines)
- All 12 files in `supabase/migrations/` (full text)
- `supabase/functions/dr-niswah-chat/index.ts` file listing (existence confirmed; not fully read line-by-line — see Partially reviewed)
- `lib/features/private_messaging/data/repositories/private_messaging_repository.dart` (full)
- `lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart` (full)
- `lib/features/pregnancy_tracking/data/repositories/pregnancy_tracking_repository_impl.dart` (first ~90 lines, full write/read paths)
- `lib/features/wellbeing/data/repositories/wellbeing_repository.dart` (first 80 lines)
- `lib/features/community/data/repositories/community_repository_impl.dart` (targeted grep for error-handling/fallback pattern)
- `lib/core/services/cycle_log_repository.dart` (targeted grep confirming legacy `cycle_logs` usage and zero callers)

### Partially reviewed
- `supabase/functions/dr-niswah-chat/index.ts` — existence and role (service-role writer to `flagged_conversations`) confirmed via migration comments and file listing; full logic not read (out of DB-integrity core scope; would matter more to Security/API audits).
- `lib/features/community/data/repositories/community_repository_impl.dart` — fallback/demo-data pattern confirmed via targeted grep, not read end-to-end.
- `lib/features/notifications/*` — file inventory only; no Supabase table found for it, so deep read was not pursued (deemed out of primary DB-integrity scope once no persistence layer was found).
- `lib/core/network/` — not deeply reviewed (client construction / session handling is primarily a Security-audit concern); no separate DB-relevant findings pursued there beyond confirming `NiswahSupabase.clientOrNull` is the shared client accessor used by all repositories reviewed.

### Structurally scanned only
- Full `lib/features/*/data/` tree structure (via `find`) to confirm which features have Supabase-backed repositories vs. local-only.
- Repo-wide grep for every schema.sql/migration table name against `lib/**/*.dart` to build the "used vs. dead table" inventory (DI-008).

### Could not inspect
- **Live Supabase project / `information_schema`** — no database credentials or live connection available or permitted (audit scope is static/read-only). All statements about "the live schema" are therefore inferences from migration text and code, clearly labeled as such.
- **Actual row counts**, **current RLS policy list as deployed** (vs. as defined in migration text — a `DROP POLICY IF EXISTS` + recreate could have been applied out of order or partially), **index usage/performance**, **whether all 12 migrations were actually applied, and in this exact order, to the current production project** — all UNKNOWN, flagged accordingly in the readiness report.
- `supabase/functions/dr-niswah-chat/pregnancy_status.ts` and its test file — not read (Deno edge function business logic, not schema/migration surface).

### Commands/actions performed
| Action | Purpose | Result |
|---|---|---|
| `wc -l`, `ls` on `supabase/schema.sql` and `supabase/migrations/` | Establish scope | 507-line schema.sql, 12 migration files (task brief said 15; 12 found — see note in findings) |
| `grep -n "^CREATE TABLE"` across schema.sql and migrations | Build table inventory, detect drift | Found 10 tables in schema.sql with no matching `CREATE TABLE` in any migration |
| `grep -rn` for table names against `lib/**/*.dart` | Determine which tables are actually read/written by the app | Found 7 tables (`adah_ledger`, `istihadah_episodes`, `nifas_records`, `ramadan_records`, `symptoms_log`, `secret_vault_entries`, `cycle_logs`) with zero app-code references |
| `grep -rn "CREATE TRIGGER"` across schema.sql and migrations | Check for DB-side `updated_at` automation | Found only 2 triggers total, neither of which auto-updates most tables' `updated_at` |
| `grep -rn "\.from('users')"` / `\.from('profiles')` across `lib/` | Determine which of `users`/`profiles` the app actually writes to | Zero references to `users`; `profiles` used by `auth` and `user_profile_repository.dart` |

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|
| Connecting to any live Supabase project | Explicitly out of scope — static/read-only audit only |
| Running `supabase db diff` / `supabase migration up` locally | Would require executing migrations against a database — prohibited by audit rules |
| Modifying, annotating, or "fixing" any `.sql` file | Auditor-only mandate — findings and a proposed (unimplemented) remediation plan only |

**Discovery Exit Gate: PASSED** for a static-only audit — all checklist items in template §23 are addressed above, with unresolved items explicitly carried into the readiness report's "Out-of-Scope / Not Verified" section rather than assumed.
