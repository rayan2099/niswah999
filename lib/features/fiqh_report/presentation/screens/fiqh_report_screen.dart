import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../cycle_tracking/domain/services/report_canonical_evidence.dart';
import '../../domain/services/fiqh_report_insights_engine.dart';
import '../pdf/fiqh_report_pdf_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Real "التقرير الفقهي" — mirrors [WellbeingReportScreen]'s structure:
/// injectable repositories, a [PdfPreview] body, and a `_generate` that
/// fetches real data, runs it through the insights engine, then the PDF
/// builder. No mock content.
class FiqhReportScreen extends StatefulWidget {
  const FiqhReportScreen({
    super.key,
    CycleTrackingRepositoryImpl? cycleRepository,
    PregnancyProfileRepository? pregnancyRepository,
  }) : _cycleRepository = cycleRepository,
       _pregnancyRepository = pregnancyRepository;

  final CycleTrackingRepositoryImpl? _cycleRepository;
  final PregnancyProfileRepository? _pregnancyRepository;

  @override
  State<FiqhReportScreen> createState() => _FiqhReportScreenState();
}

class _FiqhReportScreenState extends State<FiqhReportScreen> {
  late final CycleTrackingRepositoryImpl _cycleRepository =
      widget._cycleRepository ?? CycleTrackingRepositoryImpl();
  late final PregnancyProfileRepository _pregnancyRepository =
      widget._pregnancyRepository ?? PregnancyProfileRepository();

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(_t('Fiqh Report', 'التقرير الفقهي'))),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'niswah_fiqh_report.pdf',
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

    final cycleLogs = await _cycleRepository.getCycleLogs(limit: 1000);
    final pregnancyProfile = userId == null
        ? null
        : await _pregnancyRepository.getForUser(userId);

    final canonical = await ReportCanonicalEvidence.load(
      userId: userId,
      now: now,
    );

    final insights = FiqhReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: MadhhabController.instance.selectedOrNull,
      pregnancyProfile: pregnancyProfile,
      now: now,
      canonical: canonical,
    );

    return FiqhReportPdfBuilder.build(
      isArabic: isArabic,
      insights: insights,
      generatedAt: now,
    );
  }
}
