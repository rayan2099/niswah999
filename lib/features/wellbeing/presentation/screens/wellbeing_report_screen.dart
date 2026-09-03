import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../data/repositories/wellbeing_repository.dart';
import '../../domain/services/wellbeing_insights_engine.dart';
import '../pdf/wellbeing_report_pdf_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Generates "تقرير الحالة النفسية" from the caller's real `wellbeing_logs`
/// history (see [WellbeingRepository]) — this month vs last month, with
/// every chart/insight gated by [WellbeingInsightsEngine]'s thresholds so a
/// sparse-data user sees an honest "still building your picture" state
/// instead of a padded-out report.
class WellbeingReportScreen extends StatefulWidget {
  const WellbeingReportScreen({
    super.key,
    WellbeingRepository? repository,
    CycleTrackingRepositoryImpl? cycleRepository,
  }) : _repository = repository,
       _cycleRepository = cycleRepository;

  final WellbeingRepository? _repository;
  final CycleTrackingRepositoryImpl? _cycleRepository;

  @override
  State<WellbeingReportScreen> createState() => _WellbeingReportScreenState();
}

class _WellbeingReportScreenState extends State<WellbeingReportScreen> {
  late final WellbeingRepository _repository =
      widget._repository ?? WellbeingRepository();
  late final CycleTrackingRepositoryImpl _cycleRepository =
      widget._cycleRepository ?? CycleTrackingRepositoryImpl();

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(_t('Mental State Report', 'تقرير الحالة النفسية')),
      ),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'niswah_wellbeing_report.pdf',
        build: (format) => _generate(isArabic),
        loadingWidget: Center(
          child: Text(_t('Preparing your report…', 'جارٍ إعداد تقريركِ…')),
        ),
      ),
    );
  }

  Future<Uint8List> _generate(bool isArabic) async {
    final now = AppClock.now();
    final currentStart = DateTime(now.year, now.month, 1);
    // DateTime normalizes month 0 to December of the prior year, so this
    // handles the January -> December rollover without special-casing it.
    final previousStart = DateTime(now.year, now.month - 1, 1);

    final logs = await _repository.getLogs(from: previousStart, to: now);

    final currentLogs = logs
        .where((log) => !log.logDate.isBefore(currentStart))
        .toList();
    final previousLogs = logs
        .where(
          (log) =>
              !log.logDate.isBefore(previousStart) &&
              log.logDate.isBefore(currentStart),
        )
        .toList();

    final insights = WellbeingInsightsEngine.analyze(
      currentPeriodLogs: currentLogs,
      previousPeriodLogs: previousLogs,
      daysElapsedInPeriod: now.day,
    );

    final cycleLogs = await _cycleRepository.getCycleLogs(limit: 1000);
    final notes = CycleSymptomDecoder.recentNotes(cycleLogs);

    return WellbeingReportPdfBuilder.build(
      isArabic: isArabic,
      insights: insights,
      notes: notes,
      periodStart: currentStart,
      generatedAt: now,
    );
  }
}
