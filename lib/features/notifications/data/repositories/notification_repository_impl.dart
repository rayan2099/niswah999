import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({this.preferences});

  final SharedPreferences? preferences;

  static const String _key = 'niswah_notification_preferences';

  static final Map<NotificationType, NotificationPreference> _defaults = {
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

  @override
  Future<Map<NotificationType, NotificationPreference>>
  loadPreferences() async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return Map.of(_defaults);
    }

    try {
      final decodedList = jsonDecode(raw) as List<dynamic>;
      final decoded = <NotificationType, NotificationPreference>{};
      for (final item in decodedList) {
        final preference = NotificationPreference.fromJson(
          item as Map<String, dynamic>,
        );
        decoded[preference.type] = preference;
      }
      // Fills in any type added after this was last saved (e.g. wellbeing)
      // with its default rather than leaving it missing.
      return {..._defaults, ...decoded};
    } catch (_) {
      return Map.of(_defaults);
    }
  }

  @override
  Future<void> savePreferences(
    Map<NotificationType, NotificationPreference> preferences,
  ) async {
    final prefs = this.preferences ?? await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      preferences.values.map((preference) => preference.toJson()).toList(),
    );
    await prefs.setString(_key, encoded);
  }
}
