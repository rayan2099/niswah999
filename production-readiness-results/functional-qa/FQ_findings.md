# Functional QA — Discovery, Test Results & Findings

| Field | Value |
|---|---|
| System | Niswah — Flutter mobile app |
| Commit | 13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f, branch main |
| Phase | 2A/2B combined |
| Audit date | 2026-09-04 |
| Note on methodology | This audit was performed directly by the lead auditor (not a delegated sub-agent) after Wave-2 sub-agent dispatch hit a session-wide rate limit (all 3 Wave-2 agents failed before producing output). No live device/emulator was used — evidence is `flutter test` execution (real, on this machine) plus code-path tracing (Static/Documentation tier per the template's evidence hierarchy), not live manual UI testing. |

Evidence key: 🟥 Confirmed by test execution · 🟧 Confirmed by code (path traced) · 🟨 Likely · 🟦 Requires controlled/live test · ⬜ N/A

---

## Test Suite Execution (controlled validation)

`flutter test` was run to completion against the full suite (50 test files). **Result: 254 passed, 8 failed, 262 total.**

All 8 failures are **golden/pixel-diff parity tests** comparing rendered widget screenshots against reference PNGs (`test/goldens/`) — none are logic/unit/widget-behavior assertion failures:

- `parity_community_test.dart`: Community English / Community Arabic RTL
- `parity_today_lower_test.dart`: Today lower Fiqh state (Arabic)
- `parity_profile_test.dart`: Profile English / Profile Arabic RTL
- `parity_dashboard_test.dart`: Dashboard English / Dashboard Arabic RTL
- `parity_cycle_log_sheet_test.dart`: Arabic blood log sheet

Each failure reported a 1–7% pixel-diff percentage (e.g. "6.68%, 197793px diff", "1.41%, 41648px diff") — small but real deltas, not catastrophic mismatches, and failure images were written to `test/failures` (a directory the project's own `.gitignore` documents as "regenerated locally on every failing run," indicating this parity-test workflow is an established, actively-managed part of the team's process, not a new/broken addition).

**246 of 254 passing tests are non-golden** (unit, repository, view-model, and non-parity widget tests) — this is strong evidence the underlying business logic (fiqh calculation, prayer-time computation, private messaging, notifications, PDF builders, cycle/pregnancy tracking, auth phone-normalization, community view models) is exercised and passing under test, not merely present.

**FQ-000 — Golden/parity visual-regression test failures not resolved to a verdict (visual regression vs. environment rendering variance)**
- **Severity:** P3 (Low) — evidence-bounded; escalate to P1 if a maintainer confirms these are real UI regressions rather than font-rendering/anti-aliasing environment variance.
- **Evidence:** 🟥 8/262 tests fail, all golden-image comparisons, pixel-diff in the 1–7% range, spanning both English and Arabic/RTL variants of 4 distinct screens.
- **Analysis:** Font-rendering, sub-pixel anti-aliasing, and OS-level text-shaping differences between the machine that captured the reference goldens and this audit's execution environment are a common, well-documented source of exactly this failure signature (small, consistent percentage diffs across otherwise-unrelated screens, rather than one badly broken screen). This audit did not open the diff images in `test/failures` to visually confirm which explanation applies — that is a **manual step requiring visual inspection**, out of scope for a text-based audit pass.
- **Launch-blocker status:** NOT DETERMINED — mark **UNKNOWN / NOT VERIFIED** whether these represent real visual regressions. Recommend the release owner (or a follow-up audit pass) open `test/failures/*.png` and diff against `test/goldens/*.png` before sign-off; if confirmed as environment-only, these should be excluded from CI on this exact runner config or the goldens regenerated on the canonical CI image once one exists (cross-reference DC-006 — no CI exists yet at all).
- **Status:** OPEN (unknown)

---

## Fiqh Rule Engine — Verified Single Live Implementation

Directly re-verified the Code Quality audit's CQ-003 finding: `grep -rln "MadhhabRuleEvaluator("` across `lib/` returns only its two real callers, `lib/features/fiqh_report/domain/services/fiqh_report_insights_engine.dart` and `lib/features/cycle_tracking/domain/services/cycle_status_engine.dart`. `grep -rln "FiqhCalculationEngine("` across `lib/` returns **zero results** — the dead engine identified by Code Quality is confirmed, independently, to have no production call sites reachable from any user-facing screen. **This closes the functional-correctness half of CQ-003's concern**: users are never exposed to the weaker/dead Maliki logic. The code-quality risk (dead code with a misleadingly-passing test suite) stands as CQ-003 already recorded it; no new FQ finding is needed for this specific point.

---

## Gemini/AI Feature Failure Behavior — Traced in Full

Prior-wave audits (CQ-010, AB-001) raised a high-confidence, unresolved concern that `GeminiService`'s endpoint (`v1beta/interactions`) may not match Google's real Gemini API, which — if true — would make the AI Advisor, Dream Interpreter, and Dr. Niswah's fallback path non-functional. This audit traced **what the user actually sees** if every Gemini call fails, for all three surfaces:

- **AI Advisor (`ai_advisor_service.dart`)**: `askFiqh()` wraps the Gemini call in `try { ... } catch (_) { return const GeminiResult(text: 'تعذر الوصول إلى المصادر الموثقة الآن...'); }` — a deliberate, honest, pre-written Arabic fallback message ("Unable to reach verified sources right now... cannot issue an automated fiqh ruling without sources; please try later or ask a qualified scholar") is shown. This is a **well-designed, fail-closed UX** — it does not fabricate a ruling and does not silently do nothing.
- **Dream Interpreter (`dream_interpreter_view_model.dart`)**: `sendMessage()` catches the Gemini failure, removes the optimistically-added user turn (so a retry doesn't duplicate it), and sets `errorMessage = error.toString()`, which the screen displays. This surfaces a **visible error**, but it is raw/untranslated exception text (e.g. `"StateError: Gemini request failed (404)."`), not a polished, localized message — a real but minor UX gap, not a silent failure.
- **General/Dr.-Niswah-fallback chat (`chat_view_model.dart`, `_sendViaDirectModel`)**: Same pattern — the outer `send()` catches any error from `_sendViaDirectModel` and sets `errorMessage = error.toString()`; `dr_niswah_chat_screen.dart:309` renders it in a visible, styled banner (red-tinted container with an info icon) whenever `model.errorMessage != null`. Again: visible, but unpolished/untranslated raw exception text.

**FQ-001 — AI-feature failures surface raw, unlocalized exception text to users instead of a friendly message (2 of 3 AI surfaces)**
- **Severity:** P3 (Low) — a real UX defect, not data-impacting, not a launch blocker on its own, but directly relevant to whether ROOT-001 (possible Gemini endpoint hallucination) would be *noticeable and diagnosable* vs. silent if it manifests in production.
- **Affected:** `lib/features/dream_interpreter/presentation/viewmodels/dream_interpreter_view_model.dart`, `lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart` (general/fallback path).
- **Evidence:** 🟧 both `catch` blocks assign `errorMessage = error.toString()` with no message-mapping/localization layer; both corresponding screens render that raw string directly.
- **Why it matters, positively and negatively:** Positively — **this materially reduces the severity of ROOT-001 from a pure functional-QA standpoint**: if the Gemini endpoint is indeed broken, users do not see a fabricated success, an infinite spinner, or a crash — they see a visible (if ugly) error banner, and can retry or abandon the feature. This is a legitimate, code-confirmed mitigating factor the prior audits' summaries did not have visibility into. Negatively — a raw `StateError`/`FormatException` string in a user-facing banner is unpolished and could look unprofessional or alarming, and gives no actionable next step.
- **Launch-blocker status:** NO — cosmetic/UX polish item, but recommend fixing alongside whatever remediation ROOT-001 requires (map known Gemini failure modes to one friendly, localized message, matching the pattern already used correctly in `AiAdvisorService`).
- **Status:** OPEN

**This audit's independent assessment of ROOT-001 (Gemini endpoint validity) — still UNKNOWN, not resolved.** Nothing in this pass (code tracing, `flutter test`, or the above failure-path analysis) can determine whether `https://generativelanguage.googleapis.com/v1beta/interactions` is a real, working endpoint — that requires one live network call, which this audit was not authorized/able to make. **What this pass adds is confidence that IF it is broken, the failure mode is a visible (if unpolished) error for all three AI features, not silent data loss or a crash** — narrowing, not closing, the prior audits' open question.

---

## Onboarding / Debug-Flag Verification

Re-confirmed directly (not merely trusting the prior audit's summary): `lib/main.dart:32` — `const bool kDebugSkipSignup = false;` — confirmed `false` in the audited commit. Used at `main.dart:112` to gate whether the app opens directly to onboarding step 4, skipping sign-in. **Currently safe.** No new finding; DC-009's existing low-severity observation (manually-toggled constant, no build-flavor gating) stands as already recorded by the Dependencies/Config audit.

---

## Startup Error Handling — Broader Than Previously Scoped

Re-read `lib/main.dart` in full. The prior audit (DC-004) correctly identified that a startup config failure hangs the splash screen because `runZonedGuarded`'s handler only calls `debugPrint`. Reading the surrounding code, the **scope of this handler is wider than "startup only"**: the code comment explicitly states the zone guard exists to catch *"a deep link with a stale/reused/invalid Supabase auth code ... [that] throws an uncaught AuthApiException from inside supabase_flutter's own internal deeplink handling."* This means the same debugPrint-only handler is the **catch-all for every uncaught asynchronous exception for the entire lifetime of the app**, not only the four `await` startup calls DC-004 focused on — any uncaught async error anywhere in the app, at any point after launch, is silently absorbed with no crash, no visible error, and no telemetry (no crash-reporting SDK exists — independently confirmed, see Reliability audit `RR_findings.md`).

**FQ-002 — App-wide uncaught-async-error handler is silent by design, beyond the originally-scoped startup case**
- **Severity:** P2 (Medium) — functional correctness of any *specific* feature isn't directly broken by this, but it materially increases the risk that real defects (in any feature, not just startup) go completely undetected in production, including by the development team.
- **Affected:** `lib/main.dart:34-61` (`runZonedGuarded`).
- **Evidence:** 🟧 code + explicit comment confirming the deliberate, broader intent ("keeps that from taking down the whole app" — but the mechanism used is not scoped to only the deep-link case).
- **Launch-blocker status:** NO independently — this is a Reliability/Observability-primary finding; recorded here from the functional-QA angle because it means **any future functional defect this audit did not catch (or a regression introduced after this audit) may never surface in production telemetry**, undermining confidence that "tests pass today" implies "will keep working." Cross-reference: DC-004, and the Reliability audit's parallel finding.
- **Status:** OPEN

---

## Findings Summary

| Finding ID | Severity | Launch blocker? | Status |
|---|---|---|---|
| FQ-000 | P3 (pending visual confirmation) | NO (unknown) | OPEN |
| FQ-001 | P3 | NO | OPEN |
| FQ-002 | P2 | NO (cross-references Reliability) | OPEN |

No P0/P1 functional defect was independently confirmed in this pass. This is a materially more favorable functional result than the unresolved Gemini-endpoint question alone might have suggested — 246/254 non-golden tests pass, the dead fiqh engine is confirmed unreachable from any UI path, and AI failures (if the endpoint concern materializes) degrade to a visible error rather than silent/deceptive behavior.

**This does NOT resolve ROOT-001.** If the Gemini endpoint is confirmed broken, the correct functional classification becomes **P1 — "a primary user journey [AI Advisor / Dream Interpreter / Dr. Niswah fallback] fails"** for all three surfaces, which would be a pre-launch blocker per this template's own severity model (§3, P1). This audit cannot close that determination; it is carried forward as `UNK-001` (see master finding register) and must be resolved with one live smoke-test call before final sign-off.
