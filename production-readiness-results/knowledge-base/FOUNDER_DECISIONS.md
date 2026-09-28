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
