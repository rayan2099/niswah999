import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/services/wellbeing_trend.dart';

String _in(String en, String ar) => AppLocaleController.instance.text(en, ar);

enum _Marker { circle, square, triangle }

class _Series {
  const _Series(
    this.en,
    this.ar,
    this.color,
    this.dash,
    this.marker,
    this.pick,
  );
  final String en;
  final String ar;
  final Color color;

  /// Line pattern, so the three lines differ by more than color.
  final List<double>? dash;
  final _Marker marker;
  final double? Function(WellbeingTrendBucket) pick;

  String get label => _in(en, ar);
}

final _series = [
  _Series(
    'Mood',
    'المزاج',
    AppColors.brandPrimary,
    null,
    _Marker.circle,
    (b) => b.mood,
  ),
  _Series(
    'Energy',
    'الطاقة',
    AppColors.nifas,
    const [6, 4],
    _Marker.square,
    (b) => b.energy,
  ),
  _Series(
    'Sleep',
    'النوم',
    AppColors.istihadah,
    const [2, 3],
    _Marker.triangle,
    (b) => b.sleep,
  ),
];

/// Line chart of weekly (or monthly) mood, energy and sleep averages on the
/// 1–5 check-in scale. Only buckets with real check-ins are plotted; empty
/// ones are gaps. Time runs toward the reading direction's end (mirrored
/// in Arabic). Static: nothing animates, so reduced motion needs no case.
/// Screen readers get one text summary of the same numbers.
class WellbeingTrendChart extends StatelessWidget {
  const WellbeingTrendChart({super.key, required this.trend});

  final WellbeingTrend trend;

  static String _one(double value) => value.toStringAsFixed(1);

  String _unitPlural(int n) =>
      trend.granularity == WellbeingTrendGranularity.week
      ? _in(n == 1 ? 'week' : 'weeks', n == 1 ? 'أسبوع' : 'أسابيع')
      : _in(n == 1 ? 'month' : 'months', n == 1 ? 'شهر' : 'أشهر');

  /// "12 check-ins in 5 of 13 weeks": the sample behind the lines.
  String get sampleLine {
    final total = trend.buckets.length;
    final withData = trend.bucketsWithData;
    return _in(
      '${trend.checkIns} check-ins in $withData of $total ${_unitPlural(total)}',
      // Phrased to avoid Arabic number agreement with the counted noun.
      'التسجيلات: ${trend.checkIns} · '
          '${trend.granularity == WellbeingTrendGranularity.week ? 'أسابيع' : 'أشهر'} فيها تسجيل: $withData من $total',
    );
  }

  String get semanticSummary {
    final withData = trend.buckets.where((b) => b.hasData).toList();
    final parts = <String>[
      trend.granularity == WellbeingTrendGranularity.week
          ? _in(
              'Chart of weekly averages, 1 to 5',
              'رسم بياني للمتوسطات الأسبوعية من 1 إلى 5',
            )
          : _in(
              'Chart of monthly averages, 1 to 5',
              'رسم بياني للمتوسطات الشهرية من 1 إلى 5',
            ),
      sampleLine,
    ];
    if (withData.isNotEmpty) {
      for (final s in _series) {
        final first = s.pick(withData.first)!;
        final latest = s.pick(withData.last)!;
        parts.add(
          withData.length == 1
              ? '${s.label} ${_one(latest)}'
              : _in(
                  '${s.label}: first ${_one(first)}, latest ${_one(latest)}',
                  '${s.label}: أول قيمة ${_one(first)}، وآخر قيمة ${_one(latest)}',
                ),
        );
      }
    }
    return parts.join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [for (final s in _series) _LegendItem(series: s)],
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          key: const Key('wellbeing-trend-chart'),
          container: true,
          label: semanticSummary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 150 + scaler.scale(12) * 2,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendPainter(
                  trend: trend,
                  rtl: rtl,
                  scaler: scaler,
                  labelStyle: DefaultTextStyle.of(context).style
                      .copyWith(color: AppColors.textTertiary, fontSize: 10),
                  startLabel: _in('Start', 'البداية'),
                  endLabel: _in('Today', 'اليوم'),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sampleLine,
          key: const Key('wellbeing-trend-sample'),
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
        if (trend.bucketsWithData == 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _in(
                'Check-ins from at least two different ${_unitPlural(2)} are needed to draw a line.',
                trend.granularity == WellbeingTrendGranularity.week
                    ? 'يلزم تسجيلات من أسبوعين مختلفين على الأقل لرسم خط.'
                    : 'يلزم تسجيلات من شهرين مختلفين على الأقل لرسم خط.',
              ),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.series});
  final _Series series;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 26,
        height: 12,
        child: CustomPaint(painter: _LegendPainter(series)),
      ),
      const SizedBox(width: 5),
      Text(
        series.label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

void _strokeLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint,
  List<double>? dash,
) {
  if (dash == null) {
    canvas.drawLine(a, b, paint);
    return;
  }
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy);
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var on = 0;
    while (distance < metric.length) {
      final length = dash[on % dash.length];
      if (on.isEven) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + length, metric.length),
          ),
          paint,
        );
      }
      distance += length;
      on++;
    }
  }
}

void _drawMarker(Canvas canvas, Offset c, _Marker marker, Color color) {
  final fill = Paint()..color = color;
  final ring = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  switch (marker) {
    case _Marker.circle:
      canvas
        ..drawCircle(c, 4, fill)
        ..drawCircle(c, 4, ring);
    case _Marker.square:
      final r = Rect.fromCenter(center: c, width: 7.5, height: 7.5);
      canvas
        ..drawRect(r, fill)
        ..drawRect(r, ring);
    case _Marker.triangle:
      final p = Path()
        ..moveTo(c.dx, c.dy - 5)
        ..lineTo(c.dx + 4.5, c.dy + 3.5)
        ..lineTo(c.dx - 4.5, c.dy + 3.5)
        ..close();
      canvas
        ..drawPath(p, fill)
        ..drawPath(p, ring);
  }
}

class _LegendPainter extends CustomPainter {
  _LegendPainter(this.series);
  final _Series series;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = series.color
      ..strokeWidth = 2;
    _strokeLine(
      canvas,
      Offset(0, y),
      Offset(size.width, y),
      paint,
      series.dash,
    );
    _drawMarker(canvas, Offset(size.width / 2, y), series.marker, series.color);
  }

  @override
  bool shouldRepaint(covariant _LegendPainter old) => old.series != series;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.trend,
    required this.rtl,
    required this.scaler,
    required this.labelStyle,
    required this.startLabel,
    required this.endLabel,
  });

  final WellbeingTrend trend;
  final bool rtl;
  final TextScaler scaler;
  final TextStyle labelStyle;
  final String startLabel;
  final String endLabel;

  TextPainter _text(String value) => TextPainter(
    text: TextSpan(text: value, style: labelStyle),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textScaler: scaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final yLabels = {
      for (final v in const [1, 3, 5]) v: _text('$v'),
    };
    final gutter = yLabels.values.map((t) => t.width).reduce(math.max) + 8;
    final xLabelHeight = _text(endLabel).height + 6;
    const top = 6.0;
    final bottom = size.height - xLabelHeight;
    final plotStart = rtl ? 0.0 : gutter;
    final plotEnd = rtl ? size.width - gutter : size.width;
    final plotWidth = plotEnd - plotStart;
    final n = trend.buckets.length;
    if (n == 0 || plotWidth <= 0) return;

    double yFor(double v) => bottom - (v - 1) / 4 * (bottom - top);
    // Oldest bucket at the reading direction's start.
    double xFor(int i) {
      final fraction = (i + 0.5) / n;
      return rtl
          ? plotEnd - fraction * plotWidth
          : plotStart + fraction * plotWidth;
    }

    final grid = Paint()
      ..color = const Color(0xFFF1E9EC)
      ..strokeWidth = 1;
    for (var v = 1; v <= 5; v++) {
      canvas.drawLine(
        Offset(plotStart, yFor(v.toDouble())),
        Offset(plotEnd, yFor(v.toDouble())),
        grid,
      );
    }
    yLabels.forEach((v, painter) {
      final x = rtl ? size.width - painter.width : gutter - 8 - painter.width;
      painter.paint(canvas, Offset(x, yFor(v.toDouble()) - painter.height / 2));
    });

    final start = _text(startLabel);
    final end = _text(endLabel);
    final labelY = bottom + 6;
    if (rtl) {
      start.paint(canvas, Offset(plotEnd - start.width, labelY));
      end.paint(canvas, Offset(plotStart, labelY));
    } else {
      start.paint(canvas, Offset(plotStart, labelY));
      end.paint(canvas, Offset(plotEnd - end.width, labelY));
    }

    for (final s in _series) {
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < n; i++) {
        final a = s.pick(trend.buckets[i - 1]);
        final b = s.pick(trend.buckets[i]);
        // Gap where a bucket has no check-ins: never bridged by a guess.
        if (a == null || b == null) continue;
        _strokeLine(
          canvas,
          Offset(xFor(i - 1), yFor(a)),
          Offset(xFor(i), yFor(b)),
          line,
          s.dash,
        );
      }
      for (var i = 0; i < n; i++) {
        final v = s.pick(trend.buckets[i]);
        if (v != null) {
          _drawMarker(canvas, Offset(xFor(i), yFor(v)), s.marker, s.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.trend != trend || old.rtl != rtl || old.scaler != scaler;
}
