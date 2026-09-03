import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:niswah/features/doctor_report/domain/entities/flagged_conversation.dart';
import 'package:niswah/features/doctor_report/domain/services/doctor_report_insights_engine.dart';
import 'package:niswah/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';

CycleLog _cycleLog(
  int day, {
  required FlowLevel flow,
  int cycleDay = 1,
  List<String> symptoms = const [],
  String? notes,
}) {
  return CycleLog(
    id: 'cycle-$day',
    userId: 'user-1',
    date: DateTime(2026, 1, day),
    flow: flow,
    cycleDay: cycleDay,
    symptoms: symptoms,
    notes: notes,
  );
}

WellbeingLog _wellbeingLog(int day, {required int mood}) {
  return WellbeingLog(
    id: 'wb-$day',
    userId: 'user-1',
    logDate: DateTime(2026, 1, day),
    mood: mood,
    energy: 3,
    sleep: 3,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the fully sparse state (no data anywhere)', () async {
    final insights = DoctorReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.hanbali,
      currentWellbeingLogs: const [],
      previousWellbeingLogs: const [],
      recentFlags: const [],
      now: DateTime(2026, 1, 20),
    );

    final bytesAr = await DoctorReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );
    final bytesEn = await DoctorReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 20),
    );

    expect(bytesAr.isNotEmpty, isTrue);
    expect(bytesEn.isNotEmpty, isTrue);
  });

  test('renders every section when all data is present', () async {
    final cycleLogs = [
      _cycleLog(
        1,
        flow: FlowLevel.medium,
        cycleDay: 1,
        symptoms: const ['Cramps:2', 'Headache:1'],
        notes: 'felt dizzy, took Panadol',
      ),
      _cycleLog(2, flow: FlowLevel.medium, cycleDay: 2, symptoms: const ['Cramps:3']),
      _cycleLog(3, flow: FlowLevel.none, cycleDay: 3),
      _cycleLog(29, flow: FlowLevel.medium, cycleDay: 1, symptoms: const ['Cramps:1']),
      _cycleLog(30, flow: FlowLevel.medium, cycleDay: 2),
      _cycleLog(31, flow: FlowLevel.none, cycleDay: 3),
    ];
    final wellbeingLogs = List.generate(6, (i) => _wellbeingLog(i + 1, mood: 4));
    final flags = [
      FlaggedConversation(
        id: 'flag-1',
        threadId: 'thread-1',
        messageExcerpt: 'عندي نزيف الآن',
        matchedCategories: const ['bleeding'],
        createdAt: DateTime(2026, 1, 5),
      ),
    ];
    final profile = PregnancyProfile(
      id: 'p1',
      userId: 'user-1',
      highRiskFlags: const ['gestational diabetes'],
    );

    final insights = DoctorReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: Madhhab.hanbali,
      pregnancyProfile: profile,
      currentWellbeingLogs: wellbeingLogs,
      previousWellbeingLogs: const [],
      recentFlags: flags,
      now: DateTime(2026, 2, 5),
    );

    expect(insights.cycleAndPregnancy.hasEnoughForAverages, isTrue);
    expect(insights.topSymptoms, isNotEmpty);
    expect(insights.recentNotes, isNotEmpty);
    expect(insights.recentFlags, isNotEmpty);
    expect(insights.highRiskFlags, ['gestational diabetes']);

    final bytes = await DoctorReportPdfBuilder.build(
      isArabic: true,
      insights: insights,
      generatedAt: DateTime(2026, 2, 5),
    );

    expect(bytes.isNotEmpty, isTrue);
  });

  test('renders the nifas overview state', () async {
    final profile = PregnancyProfile(
      id: 'p1',
      userId: 'user-1',
      isPostpartum: true,
      postpartumStartDate: DateTime(2026, 1, 1),
    );

    final insights = DoctorReportInsightsEngine.analyze(
      cycleLogs: const [],
      madhhab: Madhhab.shafii,
      pregnancyProfile: profile,
      currentWellbeingLogs: const [],
      previousWellbeingLogs: const [],
      recentFlags: const [],
      now: DateTime(2026, 1, 15),
    );

    expect(insights.cycleAndPregnancy.mode.name, 'nifas');

    final bytes = await DoctorReportPdfBuilder.build(
      isArabic: false,
      insights: insights,
      generatedAt: DateTime(2026, 1, 15),
    );

    expect(bytes.isNotEmpty, isTrue);
  });
}
