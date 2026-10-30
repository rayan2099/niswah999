import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/services/wellbeing_trend.dart';
import '../wellbeing_trend_text.dart';

String _in(String en, String ar) => AppLocaleController.instance.text(en, ar);

enum _Measure { mood, energy, sleep }

extension on _Measure {
  String get label => switch (this) {
    _Measure.mood => _in('Mood', 'المزاج'),
    _Measure.energy => _in('Energy', 'الطاقة'),
    _Measure.sleep => _in('Sleep', 'النوم'),
  };

  Color get color => switch (this) {
    _Measure.mood => AppColors.brandPrimary,
    _Measure.energy => AppColors.nifas,
    _Measure.sleep => AppColors.istihadah,
  };

  double? of(WellbeingTrendBucket b) => switch (this) {
    _Measure.mood => b.mood,
    _Measure.energy => b.energy,
    _Measure.sleep => b.sleep,
  };
}

/// Weekly (monthly for 12 months) averages of one measure at a time, as a
/// smooth filled line on the 1–5 check-in scale. rayan found three lines
/// at once complicated (2026-10-30), so she picks mood, energy or sleep.
/// Only real check-ins are drawn: a week without any breaks the line,
/// never a guessed value. Time runs toward the reading
/// direction's end (mirrored in Arabic). Nothing animates. Screen readers
/// get the same numbers as text.
class WellbeingTrendChart extends StatefulWidget {
  const WellbeingTrendChart({super.key, required this.trend});

  final WellbeingTrend trend;

  @override
  State<WellbeingTrendChart> createState() => _WellbeingTrendChartState();
}

class _WellbeingTrendChartState extends State<WellbeingTrendChart> {
  _Measure _measure = _Measure.mood;

  WellbeingTrend get trend => widget.trend;
  bool get _weekly => trend.granularity == WellbeingTrendGranularity.week;

  static String _one(double value) => value.toStringAsFixed(1);

  /// "4 check-ins in 3 of 12 weeks": the sample behind the line.
  String get sampleLine => wellbeingTrendSampleLine(
    trend,
    arabic: AppLocaleController.instance.isArabic,
  );

  String get semanticSummary {
    final values = [
      for (final b in trend.buckets)
        if (_measure.of(b) != null) _measure.of(b)!,
    ];
    return [
      _weekly
          ? _in(
              '${_measure.label}, weekly averages from 1 to 5',
              '${_measure.label}، المتوسطات الأسبوعية من 1 إلى 5',
            )
          : _in(
              '${_measure.label}, monthly averages from 1 to 5',
              '${_measure.label}، المتوسطات الشهرية من 1 إلى 5',
            ),
      sampleLine,
      if (values.length == 1)
        _in('value ${_one(values.single)}', 'القيمة ${_one(values.single)}'),
      if (values.length > 1)
        _in(
          'first ${_one(values.first)}, latest ${_one(values.last)}',
          'أول قيمة ${_one(values.first)}، وآخر قيمة ${_one(values.last)}',
        ),
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _measure.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _Measure.values)
              ChoiceChip(
                key: Key('wellbeing-measure-${m.name}'),
                label: Text(m.label),
                selected: m == _measure,
                showCheckmark: false,
                onSelected: (_) => setState(() => _measure = m),
                selectedColor: m.color.withValues(alpha: 0.14),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: m == _measure ? m.color : const Color(0xFFEFE7EA),
                ),
                labelStyle: TextStyle(
                  color: m == _measure ? m.color : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          key: const Key('wellbeing-trend-chart'),
          container: true,
          label: semanticSummary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: CustomPaint(
                painter: _CurvePainter(
                  values: [for (final b in trend.buckets) _measure.of(b)],
                  color: color,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                  labelStyle: DefaultTextStyle.of(context).style
                      .copyWith(color: AppColors.textTertiary, fontSize: 10),
                  scaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Row(
            children: [
              Text(
                _in('Start', 'البداية'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                _in('Today', 'اليوم'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sampleLine,
          key: const Key('wellbeing-trend-sample'),
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

/// A smooth line with a soft fill under it. Each segment joins two
/// neighbouring weeks that both have check-ins; its control points share
/// the end points' heights, so the curve never rises above or dips below
/// a real average. A week without check-ins breaks the line.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.values,
    required this.color,
    required this.rtl,
    required this.labelStyle,
    required this.scaler,
  });

  final List<double?> values;
  final Color color;
  final bool rtl;
  final TextStyle labelStyle;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final labels = {
      for (final v in const [1, 3, 5])
        v: TextPainter(
          text: TextSpan(text: '$v', style: labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(),
    };
    final gutter =
        labels.values.map((t) => t.width).reduce((a, b) => a > b ? a : b) + 8;
    const top = 8.0;
    final bottom = size.height - 4;
    // Inset so the first and last points are not clipped or under a label.
    final start = rtl ? 8.0 : gutter + 8;
    final end = rtl ? size.width - gutter - 8 : size.width - 8;
    double y(double v) => bottom - (v - 1) / 4 * (bottom - top);
    double x(int i) {
      final f = n == 1 ? 0.5 : i / (n - 1);
      return rtl ? end - f * (end - start) : start + f * (end - start);
    }

    final grid = Paint()
      ..color = const Color(0xFFEFE7EA)
      ..strokeWidth = 1;
    for (final v in const [1, 3, 5]) {
      final gy = y(v.toDouble());
      for (var gx = start; gx < end; gx += 6) {
        canvas.drawLine(Offset(gx, gy), Offset(gx + 3, gy), grid);
      }
      final t = labels[v]!;
      t.paint(
        canvas,
        Offset(rtl ? size.width - t.width : 0, gy - t.height / 2),
      );
    }

    // Runs of consecutive weeks with data.
    final runs = <List<int>>[];
    for (var i = 0; i < n; i++) {
      if (values[i] == null) continue;
      if (runs.isEmpty || runs.last.last != i - 1) {
        runs.add([i]);
      } else {
        runs.last.add(i);
      }
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final run in runs) {
      if (run.length > 1) {
        final path = Path()..moveTo(x(run.first), y(values[run.first]!));
        for (var k = 1; k < run.length; k++) {
          final a = Offset(x(run[k - 1]), y(values[run[k - 1]]!));
          final b = Offset(x(run[k]), y(values[run[k]]!));
          final mid = (a.dx + b.dx) / 2;
          path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
        }
        final fill = Path.from(path)
          ..lineTo(x(run.last), bottom)
          ..lineTo(x(run.first), bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.02),
              ],
            ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
        );
        canvas.drawPath(path, line);
      }
      for (final i in run) {
        final c = Offset(x(i), y(values[i]!));
        canvas
          ..drawCircle(c, 6, Paint()..color = color.withValues(alpha: 0.18))
          ..drawCircle(c, 3.5, Paint()..color = color)
          ..drawCircle(
            c,
            3.5,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.color != color ||
      old.rtl != rtl ||
      old.scaler != scaler ||
      !listEquals(old.values, values);
}
