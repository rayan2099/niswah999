import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/marital_status_controller.dart';
import '../../../../core/preferences/ttc_mode_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/services/cycle_calculation_service.dart';
import '../viewmodels/cycle_tracking_view_model.dart';
import '../widgets/cycle_calendar.dart';
import '../widgets/cycle_log_form_sheet.dart';

String _ct(String en, String ar) => AppLocaleController.instance.text(en, ar);

class CycleTrackingScreen extends StatefulWidget {
  const CycleTrackingScreen({super.key, this.viewModel});

  /// Shared across tabs by [NiswahHomeShell] so a log saved on one tab is
  /// immediately reflected on the others — falls back to a private
  /// instance when unset (e.g. existing tests that mount this screen
  /// standalone).
  final CycleTrackingViewModel? viewModel;

  @override
  State<CycleTrackingScreen> createState() => _CycleTrackingScreenState();
}

class _CycleTrackingScreenState extends State<CycleTrackingScreen> {
  late final CycleTrackingViewModel _viewModel;
  DateTime _focusedMonth = AppClock.now();
  bool _hijriFirst = false;
  bool _summaryHijri = false;
  _SummaryPeriod _summaryPeriod = _SummaryPeriod.monthly;
  DateTimeRange? _customSummaryRange;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? (CycleTrackingViewModel()..loadLogs());
    TtcModeController.instance.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      _viewModel,
      MaritalStatusController.instance,
      TtcModeController.instance,
    ]),
    builder: (context, _) {
      final summary = _viewModel.summary;
      final calculation = _viewModel.cycleCalculation;
      final summaryRange = _selectedSummaryRange;
      final rangeEndExclusive = summaryRange.end.add(const Duration(days: 1));
      final monthCalculation = const CycleCalculationService().calculate(
        _viewModel.logs
            .where((log) => log.date.isBefore(rangeEndExclusive))
            .toList(),
        asOf:
            _summaryPeriod == _SummaryPeriod.monthly &&
                DateUtils.isSameMonth(_focusedMonth, AppClock.now())
            ? AppClock.now()
            : summaryRange.end,
      );
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.tahara,
            onRefresh: _viewModel.loadLogs,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _CalendarHeader(
                    month: _focusedMonth,
                    showHijri: _hijriFirst,
                    onPrevious: () => _changeMonth(-1),
                    onNext: () => _changeMonth(1),
                  ),
                ),
                if (_viewModel.isLoading)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.tahara,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (_viewModel.errorMessage != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    sliver: SliverToBoxAdapter(
                      child: _CalendarLoadError(onRetry: _viewModel.loadLogs),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 132),
                  sliver: SliverList.list(
                    children: [
                      CycleCalendar(
                        logs: _viewModel.logs,
                        month: _focusedMonth,
                        summary: summary,
                        onDateSelected: _openDate,
                        showHijri: _hijriFirst,
                        onCalendarModeChanged: (value) => setState(() {
                          _hijriFirst = value;
                          _summaryHijri = value;
                        }),
                        showFertileWindow: TtcModeController.instance.enabled,
                      ),
                      if (TtcModeController.instance.enabled &&
                          (!MaritalStatusController.instance.isMarried ||
                              !calculation.hasSufficientHistory)) ...[
                        const SizedBox(height: 24),
                        _TtcRequirementsNotice(
                          isMarried: MaritalStatusController.instance.isMarried,
                          hasSufficientHistory:
                              calculation.hasSufficientHistory,
                        ),
                      ],
                      if (MaritalStatusController.instance.isMarried &&
                          TtcModeController.instance.enabled &&
                          calculation.hasSufficientHistory) ...[
                        const SizedBox(height: 24),
                        _PregnancyChanceCard(
                          summary: summary,
                          currentCycleDay: calculation.currentCycleDay,
                        ),
                      ],
                      const SizedBox(height: 32),
                      _MonthSummary(
                        range: summaryRange,
                        period: _summaryPeriod,
                        showHijri: _summaryHijri,
                        logs: _viewModel.logs,
                        cycleDay: monthCalculation.currentCycleDay,
                        cycleLength: monthCalculation.averageCycleLength,
                        hasSufficientHistory:
                            monthCalculation.hasSufficientHistory,
                        regularity: monthCalculation.regularity,
                        onPeriodChanged: (period) {
                          setState(() => _summaryPeriod = period);
                          if (period == _SummaryPeriod.custom) {
                            _selectSummaryRange();
                          }
                        },
                        onCalendarModeChanged: (value) =>
                            setState(() => _summaryHijri = value),
                        onSelectRange: _selectSummaryRange,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _changeMonth(int delta) => setState(
    () => _focusedMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + delta,
    ),
  );

  Future<void> _selectMonth() async {
    final now = AppClock.now();
    final firstDate = DateTime(now.year - 10);
    final lastDate = DateTime(now.year, now.month + 1, 0);
    var initialDate = _focusedMonth;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final selected = await showDatePicker(
      context: context,
      builder: _brightDatePickerBuilder,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: _ct('Select month', 'اختاري الشهر'),
    );
    if (selected == null || !mounted) return;
    setState(() => _focusedMonth = DateTime(selected.year, selected.month));
  }

  DateTimeRange get _selectedSummaryRange {
    switch (_summaryPeriod) {
      case _SummaryPeriod.monthly:
        return DateTimeRange(
          start: DateTime(_focusedMonth.year, _focusedMonth.month),
          end: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0),
        );
      case _SummaryPeriod.yearly:
        if (_summaryHijri) {
          final hijriYear = hijriDateParts(_focusedMonth).$3;
          final start = gregorianDateFromHijri(hijriYear, 1, 1);
          return DateTimeRange(
            start: start,
            end: gregorianDateFromHijri(
              hijriYear + 1,
              1,
              1,
            ).subtract(const Duration(days: 1)),
          );
        }
        return DateTimeRange(
          start: DateTime(_focusedMonth.year),
          end: DateTime(_focusedMonth.year, 12, 31),
        );
      case _SummaryPeriod.custom:
        return _customSummaryRange ??
            DateTimeRange(
              start: DateTime(_focusedMonth.year, _focusedMonth.month),
              end: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0),
            );
    }
  }

  Future<void> _selectSummaryRange() async {
    if (_summaryPeriod == _SummaryPeriod.custom) {
      final now = AppClock.now();
      final selected = await showModalBottomSheet<_CustomRangeSelection>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CustomRangeSheet(
          initialRange:
              _customSummaryRange ??
              DateTimeRange(start: DateTime(now.year, now.month), end: now),
          firstDate: DateTime(now.year - 10),
          lastDate: now,
          showHijri: _summaryHijri,
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _customSummaryRange = selected.range;
        _summaryHijri = selected.showHijri;
      });
      return;
    }
    if (_summaryPeriod == _SummaryPeriod.yearly) {
      await _selectYear();
      return;
    }
    await _selectMonth();
  }

  Future<void> _selectYear() async {
    final now = AppClock.now();
    final currentYear = _summaryHijri ? hijriDateParts(now).$3 : now.year;
    final selectedYear = _summaryHijri
        ? hijriDateParts(_focusedMonth).$3
        : _focusedMonth.year;
    final years = List<int>.generate(11, (index) => currentYear - index);
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(_ct('Select year', 'اختاري السنة')),
        children: years
            .map(
              (year) => SimpleDialogOption(
                key: ValueKey('summary-year-$year'),
                onPressed: () => Navigator.of(dialogContext).pop(year),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_summaryHijri ? _ct('$year AH', '$year هـ') : '$year'),
                    if (year == selectedYear)
                      const Icon(
                        Icons.check_rounded,
                        color: AppColors.tahara,
                        size: 18,
                      ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (_summaryHijri) {
        final focusedHijriMonth = hijriDateParts(_focusedMonth).$2;
        _focusedMonth = gregorianDateFromHijri(selected, focusedHijriMonth, 1);
      } else {
        _focusedMonth = DateTime(selected, _focusedMonth.month);
      }
    });
  }

  void _openDate(DateTime date) {
    final existing = _viewModel.logs
        .where((log) => DateUtils.isSameDay(log.date, date))
        .firstOrNull;
    showCycleLogSheet(
      context,
      viewModel: _viewModel,
      existingLog: existing,
      date: date,
    );
  }
}

class _CalendarLoadError extends StatelessWidget {
  const _CalendarLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFCDD5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.haid, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _ct('Cycle data could not be loaded.', 'تعذر تحميل بيانات الدورة.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9F1239)),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(_ct('Retry', 'إعادة'))),
      ],
    ),
  );
}

/// Explains why TTC mode's calendar tools (fertile window, pregnancy
/// chance) aren't showing yet — shown while TTC mode is on but one or more
/// of its requirements (married status, sufficient cycle history) is unmet.
class _TtcRequirementsNotice extends StatelessWidget {
  const _TtcRequirementsNotice({
    required this.isMarried,
    required this.hasSufficientHistory,
  });

  final bool isMarried;
  final bool hasSufficientHistory;

  @override
  Widget build(BuildContext context) {
    final messages = [
      if (!isMarried)
        _ct(
          'Turn on "I am married" in Profile to see the pregnancy chance.',
          'فعّلي "أنا متزوجة" من الملف الشخصي لرؤية فرصة الحمل.',
        ),
      if (!hasSufficientHistory)
        _ct(
          'Log at least two cycles so the fertile window can be calculated.',
          'سجّلي دورتين على الأقل حتى يتمكن التطبيق من حساب نافذة الخصوبة.',
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCDD5)),
      ),
      child: messages.length == 1
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.haid, size: 18),
                const SizedBox(width: 10),
                Expanded(child: _NoticeText(messages.first)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.haid,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _ct(
                          'To unlock TTC tools in Calendar:',
                          'حتى تظهر أدوات وضع التخطيط في التقويم:',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9F1239),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < messages.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NoticeIndex(i + 1),
                      const SizedBox(width: 8),
                      Expanded(child: _NoticeText(messages[i])),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _NoticeText extends StatelessWidget {
  const _NoticeText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11, color: Color(0xFF9F1239), height: 1.5),
  );
}

class _NoticeIndex extends StatelessWidget {
  const _NoticeIndex(this.number);
  final int number;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.haid,
      shape: BoxShape.circle,
    ),
    child: Text(
      '$number',
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1,
      ),
    ),
  );
}

class _CustomRangeSelection {
  const _CustomRangeSelection({required this.range, required this.showHijri});
  final DateTimeRange range;
  final bool showHijri;
}

Widget _brightDatePickerBuilder(BuildContext context, Widget? child) => Theme(
  data: Theme.of(context).copyWith(
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: Colors.white,
      headerForegroundColor: AppColors.textPrimary,
      dividerColor: Color(0xFFEFE7EA),
    ),
  ),
  child: child!,
);

class _CustomRangeSheet extends StatefulWidget {
  const _CustomRangeSheet({
    required this.initialRange,
    required this.firstDate,
    required this.lastDate,
    required this.showHijri,
  });

  final DateTimeRange initialRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool showHijri;

  @override
  State<_CustomRangeSheet> createState() => _CustomRangeSheetState();
}

class _CustomRangeSheetState extends State<_CustomRangeSheet> {
  late DateTime _start = widget.initialRange.start;
  late DateTime _end = widget.initialRange.end;
  late bool _showHijri = widget.showHijri;

  String _label(DateTime date) => _showHijri
      ? hijriDateLabel(date)
      : '${date.day}/${date.month}/${date.year}';

  void _applyPreset(int days) {
    setState(() {
      _end = widget.lastDate;
      final candidate = _end.subtract(Duration(days: days - 1));
      _start = candidate.isBefore(widget.firstDate)
          ? widget.firstDate
          : candidate;
    });
  }

  Future<void> _pick({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      builder: _brightDatePickerBuilder,
      initialDate: start ? _start : _end,
      firstDate: start ? widget.firstDate : _start,
      lastDate: start ? _end : widget.lastDate,
      helpText: start
          ? _ct('Select start date', 'اختاري تاريخ البداية')
          : _ct('Select end date', 'اختاري تاريخ النهاية'),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      24,
      12,
      24,
      24 + MediaQuery.viewPaddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Color(0xFFFFFBFC),
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6C9CE),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _ct('Custom period', 'فترة مخصصة'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.emeraldInk,
                    fontFamily: AppTypography.serifFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 132,
                child: _CalendarSystemToggle(
                  key: const Key('custom-range-calendar-toggle'),
                  showHijri: _showHijri,
                  onChanged: (value) => setState(() => _showHijri = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _ct(
              'Choose a quick period or set exact start and end dates.',
              'اختاري مدة سريعة أو حددي تاريخ البداية والنهاية بدقة.',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RangePreset(
                label: _ct('30 days', '30 يوماً'),
                onTap: () => _applyPreset(30),
              ),
              _RangePreset(
                label: _ct('3 months', '3 أشهر'),
                onTap: () => _applyPreset(90),
              ),
              _RangePreset(
                label: _ct('6 months', '6 أشهر'),
                onTap: () => _applyPreset(180),
              ),
              _RangePreset(
                label: _ct('1 year', 'سنة'),
                onTap: () => _applyPreset(365),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _RangeDateField(
                  title: _ct('Start', 'البداية'),
                  value: _label(_start),
                  onTap: () => _pick(start: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
              Expanded(
                child: _RangeDateField(
                  title: _ct('End', 'النهاية'),
                  value: _label(_end),
                  onTap: () => _pick(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('apply-custom-summary-range'),
            onPressed: () => Navigator.of(context).pop(
              _CustomRangeSelection(
                range: DateTimeRange(start: _start, end: _end),
                showHijri: _showHijri,
              ),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.haid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(_ct('Apply period', 'تطبيق الفترة')),
          ),
        ],
      ),
    ),
  );
}

class _RangePreset extends StatelessWidget {
  const _RangePreset({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    onPressed: onTap,
    backgroundColor: Colors.white,
    side: const BorderSide(color: Color(0xFFD1FAE5)),
    labelStyle: const TextStyle(
      color: AppColors.emeraldInk,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _RangeDateField extends StatelessWidget {
  const _RangeDateField({
    required this.title,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 9),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.emeraldInk,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.month,
    required this.showHijri,
    required this.onPrevious,
    required this.onNext,
  });
  final DateTime month;
  final bool showHijri;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _ct('Calendar', 'التقويم'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.emeraldInk,
              fontFamily: AppTypography.serifFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.shadowColor),
            boxShadow: const [
              BoxShadow(color: AppColors.shadowColor, blurRadius: 8),
            ],
          ),
          child: Row(
            children: [
              _MonthButton(icon: Icons.chevron_left, onTap: onPrevious),
              SizedBox(
                width: 100,
                child: Text(
                  showHijri
                      ? hijriMonthLabel(month)
                      : '${_monthName(month.month)} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.emeraldInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _MonthButton(icon: Icons.chevron_right, onTap: onNext),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    padding: EdgeInsets.zero,
    icon: Icon(icon, color: AppColors.emeraldInk, size: 21),
  );
}

class _PregnancyChanceCard extends StatelessWidget {
  const _PregnancyChanceCard({
    required this.summary,
    required this.currentCycleDay,
  });
  final CycleTrackingSummary summary;
  final int? currentCycleDay;

  @override
  Widget build(BuildContext context) {
    final cycleLength = summary.averageCycleLength;
    final chanceLabel = (cycleLength == null || currentCycleDay == null)
        ? null
        : switch (_conceptionChanceAt(currentCycleDay!, cycleLength)) {
            >= 0.6 => _ct('HIGH', 'عالية'),
            >= 0.2 => _ct('MEDIUM', 'متوسطة'),
            _ => _ct('LOW', 'منخفضة'),
          };
    return _WhiteCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _ct('Chance of pregnancy', 'فرصة الحمل'),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                chanceLabel ?? '—',
                style: TextStyle(
                  color: Color(0xFF42A5F5),
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: (cycleLength == null || currentCycleDay == null)
                ? null
                : CustomPaint(
                    painter: _ChanceChartPainter(
                      cycleLength: cycleLength,
                      currentCycleDay: currentCycleDay!,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ChartLabel(
                label: _ct('START OF CYCLE', 'بداية الدورة'),
                value: summary.lastCycleStart == null
                    ? '—'
                    : _shortDate(summary.lastCycleStart!),
              ),
              _ChartLabel(
                label: _ct('OVULATION', 'التبويض'),
                value: summary.fertileWindow.peakDay == null
                    ? '—'
                    : _shortDate(summary.fertileWindow.peakDay!),
              ),
              _ChartLabel(
                label: _ct('NEXT CYCLE', 'الدورة القادمة'),
                value: summary.nextPeriodStart == null
                    ? '—'
                    : _shortDate(summary.nextPeriodStart!),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFEF3C7)),
            ),
            child: Text(
              _ct(
                'Predictions improve as you log more cycles',
                'التنبؤ يتحسن مع المزيد من الدورات',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFD97706),
                fontSize: 9,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLabel extends StatelessWidget {
  const _ChartLabel({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 8,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

// Retained for non-compact accessibility variants.
// ignore: unused_element
class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 8, bottom: 16),
        child: Text(
          'LEGEND',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const Row(
        children: [
          Expanded(
            child: _LegendCard(
              label: 'Haid',
              color: AppColors.haid,
              icon: Icons.water_drop_outlined,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _LegendCard(
              label: 'Tahara',
              color: AppColors.tahara,
              icon: Icons.auto_awesome_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Row(
        children: [
          Expanded(
            child: _LegendCard(
              label: 'Istihadah',
              color: AppColors.istihadah,
              icon: Icons.info_outline,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _LegendCard(
              label: 'Nifas',
              color: AppColors.nifas,
              icon: Icons.info_outline,
            ),
          ),
        ],
      ),
    ],
  );
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.shadowColor),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

enum _SummaryPeriod { monthly, yearly, custom }

class _CalendarSystemToggle extends StatelessWidget {
  const _CalendarSystemToggle({
    super.key,
    required this.showHijri,
    required this.onChanged,
  });

  final bool showHijri;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFDDF7EF),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        Expanded(
          child: _CalendarSystemOption(
            label: _ct('Gregorian', 'ميلادي'),
            selected: !showHijri,
            onTap: () => onChanged(false),
          ),
        ),
        Expanded(
          child: _CalendarSystemOption(
            label: _ct('Hijri', 'هجري'),
            selected: showHijri,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    ),
  );
}

class _CalendarSystemOption extends StatelessWidget {
  const _CalendarSystemOption({
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
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)]
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? AppColors.emeraldInk : AppColors.tahara,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _SummaryPeriodSelector extends StatelessWidget {
  const _SummaryPeriodSelector({
    required this.selected,
    required this.onChanged,
  });

  final _SummaryPeriod selected;
  final ValueChanged<_SummaryPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: _SummaryPeriod.values.map((period) {
      final active = period == selected;
      final label = switch (period) {
        _SummaryPeriod.monthly => _ct('Monthly', 'شهري'),
        _SummaryPeriod.yearly => _ct('Yearly', 'سنوي'),
        _SummaryPeriod.custom => _ct('Custom period', 'فترة مخصصة'),
      };
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            onPressed: () => onChanged(period),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: active ? Colors.white : AppColors.tahara,
              backgroundColor: active ? AppColors.tahara : Colors.white,
              side: BorderSide(
                color: active ? AppColors.tahara : const Color(0xFFD1FAE5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

String _summaryRangeLabel(
  DateTimeRange range,
  _SummaryPeriod period,
  bool showHijri,
) {
  if (period == _SummaryPeriod.monthly) {
    if (showHijri) return hijriMonthLabel(range.start);
    return '${_monthName(range.start.month)} ${range.start.year}';
  }
  if (period == _SummaryPeriod.yearly) {
    return showHijri
        ? hijriYearRangeLabel(range.start, range.end)
        : '${range.start.year}';
  }
  if (showHijri) {
    return '${hijriDateLabel(range.start)} – ${hijriDateLabel(range.end)}';
  }
  return '${range.start.day}/${range.start.month}/${range.start.year} – '
      '${range.end.day}/${range.end.month}/${range.end.year}';
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.range,
    required this.period,
    required this.showHijri,
    required this.logs,
    required this.cycleDay,
    required this.cycleLength,
    required this.hasSufficientHistory,
    required this.regularity,
    required this.onPeriodChanged,
    required this.onCalendarModeChanged,
    required this.onSelectRange,
  });
  final DateTimeRange range;
  final _SummaryPeriod period;
  final bool showHijri;
  final List<CycleLog> logs;
  final int? cycleDay;
  final int? cycleLength;
  final bool hasSufficientHistory;
  final CycleRegularity regularity;
  final ValueChanged<_SummaryPeriod> onPeriodChanged;
  final ValueChanged<bool> onCalendarModeChanged;
  final VoidCallback onSelectRange;

  @override
  Widget build(BuildContext context) {
    final rangeEndExclusive = range.end.add(const Duration(days: 1));
    final monthLogs = logs.where(
      (log) =>
          !log.date.isBefore(range.start) &&
          log.date.isBefore(rangeEndExclusive),
    );
    final latestByDay = <String, CycleLog>{};
    for (final log in monthLogs) {
      final key = '${log.date.year}-${log.date.month}-${log.date.day}';
      final existing = latestByDay[key];
      if (existing == null || log.date.isAfter(existing.date)) {
        latestByDay[key] = log;
      }
    }
    final haid = latestByDay.values
        .where((log) => log.flow != FlowLevel.none)
        .length;
    final tahara = latestByDay.values
        .where((log) => log.flow == FlowLevel.none)
        .length;
    final isCurrentMonth =
        period == _SummaryPeriod.monthly &&
        DateUtils.isSameMonth(range.start, AppClock.now());
    final factualCycleDay = cycleDay;
    final factualCycleLength = cycleLength;
    // Distinct from hasSufficientHistory: the Haid/Tahara day tallies above
    // stay valid on a small sample, but predicting a next period or fertile
    // window from a degenerate average (e.g. 2 days) would be misleading —
    // see CycleCalculationResult.hasPlausibleAverage.
    final canPredict =
        hasSufficientHistory &&
        factualCycleLength != null &&
        factualCycleLength >= CycleCalculationResult.minPlausibleCycleLengthDays;
    final progress = !isCurrentMonth || !canPredict || factualCycleDay == null
        ? null
        : factualCycleDay / factualCycleLength;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Column(
        children: [
          _SummaryPeriodSelector(selected: period, onChanged: onPeriodChanged),
          const SizedBox(height: 12),
          _CalendarSystemToggle(
            key: const Key('summary-calendar-toggle'),
            showHijri: showHijri,
            onChanged: onCalendarModeChanged,
          ),
          const SizedBox(height: 18),
          InkWell(
            key: const Key('month-summary-picker'),
            onTap: onSelectRange,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1FAE5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.tahara,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _summaryRangeLabel(range, period, showHijri),
                      style: const TextStyle(
                        color: AppColors.emeraldInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _ct('Change', 'تغيير'),
                    style: const TextStyle(
                      color: AppColors.tahara,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period == _SummaryPeriod.monthly
                          ? _ct('Month summary', 'ملخص الشهر')
                          : _ct('Period summary', 'ملخص الفترة'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.emeraldInk,
                        fontFamily: AppTypography.serifFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _summaryRangeLabel(range, period, showHijri),
                      style: TextStyle(
                        color: AppColors.tahara.withValues(alpha: 0.6),
                        fontSize: 9,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _ct('CYCLE REGULARITY', 'انتظام الدورة'),
                    style: TextStyle(
                      color: Color(0x660D9488),
                      fontSize: 8,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    hasSufficientHistory &&
                            regularity != CycleRegularity.insufficientData
                        ? cycleRegularityLabel(
                            regularity,
                            isArabic: AppLocaleController.instance.isArabic,
                          )
                        : '—',
                    style: TextStyle(
                      color: AppColors.emeraldInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppTypography.serifFamily,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          Builder(
            builder: (context) {
              final haidMetric = _SummaryMetric(
                label: _ct('TOTAL HAID DAYS', 'إجمالي أيام الحيض'),
                value: !hasSufficientHistory
                    ? '—'
                    : haid == 0
                    ? _ct(
                        'No Haid logged in this period',
                        'لم يُسجَّل حيض في هذه الفترة',
                      )
                    : '$haid',
                unit: !hasSufficientHistory || haid == 0
                    ? ''
                    : _ct('days', 'أيام'),
              );
              final taharaMetric = _SummaryMetric(
                label: _ct('TOTAL TAHARA DAYS', 'إجمالي أيام الطهارة'),
                value: !hasSufficientHistory
                    ? '—'
                    : tahara == 0
                    ? _ct(
                        'No Tahara logged in this period',
                        'لم تُسجَّل طهارة في هذه الفترة',
                      )
                    : '$tahara',
                unit: !hasSufficientHistory || tahara == 0
                    ? ''
                    : _ct('days', 'أيام'),
              );
              // A long descriptive sentence (haid/tahara == 0) needs the
              // full row width to read horizontally in a couple of lines —
              // squeezed into a half-width Expanded, it wraps one word per
              // line instead.
              final needsFullWidth =
                  hasSufficientHistory && (haid == 0 || tahara == 0);
              return needsFullWidth
                  ? Column(
                      children: [
                        haidMetric,
                        const SizedBox(height: 14),
                        taharaMetric,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: haidMetric),
                        const SizedBox(width: 14),
                        Expanded(child: taharaMetric),
                      ],
                    );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: _ct('AVG CYCLE LENGTH', 'متوسط طول الدورة'),
                  value: !canPredict
                      ? '—'
                      : factualCycleLength.toString(),
                  unit: !canPredict
                      ? ''
                      : _ct('days', 'أيام'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SummaryMetric(
                  label: _ct('NEXT PERIOD', 'الحيض القادم'),
                  value:
                      !isCurrentMonth || !canPredict || factualCycleDay == null
                      ? '—'
                      : '${math.max(0, factualCycleLength - factualCycleDay)}',
                  unit:
                      !isCurrentMonth || !canPredict || factualCycleDay == null
                      ? ''
                      : _ct('days left', 'أيام متبقية'),
                ),
              ),
            ],
          ),
          if (!hasSufficientHistory || !canPredict) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1FAE5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_clock_outlined,
                    size: 18,
                    color: AppColors.tahara,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      !hasSufficientHistory
                          ? _ct(
                              'Log at least two cycle starts to see cycle progress',
                              'سجّلي بدايتي دورتين على الأقل لعرض تقدم الدورة',
                            )
                          : _ct(
                              'Log a couple more cycles for a reliable prediction',
                              'سجّلي بضع دورات إضافية للحصول على توقع موثوق',
                            ),
                      style: const TextStyle(
                        color: AppColors.emeraldInk,
                        fontSize: 10,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (progress != null) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _ct('CYCLE PROGRESS', 'تقدم الدورة'),
                  style: const TextStyle(
                    color: Color(0x660D9488),
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${(progress.clamp(0, 1) * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0x660D9488),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 8,
                backgroundColor: const Color(0xFFD1FAE5),
                valueColor: const AlwaysStoppedAnimation(AppColors.success),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0x660D9488),
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  color: AppColors.emeraldInk,
                  fontSize: value.length > 20
                      ? 13
                      : value.length > 8
                      ? 17
                      : 24,
                  height: value.length > 20 ? 1.5 : 1.25,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppTypography.serifFamily,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: const TextStyle(
                    color: Color(0x990D9488),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
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
    child: child,
  );
}

/// Estimated conception-chance curve: a bell centered on the predicted
/// ovulation day (14 days before the next predicted period), matching
/// [CycleTrackingController.calculateFertileWindow]'s heuristic. [dayOfCycle]
/// is 1-indexed, matching [CycleCalculationResult.currentCycleDay].
double _conceptionChanceAt(int dayOfCycle, int cycleLength) =>
    math.exp(-math.pow(dayOfCycle - (cycleLength - 14), 2) / 15);

class _ChanceChartPainter extends CustomPainter {
  const _ChanceChartPainter({
    required this.cycleLength,
    required this.currentCycleDay,
  });
  final int cycleLength;
  final int currentCycleDay;
  @override
  void paint(Canvas canvas, Size size) {
    // Guards against dividing by zero below — a cycle length this short
    // can't be usefully charted anyway.
    if (cycleLength <= 1) return;

    final line = Path();
    final fill = Path()..moveTo(0, size.height);
    for (var i = 0; i < cycleLength; i++) {
      final x = i / (cycleLength - 1) * size.width;
      final chance = _conceptionChanceAt(i + 1, cycleLength);
      final y = size.height - chance * (size.height - 24);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      fill.lineTo(x, y);
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x554FC3F7), Color(0x004FC3F7)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF4FC3F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final markerDay = currentCycleDay.clamp(1, cycleLength);
    final markerX = (markerDay - 1) / (cycleLength - 1) * size.width;
    canvas.drawLine(
      Offset(markerX, 10),
      Offset(markerX, size.height),
      Paint()
        ..color = AppColors.success
        ..strokeWidth = 2,
    );
    final isArabic = AppLocaleController.instance.isArabic;
    final label = TextPainter(
      text: TextSpan(
        text: _ct('YOU ARE HERE', 'أنتِ هنا'),
        style: const TextStyle(
          color: AppColors.success,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(markerX - label.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _ChanceChartPainter oldDelegate) =>
      oldDelegate.cycleLength != cycleLength ||
      oldDelegate.currentCycleDay != currentCycleDay;
}

String _shortDate(DateTime date) =>
    '${date.day} ${_monthName(date.month).substring(0, 3)}';
String _monthName(int month) => (AppLocaleController.instance.isArabic
    ? const [
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
      ]
    : const [
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
      ])[month - 1];
