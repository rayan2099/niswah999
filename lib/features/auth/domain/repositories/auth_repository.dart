import '../../../../core/errors/failures.dart';
import '../entities/app_user.dart';

abstract class AuthRepository {
  Future<AppUser?> get currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  /// Returns `true` when Supabase requires email confirmation before a
  /// session is created (no active session yet — a confirmation link was
  /// sent to [email]), or `false` when a session was created immediately.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  /// Re-sends the email sign-up confirmation link.
  Future<void> resendEmailConfirmation({required String email});

  Future<void> signInWithPhone({
    required String phone,
    required String password,
  });

  Future<void> signUpWithPhone({
    required String phone,
    required String password,
    String? displayName,
  });

  /// Completes phone sign-up by confirming the SMS code sent to [phone].
  /// Required whenever the Supabase project has "Enable phone
  /// confirmations" on — [signUpWithPhone] alone leaves the account
  /// unconfirmed with no active session until this succeeds.
  Future<void> verifyPhoneOtp({required String phone, required String token});

  /// Re-sends the phone sign-up confirmation code.
  Future<void> resendPhoneOtp({required String phone});

  Future<void> signInWithGoogle();

  Future<void> resetPasswordForEmail({required String email});

  Future<AppUser?> updateProfile({
    required String displayName,
    required String email,
    String? phoneNumber,
    String? bio,
    bool? anonymousMode,
  });

  Future<void> signOut();

  /// Permanently deletes the caller's account via the existing
  /// `delete_my_account()` Supabase RPC (`SECURITY DEFINER`) — removes the
  /// `auth.users` row and, through existing `ON DELETE CASCADE` foreign
  /// keys already in the live schema, every dependent row across the app's
  /// tables (PC-002). Does not sign out locally on its own — the caller's
  /// local session is already invalid once the backend row is gone; the
  /// UI layer clears it explicitly for a clean, immediate transition to
  /// the unauthenticated state rather than relying on the next network
  /// call to discover the session is dead.
  Future<void> deleteAccount();

  Future<AppUser?> getProfile();

  /// The durable, server-side source of truth for whether the caller has
  /// completed onboarding — `public.users.onboarding_completed`, defaulted
  /// to `false` by the same trigger that creates the row on signup (AUTH-002).
  /// Returns `null` only when there is no session or the row cannot be
  /// read (caller should treat that the same as "unknown", not "false").
  /// Deliberately never inferred from in-memory/local-only signals (a
  /// signup-just-happened flag, SharedPreferences, etc.) — those cannot
  /// survive an app-process restart, which is exactly what real users
  /// experience during email confirmation (leave the app to check mail,
  /// confirm, get relaunched into a fresh process).
  Future<bool?> fetchOnboardingCompleted();

  /// Marks onboarding complete server-side. Must be called once, at the
  /// real end of the onboarding flow — never inferred from any other
  /// event (session creation, profile-row existence, email confirmation).
  Future<void> markOnboardingCompleted();
}

class AuthRepositoryException extends Failure {
  const AuthRepositoryException(super.message);
}
