import '../../data/services/app_notification_session.dart';

import 'package:flutter/foundation.dart';

import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/notification_service.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/services/notification_refresh_coordinator.dart';

class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({
    NotificationRepository? repository,
    Future<bool> Function()? requestPermission,
    Future<void> Function(String? userId)? refresh,
    String? Function()? currentUserId,
  }) : _repository = repository ?? NotificationRepositoryImpl(),
       _requestPermission =
           requestPermission ?? NotificationService.instance.requestPermission,
       _refresh =
           refresh ??
           ((userId) => NotificationRefreshCoordinator.refresh(userId: userId)),
       _currentUserId =
           currentUserId ??
           (() => NiswahSupabase.clientOrNull?.auth.currentUser?.id);

  final Future<bool> Function() _requestPermission;
  final Future<void> Function(String? userId) _refresh;
  final String? Function() _currentUserId;
  Future<void> _saveTail = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;
  bool? permissionGranted;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  final NotificationRepository _repository;

  bool isLoading = false;
  String? errorMessage;
  Map<NotificationType, NotificationPreference> preferences = {
    NotificationType.prayer: const NotificationPreference(
      type: NotificationType.prayer,
      enabled: false,
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
    final revision = _revision;
    final generation = NotificationService.instance.sessionGeneration;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loaded = await _repository.loadPreferences();
      if (revision == _revision &&
          generation == NotificationService.instance.sessionGeneration) {
        preferences = loaded;
      }
    } catch (_) {
      if (revision == _revision) errorMessage = 'load';
    } finally {
      if (revision == _revision) {
        isLoading = false;
        _notify();
      }
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
          enabled: false,
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

    // Snapshot the account and order writes before any permission dialog.
    final userId = _currentUserId();
    final generation = NotificationService.instance.sessionGeneration;
    final revision = ++_revision;
    bool isCurrent() =>
        revision == _revision &&
        generation == NotificationService.instance.sessionGeneration &&
        userId == _currentUserId();
    final previous = preferences;
    final snapshot = {...preferences, type: updated};
    try {
      NotificationPreference.fromJson(updated.toJson());
    } catch (_) {
      errorMessage = 'invalid';
      _notify();
      return;
    }
    preferences = snapshot;
    isLoading = false;
    errorMessage = null;
    _notify();
    final saved = _saveTail.then((_) => _repository.savePreferences(snapshot));
    _saveTail = saved.catchError((Object _) {});
    var persisted = false;
    try {
      await saved;
      persisted = true;
      if (!isCurrent()) return;
      if (enabled && !current.enabled) {
        permissionGranted = await _requestPermission();
        if (!isCurrent()) return;
        await AppNotificationSession.instance.refreshRegistration();
      }
      await _refresh(userId);
    } catch (_) {
      if (isCurrent()) {
        if (!persisted) preferences = previous;
        errorMessage = 'save';
        _notify();
      }
      return;
    }
    if (isCurrent()) _notify();
  }
}
