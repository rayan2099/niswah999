-- TABLE + RPC: ai_rate_limit_counters / check_and_increment_ai_rate_limit
--
-- W1-001: the deployed in-memory, per-instance sliding-window rate limiter
-- (supabase/functions/_shared/rate_limit.ts) was directly load-tested in
-- production and proven ineffective — 28 rapid requests against
-- ai-assistant-chat produced zero 429s, because Supabase's Edge Runtime
-- does not guarantee warm, single-instance reuse; each invocation can get
-- independent in-memory state. This migration replaces it with durable,
-- shared, atomically-consistent state in Postgres, the only storage layer
-- every Edge Function instance actually shares.
--
-- Design: a fixed-window counter, not a sliding-window log. One row per
-- (user, function, window). A single atomic UPSERT
-- (INSERT ... ON CONFLICT DO UPDATE ... RETURNING) both increments and
-- reads the count under one row-level lock, so concurrent requests from
-- the same user/function/window cannot race past the quota — Postgres
-- serializes conflicting UPSERTs on the same key. The one accepted
-- trade-off of fixed-window vs. a true sliding window is the well-known
-- boundary-adjacent burst (a client could in principle send close to the
-- quota right before a window boundary and again right after) — accepted
-- here because it still hard-bounds sustained abuse and Gemini cost, which
-- is the actual risk this control exists to close (AB-002/AB-008/SEC-005),
-- and it keeps the implementation simple enough to reason about and test
-- exhaustively, matching the "smallest robust solution" instruction.
--
-- Identity: derived exclusively from auth.uid() inside the SECURITY
-- DEFINER function — never a client-supplied user id — matching this
-- schema's existing delete_my_account()/is_admin() pattern exactly.
--
-- Direct client access: not needed and not granted. RLS is enabled with no
-- policies for authenticated/anon, and table grants are revoked from both
-- — every legitimate access path is the RPC below, which runs with the
-- function owner's privileges (SECURITY DEFINER) and an explicit
-- search_path (never trusts an unqualified/attacker-influenced path).

CREATE TABLE IF NOT EXISTS ai_rate_limit_counters (
  user_id UUID NOT NULL,
  function_name TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  request_count INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, function_name, window_start)
);

-- Supports the opportunistic cleanup sweep inside the RPC below (a scan by
-- window_start alone, independent of user/function) — without this, that
-- sweep would be a full table scan.
CREATE INDEX IF NOT EXISTS idx_ai_rate_limit_counters_window_start
  ON ai_rate_limit_counters (window_start);

ALTER TABLE ai_rate_limit_counters ENABLE ROW LEVEL SECURITY;

-- Deliberately no policies: RLS enabled with zero grants to
-- authenticated/anon means both roles see and can affect zero rows via the
-- normal PostgREST/table API, regardless of any future accidental grant.
REVOKE ALL ON ai_rate_limit_counters FROM PUBLIC, authenticated, anon;

-- Atomically increments the caller's counter for (function_name, current
-- window) and reports whether this request is within the configured
-- quota. Never trusts a caller-supplied identity — auth.uid() is the only
-- source of the user id, matching delete_my_account()'s existing pattern.
--
-- p_function_name: a short key naming the AI operation (e.g.
--   'dr-niswah-chat') — validated against a narrow allow-pattern so this
--   can never be used to smuggle arbitrary data into the table.
-- p_max_requests / p_window_seconds: the caller's configured quota — kept
--   as parameters (not hardcoded) so each Edge Function can pass its own
--   bound without a schema change, while the atomic check+increment
--   guarantee lives in exactly one place.
--
-- Returns exactly one row: allowed, retry_after_seconds (0 when allowed),
-- current_count (for observability/logging — never logged alongside
-- request content, which this function never sees).
CREATE OR REPLACE FUNCTION check_and_increment_ai_rate_limit(
  p_function_name TEXT,
  p_max_requests INT,
  p_window_seconds INT
)
RETURNS TABLE(allowed BOOLEAN, retry_after_seconds INT, current_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_window_start TIMESTAMPTZ;
  v_count INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  IF p_function_name IS NULL
     OR p_function_name !~ '^[a-z0-9_-]{1,64}$' THEN
    RAISE EXCEPTION 'Invalid function_name' USING ERRCODE = '22023';
  END IF;
  IF p_max_requests IS NULL OR p_max_requests <= 0 OR p_max_requests > 100000 THEN
    RAISE EXCEPTION 'Invalid max_requests' USING ERRCODE = '22023';
  END IF;
  IF p_window_seconds IS NULL OR p_window_seconds <= 0 OR p_window_seconds > 86400 THEN
    RAISE EXCEPTION 'Invalid window_seconds' USING ERRCODE = '22023';
  END IF;

  -- Bucket boundary aligned to the Unix epoch (not per-user), so every
  -- caller with the same function_name/window_seconds shares the same
  -- window edges — required for deterministic, testable reset behavior.
  v_window_start := to_timestamp(
    floor(extract(EPOCH FROM now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO ai_rate_limit_counters AS c
    (user_id, function_name, window_start, request_count, updated_at)
  VALUES
    (v_user_id, p_function_name, v_window_start, 1, now())
  ON CONFLICT (user_id, function_name, window_start)
  DO UPDATE SET
    request_count = c.request_count + 1,
    updated_at = now()
  RETURNING c.request_count INTO v_count;

  -- Opportunistic, cheap, bounded-cost retention sweep: on roughly 1 in 50
  -- calls, delete counter rows old enough that no live window could still
  -- reference them (2 hours covers every p_window_seconds this schema
  -- allows, generously). No scheduler/extension dependency (pg_cron is not
  -- enabled in this project) — bounded storage growth falls out of normal
  -- traffic alone, and the 1-in-50 sampling keeps the extra DELETE cost
  -- off the hot path for the other 49 calls.
  IF random() < 0.02 THEN
    DELETE FROM ai_rate_limit_counters
    WHERE window_start < now() - INTERVAL '2 hours';
  END IF;

  IF v_count > p_max_requests THEN
    RETURN QUERY SELECT
      false,
      GREATEST(
        1,
        CEIL(EXTRACT(EPOCH FROM (v_window_start + make_interval(secs => p_window_seconds) - now())))::INT
      ),
      v_count;
  ELSE
    RETURN QUERY SELECT true, 0, v_count;
  END IF;
END;
$$;

ALTER FUNCTION check_and_increment_ai_rate_limit(TEXT, INT, INT) OWNER TO postgres;

-- Only authenticated callers may invoke this — an anonymous caller would
-- fail the auth.uid() IS NULL check anyway, but this keeps the function
-- off the anon role's PostgREST-exposed RPC surface entirely.
REVOKE ALL ON FUNCTION check_and_increment_ai_rate_limit(TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_and_increment_ai_rate_limit(TEXT, INT, INT) TO authenticated;
