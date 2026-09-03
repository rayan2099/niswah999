import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/entities/cycle_log.dart';

class CycleCalendar extends StatelessWidget {
  const CycleCalendar({
    super.key,
    required this.logs,
    required this.month,
    required this.summary,
    required this.onDateSelected,
    required this.showHijri,
    required this.onCalendarModeChanged,
    this.showFertileWindow = false,
  });

  final List<CycleLog> logs;
  final DateTime month;
  final CycleTrackingSummary summary;
  final ValueChanged<DateTime> onDateSelected;
  final bool showHijri;
  final ValueChanged<bool> onCalendarModeChanged;
  final bool showFertileWindow;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(month.year, month.month);
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday % 7),
    );
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final dayCount = (((monthStart.weekday % 7) + daysInMonth) / 7).ceil() * 7;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.shadowColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CalendarModeButton(
                  label: AppLocaleController.instance.text(
                    'Gregorian',
                    'ميلادي',
                  ),
                  selected: !showHijri,
                  onTap: () => onCalendarModeChanged(false),
                ),
                _CalendarModeButton(
                  label: AppLocaleController.instance.text('Hijri', 'هجري'),
                  selected: showHijri,
                  onTap: () => onCalendarModeChanged(true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            itemCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (AppLocaleController.instance.isArabic
                        ? const [
                            'الأحد',
                            'الاثنين',
                            'الثلاثاء',
                            'الأربعاء',
                            'الخميس',
                            'الجمعة',
                            'السبت',
                          ]
                        : const [
                            'SUN',
                            'MON',
                            'TUE',
                            'WED',
                            'THU',
                            'FRI',
                            'SAT',
                          ])[index],
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 8,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          GridView.builder(
            itemCount: dayCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.82,
              mainAxisSpacing: 7,
              crossAxisSpacing: 3,
            ),
            itemBuilder: (context, index) {
              final date = gridStart.add(Duration(days: index));
              final log = logs
                  .where((entry) => DateUtils.isSameDay(entry.date, date))
                  .firstOrNull;
              return _CalendarDay(
                date: date,
                marker: _markerFor(date, log),
                inMonth: date.month == month.month,
                isToday: DateUtils.isSameDay(date, AppClock.now()),
                showHijri: showHijri,
                onTap: () => onDateSelected(date),
              );
            },
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const _CalendarLegend(
                labelEn: 'Haid',
                labelAr: 'حيض',
                color: AppColors.haid,
                foreground: Colors.white,
              ),
              const _CalendarLegend(
                labelEn: 'Expected Haid',
                labelAr: 'حيض متوقع',
                color: Color(0xFFFFF1F2),
                foreground: AppColors.haid,
                outlined: true,
              ),
              const _CalendarLegend(
                labelEn: 'Tahara',
                labelAr: 'طهارة',
                color: Color(0xFFE6F7F2),
                foreground: AppColors.tahara,
              ),
              if (showFertileWindow) ...[
                _CalendarLegend(
                  labelEn: _DayMarker.fertile.label,
                  labelAr: 'خصوبة',
                  color: _DayMarker.fertile.fill,
                  foreground: _DayMarker.fertile.color,
                ),
                _CalendarLegend(
                  labelEn: _DayMarker.ovulation.label,
                  labelAr: 'التبويض',
                  color: _DayMarker.ovulation.fill,
                  foreground: _DayMarker.ovulation.color,
                  outlined: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  _DayMarker _markerFor(DateTime date, CycleLog? log) {
    final cycleLength = summary.averageCycleLength;
    final periodLength = summary.averagePeriodLength;
    if (cycleLength == null || periodLength == null) {
      return _DayMarker.tahara;
    }
    if (log != null) {
      return log.flow == FlowLevel.none ? _DayMarker.tahara : _DayMarker.haid;
    }
    final start = summary.lastCycleStart;
    if (start == null) return _DayMarker.tahara;
    final difference = DateUtils.dateOnly(date)
        .difference(DateUtils.dateOnly(start))
        .inDays;
    if (difference < 0) return _DayMarker.none;
    final cycleDay = difference % cycleLength + 1;
    // A degenerate average (e.g. 2 days, from two Haid starts logged close
    // together) would otherwise repeat this "Expected Haid" block every
    // couple of days instead of once per real cycle — never project it
    // without the same plausibility gate the fertile window already uses.
    if (summary.hasPlausibleAverage && cycleDay <= periodLength) {
      return _DayMarker.expectedHaid;
    }
    if (!showFertileWindow) return _DayMarker.none;
    // Reuses the single shared fertile-window projection (CycleTrackingController
    // .calculateFertileWindow, via summary.fertileWindow) instead of a separate
    // repeating cycleLength/2 approximation — keeps this in agreement with the
    // Dashboard/Insights/Husband Report, and automatically shows nothing when
    // the average is too implausible to trust (hasPlausibleAverage guard).
    final fertileStart = summary.fertileWindow.start;
    final fertileEnd = summary.fertileWindow.end;
    final peakDay = summary.fertileWindow.peakDay;
    final day = DateUtils.dateOnly(date);
    if (peakDay != null && DateUtils.isSameDay(day, peakDay)) {
      return _DayMarker.ovulation;
    }
    if (fertileStart != null &&
        fertileEnd != null &&
        !day.isBefore(DateUtils.dateOnly(fertileStart)) &&
        !day.isAfter(DateUtils.dateOnly(fertileEnd))) {
      return _DayMarker.fertile;
    }
    return _DayMarker.none;
  }
}

class _CalendarDay extends StatefulWidget {
  const _CalendarDay({
    required this.date,
    required this.marker,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
    required this.showHijri,
  });
  final DateTime date;
  final _DayMarker marker;
  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;
  final bool showHijri;

  @override
  State<_CalendarDay> createState() => _CalendarDayState();
}

class _CalendarDayState extends State<_CalendarDay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _CalendarDay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isToday != widget.isToday) _syncAnimation();
  }

  void _syncAnimation() {
    if (!widget.isToday || MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      final isTesting = WidgetsBinding.instance.runtimeType.toString().contains(
        'Test',
      );
      if (!isTesting) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hijri = _toHijriDate(widget.date);
    final marker = widget.marker;
    final isToday = widget.isToday;
    final foreground = marker == _DayMarker.haid ? Colors.white : marker.color;
    return Opacity(
      opacity: widget.inMonth ? 1 : 0.1,
      child: Semantics(
        button: true,
        label: '${widget.date.day}, ${marker.label}',
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(9),
          child: CustomPaint(
            foregroundPainter: marker == _DayMarker.expectedHaid && !isToday
                ? const _DashedRoundedBorderPainter(
                    color: Color(0xFFFDA4AF),
                    radius: 9,
                  )
                : null,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: marker.fill,
                  border: Border.all(
                    color: isToday
                        ? AppColors.success
                        : marker.outlined && marker != _DayMarker.expectedHaid
                        ? marker.color
                        : Colors.transparent,
                    width: isToday || marker == _DayMarker.ovulation ? 2 : 1.5,
                  ),
                  boxShadow: isToday
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(
                              alpha: 0.35 * _controller.value,
                            ),
                            blurRadius: 4 + 4 * _controller.value,
                            spreadRadius: 1 * _controller.value,
                          ),
                        ]
                      : null,
                ),
                child: Transform.scale(
                  scale: isToday ? 1 + 0.08 * _controller.value : 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.showHijri ? '${hijri.$1}' : '${widget.date.day}',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          height: 1,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String hijriMonthLabel(DateTime date) {
  final midpoint = DateTime(date.year, date.month, 15);
  final hijri = _toHijriDate(midpoint);
  const namesAr = [
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
  const namesEn = [
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
  final names = AppLocaleController.instance.isArabic ? namesAr : namesEn;
  return '${names[hijri.$2 - 1]} ${hijri.$3}';
}

String hijriDateLabel(DateTime date) {
  final hijri = _toHijriDate(date);
  final suffix = AppLocaleController.instance.isArabic ? 'هـ' : 'AH';
  return '${hijri.$1}/${hijri.$2}/${hijri.$3} $suffix';
}

(int, int, int) hijriDateParts(DateTime date) => _toHijriDate(date);

DateTime gregorianDateFromHijri(int year, int month, int day) {
  final julianDay =
      day +
      (29.5 * (month - 1)).ceil() +
      (year - 1) * 354 +
      ((3 + 11 * year) ~/ 30) +
      1948439 -
      1;
  var l = julianDay + 68569;
  final n = (4 * l) ~/ 146097;
  l -= (146097 * n + 3) ~/ 4;
  final i = (4000 * (l + 1)) ~/ 1461001;
  l = l - (1461 * i) ~/ 4 + 31;
  final j = (80 * l) ~/ 2447;
  final gregorianDay = l - (2447 * j) ~/ 80;
  l = j ~/ 11;
  final gregorianMonth = j + 2 - 12 * l;
  final gregorianYear = 100 * (n - 49) + i + l;
  return DateTime(gregorianYear, gregorianMonth, gregorianDay);
}

String hijriYearRangeLabel(DateTime start, DateTime end) {
  final startYear = _toHijriDate(start).$3;
  final endYear = _toHijriDate(end).$3;
  final suffix = AppLocaleController.instance.isArabic ? 'هـ' : 'AH';
  return startYear == endYear
      ? '$startYear $suffix'
      : '$startYear–$endYear $suffix';
}

(int, int, int) _toHijriDate(DateTime date) {
  final jd =
      (1461 * (date.year + 4800 + (date.month - 14) ~/ 12)) ~/ 4 +
      (367 * (date.month - 2 - 12 * ((date.month - 14) ~/ 12))) ~/ 12 -
      (3 * ((date.year + 4900 + (date.month - 14) ~/ 12) ~/ 100)) ~/ 4 +
      date.day -
      32075;
  var l = jd - 1948440 + 10632;
  final n = (l - 1) ~/ 10631;
  l = l - 10631 * n + 354;
  final j =
      ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
      (l ~/ 5670) * ((43 * l) ~/ 15238);
  l =
      l -
      ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
      (j ~/ 16) * ((15238 * j) ~/ 43) +
      29;
  final month = (24 * l) ~/ 709;
  final day = l - (709 * month) ~/ 24;
  final year = 30 * n + j - 30;
  return (day, month, year);
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _CalendarModeButton extends StatelessWidget {
  const _CalendarModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 5)]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? AppColors.emeraldInk
              : AppColors.tahara.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({
    required this.labelEn,
    required this.labelAr,
    required this.color,
    required this.foreground,
    this.outlined = false,
  });

  final String labelEn;
  final String labelAr;
  final Color color;
  final Color foreground;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      border: outlined ? Border.all(color: foreground) : null,
    ),
    child: Text(
      AppLocaleController.instance.text(labelEn, labelAr),
      style: TextStyle(
        color: foreground,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

enum _DayMarker {
  none('No entry', Color(0xFFE2F5EF), AppColors.tahara, false),
  haid('Haid', AppColors.haid, AppColors.haid, false),
  expectedHaid('Expected Haid', Color(0xFFFFF0F4), AppColors.haid, true),
  tahara('Tahara', Color(0xFFE2F5EF), AppColors.tahara, false),
  fertile('Fertile', Color(0x1AD97706), AppColors.nifas, false),
  ovulation('Ovulation', Color(0x1A4F46E5), AppColors.istihadah, true);

  const _DayMarker(this.label, this.fill, this.color, this.outlined);
  final String label;
  final Color fill;
  final Color color;
  final bool outlined;
}
