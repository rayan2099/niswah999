-- The live cycle_entries table diverged further from what the app's
-- CycleLog entity sends than the previous migration accounted for:
--   1. No `updated_at` column existed (only `created_at`) — every insert
--      failed with "Could not find the 'updated_at' column ... in the
--      schema cache" since toJson() always sends it.
--   2. `fiqh_state` is NOT NULL with no default, and the app never
--      populates it (fiqh state is derived client-side from `flow` in
--      dashboard_screen.dart's _currentFiqhState(), never read back from
--      this column) — every insert failed with a not-null violation.
-- Both confirmed live via information_schema before this migration was
-- written. Purely additive/default-only — nothing else that reads this
-- table is affected.

ALTER TABLE cycle_entries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

ALTER TABLE cycle_entries ALTER COLUMN fiqh_state SET DEFAULT 'TAHARA';
