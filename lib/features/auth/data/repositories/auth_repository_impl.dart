import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/storage/local_sensitive_data_cleanup.dart';
import '../../domain/account_deletion_orchestrator.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _client;

  AuthRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.client;

  /// Custom URL scheme (registered in Info.plist / AndroidManifest.xml) that
  /// email confirmation and password-reset links redirect back into —
  /// without this, Supabase falls back to its dashboard Site URL (the web
  /// app) instead of opening this app. Must also be added to the Supabase
  /// project's Authentication > URL Configuration > Redirect URLs allow-list,
  /// or Supabase silently ignores it and uses the default Site URL anyway.
  static const String _emailRedirectTo = 'niswah://login-callback';

  /// Digits only, no leading "+" — confirmed against this project's actual
  /// Supabase Dashboard test-phone override list, which is stored as e.g.
  /// "966535110460=123456" (no plus). Sending a "+" here would mismatch it.
  @visibleForTesting
  static String normalizePhone(String phone) =>
      phone.trim().replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Future<AppUser?> get currentUser async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) {
      return null;
    }

    final profile = await getProfile();
    if (profile == null) {
      return AppUser(
        id: sessionUser.id,
        email: sessionUser.email ?? '',
        displayName: sessionUser.userMetadata?['full_name'] as String?,
        isAnonymous: sessionUser.isAnonymous,
      );
    }

    return profile;
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (response.user == null) {
        throw const AuthFailure('Authentication failed. Please try again.');
      }
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure(
        'Unable to sign in. Please check your credentials.',
      );
    }
  }

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: _emailRedirectTo,
        data: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'full_name': displayName.trim(),
        },
      );

      if (response.user == null) {
        throw const AuthFailure('Account creation failed.');
      }
      return response.session == null;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure('Unable to create your account right now.');
    }
  }

  @override
  Future<void> resendEmailConfirmation({required String email}) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: _emailRedirectTo,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw const AuthFailure('Unable to resend the email right now.');
    }
  }

  @override
  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        phone: AuthRepositoryImpl.normalizePhone(phone),
        password: password,
      );

      if (response.user == null) {
        throw const AuthFailure('Authentication failed. Please try again.');
      }
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure(
        'Unable to sign in. Please check your credentials.',
      );
    }
  }

  @override
  Future<void> signUpWithPhone({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        phone: AuthRepositoryImpl.normalizePhone(phone),
        password: password,
        data: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'full_name': displayName.trim(),
        },
      );

      if (response.user == null) {
        throw const AuthFailure('Account creation failed.');
      }
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure('Unable to create your account right now.');
    }
  }

  @override
  Future<void> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        phone: AuthRepositoryImpl.normalizePhone(phone),
        token: token.trim(),
        type: OtpType.sms,
      );

      if (response.session == null) {
        throw const AuthFailure('Verification failed. Please try again.');
      }
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure(
        'Unable to verify the code. Please check it and try again.',
      );
    }
  }

  @override
  Future<void> resendPhoneOtp({required String phone}) async {
    try {
      await _client.auth.resend(
        type: OtpType.sms,
        phone: AuthRepositoryImpl.normalizePhone(phone),
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw const AuthFailure('Unable to resend the code right now.');
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _emailRedirectTo,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure('Unable to sign in with Google right now.');
    }
  }

  @override
  Future<void> resetPasswordForEmail({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _emailRedirectTo,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw const AuthFailure('Unable to send the reset email right now.');
    }
  }

  @override
  Future<AppUser?> updateProfile({
    required String displayName,
    required String email,
    String? phoneNumber,
    String? bio,
    bool? anonymousMode,
  }) async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) {
      throw const AuthFailure('No authenticated user found.');
    }

    final safeDisplayName = displayName.trim();

    // AUTH-004: `display_name`/`anonymous_mode` are written to
    // `public.users` (the table that actually has these columns live),
    // not `public.profiles` (which never did — the migration that would
    // have added them there, `20260822014500_niswah_schema_sync_and_indexes.sql`,
    // was authored but never applied to production; see
    // `supabase/migrations_archive/README.md`). `email` is Supabase Auth's
    // own field and must never be duplicated into a public table.
    // `phoneNumber`/`bio` have no authoritative server column and no
    // reachable UI that collects a real value (confirmed: `ProfileFormData`,
    // the only model carrying them, is never constructed anywhere in the
    // app) — accepted here for API compatibility, intentionally not
    // persisted until both a real screen and a real server column exist.
    try {
      final updates = <String, dynamic>{'display_name': safeDisplayName};
      if (anonymousMode != null) {
        updates['anonymous_mode'] = anonymousMode;
      }

      final response = await _client
          .from('users')
          .update(updates)
          .eq('id', sessionUser.id)
          .select('display_name, anonymous_mode')
          .maybeSingle();

      return AppUser(
        id: sessionUser.id,
        email: sessionUser.email ?? email.trim(),
        displayName: (response?['display_name'] as String?) ?? safeDisplayName,
        isAnonymous:
            response?['anonymous_mode'] as bool? ?? anonymousMode ?? false,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on Failure {
      rethrow;
    } catch (error) {
      throw const AuthFailure('Unable to update your profile right now.');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    }
  }

  @override
  Future<void> deleteAccount() async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) {
      throw const AuthFailure('You must be signed in to delete your account.');
    }
    final deletedUserId = sessionUser.id;

    // Sequencing/failure-isolation contract lives in
    // performAccountDeletion (account_deletion_orchestrator.dart) —
    // extracted so it is directly unit-testable with injected fakes
    // instead of a live/mocked SupabaseClient (Reliability Evidence
    // Closure wave, 2026-09-06).
    await performAccountDeletion(
      deleteRemote: () async {
        try {
          await _client.rpc('delete_my_account');
        } on PostgrestException catch (error) {
          throw AuthFailure(error.message);
        }
      },
      // Removes this user's locally-cached sensitive data (cycle/prayer/
      // pregnancy). Any category that fails is retried on the next app
      // start (see `retryPendingLocalSensitiveDataCleanups` in main.dart).
      cleanupLocal: () => cleanUpLocalSensitiveDataForDeletedAccount(
        deletedUserId,
      ),
      // The RPC deletes `auth.users` server-side — it does not by itself
      // invalidate this client's locally-cached session/tokens or fire
      // Supabase's auth-state-change stream (the mechanism `AuthController`
      // uses to reactively swap the app back to the sign-in screen). Signing
      // out locally here is what actually clears the session and triggers
      // that transition; without it, the app would keep behaving as if
      // still authenticated until some other request happened to fail.
      signOutLocal: () async {
        try {
          await _client.auth.signOut();
        } on AuthException {
          // The account (and its session) is already gone server-side by
          // this point — a local signOut failure here doesn't change that
          // outcome, and must not be reported as if the deletion itself
          // failed. Rethrown so the orchestrator's own bookkeeping still
          // sees this step as failed (it's swallowed here, not there).
          rethrow;
        }
      },
      // cleanUpLocalSensitiveDataForDeletedAccount never actually throws
      // (it catches and reports per-category internally, via
      // SecureLocalStore.runAccountDeletionCleanup) — this callback exists
      // so the sequencing contract itself stays testable and explicit even
      // though this real callee doesn't currently exercise it.
      onCleanupFailure: (_, _) {},
    );
  }

  @override
  Future<AppUser?> getProfile() async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) {
      return null;
    }

    // AUTH-004: read from `public.users`, the table that actually carries
    // `display_name`/`anonymous_mode` in production — see the matching
    // note on `updateProfile` above.
    final fallbackName = sessionUser.userMetadata?['full_name'] as String?;
    try {
      final response = await _client
          .from('users')
          .select('display_name, anonymous_mode')
          .eq('id', sessionUser.id)
          .maybeSingle();

      final storedName = response?['display_name'] as String?;
      return AppUser(
        id: sessionUser.id,
        email: sessionUser.email ?? '',
        displayName: (storedName != null && storedName.trim().isNotEmpty)
            ? storedName
            : fallbackName,
        isAnonymous: response?['anonymous_mode'] as bool? ?? false,
      );
    } catch (_) {
      return AppUser(
        id: sessionUser.id,
        email: sessionUser.email ?? '',
        displayName: fallbackName,
        isAnonymous: sessionUser.isAnonymous,
      );
    }
  }

  @override
  Future<bool?> fetchOnboardingCompleted() async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) return null;

    try {
      final response = await _client
          .from('users')
          .select('onboarding_completed')
          .eq('id', sessionUser.id)
          .maybeSingle();
      return response?['onboarding_completed'] as bool?;
    } catch (_) {
      // Network/RLS failure — treated as "unknown", never coerced to
      // false (which would wrongly force a real returning user back
      // through onboarding) or true (which would wrongly skip it for a
      // real new user).
      return null;
    }
  }

  @override
  Future<void> markOnboardingCompleted() async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) return;

    await _client
        .from('users')
        .update({'onboarding_completed': true})
        .eq('id', sessionUser.id);
  }
}
