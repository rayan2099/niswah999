import '../../cycle_tracking/presentation/widgets/cycle_calendar.dart'
    show hijriDateParts;
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
const _hijriMonthsAr = [
  'محرم',
  'صفر',
  'ربيع الأول',
  'ربيع الآخر',
  'جمادى الأولى',
  'جمادى الآخرة',
  'رجب',
  'شعبان',
  'رمضان',
  'شوال',
  'ذو القعدة',
  'ذو الحجة',
];
const _hijriMonthsEn = [
  'Muharram',
  'Safar',
  'Rabi I',
  'Rabi II',
  'Jumada I',
  'Jumada II',
  'Rajab',
  'Sha’ban',
  'Ramadan',
  'Shawwal',
  'Dhu al-Qidah',
  'Dhu al-Hijjah',
];

/// A value shared by every day of one month, Gregorian or Hijri.
int Function(DateTime day) wellbeingMonthKey({required bool hijri}) => hijri
    ? (day) {
        final (_, month, year) = hijriDateParts(day);
        return year * 12 + month;
      }
    : (day) => day.year * 12 + day.month;

/// The name of the month [day] falls in, Gregorian or Hijri.
String wellbeingMonthName(
  DateTime day, {
  required bool arabic,
  required bool hijri,
}) => hijri
    ? (arabic ? _hijriMonthsAr : _hijriMonthsEn)[hijriDateParts(day).$2 - 1]
    : (arabic ? _monthsAr : _monthsEn)[day.month - 1];
