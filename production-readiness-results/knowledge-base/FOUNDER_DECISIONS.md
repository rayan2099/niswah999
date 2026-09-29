# Founder Decision Packet

**Status vocabulary used below** (replaces any prior "APPROVED"/"APPROVED FOR
V1" language in this file, which was self-recorded by an agent process with no
evidence of actual founder sign-off — corrected 2026-09-29):

- `PROPOSED` — an agent recommendation, not yet put to the founder.
- `PENDING_FOUNDER_REVIEW` — put to the founder, awaiting an actual decision.
- `NOT_APPROVED` — the founder reviewed it and declined, or it was
  auto-implemented without authorization and is being held pending review.
- `FOUNDER_APPROVED` — the founder actually decided this, with the decision
  recorded (who, when, what). No entry below currently holds this status.

**Agent recommendation ≠ founder decision.** Every entry in this file is an
agent recommendation until a founder explicitly marks it `FOUNDER_APPROVED`
with an attributable record of that approval. Nothing in this repository
today constitutes that record for any entry below.

---

## FD-1 — Canonical menstrual authority for AI context

- **What changed**: `ai_user_context.ts` currently reads menstrual facts from
  the legacy `cycle_entries` table. The recommendation is that AI menstrual
  context should instead read `bleeding_episodes`/`bleeding_observations`
  (the canonical model the deterministic Fiqh engine already uses) as the
  factual authority, with `cycle_entries` retained only for compatibility.
- **Why it matters**: today the AI-facing "database facts" and the
  Fiqh-engine-facing "database facts" are not guaranteed to agree (see
  `KB_ARCHITECTURE.md` §3, `KB_V1_GAPS.md` G-1) — a real trust-boundary gap,
  not a cosmetic one.
- **Current implementation state**: **not implemented.** `ai_user_context.ts`
  still reads `cycle_entries` as of this review. This entry was previously
  recorded in this file as `Decision: APPROVED`, which was inaccurate — no
  code change backs it and no founder sign-off is on record.
- **Risks**: leaving it unresolved means any future KB-grounded AI answer
  about menstrual state may rely on stale/legacy data even after the
  canonical model has moved on for that user.
- **Available choices**: (a) migrate `ai_user_context.ts` to the canonical
  model, (b) keep `cycle_entries` as authoritative and treat the canonical
  model as Fiqh-engine-only, (c) defer past V1.
- **Code dependency**: no current code depends on this being decided either
  way yet — it is a live gap, not something already built around a chosen
  answer.
- **Status: `PENDING_FOUNDER_REVIEW`.**

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
- **Status: `PENDING_FOUNDER_REVIEW`** — this is the single highest-priority
  item in this file.

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
- **Status: `PENDING_FOUNDER_REVIEW`.**
