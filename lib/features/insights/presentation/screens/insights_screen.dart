import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_calculation_service.dart';
import '../../../cycle_tracking/domain/services/cycle_symptom_decoder.dart';
import '../../../cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import '../../../cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';

String _in(String en, String ar) => AppLocaleController.instance.text(en, ar);

Color _regularityColor(CycleRegularity regularity) => switch (regularity) {
  CycleRegularity.regular || CycleRegularity.highlyRegular => AppColors.success,
  CycleRegularity.irregular => AppColors.warning,
  CycleRegularity.insufficientData => AppColors.textSecondary,
};

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.viewModel});

  /// Shared across tabs by [NiswahHomeShell] so a log saved on one tab is
  /// immediately reflected on the others — falls back to a private
  /// instance when unset (e.g. existing tests that mount this screen
  /// standalone).
  final CycleTrackingViewModel? viewModel;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final CycleTrackingViewModel _viewModel;
  int _trendMonths = 3;

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
      final canPredict = enoughData && calculation.hasPlausibleAverage;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.brandSecondary,
            onRefresh: _viewModel.loadLogs,
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
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.brandSecondary,
                      backgroundColor: Colors.transparent,
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
                      _HistoryCard(logs: _viewModel.logs),
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
    final daysUntil = nextPeriod == null
        ? null
        : DateUtils.dateOnly(nextPeriod)
              .difference(DateUtils.dateOnly(AppClock.now()))
              .inDays;
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
                  value: _date(nextPeriod),
                  note: daysUntil == null
                      ? _in('Insufficient data', 'بيانات غير كافية')
                      : _in(
                          'In about ${daysUntil.clamp(0, 999)} days',
                          'بعد ${daysUntil.clamp(0, 999)} أيام تقريباً',
                        ),
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
          ...rows.map((item) {
            final count = item.$4;
            final percent = rangeLogs.isEmpty
                ? 0.0
                : (count / rangeLogs.length).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
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
                        percent == 0 ? '—' : '${(percent * 100).round()}%',
                        style: TextStyle(color: item.$3, fontSize: 9),
                      ),
                    ],
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.logs});
  final List<CycleLog> logs;
  @override
  Widget build(BuildContext context) => _Card(
    child: logs.isEmpty
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
            children: logs
                .take(5)
                .map(
                  (log) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.calendar_today_outlined,
                      color: AppColors.brandSecondary,
                    ),
                    title: Text(
                      '${log.date.day}/${log.date.month}/${log.date.year}',
                    ),
                    subtitle: Text(
                      '${_in('Cycle day', 'يوم الدورة')} ${log.cycleDay}',
                    ),
                  ),
                )
                .toList(),
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
