import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/local_preference_scope.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/core/preferences/marital_status_controller.dart';
import 'package:niswah/core/preferences/notification_log_controller.dart';
import 'package:niswah/core/preferences/prayer_location_controller.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/preferences/ttc_mode_controller.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:niswah/features/notifications/domain/entities/notification_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-017 — device-local answers used to sit under one global key each, so a
/// second person signing in on the same phone inherited the first person's
/// marital status, TTC mode, pregnancy overview, prayer city, reminder choices
/// and notification feed. They are now namespaced by the signed-in user.
void main() {
  const a = '11111111-1111-1111-1111-111111111111';
  const b = '22222222-2222-2222-2222-222222222222';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureLocalStore.debugUserIdOverride = null;
    LocalPreferenceScope.resetInMemory();
  });
  tearDown(() {
    SecureLocalStore.debugUserIdOverride = null;
    LocalPreferenceScope.resetInMemory();
  });

  Future<void> signInAs(String? id) async {
    LocalPreferenceScope.resetInMemory();
    SecureLocalStore.debugUserIdOverride = id;
    await LocalPreferenceScope.reload();
  }

  test('a second account sees none of the first account\'s answers, and the '
      'first gets hers back', () async {
    await signInAs(a);
    await MaritalStatusController.instance.setMarried(true);
    await TtcModeController.instance.setEnabled(true);
    await PregnancyStatusController.instance.activate(startWeek: 12);
    await PrayerLocationController.instance.select(
      PrayerLocationController.presets.first, // Riyadh
    );
    await NotificationLogController.instance.add(
      NotificationLogEntry(
        id: 'n1',
        type: NotificationType.activeBleeding,
        titleAr: 'ع',
        bodyAr: 'ع',
        titleEn: 'Time for your daily check-in',
        bodyEn: 'x',
        createdAt: DateTime(2026, 9, 27),
      ),
    );
    final repoA = NotificationRepositoryImpl();
    final prefsA = await repoA.loadPreferences();
    await repoA.savePreferences({
      ...prefsA,
      NotificationType.wellbeing: prefsA[NotificationType.wellbeing]!.copyWith(
        enabled: false,
      ),
    });

    // ---- B on the same phone ----
    await signInAs(b);
    expect(MaritalStatusController.instance.isMarried, isFalse);
    expect(TtcModeController.instance.enabled, isFalse);
    expect(PregnancyStatusController.instance.isPregnant, isFalse);
    expect(PrayerLocationController.instance.selectedOrNull, isNull);
    expect(NotificationLogController.instance.entries, isEmpty);
    final prefsB = await NotificationRepositoryImpl().loadPreferences();
    expect(
      prefsB[NotificationType.wellbeing]!.enabled,
      isTrue,
      reason: 'B has her own defaults, not A\'s "wellbeing off"',
    );

    // B's own answers do not disturb A's.
    await MaritalStatusController.instance.setMarried(false);
    await TtcModeController.instance.setEnabled(true);

    // ---- A signs back in ----
    await signInAs(a);
    expect(MaritalStatusController.instance.isMarried, isTrue);
    expect(TtcModeController.instance.enabled, isTrue);
    expect(PregnancyStatusController.instance.isPregnant, isTrue);
    expect(PregnancyStatusController.instance.startWeek, 12);
    expect(PrayerLocationController.instance.selectedOrNull?.label, 'Riyadh');
    expect(NotificationLogController.instance.entries.map((e) => e.id), ['n1']);
    final prefsA2 = await NotificationRepositoryImpl().loadPreferences();
    expect(prefsA2[NotificationType.wellbeing]!.enabled, isFalse);
  });

  test('the Madhhab local cache (used when the server cannot be read) is '
      'per user too', () async {
    SecureLocalStore.debugUserIdOverride = a;
    await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
    expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);

    // B signs in and the server row cannot be read (offline / RLS error):
    // she must NOT fall back to A's cached Madhhab.
    MadhhabController.instance.resetInMemory();
    SecureLocalStore.debugUserIdOverride = b;
    await MadhhabController.instance.load();
    expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
    expect(MadhhabController.instance.selectedOrNull, isNull);

    MadhhabController.instance.resetInMemory();
    SecureLocalStore.debugUserIdOverride = a;
    await MadhhabController.instance.load();
    expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
    MadhhabController.instance.resetInMemory();
  });

  test('sign-out clears the in-memory answers at once', () async {
    await signInAs(a);
    await MaritalStatusController.instance.setMarried(true);
    await PregnancyStatusController.instance.activate(startWeek: 20);
    expect(PregnancyStatusController.instance.isPregnant, isTrue);

    LocalPreferenceScope.resetInMemory();

    expect(MaritalStatusController.instance.isMarried, isFalse);
    expect(PregnancyStatusController.instance.isPregnant, isFalse);
    expect(PregnancyStatusController.instance.nifasStartedAt, isNull);
  });

  test('Nifas state is per user too', () async {
    await signInAs(a);
    await PregnancyStatusController.instance.startNifas();
    expect(PregnancyStatusController.instance.isNifasActive, isTrue);

    await signInAs(b);
    expect(PregnancyStatusController.instance.isNifasActive, isFalse);

    await signInAs(a);
    expect(PregnancyStatusController.instance.isNifasActive, isTrue);
  });

  test('an existing install keeps its owner\'s answers exactly once: the old '
      'global keys move to the first user who loads them and are removed, so '
      'they can never reach a second user', () async {
    SharedPreferences.setMockInitialValues({
      'niswah_is_married': true,
      'niswah_ttc_mode_enabled': true,
      'niswah_is_pregnant': true,
      'niswah_pregnancy_start_week': 9,
      'niswah_pregnancy_activated_at': DateTime(2026, 9, 1).toIso8601String(),
      'niswah_prayer_location_lat': 24.7136,
      'niswah_prayer_location_lng': 46.6753,
      'niswah_prayer_location_label': 'Riyadh',
    });

    await signInAs(a);
    expect(MaritalStatusController.instance.isMarried, isTrue);
    expect(TtcModeController.instance.enabled, isTrue);
    expect(PregnancyStatusController.instance.isPregnant, isTrue);
    expect(PregnancyStatusController.instance.startWeek, 9);
    expect(PrayerLocationController.instance.selectedOrNull?.label, 'Riyadh');

    final prefs = await SharedPreferences.getInstance();
    for (final legacy in [
      'niswah_is_married',
      'niswah_ttc_mode_enabled',
      'niswah_is_pregnant',
      'niswah_pregnancy_start_week',
      'niswah_pregnancy_activated_at',
      'niswah_prayer_location_lat',
      'niswah_prayer_location_lng',
      'niswah_prayer_location_label',
    ]) {
      expect(prefs.containsKey(legacy), isFalse, reason: '$legacy moved');
    }

    await signInAs(b);
    expect(MaritalStatusController.instance.isMarried, isFalse);
    expect(TtcModeController.instance.enabled, isFalse);
    expect(PregnancyStatusController.instance.isPregnant, isFalse);
    expect(PrayerLocationController.instance.selectedOrNull, isNull);
  });

  test('with no session the plain key is used (unchanged behaviour)', () async {
    await signInAs(null);
    await MaritalStatusController.instance.setMarried(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('niswah_is_married'), isTrue);
  });
}
