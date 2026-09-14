import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import '../../../wellbeing/domain/services/wellbeing_insights_engine.dart';
import '../../domain/entities/flagged_conversation.dart';
import '../../domain/entities/report_completeness.dart';
import '../../domain/entities/report_source_status.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../domain/services/doctor_report_insights_engine.dart';

/// Renders "تقرير الطبيبة" — a comprehensive PDF combining cycle/pregnancy
/// status, symptom history, a wellbeing snapshot, and recent flagged chat
/// concerns. Every section is gated by its own source engine's thresholds
/// (reused as-is, not re-derived), so sparse data still reads honestly.
class DoctorReportPdfBuilder {
  const DoctorReportPdfBuilder._();

  static const _brandPrimary = '#BE123C';
  static const _textPrimary = '#1F2937';
  static const _textSecondary = '#6B7280';
  static const _textTertiary = '#9CA3AF';
  static const _emeraldInk = '#064E3B';
  static const _cardBg = '#FFF8F9';
  static const _lightTint = '#FFE9EC';
  static const _gridLine = '#F3F4F6';
  static const _haid = '#BE123C';
  static const _tahara = '#0D9488';
  static const _nifas = '#D97706';
  static const _advisory = '#9A6700';
  static const _urgent = '#9F1239';

  static const _monthNamesEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _monthNamesAr = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String _monthLabel(DateTime date, bool isArabic) =>
      isArabic ? _monthNamesAr[date.month - 1] : _monthNamesEn[date.month - 1];

  static (String, String) _stateLabelAndColor(
    FiqhCycleState state,
    bool isArabic,
  ) => switch (state) {
    FiqhCycleState.haid => (
      isArabic ? 'الدورة الشهرية نشطة حالياً' : 'Currently menstruating',
      _haid,
    ),
    FiqhCycleState.tahara => (
      isArabic ? 'لا توجد دورة نشطة حالياً' : 'Not currently menstruating',
      _tahara,
    ),
    FiqhCycleState.needsAdvisory => (
      isArabic
          ? 'نزيف يستدعي تقييماً طبياً'
          : 'Bleeding pattern needs evaluation',
      _advisory,
    ),
    FiqhCycleState.insufficientHistory => (
      isArabic ? 'سجل غير كافٍ بعد' : 'Not enough history yet',
      _textTertiary,
    ),
    // Fiqh Remediation Wave 1 (Section E): bleeding is occurring but no
    // Madhhab is SELECTED yet, so the fiqh-derived classification above
    // cannot be produced — shown plainly rather than guessed.
    FiqhCycleState.madhhabUnresolved => (
      isArabic
          ? 'يلزم اختيار المذهب لتحديد الحالة'
          : 'Madhhab selection required',
      _textTertiary,
    ),
  };

  static Future<Uint8List> build({
    required bool isArabic,
    required DoctorReportInsights insights,
    required DateTime generatedAt,
  }) async {
    final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final semiBoldData = await rootBundle.load(
      'assets/fonts/Cairo-SemiBold.ttf',
    );

    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    final semiBold = pw.Font.ttf(semiBoldData);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
        header: (context) => _header(isArabic, generatedAt, semiBold),
        footer: (context) => _footer(isArabic),
        build: (context) => _body(isArabic, insights, semiBold),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(
    bool isArabic,
    DateTime generatedAt,
    pw.Font semiBold,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 18),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'NISWAH',
              style: pw.TextStyle(
                color: PdfColor.fromHex(_brandPrimary),
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 2,
                fontSize: 11,
              ),
            ),
            pw.Text(
              isArabic
                  ? 'أُنشئ في ${generatedAt.day} ${_monthLabel(generatedAt, true)} ${generatedAt.year}'
                  : 'Generated ${_monthLabel(generatedAt, false)} ${generatedAt.day}, ${generatedAt.year}',
              style: pw.TextStyle(
                color: PdfColor.fromHex(_textTertiary),
                fontSize: 8,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          isArabic ? 'تقرير الطبيبة' : "Doctor's Report",
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_emeraldInk),
            fontSize: 22,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _footer(bool isArabic) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Column(
      children: [
        pw.Divider(color: PdfColor.fromHex(_gridLine)),
        pw.SizedBox(height: 6),
        pw.Text(
          isArabic
              ? 'هذا التقرير مُلخّص من بياناتكِ المسجلة في نسوة لمشاركته مع طبيبتكِ، وليس تشخيصًا طبيًا بحد ذاته.'
              : 'This report summarizes your recorded Niswah data to share with your doctor — it is not a medical diagnosis on its own.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textTertiary),
            fontSize: 8,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _card({required pw.Widget child, String? bg}) =>
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 16),
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex(bg ?? _cardBg),
          borderRadius: pw.BorderRadius.circular(14),
        ),
        child: child,
      );

  static pw.Widget _sectionLabel(String text, pw.Font semiBold) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: semiBold,
        color: PdfColor.fromHex(_emeraldInk),
        fontSize: 12,
      ),
    ),
  );

  static List<pw.Widget> _body(
    bool isArabic,
    DoctorReportInsights insights,
    pw.Font semiBold,
  ) {
    final widgets = <pw.Widget>[
      if (insights.completeness == ReportCompleteness.partial)
        _partialReportNotice(insights, isArabic),
      _sectionLabel(isArabic ? 'نظرة عامة' : 'Overview', semiBold),
      ..._overviewSection(isArabic, insights.cycleAndPregnancy, semiBold),
    ];

    if (insights.highRiskFlags.isNotEmpty) {
      widgets.add(_highRiskFlagsCard(insights.highRiskFlags, isArabic));
    }

    if (insights.topSymptoms.isNotEmpty) {
      widgets
        ..add(
          _sectionLabel(
            isArabic ? 'الأعراض الأكثر تكراراً' : 'Most frequent symptoms',
            semiBold,
          ),
        )
        ..add(_symptomChart(insights.topSymptoms, isArabic));
    }

    if (insights.recentBloodColors.isNotEmpty) {
      widgets
        ..add(
          _sectionLabel(
            isArabic ? 'لون الدم المسجّل' : 'Logged blood color',
            semiBold,
          ),
        )
        ..add(_notesSection(insights.recentBloodColors, isArabic));
    }

    if (insights.recentNotes.isNotEmpty) {
      widgets
        ..add(
          _sectionLabel(isArabic ? 'ملاحظات مسجّلة' : 'Logged notes', semiBold),
        )
        ..add(_notesSection(insights.recentNotes, isArabic));
    }

    widgets
      ..add(_sectionLabel(isArabic ? 'الحالة النفسية' : 'Wellbeing', semiBold))
      ..add(_wellbeingSummary(isArabic, insights.wellbeing, semiBold));

    // Always rendered — never silently omitted when empty (PJ-006). A
    // doctor reading this report must be able to tell "no urgent concerns
    // were recorded" from "this section simply isn't here," since the
    // second reads, to an unaware reader, as indistinguishable from the
    // first despite meaning something very different.
    widgets
      ..add(
        _sectionLabel(
          isArabic ? 'مخاوف عاجلة حديثة' : 'Recent urgent concerns',
          semiBold,
        ),
      )
      ..add(_urgentConcernsSection(insights, isArabic));

    return widgets;
  }

  static pw.Widget _urgentConcernsSection(
    DoctorReportInsights insights,
    bool isArabic,
  ) {
    if (insights.flagsStatus == ReportSourceStatus.failed) {
      return _limitationNote(
        isArabic
            ? 'تعذّر تحميل هذا القسم لهذا التقرير. لا يعني عدم ظهور مخاوف '
                  'هنا عدم وجودها.'
            : "This section could not be loaded for this report. Its "
                  "absence here does not mean no concerns exist.",
      );
    }

    if (insights.recentFlags.isEmpty) {
      return _limitationNote(
        isArabic
            ? 'لا توجد مخاوف عاجلة مسجّلة لهذه الفترة. يعكس هذا فقط '
                  'المحادثات التي تم تسجيلها بنجاح داخل التطبيق، ولا ينفي '
                  'احتمال وجود مخاوف لم تُحفظ بسبب عطل تقني.'
            : 'No urgent concerns are recorded for this period. This '
                  'reflects only conversations the app successfully '
                  'recorded, and does not rule out a concern that went '
                  'unsaved due to a technical issue.',
      );
    }

    return _flaggedConcerns(insights.recentFlags, isArabic);
  }

  /// Travels with the report wherever it goes — printed, saved, or
  /// shared — so a partial report can never lose its own disclosure by
  /// being exported out of the app (PJ-006/Phase K).
  static pw.Widget _partialReportNotice(
    DoctorReportInsights insights,
    bool isArabic,
  ) {
    final failedLabels = <String>[];
    if (insights.pregnancyStatus == ReportSourceStatus.failed) {
      failedLabels.add(isArabic ? 'حالة الحمل' : 'pregnancy status');
    }
    if (insights.wellbeingStatus == ReportSourceStatus.failed) {
      failedLabels.add(isArabic ? 'المتابعة النفسية' : 'wellbeing check-ins');
    }
    if (insights.flagsStatus == ReportSourceStatus.failed) {
      failedLabels.add(isArabic ? 'المخاوف العاجلة' : 'recent urgent concerns');
    }

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF7E6),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFF3D9A8)),
      ),
      child: pw.Text(
        isArabic
            ? 'هذا التقرير غير مكتمل. يعكس فقط المعلومات التي أمكن '
                  'تحميلها. تعذّر تحميل التالي: ${failedLabels.join("، ")}.'
            : 'This report is partial. It reflects only the information '
                  'that could be loaded. The following could not be '
                  'loaded: ${failedLabels.join(", ")}.',
        style: pw.TextStyle(color: PdfColor.fromHex(_advisory), fontSize: 9.5),
      ),
    );
  }

  static pw.Widget _limitationNote(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFF3F4F6),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(color: PdfColor.fromHex(_textSecondary), fontSize: 9),
    ),
  );

  static List<pw.Widget> _overviewSection(
    bool isArabic,
    FiqhReportInsights cycleAndPregnancy,
    pw.Font semiBold,
  ) {
    if (cycleAndPregnancy.mode == FiqhReportMode.nifas) {
      return [
        _card(
          bg: _lightTint,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isArabic
                    ? 'في فترة النفاس'
                    : 'In the postpartum (nifas) period',
                style: pw.TextStyle(
                  font: semiBold,
                  color: PdfColor.fromHex(_nifas),
                  fontSize: 13,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                isArabic
                    ? 'اليوم ${cycleAndPregnancy.daysPostpartum} بعد الولادة.'
                    : 'Day ${cycleAndPregnancy.daysPostpartum} postpartum.',
                style: pw.TextStyle(
                  color: PdfColor.fromHex(_textPrimary),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final state = cycleAndPregnancy.cycleState!;
    final (stateLabel, stateColorHex) = _stateLabelAndColor(state, isArabic);
    final widgets = <pw.Widget>[
      _card(
        bg: _lightTint,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 10,
              height: 10,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex(stateColorHex),
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              stateLabel,
              style: pw.TextStyle(
                font: semiBold,
                color: PdfColor.fromHex(stateColorHex),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ];

    if (cycleAndPregnancy.hasEnoughForAverages) {
      widgets.add(
        _card(
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _statColumn(
                isArabic ? 'متوسط طول الدورة' : 'Avg. cycle length',
                isArabic
                    ? '${cycleAndPregnancy.averageCycleLengthDays} يوماً'
                    : '${cycleAndPregnancy.averageCycleLengthDays} days',
                semiBold,
              ),
              _statColumn(
                isArabic ? 'متوسط مدة النزيف' : 'Avg. bleeding duration',
                isArabic
                    ? '${cycleAndPregnancy.averageHaidDurationDays} أيام'
                    : '${cycleAndPregnancy.averageHaidDurationDays} days',
                semiBold,
              ),
              _statColumn(
                isArabic ? 'دورات مسجّلة' : 'Cycles logged',
                '${cycleAndPregnancy.haidEpisodeCount}',
                semiBold,
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  static pw.Widget _highRiskFlagsCard(List<String> flags, bool isArabic) =>
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 16),
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFFFF8E7),
          borderRadius: pw.BorderRadius.circular(14),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE8C978)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              isArabic
                  ? 'ملاحظات طبية ذكرتها المستخدمة'
                  : 'User-stated conditions to note',
              style: pw.TextStyle(
                color: PdfColor.fromHex(_advisory),
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final flag in flags)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      // Unlike Flutter's canvas, the pdf package doesn't
                      // clamp a corner radius to half the box's own size —
                      // circular(99) on a ~17px-tall chip made the corner
                      // arcs overshoot and self-intersect into a star.
                      // 10 is comfortably below half this chip's height.
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(
                      flag,
                      style: pw.TextStyle(
                        color: PdfColor.fromHex(_textPrimary),
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );

  static pw.Widget _statColumn(String label, String value, pw.Font semiBold) =>
      pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              font: semiBold,
              color: PdfColor.fromHex(_brandPrimary),
              fontSize: 15,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: PdfColor.fromHex(_textSecondary),
              fontSize: 8.5,
            ),
          ),
        ],
      );

  static pw.Widget _symptomChart(
    List<SymptomAggregate> symptoms,
    bool isArabic,
  ) {
    final top = symptoms.take(6).toList();
    final maxCount = top
        .map((s) => s.occurrenceCount)
        .reduce((a, b) => a > b ? a : b);

    return pw.Container(
      height: 150,
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis<int>(
            [for (var i = 0; i < top.length; i++) i],
            format: (value) => top[value.toInt()].name,
            textStyle: pw.TextStyle(
              fontSize: 7,
              color: PdfColor.fromHex(_textTertiary),
            ),
          ),
          yAxis: pw.FixedAxis<int>(
            [for (var c = 0; c <= maxCount + 1; c++) c],
            divisions: true,
            divisionsColor: PdfColor.fromHex(_gridLine),
            textStyle: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromHex(_textTertiary),
            ),
          ),
        ),
        datasets: [
          pw.BarDataSet(
            data: [
              for (var i = 0; i < top.length; i++)
                pw.PointChartValue(
                  i.toDouble(),
                  top[i].occurrenceCount.toDouble(),
                ),
            ],
            color: PdfColor.fromHex(_brandPrimary),
            width: 14,
            borderColor: PdfColor.fromHex(_brandPrimary),
          ),
        ],
      ),
    );
  }

  static pw.Widget _wellbeingSummary(
    bool isArabic,
    WellbeingInsights wellbeing,
    pw.Font semiBold,
  ) {
    if (!wellbeing.hasEnoughForCharts || wellbeing.averageMoodCurrent == null) {
      return _card(
        child: pw.Text(
          isArabic
              ? 'لا يوجد سجل كافٍ للحالة النفسية هذا الشهر بعد.'
              : 'Not enough wellbeing check-ins this month yet.',
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textSecondary),
            fontSize: 10,
          ),
        ),
      );
    }

    final average = wellbeing.averageMoodCurrent!.toStringAsFixed(1);
    final trendText = switch (wellbeing.trendDirection) {
      MoodTrendDirection.improving =>
        isArabic ? 'تميل إلى التحسن' : 'trending toward improvement',
      MoodTrendDirection.declining =>
        isArabic ? 'تميل إلى الانخفاض' : 'trending downward',
      MoodTrendDirection.fluctuating =>
        isArabic ? 'متقلبة أكثر من المعتاد' : 'fluctuating more than usual',
      MoodTrendDirection.stable ||
      null => isArabic ? 'مستقرة نسبياً' : 'fairly stable',
    };

    return _card(
      child: pw.Text(
        isArabic
            ? 'متوسط الحالة المزاجية هذا الشهر $average من 5، و$trendText. للتفاصيل الكاملة، راجعي تقرير الحالة النفسية.'
            : 'Average mood this month: $average/5, $trendText. See the Mental State Report for full detail.',
        style: pw.TextStyle(
          font: semiBold,
          color: PdfColor.fromHex(_textPrimary),
          fontSize: 10,
          lineSpacing: 2,
        ),
      ),
    );
  }

  static pw.Widget _notesSection(List<NotedEntry> notes, bool isArabic) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final note in notes)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex(_cardBg),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    isArabic
                        ? '${note.date.day} ${_monthLabel(note.date, true)}'
                        : '${_monthLabel(note.date, false)} ${note.date.day}',
                    style: pw.TextStyle(
                      color: PdfColor.fromHex(_textTertiary),
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    note.text,
                    style: pw.TextStyle(
                      color: PdfColor.fromHex(_textPrimary),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  static pw.Widget _flaggedConcerns(
    List<FlaggedConversation> recentFlags,
    bool isArabic,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final flag in recentFlags)
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFFFF1F2),
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFFFCDD5)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                flag.matchedCategories.join(', '),
                style: pw.TextStyle(
                  color: PdfColor.fromHex(_urgent),
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                flag.messageExcerpt,
                style: pw.TextStyle(
                  color: PdfColor.fromHex(_textPrimary),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
