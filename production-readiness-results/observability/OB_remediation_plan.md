# Observability Remediation Plan

> ⚠️ **PROPOSED — NOT IMPLEMENTED.** This plan is a design artifact only. No code, configuration, dependency, or alert change has been made as part of this audit. Everything below requires separate technical review and an explicit implementation decision. Nothing here should be described as fixed until Controlled Signal Validation (Phase 2B) is rerun successfully against a live environment.

| Field | Value |
|---|---|
| System | Niswah |
| Commit audited | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Report created | `OB_remediation_plan.md` |

---

## 1. Root-Cause Map

| Finding | Blind spot | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `OB-001` | No crash capture at any layer | No crash-reporting SDK was ever added (Dart or native) | High | Master `ROOT-005` | R1 |
| `OB-002` | App-wide async errors vanish | `runZonedGuarded` was added only as a narrow deep-link-exception guard (per its own code comment) and was never paired with a reporting sink | High | RR-002, Master `ROOT-005` | R1 |
| `OB-003` | AI-call failure (server) invisible | Edge function's Gemini-call retry/fallback logic was written to protect the user experience (graceful fallback text) but the engineer never added a log statement in the failure branch | High | `ROOT-001`, AB-001, CQ-010 | R1 |
| `OB-004` | Safety-critical write failure can cancel the response with no trace | The urgent-flag DB insert and the Gemini call share one outer try/catch instead of independent, individually-logged guards | High | AB-007 | R1 |
| `OB-005` | Client AI failures invisible | Same graceful-degradation-without-logging pattern replicated independently on the client (`ai_advisor_service.dart`) | High | `ROOT-001` | R1 |
| `OB-006` | No logging framework | No logging dependency was ever chosen; `print`/`debugPrint` was used as a placeholder during development and never replaced | High | CQ-009, DI-002, Master `ROOT-005` | R2 |
| `OB-007` | Exceptions lose context on the way up | The `Failure` hierarchy was designed for user-facing message display, not diagnostics — it was never intended to carry the original error, so this is an architectural gap rather than a bug | High | CQ-009 | R2 |
| `OB-008` | No secondary/proxy signal via analytics | No analytics tool was ever integrated; product-analytics and observability were never considered together | Medium | — | R3 |
| `OB-009` | No version visibility, no kill-switch | No release/deployment pipeline exists yet (DC-006) — version tagging and remote-config were never prioritized in its absence | High | DC-006, Master baseline (no feature flags found) | R2 |
| `OB-010` | RLS bugs are structurally silent | This is an inherent property of RLS-based authorization (a policy bug produces a *correct-looking* successful response) combined with the total absence of any DB access/audit logging that could catch it independently | High | SEC-004 | R2/R3 |
| `OB-011` | No dashboards | Follows directly from `OB-001`/`OB-006`/`OB-008` — there is nothing to build a dashboard on top of yet | High | — | R3 |
| `OB-012` | Inconsistent/incomplete ad hoc logging | Multiple contributors (human or AI-assisted) added `print`/`debugPrint` independently at different times with no shared convention | Medium | — | R2 |

---

## 2. Remediation Principles (applied)

Per template §63: capture critical failures with no silent critical paths; add IDs/context over verbose text; correlate across the Client → Edge Function → Postgres → Gemini boundary; alert only on actionable conditions; tag every signal with release/environment; keep logs/metrics/traces conceptually separate; never leak PII/health data to a third-party logging vendor (this is a health-adjacent app — cycle/pregnancy data is sensitive; any provider chosen in R1 below must be configured to scrub PII, cross-reference Privacy audit before enabling user-context capture); and test every signal before calling a finding closed.

---

## 3. Remediation Phase Table

| # | Action | Findings closed | Components | Signals added/changed | Alert impact | Privacy risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| **R1-1** | Add a crash/error-tracking SDK (e.g. Sentry, which has first-class Flutter + Deno/Edge-Function support) at the Dart layer via `FlutterError.onError` + `PlatformDispatcher.instance.onError`, replacing/augmenting the bare `runZonedGuarded` handler in `lib/main.dart` | `OB-001` (partial, Dart-side), `OB-002` | `lib/main.dart` | Unhandled exception capture with stack trace, device/OS info, release tag | New: crash-rate alert (see R1-4) | **Must scrub cycle/pregnancy-related PII from breadcrumbs/context before enabling** — cross-ref Privacy audit before turning on user-context capture | Feature-flaggable SDK init; disable via config if it misbehaves | Trigger a synthetic uncaught exception in a debug/staging build, confirm it appears in the tool's dashboard with stack + release tag |
| **R1-2** | Add native crash capture (Sentry's native iOS/Android layer, or platform-native Crashlytics) so a crash before the Dart VM is even reachable is still captured | `OB-001` (native-side) | `ios/Runner/AppDelegate.swift`, `android/app/src/main/kotlin/com/niswah/niswah/MainActivity.kt` | Native crash reports independent of Dart | Crash-rate alert extends to native crashes | Low — native crash reports rarely contain app PII by default, but confirm before enabling any custom context | Standard SDK removal | Force a native-layer crash in a debug build, confirm capture |
| **R1-3** | Add `console.error(...)` with structured context (user ID, thread ID, model attempted, HTTP status) at every currently-silent catch in `dr-niswah-chat/index.ts`, specifically lines 269-275 (Gemini failure) and 303-308 (outer handler); split the `flagged_conversations` insert (lines 246-254) into its own try/catch that logs independently and still attempts to deliver the urgent safety banner even if the DB write fails | `OB-003`, `OB-004` | `supabase/functions/dr-niswah-chat/index.ts` | Structured Supabase Edge Function logs for both failure paths; safety banner delivery decoupled from an unrelated DB write | Enables a future alert on "AI reply fallback rate" and "urgent-flag insert failure rate" (see R1-4) | Log content must not include full message text for non-urgent cases beyond what's already stored in `chat_messages`; keep to IDs/status/error class | Log statements are additive, zero behavior risk; safe to ship independently of R1-1/R1-2 | Force a Gemini-call failure (e.g. temporarily invalid model name in a staging function) and a forced `flagged_conversations` insert failure; confirm both appear in Supabase function logs with the added context and that the urgent banner still reaches the client in the second case |
| **R1-4** | Define and wire actionable alerts for: (a) `dr-niswah-chat` non-2xx rate exceeding a threshold over a window, (b) AI-reply-fallback rate (the new signal from R1-3) exceeding a threshold — this is the direct mitigation for `ROOT-001`/`OB-003`'s "100% failure, 200 OK" blind spot, (c) crash-free-session rate dropping below a threshold (from R1-1/R1-2), (d) `flagged_conversations` insert failure (any occurrence — zero-tolerance alert given the safety context) | `OB-003`, `OB-004` (detection completeness) | Alerting platform (new — e.g. Sentry alerts, or Supabase log-based alerting if available on the project's tier) | New alert rules with explicit owner, threshold, destination, runbook | This *is* the alert-coverage remediation | None directly — alert payloads should carry IDs, not raw message content | Alerts can be disabled per-rule without code change | Use the tool's test-alert mechanism; confirm destination receipt and that the message contains actionable context (which condition, which function, link to logs) |
| **R2-1** | Introduce a single structured logging abstraction in `lib/` (thin wrapper around a `logger`-style package or the chosen SDK's breadcrumb/log API) and migrate the 18 existing `print`/`debugPrint` sites plus the highest-value silent catches (auth, cycle tracking, community, private messaging, pregnancy tracking repositories) to it, with mandatory fields: level, module, user ID (pseudonymous), operation, error object/stack | `OB-006`, `OB-012` | All repository/data-layer files listed in `OB_findings.md` §Finding Register | Structured, leveled, centrally-routed logs replacing plain-text `print`/`debugPrint` | Enables R1-4-style alerts on log volume/error rate per module | Ensure no cycle/pregnancy log payload content is captured, only operation/status/IDs | Old `print` calls can be left in place temporarily during migration for a belt-and-suspenders transition | For each migrated repository, force the equivalent of the original DI-002 failure mode (e.g. a bad Supabase call) in a test/staging environment and confirm the new structured log appears in the chosen tool with correct fields |
| **R2-2** | Extend `lib/core/errors/failures.dart`'s `Failure` hierarchy to carry `code`, `category`, and the original `Object? cause` / `StackTrace? stackTrace`, and update the highest-value catch sites (starting with `auth_repository_impl.dart`'s 21 sites, then cycle/pregnancy/community/private-messaging repositories) to populate them instead of discarding the original exception | `OB-007` | `lib/core/errors/failures.dart` and its ~129 call sites (staged rollout, not all at once) | Preserved original exception/stack reaching R1-1's error tracker instead of a bare string | None directly; is a prerequisite for R1-1 being fully useful | None — this is strictly additive context, not new PII exposure by itself (still subject to the same scrub rule as R1-1) | Backward compatible — `Failure.message` keeps working for existing UI code during migration | Unit test: trigger a known typed exception (e.g. `PostgrestException`) through one migrated repository and assert the resulting `Failure` retains `cause`/`stackTrace` |
| **R2-3** | Add `package_info_plus`, read the running version/build at startup, and attach it as a tag to every log/error signal introduced in R1-1/R1-3/R2-1 | `OB-009` (version-tagging half) | `lib/main.dart`, chosen logging/error abstraction | Release/build tag on every signal | Enables "did this start after the last release" triage | None | Trivial to add/remove | Ship two staging builds with different build numbers, confirm the tag differs in captured signals |
| **R2-4** | Introduce a minimal remote-kill-switch/feature-flag mechanism (even a simple Supabase-table-backed boolean per feature, polled on app start/resume, requires no new vendor) so a broken AI feature (recurrence of `ROOT-001`-class issue) can be disabled without an app-store release | `OB-009` (kill-switch half) | New `feature_flags`-style table + a thin client read; gate the 3 AI features on it | New operational control, not a "signal" per se, but directly mitigates the detection-to-mitigation gap this audit's scenario (a) exposes | N/A | None — flag values are not sensitive | Flip the flag back | Toggle the flag in a staging project, confirm the corresponding feature disables client-side without a rebuild |
| **R3-1** | Add a lightweight analytics/telemetry layer (privacy-reviewed — this is a cycle/pregnancy-tracking app, so scope must be operational-event-only: "AI message sent/failed," "cycle log saved/failed," not health content) to provide a secondary, independent signal for the business-critical events in `OB-008` | `OB-008` | New dependency + call sites at each critical operation | Business-event counters usable as a proxy detection signal even if R1/R2 have a gap | Enables volume-drop-based alerting as a second line of defense | **High sensitivity domain — must go through Privacy/Security review before any user-identifying or health-content field is included; operational-event-only scope recommended** | Standard SDK removal | Confirm event counts move as expected during a synthetic critical-path exercise in staging |
| **R3-2** | Build minimal dashboards (even a single Sentry/Supabase-native view per critical signal is sufficient at this stage) covering: crash-free rate, `dr-niswah-chat` error/fallback rate, repository write-failure rate | `OB-011` | Whichever tool(s) are chosen in R1/R2 | N/A (dashboards, not new signals) | N/A | None | N/A | Manual review: can a reviewer answer template §36's questions (is the system healthy / are users experiencing errors / did this begin after a deployment) from the dashboard alone |
| **R3-3** | Add minimal DB-level audit logging (e.g. a trigger-based `audit_log` table, or Postgres's own statement logging where the Supabase tier allows) for the highest-sensitivity tables (`private_messages`, `cycle_entries`, `pregnancy_profile`) as a second-line detection mechanism for RLS-class bugs like `OB-010`/`SEC-004`, independent of and in addition to actually fixing the RLS policy itself (which is Security's remit) | `OB-010` (partial — detection layer only; the underlying policy fix is Security's, not Observability's, responsibility) | New migration(s) + trigger functions | New durable audit trail | Could support a "cross-user access pattern" alert in a later iteration | **High** — an audit log of message/data access is itself sensitive; must be access-controlled at least as strictly as the underlying data, and reviewed by Security/Privacy before implementation | New table/trigger, additive; can be dropped | Confirm a controlled cross-user access attempt in staging produces an audit row |

---

## 4. Alert Design Requirements (for R1-4)

| Alert | Condition | Threshold (proposed, to be reviewed) | Window | Severity | Destination | Owner | Escalation | Suppression | Runbook needed |
|---|---|---|---|---|---|---|---|---|---|
| AI reply fallback rate | `dr-niswah-chat` returns the generic fallback text instead of a real Gemini reply | >20% of requests in window (tune after baseline observed) | 15 min | Critical | Team channel/pager | Backend owner | If sustained >1h, page | Dedup per-function | Yes — "check Gemini endpoint/key/quota first" |
| `flagged_conversations` insert failure | Any failure of the urgent-flag insert | 1 occurrence (zero-tolerance, safety-relevant) | Immediate | Critical | Team channel/pager | Backend owner | Immediate page | None (never suppress) | Yes — "confirm user received urgent banner via app-side fallback; check DB directly" |
| Crash-free session rate | Drop below baseline | To be set after 2 weeks of baseline data post-R1-1/R1-2 | Rolling 1h | High | Team channel | Mobile owner | If sustained, page | Group by crash signature | Yes |
| `dr-niswah-chat` 5xx rate | Non-2xx responses | >5% | 15 min | High | Team channel | Backend owner | If sustained, page | Dedup per-function | Yes |

---

## 5. Logging Design Requirements (for R2-1)

| Event | Severity | Context fields | Correlation IDs | Redaction rules | Destination | Sampling |
|---|---|---|---|---|---|---|
| Repository remote write/read failure | ERROR | module, operation, user ID (pseudonymous), record type, error category | Not yet available (no correlation-ID mechanism exists — proposed as a future R2 follow-up, out of scope for this plan's minimum bar) | Never log cycle/pregnancy/message content, only IDs and error class | Chosen logging/error tool | 100% (low volume expected) |
| AI call failure (client or server) | ERROR | model attempted, HTTP status, retry count, thread ID | Same as above | Never log full prompt/reply content, only metadata | Chosen logging/error tool | 100% |
| Startup config load failure | FATAL | which env var missing/invalid, environment | N/A (pre-session) | N/A | Chosen logging/error tool | 100% |
| Uncaught exception (any) | ERROR/FATAL | full stack, release, device/OS | N/A | Scrub via tool's PII-scrubbing config before enabling breadcrumbs | Chosen error tool | 100% |

---

## 6. Remediation Exit Gate

- [x] Blind spot/root cause identified for every OB0/OB1/OB2 finding (§1).
- [x] Required signals defined (§3, §4, §5).
- [ ] Correlation strategy defined — **only partially**: release/version tagging is proposed (R2-3), but a full request/thread correlation-ID mechanism across Client → Edge Function → Postgres → Gemini is flagged as a future follow-up, not fully specified in this plan. This should be treated as an open design gap in the remediation itself.
- [x] Alert action/owner defined for the R1-4 alert set (§4).
- [x] Privacy/security review flagged explicitly wherever user context, message content, or audit logging is proposed (R1-1, R1-3, R3-1, R3-3) — **must be completed before implementation, not assumed**.
- [x] Noise risk considered — thresholds marked "to be tuned after baseline," zero-tolerance alert reserved only for the one genuinely safety-critical condition.
- [x] Retest defined per phase row (§3, rightmost column).
- [x] No unnecessary high-volume logging proposed — sampling table (§5) keeps everything at low-volume, error-only granularity; no full-payload or per-render logging proposed anywhere.

This plan is **implementation-ready pending the flagged privacy/security reviews and a technical decision on tooling** (Sentry vs. an alternative; Supabase-native log-based alerting vs. a third-party alerting tool). It is not itself an implementation and closes no findings until re-verified per template §67/§70.
