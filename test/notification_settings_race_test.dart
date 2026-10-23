import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:niswah/features/notifications/domain/repositories/notification_repository.dart';
import 'package:niswah/features/notifications/presentation/viewmodels/notification_settings_view_model.dart';

class MemoryPreferences implements NotificationRepository {
  bool fail = false;
  Map<NotificationType, NotificationPreference> stored = {};
  @override
  Future<Map<NotificationType, NotificationPreference>>
  loadPreferences() async => stored;
  @override
  Future<void> savePreferences(
    Map<NotificationType, NotificationPreference> p,
  ) async {
    if (fail) throw StateError('disk full');
    stored = Map.of(p);
  }
}

void main() {
  test('late permission approval cannot restore a newer opt-out', () async {
    final repo = MemoryPreferences();
    final permission = Completer<bool>();
    final asked = Completer<void>();
    var refreshes = 0;
    final vm = NotificationSettingsViewModel(
      repository: repo,
      currentUserId: () => 'u',
      requestPermission: () {
        asked.complete();
        return permission.future;
      },
      refresh: (_) async {
        refreshes++;
      },
    );
    final enabling = vm.updatePreference(
      type: NotificationType.prayer,
      enabled: true,
      leadTimeMinutes: 15,
    );
    await asked.future;
    expect(refreshes, 0);
    await vm.updatePreference(
      type: NotificationType.prayer,
      enabled: false,
      leadTimeMinutes: 15,
    );
    permission.complete(true);
    await enabling;
    expect(repo.stored[NotificationType.prayer]!.enabled, isFalse);
    expect(refreshes, 1);
    vm.dispose();
  });
  test('persistence failure rolls switch back without reconciling', () async {
    final repo = MemoryPreferences()..fail = true;
    var refreshes = 0;
    final vm = NotificationSettingsViewModel(
      repository: repo,
      currentUserId: () => 'u',
      refresh: (_) async {
        refreshes++;
      },
      requestPermission: () async => true,
    );
    await vm.updatePreference(
      type: NotificationType.prayer,
      enabled: true,
      leadTimeMinutes: 15,
    );
    expect(vm.preferences[NotificationType.prayer]!.enabled, isFalse);
    expect(vm.errorMessage, 'save');
    expect(refreshes, 0);
    vm.dispose();
  });
  test(
    'disposed settings complete persisted intent without notifying dead UI',
    () async {
      final permission = Completer<bool>();
      final asked = Completer<void>();
      var refreshed = false;
      final vm = NotificationSettingsViewModel(
        repository: MemoryPreferences(),
        currentUserId: () => 'u',
        refresh: (_) async {
          refreshed = true;
        },
        requestPermission: () {
          asked.complete();
          return permission.future;
        },
      );
      final update = vm.updatePreference(
        type: NotificationType.prayer,
        enabled: true,
        leadTimeMinutes: 15,
      );
      await asked.future;
      vm.dispose();
      permission.complete(true);
      await update;
      expect(refreshed, isTrue);
    },
  );
}
