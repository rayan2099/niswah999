import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/auth/auth_controller.dart';

void main() {
  // AuthController is a singleton, so each test resets the flag it owns
  // rather than constructing a fresh instance.
  setUp(() => AuthController.instance.clearNewSignUp());

  test('markSignedUp flips isNewSignUp and notifies listeners', () {
    var notified = false;
    AuthController.instance.addListener(() => notified = true);

    expect(AuthController.instance.isNewSignUp, isFalse);
    AuthController.instance.markSignedUp();

    expect(AuthController.instance.isNewSignUp, isTrue);
    expect(notified, isTrue);
  });

  test(
    'clearNewSignUp resets the flag — the root router calls this from '
    "onboarding's onFinished so a completed signup only shows onboarding "
    'once',
    () {
      AuthController.instance.markSignedUp();
      expect(AuthController.instance.isNewSignUp, isTrue);

      AuthController.instance.clearNewSignUp();
      expect(AuthController.instance.isNewSignUp, isFalse);
    },
  );

  test('markSignedUp is idempotent — calling it twice notifies only once', () {
    var notifyCount = 0;
    AuthController.instance.addListener(() => notifyCount++);

    AuthController.instance.markSignedUp();
    AuthController.instance.markSignedUp();

    expect(notifyCount, 1);
  });
}
