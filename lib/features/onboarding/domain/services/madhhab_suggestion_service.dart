import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../../../../core/data/iso_countries.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;

/// How confident a geographic suggestion is. Never treated as a substitute
/// for the user's own knowledge or an explicit statement of fact.
enum MadhhabSuggestionConfidence { high, medium, low, unresolved }

/// The result of asking "what madhhab is commonly followed where this user
/// lives?" — always a SUGGESTION, never a declaration. See
/// production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json
/// for the underlying data this mirrors (kept in sync by hand; both files
/// are draft, `NOT_REVIEWED` by a qualified scholar — see that file's own
/// `_meta.warning`).
class MadhhabSuggestion {
  const MadhhabSuggestion({
    required this.confidence,
    this.likelyMadhahib = const [],
    this.regionNote,
    this.mappingId,
    this.evidenceSourceIds = const [],
    this.evidenceStatus,
  });

  final MadhhabSuggestionConfidence confidence;

  /// One entry = a single confident suggestion. More than one entry means
  /// the region genuinely has multiple commonly-followed madhahib and the
  /// UI must present all of them, not silently pick the first.
  final List<Madhhab> likelyMadhahib;

  /// A short, honest explanation shown alongside the suggestion (e.g. "This
  /// madhhab is commonly followed in your region") — never phrased as a
  /// statement of the user's own madhhab.
  final String? regionNote;

  /// Traces back to `geographic_madhhab_mapping.json`'s own `mapping_id` —
  /// lets a future scholar-review pass (or a support/debugging need) find
  /// exactly which entry produced a given suggestion. `null` for
  /// [MadhhabSuggestionConfidence.unresolved].
  final String? mappingId;

  /// Mirrors the source JSON's `source_ids` — may be empty even
  /// for a resolved suggestion (several seed entries have none yet); never
  /// fabricated when absent.
  final List<String> evidenceSourceIds;

  /// Mirrors the source JSON's `evidence_status` (e.g. `'SOURCE_VERIFIED'`)
  /// — surfaced so a future UI/report can honestly disclose the tier of
  /// trust behind a given suggestion (internet-source-verified vs. an
  /// actual qualified scholar's sign-off) without needing to re-derive
  /// that from the JSON file directly. Per the governance model (Knowledge-
  /// Base Source-Verification wave, 2026-10-13), this is never surfaced to
  /// the end user as a certainty claim either way — see
  /// [_MadhhabGeographicSuggestionStep] in madhhab_resolution_flow.dart,
  /// whose wording is identical regardless of which of the two eligible
  /// statuses produced the suggestion.
  final String? evidenceStatus;

  bool get isResolved => confidence != MadhhabSuggestionConfidence.unresolved;

  static const unresolved = MadhhabSuggestion(
    confidence: MadhhabSuggestionConfidence.unresolved,
  );
}

class _MappingEntry {
  const _MappingEntry({
    required this.mappingId,
    required this.countryCode,
    required this.countryNameEn,
    this.region,
    required this.madhahib,
    required this.confidence,
    this.evidenceSourceIds = const [],
    this.evidenceStatus = 'UNVERIFIED',
  });

  final String mappingId;

  /// ISO 3166-1 alpha-2 code — the value actually matched on. Replaces
  /// the previous fragile English-display-name string comparison, which
  /// could never fail to match for a spelling/case variant since it no
  /// longer compares strings at all for the country itself (region/city
  /// matching below is unaffected — no ISO-3166-2 subdivision list exists
  /// in this codebase yet).
  final String countryCode;

  /// Display-only English name, used solely for [MadhhabSuggestion
  /// .regionNote] text and [MadhhabSuggestionService.supportedCountries]
  /// — never compared against for matching.
  final String countryNameEn;
  final String? region;
  final List<Madhhab> madhahib;
  final MadhhabSuggestionConfidence confidence;
  final List<String> evidenceSourceIds;

  /// Mirrors `geographic_madhhab_mapping.json`'s own per-entry
  /// `evidence_status` field exactly — a real per-entry value (not a
  /// blanket constant), so each entry can independently progress through
  /// the 4-state model (Knowledge-Base Source-Verification wave,
  /// 2026-10-13, replacing the prior binary NOT_REVIEWED/APPROVED model):
  ///   - `'UNVERIFIED'` — the starting state for every entry; AI-drafted
  ///     from general knowledge, not yet checked against real sources.
  ///   - `'SOURCE_VERIFIED'` — independently checked against real,
  ///     reputable public sources (government/academic/encyclopedic/
  ///     major institutional reports) that explicitly support the specific
  ///     madhhab claim, per the wave's documented evidence threshold. This
  ///     is NOT the same as scholar approval, and is never described to
  ///     the user as such.
  ///   - `'SCHOLAR_REVIEWED'` — an actual qualified Islamic scholar has
  ///     reviewed and approved this specific entry (via
  ///     scripts/ingest_geo_madhhab_review.py, never by hand-editing this
  ///     field).
  ///   - `'REJECTED'` — a scholar actively reviewed and rejected this
  ///     entry (also only ever set via that script).
  /// Defaults to `'UNVERIFIED'` because that's what every entry in the
  /// dataset started as before this wave's research pass; entries this
  /// wave's research genuinely verified against real sources are
  /// constructed below with `evidenceStatus: 'SOURCE_VERIFIED'` explicitly.
  final String evidenceStatus;

  /// The actual trust gate: only `'SOURCE_VERIFIED'` or `'SCHOLAR_REVIEWED'`
  /// may ever produce a displayed suggestion — `'UNVERIFIED'` and
  /// `'REJECTED'` both resolve to [MadhhabSuggestion.unresolved], exactly
  /// like a country absent from the mapping entirely. This does not
  /// change any entry's underlying confidence/madhahib/evidence data; it
  /// only changes whether `suggest()` is willing to surface a match it
  /// already found.
  ///
  /// [MadhhabSuggestionService.debugApprovedMappingIdsForTesting] is
  /// consulted as a second, test-only path to eligible — it lets a test
  /// exercise the real positive path (an eligible entry actually
  /// surfacing through the real `suggest()`) without ever marking a real
  /// entry `'SOURCE_VERIFIED'`/`'SCHOLAR_REVIEWED'` in the dataset itself.
  ///
  /// Gated on `kDebugMode` (launch-readiness audit, 2026-10-15): `@visibleForTesting`
  /// is an analyzer lint, not a runtime guard, so without this the set
  /// would still be a reachable (if normally-empty) seam in a release
  /// binary. `kDebugMode` is a compile-time constant that is `false` in
  /// release builds, so the Dart compiler eliminates this whole branch —
  /// `debugApprovedMappingIdsForTesting` cannot affect `suggest()`'s
  /// output in release at all, matching the pattern already used by
  /// `BuildInfo.diagnosticsEnabled`/`acceptanceMode`.
  bool get isEligibleForDisplay =>
      evidenceStatus == 'SOURCE_VERIFIED' ||
      evidenceStatus == 'SCHOLAR_REVIEWED' ||
      (kDebugMode &&
          MadhhabSuggestionService.debugApprovedMappingIdsForTesting.contains(
            mappingId,
          ));
}

/// Suggests a likely madhhab (or madhahib) from residence signals, per the
/// Source Governance wave's explicit rules — never a declaration:
///
/// - An explicit country/city (the user directly stated it) always outranks
///   a phone-country-prefix signal.
/// - A phone-country-prefix alone is NEVER treated as proof of residence or
///   madhhab — it is the weakest signal this service accepts, and is only
///   used when no explicit country/city was given.
/// - Multi-madhhab regions return every plausible option, not one.
/// - Anything this pass's draft mapping marks low-confidence, any
///   country/region not in the mapping at all, OR any entry whose
///   `reviewer_status` isn't `'APPROVED'` (adversarial review, 2026-10-07
///   — every entry today, without exception) resolves to `unresolved` —
///   never a guessed default, and never an unreviewed mapping presented
///   as if it were a normal recommendation. Country-based selection
///   never blocks onboarding and never prevents a manual pick either
///   way — this only decides whether a suggestion *badge* is shown.
/// - The caller is responsible for requiring explicit user confirmation
///   before treating any returned suggestion as the user's actual madhhab;
///   this service only ever produces a suggestion, never a stored fact.
class MadhhabSuggestionService {
  const MadhhabSuggestionService();

  /// Mirrors `geographic_madhhab_mapping.json`'s own `_meta.last_expanded`
  /// — bump this alongside that file whenever the dataset changes, so a
  /// future scholar-review pass (or a support report) can always name
  /// which version of the mapping produced a given suggestion.
  static const datasetVersion = '2026-10-12';

  /// Test-only: mapping ids temporarily treated as if their
  /// `reviewer_status` were `'APPROVED'` — lets a test prove the real
  /// positive path ("an approved entry surfaces a real suggestion")
  /// against the real dataset and the real [suggest] method, without
  /// ever marking a real entry approved in production. Always empty
  /// outside a test; any test that sets this must clear it afterwards
  /// (e.g. in `tearDown`) so it can never leak into another test.
  @visibleForTesting
  static Set<String> debugApprovedMappingIdsForTesting = {};

  /// Every country *drafted* in this mapping (medium confidence or
  /// higher) — exposed for an inventory report/future-reviewer view of
  /// coverage. Not a claim that any of these currently produce a
  /// displayed suggestion: `suggest()` additionally requires
  /// `reviewer_status == 'APPROVED'` (adversarial review, 2026-10-07),
  /// which no entry here has yet — see `suggest` and
  /// `_MappingEntry.isApprovedForDisplay`.
  static List<String> get supportedCountries => _mapping
      .map((entry) => entry.countryNameEn)
      .toSet()
      .toList(growable: false);

  // Mirrors production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json
  // (only entries that file's own `classification` field marks
  // "country_level" or "region_level" — i.e. a single, or small
  // co-dominant set of, well-documented predominant madhhab. Entries
  // classified "mixed_heterogeneous" or "insufficient_evidence" (no
  // safe single-madhhab recommendation — majority-Shia/Ibadi
  // populations, confessionally mixed countries, heterogeneous
  // diaspora populations, or a genuinely split Sunni population) are
  // intentionally omitted here since this service always resolves
  // those to unresolved anyway; see that file for the complete draft,
  // including every excluded entry's full evidence/caveats, kept
  // there for reviewer visibility).
  static const List<_MappingEntry> _mapping = [
    _MappingEntry(
      mappingId: 'GEO-001',
      countryCode: 'EG',
      countryNameEn: 'Egypt',
      madhahib: [Madhhab.shafii, Madhhab.hanafi, Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
      evidenceSourceIds: ['SRC-INST-001'],
    ),
    _MappingEntry(
      mappingId: 'GEO-002',
      countryCode: 'SA',
      countryNameEn: 'Saudi Arabia',
      madhahib: [Madhhab.hanbali],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
      evidenceSourceIds: ['SRC-INST-002'],
    ),
    _MappingEntry(
      mappingId: 'GEO-003',
      countryCode: 'TR',
      countryNameEn: 'Turkey',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-004',
      countryCode: 'PK',
      countryNameEn: 'Pakistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-005b',
      countryCode: 'IN',
      countryNameEn: 'India',
      region: 'Kerala',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-006',
      countryCode: 'MA',
      countryNameEn: 'Morocco',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
      evidenceSourceIds: ['SRC-INST-001'],
    ),
    _MappingEntry(
      mappingId: 'GEO-007',
      countryCode: 'TN',
      countryNameEn: 'Tunisia',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-008',
      countryCode: 'DZ',
      countryNameEn: 'Algeria',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-009',
      countryCode: 'ID',
      countryNameEn: 'Indonesia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-010',
      countryCode: 'MY',
      countryNameEn: 'Malaysia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
      evidenceSourceIds: ['JUR-MY-001'],
    ),
    // Afghanistan was previously absent from this mapping entirely (not a
    // name-matching bug) — onboarding would silently fall through to
    // `unresolved` for every Afghan user. Hanafi is the well-established
    // historical/institutional majority madhhab in Afghanistan; this
    // carries the same draft/NOT_REVIEWED disclosure as every other entry
    // above, not a new or more confident jurisprudential claim.
    _MappingEntry(
      mappingId: 'GEO-014',
      countryCode: 'AF',
      countryNameEn: 'Afghanistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),

    // Knowledge-Base Completion wave (2026-10-12): expanded from the
    // original 10-country/1-region seed to every country
    // geographic_madhhab_mapping.json classifies `country_level` or
    // `region_level` (a single, or small co-dominant set of, well-
    // documented predominant madhhab) — covering the full set of
    // Muslim-majority countries plus India (already present above),
    // per the same product-relevance precedent. Countries that file
    // classifies `mixed_heterogeneous` or `insufficient_evidence` (no
    // safe single-madhhab recommendation — e.g. UAE/Nigeria above,
    // or a majority-Shia/Ibadi/diaspora population) are intentionally
    // NOT mirrored here, exactly matching this list's long-standing
    // convention for low-confidence entries: seeing one here and
    // getting a displayed suggestion are still two separate gates
    // (confidence/presence here, AND `reviewer_status == 'APPROVED'`)
    // — every entry remains `NOT_REVIEWED`, so none of these change
    // today's live behavior; they exist so a future scholar-approval
    // pass has a complete, ready-to-activate draft rather than an
    // empty one. See that file for full evidence notes/caveats.
    _MappingEntry(
      // CORRECTED 2026-10-12: Yemen was previously `low` confidence with
      // likely_madhahib: [shafii, hanafi] — the "hanafi" was an evidence
      // error (conflating the north's Zaydi Shia minority with Sunni
      // Hanafi; Zaydism is its own independent Shia legal tradition, not
      // a Hanafi variant). Corrected to Shafi'i only, which is genuinely
      // the majority among Yemen's Sunni population (~two-thirds of the
      // country) — see geographic_madhhab_mapping.json GEO-013 for the
      // full correction note.
      mappingId: 'GEO-013',
      countryCode: 'YE',
      countryNameEn: 'Yemen',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-015',
      countryCode: 'JO',
      countryNameEn: 'Jordan',
      madhahib: [Madhhab.shafii, Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-016',
      countryCode: 'PS',
      countryNameEn: 'Palestine',
      madhahib: [Madhhab.shafii, Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-017',
      countryCode: 'SY',
      countryNameEn: 'Syria',
      madhahib: [Madhhab.shafii, Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-018',
      countryCode: 'LY',
      countryNameEn: 'Libya',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-019',
      countryCode: 'MR',
      countryNameEn: 'Mauritania',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-020',
      countryCode: 'QA',
      countryNameEn: 'Qatar',
      madhahib: [Madhhab.hanbali],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
      evidenceSourceIds: ['SRC-INST-003'],
    ),
    _MappingEntry(
      mappingId: 'GEO-021',
      countryCode: 'ML',
      countryNameEn: 'Mali',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-022',
      countryCode: 'NE',
      countryNameEn: 'Niger',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-023',
      countryCode: 'SN',
      countryNameEn: 'Senegal',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-024',
      countryCode: 'GM',
      countryNameEn: 'Gambia',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-025',
      countryCode: 'GN',
      countryNameEn: 'Guinea',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-026',
      countryCode: 'GW',
      countryNameEn: 'Guinea-Bissau',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-027',
      countryCode: 'SL',
      countryNameEn: 'Sierra Leone',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-028',
      countryCode: 'TD',
      countryNameEn: 'Chad',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-029',
      countryCode: 'BF',
      countryNameEn: 'Burkina Faso',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-030',
      countryCode: 'SO',
      countryNameEn: 'Somalia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-031',
      countryCode: 'DJ',
      countryNameEn: 'Djibouti',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.high,
    ),
    _MappingEntry(
      mappingId: 'GEO-032',
      countryCode: 'KM',
      countryNameEn: 'Comoros',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-034',
      countryCode: 'BD',
      countryNameEn: 'Bangladesh',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-035',
      countryCode: 'BN',
      countryNameEn: 'Brunei',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-036',
      countryCode: 'MV',
      countryNameEn: 'Maldives',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-037',
      countryCode: 'KZ',
      countryNameEn: 'Kazakhstan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-038',
      countryCode: 'KG',
      countryNameEn: 'Kyrgyzstan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-039',
      countryCode: 'TJ',
      countryNameEn: 'Tajikistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-040',
      countryCode: 'TM',
      countryNameEn: 'Turkmenistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-041',
      countryCode: 'UZ',
      countryNameEn: 'Uzbekistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.high,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-042',
      countryCode: 'BA',
      countryNameEn: 'Bosnia and Herzegovina',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
    _MappingEntry(
      mappingId: 'GEO-043',
      countryCode: 'AL',
      countryNameEn: 'Albania',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceStatus: 'SOURCE_VERIFIED',
    ),
  ];

  /// [explicitCountryCode]: an ISO 3166-1 alpha-2 code the caller already
  /// has in hand (e.g. from an [IsoCountry] picker) — the preferred,
  /// robust way to identify a country; matched directly, never degraded
  /// to a display-name string comparison.
  /// [explicitCountry]/[explicitCity]: free-text, e.g. from onboarding's
  /// legacy text field. [explicitCountry] is resolved to a code via a
  /// reverse lookup against [kIsoCountries] (case-insensitive, either
  /// language) before matching — this makes a typed English or Arabic
  /// country name just as reliable as passing a code directly, closing
  /// the gap this free-text path used to have.
  /// [phonePrefixCountry]: a country name/guess derived only from a phone
  /// number's country-calling-code prefix — the weakest possible signal,
  /// used only when no explicit country/city is available, and never
  /// returned as if it were an explicit signal. Resolved the same way as
  /// [explicitCountry].
  MadhhabSuggestion suggest({
    String? explicitCountryCode,
    String? explicitCountry,
    String? explicitCity,
    String? phonePrefixCountry,
  }) {
    final code =
        _normalizedCode(explicitCountryCode) ??
        _resolveCodeFromName(explicitCountry) ??
        _resolveCodeFromName(phonePrefixCountry);
    if (code == null) return MadhhabSuggestion.unresolved;

    final city = explicitCity?.trim();

    // City-level entries (if any) take priority over the country-level
    // entry for the same country — e.g. Kerala vs. the rest of India.
    if (city != null && city.isNotEmpty) {
      for (final entry in _mapping) {
        if (entry.region != null &&
            entry.countryCode == code &&
            _sameRegion(entry.region!, city)) {
          // Trust gate: a match was found, but an UNVERIFIED/REJECTED
          // mapping must never be presented as a normal Madhhab
          // recommendation — resolve to `unresolved` exactly as if no
          // entry existed at all, so every existing "no suggestion
          // available" UI path (manual picker, never blocks) handles
          // this identically, with no new state to add.
          if (!entry.isEligibleForDisplay) return MadhhabSuggestion.unresolved;
          return MadhhabSuggestion(
            confidence: entry.confidence,
            likelyMadhahib: entry.madhahib,
            regionNote:
                'This madhhab is commonly followed in ${entry.region}, ${entry.countryNameEn}.',
            mappingId: entry.mappingId,
            evidenceSourceIds: entry.evidenceSourceIds,
            evidenceStatus: entry.evidenceStatus,
          );
        }
      }
    }

    for (final entry in _mapping) {
      if (entry.region == null && entry.countryCode == code) {
        if (!entry.isEligibleForDisplay) return MadhhabSuggestion.unresolved;
        return MadhhabSuggestion(
          confidence: entry.confidence,
          likelyMadhahib: entry.madhahib,
          regionNote:
              'This madhhab is commonly followed in ${entry.countryNameEn}.',
          mappingId: entry.mappingId,
          evidenceSourceIds: entry.evidenceSourceIds,
          evidenceStatus: entry.evidenceStatus,
        );
      }
    }

    return MadhhabSuggestion.unresolved;
  }

  String? _normalizedCode(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    return trimmed.isEmpty ? null : trimmed.toUpperCase();
  }

  /// Reverse-looks-up a free-text country name (English or Arabic,
  /// case-insensitive) against [kIsoCountries] to find its code — the
  /// mechanism that lets the legacy free-text [explicitCountry]/
  /// [phonePrefixCountry] parameters resolve just as reliably as a
  /// caller-supplied code, without this service re-implementing its own
  /// separate name list.
  String? _resolveCodeFromName(String? name) {
    if (name == null) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    for (final country in kIsoCountries) {
      if (country.nameEn.toLowerCase() == lower || country.nameAr == trimmed) {
        return country.code;
      }
    }
    return null;
  }

  bool _sameRegion(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Onboarding fixes wave (2026-10-11), Part 3: the regions (if any) the
  /// reviewed mapping says materially affect the recommendation for
  /// [countryCode] — empty when the country alone is sufficient. Purely
  /// data-driven from [_mapping]: a future region-level entry changes
  /// this automatically, so the UI never needs to hardcode which
  /// countries ask a follow-up region question.
  List<String> regionsFor(String countryCode) {
    final code = _normalizedCode(countryCode);
    if (code == null) return const [];
    return _mapping
        .where((entry) => entry.countryCode == code && entry.region != null)
        .map((entry) => entry.region!)
        .toSet()
        .toList(growable: false);
  }
}
