# Code Quality Audit — Phase 1: Discovery

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | Discovery |
| Audit date | 2026-09-04 |
| Previous report | none |
| Audit method | Read-only static inspection + `flutter analyze` execution |
| Environment | Local (macOS, Flutter 3.47.0 / Dart 3.13.0, both confirmed installed via `flutter --version`) |
| Restrictions | No build/run of the app; no `flutter test` execution requested in scope beyond static analyze (see CQ_static_analysis.md for what was actually run); no dependency resolution/upgrade performed |
| Report created | CQ_discovery.md |

---

## 7. Repository Structure Map

| Path | Purpose | Criticality | Ownership clarity | Notes |
|---|---|---|---|---|
| `lib/core/` | Cross-cutting: config, auth, network, models, services, theming, localization, preferences, error types, shared widgets | Critical | Clear | Contains `AppEnvironment` (config), `GeminiService`, repositories for cycle logs/user profile |
| `lib/features/*` (18 features) | Feature-first modules, each with `data/domain/presentation` sublayers | Critical | Mostly clear | Depth of layering varies — some features (`dashboard`, `education`, `insights`, `settings`) have presentation-only, no data/domain split |
| `test/` (50 files) | Unit + widget + "parity" tests | High | Clear | 242 `test`/`testWidgets` blocks, 632 `expect` calls, 0 `skip:` — see CQ_static_analysis.md and findings for quality caveats |
| `supabase/functions/dr-niswah-chat` | Single Edge Function (TypeScript) — server-side Gemini proxy for the Dr. Niswah persona | Critical | Clear | Only one Edge Function exists; all other AI features call Gemini directly from the client (see CQ-004) |
| `supabase/migrations/*.sql` | Postgres/Supabase schema | Critical | Not deeply audited (out of scope — Database Integrity audit) | Referenced only for cross-checking repository code, not reviewed exhaustively |
| `src/` (React/Vite) | **Design reference only** per user instruction — not audited as production code | N/A | N/A | Confirmed to still use `firebase` npm package (`src/firebase.ts`) — this explains the orphaned Firebase artifacts at repo root (see CQ-001) |
| `firestore.rules`, `firebase-blueprint.json`, `firebase-applet-config.json` (repo root) | Legacy/parallel Firestore data-model artifacts | None (confirmed unused by Flutter app) | Unclear — blurs the src/ vs lib/ boundary | See finding CQ-001 |
| `haidfigh.md` (repo root) | Draft fiqh (Islamic jurisprudence) rule spec, explicitly marked "Pending Human Scholar Review" | High (governs religious-ruling logic) | Unclear whether it is the sanctioned source of truth for shipped code | See finding CQ-002 |
| `.env` / `.env.example` | Runtime config | Critical | Clear; `.env` is correctly gitignored (`.env*` with `!.env.example` exception) and not tracked in git history (`git log --all -- .env` returns nothing) | `.env` is also declared as a Flutter **asset** (`pubspec.yaml` → `flutter: assets: - .env`), meaning it ships **inside the compiled app bundle** and is extractable from the APK/IPA — cross-reference Security Audit |
| `production-readiness/` | Audit templates | N/A | N/A | Source of this audit's methodology |
| No `.github/` or other CI config found | — | — | — | No CI pipeline exists in-repo; lint/test/build are not automated. Flagged as a tooling gap. |

Monorepo-ish layout: one Flutter app (`lib/`) is the release candidate, one legacy/reference React app (`src/`) coexists at the same repo root, plus a Supabase backend (`supabase/`). This is not a formal monorepo (no workspace tooling ties them together) — the two frontends are independent, and `src/` is explicitly reference-only per project convention.

---

## 8. Tech Stack and Toolchain Inventory

| Category | Technology | Version | Evidence | Actually used? | Confidence |
|---|---|---|---|---|---|
| Language | Dart | ^3.13.0 (SDK constraint), 3.13.0 installed | `pubspec.yaml:22`, `flutter --version` | YES | 🟥 |
| Framework | Flutter | 3.47.0 installed | `flutter --version` | YES | 🟥 |
| Backend | Supabase | `supabase_flutter: ^2.8.1` | `pubspec.yaml:41` | YES | 🟥 |
| Package manager | `pub` (via Flutter) | — | `pubspec.lock` present | YES | 🟥 |
| Linter/Static analyzer | `flutter_lints` ^6.0.0 via `analysis_options.yaml` | — | `analysis_options.yaml`, executed | YES | 🟥 |
| Formatter | `dart format` (not explicitly configured/run) | — | Not invoked (would modify files; out of audit scope) | UNKNOWN | 🟦 |
| Type checker | Dart's built-in static type system (sound null safety) | — | `flutter analyze` | YES | 🟥 |
| Test framework | `flutter_test` (unit/widget) | SDK-bundled | `pubspec.yaml:51`, `test/*.dart` | YES | 🟥 (tests exist; not executed in this audit — see restrictions) |
| Coverage tool | None configured | — | No `coverage` package, no CI coverage step found | NO | 🟥 |
| Static analyzer (extra) | None beyond `flutter analyze`/`flutter_lints` | — | No `dart_code_metrics`, no custom analyzer packages in `pubspec.yaml` | NO | 🟥 |
| Code generator | None (`build_runner`, `freezed`, `json_serializable` etc. absent from `pubspec.yaml`) | — | All models hand-written `fromJson`/`toJson` | NO | 🟥 |
| CI/CD | None found | — | No `.github/workflows`, no `.gitlab-ci.yml`, no `bitrise.yml`, etc. | NO | 🟥 |
| AI SDK | None — raw `http` calls to Gemini REST endpoint | `http: ^1.2.2` | `lib/core/services/gemini_service.dart` | YES | 🟥 |
| Env/config loader | `flutter_dotenv` ^5.2.1 | — | `AppEnvironment.load()` | YES | 🟥 |
| PDF generation | `pdf` ^3.13.0, `printing` ^5.15.0 | — | 4 report-builder classes | YES | 🟥 |
| Notifications | `flutter_local_notifications` ^22.3.0, `timezone` ^0.11.1 | — | `lib/features/notifications` | YES | 🟥 |
| Prayer-time calc | `adhan_dart` ^2.0.1 | — | `lib/features/prayer_tracking` | YES | 🟥 |

**Firebase is not a dependency anywhere in the Flutter app.** `grep -rli firebase lib/` → zero hits; `grep firebase pubspec.yaml pubspec.lock` → zero hits. Confirms the root-level Firestore artifacts are orphaned relative to `lib/` (see CQ-001).

---

## 9. Architectural Map

Pattern: **Feature-first / layered (data → domain → presentation)**, applied with varying rigor per feature.

Simplified dependency direction observed:

```
Presentation (screens, viewmodels/ChangeNotifier) 
    → Domain (entities, repository interfaces, domain services/engines)
        → Data (repository impls, Supabase datasources)
            → core/network (SupabaseClient wrapper) → Supabase backend
```

- **State management**: Plain `ChangeNotifier`-based ViewModels (no Riverpod/Bloc/Provider package dependency — `provider`/`riverpod` are absent from `pubspec.yaml`). ViewModels are constructed directly by screens or via small locator functions (e.g. `privateMessagingRepository` getter, `MadhhabController.instance`), i.e. **service-locator / singleton pattern**, not formal DI.
- **Data access layer**: Feature-scoped repositories wrapping `SupabaseClient` (e.g. `CycleLogRepository`, `UserProfileRepository`, `PregnancyTrackingRepositoryImpl`). Direct `.from('table').select()...` calls live inside repository classes, not scattered through UI — this boundary is respected in the modules reviewed.
- **AI integration layer** (see CQ-004 for full detail): two parallel paths —
  1. `DrNiswahBackendService` → Supabase Edge Function `dr-niswah-chat` (server-side Gemini key, server-side persona/red-flag logic) — used only for the "Dr. Niswah" medical-advisor thread type.
  2. `GeminiService` (client-side, calls Gemini REST API directly using a `GEMINI_API_KEY` read from the bundled `.env`) — used for the "Fiqh advisor" (`AiAdvisorService`), general assistant threads, the dream interpreter, and as a **fallback** for Dr. Niswah when the Supabase backend is unavailable.
- **Fiqh/religious-rule logic** (see CQ-002, CQ-003): Two independent implementations exist for the same domain concept (four-madhhab menstrual-cycle rule classification): `FiqhCalculationEngine` (dead — not imported by any production file) and `MadhhabRuleEvaluator` (live — imported by `cycle_status_engine.dart` and `fiqh_report_insights_engine.dart`). They use two different enums (`MadhhabType` vs `Madhhab`) for the same four schools.
- **Config**: `AppEnvironment` (typed, fail-fast loader with `_require`) is the intended single source of truth for env config, but is **not actually used** for AI keys — `GeminiService` bypasses it entirely via direct `dotenv.env[...]` access (see CQ-005).
- **PDF/report generation**: 4 independent builder classes (`DoctorReportPdfBuilder`, `HusbandReportPdfBuilder`, `FiqhReportPdfBuilder`, `WellbeingReportPdfBuilder`), each ~500–630 lines, each redeclaring its own copy of the brand color palette and (per visual inspection) similar section-building helpers, with no shared PDF theme/style module (see CQ-006).

No circular-dependency or illegal-layer-import violations were found in the modules sampled (presentation does not directly import `supabase_flutter` internals in the repositories reviewed; screens go through repository/viewmodel classes).

---

## 10. Module Inventory (selected — critical modules)

| Module ID | Module | Responsibility | Criticality | Cohesion | Notes |
|---|---|---|---|---|---|
| MOD-001 | `lib/core/config/app_environment.dart` | Typed env loading/validation | Critical | Medium | Declares 3 getters (`openAiApiKey`, `niswahAiApiKey`, `dreamInterpreterApiKey`) that are dead code — see CQ-005 |
| MOD-002 | `lib/core/services/gemini_service.dart` | Direct client-side Gemini REST calls | Critical | High | Bypasses `AppEnvironment`; API key shipped in app bundle via `.env` asset — see CQ-004 |
| MOD-003 | `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart` | Server-proxied AI calls via Supabase Edge Function | Critical | High | Well-documented, correct security posture (key stays server-side) |
| MOD-004 | `lib/core/services/fiqh_calculation_engine.dart` | Menstrual-cycle Madhhab rule engine (four schools) | High (religious-ruling logic) — but **unreachable** | Medium | Confirmed dead code with unused fields and a dead null-check flagged by the analyzer itself — see CQ-002/CQ-003 |
| MOD-005 | `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart` | Live Madhhab rule engine actually wired into cycle tracking and the fiqh report | High | High | This is the actual source of truth for religious-ruling boundaries |
| MOD-006 | `lib/features/private_messaging/private_messaging_locator.dart` + `mock_private_messaging_repository.dart` | Resolves messaging repository; falls back to an in-memory, hardcoded-demo-data repository when no Supabase user is signed in | Medium | Medium | Intentional "demo mode" per code comments, but reachable in production when auth state is absent/lost, not just in a deliberately-entered demo flow — see CQ-007 |
| MOD-007 | `lib/features/dashboard/presentation/screens/dashboard_screen.dart` | Main dashboard screen | Critical | Low (3,213 lines, single file) | Oversized — see CQ-008 |
| MOD-008 | `lib/features/auth/presentation/screens/profile_screen.dart` | Profile screen | High | Low (2,021 lines) | Oversized — see CQ-008 |
| MOD-009 | `lib/core/services/cycle_log_repository.dart`, `user_profile_repository.dart` | Supabase repositories for cycle logs / user profile | Critical | High | Use `print()` for error visibility instead of a logging framework — see CQ-009 |

---

## 11. Source of Truth Inventory

| Concept | Current source(s) | Expected source | Duplicated? | Drift risk | Finding |
|---|---|---|---|---|---|
| Madhhab (Islamic school) enum | `lib/core/models/madhhab_type.dart` (`MadhhabType`, used by dead `FiqhCalculationEngine`) **and** `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart` (`Madhhab`, live) | One enum | YES | HIGH | CQ-003 |
| Madhhab rule boundaries (min/max haid days, min purity) | `FiqhCalculationEngine` (dead) **and** `MadhhabRuleEvaluator` (live) **and** narrative spec in `haidfigh.md` (draft, unreviewed) | `MadhhabRuleEvaluator` + a reviewed spec | YES | HIGH | CQ-002, CQ-003 |
| AI/LLM credentials | `AppEnvironment.openAiApiKey/niswahAiApiKey/dreamInterpreterApiKey` (dead, unused) **vs** `GeminiService` reading `dotenv.env['GEMINI_API_KEY']` directly (live) | `AppEnvironment` | YES (structurally; only one path is live) | MEDIUM (confusing scaffolding, not a runtime risk since dead getters are simply never called) | CQ-005 |
| Supabase config | `AppEnvironment.supabaseUrl` / `supabaseAnonKey` | `AppEnvironment` | NO | LOW | — |
| Firestore data model (root JSON/rules files) | `firestore.rules`, `firebase-blueprint.json`, `firebase-applet-config.json` at repo root — **not used by any Supabase or Flutter code** | Should not exist alongside a Supabase-only production app, or should be clearly labeled/archived | Effectively orphaned duplicate of "the data model," inconsistent with actual Postgres/Supabase schema | MEDIUM (confusion/onboarding risk for engineers and auditors) | CQ-001 |
| PDF report branding/style constants | Redeclared independently in 4 files (`DoctorReportPdfBuilder`, `HusbandReportPdfBuilder`, `FiqhReportPdfBuilder`, `WellbeingReportPdfBuilder`) | One shared PDF theme module | YES | MEDIUM | CQ-006 |

---

## 12. Error-Handling Architecture (summary)

- No centralized logger/error-reporting framework in `lib/` (no `logging`/`logger` package; zero `dart:developer` imports).
- 14 `print(...)` call sites — all confined to `lib/core/services/cycle_log_repository.dart` and `lib/core/services/user_profile_repository.dart` — flagged by the analyzer itself (`avoid_print`, 14 info-level hits).
- 14 files contain `} catch (e) {` broad-catch blocks; most convert to typed nulls/empty lists/rethrow with UI-level `errorMessage` surfacing (`chat_view_model.dart`) rather than swallowing silently — reviewed a representative sample (`cycle_log_repository.dart`, `chat_view_model.dart`) and found no bare `catch (_) {}` that discards a failure without any visible consequence; one intentional swallow exists (`chat_view_model.dart:316`, `catch (_) { /* comment explaining why */ }`) which is explicitly documented and low-risk (best-effort history persistence).
- `AppEnvironment` fails fast/loudly (throws `FormatException`) on missing Supabase config at startup — good practice — but this same fail-fast behavior is dead for the AI keys since those getters are never invoked (see CQ-005): had they been wired up, the missing `.env.example` entries would crash the app immediately.
- No user-facing generic "success" is returned after a caught failure in the flows reviewed (repositories return `null`/`[]`, not fabricated success payloads) — full detail in CQ_findings.md.

Full detail in `CQ_findings.md`.

---

## 13. Test Architecture Inventory

- 50 test files under `test/`; 242 `test`/`testWidgets` blocks; 632 `expect` calls; 0 `skip:` markers found via static grep.
- No mocking library dependency (`mocktail`, `mockito` absent from `pubspec.yaml`) — tests appear to construct real objects/in-memory fakes directly (consistent with `MockPrivateMessagingRepository` being a genuine hand-written in-memory fake, not a mocking-framework double).
- A large "parity_*" test family (11 files: `parity_calendar_test.dart`, `parity_community_test.dart`, `parity_cycle_log_sheet_test.dart`, `parity_dashboard_test.dart`, `parity_insights_test.dart`, `parity_interactions_test.dart`, `parity_profile_test.dart`, `parity_responsive_test.dart`, `parity_today_logic_test.dart`, `parity_today_lower_test.dart`, `parity_today_stepper_consistency_test.dart`) — consistent with the project's stated goal of the Flutter app achieving UI/behavior parity with the `src/` web reference. Not fully read line-by-line; sampled 2 files (23 and 35 lines) — small, targeted, not obviously trivial/placeholder.
- **`test/calculation_engine_test.dart`** contains substantial, well-written test coverage (multiple `group`/`test` blocks with real boundary-value assertions) for `FiqhCalculationEngine` — a class confirmed dead in production code. This test suite gives false confidence that this religious-rule logic is verified and shipped; it is not (see CQ-002/CQ-003).
- `flutter test` was **not** executed as part of this audit (out of the explicitly authorized command list: only `flutter analyze` was requested). Test pass/fail status is therefore **UNKNOWN / NOT VERIFIED** — see CQ_static_analysis.md restrictions.

---

## 14. Generated and AI-Authored Code Inventory

- No framework-generated code detected (no `build_runner`, no `.g.dart` files found in a spot check of `lib/`).
- Strong circumstantial evidence of AI-agent authorship across the codebase (consistent, verbose doc-comments explaining intent above nearly every non-trivial method; parallel/competing implementations of the same domain concept — see CQ-002/CQ-003; scaffolding config getters with no callers — see CQ-005).
- `haidfigh.md` reads as an AI-agent-authored specification document (structured Markdown matrix of fiqh rules) explicitly marked "Draft Implementation Spec (Pending Human Scholar Review)" — i.e., the project's own documentation acknowledges this domain logic has not received the human scholarly review it says it needs, yet a rule engine implementing comparable logic (`MadhhabRuleEvaluator`) is live in production. Cross-reference: Functional QA / Privacy-Compliance audits for the religious/medical-advice risk angle; this audit records only the code-quality angle (undocumented provenance — no code comment or commit links `MadhhabRuleEvaluator`'s constants back to `haidfigh.md` or to any reviewed source) — see CQ-002.
- `GeminiService` targets an endpoint (`https://generativelanguage.googleapis.com/v1beta/interactions`) and model names (`gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`) that do not match the Gemini REST API surface known as of this auditor's training cutoff (January 2026: the documented generation endpoint is `v1beta/models/{model}:generateContent`, not `v1beta/interactions`). Given the current system date (2026-09-04) is 8 months past that cutoff, this **cannot be confirmed as hallucinated** — Google may have shipped a new "interactions" API and new model names in that window. Marked **UNKNOWN / REQUIRES CONTROLLED VALIDATION** (a live smoke-test call against the real endpoint, or checking current Google AI documentation, would resolve this) — see CQ-010.

---

## 15. Discovery Execution Log

### Fully reviewed
- `pubspec.yaml`, `analysis_options.yaml`, `.env.example`
- `lib/core/config/app_environment.dart`
- `lib/core/services/gemini_service.dart`, `cycle_log_repository.dart`, `user_profile_repository.dart`, `fiqh_calculation_engine.dart`
- `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`
- `lib/features/ai_advisor/ai_advisor_service.dart`
- `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (lines 1–360+)
- `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart`
- `lib/features/private_messaging/private_messaging_locator.dart`, `mock_private_messaging_repository.dart`
- `lib/features/auth/presentation/screens/profile_screen.dart` (targeted excerpt), `lib/features/community/presentation/screens/community_board_screen.dart` (targeted excerpt)
- `haidfigh.md`, `.gitignore`, `firestore.rules`/`firebase-blueprint.json`/`firebase-applet-config.json` (existence/reference-check, not full content diff against Supabase schema)
- `production-readiness/MDs/ CODE_QUALITY_AUDIT_TEMPLATE_MASTER.md` (full template)

### Partially reviewed
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart`, `profile_screen.dart`, `cycle_tracking_screen.dart` — sized and grepped, not read end-to-end (3,213 / 2,021 / 1,769 lines respectively)
- The 4 PDF report builders — header constants and class list confirmed via grep; full body not diffed line-by-line for exact duplication percentage
- `test/` — directory listing, counts, and 3 representative files read in full or excerpt; the remaining ~47 files were not individually read

### Structurally scanned only
- All 154 `lib/*.dart` files via `find`/`grep` for: TODO/FIXME/HACK, `print(`, `catch (_) {}`, `catch (e) {}`, mock/stub/placeholder/dummy tokens, Firebase imports, AppEnvironment AI-key call sites
- `supabase/functions/dr-niswah-chat` — referenced only via its client-side caller (`DrNiswahBackendService`); the Edge Function's own TypeScript source was **not** opened (cross-reference API/Backend audit)
- `supabase/migrations/*.sql` — not opened (cross-reference Database Integrity audit)

### Could not inspect
- Actual runtime behavior of `GeminiService`'s endpoint/model names against the live Gemini API — no network egress performed during this audit; classified UNKNOWN (CQ-010)
- `flutter test` results — not executed (outside the explicit command authorization for this audit pass); test **existence** and **static content** were reviewed, but pass/fail/flake status is unverified
- `dart format --set-exit-if-changed` (formatter-consistency check) — not run; would be safe/read-only but was not in the authorized command list, noted as a gap rather than a finding

### Commands/actions performed

| Action | Purpose | Result |
|---|---|---|
| `flutter --version` | Confirm toolchain availability | Flutter 3.47.0 / Dart 3.13.0 present |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | Static analysis | Ran successfully, exit 0, 33 issues (0 errors) — see CQ_static_analysis.md |
| `grep -rli firebase lib/`, `grep firebase pubspec.yaml pubspec.lock` | Verify Flutter app has no Firebase dependency | Zero hits — confirmed |
| `grep -rn openAiApiKey\|niswahAiApiKey\|dreamInterpreterApiKey\|aiApiKeys lib/ test/` | Verify AppEnvironment AI-key getters are unused | Only self-references inside `app_environment.dart` itself — confirmed dead |
| `grep -rln FiqhCalculationEngine lib/ test/` | Verify reachability of the fiqh calculation engine | Only itself + `test/calculation_engine_test.dart` — confirmed dead in production |
| `git log --all -- .env`, `git ls-files \| grep '^\.env$'` | Verify `.env` was never committed | No history, not tracked — confirmed clean |
| `git log --oneline --all`, `wc -l` | Confirm commit history depth | 2 commits total, matches known project limitation |
| `find lib -name "*.dart" -exec wc -l {} \;` | Identify oversized files | `dashboard_screen.dart` (3,213), `profile_screen.dart` (2,021), `cycle_tracking_screen.dart` (1,769) lead |

### Actions deliberately avoided

| Action avoided | Reason |
|---|---|
| `flutter pub get` / dependency resolution or upgrade | Template restriction (no dependency upgrades during audit); also unnecessary since `pubspec.lock` already exists and `flutter analyze` ran without complaint |
| `dart format` in write mode, `flutter analyze --fix`, any auto-fix flags | Template restriction — read-only static verification only |
| `flutter test` (full suite execution) | Not part of the explicitly authorized command set for this task; recorded as an unknown rather than assumed |
| Reading `.env` contents | Would risk exposing/handling live secret material outside this audit's remit; existence and gitignore status were verified instead |
| Deleting/modifying `firestore.rules`, `haidfigh.md`, or any dead-code candidate | Auditor-only mandate — findings only, no remediation performed |

---

## 16. Discovery Exit Gate

- [x] Repository structure is mapped.
- [x] Toolchain is identified.
- [x] Architecture is understood well enough to review.
- [x] Critical modules are identified.
- [x] Main sources of truth are identified.
- [x] Error handling approach is understood.
- [x] Test architecture is inventoried.
- [x] Generated/AI-authored code risk areas are identified.
- [x] Unknown/unreviewed areas are explicitly listed.
- [x] No critical architectural ambiguity prevents further review.

**Phase 1 status: COMPLETE.**
