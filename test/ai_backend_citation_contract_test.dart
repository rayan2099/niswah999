import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_advisor/ai_advisor_service.dart';

/// Pre-Merge Integration Validation, Phase 5 (Finding 7): encodes the
/// producer/consumer contract between kb_retrieval.ts's `citationPayload()`
/// (both fiqh-advisor-chat and dr-niswah-chat) and [FiqhCitation], the shared
/// Dart model both features' response parsing uses. If either side's field
/// names drift again (as happened once already — the backend added
/// `locator`, and this model silently dropped it until this fix), one of
/// these tests should fail rather than the mismatch going unnoticed.
void main() {
  group('FiqhCitation.fromJson — current backend wire shape', () {
    // Exact shape kb_retrieval.ts's citationPayload() produces today:
    // { knowledgeKey, versionId, sourceKey, title, locator, url, contentLanguage }
    const backendCitationJson = {
      'knowledgeKey': 'HL-MENS-002',
      'versionId': 'efef6ce2-3cfa-4415-b3fe-9f96136bf74f',
      'sourceKey': 'OWH_CYCLE',
      'title': 'Your menstrual cycle',
      'locator':
          'Section: How long is a typical menstrual cycle? (24–38 days in this source)',
      'url': 'https://womenshealth.gov/menstrual-cycle/your-menstrual-cycle',
      'contentLanguage': 'en',
    };

    test('parses title, url, and locator from the real backend shape', () {
      final citation = FiqhCitation.fromJson(backendCitationJson);
      expect(citation.title, 'Your menstrual cycle');
      expect(
        citation.url,
        'https://womenshealth.gov/menstrual-cycle/your-menstrual-cycle',
      );
      expect(
        citation.locator,
        'Section: How long is a typical menstrual cycle? (24–38 days in this source)',
        reason:
            'locator carries the exact source section — dropped silently '
            'before this fix even though the backend always sent it',
      );
    });

    test(
      'startIndex/endIndex default to 0 when absent (current backend never sends them)',
      () {
        final citation = FiqhCitation.fromJson(backendCitationJson);
        expect(citation.startIndex, 0);
        expect(citation.endIndex, 0);
      },
    );

    test(
      'still parses legacy startIndex/endIndex if ever present (backward compatibility with pre-KB cached data)',
      () {
        final citation = FiqhCitation.fromJson({
          ...backendCitationJson,
          'startIndex': 12,
          'endIndex': 34,
        });
        expect(citation.startIndex, 12);
        expect(citation.endIndex, 34);
      },
    );

    test('tolerates a missing locator without throwing (older cached rows)', () {
      final withoutLocator = Map<String, dynamic>.from(backendCitationJson)
        ..remove('locator');
      final citation = FiqhCitation.fromJson(withoutLocator);
      expect(citation.locator, '');
      expect(citation.title, 'Your menstrual cycle');
    });
  });

  group('FiqhCitation.toJson — what dr_niswah_chat_screen.dart reads back', () {
    test('round-trips the exact keys the shared chat screen renders', () {
      const citation = FiqhCitation(
        url: 'https://example.test/source',
        title: 'Example Source',
        locator: 'p.12',
      );
      final json = citation.toJson();

      // dr_niswah_chat_screen.dart:1184/1189 reads _citations[i]['title']
      // and _citations[i]['url'] directly off the persisted metadata map —
      // both keys must exist with exactly these names for that rendering
      // code to keep working for BOTH Fiqh Advisor and Dr Niswah messages.
      expect(json['title'], 'Example Source');
      expect(json['url'], 'https://example.test/source');
      expect(json['locator'], 'p.12');
    });

    test('a full fromJson -> toJson round trip is lossless for the fields both features use', () {
      const backendCitationJson = {
        'title': 'Your menstrual cycle',
        'locator': 'Section: How long is a typical menstrual cycle?',
        'url': 'https://womenshealth.gov/menstrual-cycle/your-menstrual-cycle',
      };
      final citation = FiqhCitation.fromJson(backendCitationJson);
      final roundTripped = citation.toJson();
      expect(roundTripped['title'], backendCitationJson['title']);
      expect(roundTripped['locator'], backendCitationJson['locator']);
      expect(roundTripped['url'], backendCitationJson['url']);
    });
  });
}
