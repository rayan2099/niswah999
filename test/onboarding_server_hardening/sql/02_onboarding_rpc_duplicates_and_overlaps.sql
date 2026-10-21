-- Onboarding/server hardening regression, finding: record_onboarding_menstrual_history (latest body:
-- supabase/migrations/20261018090000_bleeding_write_boundary_validation.sql)
-- reconciles only against an OPEN episode. Its fresh-insert branch has none
-- of start_bleeding_episode's "overlaps an episode that already ended"
-- protection, so:
--   (a) re-running onboarding (fresh operation id) with the same "started D,
--       ended E" answer inserts a second, identical ended episode — her
--       history now shows two periods where she had one;
--   (b) an onboarding "started D, still going" answer whose D falls inside an
--       already-ended episode inserts an open episode overlapping it — the
--       exact contradiction 20261018090000 #1 forbids for the live sheet.
--
--   (c) a replay of one operation id with different dates returned the
--       first attempt's episode as success (her changed answer was lost).
--
-- Expected (correct) behavior asserted here: neither write may create a
-- duplicate/overlapping episode (reuse the identical ended episode, or reject
-- with P0001). On the current schema this script FAILS at (a).
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

INSERT INTO auth.users (id) VALUES ('c0000000-0000-0000-0000-00000000000c')
ON CONFLICT DO NOTHING;           -- handle_new_user() creates public.users
INSERT INTO public.users (id) VALUES ('c0000000-0000-0000-0000-00000000000c')
ON CONFLICT DO NOTHING;

CREATE FUNCTION pg_temp.onboard(p_op uuid, p_start date, p_status text,
  p_cert text, p_end date)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM public.record_onboarding_menstrual_history(
      p_op, 180, p_start, 'date_only', NULL, p_status, p_cert, p_end,
      CASE WHEN p_end IS NULL THEN NULL ELSE 'date_only' END, NULL, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    NULL;  -- a P0001 rejection is an acceptable (correct) outcome
  END;
END $$;

\echo '--- (a) the same ended history submitted by two onboarding runs'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-00000000000c';
SELECT pg_temp.onboard('d0000000-0000-0000-0000-000000000001',
  current_date - 40, 'ended', NULL, current_date - 35);
-- She is routed through onboarding again (sign-out/reinstall, or a failed
-- onboarding_completed write) and gives the same truthful answer.
SELECT pg_temp.onboard('d0000000-0000-0000-0000-000000000002',
  current_date - 40, 'ended', NULL, current_date - 35);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.bleeding_episodes) <> 1 THEN
    RAISE EXCEPTION
      'FAIL (a): % episodes for one reported period (% observations)',
      (SELECT count(*) FROM public.bleeding_episodes),
      (SELECT count(*) FROM public.bleeding_observations);
  END IF;
END $$;
ROLLBACK;

\echo '--- (b) an onboarding open episode starting inside an ended one'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-00000000000c';
SELECT pg_temp.onboard('d0000000-0000-0000-0000-000000000003',
  current_date - 20, 'ended', NULL, current_date - 14);
SELECT pg_temp.onboard('d0000000-0000-0000-0000-000000000004',
  current_date - 17, 'open', 'confirmed', NULL);
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM public.bleeding_episodes a JOIN public.bleeding_episodes b
      ON a.id < b.id AND a.user_id = b.user_id
     AND a.start_date <= coalesce(b.end_date, 'infinity'::date)
     AND b.start_date <= coalesce(a.end_date, 'infinity'::date)
  ) THEN
    RAISE EXCEPTION 'FAIL (b): onboarding created overlapping episodes';
  END IF;
END $$;
ROLLBACK;

\echo '--- (c) a replay of one operation id with different dates is rejected'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'c0000000-0000-0000-0000-00000000000c';
SELECT pg_temp.onboard('d0000000-0000-0000-0000-000000000005',
  current_date - 3, 'open', 'confirmed', NULL);
DO $$ BEGIN
  BEGIN
    PERFORM public.record_onboarding_menstrual_history(
      'd0000000-0000-0000-0000-000000000005', 180, current_date - 1,
      'date_only', NULL, 'open', 'confirmed', NULL, NULL, NULL, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    RETURN;  -- correct: the changed answer is not silently swallowed
  END;
  RAISE EXCEPTION 'FAIL (c): replay with a different start date returned the first episode as success';
END $$;
-- an identical replay still returns the original episode
DO $$ BEGIN
  ASSERT (SELECT episode_id FROM public.record_onboarding_menstrual_history(
      'd0000000-0000-0000-0000-000000000005', 180, current_date - 3,
      'date_only', NULL, 'open', 'confirmed', NULL, NULL, NULL, NULL, NULL))
    = (SELECT id FROM public.bleeding_episodes
       WHERE client_operation_id = 'd0000000-0000-0000-0000-000000000005'),
    'FAIL (c): identical replay no longer idempotent';
END $$;
ROLLBACK;

\echo 'ALL PASSED'
