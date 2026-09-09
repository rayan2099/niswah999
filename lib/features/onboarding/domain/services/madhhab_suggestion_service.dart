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

  bool get isResolved => confidence != MadhhabSuggestionConfidence.unresolved;

  static const unresolved = MadhhabSuggestion(
    confidence: MadhhabSuggestionConfidence.unresolved,
  );
}

class _MappingEntry {
  const _MappingEntry({
    required this.country,
    this.region,
    required this.madhahib,
    required this.confidence,
  });

  final String country;
  final String? region;
  final List<Madhhab> madhahib;
  final MadhhabSuggestionConfidence confidence;
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

  // Mirrors production-readiness-results/fiqh-engine/geographic_madhhab_mapping.json
  // (mappings with confidence "medium" or higher only — "low" entries are
  // intentionally omitted here since this service always resolves "low" to
  // unresolved anyway; see that file for the complete draft, including the
  // low-confidence entries kept there for reviewer visibility).
  static const List<_MappingEntry> _mapping = [
    _MappingEntry(
      country: 'Egypt',
      madhahib: [Madhhab.shafii, Madhhab.hanafi, Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Saudi Arabia',
      madhahib: [Madhhab.hanbali],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Turkey',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Pakistan',
      madhahib: [Madhhab.hanafi],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'India',
      region: 'Kerala',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Morocco',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Tunisia',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Algeria',
      madhahib: [Madhhab.maliki],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Indonesia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
    ),
    _MappingEntry(
      country: 'Malaysia',
      madhahib: [Madhhab.shafii],
      confidence: MadhhabSuggestionConfidence.medium,
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
    final country = (explicitCountry != null && explicitCountry.trim().isNotEmpty)
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
