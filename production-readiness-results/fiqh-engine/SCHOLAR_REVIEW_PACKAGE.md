# Niswah — Scholar Review Package

**For a qualified Islamic scholar/reviewer. No engineering background required to read this document.**

This package exists because Niswah (a bilingual Arabic/English menstrual-cycle and pregnancy tracking app with Islamic worship-obligation guidance) has built a working *engineering* system for classifying a user's prayer/fasting-relevant state by madhhab — but every specific religious value in it was written by engineers referencing general knowledge, not confirmed against primary Islamic texts by a scholar. **Nothing in this app should be treated as religiously authoritative until you review it.** This document is our request for that review, organized so you don't need to read any code.

---

## 1. What the app currently does (in plain terms)

A user selects one of four madhhab (Hanafi, Maliki, Shafi'i, Hanbali) — or, in a not-yet-shipped design (see §3), may say she doesn't know hers. She logs her bleeding day by day. The app then tells her, based on her selected madhhab's rules, whether she is currently in a state of menstruation (haid), purity (tuhr), or an ambiguous state needing a scholar's guidance (`needsAdvisory`) — which in turn implies whether she is expected to pray and fast. The app also has an AI chat feature ("Fiqh Advisor") meant to explain these classifications and answer general fiqh questions, grounded in trusted sources rather than its own unaided judgment.

**The honest state of things right now**: the *engineering* (does the code correctly apply whatever numbers it's given, consistently, without mixing up madhahib) has been tested and is sound. The *numbers themselves* (how many days/hours count as minimum/maximum menstruation, etc.) are engineering's best understanding of common textbook positions — not yet checked against a primary source by anyone qualified to do so. That's what we're asking you to do.

## 2. Source hierarchy (draft)

Full machine-readable version: `fiqh_source_registry.json`. In summary, for each madhhab we've listed 2-3 well-known, real reference works that a comparative-fiqh curriculum would typically cite (e.g. Hanafi: *Al-Hidayah*, *Radd al-Muhtar*; Maliki: *Al-Mudawwana*, *Mukhtasar Khalil*; Shafi'i: *Al-Umm*, *Minhaj al-Talibin*; Hanbali: *Al-Mughni*, *Kashaf al-Qina*) — by title and author only. **We did not attempt to cite a specific chapter or page**, because no one on this engineering pass had verified access to confirm one, and a wrong page citation would misrepresent a real book. If you have direct access to any of these (or prefer different/better sources), please tell us which passages actually support or contradict what's below.

We also listed a handful of national fatwa institutions (Dar al-Ifta Egypt, Saudi Arabia's Permanent Committee, Turkey's Diyanet, etc. — see `jurisdiction_source_registry.json`) as a starting point for a future "your country's guidance" feature, described further in §3.

## 3. Four-madhhab rule matrix

Full version with code locations: `fiqh_rule_source_matrix.md`. The four numeric rules currently implemented:

| What | Hanafi | Maliki | Shafi'i | Hanbali |
|---|---|---|---|---|
| Minimum haid duration | 3 days (72h) | 1 day (24h) | 1 day (24h) | 1 day (24h) |
| Maximum haid duration | 10 days (240h) | 15 days | 15 days | 15 days |
| Minimum purity before a new haid is confirmed | 15 days | 15 days (not currently enforced by the app for this madhhab — flagged below) | 15 days (same flag) | 15 days (same flag) |
| Personal-habit ('adah) tracking | Not modeled | Modeled (informational only) | Not modeled | Not modeled |

**Two things we'd specifically like your judgment on**:
- The 15-day minimum-purity rule is only actually *enforced* by the app for Hanafi users today — Maliki/Shafi'i/Hanbali users have the same number computed but it doesn't currently block anything. Should it be enforced the same way for all four, or is Hanafi's stricter enforcement here fiqh-appropriate and the others correctly looser?
- Only Maliki users get personal-habit ('adah) tracking. Is that a fair reflection of how the four schools actually differ on this, or is this an engineering oversight that should be extended (or removed)?

## 4. Geographic madhhab suggestion (design, not yet live)

We designed (not yet shipped in the app) a feature for a user who doesn't know her madhhab: if she tells us her country (never inferred from her phone number alone), we can *suggest* a commonly-followed madhhab for that region — always phrased as "this madhhab is commonly followed in your region," never "you are Hanafi." She always has to confirm it herself; nothing is auto-assigned. The draft regional associations (Turkey→Hanafi, Morocco→Maliki, Indonesia→Shafi'i, Saudi Arabia→Hanbali, Egypt→mixed, etc.) are in `geographic_madhhab_mapping.json` — again, general-knowledge draft, not scholarly-confirmed, and several genuinely mixed regions (UAE, India, Yemen, Nigeria) were deliberately left unresolved/multi-option rather than guessed. We'd welcome your correction of any of these, and particularly your view on regions we left blank.

## 5. Golden test cases (12)

Full version: `golden_fiqh_dataset.json`. These are specific, worked examples (e.g. "Hanafi user, bleeding exactly 72 hours, previously pure 20 days — classified `haid`") used to catch code regressions. Four are flagged `disputed_or_ambiguous` for your particular attention:

- **Case 5**: bleeding one minute past the Shafi'i 15-day maximum — currently produces the same generic "needs advisory" result as every other ambiguous case, rather than a distinct istihadah-aware classification. Is that acceptable, or does this specific scenario deserve its own handling?
- **Case 7**: a Maliki user whose bleeding exceeds her own previously-logged personal habit — currently this is shown to her as information only and does not change her classification. Should it?
- **Case 10**: the *same* 30-hour bleeding episode is deliberately run through all four madhahib at once, producing three different classifications (Hanafi says not-yet-haid; the other three say haid) — included specifically so you can check each school's own position is correctly applied to identical facts.
- **Case 11**: documents that postpartum (nifas) status is handled by a completely separate part of the app, not the same engine as menstruation — flagged so you can confirm that separation itself is appropriate.

Every one of the 12 cases is currently `NOT_REVIEWED`. Please mark each `APPROVED`, `REJECTED`, or `REVISION_REQUIRED` with whatever notes you'd like — we will not change engine behavior without your input.

## 6. User-facing fiqh wording

The app's AI features are instructed (in their underlying prompts, not shown to the user) to: never assert a fiqh ruling the app's own deterministic engine didn't produce; always label a user-entered note as "her own statement, not a verified fact"; explicitly say when the app doesn't have enough information rather than guessing; and defer pregnancy, postpartum, irregular-cycle, and other complex cases to "a qualified scholar or fatwa authority" rather than attempting a personalized ruling itself. We adversarially tested this in production this pass (see `fiqh_rule_source_matrix.md`'s Phase G/K notes) — in every test, the AI correctly refused to assert a ruling it wasn't given, refused to silently "update" a user's madhhab, and refused to invent a source when asked to quote a (deliberately fictional, for testing) book. We'd still value your read of the actual prompt wording if you'd like to see it verbatim — ask and we'll provide it.

## 7. Escalation behavior

Every AI feature is designed to say, in substance, "this needs a real scholar" rather than answer definitively whenever: the case involves pregnancy/postpartum/irregular habit transitions/retrospective prayer-or-fasting obligations/danger to health, or whenever the underlying classification wasn't confidently available. The one feature meant to cite real sources for a ruling ("Fiqh Advisor") is currently unable to complete most requests because its search-grounding tool has hit its cloud provider's billing/quota limit (an account-configuration issue on our end, unrelated to your review) — when it can't find a trusted source, it tells the user exactly that and asks her to consult a scholar, rather than guessing. We consider that the correct behavior for now.

## 8. What we're asking of you

1. Correct/confirm the four numeric values in §3 against sources you trust.
2. Weigh in on the two open questions in §3 (purity-rule enforcement asymmetry, Maliki-only habit tracking).
3. Correct/confirm the geographic suggestions in §4, especially the regions we left blank or marked low-confidence.
4. Review and mark each of the 12 cases in §5.
5. Tell us if any user-facing wording (available on request) misrepresents a religious concept.

**We are not asking you to certify the app as religiously complete or launch-ready** — only to review what's here so far. This package itself makes no claim of final religious certification.

---

*Compiled by Claude Code (an AI engineering assistant) during the Source Governance, Madhhab Authority, Jurisdiction Sources, and Fiqh Advisor Grounding wave, 2026-09-09. All source attributions in the supporting files are labeled `AI_RECALLED_UNVERIFIED`/`NOT_REVIEWED` and none have been marked `APPROVED` by this process.*
