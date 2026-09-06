-- TABLE: pregnancy_milestones
--
-- W0-002: `pregnancy_tracking_repository_impl.dart` has always queried
-- `pregnancy_milestones`, which has never existed live. The live table
-- that was originally assumed to be its intended backing store,
-- `pregnancy_records` (one row per user — lmp_date/due_date/current_week/
-- birth_date/nifas_id/weekly_notes jsonb), is structurally incompatible
-- (no per-entry date/label/summary columns to query) AND, on closer
-- inspection this wave, is not actually queried by any current Flutter
-- code at all — `pregnancy_profile` (a separate, later, correctly-designed
-- table) superseded it as the app's real pregnancy-identity record. See
-- the wave report for the full evidence trail; in short, `pregnancy_records`
-- is left untouched by this migration (not read from, not written to, not
-- dropped) — its disposition is a separate, deferred question requiring
-- live data inspection this session cannot safely perform.
--
-- Model chosen: a direct per-user child table, matching this schema's own
-- existing convention for personal dated-entry logs (see wellbeing_logs) —
-- NOT nested under pregnancy_records or pregnancy_profile. Evidence for
-- this, not a guess: the application's own `PregnancyMilestone` Dart
-- entity (lib/features/pregnancy_tracking/domain/entities/
-- pregnancy_milestone.dart) has never had a pregnancy_id/pregnancy_record_id
-- field — only id/user_id/week/trimester/label/summary/date — and
-- `pregnancy_profile` itself is UNIQUE(user_id), confirming this
-- application's whole data model already assumes at most one *current*
-- pregnancy per user, with no concept of disambiguating between multiple
-- historical pregnancies that would justify an intermediate parent row.
-- Adding one here would be exactly the kind of unnecessary field this
-- wave's own instructions warn against.

CREATE TABLE IF NOT EXISTS pregnancy_milestones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week INT NOT NULL CHECK (week BETWEEN 1 AND 42),
  trimester TEXT NOT NULL CHECK (trimester IN ('first', 'second', 'third')),
  label TEXT NOT NULL,
  summary TEXT NOT NULL,
  date DATE NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'synced'
    CHECK (sync_status IN ('pending', 'synced', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Matches wellbeing_logs' own indexing pattern: the app's real access
-- pattern is "this user's entries, most recent first."
CREATE INDEX IF NOT EXISTS idx_pregnancy_milestones_user_date
  ON pregnancy_milestones(user_id, date DESC);

ALTER TABLE pregnancy_milestones ENABLE ROW LEVEL SECURITY;

-- No triggers — updated_at is set explicitly by the app on every write,
-- matching pregnancy_profile's and wellbeing_logs' existing convention
-- (see PregnancyProfileRepository.upsert / WellbeingRepository.upsertToday).

DROP POLICY IF EXISTS "Users can only read their own pregnancy_milestones" ON pregnancy_milestones;
CREATE POLICY "Users can only read their own pregnancy_milestones" ON pregnancy_milestones
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only insert their own pregnancy_milestones" ON pregnancy_milestones;
CREATE POLICY "Users can only insert their own pregnancy_milestones" ON pregnancy_milestones
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only update their own pregnancy_milestones" ON pregnancy_milestones;
CREATE POLICY "Users can only update their own pregnancy_milestones" ON pregnancy_milestones
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only delete their own pregnancy_milestones" ON pregnancy_milestones;
CREATE POLICY "Users can only delete their own pregnancy_milestones" ON pregnancy_milestones
  FOR DELETE USING (auth.uid() = user_id);
