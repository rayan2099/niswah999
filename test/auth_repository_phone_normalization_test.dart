import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/auth/data/repositories/auth_repository_impl.dart';

void main() {
  group('AuthRepositoryImpl.normalizePhone', () {
    test('strips the leading + to match the Supabase Dashboard test-phone '
        'override format ("966535110460=123456", no plus)', () {
      expect(
        AuthRepositoryImpl.normalizePhone('+966535110460'),
        '966535110460',
      );
    });

    test('leaves an already digits-only number unchanged', () {
      expect(
        AuthRepositoryImpl.normalizePhone('966535110460'),
        '966535110460',
      );
    });

    test('strips internal spaces and dashes too', () {
      expect(
        AuthRepositoryImpl.normalizePhone('+966 535-110-460'),
        '966535110460',
      );
    });
  });
}
