/// Compile-time build identity, injected by the build command
/// (`--dart-define=GIT_SHA=$(git rev-parse HEAD)`). Never read from `.env`
/// — a static asset bundled identically into every build cannot tell one
/// commit apart from another, which is exactly what this exists to do.
class BuildInfo {
  BuildInfo._();

  static const String gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'unknown',
  );

  /// Off by default in every normal build — only a test/QA build passes
  /// `--dart-define=ENABLE_DIAGNOSTICS_SCREEN=true`.
  static const bool diagnosticsEnabled = bool.fromEnvironment(
    'ENABLE_DIAGNOSTICS_SCREEN',
  );
}
