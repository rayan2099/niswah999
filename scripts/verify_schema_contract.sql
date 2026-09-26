-- Schema contract verification for a fresh Niswah database rebuild.
-- BR-002 (Migration Chain Reproducibility) wave, 2026-09-06.
--
-- Run against a freshly-built local stack (baseline, or baseline + active
-- migrations) to prove the rebuild actually produced every object the
-- application depends on. Exits with visible FAIL rows rather than a
-- generic success/failure code, so a human (or a CI log) can see exactly
-- what's missing.
--
-- Deliberately excludes pregnancy_milestones (retired feature, W0-002 —
-- must never exist in a fresh rebuild) and excludes prayer_entries
-- (superseded naming — the live/correct table is prayer_log).

WITH required_tables(name) AS (
  VALUES
    ('users'),                    -- bare public.users, FK target for most feature tables (PJ-001)
    ('profiles'),                 -- 1:1 auth.users extension, madhhab/display_name
    ('cycle_logs'),               -- original cycle table (migration #1)
    ('cycle_entries'),            -- live-only, actually-used-by-app cycle table
    ('pregnancy_profile'),        -- pregnancy-chat personalization (single row/user)
    ('pregnancy_records'),        -- legacy/orphaned — must still exist (real historical data), not queried by any current code
    ('wellbeing_logs'),
    ('community_posts'),
    ('community_comments'),
    ('community_likes'),
    ('private_conversations'),
    ('private_messages'),
    ('prayer_log'),               -- the real, live prayer table (not prayer_entries)
    ('flagged_conversations'),
    ('chat_threads'),
    ('chat_messages'),
    ('dream_entries'),
    ('secret_vault'),             -- live-only, undocumented-in-migrations (schema.sql calls it secret_vault_entries)
    ('chat_history')              -- live-only, undocumented-in-migrations
),
required_columns(table_name, column_name) AS (
  VALUES
    -- AICTX-13: this exact column was authored (2026-08-27), never applied
    -- to production, and silently broke every wellbeing check-in until
    -- 2026-09-09 with zero schema-contract coverage catching it. Listed
    -- explicitly so a future fresh rebuild (or a future column drift of
    -- the same kind) fails this contract loudly instead of silently.
    ('wellbeing_logs', 'notes')
),
required_functions(name) AS (
  VALUES
    ('create_user_profile'),      -- populates public.users on signup
    ('handle_new_user'),          -- populates public.profiles on signup
    ('delete_my_account'),
    ('is_admin'),
    ('can_access_user')
),
required_triggers(name) AS (
  VALUES
    ('auth_users_create_profile'),
    ('on_auth_user_created')
),
retired_objects(name) AS (
  VALUES
    ('pregnancy_milestones'),     -- must NOT exist — retired feature (W0-002)
    ('prayer_entries')            -- must NOT exist — superseded naming, never the real table
)
SELECT 'TABLE' AS object_type, rt.name, CASE WHEN t.table_name IS NULL THEN 'FAIL - MISSING' ELSE 'OK' END AS status
FROM required_tables rt
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public' AND t.table_name = rt.name
UNION ALL
SELECT 'COLUMN', rc.table_name || '.' || rc.column_name, CASE WHEN c.column_name IS NULL THEN 'FAIL - MISSING' ELSE 'OK' END
FROM required_columns rc
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = rc.table_name AND c.column_name = rc.column_name
UNION ALL
SELECT 'FUNCTION', rf.name, CASE WHEN p.proname IS NULL THEN 'FAIL - MISSING' ELSE 'OK' END
FROM required_functions rf
LEFT JOIN pg_proc p ON p.proname = rf.name
UNION ALL
SELECT 'TRIGGER', rtg.name, CASE WHEN tg.tgname IS NULL THEN 'FAIL - MISSING' ELSE 'OK' END
FROM required_triggers rtg
LEFT JOIN pg_trigger tg ON tg.tgname = rtg.name
UNION ALL
SELECT 'RETIRED (must be absent)', ro.name, CASE WHEN t.table_name IS NOT NULL THEN 'FAIL - SHOULD NOT EXIST' ELSE 'OK' END
FROM retired_objects ro
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public' AND t.table_name = ro.name
ORDER BY 3 DESC, 1, 2;

-- ============================================================
-- Madhhab Authority Model contract (AUTH-005 / AUTH-010, extended by the
-- BR-002 CI Migration-Reproducibility Repair wave, 2026-09-15).
--
-- The checks above only prove the historical baseline's own objects
-- exist — they say nothing about whether the *active migrations* that
-- run on top of it (supabase/migrations/20260914120000_.../20260914120100_...)
-- actually took effect in a fresh rebuild. This section closes that gap:
-- it verifies the reconstructed schema reflects the CURRENT expected
-- state (a real UNSET/UNKNOWN/SELECTED authority model, no silent
-- Hanbali default), not just the baseline's own pre-remediation shape.
-- Existing checks above are unchanged, not removed, per instruction.
-- ============================================================

-- Column shape: madhhab_selection_state is NOT NULL with a real 'unset'
-- default; madhhab is nullable with NO default at all (nothing left to
-- silently fall back to).
SELECT 'COLUMN PROPERTY' AS object_type,
       'users.madhhab_selection_state.not_null' AS name,
       CASE WHEN c.is_nullable = 'NO' THEN 'OK' ELSE 'FAIL - SHOULD BE NOT NULL' END AS status
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'users' AND c.column_name = 'madhhab_selection_state'
UNION ALL
SELECT 'COLUMN PROPERTY', 'users.madhhab_selection_state.default_unset',
       CASE WHEN c.column_default ILIKE '%unset%' THEN 'OK'
            ELSE 'FAIL - WRONG/MISSING DEFAULT: ' || COALESCE(c.column_default, 'NULL') END
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'users' AND c.column_name = 'madhhab_selection_state'
UNION ALL
SELECT 'COLUMN PROPERTY', 'users.madhhab.nullable',
       CASE WHEN c.is_nullable = 'YES' THEN 'OK' ELSE 'FAIL - SHOULD BE NULLABLE' END
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'users' AND c.column_name = 'madhhab'
UNION ALL
SELECT 'COLUMN PROPERTY', 'users.madhhab.no_silent_default',
       CASE WHEN c.column_default IS NULL THEN 'OK'
            ELSE 'FAIL - SILENT DEFAULT STILL PRESENT: ' || c.column_default END
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'users' AND c.column_name = 'madhhab';

-- Constraint presence (the 3 new constraints) and absence (the legacy
-- uppercase-only constraint the follow-up migration drops).
WITH required_constraints(name) AS (
  VALUES
    ('users_madhhab_selection_state_check'),
    ('users_madhhab_value_check'),
    ('users_madhhab_state_consistency_check')
),
retired_constraints(name) AS (
  VALUES
    ('users_madhhab_check')  -- legacy UPPERCASE-only constraint; must be dropped
)
SELECT 'CONSTRAINT' AS object_type, rc.name AS name,
       CASE WHEN pc.conname IS NULL THEN 'FAIL - MISSING' ELSE 'OK' END AS status
FROM required_constraints rc
LEFT JOIN pg_constraint pc ON pc.conname = rc.name
UNION ALL
SELECT 'RETIRED CONSTRAINT (must be absent)', rc.name,
       CASE WHEN pc.conname IS NOT NULL THEN 'FAIL - SHOULD NOT EXIST (blocks every real lowercase save)' ELSE 'OK' END
FROM retired_constraints rc
LEFT JOIN pg_constraint pc ON pc.conname = rc.name;

-- Constraint *logic*, not just presence — substring checks rather than an
-- exact-text match, since Postgres may reformat CHECK expressions
-- (e.g. IN (...) vs = ANY (ARRAY[...])) without changing their meaning.
-- Verifies the actual applied constraint encodes the right states/values,
-- not merely that a same-named constraint exists.
SELECT 'CONSTRAINT LOGIC' AS object_type,
       'users_madhhab_selection_state_check.covers_all_3_states' AS name,
       CASE WHEN pg_get_constraintdef(oid) ILIKE '%unset%'
             AND pg_get_constraintdef(oid) ILIKE '%unknown%'
             AND pg_get_constraintdef(oid) ILIKE '%selected%'
            THEN 'OK' ELSE 'FAIL - DOES NOT REFERENCE ALL 3 STATES: ' || pg_get_constraintdef(oid) END AS status
FROM pg_constraint WHERE conname = 'users_madhhab_selection_state_check'
UNION ALL
SELECT 'CONSTRAINT LOGIC', 'users_madhhab_value_check.allows_null_and_lowercase_schools',
       CASE WHEN pg_get_constraintdef(oid) ILIKE '%madhhab IS NULL%'
             AND pg_get_constraintdef(oid) LIKE '%hanafi%'   -- case-sensitive: must be lowercase
             AND pg_get_constraintdef(oid) LIKE '%hanbali%'  -- case-sensitive: must be lowercase
            THEN 'OK' ELSE 'FAIL - DOES NOT ALLOW NULL + LOWERCASE SCHOOLS: ' || pg_get_constraintdef(oid) END
FROM pg_constraint WHERE conname = 'users_madhhab_value_check'
UNION ALL
SELECT 'CONSTRAINT LOGIC', 'users_madhhab_state_consistency_check.selected_requires_value',
       CASE WHEN pg_get_constraintdef(oid) ILIKE '%selected%' AND pg_get_constraintdef(oid) ILIKE '%IS NOT NULL%'
             AND pg_get_constraintdef(oid) ILIKE '%IS NULL%'
            THEN 'OK' ELSE 'FAIL - DOES NOT TIE selected TO A REQUIRED VALUE: ' || pg_get_constraintdef(oid) END
FROM pg_constraint WHERE conname = 'users_madhhab_state_consistency_check';

-- create_user_profile()'s actual applied body — proves the fresh-rebuild
-- function matches the migration's replacement, not the baseline's
-- original hardcoded-Hanbali version (which the migration's own
-- CREATE OR REPLACE must have overridden when applied in the correct
-- order, baseline-then-migrations).
SELECT 'FUNCTION BODY' AS object_type, 'create_user_profile.no_hardcoded_HANBALI' AS name,
       CASE WHEN pg_get_functiondef(p.oid) LIKE '%HANBALI%'
            THEN 'FAIL - HARDCODED HANBALI STILL PRESENT (baseline version, not migrated)'
            ELSE 'OK' END AS status
FROM pg_proc p WHERE p.proname = 'create_user_profile'
UNION ALL
SELECT 'FUNCTION BODY', 'create_user_profile.sets_madhhab_selection_state_unset',
       CASE WHEN pg_get_functiondef(p.oid) ILIKE '%madhhab_selection_state%'
             AND pg_get_functiondef(p.oid) ILIKE '%''unset''%'
            THEN 'OK' ELSE 'FAIL - DOES NOT SET madhhab_selection_state TO unset' END
FROM pg_proc p WHERE p.proname = 'create_user_profile';

-- Account deletion: ai_rate_limit_counters has no FK to auth.users, so a
-- trigger must remove a deleted user's counters or they outlive the
-- account (acceptance-testing wave, 2026-09-25). The behavioral proof is
-- scripts/check_account_deletion_cascade.sh (run by validate_migrations.sh).
SELECT 'TRIGGER' AS object_type,
       'auth.users.ai_rate_limit_counters_delete_with_user' AS name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_trigger t
         WHERE t.tgname = 'ai_rate_limit_counters_delete_with_user'
           AND t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal
       ) THEN 'OK' ELSE 'FAIL - ai_rate_limit_counters rows would outlive a deleted account' END AS status;

-- Data export (lib/features/legal/domain/data_export_builder.dart
-- `exportSections`): every section must name a table and key column that
-- actually exist. The `account` section queried users.user_id (users has
-- only `id`), so it failed for every user and the export was always
-- reported incomplete (D-012). Keep this list in step with exportSections.
SELECT 'DATA EXPORT' AS object_type,
       'exportSections.' || v.tbl || '.' || v.col AS name,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.columns c
         WHERE c.table_schema = 'public' AND c.table_name = v.tbl AND c.column_name = v.col
       ) THEN 'OK' ELSE 'FAIL - export section queries a column that does not exist' END AS status
FROM (VALUES
  ('users','id'), ('profiles','id'), ('pregnancy_profile','user_id'),
  ('cycle_entries','user_id'), ('bleeding_episodes','user_id'),
  ('bleeding_observations','user_id'), ('cycle_baselines','user_id'),
  ('prayer_log','user_id'), ('community_posts','user_id'),
  ('chat_threads','user_id'), ('chat_messages','user_id')
) AS v(tbl, col);
