import '../../../../core/utils/calendar_day.dart';

enum PredictionGapResolution { longerCycle, missedRecords, unsure }

/// A forecasting-only user report. Never a bleeding observation or fiqh fact.
/// Exact endpoints bind it to one interval; edited/inserted starts invalidate
/// the match automatically. Unknown answers never confirm a biological cycle.
class PredictionHistoryReview {
  const PredictionHistoryReview({
    required this.start,
    required this.end,
    required this.resolution,
    required this.reportedAt,
  });

  final DateTime start;
  final DateTime end;
  final PredictionGapResolution resolution;
  final DateTime reportedAt;

  String get key => intervalKey(start, end);
  static String intervalKey(DateTime start, DateTime end) =>
      '${_date(start)}/${_date(end)}';
  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'start': _date(start),
    'end': _date(end),
    'resolution': resolution.name,
    'reportedAt': reportedAt.toUtc().toIso8601String(),
  };

  factory PredictionHistoryReview.fromJson(Map<String, dynamic> json) {
    DateTime date(Object? raw) {
      if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
        throw const FormatException('Invalid review date');
      }
      final parsed = DateTime.parse('${raw}T00:00:00Z');
      if (_date(parsed) != raw)
        throw const FormatException('Invalid review date');
      return parsed;
    }

    final start = date(json['start']);
    final end = date(json['end']);
    if (calendarDayDifference(end, start) <= 0) {
      throw const FormatException('Invalid review interval');
    }
    final reportedAt = DateTime.parse(json['reportedAt'] as String);
    if (!reportedAt.isUtc)
      throw const FormatException('Review timestamp must be UTC');
    return PredictionHistoryReview(
      start: start,
      end: end,
      resolution: PredictionGapResolution.values.byName(
        json['resolution'] as String,
      ),
      reportedAt: reportedAt,
    );
  }
}

class PredictionHistoryGap {
  const PredictionHistoryGap({
    required this.start,
    required this.end,
    this.resolution,
  });
  final DateTime start;
  final DateTime end;
  final PredictionGapResolution? resolution;
  int get days => calendarDayDifference(end, start);
  String get key => PredictionHistoryReview.intervalKey(start, end);
}
