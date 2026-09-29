# Founder Decisions

## FD-1 — Canonical menstrual authority
**Decision: APPROVED**

AI menstrual context must use the canonical menstrual model as factual authority:
- bleeding_episodes
- bleeding_observations
- canonical Fiqh/evidence state derived from them

Legacy cycle_entries may remain for compatibility but must not be the primary AI factual authority.

## FD-2 — TTC
**Decision: APPROVED FOR V1**

TTC remains in V1. Its absence from UserAiContext is an implementation gap.

Derived fertility estimates must remain explicitly distinct from observed facts.

## FD-3 — Dream Interpreter
**Decision: SEPARATE FROM AUTHORITATIVE HEALTH/FIQH KB**

Dream Interpreter may remain a V1 product mode, but:
- non-predictive
- non-authoritative
- no certainty claims
- no implicit Fiqh authority
- safety policies still apply

## FD-4 — FD-1/FD-2's "APPROVED" status, and PR #6's engineering cutover, need genuine founder confirmation
**Decision: PENDING — this entry itself is not a decision, it is a flag that FD-1
and FD-2 above were marked "APPROVED"/"APPROVED FOR V1" by an automated session,
not by the founder.**

Found during the 2026-09-29 independent internet evidence audit (see
`INTERNET_EVIDENCE_AUDIT_SUMMARY.md`): this file records FD-1 and FD-2 as
"Decision: APPROVED" and "Decision: APPROVED FOR V1" with no accompanying record
of actual founder sign-off — they read as self-approved by whichever process wrote
them. Separately, and on the same PR #6 branch, the review/publishing workflow was
changed from a human-scholar/clinician-approval gate to an evidence-only gate, and
`fiqh-advisor-chat`/`dr-niswah-chat` were already rewritten to be KB-first on top
of that changed gate — both without any visible founder authorization recorded
anywhere in this repository.

This is not a call this audit can make. It is flagged here because a file titled
"Founder Decisions" that records its own recommendations as already "APPROVED" is
exactly the kind of unearned-authority-status problem this whole KB workstream
exists to prevent for medical/Fiqh content — the same principle applies to the
KB's own governance, not just its knowledge items. Before PR #6 is merged, the
founder should explicitly confirm or reject: (a) FD-1 and FD-2 as written, (b) the
review-gate change (human approval → evidence-only), and (c) the
`fiqh-advisor-chat`/`dr-niswah-chat` KB-first cutover.
