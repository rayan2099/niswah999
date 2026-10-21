// Scholar-review item (b), decided 2026-10-21 (pending scholar
// confirmation): ending pregnancy tracking without a logged birth (e.g.
// after a pregnancy loss) never starts nifas and states no ruling about
// the bleeding after it; a neutral EN/AR note points her to a scholar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/auth/presentation/screens/profile_screen.dart';
import 'package:niswah/features/pregnancy_profile/data/pregnancy_state_sync.dart';
import 'package:niswah/features/pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends PregnancyProfileRepository {
  _FakeRepo(this.row) : super(supabaseClient: null);

  PregnancyProfile? row;
  final calls = <String>[];

  @override
  Future<PregnancyProfile?> getForUser(String userId) async => row;

  @override
  Future<PregnancyProfile> upsert(PregnancyProfile profile) async {
    calls.add('upsert');
    row = profile;
    return profile;
  }

  @override
  Future<void> markPostpartumStarted(
    String userId, {
    DateTime? startDate,
  }) async {
    calls.add('markPostpartumStarted');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 10, 21, 14);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppClock.now = () => today;
    await PregnancyStatusController.instance.load();
  });
  tearDown(() => AppClock.now = DateTime.now);

  test(
    'ending tracking at week 10 starts no nifas, locally or synced',
    () async {
      final repo = _FakeRepo(
        PregnancyProfile(
          id: 'row',
          userId: 'user-1',
          trackingBasis: TrackingBasis.manualWeek,
          manualWeekValue: 10,
          manualWeekSetAt: DateTime(2026, 10, 1),
        ),
      );
      await PregnancyStatusController.instance.activate(startWeek: 10);

      final synced = await PregnancyStateSync(
        repository: repo,
        currentUserId: () => 'user-1',
        refreshNotifications: (_) async {},
      ).deactivate();

      expect(synced, isTrue);
      final c = PregnancyStatusController.instance;
      expect(c.isPregnant, isFalse);
      expect(c.isNifasActive, isFalse);
      expect(c.nifasStartedAt, isNull);
      expect(repo.calls, isNot(contains('markPostpartumStarted')));
      expect(repo.row!.isPostpartum, isFalse);
      expect(repo.row!.postpartumStartDate, isNull);
      // No postpartum/nifas status anywhere downstream (reports, reminders,
      // AI context all read the engine).
      final status = PregnancyStatusEngine.getStatus(repo.row, today);
      expect(status.mode, isNot(PregnancyMode.postpartum));
      expect(status.phase, isNull);

      // Still none the next day.
      AppClock.now = () => today.add(const Duration(days: 1));
      await PregnancyStatusController.instance.load();
      expect(PregnancyStatusController.instance.isNifasActive, isFalse);
    },
  );

  test('the note is neutral and points to a scholar, in EN and AR', () {
    const en = PregnancyStatusEngine.trackingEndedWithoutBirthNoteEn;
    const ar = PregnancyStatusEngine.trackingEndedWithoutBirthNoteAr;
    expect(en, contains('depends on how far the pregnancy had developed'));
    expect(en, contains('please consult a scholar'));
    expect(ar, contains('يُرجى استشارة أهل العلم'));
    for (final claim in ['is lifted', 'is obligatory', 'nifas has started']) {
      expect(en.toLowerCase(), isNot(contains(claim)));
    }
  });

  for (final arabic in [false, true]) {
    testWidgets('turning "I am currently pregnant" off confirms with the '
        'neutral note (${arabic ? 'AR' : 'EN'})', (tester) async {
      AppLocaleController.instance.setArabic(arabic);
      addTearDown(() => AppLocaleController.instance.setArabic(false));
      await PregnancyStatusController.instance.activate(startWeek: 10);
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      await tester.pumpAndSettle();
      final row = find.text(
        arabic ? 'أنا حامل حالياً' : 'I am currently pregnant',
      );
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final toggle = find.descendant(
        of: find.ancestor(of: row, matching: find.byType(Row)).first,
        matching: find.byType(Switch),
      );
      await tester.tap(toggle);
      // The sync re-plans reminders through real async plugin calls.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));

      expect(PregnancyStatusController.instance.isPregnant, isFalse);
      expect(PregnancyStatusController.instance.isNifasActive, isFalse);
      expect(
        find.byKey(const Key('pregnancy-tracking-ended-note')),
        findsOneWidget,
      );
      expect(
        find.text(
          arabic
              ? PregnancyStatusEngine.trackingEndedWithoutBirthNoteAr
              : PregnancyStatusEngine.trackingEndedWithoutBirthNoteEn,
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 11));
    });
  }
}
