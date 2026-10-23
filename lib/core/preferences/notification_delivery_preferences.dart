import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_scoped_preferences.dart';

/// Device-local mirror of server activity settings. The server independently
/// enforces the same quiet window for background push.
class NotificationDeliveryPreferences extends ChangeNotifier {
  NotificationDeliveryPreferences._();
  static final instance = NotificationDeliveryPreferences._();
  static const storageKey = 'niswah_notification_delivery';
  bool messages = true, comments = true, likes = false, quietEnabled = false;
  int quietStart = 22 * 60, quietEnd = 8 * 60;
  int _generation = 0;
  void resetInMemory() {
    _generation++;
    messages = true;
    comments = true;
    likes = false;
    quietEnabled = false;
    quietStart = 1320;
    quietEnd = 480;
    notifyListeners();
  }

  bool allows(DateTime local) {
    if (!quietEnabled) return true;
    final minute = local.hour * 60 + local.minute;
    final inside = quietStart < quietEnd
        ? minute >= quietStart && minute < quietEnd
        : minute >= quietStart || minute < quietEnd;
    return !inside;
  }

  Map<String, dynamic> toJson() => {
    'messages': messages,
    'comments': comments,
    'likes': likes,
    'quiet_enabled': quietEnabled,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
  };
  void apply(Map<String, dynamic> data) {
    _generation++;
    final start = data['quiet_start'], end = data['quiet_end'];
    if (start is! int ||
        end is! int ||
        start < 0 ||
        start > 1439 ||
        end < 0 ||
        end > 1439 ||
        start == end ||
        data['messages'] is! bool ||
        data['comments'] is! bool ||
        data['likes'] is! bool ||
        data['quiet_enabled'] is! bool) {
      throw const FormatException('Invalid notification controls');
    }
    messages = data['messages'];
    comments = data['comments'];
    likes = data['likes'];
    quietEnabled = data['quiet_enabled'];
    quietStart = start;
    quietEnd = end;
    notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_generation;
    final key = UserScopedPreferences.key(storageKey);
    final p = await SharedPreferences.getInstance();
    if (generation != _generation ||
        key != UserScopedPreferences.key(storageKey)) {
      return;
    }
    final raw = p.getString(key);
    if (raw == null) return;
    try {
      apply(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      messages = false;
      comments = false;
      likes = false;
    }
  }

  Future<void> save({Map<String, dynamic>? snapshot}) async {
    _generation++;
    final key = UserScopedPreferences.key(storageKey),
        data = jsonEncode(snapshot ?? toJson());
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(key, data)) {
      throw StateError('Notification controls were not saved');
    }
  }
}
