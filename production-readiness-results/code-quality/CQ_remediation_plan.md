# Code Quality Audit — Phase 3: Remediation Plan

> ⚠️ **This remediation plan is PROPOSED and NOT IMPLEMENTED.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until code changes are completed and validation (re-run of `flutter analyze`, relevant tests, and manual verification) is completed.

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | 3 — Remediation Design (design only) |
| Audit date | 2026-09-04 |
| Previous report | CQ_findings.md |
| Report created | CQ_remediation_plan.md |

---

## 55. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| CQ-003 | Dead fiqh rule engine + passing tests coexist with the live one | Two separate implementation passes (likely two different agent sessions/dates) built the same domain concept under different enum names; the old one was never removed after the new one replaced it | 🟧 | CQ-002 (undocumented provenance of the live one's constants) | R1 |
| CQ-005 | Dead `AppEnvironment` AI-key getters | Scaffolding written ahead of/in parallel with the actual `GeminiService` implementation, then abandoned when `GeminiService` was built to read `dotenv` directly instead | 🟥 | CQ-004 (the two AI paths never got unified onto one config source) | R1 |
| CQ-004 | Inconsistent AI-key trust model across features | The Dr. Niswah path was hardened (moved server-side) after presumably being built the same way as the others; the hardening was not retroactively applied to fiqh/general/dream-interpreter | 🟧 | CQ-005, CQ-010 | R2 |
| CQ-001 | Orphaned Firebase artifacts at repo root | Legacy/parallel prototype (the `src/` web app) once used Firebase; migration to Supabase for the Flutter app happened without archiving or removing the old data-model artifacts from the repo root | 🟥 | — | R1 |
| CQ-009 | Silent, production-invisible error logging in 2 repositories | No logging framework was ever introduced project-wide; `print()` was the fastest way to get *some* visibility during development and was never revisited | 🟥 | CQ-012 (no CI gate would have caught this drifting) | R1 |
| CQ-007 | Fabricated demo data reachable outside a deliberate demo entry point | The "explore without an account" UX requirement was implemented by keying off `currentUser == null` rather than off an explicit user choice/state | 🟧 | — | R2 |
| CQ-006 | Duplicated PDF branding constants across 4 files | Each of the 4 report types was built independently (or by 4 separate agent passes) without factoring out a shared theme module first | 🟨 | — | R3 |
| CQ-008 | Oversized screen files | Feature screens grew incrementally without a decomposition pass | 🟨 | — | R3 (backlog, not pre-launch) |
| CQ-010 | Unverifiable Gemini API surface | Cannot determine root cause without controlled validation — either a real newer API this auditor's training predates, or a hallucinated/copied-from-elsewhere API contract | 🟦 | CQ-004 | **R0 — validate before anything else** |
| CQ-011 | `use_build_context_synchronously` in dashboard_screen.dart | Localized async/lifecycle oversight, consistent with the file's size (CQ-008) making full review harder | 🟨 | CQ-008 | R3 |
| CQ-012 | No CI gate | No pipeline was ever set up in this 2-commit-history repo | 🟥 | — | R3 |

---

## 56. Remediation Principles Applied

| Principle | Application here |
|---|---|
| Single source of truth | Remove the dead `FiqhCalculationEngine`/`MadhhabType` pair (CQ-003); consolidate AI-key config onto one path (CQ-004/CQ-005) |
| Fail visibly | Replace silent `print()`-and-return-empty pattern with a real logger and a distinguishable error signal (CQ-009) |
| Prefer deletion over parallel legacy paths | CQ-001, CQ-003, CQ-005 are all "delete or clearly archive the dead thing" |
| Behavior before abstraction | CQ-006 (PDF theme extraction) is deliberately sequenced *after* the higher-risk items, since it's pure refactor with no behavior-risk urgency |
| Test before refactor | R1 items must be preceded by confirming (as this audit already did via grep) zero remaining call sites before deletion |
| Small reversible changes | Each R1 item is proposed as an independent, revertible commit — do not bundle CQ-001/CQ-003/CQ-005/CQ-009 into one large "cleanup" PR |
| Retest every critical path | R0/R1 items affecting the AI/fiqh/messaging paths require re-running `flutter analyze`, the relevant existing test files, and a manual smoke pass of the affected screens |

---

## 57. Remediation Phase Table

### R0 — Must resolve before any GO decision (validation, not code change)

| # | Action | Findings closed | Files/modules | Contract impact | Data impact | Test impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| R0.1 | Execute one authenticated smoke-test call against `GeminiService`'s live endpoint (`https://generativelanguage.googleapis.com/v1beta/interactions`) in a controlled/staging environment, or confirm against current Google AI documentation, to determine whether the endpoint/model names/response schema are real and correct | CQ-010 | `lib/core/services/gemini_service.dart` | None (read-only validation) | None | Manual smoke test of fiqh advisor, general assistant, dream interpreter, and Dr. Niswah-without-backend fallback | N/A — this is validation, not a code change | N/A | Re-open CQ-010 as CQ0/CQ1 if the call fails; close as N/A if confirmed correct |

### R1 — Pre-launch blockers / high-value low-risk deletions

| # | Action | Findings closed | Files/modules | Contract impact | Data impact | Test impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| R1.1 | Delete (or move to an explicitly labeled `archive/` location outside `lib/`+`test/`) `lib/core/services/fiqh_calculation_engine.dart`, `test/calculation_engine_test.dart`, and `lib/core/models/madhhab_type.dart` **after re-confirming zero remaining call sites** | CQ-003 | 3 files | None — confirmed zero production callers | None | Removes 1 test file (18+ tests) that exercised only dead code; no live-behavior test coverage lost | Low — this audit already confirmed unreachability via grep; re-verify at implementation time in case new code was added since this audit | Revert the deletion commit | `flutter analyze` (expect the 2 `unused_field` + 1 `unnecessary_null_comparison` warnings to disappear); full remaining test suite still green |
| R1.2 | Remove the orphaned root-level Firestore artifacts (`firestore.rules`, `firebase-blueprint.json`, `firebase-applet-config.json`) or relocate into `src/`/a labeled legacy folder, with a one-line note added to `MANIFEST.md` | CQ-001 | 3 root files, `MANIFEST.md` | None | None | None | Low | Revert / restore files | None required beyond confirming `src/` (if that's where they're moved) still builds if it has any build step referencing repo-root paths |
| R1.3 | Delete the 3 dead `AppEnvironment` getters (`openAiApiKey`, `niswahAiApiKey`, `dreamInterpreterApiKey`) and the `aiApiKeys` map **after re-confirming zero call sites**; alternatively, wire `GeminiService` through them and add the corresponding vars to `.env.example` — pick one, do not leave the current half-state | CQ-005 (and partially CQ-004) | `lib/core/config/app_environment.dart`, possibly `lib/core/services/gemini_service.dart`, `.env.example` | If choosing to wire `GeminiService` through `AppEnvironment`: changes how the API key is sourced — must re-verify `.env`/deployment secrets provisioning | None | Re-run any test that constructs/mocks `AppEnvironment` | Low if deleting; Medium if rewiring (touches a live AI code path) | Revert commit | `flutter analyze`; manual smoke test of whichever AI feature(s) were touched if rewiring |
| R1.4 | Introduce a minimal structured logger and route the 14 `print()` call sites in `cycle_log_repository.dart` and `user_profile_repository.dart` through it; consider returning a distinguishable failure signal (e.g. a `Result`/exception) instead of collapsing every failure into `null`/`[]` | CQ-009 | `lib/core/services/cycle_log_repository.dart`, `lib/core/services/user_profile_repository.dart`, new logging utility | Changing return types from `null`/`[]`-on-failure to a `Result`-style type is a **breaking contract change** for every caller of these two repositories — recommend splitting into two commits: (a) low-risk logging swap only (same return contract, pre-launch-safe), (b) higher-risk return-type change (post-launch, requires updating every call site + Functional QA re-test) | None | Every caller of these repositories should be smoke-tested if (b) is done | (a) Low / (b) Medium-High | Revert commit | `flutter analyze`; manual smoke test of cycle logging and profile screens; Functional QA re-test if (b) is done |

### R2 — Should resolve before launch, requires explicit release-owner acceptance if deferred

| # | Action | Findings closed | Files/modules | Contract impact | Data impact | Test impact | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|---|
| R2.1 | Decide and document the accepted security posture for client-side Gemini calls (fiqh/general/dream-interpreter/Dr.-Niswah-fallback): either move them server-side via Edge Functions (mirroring `dr-niswah-chat`), or apply Google Cloud API key restrictions + document the accepted risk in one place (e.g. `SECURITY.md` or a comment block in `gemini_service.dart`) | CQ-004 | `lib/core/services/gemini_service.dart`, potentially new `supabase/functions/*` | If moved server-side: significant — new Edge Functions, client call-site changes across 3+ features | None | Full re-test of fiqh advisor, general assistant, dream interpreter | Medium (documentation-only) to High (if moving server-side) | N/A (design decision, not yet code) | Security Audit sign-off; Functional QA re-test of affected features if code changes |
| R2.2 | Add a source-of-truth doc comment in `madhhab_rule_evaluator.dart` citing the reviewed spec/version it implements, once `haidfigh.md` (or its successor) receives the scholarly review it says it's pending | CQ-002 | `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart`, `haidfigh.md` | None (comment-only) | None | None | Low | Revert comment | None |
| R2.3 | Add a visible "Demo Mode" UI indicator whenever `MockPrivateMessagingRepository` is active, and/or distinguish "user chose to browse unauthenticated" from "an authenticated session unexpectedly dropped" (the latter should surface an error/re-auth prompt, not fake conversations) | CQ-007 | `private_messaging_locator.dart`, `profile_screen.dart`, `community_board_screen.dart`, relevant messaging screens | UI-visible change; low logic-contract impact | None | Add/update a widget test asserting the demo banner appears when the mock repo is active | Low-Medium | Revert commit | Manual smoke test of the private-messaging entry points in both auth states |

### R3 — Backlog, non-blocking

| # | Action | Findings closed | Files/modules | Risk | Retest |
|---|---|---|---|---|---|
| R3.1 | Extract a shared `ReportPdfTheme` module used by all 4 PDF report builders | CQ-006 | 4 PDF builder files + new shared module | Low-Medium (visual regression risk in generated PDFs) | Re-run the 4 existing PDF builder tests (`doctor_report_pdf_builder_test.dart`, etc.) + visual spot-check of generated PDFs |
| R3.2 | Decompose `dashboard_screen.dart`, `profile_screen.dart`, `cycle_tracking_screen.dart` into smaller widget files | CQ-008 (partially CQ-011, since decomposition would force re-review of the async `BuildContext` usage) | 3 large screens | Medium (large mechanical refactor, regression-prone if rushed) | Full widget-test suite + manual UI smoke test per decomposed screen |
| R3.3 | Fix the `mounted`/`BuildContext` guard flagged by `use_build_context_synchronously` at `dashboard_screen.dart:328` | CQ-011 | `dashboard_screen.dart` | Low | `flutter analyze` (issue should disappear); manual test of the affected async flow |
| R3.4 | Add a CI workflow (GitHub Actions or equivalent) running `flutter analyze`, `flutter test`, and `dart format --set-exit-if-changed` on every PR | CQ-012 | new `.github/workflows/*.yml` | None to app code | N/A | Confirm the workflow runs green on the current `main` branch |

---

## 58. Refactor Safety Requirements Checklist (applies to all R1/R2/R3 items before implementation)

- [ ] Existing behavior is understood (this audit documents current behavior for each finding above).
- [ ] Relevant tests exist or are added first — note R1.1 removes tests for dead code only; R1.4(b) and R2.1/R2.3 require new/updated tests before the behavior change ships.
- [ ] Interfaces/contracts are documented — flagged explicitly where a contract changes (R1.4(b), R2.1).
- [ ] Data migrations are separated from code refactors — N/A, no data migrations proposed here.
- [ ] Rollback strategy exists — each item above has a stated rollback (git revert of a small, isolated commit); this is why items are proposed as separate commits, not one bundle.
- [ ] Feature flags are considered if necessary — recommended for R2.1 if moving AI calls server-side incrementally (flag per feature to cut over one at a time).
- [ ] Deployment ordering is documented — R2.1 (if server-side) requires the Edge Function to be deployed and verified *before* the client cutover ships.
- [ ] Cross-client compatibility is considered — N/A (single Flutter client; `src/` is reference-only and not a live client).
- [ ] Generated-code regeneration path is understood — N/A, no code generation in this project.
- [ ] No unrelated cleanup is bundled into the same change — each R-item above is scoped to one finding.

---

## 59. Regression Requirements

Every item above must, upon implementation, progress `OPEN → IMPLEMENTED → VERIFIED CLOSED` only after:
1. The original finding ID is referenced in the commit/PR.
2. `flutter analyze` is re-run and the relevant warning/info disappears (where applicable: R1.1, R1.3, R3.3).
3. Any existing or newly-added test for the affected path passes.
4. For R1.4(b), R2.1, R2.3: a Functional QA re-test of the affected user-facing flow is performed and referenced.
5. For R2.1 specifically: Security Audit sign-off is obtained given the credential-exposure dimension.

No finding in this plan should be marked closed based on code being edited alone — per template §59, editing is not closure.
