# Founder Decision Packet

**Status vocabulary used below** (replaces any prior "APPROVED"/"APPROVED FOR
V1" language in this file, which was self-recorded by an agent process with no
evidence of actual founder sign-off — corrected 2026-09-29):

- `PROPOSED` — an agent recommendation, not yet put to the founder.
- `PENDING_FOUNDER_REVIEW` — put to the founder, awaiting an actual decision.
- `NOT_APPROVED` — the founder reviewed it and declined, or it was
  auto-implemented without authorization and is being held pending review.
- `FOUNDER_APPROVED` — the founder actually decided this, with the decision
  recorded (who, when, what).
- `FOUNDER_APPROVED_WITH_CONDITIONS` — the founder approved the underlying
  policy, but attached binding conditions; the approval only covers an
  implementation that actually satisfies those conditions, not the policy
  in unconditional form.

**Agent recommendation ≠ founder decision.** Every entry in this file is an
agent recommendation until a founder explicitly marks it `FOUNDER_APPROVED`
(or `FOUNDER_APPROVED_WITH_CONDITIONS`) with an attributable record of that
approval. As of 2026-09-29, FD-5 and FD-6 carry that record; FD-1, FD-2, and
FD-3 do not yet.

---

## FD-1 — Canonical menstrual-state authority for Fiqh logic and AI context

- **Correction (2026-09-30)**: this entry originally claimed `cycle_entries`
  was a "legacy" table and recommended migrating to a canonical
  `bleeding_episodes`/`bleeding_observations` model "the deterministic Fiqh
  engine already uses." **That premise was factually wrong and was never
  code-verified before being written.** A dedicated repository investigation
  (2026-09-30, full file:line citations in
  `OPENAI_REAL_MODEL_ACCEPTANCE_REPORT.md`'s FD-1 workstream) found **no**
  `bleeding_episodes`/`bleeding_observations` table, migration, Dart class,
  or TS interface anywhere in this codebase — the claim existed only as
  prose, repeated across this file, `KB_V1_GAPS.md`, and (transitively)
  `OPENAI_REAL_MODEL_ACCEPTANCE_REPORT.md` §22, with no one having
  re-checked the actual schema/code before propagating it forward
  (that report's own §22 reference is superseded by this correction).
  `cycle_entries` is
  in fact the **only** raw menstrual-data table, and it is what the real
  Fiqh engine (below) itself reads.
- **What actually exists**: `CycleStatusEngine.evaluate()`
  (`lib/features/cycle_tracking/domain/services/cycle_status_engine.dart`)
  composing `MadhhabRuleEvaluator.evaluate()`
  (`.../madhhab_rule_evaluator.dart`) is a real, coherent, pure/deterministic
  Dart engine over `cycle_entries` rows — already the authoritative source
  the dashboard and (mostly) the PDF reports share. It has no server-side
  port; its output reaches the backend only via an optional, client-computed
  `clientFiqhState` string (see `client_fiqh_state_provider.dart`,
  `ai_advisor_service.dart`), which the server previously trusted verbatim
  with no format/enum validation, and used only for `fiqh-advisor-chat` —
  `dr-niswah-chat`, `ai-assistant-chat`, and `dream-interpreter-chat` never
  received it at all. Nifas/postpartum state for Fiqh purposes is a separate,
  disconnected concern: `PregnancyStatusEngine`'s 40-day postpartum window
  is not madhhab-aware and is never passed to `fiqh-advisor-chat`.
- **Founder-approved resolution (2026-09-30)**: "The canonical menstrual-state
  engine is the single source of truth for user menstrual/postpartum/related
  Fiqh state. AI may explain the canonical state but must not independently
  infer, override, recalculate, or contradict it. Any downstream Fiqh logic
  and AI context that depends on menstrual state must consume the same
  canonical structured state. If the canonical engine cannot resolve the
  state sufficiently for a state-dependent Fiqh answer, the system must fail
  closed rather than ask the LLM to decide the state." This does not
  authorize changing substantive Fiqh rules, and does not require inventing a
  second engine — `CycleStatusEngine`/`MadhhabRuleEvaluator` is designated as
  that engine, since it is the one real, already-shared implementation.
- **Current implementation state**: **implemented for the Haid/Tahara/
  Istihada axis, for `fiqh-advisor-chat` specifically** —
  `supabase/functions/_shared/fiqh_state_guard.ts` (new) validates
  `clientFiqhState` against the engine's real 5-value enum (an
  unrecognized/adversarial string is now normalized to `null`, never
  trusted), deterministically detects whether a given question's answer
  depends on current state, and fails closed at the application layer
  (before any KB retrieval or model call) when a state-dependent question's
  state is unresolved, `needsAdvisory`, or absent. The system prompt
  additionally instructs the model that a supplied classification is
  authoritative and must not be recalculated or overridden by the user's own
  claims — verified with 9 real-OpenAI-model test cases (deterministic +
  adversarial, English and Arabic; see `FD1_STATE_ACCEPTANCE_RESULTS.csv`),
  all passing, including the model explicitly refusing a request to
  recalculate state from user-supplied dates. **Not extended** to Nifas/
  postpartum Fiqh state (no canonical engine for that axis exists to wire
  into — a genuine, separate architecture gap, not implemented here per the
  instruction to stop and report rather than invent one), nor to
  `dr-niswah-chat`/`ai-assistant-chat`/`dream-interpreter-chat` (none of
  which issue state-dependent Fiqh rulings today).
- **Risks**: the deterministic state-dependence detector
  (`isStateDependentQuestion`) is a bilingual keyword heuristic, not a
  perfect classifier — same class of imperfection already accepted for
  `detectRedFlags()` in `dr_niswah_red_flags.ts`.
- **Nifas/postpartum governance (2026-09-30, production-readiness pass)**:
  a repository-wide trace found a well-designed, Madhhab-aware schema for
  this (`public.nifas_records`, with `madhhab_max_days` constrained to
  `40`/`60`, plus `public.istihadah_episodes`) in
  `supabase/canonical_baseline/00_public_baseline_draft.sql` — but that
  file's own header comment already flags both tables as "NOT referenced
  by any current code path," independently re-confirmed by a repo-wide
  grep (`nifas_records`/`istihadah_episodes`/`madhhab_max_days`: zero
  matches in `lib/` or `supabase/functions/`). **No active canonical
  Nifas/postpartum engine exists** — the only live postpartum computation
  is `PregnancyStatusEngine`/`pregnancy_status.ts`'s flat, non-Madhhab-aware
  40-day window, which is Health-context-only and was never wired to
  `fiqh-advisor-chat`. Per this pass's adopted policy, no engine was built
  to fill this gap (doing so would require mapping `madhhab_max_days`/
  `tamyiz_applied`/`reverted_to_adah` semantics — genuine Fiqh judgment,
  out of scope here). **Verified live instead**: a state-dependent Nifas
  question ("I just gave birth 3 days ago and I'm still bleeding, can I
  pray?", English and Arabic) already fails closed today, and an
  adversarial attempt to supply `clientFiqhState: "nifas"` is already
  rejected by the existing enum validator (`"nifas"` was never one of
  `FiqhCycleState`'s 5 real values) — both as an emergent, already-tested
  property of this FD-1 entry's own implementation, requiring no new code.
  General/definitional Nifas questions (e.g. "what is the maximum duration
  of Nifas") continue to answer normally from real KB evidence, unaffected.
- **Code dependency**: **yes** — `fiqh-advisor-chat/index.ts` and
  `_shared/ai_user_context.ts` were both changed, and a new
  `_shared/fiqh_state_guard.ts` module added; see
  `PRODUCTION_DEPLOYMENT_READINESS_REPORT.md` for the full commit record.
- **Status: `FOUNDER_APPROVED`, implemented for its stated scope (2026-09-30)**.

## FD-2 — Is TTC in scope for V1?

- **What changed**: the recommendation (previously self-recorded as
  `Decision: APPROVED FOR V1`) is that TTC stays in V1 scope, with its
  absence from `UserAiContext` treated as an implementation gap to close,
  not a scope question to defer.
- **Why it matters**: TTC has zero representation anywhere in the current
  codebase — no field, state, table, or screen (`KB_V1_GAPS.md` G-2). A KB
  taxonomy position (`HEALTH.TTC.GENERAL`) and 14 Health atoms
  (`HL-TTC-001..014`) already exist and are `PRODUCTION_ELIGIBLE` per the
  2026-09-29 evidence audit, but they describe a product surface that may
  not exist yet.
- **Current implementation state**: no TTC state field exists in
  `UserAiContext` or anywhere else. The 14 TTC Health atoms are
  content-ready and internet-verified, but unconnected to any app state.
- **Risks**: building TTC-scoped KB content further without a founder
  confirmation that TTC ships in V1 risks wasted review/engineering effort
  if the founder later says no; conversely, treating it as decided without
  asking risks scope creep the founder didn't sign off on.
- **Available choices**: (a) confirm TTC ships in V1 and prioritize the
  `UserAiContext` field, (b) defer TTC past V1 and mark its 14 atoms
  `POST_V1` in the taxonomy, (c) some partial scope (e.g. read-only
  fertile-window education, no dedicated TTC state).
- **Code dependency**: none yet — same as FD-1, this is a live gap.
- **Status: `PENDING_FOUNDER_REVIEW`.**

## FD-3 — Does Dream Interpreter belong in the authoritative KB?

- **What changed**: this file previously recorded a settled-sounding decision
  ("SEPARATE FROM AUTHORITATIVE HEALTH/FIQH KB") with sub-bullets
  (non-predictive, non-authoritative, etc.) as though already decided. No
  founder sign-off is on record for it.
- **Why it matters**: Dream Interpreter's own system prompt already
  disclaims religious/predictive authority; formalizing it into the KB either
  way changes how much weight its own disclaimer text carries and whether
  that text is centrally versioned (see `AI_MODE_KNOWLEDGE_CONTRACTS.md`
  §18).
- **Current implementation state**: Dream Interpreter is unchanged — no KB
  items, no citations, exactly as it was before this whole KB workstream
  began.
- **Risks**: low either way; this is a positioning question, not a
  safety-critical one.
- **Available choices**: (a) keep it entirely outside the KB, unchanged, (b)
  give it a thin PRODUCT-adjacent presence purely to version its own
  disclaimer text.
- **Code dependency**: none — `dream-interpreter-chat` is unmodified by any
  of this KB work.
- **Status: `PENDING_FOUNDER_REVIEW`.**

## FD-4 — FD-1/FD-2/FD-3's prior "APPROVED" language, and this file's own integrity

- **What changed**: as of 2026-09-29, this file recorded FD-1 and FD-2 as
  self-approved, and FD-3 as a settled decision, with no attributable founder
  sign-off for any of them. This entry corrects that going forward: every
  entry in this file now carries an explicit status from the vocabulary
  above, and none currently holds `FOUNDER_APPROVED`.
- **Why it matters**: a file titled "Founder Decisions" that records its own
  recommendations as already approved is exactly the unearned-authority-status
  problem this whole KB workstream exists to prevent for medical/Fiqh
  content. The same discipline has to apply to the KB's own governance
  records, not just its knowledge items — otherwise "no Scholar-Approved
  rows" in the KB coexists with a governance file quietly self-approving
  everything else.
- **Current implementation state**: corrected in this revision (all statuses
  above rewritten from self-approved language to `PENDING_FOUNDER_REVIEW`).
- **Risks**: none from making this correction; the risk was in leaving it
  uncorrected — a founder skimming this file before could have reasonably
  believed FD-1/FD-2 were already decided.
- **Available choices**: n/a — this is a correction, not a decision requiring
  founder input on its own. The founder's actual input is needed on FD-1/2/3
  and FD-5/FD-6 below, not on whether this file should be honest about its
  own status vocabulary.
- **Code dependency**: n/a.
- **Status: `NOT_APPROVED`** (the prior self-approved language) → corrected.

## FD-5 — Evidence-only production eligibility (no human scholar/clinician gate)

- **What changed**: at some point on this same branch, the governing
  publishing model was changed from the originally-designed lifecycle
  (`DRAFT → SOURCE_VERIFIED → DOMAIN_REVIEWED → APPROVED → PUBLISHED`, where a
  qualified human reviewer's sign-off was required to reach `APPROVED`) to a
  new lifecycle recorded in the current `REVIEW_AND_PUBLISHING_WORKFLOW.md`
  (`DRAFT → SOURCE_VERIFIED → EVIDENCE_CLASSIFIED → PRODUCTION_CANDIDATE →
  PUBLISHED`), where reaching `PRODUCTION_CANDIDATE` requires only an
  evidence classification (`PRIMARY_SOURCE_VERIFIED` or
  `INSTITUTIONALLY_CORROBORATED`) and human review is explicitly listed as
  **optional** (`EVIDENCE_BASED_REVIEW_POLICY.md`, `REVIEW_READINESS_GATE.md`
  carry the same model). No founder sign-off for this change is on record.
- **Why it matters**: this is the single decision that makes the 211
  `PRODUCTION_ELIGIBLE` rows in `PRODUCTION_DISPOSITION_MASTER.csv`
  meaningful as production candidates at all. It is a genuine product-risk
  decision — whether Niswah ships Fiqh/Health guidance backed only by
  internet-evidence verification, with zero human scholar or clinician ever
  having reviewed it, even as an interim V1 posture.
- **Current implementation state**: **fully implemented in code.**
  `fiqh-advisor-chat` and `dr-niswah-chat` are already rewritten on this
  branch to retrieve from the KB under exactly this evidence-only model (see
  FD-6). This is not a proposal sitting separately from the code — the code
  already assumes this decision was made.
- **Risks**: shipping evidence-only Fiqh/Health guidance without any human
  professional review is a materially different risk posture than the
  originally-designed workflow, for content whose whole premise is
  religious/medical sensitivity. Reverting it after users have seen
  evidence-only answers is also a real cost the other direction.
- **Available choices**: (a) accept the evidence-only model for V1 as an
  explicit, informed founder decision, (b) restore a mandatory human-review
  gate before anything is `PUBLISHED` (which would currently make all 254
  rows unpublishable until reviewers are engaged), (c) a hybrid — evidence-only
  for low-stakes PRODUCT/informational content, mandatory human review for
  FIQH and HEALTH.
- **Code dependency**: **yes — significant.** The KB migration, retrieval
  module, and both rewritten edge functions all assume this model.
- **Status: `FOUNDER_APPROVED_WITH_CONDITIONS` (2026-09-29).**

  **Approved policy, as recorded by the founder:** "Evidence-backed
  educational content may be used in production without prior human
  professional approval only where the proposition, scope, provenance, and
  citations satisfy the production-disposition gate. This does not
  constitute professional approval."

  **Binding conditions attached to this approval** (all of the following are
  requirements, not aspirations — see Engineering Remediation Pass, Phases
  1-5, for what was implemented to satisfy them):
  1. `human_review_status` must remain explicit on every row, always.
  2. No row with `human_review_status = NOT_REVIEWED` may ever be
     represented as `Scholar-Approved` or `Medically-Approved` anywhere —
     in the database, the API contract, or the rendered answer.
  3. Health content remains educational and non-diagnostic.
  4. Fiqh content remains source-grounded, Madhhab-specific *informational*
     guidance — never presented as a personal fatwa.
  5. Where appropriate, Fiqh output attributes the position to its
     Madhhab/source rather than presenting Niswah itself as the juristic
     authority.
  6. Any conflict, unresolved interpretation, individualized clinical
     judgment, juristic judgment, or insufficient evidence remains
     fail-closed.
  7. The 43 `FAIL_CLOSED` Fiqh rows remain inaccessible as authoritative
     production answers.
  8. The three pregnancy-loss/nifas joint scholar-and-medical review rows
     (`MLK-NIFAS-29`, `SHF-NIFAS-29`, `HNB-NIFAS-29`) remain categorically
     blocked.

## FD-6 — Fiqh Advisor: removing live Google Search grounding for KB-only retrieval

- **What changed**: `fiqh-advisor-chat` previously called Gemini with
  `useGoogleSearch: true` and filtered results through a 2-domain allowlist
  (`TRUSTED_CITATION_DOMAINS = ['islamweb.net', 'dorar.net']`). On this
  branch, that has been replaced entirely with KB-only retrieval
  (`_shared/kb_retrieval.ts`) against the 211 `PRODUCTION_ELIGIBLE` rows.
- **Why it matters**: this changes what backs a live Fiqh answer today, if
  this branch were merged and deployed — from "whatever Google Search
  returns from two allowlisted domains right now" to "whatever is in the
  frozen 211-row evidence-only KB snapshot." Both have real trade-offs: live
  search can find content the KB doesn't have yet; the KB is auditable,
  versioned, and Madhhab-filterable in a way live search never was.
- **Current implementation state**: **fully implemented in code**, same as
  FD-5 (this is the concrete mechanism FD-5 is a policy statement about).
- **Risks**: KB-only retrieval means any question outside the 211-row
  snapshot now gets a "not enough approved information" response instead of
  a live-search attempt — a real behavior change for users, in either a
  safer or a more limited direction depending on how you weigh it.
- **Available choices**: (a) accept the KB-only cutover as-is, (b) keep live
  search as a fallback when the KB has no eligible row for a question, (c)
  revert to live search until the KB has broader coverage.
- **Code dependency**: **yes** — this is a completed code change on this
  branch, not a pending one.
- **Status: `FOUNDER_APPROVED` (2026-09-29).** KB-only authoritative
  retrieval is approved for production Fiqh Advisor. Uncontrolled live
  Google Search grounding is **not** restored to production answers.
  Internet search remains permitted as part of offline research/evidence-
  verification workflows (exactly what the Internet Evidence Audit already
  did) — it is runtime authoritative answers specifically that must
  originate from the canonical production KB and its approved disposition
  state, never a live, unreviewed web search at answer time.
