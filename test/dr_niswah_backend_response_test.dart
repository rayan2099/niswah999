import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/features/ai_assistant/data/services/dr_niswah_backend_service.dart';

/// Main-vs-PR#4 merge resolution (2026-10-08): `DrNiswahBackendResponse
/// .fromBackendJson` combines two previously-separate requirements that
/// landed on the same lines of `dr_niswah_backend_service.dart` on
/// different branches — main's Knowledge-Base citation/grounding
/// extraction, and PR #4's strict empty/malformed-reply rejection. Neither
/// side's own tests ever exercised the combination directly (the method
/// this logic used to live in, `send()`, has no DI seam and can't be unit
/// tested with a fake backend response — see
/// `test/dr_niswah_red_flag_dual_state_test.dart`'s own doc comment). This
/// file proves the combined behavior with plain Maps, no Supabase needed.
void main() {
  group('DrNiswahBackendResponse.fromBackendJson', () {
    test('a valid grounded response survives validation with both citations '
        'and knowledgeGrounded preserved', () {
      final response = DrNiswahBackendResponse.fromBackendJson({
        'reply': 'Hanafi requires a minimum of three days.',
        'urgent': false,
        'knowledgeGrounded': true,
        'citations': [
          {
            'url': 'https://example.org/source',
            'title': 'Fiqh source',
            'locator': 'p.12',
            'startIndex': 10,
            'endIndex': 42,
          },
        ],
      });

      expect(response.reply, 'Hanafi requires a minimum of three days.');
      expect(response.urgent, isFalse);
      expect(response.knowledgeGrounded, isTrue);
      expect(response.citations, hasLength(1));
      expect(response.citations.single.url, 'https://example.org/source');
      expect(response.citations.single.title, 'Fiqh source');
    });

    test('a malformed response (empty reply, not urgent) is still rejected — '
        'the strict-validation requirement survives the merge', () {
      expect(
        () => DrNiswahBackendResponse.fromBackendJson({
          'reply': '',
          'urgent': false,
        }),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a missing reply field entirely (not just empty) is still rejected',
      () {
        expect(
          () => DrNiswahBackendResponse.fromBackendJson({'urgent': false}),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('a non-string reply (wrong type) is rejected, not cast-crashed', () {
      expect(
        () => DrNiswahBackendResponse.fromBackendJson({
          'reply': 12345,
          'urgent': false,
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('an urgent message with an empty reply is accepted (the safety-banner '
        'path) and still carries through whatever citations/grounding the '
        'backend sent — urgent never discards real grounding data', () {
      final response = DrNiswahBackendResponse.fromBackendJson({
        'reply': '',
        'urgent': true,
        'knowledgeGrounded': true,
        'citations': [
          {'url': 'https://example.org/urgent-source', 'title': 'Source'},
        ],
      });

      expect(response.reply, '');
      expect(response.urgent, isTrue);
      expect(
        response.knowledgeGrounded,
        isTrue,
        reason: 'urgent must not silently drop real grounding data',
      );
      expect(response.citations, hasLength(1));
    });

    test('no fallback ever fabricates missing Fiqh grounding — absent '
        'citations/knowledgeGrounded fields default to empty/false, never '
        'to a fabricated grounded-looking value', () {
      final response = DrNiswahBackendResponse.fromBackendJson({
        'reply': 'A plain, ungrounded reply.',
        'urgent': false,
      });

      expect(response.knowledgeGrounded, isFalse);
      expect(response.citations, isEmpty);
    });

    test('knowledgeGrounded: true with zero citations is preserved exactly as '
        'sent — this constructor never second-guesses the backend\'s own '
        'combination of fields', () {
      final response = DrNiswahBackendResponse.fromBackendJson({
        'reply': 'Grounded in general knowledge, no specific citation.',
        'urgent': false,
        'knowledgeGrounded': true,
        'citations': <Map<String, dynamic>>[],
      });

      expect(response.knowledgeGrounded, isTrue);
      expect(response.citations, isEmpty);
    });
  });
}
