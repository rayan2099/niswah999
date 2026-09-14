# 00_13 — Production Drift Report

**Generated**: Niswah Full Implementation Reconciliation wave, 2026-09-14. Live production (`jkmjobvxfrmuwafczvtw`) inspected directly this pass via the Supabase Management API (read-only queries only — no secret values printed, extracted and immediately discarded per this engagement's established secret-handling discipline). Discovery only — no remediation performed.

## Database schema

**Live public-schema tables (25, confirmed this pass)**: `adah_ledger`, `ai_rate_limit_counters`, `chat_history`, `chat_messages`, `chat_threads`, `community_comments`, `community_likes`, `community_posts`, `cycle_entries`, `cycle_logs`, `dream_entries`, `flagged_conversations`, `istihadah_episodes`, `nifas_records`, `prayer_log`, `pregnancy_profile`, `pregnancy_records`, `private_conversations`, `private_messages`, `profiles`, `ramadan_records`, `secret_vault`, `symptoms_log`, `users`, `wellbeing_logs`.

**Drift finding — migration ledger is not representative of the live schema.** Only 2 files exist in `supabase/migrations/` (`20260906090000_ai_rate_limit.sql`, `20260909100000_wellbeing_logs_notes.sql`) against a 25-table live schema — the overwhelming majority of the schema was applied outside the tracked migration path (consistent with the repo's own `supabase/migrations_archive/` directory, a `README`-documented 13-file archive of migrations that were superseded/consolidated, and `supabase/canonical_baseline/00_public_baseline_draft.sql`, a manually-captured schema snapshot dated 2026-09-09 — 5 days stale as of this report). This is **not a new finding** (already the subject of `DI-001`'s CI migration-drift gate, confirmed still active and correctly configured this pass) but is worth restating plainly: **the migration ledger cannot be trusted as a complete history of the live schema**, and any future schema audit should query the live database directly (as this pass did) rather than reconstruct it from migration files.

- **Classification**: `PRODUCTION_DRIFT` (expected/known, already gated by `DI-001`'s CI check — not a new blocker).

**Confirmed duplicate/orphaned tables, live in production**:
- `cycle_entries` (25 columns, live, actively written) vs. `cycle_logs` (7 columns, live, exists in the database, written by nothing in the current app — see `REQ-ARCH-001`).
- `pregnancy_profile` (12 columns, live, actively written) vs. `pregnancy_records` (8 columns, live, exists in the database — this pass did not confirm via code whether anything still writes to `pregnancy_records`; the code inventory found no dedicated pregnancy-tracking presentation layer beyond `pregnancy_profile`, and a prior wave's own remediation log records a dormant pregnancy-tracking feature already retired — `pregnancy_records` is very likely the retired feature's table, left in place rather than dropped).
- `profiles` (5 columns: `id`, `full_name`, `selected_madhhab`, `created_at`, `updated_at`) vs. `users` (33 columns — the real, live, actively-used account table, including `madhhab`, `language`, `onboarding_completed`, all prayer/location fields, etc.). `profiles` is written only by the dead `SettingsScreen`/`UserProfileRepository` code path (see `REQ-ARCH-001`).
- **Classification**: `PRODUCTION_DRIFT` — live schema contains tables/columns with no current reachable writer in the app. Not itself a security risk (RLS is correctly enabled and scoped on all of them — see below) but represents real accumulated schema debt.

## Row-Level Security

**Confirmed this pass**: RLS is **enabled on all 25 public tables**, none forced (`relforcerowsecurity = false` everywhere, which is expected/normal — forcing would also restrict the table owner, not typically desired). 58 total policies confirmed across 23 of the 25 tables.

**Two tables have RLS enabled with zero policies**: `flagged_conversations` and `ai_rate_limit_counters`. Confirmed via direct query (not inferred) — this means these two tables are **fully inaccessible to the `anon`/`authenticated` roles** and reachable only via `service_role` (i.e., edge functions). This is the **correct, safe posture** for both — `flagged_conversations` is a moderation/safety log (users should never directly read or tamper with their own flags) and `ai_rate_limit_counters` is backend bookkeeping. Confirmed not a gap.

- **Classification**: `VERIFIED` — RLS posture matches expectation across the board; no drift found.

## Auth configuration (fresh live read this pass)

| Field | Live production value (confirmed this pass) | Repository expectation |
|---|---|---|
| `site_url` | `niswah://login-callback` | Matches — `AUTH-001`'s applied fix |
| `uri_allow_list` | 4 Vercel entries + `niswah://login-callback` | Matches — `AUTH-001`'s applied fix |
| `smtp_host` | `mail.spacemail.com` (non-null) | Matches the owner's own independent SMTP setup, first observed in a prior wave; confirmed still configured |
| `mailer_autoconfirm` | `false` | Matches — real email confirmation is required, as documented throughout the engagement |
| `external_google_enabled` | `false` | Matches — Google OAuth intentionally not enabled (owner-only, requires real credentials never provided to this session) |
| `mailer_subjects_custom_contents` / `mailer_templates_custom_contents` | **All 13/13 `true`** | Matches — the Email Template Standardization + Completeness waves' claim that all 13 Supabase auth/security email types are branded is **confirmed live**, not just claimed |

- **Classification**: `VERIFIED` — no drift between documented and live Auth config. This directly corrects any impression from an incomplete documentation read that `AUTH-001` was "not applied" (an artifact of one discovery pass not reading far enough into a 5,000+ line remediation log, not a reflection of reality) — **the config genuinely is live**, independently re-confirmed by this session with a fresh API call, not carried forward from memory.

## Edge Functions

**Live, confirmed this pass**: `dr-niswah-chat` (v14, ACTIVE, `verify_jwt: true`), `fiqh-advisor-chat` (v8, ACTIVE, `verify_jwt: true`), `dream-interpreter-chat` (v8, ACTIVE, `verify_jwt: true`), `ai-assistant-chat` (v8, ACTIVE, `verify_jwt: true`).

**Repository expectation**: exactly 4 local function directories (`dr-niswah-chat`, `fiqh-advisor-chat`, `dream-interpreter-chat`, `ai-assistant-chat`, plus `_shared`) — **exact match, no drift**. All 4 are the highest-version-number seen in this engagement's history (`dr-niswah-chat` at v14 reflects its 3 independent try/catch write-path fix, `PJ-004`, among other iterations) — versions are consistent with an actively-maintained, not-stale deployment.

- **Classification**: `VERIFIED` — no drift.

## Storage

**Confirmed this pass**: zero storage buckets exist in production. The app has no file-upload feature documented or found in the code inventory (no bucket policies to check, nothing to drift).

- **Classification**: `VERIFIED` (trivially — nothing to drift).

## Migrations / operational

- Local migration count (2) vs. live schema (25 tables): see "Database schema" above.
- Cron/scheduled work: `.github/workflows/w1001-sentinel.yml` (hourly, confirmed present per the historical-finding re-verification pass) is the one confirmed scheduled job directly relevant to production data integrity (detects recurrence of the `W1-001` AI-rate-limiter regression class). No other cron/scheduled backend work was identified as expected-but-missing this pass.
- Secret names (not values): `.env.example` documents the expected secret shape (`GEMINI_API_KEY` server-side only, via `supabase secrets set`) — matches the confirmed pattern that all 4 AI features call `client.functions.invoke(...)` rather than any direct client-side key usage (re-confirmed via code grep this pass, consistent with the historical `SEC-001` closure).

## Summary of drift findings

| Item | Drift? | Severity | Remediation required? |
|---|---|---|---|
| Migration ledger vs. live schema | Yes (expected, already gated) | Low (process debt, not a live risk — `DI-001` CI gate already catches *future* drift) | No new action — already covered |
| `cycle_logs`, `pregnancy_records`, `profiles` orphaned tables | Yes (dead-code targets, not actively harmful) | Low-Medium (schema debt, real risk only if reactivated) | Recommended cleanup, not launch-blocking |
| RLS posture | No | — | — |
| Auth config | No — confirmed fully matches documentation | — | — |
| Edge functions | No | — | — |
| Storage | No (nothing to drift) | — | — |

**Overall**: production is, on the whole, **well-aligned** with what the repository documents — the one substantive drift category (orphaned tables mirroring dead code) is low-risk today and already partially explained by prior remediation waves (e.g. the retired pregnancy-tracking feature). No evidence of a security-relevant or Tier-1-behavior-relevant drift was found this pass.
