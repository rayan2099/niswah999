-- TABLE: wellbeing_logs
--
-- Daily mood/energy/sleep check-in history, feeding the "تقرير الحالة
-- النفسية" (mental state report) under Profile → Data Export. Before this
-- table, the dashboard's daily check-in only ever wrote to device-local
-- SharedPreferences (today's value, overwritten daily — no history at
-- all), and the cycle-log's separate mood picker used a different 0-4
-- scale packed as a "mood:N" string inside cycle_entries.symptoms. Neither
-- gave a reliable, queryable mood history. This table is now the single
-- source of truth for the report; the cycle-log mood picker is left
-- untouched and stays scoped to cycle tracking.
--
-- One row per user per day (see UNIQUE constraint) — the dashboard
-- check-in upserts on (user_id, log_date), matching its existing
-- "one check-in per day" UX.

CREATE TABLE IF NOT EXISTS wellbeing_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date DATE NOT NULL,
  mood INT NOT NULL CHECK (mood BETWEEN 1 AND 5),
  energy INT NOT NULL CHECK (energy BETWEEN 1 AND 5),
  sleep INT NOT NULL CHECK (sleep BETWEEN 1 AND 5),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, log_date)
);

CREATE INDEX IF NOT EXISTS idx_wellbeing_logs_user_date
  ON wellbeing_logs(user_id, log_date DESC);

ALTER TABLE wellbeing_logs ENABLE ROW LEVEL SECURITY;

-- No triggers — updated_at is set explicitly by the app on every write
-- (see WellbeingRepository.upsertToday), matching pregnancy_profile.

DROP POLICY IF EXISTS "Users can only read their own wellbeing_logs" ON wellbeing_logs;
CREATE POLICY "Users can only read their own wellbeing_logs" ON wellbeing_logs
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only insert their own wellbeing_logs" ON wellbeing_logs;
CREATE POLICY "Users can only insert their own wellbeing_logs" ON wellbeing_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only update their own wellbeing_logs" ON wellbeing_logs;
CREATE POLICY "Users can only update their own wellbeing_logs" ON wellbeing_logs
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only delete their own wellbeing_logs" ON wellbeing_logs;
CREATE POLICY "Users can only delete their own wellbeing_logs" ON wellbeing_logs
  FOR DELETE USING (auth.uid() = user_id);
