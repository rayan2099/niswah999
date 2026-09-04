import 'package:flutter/foundation.dart';

/// Single funnel for uncaught/reported errors app-wide.
///
/// Exists so every current catch-all (the zone guard, `FlutterError.onError`,
/// `PlatformDispatcher.instance.onError` in `main.dart`) reports through one
/// place instead of each silently calling `debugPrint` independently — the
/// exact gap `RR-002`/`OB-002` identified. [onReport] is a pluggable hook: a
/// future crash-reporting SDK (Sentry, Crashlytics, etc.) wires in here
/// without any call site needing to change.
class AppErrorReporter {
  const AppErrorReporter._();

  /// Set by app startup once a real crash-reporting sink is chosen. Left
  /// unset here deliberately — choosing and configuring that SDK is a
  /// separate decision (see `OB_remediation_plan.md` R1-1), not bundled into
  /// this reporting funnel.
  static void Function(Object error, StackTrace? stack, {String? context})?
  onReport;

  static void report(Object error, StackTrace? stack, {String? context}) {
    final label = context == null ? '' : ' [$context]';
    if (kDebugMode) {
      debugPrint('Unhandled error$label: $error\n$stack');
    }
    onReport?.call(error, stack, context: context);
  }
}
