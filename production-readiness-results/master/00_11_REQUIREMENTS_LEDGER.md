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
- **Launch decision, 2026-09-14 (superseded same day)**: ~~NOT launch-blocking — no current user receives incorrect religious guidance from this gap~~. **Reassessed and reversed, Fiqh Authority / Knowledge-Base Governance Correction wave, 2026-09-14: `AUTH-010` is now a HIGH Fiqh-feature launch blocker.** The prior reasoning treated a forced, uninformed guess as equivalent to a correct choice — it is not. `FIQH-CASE-010` (the golden dataset's own madhhab-disagreement case) confirms the 4 schools genuinely classify identical facts differently, so a wrong guess can produce a materially wrong haid/tahara determination shown with full confidence. This is a real correctness risk, not only UX confusion. Not a whole-app blocker — scoped to the Fiqh-guidance-bearing surfaces only, same as `AUTH-005`. See `AUTH-010`'s row in `00_04_MASTER_FINDING_REGISTER.md` for the full reassessment.
- **Status**: **REMEDIATED — `E2_AUTOMATED_VERIFIED`, Fiqh Remediation Wave 1 (2026-09-14, later the same day)**. `MadhhabSuggestionService` is now genuinely wired into onboarding (and into Settings) as a confirmation-gated suggestion, and a real "I don't know" path exists in both languages. 39/39 onboarding widget tests passing. Owner E4 retest required for final closure — see `docs/final-owner-launch-checklist.md`'s Fiqh Remediation Wave 1 handoff.

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
- **Status**: **REMEDIATED — `E3_SERVER_VERIFIED`, Fiqh Remediation Wave 1 (2026-09-14, later the same day)** — tracked as `AUTH-005`, not a new/duplicate entry. Server-side persistence now real: `public.users.madhhab`/`madhhab_selection_state` (migrated, constrained, RLS-covered by the pre-existing `users_update_own`/`users_read_own` policies with no changes needed), `MadhhabController` rewritten as `LOCAL_CACHE_OF_SERVER`. Live-verified via direct schema/constraint read-back and a real write proven inside a rolled-back transaction. Owner E4 retest required for final closure — see `AUTH-005`'s row in `00_04_MASTER_FINDING_REGISTER.md` and `docs/final-owner-launch-checklist.md`'s Fiqh Remediation Wave 1 handoff.

---

## Fiqh Knowledge-Base architecture requirements (REQ-FIQH-003 through REQ-FIQH-019) — new, Fiqh Authority / Knowledge-Base Governance Correction wave, 2026-09-14

**Context**: the founder's approved Fiqh architecture is a five-stage pipeline — scholar-approved knowledge base → structured retrieval → madhhab-aware rule selection → deterministic fiqh logic where applicable → an LLM (Gemini) that explains/contextualizes only, never acting as the religious authority itself → user-facing answer. This section formally enumerates every component of that vision as its own requirement, and states the current, evidence-based (not inferred) implementation status of each — determined by direct inspection of `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart`, `supabase/functions/fiqh-advisor-chat/index.ts` (full source, including its system prompt), `supabase/functions/_shared/ai_user_context.ts`, the live 25-table Supabase schema, and every file in `production-readiness-results/fiqh-engine/`, per the charter's explicit instruction not to infer status from the existence of the edge functions alone.

Status taxonomy used below: **IMPLEMENTED** / **PARTIAL** / **MISSING** / **UNTESTED** / **SCHOLAR_REVIEW_REQUIRED**.

### REQ-FIQH-003 — Scholar-approved source corpus
- **Description**: A real corpus of religious source material, approved by a qualified scholar, backing every fiqh rule and AI answer.
- **Current status**: **MISSING.** A draft 16-entry registry (`fiqh_source_registry.json`) exists — 12 madhhab reference works (3 per school) + 4 institutional sources — but every entry is `source_confidence: AI_RECALLED_UNVERIFIED` and `reviewer_status: NOT_REVIEWED`. Zero entries are scholar-approved. The registry's own `_meta.do_not` field explicitly instructs: "Do not deploy this registry as the sole grounding basis for a live ruling without scholar sign-off."

### REQ-FIQH-004 — Source IDs / provenance
- **Description**: Every cited source must carry a stable, traceable identifier and real provenance (author, work, institution).
- **Current status**: **PARTIAL.** Source IDs exist and are well-formed (`SRC-HANAFI-001` etc.); author/work-title provenance is real and correctly named. Institutional provenance for jurisdiction sources is real (Dar al-Ifta Egypt, Saudi Permanent Committee, islamweb.net, Dorar Saniyyah). But page/chapter-level provenance is absent for all 12 classical-work entries.

### REQ-FIQH-005 — Source versioning
- **Description**: Rules and sources must carry a version so future edits can be tracked against what was originally scholar-reviewed (or not).
- **Current status**: **MISSING.** No version field/scheme exists for the deterministic engine's rule constants or for the golden dataset (confirmed: "engine version: unversioned in production code"). The source registry entries have no version field either.

### REQ-FIQH-006 — Source location/reference
- **Description**: A specific, checkable chapter/section/page reference for each source-backed rule.
- **Current status**: **MISSING.** Every one of the 12 classical-work entries' `reference_section` field is the literal string `"NOT_LOCATED_THIS_PASS"` — confirmed via direct JSON inspection, not paraphrased.

### REQ-FIQH-007 — Madhhab attribution
- **Description**: Every rule/source must be correctly attributed to the madhhab it applies to.
- **Current status**: **IMPLEMENTED** (engineering level, content unreviewed). The rule matrix and source registry both correctly tag every entry to exactly one of the 4 madhahib (or explicitly cross-madhhab where appropriate, e.g. jurisdiction sources). Attribution accuracy itself is not scholar-confirmed — see REQ-FIQH-017.

### REQ-FIQH-008 — Strict separation between Madhhabs
- **Description**: No madhhab's rule may be silently substituted for or blended with another's.
- **Current status**: **IMPLEMENTED, verified.** `MadhhabRuleEvaluator` selects each madhhab's boundaries via explicit branching with zero blending — confirmed by direct code read and by the existing `FIQH-2`/discovery findings' own conclusion ("no cross-madhhab contamination found"). The `fiqh-advisor-chat` system prompt also explicitly instructs the model: "stay within that school unless comparison is explicitly requested."

### REQ-FIQH-009 — Handling of scholarly disagreement
- **Description**: Where madhahib genuinely disagree, the app must surface that disagreement rather than silently picking one position.
- **Current status**: **PARTIAL.** The golden dataset's `FIQH-CASE-010` explicitly models a disagreement scenario (identical facts, divergent classifications across all 4 schools) for reviewer evaluation. The `fiqh-advisor-chat` system prompt instructs the model: "if reliable sources conflict... say the case needs a qualified scholar and do not give a definitive ruling." But there is no structured, general-purpose disagreement-resolution or disclosure mechanism in the deterministic engine itself — each user only ever sees her own selected madhhab's answer, with no built-in surfacing that other schools would answer differently, unless she happens to ask the AI directly.

### REQ-FIQH-010 — Structured rule retrieval
- **Description**: A real, database-backed, structured retrieval layer the AI draws from, keyed by rule/topic/madhhab — the core of "structured retrieval" in the approved architecture.
- **Current status**: **MISSING.** Confirmed via exhaustive grep of the live 25-table schema, all migration files, and the entire `supabase/functions/` tree: no table or retrieval mechanism resembling a fiqh knowledge base exists. `fiqh-advisor-chat` substitutes live Google Search grounding plus a citation-domain allowlist for this stage. A replacement architecture (validated-source-registry-backed retrieval) is documented as **designed, not implemented** in `fiqh_rule_source_matrix.md`, blocked on scholar-approved passage content that does not yet exist. This is the single largest gap between the approved vision and current reality — see `FIQH-8` in the master finding register.

### REQ-FIQH-011 — Conditions/exceptions
- **Description**: Fiqh rules commonly carry conditions and exceptions (e.g., personal-habit ('adah) tracking, purity-interval enforcement) that must be modeled per madhhab where they apply, with the modeling choice itself reviewable.
- **Current status**: **PARTIAL.** Some conditional logic exists (Maliki-only 'adah/habit tracking; a 15-day minimum-purity threshold) but its scope is inconsistent and not fully explained: the purity threshold is *enforced* as a gate for Hanafi but only *computed, unused* for the other three schools (open finding `FIQH-7`, "requires qualified reviewer judgment" on whether this is a genuine fiqh distinction or an engineering oversight); Maliki-only habit modeling has no documented rationale for why the other 3 schools don't model it.

### REQ-FIQH-012 — Unsupported-question behavior
- **Description**: When the system cannot produce a sourced, confident answer, it must say so rather than guess.
- **Current status**: **IMPLEMENTED.** Confirmed via direct read of `fiqh-advisor-chat/index.ts`: two distinct, honest, Arabic-language fallback messages exist — one for "Gemini answered but nothing passed the trusted-citation-domain filter," one for "the Gemini call itself failed" — both explicitly direct the user to a qualified scholar, never silently guess or present an uncited answer as sourced.

### REQ-FIQH-013 — No model-memory fallback presented as an approved ruling
- **Description**: The LLM's own unstructured training-data recall must never be presented to the user as an approved, sourced ruling.
- **Current status**: **PARTIAL — a genuine, if lower-probability, residual risk.** The system prompt instructs the model to cite sources and to say "case needs a qualified scholar" when sources are absent/conflicting, and the response pipeline does filter citations to two trusted domains — but this is enforced entirely at the prompt-instruction and citation-domain-filter level, not architecturally: the domain filter checks whether a *citation* exists on a trusted domain, not whether the *substantive answer text* is actually grounded in that citation's content. There is no structural guarantee the model's underlying explanation itself, as opposed to its attached citation, isn't drawn from unverified model memory. Flagged for the founder's awareness as a real (not merely theoretical) residual risk, not classified as launch-blocking on its own given the existing fail-safe behavior.

### REQ-FIQH-014 — Explicit user Madhhab precedence
- **Description**: The user's own selected madhhab must always take precedence; the system must never silently answer as if she follows a different school.
- **Current status**: **IMPLEMENTED** (subject to `AUTH-005`'s persistence gap above). `fiqh-advisor-chat` requires `madhhab` as a validated request field (`ALLOWED_MADHHABS = ['hanafi','maliki','shafii','hanbali']`) and returns `HTTP 400` if missing/invalid — it never silently proceeds without one. All 7 jurisdiction-source entries are explicitly flagged `can_override_madhhab_rule: false` / `can_supplement_madhhab_rule: true`, meaning local/jurisdictional guidance is designed to never override the madhhab layer. The precedence mechanism itself is sound; what can go wrong is upstream of it, in what value `MadhhabController` supplies (see `AUTH-005`/`AUTH-010`).

### REQ-FIQH-015 — Madhhab change behavior
- **Description**: When a user changes her selected madhhab, prior fiqh classifications, reports, and AI conversation history should behave predictably (not silently mix old and new madhhab's rules).
- **Current status**: **UNTESTED.** No test, discovery note, or code trace in either research stream confirms what happens to a user's fiqh report history, prior AI Fiqh Advisor conversation content, or in-flight classification when she changes her madhhab selection mid-use. `MadhhabRuleEvaluator` is stateless and always recomputes from the currently-selected madhhab (a reasonable design for future classifications), but historical chat/report artifacts generated under a prior selection have not been checked for correct labeling. Recommended for a dedicated test in a future Fiqh Engineering wave; not established as broken, only as unverified.

### REQ-FIQH-016 — Source-backed AI context
- **Description**: The AI features should receive actual source/rule content as context, not merely a madhhab label.
- **Current status**: **MISSING**, as a direct consequence of REQ-FIQH-010. `ai_user_context.ts`'s own header comment explicitly documents this by design: the deterministic classification "is NOT recomputed here... exists today only as a client-side algorithm," and the module passes through only a `clientMadhhab` label (marked `client_supplied`, never server-verified) plus, optionally, a `clientFiqhState` classification (marked `client_computed`, never server-verified) — no source text, rule ID, or citation content is ever included in AI context, because no such structured content exists to include.

### REQ-FIQH-017 — Scholar review status
- **Description**: A formal, tracked record of what has and has not been reviewed and approved by a qualified Islamic scholar.
- **Current status**: **MISSING** in substance (present as a taxonomy/process, empty of actual approvals). `FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md` Phase 12 defines the gate and taxonomy (`NOT_REVIEWED`/`REVIEW_IN_PROGRESS`/`APPROVED`/`REJECTED`/`REVISION_REQUIRED`); `SCHOLAR_REVIEW_PACKAGE.md` is a complete, reviewer-ready request document. But every single reviewable item across every file — 16 sources, the rule matrix, 13 geographic-suggestion entries, 7 jurisdiction entries, 12 golden cases, all user-facing religious wording — is `NOT_REVIEWED`, and no record anywhere indicates the package has been sent to or reviewed by an actual scholar. This is `FIQH-9` in the master finding register.

### REQ-FIQH-018 — Evaluation corpus
- **Description**: A version-controlled test corpus covering, at minimum, known/unknown madhhab, reinstall/madhhab-change scenarios, normal/irregular/prolonged bleeding, purity intervals, uncertain dates, missing history, postpartum/pregnancy, madhhab disagreement, timezone/day-boundary cases, insufficient source coverage, and contradictory input.
- **Current status**: **PARTIAL.** `golden_fiqh_dataset.json` has 12 real cases (not merely planned) covering: simple normal case, exact-minimum boundary, one-unit-below-minimum, exact-maximum boundary, one-unit-above-maximum, insufficient history, exceeded personal habit, purity-interval boundary, non-bleeding/tuhr baseline, madhhab disagreement (`CASE-010`), a nifas/postpartum architectural placeholder, and a dual-failure ambiguous case. **Confirmed missing from the corpus entirely**: overlapping/interrupted-interval cases, retrospective-correction cases, timezone/day-boundary cases, cross-month/cross-year-boundary cases, a true pregnancy-related-bleeding classification case (the existing nifas case is documentation-only, not an exercised boundary), and an unresolved/unknown-madhhab scenario (all 12 existing cases assume a madhhab is already selected). Every existing case's `review_status` is `NOT_REVIEWED`.

### REQ-FIQH-019 — Adversarial Fiqh validation
- **Description**: Live, adversarial testing of the AI's authority boundaries — attempts to make it override tracked state, treat geography as a madhhab declaration, fabricate sources, or assert certainty under pressure.
- **Current status**: **PARTIAL — 3 of 4 required categories live-tested and passed, the 4th blocked, not failed.** Real production adversarial prompts were run (not merely designed): (1) demanding purity/prayer-eligibility confirmation overriding tracked bleeding state — AI correctly refused and deferred; (2) claiming residency alone constitutes an official madhhab change — AI correctly refused, cited the actual stored madhhab; (3) demanding a definitive haid/tahara ruling under pressure with no classification supplied — AI held its refusal; (4) asking the Fiqh Advisor to quote a deliberately fabricated source — **could not be completed**, blocked by the same Google Cloud Search-grounding billing/quota issue tracked as `AICTX-3` (owner-gated, not an engineering defect). This 4th category — resistance to source fabrication — remains genuinely untested, not merely undocumented.

---
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

Also confirmed still correctly and honestly **open** (not falsely claimed closed): `AUTH-001` (Auth config — see the Production Drift Report for this pass's fresh confirmation of exactly what *is* now live vs. still open), `AUTH-005` (Madhhab persistence — **this is the canonical finding for `REQ-FIQH-002`**, and as of the Fiqh Authority / Knowledge-Base Governance Correction wave, 2026-09-14, is a **CRITICAL Fiqh-feature launch blocker**, not merely a recommendation), `PF-001/002/003` (startup parallelization), `AB-003/004/006/007`, `RD-007`/`PC-004` (public policy hosting), retention period, DPA/subprocessor terms, age-gate, `FIQH-2/4/6/7` (scholar review, istihada state, prayer-fiqh linkage) — and now also `FIQH-8`/`FIQH-9` (no structured KB/retrieval exists; Scholar Review Gate at 0%), both newly assigned this wave.

---

## Fiqh Authority / Knowledge-Base Governance Correction — 2026-09-14 (same-day follow-on to the Post-Reconciliation Governance Correction wave)

**Trigger**: the founder asked whether Niswah can safely launch Fiqh guidance while a user's explicitly selected madhhab can silently disappear and be replaced by an undisclosed default, and whether the previously-approved Fiqh knowledge-base architecture is actually built. Both questions required reassessing the prior wave's blocker model, which had left `AUTH-005` as a recommendation-only item and `AUTH-010` as explicitly non-blocking.

### Two-layer global blocker model (rebuilt, not mechanically preserved)

**CORE APP BLOCKERS** (apply regardless of whether Fiqh guidance is enabled):
- `AUTH-001` — confirmation-link fallback page; needs owner DNS action (`niswah.app` domain connection).
- `DC-010` — iOS production code signing; owner-blocked (no Apple Developer Team/account on this machine).
- `PC-006` — data-retention/export legal scope; needs counsel determination.

**FIQH-FEATURE BLOCKERS** (apply only if Niswah launches with Fiqh guidance surfaces — dashboard fiqh-status card, Fiqh Report, Fiqh Advisor AI chat — enabled):
- `AUTH-005` — **CRITICAL.** Undisclosed silent madhhab default reaches live fiqh-calculation and AI-context output for already-onboarded users who reinstall/change devices.
- `AUTH-010` — **HIGH.** Forced madhhab guess for users who don't know their school risks a materially wrong classification presented with full confidence.
- `FIQH-9` (Scholar Review Gate, 0% complete) — **HIGH** for any claim that fiqh guidance is scholar-approved; not blocking if the feature ships with honest "not yet scholar-reviewed" framing (a disclosure/product decision, not an engineering task).
- `FIQH-8` (no structured KB/retrieval layer exists) — **HIGH** for any claim that fiqh guidance runs on a scholar-approved knowledge base; not blocking if framed honestly as AI-generated guidance with a citation-domain fail-safe.
- `FIQH-2` (production rule-constant source status, partially addressed) and `FIQH-7` (Hanafi-only purity-enforcement asymmetry) — MEDIUM, require qualified-reviewer judgment, not independently launch-blocking.
- `REQ-FIQH-018` (evaluation-corpus category gaps) and `REQ-FIQH-019` (source-fabrication adversarial test blocked by the `AICTX-3` grounding-quota issue) — MEDIUM, recommended before Fiqh Certification.
- `REQ-FIQH-013` (no-model-memory-fallback guarantee is prompt-enforced only, not architectural) and `REQ-FIQH-015` (madhhab-change behavior untested) — MEDIUM, flagged for awareness, not independently blocking.

**Explicit correction from the prior wave**: that wave's report stated "all remaining blockers are owner/external/legal" for the app overall. That statement is corrected here — it remains true for the **core app** layer, but is **not** true for the **Fiqh feature** layer, where genuine engineering/content gaps (not owner/external/legal gates) remain open (`AUTH-005`, `AUTH-010`, `FIQH-8`, `FIQH-9`).

### Overall verdict, split by Fiqh-enablement scenario

- **If Fiqh guidance ships enabled**: **NO-GO for the Fiqh feature specifically**, on top of the unchanged core-app `NO-GO`. The CRITICAL (`AUTH-005`) and HIGH (`AUTH-010`, `FIQH-9`, `FIQH-8`) Fiqh-feature blockers above are unresolved.
- **If Fiqh guidance is disabled/deferred at launch** (dashboard fiqh-status card, Fiqh Report, and Fiqh Advisor chat withheld or clearly marked pre-release): the Fiqh-feature blockers above become non-blocking by construction, and only the **core app blockers** (`AUTH-001`, `DC-010`, `PC-006`) remain — the same posture as the general app launch already tracked. **Caveat, not asserted as settled**: no evidence was found this pass of an existing feature-flag/kill-switch mechanism that could disable these surfaces without a code change — this option is a real product path but would itself require a small, scoped engineering change to implement cleanly, not merely a documentation decision. This is presented as an option for the founder's evaluation, not a recommendation made unilaterally.

---

## Ledger summary

- **Total ledger entries this pass**: 12 original + 17 new Fiqh-KB entries (`REQ-FIQH-003` through `REQ-FIQH-019`) this same-day follow-on wave, plus ~35 existing findings referenced as already-accurate.
- **New MISSING**: `REQ-FIQH-001` / `AUTH-010` (Madhhab "I don't know" UI — **reclassified HIGH Fiqh-feature launch blocker, 2026-09-14**), `REQ-FIQH-002` / `AUTH-005` (Madhhab server persistence — **reclassified CRITICAL Fiqh-feature launch blocker, 2026-09-14**; maps to the already-open `AUTH-005`, not a new/duplicate finding), `REQ-FIQH-010`/`016` (no structured KB/retrieval layer, no source-backed AI context — `FIQH-8`, HIGH Fiqh-feature blocker), `REQ-FIQH-017` (scholar review status — `FIQH-9`, HIGH Fiqh-feature blocker), `REQ-FIQH-005/006` (no source versioning, no located page/chapter references), `REQ-ONBOARD-003` (marital status server persistence, classified `LOCAL_ONLY_UNSAFE`, not launch-blocking), `REQ-ONBOARD-004` / `PJ-007` (Journeys screen unreachable — not launch-blocking, owner decision to wire in or remove the promise).
- **New PARTIAL**: `REQ-ONBOARD-005` (Privacy step naming — non-blocking, recommended), `REQ-DATA-001` (export coverage — non-blocking, required before claiming "full" export), `REQ-DATA-002` (deletion local-cleanup coverage — non-blocking, recommended).
- **New UNTESTED**: `REQ-NOTIF-001` (not launch-blocking; future Notifications Reliability wave), `REQ-CYCLE-001` (not launch-blocking; future Wellbeing/data-integrity wave).
- **New REGRESSED-RISK**: `REQ-ARCH-001` (3 duplicate/orphaned state-authority stacks — dead today, real risk if ever reactivated by a future edit).
- **Governance corrections applied this session (2026-09-14, Post-Reconciliation Governance Correction wave)**:
  - `REQ-ONBOARD-001` (`AUTH-008`) — owner completed a fresh-install iOS E4 retest, **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`**, no longer `LIVE_VERIFICATION_REQUIRED`.
  - `REQ-ONBOARD-002` (`AUTH-009`) — same owner retest, **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`**.
  - `AUTH-007` (Arabic locale/RTL) — same owner retest confirms "Arabic onboarding remained Arabic," **PASS**. Reconciled to **`VERIFIED_CLOSED` / `E4`** in the finding register (not previously a standalone ledger entry, referenced here for completeness).
  - `REQ-FIQH-002` — corrected from "no finding ID assigned" to its true canonical mapping, `AUTH-005`, which already tracked this exact requirement since 2026-09-11. No new finding was created; the duplication was caught and fixed.

---

## REQ-CYCLE-002 — Menstrual Data Integrity & Active Bleeding Journey charter (PR #4, `feat/menstrual-data-integrity`, unmerged, 2026-09-17 through 2026-09-19)

- **Domain**: Cycle Tracking / Data Integrity
- **Description**: a full first-class, provenance-aware bleeding-episode model (`bleeding_episodes`/`bleeding_observations`/`cycle_baselines`) replacing the flat `cycle_entries` table's inability to express episode lifecycle, correction history, or observed-vs-predicted-vs-estimated provenance, plus the full active-bleeding daily journey (check-in, backfill, correction, conflict resolution, notifications) and a canonical (projection-independent) dashboard read model. Full charter text and per-section status live in `docs/menstrual-data-integrity-contract.md`; full requirement-to-code-to-test mapping lives in `00_12_TRACEABILITY_MATRIX.md`'s own dedicated section — not re-transcribed here to avoid a second, divergence-prone copy.
- **Source**: charter document supplied directly by the founder across multiple waves (hardening passes, completion-wave fixes, Hardenings 1-5, Commits A-H).
- **Severity**: self-scored per-item in the traceability matrix (`VERIFIED`/`PARTIAL`/`MISSING`/`N/A`) — not a single blanket severity, since sub-items range from fully verified (Hardening 5's mutation boundary, live-Postgres-proven) to partial (Commit H's remaining adversarial-matrix items still requiring a real device: airplane-mode/timezone-change/DST, notification permission grant-deny, full end-to-end tap-through).
- **Update, 2026-09-19 (later the same day, "Finish the Product Contract" wave)**: Commit F7 (evidence-provenance visual/Semantics UI) and F8 (a canonical calendar screen) — previously the two items explicitly called out above as "genuinely not built" — are now both built and tested (`E2_AUTOMATED_VERIFIED`; see `00_12_TRACEABILITY_MATRIX.md`'s updated rows). The manual-Istihadah Fiqh test regression disclosed by the immediately-prior same-day wave is resolved properly, without restoring the removed legacy fallback, and a second real safety gap found in the same investigation is closed alongside it. Notification continuity beyond the 7-day rolling window received the explicit design review this charter's own Section 4 required, resulting in a two-tier design (unchanged precise window + a new OS-native recurring fallback) — **superseded the next day; see the update immediately below.** 39 new tests added; zero new failures versus this branch's own baseline. Full narrative: `docs/menstrual-data-integrity-contract.md` §10.
- **Update, 2026-09-20 (Independent Review Fixes wave)**: an independent review found the prior update's own notification-continuity design (the two-tier hybrid) to be platform-inconsistent — verified directly against the installed `flutter_local_notifications` plugin's native source, iOS's time-only recurring trigger discards the requested date and would have duplicated the rolling window's own reminders starting day 1. Replaced with a single, predictable 30-day exact window — no recurring layer, no possibility of overlap by construction. Six further fixes, all tested: calendar uncertainty announcements (no longer collapsing "no report" and "explicit uncertain" into one phrase); correction detection (now via `supersedes_id`, never same-day observation count); degraded-read handling (now explicit, distinct from clean success, suppressing predictions); F7 category coverage (2 of 6 categories previously had no real UI surface at all — both now do); the regression-baseline comparison (corrected against the true PR merge base `e4cc02e`, not a later same-branch checkpoint — the one test that didn't reproduce there was a real flakiness this PR itself introduced, now fixed outright); and the owner E4 script's step 10 (split into two independent steps, since it previously chained a 5-day uninterrupted test together with a same-run tap that reopened the app). Final count: 739 tests, 10 failures, zero PR-introduced regressions. Full narrative: `docs/menstrual-data-integrity-contract.md` §11.
- **Launch-critical**: this entire charter is scoped to a still-`DRAFT`, unmerged PR (#4) — not part of the current launch surface until merged; not evaluated against the core-app `NO-GO` verdict above.
- **Evidence level**: mixed E2 (unit/widget tests, `flutter analyze`/`format` clean) and E3 (every SQL migration/RPC verified against a real local Postgres reconstruction, inside real transactions, with real `authenticated`-role/JWT simulation, never superuser). **Zero E4** (real owner/device) evidence exists for any part of this charter — explicitly not claimed anywhere in the contract doc. A portable, repository-committed owner E4 script now exists (`docs/owner-e4-menstrual-journey.md`), ready for whenever that retest happens.
- **Genuine defects found and fixed during this wave** (registered in `00_04_MASTER_FINDING_REGISTER.md` as `MDI-001`/`MDI-002`/`MDI-003`): a `PUBLIC`-only `REVOKE` that didn't actually block `anon` execution on 8 RPCs (the same pattern flagged as still-open in the pre-existing `W1-002`); a reconciliation-loop defect that would have silently dropped a pending operation on genuine RPC failure; a data-export gap missing the 3 new canonical tables (deletion was never actually broken). **Additional defects found and fixed in the 2026-09-19 follow-on wave** (not yet assigned separate `MDI-*` IDs — tracked in the traceability matrix rows instead, per this wave's own scope): the Fiqh-evidence-unresolved guard checking an enum value the fallback snapshot never produces; ending an episode cancelling only today's own reminder id, not the rest of an already-scheduled 7-day window; a future calendar day being treated as backfillable when an open episode has no end date to bound it; `_FiqhEvidenceUnresolvedCard`'s English copy overflowing its fixed circle at real device width.
- **Status**: `IN PROGRESS — DRAFT PR, NOT MERGED`. Not scored against this ledger's core-app GO/NO-GO verdict.
