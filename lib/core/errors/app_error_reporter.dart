import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';

/// Single funnel for uncaught/reported errors app-wide.
///
/// Exists so every current catch-all (the zone guard, `FlutterError.onError`,
/// `PlatformDispatcher.instance.onError` in `main.dart`, and every repository
/// catch block that used to call `print`/`debugPrint` independently) reports
/// through one place — the exact gap `RR-002`/`OB-002`/`OB-006` identified.
///
/// [onReport] is a pluggable hook: a future crash-reporting SDK (Sentry,
/// Crashlytics, etc.) wires in here without any of the ~40+ call sites
/// needing to change. **No such sink is configured yet** — until one is,
/// this funnel only reaches `debugPrint` (visible in local/debug runs, not
/// in a release build a real user would run) and whatever `onReport` a
/// future release wires in. That gap (no *deployed* monitoring backend) is
/// a Release/Observability owner action — see `OB` remediation plan R1-1 —
/// not something this funnel can close by itself.
///
/// Deliberately excludes from every field below: auth tokens, API/service
/// keys, full health-record content, and any other PII beyond an opaque
/// record id. Callers are responsible for not passing those in `recordId`
/// or embedding them in `feature`/`context`.
class AppErrorReporter {
  const AppErrorReporter._();

  static void Function(
    Object error,
    StackTrace? stack, {
    String? context,
    String? feature,
    int? retryAttempt,
    String? recordId,
  })?
  onReport;

  /// [context] — operation/repository, e.g. `'CycleTrackingRepositoryImpl.saveCycleLog'`.
  /// [feature] — the product feature area, e.g. `'cycle_tracking'`, for
  /// grouping/filtering once a real sink is attached.
  /// [retryAttempt] — which attempt this is, when reported from inside a
  /// retry path (e.g. `syncPendingLogs`) — omit for a first/only attempt.
  /// [recordId] — an opaque identifier (e.g. a `CycleLog.id`) *only* when
  /// safe to log — never the record's content.
  static void report(
    Object error,
    StackTrace? stack, {
    String? context,
    String? feature,
    int? retryAttempt,
    String? recordId,
  }) {
    if (kDebugMode) {
      final parts = <String>[
        if (context != null) 'context=$context',
        if (feature != null) 'feature=$feature',
        if (retryAttempt != null) 'retryAttempt=$retryAttempt',
        if (recordId != null) 'recordId=$recordId',
        'env=${AppEnvironment.appEnvironment}',
      ];
      debugPrint('Unhandled error [${parts.join(', ')}]: $error\n$stack');
    }
    onReport?.call(
      error,
      stack,
      context: context,
      feature: feature,
      retryAttempt: retryAttempt,
      recordId: recordId,
    );
  }
}
