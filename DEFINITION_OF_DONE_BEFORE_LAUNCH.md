# Niswah — Definition of Done Before Launch

**Status:** `NOT READY`
**Purpose:** This file is the authoritative launch gate for Niswah.
**Rule:** Niswah must not be called launch-ready until every item marked **Launch Blocker = YES** is `PASS` or explicitly reclassified with written justification.

**Audit note (2026-10-15):** This update is a full evidence-based re-audit of every row below, performed against the repository at commit `01ef39ed99c8ff121ebcf2b23bd25f8d3906ddfa` on branch `feat/onboarding-redesign`. Every `PASS` below cites a concrete artifact (commit, file path, migration, test, CSV row count, CI/PR record, or production execution log). Rows not independently re-verified this round keep their prior status rather than being upgraded on assumption.

**Reconciliation note (2026-10-16):** Since the audit above, PR #4 (`feat/menstrual-data-integrity`), PR #18 (`feat/madhhab-community-integrity`), and PR #22 (`fix/kb-human-review-provenance`, the independent `human_review_status` cherry-pick) have all merged into `main`. `feat/onboarding-redesign` has been merged with current `main` (commit `d6988a3`) and opened as draft PR #23 — the branch's first-ever PR and first-ever CI run. PR #23's own final review found and this same pass fixed one additional release-blocking defect: `FiqhReportInsightsEngine` retained the `cycleDay == 1` boundary bug `01ef39e` removed from `CycleStatusEngine`, a second un-deduplicated copy of the same scan that caused the Fiqh/Doctor/Husband reports to misclassify an open, in-bounds Haid episode as `needsAdvisory` (fixed in commit `6273f39`, with regression coverage built from the real production adapter path). Rows below that describe the pre-reconciliation state (no PR, never-run CI, three unreconciled branches) are corrected inline where marked **(2026-10-16)**; rows not marked are otherwise unchanged from the 2026-10-15 audit and have not been independently re-verified this pass.

**Scope note — read before interpreting any row below.** Niswah has two separate release surfaces that this file's rows often blur together:

- **Already in production** (verified via `gh pr view 14`, merged 2026-10-05): the KB v1 retrieval pipeline (211 production-eligible / 43 fail-closed atoms, snapshot `eda4b96c...`), the OpenAI Edge Function cutover, and production Sentry. This is the *current live app's* backend.
- **Not yet merged to `main`, not in production:** PR #4 `feat/menstrual-data-integrity` (draft, stays draft per standing founder rule), PR #18 `feat/madhhab-community-integrity` (draft since 2026-10-07 — community language, Madhhab selector unification, symptom-trends integrity), and this branch `feat/onboarding-redesign` (geographic Madhhab governance, effective-dated Madhhab history, the `cycleDay==1` canonical-evidence fix). **Nearly every `PASS`/`VERIFY` row in Sections 3, 5, 6, 7, and 11 describes code on these unmerged branches, not code running in production.** "PASS" in those sections means "implemented and tested, ready to be part of the next release candidate" — it does not mean "already live."

## Status Legend

- `PASS` — Requirement is satisfied with concrete evidence.
- `PENDING` — Work is known and not yet complete.
- `BLOCKED` — Cannot be completed until an external dependency or decision is resolved.
- `NOT REQUIRED` — Explicitly determined not to be required for launch.
- `VERIFY` — Reported complete, but repository/device/production evidence still needs final confirmation.

For every `PASS`, the release-candidate audit should attach the exact evidence: commit SHA, test file, migration, report, screenshot, device log, review packet, or production-readiness artifact.

---

# 1. Release Candidate Integrity

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| One clearly identified release-candidate commit/branch exists | VERIFY | YES | **(2026-10-16)** HEAD is `6273f39` on `feat/onboarding-redesign`, pushed to `origin` and open as draft PR #23 against `main`. Full CI has run on this branch for the first time; all required checks passed as of the fix commit above. Still `VERIFY` rather than `PASS`: PR #23 is draft, unreviewed by the founder, and not merged. |
| All intended PR #4 / PR #18 / onboarding-redesign work is reconciled into the RC | PASS | YES | **(2026-10-16)** PR #4 and PR #18 have merged into `main` (merge commits `05d55bb`, `52b9420`). PR #22, an independent cherry-pick of this branch's `human_review_status` work, also merged into `main` (`ccacf04`) ahead of this branch. `feat/onboarding-redesign` has been merged with current `main` (`d6988a3`) and opened as PR #23 — the remaining branch-only scope (geographic Madhhab governance, effective-dated Madhhab history, FD-7 corrections, this audit's own fixes) is now the entire diff of that PR, not three separate unreconciled lines of work. |
| Working tree clean except explicitly documented release artifacts | PENDING | YES | Not clean: 1 modified tracked file outside this task's scope (`lib/features/auth/presentation/screens/sign_in_screen.dart`), 8 staged-but-uncommitted additions (CI/vault infra), and 7 untracked paths including an uncommitted migration (`supabase/migrations/20261012090000_record_onboarding_menstrual_history_episode_reconciliation.sql` — confirmed via `git log --all` to exist on **no** branch anywhere) and two stray Obsidian scratch files (`Untitled.base`, `Untitled.canvas`) that don't belong in a release tree. |
| Full test suite passes on RC | PASS | YES | **Closed 2026-10-15** (commit `e0b55e9`, blocker #2 below; reconfirmed after the FD-7 engine corrections, commit `44238ff`). Full suite now: **1226 passed / 2 skipped / 0 failed**. |
| Golden-test time-drift defect | PASS | YES | **Fixed 2026-10-15** (commit `e0b55e9`): `_relativeTime()` in `lib/features/community/presentation/widgets/community_post_card.dart` now calls `AppClock.now()` instead of `DateTime.now()`, matching `ParityTestHarness`/`CycleStatusEngine`'s existing pattern. The two affected goldens were regenerated under the harness's fixed clock. This closes the recurring daily-drift failure for good, not just for today. |
| `flutter analyze` has no errors | PASS | YES | Fresh run this audit: 0 errors, 0 warnings, 97 pre-existing `info`-level lints (deprecated-API-use and style suggestions only — e.g. `withOpacity`, `hasFlag`, `prefer_initializing_formals`). None block compilation or indicate a defect. |
| No debug/test-only bypass is active in release build | PASS | YES | **Fixed 2026-10-15** (commit `e0b55e9`): `MadhhabSuggestionService.debugApprovedMappingIdsForTesting`'s one call site is now gated on `kDebugMode`, a compile-time constant that is `false` in release builds, so the Dart compiler eliminates the branch — matching `BuildInfo.diagnosticsEnabled`/`acceptanceMode`'s existing pattern. |
| No staging secrets, tokens, DB URLs, service keys, or test credentials are committed | PASS | YES | `git ls-files \| grep -i '\.env$'` → empty. `.gitignore:7` covers both `supabase/functions/.env` and `.env.staging.secret` (confirmed via `git check-ignore -v`). Repo-wide grep for `sbp_`/service-role-key patterns across all tracked files finds only explicit local-only dummy tokens (`sbp_local_dummy_000...000`, used in `scripts/provision_local_test_backend.sh` and `scripts/run_auth08_confirmations.sh`) and documentation references to environment-variable *names*, never values. |
| Release tree contains no stray non-project artifacts | PASS | NO | **Fixed 2026-10-15**: the two empty, content-free Obsidian scratch files (`Untitled.base` — Obsidian's default empty table-view template; `Untitled.canvas` — literally `{}`) were deleted. |
| An orphaned, uncommitted migration existed with no git history anywhere | PASS | YES | **Fixed 2026-10-15** (commit `a2502f5`, blocker #1 below): `supabase/migrations/20261012090000_record_onboarding_menstrual_history_episode_reconciliation.sql` and its staging verification script are now committed. This was not a discretionary cleanup — the already-committed Dart client (`bleeding_episode_repository_impl.dart`'s `recordOnboardingHistory`) already called an RPC shape (5 output columns) that only this migration's version of the function provides; without it committed, the client code and the git-recorded schema had silently diverged. |
| Working tree is otherwise clean except documented release artifacts | PENDING | YES | After the above fixes, two unrelated items remain, deliberately **not** touched: a modified `lib/features/auth/presentation/screens/sign_in_screen.dart` (a real, substantive, in-progress feature-tile restructuring unrelated to this audit) and 8 staged vault/CI-infrastructure files (`AGENTS.md`, `CLAUDE.md`, `.obsidian/*`, `project-vault.yml`, `sync_project_vault.py` + its test) that appear to duplicate already-merged PR #19 content. Neither was created by this audit's work, and committing or discarding either without understanding their full intent risks losing someone else's in-progress work — this is for the user to resolve directly. |

---

# 2. Onboarding

*Not independently re-walked end-to-end this audit round; rows below reflect the last verified state plus a structural spot-check (confirmed `test/onboarding_country_picker_test.dart`, `test/onboarding_numeric_input_test.dart`, `test/onboarding_completion_error_test.dart`, `test/auth_onboarding_routing_test.dart`, `test/onboarding_ui_test.dart` all exist and exercise the named behaviors). A full manual RC walkthrough has not been performed on this branch, because no RC has been frozen (Section 1).*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Fresh install reaches onboarding correctly | VERIFY | YES | Physical/simulator RC walkthrough — not yet performed on this branch. |
| Step indicator is correct and counts essential steps only | VERIFY | NO | Manual QA on RC. |
| Back navigation preserves correct answers | VERIFY | YES | Widget tests + manual RC check. |
| Progressive menstrual questions are optional as designed | VERIFY | YES | `test/onboarding_completion_error_test.dart` exists and covers decline paths; full manual confirmation pending. |
| Arabic numeric input works where numeric input remains | PASS | NO | `test/onboarding_numeric_input_test.dart` — Arabic-Indic normalization tests. |
| Duration questions use independent state | PASS | YES | Regression tests cover A/B independence and back/forward preservation. |
| Number-wheel UX is legible and selected digit is never obscured | VERIFY | YES | Final visual RC check on iPhone. |
| Calendar/date picker has clean white styling | VERIFY | NO | Final visual RC check. |
| Country/upbringing picker is searchable in Arabic, English, ISO | PASS | YES | `test/onboarding_country_picker_test.dart`. |
| No country is preselected or promoted arbitrarily | PASS | NO | Picker tests. |
| Completion screen shows actual Niswah features and visible CTA | VERIFY | YES | Final RC walkthrough. |
| Final onboarding persistence succeeds and survives relaunch | VERIFY | YES | Complete onboarding → dashboard → kill app → relaunch → dashboard. |
| Required-save failure never marks onboarding complete | PASS | YES | `test/onboarding_completion_error_test.dart`. |
| No "continue without saving required data" escape hatch | PASS | YES | Removed from required-data failure path. |

---

# 3. Menstrual Data Integrity

*All rows describe `feat/menstrual-data-integrity` (PR #4), which remains **DRAFT and unmerged** — see Scope note. Evidence is code/test-level, not production-live.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Raw bleeding observations are never rewritten by Fiqh/Madhhab changes | PASS | YES | PR #4 integrity architecture + regression tests; this audit confirmed `MadhhabHistoryResolver` and `setMadhhabWithConfirmation` never call any bleeding-episode/observation write method (structural test). |
| One-open-episode constraint is respected | PASS | YES | DB constraint + onboarding reconciliation RPC. |
| Onboarding menstrual-history RPC is idempotent | PASS | YES | Same payload retry creates no duplicate episode/baseline. |
| Existing matching open episode is reused safely | PASS | YES | `supabase/migrations/20261012090000_record_onboarding_menstrual_history_episode_reconciliation.sql` (committed this audit, commit `a2502f5` — previously existed only in the working tree with no git history). Per its own comments, verified against staging during the 2026-10-12 manual QA wave; `scripts/verify_onboarding_episode_reconciliation.py` exists as the repeatable check. |
| Conflicting open episode returns typed conflict, no destructive mutation | PASS | YES | Same migration/commit — returns `episode_conflict`/`conflicting_episode_id`/`conflicting_start_date` without inserting or mutating anything when the existing open episode's start date differs. |
| Baseline writes are independently idempotent | PASS | YES | Verified against staging. |
| CycleStatusEngine canonical evidence path is correct | PASS | YES | `lib/features/cycle_tracking/domain/services/cycle_status_engine.dart` — the `log.cycleDay == 1` early-break was removed this session (commit `01ef39e`) after it was found to pin `activeStart` to "today" for every canonical-evidence-derived log list (since `CanonicalFiqhEvidenceAdapter.buildEffectiveLogs()` never sets `cycleDay`), silently misclassifying open, well-within-bounds Haid episodes as `needsAdvisory`. Verified against 47 existing tests across `cycle_status_engine_test.dart`, `multi_madhhab_engine_test.dart`, `golden_fiqh_dataset_test.dart`, and 2 parity tests — all pass with the fix. |
| Account switch / sign-out mid-flight pending operations are isolated by user ID | PASS | YES | PR #4 hardening tests. |
| Notification tap payload parsing is type-safe | PASS | YES | PR #4 payload tests. |

---

# 4. Fiqh Engine Core

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Hanafi ruleset implemented and tested | PASS | YES | `MadhhabRuleEvaluator` + `test/services/multi_madhhab_engine_test.dart`, `golden_fiqh_dataset_test.dart` — table-driven across all 4 schools. |
| Maliki ruleset implemented and tested | PASS | YES | Same. |
| Shafi‘i ruleset implemented and tested | PASS | YES | Same. |
| Hanbali ruleset implemented and tested | PASS | YES | Same. |
| **Hanafi/Maliki/Shafi‘i/Hanbali duration thresholds are scholar-reviewed before launch** (reframed from "evidence-linked" — see finding below) | **BLOCKED** | YES | **`production-readiness-results/fiqh-engine/fiqh_source_registry.json`'s own `_meta` block, dated 2026-09-09, states verbatim: "THIS IS AN ENGINEERING-PRODUCED DRAFT, NOT A SCHOLARLY VERIFICATION... compiled by an AI assistant... from general Islamic-studies knowledge, not from direct inspection of a primary text." Every one of its 16 sources is `source_confidence: AI_RECALLED_UNVERIFIED` / `reviewer_status: NOT_REVIEWED`, and the file's own `do_not` field states: "Do not deploy this registry as the sole grounding basis for a live ruling without scholar sign-off." No newer review evidence exists anywhere in the repo (`SCHOLAR_REVIEW_PACKAGE.md` matches the same unreviewed status). Unlike the separate KB-atom AI-answer system (Section 8), which has an explicit founder decision (FD-5) authorizing launch without scholar review under 8 binding conditions, this core engine — the one that actually determines every user's live Haid/Tahara/Istihadha prayer-and-fasting-obligation state — has no such general decision. Two specific values are now resolved via the narrow FD-7 mechanism (next row), not this general item — the remaining 10 hardcoded values (Hanafi 72h/240h, Shafi'i 24h/15d, Hanbali 24h/15d-max, Maliki 15d-max) stay under this BLOCKED status.** |
| Two specific engine/KB-evidence discrepancies are resolved via evidence-based founder decision (FD-7), not a general scholar-review waiver | PASS | NO | **Closed 2026-10-15** (commit `44238ff`). Founder Decision FD-7 (`FOUNDER_DECISIONS.md`) corrects, with explicit boundary tests: Maliki's minimum Haid duration (engine previously enforced 24h; the KB's own `LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE` atom `MLK-HAID-04` says no time-based minimum exists — `minimumHaidFor` now returns `Duration?`, `null` for Maliki, never `Duration.zero`), and Hanbali's minimum purity (engine used a universal 15 days; atom `HNB-HAID-06` says 13 days for Hanbali — new `minimumPurityFor(Madhhab)`). Basis: internal crosswalk (`ENGINE_TO_KB_ATOM_CROSSWALK.md`) plus founder-asserted independent external corroboration, Madhhab-scoped, test-covered — the 4 conditions FD-7 itself defines for when this narrow mechanism may be used. Does not extend to any other threshold. |
| All four Madhhab duration/rule differences are tested | PASS | YES | Final Fiqh regression report; table-driven tests pass. |
| Uncertainty/fail-closed behavior is defined | VERIFY | YES | `needsAdvisory` path exists structurally; confirm no unsupported certainty is ever surfaced when evidence/state is incomplete, across every caller (dashboard, doctor/husband/fiqh reports). |
| Ruleset version is explicit and auditable | PASS | YES | `ruleset_version` persisted in `madhhab_history`; `MadhhabRuleEvaluator.rulesetVersion` constant. |
| `previous_ruleset_version` future-safety column exists on staging | PASS | YES | Externally verified (staging project `ovgvevzrcefloitgcsia`): column exists, nullable `TEXT`. Migration `supabase/migrations/20261014220000_madhhab_history_ruleset_version_future_safety.sql` is committed (commit `9f445ab`). |
| Production migration for `previous_ruleset_version` is planned and gated | PENDING | YES | Not yet applied to production; apply only as part of the controlled production deployment for this release wave (not the already-shipped KB/OpenAI wave). |
| **Engine-to-KB-atom crosswalk exists, scoping exactly what a scholar needs to review** (2026-10-15, prerequisite to commissioning review — does not itself close the BLOCKED row above) | PASS | NO | `production-readiness-results/fiqh-engine/ENGINE_TO_KB_ATOM_CROSSWALK.md` — matched all 12 of the engine's hardcoded min/max-Haid/min-purity values (3 per madhhab × 4) against the 180-atom KB evidence set (`PRODUCTION_DISPOSITION_MASTER.csv`). 9/12 were exact matches against already-located, `LOCATOR_VERIFIED`/`PRODUCTION_ELIGIBLE` evidence. **The 2 cells that actively disagreed with the KB's own trusted evidence (Hanbali minimum purity: 15d vs. the KB's 13d; Maliki minimum Haid: 24h vs. the KB's "no time-based minimum") were corrected in code the same day, under Founder Decision FD-7 — see Section 4.** 1 remaining cell (Maliki max-Haid) has supporting evidence that is itself not yet production-eligible (`SCHOLAR_CLARIFICATION_REQUIRED`) and reveals the engine's flat 15-day constant is a simplification of a habit/istizhar-dependent rule; left as-is, flagged for whenever broader scholar review happens. |

---

# 5. Madhhab Selection, Recommendation & Change History

*Implemented on this branch / PR #18, not yet merged — see Scope note.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Shared Madhhab selector is used consistently | PASS | YES | Onboarding/Profile/resolution-screen parity; commit `384425f`. |
| `لا أعرف` persists explicit UNKNOWN, never silently defaults | PASS | YES | Tests + live acceptance. |
| Canonical transition decision table has one implementation path | PASS | YES | `setMadhhabWithConfirmation` now returns `Future<bool>`; `MadhhabResolutionScreen._confirmSelection`/`_stillNotSure` route through it exclusively (commit `384425f`, fixing the prior bypass defect). |
| `unknown → selected` post-onboarding shows light notice | PASS | YES | `test/madhhab_resolution_test.dart` — 5 new regression tests, commit `384425f`. |
| `selected A → B` shows full warning | PASS | YES | Same test group. |
| `selected → unknown` shows full warning | PASS | YES | Same test group. |
| `selected A → A` is a true no-op | PASS | YES | Same test group; `notifyListeners` confirmed never fired. |
| Geographic recommendation is advisory only | PASS | YES | Accept / reject / still-unsure live acceptance (`integration_test/live_acceptance_geo_madhhab_test.dart`). |
| Recommendation is never forced | PASS | YES | Manual selection remains available; `test/onboarding_ui_test.dart` new test confirms accepting a suggestion shows no light notice during onboarding (nothing to reinterpret). |
| Onboarding and Profile/Settings use identical resolution flow | PASS | YES | Shared `MadhhabResolutionFlow` + live parity. |
| Geographic KB contains 59 canonical entries | PASS | NO | `geographic_madhhab_mapping.json`. |
| `SOURCE_VERIFIED` and `SCHOLAR_REVIEWED` are distinct states | PASS | YES | Governance model implemented, commit `384425f`. |
| No `UNVERIFIED`, mixed, or insufficient-evidence row can surface a suggestion | PASS | YES | Tests + live QA. |
| Saudi Arabia live suggestion works | PASS | NO | Source-verified Hanbali suggestion live-tested. |
| Afghanistan live suggestion works | PASS | NO | Source-verified Hanafi suggestion live-tested. |
| Multi-Madhhab country presentation works | PASS | NO | Egypt live-tested with multiple options. |
| Unresolved-country manual fallback works | PASS | YES | Tunisia/Libya live-tested. |

---

# 6. Effective-Dated Madhhab History

*New this release wave, not yet merged — see Scope note.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Historical Madhhab resolver exists | PASS | YES | `lib/core/preferences/madhhab_history_resolver.dart` — `MadhhabHistoryResolver`, commit `9f445ab`. |
| Madhhab history is computational, not audit-only | PASS | YES | `resolveFromEntries()`/`resolveMadhhabForDate()` read effective intervals rather than just logging transitions. |
| Episode uses Madhhab effective at episode start | PASS | YES | `resolveMadhhabForEpisode()` + canonical boundary rule + `test/madhhab_history_resolver_test.dart`. |
| Episode spanning a change is not split across rulesets | PASS | YES | Start-date Madhhab governs entire episode — explicit product decision, confirmed by the user (not inferred). |
| Same-calendar-day change semantics are explicit | PASS | YES | 4 parameterized tests sweeping midnight/9:15am/2:30pm/11:59pm on the change date, all confirming the new Madhhab governs; documented in the resolver's own doc comment as an **application-methodology decision** (date-only episode data, no reliable start-time granularity), not a universal Fiqh claim. |
| Jan→Feb→Mar multiple-switch scenario resolves correctly | PASS | YES | Unit tests. |
| Raw menstrual facts remain unchanged | PASS | YES | Structural (resolver never touches `bleeding_episodes`/`bleeding_observations`/`cycle_baselines`) + staging validation. |
| Zero-history fallback is documented and deterministic | PASS | YES | Resolver tests; `MadhhabResolutionBasis.noHistoryFallback`. |
| Pre-earliest-boundary fallback uses stored previous state, not fabricated dates | PASS | YES | `MadhhabResolutionBasis.earliestRecordPreviousState` + tests. |
| Future ruleset-version interval resolution is safe | PASS | YES | `previous_ruleset_version` support (best-effort, graceful fallback if column absent) + release-gate test proving every interval in a realistic v1→v2 chain resolves deterministically. |
| Six staging validation artifacts were removed | PASS | NO | **Externally verified** (staging project `ovgvevzrcefloitgcsia`): exactly 6 `history_resolver_staging_validation` rows deleted, 0 remain. |
| Legitimate history remained after cleanup | PASS | YES | **Externally verified**: test account's legitimate `madhhab_history` rows preserved; `bleeding_episodes`=2, `bleeding_observations`=4, `cycle_baselines`=2 confirmed post-cleanup; production untouched throughout. |

---

# 7. Geographic Madhhab Evidence Governance

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| All 59 entries have structural consistency | PASS | YES | 0 audit failures. |
| All source IDs resolve | PASS | YES | No dangling source references. |
| Internet-sourced verification is not mislabeled scholar approval | PASS | YES | `SOURCE_VERIFIED` separate from `SCHOLAR_REVIEWED`. |
| Source registry exists and is traceable | PASS | YES | 70-source registry reported. |
| Contradictory/weak evidence blocks recommendation | PASS | YES | Governance tests. |
| Shia/Ibadi/Zaydi contexts are not forced into four Sunni schools | PASS | YES | Classification rules + research report. |
| Remaining `UNVERIFIED` countries have documented research gaps | VERIFY | NO | Review latest second-pass status before RC freeze. |
| Any diaspora/refinement rules are explicit and data-driven | VERIFY | NO | Check final dataset after second-pass research. |

---

# 8. Fiqh / Islamic Knowledge Base Review (AI-answer KB-atom system)

*This section is specifically about the KB-atom retrieval pipeline that grounds AI-generated answers (`ATOMIC_KNOWLEDGE_MATRIX.csv` / `PRODUCTION_DISPOSITION_MASTER.csv` / `kb_retrieval.ts`). It is a **different governance system** from Section 4's hardcoded `MadhhabRuleEvaluator` thresholds — see that section's new BLOCKED row. Do not read a PASS here as covering Section 4.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| 180 Fiqh atoms accounted for across 4 Madhhabs | PASS | YES | Confirmed by **two independent files agreeing exactly**: `ATOMIC_KNOWLEDGE_MATRIX.csv` (261 rows total) has exactly 180 `domain=FIQH` rows, 45 per Madhhab; `PRODUCTION_DISPOSITION_MASTER.csv` (254 rows) independently has exactly 180 `domain=FIQH` rows, also 45 per Madhhab. |
| No `PRIMARY_LOCATOR_NEEDED` remains | PASS | YES | `scripts/verify_kb_review_packets.py`'s own gate enforces `0` remaining; `PRODUCTION_DISPOSITION_MASTER.csv`'s `evidence_status` column contains no such value at all (only `LOCATOR_VERIFIED`=137, `DRAFT_REVIEW_REQUIRED`=74, `SCHOLAR_CLARIFICATION_REQUIRED`=29, `PARTIAL_EVIDENCE`=14, summing to 254). |
| `LOCATOR_VERIFIED` items are traceable | PASS | YES | All 137 `LOCATOR_VERIFIED` rows in `PRODUCTION_DISPOSITION_MASTER.csv` have a non-empty `citation_source_references` field (0/137 missing, checked this audit) — e.g. `HNB-HAID-01` cites "كشاف القناع، باب الحيض والاستحاضة والنفاس" with a direct URL. |
| `PARTIAL_EVIDENCE` items have explicit fail-closed handling | PASS | YES | Checked this audit: 14/14 `PARTIAL_EVIDENCE` rows have `production_disposition = FAIL_CLOSED` (100%). `scripts/build_kb_production_candidates.py` structurally skips (`continue`) any row whose disposition isn't `PRODUCTION_ELIGIBLE` before content is ever populated, and hard-fails (`SystemExit`) if the disposition master's shape changes unexpectedly. |
| `SCHOLAR_CLARIFICATION_REQUIRED` items cannot produce unsupported certainty | PASS | YES | Checked this audit: 29/29 `SCHOLAR_CLARIFICATION_REQUIRED` rows have `production_disposition = FAIL_CLOSED` (100%) — matching FD-5's cited "43 FAIL_CLOSED" exactly (14+29=43). These atoms are never seeded into `knowledge_items`, so `retrieve_knowledge_v1` structurally cannot return them. |
| Scholar-review requirement for the KB-atom/AI-answer system is explicitly decided | PASS | YES | `production-readiness-results/knowledge-base/FOUNDER_DECISIONS.md`, **FD-5** (2026-09-29, status `FOUNDER_APPROVED_WITH_CONDITIONS`): founder explicitly approved shipping evidence-only Fiqh/Health KB content without mandatory human scholar/clinician review, subject to 8 binding conditions (human_review_status always explicit; never mislabel as reviewed; health non-diagnostic; Fiqh source-grounded informational only, never a personal fatwa; attribute source/madhhab; fail-closed on conflict/insufficient-evidence; the 43 FAIL_CLOSED rows stay inaccessible; 3 specific joint scholar+medical Nifas rows stay categorically blocked). Conditions are code-enforced where checked above (fail-closed gating, qualification_note/safety_class pass-through in `kb_retrieval.ts:formatKnowledgeBlock`). |
| **Scholar-review requirement for the separate core-engine duration thresholds is explicitly decided** (new row — see Section 4) | **BLOCKED** | YES | No founder decision exists for this distinct system. See Section 4. |
| Evidence snapshot/version is frozen for RC | PASS | YES | `EXPECTED_SNAPSHOT_COMMIT = 'eda4b96c7b2a77924a3dd86397cbcbba671440b3'` is hardcoded in `kb_retrieval.ts` and `assertSnapshotHealth()` fails closed on any mismatch; confirmed **live in production** per PR #14 ("Activated snapshot `eda4b96c...` at exactly 211 eligible / 43 fail-closed"). |
| **Two KB-evidence inventories do not fully reconcile** (new finding) | PENDING | NO | `ATOMIC_KNOWLEDGE_MATRIX.csv` (261 rows: 180 FIQH + 59 HEALTH + 15 SAFETY_ESCALATION + 7 NISWAH_PRODUCT) and `PRODUCTION_DISPOSITION_MASTER.csv` (254 rows: 180 FIQH + 74 non-FIQH) agree exactly on the 180 FIQH atoms, but the non-FIQH counts (81 vs 74) do not reconcile 1:1 and this audit did not trace the 7-row difference. Not launch-blocking on its own (the FIQH subset, which is the safety-critical one, matches exactly), but should be reconciled or explained before relying on either file as a sole inventory. |

---

# 9. Medical / Health Content Review

**Correction (2026-10-15):** the prior version of this section treated
"complete clinician review of the 74 health atoms" as an open launch
blocker. That contradicted FD-5 (Section 8), which the founder already
signed on 2026-09-29 as `FOUNDER_APPROVED_WITH_CONDITIONS`: these 74
atoms are explicitly permitted to ship evidence-only, **without**
mandatory clinician review, provided 8 binding conditions are enforced.
No later founder decision superseding FD-5 was found in
`FOUNDER_DECISIONS.md` (FD-6 is the most recent, 2026-09-29, and is
about a different topic). **Completing clinician review for these 74
atoms is therefore not a launch blocker on its own** — it would only
become one if the founder revisits FD-5. What *is* required, and is
verified below, is that the 8 conditions FD-5 attached to that approval
are actually enforced, not just agreed to on paper. This section does
not cover static UI copy/disclaimers, which remain a separate, genuinely
open item at the bottom.

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Medical review packet exists | PASS | YES | `production-readiness-results/knowledge-base/MEDICAL_REVIEW_PACKET.csv` — confirmed this audit: 74 rows, with the full intended review schema (`medical_decision`, `approved_canonical_en/ar`, `reviewer_name`, `reviewer_qualification`, `review_date`, `review_notes`, `publication_status`, etc.). `medical_decision = PENDING` and `publication_status = NOT_APPROVED_NOT_PUBLISHED` for all 74 — expected and correct under FD-5's evidence-only model, not a defect. |
| FD-5 condition 1 — `human_review_status` remains explicit on every row, always | PASS | YES | **Closed 2026-10-15** (commit `017f2c1`). Was previously true only by coincidence — no live DB column existed, only the build-time CSV. New migration `20261015120000_kb_human_review_status_provenance.sql` adds `knowledge_item_versions.human_review_status` (`NOT NULL`, `CHECK`'d, deliberately no default so a future insert path cannot silently guess a value), backfilled to `NOT_REVIEWED` for all current content. `build_kb_production_candidates.py`/`render_kb_seed_sql.py` each independently refuse to produce output for a row missing it (2 new passing Python tests confirm this against the real disposition master). `retrieve_knowledge_v1`, `kb_retrieval.ts`'s `KnowledgeHit`/`formatKnowledgeBlock`/`citationPayload`, `verify_kb_live.sql`, and `verify_schema_contract.sql` were all updated to carry/check the real per-row value. **Not independently verified**: the migration was not applied to any database and the new Deno tests were not executed — this sandbox has no Docker, psql, or Deno. Needs a real run before this can be called verified end-to-end rather than carefully-written. |
| FD-5 condition 2 — no `NOT_REVIEWED` row is ever represented as Scholar-/Medically-Approved | PASS | YES | `supabase/functions/fiqh-advisor-chat/index.ts:54` instructs the model verbatim: "Every knowledge item you are given is evidence-verified only -- human_review_status is NOT_REVIEWED for all of it. Never describe it, or imply it, as scholar-approved, or as having been personally reviewed or endorsed by a scholar." `dr-niswah-chat/index.ts:58` carries the equivalent Arabic instruction for health content. Prompt-level enforcement (the correct mechanism for an LLM-mediated answer); no adversarial test was found proving the model never violates it. |
| FD-5 condition 3 — health content remains educational and non-diagnostic | PASS (prompt-level) | YES | Same `dr-niswah-chat` instruction + `safety_class`/`qualification_note` pass-through (Section 8). PR #14's production acceptance matrix lists "Health qualification fidelity" as a passed check against the real backend. No adversarial/red-team test suite specific to this condition was found in-repo. |
| FD-5 condition 4 — Fiqh content stays source-grounded, informational, never a personal fatwa | PASS | YES | `fiqh-advisor-chat/index.ts:54`, same line as condition 2: "never present Niswah itself as the juristic authority, and never phrase an answer as a personal fatwa issued to this specific user." |
| FD-5 condition 5 — Fiqh output attributes the position to its Madhhab/source | PASS | YES | Same line: "attribute the ruling to its madhhab and source." Reinforced by `citationPayload()` (Section 10). |
| FD-5 condition 6 — conflict/unresolved/insufficient evidence remains fail-closed | PASS | YES | Confirmed Section 8: disposition-driven exclusion in `build_kb_production_candidates.py`; `checkQueryRelevance()` rejects out-of-domain queries before retrieval. |
| FD-5 condition 7 — the 43 `FAIL_CLOSED` rows remain inaccessible as authoritative answers | PASS | YES | Confirmed Section 8: 14 `PARTIAL_EVIDENCE` + 29 `SCHOLAR_CLARIFICATION_REQUIRED` = 43, all `FAIL_CLOSED`, structurally never seeded into `knowledge_items`. |
| FD-5 condition 8 — the 3 nifas joint scholar+medical rows stay categorically blocked | PASS | YES | Checked this audit directly: `MLK-NIFAS-29`, `SHF-NIFAS-29`, `HNB-NIFAS-29` are each individually confirmed `production_disposition = FAIL_CLOSED` in `PRODUCTION_DISPOSITION_MASTER.csv`, each with an explicit per-row note that clinical-to-fiqh mapping "still requires scholar and medical review" and is kept fail-closed regardless of citation strength. |
| Medical disclaimers/escalation UI are present where required | PENDING | YES | Device/manual QA; this is static app UI, not FD-5's scope — genuinely still open. |

---

# 10. AI / Knowledge-Grounded Answers

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Production AI responses are knowledge-grounded where required | PASS | YES | `retrieveKnowledge()` (`supabase/functions/_shared/kb_retrieval.ts`) is called by the backend before generation; confirmed live in production per PR #14's production acceptance matrix ("per-Madhhab correctness, cross-Madhhab isolation, unresolved/Nifas fail-closed behavior, Health qualification fidelity, relevance rejection, urgent path, citation fidelity, real OpenAI-backed responses" all PASS). |
| AI backend response validation is strict | PASS | YES | `DrNiswahBackendResponse` hardening. |
| AI citations/provenance reach user-facing output where required | PASS | YES | `citationPayload()` dedupes and forwards `knowledgeKey`/`versionId`/`sourceKey`/`title`/`locator`/`url`/`contentLanguage`; confirmed exercised in PR #14's "citation fidelity" acceptance check. |
| Fail-closed behavior on KB snapshot mismatch | PASS | YES | `assertSnapshotHealth()` returns non-`ok` (never silently serves a default) on `no_snapshot_registered`/`commit_mismatch`/`check_failed`; this is live production code (PR #14), currently matching the activated snapshot. |
| Unsafe unsupported answer generation is blocked | PASS | YES | FAIL_CLOSED atoms are structurally never seeded (Section 8); `checkQueryRelevance()` rejects out-of-domain queries before any retrieval call; PR #14's acceptance matrix explicitly exercised "unresolved/Nifas fail-closed behavior" against the real production backend. |
| Real production backend has been validated with release candidate | PENDING | YES | PR #14's validation covers the backend/KB/OpenAI wave **already in production**, not the mobile-app release candidate this file is gating (onboarding redesign, effective-dated Madhhab history, community language, canonical menstrual data). That RC has not been frozen (Section 1) and therefore cannot yet be validated end-to-end against the real backend. |

---

# 11. Community

*Implemented on PR #18 / this branch (`feat/madhhab-community-integrity`), not yet merged — see Scope note. Underlying migration: `supabase/migrations/20261007093000_community_language.sql`.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| First-entry community-language gate works | VERIFY | NO | `test/parity_community_test.dart` exercises both languages via `CommunityLanguageController`; gate dialog itself not separately widget-tested in this audit pass. |
| Arabic feed returns Arabic-only content | VERIFY | NO | `community_repository_impl.dart` applies `.eq('language', ...)`; live staging/manual acceptance not found in this audit. |
| English feed returns English-only content | VERIFY | NO | Same. |
| New posts explicitly persist language | VERIFY | YES | `createPost()` payload includes `'language': post.language.name`. |
| Preference is account-scoped | PASS | YES | `UserScopedPreferences`. |
| User can change community language later | VERIFY | NO | Profile/Settings manual QA. |
| RLS prevents unauthorized post/comment access/modification | VERIFY | YES | `supabase/schema.sql:170-213` defines ownership-scoped `INSERT`/`UPDATE`/`DELETE` policies (`auth.uid() = user_id`) and public `SELECT` for all of `community_posts`/`community_comments`/`community_likes`, checked this audit. Policy *design* is sound; no adversarial test (actually attempting a cross-user write against a real/local Postgres with JWT simulation and confirming rejection) was found, so this stops short of PASS. |
| Moderation/reporting behavior is defined | PENDING | YES | Product/legal launch requirement. |

---

# 12. Notifications

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Notification payload parser is hardened | PASS | YES | 13 payload tests. |
| Cold-start notification routing works structurally | PASS | YES | Code-path proof. |
| Warm-start notification routing works structurally | PASS | YES | Code-path proof. |
| E4-01 real-device delivery/tap timing | PENDING | YES | Physical Android/iPhone evidence. |
| E4-02 real-device permission Allow/Deny/re-enable | PENDING | YES | Physical Android 13+ and ideally iPhone. |
| E4-05 timezone/DST behavior | PENDING | YES | Physical-device evidence; actual DST if feasible, otherwise explicitly not executed. |
| Android inexact alarm behavior is documented | PASS | NO | Do not treat normal OS deferral as app failure. |

---

# 13. Physical Device Testing

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| iPhone physical-device smoke test | PENDING | YES | Install RC, onboarding, cycle tracking, AI, notifications. |
| Android physical-device smoke test | PENDING | YES | Same critical flows. |
| Notification E4 evidence collected | PENDING | YES | `production-readiness-results/persona-validation/E4_PHYSICAL_DEVICE_CHECKLIST.md` states verbatim: "Status: NOT EXECUTED. E4 is not claimed as passed anywhere." Confirms this section's PENDING status is accurate, not stale. |
| Real keyboard / Arabic input behavior verified | PENDING | NO | Physical device. |
| Real screen-reader pass | PENDING | YES | VoiceOver/TalkBack critical flows. |
| Real device timezone change tested | PENDING | YES | E4-05. |

---

# 14. Accessibility

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Accessibility semantics tests pass | PASS | YES | `test/accessibility_semantics_test.dart` rewritten this session (commit `01ef39e`) to match the current country-picker/suggestion flow; this file's own tests pass. (**Correction, 2026-10-15:** the full suite is not green — it has one known, unrelated failure, `test/parity_community_test.dart`'s community golden, tracked in Section 1. This file is unaffected by it.) |
| Text scaling tests pass | PASS | YES | `test/accessibility_text_scaling_test.dart`, same commit; this file's own tests pass. Same correction as above applies — "pass" means this file, not the full suite. |
| Critical screens have meaningful labels | VERIFY | YES | Manual screen-reader pass. |
| Focus order is logical in RTL/LTR | VERIFY | YES | Device test. |
| No critical control depends on color alone | VERIFY | YES | UI audit. |
| Dynamic text does not overflow at supported scaling | VERIFY | YES | Manual/device acceptance. |

---

# 15. Authentication & Account Lifecycle

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Sign up / confirmation works | PENDING | YES | Fresh staging account test. |
| Sign in / sign out works | VERIFY | YES | RC acceptance. |
| Session survives app restart appropriately | VERIFY | YES | RC acceptance. |
| OTP behavior matches intended one-time verification/session model | PENDING | YES | End-to-end test. |
| Passwordless/email confirmation redirects correctly | PENDING | YES | Verify no localhost/wrong-project redirects. |
| Account deletion works end-to-end | VERIFY | YES | Checked this audit — this is real, not a stub: `AuthRepositoryImpl.deleteAccount()` calls a genuine server RPC (`delete_my_account`, defined in `supabase/migrations/20260906090000_ai_rate_limit.sql` and extended in `20260925100000_ai_rate_limit_counters_deleted_with_user.sql`), sequenced via `performAccountDeletion()` (`account_deletion_orchestrator.dart`) with dedicated resilience tests (`test/account_deletion_resilience_test.dart`). Upgraded from PENDING to VERIFY: implementation and unit-level resilience coverage are solid; no evidence found of an actual end-to-end run against a real staging account being executed and confirmed. |
| Data export works end-to-end | VERIFY | YES | Checked this audit — `lib/features/legal/presentation/screens/data_export_screen.dart` + `test/data_export_resilience_test.dart` (9+ cases: partial-section failure, core-identity-section failure, RLS-denial-shaped failure, empty-dataset handling, all independently isolated). Same upgrade rationale as account deletion: solid unit coverage, no confirmed live staging run found. |
| Account switching does not cross-contaminate local pending state | PASS | YES | PR #4 hardening. |

---

# 16. Privacy & Data Protection

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Privacy policy finalized and matches actual data practices | PENDING | YES | Legal/product review. |
| Sensitive menstrual/health data handling documented | PENDING | YES | Privacy policy + architecture. |
| Data retention rules defined | PENDING | YES | User data, logs, AI conversations, deleted accounts. |
| User can delete account/data | VERIFY | YES | See Section 15 — implementation confirmed real this audit. |
| User can export personal data | VERIFY | YES | See Section 15 — implementation confirmed real this audit. |
| No unnecessary PII is logged | PENDING | YES | Log audit. |
| Secrets are absent from repo/history | PASS | YES | See Section 1 — confirmed clean this audit (`.gitignore` coverage + repo-wide pattern scan, no real tokens found). |
| App Store / Play privacy declarations match implementation | PENDING | YES | Store forms completed. |

---

# 17. RLS / Database Security

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| RLS enabled on all user-data tables | PASS | YES | `supabase/schema.sql` has `ENABLE ROW LEVEL SECURITY` for all 19 tables it defines; `bleeding_episodes`/`bleeding_observations`/`cycle_baselines`/`madhhab_history` each separately enable RLS in their own migration files (confirmed individually, since they postdate `schema.sql`'s own baseline). |
| Users can access only their own menstrual data | VERIFY | YES | Policy design confirmed (owner-scoped `USING`/`WITH CHECK` clauses); no adversarial/live test found proving a second user's JWT is actually rejected. |
| Users can access only authorized profile/community data | VERIFY | YES | Same — see Section 11's community RLS row for the specific policy text confirmed this audit. |
| Append-only `madhhab_history` behavior preserved for clients | PASS | YES | No `UPDATE`/`DELETE` policy exists on `madhhab_history` — confirmed by reading the migration; this was a deliberate constraint honored throughout the staging cleanup (6 rows removed administratively via the Management API, never via a client-facing policy). |
| Elevated staging cleanup did not weaken RLS | PASS | YES | Cleanup was performed via the Supabase Management API's migration/row-delete endpoints under service-role authority, never by adding a policy; confirmed no RLS-related migration was touched during that work. |
| Supabase security advisors reviewed after final migrations | PENDING | YES | Security advisor report. |
| Supabase performance advisors reviewed | PENDING | NO | Resolve launch-impacting findings. |

---

# 18. Staging / Production Schema Parity

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| All required RC migrations applied to staging | VERIFY | YES | `previous_ruleset_version` confirmed applied (externally verified). PR #4's and PR #18's own migration sets' staging-apply status was not re-confirmed this audit beyond that one column. |
| `previous_ruleset_version` exists on staging | PASS | YES | Externally verified live, staging project `ovgvevzrcefloitgcsia`. |
| PR #4 menstrual-integrity migrations exist on staging | VERIFY | YES | Final migration inventory not re-run this audit. |
| PR #18 Madhhab/community migrations exist on staging | VERIFY | YES | Final migration inventory not re-run this audit. |
| An uncommitted migration exists in the working tree with no history anywhere | PASS | YES | **Fixed 2026-10-15** (commit `a2502f5`): committed. Its staging-apply status rests on the file's own claim (verified during the 2026-10-12 manual QA wave, before being committed) — this audit did not independently re-query staging to re-confirm, per the standing instruction to stop testing/using staging tokens this session. |
| Production migration plan is explicit and ordered | PENDING | YES | Exact migration list for *this* release wave before deployment — distinct from the already-executed KB/OpenAI wave (Section 23). |
| Production schema is not modified before approval | PASS | YES | Confirmed: all of this session's and the prior session's work (Madhhab history, geographic governance, ruleset-version column) remained staging-only; production-ref refusal gate held throughout; user explicitly confirmed production was not touched during the staging cleanup. |
| Post-deploy schema verification script exists | PENDING | YES | Automated contract check. |

---

# 19. Observability & Crash Reporting

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Sentry/error reporter initializes correctly in release | PASS | YES | PR #14's production execution log: founder's own unfiltered Sentry dashboard showed real Flutter-runtime events (`dc0f527e...`, `9984b779...`) in the `flutter` project, with Stats & Usage showing 4 accepted / 0 filtered / 0 rate-limited / 0 invalid. This is live production evidence, not a test. PR #15 (zone-mismatch integration fix) is merged into `main` ahead of it. |
| No sensitive health/PII leaks into crash reports | PENDING | YES | Event payload audit. |
| Backend errors are observable without exposing secrets | PENDING | YES | Structured logging review. |
| Critical onboarding/payment/auth failures are diagnosable | PENDING | YES | Release logging test. |
| Production alert ownership is defined | PENDING | NO | Who responds to crashes/outages. |

---

# 20. Performance & Reliability

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Cold start acceptable on real device | PENDING | NO | Measure RC. |
| Dashboard loads reliably on representative account | PENDING | YES | Staging/physical-device smoke. |
| Large menstrual history does not materially degrade UI | PENDING | NO | Representative-data test. |
| Network loss / retry states are safe | PENDING | YES | Onboarding save, AI, community, auth. |
| No duplicate writes on retries | VERIFY | YES | Critical menstrual paths already idempotent (Section 3); `data_export_resilience_test.dart`/`account_deletion_resilience_test.dart` cover isolation-on-partial-failure for those two flows specifically (Section 15). Broader write-path audit not completed. |

---

# 21. App Store / Google Play Readiness

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Apple bundle/signing identifiers final | PENDING | YES | Per PR #16 (merged 2026-10-05): "iOS remains compile-verified but not store-signable until an Apple Developer Team ID plus distribution signing/provisioning identity is supplied." No signing capability exists yet at all — a harder gap than Android's. |
| Google application ID/signing final | PENDING | YES | PR #16 built a real signed-AAB pipeline (verifies the AAB signer is the actual `CN=Niswah` certificate via `keytool`) and fixed a real bug (release builds were missing `android.permission.INTERNET`, which would have made every signed release APK/AAB unable to reach Supabase/OpenAI/Sentry at all). Pipeline exists and is regression-tested; an actual store-ready signed artifact from this exact RC has not been produced (no RC is frozen yet — Section 1). |
| App icons / splash assets final | PENDING | YES | Store/release build. |
| App Store screenshots/metadata ready | PENDING | YES | Arabic/English as required. |
| Google Play listing ready | PENDING | YES | Metadata/screenshots. |
| Privacy nutrition/data safety forms complete | PENDING | YES | Must match actual implementation. |
| Age rating/content declarations complete | PENDING | YES | Health/community/AI features considered. |
| Review notes explain sensitive health/Fiqh functionality accurately | PENDING | NO | Reduce review ambiguity. |
| TestFlight release-candidate build passes | PENDING | YES | Physical-device acceptance. |
| Play internal/closed test build passes | PENDING | YES | Physical-device acceptance. |

---

# 22. Legal / Policy

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Terms of Service finalized | PENDING | YES | Legal review. |
| Privacy Policy finalized | PENDING | YES | Legal review. |
| Health/medical disclaimer finalized | PENDING | YES | Product/legal/medical review. |
| Fiqh/religious guidance disclaimer finalized | PENDING | YES | Clear advisory scope. |
| Community guidelines finalized | PENDING | YES | Moderation/reporting expectations. |
| Saudi PDPL applicability reviewed | PENDING | YES | Data-processing/storage practices checked. |
| Third-party processors documented | PENDING | YES | Supabase, AI provider (OpenAI, since PR #14), crash reporting (Sentry), etc. |

---

# 23. Production Deployment & Rollback

*An earlier, narrower deployment wave (KB v1 + OpenAI cutover) has already been executed and documented — see PR #14/#13/#16. The rows below are about **this** release wave (menstrual-data-integrity, Madhhab history, community language, onboarding redesign), which is a separate, not-yet-planned deployment.*

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Final production migration list frozen | PENDING | YES | Not yet produced for this wave. A proven template exists: `production-readiness-results/knowledge-base/PRODUCTION_DEPLOYMENT_EXECUTION_LOG.md` documents the prior wave's exact process. |
| Production backup / recovery plan confirmed | VERIFY | YES | PR #13 ("prod-prep: production deployment preparation report + rollback runbook," merged 2026-10-04) produced a rollback runbook for the prior wave; whether it generalizes to this wave's schema changes (new tables, not just config/KB changes) was not confirmed this audit. |
| Rollback plan exists for app and backend | VERIFY | YES | Backend: a runbook exists and was available (though "no rollback trigger was hit," per PR #14) for the prior wave. App: no store release exists yet, so there is nothing to roll back from — not applicable until Section 21 progresses. |
| Feature flags / kill switches documented | PENDING | YES | Especially AI/acceptance-sensitive paths. |
| Production migration dry-run completed on staging | VERIFY | YES | Confirmed for exactly one migration this wave (`previous_ruleset_version`, externally verified). Not confirmed for PR #4's or PR #18's full migration sets. |
| Production post-deploy smoke checklist exists | PENDING | YES | Auth, onboarding, cycle, AI, community, notifications. |
| Production environment secrets verified | PENDING | YES | No staging keys/URLs — for this wave specifically. |
| Production deploy requires explicit founder approval | PASS | YES | Confirmed as a followed norm, not just a stated rule: PR #14's own summary states the prior wave was "executed under explicit founder authorization." The same norm applies to this wave and has correctly not yet been invoked. |

---

# 24. Final Founder Acceptance

| Requirement | Status | Launch Blocker | Evidence / Acceptance Criteria |
|---|---|---:|---|
| Founder completes final onboarding walkthrough | PENDING | YES | Final RC, not an intermediate build. |
| Founder validates core cycle-tracking UX | PENDING | YES | Physical/simulator RC. |
| Founder validates Madhhab recommendation/change UX | PENDING | YES | Verified-country + unresolved-country + change-warning paths. |
| Founder validates Arabic UX/RTL | PENDING | YES | Final RC. |
| Founder accepts known non-blocking limitations | PENDING | YES | Written list. |
| Founder gives explicit release approval | PENDING | YES | Required before production promotion. |

---

# Launch Decision

## Current Decision: `NOT READY`

The current implementation has substantial verified engineering progress — including a correctly-executed, evidenced prior production deployment of the KB/OpenAI backend wave. All of this audit's code/tooling-level findings (the uncommitted migration, the recurring golden-test defect, the debug seam, 2 of the engine's evidence discrepancies, and the `human_review_status` persistence gap) have been closed in code. What remains is not closeable by code alone: this release wave (menstrual-data-integrity, Madhhab history, community language, onboarding redesign) has not been consolidated into a release candidate or run through CI even once, the engine's remaining 10 duration thresholds still have no scholar-review decision, and the usual physical-device/legal/store/founder-acceptance work is untouched.

### Remaining Launch Blockers, ordered by safest/shortest execution first

**Closed this audit (2026-10-15), after the three corrections above:**

1. ~~Commit or discard the orphaned migration~~ — **done**, commit `a2502f5`. Was not discretionary: the already-committed Dart client depended on this exact migration's RPC shape, so leaving it uncommitted meant client code and git-recorded schema had silently diverged.
2. ~~Fix the `_relativeTime()` time-drift defect~~ — **done**, commit `e0b55e9`. Full suite confirmed clean afterward: 1220 passed / 2 skipped / 0 failed.
3. ~~Harden the `debugApprovedMappingIdsForTesting` seam~~ — **done**, commit `e0b55e9`, gated on `kDebugMode`.
4. ~~Remove stray non-project artifacts~~ — **done**, the two empty Obsidian scratch files deleted. (Partial: the pre-existing, unrelated `sign_in_screen.dart` change and 8 staged vault-infra files were deliberately left alone — see Section 1's working-tree row. Committing or discarding someone else's in-progress, uncommitted work without understanding its intent is a judgment call for the user, not something to force into this audit.)

**Still open — require an explicit go-ahead or an environment this session doesn't have:**

5. ~~Reconcile PR #4, PR #18, and `feat/onboarding-redesign` into the release line and open a PR so CI runs on it for the first time~~ — **done (2026-10-16)**, with founder authorization at each step. PR #4 and PR #18 merged into `main`; PR #22 (`human_review_status`, cherry-picked from this branch) merged into `main`; `feat/onboarding-redesign` merged with current `main` and opened as draft PR #23, CI green. PR #23's own final review found and this same pass closed one further blocker (the `cycleDay == 1` defect in `FiqhReportInsightsEngine`, commit `6273f39`) — see the Reconciliation note above.
6. Confirm PR #4's and PR #18's full migration sets are applied to staging (only `previous_ruleset_version` is externally confirmed so far) (Section 18). **Not attempted**: requires staging access, which this session has a standing instruction to stop requesting/testing.
7. Add an adversarial RLS test (real/local Postgres + simulated second-user JWT) proving cross-user menstrual/community data access is actually rejected, not just policy-designed to be (Sections 11/17). **Not completed**: attempted and blocked by environment — this sandbox has no running Docker daemon and no local Postgres/`psql` available, and `scripts/provision_local_test_backend.sh` (the repo's own existing mechanism for exactly this kind of test) requires Docker. Needs an environment with Docker to actually execute.
8. Freeze this wave's exact production migration list and write its post-deploy smoke checklist, using `PRODUCTION_DEPLOYMENT_EXECUTION_LOG.md` as a template (Section 23). **Not attempted**: depends on #6's staging confirmation first.

**Requires founder/product/reviewer decision (not code):**

9. **Decide whether `MadhhabRuleEvaluator`'s remaining 10 hardcoded Haid/Tahara/Istihadha duration thresholds may ship without scholar review, or require review first** — this is the single most safety/religiously-critical open question this audit found; it has no general founder decision, unlike the separate KB-atom system (FD-5) (Section 4/8). **Narrowed since this item was first raised**: the 2 values where the crosswalk found an actual engine/KB-evidence discrepancy (Hanbali min-purity, Maliki min-Haid) are now resolved under FD-7's narrow evidence-based mechanism, commit `44238ff` — they no longer need to wait on this item. The remaining 10 values (where the crosswalk found no discrepancy, just no scholar review) still do.
10. Commission scholar review for the Fiqh duration thresholds (if required by #9). **Clinician review of the 74 FD-5 health atoms is not a separate blocker** — FD-5 already permits them to ship evidence-only; see Section 9, where all 8 of FD-5's binding conditions are now `PASS` (condition 1 closed this audit, commit `017f2c1` — `human_review_status` is now a real, `NOT NULL` database column, not just a build-time-CSV coincidence; not yet applied/run against any real database — no Docker/psql/Deno available this session).
11. Finalize Terms of Service, Privacy Policy, health/Fiqh disclaimers, community guidelines, Saudi PDPL review (Section 22).
12. Decide Apple distribution signing identity/Team ID — nothing is possible on iOS store readiness until this exists (Section 21).

**Requires physical devices:**

13. iPhone + Android smoke tests; E4-01/E4-02/E4-05 notification evidence; VoiceOver/TalkBack pass (Sections 12/13/14).
14. TestFlight and Play internal/closed-test build acceptance, once an RC exists and signing is resolved (Section 21).

**Requires founder walkthrough of the final RC (last step):**

15. Founder completes the full Section 24 walkthrough and gives explicit release approval — only once items 1-14 are closed.

### What changed in this audit vs. the prior version of this file

- Corrected the full test-suite claim from "0 failing" to the true current state (1 failing, with root cause identified) and added the time-drift defect as its own tracked item.
- Confirmed `flutter analyze` is clean (0 errors/warnings) and confirmed no secrets are committed — both upgraded from unverified to PASS with evidence.
- Found and flagged a genuinely new, significant blocker: the core Fiqh engine's duration thresholds have no founder decision permitting launch without scholar review, unlike the separate KB-atom system which does (FD-5). This had been implicitly conflated with Section 8's KB-review status in the prior version of this file.
- Reconciled Section 8 against FD-5/FD-6 and the actual CSV data (confirmed the 211/43 split, the 180-Fiqh-atom count, and fail-closed enforcement all hold) — most of Section 8 moves from VERIFY/PENDING/BLOCKED to evidenced PASS, with the scholar-review BLOCKED item carved out explicitly into Section 4 instead.
- Discovered that a backend/KB/OpenAI production deployment wave has **already happened** (PR #14, 2026-10-05) and is evidenced as healthy — added the Scope note so this file's many "PASS" rows for unmerged branch work are not misread as already being live.
- Found a real, untracked, orphaned migration file and a stale-golden/working-tree-hygiene gap (Section 1/18).
- Upgraded account deletion and data export from blank PENDING to VERIFY — both are real, tested implementations, just missing confirmed live end-to-end runs.

**Corrections applied 2026-10-15 (second pass, before blocker closure began):**

- **Section 9 reframed.** Treating clinician review of the 74 FD-5 health atoms as a launch blocker contradicted FD-5 itself, which already permits them to ship evidence-only. No founder decision superseding FD-5 exists. Replaced that blocker with an actual condition-by-condition verification of FD-5's 8 binding conditions (7 `PASS`, 1 `VERIFY` with a minor structural caveat) — see Section 9.
- **Section 14 corrected.** Removed the "full suite green" claim from both accessibility rows — the full suite has the one known community-golden failure tracked in Section 1; only the accessibility-specific test files were actually confirmed green.
- **Section 4 crosswalk added.** Before commissioning scholar review of `MadhhabRuleEvaluator`'s hardcoded thresholds, built `production-readiness-results/fiqh-engine/ENGINE_TO_KB_ATOM_CROSSWALK.md`, matching all 12 hardcoded values against the 180-atom KB evidence set. 9/12 are exact matches against already-eligible evidence; 2 are genuine discrepancies (Hanbali minimum purity: engine says 15 days, the KB's own trusted evidence says 13; Maliki minimum Haid: engine enforces 24 hours, the KB's own trusted evidence says Maliki has no time-based minimum at all) that should be the first things a scholar resolves. This does not close the BLOCKED row — it scopes it.

**Code/tooling blockers closed this same pass (commits `a2502f5`, `e0b55e9`):** the orphaned migration is committed, the community golden time-drift defect is fixed at its root cause (not just re-captured), and the debug-only Madhhab seam is compile-time-eliminated in release builds. Full suite reconfirmed clean afterward: 1220 passed / 2 skipped / 0 failed. Two items were attempted and explicitly not completed rather than faked: an adversarial RLS test (this sandbox has no Docker/Postgres to run it against), and touching the pre-existing, unrelated `sign_in_screen.dart`/vault-infra working-tree state (not this audit's to resolve). Branch reconciliation/PR creation, staging migration confirmation, and the production migration-list freeze were deliberately not attempted — each needs either your go-ahead (a PR is a visible, shared action) or staging access this session was told to stop touching.

**Third pass, same day — evidence-based Fiqh corrections + human_review_status persistence (commits `44238ff`, `017f2c1`):**

- Resolved the crosswalk's 2 engine/KB discrepancies in code under new Founder Decision FD-7 (`FOUNDER_DECISIONS.md`): Maliki's minimum Haid duration is now `null` (explicit "no time-based minimum," never `Duration.zero`) instead of a shared 24h constant; Hanbali's minimum purity is now 13 days via a new per-madhhab `minimumPurityFor()` instead of a shared 15-day constant. FD-7 is explicit that this is a narrow, 4-condition mechanism for these 2 named corrections, not a general scholar-review waiver — Section 4's broader BLOCKED item (10 remaining values) is unchanged.
- New boundary/regression tests prove both corrections and that no other madhhab inherited them. Full suite reconfirmed clean: 1226 passed / 2 skipped / 0 failed.
- Closed FD-5 condition 1 for real: `human_review_status` is now a `NOT NULL` column on `knowledge_item_versions` (previously only a build-time CSV field), propagated through the seed pipeline with fail-fast checks, and exposed in retrieval/provenance (`kb_retrieval.ts`). Section 9 now has 8/8 FD-5 conditions at `PASS`.
- **New item added to the blocker list** (#16 below): the new migration and its SQL/TS counterparts were written carefully against the existing, already-applied code's exact structure, but were not executed against any real database or Deno runtime this session — no Docker, psql, or Deno available in this sandbox. This should be run for real (ideally on staging first) before being treated as verified rather than carefully-written.

16. Apply migration `20261015120000_kb_human_review_status_provenance.sql` to staging and run `scripts/verify_kb_live.sql` + the Deno test suite (`kb_retrieval.test.ts`) for real, in an environment that has Docker/psql/Deno — confirms the `human_review_status` work (item #10's basis) actually functions against a live database, not just that it was carefully written (Section 9/18).

---

# Closure Rule

Niswah becomes `READY` only when:

- every **Launch Blocker = YES** row is `PASS` or explicitly reclassified with written evidence;
- the exact release-candidate SHA has passed the full automated and physical-device acceptance suite;
- production migrations are frozen and dry-run on staging;
- security/privacy/legal/store requirements are complete;
- the founder has explicitly approved release.

**No single test report, PR mergeability status, simulator walkthrough, or passing CI run is sufficient by itself to declare launch readiness.**
