import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/models/cycle_log.dart';
import 'package:niswah/core/models/madhhab_type.dart';
import 'package:niswah/core/services/fiqh_calculation_engine.dart';

void main() {
  group('FiqhCalculationEngine', () {
    late FiqhCalculationEngine engine;

    setUp(() {
      engine = FiqhCalculationEngine();
    });

    group('isValidMenses', () {
      test(
        'Hanafi: Should return true for valid menses duration (3-10 days)',
        () {
          expect(
            engine.isValidMenses(const Duration(days: 3), MadhhabType.hanafi),
            isTrue,
          );
          expect(
            engine.isValidMenses(const Duration(days: 7), MadhhabType.hanafi),
            isTrue,
          );
          expect(
            engine.isValidMenses(const Duration(days: 10), MadhhabType.hanafi),
            isTrue,
          );
        },
      );

      test('Hanafi: Should return false for invalid menses duration (<3 or >10 days)', () {
        expect(
          engine.isValidMenses(const Duration(days: 2), MadhhabType.hanafi),
          isFalse,
        );
        expect(
          engine.isValidMenses(const Duration(days: 11), MadhhabType.hanafi),
          isFalse,
        );
      });

      test('Shafii/Hanbali: Should return true for valid menses duration (>=24 hours, <=15 days)', () {
        expect(
          engine.isValidMenses(const Duration(hours: 24), MadhhabType.shafii),
          isTrue,
        );
        expect(
          engine.isValidMenses(const Duration(days: 1), MadhhabType.hanbali),
          isTrue,
        );
        expect(
          engine.isValidMenses(const Duration(days: 15), MadhhabType.shafii),
          isTrue,
        );
      });

      test('Shafii/Hanbali: Should return false for invalid menses duration (<24 hours or >15 days)', () {
        expect(
          engine.isValidMenses(const Duration(hours: 23), MadhhabType.shafii),
          isFalse,
        );
        expect(
          engine.isValidMenses(const Duration(days: 16), MadhhabType.hanbali),
          isFalse,
        );
      });

      test('Maliki: Should return true for valid menses duration (1-15 days, simplified)', () {
        expect(
          engine.isValidMenses(const Duration(days: 1), MadhhabType.maliki),
          isTrue,
        );
        expect(
          engine.isValidMenses(const Duration(days: 15), MadhhabType.maliki),
          isTrue,
        );
      });

      test('Maliki: Should return false for invalid menses duration (more than 15 days, simplified)', () {
        expect(
          engine.isValidMenses(const Duration(days: 16), MadhhabType.maliki),
          isFalse,
        );
      });
    });

    group('calculateNextPredictedWindow', () {
      final DateTime now = DateTime.now();

      test('Should return empty list if history is empty or insufficient', () {
        expect(
          engine.calculateNextPredictedWindow([], MadhhabType.shafii),
          isEmpty,
        );
        expect(
          engine.calculateNextPredictedWindow([
            _createCycleLog(now.subtract(const Duration(days: 30))),
          ], MadhhabType.shafii),
          isEmpty,
        );
      });

      test('Should predict next window based on average cycle length', () {
        final history = [
          _createCycleLog(
            now.subtract(const Duration(days: 30)),
            endDate: now.subtract(const Duration(days: 25)),
          ),
          _createCycleLog(
            now.subtract(const Duration(days: 60)),
            endDate: now.subtract(const Duration(days: 55)),
          ),
          _createCycleLog(
            now.subtract(const Duration(days: 90)),
            endDate: now.subtract(const Duration(days: 85)),
          ),
        ];

        final predictedWindow = engine.calculateNextPredictedWindow(
          history,
          MadhhabType.shafii,
        );

        expect(predictedWindow, isNotEmpty);
        expect(predictedWindow.length, 2);

        // Average cycle length is approximately 30 days. Next cycle should be around `now`.
        final predictedStartDate = predictedWindow[0].add(
          const Duration(days: 2),
        ); // Midpoint of the window
        expect(predictedStartDate.day, equals(now.day));
        expect(predictedStartDate.month, equals(now.month));
        expect(predictedStartDate.year, equals(now.year));
      });

      test('Should handle unsorted history', () {
        final history = [
          _createCycleLog(
            now.subtract(const Duration(days: 60)),
            endDate: now.subtract(const Duration(days: 55)),
          ),
          _createCycleLog(
            now.subtract(const Duration(days: 30)),
            endDate: now.subtract(const Duration(days: 25)),
          ),
          _createCycleLog(
            now.subtract(const Duration(days: 90)),
            endDate: now.subtract(const Duration(days: 85)),
          ),
        ];

        final predictedWindow = engine.calculateNextPredictedWindow(
          history,
          MadhhabType.shafii,
        );

        expect(predictedWindow, isNotEmpty);
        expect(predictedWindow.length, 2);
      });
    });

    group('detectIstihadah', () {
      test('Hanafi: Should flag days exceeding 10 days as Istihadah', () {
        final bleedingDays = List.generate(
          12,
          (index) => DateTime(2023, 1, 1).add(Duration(days: index)),
        ); // 12 days bleeding
        final istihadahDays = engine.detectIstihadah(
          bleedingDays,
          MadhhabType.hanafi,
        );

        expect(istihadahDays, hasLength(2));
        expect(istihadahDays[0], DateTime(2023, 1, 11));
        expect(istihadahDays[1], DateTime(2023, 1, 12));
      });

      test('Hanafi: Should not flag if within 10 days', () {
        final bleedingDays = List.generate(
          10,
          (index) => DateTime(2023, 1, 1).add(Duration(days: index)),
        ); // 10 days bleeding
        final istihadahDays = engine.detectIstihadah(
          bleedingDays,
          MadhhabType.hanafi,
        );

        expect(istihadahDays, isEmpty);
      });

      test(
        'Shafii/Hanbali: Should flag days exceeding 15 days as Istihadah',
        () {
          final bleedingDays = List.generate(
            17,
            (index) => DateTime(2023, 1, 1).add(Duration(days: index)),
          ); // 17 days bleeding
          final istihadahDays = engine.detectIstihadah(
            bleedingDays,
            MadhhabType.shafii,
          );

          expect(istihadahDays, hasLength(2));
          expect(istihadahDays[0], DateTime(2023, 1, 16));
          expect(istihadahDays[1], DateTime(2023, 1, 17));
        },
      );

      test('Shafii/Hanbali: Should not flag if within 15 days', () {
        final bleedingDays = List.generate(
          15,
          (index) => DateTime(2023, 1, 1).add(Duration(days: index)),
        ); // 15 days bleeding
        final istihadahDays = engine.detectIstihadah(
          bleedingDays,
          MadhhabType.hanbali,
        );

        expect(istihadahDays, isEmpty);
      });

      test(
        'Maliki: Should flag days exceeding 15 days as Istihadah (simplified)',
        () {
          final bleedingDays = List.generate(
            17,
            (index) => DateTime(2023, 1, 1).add(Duration(days: index)),
          ); // 17 days bleeding
          final istihadahDays = engine.detectIstihadah(
            bleedingDays,
            MadhhabType.maliki,
          );

          expect(istihadahDays, hasLength(2));
          expect(istihadahDays[0], DateTime(2023, 1, 16));
          expect(istihadahDays[1], DateTime(2023, 1, 17));
        },
      );

      test('Should return empty list for empty bleedingDays', () {
        expect(engine.detectIstihadah([], MadhhabType.hanafi), isEmpty);
      });

      test('Should handle unsorted bleedingDays', () {
        final bleedingDays = [
          DateTime(2023, 1, 5),
          DateTime(2023, 1, 1),
          DateTime(2023, 1, 3),
          DateTime(2023, 1, 2),
          DateTime(2023, 1, 4),
          DateTime(2023, 1, 11), // Exceeds Hanafi 10 days
          DateTime(2023, 1, 12),
        ]; // 12 days bleeding
        final istihadahDays = engine.detectIstihadah(
          bleedingDays,
          MadhhabType.hanafi,
        );
        expect(istihadahDays, hasLength(2));
        expect(istihadahDays[0], DateTime(2023, 1, 11));
        expect(istihadahDays[1], DateTime(2023, 1, 12));
      });
    });
  });
}

// Helper function to create a CycleLog for testing
CycleLog _createCycleLog(DateTime startDate, {DateTime? endDate}) {
  return CycleLog(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    userId: 'test_user_id',
    startDate: startDate,
    endDate: endDate ?? startDate.add(const Duration(days: 5)),
    bleedingIntensity: 'moderate',
    notes: 'test notes',
    createdAt: DateTime.now(),
  );
}
