import '../domain/services/wellbeing_trend.dart';

/// Arabic counted noun: 1, 2, 3–10 and 11+ forms.
String _arCount(int n, (String, String, String, String) forms) {
  final (one, two, few, many) = forms;
  if (n == 1) return '1 $one';
  if (n == 2) return '2 $two';
  return n <= 10 ? '$n $few' : '$n $many';
}

String _units(WellbeingTrend trend, int n, bool arabic) {
  final weekly = trend.granularity == WellbeingTrendGranularity.week;
  if (arabic) {
    return weekly
        ? _arCount(n, ('أسبوع', 'أسبوعين', 'أسابيع', 'أسبوعًا'))
        : _arCount(n, ('شهر', 'شهرين', 'أشهر', 'شهرًا'));
  }
  final unit = weekly ? 'week' : 'month';
  return n == 1 ? '$n $unit' : '$n ${unit}s';
}

/// "4 check-ins in 3 of 12 weeks": the sample behind a trend line. Shared
/// by the Insights chart and the PDF report so both say the same thing.
String wellbeingTrendSampleLine(WellbeingTrend trend, {required bool arabic}) {
  final total = trend.buckets.length;
  final withData = trend.bucketsWithData;
  final checkIns = trend.checkIns;
  if (!arabic) {
    return '${checkIns == 1 ? '1 check-in' : '$checkIns check-ins'} in $withData of ${_units(trend, total, false)}';
  }
  final count = checkIns == 1
      ? 'تسجيل واحد'
      : checkIns == 2
      ? 'تسجيلان'
      : checkIns <= 10
      ? '$checkIns تسجيلات'
      : '$checkIns تسجيلًا';
  return '$count في $withData من ${_units(trend, total, true)}';
}

const _monthsAr = [
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
const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Month label under a trend chart.
String wellbeingMonthLabel(DateTime month, {required bool arabic}) =>
    (arabic ? _monthsAr : _monthsEn)[month.month - 1];

/// Whether the month span at [index] gets a label: every month up to six,
/// every other month beyond that so labels never crowd.
bool wellbeingMonthLabelShown(int index, int spans) =>
    spans <= 6 || index.isEven;
