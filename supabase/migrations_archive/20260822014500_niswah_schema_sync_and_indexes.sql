-- =========================================================================
-- NISWAH SCHEMA SYNCHRONIZATION & PERFORMANCE INDEXES MIGRATION
-- =========================================================================
-- This migration:
--   1. Renames prayer_log -> prayer_entries (matching client-side repository)
--   2. Renames pregnancy_records -> pregnancy_milestones (matching client-side repository)
--   3. Creates educational_resources table (public SELECT, restricted writes)
--   4. Creates dream_entries table (user-scoped RLS)
--   5. Consolidates profiles table as the single source of truth for user data
--   6. Adds performance indexes identified in the security audit
-- =========================================================================

-- =========================================================================
-- 1. RENAME prayer_log -> prayer_entries
-- =========================================================================
-- Drop old RLS policies on prayer_log first
DROP POLICY IF EXISTS "Users can only read their own prayer_log" ON public.prayer_log;
DROP POLICY IF EXISTS "Users can only insert their own prayer_log" ON public.prayer_log;
DROP POLICY IF EXISTS "Users can only update their own prayer_log" ON public.prayer_log;
DROP POLICY IF EXISTS "Users can only delete their own prayer_log" ON public.prayer_log;

-- Rename the table
ALTER TABLE IF EXISTS public.prayer_log RENAME TO prayer_entries;

-- Add missing columns required by the client-side PrayerEntry entity
ALTER TABLE public.prayer_entries
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL;

-- Ensure created_at exists with default
ALTER TABLE public.prayer_entries
    ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now());

-- Enable RLS (idempotent)
ALTER TABLE public.prayer_entries ENABLE ROW LEVEL SECURITY;

-- Recreate RLS policies for prayer_entries
CREATE POLICY "Users can only read their own prayer_entries"
    ON public.prayer_entries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can only insert their own prayer_entries"
    ON public.prayer_entries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only update their own prayer_entries"
    ON public.prayer_entries FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only delete their own prayer_entries"
    ON public.prayer_entries FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- 2. RENAME pregnancy_records -> pregnancy_milestones
-- =========================================================================
-- Drop old RLS policies on pregnancy_records first
DROP POLICY IF EXISTS "Users can only read their own pregnancy_records" ON public.pregnancy_records;
DROP POLICY IF EXISTS "Users can only insert their own pregnancy_records" ON public.pregnancy_records;
DROP POLICY IF EXISTS "Users can only update their own pregnancy_records" ON public.pregnancy_records;
DROP POLICY IF EXISTS "Users can only delete their own pregnancy_records" ON public.pregnancy_records;

-- Rename the table
ALTER TABLE IF EXISTS public.pregnancy_records RENAME TO pregnancy_milestones;

-- Add columns required by the client-side PregnancyMilestone entity
ALTER TABLE public.pregnancy_milestones
    ADD COLUMN IF NOT EXISTS week INT,
    ADD COLUMN IF NOT EXISTS trimester TEXT CHECK (trimester IN ('first','second','third')),
    ADD COLUMN IF NOT EXISTS label TEXT,
    ADD COLUMN IF NOT EXISTS summary TEXT,
    ADD COLUMN IF NOT EXISTS date DATE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL;

-- Ensure created_at exists with default
ALTER TABLE public.pregnancy_milestones
    ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now());

-- Enable RLS (idempotent)
ALTER TABLE public.pregnancy_milestones ENABLE ROW LEVEL SECURITY;

-- Recreate RLS policies for pregnancy_milestones
CREATE POLICY "Users can only read their own pregnancy_milestones"
    ON public.pregnancy_milestones FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can only insert their own pregnancy_milestones"
    ON public.pregnancy_milestones FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only update their own pregnancy_milestones"
    ON public.pregnancy_milestones FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only delete their own pregnancy_milestones"
    ON public.pregnancy_milestones FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- 3. CREATE educational_resources TABLE
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.educational_resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('health','fiqh','family','wellness','spouse')),
    title TEXT NOT NULL,
    summary TEXT,
    content TEXT NOT NULL,
    author TEXT DEFAULT 'Niswah Team',
    read_minutes INT DEFAULT 4,
    tags JSONB DEFAULT '[]',
    is_spouse_guide BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.educational_resources ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to ensure idempotent application
DROP POLICY IF EXISTS "Public can read educational_resources" ON public.educational_resources;
DROP POLICY IF EXISTS "Only service role can insert educational_resources" ON public.educational_resources;
DROP POLICY IF EXISTS "Only service role can update educational_resources" ON public.educational_resources;
DROP POLICY IF EXISTS "Only service role can delete educational_resources" ON public.educational_resources;

-- RLS: SELECT is public, INSERT/UPDATE/DELETE restricted (no policy = denied)
CREATE POLICY "Public can read educational_resources"
    ON public.educational_resources FOR SELECT
    USING (true);

-- =========================================================================
-- 4. CREATE dream_entries TABLE
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.dream_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    mood TEXT CHECK (mood IN ('peaceful','anxious','joyful','mysterious','fearful')),
    tags JSONB DEFAULT '[]',
    interpretation TEXT,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.dream_entries ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to ensure idempotent application
DROP POLICY IF EXISTS "Users can only read their own dream_entries" ON public.dream_entries;
DROP POLICY IF EXISTS "Users can only insert their own dream_entries" ON public.dream_entries;
DROP POLICY IF EXISTS "Users can only update their own dream_entries" ON public.dream_entries;
DROP POLICY IF EXISTS "Users can only delete their own dream_entries" ON public.dream_entries;

-- RLS: restrict access to auth.uid() = user_id
CREATE POLICY "Users can only read their own dream_entries"
    ON public.dream_entries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can only insert their own dream_entries"
    ON public.dream_entries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only update their own dream_entries"
    ON public.dream_entries FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can only delete their own dream_entries"
    ON public.dream_entries FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- 5. CONSOLIDATE profiles TABLE (single source of truth)
-- =========================================================================
-- Add columns needed by AuthRepositoryImpl's UserProfile model
-- so both AuthRepositoryImpl and UserProfileRepository query the same table.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS email TEXT,
    ADD COLUMN IF NOT EXISTS display_name TEXT,
    ADD COLUMN IF NOT EXISTS anonymous_mode BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS phone_number TEXT,
    ADD COLUMN IF NOT EXISTS bio TEXT;

-- Backfill display_name from full_name if display_name is null
UPDATE public.profiles
SET display_name = full_name
WHERE display_name IS NULL AND full_name IS NOT NULL;

-- =========================================================================
-- 6. PERFORMANCE INDEXES (from security audit)
-- =========================================================================
CREATE INDEX IF NOT EXISTS idx_cycle_logs_user_id_start_date
    ON public.cycle_logs(user_id, start_date DESC);

CREATE INDEX IF NOT EXISTS idx_prayer_entries_user_id_date
    ON public.prayer_entries(user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_cycle_entries_user_id_date
    ON public.cycle_entries(user_id, date DESC);

-- Additional supporting indexes for the new tables
CREATE INDEX IF NOT EXISTS idx_pregnancy_milestones_user_id_date
    ON public.pregnancy_milestones(user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_dream_entries_user_id_created_at
    ON public.dream_entries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_educational_resources_category_created_at
    ON public.educational_resources(category, created_at DESC);