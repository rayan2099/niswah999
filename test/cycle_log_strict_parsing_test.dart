import 'package:flutter_test/flutter_test.dart';

import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';

/// Menstrual Data Integrity charter, Commit A (2026-09-17): `CycleLog.fromJson`
/// used to coerce an invalid/missing `date` to `DateTime.now()` and an
/// invalid/missing `flow` to `FlowLevel.light` — silently manufacturing a
/// plausible-looking observation nobody actually reported. It must now throw
/// [CycleLogParseException] instead, and a batch decode must quarantine only
/// the one bad record rather than lose the whole list (see
/// [SecureLocalStore.decodeJsonListSafely]).
void main() {
  Map<String, dynamic> validJson({String? date, String? flow}) => {
    'id': 'log-1',
    'user_id': 'user-1',
    'date': date ?? '2026-09-10T00:00:00.000Z',
    'flow': flow ?? 'medium',
    'cycle_day': 2,
    'symptoms': <String>[],
    'sync_status': 'synced',
  };

  group('CycleLog.fromJson strict parsing', () {
    test('parses a well-formed record normally', () {
      final log = CycleLog.fromJson(validJson());
      expect(log.date, DateTime.parse('2026-09-10T00:00:00.000Z'));
      expect(log.flow, FlowLevel.medium);
    });

    test(
      'throws on a missing date instead of defaulting to DateTime.now()',
      () {
        final json = validJson()..remove('date');
        expect(
          () => CycleLog.fromJson(json),
          throwsA(isA<CycleLogParseException>()),
        );
      },
    );

    test(
      'throws on an unparseable date instead of defaulting to DateTime.now()',
      () {
        expect(
          () => CycleLog.fromJson(validJson(date: 'not-a-real-date')),
          throwsA(isA<CycleLogParseException>()),
        );
      },
    );

    test(
      'throws on a missing flow instead of defaulting to FlowLevel.light',
      () {
        final json = validJson()..remove('flow');
        expect(
          () => CycleLog.fromJson(json),
          throwsA(isA<CycleLogParseException>()),
        );
      },
    );

    test(
      'throws on an unrecognized flow instead of defaulting to FlowLevel.light',
      () {
        expect(
          () => CycleLog.fromJson(validJson(flow: 'torrential')),
          throwsA(isA<CycleLogParseException>()),
        );
      },
    );
  });

  group('SecureLocalStore.decodeJsonListSafely quarantines per-record', () {
    test('a single corrupt record is skipped without losing the other valid records', () {
      final raw =
          '['
          '${_jsonString(validJson(date: '2026-09-10T00:00:00.000Z'))},'
          '${_jsonString(validJson()..['date'] = 'garbage')},'
          '${_jsonString(validJson(date: '2026-09-08T00:00:00.000Z'))}'
          ']';

      final result = SecureLocalStore.decodeJsonListSafely<CycleLog>(
        raw: raw,
        category: 'test_cycle_logs',
        fromJson: CycleLog.fromJson,
      );

      expect(result, hasLength(2));
      expect(
        result.map((log) => log.date),
        containsAll([
          DateTime.parse('2026-09-10T00:00:00.000Z'),
          DateTime.parse('2026-09-08T00:00:00.000Z'),
        ]),
      );
    });

    test(
      'every record corrupt still returns an empty list, not an exception',
      () {
        final raw = '[${_jsonString(validJson()..['flow'] = 'invalid')}]';

        final result = SecureLocalStore.decodeJsonListSafely<CycleLog>(
          raw: raw,
          category: 'test_cycle_logs',
          fromJson: CycleLog.fromJson,
        );

        expect(result, isEmpty);
      },
    );
  });
}

String _jsonString(Map<String, dynamic> json) {
  final buffer = StringBuffer('{');
  var first = true;
  json.forEach((key, value) {
    if (!first) buffer.write(',');
    first = false;
    buffer.write('"$key":');
    if (value is String) {
      buffer.write('"${value.replaceAll('"', '\\"')}"');
    } else if (value is List) {
      buffer.write('[]');
    } else {
      buffer.write(value);
    }
  });
  buffer.write('}');
  return buffer.toString();
}
