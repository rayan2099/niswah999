# Fiqh Rule/Source Matrix

Source Governance, Madhhab Authority, Jurisdiction Sources, and Fiqh Advisor Grounding wave (2026-09-09). Charter: `production-readiness/MDs/FIQH_ENGINE_ACCURACY_AUDIT_MASTER.md`.

**Read this first**: every "source" cited below is an **AI-drafted, unverified** reference to a genuine, well-known classical or institutional work — not a page-accurate citation confirmed against a primary text, and not a claim of religious authority. See `fiqh_source_registry.json`'s `_meta.warning` for the full disclosure. Nothing here is `APPROVED`.

## Phase A — Current rule inventory

| Rule ID | Topic | Madhhab | Implemented value/logic | Code location | Source status | Test coverage | User-facing consequence | Affects prayer/fasting? |
|---|---|---|---|---|---|---|---|---|
| `FR-001` | Minimum hayd (menstruation) duration | Hanafi | 72 hours (3 days) | `lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart:37-40` | `AI_RECALLED_UNVERIFIED` (draft sources: `SRC-HANAFI-001/002/003`) | `test/services/multi_madhhab_engine_test.dart`, `test/services/golden_fiqh_dataset_test.dart` | Bleeding shorter than this is classified `needsAdvisory`, not `haid` — affects whether prayer/fasting are excused | **Yes** |
| `FR-001` | Minimum hayd duration | Maliki, Shafi'i, Hanbali | 24 hours (1 day) | same file, same lines | `AI_RECALLED_UNVERIFIED` (draft sources: `SRC-MALIKI-*`, `SRC-SHAFII-*`, `SRC-HANBALI-*`) | same | same | **Yes** |
| `FR-002` | Maximum hayd duration | Hanafi | 240 hours (10 days) | `madhhab_rule_evaluator.dart:41-43` | `AI_RECALLED_UNVERIFIED` | same | Bleeding longer than this is classified `needsAdvisory` (potential istihadah), not `haid` | **Yes** |
| `FR-002` | Maximum hayd duration | Maliki, Shafi'i, Hanbali | 15 days | same file, same lines | `AI_RECALLED_UNVERIFIED` | same | same | **Yes** |
| `FR-003` | Minimum purity (tuhr) before a new hayd episode can be confirmed | Hanafi (enforced as a branch condition) | 15 days | `madhhab_rule_evaluator.dart:44,51-54` | `AI_RECALLED_UNVERIFIED` | same | If violated, produces `needsAdvisory` rather than asserting a fresh `haid` | **Yes** |
| `FR-003` | Same constant, other 3 madhahib | Maliki, Shafi'i, Hanbali | 15 days (constant computed but not gated as a branch condition in this evaluator for these three) | same | `AI_RECALLED_UNVERIFIED` | same | Currently a documented asymmetry (see `FIQH-7` below), not evidence of religious content per se | **Yes** |
| `FR-004` | Personal habit (`'adah`) tracking | Maliki only | `personalHabit`/`isWithinPersonalHabit` fields — informational, does not change `state` | `madhhab_rule_evaluator.dart:66-69` | `NOT_APPLICABLE` — a product-design choice (only Maliki gets habit-tracking modeled), not a numeric threshold; the *choice itself* is undocumented as to why | same | Currently informational only, does not alter the classification the user sees | Indirectly (feeds `state`'s inputs conceptually, not gated in code) |

**Consumers** (confirmed via `grep`, unchanged from prior waves): `CycleStatusEngine` (dashboard display + `haid`/`tahara`/`needsAdvisory` classification the user sees daily), `FiqhReportInsightsEngine` (the "تقرير الحالة الشرعية" / Fiqh Report PDF), `ClientFiqhStateProvider` (feeds the AI User-State Context Layer's `clientFiqhState` field). All four rules above are load-bearing for what the app tells a user about her prayer/fasting obligation — this is precisely the "affects prayer/fasting classification" category the charter's `FIQH-0`/`FIQH-1` severities exist for.

## Phase F — Four-madhhab matrix with source/jurisdiction columns

| Rule ID | Topic | Hanafi | Maliki | Shafi'i | Hanbali | Shared? | Source IDs | Jurisdiction modifiers | Reviewer status | Implementation status |
|---|---|---|---|---|---|---|---|---|---|---|
| `FR-001` | Min. hayd | 72h | 24h | 24h | 24h | Shafi'i/Hanbali share a literal code branch; Maliki has its own branch, same value | `SRC-HANAFI-001/002/003`, `SRC-MALIKI-001/002/003`, `SRC-SHAFII-001/002/003`, `SRC-HANBALI-001/002/003` | None modeled — no jurisdiction currently overrides or supplements this value | `NOT_REVIEWED` | Implemented, matches the AI-recalled draft position for all 4 madhahib |
| `FR-002` | Max. hayd | 240h (10d) | 15d | 15d | 15d | Maliki/Shafi'i/Hanbali share one literal branch value | same source IDs as `FR-001` | None modeled | `NOT_REVIEWED` | Implemented, matches draft position |
| `FR-003` | Min. purity before new hayd | 15d, **enforced** | 15d, computed, **not gated** | 15d, computed, **not gated** | 15d, computed, **not gated** | Constant shared; only Hanafi's branch actually checks it | same source IDs as `FR-001` | None modeled | `NOT_REVIEWED` | **Flagged: implementation asymmetry** — see `FIQH-7` below |
| `FR-004` | Personal habit (`'adah`) | Not modeled | Modeled, informational-only | Not modeled | Not modeled | Maliki-only | None assigned | None modeled | `NOT_REVIEWED` | **Flagged: undocumented scope choice** — see `FIQH-4`/`FIQH-6` (prior waves) |

**No unsupported values found**: every numeric constant traces to a real, named madhhab position that a qualified reviewer can check against the draft reference works above — none are unexplained/orphaned magic numbers.

**No cross-madhhab contamination found** (re-confirmed this wave, matching Wave 52's own finding): each madhhab's value is selected via an explicit `switch`/ternary on the `madhhab` parameter, never blended or defaulted from another madhhab.

**Source disagreement**: none identified within this draft — all 4 madhahib's values here are broadly consistent with the mainstream position commonly cited for each school in comparative-fiqh literature (to the AI-recalled confidence level disclosed throughout this document). A qualified reviewer may find otherwise; this is a draft, not a settled comparison.

**Implementation/source mismatch**: none found at the *numeric-value* level. One **process** mismatch flagged: `FR-003`'s purity-before check is only gated (enforced as a branch condition) for Hanafi, while the same 15-day constant is computed but unused as a gate for the other three madhahib — this is a code-completeness gap, not evidence that the underlying *value* is wrong for those madhahib.

## Severity classification (per charter: `FIQH-0` materially incorrect worship rule; `FIQH-1` unsupported/unverified major rule)

**Note on ID overlap**: the charter's `FIQH-0`/`FIQH-1` below are *severity classes* ("materially incorrect worship rule" / "unsupported or unverified major rule"), distinct from this project's own sequentially-numbered finding IDs (`FIQH-1` through `FIQH-7` in `FIQH_AICTX_findings.md`, e.g. `FIQH-1` there is the already-remediated dead calculator, not this severity class). Where a class and a finding ID share a number below, they are being used in their two different senses — the finding register (`FIQH_AICTX_findings.md`) is authoritative for actual finding IDs/status.

- **No `FIQH-0`-class finding found.** No implemented rule is contradicted by the draft source review above, and the engine's own design (fails to `needsAdvisory`, never silently asserts a wrong `haid`) already biases toward safety on the boundary cases this session could check.
- **`FIQH-1`-class (unsupported/unverified major rule) — open for `FR-001`, `FR-002`, `FR-003` across all 4 madhahib.** This is the severity class assigned to finding `FIQH-2` in the register (see its updated row: `PARTIALLY ADDRESSED`, still `CONDITIONAL`). Every one of these load-bearing, prayer/fasting-affecting values remains `AI_RECALLED_UNVERIFIED`/`NOT_REVIEWED` — this status is **carried forward, not closed, by this wave**. Only a qualified Islamic scholar's direct confirmation against a primary or recognized secondary text can close it.
- **`FIQH-3`** (prior wave, unrelated, unchanged): the `cycle_entries.fiqh_state` dead-column data-integrity gap remains open, unaffected by this wave.
- **`FIQH-7`** (**new this wave**): the `FR-003` enforcement asymmetry (Hanafi-only gating) is now a dedicated, tracked finding — open, requires qualified reviewer judgment before an engineering fix is chosen (see `SCHOLAR_REVIEW_PACKAGE.md` §3).
- **`FIQH-4`/`FIQH-6`** (prior waves, unchanged): the Maliki-only `'adah` tracking design choice and the missing distinct `ISTIHADA` state remain open, unaffected by this wave.

## Phase G — Fiqh Advisor grounding: root cause and architecture

**Root cause: `CONFIRMED`** (Google's own first-party error message, not inferred). Investigated by adding temporary-then-kept diagnostic logging to the shared Gemini caller (`supabase/functions/_shared/gemini_client.ts`, commit `672b3af`), deploying, and reproducing live in production. The Gemini API itself returns, on every model attempted, specifically when `useGoogleSearch: true` (the grounding tool) is requested:

> `"You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. To monitor your current usage, head to: https://ai.dev/rate-limit."` (`code: too_many_requests`, HTTP 429)

This is **quota/billing**, not implementation, not configuration, not "another cause." The same API key/project succeeds reliably for the other 3 functions' plain (non-grounded) Gemini calls — this is specifically the Google Search grounding tool's own separate quota/entitlement being exhausted or never provisioned at a sufficient tier. **This requires an owner action** (the project's Google Cloud / AI Studio billing console) this session cannot perform — recorded as an owner-gated item, matching `DC-010`/`AU-009`/`PC-006`'s existing pattern in this engagement.

**The safe degraded behavior was not weakened.** `fiqh-advisor-chat`'s existing "cannot rule without trusted sources, ask a qualified scholar" fallback is completely unchanged — the only code change made was to log the *upstream error detail* that was previously being discarded, so this root cause could be determined precisely instead of guessed at.

**Preferred architecture (designed, not fully implemented this wave)**: the charter's own instruction — "the model must not use unrestricted internet search as religious authority" — points at a deeper fix than simply restoring Google Search quota. Live, unrestricted web search (even filtered post-hoc to 2 trusted domains) means Fiqh Advisor's grounding quality depends on whatever a search engine happens to index and rank *right now*, not on a reviewed, stable source set. The architecture this wave recommends:

```
validated source registry (fiqh_source_registry.json, scholar-reviewed)
  -> a curated set of approved passages/rule summaries per rule ID
  -> retrieval keyed by the deterministic fiqh state + rule IDs already
     computed server-side (no search engine in the loop at all)
  -> Gemini explains/synthesizes ONLY from the retrieved approved text
  -> the AI is never the source of the ruling, only the explainer of one
```

**Why this wasn't implemented this wave**: it requires the underlying content — actual scholar-approved passage text for each rule, in each madhhab — which does not exist yet (this wave's own source registry only reaches title-level "this book likely covers it," not passage-level approved text, precisely because that requires the qualified review this wave is not a substitute for). Building retrieval infrastructure over content that doesn't exist yet would be premature. **Recommended sequencing for a future wave**: (1) qualified scholar populates approved passage-level content against the draft registry, (2) then a retrieval-over-approved-content architecture is built and Fiqh Advisor is switched off live Google Search grounding entirely — which would also make it independent of this exact billing/quota risk going forward.

## Phase I — Golden dataset source mapping

See `golden_fiqh_dataset.json` (updated this wave: each of the 12 cases now carries a `source_ids` array referencing this registry and a `reviewer_status` field). All 12 remain `NOT_REVIEWED` — none were marked `APPROVED` by this session, per explicit instruction. No case was identified as internally disputed/ambiguous *by this session's own re-check* beyond what the original dataset's own `_meta.warning` already disclosed.
