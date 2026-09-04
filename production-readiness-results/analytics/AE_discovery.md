# Analytics & Business Events Audit — Discovery Report (AE)

## 2. Report Header

| Field | Value |
|---|---|
| System | Niswah (Flutter mobile app, Supabase backend) |
| Repository | `/Users/rynadalsabh/Niswah` |
| Branch | `main` |
| Commit / Version | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Phase | Wave 4 — Analytics & Business Events Audit |
| Audit date | 2026-09-04 |
| Environment | Static repository inspection only (no runtime/staging environment available to this audit) |
| Analytics platform(s) | **None found** — see §11 |
| Data warehouse / BI | N/A — none found |
| Synthetic test prefix | N/A — no Phase 2B controlled event validation performed (no instrumentation exists to test) |
| Restrictions | No live/runtime execution of the app; no Supabase console/dashboard access exercised interactively; findings are 100% static-evidence (source, `pubspec.yaml`/`pubspec.lock`, SQL migrations) |

---

## 1. Independent confirmation of the "no analytics" premise

The applicability matrix (`00_02_AUDIT_APPLICABILITY_MATRIX.md`) provisionally leaned N/A based on `pubspec.yaml` alone. Per master-framework rule ("no N/A without evidence," "do not mark an audit N/A merely because implementation is unclear"), the following exhaustive, independent checks were performed rather than accepting that lean:

### 1.1 `pubspec.yaml` — full dependency list reviewed
All 15 direct dependencies inspected (full file read, not grepped in isolation):
`cupertino_icons`, `collection`, `equatable`, `flutter_dotenv`, `http`, `url_launcher`, `shared_preferences`, `supabase_flutter`, `uuid`, `pdf`, `printing`, `flutter_local_notifications`, `timezone`, `geolocator`, `adhan_dart`.
No analytics, telemetry, crash-reporting, or product-metrics package present.

### 1.2 `pubspec.lock` — full transitive dependency tree reviewed
All ~90 resolved packages enumerated (`grep -E "^  [a-zA-Z_]+:" pubspec.lock`). No `firebase_*` (any variant), `sentry`, `mixpanel`, `amplitude`, `posthog`, `segment`, `appsflyer`, `adjust`, `braze`, `customer_io`, or any comparable package present, direct or transitive. Confirms Observability audit's OB-008 finding independently from the dependency-tree side, not just the direct-dependency side.

### 1.3 Homegrown/custom instrumentation search
Broad, case-insensitive grep across all of `lib/` for: `analytics`, `telemetry`, `EventTracker`, `logEvent`, `track(`, `Mixpanel`, `Amplitude`, `PostHog`, `Segment\.`, `firebase_analytics`, `AppsFlyer`, `Adjust\b`.

Result: **zero genuine hits.** Every match was a false positive from unrelated domain vocabulary:
- `adjust` → prose text ("adjust automatically after each update") and the Dart `Adjust` timezone widget code, unrelated to the Adjust attribution SDK.
- `segment`/`Segment` → `CycleSegmentId`/`CycleSegment` domain objects (menstrual-cycle-phase segments in `lib/features/cycle_tracking/domain/services/cycle_segment_planner.dart`, `dashboard_screen.dart`, `husband_report_pdf_builder.dart`), unrelated to Segment.io/CDP.

No `AnalyticsService`, `EventTracker`, `Telemetry` class, or any local/Supabase-direct event-logging abstraction exists anywhere in `lib/`.

**Conclusion of §1: the "no analytics" premise is independently confirmed, not merely re-accepted.** Evidence is exhaustive across direct deps, transitive deps, and custom code — not just "SDK absent from pubspec.yaml."

---

## 2. Independent confirmation of the "no monetization" premise

### 2.1 Payment/IAP/subscription package search
`pubspec.yaml`/`pubspec.lock` contain no `in_app_purchase`, `in_app_purchase_android`, `in_app_purchase_storekit`, `stripe`, `revenuecat`/`purchases_flutter`, `braintree`, or any comparable payment SDK.

### 2.2 Monetization keyword search in `lib/`
Broad grep for `in_app_purchase`, `InAppPurchase`, `Stripe`, `RevenueCat`, `payment`, `premium`, `subscription`, `purchase`, `paywall`, `iap` across `lib/`.

**One genuine hit of note: a `_PaywallSheet` widget exists** at `lib/features/auth/presentation/screens/profile_screen.dart:1807-2020` (approx.), a `StatefulWidget` rendering a "Unlock Niswah Plus" bottom sheet with Monthly ($9.99/mo) and Annual ($79.99/yr, "SAVE 20%") plan options, a "Start free trial" `FilledButton`, and "TERMS OF SERVICE • RESTORE PURCHASE" footer text.

**This widget is dead/unreachable code:**
- `grep -rn "_PaywallSheet" lib/` returns only its own class declaration and state-class declaration in `profile_screen.dart` — it is never instantiated, never passed to `showModalBottomSheet`, and has no caller anywhere in the codebase.
- Its "Start free trial" button's `onPressed` handler is literally `() => Navigator.pop(context)` — it does not call any purchase API, does not touch Supabase, does not set any premium flag. Even if the sheet were shown, tapping the primary CTA does nothing but dismiss the sheet.
- No `in_app_purchase` package is present to back a real purchase flow even if the sheet were wired up.

Other matches (`_subscription` for `StreamSubscription<AuthState>`/realtime subscriptions) are unrelated false positives, already known from other audits' scope (auth/realtime, not commerce).

### 2.3 `premium_status` / `isPremium` / `premium_expires_at` cross-check
Grep for `premium_status`, `isPremium`, `premium_expires` across `lib/`: **zero hits.**

This independently reconfirms the Database & Data Integrity audit's DI-004/DI-008 finding: the `users` table's `premium_status`/`premium_expires_at` columns exist in the schema but have **zero** application-code references — no read, no write, no gate, and (per this audit) no UI even attempts to reach them, since the one paywall-shaped UI element in the app (`_PaywallSheet`) is disconnected from both the purchase layer and the premium-flag layer.

**Conclusion of §2: the app has no real monetization/business model as of this commit.** The only monetization-shaped artifact is a fully mocked, unreachable paywall UI stub with no backing purchase mechanism and no wiring to the schema's dormant premium columns.

---

## 3. KPI Inventory (§5 of template)

No KPIs are defined anywhere in the repository (no product requirements doc, no analytics spec, no dashboard config found in-repo). Per template instruction, definitions are **not invented**.

| KPI ID | KPI | Business definition | Numerator | Denominator | Source of truth | Owner |
|---|---|---|---|---|---|---|
| — | — | **PRODUCT / BUSINESS OWNER DEFINITION REQUIRED** — no KPI has ever been defined for this app in-repo | — | — | — | — |

---

## 4. Critical Event Inventory (§6)

No event taxonomy, event name, or trigger point exists anywhere in `lib/` or `supabase/`.

| Event ID | Event name | Business meaning | Trigger condition | Source of truth | Criticality |
|---|---|---|---|---|---|
| — | — | **None instrumented** | — | — | — |

---

## 5. Funnel Inventory (§7)

Not applicable — no events exist to compose a funnel from.

---

## 6. Activation / Retention Definitions (§8, §9)

**PRODUCT / BUSINESS OWNER DEFINITION REQUIRED** for both. No activation event, no retention metric, no definition exists in-repo.

---

## 7. Revenue / Financial Event Inventory (§10)

No revenue/financial events exist. See §2 above: the only monetization-shaped code (`_PaywallSheet`) is unreachable UI with no backing transaction of any kind. No `payment_succeeded`, `subscription_started`, or equivalent event/state exists client- or server-side.

---

## 8. Analytics Platform Inventory (§11)

| Platform | Purpose | Client / server | Environments | SDK/config location |
|---|---|---|---|---|
| **None** | N/A | N/A | N/A | N/A — confirmed via `pubspec.yaml`, `pubspec.lock`, and full-repo grep (§1) |

---

## 9. Event Ownership (§12)

N/A — no events exist to classify.

---

## 10. Event Schema Catalog (§13)

N/A — no event schemas exist.

---

## 11. Identity Model (§14)

No analytics identity model exists (no anonymous ID, no analytics user ID, no identity merge/alias logic). Supabase Auth's own `auth.uid()` is the only identity primitive in the system, and it is used purely for RLS/authorization, not for any analytics purpose.

---

## 12. Session Definition (§15)

Not applicable — no session-based analytics metric exists. (App lifecycle/foreground-background handling, if any, is in scope for the Reliability/Performance audits, not this one.)

---

## 13. Timestamp Model (§16)

Not applicable to analytics events (none exist). Note for context: business-relevant timestamps in the database (`created_at` on `profiles`, `cycle_logs`, `chat_threads`, `chat_messages`, `wellbeing_logs`) are server-side `TIMESTAMPTZ DEFAULT now()` — trustworthy if ever used as an ad hoc analytics substitute (see §16 below).

---

## 14. Attribution Inventory (§17)

Not applicable — no install/marketing attribution capture exists anywhere in the app (no UTM capture, no referral code, no ad click ID handling found).

---

## 15. Experiment / Feature-Flag Analytics (§18)

Not applicable — no experimentation/feature-flag framework found in `pubspec.yaml`, `pubspec.lock`, or `lib/`.

---

## 16. Dashboard / Report Inventory (§19)

None exist. No BI tool, no Supabase dashboard-based reporting config, no internal admin analytics screen found in `lib/`.

---

## 17. Source-of-Truth Reconciliation Inventory (§20)

Not applicable — with no events and no revenue, there is nothing to reconcile.

---

## 18. Adjacent question (per audit brief item 5): does ANY ad hoc business-visibility substitute exist?

Distinct from the formal analytics question: does Supabase's own database provide even a rudimentary, unstructured way for the product/business side to answer basic operational questions?

**Yes, at the raw-SQL/admin-console level only** — not as a product capability. Evidence from `supabase/migrations/`:

| Question | Answerable via | Evidence |
|---|---|---|
| "How many users signed up this week?" | `SELECT count(*) FROM profiles WHERE created_at > now() - interval '7 days'` (or Supabase Studio's Auth → Users list, sortable by `created_at`) | `profiles.created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL` (`supabase/migrations/20260820174500_niswah_production_schema_security.sql:15`) |
| "How many cycle logs are created per day?" | `SELECT date_trunc('day', created_at), count(*) FROM cycle_logs GROUP BY 1` | `cycle_logs.created_at TIMESTAMPTZ ... NOT NULL` (same file, line 27) |
| "Is the AI chat feature being used at all?" | `SELECT count(*) FROM chat_messages WHERE created_at > ...` / `SELECT count(*) FROM chat_threads` | `chat_threads`/`chat_messages` both carry `created_at TIMESTAMPTZ DEFAULT now()`, with indexes `idx_chat_threads_user_id_created_at` and `idx_chat_messages_thread_id_created_at` (`supabase/migrations/20260824115900_dr_niswah_chat_threads.sql`) |

**This is a substitute of last resort, not a business-analytics capability**, for reasons that matter to the launch decision:

- It requires direct Postgres/Supabase-Studio SQL access — not available to a product manager, growth lead, or support engineer without engineering involvement and DB credentials.
- There is no dashboard, no scheduled report, no alerting, no aggregation layer, no defined KPI query anyone has written down or automated.
- It cannot distinguish real usage from errors, retries, or test traffic (no environment tagging on any of these tables).
- It says nothing about *engagement quality* (e.g., "chat_messages count > 0" cannot show whether Gemini responses actually succeeded — see cross-reference below).

**Cross-reference to `ROOT-001` / `OB-008`:** the Observability audit (Wave 3, complete) already found "no analytics/telemetry SDK exists anywhere... removes even the weakest possible secondary signal," in the context of `ROOT-001` (possible broken Gemini endpoint on the `dr-niswah-chat` edge function). This audit's finding sharpens that point: even the raw-SQL fallback above would only show *message rows existing* — a `chat_messages` row is written by the client-side repository (`chat_repository_impl.dart` per migration comments) independent of whether the assistant's Gemini call actually succeeded, so it cannot by itself confirm the AI chat feature is *working*, only that users *attempted* to use it. If `ROOT-001` is real, neither the (non-existent) analytics layer nor this raw-SQL fallback would surface it — only an explicit success/failure event (which does not exist) or manual DB inspection of message `role`/`content` for empty/error assistant replies would.

---

## 19. Discovery Execution Log (§21)

### Fully reviewed
- `pubspec.yaml` (full file, all dependencies)
- `pubspec.lock` (full transitive package list)
- `lib/` — full-tree grep for analytics/telemetry/tracking vocabulary and for monetization/payment/premium vocabulary
- `lib/features/auth/presentation/screens/profile_screen.dart` — full `_PaywallSheet`/`_PaywallSheetState` implementation read in detail
- `supabase/migrations/*.sql` — all 12 migration files reviewed for event/log/analytics/metric table definitions and for `created_at` timestamp presence on key tables
- `supabase/functions/` — directory listing (only `dr-niswah-chat`; no analytics/logging edge function)
- `00_02_AUDIT_APPLICABILITY_MATRIX.md`, `00_PRODUCTION_READINESS_MASTER.md` §§5-6 (N/A rules)

### Partially reviewed
- `supabase/functions/dr-niswah-chat/index.ts` — not read in full (out of scope for this audit; API/Backend and Observability audits own it). Referenced only to confirm no analytics-emitting code lives there via directory-level inspection.

### Structurally scanned
- Full `lib/` directory tree (via grep, not per-file read) for any additional analytics-shaped class names.

### Could not inspect
- Live Supabase project (no runtime credentials/console session available to this static audit) — cannot confirm whether anyone has, informally, run ad hoc SQL queries against production for reporting purposes. Recorded as unknown, not assumed either way.
- Any external spreadsheet/BI tool usage outside the repository — out of repo scope, cannot be verified from source.

### Actions performed

| Action | Purpose | Result |
|---|---|---|
| Full read of `pubspec.yaml` | Direct dependency audit | No analytics/payment SDK |
| Full enumeration of `pubspec.lock` package names | Transitive dependency audit | No analytics/payment SDK, direct or transitive |
| Grep `lib/` for analytics/telemetry vocabulary | Rule out homegrown instrumentation | Zero genuine hits — only false positives (`adjust`, `segment` cycle-domain terms) |
| Grep `lib/` for payment/premium/subscription vocabulary | Confirm/refute monetization surface | Found dead `_PaywallSheet` widget; confirmed unreachable and unwired |
| Grep `lib/` for `premium_status`/`isPremium`/`premium_expires` | Independently reconfirm DI-004/DI-008 | Zero hits — confirmed |
| Read `supabase/migrations/*.sql` for event/log/metric tables | Rule out DB-side analytics substitute | None found; confirmed `created_at` exists on `profiles`, `cycle_logs`, `chat_threads`, `chat_messages` enabling only raw ad hoc SQL visibility |
| Read `00_PRODUCTION_READINESS_MASTER.md` §§5-6 | Confirm N/A is a legitimate, evidenced outcome | Confirmed: "Analytics & Business Events — CONDITIONAL — May be N/A when: Product has no analytics/business measurement requirement" |

### Actions deliberately avoided

| Action | Reason |
|---|---|
| Phase 2B controlled event validation / synthetic journeys | No instrumentation exists to validate — there is nothing to execute a test against. Executing "tests" against a nonexistent system would produce fabricated evidence. |
| Wiring or instrumenting `_PaywallSheet` to a real purchase flow to "test" it | Out of scope — auditor role only, no code changes permitted per task instructions |
| Running ad hoc SQL against production Supabase | No runtime credentials available to this audit; also would require write/read access beyond static-audit scope |

---

## 20. Discovery Exit Gate (§22)

- [x] Critical KPIs identified or definition gaps documented — gap documented (none exist; PRODUCT/BUSINESS OWNER DEFINITION REQUIRED)
- [x] Critical events inventoried — none exist (documented)
- [x] Funnels mapped — N/A (no events)
- [x] Activation and retention definitions documented or escalated — escalated (undefined)
- [x] Financial events mapped — none exist; paywall UI confirmed dead/unwired
- [x] Analytics platforms mapped — none exist (confirmed exhaustively)
- [x] Event ownership known — N/A (no events)
- [x] Event schemas identified — N/A (no events)
- [x] Identity/session model understood — N/A for analytics; Supabase Auth identity model understood and out of this audit's scope
- [x] Attribution requirements understood — none exist
- [x] Dashboards/reports inventoried — none exist
- [x] Reconciliation paths identified — N/A (nothing to reconcile)
- [x] Unknown areas listed — §19 "Could not inspect"

Phase 1 (Discovery) is complete.
