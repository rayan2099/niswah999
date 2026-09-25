import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';

/// The text a person sees when a community request fails. The underlying
/// exception (which can carry the backend URL, table names or driver
/// internals) is reported through [AppErrorReporter] but never shown.
String communityErrorMessage(
  Object error,
  StackTrace stack, {
  required String context,
}) {
  AppErrorReporter.report(error, stack, context: context, feature: 'community');
  return AppLocaleController.instance.text(
    'We couldn\'t complete that right now. Check your connection and try again.',
    'تعذر إكمال ذلك الآن. تحققي من اتصالكِ وحاولي مجدداً.',
  );
}
