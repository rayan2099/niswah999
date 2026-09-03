import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../cycle_tracking/domain/services/cycle_segment_planner.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../fiqh_report/domain/services/fiqh_report_insights_engine.dart';
import '../../domain/services/husband_report_insights_engine.dart';

/// Renders "تقرير الزوج" as a real PDF from real [HusbandReportInsights] —
/// ported from the reference web app's `HusbandReport` (src/components/
/// Reports.tsx): current state, upcoming days, and a fixed religious note.
/// Deliberately excludes everything the fiqh/doctor reports show — flow
/// intensity, blood color, symptoms, notes — this report is meant to be
/// shared outside the app, so it carries the minimum a husband needs.
class HusbandReportPdfBuilder {
  const HusbandReportPdfBuilder._();

  static const _brandPrimary = '#BE123C';
  static const _lightTint = '#FFE9EC';
  static const _textPrimary = '#1F2937';
  static const _textSecondary = '#6B7280';
  static const _textTertiary = '#9CA3AF';
  static const _emeraldInk = '#064E3B';
  static const _cardBg = '#FFF8F9';
  static const _gridLine = '#F3F4F6';

  static const _tahara = '#0D9488';
  static const _haid = '#BE123C';
  static const _nifas = '#D97706';
  static const _advisory = '#9A6700';
  static const _istihadah = '#4F46E5';
  static const _brandSecondary = '#FB7185';

  static const _amberBg = '#FFFBEB';
  static const _amberBorder = '#FDE68A';
  static const _amberInk = '#92400E';

  static const _tealTint = '#E6F5F3';
  static const _tealInk = '#0F5C52';

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

  static String _dateLabel(DateTime date, bool isArabic) =>
      isArabic
          ? '${date.day} ${_monthLabel(date, true)} ${date.year}'
          : '${_monthLabel(date, false)} ${date.day}, ${date.year}';

  static (String, String) _stateLabelAndColor(
    FiqhCycleState state,
    bool isArabic,
  ) => switch (state) {
    FiqhCycleState.haid => (isArabic ? 'حيض' : 'Haid', _haid),
    FiqhCycleState.tahara => (isArabic ? 'طهارة' : 'Tahara', _tahara),
    FiqhCycleState.needsAdvisory => (
      isArabic ? 'تحتاج مراجعة' : 'Needs review',
      _advisory,
    ),
    FiqhCycleState.insufficientHistory => (
      isArabic ? 'سجل غير كافٍ' : 'Insufficient history',
      _textTertiary,
    ),
  };

  /// Mirrors the dashboard's cycle-ring color mapping (`_segmentColor` in
  /// dashboard_screen.dart) so the printed report and the live app never
  /// disagree about what each color means.
  static String _segmentColorHex(CycleSegmentId id) => switch (id) {
    CycleSegmentId.haid => _haid,
    CycleSegmentId.tahara1 || CycleSegmentId.tahara2 => _tahara,
    CycleSegmentId.fertile => _nifas,
    CycleSegmentId.prePeriod => _istihadah,
    CycleSegmentId.expected => _brandSecondary,
  };

  static String _segmentLabel(CycleSegmentId id, bool isArabic) => switch (id) {
    CycleSegmentId.haid => isArabic ? 'حيض' : 'Haid',
    CycleSegmentId.tahara1 || CycleSegmentId.tahara2 =>
      isArabic ? 'طهارة' : 'Tahara',
    CycleSegmentId.fertile => isArabic ? 'خصوبة' : 'Fertile',
    CycleSegmentId.prePeriod => isArabic ? 'ما قبل الحيض' : 'Pre-Period',
    CycleSegmentId.expected => isArabic ? 'حيض متوقع' : 'Expected Period',
  };

  static Future<Uint8List> build({
    required bool isArabic,
    required HusbandReportInsights insights,
    required DateTime generatedAt,
  }) async {
    final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final semiBoldData = await rootBundle.load(
      'assets/fonts/Cairo-SemiBold.ttf',
    );
    final logoData = await rootBundle.load('assets/images/logo.png');

    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    final semiBold = pw.Font.ttf(semiBoldData);
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        margin: const pw.EdgeInsets.fromLTRB(28, 0, 28, 28),
        header: (context) => _header(isArabic, generatedAt, semiBold, logo),
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
    pw.MemoryImage logo,
  ) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 22),
    padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex(_lightTint),
      borderRadius: const pw.BorderRadius.only(
        bottomLeft: pw.Radius.circular(20),
        bottomRight: pw.Radius.circular(20),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 30,
                  height: 30,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FFFFFF'),
                    shape: pw.BoxShape.circle,
                  ),
                  child: pw.Image(logo, width: 22, height: 22, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  'NISWAH',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex(_brandPrimary),
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            pw.Text(
              isArabic
                  ? 'أُنشئ في ${_dateLabel(generatedAt, true)}'
                  : 'Generated ${_dateLabel(generatedAt, false)}',
              style: pw.TextStyle(
                color: PdfColor.fromHex(_textSecondary),
                fontSize: 8,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          isArabic ? 'تقرير الزوج' : 'Husband Report',
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_emeraldInk),
            fontSize: 26,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: 46,
          height: 3,
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex(_brandPrimary),
            borderRadius: pw.BorderRadius.circular(1.5),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _footer(bool isArabic) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Column(
      children: [
        pw.Container(height: 1.4, color: PdfColor.fromHex(_brandPrimary)),
        pw.SizedBox(height: 8),
        pw.Text(
          isArabic
              ? 'هذا التقرير خاص وسري، أُعد بموافقة الزوجة عبر تطبيق نسوة.'
              : "This report is private and confidential — prepared with the wife's consent via the Niswah app.",
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textTertiary),
            fontSize: 8,
          ),
        ),
      ],
    ),
  );

  /// Plain rounded card — deliberately a *uniform* border/no border, since
  /// the `pdf` package's `BoxDecoration` throws if a non-uniform `Border`
  /// (e.g. a single colored accent side) is combined with `borderRadius`.
  static pw.Widget _accentCard({
    required pw.Widget child,
    required bool isArabic,
    String? bg,
    String accentHex = _brandPrimary,
  }) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 16),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex(bg ?? _cardBg),
      borderRadius: pw.BorderRadius.circular(14),
    ),
    padding: const pw.EdgeInsets.all(16),
    child: child,
  );

  static pw.Widget _sectionLabel(String text, String accentHex, pw.Font semiBold) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 7,
              height: 7,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex(accentHex),
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              text,
              style: pw.TextStyle(
                font: semiBold,
                color: PdfColor.fromHex(_emeraldInk),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  static pw.Widget _infoRow(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(color: PdfColor.fromHex(_textPrimary), fontSize: 10),
    ),
  );

  static pw.Widget _statTile({
    required String label,
    required String value,
    required String accentHex,
  }) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFFFFF'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromHex(_gridLine)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: PdfColor.fromHex(_textTertiary),
              fontSize: 7,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: PdfColor.fromHex(accentHex),
              fontWeight: pw.FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    ),
  );

  /// A proportional horizontal bar — one colored block per cycle segment,
  /// width proportional to its day count — so a husband can see at a glance
  /// where the fertile window sits relative to the whole cycle, not just
  /// read two dates. The segment matching "today" gets a dark outline.
  static pw.Widget _fertilityTimeline(CycleSegmentPlan plan) => pw.Row(
    children: [
      for (var i = 0; i < plan.segments.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 2),
        pw.Expanded(
          flex: plan.segments[i].durationDays,
          child: pw.Container(
            height: 18,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex(_segmentColorHex(plan.segments[i].id)),
              borderRadius: pw.BorderRadius.circular(4),
              border: i == plan.activeIndex
                  ? pw.Border.all(color: PdfColor.fromHex(_textPrimary), width: 1.4)
                  : null,
            ),
          ),
        ),
      ],
    ],
  );

  static pw.Widget _fertilityLegend(CycleSegmentPlan plan, bool isArabic) {
    // Dedup by the *visible label*, not the segment id — tahara1 and
    // tahara2 are distinct ids that both read "طهارة"/"Tahara", and would
    // otherwise show up as two identical legend entries.
    final seenLabels = <String>{};
    final entries = <(String label, String colorHex)>[
      for (final segment in plan.segments)
        if (seenLabels.add(_segmentLabel(segment.id, isArabic)))
          (_segmentLabel(segment.id, isArabic), _segmentColorHex(segment.id)),
    ];
    return pw.Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (label, colorHex) in entries)
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex(colorHex),
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Text(
                label,
                style: pw.TextStyle(color: PdfColor.fromHex(_textSecondary), fontSize: 8.5),
              ),
            ],
          ),
      ],
    );
  }

  static List<pw.Widget> _body(
    bool isArabic,
    HusbandReportInsights insights,
    pw.Font semiBold,
  ) {
    final fiqh = insights.fiqh;
    final isNifas = fiqh.mode == FiqhReportMode.nifas;
    final (stateLabel, stateColorHex) = isNifas
        ? (isArabic ? 'نفاس' : 'Nifas', _nifas)
        : _stateLabelAndColor(fiqh.cycleState!, isArabic);

    final currentDayLine = isNifas
        ? (isArabic
              ? 'اليوم ${insights.fiqh.daysPostpartum}'
              : 'Day ${insights.fiqh.daysPostpartum}')
        : (fiqh.cycleState == FiqhCycleState.insufficientHistory
              ? (isArabic ? 'غير كافٍ للحساب' : 'Insufficient data for calculation')
              : null);

    final safeNextPeriod = insights.nextPeriodDate == null
        ? (isArabic ? 'غير محدد بعد' : 'Not determined yet')
        : _dateLabel(insights.nextPeriodDate!, isArabic);
    final safeFertileWindow =
        insights.fertileWindowStart == null || insights.fertileWindowEnd == null
        ? '...'
        : '${_dateLabel(insights.fertileWindowStart!, isArabic)} - ${_dateLabel(insights.fertileWindowEnd!, isArabic)}';

    return [
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(0, 0, 0, 18),
        child: pw.Text(
          isArabic
              ? '${insights.displayName}،'
              : '${insights.displayName},',
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_textSecondary),
            fontSize: 12,
          ),
        ),
      ),
      _sectionLabel(
        isArabic ? 'الحالة الحالية' : 'Current State',
        stateColorHex,
        semiBold,
      ),
      _accentCard(
        bg: _lightTint,
        isArabic: isArabic,
        accentHex: stateColorHex,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex(stateColorHex),
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Text(
                isArabic ? 'الحالة: $stateLabel' : 'State: $stateLabel',
                style: pw.TextStyle(
                  font: semiBold,
                  color: PdfColor.fromHex('#FFFFFF'),
                  fontSize: 12,
                ),
              ),
            ),
            if (currentDayLine != null) ...[
              pw.SizedBox(height: 10),
              _infoRow(currentDayLine),
            ],
            pw.SizedBox(height: currentDayLine != null ? 2 : 10),
            _infoRow(
              isArabic
                  ? 'متى تنتهي الدورة المتوقع: $safeNextPeriod'
                  : 'Expected End: $safeNextPeriod',
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      _sectionLabel(
        isArabic ? 'الأيام القادمة' : 'Upcoming Days',
        _brandPrimary,
        semiBold,
      ),
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 16),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _statTile(
              label: isArabic
                  ? 'الحيض المتوقع القادم'
                  : 'NEXT EXPECTED PERIOD',
              value: safeNextPeriod,
              accentHex: _haid,
            ),
            pw.SizedBox(width: 10),
            _statTile(
              label: isArabic ? 'نافذة الخصوبة' : 'FERTILITY WINDOW',
              value: safeFertileWindow,
              accentHex: _tahara,
            ),
          ],
        ),
      ),
      if (insights.segmentPlan != null) ...[
        _sectionLabel(
          isArabic ? 'الجدول الزمني للخصوبة' : 'Fertility Timeline',
          _nifas,
          semiBold,
        ),
        _accentCard(
          isArabic: isArabic,
          bg: '#FFFFFF',
          accentHex: _nifas,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _fertilityTimeline(insights.segmentPlan!),
              pw.SizedBox(height: 10),
              _fertilityLegend(insights.segmentPlan!, isArabic),
              if (insights.fertilePeakDay != null) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex(_amberBg),
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: PdfColor.fromHex(_amberBorder)),
                  ),
                  child: pw.Text(
                    isArabic
                        ? 'أخصب يوم متوقع للحمل: ${_dateLabel(insights.fertilePeakDay!, true)}'
                        : 'Peak fertility day: ${_dateLabel(insights.fertilePeakDay!, false)}',
                    style: pw.TextStyle(
                      font: semiBold,
                      color: PdfColor.fromHex(_amberInk),
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
              pw.SizedBox(height: 12),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex(_tealTint),
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(color: PdfColor.fromHex(_tahara)),
                ),
                child: pw.Text(
                  isArabic
                      ? 'معرفة نافذة الخصوبة تساعدكما على تحديد أخصب الأيام لتحقيق الحمل بإذن الله، وهي خطوة عملية على طريق تكوين الأسرة. نسأل الله أن يبارك لكما ويرزقكما الذرية الصالحة.'
                      : 'Knowing the fertility window helps you both identify the most likely days for conception, in shaa Allah — a practical step on the path to building your family. May Allah bless you both and grant you righteous offspring.',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex(_tealInk),
                    fontSize: 9.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      _sectionLabel(
        isArabic ? 'ملاحظة دينية' : 'Religious Note',
        _amberInk,
        semiBold,
      ),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex(_amberBg),
          borderRadius: pw.BorderRadius.circular(14),
          border: pw.Border.all(color: PdfColor.fromHex(_amberBorder)),
        ),
        child: pw.Text(
          isArabic
              ? 'وفقاً للفقه الإسلامي، يُحرم الجماع خلال فترة الحيض. جزاك الله خيراً على اهتمامك بصحة زوجتك.'
              : "According to Islamic Fiqh, intercourse is prohibited during the menstrual period. May Allah reward you for your care for your wife's health.",
          style: pw.TextStyle(color: PdfColor.fromHex(_amberInk), fontSize: 10),
        ),
      ),
    ];
  }
}
