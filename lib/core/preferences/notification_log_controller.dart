import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notifications/domain/entities/notification_preference.dart';

class NotificationLogEntry {
  const NotificationLogEntry({
    required this.id,
    required this.type,
    required this.titleAr,
    required this.bodyAr,
    required this.titleEn,
    required this.bodyEn,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final NotificationType type;
  final String titleAr;
  final String bodyAr;
  final String titleEn;
  final String bodyEn;
  final DateTime createdAt;
  final bool read;

  NotificationLogEntry copyWith({bool? read}) => NotificationLogEntry(
    id: id,
    type: type,
    titleAr: titleAr,
    bodyAr: bodyAr,
    titleEn: titleEn,
    bodyEn: bodyEn,
    createdAt: createdAt,
    read: read ?? this.read,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title_ar': titleAr,
    'body_ar': bodyAr,
    'title_en': titleEn,
    'body_en': bodyEn,
    'created_at': createdAt.toIso8601String(),
    'read': read,
  };

  factory NotificationLogEntry.fromJson(Map<String, dynamic> json) {
    return NotificationLogEntry(
      id: json['id'] as String? ?? '',
      type: NotificationType.values.firstWhere(
        (value) => value.name == (json['type'] as String? ?? ''),
        orElse: () => NotificationType.wellbeing,
      ),
      titleAr: json['title_ar'] as String? ?? '',
      bodyAr: json['body_ar'] as String? ?? '',
      titleEn: json['title_en'] as String? ?? '',
      bodyEn: json['body_en'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
    );
  }
}

/// Local, on-device history of notifications this app has actually
/// scheduled/fired — what the bell icon shows. Not a settings screen (see
/// [NotificationSettingsScreen] for that, now reached from Profile).
/// Follows this codebase's `core/preferences/*_controller.dart` pattern
/// (ChangeNotifier singleton, persists directly to SharedPreferences as
/// real JSON) rather than a separate repository layer.
class NotificationLogController extends ChangeNotifier {
  NotificationLogController._();

  static final NotificationLogController instance =
      NotificationLogController._();

  static const _storageKey = 'niswah_notification_log';

  List<NotificationLogEntry> _entries = const [];

  List<NotificationLogEntry> get entries => _entries;

  int get unreadCount => _entries.where((entry) => !entry.read).length;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _entries = const [];
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _entries = decoded
          .map(
            (item) =>
                NotificationLogEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      _entries = const [];
    }
    notifyListeners();
  }

  Future<void> add(NotificationLogEntry entry) async {
    _entries = [entry, ..._entries];
    notifyListeners();
    await _persist();
  }

  Future<void> markRead(String id) async {
    _entries = [
      for (final entry in _entries)
        if (entry.id == id) entry.copyWith(read: true) else entry,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> markAllRead() async {
    _entries = [for (final entry in _entries) entry.copyWith(read: true)];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries.map((entry) => entry.toJson()).toList(),
    );
    await preferences.setString(_storageKey, encoded);
  }
}
