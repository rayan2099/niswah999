# Internet Evidence Audit Summary

## Status: Both phases independently re-verified and complete.

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

## Scope completed — Fiqh

Per the founder's Phase 2 instructions: only the 43 rows previously marked
`SCHOLAR_CLARIFICATION_REQUIRED` (29) or `PARTIAL_EVIDENCE` (14) were
independently re-audited (12 Hanafi, 12 Maliki, 11 Shafi'i, 8 Hanbali); the 137
`LOCATOR_VERIFIED` rows were not redone — no inconsistency was found in them while
working through the unresolved set that would have required revisiting them.

**All 43 remain `production_disposition = FAIL_CLOSED`.** Internet verification
never converts a row to `SCHOLAR_APPROVED`, and none of the three Fiqh evidence
conclusions used here (`PRIMARY_SOURCE_VERIFIED`, `INSTITUTIONALLY_CORROBORATED`,
`CONFLICT_OR_JUDGMENT_REQUIRED`) is a form of scholarly sign-off — see
`FIQH_INTERNET_EVIDENCE_AUDIT.csv` for the full per-row trail (madhhab, prior
status, new internet-audit status, disposition, and a reasoned explanation citing
what was independently checked).

**Result: 34 `CONFLICT_OR_JUDGMENT_REQUIRED`, 8 `PRIMARY_SOURCE_VERIFIED`, 1
`INSTITUTIONALLY_CORROBORATED`.**

### Methodology and its real limits

- Primary/secondary citations in this pack are overwhelmingly hosted on
  `islamweb.net`'s library (classical-text digitization of Radd al-Muhtar, Bada'i
  al-Sanai', Mawahib al-Jalil, Hashiyat al-Dasuqi, Al-Majmu', Tuhfat al-Muhtaj,
  Kashshaf al-Qina') plus two citations to the Kuwaiti Fiqh Encyclopedia
  (`content.awqaf.gov.kw`, a genuine 45-volume comparative-fiqh work published by
  Kuwait's Ministry of Awqaf) and one to `ablibrary.net`.
- **`islamweb.net` actively blocks automated fetches from this session** (TLS
  connections are reset at the handshake — confirmed via both the `WebFetch` tool
  and direct `curl`, not a transient failure). Direct page-content verification of
  every `islamweb.net` citation was therefore not possible. Verification instead
  used `WebSearch`, which surfaces Google's own index of these exact pages — for
  every citation checked this way, the search-indexed title and content matched
  the claimed classical work, chapter, and substance exactly (e.g. the exact
  `islamweb.net` URL cited for `SHF-NIFAS-35`'s twins/multiple-births discussion
  appeared in an independent search, confirming Al-Majmu' really does discuss
  "twins born with a time gap" under exactly three named positions, matching the
  row's own claim).
- One citation (`ablibrary.net`, `HNB-TAHARA-11`) was **directly fetched and
  confirmed verbatim** — the strongest-evidenced row in the set.
- The two Kuwaiti Fiqh Encyclopedia PDF citations could not be directly fetched
  (file size exceeds this session's fetch tool's content limit); their existence,
  publisher, and general subject matter were independently confirmed via search,
  but the exact cited page was not re-rendered this pass.
- **No anonymous sites, forums, social media, or AI-summary sites were used as
  primary authority** anywhere in this audit, per the hard constraint.
- The overwhelming majority (34/43) of rows were found, on independent check, to
  genuinely warrant staying fail-closed: their own source material explicitly
  documents multiple named positions, later-authority variants, or classical
  texts that themselves preserve juristic uncertainty (the two `*-TRANS-45`
  mutahayyira/uncertainty rows, one per relevant madhhab, are definitionally about
  *preserving* uncertainty rather than resolving it). This is the correct,
  responsible outcome for genuine areas of classical scholarly disagreement — a
  system correctly flagging "this needs a human scholar to choose a position" is
  functioning as intended, not failing an audit.
- 8 rows were reclassified `PRIMARY_SOURCE_VERIFIED`: in each, the row's own
  material describes a single, undisputed classical position with no competing
  view named, and the only remaining gap is scholar sign-off on the app-facing
  wording (not a sourcing or multiplicity problem). These stay fail-closed for
  production exactly as before — this reclassification only gives a future
  scholar reviewer a clearer signal about which of the 43 rows are likely faster
  reviews versus which require choosing among genuinely disputed positions.
- 1 row (`HNB-TRANS-40`) was reclassified `INSTITUTIONALLY_CORROBORATED`: its
  primary source, the Kuwaiti Fiqh Encyclopedia, explicitly frames the point as
  *ittifaq al-fuqaha* (jurists' consensus) that a woman pure before Fajr owes that
  day's fast — independently corroborated by a second, distinct Hanbali-specific
  commentary. This is the strongest-evidenced row in the unresolved Fiqh set.
- Three rows (`MLK-NIFAS-29`, `SHF-NIFAS-29`, `HNB-NIFAS-29` — pregnancy-loss/nifas
  across three madhahib) explicitly require a **joint scholar-and-medical**
  decision to map classical criteria (discernible human formation in expelled
  tissue) onto modern clinical/gestational terminology. This mapping is out of
  scope for any internet verification pass by design — it is exactly the kind of
  decision the directive reserves for qualified human review, and remains
  `CONFLICT_OR_JUDGMENT_REQUIRED` regardless of how well the underlying classical
  citation verifies.

## Standing trust-boundary facts (apply to both phases)

- Zero rows are labeled `Scholar-Approved` or `Medically-Approved` anywhere in this
  KB. Internet evidence verification is not professional certification.
- Every fail-closed row (Health: none currently; Fiqh: all 43 previously-unresolved
  rows, regardless of their new, more precise internet-audit status) remains
  excluded from authoritative AI retrieval regardless of internet verification
  outcome.
- **Open governance concern, unresolved by this audit**: PR #6 already contains
  production engineering (a database migration, a `kb_retrieval.ts` module, and a
  rewrite of `fiqh-advisor-chat`/`dr-niswah-chat` to be KB-first) built on the
  *prior, unverified* self-report, and separately, the review workflow was changed
  from a human-scholar/clinician-approval gate to an evidence-only gate without
  visible founder authorization for either change. Neither is addressed by this
  audit; both remain open pending founder review. See `FOUNDER_DECISIONS.md`.

## Next engineering gate (both audit phases now complete; gate itself still not cleared)

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
