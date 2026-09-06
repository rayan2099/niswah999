// Durable, shared-state rate limiter (W1-001).
//
// Replaces the prior in-memory, per-instance sliding-window limiter, which
// was deployed to production and directly load-tested: 28 rapid requests
// against ai-assistant-chat produced zero 429 responses, because Supabase's
// Edge Runtime does not guarantee warm, single-instance reuse — each
// invocation can get independent in-memory state, so a per-process Map was
// never actually shared across the concurrent instances handling real
// traffic.
//
// This version is backed by the check_and_increment_ai_rate_limit Postgres
// RPC (supabase/migrations/20260906090000_ai_rate_limit.sql) — the one
// storage layer every Edge Function instance genuinely shares. The RPC
// does the atomic check+increment; this module only shapes the call and
// its result into what each Edge Function needs.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface RateLimitConfig {
  /** Max requests allowed inside the window. */
  maxRequests: number;
  /** Window size in seconds (the RPC works in seconds, not ms). */
  windowSeconds: number;
}

export type RateLimitOutcome =
  | { status: 'allowed' }
  | { status: 'rate_limited'; retryAfterSeconds: number }
  // The limiter's own backing store was unreachable/erroring — distinct
  // from 'rate_limited' so the caller can return a different HTTP status
  // and message, and so this module never silently reports "allowed" for
  // a check it couldn't actually perform.
  | { status: 'limiter_unavailable' };

/** Shared bound for the four AI-backed Edge Functions: 15 requests per 5
 * minutes per authenticated user per function — unchanged from the prior
 * limiter's own bound, just now durably enforced. */
export const AI_ENDPOINT_RATE_LIMIT: RateLimitConfig = {
  maxRequests: 15,
  windowSeconds: 5 * 60,
};

/**
 * Checks and atomically increments the caller's quota for [functionName].
 *
 * [userClient] must be scoped to the caller's own JWT (the same
 * anon-key-plus-Authorization-header client every function already
 * creates for its RLS-scoped reads) — never the service-role client and
 * never a client-supplied user id. The RPC derives identity exclusively
 * from `auth.uid()` inside Postgres, so there is no parameter here (or in
 * the RPC's own signature) through which a caller could spoof another
 * user's identity.
 *
 * Fail-closed by design: if the RPC call itself fails — network blip, DB
 * unavailable, an unexpected shape back — this returns
 * `{ status: 'limiter_unavailable' }` rather than silently treating the
 * request as allowed. Gemini calls cost real money and are exactly the
 * abuse surface this control exists to close (AB-002/AB-008/SEC-005); an
 * unavailable safety control must not become an unrestricted proxy. The
 * failure is logged for operator visibility — function name and error
 * message only, never request content, prompts, or health data.
 */
export async function checkRateLimit(
  userClient: SupabaseClient,
  functionName: string,
  config: RateLimitConfig = AI_ENDPOINT_RATE_LIMIT,
): Promise<RateLimitOutcome> {
  try {
    const { data, error } = await userClient.rpc(
      'check_and_increment_ai_rate_limit',
      {
        p_function_name: functionName,
        p_max_requests: config.maxRequests,
        p_window_seconds: config.windowSeconds,
      },
    );

    if (error) {
      console.error('rate_limit: RPC error, failing closed', {
        functionName,
        error: error.message,
      });
      return { status: 'limiter_unavailable' };
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row || typeof row.allowed !== 'boolean') {
      console.error('rate_limit: RPC returned an unexpected shape, failing closed', {
        functionName,
      });
      return { status: 'limiter_unavailable' };
    }

    if (row.allowed) return { status: 'allowed' };
    return {
      status: 'rate_limited',
      retryAfterSeconds: Number(row.retry_after_seconds) || 1,
    };
  } catch (error) {
    console.error('rate_limit: unexpected failure, failing closed', {
      functionName,
      error: error instanceof Error ? error.message : String(error),
    });
    return { status: 'limiter_unavailable' };
  }
}

export function rateLimitedResponse(
  retryAfterSeconds: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      error: 'Too many requests. Please wait before sending another message.',
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Retry-After': String(retryAfterSeconds),
      },
    },
  );
}

/** Distinct from 429 — tells a client/operator "the safety control itself
 * is unavailable" apart from "you're over quota", without leaking any
 * database/infrastructure detail in the message body. */
export function limiterUnavailableResponse(
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      error: 'This feature is temporarily unavailable. Please try again shortly.',
    }),
    {
      status: 503,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Retry-After': '30',
      },
    },
  );
}
