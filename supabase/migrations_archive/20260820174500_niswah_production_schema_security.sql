-- =========================================================================
-- NISWAH PRODUCTION DATABASE SCHEMA & SECURITY MIGRATION
-- =========================================================================

-- 1. Extensions & Custom Types
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$ BEGIN     CREATE TYPE public.madhhab_type AS ENUM ('hanafi', 'maliki', 'shafii', 'hanbali'); EXCEPTION     WHEN duplicate_object THEN null; END $$;

-- 2. Profiles Table (1:1 Extension of auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    selected_madhhab public.madhhab_type DEFAULT 'shafii' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Cycle Logs Table (Core tracking records)
CREATE TABLE IF NOT EXISTS public.cycle_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    bleeding_intensity TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cycle_logs ENABLE ROW LEVEL SECURITY;

-- 5. Drop existing policies to ensure clean idempotent application
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

DROP POLICY IF EXISTS "Users can view own cycle logs" ON public.cycle_logs;
DROP POLICY IF EXISTS "Users can insert own cycle logs" ON public.cycle_logs;
DROP POLICY IF EXISTS "Users can update own cycle logs" ON public.cycle_logs;
DROP POLICY IF EXISTS "Users can delete own cycle logs" ON public.cycle_logs;

-- 6. Strict RLS Policies for Profiles
CREATE POLICY "Users can view own profile" 
    ON public.profiles FOR SELECT 
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" 
    ON public.profiles FOR INSERT 
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" 
    ON public.profiles FOR UPDATE 
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- 7. Strict RLS Policies for Cycle Logs
CREATE POLICY "Users can view own cycle logs" 
    ON public.cycle_logs FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own cycle logs" 
    ON public.cycle_logs FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own cycle logs" 
    ON public.cycle_logs FOR UPDATE 
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own cycle logs" 
    ON public.cycle_logs FOR DELETE 
    USING (auth.uid() = user_id);

-- 8. Automated Profile Provisioning Trigger (Security Definer with secure search path)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
SECURITY DEFINER 
SET search_path = ''
AS $$ BEGIN     INSERT INTO public.profiles (id, full_name, selected_madhhab)     VALUES (         NEW.id,          NEW.raw_user_meta_data->>'full_name',          COALESCE((NEW.raw_user_meta_data->>'selected_madhhab')::public.madhhab_type, 'shafii')     );     RETURN NEW; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();