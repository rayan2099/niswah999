import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../data/repositories/activity_notification_repository.dart';
import '../../domain/entities/activity_notification.dart';

class ActivityInboxController extends ChangeNotifier {
  ActivityInboxController();
  static final instance = ActivityInboxController();
  ActivityNotificationRepository? _repository;
  String? _userId;
  void Function()? _unsubscribe;
  int _generation = 0, _readRevision = 0;
  bool loading = false;
  bool unavailable = false;
  List<ActivityNotification> entries = const [];
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  void bind(String? userId, ActivityNotificationRepository? repository) {
    _generation++;
    _readRevision++;
    _unsubscribe?.call();
    _unsubscribe = null;
    _userId = userId;
    _repository = repository;
    entries = const [];
    _unreadCount = 0;
    loading = false;
    unavailable = false;
    notifyListeners();
    _live = null;
    _liveAgain = false;
    if (userId != null && repository != null) {
      _unsubscribe = repository.watch(userId, _changed);
      unawaited(refresh());
    }
  }

  // A bulk read or a burst of activity emits one realtime change per row.
  // At most one reload runs at a time, followed by one more if anything
  // changed meanwhile, instead of a full reload per row.
  Future<void>? _live;
  bool _liveAgain = false;
  void _changed() {
    if (_live != null) {
      _liveAgain = true;
      return;
    }
    final generation = _generation;
    late final Future<void> run;
    run = refresh().whenComplete(() {
      if (!identical(_live, run) || generation != _generation) return;
      _live = null;
      if (_liveAgain) {
        _liveAgain = false;
        _changed();
      }
    });
    _live = run;
  }

  Future<void> refresh() async {
    final user = _userId,
        repo = _repository,
        generation = _generation,
        revision = ++_readRevision;
    if (user == null || repo == null) return;
    loading = true;
    try {
      final (loaded, count) = await (
        repo.load(user),
        repo.unreadCount(user),
      ).wait.timeout(const Duration(seconds: 10));
      if (generation != _generation || revision != _readRevision) return;
      _unreadCount = count < 0 ? 0 : count;
      entries = loaded.where((e) => e.target.userId == user).toList();
      unavailable = false;
    } catch (e, s) {
      if (generation != _generation || revision != _readRevision) return;
      unavailable = true;
      AppErrorReporter.report(
        e,
        s,
        context: 'ActivityInboxController.refresh',
        feature: 'notifications',
      );
    } finally {
      if (generation == _generation && revision == _readRevision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  List<ActivityGroup> get groups => ActivityGroup.of(entries);

  /// Marks [ids] (or everything when null) read immediately in the bell and
  /// badge, then confirms with the server. A failure restores server state.
  Future<void> markRead({List<String>? ids}) async {
    final user = _userId, repo = _repository, generation = _generation;
    if (user == null || repo == null) return;
    final selected = ids?.toSet();
    final changed = entries
        .where((e) => !e.read && (selected == null || selected.contains(e.id)))
        .length;
    final previous = entries, previousCount = _unreadCount;
    // Discard any in-flight load that predates this read.
    _readRevision++;
    entries = [
      for (final e in entries)
        !e.read && (selected == null || selected.contains(e.id))
            ? ActivityNotification(
                id: e.id,
                kind: e.kind,
                target: e.target,
                createdAt: e.createdAt,
                read: true,
              )
            : e,
    ];
    _unreadCount = selected == null
        ? 0
        : (_unreadCount - changed).clamp(0, _unreadCount);
    notifyListeners();
    try {
      await repo
          .markRead(user, ids: ids?.toList())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (generation == _generation) {
        _readRevision++;
        entries = previous;
        _unreadCount = previousCount;
        notifyListeners();
        await refresh();
      }
      rethrow;
    }
    if (generation == _generation) await refresh();
  }

  @override
  void dispose() {
    _generation++;
    _unsubscribe?.call();
    super.dispose();
  }
}
