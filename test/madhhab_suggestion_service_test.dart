import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
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

  test('single-option country resolves with one madhhab', () {
    final result = service.suggest(explicitCountry: 'Morocco');
    expect(result.isResolved, true);
    expect(result.likelyMadhahib, [Madhhab.maliki]);
    expect(result.regionNote, contains('Morocco'));
  });

  test('multi-madhhab country returns every plausible option, not one', () {
    final result = service.suggest(explicitCountry: 'Egypt');
    expect(result.isResolved, true);
    expect(result.likelyMadhahib.length, greaterThan(1));
    expect(result.likelyMadhahib, containsAll([Madhhab.shafii, Madhhab.hanafi, Madhhab.maliki]));
  });

  test('explicit country outranks phone-prefix country', () {
    final result = service.suggest(
      explicitCountry: 'Morocco',
      phonePrefixCountry: 'Turkey',
    );
    expect(result.likelyMadhahib, [Madhhab.maliki]);
  });

  test('phone-prefix country is used only when no explicit country is given', () {
    final result = service.suggest(phonePrefixCountry: 'Turkey');
    expect(result.isResolved, true);
    expect(result.likelyMadhahib, [Madhhab.hanafi]);
  });

  test('phone prefix alone never resolves for an unmapped/ambiguous case the same as explicit would', () {
    // Same underlying rule as the unmapped-country test — phone prefix
    // carries no special weight, it's just a weaker fallback signal, not a
    // different resolution path.
    final result = service.suggest(phonePrefixCountry: 'Atlantis');
    expect(result.isResolved, false);
  });

  test('city-level override takes priority over the country-level entry', () {
    final indiaDefault = service.suggest(explicitCountry: 'India');
    expect(indiaDefault.isResolved, false); // India itself is low-confidence, deliberately unresolved

    final keralaOverride = service.suggest(
      explicitCountry: 'India',
      explicitCity: 'Kerala',
    );
    expect(keralaOverride.isResolved, true);
    expect(keralaOverride.likelyMadhahib, [Madhhab.shafii]);
  });

  test('country matching is case-insensitive and trims whitespace', () {
    final result = service.suggest(explicitCountry: '  moRocco  ');
    expect(result.isResolved, true);
    expect(result.likelyMadhahib, [Madhhab.maliki]);
  });

  test('empty-string signals are treated as absent, not as a literal country', () {
    final result = service.suggest(explicitCountry: '', phonePrefixCountry: '');
    expect(result.isResolved, false);
  });

  test('regionNote never phrases the suggestion as a declaration of the user\'s own madhhab', () {
    final result = service.suggest(explicitCountry: 'Saudi Arabia');
    expect(result.regionNote, isNotNull);
    expect(result.regionNote!.toLowerCase().contains('you are'), false);
    expect(result.regionNote!.toLowerCase().contains('commonly followed'), true);
  });
}
