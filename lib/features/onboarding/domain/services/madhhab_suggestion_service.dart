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
    this.reviewerStatus,
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

  /// Mirrors the source JSON's `evidence_source_ids` — may be empty even
  /// for a resolved suggestion (several seed entries have none yet); never
  /// fabricated when absent.
  final List<String> evidenceSourceIds;

  /// Mirrors the source JSON's `reviewer_status` (e.g. `'NOT_REVIEWED'`) —
  /// surfaced so a future UI/report can honestly disclose that no
  /// suggestion in this dataset has been scholar-reviewed yet, without
  /// needing to re-derive that from the JSON file directly.
  final String? reviewerStatus;

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
    this.reviewerStatus = 'NOT_REVIEWED',
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
  /// `reviewer_status` field exactly — a real per-entry value (not a
  /// blanket constant), so a future entry that genuinely gets scholar
  /// sign-off can be marked `'APPROVED'` individually without touching
  /// this field's shape or every other entry. Every entry defaults to
  /// `'NOT_REVIEWED'` because that is what the JSON source of truth
  /// actually says for all fifteen entries today (verified directly
  /// against that file, adversarial review, 2026-10-07) — not an
  /// assumption, and not something this service invents.
  final String reviewerStatus;

  /// The actual trust gate: only an entry explicitly marked `'APPROVED'`
  /// may ever produce a displayed suggestion. Every entry in the dataset
  /// is `'NOT_REVIEWED'` today, so `suggest()` currently resolves to
  /// [MadhhabSuggestion.unresolved] for every country, including the
  /// ones that previously appeared confident (Egypt, Morocco, ...) —
  /// consistent and uniform, not an Afghanistan-specific carve-out. This
  /// does not change any entry's underlying confidence/madhahib/evidence
  /// data; it only changes whether `suggest()` is willing to surface a
  /// match it already found.
  bool get isApprovedForDisplay => reviewerStatus == 'APPROVED';
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

  /// Mirrors `geographic_madhhab_mapping.json`'s own `_meta.generated` —
  /// bump this alongside that file whenever the dataset changes, so a
  /// future scholar-review pass (or a support report) can always name
  /// which version of the mapping produced a given suggestion.
  static const datasetVersion = '2026-09-09';

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
  // (mappings with confidence "medium" or higher only — "low" entries are
  // intentionally omitted here since this service always resolves "low" to
  // unresolved anyway; see that file for the complete draft, including the
  // low-confidence entries kept there for reviewer visibility).
  static const List<_MappingEntry> _mapping = [
    _MappingEntry(
      mappingId: 'GEO-001',
      countryCode: 'EG',
      countryNameEn: 'Egypt',
      madhahib: [Madhhab.shafii, Madhhab.hanafi, Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['SRC-INST-001'],
    ),
    _MappingEntry(
      mappingId: 'GEO-002',
      countryCode: 'SA',
      countryNameEn: 'Saudi Arabia',
      madhahib: [Madhhab.hanbali],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['SRC-INST-002'],
    ),
    _MappingEntry(
      mappingId: 'GEO-003',
      countryCode: 'TR',
      countryNameEn: 'Turkey',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-004',
      countryCode: 'PK',
      countryNameEn: 'Pakistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-005b',
      countryCode: 'IN',
      countryNameEn: 'India',
      region: 'Kerala',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-006',
      countryCode: 'MA',
      countryNameEn: 'Morocco',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
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
    ),
    _MappingEntry(
      mappingId: 'GEO-009',
      countryCode: 'ID',
      countryNameEn: 'Indonesia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-010',
      countryCode: 'MY',
      countryNameEn: 'Malaysia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
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
          // Trust gate (adversarial review, 2026-10-07): a match was
          // found, but an unreviewed mapping must never be presented as
          // a normal Madhhab recommendation — resolve to `unresolved`
          // exactly as if no entry existed at all, so every existing
          // "no suggestion available" UI path (manual picker, never
          // blocks) handles this identically, with no new state to add.
          if (!entry.isApprovedForDisplay) return MadhhabSuggestion.unresolved;
          return MadhhabSuggestion(
            confidence: entry.confidence,
            likelyMadhahib: entry.madhahib,
            regionNote:
                'This madhhab is commonly followed in ${entry.region}, ${entry.countryNameEn}.',
            mappingId: entry.mappingId,
            evidenceSourceIds: entry.evidenceSourceIds,
            reviewerStatus: entry.reviewerStatus,
          );
        }
      }
    }

    for (final entry in _mapping) {
      if (entry.region == null && entry.countryCode == code) {
        if (!entry.isApprovedForDisplay) return MadhhabSuggestion.unresolved;
        return MadhhabSuggestion(
          confidence: entry.confidence,
          likelyMadhahib: entry.madhahib,
          regionNote:
              'This madhhab is commonly followed in ${entry.countryNameEn}.',
          mappingId: entry.mappingId,
          evidenceSourceIds: entry.evidenceSourceIds,
          reviewerStatus: entry.reviewerStatus,
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
}
