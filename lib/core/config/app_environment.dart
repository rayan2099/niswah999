import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnvironment {
  AppEnvironment._();

  static Future<void> load() async {
    await dotenv.load();

    final url = _read('SUPABASE_URL', fallback: 'VITE_SUPABASE_URL');
    final anonKey = _read(
      'SUPABASE_ANON_KEY',
      fallback: 'VITE_SUPABASE_ANON_KEY',
    );
    final appEnv = dotenv.env['APP_ENV'] ?? 'development';

    _validateClientConfig(url: url, anonKey: anonKey);

    _supabaseUrl = url;
    _supabaseAnonKey = anonKey;
    _appEnvironment = appEnv;
  }

  static String _supabaseUrl = '';
  static String _supabaseAnonKey = '';
  static String _appEnvironment = 'development';

  static String get supabaseUrl => _require(_supabaseUrl, 'SUPABASE_URL');

  static String get supabaseAnonKey =>
      _require(_supabaseAnonKey, 'SUPABASE_ANON_KEY');

  static String get appEnvironment => _appEnvironment;

  static bool get isProduction => _appEnvironment == 'production';

  static String _read(String primaryName, {required String fallback}) {
    final primaryValue = dotenv.env[primaryName]?.trim();
    if (primaryValue != null && primaryValue.isNotEmpty) {
      return primaryValue;
    }

    final fallbackValue = dotenv.env[fallback]?.trim();
    if (fallbackValue != null && fallbackValue.isNotEmpty) {
      return fallbackValue;
    }

    return '';
  }

  static String _require(String value, String name) {
    if (value.trim().isEmpty) {
      throw FormatException(
        'Missing required environment value for $name. Add it to the .env file or configure the secret in your secure deployment environment.',
      );
    }

    return value;
  }

  static void _validateClientConfig({
    required String url,
    required String anonKey,
  }) {
    if (url.trim().isEmpty) {
      throw const FormatException(
        'SUPABASE_URL is required. Do not ship the app without a configured project URL.',
      );
    }

    if (anonKey.trim().isEmpty) {
      throw const FormatException(
        'SUPABASE_ANON_KEY is required. Use the anonymous key only in client apps.',
      );
    }

    final normalized = anonKey.toLowerCase();
    if (normalized.contains('service_role') ||
        normalized.contains('service-role') ||
        normalized.contains('secret')) {
      throw const FormatException(
        'Service role or secret credentials are forbidden in the Flutter client. '
        'This would bypass Row Level Security and expose privileged database access.',
      );
    }
  }
}
