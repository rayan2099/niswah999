import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../domain/services/husband_report_insights_engine.dart';
import '../pdf/husband_report_pdf_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Real "تقرير الزوج" — mirrors [FiqhReportScreen]'s structure: injectable
/// repositories, a [PdfPreview] body, and a `_generate` that fetches real
/// data, runs it through the insights engine, then the PDF builder. No
/// mock content — replaces the old `_ReportPreview` placeholder that always
/// showed the same hardcoded date and "log your cycle" text regardless of
/// the wife's actual state.
class HusbandReportScreen extends StatefulWidget {
  const HusbandReportScreen({
    super.key,
    required this.displayName,
    CycleTrackingRepositoryImpl? cycleRepository,
    PregnancyProfileRepository? pregnancyRepository,
  }) : _cycleRepository = cycleRepository,
       _pregnancyRepository = pregnancyRepository;

  /// The name shown at the top of the report — already resolved by the
  /// caller (falls back to "أخت"/"Sister" for an anonymous-mode user), so
  /// this screen doesn't need its own copy of that anonymity rule.
  final String displayName;

  final CycleTrackingRepositoryImpl? _cycleRepository;
  final PregnancyProfileRepository? _pregnancyRepository;

  @override
  State<HusbandReportScreen> createState() => _HusbandReportScreenState();
}

class _HusbandReportScreenState extends State<HusbandReportScreen> {
  late final CycleTrackingRepositoryImpl _cycleRepository =
      widget._cycleRepository ?? CycleTrackingRepositoryImpl();
  late final PregnancyProfileRepository _pregnancyRepository =
      widget._pregnancyRepository ?? PregnancyProfileRepository();

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(_t('Husband Report', 'تقرير الزوج'))),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'niswah_husband_report.pdf',
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

    final insights = HusbandReportInsightsEngine.analyze(
      cycleLogs: cycleLogs,
      madhhab: MadhhabController.instance.selected,
      displayName: widget.displayName,
      pregnancyProfile: pregnancyProfile,
      now: now,
    );

    return HusbandReportPdfBuilder.build(
      isArabic: isArabic,
      insights: insights,
      generatedAt: now,
    );
  }
}
