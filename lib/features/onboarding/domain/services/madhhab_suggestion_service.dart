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
    required this.country,
    this.region,
    required this.madhahib,
    required this.confidence,
    this.evidenceSourceIds = const [],
  });

  final String mappingId;
  final String country;
  final String? region;
  final List<Madhhab> madhahib;
  final MadhhabSuggestionConfidence confidence;
  final List<String> evidenceSourceIds;

  // Every seed entry in geographic_madhhab_mapping.json is currently
  // 'NOT_REVIEWED' without exception — no entry has been scholar-reviewed
  // yet, so there is nothing to make settable per-entry until that changes.
  String get reviewerStatus => 'NOT_REVIEWED';
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
/// - Anything this pass's draft mapping marks low-confidence, or any
///   country/region not in the mapping at all, resolves to `unresolved` —
///   never a guessed default.
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

  /// Every country name this service can resolve *something* for (medium
  /// confidence or higher — the only tier that ever resolves) — exposed so
  /// callers/tests/an inventory report can enumerate real coverage without
  /// re-deriving it from `suggest()`'s own control flow. Not a claim that
  /// every listed country resolves to exactly one madhhab — see `suggest`.
  static List<String> get supportedCountries =>
      _mapping.map((entry) => entry.country).toSet().toList(growable: false);

  // Mirrors production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json
  // (mappings with confidence "medium" or higher only — "low" entries are
  // intentionally omitted here since this service always resolves "low" to
  // unresolved anyway; see that file for the complete draft, including the
  // low-confidence entries kept there for reviewer visibility).
  static const List<_MappingEntry> _mapping = [
    _MappingEntry(
      mappingId: 'GEO-001',
      country: 'Egypt',
      madhahib: [Madhhab.shafii, Madhhab.hanafi, Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['SRC-INST-001'],
    ),
    _MappingEntry(
      mappingId: 'GEO-002',
      country: 'Saudi Arabia',
      madhahib: [Madhhab.hanbali],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['SRC-INST-002'],
    ),
    _MappingEntry(
      mappingId: 'GEO-003',
      country: 'Turkey',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-004',
      country: 'Pakistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-005b',
      country: 'India',
      region: 'Kerala',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-006',
      country: 'Morocco',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['SRC-INST-001'],
    ),
    _MappingEntry(
      mappingId: 'GEO-007',
      country: 'Tunisia',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-008',
      country: 'Algeria',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-009',
      country: 'Indonesia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      mappingId: 'GEO-010',
      country: 'Malaysia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
      evidenceSourceIds: ['JUR-MY-001'],
    ),
  ];

  /// [explicitCountry]/[explicitCity]: the user directly stated these (e.g.
  /// typed/selected in onboarding). Always preferred when present.
  /// [phonePrefixCountry]: a country name/guess derived only from a phone
  /// number's country-calling-code prefix — the weakest possible signal,
  /// used only when no explicit country/city is available, and never
  /// returned as if it were an explicit signal.
  MadhhabSuggestion suggest({
    String? explicitCountry,
    String? explicitCity,
    String? phonePrefixCountry,
  }) {
    final country =
        (explicitCountry != null && explicitCountry.trim().isNotEmpty)
        ? explicitCountry.trim()
        : (phonePrefixCountry != null && phonePrefixCountry.trim().isNotEmpty)
        ? phonePrefixCountry.trim()
        : null;
    if (country == null) return MadhhabSuggestion.unresolved;

    final city = explicitCity?.trim();

    // City-level entries (if any) take priority over the country-level
    // entry for the same country — e.g. Kerala vs. the rest of India.
    if (city != null && city.isNotEmpty) {
      for (final entry in _mapping) {
        if (entry.region != null &&
            _sameCountry(entry.country, country) &&
            _sameRegion(entry.region!, city)) {
          return MadhhabSuggestion(
            confidence: entry.confidence,
            likelyMadhahib: entry.madhahib,
            regionNote:
                'This madhhab is commonly followed in ${entry.region}, ${entry.country}.',
            mappingId: entry.mappingId,
            evidenceSourceIds: entry.evidenceSourceIds,
            reviewerStatus: entry.reviewerStatus,
          );
        }
      }
    }

    for (final entry in _mapping) {
      if (entry.region == null && _sameCountry(entry.country, country)) {
        return MadhhabSuggestion(
          confidence: entry.confidence,
          likelyMadhahib: entry.madhahib,
          regionNote: 'This madhhab is commonly followed in ${entry.country}.',
          mappingId: entry.mappingId,
          evidenceSourceIds: entry.evidenceSourceIds,
          reviewerStatus: entry.reviewerStatus,
        );
      }
    }

    return MadhhabSuggestion.unresolved;
  }

  bool _sameCountry(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
  bool _sameRegion(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
