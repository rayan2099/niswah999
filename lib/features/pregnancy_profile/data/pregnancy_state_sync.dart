import 'package:flutter/material.dart';

import '../../../core/errors/app_error_reporter.dart';
import '../../../core/localization/app_locale_controller.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/preferences/pregnancy_status_controller.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/calendar_days.dart';
import '../../notifications/domain/services/notification_refresh_coordinator.dart';
import 'repositories/pregnancy_profile_repository.dart';

/// The one place every pregnancy/nifas state change goes through
/// (2026-10-21, proposed). Before this, each screen changed the on-device
/// [PregnancyStatusController] and — only for some changes — the Supabase
/// `pregnancy_profile` row, and nothing re-planned the reminders, so:
/// - turning pregnancy or nifas OFF never reached the server row, and
///   notifications, the reports and the AI context kept treating her as
///   pregnant/postpartum;
/// - a pregnancy-week reminder already scheduled could still fire after
///   "Log birth" until the app was next resumed.
///
/// Every change here updates the device store, mirrors it to the row when
/// a user is signed in, and then refreshes the scheduled reminders.
///
/// Not a pregnancy-loss flow — none exists; one needs scholar and medical
/// review before it is designed.
class PregnancyStateSync {
  PregnancyStateSync({
    PregnancyProfileRepository? repository,
    String? Function()? currentUserId,
    Future<void> Function(String? userId)? refreshNotifications,
    PregnancyStatusController? controller,
  }) : _repository = repository,
       _currentUserId = currentUserId ?? _signedInUserId,
       _refreshNotifications =
           refreshNotifications ?? _defaultRefreshNotifications,
       _controller = controller ?? PregnancyStatusController.instance;

  final PregnancyProfileRepository? _repository;
  final String? Function() _currentUserId;
  final Future<void> Function(String? userId) _refreshNotifications;
  final PregnancyStatusController _controller;

  PregnancyProfileRepository get _repo =>
      _repository ?? PregnancyProfileRepository();

  static String? _signedInUserId() =>
      NiswahSupabase.clientOrNull?.auth.currentUser?.id;

  static Future<void> _defaultRefreshNotifications(String? userId) =>
      NotificationRefreshCoordinator.refresh(userId: userId);

  /// Starts nifas from [birthDate] (default today; a future date throws
  /// [ArgumentError] before anything changes). Returns false only when the
  /// server row could not be updated — the device state still changed.
  Future<bool> startNifas({DateTime? birthDate}) async {
    final birthDay = calendarDay(birthDate ?? AppClock.now());
    await _controller.startNifas(birthDate: birthDay);
    final synced = await _mirror(
      'PregnancyStateSync.startNifas',
      (userId) => _repo.markPostpartumStarted(userId, startDate: birthDay),
    );
    await refreshNotifications();
    return synced;
  }

  /// Turns pregnancy AND nifas tracking off (both profile toggles).
  /// Returns false only when the server row could not be cleared.
  Future<bool> deactivate() async {
    await _controller.deactivate();
    final synced = await _mirror(
      'PregnancyStateSync.deactivate',
      _repo.markTrackingEnded,
    );
    await refreshNotifications();
    return synced;
  }

  /// Re-plans every reminder for the signed-in user. Never throws.
  Future<void> refreshNotifications() async {
    try {
      await _refreshNotifications(_currentUserId());
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'PregnancyStateSync.refreshNotifications',
        feature: 'notifications',
      );
    }
  }

  Future<bool> _mirror(
    String context,
    Future<void> Function(String userId) write,
  ) async {
    final userId = _currentUserId();
    if (userId == null) return true;
    try {
      await write(userId);
      return true;
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: context,
        feature: 'pregnancy_profile',
      );
      return false;
    }
  }
}

/// Birth-date picker for "Log birth" / "Postpartum Mode": defaults to today
/// and never allows a future date. Null when she cancels.
Future<DateTime?> pickBirthDate(BuildContext context) {
  final today = calendarDay(AppClock.now());
  return showDatePicker(
    context: context,
    initialDate: today,
    firstDate: addCalendarDays(today, -365),
    lastDate: today,
    helpText: AppLocaleController.instance.text(
      'Date of birth (delivery)',
      'تاريخ الولادة',
    ),
  );
}
