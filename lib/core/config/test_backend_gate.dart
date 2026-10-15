/// Production-environment kill switch for the autonomous persona /
/// acceptance harness.
///
/// A persona creates real accounts and writes real rows, so it must be
/// impossible for one to run against production because someone forgot
/// to swap `.env`. This is a pure classifier: it looks ONLY at the
/// effective Supabase URL's host, and it never consults `APP_ENV` (a
/// bundled `.env` reports `development` even in a production-pointed
/// build — see [AppEnvironment.load]'s own comment), so a production URL
/// with a friendly `APP_ENV=development` is still refused.
///
/// The allowlist below is deliberately a version-controlled constant, not
/// a command-line flag or an environment variable: there is no runtime
/// switch that widens it, so a backend can only become "approved" through
/// a reviewed code change.
class TestBackendGate {
  TestBackendGate._();

  /// Hosts that can only ever be a developer's own machine or CI runner:
  /// loopback, and `10.0.2.2`, the Android emulator's fixed alias for the
  /// host machine's loopback. Compared as EXACT host strings — never
  /// prefix/suffix/contains — so `localhost.evil.com` and
  /// `127.0.0.1.nip.io` are unknown hosts, not local ones.
  static const Set<String> localHosts = {
    'localhost',
    '127.0.0.1',
    '::1',
    '10.0.2.2',
  };

  /// Explicitly approved NON-production hosted test/staging Supabase
  /// hosts. EMPTY by default: no hosted project is approved until a
  /// reviewed change adds its exact host here.
  static const Set<String> approvedTestHosts = <String>{};

  /// Known production project hosts. A denylist entry wins over every
  /// allowlist, so accidentally allowlisting production still refuses.
  static const Set<String> productionHosts = {
    'jkmjobvxfrmuwafczvtw.supabase.co',
  };

  /// Any hosted-Supabase domain that is not explicitly approved is
  /// treated as potentially production.
  static const List<String> hostedSupabaseSuffixes = [
    '.supabase.co',
    '.supabase.in',
    '.supabase.net',
  ];

  /// Evaluates [rawUrl]. [approvedHosts] exists so a unit test can model
  /// "an approved test backend" without editing the constant above;
  /// production callers never pass it.
  static BackendGateVerdict evaluate(
    String? rawUrl, {
    Set<String> approvedHosts = approvedTestHosts,
  }) {
    final trimmed = rawUrl?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const BackendGateVerdict.refused(
        host: '<empty>',
        reason: 'the configured Supabase URL is empty or missing',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const BackendGateVerdict.refused(
        host: '<unparseable>',
        reason: 'the configured Supabase URL is malformed',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return BackendGateVerdict.refused(
        host: _safeIdentifier(uri),
        reason: 'the URL scheme "${uri.scheme}" is not http/https',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      // `http://127.0.0.1@prod.example` parses to host prod.example, but
      // a URL carrying credentials/userinfo is never a legitimate
      // Supabase client URL and is a classic disguise.
      return BackendGateVerdict.refused(
        host: _safeIdentifier(uri),
        reason: 'the URL contains userinfo, which is never legitimate here',
      );
    }

    final host = uri.host.toLowerCase();
    final id = _safeIdentifier(uri);

    if (productionHosts.contains(host)) {
      return BackendGateVerdict.refused(
        host: id,
        reason: 'this is the PRODUCTION Supabase project',
      );
    }
    if (localHosts.contains(host)) return BackendGateVerdict.allowed(host: id);
    if (approvedHosts.contains(host)) {
      return BackendGateVerdict.allowed(host: id);
    }
    final hosted = hostedSupabaseSuffixes.any(host.endsWith);
    return BackendGateVerdict.refused(
      host: id,
      reason: hosted
          ? 'an unapproved hosted Supabase project (could be production)'
          : 'the host is not loopback and is not on the approved test list',
    );
  }

  /// Same URL precedence as `AppEnvironment` (SUPABASE_URL, then
  /// VITE_SUPABASE_URL). `APP_ENV` is intentionally never read here.
  static BackendGateVerdict evaluateEnvironment(
    Map<String, String> env, {
    Set<String> approvedHosts = approvedTestHosts,
  }) {
    String read(String k) => env[k]?.trim() ?? '';
    final primary = read('SUPABASE_URL');
    final url = primary.isNotEmpty ? primary : read('VITE_SUPABASE_URL');
    return evaluate(url, approvedHosts: approvedHosts);
  }

  /// host[:port] only — never a path, query, userinfo or key.
  static String _safeIdentifier(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

class BackendGateVerdict {
  const BackendGateVerdict.allowed({required this.host})
    : allowed = true,
      reason = 'approved test backend';
  const BackendGateVerdict.refused({required this.host, required this.reason})
    : allowed = false;

  final bool allowed;

  /// Safe identifier only: host[:port].
  final String host;
  final String reason;

  @override
  String toString() => allowed ? 'ALLOWED $host' : 'REFUSED $host — $reason';
}
