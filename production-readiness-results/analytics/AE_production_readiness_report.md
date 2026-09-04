# Analytics & Business Events — Production Readiness Report

## 68. Executive Summary

### System
Niswah (Flutter mobile app, Supabase backend)

### Version / Commit
`13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` (branch `main`)

### Critical KPIs measurable
`0/0` — no KPIs are defined for this product anywhere in-repo; none were invented per template rule.

### Critical events validated
`0/0` — no events exist to validate. Phase 2B (Controlled Event Validation) was not executed because there is no instrumentation to exercise (see rationale below and in `AE_discovery.md`).

### Critical reconciliations
`0/0` — no financial/business events exist to reconcile against source-of-truth records.

### Open findings
- AE0: `0`
- AE1: `0`
- AE2: `0`
- AE3: `0`
- AE4: `1` (`AE-001` — dead/unreachable paywall UI stub, informational, non-blocking; see `AE_findings.md`)

### Critical unknowns
`0` critical unknowns remain regarding the applicability question itself. One residual non-critical unknown is recorded: whether anyone informally runs ad hoc SQL against production Supabase for reporting purposes (cannot be verified from a static repo audit; does not change the verdict either way).

### Final recommendation
**N/A** — Analytics & Business Events audit is not applicable to this system at this commit. See full rationale below.

---

## Applicability Determination — N/A (with evidence and rationale)

### Whether N/A is a legitimate outcome here

The master framework (`00_PRODUCTION_READINESS_MASTER.md` §6, Default Applicability Matrix) explicitly lists:

> `Analytics & Business Events | CONDITIONAL | Product has no analytics/business measurement requirement`

and (§6 footer): **"Any N/A classification must include evidence and rationale."** This report supplies both, in full, below — it does not accept the applicability matrix's provisional "leaning N/A" lean on faith. Per the master rule quoted in this audit's brief — **"do not mark an audit N/A merely because implementation is unclear"** — the determination below rests on exhaustively confirmed *absence*, not unclear implementation.

### Evidence that no analytics/business-measurement requirement exists

1. **No analytics SDK, direct or transitive.** Full review of `pubspec.yaml` (15 direct dependencies) and full enumeration of `pubspec.lock` (~90 resolved packages, including every transitive dependency) shows zero analytics, telemetry, crash-reporting, or product-metrics package of any kind — no `firebase_analytics`, `sentry`, `mixpanel_flutter`, `amplitude_flutter`, `posthog_flutter`, Segment, AppsFlyer, Adjust, or comparable package. (`AE_discovery.md` §1.1–1.2)

2. **No homegrown instrumentation.** A broad, case-insensitive grep of the entire `lib/` tree for `analytics`, `telemetry`, `EventTracker`, `logEvent`, `track(`, `Mixpanel`, `Amplitude`, `PostHog`, `Segment\.`, `firebase_analytics`, `AppsFlyer`, `Adjust\b` produced zero genuine matches — every hit was a false positive from unrelated domain vocabulary (`adjust` in prose text; `segment`/`Segment` referring to `CycleSegmentId` menstrual-cycle-phase domain objects). No `AnalyticsService`, `EventTracker`, or `Telemetry` class exists anywhere, including nothing that logs locally or writes ad hoc event rows to Supabase. (`AE_discovery.md` §1.3)

3. **No monetization/business model exists to generate business events.** Full search for `in_app_purchase`, `Stripe`, `RevenueCat`, `payment`, `premium`, `subscription`, `purchase`, `paywall`, `iap` across `lib/` and the dependency tree found no payment/IAP SDK anywhere. The one monetization-shaped UI artifact found — `_PaywallSheet` in `lib/features/auth/presentation/screens/profile_screen.dart` — is confirmed dead code: never instantiated or shown anywhere in the app, and its "Start free trial" button does nothing but dismiss itself (`Navigator.pop(context)`), with no purchase call, no Supabase write, no premium-flag mutation. This independently reconfirms the Database & Data Integrity audit's `DI-004`/`DI-008` finding (dormant `premium_status`/`premium_expires_at` columns, zero app-code references) from the application-code side rather than the schema side. (`AE_discovery.md` §2; `AE_findings.md` `AE-001`)

4. **No KPIs, funnels, dashboards, or reconciliation targets are defined anywhere in-repo.** No product requirements document, analytics spec, event taxonomy, or dashboard config exists in the repository to audit against. Per template instruction ("Do not invent KPI definitions," §76.2), none were fabricated for this report.

### Conclusion

This system currently has **no analytics/business-measurement requirement**: it collects no product-usage telemetry, has no defined KPIs, and has no live revenue/monetization surface (the only related code is dead). This satisfies the master framework's N/A criterion for this audit precisely and evidentially — not through absence of investigation, but because the investigation was exhaustive and found nothing to audit.

**This N/A verdict is scoped strictly to "analytics/business-event instrumentation is trustworthy."** It does **not** imply:
- that the app is otherwise production-ready (that is the province of the 15 other specialist audits, several of which — Observability, Database, Security — have already found material issues elsewhere in this system);
- that analytics will never be needed (see Recommendations below); or
- that this audit found "nothing at all" — one informational finding (`AE-001`) was registered, and one cross-reference to `OB-008` is documented, both below and in `AE_findings.md`.

---

## Adjacent question addressed regardless of N/A verdict: is there ANY substitute for business visibility?

Per this audit's brief, this question was assessed independently of the formal N/A verdict, since it bears on `ROOT-001` detectability (already flagged by the Observability audit as `OB-008`).

**Finding: business visibility is not literally zero, but the only available substitute is a raw-SQL, engineering-only, unstructured fallback — not a usable business-visibility capability.**

Supabase Postgres tables carry `created_at TIMESTAMPTZ` columns that would let someone with direct database/Supabase-Studio access write ad hoc queries to answer basic questions:

| Question | Technically answerable via | Evidence |
|---|---|---|
| "How many users signed up this week?" | `profiles.created_at` (or Supabase Studio's Auth → Users list) | `supabase/migrations/20260820174500_niswah_production_schema_security.sql:15` |
| "How many cycle logs are created per day?" | `cycle_logs.created_at`, grouped | same file, line 27 |
| "Is the AI chat feature being used at all?" | `chat_threads`/`chat_messages.created_at`, indexed | `supabase/migrations/20260824115900_dr_niswah_chat_threads.sql` |

This is **not** a business-analytics capability in any meaningful sense: it requires direct database access unavailable to non-engineering stakeholders, has no dashboard/report/alert wrapping it, cannot distinguish real usage from test/error traffic, and — critically for `ROOT-001` — a `chat_messages` row being written only proves a message was *attempted*, not that the underlying Gemini call in `dr-niswah-chat` actually *succeeded*. See `AE_findings.md` "Cross-reference note" for the full `OB-008` tie-in. This point is logged as context, not as a new `AE-xxx` finding, per the audit brief's explicit instruction.

---

## `LG-M-18` — Master Launch Gate Language for This System

The master framework's Global Launch Gate table (`00_PRODUCTION_READINESS_MASTER.md`) includes:

> `LG-M-18 | Critical business analytics trustworthy | {AE AUDIT} | {PASS/FAIL/N/A}`

**This audit's determination for `LG-M-18`:**

> **`LG-M-18`: N/A.** No critical business analytics exists for this system at commit `13a9387`, therefore none can be assessed as trustworthy or untrustworthy. Rationale: (1) no analytics/telemetry instrumentation of any kind exists, confirmed exhaustively across direct dependencies, transitive dependencies, and custom code; (2) no monetization/revenue surface is live (the one paywall-shaped UI artifact found is dead, disconnected code); (3) no KPIs, funnels, or dashboards are defined anywhere in-repo to be "trustworthy" or not. `LG-M-18` should be recorded as **N/A with rationale**, not as an open blocker and not silently omitted — it does not count for or against the master GO/NO-GO decision, and should not be conflated with `LG-M-06`(Observability, which **is** MANDATORY and where the Observability audit's own findings, including `OB-008`, remain in force and unaffected by this N/A).

This resolves the ambiguity flagged in the audit brief: `LG-M-18` should not be left blank or marked FAIL-by-omission — it is explicitly N/A, with the evidence above standing as its rationale.

---

## Launch Gate Table (template §70) — completed for transparency

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-AE-01` | Zero open AE0 | `AE_findings.md` | **N/A** (no instrumentation exists to have AE0 defects) |
| `LG-AE-02` | Zero launch-blocking AE1 | `AE_findings.md` | **N/A** |
| `LG-AE-03` | Critical KPIs defined/measurable | `AE_discovery.md` §3 | **N/A** — no KPIs defined for this product; not invented |
| `LG-AE-04` | Critical events validated | `AE_discovery.md` §4 | **N/A** — no events exist |
| `LG-AE-05` | Success triggers reflect true success | — | **N/A** |
| `LG-AE-06` | Financial events accurate | `AE_discovery.md` §7, §2.2 | **N/A** — no financial events exist; paywall UI is dead code |
| `LG-AE-07` | Duplicate event behavior controlled | — | **N/A** |
| `LG-AE-08` | Identity behavior verified | `AE_discovery.md` §11 | **N/A** — no analytics identity model exists |
| `LG-AE-09` | Critical funnels reconstructable | `AE_discovery.md` §5 | **N/A** |
| `LG-AE-10` | Environment isolation verified | — | **N/A** |
| `LG-AE-11` | Critical reconciliation passes | `AE_discovery.md` §17 | **N/A** |
| `LG-AE-12` | No critical unknowns | `AE_discovery.md` §19 | **PASS** — no *critical* unknowns remain; one non-critical unknown recorded (informal ad hoc SQL usage cannot be verified statically) |

None of these gates block the master GO/NO-GO decision, consistent with the master framework's `N/A | No effect if N/A rationale is valid` rule (§ "Effect on GO" table, line 893).

---

## Residual Risk Register

| Risk ID | Finding | Severity | Probability | Business impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-AE-001` | `AE-001` — dead `_PaywallSheet` monetization stub with no analytics/revenue-event design | AE4 | LOW (currently unreachable) | If someone wires this up later without designing KPI/event instrumentation first, the app would launch monetization completely blind (no trial-start, plan-selection, or conversion visibility) | Track as a Code Quality dead-code item now; if/when monetization is ever pursued, require a KPI/event design pass (this template, Phase 1) *before* wiring `_PaywallSheet` (or its replacement) to a real purchase SDK | Product/Eng | **NO** (not required before this launch; required before any *future* monetization launch) |
| `RISK-AE-002` | No business-visibility mechanism exists at all beyond raw ad hoc SQL (cross-ref `OB-008`, `ROOT-001`) | Not an AE finding (documented as context) | N/A | Compounds detectability risk for `ROOT-001` (possible broken Gemini endpoint) — no formal or informal signal would catch a silent AI-response failure | Owned by Observability audit (`OB-008`); no action required from this audit | Observability audit owner | Per Observability audit's own verdict |

---

## Out-of-Scope / Not Verified (template §73)

- Production analytics workspace: none exists, so "unavailable" is not the reason — it is confirmed absent.
- Historical data quality: not applicable (no analytics data exists to have quality issues).
- Ad-platform attribution: not tested (no attribution capture exists).
- BI warehouse: excluded (none exists).
- CRM/CDP sync: excluded (none exists).
- Long-term cohort calculations: excluded (no data to calculate from).
- Privacy/legal tracking requirements: handled by the Privacy & Compliance audit; this audit found no tracking to have privacy implications in the first place.
- Whether anyone informally runs ad hoc SQL against production Supabase for reporting: could not be verified from static repo inspection; recorded as a non-critical unknown, not converted to PASS or FAIL.

---

## 74. Final One-Sentence Recommendation

> Analytics & Business Events recommendation: **N/A** for `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` — this system has no analytics/telemetry instrumentation (third-party or homegrown) and no live monetization/business-event surface (the only related artifact, `_PaywallSheet`, is confirmed dead/unwired code), confirmed exhaustively across `pubspec.yaml`, `pubspec.lock` (including transitive dependencies), and the full `lib/` source tree; `LG-M-18` should be recorded as N/A-with-rationale in the master report, and this verdict has no effect on the overall GO/NO-GO decision per the master framework's N/A rule.
