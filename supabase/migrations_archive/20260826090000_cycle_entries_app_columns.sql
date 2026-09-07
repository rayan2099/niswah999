-- Adds the columns the app's CycleLog entity actually reads/writes
-- (cycle_tracking/domain/entities/cycle_log.dart's toJson/fromJson:
-- flow, cycle_day, symptoms, sync_status). The live table only had the
-- schema.sql-documented columns (fiqh_state, flow_intensity, ...), which
-- don't match — every real cloud write to cycle_entries has been failing
-- with "column does not exist" since before this table was ever
-- successfully written to from the app. This is why logging a haid entry
-- or tapping "End Haid" on the dashboard silently fails.
--
-- Not touching/removing the existing schema.sql-documented columns —
-- purely additive, so nothing else that reads this table is affected.

ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS flow TEXT
  CHECK (flow IN ('none','spotting','light','medium','heavy'));
ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS cycle_day INT;
ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS symptoms TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'synced';
