# Internet Evidence Audit Summary

## Status: Health/Safety phase re-verified independently. Fiqh phase in progress.

The previous version of this document (and `INTERNET_EVIDENCE_AUDIT.csv`) self-reported
this audit as complete. Per founder instruction (2026-09-29), that self-report was
treated as **unverified** and independently redone from source rather than trusted
as-is, specifically because engineering work (production migration, edge-function
cutover) had already been built on top of it before any independent check occurred.
This document now reflects the independent pass. Findings below are supported by
direct `WebFetch`/`WebSearch` retrieval of the cited pages on 2026-09-29, not by
re-stating the prior self-report.

## Scope completed — Health/Safety (independently re-verified)

- **74 / 74 atoms independently re-verified** by directly fetching all 13 distinct
  primary source pages (`OWH_CYCLE`, `OWH_PERIOD`, `NICHD_MENS`, `CDC_WARN`,
  `OWH_TTC`, `NICHD_INF`, `OWH_STAGES`, `OWH_PRENATAL`, `OWH_PREG_SAFE`,
  `OWH_FOLATE`, `OWH_PRECON`, `OWH_RECOVERY`, `OWH_PPD`) referenced across the atom
  set, plus independent corroborating searches (ACOG, NHS, ASRM, CDC Folic Acid,
  Saudi MOH) for the highest-stakes clusters (cycle-length ranges, infertility
  evaluation timing, folic acid dosing).
- **Result: 70 `VERIFIED`, 4 `VERIFIED_WITH_QUALIFICATION`, 0 `CONFLICT_FOUND`,
  0 `INSUFFICIENT_EVIDENCE`.** Full per-atom trail (proposition, source, URL,
  locator, evidence summary, scope, contradictions, status, confidence, production
  eligibility, reviewer notes) is in `INTERNET_EVIDENCE_AUDIT.csv`.
- The prior pass's 7 wording corrections (`HEALTH_SAFETY_EVIDENCE_CORRECTIONS.csv`)
  were independently checked against source and confirmed **sound** — each
  correction narrowed an original claim to what its source actually supports (e.g.
  removing CDC's pregnancy/postpartum-scoped warning signs as a secondary source for
  general, non-pregnant menstrual atoms; narrowing an overclaimed cervical-mucus/
  ovulation-kit certainty).

### Two real defects this independent pass found that the prior self-report missed

1. **Domain-vocabulary mixing** (now fixed): the prior `INTERNET_EVIDENCE_AUDIT.csv`
   used Fiqh-only status values (`INSTITUTIONALLY_CORROBORATED`,
   `CONFLICT_OR_JUDGMENT_REQUIRED`) on Health rows, where the correct vocabulary is
   `VERIFIED` / `VERIFIED_WITH_QUALIFICATION` / `CONFLICT_FOUND` /
   `INSUFFICIENT_EVIDENCE`. This is exactly the cross-domain evidence-vocabulary
   mixing the KB architecture's domain-separation rule exists to prevent. Corrected
   in the rebuilt file.
2. **Dead source URL** (`HL-PREG-012`, Saudi MOH folic-acid guidance): the URL
   recorded in `SOURCE_REGISTRY_ADDITIONS.csv` for `SAUDI_MOH_PRECON`
   (`.../awarenessplateform/womenshealth/pages/beforepregnancy.aspx`) **times out on
   every attempt** (confirmed via both `WebFetch` and `curl`, exit code 28 —
   connection timeout). The underlying claim is real and independently confirmed —
   via a **different, working** MOH URL found this session:
   `https://www.moh.gov.sa/en/HealthAwareness/EducationalContent/wh/Pages/008.aspx`
   ("Planning for Pregnancy"), which verbatim confirms "400 micrograms (mcg) of
   folic acid... daily before and during pregnancy (until the 12th week)" and "5 mg"
   for epilepsy/diabetes/prior neural-tube-defect pregnancy. **Action required
   before this citation is ever shown to a user: replace the dead URL in
   `SOURCE_REGISTRY_ADDITIONS.csv` with the working one above.**

### Other findings worth tracking (not blocking, not defects in an existing atom)

- **KB completeness gap**: CDC's own "Urgent Maternal Warning Signs" page lists 15
  distinct signs; only 13 are represented across the 74-atom set. Missing: (1)
  severe swelling/redness/pain of a leg or arm up to 6 weeks after birth (a DVT
  warning sign, distinct from `SAFE-012`'s hands/face swelling), and (2)
  overwhelming tiredness unrelieved by sleep. This is a coverage gap in the atom
  set relative to its own cited primary source, not an error in any existing atom's
  proposition — flagged here for whoever scopes the next atom-authoring pass.
- **Genuine, disclosed numeric conflict** (`HL-MENS-002`): OWH states cycles are
  normal at 24–38 days; NICHD states 21–35 days (21–45 for teens); independently
  confirmed via search that ACOG states 21–45 days broadly / 21–35 typical. Three
  authoritative U.S. institutions use three different specific ranges. The atom's
  corrected wording already avoids asserting a bare number without naming its
  source, which is why this is `VERIFIED_WITH_QUALIFICATION` rather than
  `CONFLICT_FOUND` — but any future implementation must preserve that
  source-attribution discipline; a version that surfaces one bare range as if
  universal would not be supported by the evidence.
- **Minor cross-institution boundary-phrasing difference** (`HL-TTC-011`): ASRM
  phrases the age-35 fertility-evaluation exception as "≥35" (inclusive), while
  NICHD and ACOG phrase it as "older than 35" (exclusive). Immaterial for practical
  guidance; noted for completeness since the atom's own wording ("older than 35")
  matches the NICHD/ACOG phrasing exactly.

## Scope in progress — Fiqh

Per the founder's Phase 2 instructions: only the 43 rows currently marked
`SCHOLAR_CLARIFICATION_REQUIRED` (29) or `PARTIAL_EVIDENCE` (14) are being
independently re-audited; the 137 `LOCATOR_VERIFIED` rows are not being redone
unless an actual inconsistency turns up while working through the unresolved set.
Fiqh-appropriate evidence conclusions (`PRIMARY_SOURCE_VERIFIED` /
`INSTITUTIONALLY_CORROBORATED` / `CONFLICT_OR_JUDGMENT_REQUIRED`) are used —
**never** `SCHOLAR_APPROVED`, regardless of source strength. In progress; this
section will be updated on completion.

## Standing trust-boundary facts (apply to both phases)

- Zero rows are labeled `Scholar-Approved` or `Medically-Approved` anywhere in this
  KB. Internet evidence verification is not professional certification.
- Every fail-closed row (Health: none currently; Fiqh: the unresolved subset of the
  43) remains excluded from authoritative AI retrieval regardless of internet
  verification outcome.
- **Open governance concern, unresolved by this audit**: PR #6 already contains
  production engineering (a database migration, a `kb_retrieval.ts` module, and a
  rewrite of `fiqh-advisor-chat`/`dr-niswah-chat` to be KB-first) built on the
  *prior, unverified* self-report, and separately, the review workflow was changed
  from a human-scholar/clinician-approval gate to an evidence-only gate without
  visible founder authorization for either change. Neither is addressed by this
  audit; both remain open pending founder review. See `FOUNDER_DECISIONS.md`.

## Next engineering gate (unchanged, still blocked until Phase 2 completes)

1. Materialize the Health/Safety correction overlay into the canonical production
   candidate set — including the `SAUDI_MOH_PRECON` URL fix above.
2. Build versioned production candidate rows only from evidence-eligible items.
3. Exclude all still-unresolved Fiqh rows from authoritative retrieval.
4. Apply the KB storage schema.
5. Add structured retrieval filters before semantic retrieval.
6. Generate citations from backend metadata, never model-invented text.
7. Connect AI modes under their knowledge contracts — **with founder sign-off on
   the governance-gate and edge-function changes already sitting in PR #6**, since
   those were not authorized as part of this audit.
8. Run real-model acceptance across Madhhab, bleeding state, TTC/pregnancy/
   postpartum, safety escalation, Arabic/English, citations, UNKNOWN Madhhab, and
   insufficient-evidence cases.
