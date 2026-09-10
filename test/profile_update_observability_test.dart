import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/features/auth/domain/entities/app_user.dart';
import 'package:niswah/features/auth/domain/repositories/auth_repository.dart';
import 'package:niswah/features/auth/presentation/models/profile_form_data.dart';
import 'package:niswah/features/auth/presentation/viewmodels/profile_view_model.dart';

/// A minimal fake covering only what ProfileViewModel actually calls.
class _FakeAuthRepository implements AuthRepository {
  Object? failUpdateWith;

  @override
  Future<AppUser?> updateProfile({
    required String displayName,
    required String email,
    String? phoneNumber,
    String? bio,
    bool? anonymousMode,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;
    return AppUser(id: 'u1', email: email, displayName: displayName);
  }

  @override
  Future<AppUser?> get currentUser async => null;

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => false;

  @override
  Future<void> resendEmailConfirmation({required String email}) async {}

  @override
  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithPhone({
    required String phone,
    required String password,
    String? displayName,
  }) async {}

  @override
  Future<void> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {}

  @override
  Future<void> resendPhoneOtp({required String phone}) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> resetPasswordForEmail({required String email}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<AppUser?> getProfile() async => null;

  @override
  Future<bool?> fetchOnboardingCompleted() async => null;

  @override
  Future<void> markOnboardingCompleted() async {}
}

void main() {
  late _FakeAuthRepository repository;
  late ProfileViewModel viewModel;
  Object? reportedError;

  setUp(() {
    repository = _FakeAuthRepository();
    viewModel = ProfileViewModel(authRepository: repository);
    reportedError = null;
    AppErrorReporter.onReport = (error, stack, {context, feature, retryAttempt, recordId}) {
      reportedError = error;
    };
  });

  tearDown(() {
    AppErrorReporter.onReport = null;
  });

  group('ProfileViewModel.updateProfile (REMOTE_AUTHORITATIVE contract)', () {
    const validForm = ProfileFormData(
      displayName: 'Sara',
      email: 'sara@example.com',
    );

    test('a successful update reports nothing and applies the new user', () async {
      await viewModel.updateProfile(validForm);

      expect(viewModel.user?.displayName, 'Sara');
      expect(reportedError, isNull);
    });

    test(
      'a failure is reported via AppErrorReporter — previously the real '
      'error was discarded before being replaced with a generic message, '
      'leaving the operator with zero visibility (RR-001)',
      () async {
        repository.failUpdateWith = Exception('backend rejected the update');

        await expectLater(
          () => viewModel.updateProfile(validForm),
          throwsA(isA<AuthFailure>()),
        );

        expect(
          reportedError,
          isNotNull,
          reason: 'the underlying failure must be observable to the '
              'operator, not silently discarded',
        );
      },
    );

    test(
      'a Failure subtype is rethrown as-is, not wrapped or double-reported '
      '(this class of error already carries a meaningful, specific message)',
      () async {
        repository.failUpdateWith = const AuthFailure('email already in use');

        await expectLater(
          () => viewModel.updateProfile(validForm),
          throwsA(
            isA<AuthFailure>().having(
              (f) => f.message,
              'message',
              'email already in use',
            ),
          ),
        );
        expect(
          reportedError,
          isNull,
          reason: 'a typed Failure is rethrown directly, not routed through '
              'the generic catch/report path',
        );
      },
    );
  });

  group('ProfileViewModel.setAnonymousMode (REMOTE_AUTHORITATIVE contract)', () {
    test(
      'a failure while toggling anonymous mode is reported via '
      'AppErrorReporter',
      () async {
        // setAnonymousMode requires `user` to already be loaded.
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
        repository.failUpdateWith = Exception('network unreachable');

        await expectLater(
          () => viewModel.setAnonymousMode(true),
          throwsA(isA<AuthFailure>()),
        );

        expect(reportedError, isNotNull);
      },
    );
  });
}
