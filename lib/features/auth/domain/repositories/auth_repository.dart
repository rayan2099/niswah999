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
}

class AuthRepositoryException extends Failure {
  const AuthRepositoryException(super.message);
}
