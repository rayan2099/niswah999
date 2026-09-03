import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';

class NiswahSupabase {
  NiswahSupabase._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        persistSession: true,
        autoRefreshToken: true,
      ),
    );
  }

  static SupabaseClient? get clientOrNull {
    try {
      return Supabase.instance.client;
    } on AssertionError {
      return null;
    } catch (_) {
      return null;
    }
  }

  static SupabaseClient get client {
    final instance = clientOrNull;
    if (instance == null) {
      throw StateError('Supabase has not been initialized.');
    }
    return instance;
  }
}
