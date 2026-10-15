# Niswah — Geographic Madhhab Suggestion: Scholar Review Packet

**For a qualified Islamic scholar/reviewer. No engineering background required to read this document.**

This is the dedicated, complete reviewer packet for one specific feature: if a Niswah user says she doesn't know her madhhab, the app can *suggest* one based on where she grew up — always phrased as "this madhhab is commonly followed in your region," never "you are Hanafi." She always has to confirm it herself; nothing is ever auto-assigned. This document, and the two spreadsheets next to it, cover *every* country/region entry behind that feature, not just a handful of examples — see `SCHOLAR_REVIEW_PACKAGE.md` §4 for this feature's place in the wider Niswah fiqh engine, which this packet now supersedes for geographic-suggestion review purposes specifically.

## Before anything else: what this suggestion can and cannot do

**This is advisory only.** The app never assigns, declares, or forces a madhhab on anyone. Whatever you approve here only ever becomes a *suggestion* a user sees — worded as "this madhhab is commonly followed in your region," never "you are Hanafi" — and she still has to tap it herself to accept it. At that exact same screen, she can instead pick any of the other three schools, or choose **لا أعرف (I don't know)**, with no penalty and no extra friction either way. Your review controls whether a suggestion badge is allowed to appear at all for a given country — it never controls what the user is allowed to choose.

## What's here

- **`GEOGRAPHIC_MADHHAB_SCHOLAR_REVIEW_PACKET.csv`** — every entry (59 rows: countries, one region-level override, and a handful of entries where no safe recommendation exists at all), with columns for the proposed madhhab(s), evidence status, confidence, evidence summary, **real sources with titles/publishers/dates/URLs**, contradictory sources (if any), caveats, and blank `reviewer_decision`/`reviewer_name`/`reviewer_date`/`reviewer_notes` columns for you to fill in.
- **`GEOGRAPHIC_MADHHAB_FOCUSED_QA_BATCH.csv`** — the 8 countries the product team has already manually tested end-to-end in the app (Saudi Arabia, Afghanistan, Algeria, Morocco, Pakistan, Turkey, Indonesia, Yemen) — the most product-urgent batch if you can only review one set first.
- **`GEOGRAPHIC_MADHHAB_HIGH_CONFIDENCE_REVIEW_BATCH.csv`** — filtered to the 7 entries already `SOURCE_VERIFIED` at `high` confidence (Mauritania, Somalia, Comoros, Bangladesh, Brunei, Maldives, Uzbekistan) — these already have the strongest real-source backing (a government's own constitution/law, or multiple converging academic sources) and are the fastest to confirm or formally elevate to `SCHOLAR_REVIEWED`.
- **`geographic_madhhab_mapping.json`** — the machine-readable source all three spreadsheets are generated from, if you'd prefer to read it directly, including the full `_source_registry` (70 real sources with titles, publishers, URLs, and whether each was directly read or recovered via a search tool's extraction).

## How to record your decision

Every spreadsheet has the same four reviewer columns, and every row works exactly the same way — no engineering steps, no code, nothing else to install:

- **`reviewer_decision`** — type exactly one of `APPROVE`, `REJECT`, or `REVISE` (all caps, nothing else) into this cell.
  - `APPROVE` — you've checked the sources and the proposed madhhab(s)/confidence are correct; this row is ready to carry your sign-off (`evidence_status` becomes `SCHOLAR_REVIEWED` — a higher, distinct tier from `SOURCE_VERIFIED`, which just means our own internet research found it well-supported; `SCHOLAR_REVIEWED` means an actual qualified scholar, you, confirmed it).
  - `REJECT` — this row should never produce a suggestion, regardless of what it currently proposes or what evidence_status it currently has (e.g. you believe the evidence doesn't actually support any single recommendation, even if our research found real sources for it).
  - `REVISE` — you agree a suggestion is appropriate here, but the specific madhhab(s)/confidence/region split should change. Describe exactly what should change in `reviewer_notes`.
- **`reviewer_name`** / **`reviewer_date`** — who you are and when you reviewed this row (so there's a record of whose judgment a live suggestion rests on).
- **`reviewer_notes`** — anything you'd like engineering to know: a correction, a source you'd cite instead, or just confirmation of your reasoning. (The CSV's `reviewer_notes` column starts pre-filled with OUR research notes for context — feel free to overwrite or add to them.)

Leave a row's `reviewer_decision` blank if you haven't reached it yet — a blank row changes nothing and is never treated as a decision. Your decision is imported back into the dataset only via `scripts/ingest_geo_madhhab_review.py`, never by hand-editing the JSON — this guarantees every live `SCHOLAR_REVIEWED`/`REJECTED` status is traceable to an actual reviewer_name + date.

## Two ways an entry can already be eligible to surface, even before you review it

This is a change from the previous version of this packet: the app's governance model no longer requires every entry to wait for a scholar before it can ever show a suggestion. An entry is eligible once its `evidence_status` is either:

- **`SOURCE_VERIFIED`** — our own team independently checked it against real, reputable public sources (an official government report, a national institution's own constitution/law, or peer-reviewed academic literature — never a blog, forum, or uncited Wikipedia sentence) that explicitly support the specific madhhab claim, per a documented evidence threshold (ideally two independent sources, at least one naming the madhhab itself, not just "Sunni"). **45 of the 59 entries are at this tier today** — see the `sources` column for exactly what was found and directly fetched vs. recovered via a search tool, always labeled honestly either way.
- **`SCHOLAR_REVIEWED`** — an actual qualified Islamic scholar (you) has reviewed and approved it. This is the higher tier your review adds, and it's the only tier this packet exists to help you assign.

Everything else (`UNVERIFIED`, `REJECTED`) never surfaces, regardless of how plausible it looks. **14 entries remain `UNVERIFIED`** — either because real research found and disclosed a genuine gap (e.g. no qualifying source could be found despite real effort — see Tunisia, Libya, Djibouti, Turkmenistan, China), or because the entry is `mixed_heterogeneous`/`insufficient_evidence` by design (no single madhhab should ever be asserted for it at all — see below).

## The four possible classifications

Every entry is one of:

1. **Country-level** — a single madhhab (or small, genuinely co-dominant set) is well-documented as predominant across the whole country (e.g. Saudi Arabia → Hanbali).
2. **Region-level** — the country-level picture alone would be misleading; a specific named sub-region has its own well-documented, distinct predominant madhhab (today, only India/Kerala → Shafi'i, distinct from Hanafi elsewhere in India).
3. **Mixed/heterogeneous** — a Sunni/four-madhhab majority genuinely exists, but no single madhhab (or small set) can honestly be called predominant among it (e.g. the UAE's highly diverse resident population, or Kuwait's Sunni population split across three schools with no clear majority). We deliberately did **not** guess a single answer for these.
4. **Insufficient evidence** — no safe recommendation among the app's four supported madhahib (Hanafi/Maliki/Shafi'i/Hanbali) can be made at all. This covers two very different situations we grouped together only because the app's outcome is the same for both: (a) the population's actual majority tradition is outside these four schools entirely — Shia/Jafari-majority countries (Iran, Iraq, Bahrain, Azerbaijan), Ibadi-majority Oman, or a country with no single confessional majority at all (Lebanon); and (b) a large-Muslim-population/diaspora country (United States, United Kingdom, Canada, France, Germany, Australia, China) where "where did you grow up" is simply too weak a signal about an individual's family religious origin to guess from, regardless of national statistics.

## What we're specifically asking of you

For each row, in either spreadsheet:

1. **Check the sources** listed (titles, publishers, dates, and real URLs — click through to them) and confirm or correct the proposed madhhab(s) and confidence level.
2. Where we marked something `mixed_heterogeneous` or `insufficient_evidence`, tell us if you disagree — e.g. if you believe a safe single recommendation actually *can* be made for one of these, or conversely if you think one of our `SOURCE_VERIFIED` entries is actually too uncertain to carry your sign-off as-is.
3. Mark `reviewer_decision` as `APPROVE`, `REJECT`, or `REVISE` (with your correction in `reviewer_notes`) for each row you review.
4. Flag anything we got factually wrong. Two corrections already made this pass, for your awareness:
   - Yemen's entry previously listed "Hanafi" as a secondary madhhab for the north, mischaracterizing the region's Zaydi Shia population (a distinct Shia legal tradition, not a Hanafi variant) — corrected to Shafi'i only.
   - Sudan's entry previously proposed "Maliki and/or Shafi'i" as genuinely disputed; real research found the actual, better-evidenced disagreement is Maliki (the historically dominant population madhhab, per one academic source) versus Hanafi (a colonial-era Egyptian administrative import) — "shafii" was removed, since no source was found tying it to Sudan specifically.
   If you find a similar error elsewhere, please say so.
5. If you have better sourcing than what we found — especially a specific national fatwa institution's own stated position, or access to a paywalled reference work we couldn't open (several are named explicitly in the CSV's `reviewer_notes`, e.g. the Oxford Encyclopedia of the Islamic World's Burkina Faso entry) — please tell us; we'd rather cite your source than our own research.

## Known limitations and open questions, flagged rather than hidden

- **Western Sahara and Kosovo** are not covered — the app's own country picker doesn't list them as selectable countries yet.
- **Iraq's Kurdistan Region**: real research this pass found multiply-corroborated academic/encyclopedic sourcing (a 1998 Utrecht University paper, Encyclopaedia Britannica, Minority Rights Group International, all independently converging) that ethnic Kurds generally — including Iraqi Kurds — are predominantly Shafi'i, distinct from Hanafi Arabs/Turks. We deliberately did **not** add a "Kurdistan Region, Iraq" entry on this basis: there is no census statistic, and the Kurdistan Region itself has real Yazidi, Assyrian Christian, Shabak, Kaka'i, and Shia Turkmen populations that a region-level population claim would need to account for. This is the single most promising candidate for a new region-level entry in the whole dataset — we'd specifically value your judgment on whether the evidence clears your bar.
- **Tajikistan's Gorno-Badakhshan (Pamir) region** is predominantly Ismaili Shia, distinct from the rest of the country — kept as a caveat on Tajikistan's entry rather than a separate region-level override, for the same reason as Iraq above.
- **France (GEO-056)** has the strongest diaspora-origin skew we found (secondary sources suggest ~70-80% combined Algerian/Moroccan/Tunisian origin, stronger than the UK's or Germany's equivalent skew) but stays `UNVERIFIED`/`insufficient_evidence` like the other diaspora entries, since the exact percentages rest on secondary sources, not an independently-pulled primary table. This is the closest call among the diaspora entries for whether "too weak a signal for an individual" is still the right call — flagged specifically for your view.
- We considered and excluded Côte d'Ivoire and Eritrea as too genuinely borderline on the "Muslim-majority" threshold itself (see `geographic_madhhab_mapping.json`'s `excluded_borderline_cases`).

---

*Compiled by Claude Code (an AI engineering assistant). Originally drafted during the Source Governance wave (2026-09-09, 13-country/1-region seed) and the Knowledge-Base Completion wave (2026-10-12, expanded to full Muslim-majority + product-relevant coverage, all entries `NOT_REVIEWED`/no real sourcing attempted yet). This version reflects the Knowledge-Base Source-Verification wave (2026-10-14): real internet research against public sources, with every source honestly labeled as directly-fetched-and-quoted or recovered-via-search-tool-extraction, upgraded 45 of 59 entries to `SOURCE_VERIFIED` (internet-source-verified, not scholar-approved) and corrected two factual errors (Yemen, Sudan). No entry has been marked `SCHOLAR_REVIEWED` or `REJECTED` by this process — those tiers exist only for your actual sign-off, via `scripts/ingest_geo_madhhab_review.py`.*
