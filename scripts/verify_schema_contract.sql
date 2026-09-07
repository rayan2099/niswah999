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
