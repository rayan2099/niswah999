// PT-112: predicted bleeding never creates qadha debt. Fasting-qadha
// automation is deferred (product decision 2026-10-29), so the guarantee
// is structural: no tracking or prediction code can write a qadha record,
// no table for one exists, and prayer status is never inferred from a
// prediction.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/prayer_tracking/domain/controllers/prayer_time_calculator.dart';
import 'package:niswah/features/prayer_tracking/domain/entities/prayer_entry.dart';

final _qadha = RegExp(
  r'qadha|qada\b|makeup_fast|fasting_debt',
  caseSensitive: false,
);

Iterable<File> _files(String dir, String ext) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(ext));

void main() {
  test('PT-112: only the prayer-tracking layer works with qadha; no '
      'tracking, prediction, Today, Insights or reminder code does', () {
    // Display-only text that names qadha without touching any record.
    const allowedLines = {
      'lib/features/dashboard/presentation/screens/dashboard_screen.dart':
          "'Qadha Example: Missed Dhuhr',",
    };
    final offending = <String>[];
    for (final f in _files('lib', '.dart')) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/features/prayer_tracking/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_qadha.hasMatch(lines[i])) continue;
        if (lines[i].trim() == allowedLines[path]) continue;
        offending.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offending, isEmpty);
  });

  test('PT-112: no migration creates a qadha or fasting-debt table or '
      'column', () {
    final createsDebt = RegExp(
      r'create\s+table[^;]*(qadha|qada_|fasting_debt|makeup_fast)',
      caseSensitive: false,
    );
    final addsDebtColumn = RegExp(
      r'add\s+column[^;]*(qadha|fasting_debt|makeup_fast)',
      caseSensitive: false,
    );
    for (final f in _files('supabase/migrations', '.sql')) {
      final sql = f.readAsStringSync();
      expect(createsDebt.hasMatch(sql), isFalse, reason: f.path);
      expect(addsDebtColumn.hasMatch(sql), isFalse, reason: f.path);
    }
  });

  test('PT-112: prayer status has no qadha value and is never inferred, '
      'whatever the time or the predicted bleeding', () {
    expect(
      PrayerStatus.values.map((s) => s.name),
      isNot(contains(matches(_qadha))),
    );
    final schedule = PrayerSchedule(
      date: DateTime(2027, 2, 10),
      fajr: const TimeOfDay(hour: 5, minute: 0),
      dhuhr: const TimeOfDay(hour: 12, minute: 0),
      asr: const TimeOfDay(hour: 15, minute: 30),
      maghrib: const TimeOfDay(hour: 18, minute: 0),
      isha: const TimeOfDay(hour: 19, minute: 30),
    );
    for (final name in PrayerName.values) {
      expect(
        PrayerTimeCalculator.statusFor(
          schedule: schedule,
          prayerName: name,
          now: DateTime(2027, 2, 11, 23),
        ),
        PrayerStatus.pending,
      );
    }
  });
}
