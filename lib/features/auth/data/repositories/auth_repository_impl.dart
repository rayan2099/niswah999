import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/supabase_client.dart';
import '../models/user_profile.dart';
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
        redirectTo: null,
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
    final safeEmail = email.trim();
    final safePhoneNumber = phoneNumber?.trim();
    final safeBio = bio?.trim();

    try {
      final updates = <String, dynamic>{
        'display_name': safeDisplayName,
        'email': safeEmail,
      };

      if (safePhoneNumber != null && safePhoneNumber.isNotEmpty) {
        updates['phone_number'] = safePhoneNumber;
      }

      if (safeBio != null) {
        updates['bio'] = safeBio;
      }

      if (anonymousMode != null) {
        updates['anonymous_mode'] = anonymousMode;
      }

      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', sessionUser.id)
          .select()
          .maybeSingle();

      if (response == null) {
        return AppUser(
          id: sessionUser.id,
          email: safeEmail,
          displayName: safeDisplayName,
          isAnonymous: sessionUser.isAnonymous,
        );
      }

      final profile = UserProfile.fromJson(response);
      return AppUser(
        id: profile.id,
        email: profile.email.isEmpty ? safeEmail : profile.email,
        displayName: profile.displayName ?? safeDisplayName,
        isAnonymous: profile.isAnonymous,
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
  Future<AppUser?> getProfile() async {
    final sessionUser = _client.auth.currentUser;
    if (sessionUser == null) {
      return null;
    }

    final response = await _client
        .from('profiles')
        .select()
        .eq('id', sessionUser.id)
        .maybeSingle();

    if (response == null) {
      return AppUser(
        id: sessionUser.id,
        email: sessionUser.email ?? '',
        displayName: sessionUser.userMetadata?['full_name'] as String?,
        isAnonymous: sessionUser.isAnonymous,
      );
    }

    final profile = UserProfile.fromJson(response);
    return AppUser(
      id: profile.id,
      email: profile.email,
      displayName: profile.displayName,
      isAnonymous: profile.isAnonymous,
    );
  }
}
