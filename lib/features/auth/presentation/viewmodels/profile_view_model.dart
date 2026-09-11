import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/profile_form_data.dart';

class ProfileViewModel extends ChangeNotifier {
  // Typed against the abstract AuthRepository (not AuthRepositoryImpl) so
  // a fake can be injected in tests — this only ever calls interface
  // methods (Reliability Evidence Closure wave, 2026-09-06).
  ProfileViewModel({AuthRepository? authRepository})
    : _authRepository = authRepository ?? _safeAuthRepository();

  final AuthRepository? _authRepository;
  AppUser? user;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  Future<void> loadCurrentUser() async {
    if (_authRepository == null) {
      user = null;
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      user = await _authRepository.currentUser;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(ProfileFormData formData) async {
    final authRepository = _authRepository;
    if (authRepository == null) {
      throw const AuthFailure('Authentication is not available right now.');
    }

    final validationMessage = formData.validate();
    if (validationMessage != null) {
      throw FormatException(validationMessage);
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      final updatedUser = await authRepository.updateProfile(
        displayName: formData.displayName,
        email: formData.email,
        phoneNumber: formData.phoneNumber,
        bio: formData.bio,
      );

      if (updatedUser != null) {
        user = updatedUser;
      }
    } on Failure {
      rethrow;
    } catch (error, stack) {
      // Previously only a generic AuthFailure replaced the real error
      // before rethrowing — the user still saw an honest failure, but the
      // operator had zero visibility into what actually went wrong
      // (RR-001 observability audit, Reliability Evidence Closure wave).
      AppErrorReporter.report(
        error,
        stack,
        context: 'ProfileViewModel.updateProfile',
        feature: 'profile',
      );
      throw const AuthFailure('Unable to update your profile right now.');
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Persists just the anonymous-mode toggle, reusing whatever
  /// displayName/email are already on the loaded profile rather than
  /// routing through [ProfileFormData]'s full-form validation for a
  /// single boolean.
  Future<void> setAnonymousMode(bool value) async {
    final authRepository = _authRepository;
    final currentUser = user;
    if (authRepository == null || currentUser == null) {
      throw const AuthFailure('Authentication is not available right now.');
    }

    // Guards against a rapid double-tap firing two overlapping requests
    // before the first has resolved — previously unguarded, unlike
    // updateProfile()'s isSaving check (AUTH-004 E4 investigation,
    // Wave 1 Final Blocker Remediation follow-up, 2026-09-11).
    if (isSaving) {
      return;
    }
    isSaving = true;
    notifyListeners();

    try {
      final updatedUser = await authRepository.updateProfile(
        displayName: currentUser.displayName ?? '',
        email: currentUser.email,
        anonymousMode: value,
      );

      if (updatedUser != null) {
        user = updatedUser;
      }
    } on Failure {
      rethrow;
    } catch (error, stack) {
      // Previously only a generic AuthFailure replaced the real error
      // before rethrowing — the user still saw an honest failure, but the
      // operator had zero visibility into what actually went wrong
      // (RR-001 observability audit, Reliability Evidence Closure wave).
      AppErrorReporter.report(
        error,
        stack,
        context: 'ProfileViewModel.setAnonymousMode',
        feature: 'profile',
      );
      throw const AuthFailure('Unable to update your profile right now.');
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final authRepository = _authRepository;
    if (authRepository == null) {
      throw const AuthFailure('Authentication is not available right now.');
    }

    try {
      await authRepository.signOut();
      user = null;
    } on Failure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Unable to sign out right now.');
    } finally {
      notifyListeners();
    }
  }

  /// Permanently deletes the caller's account and all associated data via
  /// the existing `delete_my_account()` backend RPC (PC-002). Unlike
  /// [signOut], this is irreversible — the calling UI is responsible for
  /// an explicit destructive-action confirmation before invoking this.
  Future<void> deleteAccount() async {
    final authRepository = _authRepository;
    if (authRepository == null) {
      throw const AuthFailure('Authentication is not available right now.');
    }

    try {
      await authRepository.deleteAccount();
      user = null;
    } on Failure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Unable to delete your account right now.');
    } finally {
      notifyListeners();
    }
  }

  static AuthRepositoryImpl? _safeAuthRepository() {
    try {
      return AuthRepositoryImpl();
    } on StateError {
      return null;
    } catch (_) {
      return null;
    }
  }
}
