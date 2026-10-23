import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/notification_delivery_preferences.dart';
import 'package:niswah/features/notifications/domain/entities/notification_target.dart';
import 'package:niswah/features/notifications/domain/entities/activity_notification.dart';
import 'package:niswah/features/notifications/data/repositories/activity_notification_repository.dart';
import 'package:niswah/features/notifications/presentation/viewmodels/activity_inbox_controller.dart';

class ActivityRepo implements ActivityNotificationRepository {
  List<ActivityNotification> rows = [];
  Completer<List<ActivityNotification>>? held;
  VoidCallback? changed;
  bool fail = false, cancelled = false;
  @override
  Future<List<ActivityNotification>> load(String user) async {
    if (held != null) return held!.future;
    if (fail) throw StateError('offline');
    return rows;
  }

  @override
  Future<int> unreadCount(String user) async =>
      rows.where((e) => !e.read && e.target.userId == user).length;

  @override
  Future<void> markRead(String user, {String? id}) async {
    if (fail) throw StateError('offline');
    rows = [
      for (final e in rows)
        ActivityNotification(
          id: e.id,
          kind: e.kind,
          target: e.target,
          createdAt: e.createdAt,
          read: id == null || id == e.id ? true : e.read,
        ),
    ];
  }

  @override
  void Function() watch(String user, void Function() onChanged) {
    changed = onChanged;
    return () => cancelled = true;
  }
}

ActivityNotification event(String id, String user) => ActivityNotification(
  id: id,
  kind: 'privateMessage',
  target: NotificationTarget(
    destination: NotificationDestination.conversation,
    userId: user,
    targetId: 'thread',
  ),
  createdAt: DateTime.utc(2030),
);
Future<void> drain() => Future<void>.delayed(Duration.zero);
void main() {
  test('stale account fetch cannot restore the previous inbox', () async {
    final old = ActivityRepo()..held = Completer();
    final next = ActivityRepo()..rows = [event('new', 'b')];
    final controller = ActivityInboxController();
    controller.bind('a', old);
    controller.bind('b', next);
    await drain();
    old.held!.complete([event('old', 'a')]);
    await drain();
    expect(controller.entries.single.id, 'new');
    expect(old.cancelled, true);
    controller.dispose();
  });
  test(
    'live refresh updates badge, filters foreign recipients and persists reads',
    () async {
      final repo = ActivityRepo()
        ..rows = [event('one', 'a'), event('foreign', 'b')];
      final c = ActivityInboxController();
      c.bind('a', repo);
      await drain();
      expect(c.unreadCount, 1);
      repo.rows = [event('two', 'a'), event('three', 'a')];
      repo.changed!();
      await drain();
      expect(c.unreadCount, 2);
      await c.markRead(id: 'two');
      expect(c.unreadCount, 1);
      await c.markRead();
      expect(c.unreadCount, 0);
      c.dispose();
    },
  );
  test('failed refresh keeps known activity and exposes unavailable instead of empty success', () async {
    final repo = ActivityRepo()..rows = [event('one', 'a')];
    final c = ActivityInboxController();
    c.bind('a', repo);
    await drain();
    repo.fail = true;
    await c.refresh();
    expect(c.unavailable, true);
    expect(c.entries.length, 1);
    c.bind(null, null);
    expect(c.entries, isEmpty);
    expect(c.loading, false);
    c.dispose();
  });
  test('all supported targets round-trip; arbitrary URLs and malformed IDs are rejected', () {
    for (final destination in NotificationDestination.values) {
      final t = NotificationTarget(
        destination: destination,
        userId: 'a',
        targetId: 'target',
      );
      expect(NotificationTarget.tryParse(t.toJson())!.destination, destination);
    }
    for (final value in [
      null,
      {},
      {'destination': 'https://attacker.test', 'userId': 'a'},
      {'destination': 'conversation', 'userId': 'a'},
      {'destination': 'post', 'userId': 4, 'targetId': 'p'},
      {'destination': 'post', 'userId': 'a', 'targetId': 'x' * 129},
    ]) {
      expect(NotificationTarget.tryParse(value), isNull);
    }
  });
  test(
    'quiet window crosses midnight and uses inclusive start/exclusive end',
    () {
      final p = NotificationDeliveryPreferences.instance;
      p.resetInMemory();
      p.apply({
        ...p.toJson(),
        'quiet_enabled': true,
        'quiet_start': 1320,
        'quiet_end': 480,
      });
      expect(p.allows(DateTime(2030, 1, 1, 21, 59)), true);
      expect(p.allows(DateTime(2030, 1, 1, 22)), false);
      expect(p.allows(DateTime(2030, 1, 2, 7, 59)), false);
      expect(p.allows(DateTime(2030, 1, 2, 8)), true);
      expect(
        () => p.apply({...p.toJson(), 'quiet_end': 1320}),
        throwsFormatException,
      );
      p.resetInMemory();
    },
  );
}
