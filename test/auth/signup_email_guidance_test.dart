import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/failures.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:niswah/features/auth/domain/email_address.dart';
import 'package:niswah/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:niswah/features/auth/presentation/widgets/email_confirmation_pending.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-up email journeys NJ-003..NJ-006, NJ-061, NJ-062, NJ-065, NJ-066
/// and NJ-296: Niswah knows only that the email service accepted a
/// request, so it never says an email was delivered; it names the
/// destination, points to the Spam folder, lets her fix a mistyped
/// address, and paces Resend with Auth's own wait.

class _FakeAuth extends AuthRepositoryImpl {
  _FakeAuth()
    : super(
        client: SupabaseClient(
          'https://x.supabase.co',
          'k',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final signUps = <String>[];
  final resends = <String>[];
  Object? resendError;

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    signUps.add(email);
    return true;
  }

  @override
  Future<void> resendEmailConfirmation({required String email}) async {
    resends.add(email);
    if (resendError != null) throw resendError!;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('email address rules', () {
    test('NJ-061: surrounding spaces and capitals are normalized only', () {
      expect(
        normalizeEmail('  Name.Surname@Gmail.COM \n'),
        'name.surname@gmail.com',
      );
      expect(looksLikeEmail('name@gmail.com'), isTrue);
      expect(looksLikeEmail('name@gmail'), isFalse);
      expect(looksLikeEmail('na me@gmail.com'), isFalse);
    });

    test('NJ-062: a known domain typo is suggested, never applied', () {
      expect(suggestEmailCorrection('sara@gmial.com'), 'sara@gmail.com');
      expect(suggestEmailCorrection('Sara@Hotmial.com'), 'sara@hotmail.com');
      expect(suggestEmailCorrection('sara@gmail.com'), isNull);
      expect(suggestEmailCorrection('sara@company.sa'), isNull);
      expect(suggestEmailCorrection('@gmial.com'), isNull);
    });

    test("Auth's rate-limit refusal is typed and keeps its wait", () {
      final failure = AuthRepositoryImpl.emailRateLimitOr(
        const AuthException(
          'For security purposes, you can only request this after 37 seconds.',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );
      expect(failure, isA<EmailRateLimitedFailure>());
      expect((failure as EmailRateLimitedFailure).retryAfterSeconds, 37);
      expect(
        AuthRepositoryImpl.emailRateLimitOr(
          const AuthException('Invalid email', statusCode: '400'),
        ),
        isNot(isA<EmailRateLimitedFailure>()),
      );
    });
  });

  group('"Check your email"', () {
    Future<void> pump(
      WidgetTester tester, {
      required Future<void> Function() onResend,
      VoidCallback? onChangeEmail,
      int cooldown = 3,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmailConfirmationPending(
                email: 'sara@gmail.com',
                onResend: onResend,
                onChangeEmail: onChangeEmail ?? () {},
                onBackToSignIn: () {},
                cooldownSeconds: cooldown,
              ),
            ),
          ),
        ),
      );
    }

    TextButton resendButton(WidgetTester tester) => tester.widget<TextButton>(
      find.byKey(const Key('email_confirmation_resend')),
    );

    testWidgets('NJ-004: Arabic names «البريد غير المرغوب فيه (Spam)» and '
        'never claims delivery', (tester) async {
      AppLocaleController.instance.setArabic(true);
      addTearDown(() => AppLocaleController.instance.setArabic(false));
      await pump(tester, onResend: () async {});
      expect(
        find.textContaining('«البريد غير المرغوب فيه (Spam)»'),
        findsOneWidget,
      );
      expect(find.text('sara@gmail.com'), findsOneWidget);
      expect(find.textContaining('وصلت'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('NJ-003/NJ-296: English names the destination and the Spam '
        'folder, and asks rather than asserts', (tester) async {
      AppLocaleController.instance.setArabic(false);
      await pump(tester, onResend: () async {});
      expect(find.text('sara@gmail.com'), findsOneWidget);
      expect(find.textContaining('Spam or Junk folder'), findsOneWidget);
      expect(find.textContaining("can't see your inbox"), findsOneWidget);
      expect(find.textContaining('delivered'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('NJ-065: Resend waits out the cooldown, then asks once and '
        'says what actually happened', (tester) async {
      AppLocaleController.instance.setArabic(false);
      var calls = 0;
      await pump(tester, onResend: () async => calls++);

      expect(resendButton(tester).onPressed, isNull, reason: 'cooling down');
      expect(find.text('Resend in 3 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(resendButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('email_confirmation_resend')));
      await tester.pump();
      expect(calls, 1);
      expect(
        find.textContaining(
          'We asked for another email to be sent to '
          'sara@gmail.com',
        ),
        findsOneWidget,
      );
      expect(find.text('Email resent.'), findsNothing);
      // A second tap right away is not possible.
      expect(resendButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('email_confirmation_resend')));
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets("NJ-006: Auth's refusal says nothing was sent and waits "
        "Auth's time", (tester) async {
      AppLocaleController.instance.setArabic(false);
      await pump(
        tester,
        cooldown: 0,
        onResend: () async =>
            throw const EmailRateLimitedFailure('wait', retryAfterSeconds: 37),
      );
      await tester.tap(find.byKey(const Key('email_confirmation_resend')));
      await tester.pump();
      expect(find.textContaining('no new email was sent'), findsOneWidget);
      expect(find.text('Resend in 37 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 38));
    });

    testWidgets('offline: no email was requested', (tester) async {
      AppLocaleController.instance.setArabic(false);
      await pump(
        tester,
        cooldown: 0,
        onResend: () async =>
            throw const NetworkFailure('Failed host lookup: x.supabase.co'),
      );
      await tester.tap(find.byKey(const Key('email_confirmation_resend')));
      await tester.pump();
      expect(find.textContaining('no email was requested'), findsOneWidget);
    });
  });

  group('sign-up sheet', () {
    Future<_FakeAuth> openSignUp(WidgetTester tester) async {
      AppLocaleController.instance.setArabic(false);
      final auth = _FakeAuth();
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(authRepositoryOverride: auth)),
      );
      await tester.pumpAndSettle();
      final checkbox = find.byKey(const Key('consent_checkbox'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Email'));
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mode_tab_sign_up')));
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('NJ-062: the typo suggestion is offered and applied only on '
        'tap', (tester) async {
      await openSignUp(tester);
      await tester.enterText(
        find.byKey(const Key('auth_email_field')),
        'sara@gmial.com',
      );
      await tester.pump();
      expect(find.byKey(const Key('email_typo_suggestion')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('auth_email_field')),
      );
      expect(field.controller!.text, 'sara@gmial.com', reason: 'untouched');
      await tester.tap(find.byKey(const Key('email_typo_suggestion')));
      await tester.pump();
      expect(field.controller!.text, 'sara@gmail.com');
      expect(find.byKey(const Key('email_typo_suggestion')), findsNothing);
    });

    testWidgets('NJ-005/NJ-061: the normalized address is shown, and "Wrong '
        'email?" returns to the form with her name kept', (tester) async {
      final auth = await openSignUp(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Full name'),
        'Sara',
      );
      await tester.enterText(
        find.byKey(const Key('auth_email_field')),
        '  Sara@Example.com ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'a-strong-password',
      );
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(auth.signUps, ['sara@example.com']);
      expect(find.text('sara@example.com'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('email_confirmation_change_email')),
      );
      await tester.tap(
        find.byKey(const Key('email_confirmation_change_email')),
      );
      await tester.pump();
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget, reason: 'name kept');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('auth_email_field')))
            .controller!
            .text,
        '  Sara@Example.com ',
        reason: 'what she typed, ready to correct',
      );
    });

    testWidgets('an address with no domain is refused before any request', (
      tester,
    ) async {
      final auth = await openSignUp(tester);
      await tester.enterText(
        find.byKey(const Key('auth_email_field')),
        'sara@gmail',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'a-strong-password',
      );
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      expect(auth.signUps, isEmpty);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });
}
