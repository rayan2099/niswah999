import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's pregnancy engine and the SERVER's engine (the code the AI Edge
/// Functions use to build the pregnancy context) must agree. Both run over the
/// same vectors: this file runs the Dart engine; scripts/pregnancy_status_parity.mjs
/// runs the real supabase/functions/_shared/pregnancy_status.ts (Node, in CI).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vectors = jsonDecode(
    File('test/fixtures/pregnancy_status_vectors.json').readAsStringSync(),
  ) as List<dynamic>;

  for (final raw in vectors) {
    final v = raw as Map<String, dynamic>;
    test('Dart engine: ${v['name']}', () {
      final row = v['row'] as Map<String, dynamic>?;
      final status = PregnancyStatusEngine.getStatus(
        row == null ? null : PregnancyProfile.fromJson(row),
        DateTime.parse(v['today'] as String),
      );
      final want = v['expected'] as Map<String, dynamic>;
      expect(status.mode.name, want['mode']);
      if (want.containsKey('week')) expect(status.week, want['week']);
      if (want.containsKey('trimester'))
        expect(status.trimester, want['trimester']);
      if (want.containsKey('month')) expect(status.month, want['month']);
      if (want.containsKey('weeksToDue'))
        expect(status.weeksToDue, want['weeksToDue']);
      if (want.containsKey('daysPostpartum')) {
        expect(status.daysPostpartum, want['daysPostpartum']);
      }
      if (want.containsKey('phase')) expect(status.phase, want['phase']);
    });
  }

  group(
    'PREG-03: the on-device week progresses with the (controlled) clock',
    () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });
      tearDown(() => AppClock.now = DateTime.now);

      test(
        'week 12 today -> 13 after 7 days -> 19 after 49 days -> capped at 40',
        () async {
          final start = DateTime(2026, 9, 26, 10);
          AppClock.now = () => start;
          final c = PregnancyStatusController.instance;
          await c.activate(startWeek: 12);
          expect(c.currentWeek, 12);
          AppClock.now = () => start.add(const Duration(days: 6));
          expect(c.currentWeek, 12);
          AppClock.now = () => start.add(const Duration(days: 7));
          expect(c.currentWeek, 13);
          AppClock.now = () => start.add(const Duration(days: 49));
          expect(c.currentWeek, 19);
          AppClock.now = () => start.add(const Duration(days: 400));
          expect(c.currentWeek, 40);
          await c.deactivate();
        },
      );

      test('Nifas day counter follows the clock (day 1 on the day, ends after 40 days)', () async {
        final birth = DateTime(2026, 9, 1, 8);
        AppClock.now = () => birth;
        final c = PregnancyStatusController.instance;
        await c.startNifas();
        expect(c.nifasDay, 1);
        expect(c.isNifasActive, isTrue);
        AppClock.now = () => birth.add(const Duration(days: 39));
        expect(c.isNifasActive, isTrue);
        AppClock.now = () => birth.add(const Duration(days: 40));
        expect(c.isNifasActive, isFalse);
        await c.deactivate();
      });
    },
  );
}
