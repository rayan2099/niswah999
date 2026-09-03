import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/presentation/models/cycle_log_form_data.dart';

void main() {
  group('CycleLogFormData', () {
    test('accepts a valid daily log entry', () {
      final formData = CycleLogFormData(
        date: DateTime(2026, 8, 18),
        flow: FlowLevel.light,
        cycleDay: 8,
        notes: 'Tracking feels normal',
      );

      expect(formData.validate(), isNull);
    });

    test('rejects an empty date or invalid cycle day', () {
      final emptyDate = CycleLogFormData(
        date: null,
        flow: FlowLevel.none,
        cycleDay: 3,
      );
      final invalidCycleDay = CycleLogFormData(
        date: DateTime(2026, 8, 18),
        flow: FlowLevel.medium,
        cycleDay: 0,
      );

      expect(emptyDate.validate(), contains('date'));
      expect(invalidCycleDay.validate(), contains('Cycle day'));
    });

    test('binds the authenticated user id to a new cycle log', () {
      final log = CycleLogFormData(
        date: DateTime(2026, 8, 18),
        flow: FlowLevel.medium,
        cycleDay: 12,
      ).toCycleLog(userId: 'user_123');

      expect(log.userId, equals('user_123'));
    });
  });

  group('CycleTrackingController', () {
    test('filters logs by phase using cycle day bands', () {
      final logs = [
        CycleLog(
          id: '1',
          userId: 'user_1',
          date: DateTime(2026, 8, 1),
          flow: FlowLevel.heavy,
          cycleDay: 1,
        ),
        CycleLog(
          id: '2',
          userId: 'user_1',
          date: DateTime(2026, 8, 10),
          flow: FlowLevel.none,
          cycleDay: 10,
        ),
        CycleLog(
          id: '3',
          userId: 'user_1',
          date: DateTime(2026, 8, 15),
          flow: FlowLevel.light,
          cycleDay: 15,
        ),
      ];

      final filtered = CycleTrackingController().filterLogsByPhase(logs, CyclePhase.menstrual);

      expect(filtered, hasLength(1));
      expect(filtered.single.id, equals('1'));
    });
  });
}
