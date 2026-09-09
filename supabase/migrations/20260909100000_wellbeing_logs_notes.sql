-- COLUMN: wellbeing_logs.notes
--
-- AICTX-13: an optional free-text "ملاحظات" (notes) field for the daily
-- mood/energy/sleep check-in was designed and shipped in application code
-- (WellbeingLog.notes, WellbeingRepository.upsertToday, the dashboard
-- check-in dialog's notes text field) and was originally authored as its
-- own migration back on 2026-08-27 (see
-- supabase/migrations_archive/20260827120000_wellbeing_logs_notes.sql,
-- content identical to this file's single statement below). That file was
-- never actually applied to production — unlike its sibling base-table
-- migration (20260825120000_wellbeing_logs.sql), which was applied
-- out-of-band and is reflected in both the canonical baseline and
-- production today. Confirmed absent from production as of both the
-- 2026-09-04 live schema capture and this wave's live re-check
-- (2026-09-09): every real wellbeing check-in currently fails against
-- production, not only ones containing note text, because the
-- application always includes `notes` in the upsert payload (even as
-- null, so an edit can clear a previous note) and PostgREST rejects any
-- write payload referencing a column absent from its schema cache.
--
-- Purely additive: nullable, no default beyond NULL, no rewrite of
-- existing rows (they simply gain a NULL `notes` value), RLS/policies
-- unchanged (this is a column-level change, not a row-level one).
-- Idempotent — safe to run more than once.
--
-- Guarded rather than a bare ALTER: this repo's fresh-rebuild order
-- applies supabase/migrations/ (via `supabase start`) BEFORE the
-- canonical baseline (applied as a separate, later step — see
-- docs/database-migration-strategy.md), so on a truly fresh rebuild
-- `wellbeing_logs` does not exist yet when this file runs. The baseline
-- itself already defines the column directly (see its own AICTX-13 note),
-- so this guard makes the file a safe no-op there and a real ALTER
-- against the one environment that actually needs it: production, where
-- the table already exists without this column.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wellbeing_logs'
  ) THEN
    ALTER TABLE public.wellbeing_logs ADD COLUMN IF NOT EXISTS notes TEXT;
  END IF;
END $$;
