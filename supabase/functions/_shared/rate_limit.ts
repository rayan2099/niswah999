// Best-effort, in-memory, per-instance sliding-window rate limiter.
//
// Deliberately NOT database-backed (per the Gemini trust-boundary
// remediation's explicit constraint: no production schema mutation without
// separate approval). This closes the immediate "unrestricted Gemini proxy"
// risk (AB-002/SEC-005) for a single warm function instance, but is
// explicitly NOT a robust, globally-consistent rate limit — it resets on
// cold start and is not shared across concurrent instances/regions. A
// database-backed limiter (e.g. a `rate_limit_events` table + a scheduled
// cleanup) would be the durable version of this control; that is proposed,
// not implemented, in the accompanying report — implementing it requires a
// schema migration, which requires separate, explicit approval.
//
// Always keys on the server-derived, JWT-authenticated user id — never a
// client-supplied value — so a caller cannot spoof a fresh quota by sending
// an arbitrary id.

interface RateLimitConfig {
  /** Max requests allowed inside the window. */
  maxRequests: number;
  /** Window size in milliseconds. */
  windowMs: number;
}

interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds?: number;
}

const buckets = new Map<string, number[]>();

// Prevents unbounded memory growth across the isolate's lifetime.
const MAX_TRACKED_KEYS = 5000;

export function checkRateLimit(
  key: string,
  config: RateLimitConfig,
): RateLimitResult {
  const now = Date.now();
  const windowStart = now - config.windowMs;

  let timestamps = buckets.get(key);
  if (!timestamps) {
    if (buckets.size >= MAX_TRACKED_KEYS) {
      // Simple, cheap eviction rather than a full LRU — acceptable for a
      // best-effort, single-instance control.
      const firstKey = buckets.keys().next().value;
      if (firstKey !== undefined) buckets.delete(firstKey);
    }
    timestamps = [];
    buckets.set(key, timestamps);
  }

  const recent = timestamps.filter((t) => t > windowStart);

  if (recent.length >= config.maxRequests) {
    const oldestInWindow = Math.min(...recent);
    const retryAfterMs = oldestInWindow + config.windowMs - now;
    buckets.set(key, recent);
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil(retryAfterMs / 1000)),
    };
  }

  recent.push(now);
  buckets.set(key, recent);
  return { allowed: true };
}

/** Shared bound for the four AI-backed Edge Functions: 15 requests per 5
 * minutes per authenticated user per function — generous for normal chat
 * use, bounded against automated/proxy abuse. */
export const AI_ENDPOINT_RATE_LIMIT: RateLimitConfig = {
  maxRequests: 15,
  windowMs: 5 * 60 * 1000,
};

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
