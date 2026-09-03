import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../domain/services/fiqh_report_insights_engine.dart';

/// Renders "التقرير الفقهي" as a real PDF from real [FiqhReportInsights] —
/// no mock data, no fixed report text. Mirrors
/// wellbeing_report_pdf_builder.dart's structure; every section is gated by
/// the insights engine's own thresholds, so a sparse-data user gets an
/// honest "not enough history yet" state instead of a fabricated average.
class FiqhReportPdfBuilder {
  const FiqhReportPdfBuilder._();

  static const _brandPrimary = '#BE123C';
  static const _lightTint = '#FFE9EC';
  static const _textPrimary = '#1F2937';
  static const _textSecondary = '#6B7280';
  static const _textTertiary = '#9CA3AF';
  static const _emeraldInk = '#064E3B';
  static const _cardBg = '#FFF8F9';
  static const _gridLine = '#F3F4F6';

  // Fiqh-state colors — the same set already used elsewhere in the app
  // (dashboard's state badge), not invented for this report. Validated
  // (dataviz skill's validate_palette.js) for a donut/ring use, including
  // the wrap-around pair: worst adjacent normal-vision ΔE 20.0, wrap pair
  // (nifas ↔ tahara) ΔE 24.3 — well clear of the 15 floor.
  static const _tahara = '#0D9488';
  static const _haid = '#BE123C';
  static const _nifas = '#D97706';
  static const _advisory = '#9A6700'; // matches dashboard's needsAdvisory tone

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

  static String _madhhabLabel(Madhhab madhhab, bool isArabic) =>
      switch (madhhab) {
        Madhhab.hanafi => isArabic ? 'الحنفي' : 'Hanafi',
        Madhhab.maliki => isArabic ? 'المالكي' : 'Maliki',
        Madhhab.shafii => isArabic ? 'الشافعي' : 'Shafi\'i',
        Madhhab.hanbali => isArabic ? 'الحنبلي' : 'Hanbali',
      };

  static (String, String) _stateLabelAndColor(
    FiqhCycleState state,
    bool isArabic,
  ) => switch (state) {
    FiqhCycleState.haid => (isArabic ? 'حيض' : 'Haid', _haid),
    FiqhCycleState.tahara => (isArabic ? 'طهارة' : 'Tahara', _tahara),
    FiqhCycleState.needsAdvisory => (
      isArabic ? 'تحتاج استشارة' : 'Needs advisory',
      _advisory,
    ),
    FiqhCycleState.insufficientHistory => (
      isArabic ? 'سجل غير كافٍ' : 'Insufficient history',
      _textTertiary,
    ),
  };

  static Future<Uint8List> build({
    required bool isArabic,
    required FiqhReportInsights insights,
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
          isArabic ? 'التقرير الفقهي' : 'Fiqh Report',
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
              ? 'هذا التقرير وُلِّد من بياناتكِ المسجلة في نسوة لأغراض المتابعة الشخصية فقط، وليس فتوى أو تشخيصًا طبيًا.'
              : 'Generated from your recorded Niswah data for personal tracking only — not a fatwa or medical diagnosis.',
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
    FiqhReportInsights insights,
    pw.Font semiBold,
  ) {
    final widgets = <pw.Widget>[
      _card(
        child: pw.Row(
          children: [
            pw.Text(
              isArabic ? 'المذهب المختار: ' : 'Selected madhhab: ',
              style: pw.TextStyle(
                color: PdfColor.fromHex(_textSecondary),
                fontSize: 10,
              ),
            ),
            pw.Text(
              _madhhabLabel(insights.madhhab, isArabic),
              style: pw.TextStyle(
                font: semiBold,
                color: PdfColor.fromHex(_brandPrimary),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ];

    if (insights.mode == FiqhReportMode.nifas) {
      widgets.add(
        _card(
          bg: _lightTint,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isArabic ? 'الحالة الحالية: نفاس' : 'Current state: Nifas',
                style: pw.TextStyle(
                  font: semiBold,
                  color: PdfColor.fromHex(_nifas),
                  fontSize: 13,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                isArabic
                    ? 'اليوم ${insights.daysPostpartum} من ${insights.nifasPhase}.'
                    : 'Day ${insights.daysPostpartum} of ${insights.nifasPhase == "نفاس" ? "nifas" : "the post-nifas period"}.',
                style: pw.TextStyle(
                  color: PdfColor.fromHex(_textPrimary),
                  fontSize: 10,
                  lineSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
      if (insights.notes.isNotEmpty) {
        widgets
          ..add(
            _sectionLabel(isArabic ? 'ملاحظات مسجّلة' : 'Logged notes', semiBold),
          )
          ..add(_notesSection(insights.notes, isArabic));
      }
      return widgets;
    }

    final state = insights.cycleState!;
    final (stateLabel, stateColorHex) = _stateLabelAndColor(state, isArabic);
    widgets.add(
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
              isArabic
                  ? 'الحالة الحالية: $stateLabel'
                  : 'Current state: $stateLabel',
              style: pw.TextStyle(
                font: semiBold,
                color: PdfColor.fromHex(stateColorHex),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );

    if (state == FiqhCycleState.needsAdvisory) {
      widgets.add(
        _card(
          bg: '#FFF8E7',
          child: pw.Text(
            isArabic
                ? 'مدة الدم الحالية خارج الحدود المعتادة لمذهبكِ المختار. يُنصح بمراجعة "طبيبة" أو مختصة شرعية لتقييم حالتكِ.'
                : 'Your current bleeding duration falls outside your selected madhhab\'s usual bounds. Consulting "طبيبة" or a qualified scholar is recommended.',
            style: pw.TextStyle(
              color: PdfColor.fromHex(_advisory),
              fontSize: 10,
              lineSpacing: 2,
            ),
          ),
        ),
      );
    }

    if (insights.notes.isNotEmpty) {
      widgets
        ..add(_sectionLabel(isArabic ? 'ملاحظات مسجّلة' : 'Logged notes', semiBold))
        ..add(_notesSection(insights.notes, isArabic));
    }

    if (!insights.hasEnoughForAverages) {
      widgets.add(
        _card(
          child: pw.Text(
            isArabic
                ? 'يلزم تسجيل بدايتَي حيض لحساب المتوسط الشخصي. سجّلي دورتكِ بانتظام لتظهر هنا المتوسطات والرسوم البيانية.'
                : 'Two Haid starts are required to calculate a personal average. Keep logging your cycle, and averages and charts will appear here.',
            style: pw.TextStyle(
              color: PdfColor.fromHex(_textSecondary),
              fontSize: 10,
              lineSpacing: 2,
            ),
          ),
        ),
      );
      return widgets;
    }

    widgets
      ..add(
        _sectionLabel(
          isArabic ? 'المتوسطات الشخصية' : 'Personal averages',
          semiBold,
        ),
      )
      ..add(
        _card(
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _statColumn(
                isArabic ? 'متوسط طول الدورة' : 'Avg. cycle length',
                isArabic
                    ? '${insights.averageCycleLengthDays} يوماً'
                    : '${insights.averageCycleLengthDays} days',
                semiBold,
              ),
              _statColumn(
                isArabic ? 'متوسط مدة الحيض' : 'Avg. haid duration',
                isArabic
                    ? '${insights.averageHaidDurationDays} أيام'
                    : '${insights.averageHaidDurationDays} days',
                semiBold,
              ),
              _statColumn(
                isArabic ? 'دورات مسجّلة' : 'Episodes logged',
                '${insights.haidEpisodeCount}',
                semiBold,
              ),
            ],
          ),
        ),
      );

    if (insights.haidDurationsDays.length >= 2) {
      widgets
        ..add(
          _sectionLabel(
            isArabic ? 'مدة الحيض عبر الدورات' : 'Haid duration by episode',
            semiBold,
          ),
        )
        ..add(_haidDurationChart(insights));
    }

    return widgets;
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

  static pw.Widget _haidDurationChart(FiqhReportInsights insights) {
    final durations = insights.haidDurationsDays;
    final points = [
      for (var i = 0; i < durations.length; i++)
        pw.PointChartValue(i.toDouble(), durations[i].toDouble()),
    ];
    final maxDuration = durations.reduce((a, b) => a > b ? a : b);

    return pw.Container(
      height: 150,
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis<int>(
            [for (var i = 0; i < durations.length; i++) i],
            format: (value) => '${value.toInt() + 1}',
            textStyle: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromHex(_textTertiary),
            ),
          ),
          yAxis: pw.FixedAxis<int>(
            [for (var d = 0; d <= maxDuration + 1; d++) d],
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
            data: points,
            color: PdfColor.fromHex(_haid),
            width: 14,
            borderColor: PdfColor.fromHex(_haid),
          ),
        ],
      ),
    );
  }
}
