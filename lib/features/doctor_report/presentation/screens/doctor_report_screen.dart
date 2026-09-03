import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../wellbeing/data/repositories/wellbeing_repository.dart';
import '../../data/repositories/flagged_conversations_repository.dart';
import '../../domain/services/doctor_report_insights_engine.dart';
import '../pdf/doctor_report_pdf_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Real, comprehensive "تقرير الطبيبة" — mirrors [FiqhReportScreen]'s
/// structure, injecting every repository the report draws from and
/// composing them through [DoctorReportInsightsEngine].
class DoctorReportScreen extends StatefulWidget {
  const DoctorReportScreen({
    super.key,
    CycleTrackingRepositoryImpl? cycleRepository,
    PregnancyProfileRepository? pregnancyRepository,
    WellbeingRepository? wellbeingRepository,
    FlaggedConversationsRepository? flaggedConversationsRepository,
  }) : _cycleRepository = cycleRepository,
       _pregnancyRepository = pregnancyRepository,
       _wellbeingRepository = wellbeingRepository,
       _flaggedConversationsRepository = flaggedConversationsRepository;

  final CycleTrackingRepositoryImpl? _cycleRepository;
  final PregnancyProfileRepository? _pregnancyRepository;
  final WellbeingRepository? _wellbeingRepository;
  final FlaggedConversationsRepository? _flaggedConversationsRepository;

  @override
  State<DoctorReportScreen> createState() => _DoctorReportScreenState();
}

class _DoctorReportScreenState extends State<DoctorReportScreen> {
  late final CycleTrackingRepositoryImpl _cycleRepository =
      widget._cycleRepository ?? CycleTrackingRepositoryImpl();
  late final PregnancyProfileRepository _pregnancyRepository =
      widget._pregnancyRepository ?? PregnancyProfileRepository();
  late final WellbeingRepository _wellbeingRepository =
      widget._wellbeingRepository ?? WellbeingRepository();
  late final FlaggedConversationsRepository _flaggedConversationsRepository =
      widget._flaggedConversationsRepository ??
      FlaggedConversationsRepository();

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(_t("Doctor's Report", 'تقرير الطبيبة'))),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'niswah_doctor_report.pdf',
        build: (format) => _generate(isArabic),
        loadingWidget: Center(
          child: Text(_t('Preparing your report…', 'جارٍ إعداد تقريركِ…')),
        ),
      ),
    );
  }

  Future<Uint8List> _generate(bool isArabic) async {
    final now = AppClock.now();
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    final wellbeingCurrentStart = DateTime(now.year, now.month, 1);
    final wellbeingPreviousStart = DateTime(now.year, now.month - 1, 1);
    final flaggedSince = now.subtract(const Duration(days: 90));

    final cycleLogs = await _cycleRepository.getCycleLogs(limit: 1000);
    final pregnancyProfile = userId == null
        ? null
        : await _pregnancyRepository.getForUser(userId);
    final wellbeingLogs = await _wellbeingRepository.getLogs(
      from: wellbeingPreviousStart,
      to: now,
    );
    final recentFlags = await _flaggedConversationsRepository.getRecent(
      since: flaggedSince,
    );

    final currentWellbeingLogs = wellbeingLogs
        .where((log) => !log.logDate.isBefore(wellbeingCurrentStart))
        .toList();
    final previousWellbeingLogs = wellbeingLogs
        .where(
          (log) =>
              !log.logDate.isBefore(wellbeingPreviousStart) &&
              log.logDate.isBefore(wellbeingCurrentStart),
        )
        .toList();

    final insights = DoctorReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: MadhhabController.instance.selected,
      pregnancyProfile: pregnancyProfile,
      currentWellbeingLogs: currentWellbeingLogs,
      previousWellbeingLogs: previousWellbeingLogs,
      recentFlags: recentFlags,
      now: now,
    );

    return DoctorReportPdfBuilder.build(
      isArabic: isArabic,
      insights: insights,
      generatedAt: now,
    );
  }
}
