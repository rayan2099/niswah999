import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../wellbeing/data/repositories/wellbeing_repository.dart';
import '../../../wellbeing/domain/entities/wellbeing_log.dart';
import '../../data/repositories/flagged_conversations_repository.dart';
import '../../domain/entities/flagged_conversation.dart';
import '../../domain/entities/report_completeness.dart';
import '../../domain/entities/report_source_status.dart';
import '../../domain/services/doctor_report_insights_engine.dart';
import '../pdf/doctor_report_pdf_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Real, comprehensive "تقرير الطبيبة" — mirrors [FiqhReportScreen]'s
/// structure, injecting every repository the report draws from and
/// composing them through [DoctorReportInsightsEngine].
///
/// Every source is loaded independently and its real outcome — available,
/// genuinely empty, unavailable, or failed — travels with the report all
/// the way into the rendered PDF (PJ-006: this report must never present
/// missing or failed data as if it were a confirmed absence of anything to
/// report — the exact defect that let a silently-failing safety-flag
/// write read identically to "no concerns ever raised"). Doctor's Report
/// Data Completeness + Truthfulness wave, 2026-09-06.
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

  bool _loading = true;
  DoctorReportInsights? _insights;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _loading = true);

    final now = AppClock.now();
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    final wellbeingCurrentStart = DateTime(now.year, now.month, 1);
    final wellbeingPreviousStart = DateTime(now.year, now.month - 1, 1);
    final flaggedSince = now.subtract(const Duration(days: 90));

    // Every source is loaded independently — the same per-section
    // failure-isolation principle already established for Data Export
    // (PC-006): one source failing to load must never take down, hide, or
    // silently stand in for another that loaded fine.
    final cycleResult = await _cycleRepository.getCycleLogsForReport(
      limit: 1000,
    );

    ReportSourceResult<PregnancyProfile?> pregnancyResult;
    if (userId == null) {
      pregnancyResult = const ReportSourceResult(
        status: ReportSourceStatus.unavailable,
        data: null,
      );
    } else {
      try {
        final profile = await _pregnancyRepository.getForUser(userId);
        pregnancyResult = ReportSourceResult(
          status: profile == null
              ? ReportSourceStatus.empty
              : ReportSourceStatus.available,
          data: profile,
        );
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'DoctorReportScreen._loadSources.pregnancyProfile',
          feature: 'doctor_report',
        );
        pregnancyResult = const ReportSourceResult(
          status: ReportSourceStatus.failed,
          data: null,
        );
      }
    }

    ReportSourceResult<List<WellbeingLog>> wellbeingResult;
    try {
      final logs = await _wellbeingRepository.getLogs(
        from: wellbeingPreviousStart,
        to: now,
      );
      wellbeingResult = ReportSourceResult(
        status: logs.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: logs,
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'DoctorReportScreen._loadSources.wellbeing',
        feature: 'doctor_report',
      );
      wellbeingResult = const ReportSourceResult(
        status: ReportSourceStatus.failed,
        data: [],
      );
    }

    // The red-flag/urgent-concerns section carries an irreducible caveat
    // regardless of outcome (PJ-006): a genuinely empty result here can
    // never, by itself, prove no concerning conversation ever occurred —
    // only that none is currently recorded. That caveat is rendered
    // unconditionally in the PDF (see doctor_report_pdf_builder.dart), not
    // just when this fetch happens to fail.
    ReportSourceResult<List<FlaggedConversation>> flagsResult;
    try {
      final flags = await _flaggedConversationsRepository.getRecent(
        since: flaggedSince,
      );
      flagsResult = ReportSourceResult(
        status: flags.isEmpty
            ? ReportSourceStatus.empty
            : ReportSourceStatus.available,
        data: flags,
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'DoctorReportScreen._loadSources.flaggedConversations',
        feature: 'doctor_report',
      );
      flagsResult = const ReportSourceResult(
        status: ReportSourceStatus.failed,
        data: [],
      );
    }

    final cycleLogs = cycleResult.data;
    final wellbeingLogs = wellbeingResult.data;
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
      madhhab: MadhhabController.instance.selectedOrNull,
      pregnancyProfile: pregnancyResult.data,
      currentWellbeingLogs: currentWellbeingLogs,
      previousWellbeingLogs: previousWellbeingLogs,
      recentFlags: flagsResult.data,
      now: now,
      cycleStatus: cycleResult.status,
      pregnancyStatus: pregnancyResult.status,
      wellbeingStatus: wellbeingResult.status,
      flagsStatus: flagsResult.status,
    );

    if (!mounted) return;
    setState(() {
      _insights = insights;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(_t("Doctor's Report", 'تقرير الطبيبة'))),
      body: SafeArea(
        child: _loading
            ? Center(
                child: Text(
                  _t('Preparing your report…', 'جارٍ إعداد تقريركِ…'),
                ),
              )
            : _buildLoaded(isArabic),
      ),
    );
  }

  Widget _buildLoaded(bool isArabic) {
    final insights = _insights;
    if (insights == null) {
      return _buildLoadFailure(isArabic);
    }

    switch (insights.completeness) {
      case ReportCompleteness.loadFailure:
        return _buildLoadFailure(isArabic);
      case ReportCompleteness.insufficient:
        return _buildInsufficientData(isArabic);
      case ReportCompleteness.partial:
        return Column(
          children: [
            _CompletenessBanner(insights: insights, isArabic: isArabic),
            Expanded(child: _buildPdfPreview(isArabic, insights)),
          ],
        );
      case ReportCompleteness.complete:
        return _buildPdfPreview(isArabic, insights);
    }
  }

  Widget _buildPdfPreview(bool isArabic, DoctorReportInsights insights) {
    return PdfPreview(
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: 'niswah_doctor_report.pdf',
      build: (format) => DoctorReportPdfBuilder.build(
        isArabic: isArabic,
        insights: insights,
        generatedAt: AppClock.now(),
      ),
      loadingWidget: Center(
        child: Text(_t('Preparing your report…', 'جارٍ إعداد تقريركِ…')),
      ),
    );
  }

  Widget _buildLoadFailure(bool isArabic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Color(0xFF9F1239),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _t(
                  "Your cycle history could not be loaded, so this report "
                      "can't be generated right now.",
                  'تعذّر تحميل سجل دورتكِ، لذا لا يمكن إنشاء هذا التقرير '
                      'الآن.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _loadSources,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t('Try again', 'إعادة المحاولة')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsufficientData(bool isArabic) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(height: 16),
            Text(
              _t(
                "There isn't enough recorded history yet to generate a "
                    'meaningful report. Log a few cycle entries first.',
                'لا يوجد سجل كافٍ بعد لإنشاء تقرير مفيد. سجّلي بعض '
                    'بيانات الدورة أولاً.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Names, in plain non-alarming language, exactly which optional sections
/// could not be loaded this time — never silently dropped, never phrased
/// in clinical/urgent language for an ordinary loading hiccup.
class _CompletenessBanner extends StatelessWidget {
  const _CompletenessBanner({required this.insights, required this.isArabic});

  final DoctorReportInsights insights;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final failedLabels = <String>[];
    if (insights.pregnancyStatus == ReportSourceStatus.failed) {
      failedLabels.add(_t('pregnancy status', 'حالة الحمل'));
    }
    if (insights.wellbeingStatus == ReportSourceStatus.failed) {
      failedLabels.add(_t('wellbeing check-ins', 'المتابعة النفسية'));
    }
    if (insights.flagsStatus == ReportSourceStatus.failed) {
      failedLabels.add(_t('recent urgent concerns', 'المخاوف العاجلة'));
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: _t(
        'This report is partial. Some information could not be loaded.',
        'هذا التقرير غير مكتمل. تعذّر تحميل بعض المعلومات.',
      ),
      child: Container(
        width: double.infinity,
        color: const Color(0xFFFFF7E6),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _t(
                  'This report reflects only the information that could be '
                      'loaded. The following could not be loaded and are not '
                      'reflected: ${failedLabels.join(", ")}.',
                  'يعكس هذا التقرير فقط المعلومات التي أمكن تحميلها. '
                      'تعذّر تحميل التالي ولا يظهر في التقرير: '
                      '${failedLabels.join("، ")}.',
                ),
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
