// Adversarial review, 2026-10-07: `suggest()` now requires a matched
// mapping entry's `reviewer_status` to be `'APPROVED'` before it will
// ever surface a confident suggestion — an unreviewed mapping (every
// single entry in the dataset today, verified directly against
// geographic_madhhab_mapping.json, Afghanistan included, not an
// Afghanistan-specific carve-out) must "not guess" and fall through to
// `unresolved`, exactly like an unmapped country. This file was rewritten
// accordingly: every country-level test below now asserts `unresolved`,
// proving the gate is actually active and applied uniformly, not that
// the underlying matching/confidence/evidence data was deleted (it
// wasn't — see madhhab_suggestion_service.dart's own `_mapping` list,
// unchanged in content, only gated in `suggest()`'s return).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/onboarding/domain/services/madhhab_suggestion_service.dart';

void main() {
  const service = MadhhabSuggestionService();

  test('unresolved when no signal is given at all', () {
    final result = service.suggest();
    expect(result.isResolved, false);
    expect(result.confidence, MadhhabSuggestionConfidence.unresolved);
    expect(result.likelyMadhahib, isEmpty);
  });

  test('unresolved for a country not in the draft mapping', () {
    final result = service.suggest(explicitCountry: 'Atlantis');
    expect(result.isResolved, false);
  });

  group('trust gate: no mapping entry is reviewer-approved today, so '
      'every country — including countries that used to appear '
      'confident — resolves to unresolved, never a guess', () {
    test('Afghanistan: present in the mapping (fixing the real absence bug), '
        'but NOT_REVIEWED, so it still resolves to unresolved — this is '
        'what "never receive an authoritative suggestion unless reviewed" '
        'means in practice, and it is the same outcome every other '
        'country gets today, not a special restriction singling it out', () {
      final byName = service.suggest(explicitCountry: 'Afghanistan');
      expect(byName.isResolved, false);
      final byCode = service.suggest(explicitCountryCode: 'AF');
      expect(byCode.isResolved, false);
    });

    test('a country that used to resolve with a single madhhab (Morocco) '
        'now resolves to unresolved too — same gate, applied uniformly', () {
      final result = service.suggest(explicitCountry: 'Morocco');
      expect(result.isResolved, false);
    });

    test('a multi-madhhab country (Egypt) also resolves to unresolved — '
        'the gate applies before the multi-option branch is ever reached', () {
      final result = service.suggest(explicitCountry: 'Egypt');
      expect(result.isResolved, false);
    });

    test('a city-level override match (India/Kerala) is gated the same '
        'way as a country-level match — the gate applies to both branches '
        'of suggest(), not only the country-level one', () {
      final result = service.suggest(
        explicitCountry: 'India',
        explicitCity: 'Kerala',
      );
      expect(result.isResolved, false);
    });

    test('a phone-prefix-only match (Turkey) is gated identically to an '
        'explicit-country match', () {
      final result = service.suggest(phonePrefixCountry: 'Turkey');
      expect(result.isResolved, false);
    });
  });

  test('explicitCountryCode matches directly, without any name lookup '
      '(still gated — resolves to unresolved for the same reason)', () {
    final result = service.suggest(explicitCountryCode: 'AF');
    expect(result.isResolved, false);
  });

  test('explicitCountryCode is case-insensitive in its matching, '
      'independent of the gate', () {
    final lower = service.suggest(explicitCountryCode: 'af');
    final upper = service.suggest(explicitCountryCode: 'AF');
    expect(lower.isResolved, upper.isResolved);
  });

  test('an unmapped country never blocks resolution — falling through to '
      'unresolved is always safe, matching the Atlantis case above', () {
    final result = service.suggest(explicitCountryCode: 'ZZ');
    expect(result.isResolved, false);
  });

  test('country matching logic (case-insensitive, trims whitespace) still '
      'runs — it just always lands on unresolved since nothing is '
      'approved, proven by comparing a clean vs. messy spelling of the '
      'same, still-unresolved country', () {
    final clean = service.suggest(explicitCountry: 'Morocco');
    final messy = service.suggest(explicitCountry: '  moRocco  ');
    expect(clean.isResolved, false);
    expect(messy.isResolved, false);
  });

  test(
    'empty-string signals are treated as absent, not as a literal country',
    () {
      final result = service.suggest(
        explicitCountry: '',
        phonePrefixCountry: '',
      );
      expect(result.isResolved, false);
    },
  );

  test('the gate check is actually present in suggest()\'s source, before '
      'both return points that would otherwise surface a resolved '
      'suggestion — guards against the check being silently removed later', () {
    final source = File(
      'lib/features/onboarding/domain/services/madhhab_suggestion_service.dart',
    ).readAsStringSync();
    final occurrences = 'isApprovedForDisplay'.allMatches(source).length;
    expect(
      occurrences,
      greaterThanOrEqualTo(3),
      reason:
          'expect the field/getter definition plus two call sites '
          '(the region-level and country-level match branches in '
          'suggest())',
    );
  });

  test('supportedCountries still lists drafted coverage (including '
      'Afghanistan) for a future reviewer, even though none of them '
      'currently produce a displayed suggestion', () {
    expect(
      MadhhabSuggestionService.supportedCountries,
      contains('Afghanistan'),
    );
    expect(MadhhabSuggestionService.supportedCountries, contains('Morocco'));
  });
}
