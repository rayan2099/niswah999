# Fiqh Engine Accuracy & AI User-State Context — Discovery Report

**Charter:** `production-readiness/MDs/FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md`
**Date:** 2026-09-09
**Release candidate:** commit `23d319570adc62f1b439b660a4db9e65ac403ca2` (local HEAD == origin/main at start of this audit)
**Environment:** static code review (Dart source, Edge Function source, SQL schema) — no live Gemini calls made this pass (see Scope Limitations below).

---

## 1. Fiqh-Sensitive Implementation Surface Inventory

| Area | File(s) | Role |
|---|---|---|
| **Production fiqh rule engine** | `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart` | Applies per-madhhab min/max haid duration + minimum purity boundaries to a bleeding episode; produces `FiqhCycleState` (`insufficientHistory`, `tahara`, `haid`, `needsAdvisory`). The single authoritative classification function. |
| **Production state composition** | `lib/features/cycle_tracking/domain/services/cycle_status_engine.dart` | Finds the current bleeding episode's start/purity-before from raw logs, calls `MadhhabRuleEvaluator`, produces the `CycleStatusSnapshot` the dashboard renders. |
| **Statistical cycle timing** | `lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart` | Average cycle/period length, `hasSufficientHistory`, current cycle day estimate — predictions, not fiqh rulings. |
| **Dead/legacy engine (NOT production-reachable)** | `lib/core/services/fiqh_calculation_engine.dart` | A second, older, differently-shaped fiqh calculator (`FiqhCalculationEngine`). Confirmed via `grep -rn "FiqhCalculationEngine" lib/ test/` — imported only by its own test file, never by any production `lib/` code path. See FIQH-1 below. |
| **Fiqh/Doctor's Report insights** | `lib/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart` | Recomputes current fiqh state independently (own copy of the episode-boundary scan) for the Fiqh Report PDF; also surfaces nifas phase via `PregnancyStatusEngine` and recent notes via `CycleSymptomDecoder`. |
| **Fiqh Report PDF** | `lib/features/fiqh_report/presentation/pdf/fiqh_report_pdf_builder.dart` | Renders `FiqhReportInsights` to PDF. |
| **Madhhab selection/persistence** | `lib/core/preferences/madhhab_controller.dart` | `ChangeNotifier` singleton, `SharedPreferences`-backed, default `Madhhab.hanbali`. Confirmed wired into `Listenable.merge([...])` on the dashboard (`dashboard_screen.dart:228`) — madhhab changes trigger a live rebuild/recompute, not a stale cache. |
| **Nifas/pregnancy fiqh state** | `lib/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart` (referenced) | Separate state machine from menstrual `FiqhCycleState` — postpartum/pregnancy mode is derived independently and takes priority in the Fiqh Report. |
| **Doctor's Report** | `lib/features/doctor_report/domain/services/doctor_report_insights_engine.dart` | Confirmed via `grep` to have **zero** reference to `MadhhabRuleEvaluator`/`FiqhCycleState`/`CycleStatusEngine` — this report is medically-scoped, not fiqh-scoped, and is correctly out of this audit's fiqh-engine scope (though still in the AI-context audit's scope where it feeds Dr Niswah/other AI, addressed separately below). |
| **Prayer tracking** | `lib/features/prayer_tracking/**` | Fully independent feature. Confirmed via `grep -rln "FiqhCycleState\|CycleStatusEngine\|haid" lib/features/prayer_tracking/` → **zero matches**. No automatic fiqh-state awareness anywhere in prayer tracking. See FIQH-4 below. Cross-references the already-registered `W0-003` finding (a distinct, already-known `PrayerStatus` enum/DB-constraint value mismatch — see `00_04_MASTER_FINDING_REGISTER.md`), but is a separate observation. |
| **DB schema** | `supabase/canonical_baseline/00_public_baseline_draft.sql` | `cycle_entries.fiqh_state` (`HAID`/`TAHARA`/`NIFAS`/`ISTIHADAH`, default `'TAHARA'`), `prayer_log.fiqh_state_at_time` (free text, nullable). Confirmed via exhaustive `grep -rn "fiqh_state" lib/ supabase/functions/` → **never written or read by any application or Edge Function code**. See FIQH-3 below. |
| **Tests** | `test/services/multi_madhhab_engine_test.dart`, `test/services/cycle_status_engine_test.dart`, `test/services/fiqh_report_insights_engine_test.dart`, `test/calculation_engine_test.dart` (dead-code tests), `test/fiqh_report_pdf_builder_test.dart` | Real, substantive boundary-test coverage exists for the production engine (see §4 below) — the dead `FiqhCalculationEngine` also has its own, separately-passing test file, which is part of why it wasn't obviously dead at a glance. |

## 2. AI Feature Inventory (Phase 1 requirement)

Four Gemini-backed AI features exist, each a dedicated Supabase Edge Function, each already server-side-only (client never holds a Gemini key — verified in the SEC-001/ROOT-002 waves earlier in this engagement, re-confirmed here by direct re-read).

| AI feature | Edge Function | Client call site | Data queried server-side | Data sent by client | Structured or prompt-derived context? |
|---|---|---|---|---|---|
| **Dr Niswah** (pregnancy companion, "طبيبة" persona) | `dr-niswah-chat` | `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart` | `pregnancy_profile` row for the authenticated user only (`tracking_basis`, `reference_date`, `manual_week_value`, `is_postpartum`, `postpartum_start_date`, `high_risk_flags`, `fasting_status`, `locale`) | `threadId`, `content` (current message only) | Structured: a `[CONTEXT]` block is built server-side (`buildContextBlock`) and injected into the system instruction — but its **only** source is `pregnancy_profile`. |
| **General Assistant** ("Niswah AI") | `ai-assistant-chat` | `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` | **Nothing** — only `auth.getUser()` for identity/rate-limiting | `content` (current message only) | None. Zero context of any kind. |
| **Fiqh Advisor** | `fiqh-advisor-chat` | `lib/features/ai_advisor/ai_advisor_service.dart` | **Nothing** beyond identity | `question`, `madhhab` (read live from `MadhhabController.instance.selected` at call time — confirmed fresh, not cached) | Minimal: only `madhhab` as a labeled parameter. No deterministic fiqh-engine output (current classification, rule IDs, uncertainty state) is ever sent. |
| **Dream Interpreter** | `dream-interpreter-chat` | `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart` | **Nothing** beyond identity | `prompt` (full resent conversation transcript — Gemini's endpoint has no server-side history) | None. |

**No shared context-assembly layer exists anywhere in the codebase.** Confirmed by exhaustive search: no `context_version`, no structured user-state object/class, no shared "AI context builder" module in either `lib/` or `supabase/functions/`. Each of the 4 functions independently decides (or, in 3 of 4 cases, does not decide) what to query. This is the root cause behind essentially every `AICTX` finding below.

## 3. Confirmed-Absent Context Domains (cross-checked against the charter's required list)

| Required domain (charter) | Exists as real, structured app data? | Read by ANY AI feature? |
|---|---|---|
| Pregnancy status/stage | Yes — `pregnancy_profile` table, `PregnancyStatusEngine` | Only `dr-niswah-chat` |
| Current menstrual/fiqh classification | Yes — `MadhhabRuleEvaluator`/`CycleStatusEngine` (computed, not persisted) | **No AI feature** |
| Selected madhhab | Yes — `MadhhabController` | Only `fiqh-advisor-chat` (as a raw label, not tied to computed state) |
| Cycle/bleeding history | Yes — `cycle_entries` | **No AI feature** |
| Symptoms | Yes — `cycle_entries` fields decoded by `CycleSymptomDecoder` | **No AI feature** |
| Wellbeing/mood/energy/sleep | Yes — real `wellbeing_logs` table (1-5 scales), full `lib/features/wellbeing/` feature with its own repository/insights engine | **No AI feature** (confirmed via `grep -rn "wellbeing" supabase/functions/` → zero matches) |
| User-authored notes (`الملاحظات`) | Yes — free-text `notes` column on `cycle_entries`, already retrieved for the Fiqh Report via `CycleSymptomDecoder.recentNotes()` | **No AI feature** |
| Prayer-related state | Prayer tracking exists as a fully separate feature with zero fiqh-state linkage (see §1 above) | N/A — not fiqh-aware even outside AI |
| Safety/red-flag state | `dr-niswah-chat` computes this itself, per-message, from keyword matching — real-time, not persisted/shared | Computed independently inside `dr-niswah-chat` only; not available to the other 3 AI features even though a red flag detected in one thread has no bearing on another |

## 4. Existing Boundary-Test Coverage (relevant to Phase 3)

`test/services/multi_madhhab_engine_test.dart` already provides genuine, table-driven boundary coverage for the production engine (`MadhhabRuleEvaluator`) — confirmed by direct read, not assumed:

- Hanafi: rejects 71h59m, accepts exactly 72h, accepts exactly 240h, rejects 240h1m — exact min/max ± one unit on both ends.
- Shafi'i and Hanbali (looped over both): rejects 23h59m, accepts exactly 24h, accepts exactly 15 days, rejects 15 days + 1 minute.
- Maliki: rejects 23h59m, accepts exactly 24h, accepts exactly 15 days, rejects 15 days + 1 minute — plus a dedicated test for personal-habit (`'adah`) tracking.
- A dedicated test for Hanafi's 15-day minimum-purity-before-haid boundary (one minute below vs. exactly at).
- A dedicated test confirming madhhab switching changes validation without mutating raw logs (directly matches the charter's own invariant).

This is real, substantive engineering-correctness evidence for the boundary values **as implemented** — it says nothing about whether those boundary values are themselves the religiously correct ones for each madhhab (that is exactly the source-governance gap in FIQH-2, and the reason this audit cannot certify "100% religious accuracy" — see the Scholar Review Gate section of the findings document).

## 5. Scope Limitations (recorded per master framework §24, not silently treated as complete coverage)

- **No live Gemini calls were made this pass.** All AI-guardrail findings are based on static system-prompt review (Master Evidence Hierarchy tier 3: "Exact code/config/schema evidence"), not live adversarial-prompt testing (tier 1: "Controlled runtime execution"). A system prompt instructing the model not to invent rulings is strong evidence of intent and design, not a runtime guarantee against every possible model output — LLM outputs are not perfectly deterministic even with the strongest prompt. This should be revisited with real, budgeted test calls in a future wave if the owner wants that additional evidence tier.
- **No qualified Islamic scholar reviewed any rule, boundary value, or golden-dataset case.** Every `expected_classification` value in this audit's golden dataset (see `golden_fiqh_dataset.json`) is an **engineering-derived** value — literally "what the current code computes for these inputs" — never a claim of religious correctness. See the Scholar Review Gate in the findings document.
- **Two-of-two "duplicated logic" claims (FIQH-5) were verified by manual code comparison, not by a fuzz/property test proving equivalence across all inputs.** The two implementations were read side-by-side and found structurally identical for the cases inspected; a property test proving they always agree was not written this pass.
