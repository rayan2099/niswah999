-- Onboarding/server hardening regression, finding (low): cycle_baselines accepts a usual bleeding
-- duration longer than the usual cycle length (period longer than the whole
-- cycle), from both write paths: record_onboarding_menstrual_history and
-- save_baseline_estimate. The onboarding wheels allow duration 1..20 and
-- cycle 1..90 with no cross-check (onboarding_screen.dart _predictionsStep),
-- so "20-day period, 3-day cycle" is stored as a prediction baseline.
--
-- Expected (correct) behavior asserted here: such a pair is rejected.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

INSERT INTO auth.users (id) VALUES ('e0000000-0000-0000-0000-00000000000e')
ON CONFLICT DO NOTHING;
INSERT INTO public.users (id) VALUES ('e0000000-0000-0000-0000-00000000000e')
ON CONFLICT DO NOTHING;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'e0000000-0000-0000-0000-00000000000e';
DO $$ BEGIN
  BEGIN
    PERFORM public.record_onboarding_menstrual_history(
      'f0000000-0000-0000-0000-000000000001', 180,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 20, 3);
  EXCEPTION WHEN raise_exception OR check_violation THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.cycle_baselines
             WHERE usual_bleeding_duration_days > usual_cycle_length_days) THEN
    RAISE EXCEPTION 'FAIL: baseline stored with duration 20 > cycle length 3';
  END IF;
END $$;
ROLLBACK;

\echo 'ALL PASSED'
