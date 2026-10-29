import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../../cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import '../../../cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';
import '../../../cycle_tracking/presentation/widgets/predicted_range_text.dart';
import '../../../wellbeing/data/repositories/wellbeing_repository.dart';
import '../../../wellbeing/domain/entities/wellbeing_log.dart';
import '../../../wellbeing/domain/services/wellbeing_period_split.dart';

String _in(String en, String ar) => AppLocaleController.instance.text(en, ar);

Color _regularityColor(CycleRegularity regularity) => switch (regularity) {
  CycleRegularity.regular || CycleRegularity.highlyRegular => AppColors.success,
  CycleRegularity.irregular => AppColors.warning,
  CycleRegularity.insufficientData => AppColors.textSecondary,
};

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.viewModel, this.loadWellbeingLogs});

  /// Shared across tabs by [NiswahHomeShell] so a log saved on one tab is
  /// immediately reflected on the others — falls back to a private
  /// instance when unset (e.g. existing tests that mount this screen
  /// standalone).
  final CycleTrackingViewModel? viewModel;

  /// Reads mood check-ins from [from] onwards; defaults to
  /// [WellbeingRepository.getLogs]. Injectable for tests.
  final Future<List<WellbeingLog>> Function(DateTime from)? loadWellbeingLogs;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final CycleTrackingViewModel _viewModel;
  int _trendMonths = 3;
  int _wellbeingRefresh = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? (CycleTrackingViewModel()..loadLogs());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _viewModel,
    builder: (context, _) {
      final summary = _viewModel.summary;
      final calculation = _viewModel.cycleCalculation;
      final enoughData = calculation.hasSufficientHistory;
      // The same gate as Today's ring and the reminder: never a date when
      // the predictor itself declined (every interval outside the
      // predictable range), not only when the plain average is implausible.
      final canPredict = enoughData && calculation.canPredictFromHistory;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.brandSecondary,
            onRefresh: () async {
              setState(() => _wellbeingRefresh++);
              await _viewModel.loadLogs();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _in('Predictions', 'توقعات'),
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: const Color(0xFF8E244D),
                                fontFamily: AppTypography.serifFamily,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _in(
                            'Personalized insights based on your health and Fiqh data',
                            'رؤى مخصصة بناءً على بياناتكِ الصحية والفقهية',
                          ),
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_viewModel.isLoading)
                  SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.brandSecondary,
                      backgroundColor: Colors.transparent,
                      semanticsLabel: _in(
                        'Loading insights',
                        'جارٍ تحميل الإحصاءات',
                      ),
                    ),
                  ),
                if (_viewModel.errorMessage != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: _InsightsLoadError(onRetry: _viewModel.loadLogs),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 132),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: _in(
                                'AVERAGE CYCLE LENGTH',
                                'متوسط مدة الدورة',
                              ),
                              value: enoughData
                                  ? '${summary.averageCycleLength} ${_in('days', 'يوماً')}'
                                  : _in(
                                      'Insufficient data',
                                      'بيانات غير كافية',
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: _in('REGULARITY', 'الانتظام'),
                              value: cycleRegularityLabel(
                                calculation.regularity,
                                isArabic: AppLocaleController.instance.isArabic,
                              ),
                              valueColor: _regularityColor(
                                calculation.regularity,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _PredictionCard(
                        summary: summary,
                        hasData: enoughData,
                        canPredict: canPredict,
                      ),
                      const SizedBox(height: 28),
                      _SymptomTrends(
                        logs: _viewModel.logs,
                        months: _trendMonths,
                        onMonthsChanged: (value) =>
                            setState(() => _trendMonths = value),
                        onLog: () => showCycleLogSheet(
                          context,
                          viewModel: _viewModel,
                          existingLog: _viewModel.logs
                              .where(
                                (log) => DateUtils.isSameDay(
                                  log.date,
                                  AppClock.now(),
                                ),
                              )
                              .firstOrNull,
                          mode: CycleLogSheetMode.symptomsOnly,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _WellbeingTrends(
                        months: _trendMonths,
                        refreshToken: _wellbeingRefresh,
                        cycleLogs: _viewModel.logs,
                        episodes: _viewModel.canonicalEpisodes,
                        load:
                            widget.loadWellbeingLogs ??
                            (from) => WellbeingRepository().getLogs(from: from),
                      ),
                      const SizedBox(height: 28),
                      _RegularityCard(result: calculation),
                      const SizedBox(height: 32),
                      _SectionLabel(_in('HEALTH INSIGHTS', 'رؤى صحية')),
                      const SizedBox(height: 12),
                      const _InsightCard(),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SectionLabel(_in('CYCLE HISTORY', 'سجل الدورة')),
                          Text(
                            _in('VIEW ALL', 'عرض الكل'),
                            style: TextStyle(
                              color: AppColors.brandSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _HistoryCard(
                        logs: _viewModel.logs,
                        canonicalEpisodes: _viewModel.canonicalEpisodes,
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
}

class _InsightsLoadError extends StatelessWidget {
  const _InsightsLoadError({required this.onRetry});

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
            _in('Insights could not be loaded.', 'تعذر تحميل الرؤى.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9F1239)),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(_in('Retry', 'إعادة'))),
      ],
    ),
  );
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.summary,
    required this.hasData,
    required this.canPredict,
  });
  final CycleTrackingSummary summary;
  final bool hasData;
  final bool canPredict;

  String _date(DateTime? value) =>
      value == null ? '—' : '${value.day}/${value.month}/${value.year}';

  @override
  Widget build(BuildContext context) {
    final nextPeriod = canPredict ? summary.nextPeriodStart : null;
    final daysLate = canPredict ? summary.daysLate : 0;
    // A range from her stated estimate alone is shown too, labeled as such.
    final range =
        canPredict || summary.predictionBasis == PredictionBasis.statedEstimate
        ? summary.nextPeriodRange
        : null;
    final isArabic = AppLocaleController.instance.isArabic;
    final basisNote = range == null
        ? null
        : predictionBasisNote(summary.predictionBasis, isArabic: isArabic);
    final daysUntil = nextPeriod == null
        ? null
        : calendarDaysBetween(AppClock.now(), nextPeriod);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFFFE4E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                color: AppColors.brandSecondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _in('Next prediction', 'التوقع القادم'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF8E244D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      !hasData
                          ? _in(
                              'Log two cycle starts to enable predictions.',
                              'سجلي بدايتَي دورتين لتفعيل التوقعات.',
                            )
                          : !canPredict
                          ? _in(
                              'Log a couple more cycles for a reliable prediction.',
                              'سجّلي بضع دورات إضافية للحصول على توقع موثوق.',
                            )
                          : _in(
                              'Accuracy improves with every factual log.',
                              'تتحسن الدقة مع كل تسجيل حقيقي.',
                            ),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PredictionValue(
                  label: _in('EXPECTED PERIOD', 'الحيض المتوقع'),
                  value: range != null
                      ? formatPredictedRange(range, isArabic: isArabic)
                      : _date(nextPeriod),
                  note: daysLate > 0
                      ? nextPeriod != null
                            ? _in(
                                'Late by $daysLate days, may start any day',
                                'متأخرة $daysLate أيام، قد تبدأ في أي يوم',
                              )
                            : _in(
                                'Late by $daysLate days',
                                'متأخرة $daysLate أيام',
                              )
                      : basisNote ??
                            (daysUntil == null
                                // PT-079: no date is shown, never a guess.
                                ? _in(
                                    'Not enough data for a prediction',
                                    'لا تتوفر بيانات كافية للتوقع',
                                  )
                                : _in(
                                    'In about ${daysUntil.clamp(0, 999)} days',
                                    'بعد ${daysUntil.clamp(0, 999)} أيام تقريباً',
                                  )),
                  color: AppColors.haid,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PredictionValue(
                  label: _in('EXPECTED OVULATION', 'التبويض المتوقع'),
                  value: _date(
                    canPredict ? summary.fertileWindow.peakDay : null,
                  ),
                  note: _in(
                    'Planning only, not medical confirmation.',
                    'للتخطيط فقط، وليس تأكيداً طبياً.',
                  ),
                  // AU-003: this feeds a small (8px) Text color — use the
                  // contrast-safe variant, not the base brand color.
                  color: AppColors.taharaText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PredictionValue extends StatelessWidget {
  const _PredictionValue({
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });
  final String label;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.shadowColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          note,
          maxLines: 2,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 8,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor = AppColors.textSecondary,
  });
  final String label;
  final String value;
  final Color valueColor;
  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _SymptomTrends extends StatelessWidget {
  const _SymptomTrends({
    required this.logs,
    required this.months,
    required this.onMonthsChanged,
    required this.onLog,
  });
  final List<CycleLog> logs;
  final int months;
  final ValueChanged<int> onMonthsChanged;
  final VoidCallback onLog;

  Future<void> _selectRange(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrendRangeSheet(selected: months),
    );
    if (selected != null) onMonthsChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final rangeStart = DateTime(
      AppClock.now().year,
      AppClock.now().month - months + 1,
    );
    final rangeLogs = logs
        .where((log) => !log.date.isBefore(rangeStart))
        .toList();
    // Named symptoms are saved keyed by whichever locale's label was shown
    // at log time (e.g. 'Cramps' or 'تشنجات') — count under both possible
    // keys so a symptom logged in either language is found.
    final counts = <String, int>{};
    for (final aggregate in CycleSymptomDecoder.aggregateSymptoms(rangeLogs)) {
      counts[aggregate.name] = aggregate.occurrenceCount;
    }
    // Energy/sleep are 1-5 scale values, not tap-to-flag symptoms — treat a
    // logged day as "low energy"/"poor sleep" once it's at or below 2.
    final decodedRangeLogs = CycleSymptomDecoder.decodeAll(rangeLogs);
    final lowEnergyCount = decodedRangeLogs
        .where((entry) => entry.energy != null && entry.energy! <= 2)
        .length;
    final poorSleepCount = decodedRangeLogs
        .where((entry) => entry.sleep != null && entry.sleep! <= 2)
        .length;
    const symptoms = [
      ('Fatigue', 'تعب', AppColors.warning),
      ('Headache', 'صداع', AppColors.info),
      ('Cramps', 'تشنجات', AppColors.brandSecondary),
      ('Mood', 'المزاج', AppColors.istihadah),
      ('Bloating', 'انتفاخ', AppColors.nifas),
      ('Back pain', 'ألم ظهر', AppColors.haid),
      ('Nausea', 'غثيان', AppColors.success),
      ('Acne', 'حبوب', AppColors.istihadah),
      ('Breast pain', 'آلام الثدي', AppColors.brandSecondary),
    ];
    int countFor(String englishLabel, String arabicLabel) =>
        (counts[englishLabel] ?? 0) + (counts[arabicLabel] ?? 0);
    final rows = [
      for (final item in symptoms)
        (item.$1, item.$2, item.$3, countFor(item.$1, item.$2)),
      ('Low energy', 'طاقة منخفضة', AppColors.warning, lowEnergyCount),
      ('Poor sleep', 'نوم سيء', AppColors.info, poorSleepCount),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                color: AppColors.brandSecondary,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _in('Symptom trends', 'اتجاهات الأعراض'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                key: const Key('insights-trend-range'),
                onTap: () => _selectRange(context),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFFFCDD5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _in('Last $months months', 'آخر $months أشهر'),
                        style: const TextStyle(
                          color: Color(0xFF9F1239),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 15,
                        color: Color(0xFF9F1239),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Requirement 3: no fabricated percentages. With zero real logs
          // in range, there is nothing honest to show as a trend at all —
          // the range selector above stays reachable (she may want to
          // check a wider window), but the rows below are replaced
          // entirely rather than showing a wall of '—' dashes.
          if (rangeLogs.isEmpty)
            EmptyState(
              icon: Icons.trending_up_rounded,
              title: _in('Not enough data yet', 'لا توجد بيانات كافية بعد'),
              message: _in(
                'Log your symptoms to see your trends here.',
                'سجّلي أعراضك لتظهر الاتجاهات هنا.',
              ),
              actionLabel: _in("Log today's symptoms", 'سجلي أعراض اليوم'),
              onAction: onLog,
            )
          else ...[
            // Requirement 3: real user-entered observations only. Every
            // row shows both the raw frequency (symptom_days / logged_days
            // — real counts, always real) and the percentage derived from
            // it, immediately, from a single real log — no minimum-sample
            // gate. The denominator is explicitly labeled "logged days":
            // this app has no way to know whether an unlogged day was
            // symptom-free or simply not evaluated, so it is never counted
            // as either.
            ...rows.map((item) {
              final count = item.$4;
              final total = rangeLogs.length;
              final percent = (count / total).clamp(0.0, 1.0);
              final percentLabel = '${(percent * 100).round()}%';
              final percentLabelAr = '${(percent * 100).round()}٪';
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _in(item.$1, item.$2),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _in(percentLabel, percentLabelAr),
                          style: TextStyle(color: item.$3, fontSize: 9),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _in(
                        '$count of $total logged days',
                        'سُجّل في $count من أصل $total أيام مسجلة',
                      ),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFF3F4F6),
                        valueColor: AlwaysStoppedAnimation(item.$3),
                      ),
                    ),
                  ],
                ),
              );
            }),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onLog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9F1239),
                  backgroundColor: const Color(0xFFFFF1F2),
                  side: const BorderSide(color: Color(0xFFFFCDD5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _in('Log today\'s symptoms →', 'سجلي أعراض اليوم ←'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendRangeSheet extends StatelessWidget {
  const _TrendRangeSheet({required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      24,
      12,
      24,
      24 + MediaQuery.viewPaddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
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
          Text(
            _in('Symptom period', 'فترة اتجاهات الأعراض'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF8E244D),
              fontFamily: AppTypography.serifFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _in(
              'Choose the period used to calculate symptom percentages.',
              'اختاري الفترة المستخدمة لحساب نسب الأعراض.',
            ),
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.7,
            children: [1, 3, 6, 12].map((months) {
              final active = months == selected;
              return InkWell(
                onTap: () => Navigator.of(context).pop(months),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFFFF1F2)
                        : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: active
                          ? AppColors.brandSecondary
                          : const Color(0xFFEFE7EA),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (active) ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.brandSecondary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          _in('Last $months months', 'آخر $months أشهر'),
                          maxLines: 1,
                          style: TextStyle(
                            color: active
                                ? const Color(0xFF9F1239)
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}

class _RegularityCard extends StatelessWidget {
  const _RegularityCard({required this.result});
  final CycleCalculationResult result;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.bar_chart_rounded,
              color: AppColors.success,
              size: 21,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _in('Cycle regularity', 'انتظام الدورة'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _regularityColor(result.regularity),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (!result.hasRegularityData)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (_, _) => const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
            ),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                (result.cycleLengths.length > 10
                        ? result.cycleLengths.sublist(
                            result.cycleLengths.length - 10,
                          )
                        : result.cycleLengths)
                    .map(
                      (length) => Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: result.isCycleLengthWithinNormalRange(length)
                              ? AppColors.success
                              : AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 14),
          const _RegularityLegend(),
        ],
        const SizedBox(height: 22),
        Text(
          switch (result.regularity) {
            CycleRegularity.highlyRegular => _in(
              'Your cycle is highly regular based on recent logs',
              'دورتكِ منتظمة جداً بناءً على التسجيلات الأخيرة',
            ),
            CycleRegularity.regular => _in(
              'Your cycle is generally regular',
              'دورتكِ منتظمة بشكل عام',
            ),
            CycleRegularity.irregular => _in(
              'Your cycle shows notable variation',
              'دورتكِ تُظهر تفاوتاً ملحوظاً',
            ),
            CycleRegularity.insufficientData => _in(
              'Log your cycle to see the regularity chart',
              'سجلي دورتكِ لرؤية مخطط الانتظام',
            ),
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
        ),
      ],
    ),
  );
}

class _RegularityLegend extends StatelessWidget {
  const _RegularityLegend();

  Widget _item(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 9),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _item(AppColors.success, _in('Within range', 'ضمن المعتاد')),
      const SizedBox(width: 16),
      _item(AppColors.warning, _in('Outside range', 'خارج المعتاد')),
    ],
  );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard();
  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.istihadah.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.istihadah,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _in(
                  'Log your cycle for personalized insights',
                  'سجلي دورتكِ للحصول على رؤى مخصصة',
                ),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                _in(
                  'The more you log, the more accurate your insights become',
                  'كلما زادت تسجيلاتكِ أصبحت رؤاكِ أدق',
                ),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Mood, energy and sleep from the daily check-in, tracked on every day
/// whether or not there is a period (device run 2026-10-28: check-ins never
/// reached this screen). The split below says which check-ins fell on a
/// recorded bleeding day; it is not a fiqh classification.
class _WellbeingTrends extends StatefulWidget {
  const _WellbeingTrends({
    required this.months,
    required this.refreshToken,
    required this.cycleLogs,
    required this.episodes,
    required this.load,
  });
  final int months;

  /// Changes on pull-to-refresh, which reloads (and retries) the check-ins.
  final int refreshToken;
  final List<CycleLog> cycleLogs;
  final List<CanonicalEpisodeTiming> episodes;
  final Future<List<WellbeingLog>> Function(DateTime from) load;

  @override
  State<_WellbeingTrends> createState() => _WellbeingTrendsState();
}

class _WellbeingTrendsState extends State<_WellbeingTrends> {
  List<WellbeingLog>? _logs;
  bool _failed = false;
  int _generation = 0;

  DateTime get _rangeStart =>
      DateTime(AppClock.now().year, AppClock.now().month - widget.months + 1);

  @override
  void initState() {
    super.initState();
    WellbeingRepository.revision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant _WellbeingTrends oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.months != widget.months ||
        oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    WellbeingRepository.revision.removeListener(_load);
    super.dispose();
  }

  /// Only the latest request may write: a slow earlier one (say a 12-month
  /// range) finishing after a newer one must not replace its results.
  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final logs = await widget.load(_rangeStart);
      if (!mounted || generation != _generation) return;
      setState(() {
        _logs = logs;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  static String _avg(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);

  Widget _row(String label, WellbeingGroupSummary group) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label · ${group.count} ${_in('check-ins', 'تسجيلات')}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          group.count == 0
              ? _in('No check-ins yet', 'لا توجد تسجيلات بعد')
              : '${_in('Mood', 'المزاج')} ${_avg(group.averageMood)}/5 · '
                    '${_in('Energy', 'الطاقة')} ${_avg(group.averageEnergy)}/5 · '
                    '${_in('Sleep', 'النوم')} ${_avg(group.averageSleep)}/5',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    final split = logs == null
        ? null
        : WellbeingPeriodSplit.compute(
            logs: logs,
            cycleLogs: widget.cycleLogs,
            episodes: widget.episodes,
            today: AppClock.now(),
          );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.self_improvement_rounded,
                color: AppColors.istihadah,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _in('Mood & wellbeing', 'الحالة النفسية'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _in(
                  'Last ${widget.months} months',
                  'آخر ${widget.months} أشهر',
                ),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _in(
                  "Couldn't load your check-ins. Pull down to try again.",
                  'تعذّر تحميل تسجيلاتكِ. اسحبي للأسفل للمحاولة مرة أخرى.',
                ),
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            )
          else if (split == null)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (split.all.count == 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _in(
                  'Log your mood from Today on any day, with or without a period, to see it here.',
                  'سجّلي حالتكِ النفسية من الصفحة الرئيسية في أي يوم، مع الدورة أو بدونها، لتظهر هنا.',
                ),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            _row(_in('All days', 'كل الأيام'), split.all),
            _row(_in('Period days', 'أيام الدورة'), split.onPeriodDays),
            _row(
              _in('Days without a period', 'أيام بلا دورة'),
              split.onOtherDays,
            ),
            const SizedBox(height: 14),
            Text(
              _in(
                'Averages on a 1–5 scale. Period days are days with bleeding recorded; this is tracking only, not a ruling.',
                'المتوسطات من 1 إلى 5. أيام الدورة هي الأيام المسجّل فيها نزول دم؛ هذا للتتبّع فقط وليس حكمًا شرعيًا.',
              ),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.logs, this.canonicalEpisodes = const []});
  final List<CycleLog> logs;

  /// Periods the user reported (onboarding history or live tracking),
  /// shown from their REAL start/end dates — never as invented daily rows.
  final List<CanonicalEpisodeTiming> canonicalEpisodes;

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) => _Card(
    child: logs.isEmpty && canonicalEpisodes.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 44,
                  color: Color(0xFFE5E7EB),
                ),
                SizedBox(height: 12),
                Text(
                  _in('No cycle history yet', 'لا يوجد سجل للدورة بعد'),
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          )
        : Column(
            children: [
              for (final episode in canonicalEpisodes.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.event_note_outlined,
                    color: AppColors.brandSecondary,
                  ),
                  title: Text(
                    episode.endDate == null
                        ? '${_in('Reported period', 'دورة مسجّلة')}: '
                              '${_date(episode.startDate)}'
                        : '${_in('Reported period', 'دورة مسجّلة')}: '
                              '${_date(episode.startDate)} – '
                              '${_date(episode.endDate!)}',
                  ),
                  subtitle: Text(
                    episode.endDate == null
                        ? _in('Started, not yet ended', 'بدأت ولم تنتهِ بعد')
                        : _in('Completed', 'مكتملة'),
                  ),
                ),
              for (final log in logs.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.brandSecondary,
                  ),
                  title: Text(_date(log.date)),
                  subtitle: Text(
                    '${_in('Cycle day', 'يوم الدورة')} ${log.cycleDay}',
                  ),
                ),
            ],
          ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: AppColors.textTertiary,
      fontSize: 9,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: AppColors.shadowColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.045),
          blurRadius: 22,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: child,
  );
}
