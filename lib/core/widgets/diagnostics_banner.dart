import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../config/build_info.dart';

/// A small always-visible strip showing which commit and which backend this
/// build actually is — for QA/founder verification that the app on screen is
/// the build being discussed. Renders nothing unless the build was made with
/// `--dart-define=ENABLE_DIAGNOSTICS_SCREEN=true`. Shows only the backend
/// host, never a key.
class DiagnosticsBanner extends StatelessWidget {
  const DiagnosticsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!BuildInfo.diagnosticsEnabled) return const SizedBox.shrink();

    var backendHost = 'unknown';
    try {
      backendHost = Uri.parse(AppEnvironment.supabaseUrl).host;
    } catch (_) {}
    final sha = BuildInfo.gitSha;
    final shortSha = sha.length > 12 ? sha.substring(0, 12) : sha;

    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        child: Container(
          key: const Key('diagnostics_banner'),
          width: double.infinity,
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            'SHA:$shortSha  ENV:${AppEnvironment.appEnvironment}  '
            'BACKEND:$backendHost',
            key: const Key('diagnostics_banner_text'),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
