import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/auth/presentation/models/profile_form_data.dart';

void main() {
  group('ProfileFormData', () {
    test('accepts a valid display name update', () {
      final formData = ProfileFormData(
        displayName: 'Niswah User',
        email: 'user@example.com',
      );

      expect(formData.validate(), isNull);
    });

    test('rejects overly long display names', () {
      final formData = ProfileFormData(
        displayName: 'A' * 70,
        email: 'user@example.com',
      );

      expect(formData.validate(), contains('display name'));
    });
  });
}
