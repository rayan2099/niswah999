# Post-Launch Monitoring Plan — Niswah

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app + Supabase backend) |
| Release candidate | `1.0.0+1`, commit `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Audit date | 2026-09-04 |
| Template basis | **`POST_LAUNCH_MONITORING_TEMPLATE_MASTER.md` does not exist in this audit pack** (confirmed by exhaustive filesystem search — recorded in `00_02_AUDIT_APPLICABILITY_MATRIX.md`). This plan is authored directly from `00_PRODUCTION_READINESS_MASTER.md` §§16.6, 38, 49, 50, and the task brief's own Wave 6 requirements (metrics, baselines, dashboards, critical-journey signals, alerts, transaction/DB/queue/integration/analytics monitoring, operational monitoring, launch-abort triggers, rollback triggers, incident ownership, stability sign-off criteria). |
| Status | **PROPOSED — this plan describes what should exist before/at launch. It is not implemented. Executing this plan pre-launch is itself part of the remediation required to reverse the master NO-GO — see `00_07_MASTER_LAUNCH_GATE_REPORT.md`.** |

---

## 0. Why this plan is almost entirely "to be built," not "to be watched"

The Observability audit (Wave 3, `OB_findings.md`) confirmed **22 of 23 static observability checks FAIL** — no crash reporting, no structured logging, no metrics, no alerting, no dashboards, and no analytics/telemetry exist anywhere in this codebase, at any layer (Dart, native iOS, native Android, or the Supabase Edge Function). Per master §38 ("a release should not GO if critical post-launch failures would be operationally invisible and no monitoring/response plan exists"), a monitoring *plan* cannot substitute for monitoring *infrastructure* that doesn't exist yet. This document is therefore split into two parts:

- **Part A** — the plan as it would run **once the Reliability/Observability remediation (RR-xxx, OB-xxx) is implemented.** This is the target state.
- **Part B** — what is actually available **today, with zero remediation**, and the resulting monitoring posture if the release owner chose to launch before that remediation lands (not recommended — see final verdict).

---

## Part A — Target Monitoring Plan (post-remediation)

### A.1 Metrics & Baselines

| Metric | Source (once built) | Baseline (to be established at launch, no historical data exists yet) | Notes |
|---|---|---|---|
| Crash-free session rate | Crash-reporting SDK (OB-001 remediation) | Industry baseline ~99%+ for a mature app; **no baseline exists for this app** — first release establishes it | Cross-ref RR-002 |
| Uncaught-error rate (app-wide) | Structured logging + the `runZonedGuarded` handler, once it reports instead of `debugPrint`s (RR-002/OB-002 remediation) | None — first release establishes it | This is the single highest-value new signal given `ROOT-005` |
| Gemini call success/failure rate (all 3 paths: `dr-niswah-chat`, direct-client AI Advisor, Dream Interpreter) | Server-side + client-side logging (OB-003/OB-005 remediation) | None — and this metric is also how `ROOT-001` gets resolved/monitored going forward, not just at launch | **Highest-priority new metric** — directly answers whether Gemini calls are succeeding in production |
| Cycle/pregnancy remote-write failure rate | Repository-level logging (OB-006 remediation, applied to the exact DI-002 code path) | None — first release; any non-zero sustained rate is a direct recurrence of the documented incident | Cross-ref `DI-002`, `RR-001` |
| App startup time (cold start) | Would require a lightweight timing instrumentation point (not currently present) | None measured (PF-001/PF-002 static risk only) | |
| PDF generation latency | Would require timing instrumentation around the four PDF builders | None measured (PF-003 static risk only) | |
| Notification delivery/scheduling failure rate | `NotificationService` would need to report instead of silently no-op (RR-003 remediation) | None | |

### A.2 Dashboards

None exist today (`OB-011`). Once a crash-reporting/logging tool is integrated, minimum dashboard set:
1. **Crash/error dashboard** — crash-free rate, top uncaught exceptions, trend by app version (requires `OB-009`'s version-tagging remediation first).
2. **AI-integration health dashboard** — success/failure rate for all 3 Gemini call paths, broken out separately (this directly operationalizes `ROOT-001` monitoring, not just a one-time resolution).
3. **Data-integrity dashboard** — remote-write failure rate for cycle/pregnancy/community repositories (operationalizes `DI-002`/`ROOT-005` monitoring).
4. **Supabase-native dashboard** (Postgres CPU/connections, Edge Function invocation/error counts, Auth activity) — this one **exists today** as a Supabase platform default, independent of any app-side work. Its actual utilization by the team is `UNK-003`/unresolved — recorded as an operational/process unknown, not a code gap.

### A.3 Critical User-Journey Signals

Tied directly to the Final Pre-Launch User Journey audit's (Wave 5) traced journeys — for each, the signal that would have caught the journey's already-identified failure mode:

| Journey | Known risk (from Wave 1-5 findings) | Signal needed |
|---|---|---|
| Onboarding/account creation | `DI-004` — unknown whether `public.users` populates correctly | Signup-completion vs. signup-attempt funnel; FK-violation error rate on first cycle-log write |
| Daily cycle/haid logging | `DI-002`/`ROOT-005` — confirmed prior silent-failure incident, unchanged today | Remote-write failure rate on `cycle_entries`, alertable at any sustained non-zero rate |
| Dr. Niswah AI chat / red-flag path | `ROOT-001`, `OB-004` — possible endpoint failure; audit-log insert unguarded | Gemini call success rate; `flagged_conversations` insert failure rate (safety-critical — should page, not just log) |
| Private messaging | `SEC-004`, `DI-003`, `CQ-007` | RLS-policy-violation attempts (if loggable); demo-mode-fallback activation rate (should be ~0 in production; any non-zero rate signals unexpected auth-session drops) |
| PDF report export | `PF-003`, dependency on AI-derived content | Export completion rate; generation-time distribution |
| Prayer tracking/notifications | `RR-003` — silent no-op on failed init | Notification-scheduling failure rate |

### A.4 Alerts (proposed thresholds — require release-owner sign-off, not invented unilaterally per master §49)

| Trigger | Signal | Suggested threshold | Severity |
|---|---|---|---|
| AI integration down | Gemini success rate (any of 3 paths) | Sustained <90% success over 15 min | Page — directly resolves/monitors `ROOT-001` |
| Data-loss recurrence | Cycle/pregnancy remote-write failure rate | Any sustained non-zero rate over 30 min | Page — direct recurrence of documented incident |
| Safety-log failure | `flagged_conversations` insert failure | Any single failure during a detected red-flag message | Page immediately (clinical-safety-relevant, `OB-004`) |
| Crash spike | Crash-free session rate | Drop >2% from rolling baseline | Page |
| Auth/signup breakage | Signup-completion funnel drop | >20% drop from baseline | Page |

### A.5 Payment / Transaction Monitoring

**N/A.** No payment or transaction processing exists in this app (confirmed by the Analytics & Business Events audit, Wave 4 — no `in_app_purchase`/Stripe/RevenueCat integration; the one paywall UI found, `_PaywallSheet`, is dead code per `AE-001`).

### A.6 Database Monitoring

- Supabase's own default Postgres metrics (connections, CPU, query latency) — platform-level, exists today, utilization unverified (`UNK-003`).
- **New, app-specific requirement:** monitoring for the exact failure class `DI-001`/`BR-002` describe — i.e., any future migration should be dry-run against a fresh empty database (or a scripted equivalent) **before** being applied live, given the confirmed history of migrations that don't replay cleanly. This is a pre-deployment gate, not strictly "monitoring," but belongs in the same operational discipline given `ROOT-007`.
- Backup-status monitoring: entirely blocked on resolving `BR-001`/`UNK-009` (Supabase plan tier/backup configuration unknown) — cannot design backup monitoring for a mechanism whose existence is unconfirmed.

### A.7 Queue / Background-Job Monitoring

**N/A.** No queue or background-worker infrastructure exists in this app (confirmed across Database, API/Backend, and Reliability audits — the only asynchronous work is client-scheduled local notifications and the single Supabase Edge Function, both already covered above).

### A.8 Integration Monitoring

Two external integrations exist:
1. **Google Gemini API** (both server-side and confirmed client-side paths) — see A.1/A.4 above; this is the highest-priority integration to monitor given `ROOT-001`.
2. **Supabase** (Postgres, Auth, Edge Functions) — platform-level monitoring exists by default; app-side monitoring of *how the app uses it* (error rates, RLS-denial rates) does not yet exist.

### A.9 Analytics Sanity Checks

**N/A** per the Analytics & Business Events audit's independently-confirmed N/A verdict (`AE_production_readiness_report.md`) — no analytics/telemetry exists to sanity-check. Note the cross-reference already recorded by that audit and by `OB-008`: this also means there is no secondary/proxy signal (e.g., "AI messages sent" event volume) that could partially compensate for the primary monitoring gaps above.

### A.10 Operational Monitoring

- No on-call rotation, incident-response process, or runbook exists anywhere in the repository (confirmed absence, cross-ref `BR-004`).
- No status page or user-facing incident-communication channel was found.

### A.11 Launch Abort Triggers (pre-launch — do not launch if any of these is true at freeze time)

| Trigger | Source | Rationale |
|---|---|---|
| `ROOT-001` (Gemini endpoint validity) unresolved | CQ-010, AB-001, PJ (Wave 5) | Could mean 3 of the app's core AI features are dead on arrival, undetectable per `ROOT-005` |
| `BR-001`/`UNK-009` (Supabase backup config) unresolved | Backup/Recovery | Launching with an unknown/possibly-nonexistent backup posture for irreplaceable health data |
| `RD-001` (debug-signed Android release) unresolved | Dependencies/Config, Security, Release/Deployment | Mechanically cannot be legitimately published |
| `PC-001`/`PC-002` (no functioning consent gate, no account deletion) unresolved | Privacy/Compliance | Baseline expectation for a health-data consumer app |

### A.12 Rollback Triggers (post-launch — abort/rollback the rollout if any of these fires)

| Trigger | Detection (once A.1-A.4 exist) | Immediate action |
|---|---|---|
| AI integration success rate collapses | A.4 alert | Disable AI-dependent UI entry points if a remote-config/flag mechanism exists (currently does not — `ROOT-008` — so today this would require an emergency re-release) |
| Data-loss recurrence detected | A.4 alert | Halt further rollout (if phased/staged rollout is used — not currently planned per `RD-003`'s CI/CD absence), begin incident response |
| Crash-free rate collapse | A.4 alert | Halt rollout; prepare hotfix — currently blocked by `RD-001`/`RD-006` (signing, build-number process) |

### A.13 Incident Ownership

**Not assigned anywhere in the repository.** Per master §28, an AI auditor cannot assign this — it requires the release owner to name a person/team. Recorded as an open item, not invented.

### A.14 Stability Sign-Off Criteria

Recommend (not unilaterally imposed): crash-free rate ≥99% and AI-integration success rate ≥95% sustained for at least 72 hours post-launch, with zero data-loss-recurrence alerts, before considering the release "stable" — release owner should confirm or adjust these targets.

---

## Part B — Monitoring Posture Today (zero remediation, hypothetical immediate launch)

If this release launched today, without any of Part A's remediation:

- **Crash detection:** none, beyond whatever Apple/Google's own store-level automatic crash collection provides — unverified whether anyone reviews it (`UNK` — Observability audit).
- **AI-integration failure detection:** none. If `ROOT-001` is real, discovery depends entirely on user complaints (`OB-003` traced this explicitly).
- **Data-loss detection:** none. A recurrence of the exact `DI-002` incident would be silent, exactly as it was the first time.
- **Backup/recovery readiness:** unknown (`BR-001`) — cannot even state what the recovery posture would be in an incident.
- **Rollback capability:** effectively none beyond a full app-store resubmission cycle, which is itself currently blocked (`RD-001`, `RD-006`).

This posture directly satisfies master §38's Monitoring Readiness Override Rule condition for NO-GO ("critical post-launch failures would be operationally invisible and no monitoring/response plan exists") and independently supports the master NO-GO verdict.

---

## Wave 6 Status

`PL-001` (informational, non-blocking on its own but load-bearing for the master verdict): This plan is authored and ready to guide remediation, but **cannot be executed today** because the infrastructure it depends on does not exist. Per master §3.7 ("post-launch monitoring must exist before launch") and §38, this is recorded as a contributing factor to master NO-GO, not a standalone audit verdict — Post-Launch Monitoring does not carry its own specialist GO/NO-GO vocabulary in the same sense as the numbered specialist audits, per master §16's own finding-ID list (`PL-xxx` reserved for post-launch, runtime-only findings once the app is actually live). This document's role is to confirm the **plan exists and is ready**, while explicitly flagging that its prerequisites do not.
