import '../../features/notifications/domain/entities/notification_target.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notifications/domain/entities/notification_preference.dart';
import '../utils/app_clock.dart';
import '../services/notification_service.dart';
import 'user_scoped_preferences.dart';

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
    this.fireAt,
    this.target,
  });

  final String id;
  final NotificationType type;
  final NotificationTarget? target;
  final String titleAr;
  final String bodyAr;
  final String titleEn;
  final String bodyEn;
  final DateTime createdAt;
  final bool read;

  /// When the scheduled OS notification this entry mirrors is due to fire
  /// (2026-10-21, proposed). Null for entries that describe something that
  /// already happened when they were added. A future [fireAt] keeps the
  /// entry out of the feed — and out of the unread count — until then, so
  /// the feed never shows a reminder before it fires.
  final DateTime? fireAt;

  /// The time the feed shows for this entry.
  DateTime get shownAt => fireAt ?? createdAt;

  bool isVisibleAt(DateTime now) => fireAt == null || !fireAt!.isAfter(now);

  NotificationLogEntry copyWith({bool? read}) => NotificationLogEntry(
    id: id,
    type: type,
    titleAr: titleAr,
    bodyAr: bodyAr,
    titleEn: titleEn,
    bodyEn: bodyEn,
    createdAt: createdAt,
    read: read ?? this.read,
    fireAt: fireAt,
    target: target,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (target != null) 'target': target!.toJson(),
    'type': type.name,
    'title_ar': titleAr,
    'body_ar': bodyAr,
    'title_en': titleEn,
    'body_en': bodyEn,
    'created_at': createdAt.toIso8601String(),
    'read': read,
    if (fireAt != null) 'fire_at': fireAt!.toIso8601String(),
  };

  factory NotificationLogEntry.fromJson(Map<String, dynamic> json) {
    return NotificationLogEntry(
      target: NotificationTarget.tryParse(json['target']),
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
      fireAt: DateTime.tryParse(json['fire_at'] as String? ?? ''),
    );
  }
}

/// Local history of accepted schedules and in-app alerts. Due entries
/// become visible by their planned time; this is not a delivery receipt. Not a settings screen (see
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
  int _generation = 0;
  Future<void>? _writeTail;

  /// Fires when the nearest not-yet-fired entry becomes visible, so an
  /// open feed (and the bell's unread count) updates at its fire time
  /// instead of waiting for some unrelated change.
  Timer? _revealTimer;

  @override
  void notifyListeners() {
    _planReveal();
    super.notifyListeners();
  }

  void _planReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    final now = AppClock.now();
    DateTime? nearest;
    for (final entry in _entries) {
      final fireAt = entry.fireAt;
      if (fireAt == null || !fireAt.isAfter(now)) continue;
      if (nearest == null || fireAt.isBefore(nearest)) nearest = fireAt;
    }
    if (nearest == null) return;
    _revealTimer = Timer(nearest.difference(now), notifyListeners);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _revealTimer = null;
    super.dispose();
  }

  /// What the feed shows: entries whose reminder is due (or that never
  /// had a fire time), newest first by [NotificationLogEntry.shownAt].
  List<NotificationLogEntry> get entries {
    final now = AppClock.now();
    return _entries.where((entry) => entry.isVisibleAt(now)).toList()
      ..sort((a, b) => b.shownAt.compareTo(a.shownAt));
  }

  /// Every stored entry, including ones still waiting for their fire time
  /// — for de-duplication only, never for display.
  List<NotificationLogEntry> get allEntries => _entries;

  int get unreadCount => entries.where((entry) => !entry.read).length;

  /// Reads the signed-in user's own feed (never another user's).
  Future<void> load() async {
    final generation = ++_generation;
    final key = UserScopedPreferences.key(_storageKey);
    final preferences = await SharedPreferences.getInstance();
    if (generation != _generation ||
        key != UserScopedPreferences.key(_storageKey)) {
      return;
    }
    await UserScopedPreferences.adoptLegacy(preferences, const [_storageKey]);
    if (generation != _generation ||
        key != UserScopedPreferences.key(_storageKey)) {
      return;
    }
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) {
      _entries = const [];
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _entries =
          decoded
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

  /// Forgets the in-memory feed (sign-out) so the next account can never
  /// observe it before its own [load] completes.
  void resetInMemory() {
    _generation++;
    _entries = const [];
    notifyListeners();
  }

  /// Records the feed entry for a scheduled reminder in [slot] (e.g. its
  /// OS notification id). Any entry for the same slot that has NOT fired
  /// yet is replaced — a reschedule moves the reminder, it never adds a
  /// second one — and an entry with the same [NotificationLogEntry.id] is
  /// never added twice. Entries that already fired are history and stay.
  Future<void> upsertScheduled(String slot, NotificationLogEntry entry) async {
    if (!NotificationService.instance.isWorkCurrent) return;
    final now = AppClock.now();
    final kept = [
      for (final existing in _entries)
        if (!(_inSlot(existing, slot) && !existing.isVisibleAt(now))) existing,
    ];
    if (kept.any((existing) => existing.id == entry.id)) {
      if (kept.length == _entries.length) return;
      _entries = kept;
    } else {
      _entries = [entry, ...kept];
    }
    notifyListeners();
    await _persist();
  }

  /// Drops not-yet-fired entries for [slot] — its reminder was cancelled,
  /// so it must never surface in the feed later.
  Future<void> removePending(String slot) async {
    if (!NotificationService.instance.isWorkCurrent) return;
    final now = AppClock.now();
    final kept = [
      for (final existing in _entries)
        if (!(_inSlot(existing, slot) && !existing.isVisibleAt(now))) existing,
    ];
    if (kept.length == _entries.length) return;
    _entries = kept;
    notifyListeners();
    await _persist();
  }

  static bool _inSlot(NotificationLogEntry entry, String slot) =>
      entry.id == slot || entry.id.startsWith('${slot}_');

  Future<void> add(NotificationLogEntry entry) async {
    if (!NotificationService.instance.isWorkCurrent) return;
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
    final now = AppClock.now();
    _entries = [
      for (final entry in _entries)
        entry.isVisibleAt(now) ? entry.copyWith(read: true) : entry,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() {
    final key = UserScopedPreferences.key(_storageKey);
    final encoded = jsonEncode(
      _entries.map((entry) => entry.toJson()).toList(),
    );
    final operation = (_writeTail ?? Future<void>.value()).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, encoded);
    });
    final settled = operation.catchError((Object _) {});
    _writeTail = settled;
    settled.then((_) {
      if (identical(_writeTail, settled)) _writeTail = null;
    });
    return operation;
  }
}
