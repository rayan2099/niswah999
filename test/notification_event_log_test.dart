import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/features/notifications/data/local/notification_event_log_store.dart';
import 'package:niswah/features/notifications/domain/entities/notification_event.dart';

/// Closure Blocker 13 — the structural scheduling-audit trail, distinct
/// from NotificationLogController's own display feed. Proves the two
/// explicitly required transitions from the adversarial matrix:
/// scheduled → opened → responded, and scheduled → cancelled.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  NotificationEvent event(
    NotificationEventState state, {
    String id = 'r-1',
    DateTime? at,
  }) => NotificationEvent(
    reminderId: id,
    notificationType: 'activeBleeding',
    state: state,
    eventTimestamp: at ?? DateTime(2026, 9, 19, 18, 0),
    userId: 'user-1',
    episodeId: 'episode-1',
    logicalLocalDate: '2026-09-19',
  );

  group('NotificationEventLogStore', () {
    test('scheduled -> opened -> responded records the full lifecycle in '
        'order for one reminder id', () async {
      await NotificationEventLogStore.record(
        event(NotificationEventState.scheduled, at: DateTime(2026, 9, 19, 8)),
      );
      await NotificationEventLogStore.record(
        event(NotificationEventState.opened, at: DateTime(2026, 9, 19, 18)),
      );
      await NotificationEventLogStore.record(
        event(
          NotificationEventState.responded,
          at: DateTime(2026, 9, 19, 18, 2),
        ),
      );

      final history = await NotificationEventLogStore.loadForReminder('r-1');

      expect(history, hasLength(3));
      expect(history.map((e) => e.state), [
        NotificationEventState.scheduled,
        NotificationEventState.opened,
        NotificationEventState.responded,
      ]);
    });

    test('scheduled -> cancelled records both transitions for one '
        'reminder id', () async {
      await NotificationEventLogStore.record(
        event(NotificationEventState.scheduled, at: DateTime(2026, 9, 19, 8)),
      );
      await NotificationEventLogStore.record(
        event(NotificationEventState.cancelled, at: DateTime(2026, 9, 19, 12)),
      );

      final history = await NotificationEventLogStore.loadForReminder('r-1');

      expect(history, hasLength(2));
      expect(history.map((e) => e.state), [
        NotificationEventState.scheduled,
        NotificationEventState.cancelled,
      ]);
    });

    test('never stores sensitive health content — only structural fields '
        'round-trip', () async {
      await NotificationEventLogStore.record(
        event(NotificationEventState.scheduled),
      );

      final json = (await NotificationEventLogStore.loadForReminder('r-1'))
          .single
          .toJson();

      expect(json.keys, containsAll(['reminder_id', 'state', 'user_id']));
      expect(
        json.values.any((v) => v.toString().toLowerCase().contains('flow')),
        isFalse,
      );
    });

    test('events for a different reminder id are isolated', () async {
      await NotificationEventLogStore.record(
        event(NotificationEventState.scheduled, id: 'r-1'),
      );
      await NotificationEventLogStore.record(
        event(NotificationEventState.scheduled, id: 'r-2'),
      );

      expect(
        await NotificationEventLogStore.loadForReminder('r-1'),
        hasLength(1),
      );
      expect(
        await NotificationEventLogStore.loadForReminder('r-2'),
        hasLength(1),
      );
    });

    test('a malformed persisted record is quarantined, not crashed on', () {
      final parsed = NotificationEvent.tryFromJson({
        'reminder_id': 'r-1',
        'notification_type': 'activeBleeding',
        'state': 'not_a_real_state',
        'event_timestamp': DateTime(2026, 9, 19).toIso8601String(),
      });
      expect(parsed, isNull);
    });

    test('loadAll on an empty store returns an empty list', () async {
      expect(await NotificationEventLogStore.loadAll(), isEmpty);
    });
  });
}
