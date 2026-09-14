import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/supabase_client.dart';
import '../preferences/madhhab_controller.dart';

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
  // account's session lands *immediately* (no email confirmation
  // required) — never by sign-in. Used only as a UX hint for
  // OnboardingScreen's initialStep (skip the redundant login step for a
  // user who is already authenticated) — NOT as the source of truth for
  // whether onboarding is required at all. That decision is
  // [onboardingCompleted] below (AUTH-002) — this flag is never set for
  // the real production email/password path (confirmation required,
  // `mailer_autoconfirm: false`), so it must never gate routing on its
  // own; it did before this fix, which is exactly how a confirmed new
  // user could reach the dashboard without ever seeing onboarding.
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

  // AUTH-002: the durable, server-side source of truth for whether the
  // caller has completed onboarding — `public.users.onboarding_completed`.
  // `null` = not yet checked / unknown (never treated as either true or
  // false — the root router shows a brief loading state rather than
  // guessing). Re-fetched on every transition into "authenticated", not
  // just once, so a stale in-memory decision can never survive across an
  // auth-state change (a fresh sign-in, a deep-link-driven session from
  // email confirmation, or app resume all re-check this).
  //
  // Defaults to `true` (not `null`) for the exact same reason
  // `_isAuthenticated` defaults to `true`: a widget test that renders
  // `NiswahApp`/`_buildHome` directly, without ever calling `init()` (real
  // app runs always do, via main.dart's bootstrap; most widget tests
  // never call it at all), must still resolve immediately to a real
  // routing decision rather than getting permanently stuck on the
  // "checking" loading state, which only ever resolves once a real
  // backend answers `init()`'s own query.
  bool? _onboardingCompleted = true;

  bool? get onboardingCompleted => _onboardingCompleted;

  /// Optimistic local update the moment onboarding actually finishes, so
  /// routing reflects it immediately without waiting on a network
  /// round-trip — the real write to `public.users` happens separately
  /// (see `AuthRepositoryImpl.markOnboardingCompleted`) and this is not a
  /// substitute for it; a future session always re-fetches the real value.
  void setOnboardingCompletedLocally(bool value) {
    if (_onboardingCompleted == value) return;
    _onboardingCompleted = value;
    notifyListeners();
  }

  Future<void> refreshOnboardingStatus() async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      _onboardingCompleted = null;
      return;
    }

    bool? completed;
    try {
      final response = await client
          .from('users')
          .select('onboarding_completed')
          .eq('id', userId)
          .maybeSingle();
      completed = response?['onboarding_completed'] as bool?;
    } catch (_) {
      completed = null;
    }

    if (completed != _onboardingCompleted) {
      _onboardingCompleted = completed;
      notifyListeners();
    }
  }

  void init() {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      // No backend to gate against (a widget test that never bootstrapped
      // Supabase) — matches _isAuthenticated's own existing "default to
      // in" convention. `true`, not `null`: this must resolve to a real
      // state immediately so tests reach NiswahHomeShell/OnboardingScreen
      // the same way they always have, never stall on the "checking"
      // loading state that only applies when a real backend exists to
      // eventually answer.
      _isAuthenticated = true;
      _onboardingCompleted = true;
      return;
    }

    _isAuthenticated = client.auth.currentSession != null;
    if (_isAuthenticated) {
      // A real check is starting — reflect "unknown" immediately rather
      // than momentarily showing the test-only default while the real
      // network round-trip is in flight.
      _onboardingCompleted = null;
      unawaited(refreshOnboardingStatus());
    }

    _subscription ??= client.auth.onAuthStateChange.listen((state) {
      final signedIn = state.session != null;
      final wasAuthenticated = _isAuthenticated;

      if (!signedIn) {
        _isNewSignUp = false;
        _onboardingCompleted = null;
        // Fiqh Remediation Wave 1 (AUTH-005/M — account switching): clears
        // the previous account's in-memory Madhhab state immediately on
        // sign-out, so a different account signing in next can never
        // briefly observe it before its own load() below completes.
        MadhhabController.instance.resetInMemory();
      }
      if (signedIn != wasAuthenticated) {
        _isAuthenticated = signedIn;
        notifyListeners();
      }
      // Only re-check on a genuine sign-in transition (was signed out,
      // now signed in) — not on every event carrying signedIn=true (e.g.
      // a token refresh for an already-established session), which would
      // otherwise flash the "checking" loading state for no reason for a
      // user already in the dashboard.
      if (signedIn && !wasAuthenticated) {
        _onboardingCompleted = null;
        unawaited(refreshOnboardingStatus());
        // Fiqh Remediation Wave 1 (AUTH-005) — re-reads the canonical
        // server-side Madhhab state for whichever account just signed in,
        // the same way onboarding status is re-checked on every sign-in
        // transition rather than trusted from a stale in-memory value.
        unawaited(MadhhabController.instance.load());
      }
    });
  }

  /// Test-only: puts the singleton into a specific, deterministic state
  /// without needing a real Supabase backend — used to exercise
  /// `main.dart`'s routing contract (AUTH-002) for each of its states
  /// directly, since faking the real network round-trip
  /// `refreshOnboardingStatus` makes isn't otherwise practical in a
  /// widget test. Never called from application code.
  @visibleForTesting
  void setStateForTest({
    required bool isAuthenticated,
    bool? onboardingCompleted,
    bool isNewSignUp = false,
  }) {
    _isAuthenticated = isAuthenticated;
    _onboardingCompleted = onboardingCompleted;
    _isNewSignUp = isNewSignUp;
    notifyListeners();
  }
}
