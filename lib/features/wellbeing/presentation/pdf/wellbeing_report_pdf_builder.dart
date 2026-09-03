import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../domain/services/wellbeing_insights_engine.dart';

/// Renders "تقرير الحالة النفسية" as a real PDF from real
/// [WellbeingInsights] — no mock data, no fixed report text. Every section
/// below is gated by the insight engine's own thresholds (see
/// [WellbeingInsightsEngine]), so a sparse-data user gets the honest
/// "still building your picture" state instead of a padded-out report.
class WellbeingReportPdfBuilder {
  const WellbeingReportPdfBuilder._();

  static const _brandPrimary = '#BE123C';
  static const _lightTint = '#FFE9EC';
  static const _textPrimary = '#1F2937';
  static const _textSecondary = '#6B7280';
  static const _textTertiary = '#9CA3AF';
  static const _emeraldInk = '#064E3B';
  static const _tahara = '#0D9488';
  static const _cardBg = '#FFF8F9';
  static const _gridLine = '#F3F4F6';

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

  static String _moodLabel(int mood, bool isArabic) => switch (mood) {
    1 => isArabic ? 'سيء جداً' : 'Very Sad',
    2 => isArabic ? 'سيء' : 'Sad',
    3 => isArabic ? 'متوسط' : 'Neutral',
    4 => isArabic ? 'جيد' : 'Good',
    _ => isArabic ? 'ممتاز جداً' : 'Excellent',
  };

  /// One fixed, distinct hue per mood value (1-5), rather than a single-hue
  /// intensity ramp. This set is validated (dataviz skill's
  /// `validate_palette.js`) against every *adjacent* pair the donut can put
  /// on screen — including the wrap-around pair between the first and last
  /// wedge, since a ring is a cycle, not a line: worst adjacent CVD ΔE 9.1,
  /// worst adjacent normal-vision ΔE 19.6, wrap pair (slot 5 ↔ slot 1) ΔE
  /// 27.5. Never reorder these five without re-running the validator —
  /// swapping slots can break the pairwise guarantee.
  static const _moodColors = [
    '#2a78d6', // 1 — سيء جداً / Very Sad
    '#eb6834', // 2 — سيء / Sad
    '#1baf7a', // 3 — متوسط / Neutral
    '#eda100', // 4 — جيد / Good
    '#e87ba4', // 5 — ممتاز جداً / Excellent
  ];

  static PdfColor _moodShade(int mood) =>
      PdfColor.fromHex(_moodColors[(mood - 1).clamp(0, 4)]);

  static Future<Uint8List> build({
    required bool isArabic,
    required WellbeingInsights insights,
    required DateTime periodStart,
    required DateTime generatedAt,
    List<NotedEntry> notes = const [],
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
        header: (context) =>
            _header(isArabic, periodStart, generatedAt, semiBold),
        footer: (context) => _footer(isArabic),
        build: (context) => _body(isArabic, insights, notes, semiBold),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(
    bool isArabic,
    DateTime periodStart,
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
          isArabic ? 'تقرير الحالة النفسية' : 'Mental State Report',
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_emeraldInk),
            fontSize: 22,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${_monthLabel(periodStart, isArabic)} ${periodStart.year}',
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textSecondary),
            fontSize: 10,
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
              ? 'هذا التقرير وُلِّد من بياناتكِ المسجلة في نسوة لأغراض المتابعة الشخصية فقط، وليس تشخيصًا طبيًا.'
              : 'Generated from your recorded Niswah data for personal tracking only — not a medical diagnosis.',
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
    WellbeingInsights insights,
    List<NotedEntry> notes,
    pw.Font semiBold,
  ) {
    final widgets = <pw.Widget>[
      _card(
        child: pw.Text(
          _narrative(isArabic, insights),
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textPrimary),
            fontSize: 11,
            lineSpacing: 3,
          ),
        ),
      ),
      _card(
        bg: _lightTint,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                isArabic
                    ? 'سجّلتِ حالتك ${insights.currentCount} يومًا هذا الشهر — استمري'
                    : 'You checked in ${insights.currentCount} days this month — keep it up',
                style: pw.TextStyle(
                  font: semiBold,
                  color: PdfColor.fromHex(_brandPrimary),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    if (notes.isNotEmpty) {
      widgets
        ..add(_sectionLabel(isArabic ? 'ملاحظات مسجّلة' : 'Logged notes', semiBold))
        ..add(_notesSection(notes, isArabic));
    }

    if (!insights.hasEnoughForCharts) {
      widgets.add(
        _card(
          child: pw.Text(
            isArabic
                ? 'ما زلنا نبني صورة واضحة عن حالتك. سجّلي حالتكِ بانتظام في الصفحة الرئيسية لتظهر هنا الرسوم البيانية والملاحظات الشخصية.'
                : 'We\'re still building a clear picture of your patterns. Keep checking in from the dashboard, and charts and personal insights will appear here.',
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
          isArabic ? 'توزيع حالتك المزاجية' : 'Mood distribution',
          semiBold,
        ),
      )
      ..add(_moodDonut(insights, isArabic))
      ..add(pw.SizedBox(height: 10))
      ..add(
        _sectionLabel(
          isArabic ? 'اتجاه حالتك عبر الوقت' : 'Mood over time',
          semiBold,
        ),
      )
      ..add(_trendChart(insights));

    if (insights.sleepPatternFound) {
      final low = insights.averageMoodOnLowSleepDays!.toStringAsFixed(1);
      final higher = insights.averageMoodOnHigherSleepDays!.toStringAsFixed(1);
      widgets.add(
        _card(
          child: pw.Text(
            isArabic
                ? 'لاحظنا أن حالتك المزاجية غالبًا ما تكون أقل في الأيام التي سجّلتِ فيها قلة نوم (بمتوسط $low مقابل $higher في أيام النوم الأفضل). قد يفيد إعطاء الأولوية لقسط أكبر من الراحة عند الإمكان.'
                : 'We noticed your mood tends to be lower on days you logged less sleep (average $low vs $higher on better-sleep days). Prioritizing a bit more rest when you can may help.',
            style: pw.TextStyle(
              color: PdfColor.fromHex(_textPrimary),
              fontSize: 10,
              lineSpacing: 2,
            ),
          ),
        ),
      );
    }

    widgets.add(
      _card(
        bg: '#ECFDF5',
        child: pw.Text(
          insights.goodDaysCount > 0
              ? (isArabic
                    ? 'كان لديكِ ${insights.goodDaysCount} يومًا شعرتِ فيه بحالة جيدة أو ممتازة هذا الشهر — لاحظي ما ساعدكِ في تلك الأيام.'
                    : 'You had ${insights.goodDaysCount} days this month where you felt good or excellent — worth noticing what helped on those days.')
              : (isArabic
                    ? 'الأهم أنكِ واظبتِ على المتابعة هذا الشهر — وهذا بحد ذاته خطوة مهمة نحو فهم نفسك أكثر.'
                    : 'What matters most is that you kept checking in this month — that consistency is a meaningful step on its own.'),
          style: pw.TextStyle(
            color: PdfColor.fromHex(_tahara),
            fontSize: 10,
            lineSpacing: 2,
          ),
        ),
      ),
    );

    if (insights.escalationRecommended) {
      widgets.add(
        _card(
          bg: '#EEF2FF',
          child: pw.Text(
            isArabic
                ? 'لاحظنا أن حالتك المزاجية كانت منخفضة بشكل متكرر خلال هذه الفترة. نسوة هنا لدعمك، ولكن التحدث إلى شخص تثقين به، أو مع طبيبتك عبر محادثة "طبيبة"، أو مختصة نفسية، قد يكون خطوة مفيدة الآن.'
                : 'We noticed your mood has been low fairly often during this period. Niswah is here to support you, but talking to someone you trust, your doctor via the "طبيبة" chat, or a mental health professional could be a helpful next step.',
            style: pw.TextStyle(
              color: PdfColor.fromHex('#3730A3'),
              fontSize: 10,
              lineSpacing: 2,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  static String _narrative(bool isArabic, WellbeingInsights insights) {
    if (!insights.hasEnoughForCharts) {
      return isArabic
          ? 'ما زلنا نبني صورة واضحة عن حالتك النفسية — سجّلتِ حالتك ${insights.currentCount} ${insights.currentCount == 1 ? 'مرة' : 'مرات'} حتى الآن هذا الشهر. كل تسجيل يقرّبنا خطوة من فهم إيقاعك الخاص.'
          : 'We\'re still building a clear picture of how you\'ve been feeling — you\'ve checked in ${insights.currentCount} time${insights.currentCount == 1 ? '' : 's'} so far this month. Every check-in gets us a step closer to understanding your rhythm.';
    }

    final buffer = StringBuffer();
    switch (insights.trendDirection) {
      case MoodTrendDirection.improving:
        buffer.write(
          isArabic
              ? 'حالتك المزاجية هذا الشهر تميل إلى التحسن مقارنة ببداية الفترة.'
              : 'Your mood this month has been trending toward improvement compared to earlier in the period.',
        );
      case MoodTrendDirection.declining:
        buffer.write(
          isArabic
              ? 'لاحظنا ميلاً نحو الانخفاض في حالتك المزاجية هذا الشهر — هذا طبيعي وقد يستحق قليلاً من الاهتمام الإضافي بنفسك.'
              : 'We noticed a gentle downward trend in your mood this month — that\'s normal, and might be worth a little extra self-care.',
        );
      case MoodTrendDirection.fluctuating:
        buffer.write(
          isArabic
              ? 'لاحظنا أن حالتك المزاجية تقلبت أكثر من المعتاد هذا الشهر — وهذا طبيعي وقد يرتبط بعوامل كثيرة في حياتكِ.'
              : 'Your mood fluctuated more than usual this month — that\'s a normal part of life and can reflect many different factors.',
        );
      case MoodTrendDirection.stable:
        buffer.write(
          isArabic
              ? 'كانت حالتك المزاجية مستقرة إلى حد كبير هذا الشهر.'
              : 'Your mood has been fairly steady this month.',
        );
      case null:
        buffer.write(
          isArabic
              ? 'سجّلتِ حالتك ${insights.currentCount} مرة هذا الشهر — بداية جيدة لبناء صورة واضحة، وستزداد دقة التحليل كلما استمريتِ بالتسجيل.'
              : 'You\'ve checked in ${insights.currentCount} times this month — a good start, and insights will get more precise the more you log.',
        );
    }

    if (insights.canCompareToPreviousPeriod &&
        insights.averageMoodCurrent != null &&
        insights.averageMoodPrevious != null) {
      final delta =
          insights.averageMoodCurrent! - insights.averageMoodPrevious!;
      if (delta >= 0.3) {
        buffer.write(
          isArabic
              ? ' وهذا أعلى قليلاً مما كان عليه الشهر الماضي.'
              : ' That\'s a bit higher than last month.',
        );
      } else if (delta <= -0.3) {
        buffer.write(
          isArabic
              ? ' وهذا أقل قليلاً مما كان عليه الشهر الماضي — لا بأس، فالحالة المزاجية تتغير بشكل طبيعي.'
              : ' That\'s a bit lower than last month — that\'s alright, mood naturally shifts over time.',
        );
      } else {
        buffer.write(
          isArabic
              ? ' وهذا قريب مما كان عليه الشهر الماضي.'
              : ' That\'s about the same as last month.',
        );
      }
    }

    return buffer.toString();
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

  static pw.Widget _moodDonut(WellbeingInsights insights, bool isArabic) {
    final total = insights.currentCount;
    final entries = insights.moodDistribution.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return pw.Container(
      height: 190,
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Chart(
        grid: pw.PieGrid(),
        datasets: [
          for (final entry in entries)
            pw.PieDataSet(
              legend:
                  '${_moodLabel(entry.key, isArabic)} ${(entry.value * 100 / total).round()}%',
              value: entry.value.toDouble(),
              color: _moodShade(entry.key),
              innerRadius: 52,
              // Force outside placement regardless of slice size — the
              // auto "inside" placement for a large majority slice can
              // land its label behind the donut ring itself.
              legendPosition: pw.PieLegendPosition.outside,
              legendStyle: pw.TextStyle(
                fontSize: 8.5,
                color: PdfColor.fromHex(_textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _trendChart(WellbeingInsights insights) {
    final series = insights.trendSeries;
    if (series.length < 2) {
      return pw.SizedBox();
    }

    final start = series.first.date;
    final points = [
      for (final point in series)
        pw.PointChartValue(
          point.date.difference(start).inDays.toDouble(),
          point.mood.toDouble(),
        ),
    ];
    final maxDay = points.last.x.round();
    final ticks = {0, maxDay ~/ 2, maxDay}.toList()..sort();

    return pw.Container(
      height: 170,
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis<int>(
            ticks,
            format: (value) {
              final date = start.add(Duration(days: value.toInt()));
              return '${date.day}/${date.month}';
            },
            textStyle: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromHex(_textTertiary),
            ),
          ),
          yAxis: pw.FixedAxis<int>(
            const [1, 2, 3, 4, 5],
            divisions: true,
            divisionsColor: PdfColor.fromHex(_gridLine),
            textStyle: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromHex(_textTertiary),
            ),
          ),
        ),
        datasets: [
          pw.LineDataSet(
            data: points,
            isCurved: true,
            drawSurface: true,
            surfaceColor: PdfColor.fromHex(_lightTint),
            surfaceOpacity: 0.55,
            color: PdfColor.fromHex(_brandPrimary),
            lineColor: PdfColor.fromHex(_brandPrimary),
            pointColor: PdfColor.fromHex(_brandPrimary),
            pointSize: 2.5,
            lineWidth: 2,
          ),
        ],
      ),
    );
  }
}
