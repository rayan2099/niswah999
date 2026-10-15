import '../../../core/localization/app_locale_controller.dart';

/// The title shown for a private conversation. Only a real, published
/// display name is ever shown; when none is known the title is a neutral
/// label — never the other participant's raw account id.
String conversationTitle(String? displayName) {
  final name = displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return AppLocaleController.instance.text(
    'Private conversation',
    'محادثة خاصة',
  );
}
