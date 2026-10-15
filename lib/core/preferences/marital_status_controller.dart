import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_error_reporter.dart';
import '../network/supabase_client.dart';

class MaritalStatusController extends ChangeNotifier {
  MaritalStatusController._();

  static final MaritalStatusController instance = MaritalStatusController._();
  static const _storageKey = 'niswah_is_married';

  bool _isMarried = false;
  int _answerGeneration = 0;
  Future<void> _demographicsSync = Future<void>.value();
  bool get isMarried => _isMarried;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _isMarried = preferences.getBool(_storageKey) ?? false;
  }

  Future<void> setMarried(bool value) async {
    // A repeated explicit "No" is still an answer; the default false is not.
    if (_isMarried != value) {
      _isMarried = value;
      notifyListeners();
    }
    final generation = ++_answerGeneration;
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_storageKey, value);
    // Sync only an explicit onboarding/settings choice. Never backfill from
    // load() or the old device-wide default: old accounts remain unknown.
    if (client == null || userId == null) return;
    if (generation != _answerGeneration) return;
    // Serialize writes so rapid toggles cannot leave the older answer on the
    // server. Captured user ID plus RLS prevent an account-switch write.
    _demographicsSync = _demographicsSync.then((_) async {
      if (generation != _answerGeneration ||
          client.auth.currentUser?.id != userId) {
        return;
      }
      try {
        await client
            .from('user_demographics')
            .upsert({'user_id': userId, 'is_married': value});
      } catch (_, stack) {
        // Preserve the existing local UX during offline/staged rollout. A
        // later explicit choice retries; a failed write is not counted as saved.
        AppErrorReporter.report(
          StateError('Demographic answer sync failed'),
          stack,
          context: 'MaritalStatusController.setMarried',
          feature: 'profile',
        );
      }
    });
    await _demographicsSync;
  }
}
