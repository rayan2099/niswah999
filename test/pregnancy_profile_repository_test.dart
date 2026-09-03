import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';

void main() {
  group('PregnancyProfileRepository', () {
    test('getForUser returns null when Supabase is unavailable', () async {
      final repository = PregnancyProfileRepository();

      final result = await repository.getForUser('user-1');

      expect(result, isNull);
    });

    test(
      'upsert throws rather than silently succeeding when Supabase is unavailable',
      () async {
        final repository = PregnancyProfileRepository();
        final profile = PregnancyProfile(
          id: 'profile-1',
          userId: 'user-1',
          trackingBasis: TrackingBasis.manualWeek,
          manualWeekValue: 10,
          manualWeekSetAt: DateTime(2026, 1, 1),
        );

        expect(() => repository.upsert(profile), throwsA(isA<StateError>()));
      },
    );
  });
}
