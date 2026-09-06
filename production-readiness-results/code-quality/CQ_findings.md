# Code Quality Audit — Findings Register

> **Status update (2026-09-06):** `CQ-007` (private messaging's demo-mode fabricated-conversation fallback) is **VERIFIED_CLOSED** as of the Final Application Code Blockers wave — see `production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md` and `00_09_PHASE1_ROOT_CAUSE_REMEDIATION_PLAN.md` §33 for full evidence. No other finding in this document has been remediated by any wave; this document remains the frozen original audit for every finding besides `CQ-007`.

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | 2A/2B combined finding register |
| Audit date | 2026-09-04 |
| Previous reports | CQ_discovery.md, CQ_static_analysis.md |
| Report created | CQ_findings.md |

Confidence key: 🟥 Confirmed by Tool/Execution · 🟧 Confirmed by Code · 🟨 Likely · 🟦 Requires Controlled Validation · ⬜ N/A / False Positive

---

## CQ-001 — Orphaned Firebase/Firestore artifacts at repo root, unrelated to the Supabase-only Flutter app

- **Category**: `DEAD-01` / `CONF-01`
- **Severity**: **CQ3 (Low)** — no runtime risk (confirmed unreferenced), but real maintainability/onboarding-confusion risk.
- **Location**: `firestore.rules`, `firebase-blueprint.json`, `firebase-applet-config.json` (repo root)
- **Evidence**: 🟥 `grep -rli firebase lib/` → zero hits. `grep firebase pubspec.yaml pubspec.lock` → zero hits. `pubspec.yaml` has no `firebase_core`/`cloud_firestore` dependency. Confirmed live usage instead in `src/` (the reference-only web app): `src/firebase.ts`, `src/contexts/CycleContext.tsx`, `src/api/index.ts`, and `package.json:34` (`"firebase": "^12.11.0"`). These three root files describe a Firestore data model that has no relationship to the actual Postgres/Supabase schema the Flutter app (`lib/`) uses.
- **Why it matters**: An engineer, auditor, or AI coding agent exploring "the data model" at repo root could reasonably treat `firestore.rules`/`firebase-blueprint.json` as authoritative and reason about permissions/schema incorrectly. It also blurs the stated boundary that `src/` is reference-only — these root-level files are *not* inside `src/`, so they read as project-wide artifacts even though they only pertain to the legacy web prototype.
- **Confidence**: 🟥 (tool-confirmed absence of any reference from `lib/`)
- **Launch blocker**: NO
- **Recommended remediation category**: Move these three files into `src/` (or a clearly labeled `legacy/`/`reference/` folder) or delete them if the web reference no longer needs them, with a one-line note in `MANIFEST.md`/README clarifying the Flutter app's data layer is Supabase/Postgres only.
- **Status**: OPEN

---

## CQ-002 — Live religious-ruling (fiqh) logic has no documented link to a reviewed source; the one file that *is* explicitly derived from a spec is marked unreviewed

- **Category**: `DOC-01` / `GEN-01`
- **Severity**: **CQ2 (Medium)** — bounded code-quality/provenance issue; the deeper "is it safe to ship unreviewed religious rulings" question is a Functional QA / Privacy-Compliance concern, cross-referenced below, not re-litigated here.
- **Location**: `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart` (live engine) vs. `haidfigh.md` (repo root, "Draft Implementation Spec (Pending Human Scholar Review)")
- **Evidence**: 🟧 `MadhhabRuleEvaluator.evaluate()` hardcodes duration boundaries (`Duration(hours: 72)`, `Duration(hours: 240)`, `Duration(days: 15)`, `Duration(hours: 24)`) that numerically match the boundaries described in `haidfigh.md` (Hanafi 3–10 days / 72–240 hours, Shafi'i/Hanbali 1–15 days with a 24-hour minimum, 15-day minimum purity across schools). No code comment, docstring, or commit message in `madhhab_rule_evaluator.dart` cites `haidfigh.md` or any other source for these magic-number thresholds. `haidfigh.md` itself states its status is "Pending Human Scholar Review" as of the file's content, yet the numerically-matching logic is already live in production cycle-tracking and fiqh-report code paths.
- **Why it matters**: From a pure code-quality lens, these are undocumented magic-number domain constants — a reviewer six months from now has no way to trace *why* `Duration(hours: 72)` is correct, or to know a review of the source spec is still pending, without independently discovering `haidfigh.md`. This is exactly the kind of untraceable domain-constant risk the template's Magic Values audit (§24) calls out, made materially worse because the domain is a religious ruling that governs when a user should/shouldn't pray or fast.
- **Cross-reference**: Functional QA / Privacy-Compliance audits should independently assess whether shipping this logic while its source spec is marked "pending scholar review" is acceptable for launch; this audit registers the code-quality angle only (missing traceability/documentation).
- **Confidence**: 🟨 (numeric match is strong circumstantial evidence of derivation; no explicit code-level citation was found to confirm it directly)
- **Launch blocker**: NO (code-quality angle only; escalate to Privacy/Functional QA for the substantive launch-blocking question)
- **Recommended remediation category**: Add a source-of-truth doc comment in `madhhab_rule_evaluator.dart` citing the reviewed spec/version it implements once `haidfigh.md` (or its replacement) receives sign-off; do not treat this file's absence of citation as proof the values are wrong — only that provenance is undocumented.
- **Status**: OPEN

---

## CQ-003 — Two competing, differently-typed implementations of the four-Madhhab fiqh rule engine; the dead one carries a full, convincing test suite

- **Category**: `DUP-01` / `GEN-02` / `TEST-01`
- **Severity**: **CQ1 (High)**
- **Location**: 
  - Dead: `lib/core/services/fiqh_calculation_engine.dart` (`FiqhCalculationEngine`, uses `MadhhabType` enum from `lib/core/models/madhhab_type.dart`)
  - Live: `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart` (`MadhhabRuleEvaluator`, uses a *separately declared* `Madhhab` enum defined in the same file)
- **Evidence**: 
  - 🟥 `flutter analyze` independently flags `fiqh_calculation_engine.dart` with 2 `unused_field` warnings (`_hanafiMinPurityDays`, `_shafiiHanbaliMinPurityDays`) and 1 `unnecessary_null_comparison` warning (a null-check on `CycleLog.startDate`, which is non-nullable) — direct tool evidence this file was never fully wired up or exercised against the real model.
  - 🟥 `grep -rln FiqhCalculationEngine lib/` returns only `lib/core/services/fiqh_calculation_engine.dart` itself — **zero** production call sites.
  - 🟥 `grep -rln MadhhabRuleEvaluator lib/ test/` returns `fiqh_report_insights_engine.dart`, `cycle_status_engine.dart` (both production) plus its own file and `multi_madhhab_engine_test.dart` — confirmed live and reachable.
  - 🟧 `test/calculation_engine_test.dart` contains a full, well-constructed test suite (multiple `group`/`test` blocks, real boundary-value assertions per school) exercising the **dead** `FiqhCalculationEngine`, passing (presumably — not executed in this audit, see restrictions) and giving the false impression that this is verified, shipped logic.
  - The two rule sets are not identical: `FiqhCalculationEngine.isValidMenses` treats Maliki as "1–15 days, simplified" with an explicit code comment admitting "a more robust implementation would involve detailed habit tracking," while `MadhhabRuleEvaluator` implements Maliki via an explicit `personalHabit`/`isWithinPersonalHabit` comparison — i.e. the dead file's Maliki logic is a materially weaker approximation than the live file's.
- **Why it matters**: This is a textbook AI-agent "competing implementations" pattern (template §37.1/§37.2): two agents (or two passes) independently built the same domain concept under two different enum names, one abandoned in place with its test suite left green and misleading. In a religious-ruling domain, a future engineer or reviewer who finds `FiqhCalculationEngine` + its passing tests could reasonably (and incorrectly) conclude it is the shipped logic, or accidentally wire it back in during a refactor, silently changing which rule set users are governed by (notably, weaker Maliki handling).
- **Confidence**: 🟥/🟧 combined (tool-confirmed dead fields + code-confirmed zero reachability)
- **Launch blocker**: Recorded as **YES (pre-launch blocker per template severity rules for CQ1 "dangerously ... duplicated ... misleading" code)**, unless the release owner explicitly accepts the residual risk that dead code with a passing test suite remains in the tree. Removing/quarantining it is a pure code-quality cleanup with no user-facing behavior change (it is unreachable), so the remediation is low-risk to execute before launch.
- **Recommended remediation category**: Delete `lib/core/services/fiqh_calculation_engine.dart` and `lib/core/models/madhhab_type.dart` (if nothing else uses `MadhhabType`) along with `test/calculation_engine_test.dart`, or explicitly move them to an `archive/`/`experimental/` location outside `lib/`/`test/` with a comment explaining why they're retained. Do not delete blindly — first confirm (as this audit did) that zero other call sites exist.
- **Status**: OPEN

---

## CQ-004 — Inconsistent AI-key security posture: server-proxied path for Dr. Niswah vs. client-embedded Gemini key for Fiqh/General/Dream-Interpreter, with the client path also used as Dr. Niswah's fallback

- **Category**: `ARCH-01` / `CONF-02`
- **Severity**: **CQ2 (Medium)** for code-quality/architecture-consistency purposes; **escalate to Security Audit** for the credential-exposure severity determination.
- **Location**: `lib/core/services/gemini_service.dart`, `lib/features/ai_advisor/ai_advisor_service.dart`, `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (`_sendViaDirectModel`, lines ~271–336) vs. `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart` + `supabase/functions/dr-niswah-chat`
- **Evidence**: 
  - 🟧 `GeminiService._apiKey` reads `dotenv.env['GEMINI_API_KEY']` directly, client-side (`gemini_service.dart:43-49`), and `pubspec.yaml:73` declares `.env` as a bundled Flutter **asset**, meaning `GEMINI_API_KEY` ships inside the compiled app binary, extractable by anyone who unpacks the APK/IPA.
  - 🟧 `DrNiswahBackendService` instead calls the Supabase Edge Function `dr-niswah-chat` (`dr_niswah_backend_service.dart:1-46`), which — per its own doc comment — "owns the persona system prompt, the pregnancy-context lookup, the red-flag check, and the Gemini call server-side," i.e. the key never reaches the client for this one path.
  - 🟧 `chat_view_model.dart:194-219` shows the app **intentionally** uses the server path for Dr. Niswah when available, and falls back to the direct-client `GeminiService` path (a) always for fiqh/general threads, and (b) for Dr. Niswah itself when the Supabase backend isn't configured (`_sendViaDirectModel` doc comment, line 271-272).
- **Why it matters**: This is a deliberate, documented architectural layering (not accidental duplication) — a genuine positive for the Dr. Niswah path. But it means the app ships with **two different trust models for the same underlying LLM credential** depending on which feature a user opens, and the weaker model (client-embedded key) is reachable by a large fraction of the app's AI surface (fiqh advisor, general assistant, dream interpreter) plus as Dr. Niswah's own fallback. From a code-quality/consistency standpoint this is an unresolved architectural inconsistency; from a security standpoint (out of this audit's scope to fully rule) it means the `GEMINI_API_KEY` should be treated as effectively public once shipped.
- **Confidence**: 🟧
- **Launch blocker**: Recorded as code-quality **NO** on its own (the layering is intentional/documented, not a defect); flagged for mandatory Security Audit cross-reference, which may independently classify it as a blocker.
- **Recommended remediation category**: Either route all AI calls through server-side Edge Functions (highest-security option) or, if client-side Gemini access is an accepted product tradeoff, apply platform-level key restrictions (Google Cloud API key restrictions by bundle ID/package name and rate limits) and document the accepted-risk decision in one place instead of leaving it implicit in code comments split across 4 files.
- **Status**: OPEN

---

## CQ-005 — `AppEnvironment` declares three fail-fast AI-key getters (`openAiApiKey`, `niswahAiApiKey`, `dreamInterpreterApiKey`) that are never called anywhere; live AI calls bypass `AppEnvironment` entirely

- **Category**: `DEAD-02` / `CONF-03`
- **Severity**: **CQ3 (Low)** — confirmed dead, no runtime crash risk since the getters are never invoked, but it is real scaffolding debt that misrepresents the app's actual config surface.
- **Location**: `lib/core/config/app_environment.dart:62-74` (`openAiApiKey`, `niswahAiApiKey`, `dreamInterpreterApiKey`, `aiApiKeys`)
- **Evidence**: 
  - 🟥 `grep -rn "openAiApiKey|niswahAiApiKey|dreamInterpreterApiKey|aiApiKeys" lib/ test/` returns matches only inside `app_environment.dart` itself — zero external callers.
  - 🟧 The env vars these getters read (`OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, `DREAM_INTERPRETER_API_KEY`) are absent from `.env.example`, which only documents `APP_ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (plus `VITE_*` aliases).
  - 🟧 Confirmed the actual live AI calls (`GeminiService`) read `GEMINI_API_KEY` via `dotenv.env[...]` directly, never through `AppEnvironment` (CQ-004 evidence).
  - Each getter calls `_require(...)`, which **throws `FormatException`** if the value is empty — meaning if any code path ever did call `AppEnvironment.openAiApiKey` etc. today, it would crash immediately, since none of these three vars exist in any shipped `.env`.
- **Why it matters**: This is a classic AI-agent scaffolding-left-behind smell (template §37.2 "false completeness" — code exists but is not connected to anything). It creates two risks: (1) a future engineer may see `AppEnvironment.aiApiKeys` and assume it's the sanctioned way to fetch AI credentials, wire it in, and immediately crash the app in every environment because the vars were never provisioned; (2) it inflates the perceived config-validation surface, making `AppEnvironment` look more complete/audited than it is.
- **Confidence**: 🟥 (tool-confirmed zero call sites via grep across all of `lib/`+`test/`)
- **Launch blocker**: NO
- **Recommended remediation category**: Delete the three dead getters and the `aiApiKeys` map, or — if AI keys are meant to eventually route through `AppEnvironment` — wire `GeminiService` to use them and add the corresponding vars to `.env.example`, resolving CQ-004's inconsistency at the same time.
- **Status**: OPEN

---

## CQ-006 — Duplicated PDF report styling/branding across 4 independent builder classes

- **Category**: `DUP-02`
- **Severity**: **CQ3 (Low)**
- **Location**: `lib/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart`, `husband_report/presentation/pdf/husband_report_pdf_builder.dart`, `fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart`, `wellbeing/presentation/pdf/wellbeing_report_pdf_builder.dart` (514–631 lines each)
- **Evidence**: 🟧 `doctor_report_pdf_builder.dart:21-30` independently declares `_brandPrimary = '#BE123C'`, `_textPrimary`, `_textSecondary`, `_textTertiary`, `_emeraldInk`, `_cardBg`, `_lightTint`, `_gridLine`, `_haid`, `_tahara` as private static constants. No shared `lib/core/.../pdf_theme.dart` or similar module was found (`find lib -ipath "*pdf*" -iname "*util*" -o ... "*shared*" -o ... "*common*"` returned nothing).
- **Why it matters**: Four ~500-line classes independently redeclaring the same brand palette is a drift risk — a rebrand or color-accessibility fix requires editing (and keeping in sync) 4 files instead of 1. Not confirmed byte-for-byte identical across all 4 (not fully diffed), but the constant names and at least the sampled values match the pattern the template calls out in §18 (repeated constants) and §34 (under-abstraction / repeated integration wrappers).
- **Confidence**: 🟨 (constant-name/value match confirmed in one file; full 4-way diff not performed)
- **Launch blocker**: NO
- **Recommended remediation category**: Extract a shared `ReportPdfTheme` (or similar) module used by all 4 builders.
- **Status**: OPEN

---

## CQ-007 — Private messaging silently falls back to fabricated, hardcoded "demo" conversations in production when no Supabase session exists

- **Category**: `CONF-04` (mock/placeholder in production path, template §36/§37.2)
- **Severity**: **CQ2 (Medium)** — intentional and documented, but reachable outside a deliberately-entered "try the demo" flow.
- **Location**: `lib/features/private_messaging/private_messaging_locator.dart`, `lib/features/private_messaging/data/repositories/mock_private_messaging_repository.dart`, call sites in `lib/features/auth/presentation/screens/profile_screen.dart:417-424` and `lib/features/community/presentation/screens/community_board_screen.dart:97-104`
- **Evidence**: 🟧 `privateMessagingRepository` getter (`private_messaging_locator.dart:19-24`) resolution order is: (1) test override, (2) `PrivateMessagingRepository` **only if** `NiswahSupabase.clientOrNull != null`, (3) otherwise `MockPrivateMessagingRepository()`. The mock (`mock_private_messaging_repository.dart:20-123`) seeds three fabricated conversations with named fake contacts ("Umm Sara", "Huda", "Maryam") and realistic-sounding chat content (health/religious topics), served with artificial network-like delays (`Future.delayed`). Both `profile_screen.dart` and `community_board_screen.dart` also branch to this mock directly whenever `currentUser`/`_currentUserId` is null, with a code comment explicitly framing this as "Demo mode: no signed-in user — explore messaging with mock data."
- **Why it matters**: The condition gating this fallback — "no Supabase user is currently signed in" — is true both when a user deliberately explores the app pre-login **and** whenever an authenticated session unexpectedly becomes null (token expiry, network blip during Supabase init, an auth bug elsewhere). In the latter case, a signed-in user could be shown fabricated private conversations from named fake people with no error indicator distinguishing "this is a demo" from "your session dropped and this is fake data." This is precisely the "hardcoded success response masking a real failure" pattern the template flags in §30 and §36 as high-priority when reachable in production, tempered here because the intent is documented and it is a deliberate product decision for unauthenticated browsing, not an accidental leftover.
- **Confidence**: 🟧
- **Launch blocker**: NO on its own, but flagged for explicit release-owner acceptance — recommend either a visible "Demo Mode" banner whenever `MockPrivateMessagingRepository` is active, or restricting the mock path to a deliberate "Try without an account" entry point rather than any null-auth-state fallback.
- **Recommended remediation category**: Add a UI-visible demo-mode indicator; distinguish "user chose to browse unauthenticated" from "an authenticated session unexpectedly dropped" (the latter should show an error/re-auth prompt, not fake data).
- **Status**: OPEN

---

## CQ-008 — Oversized screen files reduce testability and reviewability of critical UI

- **Category**: `SIZE-01`
- **Severity**: **CQ3 (Low)** — bounded to maintainability, no confirmed functional defect.
- **Location**: `lib/features/dashboard/presentation/screens/dashboard_screen.dart` (3,213 lines), `lib/features/auth/presentation/screens/profile_screen.dart` (2,021 lines), `lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart` (1,769 lines), `lib/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart` (1,231 lines), `lib/features/auth/presentation/screens/sign_in_screen.dart` (1,130 lines)
- **Evidence**: 🟥 `find lib -name "*.dart" -exec wc -l {} \;` sorted — top 5 files listed above are all single-file Flutter screens exceeding 1,000 lines, with `dashboard_screen.dart` at over 3x that.
- **Why it matters**: Files of this size in a widget-tree-heavy UI framework typically mix multiple widget-building responsibilities, state, and business logic in one file, making them hard to unit test in isolation and increasing merge-conflict/regression risk for any change. `dashboard_screen.dart` is also the file where the one `use_build_context_synchronously` analyzer info was found (line 328) and one `deprecated_member_use` (`withOpacity`, line 2210) — consistent with a large, harder-to-fully-review file accumulating minor issues.
- **Confidence**: 🟥 (line counts are objective; the "reduces testability" conclusion is 🟨 inference, not separately measured via a complexity tool since none is configured)
- **Launch blocker**: NO
- **Recommended remediation category**: Decompose into smaller widget files per logical section; not urgent pre-launch.
- **Status**: OPEN

---

## CQ-009 — No logging framework; error visibility relies on `print()` in 2 core Supabase repositories, invisible in release builds

- **Category**: `ERR-01`
- **Severity**: **CQ2 (Medium)**
- **Location**: `lib/core/services/cycle_log_repository.dart` (8 call sites: lines 18, 21, 35, 38, 53, 56, 65, 67), `lib/core/services/user_profile_repository.dart` (6 call sites: lines 18, 21, 35, 38, 53, 56)
- **Evidence**: 🟥 `flutter analyze` flags all 14 as `avoid_print` info-level lints. 🟧 Each is inside a `catch (PostgrestException e) { print(...); return null/[]; }` / `catch (e) { print(...); return null/[]; }` pattern — every read/write/update/delete method in both repositories swallows the underlying Supabase error down to a `print()` call and a null/empty return, with no logging framework, no error-reporting/crash-analytics hook, and no propagation to the caller beyond an empty result.
- **Why it matters**: `print()` statements are frequently stripped or rate-limited in Flutter release builds and are not visible in any production log aggregation system by default. Combined with the fact that callers only see `null`/`[]` (indistinguishable from "no data" vs. "the request failed"), a real Supabase outage, RLS misconfiguration, or network failure on cycle-log or profile read/write would be **silently invisible** in production telemetry while presenting to the user as "you have no cycle logs" — a data-integrity-adjacent UX risk for a health-tracking app. No project-wide logging package is present (§8 confirmed `logger`/`logging` absent from `pubspec.yaml`; zero `dart:developer` imports across `lib/`).
- **Confidence**: 🟥 (tool + code combined)
- **Launch blocker**: Recorded as a **release-owner-acceptance item**, not an automatic NO-GO — the pattern doesn't corrupt data or return false success, but it does mean operational visibility into these two critical repositories' failure modes is effectively zero post-launch (cross-reference Observability audit).
- **Recommended remediation category**: Introduce a minimal structured logger (even `dart:developer log()` with a severity level, or a lightweight package) and route these 14 catch blocks through it; consider surfacing a distinguishable error state to callers instead of collapsing failure into the same shape as "empty."
- **Status**: OPEN

---

## CQ-010 — `GeminiService` targets an endpoint/model-name set not matching any documented Gemini REST API surface as of this auditor's knowledge cutoff

- **Category**: `GEN-03`
- **Severity**: **CQ2 (Medium)** — potentially CQ0/CQ1 if the endpoint is genuinely wrong (every AI feature using this path would be fully broken), but cannot be resolved without live validation.
- **Location**: `lib/core/services/gemini_service.dart:38-39` (`_endpoint = 'https://generativelanguage.googleapis.com/v1beta/interactions'`), lines 64-66 (`models = ['gemini-3.6-flash', 'gemini-3.5-flash', 'gemini-3.5-flash-lite']`)
- **Evidence**: 🟧 As of this auditor's training data (through January 2026), the documented Gemini generation endpoint pattern is `v1beta/models/{model}:generateContent` (or `:streamGenerateContent`), not `v1beta/interactions`; and the `gemini-3.x` model family name was not present in training data. However, the system date for this audit is 2026-09-04 — **8 months past that cutoff** — so Google may plausibly have shipped a new "Interactions"-style API and new model generations in that window. This cannot be distinguished from a genuine hallucinated/copied-from-a-different-API-version pattern (template §37.3) without a live network call or current documentation check, neither of which this read-only audit performed.
- **Why it matters**: If this endpoint/model set is wrong, then every client-side AI path (fiqh advisor, general assistant, dream interpreter, and Dr. Niswah's fallback) is fully non-functional in production — the response-parsing code (`_modelOutputBlocks`, expecting `json['steps']`/`json['outputs']` with `type == 'model_output'`) is also a schema shape not matching the documented `generateContent` response shape (`candidates[].content.parts[]`) as of this auditor's knowledge, which is additional circumstantial evidence this may be a hallucinated/invented API contract rather than a real one Google shipped later — but this remains **unconfirmed**.
- **Confidence**: 🟦 **Requires Controlled Validation** — this is the single most important open unknown in this audit; a one-line authenticated smoke-test call against the real endpoint would resolve it definitively.
- **Launch blocker**: **YES, pending validation** — if the endpoint is confirmed non-functional, this becomes a CQ0/CQ1 (multiple production AI features fully broken); if confirmed functional (a real newer Google API), this finding downgrades to N/A. Do not launch without resolving this specific unknown.
- **Recommended remediation category**: Execute one authenticated request against the live endpoint in a controlled/staging environment (or check current Gemini API documentation) before sign-off; cross-reference to the API/Backend audit and Functional QA audit, both of which should independently attempt to exercise this path.
- **Status**: OPEN

---

## CQ-011 — `use_build_context_synchronously` risk in `dashboard_screen.dart`

- **Category**: `ASYNC-01`
- **Severity**: **CQ3 (Low)**
- **Location**: `lib/features/dashboard/presentation/screens/dashboard_screen.dart:328`
- **Evidence**: 🟥 `flutter analyze`: "Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check."
- **Why it matters**: Potential for a "Looking up a deactivated widget's ancestor is unsafe" runtime exception or silently-wrong navigation/UI update if the check that's actually present doesn't guard the `BuildContext` being used. Single occurrence, analyzer-flagged, not independently traced end-to-end in this audit.
- **Confidence**: 🟥
- **Launch blocker**: NO
- **Recommended remediation category**: Fix the `mounted` guard to check the correct object per the linter's suggestion.
- **Status**: OPEN

---

## CQ-012 (Observation) — 11× `prefer_initializing_formals` info-level lints; no CI/CD pipeline; no coverage tooling; formatter consistency unverified

- **Category**: `NAME-01` / `BUILD-01`
- **Severity**: **CQ4 (Observation)**
- **Location**: Various (see CQ_static_analysis.md raw output); repo root (no `.github/workflows` or equivalent found)
- **Evidence**: 🟥 (lint output) + 🟧 (`find .github -type f` empty; no coverage package in `pubspec.yaml`)
- **Why it matters**: None of these block launch on their own, but together they mean: (a) style consistency isn't automatically enforced on every change (no CI gate running `flutter analyze`/`dart format --set-exit-if-changed`/`flutter test` on PRs — none exists to check), and (b) there is no automated signal if a future change reintroduces the `FiqhCalculationEngine`-style dead code or drops test coverage on critical modules.
- **Confidence**: 🟥/🟧
- **Launch blocker**: NO
- **Recommended remediation category**: Post-launch backlog — add a CI workflow running `flutter analyze` + `flutter test` + `dart format --set-exit-if-changed` on every PR.
- **Status**: OPEN

---

## Findings Summary Table

| Finding ID | Category | Severity | Launch blocker? | Status |
|---|---|---|---|---|
| CQ-001 | DEAD/CONF | CQ3 | NO | OPEN |
| CQ-002 | DOC/GEN | CQ2 | NO (escalate to QA/Privacy) | OPEN |
| CQ-003 | DUP/GEN/TEST | **CQ1** | **YES** (removal is low-risk/low-effort) | OPEN |
| CQ-004 | ARCH/CONF | CQ2 | NO (escalate to Security) | OPEN |
| CQ-005 | DEAD/CONF | CQ3 | NO | OPEN |
| CQ-006 | DUP | CQ3 | NO | OPEN |
| CQ-007 | CONF | CQ2 | NO (recommend acceptance decision) | OPEN |
| CQ-008 | SIZE | CQ3 | NO | OPEN |
| CQ-009 | ERR | CQ2 | NO (recommend acceptance decision) | OPEN |
| CQ-010 | GEN | CQ2 (conditionally CQ0/CQ1) | **YES, pending validation** | OPEN |
| CQ-011 | ASYNC | CQ3 | NO | OPEN |
| CQ-012 | NAME/BUILD | CQ4 | NO | OPEN |

**Open counts**: CQ0: 0 · CQ1: 1 (CQ-003) · CQ2: 5 (CQ-002, CQ-004, CQ-007, CQ-009, CQ-010) · CQ3: 5 · CQ4: 1

Note: CQ-010 is the one finding whose true severity is **unresolved** pending controlled validation — treat it as the audit's single most important open unknown.
