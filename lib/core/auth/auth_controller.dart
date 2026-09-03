import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/supabase_client.dart';

/// Tracks whether a Supabase session currently exists, so the root router
/// in main.dart can gate `NiswahHomeShell` behind `SignInScreen`. Session
/// persistence/refresh is handled by supabase_flutter itself
/// (`persistSession: true, autoRefreshToken: true` in
/// `NiswahSupabase.initialize`) — this controller just mirrors that state
/// for the widget tree via `onAuthStateChange`.
class AuthController extends ChangeNotifier {
  AuthController._();

  static final AuthController instance = AuthController._();

  StreamSubscription<AuthState>? _subscription;

  // Real app runs always initialize Supabase before calling init(), so a
  // null client here means this is a widget test that never bootstrapped
  // Supabase — there's no backend to gate against, so default to "in".
  bool _isAuthenticated = true;

  bool get isAuthenticated => _isAuthenticated;

  // Set by the sign-up flow (sign_in_screen.dart) the moment a brand-new
  // account's session lands — never by sign-in. The root router
  // (main.dart) reads this once to route through OnboardingScreen instead
  // of straight to NiswahHomeShell, then the screen's onFinished clears it.
  // In-memory only (not persisted), so it never survives an app restart —
  // a signup that requires email/OTP confirmation completed in a later
  // session won't trigger onboarding, same as before this existed.
  bool _isNewSignUp = false;

  bool get isNewSignUp => _isNewSignUp;

  void markSignedUp() {
    if (_isNewSignUp) return;
    _isNewSignUp = true;
    notifyListeners();
  }

  void clearNewSignUp() {
    if (!_isNewSignUp) return;
    _isNewSignUp = false;
    notifyListeners();
  }

  void init() {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      _isAuthenticated = true;
      return;
    }

    _isAuthenticated = client.auth.currentSession != null;
    _subscription ??= client.auth.onAuthStateChange.listen((state) {
      final signedIn = state.session != null;
      if (!signedIn) _isNewSignUp = false;
      if (signedIn != _isAuthenticated) {
        _isAuthenticated = signedIn;
        notifyListeners();
      }
    });
  }
}
