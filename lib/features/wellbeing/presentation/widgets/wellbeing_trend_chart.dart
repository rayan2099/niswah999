import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/calendar_system_controller.dart';
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

/// One glassy bar per month with its average written on it, for one
/// measure at a time (mood, energy or sleep). rayan found the weekly line
/// hard to read (2026-10-30). Only real check-ins count: a month without
/// any shows "—" and no bar, never a guessed value. Month names follow the
/// calendar screen's Gregorian / Hijri choice, and time runs toward the
/// reading direction's end (mirrored in Arabic). Nothing animates. Screen
/// readers get the same numbers as text.
class WellbeingTrendChart extends StatefulWidget {
  const WellbeingTrendChart({super.key, required this.trend});

  /// Monthly buckets (see [WellbeingTrend.computeByMonth]).
  final WellbeingTrend trend;

  @override
  State<WellbeingTrendChart> createState() => _WellbeingTrendChartState();
}

class _WellbeingTrendChartState extends State<WellbeingTrendChart> {
  _Measure _measure = _Measure.mood;

  WellbeingTrend get trend => widget.trend;
  bool get _arabic => AppLocaleController.instance.isArabic;
  bool get _hijri => CalendarSystemController.instance.hijri;

  static String _one(double value) => value.toStringAsFixed(1);

  String _month(WellbeingTrendBucket b) =>
      wellbeingMonthName(b.start, arabic: _arabic, hijri: _hijri);

  /// "6 check-ins in 2 of 3 months": the sample behind the bars.
  String get sampleLine => wellbeingTrendSampleLine(trend, arabic: _arabic);

  String get semanticSummary => [
    _in(
      '${_measure.label}, monthly averages from 1 to 5',
      '${_measure.label}، المتوسطات الشهرية من 1 إلى 5',
    ),
    sampleLine,
    [
      for (final b in trend.buckets)
        _measure.of(b) == null
            ? _in('${_month(b)} no check-ins', '${_month(b)} بلا تسجيلات')
            : '${_month(b)} ${_one(_measure.of(b)!)}',
    ].join(_in(', ', '، ')),
  ].join('. ');

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
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
        const SizedBox(height: 16),
        Semantics(
          key: const Key('wellbeing-trend-chart'),
          container: true,
          label: semanticSummary,
          child: ExcludeSemantics(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in trend.buckets)
                    Expanded(
                      child: _MonthBar(
                        value: _measure.of(b),
                        color: _measure.color,
                        month: _month(b),
                        compact: trend.buckets.length > 6,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          sampleLine,
          key: const Key('wellbeing-trend-sample'),
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

/// A frosted-glass bar: a translucent tint of the measure's color, a light
/// edge and a soft glow, with the average written above it.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.value,
    required this.color,
    required this.month,
    required this.compact,
  });

  final double? value;
  final Color color;
  final String month;

  /// More than six months: thinner bars and smaller numbers.
  final bool compact;

  static const _maxHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v == null ? '—' : v.toStringAsFixed(1),
              style: TextStyle(
                color: v == null ? AppColors.textTertiary : color,
                fontSize: compact ? 10 : 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (v == null)
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFF3EEF0),
                borderRadius: BorderRadius.circular(99),
              ),
            )
          else
            Container(
              // Heights are drawn from zero so a 1 still shows as a bar.
              height: _maxHeight * v / 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(compact ? 8 : 14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.42),
                    color.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Align(
                alignment: Alignment.topCenter,
                // The glass highlight along the top edge.
                child: Container(
                  height: 10,
                  margin: const EdgeInsets.fromLTRB(5, 4, 5, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.75),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              month,
              maxLines: 1,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
