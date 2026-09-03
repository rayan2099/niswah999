-- TABLE: pregnancy_profile
--
-- Single source of truth for the "طبيبة" pregnancy-chat feature's
-- personalization data (see supabase/functions/dr-niswah-chat/index.ts,
-- loadPregnancyContext). One row per user. Deliberately separate from
-- pregnancy_milestones (a multi-row daily-log table used by the unrelated
-- pregnancy_tracking feature) and from nifas_records (the richer,
-- madhhab-aware postpartum record) — this table only carries what the
-- pregnancy-week engine and chat context need, and is written only from
-- explicit user input, never inferred.

CREATE TABLE IF NOT EXISTS pregnancy_profile (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  tracking_basis TEXT CHECK (tracking_basis IN ('lmp','due_date','conception_date','manual_week')),
  reference_date DATE,
  manual_week_value INT CHECK (manual_week_value BETWEEN 1 AND 42),
  manual_week_set_at TIMESTAMPTZ,
  is_postpartum BOOLEAN NOT NULL DEFAULT false,
  postpartum_start_date DATE,
  high_risk_flags TEXT[] NOT NULL DEFAULT '{}',
  fasting_status TEXT NOT NULL DEFAULT 'not_applicable'
    CHECK (fasting_status IN ('not_applicable','fasting','not_fasting','unsure')),
  locale TEXT NOT NULL DEFAULT 'ar',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE pregnancy_profile ENABLE ROW LEVEL SECURITY;

-- No triggers on this table — updated_at is set explicitly by the app on
-- every write (see PregnancyProfileRepository.upsert), not DB-side.

DROP POLICY IF EXISTS "Users can only read their own pregnancy_profile" ON pregnancy_profile;
CREATE POLICY "Users can only read their own pregnancy_profile" ON pregnancy_profile
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only insert their own pregnancy_profile" ON pregnancy_profile;
CREATE POLICY "Users can only insert their own pregnancy_profile" ON pregnancy_profile
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only update their own pregnancy_profile" ON pregnancy_profile;
CREATE POLICY "Users can only update their own pregnancy_profile" ON pregnancy_profile
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only delete their own pregnancy_profile" ON pregnancy_profile;
CREATE POLICY "Users can only delete their own pregnancy_profile" ON pregnancy_profile
  FOR DELETE USING (auth.uid() = user_id);
