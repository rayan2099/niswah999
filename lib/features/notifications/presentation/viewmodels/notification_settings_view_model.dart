import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/services/notification_service.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';

class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({NotificationRepository? repository})
    : _repository = repository ?? NotificationRepositoryImpl();

  final NotificationRepository _repository;

  bool isLoading = false;
  String? errorMessage;
  Map<NotificationType, NotificationPreference> preferences = {
    NotificationType.prayer: const NotificationPreference(
      type: NotificationType.prayer,
      enabled: true,
      leadTimeMinutes: 15,
      channels: ['local'],
    ),
    NotificationType.cycle: const NotificationPreference(
      type: NotificationType.cycle,
      enabled: true,
      leadTimeMinutes: 30,
      channels: ['local'],
    ),
    NotificationType.pregnancy: const NotificationPreference(
      type: NotificationType.pregnancy,
      enabled: true,
      leadTimeMinutes: 60,
      channels: ['local'],
    ),
    NotificationType.wellbeing: const NotificationPreference(
      type: NotificationType.wellbeing,
      enabled: true,
      leadTimeMinutes: 0,
      channels: ['local'],
    ),
  };

  Future<void> loadPreferences() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      preferences = await _repository.loadPreferences();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePreference({
    required NotificationType type,
    required bool enabled,
    required int leadTimeMinutes,
    List<String>? channels,
    int? preferredHour,
    int? preferredMinute,
  }) async {
    final current =
        preferences[type] ??
        NotificationPreference(
          type: type,
          enabled: enabled,
          leadTimeMinutes: leadTimeMinutes,
          channels: channels ?? const <String>['local'],
        );

    final updated = current.copyWith(
      enabled: enabled,
      leadTimeMinutes: leadTimeMinutes,
      channels: channels ?? current.channels,
      preferredHour: preferredHour ?? current.preferredHour,
      preferredMinute: preferredMinute ?? current.preferredMinute,
    );

    preferences = {...preferences, type: updated};
    notifyListeners();

    if (enabled) {
      // Contextual — only ever prompted when a user actually turns a
      // reminder on, not unconditionally at app launch.
      unawaited(NotificationService.instance.requestPermission());
    }

    try {
      await _repository.savePreferences(preferences);
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }
}
