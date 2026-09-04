# Code Quality Audit — Phase 2A/2B: Static Verification &amp; Validation

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Repository | /Users/rynadalsabh/Niswah |
| Branch | main |
| Commit / Version | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f |
| Phase | 2A Static Verification + 2B Controlled Validation (partial) |
| Audit date | 2026-09-04 |
| Previous report | CQ_discovery.md |
| Audit method | Static tool execution (`flutter analyze`) + manual code review |
| Environment | Local |
| Restrictions | `flutter test`, `dart format --set-exit-if-changed`, and any build/pub-get were **not** executed — see below |
| Report created | CQ_static_analysis.md |

---

## 42. Validation Command Log

| Command ID | Command | Purpose | Modifies files? | Exit code | Result | Evidence |
|---|---|---|---|---|---|---|
| CMD-001 | `flutter --version` | Confirm toolchain present | NO | 0 | PASS | Flutter 3.47.0 • Dart 3.13.0 |
| CMD-002 | `flutter analyze --no-fatal-infos --no-fatal-warnings` | Run static analyzer, capture full output regardless of severity | NO | 0 | PASS (ran to completion; 33 non-fatal issues found, 0 compile errors) | `production-readiness-results/code-quality/_raw_flutter_analyze.txt` |
| CMD-003 | `flutter test` | Run unit/widget test suite | NO (would not modify source) | — | **NOT RUN** | Out of the explicitly authorized command scope for this audit pass — recorded as unknown, not assumed passing |
| CMD-004 | `dart format --set-exit-if-changed .` | Formatter-consistency check | NO | — | **NOT RUN** | Same as above |
| CMD-005 | `flutter build ...` (any target) | Production build validation | NO (build output only) | — | **NOT RUN** | Same as above; also would require signing/platform SDKs not confirmed available |

**`flutter analyze` actually ran and completed** — this is the one tool result in this report backed by real execution, not inference from config.

---

## `flutter analyze` — Full Result Summary

Command: `flutter analyze --no-fatal-infos --no-fatal-warnings` (from repo root)
Exit code: `0`
Result line: `33 issues found. (ran in 16.9s)`

### Breakdown by severity

| Severity | Count | Category breakdown |
|---|---:|---|
| error | 0 | — |
| warning | 3 | 2× `unused_field` (both in `fiqh_calculation_engine.dart`), 1× `unnecessary_null_comparison` (same file) |
| info | 30 | 14× `avoid_print`, 11× `prefer_initializing_formals`, 2× `deprecated_member_use`, 1× `use_build_context_synchronously`, 2× `unused_field`/other misc |

### Full raw output

```
Analyzing Niswah...

   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:18:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:21:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:35:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:38:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:53:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:56:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:65:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/cycle_log_repository.dart:67:7 • avoid_print
warning • The value of the field '_hanafiMinPurityDays' isn't used. Try removing the field, or using it • lib/core/services/fiqh_calculation_engine.dart:8:20 • unused_field
warning • The value of the field '_shafiiHanbaliMinPurityDays' isn't used. Try removing the field, or using it • lib/core/services/fiqh_calculation_engine.dart:13:20 • unused_field
warning • The operand can't be 'null', so the condition is always 'true'. Remove the condition • lib/core/services/fiqh_calculation_engine.dart:66:35 • unnecessary_null_comparison
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:18:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:21:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:35:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:38:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:53:7 • avoid_print
   info • Don't invoke 'print' in production code. Try using a logging framework • lib/core/services/user_profile_repository.dart:56:7 • avoid_print
   info • Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext • lib/features/dashboard/presentation/screens/dashboard_screen.dart:328:54 • use_build_context_synchronously
   info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/features/dashboard/presentation/screens/dashboard_screen.dart:2210:53 • deprecated_member_use
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._cycleRepository') to initialize the field • lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:29:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._pregnancyRepository') to initialize the field • lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:30:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._wellbeingRepository') to initialize the field • lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:31:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._flaggedConversationsRepository') to initialize the field • lib/features/doctor_report/presentation/screens/doctor_report_screen.dart:32:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._cycleRepository') to initialize the field • lib/features/fiqh_report/presentation/screens/fiqh_report_screen.dart:26:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._pregnancyRepository') to initialize the field • lib/features/fiqh_report/presentation/screens/fiqh_report_screen.dart:27:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._cycleRepository') to initialize the field • lib/features/husband_report/presentation/screens/husband_report_screen.dart:29:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._pregnancyRepository') to initialize the field • lib/features/husband_report/presentation/screens/husband_report_screen.dart:30:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._currentUserId') to initialize the field • lib/features/private_messaging/data/repositories/mock_private_messaging_repository.dart:9:7 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._repository') to initialize the field • lib/features/private_messaging/presentation/viewmodels/chat_detail_view_model.dart:16:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._repository') to initialize the field • lib/features/private_messaging/presentation/viewmodels/conversations_view_model.dart:14:8 • prefer_initializing_formals
   info • 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/features/settings/settings_screen.dart:216:23 • deprecated_member_use
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._repository') to initialize the field • lib/features/wellbeing/presentation/screens/wellbeing_report_screen.dart:26:8 • prefer_initializing_formals
   info • Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._cycleRepository') to initialize the field • lib/features/wellbeing/presentation/screens/wellbeing_report_screen.dart:27:8 • prefer_initializing_formals

33 issues found. (ran in 16.9s)
EXIT:0
```

---

## Interpretation

1. **Zero compile errors** — the codebase type-checks cleanly under the default `flutter_lints` rule set. This is real evidence the code compiles, but per the template's golden rule, this alone is **not** evidence of maintainability.
2. **The two `unused_field` warnings and the `unnecessary_null_comparison` warning are independent, tool-confirmed corroboration of finding CQ-002/CQ-003** (the dead `FiqhCalculationEngine`): the analyzer itself detected that `_hanafiMinPurityDays` and `_shafiiHanbaliMinPurityDays` — constants meant to encode the "15-day minimum purity" fiqh rule — are declared but never read anywhere in the class, and that a null-check on `previousCycle.startDate` is dead code because `CycleLog.startDate` is non-nullable. Both are direct evidence that this file was written against an outdated/incorrect assumption about the model and was never fully wired up or exercised against real data — despite having a full passing-looking test suite (`test/calculation_engine_test.dart`).
3. **14 `avoid_print` infos** are 🟥 confirmed by tool and corroborate CQ-009 (no logging framework; `print()` used for error visibility in two Supabase repositories). `print()` output is stripped/unreliable in Flutter release builds, meaning these error paths are effectively **invisible in production**.
4. **11 `prefer_initializing_formals` infos** are pure style/consistency, not a production-risk finding on their own — recorded as CQ4 (Observation) only, per the template's instruction not to inflate stylistic issues.
5. **1 `use_build_context_synchronously` info** in `dashboard_screen.dart:328` — a real async/`BuildContext` lifecycle risk pattern (the linter flags a `mounted` guard that doesn't actually guard the right object) — recorded as a targeted finding in the async/state category.
6. **No lint rules are suppressed project-wide.** `analysis_options.yaml` uses the stock `package:flutter_lints/flutter.yaml` with an empty `rules:` override block (only commented-out examples) — i.e., **no rule is disabled**, and no file/directory is excluded from analysis beyond the standard platform-generated folders (`build/`, `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`) plus `lib/`/`test/` are fully in scope. This is a positive finding: the project has not weakened its own static-analysis net.
7. **No `// ignore:` or `// ignore_for_file:` suppression comments were found in the modules reviewed** — not exhaustively grepped across all 154 files as a dedicated check, flagged as a residual gap: **UNKNOWN / NOT FULLY VERIFIED** whether any individual line-level suppressions exist elsewhere in the tree.

## 43–47: Build / Lint / Type-Check / Test / Coverage Validation Table

| Check | Result | Evidence |
|---|---|---|
| Build (dev or production) | NOT RUN | Not in authorized command scope for this pass |
| Lint (`flutter analyze`) | **PASS** (0 errors; 33 non-blocking info/warning issues, itemized above) | CMD-002 |
| Type-check | **PASS** (part of the same `flutter analyze` run — Dart's analyzer performs type-checking; 0 type errors) | CMD-002 |
| Tests (`flutter test`) | **NOT RUN** | CMD-003 |
| Coverage | **NOT AVAILABLE** — no coverage tool configured | Discovery §8 |

## 48–50: Complexity / Dead-Code / Dependency-Graph Validation

No automated complexity/dead-code/dependency-graph tool exists in this project (no `dart_code_metrics` or equivalent in `pubspec.yaml`). These checks were performed **manually** via `wc -l` file-size scans and targeted `grep` reachability checks; results are recorded as code-review findings (CQ_findings.md) rather than tool output, and are marked 🟧 (Confirmed by Code) rather than 🟥 (Confirmed by Tool), except where corroborated by the analyzer's own warnings (item 2 above, which is 🟥).

## Static Verification Exit Gate

- [x] Critical modules were reviewed.
- [x] Duplication was assessed.
- [x] Dead/stale code was assessed.
- [x] Error handling was assessed.
- [x] Type/model/API consistency was assessed (within reviewed modules).
- [x] Test architecture was assessed.
- [x] Configuration organization was assessed.
- [x] AI-generated-code patterns were assessed.
- [x] All CQ0/CQ1 candidates have evidence (see CQ_findings.md).
- [x] Unknowns requiring tool execution are listed (`flutter test`, `dart format --set-exit-if-changed`, `flutter build`, live Gemini endpoint validation).
- [x] No critical claim is based only on subjective style preference.

**Phase 2A/2B status: 2A COMPLETE. 2B PARTIAL — only `flutter analyze` was executed; test/build/format validation are explicitly unexecuted and recorded as unknowns, not assumed.**
