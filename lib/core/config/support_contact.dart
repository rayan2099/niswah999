/// Published contact for users (App Store Review Guideline 1.2 asks apps
/// with user-generated content to publish contact information).
///
/// Injected at build time with
/// `--dart-define=NISWAH_SUPPORT_EMAIL=<address>` so the address lives with
/// the release configuration rather than in source. Every release build
/// must pass it; until then the app falls back to in-app reporting copy.
class SupportContact {
  SupportContact._();

  static const String _email = String.fromEnvironment('NISWAH_SUPPORT_EMAIL');

  /// The support address, or null when the build did not set one.
  static String? get email => _email.trim().isEmpty ? null : _email.trim();
}
