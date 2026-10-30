import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/services/wellbeing_trend.dart';

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

/// Weekly (monthly for 12 months) averages of one measure at a time, as
/// plain bars on the 1–5 check-in scale. rayan found the three-line chart
/// complicated (2026-10-30), so she picks mood, energy or sleep and sees
/// one bar per week. Only real check-ins are drawn: a week without any is
/// a short grey stub, never a guessed value. Time runs toward the reading
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

  /// Arabic counted noun: 1, 2, 3–10 and 11+ forms.
  static String _arCount(int n, (String, String, String, String) forms) {
    final (one, two, few, many) = forms;
    if (n == 1) return '1 $one';
    if (n == 2) return '2 $two';
    return n <= 10 ? '$n $few' : '$n $many';
  }

  String _units(int n) => _weekly
      ? _in(
          n == 1 ? '$n week' : '$n weeks',
          _arCount(n, ('أسبوع', 'أسبوعين', 'أسابيع', 'أسبوعًا')),
        )
      : _in(
          n == 1 ? '$n month' : '$n months',
          _arCount(n, ('شهر', 'شهرين', 'أشهر', 'شهرًا')),
        );

  /// "4 check-ins in 3 of 12 weeks": the sample behind the bars.
  String get sampleLine {
    final total = trend.buckets.length;
    final withData = trend.bucketsWithData;
    final checkIns = trend.checkIns;
    return _in(
      '${checkIns == 1 ? '1 check-in' : '$checkIns check-ins'} in $withData of ${_units(total)}',
      '${checkIns == 1
          ? 'تسجيل واحد'
          : checkIns == 2
          ? 'تسجيلان'
          : checkIns <= 10
          ? '$checkIns تسجيلات'
          : '$checkIns تسجيلًا'} في $withData من ${_units(total)}',
    );
  }

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
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in trend.buckets)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _Bar(value: _measure.of(b), color: color),
                      ),
                    ),
                ],
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

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final v = value;
      if (v == null) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFEFE7EA),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: constraints.maxHeight * (v / 5).clamp(0.05, 1.0),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
      );
    },
  );
}
