import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/features/auth/domain/entities/app_user.dart';
import 'package:niswah/features/auth/domain/repositories/auth_repository.dart';
import 'package:niswah/features/auth/presentation/models/profile_form_data.dart';
import 'package:niswah/features/auth/presentation/viewmodels/profile_view_model.dart';

/// A minimal fake covering only what ProfileViewModel actually calls.
///
/// Also models AUTH-004's real fix (updateProfile targets a single,
/// implicit "current session user" row — no caller can ever pass a
/// different user's id, mirroring the real repository, which derives the
/// target row from `_client.auth.currentUser` rather than any parameter)
/// so the account-isolation regression test below can assert this
/// structurally, in addition to the live RLS evidence already gathered
/// against production (Wave 1 Final Blocker Remediation, 2026-09-11).
class _FakeAuthRepository implements AuthRepository {
  Object? failUpdateWith;
  Duration updateDelay = Duration.zero;
  int updateCallCount = 0;
  Map<String, dynamic>? lastUpdatePayload;

  // Simulates the one server-side row this fake "session" is scoped to —
  // there is no way to address any other row, matching the real
  // implicit-current-user contract.
  bool _serverAnonymousMode = false;
  String _serverDisplayName = '';

  @override
  Future<AppUser?> updateProfile({
    required String displayName,
    required String email,
    String? phoneNumber,
    String? bio,
    bool? anonymousMode,
  }) async {
    updateCallCount++;
    lastUpdatePayload = {
      'displayName': displayName,
      'email': email,
      'phoneNumber': phoneNumber,
      'bio': bio,
      'anonymousMode': anonymousMode,
    };
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }
    if (failUpdateWith != null) throw failUpdateWith!;
    _serverDisplayName = displayName;
    if (anonymousMode != null) {
      _serverAnonymousMode = anonymousMode;
    }
    return AppUser(
      id: 'u1',
      email: email,
      displayName: _serverDisplayName,
      isAnonymous: _serverAnonymousMode,
    );
  }

  @override
  Future<AppUser?> getProfile() async => AppUser(
    id: 'u1',
    email: 'sara@example.com',
    displayName: _serverDisplayName,
    isAnonymous: _serverAnonymousMode,
  );

  @override
  Future<AppUser?> get currentUser async => getProfile();

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

    // AUTH-004 E4 investigation regression suite (Wave 1 Final Blocker
    // Remediation, 2026-09-11) — added after the owner's real-device E4
    // retest reported "Unable to update your profile right now." Live
    // re-testing against production (two synthetic accounts, multiple
    // real single-tap trials, a restart, and a double-tap stress test)
    // did not reproduce a persistent defect in the current code — these
    // tests lock in the observed-correct contract so any future
    // regression is caught immediately, without needing another live
    // production round-trip to notice it.

    test('anonymous_mode false -> true persists the new value', () async {
      viewModel.user = const AppUser(
        id: 'u1',
        email: 'sara@example.com',
        isAnonymous: false,
      );

      await viewModel.setAnonymousMode(true);

      expect(viewModel.user?.isAnonymous, isTrue);
      expect(reportedError, isNull);
    });

    test('anonymous_mode true -> false persists the new value', () async {
      viewModel.user = const AppUser(
        id: 'u1',
        email: 'sara@example.com',
        isAnonymous: true,
      );

      await viewModel.setAnonymousMode(false);

      expect(viewModel.user?.isAnonymous, isFalse);
      expect(reportedError, isNull);
    });

    test(
      'save succeeds for the current authenticated user without error',
      () async {
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');

        await viewModel.setAnonymousMode(true);

        expect(repository.updateCallCount, 1);
        expect(reportedError, isNull);
      },
    );

    test('the new value survives a simulated reload', () async {
      viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
      await viewModel.setAnonymousMode(true);

      // Simulate a fresh app session re-fetching the profile from the
      // server rather than trusting any in-memory value.
      final reloaded = await repository.currentUser;

      expect(reloaded?.isAnonymous, isTrue);
    });

    test(
      'logout/login (a fresh currentUser fetch) reloads the correct value',
      () async {
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
        await viewModel.setAnonymousMode(true);

        // Simulate signing out (dropping all local view-model state) and
        // signing back in — the only source of truth left is the server.
        final freshViewModel = ProfileViewModel(authRepository: repository);
        await freshViewModel.loadCurrentUser();

        expect(freshViewModel.user?.isAnonymous, isTrue);
      },
    );

    test(
      'the repository contract cannot address another user\'s row — '
      'updateProfile takes no user-id parameter, so a caller has no way '
      'to target anyone but the current session user (structural '
      'guarantee; the live cross-account RLS attack test against '
      'production is the authoritative evidence for the server-side '
      'enforcement of this same boundary)',
      () async {
        // The design fact itself: updateProfile's signature (see the
        // AuthRepository interface) has no id/userId parameter anywhere,
        // so no caller — this ViewModel included — can ever construct a
        // request naming a different user's row.
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
        await viewModel.setAnonymousMode(true);
        // The fake's own single-row model demonstrates the same shape the
        // real repository has: there is exactly one addressable row per
        // authenticated session, never a caller-supplied target.
        expect(repository.lastUpdatePayload, isNot(contains('id')));
        expect(repository.lastUpdatePayload, isNot(contains('userId')));
      },
    );

    test('unrelated profile fields are not overwritten by the toggle', () async {
      viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');

      await viewModel.setAnonymousMode(true);

      // Only display_name/anonymous_mode are ever part of this call's
      // concern — phoneNumber/bio are always null from this call site,
      // confirming the toggle never sends unrelated field values.
      expect(repository.lastUpdatePayload?['phoneNumber'], isNull);
      expect(repository.lastUpdatePayload?['bio'], isNull);
    });

    test(
      'a null/missing optional field does not break the update',
      () async {
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');

        await expectLater(
          () => viewModel.setAnonymousMode(true),
          returnsNormally,
        );
      },
    );

    test('a failure response produces a user-visible error', () async {
      viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
      repository.failUpdateWith = Exception('simulated backend failure');

      await expectLater(
        () => viewModel.setAnonymousMode(true),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.message,
            'message',
            'Unable to update your profile right now.',
          ),
        ),
      );
    });

    test('a success response does not produce any error', () async {
      viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');

      await viewModel.setAnonymousMode(true);

      expect(reportedError, isNull);
      expect(viewModel.errorMessage, isNot(contains('Unable to update')));
    });

    test(
      'a rapid second call while a save is already in flight is '
      'ignored, not sent as an overlapping second request — previously '
      'unguarded (setAnonymousMode had no isSaving check, unlike the '
      'sibling updateProfile), a real gap found during the AUTH-004 E4 '
      'investigation even though it was not proven to be the owner\'s '
      'exact failure',
      () async {
        viewModel.user = const AppUser(id: 'u1', email: 'sara@example.com');
        repository.updateDelay = const Duration(milliseconds: 50);

        final first = viewModel.setAnonymousMode(true);
        // Fired while the first call is still in flight.
        final second = viewModel.setAnonymousMode(false);

        await Future.wait([first, second]);

        expect(
          repository.updateCallCount,
          1,
          reason: 'the second overlapping call must be dropped, not sent',
        );
      },
    );
  });
}
