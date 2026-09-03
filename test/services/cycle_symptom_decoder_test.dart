import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart';

CycleLog _log(int day, List<String> symptoms, {String? notes}) {
  return CycleLog(
    id: 'log-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: FlowLevel.medium,
    symptoms: symptoms,
    notes: notes,
  );
}

void main() {
  group('CycleSymptomDecoder.decode', () {
    test('parses the five reserved keys', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, [
          'energy:3',
          'sleep:4',
          'color:red',
          'mood:2',
          'notes:felt tired all day',
        ]),
      );

      expect(entry.energy, 3);
      expect(entry.sleep, 4);
      expect(entry.bloodColor, 'red');
      expect(entry.mood, 2);
      expect(entry.notes, 'felt tired all day');
      expect(entry.symptomSeverities, isEmpty);
    });

    test('treats unreserved keys as named symptoms', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, ['Cramps:2', 'Headache:1', 'energy:3']),
      );

      expect(entry.symptomSeverities, {'Cramps': 2, 'Headache': 1});
      expect(entry.energy, 3);
    });

    test('lowercase "mood" and capitalized "Mood" symptom chip are distinct', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, ['mood:5', 'Mood:2']),
      );

      expect(entry.mood, 5);
      expect(entry.symptomSeverities, {'Mood': 2});
    });

    test('notes containing a colon keeps the rest of the string intact', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, ['notes:appointment at 3:30pm']),
      );

      expect(entry.notes, 'appointment at 3:30pm');
    });

    test('malformed entries (no colon, non-numeric value) are ignored safely', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, ['garbage', 'energy:not-a-number', 'Cramps:oops']),
      );

      expect(entry.energy, isNull);
      expect(entry.symptomSeverities, isEmpty);
    });

    test('prefers the dedicated notes field over an encoded notes: entry', () {
      final entry = CycleSymptomDecoder.decode(
        _log(1, const [], notes: 'the real note'),
      );

      expect(entry.notes, 'the real note');
    });

    test(
      'falls back to a legacy notes: entry when the notes field is unset',
      () {
        final entry = CycleSymptomDecoder.decode(
          _log(1, ['notes:legacy note']),
        );

        expect(entry.notes, 'legacy note');
      },
    );

    test('empty symptoms list decodes to an entry with no data', () {
      final entry = CycleSymptomDecoder.decode(_log(1, const []));

      expect(entry.energy, isNull);
      expect(entry.sleep, isNull);
      expect(entry.bloodColor, isNull);
      expect(entry.mood, isNull);
      expect(entry.notes, isNull);
      expect(entry.symptomSeverities, isEmpty);
    });
  });

  group('CycleSymptomDecoder.aggregateSymptoms', () {
    test('counts occurrences and averages severity, sorted by frequency', () {
      final logs = [
        _log(1, ['Cramps:2', 'Headache:1']),
        _log(2, ['Cramps:3']),
        _log(3, ['Cramps:1', 'Headache:2']),
      ];

      final aggregates = CycleSymptomDecoder.aggregateSymptoms(logs);

      expect(aggregates.length, 2);
      expect(aggregates.first.name, 'Cramps');
      expect(aggregates.first.occurrenceCount, 3);
      expect(aggregates.first.averageSeverity, 2.0);
      expect(aggregates.last.name, 'Headache');
      expect(aggregates.last.occurrenceCount, 2);
      expect(aggregates.last.averageSeverity, 1.5);
    });

    test('excludes zero-severity entries (symptom cycled back off)', () {
      final logs = [
        _log(1, ['Cramps:0']),
      ];

      final aggregates = CycleSymptomDecoder.aggregateSymptoms(logs);

      expect(aggregates, isEmpty);
    });

    test('no logs produces no aggregates', () {
      expect(CycleSymptomDecoder.aggregateSymptoms(const []), isEmpty);
    });
  });

  group('CycleSymptomDecoder.recentNotes', () {
    test('returns only non-empty notes, newest first', () {
      final logs = [
        _log(1, const [], notes: 'first note'),
        _log(2, const []), // no note
        _log(3, const [], notes: '   '), // whitespace-only, excluded
        _log(4, const [], notes: 'third note'),
      ];

      final notes = CycleSymptomDecoder.recentNotes(logs);

      expect(notes.length, 2);
      expect(notes.first.text, 'third note');
      expect(notes.first.date, DateTime(2026, 1, 4));
      expect(notes.last.text, 'first note');
    });

    test('caps results at limit', () {
      final logs = [
        for (var day = 1; day <= 5; day++) _log(day, const [], notes: 'note $day'),
      ];

      final notes = CycleSymptomDecoder.recentNotes(logs, limit: 2);

      expect(notes.length, 2);
      expect(notes.first.text, 'note 5');
      expect(notes.last.text, 'note 4');
    });

    test('no notes produces an empty list', () {
      expect(CycleSymptomDecoder.recentNotes(const []), isEmpty);
      expect(
        CycleSymptomDecoder.recentNotes([_log(1, const [])]),
        isEmpty,
      );
    });
  });

  group('CycleSymptomDecoder.recentBloodColors', () {
    test('returns preset and custom "Other" colors alike, newest first', () {
      final logs = [
        _log(1, ['color:red']),
        _log(2, const []), // no color logged
        _log(3, ['color:أحمر فاتح مع تكتلات صغيرة']),
      ];

      final colors = CycleSymptomDecoder.recentBloodColors(logs);

      expect(colors.length, 2);
      expect(colors.first.text, 'أحمر فاتح مع تكتلات صغيرة');
      expect(colors.first.date, DateTime(2026, 1, 3));
      expect(colors.last.text, 'red');
    });

    test('caps results at limit', () {
      final logs = [
        for (var day = 1; day <= 5; day++) _log(day, ['color:color-$day']),
      ];

      final colors = CycleSymptomDecoder.recentBloodColors(logs, limit: 2);

      expect(colors.length, 2);
      expect(colors.first.text, 'color-5');
      expect(colors.last.text, 'color-4');
    });

    test('no colors logged produces an empty list', () {
      expect(CycleSymptomDecoder.recentBloodColors(const []), isEmpty);
      expect(
        CycleSymptomDecoder.recentBloodColors([_log(1, const [])]),
        isEmpty,
      );
    });
  });
}
