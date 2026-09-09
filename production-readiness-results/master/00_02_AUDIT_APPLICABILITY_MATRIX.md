# 00_02 — Audit Applicability Matrix

Architecture classification (from repository inspection, `00_01_RELEASE_CANDIDATE_BASELINE.md`):

Native mobile (iOS + Android, Flutter) · Backend/API (Supabase Postgres + Edge Functions) · Database (Postgres via Supabase, RLS-based) · Auth (Supabase Auth) · Multi-role/permissions (self vs. community vs. flagged/moderated content) · User-generated content (community posts, private messaging) · AI/LLM (Gemini, both server-proxied and — apparently — direct-from-client) · Notifications (`flutter_local_notifications`, local scheduling; no confirmed push/FCM/APNs backend) · File/PDF generation (doctor/husband reports via `pdf`/`printing`) · Regulated/sensitive data (menstrual health, pregnancy, religious practice data — health + religious category data) · Localization (Arabic/English, RTL per `MANIFEST.md` screen names) · No confirmed payments/subscriptions/booking/queues/background-job workers/multi-tenancy — to be confirmed by specialist audits, not assumed. No CI/CD found.

| Audit | Default status (master) | Applicability here | Rationale | Evidence |
|---|---|---|---|---|
| Security | MANDATORY | **MANDATORY** | Handles auth, health/religious PII, AI chat, RLS-gated DB | `01_SECURITY_AUDIT.md` |
| Functional QA | MANDATORY | **MANDATORY** | Core fiqh/cycle calculation, prayer tracking, community, chat, PDF export are all user-facing critical logic | — |
| Code Quality | MANDATORY | **MANDATORY** | 154 Dart files, mixed with legacy artifacts already observed | — |
| Database & Data Integrity | CONDITIONAL (N/A if no persistent data) | **MANDATORY** | Persistent Postgres data via Supabase; 15 migrations; RLS policies | `supabase/` |
| API & Backend | CONDITIONAL (N/A if static client-only) | **MANDATORY** | Supabase Edge Function `dr-niswah-chat`, Supabase REST/RPC, RLS-backed API surface | `supabase/functions/` |
| Performance | MANDATORY | **MANDATORY** | Mobile app with network calls, PDF generation, AI chat latency | — |
| Reliability & Resilience | MANDATORY | **MANDATORY** | AI calls, network dependency, offline behavior unknown | — |
| Observability | MANDATORY | **MANDATORY** | No crash reporting/analytics/logging tool confirmed yet — must verify, not assume N/A | — |
| Privacy & Compliance | CONDITIONAL (N/A if no personal data) | **MANDATORY** | Menstrual/pregnancy health data + religious data = high-sensitivity personal data categories | `lib/core/models`, migrations |
| Accessibility & UX | MANDATORY for user-facing | **MANDATORY** | Consumer-facing mobile app, bilingual/RTL | — |
| Dependencies & Configuration | MANDATORY | **MANDATORY** | `.env` bundling issue already observed; pubspec/lockfile review needed | `pubspec.yaml`, `pubspec.lock` |
| Backup & Recovery | CONDITIONAL (N/A if no critical persistent state) | **MANDATORY** | User health data in Postgres is critical persistent state | — |
| Release & Deployment | MANDATORY | **MANDATORY** | No CI/CD found — must be formally assessed, not assumed N/A | — |
| Analytics & Business Events | CONDITIONAL (N/A if no analytics/business measurement need) | **CONDITIONAL — leaning N/A pending confirmation** | No payments/subscriptions/monetization discovered yet; no analytics SDK found in `pubspec.yaml` dependency list. If confirmed absent, will be marked N/A by the Analytics audit itself with evidence — not pre-judged here. | `pubspec.yaml` (no analytics SDK present) |
| Final Pre-Launch User Journey | MANDATORY | **MANDATORY** | Multiple critical human journeys exist (onboarding, cycle logging, AI chat, PDF report, community) | — |
| Post-Launch Monitoring | MANDATORY | **MANDATORY** | Required regardless; plan must be authored despite template gap (see below) | — |
| **Fiqh Engine Accuracy & AI User-State Context** (added 2026-09-09) | **N/A in the default 16-audit master pack** | **MANDATORY, specialized, project-specific** | Niswah's core value proposition is a rule-driven, madhhab-aware fiqh classification engine (hayd/istihada/nifas/tuhr) feeding worship-relevant guidance, plus 4 Gemini-backed AI features that must reason over live, accurate, current user state (pregnancy, cycle, fiqh classification, wellbeing, notes) rather than behave as isolated chatbots. Neither risk category is covered by any of the 16 default specialist audits — this is a genuinely new, additional mandatory gate, not a re-run of an existing one. Charter: `production-readiness/MDs/FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md`. **Explicitly registered as mandatory before `FINAL_PRELAUNCH_USER_JOURNEY_AUDIT` (`PJ-xxx`)** — the final E2E journey audit cannot meaningfully validate fiqh-sensitive or AI-context-dependent journeys until this audit's findings are known. Finding prefixes: `FIQH-xxx` (engine/rule/calculation/state-machine correctness), `AICTX-xxx` (AI user-state context assembly, freshness, isolation, cross-AI consistency). Severity model preserved verbatim from the charter (`FIQH-0`/`AICTX-0` = automatic launch blocker, matching the master's own `BLOCKER` class) — not renumbered, not remapped to a different scale. | `production-readiness-results/fiqh-engine/` |

## Template Gap

`POST_LAUNCH_MONITORING_TEMPLATE_MASTER.md` is referenced by the master framework (`00_PRODUCTION_READINESS_MASTER.md` §1, row `16`) but **does not exist** in `production-readiness/MDs/` (confirmed via exhaustive filesystem search — only 15 of the 16 specialist template files plus the master are present). This is recorded as `UNK-000` / a scope-limitation, not silently treated as N/A. The Post-Launch Monitoring plan (Wave 6) will be authored directly from the master framework's own embedded requirements for that domain (§§16.6, 38, 49, 50 of `00_PRODUCTION_READINESS_MASTER.md`), which are detailed enough to produce a conformant plan. This substitution is explicitly logged so a reviewer can tell the deliverable was not produced from a dedicated template.

## Conditional Audits Requiring Confirmation During Wave 1

- **Analytics & Business Events** — provisionally CONDITIONAL/leaning N/A; the assigned Wave 4 audit must independently confirm via `pubspec.yaml`, `lib/`, and Supabase inspection before it is allowed to close as N/A (master rule: no N/A without evidence).
