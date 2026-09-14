# 00_11 — Canonical Requirements Ledger

**Generated**: Niswah Full Implementation Reconciliation wave, 2026-09-14.
**Method**: three parallel documentation/code discovery passes (all approved product/technical/security/privacy/onboarding/auth/fiqh documentation across `production-readiness/MDs/` and `production-readiness-results/`; a full `lib/` code inventory; a spot-check re-verification of 30 historical findings across every finding namespace) plus direct live Supabase inspection (schema, RLS, edge functions, storage, current Auth config) performed by this session directly. This is discovery only — **nothing in this document has been remediated**, per explicit instruction.

**Scope note**: this ledger is not a literal line-by-line transcription of every sentence in every audit document (that would run to many hundreds of near-duplicate micro-items across 15+ audit domains, most already fully tracked in `00_04_MASTER_FINDING_REGISTER.md`). It captures every **distinct** approved requirement/decision/product behavior that this pass's discovery surfaced as either (a) not yet mapped to a finding ID, (b) mapped but with a concrete implementation gap not previously called out this precisely, or (c) launch-critical and worth an explicit, current status regardless of prior tracking. Requirements already fully and correctly tracked as CLOSED findings (confirmed still valid by the historical re-verification pass) are referenced by their existing finding ID rather than re-litigated here.

Each requirement has 9 fields, per the charter: ID · Domain · Description · Source · Severity · Launch-critical · Implementation location · Persistence dependency · Test location · Evidence level · Live verification status · Production deployment status · Finding IDs · Status.

---

## REQ-FIQH-001 — Madhhab: "I don't know" path (FLAGSHIP)

- **Domain**: Fiqh / Onboarding
- **Description**: Onboarding's madhhab step must offer a 5th option — "I don't know my madhhab" — alongside Hanafi/Maliki/Shafi'i/Hanbali. Selecting it must not force a religious classification; the app may offer a hedged, geography-based *suggestion* (never a declaration), require explicit user confirmation before any suggestion becomes authoritative, and must never let the AI say "you are Hanafi" based on location alone.
- **Source**: `production-readiness/MDs/FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md` §"Onboarding Flow" (verbatim: "Options: Hanafi / Maliki / Shafi'i / Hanbali / **I don't know my madhhab**"); independently corroborated by `production-readiness-results/fiqh-engine/SCHOLAR_REVIEW_PACKAGE.md` §1 ("a not-yet-shipped design") and `docs/final-owner-launch-checklist.md` (explicitly documents a built-but-unwired suggestion engine).
- **Severity**: Not formally severity-tagged by the charter itself; this reconciliation classifies it **HIGH** — it is a named, explicit, repeatedly-documented product requirement with a real user-facing consequence (a woman who genuinely doesn't know her madhhab is forced to guess or cannot complete onboarding).
- **Launch-critical**: Product/UX judgment call, not a technical blocker — flagged for owner decision, not asserted here.
- **Implementation location**: Onboarding step (`lib/features/onboarding/presentation/screens/onboarding_screen.dart`, `_madhhabChoices` getter) offers only the 4 fixed choices; `onNext` is disabled until one is picked — no escape hatch exists, unlike the Last-Period step's real "I'm not sure" pattern in the same file. A separate, fully-built geographic-suggestion engine exists (`lib/features/onboarding/domain/services/madhhab_suggestion_service.dart` — confidence levels, 10-country mapping, explicit-confirmation contract, 11/11 unit tests passing) but is **dead code**: confirmed via exhaustive grep, it is instantiated nowhere in `lib/`, not imported by the onboarding screen.
- **Backend/database dependency**: None currently — see REQ-FIQH-002 below (madhhab has no server persistence at all, a second, separate gap).
- **Local storage dependency**: `MadhhabController` (`lib/core/preferences/madhhab_controller.dart`), SharedPreferences key `niswah_selected_madhhab`; the `Madhhab` enum backing it (`hanafi, maliki, shafii, hanbali`) has no `unsure`/`unknown` value, so even if the UI were fixed, the persistence type itself would need extending.
- **Test location**: `MadhhabSuggestionService` has its own unit test suite (11/11 passing, per `00_09` §58) — but this tests the *unwired* service in isolation, not the actual onboarding UI (which has zero tests exercising an "I don't know" path, because no such path exists to test).
- **Evidence level**: **E1 (static verified)** for the suggestion engine's own logic in isolation; **E0 (assumed/not applicable)** for the end-to-end product requirement, since the feature does not exist in any reachable UI.
- **Live verification status**: Not applicable — nothing to verify live.
- **Production deployment status**: `MadhhabSuggestionService` and its data files are in the repository and would ship in any build, but are inert (never called) — effectively **not deployed as a feature**, only as dormant code.
- **Finding IDs**: **`AUTH-010`** (formally assigned, Post-Reconciliation Governance Correction wave, 2026-09-14 — this specific gap, item A only; the silent-default behavior, item B, is `AUTH-005`, a separate already-tracked finding, not duplicated here).
- **Launch decision, 2026-09-14**: **NOT launch-blocking** — recorded explicitly, not left implicit. No current user receives incorrect religious guidance from this gap (every user who completes onboarding explicitly picks a real madhhab); the harm is a forced-guess UX gap, not a correctness defect. Recommended for a near-term post-reconciliation wave, pending owner priority.
- **Status**: **MISSING** (UI/product surface) with **VERIFIED** (isolated, dead) backend logic underneath.

## REQ-FIQH-002 — Madhhab: no server-side persistence (reinstall/new-device loss)

- **Domain**: Fiqh / Data integrity
- **Description**: A user's madhhab choice, once made, must survive a reinstall or a new device — matching the adversarial-validation charter's own "no local-only authority" Tier-1 rule for onboarding/user state.
- **Source**: `production-readiness/MDs/NISWAH_PRELAUNCH_ADVERSARIAL_VALIDATION_MASTER.md` §7.2 ("no local-only authority"); implied by the general onboarding-completion server-authority pattern already established for `onboarding_completed` (AUTH-002).
- **Severity**: HIGH — silent, total loss of an explicit religious-practice choice on reinstall is a real, user-facing correctness defect for a fiqh app specifically.
- **Launch-critical**: Recommended yes, given the app's own stated purpose (a fiqh-aware tracker) — flagged for owner confirmation, not asserted unilaterally.
- **Implementation location**: `MadhhabController` — SharedPreferences only. Live Supabase schema check this pass confirms **no column on `public.users` (or any other table) stores a client-selected madhhab** — the closest-named column, `users.madhhab` (`text`, default `'HANBALI'`), is confirmed via code grep to be **never read or written by any app code path** (a second, independent local-only-unsafe pattern, structurally identical to the already-tracked `AUTH-006` prayer-location finding but never itself assigned a finding ID). A *different*, fully orphaned table/column (`profiles.selected_madhhab`, `USER-DEFINED madhhab_type`, default `'shafii'`) exists and is written only by the dead `SettingsScreen`/`UserProfileRepository` stack (see REQ-ARCH-001).
- **Backend/database dependency**: `public.users.madhhab` column exists live, unused by app code. `public.profiles.selected_madhhab` exists live, used only by dead code.
- **Local storage dependency**: `SharedPreferences` key `niswah_selected_madhhab`, unsynced.
- **Test location**: None — no test exercises reinstall-persistence of madhhab, because there is no server sync to test.
- **Evidence level**: **E2 (automated verified)** for the fact of local-only storage (confirmed via direct code grep and live schema query this pass); **E0** for any claim of correctness, since correctness requires server sync that doesn't exist.
- **Live verification status**: Confirmed live via direct Supabase query this pass (`users.madhhab` and `profiles.selected_madhhab` both exist; app never writes the former, only dead code writes the latter).
- **Production deployment status**: The gap is present in current production — a real reinstall today loses the madhhab choice.
- **Finding IDs**: **`AUTH-005`** — **governance correction, 2026-09-14**: this ledger entry was drafted without cross-referencing the finding register and incorrectly stated "none previously assigned." `AUTH-005` (opened Wave 1 Governance Update, 2026-09-11) already tracks this exact requirement, in nearly identical terms, with the same evidence. `REQ-FIQH-002` and `AUTH-005` are the same requirement — this entry is retained in the ledger for the charter's requested REQ-ID structure, but the finding register's `AUTH-005` row is the canonical, authoritative record; see it for the current, corrected status (including this pass's confirmation that the silent-default mechanism reaches live fiqh-calculation and AI-context code, and a recommendation for owner reconsideration of its blocking status). Same class of gap as `AUTH-006` (prayer location) and the newly-classified marital-status equivalent (`REQ-ONBOARD-003`, `LOCAL_ONLY_UNSAFE`, not yet assigned its own finding ID).
- **Status**: **MISSING** (server persistence) — tracked as `AUTH-005`, not a new/duplicate entry.

## REQ-ONBOARD-001 — Onboarding must not show authentication UI to an already-authenticated user

- **Domain**: Onboarding / Auth
- **Source**: Adversarial-validation charter §7.1/§7.2; directly, repeatedly re-litigated this engagement as `AUTH-008`.
- **Severity**: CRITICAL / launch blocker.
- **Launch-critical**: YES.
- **Implementation location**: `lib/main.dart` `_buildHome` (sole root auth guard); `lib/features/onboarding/presentation/screens/onboarding_screen.dart` (no embedded login step, as of the `AUTH-008` fix).
- **Backend/database dependency**: `public.users.onboarding_completed`.
- **Local storage dependency**: none (in-memory `AuthController` state only, re-fetched from server on every genuine sign-in).
- **Test location**: `test/auth_onboarding_routing_test.dart`, `test/onboarding_ui_test.dart`.
- **Evidence level**: **E4 (live journey verified)** — automated coverage plus a real, fresh-install owner device retest.
- **Live verification status**: **E4 PASS, 2026-09-14** — the owner completed a fresh-install iOS retest of the exact prescribed script and reported PASS on every item this requirement covers (no second Sign In/Sign Up during onboarding; Sign Out returns to Sign In; subsequent Sign In goes directly to the dashboard). This supersedes the prior `E4_FAIL`/`REOPENED` status recorded below for historical context.
- **Production deployment status**: The fix is live in the current codebase and now confirmed running on the owner's real device.
- **Finding IDs**: `AUTH-008` (`VERIFIED_CLOSED` / `E4`, closed 2026-09-14; the full reopening episode is preserved in the finding register as historical evidence).
- **Status**: **VERIFIED_CLOSED** (`E4`).

## REQ-ONBOARD-002 — Onboarding must not re-ask for a language already selected pre-auth

- **Domain**: Onboarding
- **Source**: Owner-reported live defect; adversarial-validation charter's general "no unnecessary duplication" framing.
- **Severity**: HIGH.
- **Launch-critical**: YES (owner-reported, real UX regression on the primary signup path).
- **Implementation location**: `lib/features/onboarding/presentation/screens/onboarding_screen.dart` (Language step removed as of `AUTH-009`); `AppLocaleController` is now the sole authority.
- **Backend/database dependency**: none — language is intentionally local-only by design (not flagged as a gap, unlike madhhab/marital-status/prayer-location, since there is no server-side concept of "account language" documented as required).
- **Local storage dependency**: SharedPreferences key `niswah_arabic`.
- **Test location**: `test/onboarding_ui_test.dart` (splash → Madhhab direct-transition group), `test/auth_onboarding_routing_test.dart` (real-journey group).
- **Evidence level**: **E4 (live journey verified)**, including root-router-level tests reproducing the owner's exact real sequence, plus a real owner device retest.
- **Live verification status**: **E4 PASS, 2026-09-14** — the owner's fresh-install iOS retest reported both "language selected pre-auth: PASS" and "no duplicate Language screen after login: PASS."
- **Production deployment status**: fix is live in current codebase, confirmed running on the owner's real device.
- **Finding IDs**: `AUTH-009` (`VERIFIED_CLOSED` / `E4`, closed 2026-09-14).
- **Status**: **VERIFIED_CLOSED** (`E4`).

## REQ-ONBOARD-003 — Marital status must not be local-only if it is account-level state

- **Domain**: Onboarding / Data integrity
- **Description**: Same class of concern as `AUTH-006` (prayer location): if marital status is meant to be account-level state (it gates spouse-only pregnancy tools/reports, per existing product logic), it should not be lost on reinstall.
- **Source**: Inferred from the adversarial charter's general local-only-authority rule, applied by analogy to `AUTH-006`'s own reasoning; newly surfaced by this pass's code inventory, not previously documented as its own gap.
- **Severity**: MEDIUM — lower than madhhab/prayer-location since marital status gates optional UI, not core fiqh correctness, but the same structural defect.
- **Governance classification (item 5 of the correction charter)**: **`LOCAL_ONLY_UNSAFE`**, not `INTENTIONAL_LOCAL_ONLY` — reasoned explicitly, not asserted by analogy alone: (1) it is **not** documented anywhere as an intentional device-only preference (unlike, say, theme mode, which genuinely is a device preference by design); (2) a real downstream feature depends on it — the Married onboarding step's own subtitle states it "controls spouse-only pregnancy tools and reports," confirming real features are gated by this value; (3) reinstall/account-switching **does** cause incorrect behavior: since `onboarding_completed = true` for an already-onboarded user routes her straight to the dashboard (never back through the Married step), a silent reset to the unmarried default would hide spouse-only features she should have access to, with no prompt to re-answer; (4) server durability is therefore genuinely required for correctness, not merely nice-to-have. This is a real, if lower-stakes than `AUTH-005`/`AUTH-006`, product-correctness gap — not ordinary UX polish.
- **Launch-critical**: Not launch-blocking (feature-visibility gap, not religious/safety correctness) — flagged for owner triage alongside `AUTH-006`.
- **Implementation location**: `MaritalStatusController` (`lib/core/preferences/marital_status_controller.dart`).
- **Backend/database dependency**: none found — confirmed via grep, no Supabase column for marital status is read or written anywhere in `lib/`.
- **Local storage dependency**: SharedPreferences key `niswah_is_married`.
- **Test location**: covered incidentally by onboarding tests for the Married step's UI behavior; no reinstall/persistence-loss test exists (there is nothing to test).
- **Evidence level**: **E2 (automated verified)** for the fact of local-only storage.
- **Live verification status**: not applicable (no server sync to verify).
- **Production deployment status**: gap present in current production.
- **Finding IDs**: none previously assigned — recommend tracking alongside `AUTH-006` in a future wave (not done here; this pass classifies but does not allocate a new finding ID for this one, since the charter's item 5 asked for classification, not formal tracking).
- **Status**: **MISSING** (server persistence), classified **`LOCAL_ONLY_UNSAFE`**.

## REQ-ARCH-001 — No duplicate/orphaned state-authority stacks for the same user concept

- **Domain**: Architecture / Code quality
- **Description**: Each user-state concept (settings, madhhab, cycle logs, prayer tracking) should have exactly one implementation reachable from the app's real navigation graph — this is the exact class of bug already found and fixed once this engagement (onboarding's duplicated `_arabic` locale field, `AUTH-007`).
- **Source**: Pattern established by `AUTH-007`'s own root-cause; this pass's code inventory found the pattern recurs elsewhere, undetected until now.
- **Severity**: MEDIUM as currently shipped (the duplicates are dead code, not live-divergence bugs) — but HIGH risk, since a future edit to the wrong stack (an easy mistake, since both compile and look plausible) would silently ship a real state-divergence bug.
- **Launch-critical**: Not blocking (dead code cannot diverge at runtime) — recommended cleanup, not a launch gate.
- **Implementation location — 3 confirmed instances**:
  1. **Settings**: `ProfileScreen` (live, reachable) vs. `SettingsScreen` (`lib/features/settings/settings_screen.dart`, fully orphaned — confirmed zero references outside its own file) and `AccountSettingsScreen` (`lib/features/auth/presentation/screens/account_settings_screen.dart`, also fully orphaned). The orphaned `SettingsScreen` additionally uses its own dead type stack: `MadhhabType` enum (`lib/core/models/madhhab_type.dart`) + `UserProfile` model + `UserProfileRepository` → table `profiles` — a second, independent madhhab representation from the live `Madhhab`/`MadhhabController` stack (see REQ-FIQH-002).
  2. **Cycle logging**: `CycleTrackingRepositoryImpl` → table `cycle_entries` (live, injected into the real `CycleTrackingViewModel`) vs. `CycleLogRepository` (`lib/core/services/cycle_log_repository.dart`) → a *different* table, `cycle_logs`, with its own separate entity — confirmed fully orphaned (zero references outside its own file).
  3. **Prayer tracking**: a dashboard-embedded card (live, reachable, backed by `PrayerTrackingViewModel`) vs. a full-screen `PrayerTrackingScreen` (`lib/features/prayer_tracking/presentation/screens/prayer_tracking_screen.dart`) using the *same* view model but never pushed from anywhere — an orphaned duplicate UI for the same live state, not a duplicate state authority.
- **Backend/database dependency**: live tables `cycle_entries` (real) and `cycle_logs` (orphaned, confirmed to exist in production schema with 7 columns — see production drift report); `profiles.selected_madhhab` (orphaned) vs `users.madhhab`/`MadhhabController` (unused vs. live, respectively — a 3-way split).
- **Local storage dependency**: n/a beyond what's already covered under REQ-FIQH-002.
- **Test location**: none of the orphaned stacks have their own tests (expected, since they're unreachable).
- **Evidence level**: **E2 (automated verified)** — confirmed via exhaustive code grep this pass, not inference.
- **Live verification status**: n/a (dead code).
- **Production deployment status**: the dead code ships in the app bundle (harmless bloat) but is never executed.
- **Finding IDs**: none previously assigned.
- **Status**: **REGRESSED-RISK / DEAD-CODE** — not a live bug today, but recommended for cleanup before it becomes one.

## REQ-ONBOARD-004 — "Journeys" feature advertised at onboarding completion must be reachable

- **Domain**: Onboarding / Product completeness
- **Description**: The Welcome screen (onboarding's final step) advertises a "Journeys" feature (`_Feature(Icons.menu_book_rounded, 'Journeys')`) as part of what the app delivers.
- **Source**: `lib/features/onboarding/presentation/screens/onboarding_screen.dart` itself (the promise), cross-checked against the code inventory (the gap).
- **Severity**: MEDIUM — a promise made directly to every new user that isn't kept.
- **Launch-critical**: Recommended yes (false advertising to every single new user at the exact moment of highest trust) — flagged for owner decision.
- **Implementation location**: The screen implementing this, `GuidedJourneysScreen` (`lib/features/education/presentation/screens/guided_journeys_screen.dart`), exists and is confirmed fully built but **orphaned** — zero references anywhere outside its own file, not reachable from any navigation path in the app.
- **Backend/database dependency**: unknown without deeper inspection of `GuidedJourneysScreen`'s own data needs (out of scope for this pass).
- **Local storage dependency**: unknown, same reason.
- **Test location**: not checked this pass (screen is unreachable, so no integration test would exercise it via real navigation).
- **Evidence level**: **E2 (automated verified)** for the fact of the promise + the orphaned screen; **E0** for whether the screen itself works if wired in.
- **Live verification status**: not applicable.
- **Production deployment status**: ships in the bundle, unreachable.
- **Finding IDs**: **`PJ-007`** (formally assigned, Post-Reconciliation Governance Correction wave, 2026-09-14).
- **Governance classification (item 6 of the correction charter)**: **not** `GRAY`/`DEFERRED` — every genuinely-deferred item in the founder dashboard (retention period, DPA terms, age-gate, scholar review) has an explicit, on-record rationale and, critically, does **not** advertise the missing thing to users. This one does (onboarding's own Welcome screen lists it as delivered), which is a materially worse, more visible pattern than a silent gap. Classified as approved-but-undelivered launch functionality.
- **Status**: **MISSING** (navigation wiring only — the feature itself appears built), tracked as `PJ-007`.

## REQ-ONBOARD-005 — Onboarding's "Privacy" step must match its name

- **Domain**: Onboarding / Privacy
- **Description**: A step titled "Privacy" in a 4/8-step onboarding flow collecting health and religious data should reasonably be expected to address data-processing consent, not just a display-identity toggle.
- **Source**: Cross-referenced from `PRIVACY_COMPLIANCE_AUDIT_TEMPLATE_MASTER.md`'s heightened-consent requirement (already tracked as `PC-001`/a proposed-but-unbuilt `R1-2` durable consent record) against the actual current onboarding step inventory.
- **Severity**: LOW as a naming issue, MEDIUM as a symptom of the still-open `PC-005` labeling finding and the never-built `R1-2` durable consent record.
- **Launch-critical**: **Launch decision (item 7 of the correction charter): non-blocking but recommended.** The underlying consent-gate defect (`PC-001`) is already fixed and tracked; this is a naming/UX clarity observation layered on top, not a functional gap.
- **Implementation location**: `_Privacy` widget, onboarding step 9/7 — contains only the Anonymous Mode ("Hide my identity") toggle. The actual ToS/Privacy-Policy consent checkbox lives on the embedded sign-in step (`sign_in_screen.dart`, `Key('consent_checkbox')`), not this step.
- **Backend/database dependency**: `profiles.anonymous_mode` (correct, server-authoritative, single authority — confirmed clean).
- **Local storage dependency**: none.
- **Test location**: `sign_in_consent_gating_test.dart` (for the real consent checkbox, correctly named/tested); no test asserts what onboarding step 9's "Privacy" title should mean.
- **Evidence level**: **E2 (automated verified)** for the current behavior; this is a documentation/product-clarity finding, not a functional defect.
- **Live verification status**: n/a.
- **Production deployment status**: current, live.
- **Finding IDs**: relates to `PC-005` (open, labeling) — not merged into it here since the underlying mechanism is different (this is onboarding-step naming, `PC-005` is broader in-app labeling).
- **Status**: **PARTIAL** (functionally fine, naming/expectation mismatch).

## REQ-DATA-001 — Full personal-data export must cover every table the app writes to

- **Domain**: Privacy / Data rights
- **Source**: `PRIVACY_COMPLIANCE_AUDIT_TEMPLATE_MASTER.md` §23; already tracked as `PC-006`, `PARTIALLY_REMEDIATED`.
- **Severity**: MEDIUM (legal-adjacent, GDPR/data-portability-style expectation).
- **Launch-critical**: **Launch decision (item 7): non-blocking but required before the app can honestly claim "full data export."** No cross-user data leaks and no security exposure — the gap is completeness, not correctness. Recommended resolution alongside the already-legal-gated retention-period and DPA items, not a technical launch blocker on its own.
- **Implementation location**: `lib/features/legal/domain/data_export_builder.dart` — exports `users`, `profiles`, `pregnancy_profile`, `cycle_entries`, `prayer_log`, `community_posts`, `chat_threads`, `chat_messages`.
- **Backend/database dependency**: confirmed live tables **not** included: `wellbeing_logs`, `community_comments`, `community_likes`, `private_conversations`, `private_messages`, `dream_entries`, `educational_resources`. `flagged_conversations` is deliberately, correctly excluded (documented `UNAVAILABLE_BY_DESIGN`, a safety log).
- **Local storage dependency**: none (export is server-data only, correctly).
- **Test location**: not independently verified this pass whether an export test exists asserting full table coverage — the gap was found via direct comparison of `exportSections` against the live table list, not via a failing test.
- **Evidence level**: **E2 (automated verified)** — confirmed via direct code-to-live-schema comparison this pass.
- **Live verification status**: confirmed live (both the export code and the live table list were checked this pass).
- **Production deployment status**: current gap is live in production.
- **Finding IDs**: `PC-006` (existing, `PARTIALLY_REMEDIATED`) — this ledger entry adds a **complete, live-schema-verified list** of exactly which tables are still missing, which the existing finding did not previously enumerate this precisely.
- **Status**: **PARTIAL**.

## REQ-DATA-002 — Account deletion must clear all local device state, not only cycle/prayer caches

- **Domain**: Privacy / Data rights
- **Source**: Addendum to `PC-007`; this pass's code inventory.
- **Severity**: MEDIUM.
- **Launch-critical**: **Launch decision (item 7): non-blocking but recommended.** This is on-device residue only (not a cross-user leak — `PC-010`'s cross-user isolation fix is unaffected and remains correct); a "deleted" account leaving stale local preferences on the same physical device is a privacy-hygiene gap, not a security or correctness one.
- **Implementation location**: `lib/core/storage/local_sensitive_data_cleanup.dart`, `localSensitiveDataCleanupTasks` map — covers only `cycle_tracking` and `prayer_tracking` local caches.
- **Backend/database dependency**: n/a (this is entirely about local, on-device residue after the server-side `delete_my_account` RPC succeeds).
- **Local storage dependency**: confirmed **not** cleared on deletion: madhhab selection, marital status, prayer-location (3 keys), pregnancy-status (4 keys), notification log/preferences, theme mode, TTC-mode, language preference.
- **Test location**: not checked this pass whether a test asserts full local-key cleanup on deletion.
- **Evidence level**: **E2 (automated verified)** — confirmed via direct comparison of the cleanup map against the full SharedPreferences key inventory this pass produced.
- **Live verification status**: confirmed via code inspection; not live-tested against a real deletion this pass.
- **Production deployment status**: current gap is live.
- **Finding IDs**: relates to `PC-007` (existing) — not previously enumerated this precisely.
- **Status**: **PARTIAL**.

## REQ-NOTIF-001 — Prayer-time notification scheduling must fail loudly, not silently

- **Domain**: Notifications / Reliability
- **Source**: Already tracked, `RR-003`.
- **Severity**: HIGH.
- **Launch-critical**: Recommended yes for a prayer-tracking core feature.
- **Implementation location**: `lib/core/services/notification_service.dart` — a failed `initialize()` causes every subsequent `scheduleAt`/`scheduleDaily` call to silently no-op for the rest of the app's process lifetime.
- **Backend/database dependency**: none (100% on-device — confirmed via this pass's grep, zero Supabase tables/RPCs anywhere under `lib/features/notifications/`).
- **Local storage dependency**: `niswah_notification_log`, `niswah_notification_preferences`.
- **Test location**: traced in `PJ_journey_traces.md` §PJ-J6 (verdict: PARTIAL); this pass did not confirm whether an automated regression test now guards the silent-no-op path specifically.
- **Evidence level**: **E2 (automated verified)** for the root cause; unresolved whether a fix has landed (not confirmed by either the historical-finding agent's sample or this pass's own check — flagged as **UNTESTED** for current status pending a direct check).
- **Live verification status**: not checked this pass.
- **Production deployment status**: unknown current state — this is the one item in this ledger this pass could not confidently resolve either way.
- **Finding IDs**: `RR-003`.
- **Governance answer (item 8 of the correction charter)**: **Required evidence level**: E2 (an automated test asserting `NotificationService` failure surfaces visibly and does not silently no-op) at minimum; E3/E4 recommended given it affects a core prayer-tracking feature. **Launch-blocking**: NO — this is a failure-path/edge-case defect (occurs only if `initialize()` itself fails), not a defect in the normal, working path. **Recommended future validation wave**: a dedicated Notifications Reliability wave, bundled with `RR-003`'s original scope, not this reconciliation pass.
- **Status**: **UNTESTED** (this reconciliation could not confirm current resolution state; recommend explicit re-check in the traceability matrix's follow-up column).

## REQ-CYCLE-001 — Wellbeing check-in local cache must not silently diverge from the synced record

- **Domain**: Wellbeing / Data integrity
- **Source**: Newly surfaced by this pass's code inventory (not previously documented as its own concern).
- **Severity**: LOW-MEDIUM.
- **Launch-critical**: No.
- **Implementation location**: `dashboard_screen.dart` maintains its own "today's check-in" cache (`dashboard_wellbeing_mood/energy/sleep/date/notes`) separate from the Supabase-backed `WellbeingRepository`/`wellbeing_logs` table.
- **Backend/database dependency**: `wellbeing_logs` (live, correct, single server authority for the *durable* record).
- **Local storage dependency**: 5 SharedPreferences keys, purpose appears to be UI-responsiveness (show today's entry instantly without a round-trip), not a second durable authority — but not confirmed atomic/reconciled against the server write.
- **Test location**: not checked this pass.
- **Evidence level**: **E1 (static verified)** — code exists as described; live-divergence risk not tested.
- **Live verification status**: not tested.
- **Production deployment status**: current, live.
- **Finding IDs**: none previously assigned.
- **Governance answer (item 8 of the correction charter)**: **Required evidence level**: E2 (a test asserting the local "today" cache and the server `wellbeing_logs` upsert stay consistent, or explicitly confirming the cache is display-only and cannot cause data loss if they diverge). **Launch-blocking**: NO — low-medium severity, no confirmed live-divergence, no data-loss mechanism identified (the durable record is server-side and correct). **Recommended future validation wave**: a future Wellbeing/data-integrity wave, not this reconciliation pass.
- **Status**: **UNTESTED**.

---

## Requirements already fully and correctly tracked (referenced, not re-litigated)

The following approved requirements were confirmed by this pass's historical-finding re-verification to already have accurate, current `CLOSED`/`VERIFIED_CLOSED` tracking in `00_04_MASTER_FINDING_REGISTER.md`, with their cited code/test evidence still present and unregressed — they are intentionally **not** duplicated as new ledger entries: `AUTH-002` (onboarding-completion server authority), `RR-004/005/006/007/008` (reliability contracts + idempotency), `OB-002`/`RR-002`/`FQ-002` (global error reporting), `DC-003/004` (secret handling, config-load safety), `SEC-001` (no client-side AI keys), `DI-001`/`BR-002` (migration-drift CI gate), `CQ-007`/`PJ-005` (no fabricated-data fallback on session loss), `PJ-004` (chat persistence error visibility), `PJ-006` (report completeness), `PC-001/002/010` (consent gating, account deletion, cross-user local-storage isolation), `AU-003/004/012/013/014` (contrast, severity-indicator, semantics), `RD-006/009` (release workflows), `AB-008`/`W1-001` (AI rate-limiter regression + its own sentinel detection).

**Closed this session (2026-09-14) on fresh owner E4 evidence**: `AUTH-007` (Arabic locale/RTL), `AUTH-008` (circular auth, reopened then reclosed), `AUTH-009` (redundant language step) — all `VERIFIED_CLOSED` / `E4`, per the owner's fresh-install iOS retest reporting PASS on every covered item. See the finding register for the full reconciliation and preserved historical-evidence trail.

**New findings formally assigned this session (2026-09-14)**: `AUTH-010` (Madhhab "I don't know" UX — `REQ-FIQH-001`), `PJ-007` (Journeys screen unreachable — `REQ-ONBOARD-004`).

Also confirmed still correctly and honestly **open** (not falsely claimed closed): `AUTH-001` (Auth config — see the Production Drift Report for this pass's fresh confirmation of exactly what *is* now live vs. still open), `AUTH-005` (Madhhab persistence — **this is the canonical finding for `REQ-FIQH-002`**, sharpened this session with a confirmed live fiqh-calculation/AI-context impact mechanism and a recommendation for owner reconsideration of its blocking status), `PF-001/002/003` (startup parallelization), `AB-003/004/006/007`, `RD-007`/`PC-004` (public policy hosting), retention period, DPA/subprocessor terms, age-gate, `FIQH-2/4/6/7` (scholar review, istihada state, prayer-fiqh linkage).

---

## Ledger summary

- **Total ledger entries this pass**: 12 new/refined (above), plus ~35 existing findings referenced as already-accurate.
- **New MISSING**: `REQ-FIQH-001` / `AUTH-010` (Madhhab "I don't know" UI — not launch-blocking), `REQ-FIQH-002` / `AUTH-005` (Madhhab server persistence — **corrected**: maps to the already-open `AUTH-005`, not a new/duplicate finding), `REQ-ONBOARD-003` (marital status server persistence, classified `LOCAL_ONLY_UNSAFE`, not launch-blocking), `REQ-ONBOARD-004` / `PJ-007` (Journeys screen unreachable — not launch-blocking, owner decision to wire in or remove the promise).
- **New PARTIAL**: `REQ-ONBOARD-005` (Privacy step naming — non-blocking, recommended), `REQ-DATA-001` (export coverage — non-blocking, required before claiming "full" export), `REQ-DATA-002` (deletion local-cleanup coverage — non-blocking, recommended).
- **New UNTESTED**: `REQ-NOTIF-001` (not launch-blocking; future Notifications Reliability wave), `REQ-CYCLE-001` (not launch-blocking; future Wellbeing/data-integrity wave).
- **New REGRESSED-RISK**: `REQ-ARCH-001` (3 duplicate/orphaned state-authority stacks — dead today, real risk if ever reactivated by a future edit).
- **Governance corrections applied this session (2026-09-14, Post-Reconciliation Governance Correction wave)**:
  - `REQ-ONBOARD-001` (`AUTH-008`) — owner completed a fresh-install iOS E4 retest, **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`**, no longer `LIVE_VERIFICATION_REQUIRED`.
  - `REQ-ONBOARD-002` (`AUTH-009`) — same owner retest, **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`**.
  - `AUTH-007` (Arabic locale/RTL) — same owner retest confirms "Arabic onboarding remained Arabic," **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`** in the finding register (not previously a standalone ledger entry, referenced here for completeness).
  - `REQ-FIQH-002` — corrected from "no finding ID assigned" to its true canonical mapping, `AUTH-005`, which already tracked this exact requirement since 2026-09-11. No new finding was created; the duplication was caught and fixed.
