import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error_reporter.dart';
import '../network/supabase_client.dart';
import '../preferences/madhhab_controller.dart';

/// Startup Auth-Gate Infinite-Spinner Investigation (AUTH-012): the
/// server-side onboarding-status check this controller performs must never
/// leave the root router (`main.dart`) unable to tell "still checking"
/// apart from "checking failed" — both used to collapse to the same `null`
/// value, and a `completed != _onboardingCompleted` guard silently
/// suppressed `notifyListeners()` whenever a failed check produced `null`
/// on top of an already-`null` value, so the UI never even got a chance to
/// react. [OnboardingStatus] replaces that ambiguous `bool?` contract with
/// four explicit states, so a genuine backend failure is always
/// distinguishable from "still loading" and the router can show a real,
/// recoverable error instead of an indefinite spinner.
enum OnboardingStatus { loading, incomplete, complete, error }

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
  // [onboardingStatus] below (AUTH-002) — this flag is never set for
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

  // AUTH-002/AUTH-012: the durable, server-side source of truth for
  // whether the caller has completed onboarding —
  // `public.users.onboarding_completed`. Re-fetched on every transition
  // into "authenticated", not just once, so a stale in-memory decision can
  // never survive across an auth-state change (a fresh sign-in, a
  // deep-link-driven session from email confirmation, or app resume all
  // re-check this).
  //
  // Defaults to `complete` (not `loading`) for the exact same reason
  // `_isAuthenticated` defaults to `true`: a widget test that renders
  // `NiswahApp`/`_buildHome` directly, without ever calling `init()` (real
  // app runs always do, via main.dart's bootstrap; most widget tests never
  // call it at all), must still resolve immediately to a real routing
  // decision rather than getting permanently stuck on the loading state,
  // which only ever resolves once a real backend answers `init()`'s own
  // query.
  OnboardingStatus _onboardingStatus = OnboardingStatus.complete;

  OnboardingStatus get onboardingStatus => _onboardingStatus;

  /// Legacy tri-state view of [onboardingStatus], kept only because it is
  /// still the most convenient shape for a handful of existing call sites
  /// (`isNewSignUp`'s sibling checks, widget tests). `null` means
  /// [OnboardingStatus.loading] **or** [OnboardingStatus.error] — anything
  /// that needs to tell those two apart must read [onboardingStatus]
  /// directly, which is exactly what `main.dart`'s router now does.
  bool? get onboardingCompleted => switch (_onboardingStatus) {
    OnboardingStatus.complete => true,
    OnboardingStatus.incomplete => false,
    OnboardingStatus.loading || OnboardingStatus.error => null,
  };

  /// Incremented at the start of every [refreshOnboardingStatus] call and
  /// on every sign-out. A request whose generation no longer matches the
  /// current one when it resolves is stale — its result is discarded
  /// rather than applied, so neither an overlapping duplicate request nor
  /// a request that started before a logout/account-switch can ever
  /// clobber a newer, more current state (Section 9/10 H/I of the AUTH-012
  /// investigation: logout-in-flight and account-switch-in-flight must
  /// never apply a stale result).
  int _onboardingRequestGeneration = 0;

  void _setOnboardingStatus(OnboardingStatus value) {
    if (_onboardingStatus == value) return;
    _onboardingStatus = value;
    notifyListeners();
  }

  /// Optimistic local update the moment onboarding actually finishes, so
  /// routing reflects it immediately without waiting on a network
  /// round-trip — the real write to `public.users` happens separately
  /// (see `AuthRepositoryImpl.markOnboardingCompleted`) and this is not a
  /// substitute for it; a future session always re-fetches the real value.
  void setOnboardingCompletedLocally(bool value) {
    _onboardingRequestGeneration++; // supersedes any in-flight refresh
    _setOnboardingStatus(
      value ? OnboardingStatus.complete : OnboardingStatus.incomplete,
    );
  }

  /// Re-fetches the current user's onboarding status from the server.
  /// Never leaves [onboardingStatus] stuck at [OnboardingStatus.loading]
  /// on failure — every exit path (missing client/session, a missing
  /// `public.users` row, a thrown exception, a timeout) resolves to a
  /// real, distinguishable state. This is also the sole retry path
  /// (Section 8): calling it again from [OnboardingStatus.error] is safe —
  /// it starts a new request generation, so a slow, still-in-flight
  /// earlier attempt can never overwrite the retry's own result.
  Future<void> refreshOnboardingStatus() {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      _onboardingRequestGeneration++;
      _setOnboardingStatus(OnboardingStatus.error);
      return Future.value();
    }
    return _resolveOnboardingStatus(
      () => client
          .from('users')
          .select('onboarding_completed')
          .eq('id', userId)
          .maybeSingle(),
    );
  }

  /// Test-only seam: runs the exact same generation-guarded,
  /// timeout-bounded, error-classifying logic [refreshOnboardingStatus]
  /// uses, but against an injected fetch function instead of a real
  /// Supabase client — lets tests exercise every branch (slow response,
  /// timeout, thrown exception, a missing row represented as a `null`
  /// response, logout/account-switch racing an in-flight request) without
  /// a live backend. Never called from application code.
  @visibleForTesting
  Future<void> refreshOnboardingStatusForTest(
    Future<Map<String, dynamic>?> Function() fetchRow,
  ) => _resolveOnboardingStatus(fetchRow);

  Future<void> _resolveOnboardingStatus(
    Future<Map<String, dynamic>?> Function() fetchRow,
  ) async {
    final generation = ++_onboardingRequestGeneration;
    _setOnboardingStatus(OnboardingStatus.loading);

    OnboardingStatus result;
    try {
      final response = await fetchRow().timeout(const Duration(seconds: 15));
      if (response == null) {
        // AUTH-012, Section 6: a real Supabase session exists but no
        // matching public.users row does — never silently treated as
        // "onboarding complete" (that would skip onboarding for someone
        // who never did it) and never silently repaired client-side (this
        // controller has no way to know what a fabricated row's other
        // fields should honestly contain). Surfaced as a real, reported,
        // recoverable error instead.
        result = OnboardingStatus.error;
        AppErrorReporter.report(
          StateError('authenticated user has no public.users row'),
          StackTrace.current,
          context: 'AuthController.refreshOnboardingStatus',
          feature: 'auth',
        );
      } else {
        result = response['onboarding_completed'] == true
            ? OnboardingStatus.complete
            : OnboardingStatus.incomplete;
      }
    } catch (error, stack) {
      result = OnboardingStatus.error;
      AppErrorReporter.report(
        error,
        stack,
        context: 'AuthController.refreshOnboardingStatus',
        feature: 'auth',
      );
    }

    if (generation != _onboardingRequestGeneration) return;
    _setOnboardingStatus(result);
  }

  void init() {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      // No backend to gate against (a widget test that never bootstrapped
      // Supabase) — matches _isAuthenticated's own existing "default to
      // in" convention. `complete`, not `loading`: this must resolve to a
      // real state immediately so tests reach NiswahHomeShell/
      // OnboardingScreen the same way they always have, never stall on
      // the loading state that only applies when a real backend exists to
      // eventually answer.
      _isAuthenticated = true;
      _onboardingStatus = OnboardingStatus.complete;
      return;
    }

    _isAuthenticated = client.auth.currentSession != null;
    if (_isAuthenticated) {
      unawaited(refreshOnboardingStatus());
    }

    _subscription ??= client.auth.onAuthStateChange.listen((state) {
      final signedIn = state.session != null;
      final wasAuthenticated = _isAuthenticated;

      if (!signedIn) {
        _isNewSignUp = false;
        // Invalidates any request still in flight from the session that
        // just ended, so its eventual (possibly successful) result can
        // never apply after sign-out or to whichever different account
        // signs in next.
        _onboardingRequestGeneration++;
        _onboardingStatus = OnboardingStatus.loading;
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
      // otherwise flash the loading state for no reason for a user
      // already in the dashboard.
      if (signedIn && !wasAuthenticated) {
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
  /// `main.dart`'s routing contract (AUTH-002/AUTH-012) for each of its
  /// states directly, since faking the real network round-trip
  /// `refreshOnboardingStatus` makes isn't otherwise practical in a widget
  /// test. Never called from application code. Accepts the legacy `bool?`
  /// shape (`null` => loading) for every existing call site, plus an
  /// optional [onboardingStatus] override for tests that need to reach
  /// [OnboardingStatus.error] specifically, which `bool?` cannot express.
  @visibleForTesting
  void setStateForTest({
    required bool isAuthenticated,
    bool? onboardingCompleted,
    OnboardingStatus? onboardingStatus,
    bool isNewSignUp = false,
  }) {
    _onboardingRequestGeneration++;
    _isAuthenticated = isAuthenticated;
    _onboardingStatus =
        onboardingStatus ??
        switch (onboardingCompleted) {
          true => OnboardingStatus.complete,
          false => OnboardingStatus.incomplete,
          null => OnboardingStatus.loading,
        };
    _isNewSignUp = isNewSignUp;
    notifyListeners();
  }
}
