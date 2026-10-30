import 'dart:typed_data';

import '../../domain/services/wellbeing_period_split.dart';
import '../../domain/services/wellbeing_trend.dart';
import '../wellbeing_trend_text.dart';

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
    WellbeingPeriodSplit? periodSplit,
    WellbeingTrend? trend,
    int trendMonths = 3,
    bool hijri = false,
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
        build: (context) => _body(
          isArabic,
          insights,
          notes,
          semiBold,
          periodSplit,
          trend,
          trendMonths,
          hijri,
        ),
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

  /// Device run 2026-10-28: mood is tracked on every day, with or without a
  /// period. Testing feedback 2026-10-30: the report shows the same three
  /// views as Insights (all days, period days, other days) as a table of
  /// mood, energy and sleep averages with their check-in counts.
  ///
  /// Rows of cells, first row the header; `—` where a group has no
  /// check-ins. Exposed for tests.
  static List<List<String>> periodSplitRows(
    bool isArabic,
    WellbeingPeriodSplit split,
  ) {
    String avg(double? value) =>
        value == null ? '—' : '${value.toStringAsFixed(1)}/5';
    final groups = [split.all, split.onPeriodDays, split.onOtherDays];
    return [
      [
        '',
        isArabic ? 'كل الأيام' : 'All days',
        isArabic ? 'أيام الدورة' : 'Period days',
        isArabic ? 'بقية الأيام' : 'Other days',
      ],
      [
        isArabic ? 'المزاج' : 'Mood',
        for (final g in groups) avg(g.averageMood),
      ],
      [
        isArabic ? 'الطاقة' : 'Energy',
        for (final g in groups) avg(g.averageEnergy),
      ],
      [
        isArabic ? 'النوم' : 'Sleep',
        for (final g in groups) avg(g.averageSleep),
      ],
      [
        isArabic ? 'التسجيلات' : 'Check-ins',
        for (final g in groups) '${g.count}',
      ],
    ];
  }

  static pw.Widget _periodSplitTable(
    bool isArabic,
    WellbeingPeriodSplit split,
    pw.Font semiBold,
  ) {
    final rows = periodSplitRows(isArabic, split);
    pw.Widget cell(String text, {bool head = false, bool first = false}) =>
        pw.Expanded(
          flex: first ? 5 : 4,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(
              text,
              textAlign: first ? pw.TextAlign.start : pw.TextAlign.center,
              style: pw.TextStyle(
                font: head || first ? semiBold : null,
                color: PdfColor.fromHex(
                  head
                      ? _textSecondary
                      : (first ? _textPrimary : _brandPrimary),
                ),
                fontSize: head ? 9 : 10,
              ),
            ),
          ),
        );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          isArabic
              ? 'الحالة النفسية في أيام الدورة وبقية الأيام'
              : 'Mood on period days and other days',
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_textPrimary),
            fontSize: 11,
          ),
        ),
        pw.SizedBox(height: 6),
        for (var r = 0; r < rows.length; r++)
          pw.Container(
            decoration: r == 0
                ? null
                : pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(
                        color: PdfColor.fromHex(_gridLine),
                        width: 0.8,
                      ),
                    ),
                  ),
            child: pw.Row(
              children: [
                for (var c = 0; c < rows[r].length; c++)
                  cell(rows[r][c], head: r == 0, first: c == 0),
              ],
            ),
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          isArabic
              ? 'المتوسطات من 1 إلى 5. تُسجَّل الحالة النفسية في كل الأيام، وأيام الدورة هي الأيام المسجّل فيها نزول دم، وليست حكمًا شرعيًا.'
              : 'Averages on a 1–5 scale. Mood is tracked on every day; period days are days with bleeding recorded, not a religious ruling.',
          style: pw.TextStyle(
            color: PdfColor.fromHex(_textTertiary),
            fontSize: 8,
            lineSpacing: 2,
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _body(
    bool isArabic,
    WellbeingInsights insights,
    List<NotedEntry> notes,
    pw.Font semiBold,
    WellbeingPeriodSplit? periodSplit,
    WellbeingTrend? trend,
    int trendMonths,
    bool hijri,
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
      // The table, then the weekly line right under it (rayan,
      // 2026-10-30). Each stays whole on a page, so the chart is never cut
      // from its legend.
      if (periodSplit != null && periodSplit.all.count > 0)
        pw.Inseparable(
          child: _card(
            child: _periodSplitTable(isArabic, periodSplit, semiBold),
          ),
        ),
      if (trend != null && trend.checkIns > 0)
        pw.Inseparable(
          child: _card(
            child: _weeklyTrends(isArabic, trend, trendMonths, hijri, semiBold),
          ),
        ),
    ];

    if (notes.isNotEmpty) {
      widgets
        ..add(
          _sectionLabel(isArabic ? 'ملاحظات مسجّلة' : 'Logged notes', semiBold),
        )
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

  /// The Insights card's weekly lines for mood, energy and sleep on one
  /// chart with a legend, since paper cannot switch between them (rayan,
  /// 2026-10-30). Same rules as the app: only real weekly averages, a week
  /// without check-ins breaks the line, and the curve never goes above or
  /// below a real average. Each line also has its own marker shape, so the
  /// chart reads without color.
  static pw.Widget _weeklyTrends(
    bool isArabic,
    WellbeingTrend trend,
    int months,
    bool hijri,
    pw.Font semiBold,
  ) {
    final weekly = trend.granularity == WellbeingTrendGranularity.week;
    final period = isArabic
        ? (months == 1
              ? 'آخر شهر'
              : months <= 10
              ? 'آخر $months أشهر'
              : 'آخر $months شهرًا')
        : (months == 1 ? 'last month' : 'last $months months');
    final title = isArabic
        ? '${weekly ? 'المتوسطات الأسبوعية' : 'المتوسطات الشهرية'} · $period'
        : '${weekly ? 'Weekly averages' : 'Monthly averages'} · $period';
    final small = pw.TextStyle(
      color: PdfColor.fromHex(_textTertiary),
      fontSize: 7.5,
    );
    final monthLabels = wellbeingMonthLabels(
      trend,
      arabic: isArabic,
      hijri: hijri,
    );
    final series = [
      _TrendSeries(isArabic ? 'المزاج' : 'Mood', _moodLine, _Marker.circle, [
        for (final b in trend.buckets) b.mood,
      ]),
      _TrendSeries(
        isArabic ? 'الطاقة' : 'Energy',
        _energyLine,
        _Marker.square,
        [for (final b in trend.buckets) b.energy],
      ),
      _TrendSeries(isArabic ? 'النوم' : 'Sleep', _sleepLine, _Marker.triangle, [
        for (final b in trend.buckets) b.sleep,
      ]),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: semiBold,
            color: PdfColor.fromHex(_textPrimary),
            fontSize: 11,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            for (final s in series) ...[
              pw.CustomPaint(
                size: const PdfPoint(16, 8),
                painter: (canvas, size) {
                  final color = PdfColor.fromHex(s.hex);
                  canvas
                    ..setStrokeColor(color)
                    ..setLineWidth(1.4)
                    ..moveTo(0, size.y / 2)
                    ..lineTo(size.x, size.y / 2)
                    ..strokePath();
                  _drawMarker(canvas, s.marker, size.x / 2, size.y / 2, color);
                },
              ),
              pw.SizedBox(width: 4),
              pw.Text(
                s.label,
                style: pw.TextStyle(
                  font: semiBold,
                  color: PdfColor.fromHex(s.hex),
                  fontSize: 9,
                ),
              ),
              pw.SizedBox(width: 14),
            ],
          ],
        ),
        pw.SizedBox(height: 6),
        // Scale labels sit at the start side, as in the app (right in
        // Arabic); time runs toward the reading direction's end.
        pw.Row(
          children: [
            pw.SizedBox(
              width: 12,
              height: _trendHeight,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  for (final v in const [5, 3, 1]) pw.Text('$v', style: small),
                ],
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Expanded(
              child: pw.CustomPaint(
                size: const PdfPoint(double.infinity, _trendHeight),
                painter: (canvas, size) =>
                    _paintCurves(canvas, size, series, isArabic),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        // Month names under the weeks they cover; time runs toward the
        // reading direction's end (right to left in Arabic).
        pw.Row(
          children: [
            pw.SizedBox(width: 16),
            for (final (label, count) in monthLabels)
              pw.Expanded(
                flex: count,
                child: pw.Text(
                  label,
                  textAlign: pw.TextAlign.center,
                  style: small,
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          isArabic
              ? '${wellbeingTrendSampleLine(trend, arabic: true)}. متوسطات من 1 إلى 5. الخط المنقّط يصل بين أسابيع تفصلها أسابيع بلا تسجيلات.'
              : '${wellbeingTrendSampleLine(trend, arabic: false)}. Averages from 1 to 5. A dotted line joins weeks that have weeks without check-ins between them.',
          style: small,
        ),
      ],
    );
  }

  static const _trendHeight = 80.0;
  static const _moodLine = _brandPrimary;
  static const _energyLine = '#D97706';
  static const _sleepLine = '#4F46E5';

  static void _drawMarker(
    PdfGraphics canvas,
    _Marker marker,
    double cx,
    double cy,
    PdfColor color,
  ) {
    canvas.setFillColor(color);
    switch (marker) {
      case _Marker.circle:
        canvas.drawEllipse(cx, cy, 2.4, 2.4);
      case _Marker.square:
        canvas.drawRect(cx - 2.2, cy - 2.2, 4.4, 4.4);
      case _Marker.triangle:
        canvas
          ..moveTo(cx, cy + 2.8)
          ..lineTo(cx + 2.8, cy - 2.2)
          ..lineTo(cx - 2.8, cy - 2.2)
          ..closePath();
    }
    canvas.fillPath();
  }

  /// PDF coordinates start at the bottom left.
  static void _paintCurves(
    PdfGraphics canvas,
    PdfPoint size,
    List<_TrendSeries> series,
    bool rtl,
  ) {
    final n = series.first.values.length;
    if (n == 0) return;
    const inset = 5.0;
    final top = size.y - inset;
    const bottom = inset;
    double y(double v) => bottom + (v - 1) / 4 * (top - bottom);
    // Each week sits at the centre of its slot, so the month labels below
    // line up with the weeks they cover.
    double x(int i) {
      final ltr = (i + 0.5) / n * size.x;
      return rtl ? size.x - ltr : ltr;
    }

    canvas
      ..setStrokeColor(PdfColor.fromHex('#EFE7EA'))
      ..setLineWidth(0.6)
      ..setLineDashPattern(const [2, 2]);
    for (final v in const [1, 2, 3, 4, 5]) {
      canvas
        ..moveTo(0, y(v.toDouble()))
        ..lineTo(size.x, y(v.toDouble()))
        ..strokePath();
    }
    canvas.setLineDashPattern();

    for (final s in series) {
      final values = s.values;
      final color = PdfColor.fromHex(s.hex);
      final runs = <List<int>>[];
      for (var i = 0; i < n; i++) {
        if (values[i] == null) continue;
        if (runs.isEmpty || runs.last.last != i - 1) {
          runs.add([i]);
        } else {
          runs.last.add(i);
        }
      }

      void curve(List<int> run) {
        canvas.moveTo(x(run.first), y(values[run.first]!));
        for (var k = 1; k < run.length; k++) {
          final ax = x(run[k - 1]), ay = y(values[run[k - 1]]!);
          final bx = x(run[k]), by = y(values[run[k]]!);
          final mid = (ax + bx) / 2;
          canvas.curveTo(mid, ay, mid, by, bx, by);
        }
      }

      // Weeks without check-ins between two real averages: a thin dotted
      // line joins them so the chart reads as one line, with no point or
      // fill where nothing was recorded.
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(1)
        ..setLineDashPattern(const [1.5, 2.5]);
      for (var r = 1; r < runs.length; r++) {
        final from = runs[r - 1].last, to = runs[r].first;
        canvas
          ..moveTo(x(from), y(values[from]!))
          ..lineTo(x(to), y(values[to]!))
          ..strokePath();
      }
      canvas.setLineDashPattern();

      for (final run in runs) {
        if (run.length > 1) {
          canvas
            ..saveContext()
            ..setGraphicState(PdfGraphicState(opacity: 0.10))
            ..setFillColor(color);
          curve(run);
          canvas
            ..lineTo(x(run.last), bottom)
            ..lineTo(x(run.first), bottom)
            ..closePath()
            ..fillPath()
            ..restoreContext();
          canvas
            ..setStrokeColor(color)
            ..setLineWidth(1.6)
            ..setLineCap(PdfLineCap.round);
          curve(run);
          canvas.strokePath();
        }
        for (final i in run) {
          _drawMarker(canvas, s.marker, x(i), y(values[i]!), color);
        }
      }
    }
  }

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

enum _Marker { circle, square, triangle }

class _TrendSeries {
  const _TrendSeries(this.label, this.hex, this.marker, this.values);

  final String label;
  final String hex;
  final _Marker marker;
  final List<double?> values;
}
