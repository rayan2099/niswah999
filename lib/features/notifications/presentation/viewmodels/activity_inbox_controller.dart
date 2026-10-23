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
    if (userId != null && repository != null) {
      _unsubscribe = repository.watch(userId, () => unawaited(refresh()));
      unawaited(refresh());
    }
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

  Future<void> markRead({String? id}) async {
    final user = _userId, repo = _repository, generation = _generation;
    if (user == null || repo == null) return;
    await repo.markRead(user, id: id).timeout(const Duration(seconds: 10));
    if (generation == _generation) await refresh();
  }

  @override
  void dispose() {
    _generation++;
    _unsubscribe?.call();
    super.dispose();
  }
}
