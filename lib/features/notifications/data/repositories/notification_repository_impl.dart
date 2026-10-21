import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/preferences/user_scoped_preferences.dart';
import '../../../../core/errors/app_error_reporter.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({this.preferences});

  final SharedPreferences? preferences;

  static Future<void>? _saveTail;

  static const String _key = 'niswah_notification_preferences';

  static final Map<NotificationType, NotificationPreference> _defaults = {
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
    // Commit E2 — unlike every other type here, default OFF: this one
    // requires an explicit, contextual "would you like reminders while
    // tracking?" ask (see the Start Bleeding sheet's own consent prompt),
    // never a silent opt-in.
    NotificationType.activeBleeding: const NotificationPreference(
      type: NotificationType.activeBleeding,
      enabled: false,
      leadTimeMinutes: 0,
      channels: ['local'],
    ),
  };

  @override
  Future<Map<NotificationType, NotificationPreference>>
  loadPreferences() async {
    final key = UserScopedPreferences.key(_key);
    final pendingSave = _saveTail;
    if (pendingSave != null) await pendingSave;
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (key != UserScopedPreferences.key(_key)) return _disabledDefaults();
    await UserScopedPreferences.adoptLegacy(prefs, const [_key]);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return Map.of(_defaults);
    }

    try {
      final decodedList = jsonDecode(raw) as List<dynamic>;
      final decoded = <NotificationType, NotificationPreference>{};
      for (final item in decodedList) {
        try {
          final preference = NotificationPreference.fromJson(
            item as Map<String, dynamic>,
          );
          decoded[preference.type] = preference;
        } catch (error, stack) {
          // Unknown records cannot masquerade as prayer preferences; a bad
          // known record fails closed without discarding other valid choices.
          final type = item is Map
              ? NotificationType.values
                    .where((t) => t.name == item['type'])
                    .firstOrNull
              : null;
          if (type != null) {
            decoded[type] = _defaults[type]!.copyWith(enabled: false);
          }
          AppErrorReporter.report(
            const FormatException(
              'Invalid notification preference quarantined',
            ),
            stack,
            context: 'NotificationRepositoryImpl.loadPreferences',
          );
        }
      }
      // Fills in any type added after this was last saved (e.g. wellbeing)
      // with its default rather than leaving it missing.
      return {..._defaults, ...decoded};
    } catch (error, stack) {
      AppErrorReporter.report(
        const FormatException('Notification settings could not be decoded'),
        stack,
        context: 'NotificationRepositoryImpl.loadPreferences',
      );
      return _disabledDefaults();
    }
  }

  static Map<NotificationType, NotificationPreference> _disabledDefaults() => {
    for (final entry in _defaults.entries)
      entry.key: entry.value.copyWith(enabled: false),
  };

  @override
  Future<void> savePreferences(
    Map<NotificationType, NotificationPreference> preferences,
  ) {
    final key = UserScopedPreferences.key(_key);
    final encoded = jsonEncode(
      preferences.values.map((preference) {
        NotificationPreference.fromJson(
          preference.toJson(),
        ); // validate before persisting
        return preference.toJson();
      }).toList(),
    );
    final operation = (_saveTail ?? Future<void>.value()).then((_) async {
      final prefs = this.preferences ?? await SharedPreferences.getInstance();
      if (!await prefs.setString(key, encoded)) {
        throw StateError('Notification settings were not saved');
      }
    });
    final settled = operation.catchError((Object _) {});
    _saveTail = settled;
    settled.then((_) {
      if (identical(_saveTail, settled)) _saveTail = null;
    });
    return operation;
  }
}
