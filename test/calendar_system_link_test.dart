import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/calendar_system_controller.dart';
import 'package:niswah/core/preferences/local_preference_scope.dart';
import 'package:niswah/core/storage/secure_local_store.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';
import 'package:niswah/features/wellbeing/domain/services/wellbeing_trend.dart';
import 'package:niswah/features/wellbeing/presentation/wellbeing_trend_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rayan, 2026-10-30: the mood chart's month names follow the Gregorian /
/// Hijri choice made in the calendar screen. All data here is synthetic.
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

  Future<void> signInAs(String id) async {
    LocalPreferenceScope.resetInMemory();
    SecureLocalStore.debugUserIdOverride = id;
    await LocalPreferenceScope.reload();
  }

  test('the calendar choice is saved per account', () async {
    await signInAs(a);
    expect(CalendarSystemController.instance.hijri, isFalse);
    await CalendarSystemController.instance.setHijri(true);

    await signInAs(b);
    expect(CalendarSystemController.instance.hijri, isFalse);

    await signInAs(a);
    expect(CalendarSystemController.instance.hijri, isTrue);
  });

  final logs = [
    WellbeingLog(
      id: 'w1',
      userId: 'local-user',
      logDate: DateTime(2026, 6, 3),
      mood: 3,
      energy: 3,
      sleep: 3,
    ),
  ];

  List<String> names(bool hijri, {bool arabic = true}) => [
    for (final b in WellbeingTrend.computeByMonth(
      logs: logs,
      from: DateTime(2026, 6, 1),
      today: DateTime(2026, 8, 18),
      monthOf: wellbeingMonthKey(hijri: hijri),
    ).buckets)
      wellbeingMonthName(b.start, arabic: arabic, hijri: hijri),
  ];

  test('Gregorian months by default', () {
    expect(names(false), ['يونيو', 'يوليو', 'أغسطس']);
  });

  test('Hijri months when the calendar is set to Hijri', () {
    // 1 June to 18 August 2026 spans Dhu al-Hijjah 1447 to Rabi I 1448.
    final hijri = names(true);
    expect(hijri.first, 'ذو الحجة');
    expect(hijri[1], 'محرم');
    expect(hijri, hasLength(greaterThanOrEqualTo(3)));
    expect(names(true, arabic: false).first, 'Dhu al-Hijjah');
  });
}
