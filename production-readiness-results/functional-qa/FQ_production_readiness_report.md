# Functional QA — Production Readiness Report

**Verdict: 🟡 CONDITIONAL GO**

## Basis

No P0 (Critical) or P1 (High) functional defect was independently confirmed by this audit. `flutter test` executed cleanly against 262 tests with 254 passing (246 of them non-golden logic/widget tests, all passing), and the single most consequential prior-wave concern in this domain — a dead, differently-typed duplicate fiqh rule engine (CQ-003) — was independently confirmed to have **zero reachable call sites from any user-facing screen**, meaning users are not exposed to its weaker Maliki-school logic regardless of how CQ-003 itself is remediated.

This CONDITIONAL GO is issued subject to two explicit, unresolved conditions, matching the master finding register's `UNK-001`:

1. **`ROOT-001` / `UNK-001` (shared with Code Quality and API/Backend audits):** Whether `GeminiService`'s endpoint (`https://generativelanguage.googleapis.com/v1beta/interactions`) is a real, functioning Gemini API surface remains genuinely unknown — not verifiable without one live network call. This audit's contribution is narrowing, not closing, that question: it confirms that **if** the endpoint is broken, all three AI features (AI Advisor, Dream Interpreter, Dr. Niswah's fallback path) fail *visibly* (a shown error state) rather than silently or deceptively — but a visibly-failing core feature is still a failing core feature. Per this template's own severity model (§3), a confirmed-broken AI Advisor/Dream Interpreter/Dr.-Niswah-fallback would be classified **P1 — "a primary user journey fails"** for each, which is a mandatory pre-launch blocker. **This audit cannot issue an unconditional GO while that possibility remains open.**
2. **`FQ-000`:** 8 of 262 tests failed, all golden/pixel-diff visual-parity comparisons (Community, Dashboard, Profile, Today-lower, cycle-log-sheet — both English and Arabic/RTL variants for most). The failure pattern (small, consistent 1–7% pixel deltas across otherwise-unrelated screens) is consistent with font-rendering/environment variance rather than a real UI regression, but this audit did not visually inspect the diff images in `test/failures` to confirm that explanation. **Do not assume PASS from an untested hypothesis** — a maintainer or follow-up pass must open these diffs before this condition can close.

## What Was and Was Not Tested

- **Tested (controlled validation):** Full `flutter test` suite execution (real, on this machine) — 262 tests, 254 pass.
- **Tested (code-path tracing, Static/Documentation tier):** Fiqh-engine reachability, AI-failure UI behavior for all three AI surfaces, `kDebugSkipSignup` value, startup error-handling scope.
- **NOT tested:** Any live device/emulator manual UI walkthrough (none was available in this environment); live Supabase/Gemini network behavior; localization completeness beyond a spot check; full boundary-value verification of all four madhhabs' fiqh rules against `haidfigh.md` (spot-checked Hanafi/Shafi'i boundary constants only, via the Code Quality audit's CQ-002 evidence — not independently re-derived here).

## Conditions for closing this CONDITIONAL GO

| Condition ID | Requirement | Owner | Verification |
|---|---|---|---|
| `FQ-COND-01` | Confirm or refute the Gemini endpoint's validity with one live authenticated smoke-test call (shared condition with Code Quality `CQ-COND` and API/Backend `AB-COND`) | Release owner / backend engineer | One successful (or diagnostically-failed) live call against each of the three call sites |
| `FQ-COND-02` | Visually inspect `test/failures/*.png` vs. `test/goldens/*.png` for the 8 failing parity tests; confirm environment-variance or fix a real regression | QA / release owner | Diff review; regenerate goldens on canonical build environment if confirmed environment-only |

## Remediation Plan — **PROPOSED, NOT IMPLEMENTED**

No code was modified during this audit. Recommended (not executed):

- **R1 (supports FQ-COND-01):** Once ROOT-001 is resolved, if the endpoint is confirmed broken, fix `GeminiService`'s endpoint/request/response contract to match the real Gemini API (cross-reference Code Quality and API/Backend remediation plans for the same root cause — do not remediate independently in three places).
- **R2 (FQ-001):** Add a friendly, localized error-message mapping layer for known Gemini/network failure classes in `DreamInterpreterViewModel` and `ChatViewModel`'s direct-model path, matching the pattern already correctly used in `AiAdvisorService.askFiqh()`.
- **R3 (FQ-002):** Cross-reference Reliability audit's parallel finding — do not fix in Functional QA scope alone; requires an app-wide decision on error visibility/telemetry (crash reporting, structured logging), not a one-file patch.
- **R4 (FQ-000):** Visually triage the 8 golden-test failures; regenerate goldens or fix the regression as appropriate.

## Master Cross-Reference

This verdict is consistent with the Code Quality audit's own CONDITIONAL GO, issued for the same unresolved ROOT-001 condition — the two audits corroborate rather than conflict (master §20 cross-audit conflict resolution is not triggered here, since both reach the same conclusion from independent evidence).
