import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

NotificationLogEntry _entry(String id, {bool read = false}) {
  return NotificationLogEntry(
    id: id,
    type: NotificationType.cycle,
    titleAr: 'عنوان',
    bodyAr: 'نص',
    titleEn: 'Title',
    bodyEn: 'Body',
    createdAt: DateTime(2026, 1, 1),
    read: read,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty until loaded', () async {
    final controller = NotificationLogController.instance;
    await controller.load();
    expect(controller.entries, isEmpty);
    expect(controller.unreadCount, 0);
  });

  test('add persists and is readable after a fresh load', () async {
    final controller = NotificationLogController.instance;
    await controller.load();
    await controller.add(_entry('n1'));

    expect(controller.entries, hasLength(1));
    expect(controller.unreadCount, 1);

    // Simulate a fresh app start reading the same persisted storage.
    await controller.load();
    expect(controller.entries.single.id, 'n1');
  });

  test('newest entries sort first', () async {
    final controller = NotificationLogController.instance;
    await controller.load();
    await controller.add(_entry('older'));
    await controller.add(_entry('newer'));

    expect(controller.entries.first.id, 'newer');
  });

  test('markRead flips only the targeted entry and updates unread count', () async {
    final controller = NotificationLogController.instance;
    await controller.load();
    await controller.add(_entry('a'));
    await controller.add(_entry('b'));

    await controller.markRead('a');

    final a = controller.entries.firstWhere((e) => e.id == 'a');
    final b = controller.entries.firstWhere((e) => e.id == 'b');
    expect(a.read, isTrue);
    expect(b.read, isFalse);
    expect(controller.unreadCount, 1);
  });

  test('markAllRead clears the unread count', () async {
    final controller = NotificationLogController.instance;
    await controller.load();
    await controller.add(_entry('a'));
    await controller.add(_entry('b'));

    await controller.markAllRead();

    expect(controller.unreadCount, 0);
  });
}
