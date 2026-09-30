# Retrieval Precision Study (Phase 13, OpenAI Migration Pass)

**Date**: 2026-09-30. Revisits the false-positive Health retrieval finding
from `PRE_MERGE_INTEGRATION_REPORT.md` with a measured, categorized dataset
rather than a single anecdote. Executed directly against
`retrieve_knowledge_v1` on the same disposable local database used
throughout this workstream — **real RPC calls, not simulated scores**. Raw
data: `RETRIEVAL_PRECISION_STUDY.csv` (22 cases).

## Method

22 queries across both domains, in 5 categories per the task's own
specification: clearly relevant, paraphrase, borderline, clearly unrelated,
gibberish/random. Each run through `retrieve_knowledge_v1` at `limit=10`
with the production default relevance floor (`score >= 0.12`, unchanged).
Recorded: query, all returned atom IDs (ranked), top atom, top score,
expected classification (relevant/borderline/not_relevant).

## Headline result

Classifying "observed relevant" as *any hit returned at all* (the actual
production behavior — `kbHits.length > 0` is what gates generation) and
excluding the 4 deliberately-ambiguous borderline cases:

| Metric | Value |
|---|---|
| Clear-cut cases | 18 |
| True Positives (relevant, correctly retrieved something) | 9 |
| False Positives (not_relevant, still retrieved something) | 8 |
| True Negatives (not_relevant, correctly retrieved nothing) | 1 |
| False Negatives (relevant, wrongly retrieved nothing) | 0 |
| **Precision** | **0.529** |
| **Recall** | **1.000** |
| **False-positive rate** | **0.889** (8 of 9 unrelated/gibberish queries still matched something) |

**Recall is perfect in this sample** — no genuinely relevant query was ever
wrongly starved of evidence. **Precision is poor** — the large majority of
clearly-unrelated or gibberish queries in this sample still returned at
least one real, eligible KB row rather than a clean zero.

This is a broader, more systematic version of the single `HL-POST-010`
anecdote noted in the prior pass — not new in kind, but now quantified.

## Why a simple threshold raise is not a defensible fix

| | Scores observed |
|---|---|
| True-positive top scores (9 cases) | 0.2656, 0.28, 0.2823, 0.2917, 0.3846, 0.5, 0.5556, 0.6364, 0.7965 |
| False-positive top scores (8 cases) | 0.1264, 0.1333, 0.1463, 0.1667, 0.1765, 0.1944, 0.2245, **0.325** |

**The distributions overlap**: the highest false-positive score (0.325, for
*"What is the capital of France?"* against `HL-TTC-001`) exceeds the lowest
true-positive score (0.2656, for a genuine Fiqh paraphrase). No single
cutoff value can separate these two classes cleanly in this dataset — any
threshold high enough to exclude the France false positive would also
exclude that genuine true positive.

That said, the overlap is narrow: **7 of the 8 false positives score below
0.2656** (the lowest true positive). Raising the floor from `0.12` to
somewhere in the `~0.20–0.26` range would, *on this specific sample*,
eliminate 7 of 8 measured false positives at zero measured recall cost —
a real, partial, evidence-backed improvement, just not a complete fix.

## Decision: threshold left unchanged this pass

Per the explicit instruction to change the threshold only when the measured
dataset demonstrates a defensible improvement, and to leave it unchanged and
document the result otherwise: **the threshold is not changed in this
pass.** Reasoning:

1. Even the best achievable cutoff in this sample does not fully solve the
   problem (one clear false positive remains above any viable line).
2. **22 hand-authored, English-only queries is not a large or representative
   enough sample to confidently retune a single global parameter** that
   gates every future query in both Arabic and English, across phrasings
   this study never tested. A threshold chosen to fit 22 synthetic cases
   risks introducing false negatives on real user phrasing this sample
   never covers — exactly the failure mode the instruction warns against
   overfitting to.
3. This is consistent with the architecture-level nuance already flagged:
   a single trigram-similarity threshold has a structural ceiling for short
   queries with generic sentence structure (the France question scores
   higher than several genuine paraphrases largely on function-word/
   sentence-shape overlap, not topical content) — no single number will
   fully separate this class of confusion.

## Recommendation (not implemented this pass — architecture/founder decision)

An explicit minimum-relevance or gibberish-detection gate, separate from
(and prior to) the similarity ranking, is architecturally more promising
than continuing to tune one threshold — for example: a minimum
distinctive-term overlap check, a length/entropy-based gibberish filter, or
a semantic (embedding-based) relevance re-ranker ahead of the trigram score.
**This is a new architectural component, not an ordinary implementation
fix** — per this pass's own stop conditions, it requires founder/
architecture sign-off before being designed or built, and is recorded as
such rather than implemented unilaterally here.

## A distinct, secondary finding: ranking quality for genuine matches

Independent of the false-positive question: for `H-REL-02`
("What if my period lasts more than eight days?"), the single most
topically exact atom (`HL-MENS-003`, whose canonical statement is literally
about an eight-day period-length threshold) ranked **4th** (score 0.2787),
behind `HL-WELL-002` (0.2917, a wellbeing/mood row) and two others. The
correct atom is still within the 10 items handed to the model — so this
does not currently break the trust boundary — but it means the *most*
relevant evidence is not reliably the *first* evidence the model sees for
every query, which matters if a future change reduces `limit` or if the
model exhibits position bias toward earlier context. Recorded as a
secondary, lower-severity observation; not a blocker.

## What this does not affect

No fail-closed row was ever returned in this study (nothing quarantined
appeared in any `all_atoms` list). No Madhhab boundary was crossed. The
false positives are all real, `PRODUCTION_ELIGIBLE`, correctly-domain-tagged
rows — this is a precision/relevance-quality finding, not a trust-boundary
violation.
