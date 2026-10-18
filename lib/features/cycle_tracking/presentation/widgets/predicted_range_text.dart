import '../../domain/entities/cycle_log.dart';

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

String _day(DateTime date, bool isArabic) =>
    '${date.day} ${(isArabic ? _monthsAr : _monthsEn)[date.month - 1]}';

/// "27 Oct – 1 Nov", or a single day when the range is one day.
String formatPredictedRange(
  PredictedDateRange range, {
  required bool isArabic,
}) {
  if (range.earliest == range.latest) return _day(range.earliest, isArabic);
  return '${_day(range.earliest, isArabic)} – ${_day(range.latest, isArabic)}';
}

/// Says when a prediction rests on her own stated estimate (charter F6:
/// "Based on the estimate you gave us", never "your average"). Null for a
/// prediction from logged cycles alone.
String? predictionBasisNote(PredictionBasis? basis, {required bool isArabic}) =>
    switch (basis) {
      PredictionBasis.statedEstimate =>
        isArabic
            ? 'بناءً على التقدير الذي ذكرتِه لنا'
            : 'Based on the estimate you gave us',
      PredictionBasis.historyAndEstimate =>
        isArabic
            ? 'بناءً على دوراتكِ المسجلة والتقدير الذي ذكرتِه لنا'
            : 'Based on your logged cycles and the estimate you gave us',
      PredictionBasis.history || null => null,
    };
